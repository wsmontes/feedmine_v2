import Foundation
import GRDB
import FeedMineDomain

extension ReaderHistoryBindingStore {
    public struct LegacyCheckpoint: Hashable, Sendable {
        /// The original saved statement, including an inconsistent Edition column if present.
        public let point: SessionStore.CheckpointRecord
        public let isActive: Bool
    }

    public struct LegacyCandidate: Hashable, Sendable {
        public let edition: PublicationStore.EditionRecord
        public let evidence: Evidence
        /// All distinct known statements; the active singleton precedes retained context rows.
        public let checkpoints: [LegacyCheckpoint]
    }

    /// Inspect known raw/current-forward matches without claiming history or changing reader authority.
    /// Multiple candidates remain multiple: compatibility and explicit ambiguity recovery belong to the host.
    public func legacyCandidates(logicalKey: ContextKey,
        wordExclusions: ReaderWordExclusionSnapshot) throws -> [LegacyCandidate] {
        try database.read { db in
            guard wordExclusions.context == logicalKey.filter.exclusions else { throw Failure.incompatibleAdoption }
            guard try wordExclusions.matches(settings: ReaderPreferencesStore.publicationSettings(in: db)) else {
                throw Failure.staleAdoptionPolicy
            }
            let forward = ContextKey(request: logicalKey.request, preset: logicalKey.preset,
                filter: logicalKey.filter.replacing(exclusions: wordExclusions.exclusions),
                searchScope: logicalKey.searchScope, identitySchemaVersion: logicalKey.identitySchemaVersion)
            let editions = try Row.fetchAll(db, sql: """
                SELECT e.* FROM feed_editions e
                WHERE e.context_identity IN (?, ?) AND NOT EXISTS(
                    SELECT 1 FROM reader_history_editions h WHERE h.edition_id = e.id)
                ORDER BY e.id COLLATE BINARY
                """, arguments: [logicalKey.canonicalIdentity, forward.canonicalIdentity])
                .map(PublicationStore.decodeEdition)
            guard !editions.isEmpty else { return [] }
            let active = try Row.fetchOne(db, sql: "SELECT * FROM session_checkpoint WHERE singleton_id = 1")
                .map(SessionStore.checkpoint)
            // A legacy statement can also be filed under the wrong context projection. Resolve
            // these small per-context rows by card identity, rather than dropping their evidence.
            let retained = try Row.fetchAll(db, sql: """
                SELECT * FROM context_checkpoints ORDER BY context_identity COLLATE BINARY
                """)
                .map(SessionStore.checkpoint)
            var seen = Set<SessionStore.CheckpointRecord>()
            var statements: [(FeedEditionID, LegacyCheckpoint)] = []
            for point in (active.map({ [$0] }) ?? []) + retained {
                guard seen.insert(point).inserted else { continue }
                let editionID = try PublicationStore.location(ofCard: point.cardID, in: db)?.editionID ?? point.editionID
                statements.append((editionID, LegacyCheckpoint(point: point, isActive: point == active)))
            }
            return try editions.map { edition in
                let frozen = edition.editorialRevision.contextKey
                // Verify decoded metadata rather than relying solely on its indexed identity projection.
                guard frozen == logicalKey || frozen == forward else { throw Failure.corruption }
                return LegacyCandidate(edition: edition,
                    evidence: frozen == logicalKey ? .exactContext : .legacyWords(wordExclusions),
                    checkpoints: statements.filter { $0.0 == edition.id }.map(\.1))
            }
        }
    }
}
