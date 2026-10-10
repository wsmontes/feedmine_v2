//
// File: ReaderSettingsView.swift
// Module: FeedMineUI
//
// Responsibility:
// V1's `SettingsSheetView`, as values over `ReaderSettings`: the appearance that follows the clock, the font and
// its size, the night palette, image preloading, the reader's own filter rules, and about. Layout, section
// order, labels and SF Symbols are V1's.
//
// Deliberate differences, recorded in docs/v1-study/PORT_LOG.md:
// - V1's "Language" section (a picker plus "requires restarting the app") is not drawn: V2 has no String Catalog
//   of its own yet, and a picker that changes nothing would be a dead control.
// - V1's "Reading Data" and "Share" sections stated counts from its own registry and shared a rendered card;
//   V2 tracks neither that count nor a rendered artifact, so neither is drawn. "Storage" states the size of the
//   library file, which V2 does have.
import SwiftUI
import FeedMineDomain

public struct ReaderSettingsView: View {
    @State private var store: ReaderSettingsStore
    private let appearance: ReaderAppearance
    /// The clock's own period, stated by the host: the view never reads a clock, so it cannot disagree with the
    /// appearance the app is drawing with.
    private let period: ReaderPeriod
    /// The library file's size, when the host can measure it.
    private let storageDescription: String?
    private let onClose: () -> Void

    public init(store: ReaderSettingsStore, appearance: ReaderAppearance = .standard,
        period: ReaderPeriod = .morning, storageDescription: String? = nil,
        onClose: @escaping () -> Void = {}) {
        _store = State(initialValue: store)
        self.appearance = appearance
        self.period = period
        self.storageDescription = storageDescription
        self.onClose = onClose
    }

    /// V1's appearance vocabularies, as the rows offer them.
    public static let paletteFamilies: [(value: String, label: String)] = [
        ("warmEarth", String(localized: "Terra quente")),
        ("coolSky", String(localized: "Céu frio")),
        ("botanical", String(localized: "Botânico")),
        ("lavenderHour", String(localized: "Hora lavanda")),
        ("monochrome", String(localized: "Monocromático")),
    ]

    public static let fontStyles: [(value: String, label: String)] = [
        ("system", String(localized: "Sistema")),
        ("newYork", String(localized: "New York")),
        ("sfMono", String(localized: "Mono")),
        ("georgia", String(localized: "Georgia")),
    ]

    public static let typeScales: [(value: String, label: String)] = [
        ("small", String(localized: "Pequeno")),
        ("medium", String(localized: "Médio")),
        ("large", String(localized: "Grande")),
    ]

