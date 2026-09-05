// swift-tools-version: 5.10

import PackageDescription

#if compiler(>=6.0)
  let supportedSwiftLanguageVersions: [SwiftVersion] = [.v5, .version("6")]
#else
  let supportedSwiftLanguageVersions: [SwiftVersion] = [.v5]
#endif

let strictSwiftSettings: [SwiftSetting] = [
  .unsafeFlags(["-warnings-as-errors", "-strict-concurrency=complete"]),
  .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
]

let package = Package(
  name: "OCRCapture",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "hm-ocr-capture", targets: ["OCRCapture"])
  ],
  targets: [
    .executableTarget(
      name: "OCRCapture",
      path: "Sources/OCRCapture",
      swiftSettings: strictSwiftSettings
    ),
    .testTarget(
      name: "OCRCaptureTests",
      dependencies: ["OCRCapture"],
      path: "Tests/OCRCaptureTests",
      swiftSettings: strictSwiftSettings
    ),
  ],
  swiftLanguageVersions: supportedSwiftLanguageVersions
)
