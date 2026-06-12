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
        // FFI exports are dlsym-only: nothing in native code references them, so
        // when this target is statically linked into the app through the
        // generated umbrella, the linker may not pull this archive member at all.
        // `__attribute__((used))` on each function prevents dead-stripping *within*
        // a loaded object, but it does not force selection of an unreferenced
        // archive member. Mark each export `-u` (undefined-required) at the final
        // link so the member is always pulled and the symbols reach the dynamic
        // symbol table for `DynamicLibrary.process()`. (SwiftPM linkerSettings
        // only apply to SPM builds; the CocoaPods path ships a dynamic framework
        // whose exports already survive, so it needs none of this.)
        .unsafeFlags([
          "-Wl,-u,_flutter_tvos_is_tvos",
          "-Wl,-u,_flutter_tvos_system_version",
          "-Wl,-u,_flutter_tvos_device_model",
          "-Wl,-u,_flutter_tvos_machine_id",
          "-Wl,-u,_flutter_tvos_is_simulator",
          "-Wl,-u,_flutter_tvos_supports_4k",
          "-Wl,-u,_flutter_tvos_supports_hdr",
          "-Wl,-u,_flutter_tvos_supports_multi_user",
          "-Wl,-u,_flutter_tvos_display_width",
          "-Wl,-u,_flutter_tvos_display_height",
        ]),
      ]
    ),
  ]
)
