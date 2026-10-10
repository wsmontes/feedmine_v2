//
// File: ReaderImportExportViews.swift
// Module: FeedMineUI
//
// Responsibility:
// V1's two tools as surfaces: the export sheet (scope × format, a preview of the document, and the actions on
// it) and the import preview (what a file offers, what it repeats, what it cannot use, and one confirmation).
//
// The import is deliberately two steps on screen as well: the preview is shown *before* anything is written, so
// cancelling is free. Sharing and saving the exported file belong to the host.
//
// Does not own: writing the file (Composition), reading the file (the app) or the share sheet (a platform
// surface).
import SwiftUI
import FeedMineDomain
import FeedMineRuntime

public struct ReaderExportView: View {
    private let scopes: [ReaderExportChoice]
    private let formats: [ReaderExportFormat]
    /// The document's text, when the host has produced one for the current choice. Nil while it is being made.
    private let previewText: String?
    private let onSelect: (ReaderExportChoice, ReaderExportFormat) -> Void
    private let onShare: () -> Void
    private let onSave: () -> Void
    private let onClose: () -> Void

    @State private var scope: ReaderExportChoice
    @State private var format: ReaderExportFormat

    public init(scopes: [ReaderExportChoice], formats: [ReaderExportFormat] = ReaderExportFormat.allCases,
        initial: ReaderExportChoice, initialFormat: ReaderExportFormat = .opml, previewText: String?,
        onSelect: @escaping (ReaderExportChoice, ReaderExportFormat) -> Void,
        onShare: @escaping () -> Void, onSave: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.scopes = scopes
        self.formats = formats
        self.previewText = previewText
        self.onSelect = onSelect
        self.onShare = onShare
        self.onSave = onSave
        self.onClose = onClose
        _scope = State(initialValue: initial)
        _format = State(initialValue: initialFormat)
    }

    public var body: some View {
        List {
            Section(String(localized: "O que exportar")) {
                ForEach(scopes) { choice in
                    Button {
                        scope = choice
                        onSelect(choice, format)
                    } label: {
                        HStack {
                            Label(choice.title, systemImage: choice.systemImage)
                            Spacer(minLength: 0)
                            if choice == scope {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("export-scope-\(choice.id)")
                }
            }
            Section(String(localized: "Formato")) {
                Picker(String(localized: "Formato"), selection: Binding(get: { format }, set: { value in
                    format = value
                    onSelect(scope, value)
                })) {
                    ForEach(formats) { option in
                        Label(option.title, systemImage: option.systemImage).tag(option)
                    }
                }
                .accessibilityIdentifier("export-format")
            }
            Section(String(localized: "Prévia")) {
                if let previewText, !previewText.isEmpty {
                    ScrollView(.vertical) {
                        Text(verbatim: String(previewText.prefix(4_000)))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("export-preview")
                    }
                    .frame(maxHeight: 220)
                } else {
                    Text(verbatim: String(localized: "Nada para exportar."))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("export-empty")
                }
            }
            Section {
                Button {
                    onShare()
                } label: {
                    Label(String(localized: "Compartilhar"), systemImage: "square.and.arrow.up")
                }
                .disabled(previewText?.isEmpty != false)
                .accessibilityIdentifier("export-share")
                Button {
                    onSave()
                } label: {
                    Label(String(localized: "Salvar arquivo"), systemImage: "folder")
                }
                .disabled(previewText?.isEmpty != false)
                .accessibilityIdentifier("export-save")
            }
        }
        .listStyle(Self.listStyle)
        .navigationTitle(Text(verbatim: String(localized: "Exportar")))
        .toolbar {
            ToolbarItem(placement: ReaderToolbarPlacement.trailing) {
                Button(String(localized: "Concluir"), action: onClose)
                    .accessibilityIdentifier("export-done")
            }
        }
    }

    #if os(iOS)
    private static let listStyle = InsetGroupedListStyle()
    #else
    private static let listStyle = InsetListStyle()
    #endif
}

/// One list a reader can export, as the sheet offers it.
public struct ReaderExportChoice: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let scope: ReaderExportScope

    public init(id: String, title: String, systemImage: String, scope: ReaderExportScope) {
        self.id = id; self.title = title; self.systemImage = systemImage; self.scope = scope
    }
}

/// V1's import preview: what the file offers, before anything is written.
public struct ReaderImportPreviewView: View {
    private let preview: ReaderImportPreview
    private let isCommitting: Bool
    private let onCancel: () -> Void
    private let onConfirm: () -> Void

    public init(preview: ReaderImportPreview, isCommitting: Bool = false,
        onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self.preview = preview
        self.isCommitting = isCommitting
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    public var body: some View {
        List {
            Section {
                if preview.entries.isEmpty {
                    Text(verbatim: String(localized: "Este arquivo não tem fontes para importar."))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("import-none")
                }
                ForEach(preview.entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: entry.title.isEmpty ? Self.host(entry.requestURL) : entry.title)
                        Text(verbatim: entry.requestURL)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if !entry.categoryPath.isEmpty {
                            Text(verbatim: entry.categoryPath.joined(separator: " › "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("import-entry")
                }
            } header: {
                Text(verbatim: preview.name ?? String(localized: "Importar OPML"))
            } footer: {
                Text(verbatim: Self.summary(preview))
                    .font(.caption)
                    .accessibilityIdentifier("import-summary")
            }
            if !preview.rejections.isEmpty {
                Section(String(localized: "Não serão importados")) {
                    ForEach(preview.rejections, id: \.self) { rejection in
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: rejection.title ?? rejection.rawAddress ?? "—")
                                Text(verbatim: rejection.reason == .unusableAddress
                                    ? String(localized: "endereço não utilizável")
                                    : String(localized: "categoria vazia"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("import-rejection")
                    }
                }
            }
        }
        .listStyle(Self.listStyle)
        .navigationTitle(Text(verbatim: String(localized: "Importar OPML")))
        .toolbar {
            ToolbarItem(placement: ReaderToolbarPlacement.trailing) {
                Button(String(localized: "Importar"), action: onConfirm)
                    .disabled(preview.entries.isEmpty || isCommitting)
                    .accessibilityIdentifier("import-confirm")
            }
            ToolbarItem(placement: ReaderToolbarPlacement.trailing) {
                Button(String(localized: "Cancelar"), action: onCancel)
                    .accessibilityIdentifier("import-cancel")
            }
        }
    }

    /// The one line V1 printed after a parse: how many feeds, how many repeats, how many unusable.
    static func summary(_ preview: ReaderImportPreview) -> String {
        var parts = [String(localized: "\(preview.entries.count) fontes")]
        if preview.repeats > 0 { parts.append(String(localized: "\(preview.repeats) repetidas")) }
        if !preview.rejections.isEmpty { parts.append(String(localized: "\(preview.rejections.count) ignoradas")) }
        return parts.joined(separator: " · ")
    }

    static func host(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }

    #if os(iOS)
    private static let listStyle = InsetGroupedListStyle()
    #else
    private static let listStyle = InsetListStyle()
    #endif
}
