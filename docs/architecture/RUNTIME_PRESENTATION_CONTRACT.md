# Runtime presentation contract — Phase 2I

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

No checkpoint returns nil, without a fake empty snapshot. Errors propagate. Restore is synchronous and read-only: no checkpoint timestamp update, selection, network, catalog, canonical supply or media bytes. FeedSession is now an actor owning explicit current local state through one optional internal FeedSessionState. Its only other stored property is the immutable PublicationHistory dependency. Local history operations remain synchronous; external callers use await for actor isolation, without an async wrapper. Successful restore installs the snapshot and supplied capacities; no checkpoint clears state; a failed restore preserves prior state. currentPresentation returns the installed snapshot without I/O.

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

FeedSessionUI, AsyncStream, reducer/effects, intents, runway, refresh, context switching, exposure, action execution, media materialization, cold-start bootstrap and UI implementation remain deferred.

## 7. UI dependency boundary

FeedMineUI consumes only FeedMineDomain, FeedMineRuntime and Foundation types. PresentationCard, FeedWindowSnapshot and FeedPresentationSnapshot expose no Publication, Persistence or Media types. Their Publication projection initializers are internal.

The explicitly approved composition exception is `FeedSession.init(publicationHistory:)`: this public initializer accepts PublicationHistory so composition can supply the semantic boundary. It exposes a Publication type only at construction; `restoreLocalPresentation` returns solely Runtime presentation values. FeedSession does not accept RuntimeDatabase or mechanical stores. UI does not construct this dependency or import Publication.

## 8. Local viewport movement

ViewportObservation contains only a logical PresentationAnchor, with a non-failable initializer and no timestamp or telemetry. No viewport observation performs acquisition.

Without state, submitViewport returns nil without I/O. Stale observations whose card is absent from the current window are ignored. An identical anchor is a no-op, with no read or mutation. Placement-only changes are valid.

An accepted observation moves the finite window within one immutable Edition using the capacities supplied at restore. It materializes retained local history, projects a new snapshot, and installs in-memory state only after successful materialization. A materialization failure propagates and preserves the previous presentation. ContextKey and EditionID stay unchanged, and published history is never modified or deleted. At local history boundaries the window contains only what exists.

FeedSessionState contains exactly presentation, backwardCapacity and forwardCapacity; it does not duplicate context, Edition or anchor. Actor isolation establishes one mutable state owner without locks, detached tasks or queues.

Viewport movement updates the actor-owned current local session state but does not itself durably checkpoint that state. After moving from a saved P4/center to a current P6/center, reopening restores P4/center because ordinary scroll never writes the SQLite checkpoint. Placement-only changes are also memory-local.

## 9. Explicit session checkpoint milestone

viewport movement = memory-local. checkpointCurrentPosition(at:) = explicit durability boundary. The operation converts the current presentation Edition and logical top/center anchor into a SessionCursor and saves it through PublicationHistory.saveCursor. It returns false without I/O when no state exists, and true after a successful save. It does not change presentation, capacities or any in-memory state. Persistence validates the supplied date; failures propagate while preserving both current memory state and the previous durable cursor.

Without a milestone, scrolling from durable P4/center to current P6/center and reopening restores P4/center. With an explicit milestone after that scroll, reopening restores P6/center. Top placement remains top. An explicit milestone without movement may write the same logical position again with the supplied metadata time; no extra idempotency optimization is introduced.

FeedSession does not decide when lifecycle milestones occur. App lifecycle wiring, automatic save policy, checkpoint batching, UI streams, exposure and Runway remain deferred.
