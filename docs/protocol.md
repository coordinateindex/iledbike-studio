# Observed iLedBike protocol

Scope: locally tested, powered-on 36×12 iLedBike panels. These findings are not a compatibility claim for every CoolLED product. USB did not expose a programming interface; the controller uses BLE directly.

## Discovery and transport

Scan service `FFF0`, advertised name `iLedBike`. Require manufacturer-data bytes 8–10 to describe height 12 and big-endian width 36. Subscribe to `FFF1` notifications and write without response to that characteristic. No authentication command was needed on this unit.

Frame: `01`, escaped two-byte big-endian payload length, escaped payload, `03`. Escape bytes `01`, `02`, `03` as `02` followed by the original byte XOR `04`. Frame parsing supports fragmented and coalesced notifications. Outgoing frames are fragmented into at most 180 bytes, further bounded by CoreBluetooth's negotiated write limit; fragments are paced by 60 ms and flow control.

## Ordinary program upload

- Query: payload `1F`. This firmware returns seven bytes; save a baseline and compare it after upload. This is not a comprehensive remote-state readback.
- Announce: `02`, CRC-32/MPEG-2 of the uncompressed program (4 bytes), uncompressed length (4 bytes), index `00`, count `01`, show count `01`. All multi-byte fields are big-endian. CRC starts at `FFFFFFFF`, polynomial `04C11DB7`, no reflection or final XOR.
- Response `02 00`: send data. Response `02 01`: content is cached, proceed to the settings check.
- Compress using LZSS literal groups: one flag byte followed by up to eight literal bytes, corresponding low flag bits set. This deliberately avoids backreferences and increases size by approximately 12.5%.
- Data payload: `03 00`, compressed total length (4 bytes), chunk index (2 bytes), chunk length (2 bytes), up to 1024 bytes, XOR checksum of all bytes after the command. Response: `03 00`, index (2 bytes), status `00` for accepted. Wait for the matching index before the next chunk. No automatic retries.

The ordinary-content announce is `02`. The reference SDK distinguishes driving artwork with `1A` and firmware transfer with `FE`/`FF`. The app's final write boundary ordinarily permits only `1F`, `02`, and `03` with constrained shapes. The explicit double-flash replacement option additionally permits an exactly ten-byte `1A` announcement ending in state `05`; every other state remains blocked. Firmware commands are always blocked.

## Single-image program

Program prefix: eight zero bytes, segment count `01`, zero. Segment: four-byte length including that length field; type `02`; eight zero bytes; start column, start row, width and height (each two bytes); mode, speed, stay; four-byte pixel-data length; pixel data. Start coordinates are zero, height is 12, stay is 3. Mode `01` is static, `02` scrolls left. Uploaded images use width 36; messages use a wider raster when necessary, bounded at 255 columns by the text renderer.

Pixels are column-major, top to bottom. Each RGB444 pixel occupies two bytes: `0R GB`. Each RGB888 input channel maps to 0 at values ≤30, 15 at ≥238, otherwise `(value − 30) / 15 + 1` using integer division. UI preview uses the same quantization.

Messages are rasterized locally and sent as a single image segment. A native text-mask plus separate color segment displayed unwanted sparkle artifacts and held a full cyan panel on this firmware; that encoder was removed. The single-image scrolling path was physically confirmed to loop without the full-color hold.

## Center-button double-flash replacement

