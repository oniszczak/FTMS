// (C) 2026 Aleks Oniszczak

import Foundation
import Combine
import CoreBluetooth

struct DiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
    let advertisesFTMS: Bool
    let advertisesCSC: Bool
}

struct LiveMetric: Identifiable, Equatable {
    let id: String
    let name: String
    let value: String

    init(name: String, value: String) {
        self.id = name
        self.name = name
        self.value = value
    }
}

struct RawCharacteristicValue: Identifiable, Equatable {
    let id: String
    let name: String
    let uuid: String
    let valueHex: String
}

private struct CSCSnapshot {
    var wheelRevolutions: UInt32?
    var wheelEventTime: UInt16?
    var crankRevolutions: UInt16?
    var crankEventTime: UInt16?
}

@MainActor
final class FTMSManager: NSObject, ObservableObject {
    @Published private(set) var bluetoothState: String = "Starting Bluetooth..."
    @Published private(set) var isScanning = false
    @Published private(set) var discoveredDevices: [DiscoveredDevice] = []
    @Published private(set) var connectedDeviceName: String?
    @Published private(set) var connectionState: String = "Not connected"
    @Published private(set) var metrics: [LiveMetric] = []
    @Published private(set) var rawValues: [RawCharacteristicValue] = []
    @Published private(set) var activityUnits: Int = 0
    @Published private(set) var lastError: String?

    private let ftmsServiceUUID = CBUUID(string: "1826")
    private let cscServiceUUID = CBUUID(string: "1816")
    private var centralManager: CBCentralManager!
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var metricStore: [String: String] = [:]
    private var rawStore: [String: RawCharacteristicValue] = [:]
    private var cscSnapshots: [UUID: CSCSnapshot] = [:]
    private var lastRowerStrokeCount: UInt16?
    private var rowerStrokeCountBaseline: UInt16?
    private var shouldUseRowerStrokeCountForUnits = false

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard centralManager.state == .poweredOn else {
            lastError = "Bluetooth is not ready yet."
            return
        }

        if isScanning {
            return
        }

