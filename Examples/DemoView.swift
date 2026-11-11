import SwiftUI
import PresentationSizingBackport

struct DemoView: View {
    @State private var showingForm = false

    var body: some View {
        Button("Show form") { showingForm = true }
            .fittedSheet(isPresented: $showingForm) {
                ExampleForm()
            }
    }
}

private struct ExampleForm: View {
    @Environment(\.fittedSheetDismiss) private var dismiss
    @State private var name = ""
    @State private var details = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your profile").font(.title2.bold())
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            Toggle("Show details", isOn: $details)
            if details {
                Text("This additional content changes the height of the sheet. Try larger accessibility text sizes and rotate the device, too.")
            }
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}
