// SwiftUI reads the sole observable store and presents its finite local window.
// Factual automatic reading-position capture is deferred; view creation emits no observations.
import SwiftUI

@MainActor
public struct FeedScreen: View {
    private let store: FeedScreenStore

    public init(store: FeedScreenStore) {
        self.store = store
    }

    public var body: some View {
        if let presentation = store.state.presentation {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(presentation.window.items) { card in
                        FeedCardView(card: card)
                    }
                }
                .padding()
            }
        } else {
            FeedLoadingView(work: store.state.work)
        }
    }
}
