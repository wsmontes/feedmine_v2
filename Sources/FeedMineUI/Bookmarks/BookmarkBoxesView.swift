//
// File: BookmarkBoxesView.swift
// Module: FeedMineUI
//
// Responsibility:
// V1's `BookmarkBoxesView` — the reader's boxes: which one a new bookmark lands in, creating, renaming,
// deleting and reordering them, and the way into a box's own contents. Layout, labels, swipe actions and the
// reorder mode are copied; what the rows *open* is the host's.
//
// Deliberate difference from V1, recorded in docs/v1-study/PORT_LOG.md: V1's row tap made the feed show that
// box (its `lastClicked` preset over `selectedBookmarkListID`), and it carried two marks — a checkmark for the
// shown box and bold for the preferred one. V2 has no second feed engine behind a box, so a row tap opens the
// box's own saved list and the row carries V1's bold plus a checkmark for the box a new bookmark lands in.
import SwiftUI
import FeedMineDomain
#if os(iOS)
import UIKit
#endif

public struct BookmarkBoxesView: View {
    @State private var store: BookmarkBoxesStore
    private let appearance: ReaderAppearance
    /// Opening a box's contents and the all-saved list belongs to the host's navigation.
    private let onOpenAll: () -> Void
    private let onOpenBox: (String) -> Void
    private let onClose: () -> Void

    @State private var isCreating = false
    @State private var newName = ""
    @State private var renameTarget: BookmarkBoxRow?
    @State private var renameName = ""

    public init(store: BookmarkBoxesStore, appearance: ReaderAppearance = .standard,
        onOpenAll: @escaping () -> Void, onOpenBox: @escaping (String) -> Void, onClose: @escaping () -> Void = {}) {
        _store = State(initialValue: store)
        self.appearance = appearance
        self.onOpenAll = onOpenAll
        self.onOpenBox = onOpenBox
        self.onClose = onClose
    }

    public var body: some View {
        List {
            Section {
                Button(action: onOpenAll) {
                    Label(String(localized: "Todos os salvos"), systemImage: "line.3.horizontal")
                }
                ForEach(store.boxes) { box in
                    row(box)
                }
                .onMove { from, to in
                    var ids = store.boxes.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    Task { await store.reorder(ids) }
                }
            } header: {
                Text(verbatim: String(localized: "Caixas de salvos"))
            }
            Section {
                Button {
                    newName = ""
                    isCreating = true
                } label: {
                    Label(String(localized: "Nova caixa"), systemImage: "plus.circle")
                }
                .accessibilityIdentifier("bookmarkBoxes.new")
            }
        }
        .listStyle(Self.listStyle)
        .scrollContentBackground(.hidden)
        .background(appearance.pageBackground)
        .navigationTitle(Text(verbatim: String(localized: "Caixas de salvos")))
        .toolbar {
            ToolbarItem(placement: ReaderToolbarPlacement.trailing) {
                Button(store.isReordering ? String(localized: "Concluir") : String(localized: "Reordenar")) {
                    store.setReordering(!store.isReordering)
                    #if os(iOS)
                    reorderMode = store.isReordering ? .active : .inactive
                    #endif
                }
                .accessibilityIdentifier("bookmarkBoxes.reorder")
            }
        }
        #if os(iOS)
        .environment(\.editMode, $reorderMode)
        #endif
        .alert(String(localized: "Nova caixa"), isPresented: $isCreating) {
            TextField(String(localized: "Nome"), text: $newName)
            Button(String(localized: "Cancelar"), role: .cancel) {}
            Button(String(localized: "Criar")) {
                guard let name = BookmarkBoxesStore.usableName(newName) else { return }
                Task { await store.create(named: name) }
            }
        }
        .alert(String(localized: "Renomear"), isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } })) {
            TextField(String(localized: "Nome"), text: $renameName)
            Button(String(localized: "Cancelar"), role: .cancel) { renameTarget = nil }
            Button(String(localized: "Renomear")) {
                guard let box = renameTarget, let name = BookmarkBoxesStore.usableName(renameName) else { return }
                Task { await store.rename(id: box.id, to: name) }
                renameTarget = nil
            }
        }
        .alert(String(localized: "Não foi possível alterar as caixas de salvos"), isPresented: Binding(
            get: { store.errorMessage != nil }, set: { _ in })) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(verbatim: store.errorMessage ?? "")
        }
        .task { if store.boxes.isEmpty { await store.load() } }
    }

    #if os(iOS)
    @State private var reorderMode: EditMode = .inactive
    #endif

    @ViewBuilder private func row(_ box: BookmarkBoxRow) -> some View {
        Button {
            guard !store.isReordering else { return }
            onOpenBox(box.id)
        } label: {
            HStack {
                Label(verbatim: box.name, systemImage: "folder")
                    .fontWeight(box.isPreferred ? .bold : .regular)
                Spacer()
                Text(verbatim: "\(box.count)").font(.caption).foregroundStyle(.secondary)
                if box.isPreferred {
                    Image(systemName: "checkmark").font(.caption).foregroundStyle(appearance.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bookmarkBox.row")
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                Task { await store.setPreferred(id: box.isDefault ? nil : box.id) }
            } label: {
                Label(String(localized: "Padrão"), systemImage: "star.fill")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(String(localized: "Renomear")) {
                renameTarget = box
                renameName = box.name
            }
            .tint(.blue)
            if !box.isDefault {
                Button(role: .destructive) {
                    Task { await store.delete(id: box.id) }
                } label: {
                    Label(String(localized: "Apagar"), systemImage: "trash")
                }
            }
        }
    }

    #if os(iOS)
    private static let listStyle = InsetGroupedListStyle()
    #else
    private static let listStyle = InsetListStyle()
    #endif
}

private extension Label where Title == Text, Icon == Image {
    init(verbatim text: String, systemImage: String) {
        self.init { Text(verbatim: text) } icon: { Image(systemName: systemImage) }
    }
}
