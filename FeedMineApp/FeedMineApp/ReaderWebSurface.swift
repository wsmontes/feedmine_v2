//
// File: ReaderWebSurface.swift
// Module: FeedMine
// Owns: the publisher's page as the reader reads it **inside the app's reader sheet** — a `WKWebView` with a slim
//       header, its load progress, its failure and retry state, and the pull-down-at-top dismissal gesture on its
//       scroll view.
// Does not own: which address was asked for (the app's surface stack decides that), the presentation itself
//       (`ReaderHost` owns the one page sheet), the local text page (`FeedReadingSurface`), or what a dismissal
//       does (the host's one `onFinish`).
//
// V1 read the site in a `WKWebView` inside a drag-dismissable sheet (`ArticleReaderView`/`ArticleWebView`). V2
// had replaced that with `SFSafariViewController`, whose chrome the app does not own and which cannot carry the
// product's own dismissal rule. This restores V1's model without giving up the explicit way out: "Abrir no
// Safari" leaves for the system browser, exactly as V1's `Link(destination:)` did.
//
// The load identity is the *requested* address, never the web view's current one: a redirect changes the latter,
// and comparing against it reloads the article the reader is reading. V1 recorded this same defect (its comment
// "Reload only when the input changed (#46)") and this file keeps the rule.
import SwiftUI
import UIKit
import WebKit
import FeedMineUI
import FeedMineRuntime

/// The identity of one page load: the address the surface was given, plus an explicit attempt number. A retry the
/// reader asked for is a new attempt; a body re-render is not. The web view's own `url` is deliberately absent:
/// it is the result of a load, and it changes on a redirect.
struct ReaderWebRequest: Equatable {
    let url: URL
    let attempt: Int

    init(url: URL, attempt: Int = 0) {
        self.url = url
        self.attempt = attempt
    }
}

/// What the page is doing. `.ready` is stated when the platform reports the load finished; `.failed` only when
/// it reports a failure that is not a cancellation (a redirect cancels the provisional load and is not a fault).
enum ReaderWebPhase: Equatable {
    case loading
    case ready
    case failed(message: String)
}

struct ReaderWebSurface: View {
    let url: URL
    let appearance: ReaderAppearance
    let onClose: () -> Void
    /// Whether the page is at its top edge, reported to the sheet that presents it — the same fact the text page
    /// reports, so the platform's own drag obeys the same rule on both pages.
    var onTopChange: ((Bool) -> Void)? = nil

    @State private var attempt = 0
    @State private var phase: ReaderWebPhase = .loading
    @State private var progress: Double = 0
    @State private var atTop = true

    private var request: ReaderWebRequest { ReaderWebRequest(url: url, attempt: attempt) }

