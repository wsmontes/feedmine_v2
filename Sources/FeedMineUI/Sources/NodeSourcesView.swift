//
// File: NodeSourcesView.swift
// Module: FeedMineUI
//
// Responsibility:
// V1's detail for one node of the catalog — `Views/CountryDetailScreen.swift` and
// `Views/RegionDetailScreen.swift` were the same screen twice (a list of sub-regions and the node's own
// feeds, each with its own toggle). The V2 catalog has one node model, so this is one view: the node's
// children (V1's "Regions" section, each row drilling further or toggling the whole sub-tree) and the
// node's own sources, grouped into sections with an icon, each with its own toggle.
//
// Deliberate difference from V1, deliberate and recorded (docs/v1-study/PORT_LOG.md): V1 grouped a
// node's feeds by the `FeedSource.category` string its own registry carried, with an icon chosen from
// that free text (news/sport/tech/…). The V2 catalog has no category column; it has `media_kind`, so the
// grouping is by media kind with the same icon language V1 used for audio and video. The grouping is a
// value (`sections(sources:)`), so the layout is testable without a store.
//
// Does not own: reading the catalog, persisting the selection (the store does) or navigation (the host).
import SwiftUI
import FeedMineRuntime

/// One of a node's own sources, as the row draws it. V1's row was a title plus the feed's URL; the catalog
/// key of a source *is* its feed URL, so the secondary line states the same thing from V2's own value.
public struct NodeSourceRow: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let isSelected: Bool

    public init(id: String, title: String, detail: String, isSelected: Bool) {
        self.id = id; self.title = title; self.detail = detail; self.isSelected = isSelected
    }
}

/// A section of a node's own sources. V1 drew one section per category with a label and an icon.
public struct NodeSourceSection: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let icon: String
    public let rows: [NodeSourceRow]

    public init(id: String, title: String, icon: String, rows: [NodeSourceRow]) {
        self.id = id; self.title = title; self.icon = icon; self.rows = rows
    }
}

public struct NodeSourcesView: View {
    @State private var store: SourceManagementStore
    private let node: CatalogNodeSummary
    private let appearance: ReaderAppearance
    /// Drilling one level further stays with the host: this view states no navigation of its own.
    private let onOpenNode: (CatalogNodeSummary) -> Void

    public init(store: SourceManagementStore, node: CatalogNodeSummary,
        appearance: ReaderAppearance = .standard, onOpenNode: @escaping (CatalogNodeSummary) -> Void) {
        _store = State(initialValue: store)
        self.node = node
        self.appearance = appearance
        self.onOpenNode = onOpenNode
    }

    /// The sections the node's own sources are drawn in: audio, then video, then text, then anything the
    /// catalog states that this delivery does not know — a fixed order, so the same list always draws the
    /// same way. Empty sections are not drawn, so a node with only feeds never states a heading it cannot fill.
    public static func sections(sources: [CatalogSourceSummary], selection: Set<String>) -> [NodeSourceSection] {
        var grouped: [String: [CatalogSourceSummary]] = [:]
        for source in sources { grouped[source.mediaKind, default: []].append(source) }
        let rank: (String) -> Int = { kind in
            switch kind {
            case "audio": return 0
            case "video": return 1
            case "text": return 2
            default: return 3
            }
        }
        return grouped.keys.sorted { left, right in
            let (leftRank, rightRank) = (rank(left), rank(right))
            return leftRank == rightRank ? left < right : leftRank < rightRank
        }
        .map { kind in
            NodeSourceSection(id: kind,
                title: Self.title(kind),
                icon: Self.icon(kind),
                rows: (grouped[kind] ?? []).map { source in
                    NodeSourceRow(id: source.id, title: source.title, detail: source.id,
                        isSelected: selection.contains(source.id))
                })
        }
    }

    /// A media kind's own name, in the app's language, with the catalog's own word when nothing matches.
    public static func title(_ mediaKind: String) -> String {
        switch mediaKind {
        case "audio": return String(localized: "Podcasts")
        case "video": return String(localized: "Vídeo")
        case "text": return String(localized: "Texto")
        default: return mediaKind.isEmpty ? String(localized: "Fontes") : mediaKind
        }
    }

    /// V1's icon language for the same kinds (`headphones` for podcasts, `play.rectangle.fill` for video).
    public static func icon(_ mediaKind: String) -> String {
        switch mediaKind {
        case "audio": return "headphones"
        case "video": return "play.rectangle.fill"
        case "text": return "doc.text"
        default: return "antenna.radiowaves.left.and.right"
        }
    }

