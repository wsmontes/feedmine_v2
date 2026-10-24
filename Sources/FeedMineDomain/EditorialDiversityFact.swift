// File: EditorialDiversityFact.swift
// Module: FeedMineDomain
//
// Responsibility:
// R17: the small editorial facts a published segment is allowed to remember for diversity decisions. They are
// frozen at publication (the story's own declared subjects, the source and the provider — never the latest
// canonical revision, never the Source's category as a story subject) and are unknown when absent.
//
// Does not own: selection, ordering or publication. It is a value the publication owner stores and the editorial
// context reads.
import Foundation

public struct EditorialDiversityFact: Hashable, Codable, Sendable {
    public let sourceIDs: [SourceID]
    public let providerID: ProviderID?
    /// Declared-subject identities (the publisher's own vocabulary). Empty is absence of evidence.
    public let subjects: [String]

    public init(sourceIDs: [SourceID], providerID: ProviderID?, subjects: [String]) {
        self.sourceIDs = sourceIDs.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
        self.providerID = providerID
        self.subjects = subjects
    }
}
