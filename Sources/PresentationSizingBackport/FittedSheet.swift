import SwiftUI
import UIKit

public extension View {
    /// Presents a vertically fitted form. Uses a native sheet on iOS 18+.
    ///
    /// Supply intrinsically sized content, such as a VStack. Compact native sheets
    /// and the legacy presenter supply scrolling when content exceeds available height.
    @MainActor
    func fittedSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(FittedSheetModifier(
            isPresented: isPresented, onDismiss: onDismiss, sheetContent: content
        ))
    }
}

private struct FittedSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let onDismiss: (() -> Void)?
    let sheetContent: () -> SheetContent

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                Group {
                    if horizontalSizeClass == .compact {
                        CompactFittedSheet(content: sheetContent())
                    } else {
                        sheetContent()
                            .presentationSizing(.form.fitted(horizontal: false, vertical: true))
                    }
                }
                .environment(\.fittedSheetDismiss, { isPresented = false })
            }
        } else {
            content.legacyFittedSheet(isPresented: $isPresented, onDismiss: onDismiss, content: sheetContent)
        }
    }
}

@available(iOS 18.0, *)
private struct CompactFittedSheet<Content: View>: View {
    let content: Content
    @State private var contentHeight: CGFloat?

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity)
                // Measure the content at the sheet's width without proposing the detent's height.
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height.rounded(.up)
                } action: { height in
                    if height.isFinite { contentHeight = max(1, height) }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([contentHeight.map { .height($0) } ?? .large])
    }
}

// An internal entry point also lets integration tests exercise the fallback on newer simulators.
extension View {
    func legacyFittedSheet<SheetContent: View>(
        isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: () -> SheetContent
    ) -> some View {
        background(LegacySheet(isPresented: isPresented, onDismiss: onDismiss, sheetContent: content()))
    }
}

private struct LegacySheet<SheetContent: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let sheetContent: SheetContent
    @Environment(\.self) private var environment

    func makeUIViewController(context: Context) -> AnchorController {
        let controller = AnchorController()
        controller.onAppear = { [weak coordinator = context.coordinator, weak controller] in
            guard let controller else { return }
            coordinator?.reconcile(from: controller)
        }
        return controller
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateUIViewController(_ controller: AnchorController, context: Context) {
        let coordinator = context.coordinator
        coordinator.binding = $isPresented
        coordinator.onDismiss = onDismiss
        // Carry the caller's SwiftUI environment across the UIKit presentation boundary.
        var sheetEnvironment = environment
        sheetEnvironment.fittedSheetDismiss = { [weak coordinator] in coordinator?.requestDismissal() }
        coordinator.content = AnyView(sheetContent.environment(\.self, sheetEnvironment))
        coordinator.host?.update(content: coordinator.content, dismiss: {
            [weak coordinator] in coordinator?.requestDismissal()
        })
        // Read the wrapped value here so SwiftUI schedules updates when the binding changes.
        guard isPresented || coordinator.host != nil else { return }
        // Avoid changing SwiftUI state during representable updates.
        DispatchQueue.main.async { [weak controller, weak coordinator] in
            guard let controller else { return }
            coordinator?.reconcile(from: controller)
        }
    }

    static func dismantleUIViewController(_ controller: AnchorController, coordinator: Coordinator) {
        controller.onAppear = nil
        coordinator.tornDown = true
        coordinator.host?.dismiss(animated: false)
        coordinator.host = nil
    }

    @MainActor
    final class Coordinator {
        var binding: Binding<Bool> = .constant(false)
        var onDismiss: (() -> Void)?
        var content = AnyView(EmptyView())
        var host: FittingHost?
        var transitioning = false
        var tornDown = false

        func requestDismissal() {
            binding.wrappedValue = false
            host?.dismiss(animated: true)
        }

        func reconcile(from anchor: AnchorController) {
            guard !tornDown, !transitioning, anchor.viewIfLoaded?.window != nil else { return }
            if binding.wrappedValue {
                guard host == nil else { return }
                // Do not dismiss or present over another modal owned by the app.
                guard anchor.presentedViewController == nil,
                      anchor.parent?.presentedViewController == nil else { return }
                let controller = FittingHost(content: content, dismiss: {
                    [weak self] in self?.requestDismissal()
                })
                host = controller
                controller.didDisappear = { [weak self, weak anchor, weak controller] in
                    guard let self, self.host === controller else { return }
                    self.host = nil
                    self.transitioning = false
                    guard !self.tornDown else { return }
                    self.binding.wrappedValue = false
                    self.onDismiss?()
                    if let anchor { self.reconcile(from: anchor) }
                }
                transitioning = true
                anchor.present(controller, animated: true) { [weak self, weak anchor] in
                    guard let self else { return }
                    self.transitioning = false
                    if let anchor { self.reconcile(from: anchor) }
                }
            } else if let host, !host.isBeingDismissed {
                host.dismiss(animated: true)
            }
        }
    }
}

private final class AnchorController: UIViewController {
    var onAppear: (() -> Void)?
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onAppear?()
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FittingContent: View {
    let content: AnyView
    let dismiss: () -> Void
    let measured: (CGFloat) -> Void

    var body: some View {
        ScrollView {
            content
                .environment(\.fittedSheetDismiss, dismiss)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
                })
        }
        .onPreferenceChange(HeightKey.self, perform: measured)
    }
}

private struct FittedSheetDismissKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

public extension EnvironmentValues {
    /// Dismisses a fitted sheet on every supported OS. Native dismiss is also
    /// supported on iOS 18+; use this action in content shared with older systems.
    var fittedSheetDismiss: () -> Void {
        get { self[FittedSheetDismissKey.self] }
        set { self[FittedSheetDismissKey.self] = newValue }
    }
}

