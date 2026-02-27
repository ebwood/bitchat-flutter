import Cocoa
import FlutterMacOS
import CoreBluetooth
import CoreLocation
import CryptoKit

// MARK: - Wire Protocol Types (matching original bitchat)

/// Message types matching original BitchatProtocol.swift
private enum MessageType: UInt8 {
    case announce = 0x01
    case message = 0x02
    case leave = 0x03
    case noiseHandshake = 0x10
    case noiseEncrypted = 0x11
    case fragment = 0x20
    case requestSync = 0x21
    case fileTransfer = 0x22
}

/// Minimal BitchatPacket matching original BitchatPacket.swift
private struct BitchatPacket {
    let version: UInt8
    let type: UInt8
    let senderID: Data   // 8 bytes
    let recipientID: Data?
    let timestamp: UInt64
    let payload: Data
    var signature: Data?
    var ttl: UInt8
    
    func toBinaryDataForSigning() -> Data? {
        let unsignedPacket = BitchatPacket(
            version: version,
            type: type,
            senderID: senderID,
            recipientID: recipientID,
            timestamp: timestamp,
            payload: payload,
            signature: nil,
            ttl: 0
        )
        return BinaryProtocol.encode(unsignedPacket)
    }
}

/// Minimal BinaryProtocol matching original BinaryProtocol.swift
/// Wire format (v1):
///   Version(1) | Type(1) | TTL(1) | Timestamp(8) | Flags(1) | PayloadLen(2)
///   SenderID(8) | [RecipientID(8)] | Payload | [Signature(64)]
private struct BinaryProtocol {
    static let headerSize = 14
    static let senderIDSize = 8
    static let recipientIDSize = 8
    static let signatureSize = 64

    struct Flags {
        static let hasRecipient: UInt8 = 0x01
        static let hasSignature: UInt8 = 0x02
        static let isCompressed: UInt8 = 0x04
    }

