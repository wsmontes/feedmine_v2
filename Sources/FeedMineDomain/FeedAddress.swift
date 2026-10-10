//
// File: FeedAddress.swift
// Module: FeedMineDomain
//
// Responsibility:
// A feed's two addresses, exactly as V1's `OPMLParser` and the catalog builder (`scripts/catalog_identity.py`)
// define them: the **identity** (what makes two entries the same feed, and therefore what an imported file has
// to land on to match the shipped catalog) and the **request** address (what is fetched, which keeps the signed
// parameters the identity drops).
//
// The rules are copied, not reinvented, because identity is what dedups an import and what the catalog's keys
// already are:
//   - XML entities are repaired (the five named ones and numeric entities, case-insensitively, a few passes);
//   - the host is validated before the port, lowercased, `www.` stripped for identity, IPv6 brackets kept;
//   - identity is always `https`, drops default ports, removes **every** trailing slash and **filters the
//     query**: tracking and session parameters (utm_*, fbclid, token, signature, `x-amz-*`, …) are not identity;
//   - the request address keeps the original scheme, `www.`, ports, trailing slashes and the whole query;
//   - neither keeps a fragment.
import Foundation

public enum FeedAddress {
    /// The identity key. Two entries with the same one are the same feed.
    public static func identity(_ raw: String) -> String {
        transform(raw, forIdentity: true)
    }

    /// The address to fetch. Signed and authorized parameters survive.
    public static func request(_ raw: String) -> String {
        transform(raw, forIdentity: false)
    }

    /// Parameters that name a *visit*, not a feed. V1's own list, plus anything `x-amz-*` signs.
    static let identityQueryParameters: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "ref", "source",
        "fbclid", "gclid", "mc_cid", "mc_eid", "ref_src", "temp_url_sig", "temp_url_expires", "expires",
        "cfid", "cftoken", "jsessionid", "phpsessid",
        "token", "sig", "key", "auth", "apikey", "api_key", "signature", "access_token", "refresh_token",
    ]

    private static func transform(_ raw: String, forIdentity identity: Bool) -> String {
        let decoded = decodingEntities(raw)
        // The host is validated first: a URL with a bad port *and* a percent-decoded host delimiter must still
        // be refused, so the host check cannot be gated on the port one.
        if let components = URLComponents(string: decoded), let host = components.host {
            guard validHost(host) else { return decoded }
        }
        guard let components = URLComponents(string: decoded),
            let originalScheme = components.scheme?.lowercased(),
            originalScheme == "http" || originalScheme == "https",
            let host = components.host, !host.isEmpty else { return decoded }
        if let port = components.port, !(1...65_535).contains(port) { return decoded }
        let isIPv6 = components.percentEncodedHost?.hasPrefix("[") ?? false
        guard let authority = encodedHost(host, stripWWW: identity, isIPv6: isIPv6) else { return decoded }

        var text = identity ? "https" : originalScheme
        text += "://"
        if let user = components.percentEncodedUser {
            text += normalized(user, safe: userInfoSafe)
            if let password = components.percentEncodedPassword { text += ":" + normalized(password, safe: userInfoSafe) }
            text += "@"
        }
        text += authority
        if let port = components.port,
            !(identity && ((originalScheme == "https" && port == 443) || (originalScheme == "http" && port == 80))) {
            text += ":\(port)"
        }
        var path = normalized(components.percentEncodedPath, safe: pathSafe)
        if identity { while path.hasSuffix("/") { path.removeLast() } }
        text += path
        let query: String?
        if identity {
            query = filteredIdentityQuery(components.percentEncodedQuery)
        } else if let raw = components.percentEncodedQuery {
            query = normalized(raw, safe: querySafe)
        } else {
            query = nil
        }
        if let query { text += "?" + query }
        return text
    }

    /// V1 and the catalog builder both drop the parameters that name a visit rather than a feed.
    static func filteredIdentityQuery(_ rawQuery: String?) -> String? {
        guard let rawQuery else { return nil }
        let retained = rawQuery.split(separator: "&", omittingEmptySubsequences: true).compactMap { segment -> String? in
            let rawName = String(segment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                .first ?? "")
            let name = (rawName.removingPercentEncoding ?? rawName)
                .replacingOccurrences(of: "+", with: " ").lowercased()
            guard !identityQueryParameters.contains(name), !name.hasPrefix("x-amz-") else { return nil }
            return normalized(String(segment), safe: querySafe)
        }
        return retained.isEmpty ? nil : retained.joined(separator: "&")
    }

    /// Existing `%XX` sequences are upper-cased; anything outside the safe set is percent-encoded per UTF-8
    /// byte. This is what makes `ção` and `%C3%A7%C3%A3o` one identity.
    static func normalized(_ value: String, safe: CharacterSet) -> String {
        let scalars = Array(value.unicodeScalars)
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        var result = ""
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "%", index + 2 < scalars.count, hexadecimal.contains(scalars[index + 1]),
                hexadecimal.contains(scalars[index + 2]) {
                result += "%" + String(scalars[index + 1]).uppercased() + String(scalars[index + 2]).uppercased()
                index += 3
                continue
            }
            if scalar.isASCII, safe.contains(scalar) {
                result.append(Character(String(scalar)))
            } else {
                for byte in String(scalar).utf8 { result += String(format: "%%%02X", byte) }
            }
            index += 1
        }
        return result
    }

    /// OPML is XML, so only the five named entities and numeric ones are portable. Recognising anything broader
    /// would decode an address differently from the tool that built the catalog.
    static func decodingEntities(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for _ in 0..<3 {
            var decoded = value
                .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
                .replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
                .replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
                .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
                .replacingOccurrences(of: "&apos;", with: "'", options: .caseInsensitive)
            let pattern = "&#[0-9]+;|&#[xX][0-9A-Fa-f]+;"
            while let range = decoded.range(of: pattern, options: .regularExpression) {
                let payload = decoded[range].dropFirst(2).dropLast()
                let radix = payload.first == "x" || payload.first == "X" ? 16 : 10
                let digits = radix == 16 ? payload.dropFirst() : payload
                guard let scalarValue = UInt32(digits, radix: radix), scalarValue <= 0x10FFFF,
                    !(0xD800...0xDFFF).contains(scalarValue), let scalar = UnicodeScalar(scalarValue) else {
                    // An invalid entity is removed so the scan advances; leaving it would match itself forever.
                    decoded.replaceSubrange(range, with: "")
                    continue
                }
                decoded.replaceSubrange(range, with: String(scalar))
            }
            guard decoded != value else { break }
            value = decoded
        }
        return value
    }

    private static func validHost(_ host: String) -> Bool {
        !host.isEmpty && !host.contains("%") && !host.contains("/") && !host.contains("@")
    }

    private static func encodedHost(_ host: String, stripWWW: Bool, isIPv6: Bool) -> String? {
        guard validHost(host) else { return nil }
        var value = host.lowercased()
        if stripWWW, !isIPv6, value.hasPrefix("www."), value.count > 4 { value = String(value.dropFirst(4)) }
        return value
    }

    private static var pathSafe: CharacterSet {
        CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
            + "-._~!$&'()*+,;=/:@")
    }

    private static var querySafe: CharacterSet { pathSafe.union(CharacterSet(charactersIn: "?")) }

    private static var userInfoSafe: CharacterSet {
        CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
            + "-._~!$&'()*+,;=:")
    }
}
