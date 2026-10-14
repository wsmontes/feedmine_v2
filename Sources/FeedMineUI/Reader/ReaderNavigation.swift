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
    /// V1's own conditional entry: adding a feed straight into the collection the reader is looking at.
    case addFeedToCollection
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
    /// The identifier this entry exposes to accessibility queries, when it must differ from the visible title.
    ///
    /// The menu is otherwise addressed by its visible title, and that title is translatable: on a device whose
    /// language is English, a query by Portuguese copy stops matching (measured 2026-10-11 for the settings
    /// entry, whose label read "Settings"). Stating an identifier keeps the visible copy in the reader's own
    /// language — an identifier is not visible copy — while the entry stays reachable by the string that names
    /// it for the callers that must not depend on translation.
    public let accessibilityID: String?

    public init(id: String, destination: ReaderDestination, title: String, systemImage: String,
        isDestructive: Bool = false, accessibilityID: String? = nil) {
        self.id = id
        self.destination = destination
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.accessibilityID = accessibilityID
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
        .init(id: "add-feed-to-collection", destination: .addFeedToCollection,
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
        // V1's own `Salvos` (its navigation toolbar's saved-boxes control, removed with the toolbar; V2 draws
        // that surface from the header and from here). It sits beside `Fontes` because V1's toolbar had them
        // together, and it carries the symbol the header's control already uses for the same surface.
        //
        // The title stays in the catalogue (English renders "Saved"). What does **not** get translated is the
        // entry's access identifier: the frozen B05 driver reaches its B surface with a query for that word, and
        // a translated identifier would make the A→B→A it exists for unreachable — the defect this entry closes
        // (PO 2026-10-14). The identifier is not visible copy, so stating it costs the reader nothing.
        .init(id: "bookmark-boxes", destination: .bookmarkBoxes, title: String(localized: "Salvos"),
            systemImage: "bookmark", accessibilityID: "Salvos"),
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