    static func encode(_ packet: BitchatPacket) -> Data? {
        var data = Data()
        data.reserveCapacity(headerSize + senderIDSize + packet.payload.count + 64)

        // Header
        data.append(packet.version)
        data.append(packet.type)
        data.append(packet.ttl)

        // Timestamp (big-endian 8 bytes)
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8((packet.timestamp >> UInt64(shift)) & 0xFF))
        }

        // Flags
        var flags: UInt8 = 0
        if packet.recipientID != nil { flags |= Flags.hasRecipient }
        if packet.signature != nil { flags |= Flags.hasSignature }
        data.append(flags)

        // Payload length (big-endian 2 bytes)
        let payloadLen = UInt16(packet.payload.count)
        data.append(UInt8((payloadLen >> 8) & 0xFF))
        data.append(UInt8(payloadLen & 0xFF))

        // SenderID (padded to 8 bytes)
        let senderBytes = packet.senderID.prefix(senderIDSize)
        data.append(senderBytes)
        if senderBytes.count < senderIDSize {
            data.append(Data(repeating: 0, count: senderIDSize - senderBytes.count))
        }

        // RecipientID (optional)
        if let recipientID = packet.recipientID {
            let recipientBytes = recipientID.prefix(recipientIDSize)
            data.append(recipientBytes)
            if recipientBytes.count < recipientIDSize {
                data.append(Data(repeating: 0, count: recipientIDSize - recipientBytes.count))
            }
        }

        // Payload
        data.append(packet.payload)

        // Signature (optional)
        if let signature = packet.signature {
            data.append(signature.prefix(signatureSize))
        }

        return data
    }

    static func decode(_ raw: Data) -> BitchatPacket? {
        guard raw.count >= headerSize + senderIDSize else {
            NSLog("[BinaryProtocol] Decode failed: raw data too short (\(raw.count) bytes)")
            return nil
        }

        var offset = 0
        func require(_ n: Int) -> Bool { offset + n <= raw.count }
        func read8() -> UInt8? {
            guard require(1) else { return nil }
            let v = raw[offset]
            offset += 1
            return v
        }
        func read16() -> UInt16? {
            guard require(2) else { return nil }
            let v = (UInt16(raw[offset]) << 8) | UInt16(raw[offset + 1])
            offset += 2
            return v
        }
        func readData(_ n: Int) -> Data? {
            guard require(n) else { return nil }
            let d = raw[offset..<offset + n]
            offset += n
            return Data(d)
        }

        guard let version = read8(), version == 1 || version == 2 else {
            NSLog("[BinaryProtocol] Decode failed: unsupported version")
            return nil
        }
        guard let type = read8(), let ttl = read8() else {
            NSLog("[BinaryProtocol] Decode failed: missing type/ttl")
            return nil
        }

        var timestamp: UInt64 = 0
        for _ in 0..<8 {
            guard let byte = read8() else {
                NSLog("[BinaryProtocol] Decode failed: incomplete timestamp")
                return nil
            }
            timestamp = (timestamp << 8) | UInt64(byte)
        }

        guard let flags = read8() else {
            NSLog("[BinaryProtocol] Decode failed: missing flags")
            return nil
        }
        let hasRecipient = (flags & Flags.hasRecipient) != 0
        let hasSignature = (flags & Flags.hasSignature) != 0
        let isCompressed = (flags & Flags.isCompressed) != 0

        // For v2, payload length is 4 bytes; for v1, 2 bytes
        let payloadLength: Int
        if version == 2 {
            guard require(4) else {
                NSLog("[BinaryProtocol] Decode failed: missing v2 payload length")
                return nil
            }
            let b0 = UInt32(raw[offset]) << 24
            let b1 = UInt32(raw[offset+1]) << 16
            let b2 = UInt32(raw[offset+2]) << 8
            let b3 = UInt32(raw[offset+3])
            payloadLength = Int(b0 | b1 | b2 | b3)
            offset += 4
        } else {
            guard let len = read16() else {
                NSLog("[BinaryProtocol] Decode failed: missing v1 payload length")
                return nil
            }
            payloadLength = Int(len)
        }

        guard payloadLength >= 0, payloadLength <= 65535 else {
            NSLog("[BinaryProtocol] Decode failed: invalid payload length \(payloadLength)")
            return nil
        }
        guard let senderID = readData(senderIDSize) else {
            NSLog("[BinaryProtocol] Decode failed: missing senderID")
            return nil
        }

        var recipientID: Data? = nil
        if hasRecipient {
            recipientID = readData(recipientIDSize)
            if recipientID == nil {
                NSLog("[BinaryProtocol] Decode failed: missing recipientID")
                return nil
            }
        }

        // Skip compressed payloads for now (chat messages are small)
        let payload: Data
        if isCompressed {
            // Skip original-size field and read raw compressed data
            // For simplicity, return nil for compressed packets
            NSLog("[BinaryProtocol] Decode failed: compressed payload not supported yet")
            return nil
        } else {
            guard let rawPayload = readData(payloadLength) else {
                NSLog("[BinaryProtocol] Decode failed: missing payload, expected \(payloadLength) bytes but have \(raw.count - offset)")
                return nil
            }
            payload = rawPayload
        }

        var signature: Data? = nil
        if hasSignature {
            signature = readData(signatureSize)
        }

        return BitchatPacket(
            version: version,
            type: type,
            senderID: senderID,
            recipientID: recipientID,
            timestamp: timestamp,
            payload: payload,
            signature: signature,
            ttl: ttl
        )
    }
}

/// AnnouncementPacket TLV matching original Packets.swift
private struct AnnouncementPacket {
    let nickname: String
    let noisePublicKey: Data
    let signingPublicKey: Data

    private enum TLVType: UInt8 {
        case nickname = 0x01
        case noisePublicKey = 0x02
        case signingPublicKey = 0x03
    }

