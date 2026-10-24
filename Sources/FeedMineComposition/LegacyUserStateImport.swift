//
// File: LegacyUserStateImport.swift
// Module: FeedMineComposition
//
// Responsibility:
// Carry the reader's own state from V1's `user.sqlite` into V2's library, for the categories this build
// supports: personal sources (`imported_source`), bookmark boxes (`bookmark_list`) and source collections
// (`source_collection` / `source_collection_member`). It reads the V1 file read-only and never writes, moves or
// deletes anything beside it.
//
// Every row it does not carry is reported with a reason in the same transaction as the rows it does carry.
// Saved articles, smart feeds and curated feeds stay in V1 and are counted as temporarily inaccessible; the
// durable receipt says so and the first-open notice tells the reader.
//
// Does not own: the V1 database (Persistence reads it), the library rows (the store writes them) or the notice
// surface (the app draws it).
import Foundation
import FeedMineDomain
import FeedMinePersistence

public struct LegacyUserStateImport: Sendable {
    public struct Report: Hashable, Sendable {
        public let inserted: ReaderLibraryImportReport
        public let schema: LegacyUserStateSchema
        public let skips: [ReaderLegacySkip]

        public var skippedSavedArticles: Int {
            skips.filter { $0.category == "savedArticles" }.reduce(0) { $0 + $1.count }
        }
    }

    /// The explicit id map. A V1 integer is never reused as a V2 identity: it names the row it came from, so a
    /// repeated import finds its own work and adds nothing.
    static func listID(_ legacy: Int64) -> String { "v1:list:\(legacy)" }
    static func collectionID(_ legacy: Int64) -> String { "v1:collection:\(legacy)" }

    /// The V1 generation this build reads is the one V1's own `UserStateStore` migrations created (schema
    /// `v1_bookmarks` … `v11_user_operation`, the shape `BookmarkStore` writes). A file with the tables but an
    /// older column set is reported as `unsupportedV1Schema`; it is never queried with modern assumptions.
    @discardableResult
    public static func run(reader: LegacyUserStateReader, into database: RuntimeDatabase,
        at date: Date = Date()) throws -> Report {
        let store = ReaderLibraryStore(database: database)
        let schema = try reader.schemaVariant()
        guard schema == .modern else {
            let skip = ReaderLegacySkip(category: "schema", reason: "unsupportedV1Schema", count: 1)
            let inserted = try store.apply(ReaderLibraryImport(),
                legacyUpgrade: .init(sourcePath: reader.url.path, status: .unsupported, skips: [skip]), at: date)
            return Report(inserted: inserted, schema: schema, skips: [skip])
        }

        var skips: [ReaderLegacySkip] = []

        // Boxes: V1's default box *is* V2's default box, so it is not imported again — its identity is the one
        // the card control already writes to. Every other box keeps V1's name and its own order. A persistent
        // search list has no V2 surface (no V1 UI ever created one); the box is reported, not invented.
        let lists = try reader.bookmarkLists()
        var importedLists: [ReaderLibraryImport.BookmarkList] = []
        var deadPersistentSearchLists = 0
        for list in lists {
            if list.carriesDeadPersistentSearch { deadPersistentSearchLists += 1 }
            guard !list.isDefault, !list.carriesDeadPersistentSearch else { continue }
            importedLists.append(.init(id: listID(list.id), name: list.name))
        }
        if deadPersistentSearchLists > 0 {
            skips.append(.init(category: "boxes", reason: "persistentSearchListUnsupported",
                count: deadPersistentSearchLists))
        }

        // Personal sources: identity is canonical, `request_url` is what is fetched. A row whose address cannot
        // be fetched is reported instead of being written as a key V2 could never resolve.
        let sourceRows = try reader.importedSources()
        let sourceRowCount = try reader.importedSourceCount()
        var importedSources: [ReaderLibraryImport.Source] = []
        var invalidSources = 0
        for source in sourceRows {
            guard !source.identity.isEmpty, FeedAddress.isValidHTTPURL(source.requestURL),
                FeedAddress.isValidHTTPURL(source.identity) else {
                invalidSources += 1
                continue
            }
            importedSources.append(.init(key: source.identity, requestURL: source.requestURL,
                title: source.title.isEmpty ? source.requestURL : source.title, select: source.enabled))
        }
        if invalidSources > 0 {
            skips.append(.init(category: "sources", reason: "invalidSourceAddress", count: invalidSources))
        }
        if sourceRowCount > sourceRows.count {
            skips.append(.init(category: "sources", reason: "unreadableImportedSourceRow",
                count: sourceRowCount - sourceRows.count))
        }

        // Collections carry over whole. Members are canonical identities; a member whose identity is not a
        // fetchable address cannot name a V2 source and is reported.
        let collections = try reader.collections()
        var importedCollections: [ReaderLibraryImport.Collection] = []
        var invalidCollectionMembers = 0
        for collection in collections {
            let members = collection.memberKeys.filter { key in
                let valid = !key.isEmpty && FeedAddress.isValidHTTPURL(key)
                if !valid { invalidCollectionMembers += 1 }
                return valid
            }
            importedCollections.append(.init(id: collectionID(collection.id), name: collection.name,
                memberKeys: members))
        }
        if invalidCollectionMembers > 0 {
            skips.append(.init(category: "collections", reason: "invalidSourceIdentity",
                count: invalidCollectionMembers))
        }

        // V1 state this build does not import, stated instead of dropped in silence. Saved articles are counted
        // from `bookmark_item`, the membership authority; they remain in `user.sqlite`.
        let savedArticles = try reader.bookmarkItemCounts().values.reduce(0, +)
        if savedArticles > 0 {
            skips.append(.init(category: "savedArticles", reason: "notImportedInThisBuild", count: savedArticles))
        }
        let smartFeedCount = try reader.smartFeeds().count
        if smartFeedCount > 0 {
            skips.append(.init(category: "smartFeeds", reason: "notImportedInThisBuild", count: smartFeedCount))
        }
        let curatedCount = try reader.curatedFeedCount()
        if curatedCount > 0 {
            skips.append(.init(category: "curatedFeeds", reason: "notImportedInThisBuild", count: curatedCount))
        }

        let payload = ReaderLibraryImport(bookmarkLists: importedLists, sources: importedSources,
            collections: importedCollections)
        let inserted = try store.apply(payload,
            legacyUpgrade: .init(sourcePath: reader.url.path, status: .completed, skips: skips), at: date)
        return Report(inserted: inserted, schema: schema, skips: skips)
    }
}
