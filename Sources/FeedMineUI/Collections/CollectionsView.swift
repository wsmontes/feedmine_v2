//
// File: CollectionsView.swift
// Module: FeedMineUI
//
// Responsibility:
// V1's `CollectionManagementView` and `SourceCollectionDetailView`: the reader's source collections, the empty
// state that explains them, create/rename/delete/reorder, and one collection's own members with the way into
// its feed.
//
// Deliberate difference from V1, recorded in docs/v1-study/PORT_LOG.md: V1 printed a member's stored
// `title_snapshot` on the row. V2's membership is the source key itself (the feed's own address), because a
// snapshot title can go stale and the catalog is always there to state it; the row shows the host instead.
import SwiftUI
import FeedMineDomain

public struct CollectionsView: View {
    @State private var store: CollectionsStore
    private let appearance: ReaderAppearance
    /// Opening a collection's feed belongs to the host: it is a session transition, not a layout decision.
    private let onOpenFeed: (String) -> Void
    private let onClose: () -> Void

    @State private var isCreating = false
    @State private var newName = ""
    @State private var renameTarget: SourceCollectionRow?
    @State private var deleteTarget: SourceCollectionRow?
    /// The collection whose detail is on screen. The store is told when it opens and when it closes.
    @State private var opened: SourceCollectionRow?

    public init(store: CollectionsStore, appearance: ReaderAppearance = .standard,
        onOpenFeed: @escaping (String) -> Void, onClose: @escaping () -> Void = {}) {
        _store = State(initialValue: store)
        self.appearance = appearance
        self.onOpenFeed = onOpenFeed
        self.onClose = onClose
    }

