//
// File: ReaderBookmarkBoxesBackend.swift
// Module: FeedMineComposition
//
// Responsibility:
// The bookmark-boxes surface's backend (declared in FeedMineUI) implemented over the reader's library and the
// preference that says where a new bookmark lands. Values in, values out; ids stay strings at this boundary.
//
// Does not own: storage (Persistence), the active context (the app) or any layout.
import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineUI

public struct ReaderBookmarkBoxesBackend: BookmarkBoxesBackend {
    private let database: RuntimeDatabase
    /// R02: delivered **after** a durable mutation that can change the bookmark set (a box deletion removes its
    /// memberships). The composition routes it through the same confirmed path a save uses, so one revision fences
    /// every older preparation. Nil — the default — keeps the surface a pure boxes backend.
    private let onConfirmedChange: (@Sendable () async -> Void)?

    public init(database: RuntimeDatabase, onConfirmedChange: (@Sendable () async -> Void)? = nil) {
        self.database = database
        self.onConfirmedChange = onConfirmedChange
    }

    public func boxes() async throws -> [BookmarkBoxRow] {
        let library = ReaderLibraryStore(database: database)
        let lists = try library.bookmarkLists()
        let counts = try library.bookmarkListCounts()
        let preferred = try ReaderPreferencesStore(database: database).load()?.preferredBookmarkListID
        return lists.map { list in
            BookmarkBoxRow(id: list.id, name: list.name, count: counts[list.id] ?? 0,
                isDefault: list.id == ReaderBookmarkList.defaultID,
                isPreferred: preferred == nil ? list.id == ReaderBookmarkList.defaultID : preferred == list.id)
        }
    }

    public func create(name: String) async throws -> String {
        try ReaderLibraryStore(database: database).createBookmarkList(named: name).id
    }

    public func rename(id: String, name: String) async throws {
        _ = try ReaderLibraryStore(database: database).renameBookmarkList(id: id, to: name)
    }

    public func delete(id: String) async throws {
        let removed = try ReaderLibraryStore(database: database).deleteBookmarkList(id: id)
        if removed { await onConfirmedChange?() }
    }

    public func reorder(ids: [String]) async throws {
        _ = try ReaderLibraryStore(database: database).reorderBookmarkLists(ids)
    }

    /// V1's "Default": the box a new bookmark lands in. Deleting the preferred box clears the preference, and
    /// the default box is what nothing-preferred means — so the preference never points at a box that is gone.
    public func setPreferred(id: String?) async throws {
        _ = try ReaderPreferencesStore(database: database).setPreferredBookmarkList(id)
    }
}
