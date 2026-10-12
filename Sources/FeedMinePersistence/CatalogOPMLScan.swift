//
// File: CatalogOPMLScan.swift
// Module: FeedMinePersistence
//
// Responsibility:
// The catalogue builder's *input* rules, in Swift: walking an OPML tree and turning it into the occurrences
// `catalog.sqlite` is compiled from.
//
// The reference is V1's `scripts/build_catalog.py` — `slug`, `display_name`, `semantic_path_name`,
// `media_kind_for_file`, `media_kind_for_url`, `declared_media_kind`, `folder_nodes`, `extract_language` and
// `scan_opml` (that is the builder the shipped snapshot was compiled by). This file reproduces its
// *behaviour*: the same folder→node_path derivation, the same media-kind precedence, the same language
// inheritance, the same sort_order and the same two counters. It deliberately does NOT follow V1's Swift
// `feedmine/FeedEngine/OPMLCatalogScanner.swift`, which diverges from the builder in seven measured places —
// see the notes on `folderNodes`, `slug`/`displayName`, `mediaKind`, `declaredLanguage`, URL validity, file
// discovery and parse failures. Porting that scanner would have produced catalogues the builder would not.
//
// Does not own: identity (`FeedAddress.identity`, the same cross-language contract the builder's
// `canonical_url` implements), the schema, the database, or the decision to publish.
//
// Measured divergences from the reference, both found by compiling the 118-file editorial tree and diffing it
// against the catalogue the Python builder produces from the same tree (77,443 sources, 6,450 nodes): the
// taxonomy is identical and every source's derivations match, except
//
//   * 12 sources whose identity key differs, because `FeedAddress` is not byte-identical to `canonical_url` for
//     an address with an explicit default port (`https://www.aljazeera.net:443/...`: the builder keeps `:443`,
//     the app's identity transform drops it — a deliberate V1-Swift rule) or with a punycode host
//     (`https://xn--d1acibrhefqcr.bg/feed`: Foundation decodes the punycode, the builder keeps it). This file
//     follows the app's identity contract; the divergence is in that contract, not here.
//   * 4 titles whose reference value begins with U+FEFF. Foundation's XMLParser drops that scalar inside an
//     attribute value — a raw BOM and its `&#xFEFF;` character reference alike — where expat (ElementTree) keeps
//     it. There is no way to recover it through XMLParser; the entries are the same source either way.
//
// Allowed dependencies: Foundation (XMLParser, URLComponents) and CryptoKit (the builder's SHA-256 id rule),
// FeedMineDomain (`FeedAddress`).
//
// Status:
// Production: the compiler's input half; `CatalogCompiler` is the only caller.
//

import CryptoKit
import FeedMineDomain
import Foundation

/// One node of the taxonomy an occurrence is placed under, as the builder's `InputNode` carries it.
struct CatalogInputNode: Hashable, Sendable {
    let key: String
    let name: String
    let kind: Int
    let language: String?
}

/// One feed outline the tree declared, as the builder's `Occurrence` carries it.
struct CatalogOccurrence: Hashable, Sendable {
    let title: String
    let declaredURL: String
    let requestURL: String
    let mediaKind: String
    let language: String?
    let nodePath: [CatalogInputNode]
    let opmlFile: String
    let sortOrder: Int
    let titleOverride: String?
    let languageOverride: String?
    let mediaKindOverride: String?
    let siteURL: String?
    let description: String?
    let tags: String?
    let nature: String?
    let activity: String?
    let latestItemAt: String?
    let qualityScore: Int?
    let defaultEnabled: Bool
    let feedType: String?
}

/// What one scan of the tree found: the occurrences, plus the three counters the catalogue's own
/// `catalog_metadata` declares about the inputs.
struct CatalogScanResult: Hashable, Sendable {
    let occurrences: [CatalogOccurrence]
    let fileCount: Int
    let failedFileCount: Int
    let invalidSourceCount: Int
}

