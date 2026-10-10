//
// File: ReaderCollectionsBackend.swift
// Module: FeedMineComposition
//
// Responsibility:
// The collections surface's backend (declared in FeedMineUI) over the reader's own library, plus the read the
// app needs to open a collection as a feed: exactly the keys the collection holds.
//
// Does not own: storage (Persistence), the session that a collection feed runs in (the app) or any layout.
import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineUI

public struct ReaderCollectionsBackend: CollectionsBackend {
    private let database: RuntimeDatabase

    public init(database: RuntimeDatabase) { self.database = database }

    public func collections() async throws -> [SourceCollectionRow] {
        let library = ReaderLibraryStore(database: database)
        return try library.collections().map { collection in
            SourceCollectionRow(id: collection.id, name: collection.name,
                memberCount: try library.sourceKeys(inCollection: collection.id).count)
        }
    }

    public func create(name: String) async throws -> String {
        try ReaderLibraryStore(database: database).createCollection(named: name).id
    }

    public func rename(id: String, name: String) async throws {
        _ = try ReaderLibraryStore(database: database).renameCollection(id: id, to: name)
    }

    public func delete(id: String) async throws {
        _ = try ReaderLibraryStore(database: database).deleteCollection(id: id)
    }

    public func reorder(ids: [String]) async throws {
        _ = try ReaderLibraryStore(database: database).reorderCollections(ids)
    }

    public func members(of id: String) async throws -> [SourceCollectionMemberRow] {
        try ReaderLibraryStore(database: database).sourceKeys(inCollection: id)
            .sorted()
            .map(SourceCollectionMemberRow.row(forKey:))
    }

    public func setMembership(sourceKey: String, collectionID: String, included: Bool) async throws {
        try ReaderLibraryStore(database: database).setCollectionMembership(sourceKey: sourceKey,
            collectionID: collectionID, included: included, at: Date())
    }
}
