import CoreBluetooth
import Foundation
import Observation

/// Bluetooth Smart (BLE) heart-rate monitor — wraps CBCentralManager
/// to discover sensors advertising the Heart Rate Service (`0x180D`),
/// connect, subscribe to the Heart Rate Measurement characteristic
/// (`0x2A37`), and stream BPM samples to whoever's listening.
///
/// Designed for cycling chest straps (Polar H10, Wahoo TICKR, Garmin
/// HRM-Dual, etc.) but works with any sensor implementing the
/// Bluetooth SIG standard Heart Rate Service.
///
/// State machine:
///   .poweredOff       → user has BT off, ask them to enable
///   .unauthorized     → first-launch permission denied
///   .idle             → BT ready, not scanning, not paired
///   .scanning         → CBCentralManager.scanForPeripherals running
///   .connecting       → mid-connect to a discovered sensor
///   .connected        → subscribed, BPM flowing through `currentBpm`
///
/// The discovered list is exposed as `discoveredPeripherals` so the
/// pairing UI can render a picker. Once the user taps a sensor, the
/// manager auto-stops the scan + initiates connection. Last-paired
/// peripheral UUID is persisted to UserDefaults so reconnect-on-launch
/// is possible later (not done here — keep v1 minimal).
@Observable
@MainActor
final class HeartRateMonitor: NSObject {
    /// Nonisolated init so AppEnvironment (not @MainActor) can build
    /// the instance during its own init. The class's mutable state is
    /// still MainActor-isolated; the synthesized init only assigns
    /// constants + calls super.init() which doesn't touch MainActor state.
    nonisolated override init() {
        super.init()
    }

    enum State: Equatable {
        case poweredOff
        case unauthorized
        case idle
        case scanning
        case connecting
        case connected(deviceName: String)
    }

    private(set) var state: State = .idle
    /// Live HR reading from the connected sensor. Nil when not connected.
    private(set) var currentBpm: Int?
    /// Battery level (0-100) if the sensor exposes the optional
    /// Battery Service `0x180F`. Many chest straps do; some don't.
    private(set) var batteryPct: Int?
    /// Peripherals seen during the current scan. Sorted by RSSI desc
    /// (strongest signal first) so the user's own sensor — typically
    /// strapped to their chest, < 1 m away — rises to the top.
    private(set) var discoveredPeripherals: [DiscoveredSensor] = []

    /// Set by RideTracker (or any client) — called every time a fresh
    /// HR sample arrives. The signature stays small so we don't have
    /// to lock the API in.
    var onBpmUpdate: ((Int) -> Void)?

    private var central: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var hrCharacteristic: CBCharacteristic?

    // SIG-assigned UUIDs — DO NOT change.
    private let heartRateServiceUUID  = CBUUID(string: "180D")
    private let heartRateMeasurementCharUUID = CBUUID(string: "2A37")
    private let batteryServiceUUID    = CBUUID(string: "180F")
    private let batteryLevelCharUUID  = CBUUID(string: "2A19")

    /// Lazily initialise the central — instantiating CBCentralManager
    /// triggers the system Bluetooth permission prompt. We delay it
    /// until the user actively wants to scan so the prompt doesn't
    /// fire on app launch.
    func startScan() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil, options: [
                CBCentralManagerOptionShowPowerAlertKey: true,
            ])
            return // delegate will start scan once .poweredOn fires
        }
        guard let central, central.state == .poweredOn else { return }
        discoveredPeripherals.removeAll()
        state = .scanning
        // Filter by the HR service UUID so we only see relevant sensors
        // (not someone's AirPods or speaker).
        central.scanForPeripherals(
            withServices: [heartRateServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false],
        )
        Log.tracking.notice("BLE HR: scanning for sensors")
    }

    func stopScan() {
        central?.stopScan()
        if state == .scanning { state = .idle }
    }

    func connect(_ sensor: DiscoveredSensor) {
        guard let central else { return }
        stopScan()
        state = .connecting
        connectedPeripheral = sensor.peripheral
        sensor.peripheral.delegate = self
        central.connect(sensor.peripheral, options: nil)
        Log.tracking.notice("BLE HR: connecting to \(sensor.name, privacy: .public)")
    }

    func disconnect() {
        guard let central, let peripheral = connectedPeripheral else { return }
        central.cancelPeripheralConnection(peripheral)
        connectedPeripheral = nil
        hrCharacteristic = nil
        currentBpm = nil
        batteryPct = nil
        state = .idle
    }

    /// One row in the pairing UI.
    struct DiscoveredSensor: Identifiable, Hashable {
        let peripheral: CBPeripheral
        let rssi: Int
        var id: UUID { peripheral.identifier }
        var name: String {
            peripheral.name ?? "Capteur \(peripheral.identifier.uuidString.prefix(4))"
        }
        // Equatable / Hashable on peripheral identifier so SwiftUI
        // ForEach diffing works across re-renders.
        static func == (lhs: DiscoveredSensor, rhs: DiscoveredSensor) -> Bool {
            lhs.peripheral.identifier == rhs.peripheral.identifier
        }
        func hash(into hasher: inout Hasher) {
            hasher.combine(peripheral.identifier)
        }
    }
}