/// The node kinds `catalog_node.kind` carries. The builder's names — V1's Swift scanner reused the same
/// integers under different names (`section`, `topic`, …), so the numbers, not the names, are the contract.
enum CatalogNodeKind {
    static let topic = 0
    static let country = 1
    static let region = 2
    static let subcategory = 3
    static let language = 4
}

/// The builder's scan rules. Pure except for reading the tree: no database, no identity allocation.
enum CatalogOPMLScan {
    /// Every source a validated OPML tree declares, in the builder's own order.
    static func scanTree(at feedsRoot: URL) throws -> CatalogScanResult {
        let files = try opmlFiles(under: feedsRoot)
        var occurrences: [CatalogOccurrence] = []
        var failedFiles = 0
        var invalidSources = 0

        for (fileIndex, fileURL) in files.enumerated() {
            let relativePath = relativePath(of: fileURL, under: feedsRoot)
            let fileName = fileURL.deletingPathExtension().lastPathComponent
            let data: Data
            do { data = try Data(contentsOf: fileURL, options: [.mappedIfSafe]) } catch {
                // The builder counts a file it cannot read as a failed file and keeps going: one unreadable
                // input must not lose the other 117.
                failedFiles += 1
                continue
            }
            // The builder reads `head/language` before it walks the body, so an outline's inherited language
            // cannot depend on where the head sits. The first pass reads exactly that and stops at the body.
            let head = CatalogHeadScan.read(data)
            // A default-namespaced OPML has no `body` ElementTree can find (`root.find("body")` is None), so the
            // builder contributes nothing from such a file — it is not a failed file, it is an empty one. This
            // is the builder's own behaviour, reproduced rather than corrected: a catalogue that silently
            // gained sources the reference build would not have would fail the release gate's count check.
            guard !head.namespacedRoot else { continue }
            let scanner = CatalogOutlineScanner(
                folderNodes: folderNodes(relativePath: relativePath, fileName: fileName),
                fallbackCategory: displayName(fileName),
                opmlFile: relativePath,
                fileIndex: fileIndex,
                fileLanguage: head.language,
                defaultMediaKind: mediaKind(forFileName: fileName))
            let parser = XMLParser(data: data)
            parser.delegate = scanner
            guard parser.parse() else {
                // A file that does not parse is dropped whole, exactly as the builder drops it: its partial
                // rows never reach the catalogue, and `failed_file_count` says so.
                failedFiles += 1
                continue
            }
            occurrences.append(contentsOf: scanner.occurrences)
            invalidSources += scanner.invalidSourceCount
        }
        return CatalogScanResult(occurrences: occurrences, fileCount: files.count, failedFileCount: failedFiles,
            invalidSourceCount: invalidSources)
    }

    /// The builder's `stable_uint32`: SHA-256 of the key's UTF-8 bytes, first four bytes big-endian, with zero
    /// reserved. This is what makes a source or node id stable across rebuilds — the ids in the shipped
    /// snapshot are these values, which is why a rebuilt catalogue keeps every source's id.
    static func stableUInt32(_ raw: String) -> UInt32 {
        var value: UInt32 = 0
        for byte in SHA256.hash(data: Data(raw.utf8)).prefix(4) { value = (value << 8) | UInt32(byte) }
        return value == 0 ? 1 : value
    }

    /// The builder's `slug`. NFKD-folded to ASCII, lowercased, every run of non-alphanumerics collapsed to one
    /// `-`, ends trimmed, `untitled` when nothing is left.
    static func slug(_ raw: String) -> String {
        var folded = ""
        for scalar in raw.decomposedStringWithCompatibilityMapping.unicodeScalars where scalar.isASCII {
            folded.unicodeScalars.append(scalar)
        }
        var result = ""
        var separator = false
        for scalar in folded.lowercased().unicodeScalars {
            let alphanumeric = scalar.isASCII && (("a"..."z").contains(Character(scalar))
                || ("0"..."9").contains(Character(scalar)))
            if alphanumeric {
                if separator, !result.isEmpty { result.append("-") }
                separator = false
                result.unicodeScalars.append(scalar)
            } else {
                separator = true
            }
        }
        return result.isEmpty ? "untitled" : result
    }