    public var body: some View {
        Group {
            if store.collections.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "Nenhuma coleção de fontes"), systemImage: "rectangle.stack.badge.plus")
                } description: {
                    Text(verbatim: String(localized: "Crie uma lista reutilizável de fontes. Uma fonte pode pertencer a mais de uma coleção."))
                }
                .accessibilityIdentifier("collections-empty")
            } else {
                List {
                    Section {
                        ForEach(store.collections) { collection in
                            CollectionRowView(collection: collection, isReordering: store.isReordering,
                                onOpen: { opened = collection },
                                onRename: { renameTarget = collection; newName = collection.name },
                                onDelete: { deleteTarget = collection })
                        }
                        .onMove { from, to in
                            var ids = store.collections.map(\.id)
                            ids.move(fromOffsets: from, toOffset: to)
                            Task { await store.reorder(ids) }
                        }
                    } footer: {
                        Text(verbatim: String(localized: "Coleções referenciam fontes pelo endereço do feed. Apagar uma remove apenas a lista, nunca a fonte."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(Self.listStyle)
        .scrollContentBackground(.hidden)
        .background(appearance.pageBackground)
        .navigationTitle(Text(verbatim: String(localized: "Coleções de fontes")))
        .toolbar {
            ToolbarItem(placement: ReaderToolbarPlacement.trailing) {
                Button(String(localized: "Concluir"), action: onClose)
                    .accessibilityIdentifier("collections.done")
            }
            ToolbarItem(placement: ReaderToolbarPlacement.trailing) {
                Button {
                    newName = ""
                    isCreating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "Criar coleção de fontes"))
                .accessibilityIdentifier("collections.new")
            }
        }
        // V1 pushed one collection's own detail inside the same navigation stack (`NavigationLink`), so the
        // way back is the stack's own. Presenting it as a second sheet left the detail with no way out but a
        // drag, and made the surface behind it unreachable.
        .navigationDestination(item: $opened) { collection in
            CollectionDetailView(store: store, collection: collection, appearance: appearance,
                onOpenFeed: onOpenFeed)
        }
        .alert(String(localized: "Nova coleção de fontes"), isPresented: $isCreating) {
            TextField(String(localized: "Nome"), text: $newName)
            Button(String(localized: "Cancelar"), role: .cancel) {}
            Button(String(localized: "Criar")) {
                guard let name = CollectionsStore.usableName(newName) else { return }
                Task { await store.create(named: name) }
            }
        } message: {
            Text(verbatim: String(localized: "Use como uma lista: misture fontes do catálogo e importadas."))
        }
        .alert(String(localized: "Renomear"), isPresented: Binding(
            get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField(String(localized: "Nome"), text: $newName)
            Button(String(localized: "Cancelar"), role: .cancel) { renameTarget = nil }
            Button(String(localized: "Renomear")) {
                guard let target = renameTarget, let name = CollectionsStore.usableName(newName) else { return }
                Task { await store.rename(id: target.id, to: name) }
                renameTarget = nil
            }
        }
        .confirmationDialog(Text(verbatim: String(localized: "Apagar “\(deleteTarget?.name ?? "")”?")),
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible) {
            Button(String(localized: "Apagar coleção"), role: .destructive) {
                guard let target = deleteTarget else { return }
                deleteTarget = nil
                Task { await store.delete(id: target.id) }
            }
            Button(String(localized: "Cancelar"), role: .cancel) { deleteTarget = nil }
        } message: {
            Text(verbatim: String(localized: "As fontes e suas classificações continuam intactas."))
        }
        .onChange(of: opened) { _, collection in
            Task { await store.open(collection) }
        }
        .alert(String(localized: "Não foi possível alterar as coleções"), isPresented: Binding(
            get: { store.errorMessage != nil }, set: { _ in })) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(verbatim: store.errorMessage ?? "")
        }
        .task { if store.collections.isEmpty { await store.load() } }
    }

    #if os(iOS)
    private static let listStyle = InsetGroupedListStyle()
    #else
    private static let listStyle = InsetListStyle()
    #endif
}

/// V1's collection row: the playlist icon, the name, the member count, and its own two actions.
struct CollectionRowView: View {
    let collection: SourceCollectionRow
    let isReordering: Bool
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button {
            guard !isReordering else { return }
            onOpen()
        } label: {
            label
        }
        .buttonStyle(.plain)
        // The row states its identity without taking its own name away: a plain identifier here would
        // override the name inside it (the same rule the card and the empty state document).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("collection.row")
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label(String(localized: "Apagar"), systemImage: "trash")
            }
            Button(action: onRename) {
                Label(String(localized: "Renomear"), systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    private var label: some View {
        HStack {
            Label(verbatim: collection.name, systemImage: "rectangle.stack.fill")
            Spacer()
            Text(verbatim: Self.memberText(collection.memberCount))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    static func memberText(_ count: Int) -> String { String(localized: "\(count) fontes") }
}

/// One collection's own members, with V1's one action per member and the way into its feed.
struct CollectionDetailView: View {
    let store: CollectionsStore
    let collection: SourceCollectionRow
    let appearance: ReaderAppearance
    let onOpenFeed: (String) -> Void

    var body: some View {
        List {
            Section {
                Button {
                    onOpenFeed(collection.id)
                } label: {
                    Label(String(localized: "Abrir o feed da coleção"), systemImage: "play.rectangle.on.rectangle")
                }
                .disabled(store.members.isEmpty)
                .accessibilityIdentifier("collection.openFeed")
            } footer: {
                Text(verbatim: String(localized: "Abrir atualiza exatamente este conjunto de fontes e reúne o que elas publicaram."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                if store.members.isEmpty {
                    Text(verbatim: String(localized: "Adicione fontes a partir de um card ou de um resultado."))
                        .foregroundStyle(.secondary)
                }
                ForEach(store.members) { member in
                    HStack(spacing: 10) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: member.title)
                            Text(verbatim: member.host)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .accessibilityIdentifier("collection.member")
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await store.setMembership(sourceKey: member.id, included: false) }
                        } label: {
                            Label(String(localized: "Remover"), systemImage: "minus.circle")
                        }
                    }
                }
            } header: {
                Text(verbatim: String(localized: "Fontes"))
            }
        }
        .navigationTitle(Text(verbatim: collection.name))
        // The detail keeps the app's own title treatment on iOS; macOS has no inline mode.
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await store.open(collection) }
    }
}

private extension Label where Title == Text, Icon == Image {
    init(verbatim text: String, systemImage: String) {
        self.init { Text(verbatim: text) } icon: { Image(systemName: systemImage) }
    }
}
