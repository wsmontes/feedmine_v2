# Runtime presentation contract — Phase 2I

## 1. Purpose

Prove the warm/offline vertical slice from retained local publication to an immutable presentation-ready Runtime snapshot. Projection is disposable and reconstructible. Publication remains authority. Presentation values are neither persisted nor cached and never reconstruct publication.

## 2. Warm restore path

```text
runtime.sqlite
        ↓ PublicationHistory.restore()
RestoredPublication
        ↓ FeedSession.admitPresentation(.restore(bounds))
FeedPresentationSnapshot
        ↓ FeedWindowSnapshot
PresentationCard[]
```

No checkpoint returns nil, without a fake empty snapshot. Errors propagate. Restore is synchronous and read-only: no checkpoint timestamp update, selection, network, catalog, canonical supply or media bytes. FeedSession is now an actor owning explicit current local state through one optional internal FeedSessionState. Its only other stored property is the immutable PublicationHistory dependency. Local history operations remain synchronous; external callers use await for actor isolation, without an async wrapper. Successful restore installs the snapshot and the supplied bounds, frozen for the life of that presentation; no checkpoint clears state; a failed restore preserves prior state. currentPresentation returns the installed snapshot without I/O.

backwardCapacity / forwardCapacity are finite materialization bounds, not page size, feed size or runway strategy. They are explicit caller inputs with no defaults; zero/zero restores the anchor alone. Published order and the exact anchor occurrence/placement remain unchanged.

**What the restore reaches behind the cursor is the presentation's own bound** (2026-10-14). A list whose `FeedPresentationBounds.keepsAdmittedHead` is `true` held every card above the reader for the life of the session, so its restore reaches the Edition's first card (`PublicationHistory.restoreFromEditionStart`) instead of `backwardCapacity` cards behind the cursor — otherwise the reopen itself drops what the reader had already passed, and a card they saved above the durable position is not drawn at all (B05: the saved card stood 22 cards above the durable position and was absent after terminate+launch). `backwardCapacity` still bounds decoded-image residency and backward navigation there. A list bounded around the reader keeps the bounded restore: it re-reads a cut card on the next backward admission. The reach is the Edition, with no cap below it: a cap would be the same defect for a reader who read past it. Measured cost on this host (800-card Edition, durable position at the 750th, hero images): the bounded restore admitted 25 cards in 53 ms with 25 decodes; the head restore admitted 766 cards in 88 ms with the same 25 decodes — the extra cards are values and released bitmaps, and the pixels stay the residency band's.

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

The explicitly approved composition exception is `FeedSession.init(publicationHistory:)`: this public initializer accepts PublicationHistory so composition can supply the semantic boundary. It exposes a Publication type only at construction; `admitPresentation` returns solely Runtime presentation values. FeedSession does not accept RuntimeDatabase or mechanical stores. UI does not construct this dependency or import Publication.

## 8. Local viewport movement

ViewportObservation contains only a logical PresentationAnchor, with a non-failable initializer and no timestamp or telemetry. No viewport observation performs acquisition.

Without state, submitViewport returns nil without I/O. Observations whose card is absent from the admitted items are ignored. An identical anchor is a no-op, with no read or mutation. Placement-only changes are valid and allocate a new projection only for the anchor.

An accepted observation records exposure, moves the logical anchor inside the admitted items and bounds decoded-image residency around it; it never materializes a new window. Only `admitPresentation(.forwardScroll(observation))` and `admitPresentation(.publishedGrowth)` extend the admitted list. The forward-scroll case requires the observation to still be the reader's current anchor; the growth case carries no observation at all — the runtime owns it (R4/F05), because the first open must present the cards the local store already published instead of waiting for a scroll nobody made. Both append already-published cards that follow the admitted tail, bounded by the frozen forward capacity, so nothing is inserted above the reader and no admitted card changes; the growth case additionally leaves the anchor, the reading position and the provenance order of the existing cards untouched, and is a no-op when nothing new is published. At local history boundaries the append adds nothing and the screen is preserved. ContextKey and EditionID stay unchanged, and published history is never modified or deleted.

FeedSessionState contains exactly editorialRevisionID, presentation and the frozen FeedPresentationBounds; it does not duplicate context, Edition or anchor.

