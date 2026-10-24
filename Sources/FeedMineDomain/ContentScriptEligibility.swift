// File: ContentScriptEligibility.swift
// Module: FeedMineDomain
//
// Responsibility:
// The one place that answers, from the text a candidate would show, whether that text can belong to a language.
// It exists because the catalogue and the feed documents declare a language per channel, not per story: a channel
// that declares `en` can publish a story written in another script, and the reader who selected only English then
// receives it. The value is the writing system the story's own text is actually in — never an inference about
// meaning, translation or editorial quality.
//
// Does not own: deciding which languages the reader chose (the recipe and the filter do), fetching a language tag
// from a document (acquisition does), or hiding a card after publication (this runs at admission only).
import Foundation

/// The writing systems this build can tell apart. `other` never decides anything: a text whose letters are all in
/// a script this build does not classify has no evidence, and no evidence never rejects content.
public enum ContentScript: String, CaseIterable, Sendable {
    case latin, greek, cyrillic, hebrew, arabic, devanagari, thai, han, kana, hangul

    /// The scripts a language uses. `nil` means this build does not know the language, which is the same fact as
    /// "no evidence": the caller must then admit rather than reject.
    public static func scripts(forLanguage language: String) -> Set<ContentScript>? {
        guard let base = ReaderLanguageScript.baseLanguage(language) else { return nil }
        switch base {
        case "en", "es", "pt", "fr", "de", "it", "nl", "da", "sv", "nb", "no", "fi", "is", "pl", "cs", "sk",
            "sl", "hr", "bs", "sr-latn", "ro", "hu", "et", "lv", "lt", "tr", "az", "id", "ms", "vi", "sw",
            "af", "ca", "gl", "eu", "cy", "ga", "sq", "tl", "fil", "mt", "lb", "fo":
            return [.latin]
        case "ru", "uk", "bg", "sr", "mk", "be", "kk", "ky", "tg", "mn":
            return [.cyrillic]
        case "el": return [.greek]
        case "he", "yi": return [.hebrew]
        case "ar", "fa", "ur", "ps", "sd", "ug": return [.arabic]
        case "hi", "mr", "ne", "sa": return [.devanagari]
        case "th": return [.thai]
        case "zh", "yue": return [.han]
        case "ja": return [.han, .kana]
        case "ko": return [.hangul, .han]
        default: return nil
        }
    }
}

public enum ReaderLanguageScript {
    /// The language part of a tag this build already treats as one language (`pt-BR` and `pt` are the same), and
    /// `nil` for an absent or unusable tag.
    public static func baseLanguage(_ language: String) -> String? {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let base = trimmed.split(separator: "-").first.map(String.init) ?? trimmed
        return base.isEmpty ? nil : base
    }

    /// Which scripts a set of languages uses. Empty means "this build cannot answer", never "no script allowed".
    public static func scripts(for languages: some Sequence<String>) -> Set<ContentScript> {
        var union = Set<ContentScript>()
        var unknown = false
        for language in languages {
            guard let scripts = ContentScript.scripts(forLanguage: language) else { unknown = true; continue }
            union.formUnion(scripts)
        }
        return unknown ? [] : union
    }

    /// The sign the text is actually written in: the script holding a strict majority of its letters, or `nil` when
    /// there are no letters or no majority (a mixed title is ambiguous, and ambiguity never rejects content).
    public static func dominantScript(of text: String) -> ContentScript? {
        var counts: [ContentScript: Int] = [:]
        var total = 0
        for scalar in text.unicodeScalars {
            guard let script = script(of: scalar) else { continue }
            counts[script, default: 0] += 1
            total += 1
        }
        guard total > 0 else { return nil }
        // Deterministic tie-break: the alphabetically first script wins ties, but a tie is *not* a majority and is
        // therefore reported as no evidence.
        for (script, count) in counts.sorted(by: { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }) {
            return count * 2 > total ? script : nil
        }
        return nil
    }

    /// Whether the text can belong to the language the document itself declared. A missing declaration, an unknown
    /// language or ambiguous text is admitted: the rule exists to catch a *proven* mismatch, not to guess.
    public static func admits(_ text: String, declaredLanguage: String?) -> Bool {
        guard let declaredLanguage, let scripts = ContentScript.scripts(forLanguage: declaredLanguage),
            let dominant = dominantScript(of: text) else { return true }
        return scripts.contains(dominant)
    }

    /// Whether the text can belong to any of the languages the reader chose. An empty or partly unknown set is not
    /// evidence against the text, so it admits.
    public static func admits(_ text: String, languages: some Sequence<String>) -> Bool {
        let wanted = scripts(for: languages)
        guard !wanted.isEmpty, let dominant = dominantScript(of: text) else { return true }
        return wanted.contains(dominant)
    }

    /// The script one scalar belongs to, or `nil` when it is not a letter this build classifies.
    private static func script(of scalar: Unicode.Scalar) -> ContentScript? {
        let v = scalar.value
        switch v {
        case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F, 0x1E00...0x1EFF, 0x2C60...0x2C7F,
            0xA720...0xA7FF, 0xFB00...0xFB06: return .latin
        case 0x0370...0x03FF, 0x1F00...0x1FFF: return .greek
        case 0x0400...0x04FF, 0x0500...0x052F, 0x2DE0...0x2DFF, 0xA640...0xA69F, 0x1C80...0x1C88: return .cyrillic
        case 0x0590...0x05FF, 0xFB1D...0xFB4F: return .hebrew
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF: return .arabic
        case 0x0900...0x097F, 0x1CD0...0x1CFF, 0xA8E0...0xA8FF: return .devanagari
        case 0x0E00...0x0E7F: return .thai
        case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9D: return .kana
        case 0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xAC00...0xD7FF: return .hangul
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: return .han
        default: return nil
        }
    }
}