    public var body: some View {
        List {
            appearanceSection
            circadianSection
            performanceSection
            readingSection
            if let storageDescription {
                Section(String(localized: "Armazenamento")) {
                    HStack {
                        Text(verbatim: String(localized: "Biblioteca local"))
                        Spacer()
                        Text(verbatim: storageDescription).foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings-storage")
                    }
                }
            }
            Section(String(localized: "Sobre")) {
                HStack {
                    Text(verbatim: String(localized: "Feedmine"))
                    Spacer()
                    Text(verbatim: Self.version).foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings-version")
                }
                Text(verbatim: String(localized: "Leitor de feeds com curadoria local e sem conta."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(Self.listStyle)
        .scrollContentBackground(.hidden)
        .background(appearance.pageBackground)
        .navigationTitle(Text(verbatim: String(localized: "Ajustes")))
        .toolbar {
            ToolbarItem(placement: ReaderToolbarPlacement.trailing) {
                Button(String(localized: "Concluir"), action: onClose)
                    .accessibilityIdentifier("settings-done")
            }
        }
        .alert(String(localized: "Não foi possível salvar as preferências"), isPresented: Binding(
            get: { store.errorMessage != nil }, set: { _ in })) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(verbatim: store.errorMessage ?? "")
        }
        .task { await store.load() }
    }

    /// V1: "Appearance" — the font's size, and the vocabulary the two clock rules draw from.
    @ViewBuilder private var appearanceSection: some View {
        Section(String(localized: "Aparência")) {
            Picker(String(localized: "Tamanho do texto"), selection: Binding(
                get: { store.settings.typeScale }, set: { value in
                    Task { await store.update { $0.typeScale = value } }
                })) {
                ForEach(Self.typeScales, id: \.value) { option in
                    Text(verbatim: option.label).tag(option.value)
                }
            }
            .accessibilityIdentifier("settings-type-scale")
        }
    }

    /// V1: "Circadian Design" — the two rules that follow the hour, the families they draw from, and the hour
    /// they are on now.
    @ViewBuilder private var circadianSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { store.settings.followsClock },
                set: { value in Task { await store.update { $0.followsClock = value } } })) {
                Label(String(localized: "Paleta adaptativa"), systemImage: "paintpalette.fill")
            }
            .accessibilityIdentifier("settings-circadian-palette")
            Picker(String(localized: "Família de paleta"), selection: Binding(
                get: { store.settings.paletteFamily }, set: { value in
                    Task { await store.update { $0.paletteFamily = value } }
                })) {
                ForEach(Self.paletteFamilies, id: \.value) { option in
                    Text(verbatim: option.label).tag(option.value)
                }
            }
            .disabled(!store.settings.followsClock)
            .accessibilityIdentifier("settings-palette-family")
            Toggle(isOn: Binding(
                get: { store.settings.followsClockTypography },
                set: { value in Task { await store.update { $0.followsClockTypography = value } } })) {
                Label(String(localized: "Tipografia adaptativa"), systemImage: "textformat.size")
            }
            .accessibilityIdentifier("settings-circadian-typography")
            Picker(String(localized: "Estilo da fonte"), selection: Binding(
                get: { store.settings.fontStyle }, set: { value in
                    Task { await store.update { $0.fontStyle = value } }
                })) {
                ForEach(Self.fontStyles, id: \.value) { option in
                    Text(verbatim: option.label).tag(option.value)
                }
            }
            .disabled(!store.settings.followsClockTypography)
            .accessibilityIdentifier("settings-font-style")
        } header: {
            Text(verbatim: String(localized: "Design circadiano"))
        } footer: {
            Text(verbatim: String(localized: "Cores e tipografia mudam com a hora do dia. \(period.glyph) \(period.label) agora"))
                .font(.caption)
                .accessibilityIdentifier("settings-circadian-footer")
        }
    }

    /// V1: "Performance".
    @ViewBuilder private var performanceSection: some View {
        Section(String(localized: "Desempenho")) {
            Toggle(isOn: Binding(
                get: { store.settings.prefetchesImages },
                set: { value in Task { await store.update { $0.prefetchesImages = value } } })) {
                Label(String(localized: "Pré-carregar imagens"), systemImage: "photo.stack.fill")
            }
            .accessibilityIdentifier("settings-prefetch")
        }
    }

    /// V1: "Reading" — the night palette and the two rules that decide what content is hidden or cleared.
    @ViewBuilder private var readingSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { store.settings.nightMode },
                set: { value in Task { await store.update { $0.nightMode = value } } })) {
                Label(String(localized: "Modo noturno"), systemImage: "moon.stars.fill")
            }
            .accessibilityIdentifier("settings-night-mode")
            Toggle(isOn: Binding(
                get: { store.settings.filterAutoExpires },
                set: { value in Task { await store.update { $0.filterAutoExpires = value } } })) {
                Label(String(localized: "Limpar filtros sozinho"), systemImage: "clock.arrow.2.circlepath")
            }
            .accessibilityIdentifier("settings-filter-expiry")
            Toggle(isOn: Binding(
                get: { store.settings.contentFiltersEnabled },
                set: { value in Task { await store.update { $0.contentFiltersEnabled = value } } })) {
                Label(String(localized: "Filtros de conteúdo"), systemImage: "eye.slash")
            }
            .accessibilityIdentifier("settings-content-filters")
        } header: {
            Text(verbatim: String(localized: "Leitura"))
        } footer: {
            Text(verbatim: String(localized: "Filtros de categoria, humor e tipo se reiniciam depois de 4 horas para você nunca abrir num feed vazio."))
                .font(.caption)
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    #if os(iOS)
    private static let listStyle = InsetGroupedListStyle()
    #else
    private static let listStyle = InsetListStyle()
    #endif
}

public extension ReaderPeriod {
    /// V1's own mark for the hour, stated by the surface.
    var glyph: String {
        switch self {
        case .dawn: "🌅"
        case .morning: "☀️"
        case .afternoon: "🌤️"
        case .evening: "🌇"
        case .night: "🌙"
        }
    }

    var label: String {
        switch self {
        case .dawn: String(localized: "amanhecer")
        case .morning: String(localized: "manhã")
        case .afternoon: String(localized: "tarde")
        case .evening: String(localized: "fim de tarde")
        case .night: String(localized: "noite")
        }
    }
}
