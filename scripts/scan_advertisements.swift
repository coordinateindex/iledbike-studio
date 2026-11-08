// Read-only BLE discovery. No connections, GATT reads/writes, pairing or device changes.
// Save output only in ignored .build/: nearby names and identifiers are private.
import Foundation
import CoreBluetooth

func emit(_ record: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) { print(text); fflush(stdout) }
}
final class AdvertisementScanner: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager!
    private var started = false
    private var counts: [UUID: Int] = [:]
    private var latest: [UUID: [String: Any]] = [:]
    private let duration: Double
    init(seconds: Double) {
        duration = seconds; super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { self.finish("startup_timeout", code: 2) }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        emit(["event": "bluetooth_state", "state": central.state.rawValue, "authorization": CBCentralManager.authorization.rawValue])
        switch central.state {
        case .poweredOn:
            guard !started else { return }; started = true
            emit(["event": "scan_started", "seconds": duration])
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { self.finish("scan_complete", code: 0) }
        case .unauthorized: finish("bluetooth_permission_denied", code: 3)
        case .poweredOff: finish("bluetooth_off", code: 4)
        case .unsupported: finish("bluetooth_unsupported", code: 5)
        default: break
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let id = peripheral.identifier
        counts[id, default: 0] += 1
        let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data ?? Data()
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)
        let record: [String: Any] = ["event": "advertisement", "identifier": id.uuidString,
            "name": advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "",
            "services": services, "manufacturer_bytes": manufacturer.count,
            "manufacturer_company": manufacturer.count >= 2 ? Int(manufacturer[0]) + Int(manufacturer[1]) * 256 : -1,
            "connectable": (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false,
            "rssi": rssi.intValue, "count": counts[id]!, "time": ProcessInfo.processInfo.systemUptime]
        latest[id] = record
        if counts[id] == 1 { emit(record) }
    }
    private func finish(_ reason: String, code: Int32) {
        if started { central.stopScan() }
        for id in latest.keys.sorted(by: { $0.uuidString < $1.uuidString }) { emit(latest[id]!) }
        emit(["event": reason, "unique_devices": counts.count, "observations": counts.values.reduce(0,+)])
        exit(code)
    }
}
let seconds = min(45, max(5, Double(CommandLine.arguments.dropFirst().first ?? "25") ?? 25))
let scanner = AdvertisementScanner(seconds: seconds)
RunLoop.main.run()
