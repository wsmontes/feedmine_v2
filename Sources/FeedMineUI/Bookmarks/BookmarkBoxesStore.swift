//
// File: BookmarkBoxesStore.swift
// Module: FeedMineUI
//
// Responsibility:
// The reader's bookmark boxes as observable values plus intents, over a backend the composition implements.
// V1's screen managed the boxes *and* chose which one the feed showed; V2 keeps the management and hands the
// reader the box's own contents, because there is no second feed engine behind a box.
//
// Does not own: storage (Persistence), the active context (the app) or any layout (the view).
import Foundation
import Observation
import FeedMineDomain
import FeedMineRuntime

/// One box as its row draws it. `isPreferred` is V1's `preferredBookmarkListID`: where a new bookmark lands.
public struct BookmarkBoxRow: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// How many published cards the box holds. V1 printed the same figure on the row.
    public let count: Int
    public let isDefault: Bool
    public let isPreferred: Bool

    public init(id: String, name: String, count: Int, isDefault: Bool, isPreferred: Bool) {
        self.id = id; self.name = name; self.count = count; self.isDefault = isDefault
        self.isPreferred = isPreferred
    }
}

public protocol BookmarkBoxesBackend: Sendable {
    /// Every box, with its own card count, in the reader's order.
    func boxes() async throws -> [BookmarkBoxRow]
    func create(name: String) async throws -> String
    func rename(id: String, name: String) async throws
    func delete(id: String) async throws
    func reorder(ids: [String]) async throws
    /// Nil means the default box (V1's own default when nothing was preferred).
    func setPreferred(id: String?) async throws
}

@MainActor
@Observable
public final class BookmarkBoxesStore {
    public private(set) var boxes: [BookmarkBoxRow] = []
    public private(set) var errorMessage: String?
    public private(set) var isLoading = false
    public private(set) var isReordering = false

    @ObservationIgnored private let backend: BookmarkBoxesBackend

    public init(backend: BookmarkBoxesBackend) { self.backend = backend }

    /// The box a new bookmark lands in: the preferred one, or the default box when nothing is preferred.
    public var preferredID: String {
        boxes.first(where: \.isPreferred)?.id ?? ReaderBookmarkList.defaultID
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do { boxes = try await backend.boxes(); errorMessage = nil }
        catch { errorMessage = String(localized: "Não foi possível carregar as caixas de salvos.") }
    }

    public func create(named name: String) async {
        do {
            _ = try await backend.create(name: name)
            await load()
        } catch { errorMessage = Self.message(for: error) }
    }

    public func rename(id: String, to name: String) async {
        do {
            try await backend.rename(id: id, name: name)
            await load()
        } catch { errorMessage = Self.message(for: error) }
    }

    /// A refused delete (the default box) leaves the list exactly as the store has it.
    public func delete(id: String) async {
        do {
            try await backend.delete(id: id)
            await load()
        } catch { errorMessage = Self.message(for: error) }
    }

    /// Persists the order a drag applied. A failed write reloads the stored order instead of leaving the
    /// screen showing an order the database never received (V1 learned this the hard way).
    public func reorder(_ ids: [String]) async {
        do {
            try await backend.reorder(ids: ids)
            await load()
        } catch {
            errorMessage = Self.message(for: error)
            await load()
        }
    }

    public func setPreferred(id: String?) async {
        do {
            try await backend.setPreferred(id: id)
            await load()
        } catch { errorMessage = Self.message(for: error) }
    }

    public func setReordering(_ enabled: Bool) { isReordering = enabled }

    /// A name the reader can use: trimmed and never empty, checked before a write is attempted.
    public static func usableName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func message(for error: any Error) -> String {
        String(localized: "Não foi possível alterar as caixas de salvos.")
    }
}
