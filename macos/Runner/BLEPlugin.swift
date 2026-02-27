import Cocoa
import FlutterMacOS
import CoreBluetooth

/// Native macOS BLE Central plugin — bypasses flutter_blue_plus for reliable
/// CoreBluetooth connections (matching original BLEService.swift behavior).
class BLEPlugin: NSObject, FlutterPlugin {

    // MARK: - Constants (must match Android/iOS originals)

    static let serviceUUID = CBUUID(string: "F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C")
    static let characteristicUUID = CBUUID(string: "A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D")

    // MARK: - Flutter Channels

    private let methodChannel: FlutterMethodChannel
    private let scanEventChannel: FlutterEventChannel
    private let connectionEventChannel: FlutterEventChannel
    private let dataEventChannel: FlutterEventChannel

    private var scanEventSink: FlutterEventSink? { scanHandler.sink }
    private var connectionEventSink: FlutterEventSink? { connectionHandler.sink }
    private var dataEventSink: FlutterEventSink? { dataHandler.sink }

    private let scanHandler = StreamHandler()
    private let connectionHandler = StreamHandler()
    private let dataHandler = StreamHandler()

    // MARK: - CoreBluetooth

    private var centralManager: CBCentralManager!
    private var discoveredPeripherals: [String: CBPeripheral] = [:]
    private var connectedPeripherals: [String: CBPeripheral] = [:]
    private var characteristics: [String: CBCharacteristic] = [:] // peripheralUUID -> characteristic
    private var connectingSet: Set<String> = []

