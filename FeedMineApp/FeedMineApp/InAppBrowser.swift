// U2: in-app reading. The composition resolves the frozen card action to a URL; the app host
// presents it with the system in-app browser. SafariServices keeps the reader inside the app
// (reader mode, share, translation) without us maintaining a web engine or its security surface.
import SwiftUI
import SafariServices

struct InAppBrowser: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: { dismiss() })
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
