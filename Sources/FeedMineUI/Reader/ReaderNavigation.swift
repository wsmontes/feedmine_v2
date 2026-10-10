// File: ReaderNavigation.swift
// Module: FeedMineUI
// Owns: the typed vocabulary of reader surfaces and overflow-menu entries, copied from V1's
//       `FeedScreen` menu, sheets and alerts.
// Does not own: presenting them. The host keeps one typed modal presentation, offers only the entries
// its deliveries already implement, and executes the flow behind each one.

import Foundation

/// Every surface the V1 reader could reach (menu, sheets, alerts) — see
/// `docs/v1-study/UI_TRANSFER_MATRIX.md` §1.2 and §1.5. Prompt/confirmation surfaces are values too:
/// V1 opened an alert with a text field for them, and that alert is a surface like any other.
public enum ReaderDestination: String, CaseIterable, Hashable, Sendable {
    case sources
    case saved
    case settings
    case filters
    case bookmarkBoxes
    case collections
    case addFeed
    case export
    case catalog
    case curatedOnboarding
    case curatedInspector
    case curatedDeletion
    case smartFeedPrompt
    case smartFeedDeletion
    case collectionFromContextPrompt
    case collectionExport
    case collectionImport
}

/// One entry of the reader's overflow menu, in V1's order, with V1's labels and symbols.
public struct ReaderMenuEntry: Hashable, Identifiable, Sendable {
    /// Stable identity: two V1 items can open the same surface (a confirmation and its target), so the
    /// destination alone is not an identifier.
    public let id: String
    public let destination: ReaderDestination
    public let title: String
    public let systemImage: String
    /// Destructive entries render with V1's `role: .destructive`.
    public let isDestructive: Bool

    public init(id: String, destination: ReaderDestination, title: String, systemImage: String,
        isDestructive: Bool = false) {
        self.id = id
        self.destination = destination
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
    }
}

public extension ReaderMenuEntry {
    /// V1 `FeedScreen.swift` 556–635: item order, labels and SF Symbols. The conditional items are
    /// included with the condition named, so a host can offer exactly the ones that apply.
    static let standard: [ReaderMenuEntry] = [
        .init(id: "create-curated", destination: .curatedOnboarding,
            title: String(localized: "Criar feed curado"), systemImage: "wand.and.stars"),
        .init(id: "open-curated-hood", destination: .curatedInspector,
            title: String(localized: "Abrir o capô do feed curado"), systemImage: "slider.horizontal.3"),
        .init(id: "delete-curated", destination: .curatedDeletion,
            title: String(localized: "Excluir feed curado"), systemImage: "trash", isDestructive: true),
        .init(id: "save-smart-bookmark", destination: .smartFeedPrompt,
            title: String(localized: "Salvar como marcador inteligente"),
            systemImage: "sparkles.rectangle.stack"),
        .init(id: "collect-sources", destination: .collectionFromContextPrompt,
            title: String(localized: "Reunir estas fontes"), systemImage: "folder.badge.plus"),
        .init(id: "export-collection", destination: .collectionExport,
            title: String(localized: "Exportar coleção"), systemImage: "square.and.arrow.up"),
        .init(id: "import-collection", destination: .collectionImport,
            title: String(localized: "Importar para a coleção"),
            systemImage: "square.and.arrow.down"),
        .init(id: "add-feed-to-collection", destination: .addFeed,
            title: String(localized: "Adicionar feed à coleção"), systemImage: "link.badge.plus"),
        .init(id: "delete-smart-bookmark", destination: .smartFeedDeletion,
            title: String(localized: "Excluir marcador inteligente"), systemImage: "trash",
            isDestructive: true),
        .init(id: "add-feed", destination: .addFeed, title: String(localized: "Adicionar feed"),
            systemImage: "plus.circle"),
        .init(id: "export", destination: .export, title: String(localized: "Exportar"),
            systemImage: "square.and.arrow.up"),
        .init(id: "collections", destination: .collections,
            title: String(localized: "Coleções de fontes"), systemImage: "rectangle.stack.fill"),
        .init(id: "sources", destination: .sources, title: String(localized: "Fontes"),
            systemImage: "antenna.radiowaves.left.and.right"),
        .init(id: "settings", destination: .settings, title: String(localized: "Ajustes"),
            systemImage: "gearshape"),
    ]

    /// The entry a host resolves a destination to, so the presentation does not need a second table.
    static func entry(for destination: ReaderDestination) -> ReaderMenuEntry? {
        standard.first { $0.destination == destination }
    }
}
