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

## 10. Continuous-production boundary — Phase 3J design only

FeedWindow backwardCapacity / forwardCapacity bound disposable presentation materialization. They are not desired ready-ahead runway, refill/page sizes or acquisition targets. Published-ready runway measures already-published local presentation-ready occurrences ahead of the logical anchor in the visible Edition, independently of the current window. The future narrow measurement boundary is specified in [CONTINUOUS_FEED_RUNWAY_DESIGN.md](CONTINUOUS_FEED_RUNWAY_DESIGN.md); no query or session behavior is implemented here.

Normal future replenishment durably appends a new tail segment to the same Edition. A future publishedTailAdvanced notification permits later rematerialization around the unchanged logical anchor/placement and capacities; it does not reorder/remove visible history, force scrolling, replace Edition or implicitly checkpoint. Explicit successor preparation/swap remains separate. Existing Phase 2I restore, memory-local movement and explicit checkpoint semantics are unchanged.

Production pressure, progress, in-flight intent and diagnostics are operational Runtime state outside FeedPresentationSnapshot. No tailState, runwayState, refreshState or generation placeholder is added. Future separate RunwayObservation reports logical consumption measurements without production I/O; ViewportObservation remains anchor-only. Existing retained-history window materialization remains unchanged.

## 11. Feed presentation state boundary — Phase 3Q2

FeedMineUI now exposes one pure immutable FeedPresentationState. It contains only the optional received FeedPresentationSnapshot and a caller-reported Work condition: idle, pending, unavailable, deferred or failed(message:). No UI-facing state contract existed in the four UI scaffolds or FeedSessionUI before this gate. The new value closes that gap; FeedScreenStore, FeedScreen, FeedCardView and FeedLoadingView remain scaffolds. No screen store, subscription, effects, SwiftUI renderer or execution wiring is implemented.

| Received presentation | Work condition | Meaning |
| --- | --- | --- |
| nil | idle | No published presentation currently supplied; no claim of global exhaustion. |
| nil | pending | A real initial preparation opportunity is in progress. |
| snapshot | idle | Present the local published window immediately. |
| snapshot | pending | Keep the exact window visible during subsequent work. |
| nil or snapshot | unavailable | Current factual unavailability; preserve any presentation. |
| nil or snapshot | deferred | Work was deferred; preserve any presentation. |
| nil or snapshot | failed(message:) | Caller-supplied failure message; preserve any presentation. |

The caller supplies factual work reports. reporting(_) returns a value with unchanged presentation; loading/failure can never remove cards, Edition, context or anchor. No percentages, minimum loading duration, spinner policy, request budgets or automatic acquisition enter this contract. Receiving a snapshot does not imply all external work has settled: receiving(_) preserves the work condition until the caller explicitly reports another fact.

receiving(_) accepts a first snapshot, or another snapshot with the exact same Edition and context. An implicit identity replacement throws FeedPresentationStateError.presentationIdentityMismatch and leaves the prior value intact. Explicit context/Edition lifecycle and successor refresh remain future gates; this value performs neither. The snapshot remains the sole source of card order, PublicationCardID, context, Edition and PresentationAnchor. There are no separate card arrays, Edition fields, history cache or cursor. A caller can use the received anchor with the existing ViewportObservation contract; this gate introduces no new viewport identity or forwarding execution layer.

A finite window edge is a materialization boundary. It never produces a global exhausted state or reader intent. Runtime may supply another window of the same Edition in its exact published order, including a new logical anchor accepted by FeedSession. Ordinary viewport movement/checkpoint rules remain unchanged.

ColdFeedBootstrap and FeedRunwayDriver outcomes/errors are interpreted by their external composition, not imported into FeedMineUI. A published snapshot is received as-is; unavailable and deferred stay distinct caller reports. Local work remaining or no publication after one finite opportunity remain absence of a supplied presentation rather than definitive empty feed. Pending must be explicitly reported for actual work. Any existing presentation survives subsequent failures. This gate creates no autonomous mapping/execution machinery.

The UI implementation imports only FeedMineRuntime and performs no HTTP, database access, Selection, Publication, Acquisition coordination, Runway execution, timer, retry or background work. FeedSession retains viewport/presentation authority; the finite bootstrap and continuous driver retain their separate production ownership.

FeedPresentationStateTests lives in ArchitectureSmokeTests because Package.swift has no FeedMineUITests target and the existing smoke target already depends on UI and the needed fixture modules. The 12 substantive tests obtain real snapshots through temporary durable publication and FeedSession, then exercise pure state transitions: T1–T9, initial pending-to-presentation arrival, different-Edition rejection and different-context rejection. Cold bootstrap, driver and Runtime regressions cover T10. Package.swift and all non-UI production contracts remain unchanged.
