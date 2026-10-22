import Foundation
import Testing
@testable import DeviceMonitor

@Suite("ICMP packets")
struct ICMPPacketTests {
    @Test func rfc1071ChecksumVector() {
        // Classic example: 0x0001 0xf203 0xf4f5 0xf6f7 → 0x220d
        let data = Data([0x00, 0x01, 0xf2, 0x03, 0xf4, 0xf5, 0xf6, 0xf7])
        #expect(ICMPPacket.checksum(data) == 0x220d)
    }

    @Test func oddLengthIsPadded() {
        #expect(ICMPPacket.checksum(Data([0x01])) == ~UInt16(0x0100))
    }

    @Test func echoRequestVerifiesToZero() {
        let packet = ICMPPacket.echoRequest(identifier: 0xABCD, sequence: 7, payload: Data(repeating: 0x42, count: 32))
        #expect(packet.count == 40)
        #expect(packet[0] == 8)
        #expect(packet[1] == 0)
        #expect(packet[4] == 0xAB && packet[5] == 0xCD)
        #expect(packet[6] == 0 && packet[7] == 7)
        // A packet with a valid checksum sums to zero.
        #expect(ICMPPacket.checksum(packet) == 0)
    }

    @Test func parsesReplyWithIPv4Header() {
        var datagram = Data(repeating: 0, count: 20)
        datagram[0] = 0x45
        datagram.append(contentsOf: [0, 0, 0, 0, 0x12, 0x34, 0x00, 0x09, 1, 2, 3])
        #expect(ICMPPacket.isEchoReply(datagram, identifier: 0x1234, sequence: 9))
        #expect(ICMPPacket.isEchoReply(datagram, identifier: 0x1234, sequence: 8) == false)
        #expect(ICMPPacket.isEchoReply(datagram, identifier: 0x1235, sequence: 9) == false)
    }

    @Test func parsesReplyWithoutHeaderAndRejectsRequests() {
        let reply = Data([0, 0, 0, 0, 0x00, 0x05, 0x00, 0x01])
        #expect(ICMPPacket.isEchoReply(reply, identifier: 5, sequence: 1))
        let request = Data([8, 0, 0, 0, 0x00, 0x05, 0x00, 0x01])
        #expect(ICMPPacket.isEchoReply(request, identifier: 5, sequence: 1) == false)
        #expect(ICMPPacket.isEchoReply(Data([0, 0, 0]), identifier: 5, sequence: 1) == false)
    }
}

@Suite("Wake-on-LAN")
struct WakeOnLANTests {
    @Test("MAC formats parse", arguments: ["A4:83:E7:12:34:56", "a4-83-e7-12-34-56", "a483.e712.3456", "a483e7123456"])
    func parsesFormats(_ text: String) throws {
        let mac = try #require(MACAddress(text))
        #expect(mac.description == "A4:83:E7:12:34:56")
        #expect(mac.ouiPrefix == "A4:83:E7")
        #expect(mac.isLocallyAdministered == false)
    }

    @Test func rejectsBadMACs() {
        #expect(MACAddress("A4:83:E7:12:34") == nil)
        #expect(MACAddress("ZZ:83:E7:12:34:56") == nil)
        #expect(MACAddress("") == nil)
        #expect(MACAddress(bytes: [1, 2, 3]) == nil)
    }

    @Test func locallyAdministeredBit() throws {
        let first = try #require(MACAddress("02:00:00:00:00:00"))
        let second = try #require(MACAddress("DA:1B:2C:3D:4E:5F"))
        #expect(first.isLocallyAdministered)
        #expect(second.isLocallyAdministered)
    }

    @Test func magicPacketLayout() throws {
        let mac = try #require(MACAddress("00:11:22:33:44:55"))
        let packet = WakeOnLAN.magicPacket(for: mac)
        #expect(packet.count == 102)
        #expect(packet.prefix(6) == Data(repeating: 0xFF, count: 6))
        for repetition in 0..<16 {
            let start = 6 + repetition * 6
            #expect(Array(packet[start..<start + 6]) == mac.bytes)
        }
    }
}

@Suite("Device identity")
struct DeviceIdentityTests {
    @Test func priorityOrder() {
        #expect(DeviceIdentity.key(macAddress: "A4:83:E7:12:34:56", hostname: "printer.local", bonjourName: "Printer", host: "10.0.0.5") == "mac:A4:83:E7:12:34:56")
        #expect(DeviceIdentity.key(macAddress: "02:00:00:00:00:01", hostname: "Printer.Local.", bonjourName: nil, host: "10.0.0.5") == "host:printer")
        #expect(DeviceIdentity.key(macAddress: nil, hostname: nil, bonjourName: " Living Room ", host: "10.0.0.5") == "bonjour:living room")
        #expect(DeviceIdentity.key(macAddress: nil, hostname: "", bonjourName: "", host: "10.0.0.5") == "ip:10.0.0.5")
        // RAOP-style names carry the MAC before "@"; the rest matches the device's other services.
        #expect(DeviceIdentity.key(macAddress: nil, hostname: nil, bonjourName: "C869CD123456@Living Room", host: "10.0.0.5") == "mac:C8:69:CD:12:34:56")
        #expect(DeviceIdentity.key(macAddress: nil, hostname: nil, bonjourName: "02AABBCCDDEE@Kitchen", host: "10.0.0.5") == "bonjour:kitchen")
        #expect(DeviceIdentity.key(macAddress: nil, hostname: nil, bonjourName: "Sonos-ABC123@Kitchen", host: "10.0.0.5") == "bonjour:sonos-abc123@kitchen")
    }

    @Test func stableUUIDs() {
        let a = DeviceIdentity.uuid(forKey: "host:printer")
        let b = DeviceIdentity.uuid(forKey: "host:printer")
        let c = DeviceIdentity.uuid(forKey: "host:printer2")
        #expect(a == b)
        #expect(a != c)
        let bytes = a.uuid
        #expect(bytes.6 >> 4 == 5)
        #expect(bytes.8 & 0xC0 == 0x80)
    }

    @Test func jitterFractionInRange() {
        for _ in 0..<20 {
            let fraction = DeviceIdentity.jitterFraction(for: UUID())
            #expect(fraction >= 0 && fraction < 1)
        }
    }
}
