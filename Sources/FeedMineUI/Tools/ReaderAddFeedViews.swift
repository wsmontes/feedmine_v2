//
// File: ReaderAddFeedViews.swift
// Module: FeedMineUI
//
// Responsibility:
// V1's "Add Feeds" sheet as values and a view: the reader pastes addresses — one, several, or prose with links
// in it — the addresses are resolved into feed addresses, the resolved feeds are shown before they are added,
// and the reader may file them into a personal collection in the same action. Copy is V2's own (Portuguese),
// the layout, controls and rules are V1's `AddFeedView`.
//
// Does not own: resolving an address (the backend does that — a view never opens a network connection), storing
// anything (Persistence), or reading the clipboard (the host hands the paste in).
import Foundation
import Observation
import SwiftUI
import FeedMineDomain

/// What kind of feed an address resolved to. V1 named and drew these three.
public enum ReaderFeedMediaKind: String, Hashable, Sendable {
    case text
    case video
    case audio
}

/// One feed a resolution produced, as the preview draws it.
public struct ReaderFeedCandidate: Hashable, Sendable, Identifiable {
    /// The feed's identity (`FeedAddress.identity`), which is what the reader's selection stores.
    public let id: String
    public let title: String
    /// The address to fetch.
    public let feedURL: String
    public let mediaKind: ReaderFeedMediaKind

    public init(id: String, title: String, feedURL: String, mediaKind: ReaderFeedMediaKind) {
        self.id = id; self.title = title; self.feedURL = feedURL; self.mediaKind = mediaKind
    }
}

public enum ReaderFeedFailureReason: String, Hashable, Sendable {
    case noFeedFound
    case unreachable
    case invalidURL
    case refused
}

/// One address that produced no feed, with why — so the surface states it instead of shrinking silently.
public struct ReaderFeedRejection: Hashable, Sendable, Identifiable {
    public let input: String
    public let reason: ReaderFeedFailureReason

    public init(input: String, reason: ReaderFeedFailureReason) {
        self.input = input; self.reason = reason
    }

    public var id: String { input + "#" + reason.rawValue }
}

/// What resolving the reader's input produced.
public struct ReaderFeedProposal: Hashable, Sendable {
    public let feeds: [ReaderFeedCandidate]
    public let rejections: [ReaderFeedRejection]
    /// OPML addresses in the input: they are lists of feeds, so they belong to the import pipeline.
    public let opmlLinks: [String]

    public init(feeds: [ReaderFeedCandidate], rejections: [ReaderFeedRejection], opmlLinks: [String]) {
        self.feeds = feeds; self.rejections = rejections; self.opmlLinks = opmlLinks
    }

    public var isEmpty: Bool { feeds.isEmpty && opmlLinks.isEmpty }
    /// How many things the reader is about to add, of any kind.
    public var total: Int { feeds.count + opmlLinks.count }
}

/// What adding the proposal did.
public struct ReaderFeedAdoption: Hashable, Sendable {
    public let added: Int
    public let alreadySelected: Int
    public let rejected: Int
    public let collectionName: String?
    public let filedInCollection: Int

    public init(added: Int, alreadySelected: Int, rejected: Int, collectionName: String?,
        filedInCollection: Int) {
        self.added = added; self.alreadySelected = alreadySelected; self.rejected = rejected
        self.collectionName = collectionName; self.filedInCollection = filedInCollection
    }
}

/// One collection the sheet can file a feed into.
public struct ReaderFeedCollectionOption: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// The operations the sheet needs. The composition implements it (resolution, storage, collections); the view
/// never opens a connection and never touches the library.
public protocol ReaderAddFeedBackend: Sendable {
    func resolve(_ text: String) async -> ReaderFeedProposal
    func adopt(_ proposal: ReaderFeedProposal, collectionID: String?) async throws -> ReaderFeedAdoption
    func collections() async throws -> [ReaderFeedCollectionOption]
    func createCollection(named name: String) async throws -> ReaderFeedCollectionOption
}

@MainActor
@Observable
public final class ReaderAddFeedStore {
    public private(set) var input: String = ""
    public private(set) var isResolving = false
    public private(set) var isAdopting = false
    /// The resolution waiting for the reader's confirmation — V1 asked before adding more than five.
    public private(set) var pendingProposal: ReaderFeedProposal?
    public private(set) var adoption: ReaderFeedAdoption?
    public private(set) var collections: [ReaderFeedCollectionOption] = []
    public private(set) var errorMessage: String?
    public var selectedCollectionID: String?

    private let backend: any ReaderAddFeedBackend
    /// How the host reads the clipboard. A platform surface, so a view and this store never touch it.
    private let clipboard: @MainActor () -> String?

