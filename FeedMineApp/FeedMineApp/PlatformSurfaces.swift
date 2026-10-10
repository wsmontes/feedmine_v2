//
// File: PlatformSurfaces.swift
// Module: FeedMineApp
//
// Responsibility:
// The two platform surfaces a card action ends at: the pasteboard and the share sheet. They live in the app so
// no renderer and no package target ever touches UIKit's pasteboard or presents an activity view (T9's rule).
//
// Does not own: resolving what is copied or shared (the action coordinator does) or any layout.
import SwiftUI
#if os(iOS)
import UIKit
#endif

enum PlatformPasteboard {
    /// V1's "copy link" put the URL itself on the clipboard (`item.url`, not a formatted line).
    @discardableResult
    static func copy(_ text: String) -> Bool {
        #if os(iOS)
        UIPasteboard.general.string = text
        return true
        #else
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

/// What is being shared, so the sheet has an identity to present.
struct SharedLink: Identifiable {
    let id = UUID()
    let url: URL
    let subject: String
}

#if os(iOS)
/// V1 presented its share sheet through `UIActivityViewController`; SwiftUI has no programmatic equivalent, so
/// the small representable is the adapter — and it carries the link alone, exactly as V1 shared it.
struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    let subject: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
