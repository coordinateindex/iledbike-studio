# Bike Studio for iPhone

The iOS companion to [iLedBike Studio](../README.md), with two local bike profiles, separate drafts, and reusable designs. Requires **iOS 17+** and a compatible 36 × 12 panel; hardware communication needs a physical device.

## Build and install

1. Open [iLedBikeMobile.xcodeproj](iLedBikeMobile.xcodeproj) in Xcode and select **iLedBikeMobile**.
2. Configure signing in Xcode. Keep the development team in ignored `iOS/Signing.local.xcconfig` using `DEVELOPMENT_TEAM = YOUR_TEAM_ID`, so project regeneration preserves the local choice.
3. Connect and unlock the iPhone, select it as the destination, and run. Follow Xcode’s device setup prompts and allow Bluetooth access.

If provisioning needs renewal, install over the existing app rather than deleting it. Preserve important designs separately. No App Store distribution is configured.

## First connection

Disconnect other controllers and isolate the intended panel. In **Bikes**, choose **Find Bike 1** or **Find Bike 2**, connect, short-press RIGHT on its remote, and confirm the arrow appeared on that panel before saving its identity. Keep the app open during transfers. An advertisement or remote event alone is not proof of which physical panel is connected.

The [user guide](../docs/user-guide.md) covers editing, importing designs, display controls, storage, and the default double-flash replacement behavior.

## Simulator checks

From the repository root:

```sh
xcodebuild -project iOS/iLedBikeMobile.xcodeproj -scheme iLedBikeMobile -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO build
# Select an available simulator ID with: xcrun simctl list devices available
xcodebuild -project iOS/iLedBikeMobile.xcodeproj -scheme iLedBikeMobile -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO test
```

Tests cover encoding policy, persistence, malformed-library handling, migration, and image/text orientation. Simulator checks cannot verify physical pixels or remote behavior. See [AGENTS.md](../AGENTS.md) for project/icon regeneration commands; routine builds use the checked-in project and assets.
