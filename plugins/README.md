# Flutter tvOS Plugins

Flutter plugins for Apple TV (tvOS), maintained by the FlutterTV team.

These are companions to [flutter-tvos](https://github.com/fluttertv/flutter-tvos) — the Flutter tvOS custom embedder. Apps built with `flutter-tvos` can use these plugins to access platform features (UserDefaults, Siri Remote events, etc.) and to get tvOS support for popular pub.dev plugins.

## Plugin types

**Ports** — federated platform implementations of existing pub.dev plugins, suffixed `_tvos`:

| Plugin | Upstream | Status | Notes |
|--------|----------|--------|-------|
| `shared_preferences_tvos` | `shared_preferences` | ✅ done | NSUserDefaults |
| `path_provider_tvos` | `path_provider` | ✅ done | NSFileManager; no Downloads/External |
| `url_launcher_tvos` | `url_launcher` | ✅ done | UIApplication.open; no in-app browser |
| `device_info_plus_tvos` | `device_info_plus` | 🟡 planned | UIDevice, ProcessInfo |
| `package_info_plus_tvos` | `package_info_plus` | 🟡 planned | Bundle.main |
| `connectivity_plus_tvos` | `connectivity_plus` | 🟡 planned | NWPathMonitor |
| `network_info_plus_tvos` | `network_info_plus` | 🟡 planned | NEHotspotNetwork |
| `flutter_secure_storage_tvos` | `flutter_secure_storage` | 🟡 planned | Keychain |
| `wakelock_plus_tvos` | `wakelock_plus` | 🟡 planned | UIApplication.isIdleTimerDisabled |
| `video_player_tvos` | `video_player` | 🟡 planned | AVPlayer; the big one for TV apps |
| `in_app_purchase_tvos` | `in_app_purchase` | 🟡 planned | StoreKit |
| `sqflite_tvos` | `sqflite` | 🟡 planned | System SQLite |
| `flutter_tts_tvos` | `flutter_tts` | 🟡 planned | AVSpeechSynthesizer |
| `integration_test_tvos` | `integration_test` | 🟡 planned | Test infra |
| `audioplayers_tvos` | `audioplayers` | 🟡 planned | AVAudioPlayer |
| `firebase_core_tvos` | `firebase_core` | 🔵 maybe | Firebase tvOS SDK exists |
| `geolocator_tvos` | `geolocator` | 🔵 maybe | CoreLocation present but no GPS; WiFi-based only |
| `google_sign_in_tvos` | `google_sign_in` | 🔵 maybe | Needs device-pairing OAuth flow; complex |
| `battery_plus_tvos` | `battery_plus` | 🔵 maybe | Apple TV is mains-powered; could stub as always-full |
| `permission_handler_tvos` | `permission_handler` | 🔵 maybe | Most permissions N/A on tvOS |
| `sensors_plus_tvos` | `sensors_plus` | 🔵 maybe | Apple TV has no sensors; Siri Remote motion is separate |
| `camera_tvos` | `camera` | ❌ N/A | No camera on Apple TV |
| `image_picker_tvos` | `image_picker` | ❌ N/A | No photo library on tvOS |
| `webview_flutter_tvos` | `webview_flutter` | ❌ N/A | No WebKit on tvOS |
| `flutter_app_badger_tvos` | `flutter_app_badger` | ❌ N/A | No app badges on tvOS |
| `flutter_webrtc_tvos` | `flutter_webrtc` | ❌ N/A | No camera/mic; very limited use |
| `google_maps_flutter_tvos` | `google_maps_flutter` | ❌ N/A | No Maps SDK for tvOS |

Legend: ✅ done · 🟡 planned (next wave) · 🔵 maybe (evaluating feasibility) · ❌ N/A (platform doesn't support it)

See [`AUTHORING.md`](AUTHORING.md) for the step-by-step guide on porting a new plugin.

**Exclusives** — new plugins exposing tvOS-only APIs, prefixed `tvos_`:

| Plugin | Purpose | Status |
|--------|---------|--------|
| `tvos_remote` | Siri Remote button events beyond what UIKit exposes | 🟡 planned |
| `tvos_focus` | Focus engine bridge for custom focusable Flutter widgets | 🟡 planned |
| `tvos_gamepad` | MFi gamepad input via GameController.framework | 🟡 planned |
| `tvos_top_shelf` | Top shelf extension (featured content on home screen) | 🔵 maybe |

Tizen-only plugins (`messageport`, `tizen_*`, `video_player_avplay`, `video_player_videohole`, `webview_flutter_lwe`, `wearable_rotary`) have no tvOS equivalent and are not planned.

## Usage

Add both the upstream plugin and the tvOS implementation to your `pubspec.yaml`:

```yaml
dependencies:
  shared_preferences: ^2.2.0
  shared_preferences_tvos:
    git:
      url: https://github.com/fluttertv/plugins.git
      path: packages/shared_preferences_tvos
```

For tvOS-exclusive plugins, just depend on them directly:

```yaml
dependencies:
  tvos_remote:
    git:
      url: https://github.com/fluttertv/plugins.git
      path: packages/tvos_remote
```

Once published to pub.dev (coming), the git dependencies become plain version dependencies.

## Repository layout

```
plugins/
├── packages/                  # One directory per plugin
│   ├── shared_preferences_tvos/
│   ├── path_provider_tvos/
│   └── tvos_remote/
├── tools/                     # CI helper scripts
└── .github/workflows/         # CI
```

Each plugin follows the standard Flutter plugin layout:

```
packages/<plugin_name>/
├── lib/                       # Dart code
├── tvos/                      # Native Swift / Objective-C code
│   ├── Classes/               # Plugin implementation (Swift)
│   └── <plugin>.podspec       # CocoaPods spec targeting tvOS 13.0+
├── example/                   # Example app for testing
├── pubspec.yaml
├── README.md
├── CHANGELOG.md
└── LICENSE
```

## Contributing

Plugin ports should:

- Target tvOS 13.0+ (matches `flutter-tvos` engine deployment target)
- Use `#if os(tvOS)` guards when sharing code with iOS implementations
- Federate via the upstream plugin's `*_platform_interface` package when porting

Exclusive plugins should:

- Be prefixed `tvos_`
- Document which tvOS system framework they wrap
- Include an `example/` app demonstrating usage

## License

BSD-3-Clause. See `LICENSE`.
