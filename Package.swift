// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodetrixStudioCapacitorGoogleAuth",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "CodetrixStudioCapacitorGoogleAuth",
            targets: ["GoogleAuthPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "7.0.0"),
        // Upgrading from 6.2.4 to 8.x for compatibility with Firebase's GTMSessionFetcher requirement
        // This is a MAJOR version upgrade - needs testing
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "8.0.0")
    ],
    targets: [
        // Objective-C target for plugin registration
        .target(
            name: "GoogleAuthPluginObjC",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm")
            ],
            path: "ios/Plugin",
            sources: ["Plugin.m"],
            publicHeadersPath: "."),
        // Swift target for main implementation
        .target(
            name: "GoogleAuthPlugin",
            dependencies: [
                "GoogleAuthPluginObjC",
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS")
            ],
            path: "ios/Plugin",
            sources: ["Plugin.swift"])
    ]
)
