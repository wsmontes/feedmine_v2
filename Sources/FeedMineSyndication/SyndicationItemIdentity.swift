// Owns: canonical text for link-derived item identity (v1 lesson IN-3).
// Does not own: guid/id identity (opaque, never rewritten) or request URLs (fetching keeps the original).
//
// v1 hashed raw links, so `utm_*` churn, `http`/`https` flips, `www.` and trailing slashes minted
// "new" articles and duplicate cards. Source identity in v1 already used this normalization
// (`OPMLParser.normalizeURL`, 0 drift over 77,443 sources); items now get the same rigor.

import Foundation

enum SyndicationItemIdentity {
    /// Query parameters that never identify an article: campaign tracking, click ids, sessions, signatures.
    private static let ignoredParameters: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id", "utm_name",
        "fbclid", "gclid", "dclid", "yclid", "msclkid", "igshid", "mc_cid", "mc_eid", "_hsenc", "_hsmi", "mkt_tok",
        "ref", "ref_src", "source", "cmpid", "ncid", "sr_share", "share", "smid",
        "jsessionid", "phpsessid", "cfid", "cftoken", "temp_url_sig", "temp_url_expires", "expires",
        "token", "sig", "signature", "access_token"
    ]

    /// Normalized identity text for an article link, or the input unchanged when it is not an http(s) URL.
    static func linkIdentity(_ raw: String) -> String {
        guard var components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
            var host = components.host?.lowercased(), !host.isEmpty else { return raw }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        components.scheme = "https"
        components.host = host
        if components.port == 80 || components.port == 443 { components.port = nil }
        components.fragment = nil
        components.user = nil
        components.password = nil
        var path = components.percentEncodedPath
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        if path == "/" { path = "" }
        components.percentEncodedPath = path
        if let items = components.percentEncodedQueryItems {
            let kept = items.filter { item in
                let name = item.name.lowercased()
                return !ignoredParameters.contains(name) && !name.hasPrefix("utm_") && !name.hasPrefix("x-amz-")
            }
            components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        }
        return components.string ?? raw
    }
}
