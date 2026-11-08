# Supply chain

No third-party runtime or build dependencies were added. The app uses installed Apple frameworks and Xcode. The cockpit script uses Python's standard library in the project `.venv`. No package installers, vendor applications, SDK binaries, remote scripts or firmware images were executed.

Public source checkouts were inspected as protocol research only and are kept in ignored `.research/`:

- `NunoMiguelVeloso/coolledux-controller` at `cacb1e8a1d1369fea2088b94d5d17b412852ad2b`, particularly the Java SDK references for ordinary versus driving uploads, frame content, color transfer and acknowledgements.
- `CharlesLennon/coolledux-ble` at `4f5656d9882adb4926c9dff4dc3fa5783b40a7ac`, for framing, CRC and LZSS research. Some behavior described for its different panel did not transfer to this bike model; hardware evidence takes precedence.

The Swift implementation is local and does not load either repository at runtime. No third-party app installation or firmware flashing is required. Local app signing is ad hoc; there is no paid developer account or distribution/notarization step. No push or publication is part of this task.

## iPhone target

The iOS target adds only Apple UIKit, PhotosUI, UniformTypeIdentifiers, SwiftUI and CoreBluetooth usage through the installed Xcode SDK. Project and geometric icon generation use Python standard library scripts in the existing `.venv`. No npm or pip dependencies were added. The iOS app supports local development signing in Xcode/Keychain, unlike the Mac app's ad-hoc signature. No signing keys, provisioning profiles or real device identities belong in committed source. Distribution is local device testing only.