        discoveredDevices = []
        peripheralsByID = [:]
        lastError = nil

        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
    }

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
    }

    func connect(to device: DiscoveredDevice) {
        guard let peripheral = peripheralsByID[device.id] else {
            lastError = "Device is no longer available."
            return
        }

        stopScan()
        clearLiveData()
        peripheral.delegate = self
        connectedDeviceName = device.name
        connectionState = "Connecting to \(device.name)..."
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = connectedPeripheral else {
            return
        }

        centralManager.cancelPeripheralConnection(peripheral)
    }

    private var connectedPeripheral: CBPeripheral? {
        peripheralsByID.values.first { $0.state == .connected || $0.state == .connecting }
    }

    private func clearLiveData() {
        metricStore = [:]
        metrics = []
        rawStore = [:]
        rawValues = []
        cscSnapshots = [:]
        lastRowerStrokeCount = nil
        rowerStrokeCountBaseline = nil
        shouldUseRowerStrokeCountForUnits = false
        activityUnits = 0
    }

    private func updateMetric(_ name: String, _ value: String) {
        metricStore[name] = value
        metrics = metricStore
            .keys
            .sorted()
            .map { LiveMetric(name: $0, value: metricStore[$0] ?? "") }
    }

    private func updateRaw(uuid: String, name: String, hex: String) {
        rawStore[uuid] = RawCharacteristicValue(id: uuid, name: name, uuid: uuid, valueHex: hex)
        rawValues = rawStore
            .values
            .sorted { $0.name < $1.name }
    }

    private func addActivityUnits(_ units: Int) {
        guard units > 0 else { return }
        activityUnits += units
    }

    private func parse(data: Data, for characteristicUUID: String, peripheralID: UUID) {
        let parser = FTMSParser(data: data)

        switch characteristicUUID.uppercased() {
        case "2AD2":
            parseIndoorBikeData(parser)
        case "2AD1":
            parseRowerData(parser)
        case "2ADA":
            parseFitnessMachineStatus(parser)
        case "2A37":
            parseHeartRateMeasurement(parser)
        case "2A63":
            parseCyclingPowerMeasurement(parser)
        case "2ACC":
            parseFitnessMachineFeature(parser)
        case "2A5B":
            parseCyclingSpeedCadenceMeasurement(parser, peripheralID: peripheralID)
        case "2A5C":
            parseCSCFeature(parser)
        case "2A5D":
            parseSensorLocation(parser)
        default:
            break
        }
    }

    private func parseIndoorBikeData(_ parser: FTMSParser) {
        guard let flags = parser.readUInt16(at: 0) else { return }
        var index = 2

        if let speed = parser.readUInt16(at: index) {
            updateMetric("Bike Speed", String(format: "%.2f km/h", Double(speed) / 100.0))
            index += 2
        }

        if flags.bit(1), let avgSpeed = parser.readUInt16(at: index) {
            updateMetric("Bike Average Speed", String(format: "%.2f km/h", Double(avgSpeed) / 100.0))
            index += 2
        }

        if flags.bit(2), let cadence = parser.readUInt16(at: index) {
            updateMetric("Bike Cadence", String(format: "%.1f rpm", Double(cadence) / 2.0))
            index += 2
        }

        if flags.bit(3), let avgCadence = parser.readUInt16(at: index) {
            updateMetric("Bike Average Cadence", String(format: "%.1f rpm", Double(avgCadence) / 2.0))
            index += 2
        }

        if flags.bit(4), let distance = parser.readUInt24(at: index) {
            updateMetric("Bike Distance", "\(distance) m")
            index += 3
        }

        if flags.bit(5), let resistance = parser.readInt16(at: index) {
            updateMetric("Bike Resistance Level", "\(resistance)")
            index += 2
        }

        if flags.bit(6), let power = parser.readInt16(at: index) {
            updateMetric("Bike Power", "\(power) W")
            index += 2
        }

        if flags.bit(7), let avgPower = parser.readInt16(at: index) {
            updateMetric("Bike Average Power", "\(avgPower) W")
            index += 2
        }

        if flags.bit(8) {
            if let totalEnergy = parser.readUInt16(at: index) {
                updateMetric("Bike Total Energy", "\(totalEnergy) kcal")
                index += 2
            }

            if let energyPerHour = parser.readUInt16(at: index) {
                updateMetric("Bike Energy Per Hour", "\(energyPerHour) kcal/h")
                index += 2
            }

            if let energyPerMinute = parser.readUInt8(at: index) {
                updateMetric("Bike Energy Per Minute", "\(energyPerMinute) kcal/min")
                index += 1
            }
        }

        if flags.bit(9), let heartRate = parser.readUInt8(at: index) {
            updateMetric("Heart Rate", "\(heartRate) bpm")
            index += 1
        }

        if flags.bit(10), let met = parser.readUInt8(at: index) {
            updateMetric("Bike MET", String(format: "%.1f", Double(met) / 10.0))
            index += 1
        }

        if flags.bit(11), let elapsed = parser.readUInt16(at: index) {
            updateMetric("Elapsed Time", "\(elapsed) s")
            index += 2
        }

        if flags.bit(12), let remaining = parser.readUInt16(at: index) {
            updateMetric("Remaining Time", "\(remaining) s")
        }
    }

    private func parseRowerData(_ parser: FTMSParser) {
        guard let flags = parser.readUInt16(at: 0) else { return }
        var index = 2

        if let strokeRate = parser.readUInt8(at: index) {
            updateMetric("Rower Stroke Rate", String(format: "%.1f spm", Double(strokeRate) / 2.0))
            index += 1
        }

        if let strokeCount = parser.readUInt16(at: index) {
            updateMetric("Rower Stroke Count", "\(strokeCount)")
            shouldUseRowerStrokeCountForUnits = true

            if rowerStrokeCountBaseline == nil {
                rowerStrokeCountBaseline = strokeCount
            }

            if let baseline = rowerStrokeCountBaseline {
                if strokeCount >= baseline {
                    // Rower units follow displayed stroke count exactly from session baseline.
                    activityUnits = Int(strokeCount - baseline)
                } else {
                    // If the machine resets the stroke counter, reset baseline to avoid jumps.
                    rowerStrokeCountBaseline = strokeCount
                    activityUnits = 0
                }
            }

            lastRowerStrokeCount = strokeCount
            index += 2
        }

        if flags.bit(1), let avgStrokeRate = parser.readUInt8(at: index) {
            updateMetric("Rower Average Stroke Rate", String(format: "%.1f spm", Double(avgStrokeRate) / 2.0))
            index += 1
        }

        if flags.bit(2), let distance = parser.readUInt24(at: index) {
            updateMetric("Rower Distance", "\(distance) m")
            index += 3
        }

        if flags.bit(3), let pace = parser.readUInt16(at: index) {
            updateMetric("Rower Pace", "\(pace) /500m")
            index += 2
        }

        if flags.bit(4), let avgPace = parser.readUInt16(at: index) {
            updateMetric("Rower Average Pace", "\(avgPace) /500m")
            index += 2
        }

        if flags.bit(5), let power = parser.readInt16(at: index) {
            updateMetric("Rower Power", "\(power) W")
            index += 2
        }

        if flags.bit(6), let avgPower = parser.readInt16(at: index) {
            updateMetric("Rower Average Power", "\(avgPower) W")
            index += 2
        }

        if flags.bit(7), let resistance = parser.readInt16(at: index) {
            updateMetric("Rower Resistance Level", "\(resistance)")
            index += 2
        }

        if flags.bit(8) {
            if let totalEnergy = parser.readUInt16(at: index) {
                updateMetric("Rower Total Energy", "\(totalEnergy) kcal")
                index += 2
            }

            if let energyPerHour = parser.readUInt16(at: index) {
                updateMetric("Rower Energy Per Hour", "\(energyPerHour) kcal/h")
                index += 2
            }

            if let energyPerMinute = parser.readUInt8(at: index) {
                updateMetric("Rower Energy Per Minute", "\(energyPerMinute) kcal/min")
                index += 1
            }
        }

        if flags.bit(9), let heartRate = parser.readUInt8(at: index) {
            updateMetric("Heart Rate", "\(heartRate) bpm")
            index += 1
        }

        if flags.bit(10), let met = parser.readUInt8(at: index) {
            updateMetric("Rower MET", String(format: "%.1f", Double(met) / 10.0))
            index += 1
        }

        if flags.bit(11), let elapsed = parser.readUInt16(at: index) {
            updateMetric("Elapsed Time", "\(elapsed) s")
            index += 2
        }

        if flags.bit(12), let remaining = parser.readUInt16(at: index) {
            updateMetric("Remaining Time", "\(remaining) s")
        }
    }

    private func parseFitnessMachineStatus(_ parser: FTMSParser) {
        guard let statusCode = parser.readUInt8(at: 0) else { return }
        let status = switch statusCode {
        case 0x01: "Reset"
        case 0x02: "Stopped or Paused by User"
        case 0x03: "Stopped by Safety Key"
        case 0x04: "Started or Resumed"
        case 0x05: "Target Speed Changed"
        case 0x06: "Target Incline Changed"
        case 0x07: "Target Resistance Changed"
        case 0x08: "Target Power Changed"
        case 0x09: "Target Heart Rate Changed"
        case 0x0A: "Targeted Expended Energy Changed"
        case 0x0B: "Targeted Number of Steps Changed"
        case 0x0C: "Targeted Number of Strides Changed"
        case 0x0D: "Targeted Distance Changed"
        case 0x0E: "Targeted Training Time Changed"
        case 0x0F: "Targeted Time in Two Heart Rate Zones Changed"
        case 0x10: "Targeted Time in Three Heart Rate Zones Changed"
        case 0x11: "Targeted Time in Five Heart Rate Zones Changed"
        case 0x12: "Indoor Bike Simulation Parameters Changed"
        case 0x13: "Wheel Circumference Changed"
        case 0x14: "Spin Down Status"
        case 0x15: "Targeted Cadence Changed"
        default: "Status Code \(statusCode)"
        }

        updateMetric("FTMS Status", status)
    }

    private func parseHeartRateMeasurement(_ parser: FTMSParser) {
        guard let flags = parser.readUInt8(at: 0) else { return }

        if flags.bit(0), let hr = parser.readUInt16(at: 1) {
            updateMetric("Heart Rate", "\(hr) bpm")
        } else if let hr = parser.readUInt8(at: 1) {
            updateMetric("Heart Rate", "\(hr) bpm")
        }
    }

    private func parseCyclingPowerMeasurement(_ parser: FTMSParser) {
        guard let power = parser.readInt16(at: 2) else { return }
        updateMetric("Cycling Power", "\(power) W")
    }

    private func parseFitnessMachineFeature(_ parser: FTMSParser) {
        guard let machineFeatures = parser.readUInt32(at: 0), let targetFeatures = parser.readUInt32(at: 4) else { return }
        updateMetric("FTMS Machine Feature Flags", String(format: "0x%08X", machineFeatures))
        updateMetric("FTMS Target Setting Feature Flags", String(format: "0x%08X", targetFeatures))
    }

    private func parseCyclingSpeedCadenceMeasurement(_ parser: FTMSParser, peripheralID: UUID) {
        guard let flags = parser.readUInt8(at: 0) else { return }
        var index = 1

        var snapshot = cscSnapshots[peripheralID] ?? CSCSnapshot()
        var wheelDeltaForUnits: Int?
        var crankDeltaForUnits: Int?

        if flags.bit(0), let wheelRevolutions = parser.readUInt32(at: index), let wheelEventTime = parser.readUInt16(at: index + 4) {
            updateMetric("CSC Wheel Revolutions", "\(wheelRevolutions)")

            if let previousRevolutions = snapshot.wheelRevolutions,
               let previousEventTime = snapshot.wheelEventTime,
               let deltaSeconds = deltaEventSeconds(current: wheelEventTime, previous: previousEventTime),
               deltaSeconds > 0,
               let deltaRevolutions = deltaCounter(current: wheelRevolutions, previous: previousRevolutions),
               deltaRevolutions > 0 {
                let revPerSecond = Double(deltaRevolutions) / deltaSeconds
                let speedMetersPerSecond = revPerSecond * 2.105
                updateMetric("CSC Speed", String(format: "%.2f km/h", speedMetersPerSecond * 3.6))
                updateMetric("CSC Wheel RPM", String(format: "%.1f rpm", revPerSecond * 60.0))
                wheelDeltaForUnits = Int(deltaRevolutions)
            }

            snapshot.wheelRevolutions = wheelRevolutions
            snapshot.wheelEventTime = wheelEventTime
            index += 6
        }

        if flags.bit(1), let crankRevolutions = parser.readUInt16(at: index), let crankEventTime = parser.readUInt16(at: index + 2) {
            updateMetric("CSC Crank Revolutions", "\(crankRevolutions)")

            if let previousRevolutions = snapshot.crankRevolutions,
               let previousEventTime = snapshot.crankEventTime,
               let deltaSeconds = deltaEventSeconds(current: crankEventTime, previous: previousEventTime),
               deltaSeconds > 0,
               let deltaRevolutions = deltaCounter(current: crankRevolutions, previous: previousRevolutions),
               deltaRevolutions > 0 {
                let cadenceRPM = (Double(deltaRevolutions) / deltaSeconds) * 60.0
                updateMetric("CSC Cadence", String(format: "%.1f rpm", cadenceRPM))
                crankDeltaForUnits = Int(deltaRevolutions)
            }

            snapshot.crankRevolutions = crankRevolutions
            snapshot.crankEventTime = crankEventTime
        }

        if !shouldUseRowerStrokeCountForUnits {
            // For bike-like devices, prefer crank rotations for unit pacing.
            if let crankDeltaForUnits, crankDeltaForUnits > 0 {
                addActivityUnits(crankDeltaForUnits)
            } else if let wheelDeltaForUnits, wheelDeltaForUnits > 0 {
                addActivityUnits(wheelDeltaForUnits)
            }
        }

        cscSnapshots[peripheralID] = snapshot
    }

    private func parseCSCFeature(_ parser: FTMSParser) {
        guard let featureFlags = parser.readUInt16(at: 0) else { return }
        updateMetric("CSC Feature Flags", String(format: "0x%04X", featureFlags))
    }

    private func parseSensorLocation(_ parser: FTMSParser) {
        guard let locationRaw = parser.readUInt8(at: 0) else { return }
        let location: String
        switch locationRaw {
        case 0: location = "Other"
        case 1: location = "Top of Shoe"
        case 2: location = "In Shoe"
        case 3: location = "Hip"
        case 4: location = "Front Wheel"
        case 5: location = "Left Crank"
        case 6: location = "Right Crank"
        case 7: location = "Left Pedal"
        case 8: location = "Right Pedal"
        case 9: location = "Front Hub"
        case 10: location = "Rear Dropout"
        case 11: location = "Chainstay"
        case 12: location = "Rear Wheel"
        case 13: location = "Rear Hub"
        case 14: location = "Chest"
        case 15: location = "Spider"
        case 16: location = "Chain Ring"
        default: location = "Unknown (\(locationRaw))"
        }
        updateMetric("Sensor Location", location)
    }

    private func deltaEventSeconds(current: UInt16, previous: UInt16) -> Double? {
        let ticks: UInt16
        if current >= previous {
            ticks = current - previous
        } else {
            ticks = current &+ (UInt16.max - previous) &+ 1
        }
        guard ticks > 0 else { return nil }
        return Double(ticks) / 1024.0
    }

    private func deltaCounter<T: FixedWidthInteger & UnsignedInteger>(current: T, previous: T) -> UInt64? {
        if current >= previous {
            return UInt64(current - previous)
        }
        let wrapped = current &+ (T.max - previous) &+ 1
        return UInt64(wrapped)
    }

    private func bluetoothStateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .unknown:
            return "Unknown"
        case .resetting:
            return "Resetting"
        case .unsupported:
            return "Unsupported on this device"
        case .unauthorized:
            return "Unauthorized. Enable Bluetooth permission in Settings."
        case .poweredOff:
            return "Powered Off"
        case .poweredOn:
            return "Powered On"
        @unknown default:
            return "Unknown state"
        }
    }

    private func characteristicName(for uuid: String) -> String {
        switch uuid.uppercased() {
        case "2AD2": return "Indoor Bike Data"
        case "2AD1": return "Rower Data"
        case "2ACE": return "Cross Trainer Data"
        case "2ACD": return "Treadmill Data"
        case "2ADA": return "Fitness Machine Status"
        case "2ACC": return "Fitness Machine Feature"
        case "2A37": return "Heart Rate Measurement"
        case "2A63": return "Cycling Power Measurement"
        case "2A5B": return "CSC Measurement"
        case "2A5C": return "CSC Feature"
        case "2A5D": return "Sensor Location"
        default: return "Characteristic \(uuid.uppercased())"
        }
    }

    private func advertisementScore(for device: DiscoveredDevice) -> Int {
        var score = 0
        if device.advertisesFTMS {
            score += 2
        }
        if device.advertisesCSC {
            score += 1
        }
        return score
    }
}