## 8a. Decoded-image residency (T3)

Decoded pixels are residency, not identity. Only cards inside the frozen bounds around the reader keep their `CGImage`; cards outside keep their frozen descriptor — layout, aspect ratio, text, action, source — and release the bitmap through `PresentationCard.releasingDecodedImage()`. Returning to one decodes the same local asset again (`withDecodedImage(_:)`), so a released card is never "upgraded": the layout decided at publication is what it renders, and no slot changes geometry. `releasedImageCards` records which cards were released on purpose, so a genuinely absent asset is not retried on every observation. Re-entering already-admitted history re-materializes decoded pixels only; it is not an admission. Actor isolation establishes one mutable state owner without locks, detached tasks or queues.

Viewport movement updates the actor-owned current local session state but does not itself durably checkpoint that state. After moving from a saved P4/center to a current P6/center, reopening restores P4/center **until the app wires the settled observation to the durability boundary below**; `submitViewport` itself never writes. Placement-only changes are also memory-local.

## 9. Explicit session checkpoint milestone

viewport movement = memory-local. checkpointCurrentPosition(at:) = explicit durability boundary. The operation converts the current presentation Edition and logical top/center anchor into a SessionCursor and saves it through PublicationHistory.saveCursor. It returns false without I/O when no state exists, and true after a successful save. It does not change presentation, capacities or any in-memory state. Persistence validates the supplied date; failures propagate while preserving both current memory state and the previous durable cursor.

Without a milestone, scrolling from durable P4/center to current P6/center and reopening restores P4/center. With an explicit milestone after that scroll, reopening restores P6/center. Top placement remains top. When the app states a **presented top card** (§9a), that card is what the record names with `.top`, and the window's own anchor is used only when the app states none or names a card the admitted window does not carry: a record may never name a position nobody can restore. An explicit milestone without movement may write the same logical position again with the supplied metadata time; no extra idempotency optimization is introduced.

### 9a. Debounced durability of the settled position (PO, 2026-10-14)

Requirement ratified by the owner: returning to the app must recover the reader's position **also after a forced close**. A forced close runs no lifecycle milestone at all, so a durable cursor written only by milestones recovers the beginning of the Edition instead of what the reader was reading (measured, B05 2026-10-14: `context_checkpoints.card_id` still pointed at the Edition's first card, `updated_at == feed_editions.created_at`).

`recordSettledPosition(at:settled:)` is the second durability boundary of the same owner. **What it names is the reader's viewport position — the card the reader's screen starts at, pinned to the top edge — and not the card the reader is on.** The window's anchor is the card the capture picks by its reference line (the viewport's middle), and a record that names it is **incomplete**: the distance from that line to the card's top edge is not part of a record that never carries pixels, so a restore that honours it lands on a neighbouring card. Measured (2026-10-14, on the reopen clause of B05 and on the app's own UI test): with the reader's card at y=399 and the top card at y=234 inside an 834 pt viewport, a cold start that honoured the reader's card drew its top card 4–5 cards away from the one measured before the forced close, and centring that card put *another* card at the top. The presented top card reproduces the measured card exactly, because pinning its top edge to the viewport's top edge is the one alignment the record determines. **Declared spatial loss: the offset inside the first card (at most one card height)** — the card identity that acceptance measures is exact; the pixels below it are not part of a position.

The record is stated by the app's own rendering — `FeedScreenStore.publishPresentedPosition(_:atRest:)` forwards it and `FeedSession.notePresentedPosition(_:atRest:)` remembers it, from the capture's card geometry: the first card whose top edge is at or below the viewport's top edge — and `FeedSession` refuses a card the current admitted window does not hold, falling back to the window's anchor. The choice is made in **content coordinates** (`frame.minY + offset`, invariant while the reader scrolls), because — and those coordinates are kept aligned when the content **above** the reader changes size: a reporting card whose coordinate and offset moved by the **same** amount is the signature of an insert/removal (a scroll moves only the offset), and the same shift is then applied to every stored entry before the choice is recomputed, because the cards that do not report again would otherwise keep an aged coordinate, be discarded by the offset filter as if they were above the viewport, and let the choice fall to a deeper card — measured in B05 and reproduced deterministically in `FeedViewportCaptureTests.testWindowHeadThatGrowsAboveTheChoiceMustNotMoveThePresentedTop` (8 where the screen showed 6) — because card bounds measured *in the viewport* during different layout passes are not comparable: the first version compared them and published six different positions in a single rest, with the cursor ending on a card that was not the one at the top of the screen (measured 2026-10-14, B05). The temporal rule has two parts, and the second is what makes the declared tolerance small in practice:

