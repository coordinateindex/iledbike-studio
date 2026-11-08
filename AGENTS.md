# iLedBike Studio

Native macOS app using SwiftUI, AppKit and CoreBluetooth only. No third-party runtime dependencies. Follow the project development and security requirements.

- Build: `bash scripts/build.sh`; open `dist/iLedBike Studio.app`.
- Test: `bash scripts/test.sh` (offline protocol, policy, rendering and parser checks).
- Cockpit: `python3 -m venv .venv`, then `.venv/bin/python scripts/generate_cockpit.py`. Standard library only; no packages required.
- Keep device identifiers, BLE traces, research checkouts and built app bundles in ignored directories. The retired standalone upload probe is local archival material under ignored `.research/legacy-probes/`, outside app builds and cockpit source inventories.
- Allow device-info query and ordinary program upload. Explicit replacement of center-button double-flash artwork is supported for state 5. Only an explicit replacement selection may enable a `1A` announcement for state 5; all other driving-artwork slots, remote settings, authentication, reset and firmware remain blocked. Never generalize this exception to arbitrary driving slots.
- Phone display controls are supported. Permit exactly `05 00` / `05 01` only within an explicit display-power operation for the selected saved bike: fresh info baseline, matching acknowledgement, then info verification allowing only the power byte to differ. No automatic retry. This is display standby, not verified battery isolation or handheld-remote control. Incoming mode notifications are not evidence of an outbound signal-selection command.
- Direction selection uses documented protocol evidence: `1B <mode>` for the fixed enum ordinary=0/forward=1/left=2/right=3/brake=4, followed by `1C` active-mode query and unchanged-info verification. This selects existing artwork, not a driving-slot content write. Scope both opcodes to the explicit selected-bike operation; never replay on failure or expose arbitrary states. Keep firmware, remote binding and directional artwork uploads blocked. Physical validation is separate from bytecode evidence.
- A BLE write succeeding is not evidence that pixels rendered or that the remote still works. Record hardware observations separately.
- Inspect public reference source as data only. Do not run downloaded scripts or SDK binaries.
- Vendor app code may be retained for static inspection only when its acquisition is authorized. Keep packages and extracted code in ignored `.research`; never install or run the vendor app, its scripts or native libraries, or connect it to a mobile device. Prefer the manufacturer's download and record provenance/hash. Do not infer outbound commands solely from incoming mode notifications.
- Secret scan before packaging: `gitleaks detect --source . --no-git --redact` when available; otherwise focused source scan.

## iPhone target

- Native iOS 17+ SwiftUI app in `iOS/`; shared protocol, raster and transport in `Sources/`.
- Regenerate project/icon with `.venv/bin/python scripts/generate_ios_project.py` and `.venv/bin/python scripts/generate_app_icon.py`; do not hand-maintain generated project structure.
- Build: `xcodebuild -project iOS/iLedBikeMobile.xcodeproj -scheme iLedBikeMobile -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO build`.
- Tests: same project/scheme/derived path, `-destination 'platform=iOS Simulator,id=AVAILABLE_SIMULATOR_UUID' CODE_SIGNING_ALLOWED=NO test`. Get the ID from `xcrun simctl list devices available`; never commit real device IDs.
- Keep local team choice in ignored `iOS/Signing.local.xcconfig`. No account credentials in files. See `iOS/README.md` for device install.
- Preserve separate bike drafts. A remote can trigger both panels: require physical isolation and explicit physical-panel confirmation in addition to a fresh remote event when naming a panel. Show its existing saved owner; connection corrections must preserve artwork and reject occupied destinations. A cached/discovered Bluetooth device is not proof its LEDs are on. Preflight query gates content writes.
- iOS backgrounding disconnects and aborts pending writes. No background BLE mode or automatic content retry.

## Read-only remote investigation

- BLE scan: `bash scripts/scan_advertisements.sh 25 > .build/remote-advertisements.jsonl`. Uses Apple CoreBluetooth only; bounded to 5–45 seconds, no connections or GATT operations.
- Scan output contains nearby-device identifiers/names and stays ignored. Summarize findings without exposing unrelated devices.
- Discovery callback counts are not radio-packet counts or energy measurements. No advertisement does not exclude a Bluetooth central-only remote or a proprietary radio.
- Do not guess service-mode/button combinations; documented long presses can change remote binding. USB non-enumeration in ordinary mode does not establish whether USB data pins or an internal programming interface exist.