extension FTMSManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            bluetoothState = bluetoothStateDescription(central.state)
            if central.state != .poweredOn {
                stopScan()
                connectionState = "Bluetooth not ready"
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unnamed Device"
            let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
            let advertisesFTMS = serviceUUIDs.contains(ftmsServiceUUID)
            let advertisesCSC = serviceUUIDs.contains(cscServiceUUID)

            guard advertisesFTMS || advertisesCSC else {
                return
            }

            peripheralsByID[peripheral.identifier] = peripheral

            let candidate = DiscoveredDevice(
                id: peripheral.identifier,
                name: name,
                rssi: RSSI.intValue,
                advertisesFTMS: advertisesFTMS,
                advertisesCSC: advertisesCSC
            )

            if let existingIndex = discoveredDevices.firstIndex(where: { $0.id == candidate.id }) {
                discoveredDevices[existingIndex] = candidate
            } else {
                discoveredDevices.append(candidate)
            }

            discoveredDevices.sort {
                let leftScore = advertisementScore(for: $0)
                let rightScore = advertisementScore(for: $1)
                if leftScore != rightScore {
                    return leftScore > rightScore
                }
                return $0.rssi > $1.rssi
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectionState = "Connected to \(peripheral.name ?? "device")"
            connectedDeviceName = peripheral.name ?? "Connected device"
            clearLiveData()
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        Task { @MainActor in
            connectionState = "Failed to connect"
            lastError = error?.localizedDescription ?? "Unknown connection error"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        Task { @MainActor in
            connectionState = "Disconnected"
            connectedDeviceName = nil
            cscSnapshots[peripheral.identifier] = nil
            if let error {
                lastError = error.localizedDescription
            }
        }
    }
}

extension FTMSManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        Task { @MainActor in
            if let error {
                lastError = "Service discovery failed: \(error.localizedDescription)"
                return
            }

            guard let services = peripheral.services else { return }
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        Task { @MainActor in
            if let error {
                lastError = "Characteristic discovery failed: \(error.localizedDescription)"
                return
            }

            guard let characteristics = service.characteristics else { return }
            for characteristic in characteristics {
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic)
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        Task { @MainActor in
            if let error {
                lastError = "Update failed for \(characteristic.uuid.uuidString): \(error.localizedDescription)"
                return
            }

            guard let data = characteristic.value else { return }
            let uuid = characteristic.uuid.uuidString
            let name = characteristicName(for: uuid)
            let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")

            updateRaw(uuid: uuid, name: name, hex: hex)
            parse(data: data, for: uuid, peripheralID: peripheral.identifier)
        }
    }
}

private struct FTMSParser {
    let data: Data

    func readUInt8(at index: Int) -> UInt8? {
        guard index + 1 <= data.count else { return nil }
        return data[index]
    }

    func readUInt16(at index: Int) -> UInt16? {
        guard index + 2 <= data.count else { return nil }
        return UInt16(data[index]) | (UInt16(data[index + 1]) << 8)
    }

    func readInt16(at index: Int) -> Int16? {
        guard let value = readUInt16(at: index) else { return nil }
        return Int16(bitPattern: value)
    }

    func readUInt24(at index: Int) -> UInt32? {
        guard index + 3 <= data.count else { return nil }
        return UInt32(data[index]) | (UInt32(data[index + 1]) << 8) | (UInt32(data[index + 2]) << 16)
    }

    func readUInt32(at index: Int) -> UInt32? {
        guard index + 4 <= data.count else { return nil }
        return UInt32(data[index]) | (UInt32(data[index + 1]) << 8) | (UInt32(data[index + 2]) << 16) | (UInt32(data[index + 3]) << 24)
    }
}

private extension BinaryInteger {
    func bit(_ position: Int) -> Bool {
        ((self >> position) & 1) == 1
    }
}