    func encode() -> Data? {
        var data = Data()
        guard let nicknameData = nickname.data(using: .utf8), nicknameData.count <= 255 else { return nil }
        data.append(TLVType.nickname.rawValue)
        data.append(UInt8(nicknameData.count))
        data.append(nicknameData)

        guard noisePublicKey.count <= 255 else { return nil }
        data.append(TLVType.noisePublicKey.rawValue)
        data.append(UInt8(noisePublicKey.count))
        data.append(noisePublicKey)

        guard signingPublicKey.count <= 255 else { return nil }
        data.append(TLVType.signingPublicKey.rawValue)
        data.append(UInt8(signingPublicKey.count))
        data.append(signingPublicKey)

        return data
    }

    static func decode(from data: Data) -> AnnouncementPacket? {
        var offset = 0
        var nickname: String?
        var noisePublicKey: Data?
        var signingPublicKey: Data?

        while offset + 2 <= data.count {
            let typeRaw = data[offset]
            offset += 1
            let length = Int(data[offset])
            offset += 1
            guard offset + length <= data.count else { return nil }
            let value = data[offset..<offset + length]
            offset += length

            if let type = TLVType(rawValue: typeRaw) {
                switch type {
                case .nickname:
                    nickname = String(data: value, encoding: .utf8)
                case .noisePublicKey:
                    noisePublicKey = Data(value)
                case .signingPublicKey:
                    signingPublicKey = Data(value)
                }
            }
        }

        guard let nick = nickname, let noise = noisePublicKey, let signing = signingPublicKey else { return nil }
        return AnnouncementPacket(nickname: nick, noisePublicKey: noise, signingPublicKey: signing)
    }
}

// MARK: - BLEPlugin

/// Native macOS BLE plugin — Full dual-role (Central + Peripheral) mesh matching
/// original BLEService.swift behavior. Handles scanning, advertising, connecting,
/// BinaryProtocol packet encode/decode, and announcement exchange.
class BLEPlugin: NSObject, FlutterPlugin {

    // MARK: - Constants (matching original BLEService.swift)

    #if DEBUG
    static let serviceUUID = CBUUID(string: "F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5A") // testnet
    #else
    static let serviceUUID = CBUUID(string: "F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C") // mainnet
    #endif
    static let characteristicUUID = CBUUID(string: "A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D")

    private let defaultTTL: UInt8 = 3

    // MARK: - Location Support
    private var locationManager: CLLocationManager?
    private var pendingLocationResult: FlutterResult?

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

    // MARK: - CoreBluetooth (Dual Role)

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    private let bleQueue = DispatchQueue(label: "com.bitchat.ble", qos: .userInitiated)

    // Central role state
    private var discoveredPeripherals: [String: CBPeripheral] = [:]
    private var connectedPeripherals: [String: CBPeripheral] = [:]
    private var peripheralCharacteristics: [String: CBCharacteristic] = [:] // peripheralUUID -> characteristic
    private var connectingSet: Set<String> = []

    // Peripheral role state
    private var localCharacteristic: CBMutableCharacteristic?
    private var subscribedCentrals: [CBCentral] = []
    private var centralToPeerID: [String: String] = [:] // Central UUID -> hex peer ID
    private var pendingWriteBuffers: [String: Data] = [:] // Central UUID -> accumulated data

    // Identity
    private var myPeerID: Data! // 8-byte peer ID
    private var myNickname: String = "FlutterMac"
    private var noisePublicKey: Data! // placeholder
    private var signingPublicKey: Data! // placeholder
    private var signingKey: Curve25519.Signing.PrivateKey!

    // Deduplication
    private var seenMessageIDs: Set<String> = []
    private let maxSeenIDs = 500

    // Announce timer
    private var announceTimer: DispatchSourceTimer?

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

