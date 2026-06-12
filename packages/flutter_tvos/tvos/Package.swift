// swift-tools-version: 5.9
// Lets flutter_tvos be consumed via Swift Package Manager in addition to the
// CocoaPods podspec. This is an FFI plugin: the target is the Objective-C
// `Classes/flutter_tvos_ffi.{h,m}` shim that Dart calls through
// `DynamicLibrary.process()`. It has no Flutter dependency (UIKit only).
import PackageDescription

let package = Package(
  name: "flutter_tvos",
  platforms: [
    .tvOS(.v13),
  ],
  products: [
    .library(name: "flutter-tvos", targets: ["flutter_tvos"]),
  ],
  targets: [
    .target(
      name: "flutter_tvos",
      path: "Classes",
      // The single header lives next to the source under Classes/.
      publicHeadersPath: ".",
      cSettings: [
        .define("TARGET_OS_TV"),
      ],
      // flutter_tvos_ffi.m calls UIDevice / UIScreen.
      linkerSettings: [
        .linkedFramework("UIKit"),
      ]
    ),
  ]
)
