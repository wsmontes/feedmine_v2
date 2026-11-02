import Foundation
import XCTest
import GRDB
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
@testable import FeedMineComposition

final class FM59DiscoveryVarietyTests: XCTestCase {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fm59-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func catalogue(in root: URL, revision: Int64 = 5) throws -> URL {
        let url = try makeCatalogue(in: root, sources: 7, revision: revision)
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: """
                UPDATE catalog_source SET media_kind='audio' WHERE id=2;
                UPDATE catalog_source SET media_kind='video' WHERE id=3;
                UPDATE catalog_source SET language='en' WHERE id=4;
                UPDATE catalog_source SET default_enabled=0 WHERE id=5;
                UPDATE catalog_source SET language=NULL WHERE id=6;
                INSERT INTO catalog_node (id,key,parent_id,name,kind) VALUES (2,'topics/sport',NULL,'Sport',0);
                UPDATE catalog_placement SET node_id=2,node_name='Sport' WHERE source_id=7;
                UPDATE catalog_metadata SET value='2' WHERE key='node_count';
                """)
        }
        return url
    }

    private var profile: ReaderDiscoveryProfile {
        .init(languages: ["pt"], topicNodeKeys: ["topics/science"])
    }
    private var expected: Set<SourceID> {
        Set((0..<3).map { LegacyCatalogImport.sourceID(forKey: "https://exemplo.pt/feed\($0)") })
    }
    private func manifest(_ url: URL, revision: Int, sources: Int) throws -> Data {
        let bytes = try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        return try CatalogManifest(revision: revision, sourceCount: sources, fileCount: 1,
            files: [.init(path: "catalog.sqlite", bytes: bytes, sha256: CatalogManifest.sha256(ofFile: url))]).encoded()
    }
    private func snapshot(catalogue: URL, root: URL, installation: CatalogInstallation? = nil) throws
        -> (SyndicationAcquisitionSnapshot, ReaderDiscoveryTraversal, FeedContext) {
        let context = FeedContext(request: .main, filter: ReaderFilter(languages: ["pt"]))
        let traversal = ReaderDiscoveryTraversal(builder: ReaderDiscoveryBuilder(catalogURL: catalogue),
            profile: profile, contextKey: context.key, installation: installation)
        let database = try RuntimeDatabase(location: .init(directory: root.appendingPathComponent("runtime")))
        let transport = URLSession(configuration: .ephemeral)
        addTeardownBlock { transport.invalidateAndCancel() }
        let acquisition = try SyndicationAcquisitionSnapshot(database: database, registrations: [], session: transport,
            redirectCapacity: 0, discovery: traversal, installation: installation)
        return (acquisition, traversal, context)
    }
    private func exhaust(_ acquisition: SyndicationAcquisitionSnapshot, context: FeedContext) throws {
        for _ in 0..<12 {
            guard let page = try acquisition.advanceDiscovery(for: context, examinedCapacity: 2) else { return }
            if page.exhausted { return }
        }
        XCTFail("Seven-source fixture must finish bounded catalogue examination")
    }

    func testPreviewOffersEveryAllowedKindWithoutRelaxingLanguageTopicOrEnablement() throws {
        let url = try catalogue(in: root())
        let entries = try ReaderDiscoveryBuilder(catalogURL: url).pool(for: profile, limit: 20).entries
        XCTAssertEqual(Set(entries.map(\.source.id)), expected,
            "A Portuguese science reader must discover real text/audio/video suppliers, not English, unknown, disabled or sport-only suppliers")
    }

    func testPagedDiscoveryMaterializesVideoAcquisitionWithoutManualSubscription() throws {
        let root = try root(), url = try catalogue(in: root.appendingPathComponent("catalogue"))
        let (acquisition, traversal, context) = try snapshot(catalogue: url, root: root)
        try exhaust(acquisition, context: context)
        XCTAssertEqual(Set(traversal.entries.map(\.source.id)), expected)
        let targetIDs = Set(try acquisition.eligibleTargets(for: context).map(\.id))
        let video = try XCTUnwrap(LegacyCatalogImport.entry(LegacyCatalogReader(catalogURL: url)
            .source(key: "https://exemplo.pt/feed2")!))
        XCTAssertTrue(targetIDs.contains(video.targetID), "Video must reach the actual acquisition target set")
        XCTAssertEqual(targetIDs.count, expected.count, "Item/placement counts must not inflate supplier coverage")
    }

    func testCataloguePromotionKeepsNewVideoReachableAndPreservesExistingSourceIdentity() throws {
        let root = try root()
        let initial = try makeCatalogue(in: root.appendingPathComponent("initial"), sources: 1, revision: 5)
        let descriptor = root.appendingPathComponent("initial.json")
        try manifest(initial, revision: 5, sources: 1).write(to: descriptor)
        let installation = CatalogInstallation(directory: root.appendingPathComponent("installed"),
            bundledCatalogue: initial, bundledManifest: descriptor)
        let active = try XCTUnwrap(installation.bootstrap())
        let (acquisition, traversal, context) = try snapshot(catalogue: active.catalogueURL, root: root,
            installation: installation)
        try exhaust(acquisition, context: context)
        let original = try XCTUnwrap(traversal.entries.first)
        let promoted = try catalogue(in: root.appendingPathComponent("promoted"), revision: 6)
        guard case .installed = installation.install(manifestData: try manifest(promoted, revision: 6, sources: 7),
            catalogue: promoted) else { return XCTFail("Valid local test catalogue must promote") }
        try exhaust(acquisition, context: context)
        XCTAssertEqual(Set(traversal.entries.map(\.source.id)), expected,
            "Promotion cannot reconstruct a text/audio-only automatic discovery policy")
        let retained = try XCTUnwrap(traversal.entries.first { $0.principal == original.principal })
        XCTAssertEqual(retained.source.id, original.source.id)
        XCTAssertEqual(retained.targetID, original.targetID)
        XCTAssertEqual(retained.bindingID, original.bindingID)
        XCTAssertEqual(retained.endpoint, original.endpoint)
    }

    func testExplicitKindAndSourceScopesRemainNarrowAndGenuineScarcityIsNotInvented() throws {
        let root = try root(), url = try catalogue(in: root.appendingPathComponent("catalogue"))
        let videoOnly = try ReaderDiscoveryBuilder(catalogURL: url, mediaKinds: ["video"])
            .pool(for: profile, limit: 50).entries
        XCTAssertEqual(videoOnly.map(\.source.id), [LegacyCatalogImport.sourceID(forKey: "https://exemplo.pt/feed2")])
        let absent = try ReaderDiscoveryBuilder(catalogURL: url).pool(for: .init(languages: ["ja"]), limit: 50)
        XCTAssertTrue(absent.entries.isEmpty, "Do not replace a scarce language with plentiful Portuguese")
        let (acquisition, traversal, _) = try snapshot(catalogue: url, root: root)
        let source = FeedContext(request: .source(expected.first!), filter: ReaderFilter(languages: ["pt"]))
        XCTAssertNil(try acquisition.advanceDiscovery(for: source, examinedCapacity: 20))
        XCTAssertTrue(traversal.entries.isEmpty, "A source visit must not expand automatic discovery")
        let search = FeedContext(request: .search(SearchContext(query: "science")!))
        XCTAssertNil(try acquisition.advanceDiscovery(for: search, examinedCapacity: 20))
    }

    func testRichPreviewIsNotOnlyTheFirstPodcastKeyPrefix() throws {
        let root = try root()
        let url = try makeCatalogue(in: root.appendingPathComponent("rich"), sources: 560)
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            for id in 1...560 {
                let kind = id <= 500 ? "audio" : (id <= 530 ? "text" : "video")
                let key = String(format: "https://supplier-%04d.test/feed", id)
                try db.execute(sql: "UPDATE catalog_source SET key=?,declared_url=?,request_url=?,media_kind=?,quality_score=90 WHERE id=?",
                    arguments: [key, key, key, kind, id])
            }
        }
        let entries = try ReaderDiscoveryBuilder(catalogURL: url).pool(for: profile, limit: 50).entries
        let reader = try LegacyCatalogReader(catalogURL: url)
        let kinds = try Set(entries.compactMap { try reader.source(key: $0.principal)?.mediaKind })
        XCTAssertEqual(Set(entries.map(\.source.id)).count, 50)
        XCTAssertEqual(kinds, ["text", "audio", "video"],
            "Equal-quality eligible suppliers beyond a prolific podcast key prefix must get opening opportunities")
    }
}

