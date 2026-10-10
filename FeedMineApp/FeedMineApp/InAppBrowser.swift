// U2: in-app reading. The composition resolves the frozen card action to a URL; the app host
// presents it with the system in-app browser. SafariServices keeps the reader inside the app
// (reader mode, share, translation) without us maintaining a web engine or its security surface.
import SwiftUI
import SafariServices

struct InAppBrowser: UIViewControllerRepresentable {
    let url: URL
    /// The reader's own way out, reported to the host: the host owns the presentation, so it is the host that
    /// clears the state the sheet was presented from. `dismiss()` here would leave that state set, and a
    /// presentation whose item is still set is one SwiftUI may keep or re-present.
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.delegate = context.coordinator
        controller.dismissButtonStyle = .close
        controller.preferredControlTintColor = UIColor.tintColor
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    /// The close button belongs to Safari's own controller, so dismissal must come back through it.
    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onFinish() }
    }
}
