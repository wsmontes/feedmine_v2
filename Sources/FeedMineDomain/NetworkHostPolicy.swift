// Owns: the pure rule for which remote hosts feed-supplied locators may reach (review R15).
// Feed content is untrusted: an item can point its image at loopback, the local network or a
// cloud metadata address. Such locators are refused at admission and again on every redirect.
// Limit: this inspects host text; a public name that DNS-resolves to a private address is not
// detected here (that needs connect-time checks the platform transport does not expose).

import Foundation

public enum NetworkHostPolicy {
    /// True when `host` (name or IP literal, IPv6 with or without brackets) may be contacted.
    public static func isPubliclyRoutable(_ host: String) -> Bool {
        var name = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.hasPrefix("["), name.hasSuffix("]") { name = String(name.dropFirst().dropLast()) }
        while name.hasSuffix(".") { name.removeLast() }
        guard !name.isEmpty else { return false }
        if name.contains(":") { return isPublicIPv6(name) }
        if let octets = dottedQuad(name) { return isPublicIPv4(octets) }
        // Shorthand numeric forms (2130706433, 0x7f.1, 127.1, 0177.0.0.1) are IPs to some resolvers.
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        let numeric: (Substring) -> Bool = { label in
            !label.isEmpty && (label.allSatisfy(\.isNumber)
                || (label.hasPrefix("0x") && label.dropFirst(2).allSatisfy(\.isHexDigit)))
        }
        if labels.allSatisfy(numeric) { return false }
        if name == "localhost" || !name.contains(".") { return false }
        for suffix in [".localhost", ".local", ".internal", ".home.arpa", ".lan", ".intranet"] where name.hasSuffix(suffix) {
            return false
        }
        return true
    }

    private static func dottedQuad(_ name: String) -> [UInt8]? {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets: [UInt8] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber), let value = UInt8(part) else { return nil }
            octets.append(value)
        }
        return octets
    }

    private static func isPublicIPv4(_ o: [UInt8]) -> Bool {
        switch (o[0], o[1]) {
        case (0, _), (10, _), (127, _): return false
        case (100, 64...127): return false          // carrier-grade NAT
        case (169, 254): return false               // link-local, cloud metadata
        case (172, 16...31): return false
        case (192, 168): return false
        case (192, 0) where o[2] == 0: return false // IETF protocol assignments
        case (198, 18...19): return false           // benchmarking
        case (224...255, _): return false           // multicast, reserved, broadcast
        default: return true
        }
    }

    private static func isPublicIPv6(_ name: String) -> Bool {
        let address = name.split(separator: "%").first.map(String.init) ?? name   // drop zone id
        if address == "::" || address == "::1" { return false }
        if address.hasPrefix("::ffff:") {                                          // IPv4-mapped
            let tail = String(address.dropFirst("::ffff:".count))
            guard let octets = dottedQuad(tail) else { return false }
            return isPublicIPv4(octets)
        }
        guard let first = address.split(separator: ":", omittingEmptySubsequences: false).first,
            let head = UInt16(first.isEmpty ? "0" : String(first), radix: 16) else { return false }
        if head & 0xFE00 == 0xFC00 { return false }   // fc00::/7 unique local
        if head & 0xFFC0 == 0xFE80 { return false }   // fe80::/10 link-local
        if head & 0xFF00 == 0xFF00 { return false }   // ff00::/8 multicast
        if head == 0 { return false }                 // ::/16 incl. IPv4-compatible forms
        return true
    }
}
