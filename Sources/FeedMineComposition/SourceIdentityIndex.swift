//
// File: SourceIdentityIndex.swift
// Module: FeedMineComposition
//
// Responsibility:
// The one answer to "which durable key does this frozen source id name?" — the question a published card asks when
// it names a source the reader is not currently reading. The id is compared with the derivation that **minted** it
// (`LegacyCatalogImport` for a catalogue key, `ReaderSourceIdentity` for a key the reader brought), never with a
// title, a URL or a second namespace.
//
// A verified alias keeps two keys per source: `anchorKey`, the id cards published before a catalogue rename carry,
// and `currentKey`, what the catalogue resolves today. Both derivations therefore have to be tried, or one half of
// the reader's cards loses its destination — and the answer is always `currentKey`, which every row of the alias
// states identically, so the result does not depend on the order the rows come back in.
//
// Does not own: writing the identity table (Persistence), resolving a key into a feed (`TrustedFeed`) or opening a
// context (the app host).
import Foundation
import FeedMineDomain
import FeedMinePersistence

public enum SourceIdentityIndex {
    /// The key a frozen `SourceID` names, read off the identity rows that know it. `nil` when this reader never
    /// resolved the key — an honest absence, not a guess.
    public static func key(for sourceID: SourceID,
        links: [String: ReaderLibraryStore.SourceLink]) -> String? {
        // Sorted so the answer cannot depend on dictionary iteration order even when two rows disagree about which
        // key they are filed under.
        for key in links.keys.sorted() {
            guard let link = links[key],
                let canonical = canonicalKey(of: link, minting: sourceID) else { continue }
            return canonical
        }
        return nil
    }

    /// Both minted ids one editorial source answers to, read off the rows that name it in either derivation. A
    /// verified alias records `anchor = oldKey` and `current = newKey`, so a card published before a catalogue
    /// rename carries the anchor's id and a card published after it carries the current key's. A surface that
    /// reads the source has to name both, or half of its published history is unreachable.
    ///
    /// Only rows that name `sourceID` contribute — this is never a global id mapping — and the answer is `[]` for a
    /// source no row knows or whose authority this build does not declare.
    public static func sourceIDs(in links: [String: ReaderLibraryStore.SourceLink],
        for sourceID: SourceID) -> Set<SourceID> {
        var result: Set<SourceID> = []
        for link in links.values {
            let derive: (String) -> SourceID
            switch link.authority {
            case "reader": derive = ReaderSourceIdentity.sourceID(forKey:)
            case "catalog": derive = LegacyCatalogImport.sourceID(forKey:)
            default: continue
            }
            let anchorID = derive(link.anchorKey), currentID = derive(link.currentKey)
            guard anchorID == sourceID || currentID == sourceID else { continue }
            result.insert(anchorID)
            result.insert(currentID)
        }
        return result
    }

    /// The key one row answers with, or `nil` when the row minted neither of its keys to that id, or when it states
    /// an authority this build does not declare — an undeclared namespace is never read as the catalogue's.
    /// `currentKey` comes first because it is where the catalogue resolves the source now; the other two are only a
    /// fallback for a row that lost it, never a preference.
    private static func canonicalKey(of link: ReaderLibraryStore.SourceLink,
        minting sourceID: SourceID) -> String? {
        let derive: (String) -> SourceID
        switch link.authority {
        case "reader": derive = ReaderSourceIdentity.sourceID(forKey:)
        case "catalog": derive = LegacyCatalogImport.sourceID(forKey:)
        default: return nil
        }
        guard derive(link.anchorKey) == sourceID || derive(link.currentKey) == sourceID else { return nil }
        return [link.currentKey, link.sourceKey, link.anchorKey].first { !$0.isEmpty }
    }
}
