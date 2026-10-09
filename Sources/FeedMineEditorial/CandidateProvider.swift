// Owns: context mapping and one bounded local structural supply window per call.
// Does not own: selection/policy execution, source filtering mechanics or acquisition.

import Foundation
import FeedMineDomain
import FeedMinePersistence

public struct CandidateSupplyCursor: Hashable, Sendable {
    public let sortDate: Date
    public let originRecordID: OriginRecordID

    public init(sortDate: Date, originRecordID: OriginRecordID) {
        self.sortDate = sortDate
        self.originRecordID = originRecordID
    }
}

public struct CandidateSupplyWindow: Hashable, Sendable {
    public let candidates: [Candidate]
    public let examinedCount: Int
    public let nextCursor: CandidateSupplyCursor?
    public let exhausted: Bool
}

public enum CandidateProviderError: Error, Equatable, Sendable {
    case searchContextUnavailable
}

public struct CandidateProvider: Sendable {
    private let contentStore: ContentStore

    public init(contentStore: ContentStore) { self.contentStore = contentStore }

    /// Uses only the plan context. Editorial policy versions are not executed in 3C.
    public func candidates(for plan: FeedPlan, after cursor: CandidateSupplyCursor?,
        examinedCapacity: Int) throws -> CandidateSupplyWindow {
        let sourceID: SourceID?
        switch plan.context.request {
        case .main: sourceID = nil
        case .source(let id): sourceID = id
        case .search: sourceID = nil
        }
        let window = try contentStore.candidateWindow(sourceID: sourceID,
            after: cursor.map { ContentStore.CandidateCursor(sortDate: $0.sortDate, originRecordID: $0.originRecordID) },
            examinedCapacity: examinedCapacity)
        var candidates = window.records.map { record in
            let kind: CandidateTimestampKind
            switch record.sortDateBasis {
            case .authored: kind = .authored
            case .observedFallback: kind = .observed
            }
            return Candidate(originRecordID: record.originRecordID, originRevisionID: record.originRevisionID,
                headline: record.headline.map(ReadablePublicationText.convert), summary: record.summary.map(ReadablePublicationText.convert),
                timestamp: CandidateTimestamp(value: record.sortDate, kind: kind),
                language: record.language, providerID: record.providerID, sourceIDs: Set(record.sourceIDs),
                primaryMediaLocator: record.primaryMediaLocator, primaryLink: record.primaryLink)
        }
        if case .search(let search) = plan.context.request {
            let query = search.query.trimmingCharacters(in: .whitespacesAndNewlines)
            candidates = candidates.filter { candidate in
                [candidate.headline, candidate.summary].compactMap { $0 }.contains {
                    $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) != nil
                }
            }
        }
        return CandidateSupplyWindow(candidates: candidates, examinedCount: window.examinedCount,
            nextCursor: window.nextCursor.map { CandidateSupplyCursor(sortDate: $0.sortDate, originRecordID: $0.originRecordID) },
            exhausted: window.exhausted)
    }
}

