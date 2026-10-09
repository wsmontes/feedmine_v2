import XCTest
@testable import FeedMineDomain

/// Review R15: feed-supplied locators may not reach loopback, LAN, link-local or metadata hosts.
final class NetworkHostPolicyTests: XCTestCase {
    func testRefusesNonPublicHosts() {
        for host in ["localhost", "LOCALHOST.", "printer.local", "api.internal", "router.home.arpa", "intranet",
            "127.0.0.1", "127.1", "2130706433", "0x7f000001", "0177.0.0.1", "0.0.0.0", "10.1.2.3", "172.16.0.1",
            "172.31.255.255", "192.168.1.10", "169.254.169.254", "100.64.0.1", "224.0.0.1", "255.255.255.255",
            "::1", "[::1]", "::", "fe80::1", "fd00::1", "fc12::1", "ff02::1", "::ffff:127.0.0.1", "::ffff:10.0.0.1", ""] {
            XCTAssertFalse(NetworkHostPolicy.isPubliclyRoutable(host), host)
        }
    }

    func testAllowsPublicNamesAndAddresses() {
        for host in ["ichef.bbci.co.uk", "media.guim.co.uk", "cdn.example.com", "beef.cafe", "abc1.de", "8.8.8.8",
            "172.32.0.1", "192.169.0.1", "100.128.0.1", "2001:4860:4860::8888", "[2606:4700::1111]", "::ffff:8.8.8.8"] {
            XCTAssertTrue(NetworkHostPolicy.isPubliclyRoutable(host), host)
        }
    }
}