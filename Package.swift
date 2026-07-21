// swift-tools-version: 6.0

import PackageDescription

let package = Package(
	name: "SwiftBaileys",
	platforms: [
		.macOS(.v13)
	],
	products: [
		.library(
			name: "WhatsAppWeb",
			targets: ["WhatsAppWeb"]
		),
		.executable(
			name: "NativeSignalBridgeExample",
			targets: ["NativeSignalBridgeExample"]
		)
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-protobuf.git", from: "1.38.0")
	],
	targets: [
		.target(
			name: "WhatsAppWeb",
			dependencies: [
				.product(name: "SwiftProtobuf", package: "swift-protobuf")
			],
			resources: [
				.process("Resources")
			]
		),
		.testTarget(
			name: "WhatsAppWebTests",
			dependencies: ["WhatsAppWeb"]
		),
		.executableTarget(
			name: "NativeSignalBridgeExample",
			dependencies: ["WhatsAppWeb"],
			path: "Examples/NativeSignalBridgeExample"
		)
	]
)
