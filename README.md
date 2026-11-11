# PresentationSizingBackport

A Swift package that fits a SwiftUI sheet to the height of its content. Supports iOS 15 and later and requires Xcode 16 or later to build.

## Installation

In Xcode, choose **File → Add Package Dependencies…** and enter the repository URL.

```text
https://github.com/AcrylicMadness/PresentationSizingBackport.git
```

Set the dependency rule to **Branch**, enter `main`, and add the `PresentationSizingBackport` product to your app target. For a local checkout, choose **Add Local…** in the same dialog.

## Usage

Attach `.fittedSheet` to the presenting view and pass a binding that controls whether the sheet is open.

```swift
import SwiftUI
import PresentationSizingBackport

struct ContentView: View {
    @State private var showingProfile = false
    @State private var name = ""

    var body: some View {
        Button("Edit profile") { showingProfile = true }
            .fittedSheet(isPresented: $showingProfile) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Profile").font(.headline)
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    Button("Done") { showingProfile = false }
                }
                .padding(24)
            }
    }
}
```

Use a `VStack` or another view with a natural height so the sheet can measure it. Give views such as `Form`, `List`, and `ScrollView` an explicit height when using them as the sheet root.

To dismiss from a separate content view, declare `@Environment(\.fittedSheetDismiss) private var dismiss` and call `dismiss()`. Pass `onDismiss` to run code after the sheet closes.

## Compatibility

On iOS 15–17, the package presents a custom UIKit sheet that hosts your SwiftUI content. On iOS 18 and later, it uses a native SwiftUI sheet with a content-height detent in compact width and fitted form sizing in regular width.

## Demo

Open [Examples/DemoApp.xcodeproj](Examples/DemoApp.xcodeproj) and run the `PresentationSizingBackportDemo` scheme. Toggle **Show details** to see the sheet resize.
