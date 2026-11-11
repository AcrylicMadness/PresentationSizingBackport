# PresentationSizingBackport

A dependency-free Swift package for vertically fitted SwiftUI form sheets, supporting iOS 15+.

```swift
import PresentationSizingBackport

Button("Edit profile") { showingForm = true }
    .fittedSheet(isPresented: $showingForm, onDismiss: saveDraft) {
        ProfileForm()
    }
```

Add this directory as a local package in Xcode and link the `PresentationSizingBackport` product. For remote installation, push it to your Git repository and add that repository URL as a package dependency. Building requires Xcode 16+ (an iOS 18+ SDK); the deployment target is iOS 15.

## How it works

- **iOS 18+** uses SwiftUI `.sheet`. In compact width, a measured detent tracks the content height and the content can scroll when it exceeds the available height. In regular width, the sheet uses `.presentationSizing(.form.fitted(horizontal: false, vertical: true))`.
- **iOS 15–17:** a public-API UIKit custom presentation controller hosting SwiftUI. The form is centered in regular-width layouts (up to 540 points wide), and bottom attached in compact-width layouts. It measures content height at the current width, includes bottom safe area when attached, and caps the frame to the available space. An enclosing scroll view makes oversized content reachable. Docked keyboards reduce the available height.

The wrapper owns presentation, rather than modifying an existing `.sheet`. This avoids relying on SwiftUI's private view-controller hierarchy or private iOS 15 detent APIs. It deliberately covers the vertically fitted form use case, rather than duplicating the entire `PresentationSizing` protocol.

Apple references: [presentationSizing(_:)](https://developer.apple.com/documentation/swiftui/view/presentationsizing(_:)), [fitted(horizontal:vertical:)](https://developer.apple.com/documentation/swiftui/presentationsizing/fitted(horizontal:vertical:)), [custom detents (iOS 16+)](https://developer.apple.com/documentation/uikit/uisheetpresentationcontroller/detent/custom(identifier:resolver:)).

## Content and dismissal

Use a `VStack` or another container with a meaningful ideal height. Apply padding inside your content. Dynamic content and Dynamic Type can change the measured height. Open `Examples/DemoApp.xcodeproj` and run the `PresentationSizingBackportDemo` scheme for an expandable form (`Examples/DemoView.swift`).

For a shared dismissal action:

```swift
struct ProfileForm: View {
    @Environment(\.fittedSheetDismiss) private var dismiss

    var body: some View {
        VStack {
            Text("Profile")
            Button("Done") { dismiss() }
        }
        .padding()
    }
}
```

Setting the presenting binding to `false` also dismisses. `onDismiss` runs once after dismissal. The legacy backdrop dismisses on tap. The presenting SwiftUI environment (including environment objects) is forwarded to the legacy sheet.

## Differences from system sheets

- Native sheets follow Apple's device-specific adaptation rules, including full-screen presentation in compact height where applicable.
- Compact-width native sheets and legacy sheets supply their own scrolling. Use a plain `VStack` or another finite-height container at the root so the sheet can measure its height. `Form`, `List`, `GeometryReader`, `NavigationView`/`NavigationStack`, and unconstrained `ScrollView` expand to their proposed space.
- Legacy sheets have a dimmed backdrop and a simple slide transition. They do not replicate native drag-to-dismiss, grabbers, detent interactions, or system sheet stacking. Height changes update layout without a spring animation.
- Use `fittedSheetDismiss` or the binding on all versions. SwiftUI's standard `dismiss`/`presentationMode` is not wired to the custom presenter. Other sheet-specific SwiftUI modifiers, such as `presentationDetents`, `presentationBackground`, and `interactiveDismissDisabled`, are not supported by the legacy presenter. Do not use it for forms that must prohibit backdrop dismissal.
- Present one modal at a time from the same view hierarchy. If another modal already occupies the presenter, the legacy presenter will not replace it; a subsequent view update or appearance is needed to retry.
- Removing the presenting view tears down its sheet without invoking `onDismiss`.

## Validation

Build for iOS Simulator:

```sh
xcodebuild -scheme PresentationSizingBackport \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Run tests using an installed simulator destination:

```sh
xcodebuild -scheme PresentationSizingBackport \
  -destination 'platform=iOS Simulator,name=YOUR_SIMULATOR' test
```

The package tests cover height bounds. UIKit presentation tests need an application host, so the demo project includes a separate hosted test target. Run it with:

```sh
xcodebuild -project Examples/DemoApp.xcodeproj \
  -scheme PresentationSizingBackportDemo \
  -destination 'platform=iOS Simulator,name=YOUR_SIMULATOR' test
```

The hosted tests force the legacy presenter on newer systems to exercise growth, shrinkage, overflow, environment forwarding, dismissal, and re-presentation. They also exercise the public API, including content-height changes on compact-width iOS 18+ simulators in portrait. Before release, also verify on iOS 15, 16, and 17 devices/simulators: compact and regular widths, rotation, Dynamic Type, keyboard appearance, and VoiceOver. SDK compatibility and tests on a newer runtime cannot establish older-runtime behavior.