// MARK: - CBCentralManagerDelegate (state changes + discovery)

extension HeartRateMonitor: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let mapped: State
        switch central.state {
        case .poweredOn:      mapped = .idle
        case .poweredOff:     mapped = .poweredOff
        case .unauthorized:   mapped = .unauthorized
        case .unsupported, .unknown, .resetting:
            mapped = .poweredOff
        @unknown default:
            mapped = .poweredOff
        }
        Task { @MainActor in
            self.state = mapped
            // If we had instantiated central JUST to scan, kick off
            // the scan now that we know the radio is on.
            if mapped == .idle && self.discoveredPeripherals.isEmpty {
                self.startScan()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Suppress noise — RSSI 0 / +127 means "unknown signal".
        let rssi = RSSI.intValue
        guard rssi != 127, rssi != 0 else { return }
        let sensor = DiscoveredSensor(peripheral: peripheral, rssi: rssi)
        Task { @MainActor in
            // Deduplicate by identifier; refresh RSSI on re-discovery.
            if let idx = self.discoveredPeripherals.firstIndex(where: { $0.peripheral.identifier == peripheral.identifier }) {
                self.discoveredPeripherals[idx] = sensor
            } else {
                self.discoveredPeripherals.append(sensor)
            }
            self.discoveredPeripherals.sort { $0.rssi > $1.rssi }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            Log.tracking.notice("BLE HR: connected to \(peripheral.name ?? "?", privacy: .public) — discovering services")
            peripheral.discoverServices([self.heartRateServiceUUID, self.batteryServiceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            Log.tracking.error("BLE HR: connect failed — \(error?.localizedDescription ?? "unknown", privacy: .public)")
            self.state = .idle
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            Log.tracking.notice("BLE HR: disconnected — \(error?.localizedDescription ?? "clean", privacy: .public)")
            self.currentBpm = nil
            self.batteryPct = nil
            self.hrCharacteristic = nil
            self.state = .idle
        }
    }
}

// MARK: - CBPeripheralDelegate (service / characteristic discovery + notifications)

extension HeartRateMonitor: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == heartRateServiceUUID {
                peripheral.discoverCharacteristics([heartRateMeasurementCharUUID], for: service)
            } else if service.uuid == batteryServiceUUID {
                peripheral.discoverCharacteristics([batteryLevelCharUUID], for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars {
            if char.uuid == heartRateMeasurementCharUUID {
                // Subscribe — HR strap will then notify us ~1 Hz with
                // each new measurement.
                peripheral.setNotifyValue(true, for: char)
                Task { @MainActor in
                    self.hrCharacteristic = char
                    self.state = .connected(deviceName: peripheral.name ?? "Capteur HR")
                }
            } else if char.uuid == batteryLevelCharUUID {
                // One-shot read; battery doesn't change every second.
                peripheral.readValue(for: char)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        if characteristic.uuid == heartRateMeasurementCharUUID {
            let bpm = parseHeartRate(data: data)
            Task { @MainActor in
                self.currentBpm = bpm
                self.onBpmUpdate?(bpm)
            }
        } else if characteristic.uuid == batteryLevelCharUUID {
            // Battery is a single byte 0-100.
            if let first = data.first {
                Task { @MainActor in self.batteryPct = Int(first) }
            }
        }
    }

    /// Parse the GATT Heart Rate Measurement characteristic. Layout:
    ///   byte 0     : flags  (bit 0 = HR is 16-bit if set, else 8-bit)
    ///   bytes 1..n : HR (1 or 2 bytes, little-endian)
    ///   + optional: energy expended, RR intervals (we ignore)
    /// Spec: https://www.bluetooth.com/specifications/specs/heart-rate-service-1-0/
    nonisolated private func parseHeartRate(data: Data) -> Int {
        guard !data.isEmpty else { return 0 }
        let flags = data[0]
        let isUInt16 = (flags & 0x01) != 0
        if isUInt16, data.count >= 3 {
            return Int(data[1]) | (Int(data[2]) << 8)
        }
        if data.count >= 2 {
            return Int(data[1])
        }
        return 0
    }
}
