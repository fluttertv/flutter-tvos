# Publishing to the Apple TV App Store

## Prepare for release

### 1. Configure code signing

You need an Apple Developer account with an active membership.

Set your development team via environment variable:

```sh
export DEVELOPMENT_TEAM=XXXXXXXXXX  # your 10-character team ID
```

Or open `tvos/Runner.xcodeproj` in Xcode, select the Runner target, go to **Signing & Capabilities**, and set your team there.

### 2. Build in release mode

```sh
flutter-tvos build tvos --release
```

This produces an AOT-compiled app at `build/tvos/Release-appletvos/Runner.app`.

### 3. Test the release build

Run on a physical Apple TV before submitting:

```sh
flutter-tvos devices          # find your Apple TV device ID
flutter-tvos run -d <device_id> --release
```

## Archive and upload

### Using Xcode (recommended)

1. Open the workspace in Xcode:

   ```sh
   open tvos/Runner.xcworkspace
   ```

2. Set the scheme to **Runner** and the destination to **Any tvOS Device (arm64)**.

3. Select **Product → Archive**. Xcode will build and archive the app.

4. Once archiving completes, the **Organizer** window opens. Select your archive and click **Distribute App**.

5. Choose **App Store Connect** → **Upload** and follow the prompts.

### Using the command line

```sh
# Archive
xcodebuild archive \
  -workspace tvos/Runner.xcworkspace \
  -scheme Runner \
  -sdk appletvos \
  -configuration Release \
  -archivePath build/Runner.xcarchive

# Export the archive
xcodebuild -exportArchive \
  -archivePath build/Runner.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export

# Upload via App Store Connect API
xcrun notarytool submit build/export/Runner.ipa \
  --key <path_to_api_key.p8> \
  --key-id <key_id> \
  --issuer <issuer_id>
```

> **Tip:** You can also use the [Transporter](https://apps.apple.com/app/transporter/id1450874784) app to upload `.ipa` files to App Store Connect.

## App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com) and create a new app.
2. Set **Platform** to **tvOS**.
3. Fill in the app name, bundle ID, category, and description.
4. Select the build you uploaded and submit for review.

## tvOS-specific requirements

Apple has additional requirements for tvOS apps:

| Asset | Specification |
|-------|--------------|
| App icon | 1280×768 px |
| Top Shelf image | 1920×720 px (required) |
| Top Shelf image (wide) | 2320×720 px (optional) |
| App preview video | Up to 30 seconds, 1920×1080 or 3840×2160 |
| Screenshots | 1920×1080 px |

The **Top Shelf image** is shown when your app is in the top row of the Apple TV home screen. It is required for App Store submission.

## TestFlight

To distribute a beta version before release:

1. Upload a build via Xcode Organizer or command line (see above).
2. In App Store Connect, go to **TestFlight** and add testers.
3. Testers install the TestFlight app on their Apple TV and receive the build.

## Useful links

- [Apple: Submitting apps to the App Store](https://developer.apple.com/app-store/submitting/)
- [Apple: tvOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/tvos)
- [Apple: Top Shelf](https://developer.apple.com/documentation/tvservices/creating_a_top_shelf_extension)
