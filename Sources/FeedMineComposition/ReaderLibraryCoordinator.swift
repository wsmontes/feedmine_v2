//
// File: ReaderLibraryCoordinator.swift
// Module: FeedMineComposition
//
// Responsibility:
// The reader's library as the UI sees it: named boxes, collections and saved presets, plus the two product
// operations V1 offered from a context — "Save as Smart Bookmark" and "Collect these sources".
//
// Activation is deliberately **not** here. A preset's content is a T6 `ContextKey`, and the only thing that can
// activate one is the session that owns the active context (the app), so this boundary hands out the identity
// and the app performs an ordinary transition with it. No second feed engine grows behind the reader.
//
// Does not own: storage (Persistence), the active context or acquisition (the app), or any layout.
import Foundation
import FeedMineDomain
import FeedMinePersistence

public struct ReaderLibraryCoordinator: Sendable {
    private let database: RuntimeDatabase
    private let store: ReaderLibraryStore

    public init(database: RuntimeDatabase) {
        self.database = database
        store = ReaderLibraryStore(database: database)
    }

    // MARK: - Boxes

    public func bookmarkLists() throws -> [ReaderBookmarkList] { try store.bookmarkLists() }

    @discardableResult
    public func createBookmarkList(named name: String) throws -> ReaderBookmarkList {
        try store.createBookmarkList(named: name)
    }

    @discardableResult
    public func renameBookmarkList(id: String, to name: String) throws -> ReaderBookmarkList {
        try store.renameBookmarkList(id: id, to: name)
    }

    /// Deleting a box is refused for the default one, which is where the card control puts a bookmark.
    @discardableResult
    public func deleteBookmarkList(id: String) throws -> Bool { try store.deleteBookmarkList(id: id) }

    @discardableResult
    public func reorderBookmarkLists(_ ids: [String]) throws -> [ReaderBookmarkList] {
        try store.reorderBookmarkLists(ids)
    }

    public func setBookmarkMembership(cardID: PublicationCardID, listID: String, included: Bool,
        at date: Date = Date()) throws {
        try store.setBookmarkMembership(cardID: cardID, listID: listID, included: included, at: date)
    }

    public func bookmarkedCardIDs(inList listID: String) throws -> Set<PublicationCardID> {
        try store.bookmarkedCardIDs(inList: listID)
    }

    public func bookmarkListIDs(forCard cardID: PublicationCardID) throws -> Set<String> {
        try store.bookmarkListIDs(forCard: cardID)
    }

    // MARK: - Collections

    public func collections() throws -> [ReaderCollection] { try store.collections() }

    @discardableResult
    public func createCollection(named name: String) throws -> ReaderCollection {
        try store.createCollection(named: name)
    }

    @discardableResult
    public func renameCollection(id: String, to name: String) throws -> ReaderCollection {
        try store.renameCollection(id: id, to: name)
    }

    /// V1's "Collect these sources": the collection and every membership land in one transaction, so an
    /// interrupted action never leaves a half-filled collection behind.
    @discardableResult
    public func collectSources(named name: String, sourceKeys: [String]) throws -> ReaderCollection {
        guard let normalized = ReaderLibraryRules.normalizedName(name) else {
            throw ReaderLibraryError.invalidName
        }
        let id = ReaderLibraryStore.mintID()
        let payload = ReaderLibraryImport(collections: [
            .init(id: id, name: normalized, memberKeys: sourceKeys),
        ])
        _ = try store.apply(payload, at: Date())
        guard let created = try store.collections().first(where: { $0.id == id }) else {
            throw ReaderLibraryError.missingLibraryItem
        }
        return created
    }

    @discardableResult
    public func deleteCollection(id: String) throws -> Bool { try store.deleteCollection(id: id) }

    @discardableResult
    public func reorderCollections(_ ids: [String]) throws -> [ReaderCollection] {
        try store.reorderCollections(ids)
    }

    public func setCollectionMembership(sourceKey: String, collectionID: String, included: Bool,
        at date: Date = Date()) throws {
        try store.setCollectionMembership(sourceKey: sourceKey, collectionID: collectionID, included: included,
            at: date)
    }

    @discardableResult
    public func addToCollection(id: String, sourceKeys: [String]) throws -> Int {
        try store.addToCollection(id: id, sourceKeys: sourceKeys, at: Date())
    }

    public func sourceKeys(inCollection id: String) throws -> Set<String> {
        try store.sourceKeys(inCollection: id)
    }

    // MARK: - Presets

    public func presets() throws -> [ReaderPreset] { try store.presets() }

    public func preset(id: String) throws -> ReaderPreset? { try store.presets().first { $0.id == id } }

    /// V1's "Save as Smart Bookmark" and its curated counterpart: the context the reader is on is stored under
    /// a name, and the stored key **names its own preset**, so activating it is an ordinary transition.
    @discardableResult
    public func savePreset(named name: String, kind: ReaderPreset.Kind, from key: ContextKey,
        recipe: FeedRecipeDefinition? = nil) throws -> ReaderPreset {
        let provisional = try store.createPreset(named: name, kind: kind, key: key, recipe: recipe)
        let renamed = ContextKey(request: key.request, preset: provisional.presetID, filter: key.filter,
            searchScope: key.searchScope, identitySchemaVersion: key.identitySchemaVersion)
        guard renamed != provisional.key else { return provisional }
        return try store.replacePresetKey(id: provisional.id, key: renamed)
    }

    /// T11: edits a curated feed — its name, the recipe, and the identity the recipe resolves to, together.
    @discardableResult
    public func updateCuratedPreset(id: String, name: String, key: ContextKey,
        recipe: FeedRecipeDefinition) throws -> ReaderPreset {
        try store.updateCuratedPreset(id: id, name: name, key: key, recipe: recipe)
    }

    @discardableResult
    public func renamePreset(id: String, to name: String) throws -> ReaderPreset {
        try store.renamePreset(id: id, to: name)
    }

    @discardableResult
    public func deletePreset(id: String) throws -> Bool { try store.deletePreset(id: id) }

    @discardableResult
    public func reorderPresets(_ ids: [String]) throws -> [ReaderPreset] { try store.reorderPresets(ids) }

    // MARK: - V1's legacy import

    /// Carries what V2 can represent from a V1 user database. The report states what could not come across.
    @discardableResult
    public func importLegacyUserState(at url: URL, at date: Date = Date()) throws -> LegacyUserStateImport.Report {
        try LegacyUserStateImport.run(reader: LegacyUserStateReader(url: url), into: database, at: date)
    }
}
