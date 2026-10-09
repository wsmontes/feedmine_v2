import Foundation
import XCTest
import FeedMineDomain
import FeedMineEditorial
import FeedMineMedia
import FeedMinePublication
import FeedMinePersistence
import FeedMineRuntime

final class PublicationPreparationTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==")!
    private func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!
    }
    private func candidate(_ number: Int) -> Candidate {
        Candidate(originRecordID: OriginRecordID(rawValue: uuid(number)),
            originRevisionID: OriginRevisionID(rawValue: uuid(100 + number)),
            headline: number == 1 ? nil : number == 2 ? "" : " e\u{301}\n ",
            summary: number == 1 ? "" : number == 2 ? nil : " Exact Summary ",
            timestamp: CandidateTimestamp(value: Date(timeIntervalSince1970: Double(100 - number) + 0.25),
                kind: number % 2 == 0 ? .observed : .authored), language: nil,
            providerID: number == 1 ? nil : ProviderID(rawValue: uuid(200 + number)))
    }
    private func selection(_ candidates: [Candidate]) -> SelectionResult {
        SelectionResult(editorialRevision: EditorialRevision(id: EditorialRevisionID(rawValue: uuid(800)),
            contextKey: ContextKey(request: .main), catalogGeneration: CatalogGeneration(rawValue: 1),
            userSelectionVersion: PolicyVersion(rawValue: 1), eligibilityPolicyVersion: PolicyVersion(rawValue: 1),
            scoringPolicyVersion: PolicyVersion(rawValue: 1), sequencingPolicyVersion: PolicyVersion(rawValue: 1),
            exposurePolicyVersion: PolicyVersion(rawValue: 1), selectionSchemaVersion: SelectionSchemaVersion(rawValue: 1)),
            orderedCandidates: candidates,
            supplyReport: SelectionSupplyReport(examinedCount: 41, nextCursor: nil, exhausted: false))
    }
    private func origin(_ candidate: Candidate, mismatch: String? = nil) -> PublishedOrigin {
        PublishedOrigin(originRecordID: mismatch == "record" ? OriginRecordID(rawValue: uuid(999)) : candidate.originRecordID,
            originRevisionID: mismatch == "revision" ? OriginRevisionID(rawValue: uuid(999)) : candidate.originRevisionID,
            sourceID: SourceID(rawValue: uuid(300)),
            providerID: mismatch == "provider" ? ProviderID(rawValue: uuid(999)) : candidate.providerID,
            sourceDisplayName: " Frozen Source ", providerDisplayName: "")
    }
    private func input(_ candidate: Candidate, presentation: PublicationPresentation = .textOnly,
        mismatch: String? = nil) -> PublicationPreparationInput {
        PublicationPreparationInput(origin: origin(candidate, mismatch: mismatch),
            contentEntityID: ContentEntityID(rawValue: uuid(400)),
            contentClusterID: ContentClusterID(rawValue: uuid(500)), primaryAction: .localContentDetail,
            presentation: presentation)
    }
    private func root() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func mediaCandidate(_ revision: OriginRevisionID) throws -> MediaCandidate {
        try XCTUnwrap(MediaCandidate(id: MediaCandidateID(rawValue: uuid(600)), originRevisionID: revision,
            role: .cardVisual, mediaClass: .image, remoteURL: URL(string: "https://definitely.invalid/no-request")!,
            declaredMimeType: "wrong/type", declaredPixelWidth: 90, declaredPixelHeight: 10))
    }
    private func prepared(_ candidate: Candidate, input: MediaPreparationInput = .unavailable,
        directory: URL? = nil) throws -> MediaPreparationResult {
        try MediaPreparation(assetDirectory: directory ?? root()).prepare(
            candidate: mediaCandidate(candidate.originRevisionID), input: input)
    }
    private func assertError(_ expected: PublicationPreparationError, _ body: () throws -> Void,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual($0 as? PublicationPreparationError, expected, file: file, line: line)
        }
    }

    func testTextOnlyUsesExactOrderedSelectionWithoutAnyMediaWork() throws {
        let candidates = [candidate(3), candidate(2), candidate(1)]
        let inputs = candidates.map { input($0) }
        let drafts = try PublicationPreparation.drafts(selection: selection(candidates), inputs: inputs)
        XCTAssertEqual(drafts.count, 3)
        XCTAssertEqual(drafts.map(\.origin.originRecordID), candidates.map(\.originRecordID))
        XCTAssertEqual(drafts[0].text.title?.utf8.map { $0 }, Array(" e\u{301}\n ".utf8))
        XCTAssertEqual(drafts[0].text.primaryText, " Exact Summary ")
        XCTAssertEqual(drafts[1].text.title, "")
        XCTAssertNil(drafts[1].text.primaryText)
        XCTAssertNil(drafts[2].text.title)
        XCTAssertEqual(drafts[2].text.primaryText, "")
        XCTAssertEqual(drafts.map { $0.timestamp?.kind }, [.authored, .observed, .authored])
        XCTAssertEqual(drafts.map { $0.timestamp?.value }, [97.25, 98.25, 99.25].map { Date(timeIntervalSince1970: $0) })
        for (draft, input) in zip(drafts, inputs) {
            XCTAssertEqual(draft.origin, input.origin)
            XCTAssertEqual(draft.contentEntityID, ContentEntityID(rawValue: uuid(400)))
            XCTAssertEqual(draft.contentClusterID, ContentClusterID(rawValue: uuid(500)))
            XCTAssertEqual(draft.primaryAction, .localContentDetail)
            XCTAssertEqual(draft.media, .none)
            XCTAssertEqual(draft.renderContract.layout, .textOnly)
            XCTAssertNil(draft.renderContract.mediaAspectRatio)
        }
    }

    func testDirectCandidateIsCopiedExactlyWithoutSecondNormalization() throws {
        let c = Candidate(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(),
            headline: "<em>Explicit raw title</em>", summary: "&lt;b&gt;already decoded once &amp; literal",
            timestamp: .init(value: Date(timeIntervalSince1970: 1), kind: .observed), language: nil, providerID: nil)
        let draft = try XCTUnwrap(PublicationPreparation.drafts(selection: selection([c]), inputs: [input(c)]).first)
        XCTAssertEqual(draft.text.title?.utf8.map { $0 }, c.headline?.utf8.map { $0 })
        XCTAssertEqual(draft.text.primaryText?.utf8.map { $0 }, c.summary?.utf8.map { $0 })
    }

    func testEmptyCountMismatchAndPositionalOriginAlignment() throws {
        XCTAssertEqual(try PublicationPreparation.drafts(selection: selection([]), inputs: []), [])
        let a = candidate(1), b = candidate(2)
        assertError(.inputCountMismatch) {
            _ = try PublicationPreparation.drafts(selection: selection([a]), inputs: [])
        }
        assertError(.inputCountMismatch) {
            _ = try PublicationPreparation.drafts(selection: selection([]), inputs: [input(a)])
        }
        for mismatch in ["record", "revision", "provider"] {
            assertError(.originMismatch(index: 1)) {
                _ = try PublicationPreparation.drafts(selection: selection([a, b]), inputs: [input(a), input(b, mismatch: mismatch)])
            }
        }
        assertError(.originMismatch(index: 0)) {
            _ = try PublicationPreparation.drafts(selection: selection([a, b]), inputs: [input(b), input(a)])
        }
    }

    func testImagesUseRealPreparedMetadataAndExplicitHeroOrThumbnailLayout() throws {
        let candidate = candidate(2), result = try prepared(candidate, input: .bytes(png))
        guard case .usable(let asset) = result.state else { return XCTFail("Expected usable") }
        for layout in [PublishedCardLayout.hero, .thumbnail] {
            let draft = try XCTUnwrap(PublicationPreparation.drafts(selection: selection([candidate]),
                inputs: [input(candidate, presentation: .image(result, layout: layout))]).first)
            XCTAssertEqual(draft.media.primary?.key, asset.key)
            XCTAssertEqual(draft.media.primary?.pixelWidth, 2)
            XCTAssertEqual(draft.media.primary?.pixelHeight, 3)
            XCTAssertEqual(draft.media.primary?.mimeType, "image/png")
            XCTAssertEqual(draft.renderContract.layout, layout)
            XCTAssertEqual(draft.renderContract.mediaAspectRatio, 2.0 / 3.0)
            XCTAssertEqual(draft.text.title, "")
            XCTAssertNil(draft.text.primaryText)
            XCTAssertEqual(draft.primaryAction, .localContentDetail)
        }
    }

    func testMediaRevisionMismatchAndTextOnlyImageLayoutAreRejected() throws {
        let a = candidate(1), b = candidate(2), result = try prepared(a, input: .bytes(png))
        assertError(.mediaRevisionMismatch(index: 0)) {
            _ = try PublicationPreparation.drafts(selection: selection([b]), inputs: [input(b, presentation: .image(result, layout: .hero))])
        }
        assertError(.invalidImageLayout(index: 0)) {
            _ = try PublicationPreparation.drafts(selection: selection([a]), inputs: [input(a, presentation: .image(result, layout: .textOnly))])
        }
    }

    func testUnavailableAndUnsuitableRequireExplicitTextOnlyChoice() throws {
        let candidate = candidate(1)
        for localInput in [MediaPreparationInput.unavailable, .bytes(Data("not an image".utf8))] {
            let result = try prepared(candidate, input: localInput)
            assertError(.mediaNotUsable(index: 0)) {
                _ = try PublicationPreparation.drafts(selection: selection([candidate]), inputs: [input(candidate, presentation: .image(result, layout: .thumbnail))])
            }
            let drafts = try PublicationPreparation.drafts(selection: selection([candidate]), inputs: [input(candidate)])
            XCTAssertEqual(drafts.count, 1)
            XCTAssertEqual(drafts[0].media, .none)
            XCTAssertEqual(drafts[0].renderContract.layout, .textOnly)
        }
    }

    func testLateLocalMediaCreatesFutureOccurrenceWithoutChangingEarlierTextOnlyHistory() throws {
        let directory = root(), candidate = candidate(2), selection = selection([candidate])
        let location = RuntimeDatabaseLocation(directory: directory.appendingPathComponent("runtime"))
        let editionID = FeedEditionID(rawValue: uuid(900)), firstID = PublicationCardID(rawValue: uuid(901)), nextID = PublicationCardID(rawValue: uuid(902))
        let original: PublicationStore.CardRecord
        let preparedKey: PublishedMediaKey
        do {
            let database = try RuntimeDatabase(location: location), coordinator = PublicationCoordinator(database: database)
            let firstDrafts = try PublicationPreparation.drafts(selection: selection, inputs: [input(candidate)])
            let first = try coordinator.createEdition(.init(selection: selection, drafts: firstDrafts,
                editionID: editionID, publicationSchemaVersion: PublicationSchemaVersion(rawValue: 1),
                selectionSeed: 11, editionCreatedAt: Date(timeIntervalSince1970: 200),
                segmentID: FeedSegmentID(rawValue: uuid(910)), segmentSeed: 12,
                segmentCreatedAt: Date(timeIntervalSince1970: 201), cardIDs: [firstID]))
            guard case .published = first else { return XCTFail("Expected first publication") }
            original = try XCTUnwrap(PublicationStore(database: database).card(id: firstID))
            XCTAssertEqual(original.renderLayout, "textOnly")
            XCTAssertNil(original.mediaKey)
            let result = try prepared(candidate, input: .bytes(png), directory: directory.appendingPathComponent("assets"))
            guard case .usable(let asset) = result.state else { return XCTFail("Expected usable") }
            preparedKey = asset.key
            let laterDrafts = try PublicationPreparation.drafts(selection: selection,
                inputs: [input(candidate, presentation: .image(result, layout: .thumbnail))])
            let later = try coordinator.createEdition(.init(selection: selection, drafts: laterDrafts,
                editionID: FeedEditionID(rawValue: uuid(903)), publicationSchemaVersion: PublicationSchemaVersion(rawValue: 1),
                selectionSeed: 14, editionCreatedAt: Date(timeIntervalSince1970: 202), segmentID: FeedSegmentID(rawValue: uuid(911)), segmentSeed: 13,
                segmentCreatedAt: Date(timeIntervalSince1970: 202), cardIDs: [nextID]))
            guard case .published(let receipt) = later else { return XCTFail("Expected later publication") }
            XCTAssertEqual(receipt.segmentOrdinal, 0)
            XCTAssertEqual(try PublicationStore(database: database).card(id: firstID), original)
        }
        let store = PublicationStore(database: try RuntimeDatabase(location: location))
        XCTAssertEqual(try store.card(id: firstID), original)
        let later = try XCTUnwrap(store.card(id: nextID))
        XCTAssertEqual(later.originRecordID, original.originRecordID)
        XCTAssertEqual(later.originRevisionID, original.originRevisionID)
        XCTAssertEqual(later.mediaKey, preparedKey.rawValue)
        XCTAssertEqual(later.renderLayout, "thumbnail")
        XCTAssertEqual(later.mediaPixelWidth, 2)
        XCTAssertEqual(later.mediaPixelHeight, 3)
        XCTAssertNotEqual(later.id, original.id)
        XCTAssertEqual(try store.segments(editionID: editionID).flatMap(\.cardIDs), [firstID])
        XCTAssertEqual(try store.segments(editionID: FeedEditionID(rawValue: uuid(903))).flatMap(\.cardIDs), [nextID])
    }
}