    // MARK: - Plugin Registration

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = BLEPlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel)
    }

    init(registrar: FlutterPluginRegistrar) {
        methodChannel = FlutterMethodChannel(
            name: "com.bitchat/ble",
            binaryMessenger: registrar.messenger
        )
        scanEventChannel = FlutterEventChannel(
            name: "com.bitchat/ble/scan",
            binaryMessenger: registrar.messenger
        )
        connectionEventChannel = FlutterEventChannel(
            name: "com.bitchat/ble/connection",
            binaryMessenger: registrar.messenger
        )
        dataEventChannel = FlutterEventChannel(
            name: "com.bitchat/ble/data",
            binaryMessenger: registrar.messenger
        )

        super.init()

        scanEventChannel.setStreamHandler(scanHandler)
        connectionEventChannel.setStreamHandler(connectionHandler)
        dataEventChannel.setStreamHandler(dataHandler)

        // Initialize CBCentralManager on a background queue (like original BLEService)
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue(label: "com.bitchat.ble", qos: .userInitiated))
    }

    // MARK: - Method Call Handler

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getAdapterState":
            result(centralManager.state == .poweredOn)

        case "startScan":
            startScan(result: result)

        case "stopScan":
            centralManager.stopScan()
            result(nil)

        case "connect":
            guard let args = call.arguments as? [String: Any],
                  let deviceId = args["deviceId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "deviceId required", details: nil))
                return
            }
            connectToDevice(deviceId: deviceId, result: result)

        case "disconnect":
            guard let args = call.arguments as? [String: Any],
                  let deviceId = args["deviceId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "deviceId required", details: nil))
                return
            }
            disconnectDevice(deviceId: deviceId, result: result)

        case "write":
            guard let args = call.arguments as? [String: Any],
                  let deviceId = args["deviceId"] as? String,
                  let data = args["data"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGS", message: "deviceId and data required", details: nil))
                return
            }
            writeData(deviceId: deviceId, data: data.data, result: result)

        case "disconnectAll":
            disconnectAll()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - BLE Operations

    private func startScan(result: FlutterResult) {
        guard centralManager.state == .poweredOn else {
            result(FlutterError(code: "BT_OFF", message: "Bluetooth is not powered on", details: nil))
            return
        }
        // Scan with service filter and allow duplicates (like original)
        centralManager.scanForPeripherals(
            withServices: [BLEPlugin.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        result(nil)
    }

    private func connectToDevice(deviceId: String, result: FlutterResult) {
        guard let peripheral = discoveredPeripherals[deviceId] else {
            result(FlutterError(code: "NOT_FOUND", message: "Device not discovered: \(deviceId)", details: nil))
            return
        }
        guard !connectingSet.contains(deviceId),
              connectedPeripherals[deviceId] == nil else {
            result(nil) // Already connecting or connected
            return
        }

        connectingSet.insert(deviceId)

        // Connect with notification options (matching original BLEService.swift)
        let options: [String: Any] = [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey: true
        ]
        centralManager.connect(peripheral, options: options)

        // Manual timeout (matching original — TransportConfig.bleConnectTimeoutSeconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self,
                  self.connectingSet.contains(deviceId),
                  self.connectedPeripherals[deviceId] == nil else { return }

            // Timeout — cancel connection
            self.centralManager.cancelPeripheralConnection(peripheral)
            self.connectingSet.remove(deviceId)
            self.sendConnectionEvent(deviceId: deviceId, state: "timeout")
        }

        result(nil)
    }

    private func disconnectDevice(deviceId: String, result: FlutterResult) {
        if let peripheral = connectedPeripherals[deviceId] ?? discoveredPeripherals[deviceId] {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripherals.removeValue(forKey: deviceId)
        connectingSet.remove(deviceId)
        characteristics.removeValue(forKey: deviceId)
        result(nil)
    }

    private func disconnectAll() {
        for (_, peripheral) in connectedPeripherals {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        for (id, peripheral) in discoveredPeripherals where connectingSet.contains(id) {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripherals.removeAll()
        connectingSet.removeAll()
        characteristics.removeAll()
    }

    private func writeData(deviceId: String, data: Data, result: FlutterResult) {
        guard let characteristic = characteristics[deviceId] else {
            result(FlutterError(code: "NOT_CONNECTED", message: "No characteristic for \(deviceId)", details: nil))
            return
        }
        guard let peripheral = connectedPeripherals[deviceId] else {
            result(FlutterError(code: "NOT_CONNECTED", message: "Not connected to \(deviceId)", details: nil))
            return
        }

        // Use writeWithResponse for reliability (matching original)
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write)
            ? .withResponse
            : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: writeType)
        result(nil)
    }

    // MARK: - Event Helpers

    private func sendScanEvent(deviceId: String, rssi: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.scanEventSink?([
                "deviceId": deviceId,
                "rssi": rssi
            ])
        }
    }

    private func sendConnectionEvent(deviceId: String, state: String) {
        DispatchQueue.main.async { [weak self] in
            self?.connectionEventSink?([
                "deviceId": deviceId,
                "state": state
            ])
        }
    }

    private func sendDataEvent(deviceId: String, data: Data) {
        DispatchQueue.main.async { [weak self] in
            self?.dataEventSink?([
                "deviceId": deviceId,
                "data": FlutterStandardTypedData(bytes: data)
            ])
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEPlugin: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let stateStr: String
        switch central.state {
        case .poweredOn: stateStr = "on"
        case .poweredOff: stateStr = "off"
        case .unauthorized: stateStr = "unauthorized"
        case .unsupported: stateStr = "unsupported"
        default: stateStr = "unknown"
        }
        DispatchQueue.main.async { [weak self] in
            self?.methodChannel.invokeMethod("onAdapterStateChanged", arguments: stateStr)
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let deviceId = peripheral.identifier.uuidString
        discoveredPeripherals[deviceId] = peripheral
        sendScanEvent(deviceId: deviceId, rssi: RSSI.intValue)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let deviceId = peripheral.identifier.uuidString
        connectingSet.remove(deviceId)
        connectedPeripherals[deviceId] = peripheral
        peripheral.delegate = self
        sendConnectionEvent(deviceId: deviceId, state: "connected")

        // Discover our service
        peripheral.discoverServices([BLEPlugin.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let deviceId = peripheral.identifier.uuidString
        connectingSet.remove(deviceId)
        sendConnectionEvent(deviceId: deviceId, state: "failed")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let deviceId = peripheral.identifier.uuidString
        connectedPeripherals.removeValue(forKey: deviceId)
        connectingSet.remove(deviceId)
        characteristics.removeValue(forKey: deviceId)
        sendConnectionEvent(deviceId: deviceId, state: "disconnected")
    }
}

// MARK: - CBPeripheralDelegate

extension BLEPlugin: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == BLEPlugin.serviceUUID }) else {
            return
        }
        peripheral.discoverCharacteristics([BLEPlugin.characteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil,
              let characteristic = service.characteristics?.first(where: { $0.uuid == BLEPlugin.characteristicUUID }) else {
            return
        }

        let deviceId = peripheral.identifier.uuidString
        characteristics[deviceId] = characteristic

        // Subscribe to notifications
        if characteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: characteristic)
        }

        // Notify Flutter that the device is fully ready
        sendConnectionEvent(deviceId: deviceId, state: "ready")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil,
              let data = characteristic.value, !data.isEmpty else { return }

        let deviceId = peripheral.identifier.uuidString
        sendDataEvent(deviceId: deviceId, data: data)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            let deviceId = peripheral.identifier.uuidString
            NSLog("[BLEPlugin] Write error for \(deviceId): \(error.localizedDescription)")
        }
    }
}

// MARK: - FlutterStreamHandler helper

private class StreamHandler: NSObject, FlutterStreamHandler {
    var sink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }
}
