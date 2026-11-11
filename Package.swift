// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PresentationSizingBackport",
    platforms: [.iOS(.v15)],
    products: [.library(name: "PresentationSizingBackport", targets: ["PresentationSizingBackport"])],
    targets: [
        .target(name: "PresentationSizingBackport"),
        .testTarget(name: "PresentationSizingBackportTests", dependencies: ["PresentationSizingBackport"])
    ]
)