        // Generate placeholder keys (32 bytes each)
        var noiseBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &noiseBytes)
        noisePublicKey = Data(noiseBytes)

        signingKey = Curve25519.Signing.PrivateKey()
        signingPublicKey = signingKey.publicKey.rawRepresentation

        // The exact requirement from original app:
        // PeerID is derived from the first 16 hex chars of SHA256(noisePublicKey),
        // which exactly matches the first 8 bytes of the binary SHA256 hash.
        let digest = SHA256.hash(data: noisePublicKey)
        myPeerID = Data(digest).prefix(8)

        // Initialize both Central and Peripheral managers (matching original)
        centralManager = CBCentralManager(delegate: self, queue: bleQueue)
        peripheralManager = CBPeripheralManager(delegate: self, queue: bleQueue)
    }

    deinit {
        announceTimer?.cancel()
        centralManager?.stopScan()
        peripheralManager?.stopAdvertising()
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

        case "sendMessage":
            guard let args = call.arguments as? [String: Any],
                  let content = args["content"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "content required", details: nil))
                return
            }
            let nickname = args["nickname"] as? String ?? myNickname
            sendPublicMessage(content: content, nickname: nickname)
            result(nil)

        case "sendAnnounce":
            let args = call.arguments as? [String: Any]
            if let nick = args?["nickname"] as? String {
                myNickname = nick
            }
            broadcastAnnounce()
            result(nil)

        case "setNickname":
            if let args = call.arguments as? [String: Any],
               let nick = args["nickname"] as? String {
                myNickname = nick
            }
            result(nil)

        case "disconnectAll":
            disconnectAll()
            result(nil)

        case "getLocation":
            fetchNativeLocation(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Native Location
    private func fetchNativeLocation(result: @escaping FlutterResult) {
        if locationManager == nil {
            locationManager = CLLocationManager()
            locationManager?.delegate = self
            locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }
        
        // Save pending result
        if pendingLocationResult != nil {
            pendingLocationResult?(FlutterError(code: "CANCELED", message: "New location request started", details: nil))
        }
        pendingLocationResult = result
        
        // requestLocation will trigger didUpdateLocations or didFailWithError
        locationManager?.requestLocation()
        
        // Timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self, let pending = self.pendingLocationResult else { return }
            pending(FlutterError(code: "TIMEOUT", message: "Location request timed out", details: nil))
            self.pendingLocationResult = nil
        }
    }

    // MARK: - BLE Central Operations

    private func startScan(result: FlutterResult) {
        guard centralManager.state == .poweredOn else {
            result(FlutterError(code: "BT_OFF", message: "Bluetooth is not powered on", details: nil))
            return
        }
        centralManager.scanForPeripherals(
            withServices: [BLEPlugin.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        startAnnounceTimer()
        result(nil)
    }

    private func connectToDevice(deviceId: String, result: FlutterResult) {
        guard let peripheral = discoveredPeripherals[deviceId] else {
            result(FlutterError(code: "NOT_FOUND", message: "Device not discovered: \(deviceId)", details: nil))
            return
        }
        guard !connectingSet.contains(deviceId),
              connectedPeripherals[deviceId] == nil else {
            result(nil)
            return
        }

        connectingSet.insert(deviceId)

        let options: [String: Any] = [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey: true
        ]
        centralManager.connect(peripheral, options: options)

        // Timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self,
                  self.connectingSet.contains(deviceId),
                  self.connectedPeripherals[deviceId] == nil else { return }
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
        peripheralCharacteristics.removeValue(forKey: deviceId)
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
        peripheralCharacteristics.removeAll()
        announceTimer?.cancel()
        announceTimer = nil
        peripheralManager?.stopAdvertising()
    }

    private func writeData(deviceId: String, data: Data, result: FlutterResult) {
        guard let characteristic = peripheralCharacteristics[deviceId] else {
            result(FlutterError(code: "NOT_CONNECTED", message: "No characteristic for \(deviceId)", details: nil))
            return
        }
        guard let peripheral = connectedPeripherals[deviceId] else {
            result(FlutterError(code: "NOT_CONNECTED", message: "Not connected to \(deviceId)", details: nil))
            return
        }

        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write)
            ? .withResponse
            : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: writeType)
        result(nil)
    }

    // MARK: - Mesh Protocol (Sending)

    /// Send a public message as a BitchatPacket (type 0x02) to all connected peers
    private func sendPublicMessage(content: String, nickname: String) {
        guard let payloadData = content.data(using: .utf8) else { return }

        let packet = BitchatPacket(
            version: 1,
            type: MessageType.message.rawValue,
            senderID: myPeerID,
            recipientID: nil,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            payload: payloadData,
            signature: nil,
            ttl: defaultTTL
        )

        guard let data = BinaryProtocol.encode(packet) else { return }
        broadcastData(data)

        // Also send to Flutter as a local echo
        let peerIdHex = myPeerID.map { String(format: "%02x", $0) }.joined()
        sendMessageToFlutter(
            senderPeerID: peerIdHex,
            nickname: nickname,
            content: content,
            timestamp: Date(),
            isOwnMessage: true
        )
    }

    /// Broadcast an announcement packet to all connected peers
    private func broadcastAnnounce() {
        let announce = AnnouncementPacket(
            nickname: myNickname,
            noisePublicKey: noisePublicKey,
            signingPublicKey: signingPublicKey
        )
        guard let announcePayload = announce.encode() else { return }

        var packet = BitchatPacket(
            version: 1,
            type: MessageType.announce.rawValue,
            senderID: myPeerID,
            recipientID: nil,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            payload: announcePayload,
            signature: nil,
            ttl: defaultTTL
        )

        if let signingData = packet.toBinaryDataForSigning() {
            do {
                packet.signature = try signingKey.signature(for: signingData)
            } catch {
                NSLog("[BLEPlugin] Failed to sign announce packet: \(error)")
            }
        }

        guard let data = BinaryProtocol.encode(packet) else { return }
        broadcastData(data)
    }

    /// Send data to ALL connected peers (both peripherals we connected to, and centrals subscribed to us)
    private func broadcastData(_ data: Data) {
        // 1) Write to peripherals we're connected to as Central
        for (_, state) in connectedPeripherals {
            let deviceId = state.identifier.uuidString
            if let characteristic = peripheralCharacteristics[deviceId] {
                let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write)
                    ? .withResponse
                    : .withoutResponse
                state.writeValue(data, for: characteristic, type: writeType)
            }
        }

        // 2) Notify centrals subscribed to us as Peripheral
        if !subscribedCentrals.isEmpty, let ch = localCharacteristic {
            peripheralManager?.updateValue(data, for: ch, onSubscribedCentrals: nil)
        }
    }

    /// Periodic announce timer (matching original 10-second interval)
    private func startAnnounceTimer() {
        announceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: bleQueue)
        timer.schedule(deadline: .now() + 2, repeating: 10, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            self?.broadcastAnnounce()
        }
        timer.resume()
        announceTimer = timer
    }

    // MARK: - Mesh Protocol (Receiving)

    /// Handle a received BinaryProtocol packet
    private func handleReceivedPacket(_ data: Data, fromPeerUUID: String) {
        guard let packet = BinaryProtocol.decode(data) else {
            // Try without padding removal (raw data might work directly)
            NSLog("[BLEPlugin] Failed to decode packet (\(data.count) bytes) from \(fromPeerUUID.prefix(8))")
            return
        }

        let senderHex = packet.senderID.map { String(format: "%02x", $0) }.joined()

        // Deduplication
        let msgID = "\(senderHex)-\(packet.timestamp)"
        if seenMessageIDs.contains(msgID) { return }
        seenMessageIDs.insert(msgID)
        if seenMessageIDs.count > maxSeenIDs {
            seenMessageIDs.removeFirst()
        }

        switch packet.type {
        case MessageType.announce.rawValue:
            handleAnnounce(packet, from: senderHex, peerUUID: fromPeerUUID)

        case MessageType.message.rawValue:
            handleMessage(packet, from: senderHex)

        case MessageType.leave.rawValue:
            NSLog("[BLEPlugin] Peer \(senderHex.prefix(8))… left the mesh")
            sendConnectionEvent(deviceId: fromPeerUUID, state: "disconnected")

        default:
            NSLog("[BLEPlugin] Unknown packet type: \(packet.type) from \(senderHex.prefix(8))…")
        }
    }

    private func handleAnnounce(_ packet: BitchatPacket, from senderHex: String, peerUUID: String) {
        guard let announce = AnnouncementPacket.decode(from: packet.payload) else {
            NSLog("[BLEPlugin] Failed to decode announcement from \(senderHex.prefix(8))…")
            return
        }

        NSLog("[BLEPlugin] 👋 Peer announced: \(announce.nickname) (\(senderHex.prefix(8))…)")

        // Emit peer discovery to Flutter
        DispatchQueue.main.async { [weak self] in
            self?.methodChannel.invokeMethod("onPeerDiscovered", arguments: [
                "peerID": senderHex,
                "nickname": announce.nickname,
                "deviceId": peerUUID
            ])
        }
    }

    private func handleMessage(_ packet: BitchatPacket, from senderHex: String) {
        guard let content = String(data: packet.payload, encoding: .utf8) else {
            NSLog("[BLEPlugin] Failed to decode message content from \(senderHex.prefix(8))…")
            return
        }

        let timestamp = Date(timeIntervalSince1970: TimeInterval(packet.timestamp) / 1000.0)
        NSLog("[BLEPlugin] 💬 Message from \(senderHex.prefix(8))…: \(content.prefix(50))")

        sendMessageToFlutter(
            senderPeerID: senderHex,
            nickname: senderHex.prefix(8) + "…",
            content: content,
            timestamp: timestamp,
            isOwnMessage: false
        )
    }

    /// Forward a parsed message to Flutter via the data event channel
    private func sendMessageToFlutter(senderPeerID: String, nickname: String, content: String,
                                      timestamp: Date, isOwnMessage: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.dataEventSink?([
                "type": "message",
                "senderPeerID": senderPeerID,
                "nickname": nickname,
                "content": content,
                "timestamp": Int64(timestamp.timeIntervalSince1970 * 1000),
                "isOwnMessage": isOwnMessage
            ])
        }
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
        NSLog("[BLEPlugin] Central state: \(stateStr)")
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
        peripheralCharacteristics.removeValue(forKey: deviceId)
        sendConnectionEvent(deviceId: deviceId, state: "disconnected")
    }
}

