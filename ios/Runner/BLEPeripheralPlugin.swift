import UIKit
import Flutter
import CoreBluetooth

/// BLE Peripheral plugin — exposes CBPeripheralManager to Flutter.
///
/// Handles advertising, characteristic setup, and data exchange with centrals.
class BLEPeripheralPlugin: NSObject, FlutterPlugin, CBPeripheralManagerDelegate {

    static let SERVICE_UUID = CBUUID(string: "F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C")
    static let CHARACTERISTIC_UUID = CBUUID(string: "A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D")

    private var peripheralManager: CBPeripheralManager?
    private var characteristic: CBMutableCharacteristic?
    private var channel: FlutterMethodChannel?
    private var connectedCentrals: [CBCentral] = []

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.ebwood.bitchat/ble_peripheral",
            binaryMessenger: registrar.messenger()
        )
        let instance = BLEPeripheralPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
            result("idle")

        case "startAdvertising":
            guard let args = call.arguments as? [String: Any],
                  let serviceUUID = args["serviceUUID"] as? String,
                  let charUUID = args["characteristicUUID"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing UUIDs", details: nil))
                return
            }

            let sUUID = CBUUID(string: serviceUUID)
            let cUUID = CBUUID(string: charUUID)

            characteristic = CBMutableCharacteristic(
                type: cUUID,
                properties: [.read, .write, .notify, .writeWithoutResponse],
                value: nil,
                permissions: [.readable, .writeable]
            )

            let service = CBMutableService(type: sUUID, primary: true)
            service.characteristics = [characteristic!]
            peripheralManager?.add(service)

            let localName = args["localName"] as? String ?? "BitChat"
            peripheralManager?.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [sUUID],
                CBAdvertisementDataLocalNameKey: localName
            ])
            result(true)

        case "stopAdvertising":
            peripheralManager?.stopAdvertising()
            peripheralManager?.removeAllServices()
            connectedCentrals.removeAll()
            result(nil)

        case "sendData":
            guard let args = call.arguments as? [String: Any],
                  let data = args["data"] as? FlutterStandardTypedData,
                  let char = characteristic else {
                result(false)
                return
            }

            let success = peripheralManager?.updateValue(
                data.data,
                for: char,
                onSubscribedCentrals: nil
            ) ?? false
            result(success)

        case "getConnectedCount":
            result(connectedCentrals.count)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - CBPeripheralManagerDelegate

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let state: String
        switch peripheral.state {
        case .poweredOn: state = "idle"
        case .poweredOff: state = "unknown"
        case .unauthorized: state = "unauthorized"
        case .unsupported: state = "unsupported"
        default: state = "unknown"
        }
        channel?.invokeMethod("onStateChanged", arguments: state)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        if !connectedCentrals.contains(where: { $0.identifier == central.identifier }) {
            connectedCentrals.append(central)
        }
        channel?.invokeMethod("onCentralConnected", arguments: central.identifier.uuidString)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        connectedCentrals.removeAll { $0.identifier == central.identifier }
        channel?.invokeMethod("onCentralDisconnected", arguments: central.identifier.uuidString)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let data = request.value {
                channel?.invokeMethod("onDataReceived", arguments: [
                    "data": FlutterStandardTypedData(bytes: data),
                    "centralId": request.central.identifier.uuidString
                ])
            }
            peripheral.respond(to: request, withResult: .success)
        }
    }
}