    /// The builder's `display_name`: the leading `NN_`/`NN-`/`NN ` index dropped, `_`/`-` read as spaces, then
    /// title-cased.
    static func displayName(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"^\d+[ _-]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    /// The builder's `semantic_path_name`: a directory name without its numeric prefix, lowercased. It decides
    /// only whether a folder names countries/staging; the *key* keeps the raw directory name.
    static func semanticPathName(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"^[\d_]+[ _-]+"#, with: "", options: .regularExpression).lowercased()
    }

    /// The builder's `media_kind_for_file`: the file-name guess that seeds a whole file.
    static func mediaKind(forFileName fileName: String) -> String {
        let lower = fileName.lowercased()
        if lower.contains("podcast") { return "audio" }
        if lower.contains("youtube") { return "video" }
        if lower.contains("reddit") || lower.contains("forum") { return "forum" }
        return "text"
    }

    /// The builder's `media_kind_for_url`: the URL guess applied to a feed's own address.
    static func mediaKind(forURL xmlURL: String, default defaultKind: String) -> String {
        let lower = xmlURL.lowercased()
        if lower.contains("youtube.com/feeds") { return "video" }
        if lower.contains("anchor.fm") || lower.contains("spreaker.com") || lower.contains("podcast") { return "audio" }
        if lower.contains("reddit.com/r/") { return "forum" }
        return defaultKind
    }

    /// The kinds an outline may declare with `feedmineMediaKind` and have it honoured. `text` is the generic
    /// default the curation pipeline writes for whatever it has not classified, so file-name and URL evidence
    /// still wins for it; audio/video/forum are editorial decisions and are not overridden by a guess.
    static let explicitMediaKinds: Set<String> = ["audio", "video", "forum"]

    /// The builder's `declared_media_kind`.
    static func declaredMediaKind(_ raw: String?) -> String? {
        let value = trimmed(raw ?? "").lowercased()
        return explicitMediaKinds.contains(value) ? value : nil
    }

    /// The builder's `folder_nodes`: the taxonomy path a file's folder gives every occurrence in it.
    ///
    /// Two differences from V1's Swift scanner, both measured against the shipped snapshot: the countries
    /// branch is entered for `countries` **and** `staging` and keeps the raw directory name as the node key
    /// (`90_countries`, not `90-countries`), and the language branch keys its first child by the raw language
    /// directory name with kind 4.
    static func folderNodes(relativePath: String, fileName: String) -> [CatalogInputNode] {
        let parts = relativePath.split(separator: "/").dropLast().map(String.init)

        if let first = parts.first, ["countries", "staging"].contains(semanticPathName(first)) {
            var nodes = [CatalogInputNode(key: first, name: "Countries", kind: CatalogNodeKind.topic, language: nil)]
            let countryParts = Array(parts.dropFirst())
            for (index, part) in countryParts.enumerated() {
                nodes.append(CatalogInputNode(key: part, name: displayName(part),
                    kind: index == 0 ? CatalogNodeKind.country : CatalogNodeKind.region, language: nil))
            }
            if let country = countryParts.first {
                if fileName == country { return nodes }
                if fileName.hasPrefix("\(country)-") {
                    appendFileNode(fileName: String(fileName.dropFirst(country.count + 1)),
                        kind: CatalogNodeKind.region, to: &nodes)
                } else {
                    appendFileNode(fileName: fileName, kind: CatalogNodeKind.region, to: &nodes)
                }
            }
            return nodes
        }

        if parts.first == "languages", parts.count >= 2 {
            var nodes = [CatalogInputNode(key: "languages", name: "Languages", kind: CatalogNodeKind.topic,
                language: nil)]
            for (index, part) in parts.dropFirst().enumerated() {
                nodes.append(CatalogInputNode(key: part, name: displayName(part),
                    kind: index == 0 ? CatalogNodeKind.language : CatalogNodeKind.subcategory,
                    language: index == 0 ? part : nil))
            }
            appendFileNode(fileName: fileName, kind: CatalogNodeKind.subcategory, to: &nodes)
            return nodes
        }

        if !parts.isEmpty {
            var nodes = parts.enumerated().map { index, part in
                CatalogInputNode(key: slug(part), name: displayName(part),
                    kind: index == 0 ? CatalogNodeKind.topic : CatalogNodeKind.subcategory, language: nil)
            }
            appendFileNode(fileName: fileName, kind: CatalogNodeKind.subcategory, to: &nodes)
            return nodes
        }

        return [
            CatalogInputNode(key: "global", name: "Global", kind: CatalogNodeKind.topic, language: nil),
            CatalogInputNode(key: slug(fileName), name: displayName(fileName), kind: CatalogNodeKind.subcategory,
                language: nil),
        ]
    }

    /// The builder's `.strip()` — Python's `str.strip()`, which is *not* Foundation's
    /// `whitespacesAndNewlines`: the latter also removes U+FEFF, and a BOM inside an editorial title is real data
    /// in the feeds tree. The reference build keeps it, so a trim that dropped it would put a different title —
    /// and a different placement `title_override` — in the catalogue than the reference has.
    static func trimmed(_ raw: String) -> String {
        let scalars = Array(raw.unicodeScalars)
        var start = 0
        var end = scalars.count
        while start < end, isPythonWhitespace(scalars[start]) { start += 1 }
        while end > start, isPythonWhitespace(scalars[end - 1]) { end -= 1 }
        return String(String.UnicodeScalarView(scalars[start..<end]))
    }

    /// Python's `str.isspace()`: Unicode whitespace, plus the ASCII separators Unicode does not list as
    /// `White_Space` but Python's `strip()` removes.
    private static func isPythonWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        if Character(scalar).isWhitespace { return true }
        switch scalar.value {
        case 0x1C...0x1F: return true
        default: return false
        }
    }

