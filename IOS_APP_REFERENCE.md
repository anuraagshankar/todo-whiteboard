# Personal iPhone App + Widget — Reference

## Goal
Build a private iPhone app with a native Home Screen/Lock Screen widget, use it indefinitely without paying for Apple Developer Program membership, and refresh it wirelessly from a Mac.

## Key constraints
- Free Apple Account + Xcode can build and install an app and WidgetKit extension on a personal iPhone.
- Free development provisioning generally expires after **7 days**; the app/widget may stop functioning until refreshed.
- Refreshing every **2 days** is fine and provides a buffer, **provided the app is re-signed with valid renewed provisioning**. Merely reinstalling an unchanged, expiring signed build does not reset validity.
- This is not a truly permanent installation: periodic provisioning and occasional manual intervention remain possible.
- Paid Apple Developer Program membership costs about **US$99/year** and enables distribution options, but development-installed builds also have provisioning limits.

## One-time setup
1. Install Xcode; add Apple Account under Xcode Settings > Accounts.
2. Create a SwiftUI iOS app with a WidgetKit extension. Set the same signing team for both targets, with automatic signing.
3. Connect iPhone to Mac by USB, trust the Mac, and enable iPhone **Settings > Privacy & Security > Developer Mode**.
4. Open Xcode > Window > Devices and Simulators; pair/enable network connection if offered. Verify iPhone appears over Wi-Fi after unplugging.
5. Build and run once from Xcode to verify app and widget installation.

## Terminal refresh workflow
From the project directory, discover the paired device:

```bash
xcrun devicectl list devices
```

Build with development signing (replace project/scheme):

```bash
xcodebuild \
  -project MyApp.xcodeproj \
  -scheme MyApp \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath ./build \
  -allowProvisioningUpdates \
  build
```

Install wirelessly (replace device ID and app name):

```bash
xcrun devicectl device install app \
  --device YOUR_DEVICE_ID \
  ./build/Build/Products/Debug-iphoneos/MyApp.app
```

WidgetKit extension is bundled with the containing app; no separate widget installation is needed.

## Automation idea
- Use macOS `launchd` to invoke a refresh script **every 2 days**.
- Script should build/sign with a currently valid profile, install, log success/failure, and ideally check the embedded provisioning profile's expiration.
- Requires Mac awake, iPhone powered on/reachable via the paired wireless connection, and successful Apple signing; retries/alerts are advisable.
- Preserve bundle identifiers and signing configuration to avoid disrupting installed app data.

## Caveats
- Some entitlements/features are unavailable to free Personal Teams.
- Wireless device discovery and pairing vary by Xcode/iOS version; initial USB pairing may be necessary.
- The 2-day schedule does **not** itself guarantee renewal of the provisioning profile; verify expiration after signing rather than assuming it reset.
- A PWA can be installed on the Home Screen for free but is **not equivalent to a native WidgetKit widget**.
