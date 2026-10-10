//
// File: CollectionsStore.swift
// Module: FeedMineUI
//
// Responsibility:
// V1's source collections as observable values plus intents: the list, one collection's members, and the
// intents to create, rename, delete, reorder and change membership. The composition implements the backend.
//
// Does not own: storage (Persistence), acquiring the collection as a feed (the app) or any layout.
import Foundation
import Observation
import FeedMineDomain
import FeedMineRuntime

/// One collection as its row draws it. V1 printed the member count on the row.
public struct SourceCollectionRow: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let memberCount: Int

    public init(id: String, name: String, memberCount: Int) {
        self.id = id; self.name = name; self.memberCount = memberCount
    }
}

/// One member of a collection. The catalog key *is* the feed's address, so the row's second line is V1's:
/// the host the reader recognizes.
public struct SourceCollectionMemberRow: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let host: String

    public init(id: String, title: String, host: String) {
        self.id = id; self.title = title; self.host = host
    }

    /// The row V1 drew: no catalog title is stored with a membership, so the address states itself.
    public static func row(forKey key: String) -> SourceCollectionMemberRow {
        let host = URL(string: key)?.host ?? key
        return SourceCollectionMemberRow(id: key, title: host, host: key)
    }
}

public protocol CollectionsBackend: Sendable {
    func collections() async throws -> [SourceCollectionRow]
    func create(name: String) async throws -> String
    func rename(id: String, name: String) async throws
    func delete(id: String) async throws
    func reorder(ids: [String]) async throws
    func members(of id: String) async throws -> [SourceCollectionMemberRow]
    func setMembership(sourceKey: String, collectionID: String, included: Bool) async throws
}

@MainActor
@Observable
public final class CollectionsStore {
    public private(set) var collections: [SourceCollectionRow] = []
    public private(set) var members: [SourceCollectionMemberRow] = []
    public private(set) var openCollection: SourceCollectionRow?
    public private(set) var errorMessage: String?
    public private(set) var isLoading = false
    public private(set) var isReordering = false

    @ObservationIgnored private let backend: CollectionsBackend

    public init(backend: CollectionsBackend) { self.backend = backend }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do { collections = try await backend.collections(); errorMessage = nil }
        catch { errorMessage = String(localized: "Não foi possível carregar as coleções.") }
    }

    public func create(named name: String) async {
        do {
            _ = try await backend.create(name: name)
            await load()
        } catch { errorMessage = Self.message }
    }

    public func rename(id: String, to name: String) async {
        do {
            try await backend.rename(id: id, name: name)
            await load()
        } catch { errorMessage = Self.message }
    }

    public func delete(id: String) async {
        do {
            try await backend.delete(id: id)
            await load()
        } catch { errorMessage = Self.message }
    }

    /// A failed reorder reloads the stored order: the screen never keeps an order the database never received.
    public func reorder(_ ids: [String]) async {
        do {
            try await backend.reorder(ids: ids)
            await load()
        } catch {
            errorMessage = Self.message
            await load()
        }
    }

    /// Opens one collection's own members. Nil closes it.
    public func open(_ collection: SourceCollectionRow?) async {
        openCollection = collection
        guard let collection else { members = []; return }
        do { members = try await backend.members(of: collection.id); errorMessage = nil }
        catch { members = []; errorMessage = Self.message }
    }

    /// Adds or removes one source. The list is refreshed from the backend, so a refused change never leaves an
    /// optimistic membership on screen.
    public func setMembership(sourceKey: String, included: Bool) async {
        guard let collection = openCollection else { return }
        do {
            try await backend.setMembership(sourceKey: sourceKey, collectionID: collection.id, included: included)
            await open(collection)
            await load()
        } catch { errorMessage = Self.message }
    }

    public func setReordering(_ enabled: Bool) { isReordering = enabled }

    public static func usableName(_ raw: String) -> String? {
        ReaderLibraryRules.normalizedName(raw)
    }

    private static var message: String { String(localized: "Não foi possível alterar as coleções.") }
}
