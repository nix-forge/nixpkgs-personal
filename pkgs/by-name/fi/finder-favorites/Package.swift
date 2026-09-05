// swift-tools-version: 5.10

import PackageDescription

let strictConcurrency: [SwiftSetting] = [
  .enableExperimentalFeature("StrictConcurrency")
]

let package = Package(
  name: "FinderFavorites",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "FinderFavoritesCore", targets: ["FinderFavoritesCore"]),
    .executable(name: "finder-favorites", targets: ["FinderFavoritesCLI"]),
    .executable(name: "finder-favorites-selftest", targets: ["FinderFavoritesSelfTests"]),
  ],
  targets: [
    .target(
      name: "FinderFavoritesBridge",
      linkerSettings: [.linkedFramework("CoreServices")]
    ),
    .target(
      name: "FinderFavoritesCore",
      dependencies: ["FinderFavoritesBridge"],
      swiftSettings: strictConcurrency
    ),
    .executableTarget(
      name: "FinderFavoritesCLI",
      dependencies: ["FinderFavoritesCore"],
      swiftSettings: strictConcurrency
    ),
    .executableTarget(
      name: "FinderFavoritesSelfTests",
      dependencies: ["FinderFavoritesCore"],
      swiftSettings: strictConcurrency
    ),
    .testTarget(
      name: "FinderFavoritesCoreTests",
      dependencies: ["FinderFavoritesCore"],
      swiftSettings: strictConcurrency
    ),
  ],
  cLanguageStandard: .c17
)