Physical observations show that short presses of the remote's center/power button cycle through a double-flashing two-arrow mode; it continues until another press. This is distinct from a momentary upload transition. The [manufacturer's manual](https://fcc.report/FCC-ID/2A455-JTPD-03-042/7527690.pdf) labels the center button's short-press action as advance, and documents separate editable driving content. No cycle-removal command is established. The implemented alternative sends the same design to both ordinary content and the physically identified flashing slot, so changing cycle position should not reveal the unwanted arrows. This replaces hazard/emergency artwork; it does not change remote routing or eliminate the position from the cycle.

The option defaults on and persists as the local app preference `replaceFlashingMode` across disconnects and app restarts. It applies to whichever panel is selected and is not stored in design files. Send first completes ordinary content, then sends `1A + CRC32/MPEG-2(raw program) + raw length + 05`. `1A00` requests the same `03` data chunks used for ordinary programs; `1A01` reports cached content. After both uploads, query `1F` and compare with the original baseline. These two uploads are not atomic: a failure may leave one updated slot. There is no automatic retry. Original factory slot artwork cannot be read back for restoration with the known protocol.

## Center-button investigation: passive mode notifications

The existing app's connection log contains unsolicited `1E <state>` notifications during remote use, including states `00`, `04` and `05`. These are incoming notifications, not commands issued by Studio. Their presence provides a way to map physical remote actions without guessing a query or modifying content. A specific visual mode must be correlated with a fresh notification before assigning it a meaning; the historical sequence alone is insufficient.

Labeled physical checks correlated double-flash with `1E05`, left/right/forward/brake with `1E02`/`1E03`/`1E01`/`1E04`, and ordinary content with `1E00`. The four protected directions are distinct from state 5. These observations do not establish separately addressable emergency and center-button flashing artwork.

The pinned [iOS receiver implementation](https://github.com/minimalistech/mobill-drivers/blob/02076f3c735570ee3f21001a70d94838483c91ee/ios/MobillDriversProtocol/HLBluetoothManager.m#L802) explicitly includes the iLedBike device type and decodes two-byte `1E`/`1C` responses into states 0–5. Its [driving-content writer](https://github.com/minimalistech/mobill-drivers/blob/02076f3c735570ee3f21001a70d94838483c91ee/ios/MobillDriversProtocol/JTTool.m#L119) independently confirms the `1A + CRC32 + raw length + state` announcement and `1A00`/`1A01` acceptance responses. This supports separate artwork slots; it does not prove which slot the center button selects, that a slot can be removed from its cycle, or that emergency and center-button behavior use separate slots.

[Public reverse-engineering notes](https://github.com/voidnullvalue/cooled/blob/96038c19ed74c427f8ddc906c2f02b9efa66911b/base_apk_bluetooth_spec_reimplementation.md) distinguish the U/UD response shape from the UX family's `1C 02` query and `1C 01 <state>` setter. The notes explicitly leave the U-family query builder unresolved. Do not borrow the UX command layout for this panel based on a shared opcode. Passive monitoring needs no additional outbound permissions or commands.

## Verification record and limits

- Physical tests observed RGB images and scrolling single-bitmap text, with acknowledged uploads and unchanged reported settings. A prior native text-mask encoder produced a full-color hold and was replaced.
- Ordinary and state-5 cached-content assignment were exercised on two panels. Physical display and protected remote-button observations are distinct from protocol acknowledgements.
- A display-off nearby panel still answered discovery and information queries; its upload announcement timed out. Discovery order and cached identity are insufficient for ownership or readiness.
- Offline checks cover framing, checksums, escaping, opcode rejection, pixel ordering, rendering, import and design roundtrips. Device-info equality cannot prove that every remote setting is unchanged.
- Original factory artwork cannot be read back for backup with the implemented protocol. Firmware and remote-pairing writes remain blocked.

## Phone display switch

Phone on/off controls use a separate scoped operation. The pinned SDK `SendDataUtils.getSwitchData` encodes `05 00` (off) or `05 01` (on); `Jotus` parses a matching state echo. These are now enabled only for an explicit display-power operation. A fresh `1F` baseline is obtained first, then the exact `05` echo, then a new `1F` response with only byte 1 permitted to change to the requested state. Already-matching state needs no write. Missing or conflicting responses fail without retry; UI reports display standby rather than complete power isolation. The remote is a separate device with no identified control interface.

The implementation is source-backed and physical testing confirmed phone-issued display off/on on the selected panel. Previously observed `05` notifications and `1F` power bytes support the response format. Incoming `1E <mode>` and `1C <mode>` are not proof that sending them selects a signal; the SDK uses outbound `1E` for a different settings operation. Direction selection was subsequently identified through static vendor-code inspection, described below.

Verification includes Mac offline checks and simulator tests for command scope, malformed responses and unrelated-setting rejection. Physical testing observed selected-panel off/on and preserved remote functions; battery savings and compatibility with other firmware remain unverified.

Physical acceptance (2026-10-20): device testing confirmed that Display off then Display on affected only the selected panel, returned it to its design, and preserved the remote's left/right/forward/brake functions. The response did not identify which bike was tested or establish that both units were tested individually. Battery consumption and complete radio shutdown were not measured.

## Direction selection from static vendor code

Vendor app code was acquired for static inspection only. The manufacturer's [download page](https://www.jotus-tech.com/h-col-153.html) links a [CoolLed1248 Android package](https://download.s21i.faiusr.com/29716575/0/0/ABUIABBKGAAgnY2yuAYo5P2-5wQ.apk?f=CoolLed1248.apk&v=1728874172). On 2026-10-20, HTTPS byte ranges retrieved its ZIP index and four DEX entries, avoiding the bulk of the 233,975,189-byte package. ZIP CRCs and embedded DEX SHA-1 integrity values were verified; individual SHA-256 hashes and range metadata are in ignored `.research/vendor-static/provenance.json`. The entire APK was not retrieved and its signing certificate was not verified. No vendor code was installed or executed. A locally authored standard-library parser read the bytecode according to Android's published DEX specification; no new dependencies were installed.

Relevant `classes3.dex` SHA-256: `bf83be2eeb969e46641e2b08457f1a9721478811fcaaf3edd8960db15b34eb0b`. Static evidence in `com.jtkj.led1248.light.utils.CoolledUDUtils`:

- `setDriveState(int)` constructs payload `1B` followed by `LightUtils.getHexListStringForInt(state)`, one byte for supported values.
- `getDriveState()` constructs payload `1C`.
- Both use the existing escaped length envelope through `getSendDataWithInfo`.
- `coolledud.DriveFragment.onClick` passes fixed driving modes to `setDriveState`; `DeviceManager.onEvent(SetDriveStateEvent)` sends the resulting data. `DeviceManager.updateDeviceInfo` maps `iLedBike` to the UD utilities. Its U/UD receive handler accepts `1C` and `1E` and reads mode from byte 1.
- Distinguish the other family: `CoolledUXUtils.getSetDriveState` uses `1C 01 <state>` and its query uses `1C 02`. Those car/display commands are not enabled for iLedBike.

Our phone UI exposes ordinary artwork=0, forward/up=1, left=2, right=3 and brake/down=4; these agree with the prior physical-remote mapping. It does not expose state 5. A selected saved bike and idle transport are required. The operation reads fresh `1F` info, requires display on, sends `1B <mode>`, then queries `1C` after a brief transport spacing. The SDK does not establish a `1B` acknowledgement, so success requires exact `1C <requested mode>` and another unchanged `1F` response, with no intervening different mode report. Timeout, conflicting report, backgrounding or disconnect cancels without retry. No artwork upload, firmware or pairing operation is part of this path. Physical phone-direction testing passed as recorded below.

Implementation checks include a golden left-command frame, rejection of unsupported states and malformed replies, and preservation of artwork-slot restrictions. Physical controls and library preservation received separate device testing. Signing, installation and account configuration remain local development concerns.

## Reference evidence

The manufacturer manual documents a Cycling screen. Static reference-source inspection supplies the opcode evidence below; downloaded vendor code is never executed.

Read-only source research: [Java SDK reference](https://github.com/NunoMiguelVeloso/coolledux-controller/tree/cacb1e8a1d1369fea2088b94d5d17b412852ad2b/references/sdktools), especially `SendDataUtils.java`, `CreateDataUtils.java`, `Jotus.java` and `ColorUtils.java`; [BLE protocol reference](https://github.com/CharlesLennon/coolledux-ble/tree/4f5656d9882adb4926c9dff4dc3fa5783b40a7ac). Reference implementations target varying models; this project's hardware observations take precedence. Neither repository is a runtime dependency.

## Phone identity correction

A single remote was observed triggering both panels. A mode notification alone cannot establish ownership. Isolate the intended panel and explicitly verify its large LED display during naming. Connection correction moves only the saved peripheral association into an empty profile; both drafts and saved designs remain intact. This operation changes no panel content, pairing, radio configuration or firmware.

### Phone signal physical acceptance (2026-10-20)

Physical checks confirmed that Forward, Left, Right and Brake showed the correct signals on only the selected panel, My design restored the uploaded artwork, and the physical remote buttons still worked. This validates the phone controls on the tested panel; the response did not identify which bike was tested or establish separate testing of both units.
