// swift-tools-version:6.0
import PackageDescription

// SwiftPM manifest for the portable core of CalendarCountdown.
//
// The shipping product is a macOS app built with XcodeGen + xcodebuild (see
// project.yml). That toolchain remains the source of truth for the app, widget,
// CLI, and EventKit bridge, all of which depend on macOS-only frameworks
// (AppKit / EventKit / WidgetKit / SwiftUI).
//
// `CalendarCountdownCore` and its test suite depend only on Foundation and
// XCTest, so this manifest lets them build and run on any Swift-supported
// platform — including Linux CI and Cloud Agent environments where Xcode is not
// available. It intentionally exposes only the cross-platform targets.
let package = Package(
    name: "CalendarCountdown",
    products: [
        .library(name: "CalendarCountdownCore", targets: ["CalendarCountdownCore"])
    ],
    targets: [
        .target(
            name: "CalendarCountdownCore",
            path: "Core"
        ),
        .testTarget(
            name: "CalendarCountdownCoreTests",
            dependencies: ["CalendarCountdownCore"],
            path: "Tests"
        )
    ]
)