    /// What a node's children are called: their own kind when the catalog is uniform under this node, and a
    /// plain "sub-nodes" when it is not. V1's word ("Regions") came from its own fixed tree; V2 states what
    /// the catalog actually placed under the node.
    public static func childLabel(for children: [CatalogNodeSummary]) -> String {
        let kinds = Set(children.map(\.kind))
        guard kinds.count == 1, let kind = kinds.first else { return String(localized: "Sub-nós") }
        switch kind {
        case .section: return String(localized: "Seções")
        case .country: return String(localized: "Países")
        case .topic: return String(localized: "Tópicos")
        case .other: return String(localized: "Sub-nós")
        }
    }

    public var body: some View {
        List { content }
            .listStyle(Self.listStyle)
            .scrollContentBackground(.hidden)
            .background(appearance.pageBackground)
            .navigationTitle(Text(verbatim: node.name))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task { await store.open(node) }
    }

    #if os(iOS)
    private static let listStyle = InsetGroupedListStyle()
    #else
    private static let listStyle = InsetListStyle()
    #endif

    @ViewBuilder private var content: some View {
        if store.hasCatalog {
            childrenSection
            sourcesSection
        } else {
            // The catalog is an optional shipped asset: its absence is a state, never an empty tree.
            Section {
                Label(String(localized: "O catálogo de fontes não está disponível."),
                    systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("catalog-unavailable")
            }
        }
    }

    @ViewBuilder private var childrenSection: some View {
        if !store.children.isEmpty {
            Section {
                ForEach(store.children) { child in
                    NodeChildRow(child: child, isEnabled: store.isNodeEnabled(child),
                        onOpen: { onOpenNode(child) },
                        onToggle: { enabled in Task { await store.setEnabled(child, enabled: enabled) } })
                }
            } header: {
                Label(String(localized: "\(Self.childLabel(for: store.children)) (\(store.children.count))"),
                    systemImage: "map.fill")
            }
        }
    }

    @ViewBuilder private var sourcesSection: some View {
        ForEach(store.nodeSections) { section in
            Section {
                ForEach(section.rows) { row in
                    NodeSourceRowView(row: row, isSelected: store.selection.contains(row.id),
                        onToggle: {
                            guard let source = store.sources.first(where: { $0.id == row.id }) else { return }
                            Task { await store.toggle(source) }
                        })
                }
            } header: {
                NodeSectionHeader(section: section)
            }
        }
    }
}

/// V1's feed row: the title, the feed's own address underneath, and the source's toggle.
public struct NodeSourceRowView: View {
    public let row: NodeSourceRow
    public let isSelected: Bool
    public let onToggle: () -> Void

    public init(row: NodeSourceRow, isSelected: Bool, onToggle: @escaping () -> Void) {
        self.row = row; self.isSelected = isSelected; self.onToggle = onToggle
    }

    public var body: some View {
        HStack {
            title
            Spacer()
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in onToggle() }))
                .labelsHidden()
                .tint(.green)
                .accessibilityIdentifier("node-source-toggle-\(row.id)")
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: row.title).font(.subheadline)
            Text(verbatim: row.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// V1's section header: the group's name with its count and its own icon.
public struct NodeSectionHeader: View {
    public let section: NodeSourceSection

    public init(section: NodeSourceSection) { self.section = section }

    public var body: some View {
        Label(verbatim: "\(section.title) (\(section.rows.count))", systemImage: section.icon)
    }
}

/// V1's sub-region row: a way in, the node's own colour of icon, and a toggle for the whole sub-tree.
public struct NodeChildRow: View {
    public let child: CatalogNodeSummary
    public let isEnabled: Bool
    public let onOpen: () -> Void
    public let onToggle: (Bool) -> Void

    public init(child: CatalogNodeSummary, isEnabled: Bool, onOpen: @escaping () -> Void,
        onToggle: @escaping (Bool) -> Void) {
        self.child = child; self.isEnabled = isEnabled; self.onOpen = onOpen; self.onToggle = onToggle
    }

    public var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                label
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("node-child-\(child.id)")
            Toggle("", isOn: Binding(get: { isEnabled }, set: onToggle))
                .labelsHidden()
                .tint(.green)
        }
    }

    private var label: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: child.name).font(.body)
                Text(verbatim: Self.countText(child.sourceCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    static func countText(_ count: Int) -> String { String(localized: "\(count) feeds") }
}

private extension Label where Title == Text, Icon == Image {
    init(verbatim text: String, systemImage: String) {
        self.init { Text(verbatim: text) } icon: { Image(systemName: systemImage) }
    }
}