    /// The site named by its host: the address bar Safari used to draw, without inventing chrome for it.
    private var source: String { url.host ?? url.absoluteString }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(appearance.separatorOpacity)
            progressBar
            ZStack {
                ReaderWebContainer(request: request,
                    onProgress: { progress = $0 },
                    onPhase: { phase = $0 },
                    onTopChange: { value in
                        atTop = value
                        onTopChange?(value)
                    },
                    onDismiss: onClose)
                    .accessibilityIdentifier("reading.web")
                if case .failed(let message) = phase {
                    failure(message)
                }
            }
        }
        .background(appearance.pageBackground)
        // A new request (a different address, or the reader's retry) starts from the load's own zero, stated here
        // rather than from inside the representable's update pass — the view's state is not mutated while SwiftUI
        // is laying it out.
        .task(id: request) {
            phase = .loading
            progress = 0
        }
        // The visible control stays the primary path. The same dismissal is reachable as an accessibility action
        // on the page, and Escape does it from a hardware keyboard.
        .accessibilityAction(named: Text("Fechar")) { onClose() }
        #if DEBUG
        // The facts a journey cannot read out of the web process: whether the page is still at its top edge, and
        // the address that was requested (not the browser's current one). Invisible, non-interactive, no layout.
        .overlay(alignment: .bottomLeading) {
            ReaderWebWitness(atTop: atTop, address: request.url.absoluteString)
        }
        #endif
    }

    private var header: some View {
        HStack(spacing: FeedDesignTokens.Spacing.normal) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("reading.close")
            .accessibilityLabel(String(localized: "Fechar"))
            .keyboardShortcut(.cancelAction)

            Text(verbatim: source)
                .font(FeedDesignTokens.Typography.label)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityIdentifier("reading.web-source")

            Spacer(minLength: 0)

            // The escape, kept explicit: a site that needs Safari still has one, and it leaves the app instead
            // of opening a second presentation underneath the sheet the reader is in.
            Button(action: openInSafari) {
                Label("Safari", systemImage: "safari")
                    .font(FeedDesignTokens.Typography.label)
                    .lineLimit(1)
                    .fixedSize()
            }
            .accessibilityIdentifier("reading.open-safari")
            .accessibilityLabel(String(localized: "Abrir no Safari"))
        }
        .tint(appearance.accent)
        .padding(.horizontal, FeedDesignTokens.Spacing.compact)
        .padding(.vertical, FeedDesignTokens.Spacing.tight)
    }

    /// A fixed two points: it states the load's own progress (`estimatedProgress`) and never moves the page when
    /// it disappears, so finishing a load cannot shift the text the reader is reading.
    private var progressBar: some View {
        ProgressView(value: progress)
            .progressViewStyle(.linear)
            .tint(appearance.accent)
            .frame(height: 2)
            .opacity(phase == .loading ? 1 : 0)
            .accessibilityHidden(true)
    }

    /// The failure the platform reported, in the only words the app can stand behind, with the one action that
    /// exists: ask again. The control is never drawn for a load that is still running.
    private func failure(_ message: String) -> some View {
        VStack(spacing: FeedDesignTokens.Spacing.normal) {
            Text(verbatim: message)
                .font(FeedDesignTokens.Typography.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("reading.web-failure")
            Button(String(localized: "Tentar novamente")) {
                attempt += 1
                phase = .loading
                progress = 0
            }
            .accessibilityIdentifier("reading.web-retry")
        }
        .padding(FeedDesignTokens.Spacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appearance.pageBackground)
    }

    private func openInSafari() {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - The web view

struct ReaderWebContainer: UIViewRepresentable {
    let request: ReaderWebRequest
    let onProgress: (Double) -> Void
    let onPhase: (ReaderWebPhase) -> Void
    let onTopChange: (Bool) -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        // The standard browser the app can offer: JavaScript and inline playback on, the default cookie store
        // and the default user agent. No user script, no injected CSS, no custom scheme, no address rewrite —
        // the page is the publisher's, and the app only decides *when* it is loaded.
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = true
        context.coordinator.install(on: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // The app's body rebuilds while the page is up (a playback tick, a feed advance), so the closures the
        // page reports to are refreshed here — and the load is started only when the *request* changed.
        context.coordinator.update(onProgress: onProgress, onPhase: onPhase,
            onTopChange: onTopChange, onDismiss: onDismiss)
        context.coordinator.apply(request, to: webView)
    }

    /// The one way a request becomes a load. A retry's `attempt` is what makes it a new identity; the browser's
    /// current address never is.
    static func load(_ request: ReaderWebRequest, into webView: WKWebView) {
        #if DEBUG
        // The app's own fixture feed publishes `example.test` addresses. A journey that must drive the sheet's
        // gestures with no network asks for that page here; the address is the card's own, nothing is rewritten,
        // and the substitution is off unless the run says so.
        if let document = ReaderWebFixture.document(for: request.url) {
            webView.loadHTMLString(document, baseURL: nil)
            return
        }
        #endif
        webView.load(URLRequest(url: request.url))
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        /// The request whose load was started. This — not `webView.url` — is the identity the next render is
        /// compared with.
        private var requested: ReaderWebRequest?
        /// A dismissal was already asked for during this requested page; the gesture keeps emitting offsets and
        /// must not ask twice.
        private var dismissalRequested = false
        /// The page's top state last reported to the surface, so a scroll that does not change it is free.
        private var reportedTop = true
        /// Whether the current drag began with the page at its top edge. Latched at the first dragging report:
        /// a reader who scrolls back up through the article is not asking to dismiss it.
        private var gestureStartedAtTop = false
        private var wasDragging = false

        private var onProgress: (Double) -> Void = { _ in }
        private var onPhase: (ReaderWebPhase) -> Void = { _ in }
        private var onTopChange: (Bool) -> Void = { _ in }
        private var onDismiss: () -> Void = {}

        /// The platform act that starts a load. Production uses `ReaderWebContainer.load`; a test replaces it to
        /// observe the request identity without a network, which is the only way to exercise "a redirect is not
        /// a new input".
        var requestLoader: ((WKWebView, ReaderWebRequest) -> Void)?

        private var progressObservation: NSKeyValueObservation?
        private var offsetObservation: NSKeyValueObservation?

        func install(on webView: WKWebView) {
            webView.navigationDelegate = self
            // `estimatedProgress` and `contentOffset` are the platform's own accounts of the page. They are read
            // where they change; nothing is inferred from a timer.
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.onProgress(view.estimatedProgress) }
            }
            offsetObservation = webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.reportScroll(view) }
            }
        }

        func update(onProgress: @escaping (Double) -> Void, onPhase: @escaping (ReaderWebPhase) -> Void,
            onTopChange: @escaping (Bool) -> Void, onDismiss: @escaping () -> Void) {
            self.onProgress = onProgress
            self.onPhase = onPhase
            self.onTopChange = onTopChange
            self.onDismiss = onDismiss
        }

        /// Starts a load only when the request changed. The same request across a redirect, a playback tick or
        /// any other body rebuild is not a reason to load again.
        func apply(_ request: ReaderWebRequest, to webView: WKWebView) {
            guard requested != request else { return }
            requested = request
            dismissalRequested = false
            gestureStartedAtTop = false
            wasDragging = false
            if let requestLoader {
                requestLoader(webView, request)
            } else {
                ReaderWebContainer.load(request, into: webView)
            }
        }

        /// The scroll view's own report: the top state (for the surface), and — only while the reader is really
        /// dragging — the sheet's dismissal rule. A bounce after release, a load's own inset adjustment and a
        /// programmatic scroll all arrive with `isDragging == false` and cannot dismiss.
        private func reportScroll(_ scrollView: UIScrollView) {
            let topInset = scrollView.adjustedContentInset.top
            let atTop = ReaderSheetPullDown.isAtTop(contentOffsetY: scrollView.contentOffset.y,
                topInset: topInset)
            if atTop != reportedTop {
                reportedTop = atTop
                onTopChange(atTop)
            }

            if scrollView.isDragging {
                if !wasDragging {
                    wasDragging = true
                    // The state before this drag moved anything: `reportedTop` is the last settled position.
                    gestureStartedAtTop = reportedTop
                }
            } else {
                wasDragging = false
                gestureStartedAtTop = false
            }

            guard scrollView.isDragging, !dismissalRequested else { return }
            let pull = ReaderSheetPullDown.pull(contentOffsetY: scrollView.contentOffset.y,
                topInset: topInset)
            let translation = scrollView.panGestureRecognizer.translation(in: scrollView)
            guard ReaderSheetPullDown.dismisses(startedAtTop: gestureStartedAtTop, isTracking: true,
                verticalPull: pull, horizontalPull: translation.x) else { return }
            dismissalRequested = true
            // This runs inside the scroll view's own KVO pass; the app's surface stack is not mutated while a view is
            // being observed (the text page's identical rule). One main-actor hop later the same `onDismiss` runs.
            let dismiss = onDismiss
            Task { @MainActor in dismiss() }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onPhase(.loading)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onPhase(.ready)
            onProgress(1)
            reportScroll(webView.scrollView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error) {
            reportFailure(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportFailure(error)
        }

        /// A cancellation is not a failure: a redirect, a new load and the web process's own teardown all cancel
        /// provisional loads. Stating one as a failure would put "could not load" over a page that is loading.
        private func reportFailure(_ error: Error) {
            let failure = error as NSError
            if failure.domain == NSURLErrorDomain, failure.code == NSURLErrorCancelled { return }
            if failure.domain == "WebKitErrorDomain", failure.code == 102 { return }
            onPhase(.failed(message: String(localized: "Não foi possível carregar esta página.")))
        }
    }
}

