import Foundation
import CoreBluetooth
import Combine

final class BikeConnection: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var status = "Ready to connect"
    @Published var connected = false
    @Published var busy = false
    @Published var progress: Double = 0
    @Published var info: [UInt8] = []
    @Published var events: [String] = []
    @Published var devices: [CBPeripheral] = []
    @Published var selectedIdentifier: UUID?
    @Published var lastRemoteMode: UInt8?
    @Published var remoteEventCount = 0
    @Published var scanning = false
    var displayIsOn: Bool { info.count >= 2 && info[1] == 1 }
    var onReady: (() -> Void)?
    var onInfo: (([UInt8]) -> Void)?
    var onUploaded: (() -> Void)?
    var onDisplayPowerChanged: ((Bool) -> Void)?
    var onSignalChanged: ((BikeProtocol.Signal) -> Void)?
    var onFailure: ((String) -> Void)?
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var decoder = FrameDecoder()
    private var timer: DispatchWorkItem?
    private var waitingCommand: UInt8?
    private var packets: [Data] = []
    private var packetIndex = 0
    private var fragments: [Data] = []
    private var generation = 0
    private var scanRequested = false
    private var baselineInfo: [UInt8] = []
    private var checkingAfterUpload = false
    private var uploadTarget: BikeProtocol.UploadTarget = .ordinary
    private var pendingFlashProgram: [UInt8]?
    private var queuedUpload: (program: [UInt8], replaceFlash: Bool)?
    private var queuedDisplayPower: Bool?
    private var displayPowerChange: DisplayPowerChange?
    private var queuedSignal: BikeProtocol.Signal?
    private var pendingSignal: BikeProtocol.Signal?
    private var signalBaseline: [UInt8] = []
    private var checkingSignalSettings = false
    private var reconnectIdentifier: UUID?

    override init() { super.init(); central = CBCentralManager(delegate: self, queue: .main) }
    func log(_ text: String) {
        events.append(text); if events.count > 150 { events.removeFirst() }
        print(text); fflush(stdout)
    }
    func scan() {
        guard !busy, peripheral == nil else { return }
        scanRequested = true
        if central.state == .poweredOn {
            devices = []; scanning = true; status = "Looking for iLedBike…"
            central.scanForPeripherals(withServices: [CBUUID(string: "FFF0")])
            deadline(12) { [weak self] in
                guard let self else { return }
                self.central.stopScan(); self.scanRequested = false; self.scanning = false
                self.status = self.devices.isEmpty ? "No iLedBike found. Keep it powered on nearby." : "Choose your iLedBike"
            }
        } else { status = "Turn on Bluetooth to connect" }
    }
    func connect(_ device: CBPeripheral) {
        guard peripheral == nil, devices.contains(where: { $0.identifier == device.identifier }) else { return }
        central.stopScan(); scanRequested = false; scanning = false; timer?.cancel()
        selectedIdentifier = device.identifier; info = []; lastRemoteMode = nil
        peripheral = device; device.delegate = self; busy = true; status = "Connecting…"
        central.connect(device)
        deadline(15) { [weak self] in self?.fail("Connection timed out.") }
    }
    func disconnect() {
        generation += 1; timer?.cancel(); waitingCommand = nil; fragments = []; packets = []
        central.stopScan(); scanRequested = false; scanning = false; reconnectIdentifier = nil
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        peripheral = nil; characteristic = nil; decoder = FrameDecoder()
        connected = false; busy = false; checkingAfterUpload = false; status = "Disconnected"
        uploadTarget = .ordinary; pendingFlashProgram = nil
        queuedUpload = nil; selectedIdentifier = nil; info = []; lastRemoteMode = nil
        queuedDisplayPower = nil; displayPowerChange = nil
        queuedSignal = nil; pendingSignal = nil; signalBaseline = []; checkingSignalSettings = false
    }
    // Only pass identifiers previously saved from this phone's validated scan.
    func reconnect(_ identifier: UUID) {
        guard peripheral == nil, !busy else { return }
        guard central.state == .poweredOn else {
            reconnectIdentifier = identifier; status = "Turn on Bluetooth to connect"; return
        }
        reconnectIdentifier = nil
        if let device = central.retrievePeripherals(withIdentifiers: [identifier]).first {
            if !devices.contains(where: { $0.identifier == identifier }) { devices.append(device) }
            connect(device)
        } else { status = "Bike needs to be found again. Tap Find nearby bikes." }
    }
    func pauseForBackground() {
        if busy { fail("Operation interrupted when the app closed. Keep it open while sending; reconnect before retrying.") }
        else { disconnect() }
    }
    private func fail(_ message: String) {
        log(message); disconnect(); status = message; onFailure?(message)
    }
    private func deadline(_ seconds: Double, action: @escaping () -> Void) {
        timer?.cancel(); let item = DispatchWorkItem(block: action); timer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if let identifier = reconnectIdentifier { reconnect(identifier) }
            else if scanRequested { scan() }
        }
        else if central.state == .unauthorized {
            #if os(iOS)
            fail("Allow Bluetooth access for Bike Studio in Settings → Privacy & Security → Bluetooth.")
            #else
            fail("Allow Bluetooth access in System Settings → Privacy & Security → Bluetooth.")
            #endif
        }
        else if central.state == .unsupported { disconnect(); status = "Bluetooth is unavailable here. Use a physical iPhone to connect to a bike." }
        else if central.state == .poweredOff { disconnect(); status = "Bluetooth is off" }
    }
    func centralManager(_ central: CBCentralManager, didDiscover device: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? device.name ?? ""
        guard name.lowercased() == "iledbike", let raw = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return }
        let bytes = [UInt8](raw)
        // Observed 36×12 iLedBike profile; refuse a different panel rather than guessing its layout.
        guard bytes.count >= 12, bytes[8] == 12, bytes[9] == 0, bytes[10] == 36 else { return }
        if !devices.contains(where: { $0.identifier == device.identifier }) {
            devices.append(device); status = "Found iLedBike · 36 × 12"; log("Found iLedBike (36 × 12), signal \(RSSI) dBm.")
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect device: CBPeripheral) {
        guard device === peripheral else { return }
        device.discoverServices([CBUUID(string: "FFF0")])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect device: CBPeripheral, error: Error?) { guard device === peripheral else { return }; fail(error?.localizedDescription ?? "Could not connect.") }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral device: CBPeripheral, error: Error?) {
        guard peripheral?.identifier == device.identifier else { return }
        fail(error?.localizedDescription ?? "The panel disconnected. Reconnect to try again.")
    }
    func peripheral(_ device: CBPeripheral, didDiscoverServices error: Error?) {
        guard device === peripheral else { return }
        guard error == nil, let service = device.services?.first(where: { $0.uuid == CBUUID(string: "FFF0") }) else { fail("Expected Bluetooth service missing."); return }
        device.discoverCharacteristics([CBUUID(string: "FFF1")], for: service)
    }
    func peripheral(_ device: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard device === peripheral else { return }
        guard error == nil, let char = service.characteristics?.first(where: { $0.uuid == CBUUID(string: "FFF1") }), char.properties.contains(.notify), char.properties.contains(.writeWithoutResponse) else { fail("Expected upload channel missing."); return }
        characteristic = char; device.setNotifyValue(true, for: char)
    }
    func peripheral(_ device: CBPeripheral, didUpdateNotificationStateFor char: CBCharacteristic, error: Error?) {
        guard device === peripheral else { return }
        guard error == nil, char.isNotifying else { fail("Could not subscribe to panel responses."); return }
        timer?.cancel(); connected = true; busy = false; status = "Connected · 36 × 12"
        log("Connected. Directional/brake slots, remote settings and firmware are protected.")
        queryInfo()
    }
    func queryInfo() {
        guard connected, !busy else { return }
        busy = true; waitingCommand = 0x1f
        guard send(BikeProtocol.envelope([0x1f])) else { return }
        deadline(8) { [weak self] in
            guard let self else { return }
            if self.pendingSignal != nil {
                self.fail("Signal was requested, but the settings check timed out. Reconnect to inspect; no command was repeated.")
            } else if self.displayPowerChange != nil {
                self.fail("Display command acknowledged, but status verification timed out. Reconnect to check; the command will not be repeated.")
            } else {
                self.fail(self.checkingAfterUpload ? "Upload acknowledged, but the settings check timed out. Reconnect to inspect." : "No device-info response. No change command was sent.")
            }
        }
    }
    func selectSignal(_ signal: BikeProtocol.Signal, for identifier: UUID) {
        guard connected, !busy, selectedIdentifier == identifier else { return }
        queuedSignal = signal
        status = "Checking panel before selecting \(signal.label.lowercased())…"
        queryInfo()
    }
    private func beginSignalSelection(_ signal: BikeProtocol.Signal) {
        guard displayIsOn else {
            status = "Display is off. Turn it on before selecting a signal."
            onFailure?(status)
            return
        }
        pendingSignal = signal; signalBaseline = info; checkingSignalSettings = false
        busy = true; progress = 0; waitingCommand = 0x1b
        status = "Selecting \(signal.label.lowercased())…"
        guard send(BikeProtocol.envelope(signal.payload)) else { return }
        // The vendor app consumes state reports (1E/1C), not a documented 1B ACK.
        // Ask for the active mode after the small command has left the queue.
        let token = generation
        deadline(8) { [weak self] in
            self?.fail("Signal status was not confirmed. Reconnect to inspect; no command was repeated.")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.generation == token, self.pendingSignal == signal else { return }
            self.waitingCommand = 0x1c
            self.status = "Checking the panel’s active signal…"
            _ = self.send(BikeProtocol.envelope([0x1c]))
        }
    }
    func setDisplayPower(_ isOn: Bool, for identifier: UUID) {
        guard connected, !busy, selectedIdentifier == identifier else { return }
        queuedDisplayPower = isOn
        status = "Checking display status…"
        queryInfo()
    }
    private func beginDisplayPowerChange(_ isOn: Bool) {
        do {
            let change = try DisplayPowerChange(isOn: isOn, baseline: info)
            if displayIsOn == isOn {
                status = isOn ? "Display already on" : "Display already off · Bluetooth may remain awake"
                onDisplayPowerChanged?(isOn)
                return
            }
            displayPowerChange = change; busy = true; waitingCommand = 5
            status = isOn ? "Turning display on…" : "Turning display off…"
            guard send(BikeProtocol.envelope(change.payload)) else { return }
            deadline(8) { [weak self] in
                self?.fail("Display command was not acknowledged. Its outcome is unknown; reconnect to check. It will not be repeated.")
            }
        } catch { fail(error.localizedDescription) }
    }
    func upload(program: [UInt8], replaceFlashingMode: Bool = false) {
        guard connected, !busy, !info.isEmpty else { return }
        queuedUpload = (program, replaceFlashingMode)
        queryInfo() // Fresh power/settings baseline; never infer readiness from advertising.
    }
    private func beginUpload(program: [UInt8], replaceFlashingMode: Bool) {
        do {
            packets = try BikeProtocol.upload(program)
            uploadTarget = .ordinary
            pendingFlashProgram = replaceFlashingMode ? program : nil
            baselineInfo = info; checkingAfterUpload = false; packetIndex = 0
            busy = true; progress = 0; status = "Preparing panel…"
            sendPacket()
        } catch { status = error.localizedDescription }
    }
    private func sendPacket() {
        guard packetIndex < packets.count else { finishUpload(); return }
        waitingCommand = packetIndex == 0 ? uploadTarget.command : 3
        status = packetIndex == 0 ? "Preparing \(uploadTarget.label)…" : "Sending \(uploadTarget.label): \(packetIndex) of \(packets.count - 1)…"
        guard send(packets[packetIndex]) else { return }
        let targetLabel = uploadTarget.label
        deadline(8) { [weak self] in self?.fail("Acknowledgement timed out for \(targetLabel). The update may be partial; reconnect before retrying.") }
    }
    private func finishUpload() {
        log("Panel acknowledged the complete \(uploadTarget.label) upload.")
        if let program = pendingFlashProgram {
            pendingFlashProgram = nil
            do {
                packets = try BikeProtocol.upload(program, target: .flashingMode)
                uploadTarget = .flashingMode; packetIndex = 0; progress = 0
                sendPacket()
            } catch { fail("Ordinary display uploaded, but double-flash replacement failed: \(error.localizedDescription)") }
            return
        }
        packets = []; progress = 1; busy = false; checkingAfterUpload = true
        queryInfo()
    }
    private func send(_ frame: Data) -> Bool {
        guard let peripheral, characteristic != nil, fragments.isEmpty else { fail("Bluetooth transport is unavailable or busy."); return false }
        var check = FrameDecoder()
        let decoded = check.feed(frame)
        do {
            guard decoded.count == 1 else { throw StudioError.invalid("Invalid outbound frame.") }
            try BikeProtocol.validate(decoded[0], target: uploadTarget,
                                      displayPower: waitingCommand == 5 ? displayPowerChange?.isOn : nil,
                                      signal: (waitingCommand == 0x1b || waitingCommand == 0x1c) ? pendingSignal : nil)
        } catch { fail(error.localizedDescription); return false }
        let limit = min(180, peripheral.maximumWriteValueLength(for: .withoutResponse))
        guard limit > 0 else { fail("Invalid Bluetooth write limit."); return false }
        fragments = stride(from: 0, to: frame.count, by: limit).map { frame.subdata(in: $0..<min($0 + limit, frame.count)) }
        pump()
        return true
    }
    private func pump() {
        guard let peripheral, let characteristic, peripheral.canSendWriteWithoutResponse, !fragments.isEmpty else { return }
        let fragment = fragments.removeFirst()
        peripheral.writeValue(fragment, for: characteristic, type: .withoutResponse)
        let token = generation
        if !fragments.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self, self.generation == token else { return }; self.pump()
        }}
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) { guard peripheral === self.peripheral else { return }; pump() }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristic === self.characteristic else { return }
        guard error == nil, let data = characteristic.value else { fail("Unable to receive panel response."); return }
        for response in decoder.feed(data) {
            log("Response: " + response.map { String(format: "%02x", $0) }.joined())
            if response.count == 2, [0x1e, 0x1c].contains(response[0]), response[1] <= 5 {
                lastRemoteMode = response[1]; remoteEventCount += 1
            }
            if response.count == 2, response[0] == 5, response[1] <= 1 {
                if let change = displayPowerChange {
                    if waitingCommand == 5 {
                        guard response == change.payload else { fail("Panel reported a different display state. Reconnect to check."); return }
                        timer?.cancel(); waitingCommand = nil; busy = false
                        status = "Checking display state and settings…"
                        queryInfo()
                    }
                    // During verification, the fresh information response is authoritative.
                    continue
                }
                if response[1] == 0 && busy { fail("The panel display turned off during the operation. Reconnect before retrying."); return }
                if info.count >= 2 { info[1] = response[1] }
                if !busy { status = response[1] == 1 ? "Connected · ready to send" : "Connected · display off" }
            }
            guard let command = response.first, command == waitingCommand else { continue }
            if command == 0x1c, let signal = pendingSignal {
                do { try signal.verifyMode(response) }
                catch { fail(error.localizedDescription); return }
                timer?.cancel(); waitingCommand = nil; busy = false; checkingSignalSettings = true
                queryInfo()
            } else if command == 0x1f {
                guard response.count >= 7 else { fail("Device-info response is too short."); return }
                timer?.cancel(); waitingCommand = nil; info = response; busy = false
                if checkingSignalSettings, let signal = pendingSignal {
                    guard response == signalBaseline else { fail("Device settings changed during signal selection. Reconnect and inspect."); return }
                    // A later physical-remote event takes precedence over the earlier query.
                    guard lastRemoteMode == signal.rawValue else { fail("The active signal changed during verification. Reconnect to inspect."); return }
                    checkingSignalSettings = false; pendingSignal = nil; signalBaseline = []
                    status = "Panel reports \(signal.label.lowercased()) · settings unchanged"
                    onSignalChanged?(signal)
                } else if let signal = queuedSignal {
                    queuedSignal = nil
                    beginSignalSelection(signal)
                } else if let change = displayPowerChange {
                    do { try change.verify(response) }
                    catch { fail(error.localizedDescription); return }
                    displayPowerChange = nil
                    status = change.isOn ? "Display on · other settings unchanged" : "Display off · Bluetooth may remain awake"
                    onDisplayPowerChanged?(change.isOn)
                } else if let isOn = queuedDisplayPower {
                    queuedDisplayPower = nil
                    beginDisplayPowerChange(isOn)
                } else if checkingAfterUpload {
                    checkingAfterUpload = false
                    guard response == baselineInfo else { fail("Device settings changed after upload. Stop and inspect before continuing."); return }
                    status = uploadTarget == .flashingMode ? "Both display slots uploaded · settings unchanged" : "Uploaded · device settings unchanged"
                    uploadTarget = .ordinary
                    onUploaded?()
                } else if let request = queuedUpload {
                    queuedUpload = nil
                    if displayIsOn { beginUpload(program: request.program, replaceFlashingMode: request.replaceFlash) }
                    else { status = "Display is off. Turn the panel on, then refresh its status. No content sent." }
                } else { status = displayIsOn ? "Connected · ready to send" : "Connected · display off"; onReady?() }
                onInfo?(response)
            } else if command == uploadTarget.command {
                guard response.count == 2, [0, 1].contains(response[1]) else { fail("Panel rejected program announcement."); return }
                timer?.cancel(); waitingCommand = nil
                if response[1] == 1 { finishUpload() } else { packetIndex = 1; sendPacket() }
            } else if command == 3 {
                guard response.count == 5 else { fail("Unexpected chunk acknowledgement."); return }
                let index = Int(response[2]) * 256 + Int(response[3])
                guard index == packetIndex - 1 else { continue }
                guard response[4] == 0 else { fail("Panel rejected chunk \(index) (code \(response[4]))."); return }
                timer?.cancel(); waitingCommand = nil
                progress = Double(packetIndex) / Double(max(1, packets.count - 1))
                packetIndex += 1
                let token = generation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                    guard let self, self.generation == token else { return }; self.sendPacket()
                }
            }
        }
    }
}
