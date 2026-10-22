import Foundation
import Testing
@testable import DeviceMonitor

@Suite("IPv4 parsing and subnet math")
struct IPAddressingTests {
    @Test("Canonical dotted quads parse and round-trip", arguments: ["192.168.1.10", "10.0.0.1", "0.0.0.0", "255.255.255.255", "172.16.0.5"])
    func parsesValidAddresses(_ text: String) throws {
        let address = try #require(IPv4Host(text))
        #expect(address.description == text)
    }

    @Test("Malformed addresses are rejected", arguments: ["192.168..1", "1.2.3.4.", ".1.2.3.4", "1...2...3...4", "01.2.3.4", "256.1.1.1", "1.2.3.4.5", "", " 1.2.3.4", "1.2.3", "a.b.c.d", "+1.2.3.4", "-1.2.3.4", "1.2.3.04"])
    func rejectsMalformedAddresses(_ text: String) {
        #expect(IPv4Host(text) == nil)
    }

    @Test func classifiesRanges() throws {
        let tenNet = try #require(IPv4Host("10.1.2.3"))
        let privateB = try #require(IPv4Host("172.31.0.1"))
        let publicB = try #require(IPv4Host("172.32.0.1"))
        let privateC = try #require(IPv4Host("192.168.0.1"))
        let linkLocal = try #require(IPv4Host("169.254.3.4"))
        let loopback = try #require(IPv4Host("127.0.0.1"))
        let multicast = try #require(IPv4Host("224.0.0.251"))
        #expect(tenNet.isPrivate)
        #expect(privateB.isPrivate)
        #expect(publicB.isPrivate == false)
        #expect(privateC.isPrivate)
        #expect(linkLocal.isLinkLocal)
        #expect(loopback.isLoopback)
        #expect(multicast.isMulticast)
    }

    @Test func subnetFromNetmask() throws {
        let address = try #require(IPv4Host("192.168.1.42"))
        let mask = try #require(IPv4Host("255.255.255.0"))
        let subnet = try #require(IPv4Subnet(address: address, netmask: mask))
        #expect(subnet.description == "192.168.1.0/24")
        #expect(subnet.prefixLength == 24)
        #expect(subnet.broadcast.description == "192.168.1.255")
        #expect(subnet.hostCount == 254)
        #expect(subnet.hosts().first?.description == "192.168.1.1")
        #expect(subnet.hosts().last?.description == "192.168.1.254")
        #expect(subnet.contains(address))
        let outside = try #require(IPv4Host("192.168.2.1"))
        #expect(subnet.contains(outside) == false)
        #expect(subnet.isScannable)
    }

    @Test func nonContiguousNetmaskIsRejected() throws {
        let address = try #require(IPv4Host("10.0.0.1"))
        let badMask = try #require(IPv4Host("255.0.255.0"))
        #expect(IPv4Subnet(address: address, netmask: badMask) == nil)
    }

    @Test func cidrParsingAndLimits() throws {
        let large = try #require(IPv4Subnet(cidr: "10.0.0.0/16"))
        #expect(large.hostCount == 65_534)
        #expect(large.isScannable == false)
        let edge = try #require(IPv4Subnet(cidr: "10.0.0.0/22"))
        #expect(edge.hostCount == 1_022)
        #expect(edge.isScannable)
        let tiny = try #require(IPv4Subnet(cidr: "10.0.0.0/31"))
        #expect(tiny.hostCount == 0)
        #expect(tiny.hosts().isEmpty)
        #expect(IPv4Subnet(cidr: "10.0.0.0/33") == nil)
        #expect(IPv4Subnet(cidr: "10.0.0.0") == nil)
        #expect(IPv4Subnet(cidr: "bad/24") == nil)
    }

    @Test func hostInputValidation() {
        if case .success(let input) = HostInputValidator.validate(" 192.168.1.10 ") {
            #expect(input.kind == .ipv4)
            #expect(input.normalized == "192.168.1.10")
        } else {
            Issue.record("IPv4 input should validate")
        }
        if case .success(let input) = HostInputValidator.validate("[FE80::1%en0]") {
            #expect(input.kind == .ipv6)
        } else {
            Issue.record("IPv6 input should validate")
        }
        if case .success(let input) = HostInputValidator.validate("Printer.Local") {
            #expect(input.kind == .hostname)
            #expect(input.normalized == "printer.local")
        } else {
            Issue.record("hostname should validate")
        }
        #expect(HostInputValidator.isValidHostname("-bad.local") == false)
        #expect(HostInputValidator.isValidHostname("ok-name") == true)
        #expect(HostInputValidator.isValidHostname("192.168.1") == false)
        #expect(HostInputValidator.isValidIPv6("not:an:ip:::") == false)
        #expect(HostInputValidator.validatePort("8080") == 8080)
        #expect(HostInputValidator.validatePort("0") == nil)
        #expect(HostInputValidator.validatePort("70000") == nil)
        if case .failure(let error) = HostInputValidator.validate("") {
            #expect(error == .invalidInput(field: "address", reason: "Enter an IP address or hostname."))
        } else {
            Issue.record("empty input must fail")
        }
    }
}