    /// The builder's `display_host`: the lowercased host of the declared address, read out of the address text
    /// the way `urllib.parse.urlsplit(...).hostname` reads it — userinfo and port dropped, IPv6 brackets dropped,
    /// no punycode decoding. `URLComponents` cannot express this: it decodes `xn--d1acibrhefqcr.bg` into Unicode
    /// and re-encodes the Unicode host as percent-escapes, where the builder keeps the host the tree wrote — and
    /// `display_host` reaches the catalogue's editorial facts, so it has to be the same host.
    static func displayHost(_ raw: String) -> String? {
        let value = trimmed(raw)
        guard let separator = value.range(of: "://") else { return nil }
        var authority = value[separator.upperBound...]
        if let end = authority.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            authority = authority[..<end]
        }
        if let at = authority.lastIndex(of: "@") { authority = authority[authority.index(after: at)...] }
        let host: Substring
        if let open = authority.firstIndex(of: "[") {
            guard let close = authority[open...].firstIndex(of: "]") else { return nil }
            host = authority[authority.index(after: open)..<close]
        } else if let colon = authority.firstIndex(of: ":") {
            host = authority[..<colon]
        } else {
            host = authority
        }
        return host.isEmpty ? nil : host.lowercased()
    }

    /// The builder's `append_file_node`: the file's own node, unless it would repeat the node above it.
    private static func appendFileNode(fileName: String, kind: Int, to nodes: inout [CatalogInputNode]) {
        let key = slug(fileName)
        guard nodes.last?.key != key else { return }
        nodes.append(CatalogInputNode(key: key, name: displayName(fileName), kind: kind, language: nil))
    }

    /// The builder's file discovery: every `*.opml` under the tree, in path order, extension matched exactly.
    /// V1's Swift scanner skipped hidden files and lowercased the extension; the builder does neither, and the
    /// order is the `sort_order` every placement carries.
    private static func opmlFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []) else {
            throw CatalogCompilerError.feedsRootUnreadable(root.path)
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "opml" else { continue }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard !isDirectory else { continue }
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    /// The builder's `relative_path`: the path under the tree root, `/`-joined. It is the placement's
    /// `opml_file` and the provenance of every row compiled from that file.
    static func relativePath(of fileURL: URL, under root: URL) -> String {
        var rootPath = root.standardizedFileURL.path
        while rootPath.hasSuffix("/") { rootPath.removeLast() }
        let path = fileURL.standardizedFileURL.path
        if path.hasPrefix(rootPath + "/") { return String(path.dropFirst(rootPath.count + 1)) }
        return fileURL.lastPathComponent
    }
}

