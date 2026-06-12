// swift-tools-version: 5.9
// Lets flutter_tvos be consumed via Swift Package Manager in addition to the
// CocoaPods podspec. This is an FFI plugin: the target is the Objective-C
// `Classes/flutter_tvos_ffi.{h,m}` shim that Dart calls through
// `DynamicLibrary.process()`. It has no Flutter dependency (UIKit only).
//
// FFI exports are dlsym-only — nothing in native code references them — so when
// this target is statically linked into the app through the generated
// FlutterGeneratedPluginSwiftPackage umbrella, the linker would otherwise drop
// this archive member and the symbols would be absent from the binary. The
// forced reference that pulls the member lives in the app's generated
// GeneratedPluginRegistrant.m (emitted by flutter-tvos from the `ffiSymbols`
// list this plugin declares in pubspec.yaml), NOT here: a `-u` flag in this
// manifest's linkerSettings applies only when building flutter_tvos itself and
// does not propagate to the Runner link. The `__attribute__((used))` /
// visibility("default") on each export (see flutter_tvos_ffi.h) then keeps the
// pulled-in symbols in the dynamic symbol table for DynamicLibrary.process().
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