- **The position a reader holds at rest is recorded at once.** `settled: true` is the app's own semantic rest, and it now arrives from two facts that both come from the rendering: the capture's settle (`RunwayActivity.stationary`, once per gesture rest) and the rendering coming to rest at a **distinct** position with no gesture at all (`FeedScreenStore.publishPresentedPosition(_:atRest:)` — an accessibility scroll, a system animation, a programmatic scroll). The second one exists because a viewport can move without a reader's gesture: measured in B05 (2026-10-14), the driver's own scroll-to-visible moved the reader's screen ~8 cards, the app registered no observation, and the forced close returned to a position the reader had already left. A rest never waits for a window, so a reader who stops loses nothing.
- **While the reader is moving**, a write happens at most once per `FeedSession.settledPositionDebounceWindow`. **Declared maximum debounce loss: 20 seconds** — a forced close *during movement* can lose at most the reading advance of the last 20 seconds of scrolling, and nothing more. The ordinary ways of leaving the app keep writing the exact position with no window at all (background/suspend, context switch, session replacement, edition creation — each now stating the same presented top card), so the declared loss only covers sudden death while the reader is still moving.
- **Uma correção nativa do offset termina quando o layout reporta a geometria corrigida** (`FeedNativeScrollOffset`). A supressão que impede a própria escrita da correção de virar movimento do leitor era desfeita apenas por um gesto; enquanto ficava de pé, toda mudança de geometria saía pelo ramo de correção e todo callback de carta era consumido por ela — a captura nunca reaprendia o que o desenho mostrava, e a posição do viewport congelava na carta anterior à correção (medido em B05, 2026-10-14: o cursor durável nomeava o card 13 enquanto a carta do topo desenhada era a 6, sete cartas atrás, e a reabertura desenhou a tela errada). Ela agora termina onde a testemunha da correção é consumida — o primeiro reporte da geometria corrigida —, que é exatamente o ponto em que os resíduos da correção já eram medidos.

**Uma afirmação incompleta não substitui uma exata** (lead, 2026-10-14), no limite **automático** da durabilidade — o que dispara sozinho a partir do desenho, `recordSettledPosition(at:settled:)`. É **exata** a escrita que afirma a carta do topo do viewport (`.top`, declarada pela captura); é **aproximada** a que cai na âncora da janela (`.center`) porque a sessão que escreve não tem posição apresentada. Uma escrita aproximada **não** substitui um registro exato da mesma edição — fica o que já estava —, e uma escrita exata vence por ser mais nova. A comparação lê o registro que **uma restauração leria** (o do contexto, senão o singleton) e é paga **somente** no caminho aproximado: uma afirmação exata escreve sem ler nada. Duas afirmações aproximadas continuam competindo (a mais nova vence), um registro de outra edição não é uma afirmação concorrente, e a ausência de registro também não — nos dois a escrita passa. `SettledPositionRecording.keptExactRecord(cardID:)` é o desfecho que declara o caso. Um **milestone** (`checkpointCurrentPosition(at:)`) fica de fora de propósito: é uma afirmação explícita do chamador, e §9 (com `testO15…`) fixa o contrato de que um milestone escreve a posição que declara. Sem a regra no limite automático, a associação reconstruída pela volta A→B→A sobrescrevia a posição exata do leitor com o seu próprio ponto de restauração 145 ms depois de o desenho tê-la afirmado (B05, 2026-10-14: o cursor durável ficou no card 15 enquanto a carta do topo desenhada era a 7). Custo medido nesta máquina, lado a lado (`FeedSessionCheckpointTests.testTheDurabilityWriteCostsFarLessThanOneFramePerWindow`, 200 escritas de cada caminho): a escrita aproximada — a que paga a leitura de uma linha — custa **1,018 ms** e a exata — a comum, que não lê nada — **0,607 ms**; a comparação cabe em ~0,4 ms, muito abaixo do quadro de 16,67 ms.

