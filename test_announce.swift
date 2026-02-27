import Foundation
import CryptoKit

// Test script to verify the flutter BLEPlugin encoding matches the original Bitchat packet formats
let noiseBytes = [UInt8](repeating: 0x41, count: 32)
let noiseData = Data(noiseBytes)
let digest = SHA256.hash(data: noiseData)
let myPeerID = Data(digest).prefix(8)

print("Generated noise key: \(noiseData.map { String(format: "%02x", $0) }.joined())")
print("Generated peer ID: \(myPeerID.map { String(format: "%02x", $0) }.joined())")