/// The builder's `extract_language`, and the namespace test the builder's ElementTree traversal implies: reads
/// the root's namespace declaration and `head/language`, then stops — the body is walked by the reader below.
private final class CatalogHeadScan: NSObject, XMLParserDelegate {
    private var names: [String] = []
    private var inHead = false
    private var languageDepth: Int?
    private var languageText = ""

    private(set) var namespacedRoot = false
    private(set) var language: String?

    /// Runs the head pass over one document. The result of `parse()` is deliberately discarded: a document that
    /// fails here fails again, identically, in the body pass, which is where the failure is counted.
    static func read(_ data: Data) -> (language: String?, namespacedRoot: Bool) {
        let scanner = CatalogHeadScan()
        let parser = XMLParser(data: data)
        parser.delegate = scanner
        parser.parse()
        return (scanner.language, scanner.namespacedRoot)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let depth = names.count
        if depth == 0, attributes.keys.contains(where: { $0 == "xmlns" || $0.hasPrefix("xmlns:") }) {
            namespacedRoot = true
            // A namespaced root has no `body` the builder can find, so there is nothing left to read.
            parser.abortParsing()
            return
        }
        names.append(elementName)
        if depth == 1, elementName == "head" { inHead = true }
        if inHead, depth == 2, elementName == "language" { languageDepth = depth; languageText = "" }
        if depth == 1, elementName == "body" { parser.abortParsing() }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?) {
        let depth = names.count - 1
        if names.last == elementName { names.removeLast() }
        if elementName == "language", depth == 2, languageDepth == depth {
            languageDepth = nil
            let trimmed = CatalogOPMLScan.trimmed(languageText)
            if language == nil, !trimmed.isEmpty { language = trimmed }
        }
        if elementName == "head", depth == 1 { parser.abortParsing() }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if languageDepth != nil { languageText += string }
    }
}

/// One `body` traversal, the same rules as the builder's recursive `iter_outline_occurrences`: an outline with a
/// valid `xmlUrl` is a source, an outline with an unusable one is an invalid source, an outline without one is a
/// category that nests and passes its language down, and nothing inside a source outline is ever read.
private final class CatalogOutlineScanner: NSObject, XMLParserDelegate {
    private let folderNodes: [CatalogInputNode]
    private let fallbackCategory: String
    private let opmlFile: String
    private let fileIndex: Int
    private let fileLanguage: String?
    private let defaultMediaKind: String

    private var names: [String] = []
    private var bodyDepth: Int?
    private var categoryStack: [(name: String, language: String?)] = []
    private var pushedCategories: [Int: Bool] = [:]
    private var skipDepth: Int?
    private var order = 0

    private(set) var occurrences: [CatalogOccurrence] = []
    private(set) var invalidSourceCount = 0

    init(folderNodes: [CatalogInputNode], fallbackCategory: String, opmlFile: String, fileIndex: Int,
        fileLanguage: String?, defaultMediaKind: String) {
        self.folderNodes = folderNodes
        self.fallbackCategory = fallbackCategory
        self.opmlFile = opmlFile
        self.fileIndex = fileIndex
        self.fileLanguage = fileLanguage
        self.defaultMediaKind = defaultMediaKind
        super.init()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let depth = names.count
        names.append(elementName)
        if depth == 1, elementName == "body" { bodyDepth = depth }
        guard elementName == "outline", skipDepth == nil, let bodyDepth, depth > bodyDepth else { return }
        handleOutline(depth: depth, attributes: attributes)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?) {
        let depth = names.count - 1
        if names.last == elementName { names.removeLast() }
        if let skip = skipDepth, skip == depth { skipDepth = nil }
        if elementName == "outline", skipDepth == nil, pushedCategories.removeValue(forKey: depth) == true {
            categoryStack.removeLast()
        }
        if elementName == "body", depth == 1 { bodyDepth = nil }
    }