// Conservative lexical conversion, not an HTML document/DOM interpreter. Format hints
// do not survive into Candidate. Only syntactically identifiable tags are removed;
// malformed tag spans and unknown/invalid entities remain literal. Unclosed comments
// and recognized non-presentable raw-text elements suppress their remaining content.
// Decoded entities are appended as text and never tokenized again.
private enum ReadablePublicationText {
    private struct Tag {
        let name: String
        let closing: Bool
        let empty: Bool
    }
    private static let blocks: Set<String> = ["p", "div", "section", "article", "header", "footer", "blockquote",
        "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "pre"]
    private static let hidden: Set<String> = ["script", "style", "iframe", "object", "embed"]
    // Complete HTML 4.01 table (HTMLNamedEntities.swift); unknown names remain literal.
    private static var entities: [String: String] { HTMLNamedEntities.table }

    static func convert(_ text: String) -> String {
        let source = Array(text.unicodeScalars)
        var output: [Unicode.Scalar] = []
        output.reserveCapacity(source.count)
        var index = 0, separator = 0
        var suppressed: String?
        func trimBoundary() {
            while let last = output.last, whitespace(last) { output.removeLast() }
        }
        func append(_ scalar: Unicode.Scalar) {
            if separator > 0 {
                if whitespace(scalar) { return }
                trimBoundary()
                if !output.isEmpty { output.append(contentsOf: repeatElement(Unicode.Scalar(10)!, count: separator)) }
                separator = 0
            }
            output.append(scalar)
        }
        while index < source.count {
            if let raw = suppressed {
                // Only a syntactically complete closing tag of the same name ends raw text.
                // Other '<' characters in script/style text do not start nested tokenization.
                if source[index] == "<", index + 1 < source.count, source[index + 1] == "/" {
                    let token = tag(source, at: index)
                    if let value = token.value, value.closing, value.name == raw { suppressed = nil }
                    index = token.end
                } else { index += 1 }
                continue
            }
            if source[index] == "<" {
                if index + 3 < source.count, source[index + 1] == "!", source[index + 2] == "-", source[index + 3] == "-" {
                    index += 4
                    while index + 2 < source.count,
                        !(source[index] == "-" && source[index + 1] == "-" && source[index + 2] == ">") { index += 1 }
                    index = min(source.count, index + 3)
                    continue
                }
                let token = tag(source, at: index)
                if let value = token.value {
                    if hidden.contains(value.name) {
                        if !value.closing, !value.empty { suppressed = value.name }
                    } else if blocks.contains(value.name) { separator = 2 }
                    else if value.name == "br" { separator = max(separator, 1) }
                } else {
                    // Consume a failed scanned span once, rather than rescanning its suffix
                    // at every '<'. This keeps malformed/unterminated attributes bounded.
                    for scalar in source[index..<token.end] { append(scalar) }
                }
                index = token.end
                continue
            }
            if source[index] == "&" {
                var end = index + 1
                while end < source.count, source[end] != ";", source[end] != "&", source[end] != "<", !whitespace(source[end]) { end += 1 }
                if end < source.count, source[end] == ";" {
                    let name = String(String.UnicodeScalarView(source[(index + 1)..<end]))
                    let decoded: String?
                    if name.hasPrefix("#") {
                        let hex = name.hasPrefix("#x") || name.hasPrefix("#X")
                        let digits = name.dropFirst(hex ? 2 : 1)
                        let validDigits = !digits.isEmpty && digits.utf8.allSatisfy { byte in
                            (48...57).contains(byte) || (hex && ((65...70).contains(byte) || (97...102).contains(byte)))
                        }
                        if validDigits, let number = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(number) {
                            decoded = String(scalar)
                        } else { decoded = nil }
                    } else { decoded = entities[name] }
                    if let decoded { for scalar in decoded.unicodeScalars { append(scalar) } }
                    else { for scalar in source[index...end] { append(scalar) } }
                    index = end + 1
                } else {
                    for scalar in source[index..<end] { append(scalar) }
                    index = end
                }
                continue
            }
            append(source[index]); index += 1
        }
        if separator > 0 { trimBoundary() }
        return String(String.UnicodeScalarView(output))
    }

    private static func whitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" || scalar.value == 12
    }
    private static func letter(_ scalar: Unicode.Scalar) -> Bool {
        (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }
    private static func tag(_ source: [Unicode.Scalar], at start: Int) -> (end: Int, value: Tag?) {
        var cursor = start + 1
        let closing = cursor < source.count && source[cursor] == "/"
        if closing { cursor += 1 }
        guard cursor < source.count, letter(source[cursor]) else { return (start + 1, nil) }
        let nameStart = cursor
        while cursor < source.count, letter(source[cursor]) || (48...57).contains(source[cursor].value) || source[cursor] == "-" || source[cursor] == ":" { cursor += 1 }
        let name = String(String.UnicodeScalarView(source[nameStart..<cursor])).lowercased()
        guard cursor < source.count else { return (cursor, nil) }
        guard whitespace(source[cursor]) || source[cursor] == "/" || source[cursor] == ">" else { return (cursor, nil) }
        // Slash directly after a name is only a self-closing suffix, not a URL/tag.
        if source[cursor] == "/", (cursor + 1 == source.count || source[cursor + 1] != ">") { return (cursor, nil) }
        var quote: Unicode.Scalar?
        while cursor < source.count {
            let scalar = source[cursor]
            if let current = quote {
                if scalar == current { quote = nil }
            } else if scalar == "\"" || scalar == "'" { quote = scalar }
            else if scalar == "<" { return (cursor, nil) }
            else if scalar == ">" {
                return (cursor + 1, Tag(name: name, closing: closing, empty: source[cursor - 1] == "/"))
            }
            cursor += 1
        }
        return (cursor, nil)
    }
}