    public init(backend: any ReaderAddFeedBackend, clipboard: @escaping @MainActor () -> String? = { nil }) {
        self.backend = backend
        self.clipboard = clipboard
    }

    /// V1 asked for confirmation above five feeds; up to that, adding is one action.
    public static let confirmationThreshold = 5

    public var canSubmit: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResolving && !isAdopting }

    public func setInput(_ text: String) {
        input = text
        errorMessage = nil
        // The reader is typing something else: what the last attempt resolved is no longer what is being added.
        pendingProposal = nil
        adoption = nil
    }

    public func pasteFromClipboard() {
        guard let text = clipboard(), !text.isEmpty else { return }
        input = input.isEmpty ? text : input + "\n" + text
        errorMessage = nil
    }

    public func loadCollections() async {
        collections = (try? await backend.collections()) ?? []
        if let selected = selectedCollectionID, !collections.contains(where: { $0.id == selected }) {
            selectedCollectionID = nil
        }
    }

    public func createCollection(named rawName: String) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = String(localized: "O nome da coleção não pode ficar vazio.")
            return
        }
        do {
            let created = try await backend.createCollection(named: name)
            await loadCollections()
            selectedCollectionID = created.id
        } catch {
            errorMessage = String(localized: "Não foi possível criar a coleção.")
        }
    }

    /// The sheet's one action: resolve what the reader typed, and add it — showing the resolution first when it
    /// is a lot, and adding directly when it is one action's worth.
    ///
    /// A resolution that found nothing stays on screen (with the reason for each address) and **does not** count
    /// as a confirmation: tapping again resolves the input again, so one bad paste cannot leave the reader with a
    /// button that does nothing.
    public func submit() async {
        if let proposal = pendingProposal, !proposal.isEmpty {
            await adopt(proposal)
            return
        }
        guard canSubmit else { return }
        isResolving = true
        let proposal = await backend.resolve(input)
        isResolving = false
        adoption = nil
        if proposal.isEmpty || proposal.total > Self.confirmationThreshold {
            // Nothing to add is stated as such; more than V1's own threshold is stated before it is added.
            pendingProposal = proposal
            return
        }
        await adopt(proposal)
    }

    private func adopt(_ proposal: ReaderFeedProposal) async {
        guard !proposal.isEmpty else { return }
        isAdopting = true
        defer { isAdopting = false }
        do {
            adoption = try await backend.adopt(proposal, collectionID: selectedCollectionID)
            pendingProposal = nil
            input = ""
        } catch {
            errorMessage = String(localized: "Não foi possível adicionar as fontes.")
        }
    }
}

/// V1's "Add Feeds" sheet: paste, resolve, preview, add — with the collection picker in the same screen.
public struct ReaderAddFeedView: View {
    @State private var store: ReaderAddFeedStore
    private let appearance: ReaderAppearance
    private let onClose: () -> Void
    /// What the sheet adds when it was opened from a collection's own screen.
    private let targetCollectionName: String?

    @State private var newCollectionName = ""
    @State private var showsNewCollection = false
    @FocusState private var inputFocused: Bool

    public init(store: ReaderAddFeedStore, appearance: ReaderAppearance = .standard,
        targetCollectionName: String? = nil, onClose: @escaping () -> Void) {
        _store = State(initialValue: store)
        self.appearance = appearance
        self.targetCollectionName = targetCollectionName
        self.onClose = onClose
    }

