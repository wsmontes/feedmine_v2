import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
@testable import FeedMineEditorial

final class CandidateProviderTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_700_000_000)

    private func withProvider(_ body: (ContentStore, CandidateProvider) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        let store = ContentStore(database: database)
        try body(store, CandidateProvider(contentStore: store))
    }
    private func origin(_ number: Int) -> OriginRecordID {
        OriginRecordID(rawValue: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!)
    }
    private func plan(_ request: FeedContextRequest, policy: UInt64 = 1) throws -> FeedPlan {
        let context = FeedContext(request: request)
        let version = PolicyVersion(rawValue: policy)
        return try XCTUnwrap(FeedPlan(context: context, revision: EditorialRevision(id: EditorialRevisionID(),
            contextKey: context.key, catalogGeneration: CatalogGeneration(rawValue: 1),
            userSelectionVersion: version, eligibilityPolicyVersion: version, scoringPolicyVersion: version,
            sequencingPolicyVersion: version, exposurePolicyVersion: version,
            selectionSchemaVersion: SelectionSchemaVersion(rawValue: 1))))
    }
    @discardableResult
    private func insert(_ number: Int, source: SourceID, into store: ContentStore,
        authored: Date? = nil, modified: Date? = nil, observed: Date? = nil, headline: String? = "", summary: String? = nil,
        language: String? = nil, provider: ProviderID? = nil,
        nonMaterialText: String = "not a candidate field") throws -> OriginRevision {
        let revision = OriginRevision(id: OriginRevisionID(), originRecordID: origin(number), externalVersionIdentity: nil,
            headline: headline, summary: summary, bodyText: "not a candidate field", authoredAt: authored,
            modifiedAt: modified, observedAt: observed ?? time, language: language,
            primaryLink: URL(string: "https://example.test/item")!, searchProjection: nonMaterialText, providerID: provider)
        try store.commitCanonicalChange(ContentStore.CanonicalChange(recordID: origin(number),
            externalObjectIdentity: ExternalIdentity(connectorKind: ConnectorKind(rawValue: "test"),
                namespace: "objects", value: String(number), role: .object), revision: revision, mediaCandidates: [],
            availability: .available, observedAt: time, expectedCurrent: .none, currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: source, kind: .direct, observedAt: time)]))
        return revision
    }

    func testReadableProjectionPreservesCanonicalBytesIdentityMetadataAndWindow() throws {
        try withProvider { store, provider in
            let source = SourceID(), other = SourceID(), attribution = ProviderID()
            let raw = try insert(1, source: source, into: store, authored: time.addingTimeInterval(10),
                headline: "<em>Headline &amp; news</em>", summary: "<p>One</p><p>Two &amp; three</p>", language: "pt", provider: attribution)
            _ = try insert(2, source: other, into: store, headline: "plain  title", summary: "2 < 3\n next")
            let original = try store.candidateWindow(sourceID: nil, after: nil, examinedCapacity: 1)
            let projected = try provider.candidates(for: plan(.main), after: nil, examinedCapacity: 1)
            let candidate = try XCTUnwrap(projected.candidates.first)
            XCTAssertEqual(candidate.headline, "Headline & news"); XCTAssertEqual(candidate.summary, "One\n\nTwo & three")
            XCTAssertEqual(candidate.originRecordID, raw.originRecordID); XCTAssertEqual(candidate.originRevisionID, raw.id)
            XCTAssertEqual(candidate.timestamp, .init(value: time.addingTimeInterval(10), kind: .authored))
            XCTAssertEqual(candidate.language, "pt"); XCTAssertEqual(candidate.providerID, attribution)
            XCTAssertEqual(projected.examinedCount, original.examinedCount); XCTAssertEqual(projected.exhausted, original.exhausted)
            XCTAssertEqual(projected.nextCursor, original.nextCursor.map { .init(sortDate: $0.sortDate, originRecordID: $0.originRecordID) })
            XCTAssertEqual(try store.originRevision(id: raw.id), raw)
            let rest = try provider.candidates(for: plan(.main), after: projected.nextCursor, examinedCapacity: 2)
            XCTAssertEqual(rest.candidates.map(\.originRecordID), [origin(2)])
            XCTAssertEqual(rest.candidates.first?.headline, "plain  title"); XCTAssertEqual(rest.candidates.first?.summary, "2 < 3\n next")
            let filtered = try provider.candidates(for: plan(.source(source)), after: nil, examinedCapacity: 3)
            XCTAssertEqual(filtered.candidates.map(\.originRecordID), [raw.originRecordID])
        }
    }

    /// R14: the provider reads the same expression the UI wrote — positives across fields and exclusions —
    /// while a legacy literal keeps the old single-substring meaning.
    func testSearchExpressionReadsPositivesAcrossFieldsAndExclusions() throws {
        try withProvider { store, provider in
            let source = SourceID()
            _ = try insert(1, source: source, into: store, headline: "Astronomia", summary: "Ciência aberta")
            _ = try insert(2, source: source, into: store, headline: "Astronomia", summary: "Astrologia e ciência")
            let current = try XCTUnwrap(SearchContext(query: "astronomia ciência -astrologia"))
            let matched = try provider.candidates(for: plan(.search(current)), after: nil, examinedCapacity: 10)
            XCTAssertEqual(matched.candidates.map(\.originRecordID), [origin(1)],
                "ambos os positivos, em campos separados, e nenhum campo com o excluído")
            let legacy = try XCTUnwrap(SearchContext(query: "astronomia ciência", semantics: .legacyLiteral))
            let literal = try provider.candidates(for: plan(.search(legacy)), after: nil, examinedCapacity: 10)
            XCTAssertTrue(literal.candidates.isEmpty,
                "o literal antigo é uma substring única e não casa com campos separados")
        }
    }

    func testMainMapsIDsOptionalPayloadTimestampsAndWindowMetadata() throws {
        try withProvider { store, provider in
            let a = SourceID(), b = SourceID(), attribution = ProviderID()
            let authored = time.addingTimeInterval(20), observed = time.addingTimeInterval(100)
            let v1 = try insert(1, source: a, into: store, authored: authored, observed: observed,
                headline: nil, summary: "summary é", language: "pt-BR", provider: attribution)
            let v2 = try insert(2, source: b, into: store, headline: "", summary: "")
            let result = try provider.candidates(for: plan(.main), after: nil, examinedCapacity: 3)
            XCTAssertEqual(result.candidates, [
                Candidate(originRecordID: origin(1), originRevisionID: v1.id, headline: nil, summary: "summary é",
                    timestamp: CandidateTimestamp(value: authored, kind: .authored),
                    temporal: CandidateTemporalEvidence(observedAt: observed, acceptedAuthoredAt: authored),
                    language: "pt-BR", providerID: attribution, sourceIDs: [a], primaryLink: URL(string: "https://example.test/item")!),
                Candidate(originRecordID: origin(2), originRevisionID: v2.id, headline: "", summary: "",
                    timestamp: CandidateTimestamp(value: time, kind: .observed),
                    temporal: CandidateTemporalEvidence(observedAt: time),
                    language: nil, providerID: nil, sourceIDs: [b], primaryLink: URL(string: "https://example.test/item")!)])
            XCTAssertEqual(result.examinedCount, 2)
            XCTAssertEqual(result.nextCursor, CandidateSupplyCursor(sortDate: time, originRecordID: origin(2)))
            XCTAssertTrue(result.exhausted)
            // This baseline uses context only; versions are not executed as policy.
            XCTAssertEqual(try provider.candidates(for: plan(.main, policy: UInt64.max), after: nil, examinedCapacity: 3), result)
        }
    }

    /// TX-07D: the candidate carries the temporal facts as distinct evidence reconstructed from canonical
    /// supply. A declared publication date is never substituted by the observation, absence stays absence,
    /// the accepted change instant stays a different fact from both, and an accepted instant that equals the
    /// observation instant is reported as ambiguous instead of being called a declared date.
    func testTemporalEvidenceKeepsDeclaredObservationAndAbsenceDistinct() throws {
        try withProvider { store, provider in
            let source = SourceID()
            let declared = time.addingTimeInterval(-30 * 86_400)
            let dated = try insert(1, source: source, into: store, authored: declared, observed: time)
            let undated = try insert(2, source: source, into: store, observed: time)
            let withChange = try insert(3, source: source, into: store, authored: declared,
                modified: declared.addingTimeInterval(3600), observed: time)
            // Exactly what a declaration ahead of the observation leaves behind once the original claim is
            // gone, and what a genuine coincidence would look like: identical canonical bytes.
            let coincident = try insert(4, source: source, into: store, authored: time, modified: time, observed: time)
            let candidates = try provider.candidates(for: plan(.main), after: nil, examinedCapacity: 4).candidates
            XCTAssertEqual(candidates.count, 4)
            let byOrigin = Dictionary(uniqueKeysWithValues: candidates.map { ($0.originRecordID, $0) })
            let datedEvidence = try XCTUnwrap(byOrigin[dated.originRecordID]?.temporal)
            XCTAssertEqual(datedEvidence.publicationDate, .declared(declared))
            XCTAssertEqual(datedEvidence.observedAt, time)
            XCTAssertNil(datedEvidence.acceptedModifiedAt)
            XCTAssertEqual(datedEvidence.modificationDate, .absent)
            XCTAssertEqual(byOrigin[dated.originRecordID]?.timestamp, CandidateTimestamp(value: declared, kind: .authored))
            let undatedEvidence = try XCTUnwrap(byOrigin[undated.originRecordID]?.temporal)
            XCTAssertEqual(undatedEvidence.publicationDate, .absent)
            XCTAssertNil(undatedEvidence.acceptedAuthoredAt)
            XCTAssertEqual(undatedEvidence.observedAt, time)
            XCTAssertEqual(byOrigin[undated.originRecordID]?.timestamp, CandidateTimestamp(value: time, kind: .observed))
            // The observation is never promoted into the publication date, only into the ordering key the
            // contract already documented (sort_date_basis == observedFallback).
            XCTAssertNotEqual(undatedEvidence.publicationDate, .declared(time))
            let changeEvidence = try XCTUnwrap(byOrigin[withChange.originRecordID]?.temporal)
            XCTAssertEqual(changeEvidence.publicationDate, .declared(declared))
            XCTAssertEqual(changeEvidence.acceptedModifiedAt, declared.addingTimeInterval(3600))
            XCTAssertEqual(changeEvidence.modificationDate, .declared(declared.addingTimeInterval(3600)))
            XCTAssertEqual(changeEvidence.inconsistencies, [])
            let coincidentEvidence = try XCTUnwrap(byOrigin[coincident.originRecordID]?.temporal)
            XCTAssertEqual(coincidentEvidence.acceptedAuthoredAt, time)
            XCTAssertEqual(coincidentEvidence.publicationDate, .ambiguousAtObservation(time))
            XCTAssertNotEqual(coincidentEvidence.publicationDate, .declared(time))
            XCTAssertEqual(coincidentEvidence.modificationDate, .ambiguousAtObservation(time))
            XCTAssertEqual(coincidentEvidence.inconsistencies, [])
            // The conservative reading changes no fact and removes nothing: the accepted values, the
            // ordering timestamp and the story itself are all exactly what canonical supply holds.
            XCTAssertEqual(coincidentEvidence.observedAt, time)
            XCTAssertEqual(byOrigin[coincident.originRecordID]?.timestamp, CandidateTimestamp(value: time, kind: .authored))
            XCTAssertEqual(byOrigin[coincident.originRecordID]?.originRevisionID, coincident.id)
        }
    }

    /// TX-07D: contextual temporal nature is a different dimension from date reliability, and a
    /// representation never becomes a presumed category by default. Only `unknown` is representable, and
    /// there is no category to reach for: age, subject, source and title are not evidence.
    func testTemporalNatureStaysUnknownForEveryRepresentation() throws {
        try withProvider { store, provider in
            let source = SourceID()
            try insert(1, source: source, into: store, authored: time.addingTimeInterval(-86_400))
            try insert(2, source: source, into: store)
            try insert(3, source: source, into: store, authored: time.addingTimeInterval(-5 * 365 * 86_400))
            let candidates = try provider.candidates(for: plan(.main), after: nil, examinedCapacity: 3).candidates
            XCTAssertEqual(candidates.count, 3)
            XCTAssertEqual(Set(candidates.map(\.temporal.nature)), [.unknown])
            // Three different date representations are present, and none of them is interpreted.
            XCTAssertEqual(Set(candidates.map(\.temporal.publicationDate)).count, 3)
            XCTAssertNil(StoryTemporalNature(rawValue: "timeSensitive"))
            XCTAssertNil(StoryTemporalNature(rawValue: "durable"))
            XCTAssertNil(StoryTemporalNature(rawValue: "news"))
            XCTAssertEqual(StoryTemporalNature(rawValue: "unknown"), .unknown)
        }
    }

    /// TX-07D: the evidence states only what the recorded facts themselves show. A declared change instant
    /// that precedes the declared publication instant is an inconsistency; nothing is estimated.
    func testTemporalEvidenceStatesOnlyInconsistenciesTheFactsThemselvesShow() throws {
        try withProvider { store, provider in
            let source = SourceID()
            let publication = time.addingTimeInterval(-10 * 86_400)
            let earlier = publication.addingTimeInterval(-3600)
            try insert(1, source: source, into: store, authored: publication, modified: publication.addingTimeInterval(3600))
            try insert(2, source: source, into: store, authored: publication, modified: earlier)
            // A clamped authorship: the accepted publication instant is the observation's own, so the order
            // it would imply is not evidence about the origin and must never fabricate an inconsistency.
            try insert(3, source: source, into: store, authored: time, modified: time.addingTimeInterval(-3600), observed: time)
            let candidates = try provider.candidates(for: plan(.main), after: nil, examinedCapacity: 3).candidates
            let byOrigin = Dictionary(uniqueKeysWithValues: candidates.map { ($0.originRecordID, $0) })
            XCTAssertEqual(byOrigin[origin(1)]?.temporal.inconsistencies, [])
            XCTAssertEqual(byOrigin[origin(2)]?.temporal.inconsistencies,
                [.modificationBeforePublication(publication: publication, modification: earlier)])
            XCTAssertEqual(byOrigin[origin(2)]?.temporal.acceptedModifiedAt, earlier)
            XCTAssertEqual(byOrigin[origin(2)]?.temporal.publicationDate, .declared(publication))
            XCTAssertEqual(byOrigin[origin(1)]?.temporal.publicationDate, byOrigin[origin(2)]?.temporal.publicationDate)
            XCTAssertEqual(byOrigin[origin(3)]?.temporal.publicationDate, .ambiguousAtObservation(time))
            XCTAssertEqual(byOrigin[origin(3)]?.temporal.modificationDate, .declared(time.addingTimeInterval(-3600)))
            XCTAssertEqual(byOrigin[origin(3)]?.temporal.inconsistencies, [])
        }
    }

    /// TX-07D: a caller that states only a timestamp states the narrowest fact it has, and the
    /// reconstruction never contradicts that timestamp's own kind — and never turns the single instant it
    /// was given into a declared publication date, because with no separate observation instant a declared
    /// value equal to that instant is indistinguishable from one the observation had to accept as itself.
    func testTimestampOnlyConstructionReconstructsTheNarrowestTemporalEvidence() {
        let authored = Candidate(originRecordID: origin(1), originRevisionID: OriginRevisionID(), headline: "H",
            summary: "S", timestamp: CandidateTimestamp(value: time, kind: .authored), language: nil, providerID: nil)
        XCTAssertEqual(authored.temporal.acceptedAuthoredAt, time)
        XCTAssertEqual(authored.temporal.observedAt, time)
        XCTAssertEqual(authored.temporal.publicationDate, .ambiguousAtObservation(time))
        XCTAssertNotEqual(authored.temporal.publicationDate, .declared(time))
        XCTAssertEqual(authored.temporal.modificationDate, .absent)
        XCTAssertTrue(authored.temporal.inconsistencies.isEmpty)
        let observed = Candidate(originRecordID: origin(2), originRevisionID: OriginRevisionID(), headline: "H",
            summary: "S", timestamp: CandidateTimestamp(value: time, kind: .observed), language: nil, providerID: nil)
        XCTAssertEqual(observed.temporal.publicationDate, .absent)
        XCTAssertNil(observed.temporal.acceptedAuthoredAt)
        XCTAssertEqual(observed.temporal.observedAt, time)
        XCTAssertEqual(observed.temporal.modificationDate, .absent)
        XCTAssertTrue(observed.temporal.inconsistencies.isEmpty)
        XCTAssertEqual(observed.temporal.nature, .unknown)
        // Stated evidence is never second-guessed: a caller that says the declaration is older than the
        // observation gets `.declared`, whether it comes from a store or from a fixture.
        let stated = Candidate(originRecordID: origin(3), originRevisionID: OriginRevisionID(), headline: "H",
            summary: "S", timestamp: CandidateTimestamp(value: time.addingTimeInterval(-86_400), kind: .authored),
            temporal: CandidateTemporalEvidence(observedAt: time,
                acceptedAuthoredAt: time.addingTimeInterval(-86_400)), language: nil, providerID: nil)
        XCTAssertEqual(stated.temporal.publicationDate, .declared(time.addingTimeInterval(-86_400)))
    }

    /// TX-07D (architect's acceptance condition): a declaration ahead of the observation is accepted as the
    /// observation instant and the original declaration is transient — it does not survive persistence. So
    /// after a real admission and a reopen, a future-declared story is never presented as a publication date
    /// that is provably current: the contract states the ambiguity, keeps the story in the offer, and leaves
    /// the canonical value and the ordering key exactly as they were written.
    func testFutureDeclarationAdmittedThenReopenedIsAmbiguousAndNeverDatedToday() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = RuntimeDatabaseLocation(directory: root)
        let sourceID = SourceID(), targetID = AcquisitionTargetID()
        let observation = Date(timeIntervalSince1970: 1_700_000_000)
        let claimed = Date(timeIntervalSince1970: 4_102_444_800) // 2100-01-01T00:00:00Z
        let object = ExternalIdentity(connectorKind: .syndication, namespace: "tx07d", value: "future", role: .object)
        do {
            let db = try RuntimeDatabase(location: location)
            _ = try AcquisitionTargetStore(database: db).register(id: targetID, connectorKind: .syndication,
                authorizedSources: [sourceID])
            let receipt = try AcquisitionAdmissionStore(database: db).admit(.init(targetID: targetID,
                targetGeneration: 1, expectedCheckpointRevision: 0, observations: [
                    .init(objectIdentity: object, versionIdentity: nil, precedence: .makeCurrent,
                        availability: .available, headline: "Declared 2100", summary: "Summary", bodyText: nil,
                        authoredAt: observation, modifiedAt: nil, observedAt: observation, language: "en",
                        primaryLink: nil, searchProjection: nil, providerID: nil,
                        memberships: [.init(sourceID: sourceID, kind: .direct)], mediaCandidates: [],
                        declaredAuthoredAt: claimed)
                ], nextCheckpoint: nil))
            XCTAssertTrue(receipt.rejectedObservations.isEmpty)
            // Canonical supply holds the accepted value and nothing else: the claim is already gone.
            let written = ContentStore(database: db)
            let revisionID = try XCTUnwrap(written.candidateWindow(sourceID: nil, after: nil,
                examinedCapacity: 1).records.first?.originRevisionID)
            let stored = try XCTUnwrap(written.originRevision(id: revisionID))
            XCTAssertEqual(stored.authoredAt, observation)
            XCTAssertNotEqual(stored.authoredAt, claimed)
        }
        let reopened = try RuntimeDatabase(location: location)
        let store = ContentStore(database: reopened)
        let record = try XCTUnwrap(store.candidateWindow(sourceID: nil, after: nil, examinedCapacity: 1).records.first)
        XCTAssertEqual(record.authoredAt, observation)
        XCTAssertEqual(record.observedAt, observation)
        XCTAssertEqual(record.sortDate, observation)
        XCTAssertEqual(record.sortDateBasis, .authored)
        let candidate = try XCTUnwrap(CandidateProvider(contentStore: store)
            .candidates(for: plan(.main), after: nil, examinedCapacity: 1).candidates.first)
        XCTAssertEqual(candidate.temporal.publicationDate, .ambiguousAtObservation(observation))
        XCTAssertNotEqual(candidate.temporal.publicationDate, .declared(observation))
        XCTAssertNotEqual(candidate.temporal.publicationDate, .declared(claimed))
        // Conservative classification is not removal: same story, same identity, same canonical value.
        XCTAssertEqual(candidate.headline, "Declared 2100")
        XCTAssertEqual(candidate.originRevisionID, record.originRevisionID)
        XCTAssertEqual(candidate.timestamp, CandidateTimestamp(value: observation, kind: .authored))
        XCTAssertEqual(candidate.temporal.observedAt, observation)
        XCTAssertEqual(candidate.temporal.modificationDate, .absent)
        XCTAssertTrue(candidate.temporal.inconsistencies.isEmpty)
        XCTAssertEqual(candidate.temporal.nature, .unknown)
    }

    /// TX-07D: an accepted instant LATER than the observation instant is not a publication date the story may
    /// be treated as having. It is never reported as `.declared`: the evidence states the absence of a usable
    /// date and keeps the raw instant for diagnosis. The same rule governs the change instant.
    func testAcceptedInstantLaterThanTheObservationYieldsNoUsableDate() {
        let observation = Date(timeIntervalSince1970: 1_700_000_000)
        let later = observation.addingTimeInterval(10)
        let evidence = CandidateTemporalEvidence(observedAt: observation,
            acceptedAuthoredAt: later, acceptedModifiedAt: later.addingTimeInterval(5))
        // The raw canonical values are retained exactly as accepted.
        XCTAssertEqual(evidence.acceptedAuthoredAt, later)
        XCTAssertEqual(evidence.acceptedModifiedAt, later.addingTimeInterval(5))
        XCTAssertNotEqual(evidence.publicationDate, .declared(later))
        XCTAssertNotEqual(evidence.modificationDate, .declared(later.addingTimeInterval(5)))
        XCTAssertEqual(evidence.publicationDate, .absent)
        XCTAssertEqual(evidence.modificationDate, .absent)
        XCTAssertTrue(evidence.inconsistencies.isEmpty)
        // "no usable date" is not "no declaration": the two absences stay distinguishable from the raw value.
        let undeclared = CandidateTemporalEvidence(observedAt: observation)
        XCTAssertNil(undeclared.acceptedAuthoredAt)
        XCTAssertNil(undeclared.acceptedModifiedAt)
        XCTAssertEqual(undeclared.publicationDate, .absent)
        XCTAssertEqual(undeclared.modificationDate, .absent)
        XCTAssertNotEqual(evidence.acceptedAuthoredAt, undeclared.acceptedAuthoredAt)
        XCTAssertNotEqual(evidence, undeclared)
        // A usable date is still strictly before the observation, and equality stays the ambiguous case.
        XCTAssertEqual(CandidateTemporalEvidence(observedAt: observation,
            acceptedAuthoredAt: observation.addingTimeInterval(-1)).publicationDate,
            .declared(observation.addingTimeInterval(-1)))
        XCTAssertEqual(CandidateTemporalEvidence(observedAt: observation,
            acceptedAuthoredAt: observation).publicationDate, .ambiguousAtObservation(observation))
    }

    /// TX-07D: the same condition reached through real canonical supply. `ContentStore` accepts finite dates
    /// without ordering them against the observation, so a revision whose accepted publication instant is
    /// later than the observation is reachable; the contract reports no usable date, keeps the raw instant,
    /// and the story stays offered under its own identity and ordering key.
    func testCanonicalInstantAfterTheObservationStaysReachableWithNoUsableDate() throws {
        try withProvider { store, provider in
            let source = SourceID()
            let later = time.addingTimeInterval(10)
            let accepted = try insert(1, source: source, into: store, authored: later, modified: later.addingTimeInterval(5),
                observed: time, headline: "Accepted after the observation")
            let other = try insert(2, source: source, into: store, authored: time.addingTimeInterval(-86_400),
                observed: time, headline: "Older declared story")
            let byOrigin = Dictionary(uniqueKeysWithValues: try provider.candidates(for: plan(.main), after: nil,
                examinedCapacity: 2).candidates.map { ($0.originRecordID, $0) })
            let candidate = try XCTUnwrap(byOrigin[accepted.originRecordID])
            // No usable date, no fabricated one, and the raw canonical instant is intact for diagnosis.
            XCTAssertEqual(candidate.temporal.acceptedAuthoredAt, later)
            XCTAssertEqual(candidate.temporal.acceptedModifiedAt, later.addingTimeInterval(5))
            XCTAssertEqual(candidate.temporal.publicationDate, .absent)
            XCTAssertNotEqual(candidate.temporal.publicationDate, .declared(later))
            XCTAssertEqual(candidate.temporal.modificationDate, .absent)
            XCTAssertTrue(candidate.temporal.inconsistencies.isEmpty)
            // Reachable and unchanged: same story, same identity and the same ordering key the supply holds.
            XCTAssertEqual(candidate.originRevisionID, accepted.id)
            XCTAssertEqual(candidate.headline, "Accepted after the observation")
            XCTAssertEqual(candidate.timestamp, CandidateTimestamp(value: later, kind: .authored))
            XCTAssertEqual(candidate.temporal.observedAt, time)
            XCTAssertEqual(byOrigin[other.originRecordID]?.temporal.publicationDate,
                .declared(time.addingTimeInterval(-86_400)))
            // The keyset still walks the whole supply: the next window after the last examined row is empty
            // and exhaustion is confirmed, so nothing was removed from retrieval.
            let first = try provider.candidates(for: plan(.main), after: nil, examinedCapacity: 1)
            XCTAssertEqual(first.candidates.count, 1)
            XCTAssertFalse(first.exhausted)
            let rest = try provider.candidates(for: plan(.main), after: first.nextCursor, examinedCapacity: 1)
            XCTAssertEqual(rest.candidates.map(\.originRecordID), [other.originRecordID])
            XCTAssertFalse(rest.exhausted)
            let end = try provider.candidates(for: plan(.main), after: rest.nextCursor, examinedCapacity: 1)
            XCTAssertTrue(end.candidates.isEmpty)
            XCTAssertTrue(end.exhausted)
        }
    }

    /// TX-07D: a material edit is a new revision and adds no fabricated publication date. The ordering key
    /// stays the declared publication instant, so an edit alone never manufactures novelty, and the
    /// evidence keeps stating what was observed about *that* revision. The observation a candidate states
    /// is `origin_revisions.observed_at` — the revision's own, written once by `ContentStore.insertRevision`
    /// and never rewritten (immutable revisions) — not `origin_records.last_observed_at`, which is the
    /// record's separate clock and moves on every admission.
    func testMaterialEditKeepsTheDeclaredPublicationDateAndManufacturesNoNovelty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        let content = ContentStore(database: db), provider = CandidateProvider(contentStore: content)
        let sourceID = SourceID(), originID = origin(700)
        let object = ExternalIdentity(connectorKind: .syndication, namespace: "tx07d", value: "story", role: .object)
        let declared = time.addingTimeInterval(-30 * 86_400)
        func revision(_ body: String, observed: Date) -> OriginRevision {
            OriginRevision(id: OriginRevisionID(), originRecordID: originID, externalVersionIdentity: nil,
                headline: "Story", summary: "Summary", bodyText: body, authoredAt: declared, modifiedAt: nil,
                observedAt: observed, language: "en", primaryLink: nil, searchProjection: nil, providerID: nil)
        }
        // The revision carries its own observation and the record its own clock, exactly as
        // AcquisitionAdmissionStore stamps a newly admitted revision: both receive the admission instant.
        func admit(_ value: OriginRevision, expected: ContentStore.CurrentRevisionExpectation) throws {
            try content.commitCanonicalChange(.init(recordID: originID, externalObjectIdentity: object,
                revision: value, mediaCandidates: [], availability: .available, observedAt: value.observedAt,
                expectedCurrent: expected, currentUpdate: .useSuppliedRevision,
                membershipMutations: [.upsert(sourceID: sourceID, kind: .direct, observedAt: value.observedAt)],
                fingerprintGeneration: 2, bodySourceElement: "content"))
        }
        let first = revision("Original body", observed: time)
        try admit(first, expected: .none)
        let feedPlan = try plan(.main)
        let before = try XCTUnwrap(provider.candidates(for: feedPlan, after: nil, examinedCapacity: 1).candidates.first)
        XCTAssertEqual(before.originRevisionID, first.id)
        XCTAssertEqual(before.temporal.publicationDate, .declared(declared))
        XCTAssertEqual(before.temporal.observedAt, time)
        let edit = revision("Substantially revised body", observed: time.addingTimeInterval(3600))
        try admit(edit, expected: .revision(first.id))
        let after = try XCTUnwrap(provider.candidates(for: feedPlan, after: nil, examinedCapacity: 1).candidates.first)
        XCTAssertEqual(after.originRevisionID, edit.id)
        XCTAssertNotEqual(after.originRevisionID, before.originRevisionID)
        XCTAssertEqual(after.temporal.publicationDate, .declared(declared))
        XCTAssertEqual(after.timestamp, before.timestamp)
        XCTAssertEqual(after.temporal.observedAt, time.addingTimeInterval(3600))
        XCTAssertNotEqual(after.temporal.observedAt, before.temporal.observedAt)
        XCTAssertNil(after.temporal.acceptedModifiedAt)
        // Both canonical facts, stated by their own owner: the record's clock followed the admission, and
        // the revision's observation (the one the candidate reports) is the one that revision was stamped with.
        XCTAssertEqual(try content.originRecord(id: originID)?.lastObservedAt, time.addingTimeInterval(3600))
        XCTAssertEqual(try content.currentRevision(originRecordID: originID)?.observedAt, time.addingTimeInterval(3600))
        XCTAssertEqual(try content.currentRevision(originRecordID: originID), edit)
    }

    func testSourceFilteringPreservesExaminedCountAndRelativeOrder() throws {
        try withProvider { store, provider in
            let a = SourceID(), b = SourceID()
            let v1 = try insert(1, source: a, into: store)
            try insert(2, source: b, into: store)
            let v3 = try insert(3, source: a, into: store)
            let result = try provider.candidates(for: plan(.source(a)), after: nil, examinedCapacity: 4)
            XCTAssertEqual(result.candidates.map(\.originRecordID), [origin(3), origin(1)])
            XCTAssertEqual(result.candidates.map(\.originRevisionID), [v3.id, v1.id])
            XCTAssertEqual(result.examinedCount, 3)
            XCTAssertEqual(result.nextCursor, CandidateSupplyCursor(sortDate: time, originRecordID: origin(1)))
            XCTAssertTrue(result.exhausted)
        }
    }

    func testSparseSourceDoesNotRefillAndEditorialCursorProgresses() throws {
        try withProvider { store, provider in
            let a = SourceID(), b = SourceID()
            for n in 1...4 { try insert(n, source: n <= 2 ? a : b, into: store) }
            let sourcePlan = try plan(.source(a))
            let first = try provider.candidates(for: sourcePlan, after: nil, examinedCapacity: 2)
            XCTAssertEqual(first.candidates, [])
            XCTAssertEqual(first.examinedCount, 2)
            XCTAssertFalse(first.exhausted)
            XCTAssertEqual(first.nextCursor, CandidateSupplyCursor(sortDate: time, originRecordID: origin(3)))
            let second = try provider.candidates(for: sourcePlan, after: first.nextCursor, examinedCapacity: 2)
            XCTAssertEqual(second.candidates.map(\.originRecordID), [origin(2), origin(1)])
            XCTAssertEqual(second.examinedCount, 2)
            XCTAssertEqual(second.nextCursor, CandidateSupplyCursor(sortDate: time, originRecordID: origin(1)))
            XCTAssertNotEqual(second.nextCursor, first.nextCursor)
            XCTAssertFalse(second.exhausted)
            let empty = try provider.candidates(for: sourcePlan, after: second.nextCursor, examinedCapacity: 2)
            XCTAssertEqual(empty.candidates, [])
            XCTAssertEqual(empty.examinedCount, 0)
            XCTAssertNil(empty.nextCursor)
            XCTAssertTrue(empty.exhausted)
        }
    }

    func testMainCursorIsExclusiveWithNoDuplicateOrMissingCandidate() throws {
        try withProvider { store, provider in
            let source = SourceID()
            for n in 1...5 { try insert(n, source: source, into: store, observed: time.addingTimeInterval(Double(n / 2))) }
            let main = try plan(.main)
            let first = try provider.candidates(for: main, after: nil, examinedCapacity: 2)
            XCTAssertEqual(first.candidates.map(\.originRecordID), [origin(5), origin(4)])
            XCTAssertEqual(first.nextCursor, CandidateSupplyCursor(sortDate: time.addingTimeInterval(2), originRecordID: origin(4)))
            let second = try provider.candidates(for: main, after: first.nextCursor, examinedCapacity: 2)
            let third = try provider.candidates(for: main, after: second.nextCursor, examinedCapacity: 2)
            let all = (first.candidates + second.candidates + third.candidates).map(\.originRecordID)
            XCTAssertEqual(all, [5, 4, 3, 2, 1].map(origin))
            XCTAssertEqual(Set(all).count, 5)
            XCTAssertEqual(third.examinedCount, 1)
            XCTAssertTrue(third.exhausted)
        }
    }

    func testLocalSearchReadsReadableTextAndPreservesBoundedCursor() throws {
        try withProvider { store, provider in
            let source = SourceID()
            try insert(1, source: source, into: store, headline: "<b>Café</b>")
            try insert(2, source: source, into: store, headline: "other")
            let search = try plan(.search(XCTUnwrap(SearchContext(query: " CAFE "))))
            let first = try provider.candidates(for: search, after: nil, examinedCapacity: 1)
            XCTAssertTrue(first.candidates.isEmpty)
            XCTAssertEqual(first.examinedCount, 1)
            XCTAssertFalse(first.exhausted)
            let second = try provider.candidates(for: search, after: first.nextCursor, examinedCapacity: 1)
            XCTAssertEqual(second.candidates.map(\.originRecordID), [origin(1)])
            let end = try provider.candidates(for: search, after: second.nextCursor, examinedCapacity: 1)
            XCTAssertTrue(end.exhausted)
            XCTAssertTrue(end.candidates.isEmpty)
            XCTAssertEqual(search.context.request, .search(SearchContext(query: " CAFE ")!))
        }
    }

    func testFactualPersistenceValidationErrorsPropagate() throws {
        try withProvider { _, provider in
            for request in [FeedContextRequest.main, .source(SourceID())] {
                for capacity in [0, -1] {
                    XCTAssertThrowsError(try provider.candidates(for: plan(request), after: nil, examinedCapacity: capacity)) {
                        XCTAssertEqual($0 as? ContentStoreError, .invalidCapacity)
                    }
                }
                let cursor = CandidateSupplyCursor(sortDate: Date(timeIntervalSince1970: .nan), originRecordID: origin(1))
                XCTAssertThrowsError(try provider.candidates(for: plan(request), after: cursor, examinedCapacity: 1)) {
                    XCTAssertEqual($0 as? ContentStoreError, .invalidRepresentation("cursor.sort_date"))
                }
            }
        }
    }

    /// Regresses K-15 across real canonical supply, editorial exposure and atomic publication guard.
    func testK15BodyOnlyEditCreatesNewPublishedOccurrenceAcrossRealStores() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        let content = ContentStore(database: db), publisher = PublicationStore(database: db)
        let provider = CandidateProvider(contentStore: content)
        let originID = origin(415), sourceID = SourceID()
        let object = ExternalIdentity(connectorKind: .syndication, namespace: "k15", value: "article", role: .object)
        let link = try XCTUnwrap(URL(string: "https://example.test/article"))
        func revision(_ text: String) -> OriginRevision {
            OriginRevision(id: OriginRevisionID(), originRecordID: originID, externalVersionIdentity: nil,
                headline: "Unchanged title", summary: "Same summary", bodyText: text,
                authoredAt: nil, modifiedAt: nil, observedAt: self.time, language: nil,
                primaryLink: link, searchProjection: nil, providerID: nil)
        }
        func admit(_ value: OriginRevision, expected: ContentStore.CurrentRevisionExpectation) throws {
            try content.commitCanonicalChange(.init(recordID: originID, externalObjectIdentity: object,
                revision: value, mediaCandidates: [], availability: .available, observedAt: self.time,
                expectedCurrent: expected, currentUpdate: .useSuppliedRevision,
                membershipMutations: [.upsert(sourceID: sourceID, kind: .direct, observedAt: self.time)],
                fingerprintGeneration: 2, bodySourceElement: "content"))
        }
        func card(_ revisionID: OriginRevisionID) -> PublicationStore.CardRecord {
            .init(id: PublicationCardID(), originRecordID: originID, originRevisionID: revisionID,
                sourceID: sourceID, providerID: nil, sourceDisplayName: "Feed", providerDisplayName: nil,
                contentEntityID: nil, contentClusterID: nil, title: "Unchanged title",
                primaryText: "Same summary", timestampValue: nil, timestampKind: nil,
                mediaKey: nil, mediaPixelWidth: nil, mediaPixelHeight: nil, mediaMimeType: nil,
                renderLayout: "textOnly", renderMediaAspectRatio: nil,
                primaryActionKind: "externalURL", primaryActionReference: link.absoluteString)
        }
        let a = revision("Body A")
        try admit(a, expected: .none)
        let feedPlan = try plan(.main)
        let initial = try XCTUnwrap(provider.candidates(for: feedPlan, after: nil,
            examinedCapacity: 5).candidates.first)
        XCTAssertEqual(initial.declaredBody, "Body A")
        let edition = PublicationStore.EditionRecord(id: FeedEditionID(),
            editorialRevision: feedPlan.revision, publicationSchemaVersion: 1, selectionSeed: 100,
            createdAt: self.time)
        let first = card(a.id)
        let initialSegment = PublicationStore.SegmentRecord(id: FeedSegmentID(),
            editionID: edition.id, ordinal: 0, segmentSeed: 10,
            publicationSchemaVersion: 1, createdAt: self.time, cardIDs: [first.id])
        try publisher.createEdition(edition, firstSegment: initialSegment, cards: [first])
        let oldKeys = try publisher.exposure(editionID: edition.id, originIDs: [originID])
        XCTAssertEqual(oldKeys.publishedMaterialKeys[originID]?.count, 1)

        let b = revision("Body B")
        try admit(b, expected: .revision(a.id))
        let window = try provider.candidates(for: feedPlan, after: nil, examinedCapacity: 5)
        let next = try XCTUnwrap(window.candidates.first)
        XCTAssertEqual(next.originRevisionID, b.id)
        XCTAssertEqual(next.summary, initial.summary)
        XCTAssertEqual(next.declaredBody, "Body B")

        func selection() throws -> SelectionResult {
            let exposure = try publisher.exposure(editionID: edition.id, originIDs: [originID])
            let snapshot = try XCTUnwrap(SelectionExposureSnapshot(requestedOriginIDs: [originID],
                publishedOriginIDs: exposure.publishedOriginIDs,
                publishedMaterialKeys: exposure.publishedMaterialKeys,
                unseenOriginIDs: exposure.unseenOriginIDs))
            let p = feedPlan.revision
            let policy = ResolvedSelectionPolicy(contextKey: p.contextKey,
                userSelectionVersion: p.userSelectionVersion,
                eligibilityPolicyVersion: p.eligibilityPolicyVersion,
                scoringPolicyVersion: p.scoringPolicyVersion,
                sequencingPolicyVersion: p.sequencingPolicyVersion,
                exposurePolicyVersion: p.exposurePolicyVersion,
                selectionSchemaVersion: p.selectionSchemaVersion,
                eligibility: .structuralOnly, scoring: .equal,
                sequencing: .recencyDescending, exposure: .excludePublishedMaterial)
            return try SelectionEngine().select(plan: feedPlan, policy: policy,
                window: window, exposure: snapshot)
        }
        XCTAssertEqual(try selection().orderedCandidates.map(\.originRevisionID), [b.id])
        let second = card(b.id)
        let nextSegment = PublicationStore.SegmentRecord(id: FeedSegmentID(),
            editionID: edition.id, ordinal: 1, segmentSeed: 11,
            publicationSchemaVersion: 1, createdAt: self.time, cardIDs: [second.id])
        try publisher.appendSegment(nextSegment, cards: [second],
            expectingTailCardID: first.id, recurrence: .whenMaterialChanged)
        XCTAssertEqual(try publisher.exposure(editionID: edition.id,
            originIDs: [originID]).publishedMaterialKeys[originID]?.count, 2)
        XCTAssertEqual(try publisher.card(id: first.id), first)
        XCTAssertEqual(try publisher.card(id: second.id), second)
        XCTAssertTrue(try selection().orderedCandidates.isEmpty,
            "after publication, the same body must not publish again")
    }



    func testK15LegacyEnrichmentMatchesGeneration2BodyAndRealRemovalPublishes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        let content = ContentStore(database: db), publisher = PublicationStore(database: db)
        let provider = CandidateProvider(contentStore: content), source = SourceID()
        let originID = origin(416), stamp = self.time
        let object = ExternalIdentity(connectorKind: .syndication, namespace: "legacy-atom",
            value: "published", role: .object)
        let link = try XCTUnwrap(URL(string: "https://example.test/legacy"))
        let legacy = OriginRevision(id: OriginRevisionID(), originRecordID: originID,
            externalVersionIdentity: nil, headline: "Unchanged", summary: "S",
            bodyText: nil, authoredAt: stamp, modifiedAt: nil, observedAt: stamp,
            language: nil, primaryLink: link, searchProjection: nil, providerID: nil)
        try content.commitCanonicalChange(.init(recordID: originID,
            externalObjectIdentity: object, revision: legacy, mediaCandidates: [],
            availability: .available, observedAt: stamp,
            expectedCurrent: .none, currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: source, kind: .direct, observedAt: stamp)],
            fingerprintGeneration: 1))
        let plan = try plan(.main)
        let edition = PublicationStore.EditionRecord(id: FeedEditionID(),
            editorialRevision: plan.revision, publicationSchemaVersion: 1,
            selectionSeed: 1, createdAt: stamp)
        func card(_ rev: OriginRevisionID) -> PublicationStore.CardRecord {
            .init(id: PublicationCardID(), originRecordID: originID, originRevisionID: rev,
                sourceID: source, providerID: nil, sourceDisplayName: "Legacy",
                providerDisplayName: nil, contentEntityID: nil, contentClusterID: nil,
                title: "Unchanged", primaryText: "S", timestampValue: nil, timestampKind: nil,
                mediaKey: nil, mediaPixelWidth: nil, mediaPixelHeight: nil, mediaMimeType: nil,
                renderLayout: "textOnly", renderMediaAspectRatio: nil,
                primaryActionKind: "externalURL", primaryActionReference: link.absoluteString)
        }
        func segment(_ card: PublicationStore.CardRecord, ordinal: UInt64) -> PublicationStore.SegmentRecord {
            .init(id: FeedSegmentID(), editionID: edition.id, ordinal: ordinal,
                segmentSeed: ordinal + 1, publicationSchemaVersion: 1,
                createdAt: stamp, cardIDs: [card.id])
        }
        let published = card(legacy.id)
        try publisher.createEdition(edition, firstSegment: segment(published, ordinal: 0), cards: [published])
        let historicalKey = try XCTUnwrap(publisher.exposure(
            editionID: edition.id, originIDs: [originID]).publishedMaterialKeys[originID]?.first)
        XCTAssertEqual(historicalKey, SelectionExposureSnapshot.materialKey(headline: "Unchanged", summary: "S"))

        // Same original card, first body observation: real admission enriches its generation-1 revision.
        let target = try AcquisitionTargetStore(database: db).register(id: AcquisitionTargetID(),
            connectorKind: .syndication, authorizedSources: [source])
        let observed = AcquisitionAdmissionStore.ObservationCommand(
            objectIdentity: object, versionIdentity: nil, precedence: .makeCurrent,
            availability: .available, headline: legacy.headline, summary: legacy.summary,
            bodyText: "A", authoredAt: legacy.authoredAt, modifiedAt: legacy.modifiedAt,
            observedAt: stamp.addingTimeInterval(1), language: legacy.language,
            primaryLink: link, searchProjection: nil, providerID: nil,
            memberships: [.init(sourceID: source, kind: .direct)], mediaCandidates: [],
            fingerprintGeneration: 2, bodySourceElement: "content")
        let receipt = try AcquisitionAdmissionStore(database: db).admit(.init(
            targetID: target.id, targetGeneration: target.generation,
            expectedCheckpointRevision: target.checkpointRevision,
            observations: [observed], nextCheckpoint: nil))
        XCTAssertFalse(receipt.selectableSupplyChanged)
        XCTAssertEqual(try content.currentRevision(originRecordID: originID), legacy)
        XCTAssertEqual(try publisher.card(id: published.id), published)

        let observedKey = try XCTUnwrap(publisher.exposure(editionID: edition.id,
            originIDs: [originID]).publishedMaterialKeys[originID]?.first)
        XCTAssertEqual(observedKey, SelectionExposureSnapshot.materialKey(headline: "Unchanged",
            summary: "S", declaredBody: "A", bodyObserved: true))
        XCTAssertNotEqual(observedKey, historicalKey,
            "the derived comparison reflects observed evidence without mutating published history")
        let version2Same = OriginRevision(id: OriginRevisionID(), originRecordID: originID,
            externalVersionIdentity: nil, headline: "Unchanged", summary: "S",
            bodyText: "A", authoredAt: stamp, modifiedAt: stamp.addingTimeInterval(2),
            observedAt: stamp.addingTimeInterval(2), language: nil, primaryLink: link,
            searchProjection: nil, providerID: nil)
        func admit(_ revision: OriginRevision, previous: OriginRevisionID, sourceElement: String?) throws {
            try content.commitCanonicalChange(.init(recordID: originID,
                externalObjectIdentity: object, revision: revision, mediaCandidates: [],
                availability: .available, observedAt: revision.observedAt,
                expectedCurrent: .revision(previous), currentUpdate: .useSuppliedRevision,
                membershipMutations: [.upsert(sourceID: source, kind: .direct,
                    observedAt: revision.observedAt)], fingerprintGeneration: 2,
                bodySourceElement: sourceElement))
        }
        try admit(version2Same, previous: legacy.id, sourceElement: "content")
        let sameWindow = try provider.candidates(for: plan, after: nil, examinedCapacity: 5)
        let sameCandidate = try XCTUnwrap(sameWindow.candidates.first)
        XCTAssertEqual(sameCandidate.declaredBody, "A")
        XCTAssertTrue(sameCandidate.bodyObserved)
        let p = plan.revision
        let policy = ResolvedSelectionPolicy(contextKey: p.contextKey,
            userSelectionVersion: p.userSelectionVersion, eligibilityPolicyVersion: p.eligibilityPolicyVersion,
            scoringPolicyVersion: p.scoringPolicyVersion, sequencingPolicyVersion: p.sequencingPolicyVersion,
            exposurePolicyVersion: p.exposurePolicyVersion, selectionSchemaVersion: p.selectionSchemaVersion,
            eligibility: .structuralOnly, scoring: .equal, sequencing: .recencyDescending,
            exposure: .excludePublishedMaterial)
        func select(_ window: CandidateSupplyWindow) throws -> SelectionResult {
            let e = try publisher.exposure(editionID: edition.id, originIDs: [originID])
            let snapshot = try XCTUnwrap(SelectionExposureSnapshot(requestedOriginIDs: [originID],
                publishedOriginIDs: e.publishedOriginIDs, publishedMaterialKeys: e.publishedMaterialKeys,
                unseenOriginIDs: e.unseenOriginIDs))
            return try SelectionEngine().select(plan: plan, policy: policy, window: window, exposure: snapshot)
        }
        XCTAssertTrue(try select(sameWindow).orderedCandidates.isEmpty,
            "timestamp-only Atom update with identical A is not a new publication")
        let duplicate = card(version2Same.id)
        XCTAssertThrowsError(try publisher.appendSegment(segment(duplicate, ordinal: 1),
            cards: [duplicate], expectingTailCardID: published.id, recurrence: .whenMaterialChanged)) {
            XCTAssertEqual($0 as? PublicationStoreError, .duplicateOriginInEdition)
        }
        XCTAssertEqual(try publisher.segments(editionID: edition.id).flatMap(\.cardIDs), [published.id])

        let removed = OriginRevision(id: OriginRevisionID(), originRecordID: originID,
            externalVersionIdentity: nil, headline: "Unchanged", summary: "S",
            bodyText: nil, authoredAt: stamp, modifiedAt: stamp.addingTimeInterval(3),
            observedAt: stamp.addingTimeInterval(3), language: nil, primaryLink: link,
            searchProjection: nil, providerID: nil)
        try admit(removed, previous: version2Same.id, sourceElement: nil)
        let removedWindow = try provider.candidates(for: plan, after: nil, examinedCapacity: 5)
        let removedCandidate = try XCTUnwrap(removedWindow.candidates.first)
        XCTAssertNil(removedCandidate.declaredBody)
        XCTAssertTrue(removedCandidate.bodyObserved, "observed absence is not legacy unknown")
        XCTAssertEqual(try select(removedWindow).orderedCandidates.map(\.originRevisionID), [removed.id])
        let changed = card(removed.id)
        try publisher.appendSegment(segment(changed, ordinal: 1), cards: [changed],
            expectingTailCardID: published.id, recurrence: .whenMaterialChanged)
        XCTAssertEqual(try publisher.card(id: published.id), published)
        XCTAssertEqual(try publisher.segments(editionID: edition.id).flatMap(\.cardIDs),
            [published.id, changed.id])
    }

    func testK15Generation2BodyRemovedAfterIntermediateEditIsMaterial() throws {
        let originID = origin(417), stamp = CandidateTimestamp(value: self.time, kind: .authored)
        let edited = Candidate(originRecordID: originID, originRevisionID: OriginRevisionID(),
            headline: "Same", summary: "S", timestamp: stamp, language: nil, providerID: nil,
            declaredBody: "B", bodyObserved: true)
        let removed = Candidate(originRecordID: originID, originRevisionID: OriginRevisionID(),
            headline: "Same", summary: "S", timestamp: stamp, language: nil, providerID: nil,
            bodyObserved: true)
        let unknown = SelectionExposureSnapshot.materialKey(headline: "Same", summary: "S")
        let absent = SelectionExposureSnapshot.materialKey(headline: "Same", summary: "S",
            bodyObserved: true)
        let bodyA = SelectionExposureSnapshot.materialKey(headline: "Same", summary: "S",
            declaredBody: "A", bodyObserved: true)
        let bodyB = SelectionExposureSnapshot.materialKey(headline: "Same", summary: "S",
            declaredBody: "B", bodyObserved: true)
        XCTAssertNotEqual(absent, unknown)
        XCTAssertNotEqual(absent, bodyA)
        XCTAssertNotEqual(absent, bodyB)
        XCTAssertEqual(edited.declaredBody, "B")
        XCTAssertNil(removed.declaredBody)
        XCTAssertTrue(removed.bodyObserved)
        let plan = try plan(.main), p = plan.revision
        let policy = ResolvedSelectionPolicy(contextKey: p.contextKey,
            userSelectionVersion: p.userSelectionVersion, eligibilityPolicyVersion: p.eligibilityPolicyVersion,
            scoringPolicyVersion: p.scoringPolicyVersion, sequencingPolicyVersion: p.sequencingPolicyVersion,
            exposurePolicyVersion: p.exposurePolicyVersion, selectionSchemaVersion: p.selectionSchemaVersion,
            eligibility: .structuralOnly, scoring: .equal, sequencing: .recencyDescending,
            exposure: .excludePublishedMaterial)
        let published = try XCTUnwrap(SelectionExposureSnapshot(
            requestedOriginIDs: [originID], publishedOriginIDs: [originID],
            publishedMaterialKeys: [originID: [bodyA, bodyB]]))
        let window = CandidateSupplyWindow(candidates: [removed], examinedCount: 1,
            nextCursor: nil, exhausted: true)
        XCTAssertEqual(try SelectionEngine().select(plan: plan, policy: policy,
            window: window, exposure: published).orderedCandidates, [removed])
    }

    // MARK: - TX-05D: the subject a story's own document declared

    private func declared(_ label: String) -> String {
        StoryDeclaredSubjects([DeclaredSubjectClaim(surface: .rssItemCategory, label: label)!])!.canonicalText
    }

    /// A candidate carries the subject its own document declared, rebuilt from canonical supply. Two
    /// stories of one source that declared different subjects never share an identity — the Source's
    /// taxonomy does not fill it — and two sources that wrote incompatible labels are never unified.
    func testTopicEvidenceComesFromTheStorysOwnDeclarationAndNotFromItsSource() throws {
        try withProvider { store, provider in
            let shared = SourceID(), other = SourceID()
            let declared = try insert(1, source: shared, into: store, nonMaterialText: self.declared("Futebol"))
            let different = try insert(2, source: shared, into: store, nonMaterialText: self.declared("Premier League"))
            let incompatible = try insert(3, source: other, into: store, nonMaterialText: self.declared("sports"))
            let sameWords = try insert(4, source: other, into: store, nonMaterialText: self.declared("futebol"))
            let silent = try insert(5, source: other, into: store)
            let candidates = try provider.candidates(for: plan(.main), after: nil, examinedCapacity: 5).candidates
            let byOrigin = Dictionary(uniqueKeysWithValues: candidates.map { ($0.originRecordID,$0) })
            func topics(_ revision: OriginRevision) throws -> CandidateTopicEvidence {
                try XCTUnwrap(byOrigin[revision.originRecordID]).topics
            }
            let first = try topics(declared)
            XCTAssertEqual(first.identities.map(\.key),["futebol"])
            XCTAssertEqual(first.identities.map(\.surface),[.rssItemCategory])
            XCTAssertNil(first.identities.first?.scheme)
            XCTAssertEqual(first.equivalence,.declaredLabelOnly)
            XCTAssertEqual(first.declaredSubjects.map(\.label),["Futebol"])
            XCTAssertFalse(first.sharesDeclaredSubject(with: try topics(different)))
            XCTAssertFalse(first.sharesDeclaredSubject(with: try topics(incompatible)))
            XCTAssertTrue(first.sharesDeclaredSubject(with: try topics(sameWords)))
            // A story whose document declared nothing has no topic evidence, and a value another producer
            // stored in that slot is not a declaration either.
            let absent = try topics(silent)
            XCTAssertTrue(absent.isAbsent)
            XCTAssertTrue(absent.identities.isEmpty)
            XCTAssertFalse(absent.sharesDeclaredSubject(with: first))
            XCTAssertEqual(Candidate(originRecordID: origin(9),originRevisionID: OriginRevisionID(),
                headline: nil,summary: nil,timestamp: CandidateTimestamp(value: time,kind: .observed),
                language: nil,providerID: nil).topics,.absent)
        }
    }

    /// The identity a candidate exposes is the one canonical supply holds, admitted through the real
    /// admission path: the projection is reconstructed from the canonical fact, never restated.
    func testTopicIdentityIsDeliveredFromAdmittedCanonicalEvidence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        let content = ContentStore(database: db), source = SourceID()
        let target = try AcquisitionTargetStore(database: db).register(id: AcquisitionTargetID(),
            connectorKind: .syndication, authorizedSources: [source])
        let subjects = try XCTUnwrap(StoryDeclaredSubjects([DeclaredSubjectClaim(surface: .atomEntryCategory,
            scheme: "urn:example:subjects", label: "Music")!]))
        let observation = AcquisitionAdmissionStore.ObservationCommand(
            objectIdentity: ExternalIdentity(connectorKind: .syndication,namespace: "admitted",value: "a",role: .object),
            versionIdentity: nil,precedence: .makeCurrent,availability: .available,headline: "Admitted",summary: nil,
            bodyText: nil,authoredAt: time,modifiedAt: nil,observedAt: time,language: nil,primaryLink: nil,
            searchProjection: nil,providerID: nil,memberships: [.init(sourceID: source,kind: .direct)],
            mediaCandidates: [], declaredSubjects: subjects)
        _ = try AcquisitionAdmissionStore(database: db).admit(.init(targetID: target.id,
            targetGeneration: target.generation,expectedCheckpointRevision: target.checkpointRevision,
            observations: [observation],nextCheckpoint: nil))
        let candidate = try XCTUnwrap(CandidateProvider(contentStore: content)
            .candidates(for: try plan(.main), after: nil, examinedCapacity: 4).candidates.first)
        XCTAssertEqual(candidate.topics.declaredSubjects,subjects.claims)
        XCTAssertEqual(candidate.topics.identities,subjects.identities)
        XCTAssertEqual(candidate.topics.identities.map(\.key),["music"])
        XCTAssertEqual(candidate.topics.equivalence,.declaredLabelOnly)
    }

}
