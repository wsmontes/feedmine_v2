// File: ToastView.swift
// Module: FeedMineUI
// Owns: the transient reader feedback message, copied from V1 `Views/ToastView.swift` and its
//       presentation values (FeedScreen 1097–1119: black capsule, bottom 100, spring 0.35/0.8, 2 s).
// Does not own: what deserves a message. The host states it; this view only draws and dismisses it.

import SwiftUI

public struct ToastView: View {
    public let message: String
    public let systemImage: String?

    public init(message: String, systemImage: String? = nil) {
        self.message = message
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(verbatim: message)
                .lineLimit(2)
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.8), in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        // Feedback must never intercept a gesture or move content (T3): it is decoration over the feed.
        .allowsHitTesting(false)
        // The message stays a text of its own inside the toast's own element, so what the app says is
        // readable as what it says.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader-toast")
    }
}

/// V1's toast lifetime: 2 s, spring 0.35/0.8, at the bottom 100 pt above the safe area.
/// V1's lifetime: 2 s, spring 0.35/0.8, 100 pt above the bottom safe area. The host owns the message;
/// the shell only owns how long it stays on screen.
public struct ReaderToastModifier: ViewModifier {
    public let message: ReaderToastMessage?
    public let onDismiss: () -> Void

    public init(message: ReaderToastMessage?, onDismiss: @escaping () -> Void) {
        self.message = message
        self.onDismiss = onDismiss
    }

    public func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                ToastView(message: message.text, systemImage: message.systemImage)
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message.id) {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        onDismiss()
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: message)
    }
}

/// One toast occurrence. Identity is explicit so a repeated identical message restarts its lifetime.
public struct ReaderToastMessage: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let text: String
    public let systemImage: String?

    public init(text: String, systemImage: String? = nil) {
        id = UUID()
        self.text = text
        self.systemImage = systemImage
    }
}

public extension View {
    func readerToast(_ message: ReaderToastMessage?, onDismiss: @escaping () -> Void) -> some View {
        modifier(ReaderToastModifier(message: message, onDismiss: onDismiss))
    }
}