    public var body: some View {
        List {
            Section {
                TextField(String(localized: "Cole endereços, links ou domínios…"), text: Binding(
                    get: { store.input }, set: { store.setInput($0) }), axis: .vertical)
                    .lineLimit(3...8)
                    .focused($inputFocused)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("add-feed-input")
            } header: {
                Text(verbatim: String(localized: "Adicionar fontes"))
            } footer: {
                Text(verbatim: String(localized: "Cole qualquer link — sites, canais do YouTube, repositórios do GitHub, podcasts ou endereços de feed. Encontramos os feeds automaticamente."))
                    .font(.caption)
            }

            Section {
                Button {
                    store.pasteFromClipboard()
                } label: {
                    Label(String(localized: "Colar da área de transferência"), systemImage: "doc.on.clipboard")
                }
                .accessibilityIdentifier("add-feed-paste")
            }

            if let proposal = store.pendingProposal, !proposal.isEmpty {
                Section {
                    ForEach(proposal.feeds.prefix(20)) { feed in
                        HStack(spacing: 8) {
                            Image(systemName: Self.mediaIcon(feed.mediaKind))
                                .font(.caption)
                                .foregroundStyle(Self.mediaColor(feed.mediaKind))
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: feed.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text(verbatim: feed.feedURL)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("add-feed-preview-entry")
                    }
                    if proposal.feeds.count > 20 {
                        Text(verbatim: String(localized: "… e mais \(proposal.feeds.count - 20)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(verbatim: String(localized: "Pré-visualização (\(proposal.total))"))
                }
            }

            if !rejections.isEmpty {
                Section(String(localized: "Sem feed encontrado")) {
                    ForEach(rejections) { rejection in
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: rejection.input).lineLimit(1)
                                Text(verbatim: Self.message(rejection.reason))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("add-feed-rejection")
                    }
                }
            }

            Section {
                Picker(String(localized: "Adicionar a"), selection: Binding(
                    get: { store.selectedCollectionID }, set: { store.selectedCollectionID = $0 })) {
                    Text(verbatim: String(localized: "Nenhuma coleção")).tag(String?.none)
                    ForEach(store.collections) { option in
                        Text(verbatim: option.name).tag(String?.some(option.id))
                    }
                }
                .accessibilityIdentifier("add-feed-collection-picker")
                Button {
                    newCollectionName = ""
                    showsNewCollection = true
                } label: {
                    Label(String(localized: "Nova coleção…"), systemImage: "folder.badge.plus")
                        .foregroundStyle(appearance.accent)
                }
                .accessibilityIdentifier("add-feed-new-collection")
            } header: {
                Text(verbatim: String(localized: "Coleção pessoal"))
            } footer: {
                Text(verbatim: String(localized: "As coleções pessoais são as pastas em Coleções de fontes. As categorias do catálogo ficam à parte."))
                    .font(.caption)
            }

            if let adoption = store.adoption {
                Section(String(localized: "Resultado")) {
                    if adoption.added > 0 {
                        Label(String(localized: "\(adoption.added) adicionada(s)"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityIdentifier("add-feed-result-added")
                    }
                    if adoption.alreadySelected > 0 {
                        Label(String(localized: "\(adoption.alreadySelected) já estava(m) nas suas fontes"),
                            systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if adoption.filedInCollection > 0, let name = adoption.collectionName {
                        Label(String(localized: "\(adoption.filedInCollection) guardada(s) em \(name)"),
                            systemImage: "folder.fill")
                            .font(.caption)
                            .foregroundStyle(appearance.accent)
                    }
                    if adoption.rejected > 0 {
                        Label(String(localized: "\(adoption.rejected) recusada(s)"), systemImage: "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            if let error = store.errorMessage {
                Section {
                    Text(verbatim: error).foregroundStyle(.red)
                        .accessibilityIdentifier("add-feed-error")
                }
            }
        }
        .listStyle(Self.listStyle)
        .navigationTitle(Text(verbatim: targetCollectionName.map { String(localized: "Adicionar a \($0)") }
            ?? String(localized: "Adicionar fontes")))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancelar"), action: onClose)
                    .accessibilityIdentifier("add-feed-cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await store.submit() }
                } label: {
                    if store.isResolving || store.isAdopting {
                        ProgressView()
                    } else {
                        Text(verbatim: String(localized: "Adicionar")).fontWeight(.semibold)
                    }
                }
                .disabled(!store.canSubmit)
                .accessibilityIdentifier("add-feed-add")
            }
        }
        .alert(String(localized: "Nova coleção"), isPresented: $showsNewCollection) {
            TextField(String(localized: "Nome da coleção"), text: $newCollectionName)
            Button(String(localized: "Criar")) {
                let name = newCollectionName
                Task { await store.createCollection(named: name) }
            }
            Button(String(localized: "Cancelar"), role: .cancel) {}
        }
        .task {
            await store.loadCollections()
            inputFocused = true
        }
    }

    private var rejections: [ReaderFeedRejection] { store.pendingProposal?.rejections ?? [] }

    #if os(iOS)
    private static let listStyle = InsetGroupedListStyle()
    #else
    private static let listStyle = InsetListStyle()
    #endif

    /// V1's own icons and colours for the three kinds.
    static func mediaIcon(_ kind: ReaderFeedMediaKind) -> String {
        switch kind {
        case .text: return "doc.text"
        case .video: return "play.rectangle.fill"
        case .audio: return "headphones"
        }
    }

    static func mediaColor(_ kind: ReaderFeedMediaKind) -> Color {
        switch kind {
        case .text: return .blue
        case .video: return .red
        case .audio: return .purple
        }
    }

    static func message(_ reason: ReaderFeedFailureReason) -> String {
        switch reason {
        case .noFeedFound: return String(localized: "nenhum feed encontrado")
        case .unreachable: return String(localized: "não foi possível alcançar")
        case .invalidURL: return String(localized: "endereço inválido")
        case .refused: return String(localized: "endereço recusado")
        }
    }
}