private final class FittingHost: UIHostingController<FittingContent>, UIViewControllerTransitioningDelegate {
    var didDisappear: (() -> Void)?
    var contentHeight: CGFloat = 1

    init(content: AnyView, dismiss: @escaping () -> Void) {
        super.init(rootView: FittingContent(content: content, dismiss: dismiss, measured: { _ in }))
        modalPresentationStyle = .custom
        transitioningDelegate = self
        update(content: content, dismiss: dismiss)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func update(content: AnyView, dismiss: @escaping () -> Void) {
        rootView = FittingContent(content: content, dismiss: dismiss) { [weak self] height in
            guard let self, height.isFinite, height > 0,
                  abs(self.contentHeight - height) > 0.5 else { return }
            self.contentHeight = height
            self.presentationController?.containerView?.setNeedsLayout()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // A full-screen modal above this sheet can also make it disappear.
        if isBeingDismissed || presentingViewController == nil { didDisappear?() }
    }

    func presentationController(
        forPresented presented: UIViewController,
        presenting: UIViewController?, source: UIViewController
    ) -> UIPresentationController? {
        return FittedPresentationController(presentedViewController: presented, presenting: presenting)
    }

    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController, source: UIViewController)
        -> UIViewControllerAnimatedTransitioning? { SheetAnimation(presenting: true) }

    func animationController(forDismissed dismissed: UIViewController)
        -> UIViewControllerAnimatedTransitioning? { SheetAnimation(presenting: false) }
}

private final class FittedPresentationController: UIPresentationController {
    private let dimming = UIView()
    private var keyboardFrame: CGRect?
    private var keyboardObserver: NSObjectProtocol?

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let container = containerView else { return .zero }
        let safe = container.bounds.inset(by: container.safeAreaInsets)
        let floating = container.traitCollection.horizontalSizeClass == .regular
        let width = floating ? min(540, max(1, safe.width - 40)) : container.bounds.width
        var bottom = floating ? safe.maxY - 20 : container.bounds.maxY
        if let keyboardFrame {
            let keyboard = container.convert(keyboardFrame, from: nil)
            // Floating keyboards should not collapse the entire form.
            if keyboard.maxY >= container.bounds.maxY - 1,
               keyboard.width >= container.bounds.width * 0.7 {
                bottom = min(bottom, keyboard.minY)
            }
        }
        let top = safe.minY + 20
        let inset = floating ? 0 : container.safeAreaInsets.bottom
        let height = SheetGeometry.height(
            content: (presentedViewController as? FittingHost)?.contentHeight ?? 1,
            bottomInset: inset, available: bottom - top
        )
        let y = floating ? max(top, top + (bottom - top - height) / 2) : bottom - height
        return CGRect(x: container.bounds.midX - width / 2, y: y, width: width, height: height)
    }

    override func presentationTransitionWillBegin() {
        guard let container = containerView else { return }
        dimming.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        dimming.alpha = 0
        dimming.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
        container.insertSubview(dimming, at: 0)
        presentedView?.layer.cornerRadius = 16
        presentedView?.clipsToBounds = true
        presentedView?.backgroundColor = .systemBackground
        presentedView?.accessibilityViewIsModal = true
        keyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            self.keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            UIView.animate(withDuration: duration) {
                self.containerView?.setNeedsLayout()
                self.containerView?.layoutIfNeeded()
            }
        }
        if let coordinator = presentedViewController.transitionCoordinator {
            coordinator.animate(alongsideTransition: { _ in self.dimming.alpha = 1 })
        } else { dimming.alpha = 1 }
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        dimming.frame = containerView?.bounds ?? .zero
        presentedView?.frame = frameOfPresentedViewInContainerView
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.dimming.alpha = 0
        }, completion: { context in
            if context.isCancelled { self.dimming.alpha = 1 }
        })
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        if completed {
            dimming.removeFromSuperview()
            if let keyboardObserver { NotificationCenter.default.removeObserver(keyboardObserver) }
            keyboardObserver = nil
        }
    }

    deinit {
        if let keyboardObserver { NotificationCenter.default.removeObserver(keyboardObserver) }
    }

    @objc private func close() {
        guard !presentedViewController.isModalInPresentation else { return }
        presentedViewController.dismiss(animated: true)
    }
}

private final class SheetAnimation: NSObject, UIViewControllerAnimatedTransitioning {
    let presenting: Bool
    init(presenting: Bool) { self.presenting = presenting }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0 : 0.25
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        let key: UITransitionContextViewControllerKey = presenting ? .to : .from
        guard let controller = context.viewController(forKey: key),
              let view = context.view(forKey: presenting ? .to : .from) ?? controller.view else {
            context.completeTransition(false)
            return
        }
        if presenting {
            context.containerView.addSubview(view)
            view.frame = controller.presentationController?.frameOfPresentedViewInContainerView
                ?? context.finalFrame(for: controller)
            // Establish the width before measuring wrapped SwiftUI content.
            view.setNeedsLayout()
            view.layoutIfNeeded()
            controller.presentationController?.containerView?.layoutIfNeeded()
        }
        let offset = CGAffineTransform(translationX: 0, y: context.containerView.bounds.height - view.frame.minY)
        if presenting { view.transform = offset }
        UIView.animate(withDuration: transitionDuration(using: context), animations: {
            view.transform = self.presenting ? .identity : offset
        }, completion: { _ in
            view.transform = .identity
            context.completeTransition(!context.transitionWasCancelled)
        })
    }
}
