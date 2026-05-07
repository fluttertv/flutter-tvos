# url_launcher_tvos

The tvOS implementation of [`url_launcher`][upstream], backed by
`UIApplication.open`.

## Usage

```yaml
dependencies:
  url_launcher: ^6.2.0
  url_launcher_tvos:
    git:
      url: https://github.com/fluttertv/plugins.git
      path: packages/url_launcher_tvos
```

Then use the standard `url_launcher` API:

```dart
final Uri uri = Uri.parse('https://flutter.dev');
if (await canLaunchUrl(uri)) {
  await launchUrl(uri);
}
```

## What's supported

| Capability | tvOS behaviour |
|------------|----------------|
| `canLaunchUrl` / `canLaunch` | `UIApplication.shared.canOpenURL` |
| `launchUrl` / `launch` | `UIApplication.shared.open` |
| `externalApplication` mode | ✅ the only real mode on tvOS |
| `externalNonBrowserApplication` mode | ✅ mapped to `universalLinksOnly` |
| `inAppWebView` / `inAppBrowserView` | ❌ no WebKit on tvOS |
| `SFSafariViewController` | ❌ not available on tvOS |
| `closeInAppWebView` | no-op |

Anything that would have opened an in-app browser on iOS degrades to
"launch via the system" on tvOS. If no installed app handles the URL, the
call resolves to `false`.

## Limitations

- **No `mailto:` / `tel:` / `sms:` / `facetime:`** — tvOS lacks Mail,
  Phone, Messages and FaceTime. These schemes return `false`.
- **No in-app browser** — there is no WebKit on tvOS, so `http(s)` URLs
  only open if another installed app registers for them. Many Apple TVs
  have no browser app installed at all, in which case `launchUrl` for
  `https://` URLs returns `false`.
- **App-scheme URLs work** — `youtube://`, `netflix://` etc. launch the
  corresponding app if it is installed on the Apple TV.

## Requirements

- tvOS 13.0 or newer
- Built against the `flutter-tvos` engine

[upstream]: https://pub.dev/packages/url_launcher
