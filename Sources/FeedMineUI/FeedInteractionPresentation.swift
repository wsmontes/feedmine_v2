import FeedMineDomain
import FeedMineRuntime

/// A borrowed value for one native interaction, not another admission or history store.
@MainActor
struct FeedInteractionPresentation {
    private var held: FeedPresentationSnapshot?
    private var owner: ObjectIdentifier?
    private var releaseAnchor: PublicationCardID?
    private(set) var deferredWindows = 0
    var isHolding: Bool { held != nil }

    mutating func begin(_ presentation: FeedPresentationSnapshot?, owner: ObjectIdentifier) {
        // A new gesture supersedes an idle acknowledgement still in flight.
        releaseAnchor = nil
        guard held == nil else { return }
        held = presentation
        self.owner = owner
    }
    mutating func end() { held = nil; owner = nil; releaseAnchor = nil }
    mutating func end(afterReading card: PublicationCardID?, store: FeedScreenStore) {
        guard let held, presentation(for: store) == held else { end(); return }
        if let card, let current = store.state.presentation,
            !current.window.items.contains(where: { $0.id == card }) {
            releaseAnchor = card
            return
        }
        end()
    }

    func presentation(for store: FeedScreenStore) -> FeedPresentationSnapshot? {
        guard let current = store.state.presentation, let held,
            owner == ObjectIdentifier(store), current.contextKey == held.contextKey,
            current.editionID == held.editionID,
            current.provenance.sequenceID == held.provenance.sequenceID else { return store.state.presentation }
        return held
    }
    mutating func noteIncoming(_ store: FeedScreenStore) {
        guard let held else { return }
        guard presentation(for: store) == held, let current = store.state.presentation else {
            end()
            store.setReadingInteractionActive(false)
            return
        }
        if let releaseAnchor, current.window.items.contains(where: { $0.id == releaseAnchor }) {
            end()
            store.setReadingInteractionActive(false)
            return
        }
        if held.window.items.map(\.id) != current.window.items.map(\.id) { deferredWindows += 1 }
    }
}