extension FM59DiscoveryVarietyTests {
    func testBroadProfileExploresSourceTopicsWithoutPretendingTheyAreItemSubjects() throws {
        let root = try root()
        let url = try makeCatalogue(in: root.appendingPathComponent("topics"), sources: 80)
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO catalog_node (id,key,parent_id,name,kind) VALUES (2,'topics/sport',NULL,'Sport',0);
                UPDATE catalog_placement SET node_id=2,node_name='Sport' WHERE source_id>60;
                UPDATE catalog_metadata SET value='2' WHERE key='node_count';
                """)
            for id in 1...80 {
                let key = String(format: "https://supplier-%04d.test/feed", id)
                try db.execute(sql: "UPDATE catalog_source SET key=?,declared_url=?,request_url=?,quality_score=90 WHERE id=?",
                    arguments: [key, key, key, id])
            }
        }
        let entries = try ReaderDiscoveryBuilder(catalogURL: url)
            .pool(for: .init(languages: ["pt"]), limit: 20).entries
        XCTAssertEqual(Set(entries.flatMap(\.nodeKeys)), ["topics/science", "topics/sport"],
            "A broad reader's source opportunities must not come from just the first topic's prolific key prefix")
        // These are source placements only. No canonical item or item-topic evidence is manufactured here.
    }
}