#if DEBUG
/// The app's own answer for its fixture feed's pages, so a journey can drive a real, long publisher page with no
/// network. Only `FEEDMINE_READER_WEB_FIXTURE=1` enables it, and only the fixture's own hostname is served.
enum ReaderWebFixture {
    static let enabled = ProcessInfo.processInfo.environment["FEEDMINE_READER_WEB_FIXTURE"] == "1"

    static func document(for url: URL) -> String? {
        guard enabled, url.host == "example.test" else { return nil }
        return page
    }

    /// Long enough that scrolling is real: 80 paragraphs plus the sheet's own header.
    private static let page: String = {
        let paragraphs = (1...80).map {
            "<p>Parágrafo \($0): o texto que a fonte publicou, servido pelo próprio app para esta jornada.</p>"
        }.joined()
        return """
        <!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body { margin: 0 20px; font: 17px -apple-system, system-ui; color: #111; background: #fff; }
        h1 { font-size: 24px; margin: 20px 0 16px; }
        p { margin: 0 0 18px; line-height: 1.45; }
        </style></head><body>
        <h1>Página de teste do leitor</h1>
        \(paragraphs)
        <p id="end">Fim da página de teste.</p>
        </body></html>
        """
    }()
}

/// The web surface's own facts as one invisible accessibility element. It draws nothing and changes no layout.
private struct ReaderWebWitness: View {
    let atTop: Bool
    let address: String

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: atTop ? "atTop=1" : "atTop=0")
                .accessibilityIdentifier("reader-web-state")
            Text(verbatim: address)
                .accessibilityIdentifier("reader-web-address")
        }
        .font(.system(size: 1))
        .frame(width: 1, height: 1)
        .opacity(0)
        .allowsHitTesting(false)
    }
}
#endif
