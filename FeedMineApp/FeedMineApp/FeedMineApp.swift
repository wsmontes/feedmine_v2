import SwiftUI
import FeedMineUI

@main
struct FeedMineApp: App {
    @State private var composition = AppComposition()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Group {
                if let association = composition.association {
                    FeedScreen(store: association.store)
                        #if DEBUG
                        .overlay(alignment: .topTrailing) {
                            Text("received=\(association.viewportReceived) completed=\(association.viewportCompleted) backward=\(association.backwardCompleted)")
                                .font(.system(size: 8)).padding(2).background(.background)
                                .accessibilityIdentifier("native-viewport-delivery")
                                .allowsHitTesting(false)
                        }
                        #endif
                } else if let failure = composition.startupFailure {
                    Text(failure).padding()
                } else {
                    ProgressView("Abrindo feed local")
                }
            }
            .task { await composition.launch() }
            .onChange(of: phase) { _, next in
                if next == .background { Task { await composition.background() } }
                if next == .active { Task { await composition.foreground() } }
            }
        }
    }
}
