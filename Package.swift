// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "WaitList",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WaitList", targets: ["WaitList"]),
        .library(name: "WaitListCore", targets: ["WaitListCore"]),
    ],
    targets: [
        // Pure logic: model, store, persistence, scheduling math. No UI, fully testable.
        .target(name: "WaitListCore"),
        // The menubar app: AppKit lifecycle, notifications, SwiftUI views.
        .executableTarget(name: "WaitList", dependencies: ["WaitListCore"]),
        .testTarget(name: "WaitListCoreTests", dependencies: ["WaitListCore"]),
    ]
)
