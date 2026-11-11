import SwiftUI
import UIKit
import XCTest
@testable import PresentationSizingBackport

@MainActor
final class PresentationTests: XCTestCase {
    private final class Model: ObservableObject {
        @Published var presented = false
        @Published var height: CGFloat = 180
        var presentationBinding: Binding<Bool>?
        var dismissals = 0
        var dismissAction: (() -> Void)?
        var environmentWasForwarded = false
    }

    private struct Harness: View {
        @ObservedObject var model: Model
        var legacy = true
        @ViewBuilder var body: some View {
            if legacy {
                Color.white.legacyFittedSheet(
                    isPresented: $model.presented,
                    onDismiss: { model.dismissals += 1 }
                ) {
                    SheetBody(model: model)
                }
            } else {
                Color.white.fittedSheet(isPresented: $model.presented,
                    onDismiss: { model.dismissals += 1 }) {
                    SheetBody(model: model)
                }
            }
        }
    }

    private struct StateBindingHarness: View {
        @State private var presented = false
        let model: Model

        var body: some View {
            Button("Show form") { presented = true }
                .fittedSheet(isPresented: $presented, onDismiss: { model.dismissals += 1 }) {
                    SheetBody(model: model)
                }
                .onAppear { model.presentationBinding = $presented }
        }
    }

    private struct SheetBody: View {
        @ObservedObject var model: Model
        @Environment(\.fittedSheetDismiss) private var dismiss
        @EnvironmentObject private var sharedModel: Model
        var body: some View {
            Color.blue.frame(height: model.height)
                .onAppear {
                    model.dismissAction = dismiss
                    model.environmentWasForwarded = sharedModel === model
                }
        }
    }

    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<300 {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Presentation did not reach its expected state", file: file, line: line)
    }

    func testLegacyResizesInBothDirectionsAndDismissesExactlyOnce() async {
        let model = Model()
        let root = UIHostingController(rootView: Harness(model: model).environmentObject(model))
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }

        model.presented = true
        await eventually { root.presentedViewController?.view.bounds.height ?? 0 >= 180 }
        guard let sheet = root.presentedViewController else { return XCTFail("Missing sheet") }
        let initial = sheet.view.bounds.height

        model.height = 340
        await eventually { sheet.view.bounds.height > initial + 100 }
        model.height = 100
        await eventually { sheet.view.bounds.height < initial - 50 }

        model.height = 10_000
        await eventually { sheet.view.bounds.height > 400 }
        XCTAssertLessThan(sheet.view.bounds.height, window.bounds.height)

        XCTAssertTrue(model.environmentWasForwarded)
        XCTAssertNotNil(model.dismissAction)
        model.dismissAction?()
        await eventually { model.dismissals == 1 }
        XCTAssertNil(root.presentedViewController)
        XCTAssertFalse(model.presented)

        // Re-presentation must not retain the previous sheet or invoke its callback twice.
        model.height = 180
        model.presented = true
        await eventually { root.presentedViewController?.view.window != nil }
        root.presentedViewController?.dismiss(animated: false)
        await eventually { model.dismissals == 2 }
        XCTAssertFalse(model.presented)
    }

    func testPublicAPIPresentsAndDismissesWithStateBinding() async throws {
        let model = Model()
        let root = UIHostingController(rootView: StateBindingHarness(model: model).environmentObject(model))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }

        await eventually { model.presentationBinding != nil }
        let presentation = try XCTUnwrap(model.presentationBinding)
        presentation.wrappedValue = true
        await eventually { model.dismissAction != nil }
        let dismiss = try XCTUnwrap(model.dismissAction)
        XCTAssertTrue(model.environmentWasForwarded)
        XCTAssertNotNil(root.presentedViewController)
        dismiss()
        await eventually { model.dismissals == 1 }
        XCTAssertFalse(presentation.wrappedValue)

        model.dismissAction = nil
        presentation.wrappedValue = true
        await eventually { model.dismissAction != nil }
        presentation.wrappedValue = false
        await eventually { model.dismissals == 2 }
    }

    func testNativeCompactSheetFollowsContentHeight() async throws {
        guard #available(iOS 18.0, *) else { throw XCTSkip("Requires a native fitted sheet") }
        let model = Model()
        let root = UIHostingController(rootView: Harness(model: model, legacy: false).environmentObject(model))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        guard root.traitCollection.horizontalSizeClass == .compact,
              root.traitCollection.verticalSizeClass == .regular else {
            throw XCTSkip("Requires a compact-width, regular-height window")
        }

        model.presented = true
        await eventually {
            guard let height = root.presentedViewController?.view.bounds.height else { return false }
            return height >= 180 && height < 280
        }
        let sheet = try XCTUnwrap(root.presentedViewController)
        let initial = sheet.view.bounds.height

        model.height = 340
        await eventually { sheet.view.bounds.height > initial + 100 }
        model.height = 100
        await eventually { sheet.view.bounds.height < initial - 50 }

        model.height = 10_000
        await eventually { sheet.view.bounds.height > 400 }
        XCTAssertLessThanOrEqual(sheet.view.bounds.height, window.bounds.height)
        model.height = 180
        await eventually { abs(sheet.view.bounds.height - initial) < 1 }

        model.presented = false
        await eventually { model.dismissals == 1 }
    }
}