    private func handleOutline(depth: Int, attributes: [String: String]) {
        let xmlURL = CatalogOPMLScan.trimmed(attributes["xmlUrl"] ?? "")
        let name = outlineName(attributes)
        let language = declaredLanguage(attributes)

        if !xmlURL.isEmpty, FeedAddress.isValidHTTPURL(xmlURL) {
            let categoryNodes = categoryStack.map {
                CatalogInputNode(key: CatalogOPMLScan.slug($0.name), name: $0.name, kind: CatalogNodeKind.subcategory,
                    language: $0.language)
            }
            let title = name.isEmpty ? (categoryStack.last?.name ?? fallbackCategory) : name
            let mediaKind = CatalogOPMLScan.declaredMediaKind(attributes["feedmineMediaKind"])
                ?? CatalogOPMLScan.mediaKind(forURL: xmlURL, default: defaultMediaKind)
            occurrences.append(CatalogOccurrence(
                title: title,
                declaredURL: xmlURL,
                requestURL: xmlURL,
                mediaKind: mediaKind,
                language: language,
                nodePath: folderNodes + categoryNodes,
                opmlFile: opmlFile,
                sortOrder: fileIndex * 1_000_000 + order,
                titleOverride: title,
                languageOverride: language,
                mediaKindOverride: mediaKind,
                siteURL: trimmed(attributes["htmlUrl"]),
                description: trimmed(attributes["description"]),
                tags: trimmed(attributes["category"]),
                nature: trimmed(attributes["feedmineNature"]),
                activity: trimmed(attributes["feedmineActivity"]),
                latestItemAt: trimmed(attributes["feedmineLatestItemAt"]),
                qualityScore: qualityScore(attributes["feedmineQualityScore"]),
                defaultEnabled: (attributes["feedmineDefaultEnabled"] ?? "true").lowercased() != "false",
                feedType: trimmed(attributes["type"])))
            order += 1
            skipDepth = depth
            return
        }

        if !xmlURL.isEmpty {
            invalidSourceCount += 1
            skipDepth = depth
            return
        }

        guard !name.isEmpty else { return }
        pushedCategories[depth] = true
        categoryStack.append((name, language))
    }

    /// The builder's `outline_name`: `title`, else `text`, else the file's own display name — the `or` chain is
    /// decided before trimming, so a whitespace-only attribute still falls through to nothing.
    private func outlineName(_ attributes: [String: String]) -> String {
        let title = attributes["title"] ?? ""
        let text = attributes["text"] ?? ""
        let chosen = !title.isEmpty ? title : (!text.isEmpty ? text : fallbackCategory)
        return CatalogOPMLScan.trimmed(chosen)
    }

    /// The builder's language rule: the outline's own `language`, else the nearest enclosing category's, else the
    /// file's `head/language`. `und` is kept exactly as declared — the catalogue's own data has 27,741 of them,
    /// and V1's Swift scanner dropped them to NULL, which is a different source and node language.
    private func declaredLanguage(_ attributes: [String: String]) -> String? {
        let declared = attributes["language"] ?? ""
        if !declared.isEmpty { return declared }
        return categoryStack.last?.language ?? fileLanguage
    }

    private func trimmed(_ raw: String?) -> String? {
        let value = CatalogOPMLScan.trimmed(raw ?? "")
        return value.isEmpty ? nil : value
    }

    /// The builder's `int(...) if attrib.get(...).isdigit() else None`: digits only, nothing stripped first.
    private func qualityScore(_ raw: String?) -> Int? {
        guard let raw, !raw.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(raw)
    }
}
