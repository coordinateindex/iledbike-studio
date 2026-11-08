# iLedBike Studio

Native Mac and iPhone apps for editing messages and pixel art on compatible **36 × 12 iLedBike panels** over Bluetooth. No vendor app, cloud service, account, or third-party runtime dependencies.

## What it does

- Compose scrolling messages, import images, or draw directly on the pixel canvas.
- Save reusable designs and transfer `.iledbike.json` files between Mac and iPhone.
- Keep separate drafts and verified connections for two bike profiles on iPhone.
- On iPhone, switch the display on/off or select existing forward, left, right, and brake signals.

Editing and importing do not send anything to the panel; uploads require an explicit Send.

## Build and run

**Mac:** requires macOS 14+ and Xcode’s Swift toolchain. From the repository root:

```sh
bash scripts/build.sh
open "dist/iLedBike Studio.app"
```

The app bundle is generated locally and excluded from Git. The [launcher](Open%20iLedBike%20Studio.command) also builds it if missing. Allow Bluetooth access, choose **Find panel**, select the intended panel, compose a design, and press **Send to panel**.

**iPhone:** requires iOS 17+ and Xcode with an iOS SDK. Open [iOS/iLedBikeMobile.xcodeproj](iOS/iLedBikeMobile.xcodeproj), choose the **iLedBikeMobile** scheme, configure local signing, and run on a physical device. See [iPhone setup](iOS/README.md).

## Before sending

Isolate the intended panel when identifying it: a remote can trigger more than one nearby panel, and an LED-off panel can still advertise. Verify the physical display, not just a name or connection indicator.

**Double-flash replacement defaults on.** “Use this design in the double-flash slot, too” on Mac, or “Same design when cycling” on iPhone, also replaces the hazard/double-flash artwork. This does not remove a firmware mode, and factory artwork cannot be read back for restoration. Forward/left/right/brake artwork, remote settings, reset, and firmware writes remain blocked.

Keep the app open through upload verification, then check the actual LEDs and remote. Compatibility is based on tested 36 × 12 panels, not every product advertised as CoolLED or iLedBike.

## Use, inspect, and test

- [User guide](docs/user-guide.md) — drawing, panel identification, per-bike storage, imports, and display/signal controls.
- [Shared source](Sources/) and [iPhone source](iOS/iLedBikeMobile/).
- [Architecture](docs/architecture.md) and [protocol evidence](docs/protocol.md).
- [Mac tests](Tests/) and [iPhone tests](iOS/iLedBikeMobileTests/); run `bash scripts/test.sh` for offline Mac checks. Simulator checks are documented in [iPhone setup](iOS/README.md).
- Generated [code](docs/code_map.html), [data](docs/data_map.html), and [output](docs/output_map.html) maps; open locally. [AGENTS.md](AGENTS.md) documents regeneration and development commands.
