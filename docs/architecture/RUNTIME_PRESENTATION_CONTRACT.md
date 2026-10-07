# Runtime presentation contract — Phase 2G

## 1. Purpose

Prove the warm/offline vertical slice from retained local publication to an immutable presentation-ready Runtime snapshot. Projection is disposable and reconstructible. Publication remains authority. Presentation values are neither persisted nor cached and never reconstruct publication.

## 2. Warm restore path

```text
runtime.sqlite
        ↓ PublicationHistory.restore()
RestoredPublication
        ↓ FeedSession.restoreLocalPresentation()
FeedPresentationSnapshot
        ↓ FeedWindowSnapshot
PresentationCard[]
```

No checkpoint returns nil, without a fake empty snapshot. Errors propagate. Restore is synchronous and read-only: no checkpoint timestamp update, selection, network, catalog, canonical supply or media bytes. FeedSession holds only an immutable PublicationHistory dependency, with no current session state, actor, lock or async wrapper. The future owner chooses the executor for local database work.

backwardCapacity / forwardCapacity are finite materialization bounds, not page size, feed size or runway strategy. They are explicit caller inputs with no defaults; zero/zero restores the anchor alone. Published order and the exact anchor occurrence/placement remain unchanged.

## 3. Publication → Runtime projection

```text
PublishedCard
        ↓ Runtime projection
PresentationCard

RestoredPublication
        ↓
FeedPresentationSnapshot
```

Internal projection copies exact optional text, frozen display attribution, timestamp value and meaning, layout, aspect ratio and action affordance kind. It performs no normalization, catalog lookup or duplicate publication business validation. Action targets and backend provenance are deliberately omitted.

## 4. PresentationCard surface

PresentationCard is Identifiable, Hashable and Sendable, with only id, title, primaryText, timestamp, sourceDisplayName, providerDisplayName, layout, mediaAspectRatio and primaryActionKind. Runtime owns the layout, timestamp-kind and action-kind enums. Observed timestamps remain observed; absent values remain absent.

The card has no origin/revision/source/provider/entity/cluster IDs, media key/reference, remote target, bytes, path or image object. Hero/thumbnail layout and ratio support deterministic placeholder geometry until a concrete media materializer exists. Future action intents identify a PublicationCardID; Runtime will resolve and execute them.

## 5. FeedPresentationSnapshot baseline

The top-level snapshot has exactly contextKey, editionID and window. FeedWindowSnapshot has only items and anchor. Its public failable initializer rejects empty items, duplicate occurrence IDs and absent anchors without sorting or deduplication. Internal projection from a validated FeedWindow preserves these invariants. PresentationAnchor is cardID plus Runtime-owned top/center placement, never pixels.

Snapshot existence means a local Edition and semantically presentable local cards are ready. No generation, supersedesGeneration, phase, tailState, refreshState or transition placeholder is introduced.

## 6. What is deliberately deferred

Mutable FeedSessionState ownership, FeedSessionUI, AsyncStream, reducer/effects, intents, viewport observations, scroll shifts, runway, refresh, context switching, exposure, action execution, media materialization, cold-start bootstrap and UI implementation remain deferred.

## 7. UI dependency boundary

FeedMineUI consumes only FeedMineDomain, FeedMineRuntime and Foundation types. PresentationCard, FeedWindowSnapshot and FeedPresentationSnapshot expose no Publication, Persistence or Media types. Their Publication projection initializers are internal.

The explicitly approved composition exception is `FeedSession.init(publicationHistory:)`: this public initializer accepts PublicationHistory so composition can supply the semantic boundary. It exposes a Publication type only at construction; `restoreLocalPresentation` returns solely Runtime presentation values. FeedSession does not accept RuntimeDatabase or mechanical stores. UI does not construct this dependency or import Publication.

## 8. Next runtime step

A future phase may establish explicit FeedSessionState ownership and the necessary coordination semantics before adding UI streams, intents or viewport-driven changes. Phase 2G stops at warm restore and pure immutable projection; it does not implement that next step.