// MARK: - CBPeripheralDelegate (Central role — interacting with remote peripherals)

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
        peripheralCharacteristics[deviceId] = characteristic

        // Subscribe to notifications
        if characteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: characteristic)
        }

        sendConnectionEvent(deviceId: deviceId, state: "ready")

        // Send our announce to the newly connected device
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.broadcastAnnounce()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil,
              let data = characteristic.value, !data.isEmpty else { return }

        let deviceId = peripheral.identifier.uuidString

        // Try to decode as BinaryProtocol packet
        handleReceivedPacket(data, fromPeerUUID: deviceId)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            let deviceId = peripheral.identifier.uuidString
            NSLog("[BLEPlugin] Write error for \(deviceId): \(error.localizedDescription)")
        }
    }
}

// MARK: - CBPeripheralManagerDelegate (Peripheral role — letting others discover and connect to us)

extension BLEPlugin: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        NSLog("[BLEPlugin] Peripheral state: \(peripheral.state.rawValue)")

        switch peripheral.state {
        case .poweredOn:
            // Clean slate
            peripheral.removeAllServices()

            // Create characteristic (matching original BLEService.swift line 2322-2327)
            localCharacteristic = CBMutableCharacteristic(
                type: BLEPlugin.characteristicUUID,
                properties: [.notify, .write, .writeWithoutResponse, .read],
                value: nil,
                permissions: [.readable, .writeable]
            )

            // Create service
            let service = CBMutableService(type: BLEPlugin.serviceUUID, primary: true)
            service.characteristics = [localCharacteristic!]

            NSLog("[BLEPlugin] Adding BLE service...")
            peripheral.add(service)

        case .poweredOff:
            peripheral.stopAdvertising()
            subscribedCentrals.removeAll()
            centralToPeerID.removeAll()
            localCharacteristic = nil

        default:
            break
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            NSLog("[BLEPlugin] ❌ Failed to add service: \(error.localizedDescription)")
            return
        }

        NSLog("[BLEPlugin] ✅ Service added, starting advertising")

        // Start advertising (matching original — only service UUID, no local name for privacy)
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BLEPlugin.serviceUUID]
        ])
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        let centralUUID = central.identifier.uuidString
        NSLog("[BLEPlugin] 📥 Central subscribed: \(centralUUID.prefix(8))…")
        subscribedCentrals.append(central)

        // Send our announcement to the new subscriber (matching original BLEService behavior)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.broadcastAnnounce()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        let centralUUID = central.identifier.uuidString
        NSLog("[BLEPlugin] 📤 Central unsubscribed: \(centralUUID.prefix(8))…")
        subscribedCentrals.removeAll { $0.identifier == central.identifier }
        centralToPeerID.removeValue(forKey: centralUUID)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        // Respond immediately (matching original BLEService line 2601)
        for request in requests {
            peripheral.respond(to: request, withResult: .success)
        }

        // Group by central and process (matching original BLEService line 2607-2697)
        let grouped = Dictionary(grouping: requests, by: { $0.central.identifier.uuidString })
        for (centralUUID, group) in grouped {
            let sorted = group.sorted { $0.offset < $1.offset }

            // Accumulate into per-central buffer for multi-write support
            var combined = pendingWriteBuffers[centralUUID] ?? Data()
            for r in sorted {
                guard let chunk = r.value, !chunk.isEmpty else { continue }
                let end = r.offset + chunk.count
                if combined.count < end {
                    combined.append(Data(repeating: 0, count: end - combined.count))
                }
                combined.replaceSubrange(r.offset..<end, with: chunk)
            }
            pendingWriteBuffers[centralUUID] = combined

            // Try to decode the accumulated buffer
            if let packet = BinaryProtocol.decode(combined) {
                pendingWriteBuffers.removeValue(forKey: centralUUID)

                let claimedSenderHex = packet.senderID.map { String(format: "%02x", $0) }.joined()

                // Track central → peer mapping from announce packets
                if packet.type == MessageType.announce.rawValue {
                    centralToPeerID[centralUUID] = claimedSenderHex
                    // Also ensure central is tracked
                    if !subscribedCentrals.contains(where: { $0.identifier.uuidString == centralUUID }) {
                        subscribedCentrals.append(sorted[0].central)
                    }
                }

                handleReceivedPacket(combined, fromPeerUUID: centralUUID)
            } else if combined.count > 4096 {
                // Safety: drop oversized buffers
                pendingWriteBuffers.removeValue(forKey: centralUUID)
                NSLog("[BLEPlugin] ⚠️ Dropped oversized write buffer (\(combined.count) bytes)")
            }
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // The transmit queue has space again — could flush pending notifications here
        NSLog("[BLEPlugin] Peripheral ready to update subscribers")
    }
}

// MARK: - CLLocationManagerDelegate

extension BLEPlugin: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, let pending = pendingLocationResult else { return }
        pending([
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude
        ])
        pendingLocationResult = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("[BLEPlugin] Location failed: \(error.localizedDescription)")
        guard let pending = pendingLocationResult else { return }
        
        // Don't fail the whole app on location error, just return nil to trigger IP fallback
        pending(FlutterError(code: "LOCATION_ERROR", message: error.localizedDescription, details: nil))
        pendingLocationResult = nil
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
