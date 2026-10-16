// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Veyra", platforms: [.macOS(.v14)], products: [.executable(name: "Veyra", targets: ["Veyra"])], targets: [
    .executableTarget(name: "Veyra", path: ".", exclude: ["assets", "docs", "scripts", "tests", "watchbridge", "ios/WatchBridge.xcodeproj", "ios/WatchBridge/Assets.xcassets", "ios/WatchBridge/ContentView.swift", "ios/WatchBridge/HealthReader.swift", "ios/WatchBridge/SyncModel.swift", "ios/WatchBridge/PairingSheet.swift", "ios/WatchBridge/WatchBridgeApp.swift", "ios/WatchBridge/Keychain.swift", "ios/WatchBridge/Info.plist", "ios/WatchBridge/WatchBridge.entitlements", "AGENTS.md", "README.md", "PRODUCT.md", "DESIGN.md", "UX-CONTRACT.md", "BUILD-STATUS.json", "premium-ui.json", "macos/Tests"], sources: ["macos/Sources", "ios/WatchBridge/Models.swift", "ios/WatchBridge/Theme.swift", "ios/WatchBridge/BridgeClient.swift"], linkerSettings: [.linkedLibrary("sqlite3")]),
    .testTarget(name: "VeyraTests", dependencies: ["Veyra"], path: "macos/Tests", linkerSettings: [.linkedLibrary("sqlite3")])
])
