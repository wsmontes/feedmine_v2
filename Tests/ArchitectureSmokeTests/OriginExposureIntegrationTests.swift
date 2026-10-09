// H3 integration: real unversioned RSS admission, origin exposure and durable publication.
import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineSyndication
import FeedMineEditorial
import FeedMinePublication
import FeedMineRuntime

final class OriginExposureIntegrationTests: XCTestCase {
    private static func prepare(_ selection: SelectionResult) -> LocalPreparedPublication {
        .init(inputs: selection.orderedCandidates.map {
            .init(origin: .init(originRecordID: $0.originRecordID,originRevisionID: $0.originRevisionID,
                sourceID: nil,providerID: $0.providerID,sourceDisplayName: "RSS",providerDisplayName: nil),
                contentEntityID: nil,contentClusterID: nil,primaryAction: .localContentDetail,presentation: .textOnly)
        },cardIDs: selection.orderedCandidates.map { _ in PublicationCardID() })
    }

    func test3R5RealRSSStableGUIDEditsAndMediaOnlyRevisionNeverRepeatAfterReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = RuntimeDatabaseLocation(directory: root)
        let target = AcquisitionTargetID(), source = SourceID(), edition = FeedEditionID()
        let configuration = try XCTUnwrap(SyndicationTargetConfiguration(targetID: target,
            endpoint: URL(string: "https://example.invalid/feed")!,memberships: [.init(sourceID: source,kind: .direct)]))
        let context = FeedContext(request: .main), version = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(),contextKey: context.key,catalogGeneration: .init(rawValue: 1),
            userSelectionVersion: version,eligibilityPolicyVersion: version,scoringPolicyVersion: version,
            sequencingPolicyVersion: version,exposurePolicyVersion: version,selectionSchemaVersion: .init(rawValue: 1))
        let plan = try XCTUnwrap(FeedPlan(context: context,revision: revision))
        let policy = ResolvedSelectionPolicy(contextKey: context.key,userSelectionVersion: version,eligibilityPolicyVersion: version,
            scoringPolicyVersion: version,sequencingPolicyVersion: version,exposurePolicyVersion: version,
            selectionSchemaVersion: revision.selectionSchemaVersion,eligibility: .structuralOnly,scoring: .equal,
            sequencing: .recencyDescending,exposure: .excludePublishedRevisions)
        func admit(_ database: RuntimeDatabase,title: String,description: String,media: Bool = false) throws -> OriginRevision {
            let xml = """
                <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel><title>Feed</title><item>
                <guid isPermaLink="false">stable-guid</guid><title>\(title)</title><description>\(description)</description>
                \(media ? "<media:thumbnail url=\"https://example.invalid/image.png\" width=\"20\" height=\"30\"/>" : "")
                </item></channel></rss>
                """
            let translated = try SyndicationTranslator().translate(data: Data(xml.utf8),configuration: configuration,
                observedAt: Date(timeIntervalSince1970: 1234),startIndex: 0,itemCapacity: 1)
            XCTAssertTrue(translated.rejections.isEmpty)
            let authority = try XCTUnwrap(AcquisitionTargetAuthority(database: database).target(id: target))
            let batch = try XCTUnwrap(AcquisitionBatch(targetID: target,targetGeneration: authority.generation,
                expectedCheckpointRevision: authority.checkpointRevision,observations: translated.observations,nextCheckpoint: nil))
            let receipt = try AdmissionPolicy(database: database).admit(batch)
            XCTAssertTrue(receipt.selectableSupplyChanged)
            let records = try ContentStore(database: database).candidateWindow(sourceID: source,after: nil,examinedCapacity: 10).records
            XCTAssertEqual(records.count,1)
            return try XCTUnwrap(ContentStore(database: database).currentRevision(originRecordID: records[0].originRecordID))
        }
        func assertExcluded(_ database: RuntimeDatabase) throws {
            let outcome = try LocalProductionSlice(database: database).run(.init(plan: plan,policy: policy,editionID: edition,
                after: nil,examinedCapacity: 2,segmentID: FeedSegmentID(),segmentSeed: 2,segmentCreatedAt: Date(timeIntervalSince1970: 1300))) { _ in
                XCTFail("Exposed origin must never reach preparation"); return .init(inputs: [],cardIDs: [])
            }
            guard case .advancedWithoutPublication(let progress) = outcome else { return XCTFail("Expected origin exclusion") }
            XCTAssertEqual(progress.examinedCount,1); XCTAssertTrue(progress.exhausted); XCTAssertNotNil(progress.nextCursor)
        }
        let original: PublicationStore.CardRecord
        let oldRevision: OriginRevision
        do {
            let database = try RuntimeDatabase(location: location)
            _ = try AcquisitionTargetAuthority(database: database).register(id: target,connectorKind: .syndication, authorizedSources: [source])
            oldRevision = try admit(database,title: "First",description: "Original")
            let initial = try InitialProductionSlice(database: database).run(.init(plan: plan,policy: policy,examinedCapacity: 1,
                editionID: edition,publicationSchemaVersion: .init(rawValue: 1),selectionSeed: 1,
                editionCreatedAt: Date(timeIntervalSince1970: 1250),segmentID: FeedSegmentID(),segmentSeed: 2,
                segmentCreatedAt: Date(timeIntervalSince1970: 1251),anchorPlacement: .top,checkpointedAt: Date(timeIntervalSince1970: 1252)),prepare: Self.prepare)
            guard case .published(_,let receipt) = initial else { return XCTFail("Expected initial publication") }
            original = try XCTUnwrap(PublicationStore(database: database).card(id: receipt.cardIDs[0]))
            let edited = try admit(database,title: "Edited",description: "Changed description")
            XCTAssertEqual(edited.originRecordID,oldRevision.originRecordID); XCTAssertNotEqual(edited.id,oldRevision.id)
            XCTAssertNil(edited.externalVersionIdentity)
            try assertExcluded(database)
            XCTAssertEqual(try PublicationStore(database: database).card(id: original.id),original)
        }
        let reopened = try RuntimeDatabase(location: location)
        try assertExcluded(reopened)
        let beforeMedia = try XCTUnwrap(ContentStore(database: reopened).currentRevision(originRecordID: oldRevision.originRecordID))
        let withMedia = try admit(reopened,title: "Edited",description: "Changed description",media: true)
        XCTAssertEqual(withMedia.originRecordID,oldRevision.originRecordID); XCTAssertNotEqual(withMedia.id,beforeMedia.id)
        XCTAssertEqual(withMedia.headline,beforeMedia.headline); XCTAssertEqual(withMedia.summary,beforeMedia.summary)
        XCTAssertEqual(try ContentStore(database: reopened).mediaCandidates(originRevisionID: withMedia.id)?.count,1)
        try assertExcluded(reopened)
        let store = PublicationStore(database: reopened)
        XCTAssertEqual(try store.card(id: original.id),original)
        XCTAssertEqual(try store.segments(editionID: edition).flatMap(\.cardIDs),[original.id])
        XCTAssertEqual(try ContentStore(database: reopened).originRevision(id: oldRevision.id),oldRevision)
        let other = FeedEditionID()
        let window = try CandidateProvider(contentStore: ContentStore(database: reopened)).candidates(for: plan,after: nil,examinedCapacity: 2)
        let exposure = try XCTUnwrap(SelectionExposureSnapshot(requestedOriginIDs: window.candidates.map(\.originRecordID),publishedOriginIDs: []))
        let selected = try SelectionEngine().select(plan: plan,policy: policy,window: window,exposure: exposure)
        let prepared = Self.prepare(selected)
        let outcome = try PublicationCoordinator(database: reopened).createEdition(.init(selection: selected,
            drafts: PublicationPreparation.drafts(selection: selected,inputs: prepared.inputs),editionID: other,
            publicationSchemaVersion: .init(rawValue: 1),selectionSeed: 3,editionCreatedAt: Date(timeIntervalSince1970: 1400),
            segmentID: FeedSegmentID(),segmentSeed: 4,segmentCreatedAt: Date(timeIntervalSince1970: 1401),cardIDs: prepared.cardIDs))
        guard case .published(let receipt) = outcome else { return XCTFail("Expected independent Edition publication") }
        XCTAssertEqual(try store.card(id: receipt.cardIDs[0])?.originRevisionID,withMedia.id)
        XCTAssertEqual(try store.segments(editionID: edition).flatMap(\.cardIDs),[original.id])
        XCTAssertEqual(try SessionStore(database: reopened).checkpoint()?.cardID,original.id)
    }
}