**What the restore does with it**: `FeedScreen`'s scroll position names the recorded card and nothing else, and the scroll view's own alignment pins that card's **top edge to the viewport's top edge** — measured twice on 2026-10-14 (the dev-feed UI test and the B05 run: the restored card's top landed at y=121.8 against a viewport top of 122). That is exactly what the record's placement (`.top`) means, so the record the code now writes is honoured exactly. Passing an explicit `anchor: .top` to `scrollPosition(id:anchor:)` was tried and reverted: it re-aligns the identified card on every window mutation and moves the reader's visible position (`FeedViewportCaptureTests.testNativeHostedLayoutPreservesPositionWithoutInventingReading`, 440 → 369). An older row (`.center`, written by the previous build, naming the reader's card) keeps the previous build's behaviour — pinned at the top — and the next rest rewrites it as `.top`. The presentation is materialized around the same card with the frozen capacities, so the card and what follows it are already admitted.

**Declared cost, against the fluidity budget** (the frame meter's 16,67 ms per frame at 60 Hz): at most `60 / 20` = **3 durable writes per minute while moving**, plus **one per rest** (a reader who never moves produces none), plus one on the first settled observation of each association, plus the milestone writes that already existed. Each write is a one-row upsert in SQLite executed on `FeedSession`'s own executor — never in a view body, never on the main actor, never inside a frame. Measured on this machine: 0,82 ms per write (`FeedMineRuntimeTests.FeedSessionCheckpointTests.testTheDurabilityWriteCostsFarLessThanOneFramePerWindow`, 200 writes). `SettledPositionRecording` states which of the four outcomes happened (nothing to record, already durable, inside the window with the remaining time, or written) so the run's own record can tell a skip from a write; the app writes a `position_checkpoint` trace event with the declared window beside the anchor.

FeedSession does not decide when lifecycle milestones occur. App lifecycle wiring, automatic save policy, checkpoint batching, UI streams, exposure and Runway remain deferred — the app states *when* (a settled viewport opportunity it has admitted and installed) and this owner states *how often*.

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

## 12. Explicit presentation handoff and viewport bridge — Phase 3Q3

Discovery found no executable presentation bridge in Composition. FeedSession exposes currentPresentation, admitPresentation and submitViewport; ColdFeedBootstrap.run returns its finite typed outcome; FeedRunwayDriver exposes restoreAndActivate, activateCurrentPresentation, submitViewport and drive. Their snapshots already satisfy the immutable UI contract. FeedScreenStore/FeedScreen and the environment/object-graph scaffolds remain unimplemented. The gap is typed result interpretation and explicit continuous viewport forwarding, not snapshot projection or a second runtime.

FeedPresentationHandoff is a stateless namespace of composition functions. It stores no dependencies, current UI state, cards, Edition, anchor, cursor, checkpoint, supply or Runway intent. Each caller provides the existing FeedPresentationState; functions return the next value by its unchanged receiving(_) and reporting(_) APIs. No initializer, additional actor, subscription, task or automatic execution exists.

| Explicit input | Handoff |
| --- | --- |
| Warm restored or continuous driver snapshot | receive(snapshot:into:) forwards the exact snapshot. |
| nil snapshot | Returns the exact prior state, including its work condition. |
| Cold published snapshot | Receives it unchanged, then reports idle for the settled finite opportunity. |
| Cold localWorkRemaining / noPublicationAfterAcquisition | Reports idle for that completed finite opportunity; retains any visible snapshot, and makes no global-exhaustion claim. |
| Cold unavailable / deferred | Reports unavailable / deferred distinctly without replacing content. |
| Acquisition executed | Reports only settled work; neither receipts nor selectable supply changes create visual success. |
| Acquisition acceptedUnavailable / deferred | Reports unavailable / deferred; retains content. |
| Caller-reported actual pending/completion/failure | report(_:into:) delegates to reporting(_), preserving presentation. |

The caller explicitly invokes warm restore or cold/continuous work, then hands off the result. Raw snapshots do not settle work automatically: the caller reports completion when appropriate. Work facts refer to the explicit opportunity, not a claim about global feed availability or all concurrent work. Error messages remain an explicit external choice; underlying operation and identity errors propagate. The caller retains its prior value on failure and may report failed(message:) without clearing it. No error recovery, fallback or repeat opportunity is introduced.

submitViewport(_:activity:resources:driver:into:) forwards the exact ViewportObservation, semantic RunwayActivity and physical resources once to the existing FeedRunwayDriver.submitViewport. Only the returned snapshot is handed off. FeedSession still owns the logical movement and the frozen bounds; Runway still owns production intents. The bridge creates no second cursor, scroll algorithm, HTTP operation or window-end inference. PublicationCardID, top/center placement, published order, Edition/context and anchor are all retained from Runtime. receiving(_) still rejects implicit Edition/context replacement.

External composition continues to supply one shared AcquisitionCoordinator to cold and continuous consumers over the same database. The bridge never constructs or stores a coordinator, queries a store, runs Selection/Publication, writes a checkpoint or retains history. Receiving/reporting starts no work. Only the explicit viewport call delegates an opportunity to the existing driver.

FeedPresentationHandoffTests contains 16 focused tests over real temporary RuntimeDatabase, publication history, FeedSession, ColdFeedBootstrap, FeedRunwayDriver, shared coordinator and bounded local URLProtocol transport. H1–H11 prove warm/cold/continuous handoff, suspended-work preservation, factual dispositions, original-error propagation, exact viewport identity, no swap, no inferred exhaustion, shared ownership, no extra checkpoint and no hidden work. Additional tests prove real acquisition success without visual publication, checkpoint-only cold settlement, real nonexhausted local miss, nil driver return preservation and static ownership boundaries. H12 reruns the existing cold/driver/UI-state/Runtime regressions. No previous production contract or UI scaffold changes.


## 13. Minimal observable screen store — Phase 3Q4

FeedScreenStore closes the observable/intent boundary; the previous file declared no implementation. It is a MainActor class using native Observation (@Observable), supported by the current Swift 6 package and macOS 14/iOS 18 platforms. A future SwiftUI consumer reads store.state, the only authoritative FeedPresentationState. The store retains no separate cards, identity, anchor, cursor, history, work enum or Runtime owner. No renderer is introduced.

The explicit public contract is:

- init(onViewport:): starts with FeedPresentationState(presentation: nil), idle, and stores a synchronous MainActor consumer of ViewportObservation and RunwayActivity. Construction invokes no consumer or work.
- install(_:): accepts FeedPresentationState computed by external composition. For a supplied snapshot it invokes the current state's receiving(_); for no snapshot it retains current presentation. It applies the supplied work using reporting(_) and installs the resulting single observable value only after successful reception.
- submitViewport(_:activity:): forwards exact Runtime semantic values once to the injected consumer. It performs no execution or state change of its own.

Composition computes delivery with FeedPresentationHandoff using the store's current state. Installation also delegates to the existing receiving(_) fence, so a supplied complete state cannot bypass same-Edition/context acceptance. Identity failure propagates and leaves the current value intact. This adds no duplicate identity comparison. A state without a new snapshot can change work but cannot erase existing presentation. Pending, failed, deferred and unavailable preserve the Runtime projection; absence and a finite window edge never imply global exhaustion. Order, occurrence IDs, Edition, context and top/center anchor remain the exact Runtime values.

The callback is intentionally synchronous and semantic. UI imports neither FeedMineComposition nor driver resources. External composition resolves physical resources, explicitly calls FeedPresentationHandoff.submitViewport with its existing driver, handles errors through the existing factual work contract, and installs the returned state on MainActor. The store coordinates no asynchronous operations, response ordering, cancellation or overlapping-work policy; those remain responsibilities of the external consumer. No task, queue, automatic pending effect, subscriber loop, timer or scheduler is added.

withObservationTracking tests observe both snapshot arrival and work-only changes, and observe a returned same-Edition Runtime window after a consumer receives viewport intent. Tests use real durable publication/FeedSession fixtures and verify no extra checkpoint/history write from store creation, state reception or intent forwarding. Rejected Edition/context, nil delivery, exact top/center inputs and all RunwayActivity cases are covered. Reflection/static boundary proofs establish one presentation field plus the immutable consumer and Observation's registrar. MainActor mutation is exercised by an external async consumer entering MainActor. Existing state/handoff/cold/driver and all Runtime regressions remain unchanged.

FeedScreenStoreTests lives in the existing ArchitectureSmokeTests target. Package.swift and its dependency graph are untouched: Composition -> UI -> Runtime, with no UI -> Composition dependency. SwiftUI screens, full external application wiring, explicit context/Edition replacement and future lifecycle policy are outside this gate.


## 14. Minimal SwiftUI presentation surface — Phase 3Q5

The previously scaffold-only FeedScreen, FeedCardView and FeedLoadingView now implement pure local rendering. FeedScreen accepts the external FeedScreenStore reference, reads its single state through native SwiftUI/Observation, and holds no State copy, alternate model, card cache, identity, anchor or cursor. With presentation it renders ScrollView/LazyVStack/ForEach over window.items in the supplied order, using PresentationCard's published occurrence ID. With no presentation it renders FeedLoadingView(work:). Pending, failed, deferred or unavailable never replace an existing feed with a loading surface. There is no automatic bootstrap or work opportunity on rendering.

FeedCardView(card:) receives one Runtime PresentationCard. Optional title/body/attribution remain optional and are rendered literally; no remote markup is interpreted. Native adaptive fonts/width support wrapped text without a fixed card/page size. Hero uses title2 typography; thumbnail/textOnly retain headline typography and the same honest textual content. Timestamp formatting uses only the supplied date, with distinct Autoria/Modificado/Observado labels. mediaAspectRatio cannot supply image bytes, and primaryActionKind cannot supply an action target. Neither is converted into downloads, generic images, fake navigation or playback. Accessibility identity also derives from card.id.

FeedLoadingView(work:) directly switches on the existing Work: idle states that no local presentation has been received; pending states preparation is underway; unavailable and deferred have distinct messages; failed renders the caller's exact message. Pending uses a plain factual preparation message. No progress amount, preview, fake card, terminal-empty claim, minimum duration or execution callback exists. Work while presentation is available needs no blocking overlay and is left under external ownership.

### Explicit viewport limit

No automatic viewport observation is emitted. The SDK's minimum-platform scrollPosition(id:anchor:) binding is available on macOS 14/iOS 17, but a returned ID alone does not establish factual user movement together with placement and RunwayActivity without another scroll mechanism. The richer ScrollPosition/phase/geometry APIs require macOS 15/iOS 18. This gate does not add platform-specific scroll coordination, a second cursor, per-card geometry, appearance-based anchors or heuristics. The spec explicitly permits render-only completion with this limitation recorded. Real user-position capture, semantic input delivery and any initial/programmatic scroll-position policy remain a later delimited gate. The existing FeedScreenStore.submitViewport contract is unchanged; no fabricated event is sent merely to exercise it.

### Functional rendering evidence

FeedScreenRenderingTests uses the existing ArchitectureSmokeTests target and native macOS AppKit/SwiftUI/Vision frameworks, with no package dependency or production hook. NSHostingView in an offscreen window renders the actual production views, including the platform-backed ScrollView/lazy stack; synchronous bitmap capture and local Vision OCR establish visible text/order. A single retained host also observes initial state, first arrival, pending and same-Edition window updates without replacing its root view. Tests use real temporary publication and FeedSession for windows, with semantic PublishedCard projections for absent optional fields/layouts. Public ForEach data with PublicationCardID identity supplements visual order evidence. Static import/effect checks are complementary, not substitutes for these functional renderings.

The 17 tests cover U1–U14 plus timestamp meaning, narrow-width adaptation and native Observation. U12 records intentional capture deferral and proves zero fabricated observations. U15 preserves the existing store/state/handoff and full-package regressions. Pixel checks execute on macOS; iOS device execution, interactive scroll capture, media rendering, action navigation and a full application container are not claimed. No durable checkpoint or history mutation follows view construction/rendering, and the finite window never becomes a claim of logical Edition exhaustion.
