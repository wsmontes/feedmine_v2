# Code review — FeedMine `main` @ `8873e72` (2026-10-08)

Audience: the implementing agent. Each finding has location, mechanism, effect and an
acceptance criterion. Line numbers refer to `8873e72`. Review was static (no Swift
toolchain on the reviewer machine); `swift build` / `swift test` were not run.

Severity: **H** = can stall or corrupt the user-visible feed with real feeds; **M** =
correctness/performance risk or architecture debt; **L** = hygiene.

Suggested order: H1 → H2 → H3 → H4 → M-concurrency → docs/CI.

---

## H1 — One mutated item permanently stalls a target (poison batch)

- Location: `Sources/FeedMinePersistence/ContentStore.swift:258` (`revisionConflict`),
  `validateMediaReplay` (`mediaCandidateCollectionConflict`),
  `Sources/FeedMinePersistence/AcquisitionAdmissionStore.swift` `admit` (known-version branch).
- Mechanism: Atom/JSON version identity is derived from `updated` / `dateModified`
  (`SyndicationTranslator.swift`). If a publisher edits title/summary/media without
  changing that date, admission rebuilds the revision with the stored ID and new payload →
  `sameRevision` fails → the whole batch rolls back, **including the checkpoint**.
- Effect: next pull downloads the same document, hits the same item, fails again. The
  target never advances. Combined with H2, it also blocks every later target.
- Tests asserting current behavior: `testKnownVersionPayloadConflictsRollbackAllFields`,
  `testKnownVersionMediaConflictsAndCompleteOrderedCollection`,
  `testLaterConflictRollsBackEarlierObjectMediaMembershipSupplyAndCheckpoint`.
  Correct at store level; wrong as system behavior.
- Fix direction (pick one, document the choice):
  1. Admission policy treats "same version, different payload" as a new unversioned-style
     revision (do not reuse the stored ID), or
  2. Reject only the offending observation (record a per-item rejection in the receipt)
     and still commit the rest + checkpoint.
- Acceptance: a test feeding an Atom entry twice with identical `id`/`updated` and a
  changed `summary` results in a committed checkpoint and no thrown error; the other items
  of the batch are admitted.

## H2 — One failing target aborts acquisition for all others; no fairness

- Location: `Sources/FeedMineComposition/RunwayAcquisitionCycle.swift:50`,
  `Sources/FeedMineComposition/ColdFeedBootstrap.swift:121`,
  `Sources/FeedMineAcquisition/AcquisitionPlanner.swift:111`.
- Mechanism: planned work runs sequentially with `try await coordinator.execute(work)`.
  Any error (HTTP 404/500, `parseFailed`, `bodyTooLarge`, H1) exits the loop. The planner
  always takes the first `targetWorkCapacity` enabled targets in registration order.
- Effect: a permanently broken feed early in the registration list starves every later
  feed forever. Latency is also the sum of all feeds.
- Fix direction: settle each target independently (collect per-target success/failure in
  the outcome), run with bounded parallelism (`withThrowingTaskGroup` / TaskGroup with a
  limit), and rotate or otherwise fairly order targets across cycles.
- Acceptance: with targets [A (always throws), B (returns items)], one cycle admits B's
  items and reports A's failure without throwing; repeated cycles with capacity 1 eventually
  service every enabled target.

## H3 — The same article is republished as a new card

- Location: `Sources/FeedMineEditorial/SelectionEngine.swift:66`.
- Mechanism: exposure exclusion compares `originRevisionID`. RSS has no version identity,
  so any content change (typo fix, reordered `media:thumbnail`, dynamic text in
  `description`) creates a new revision that is not "published" → selected again.
- Effect: duplicate cards for one article in the same Edition.
- Fix direction: unless "edited revision = new occurrence" is an explicit product decision
  (then write it in `PRODUCT_INVARIANTS.md`), exclude by `originRecordID` within the
  Edition (requires an `origin_record_id` exposure probe/index on `published_cards`).
- Acceptance: admitting a changed unversioned revision of an already-published origin does
  not produce a second card in the same Edition.

## H4 — Redundant full-document downloads

- Location: `Sources/FeedMineSyndication/SyndicationConnector.swift:66`,
  `Sources/FeedMineAcquisition/AcquisitionCoordinator.swift` (`run` loop).
- Mechanism A (no ETag/Last-Modified): after consuming the whole document, `nextState ==
  oldState` → `delta == nil`, but observations are non-empty → `.batch` is returned → the
  coordinator loops and refetches the same document up to `batchCapacity` times.
- Mechanism B (paging): when items > `observationCapacity`, each page is a full
  unconditional re-download (N pages = N downloads).
- Fix direction: persist the fingerprint of the last fully consumed document (e.g.
  `lastConsumedFingerprint`) and return `.upToDate` when the body matches; consider
  translating the whole document once and admitting in several batches from memory within
  one execution.
- Acceptance: against a server without validators, one execution performs exactly one GET
  when the document is unchanged.

---

## M — Concurrency

- **M1 Cancellation does not propagate.** `AcquisitionCoordinator.swift:87` creates an
  unstructured `Task {}`; cancelling the caller does not cancel the HTTP pull. Use
  `withTaskCancellationHandler` to cancel the stored task when the creator is cancelled
  (joiners must not cancel it).
- **M2 Actor reentrancy in `FeedRunwayDriver`.** `submitViewport` can enter while `drive`
  is suspended on network, so two `drive` loops interleave. Benign supersession surfaces as
  thrown errors (`staleMeasurement`, `staleAcquisitionAcknowledgement`) to the UI. Either
  serialize `drive` (single in-flight drive task; new observations just mark "dirty"), or
  treat these errors as "superseded, re-reconsider".
- **M3 Blocking I/O on actors.** Synchronous SQLite and the `prepare` closure (may `fsync`
  media) run inside `FeedSession` / `FeedRunwayDriver`, occupying the cooperative pool.
- **M4 Masked error.** `FeedRunwayDriver.swift:132`: if `failLocalSlice` throws, the
  original error is lost. Use `try?` there or rethrow the original.
- **M5 Unbounded loop.** `FeedRunwayDriver.swift:110` `while true` has no iteration or
  network-call cap per `drive` invocation. Add a bound and return.

## M — Runway policy

- **M6** `RunwayController.swift:340`: `.forwardBeyondProbe` clears consumption samples →
  coverage becomes `.unknown`. The fastest reader gets the weakest response. Treat it as a
  lower-bound rate (`probeBound / elapsed`) instead.
- **M7** After a local slice failure, `lastFailure` blocks `reconsider` until a new
  observation or supply change. No retry/backoff exists.

## M — Performance / scale

- **M8** `ContentStore.swift:103` `candidateWindow`: examines N global rows, then filters
  by source. Low-volume sources inside a large supply need many slices to fill. No index on
  `source_memberships(source_id)`. Consider a source-scoped query path.
- **M9** N+1 queries: `candidateWindow` does 3–4 queries per row; `PublicationStore.cards(around:)`
  decodes touched/crossed segments twice.
- **M10** No retention/eviction for DB or assets (acknowledged as future in docs).

## M — Content handling

- **M11** RSS `description` (HTML) flows raw into `primaryText`
  (`SyndicationTranslator.swift:61` → `PublicationPreparation.swift:88`) and is now
  rendered with `Text(verbatim:)` in `FeedCardView`. Users will see tags/entities.
  Convert to plain text at the connector/admission boundary (INV-13).
- **M12** Future `pubDate` pins items to the top (recency sort, no clamp to `observedAt`).
- **M13** Redirect https → http is accepted (`SyndicationHTTP.swift`). Refuse downgrade.

## M — Functional gaps (not yet an app)

- **M14 Scroll is disconnected from the runway.** `FeedScreen` (new in `8873e72`) never
  calls `store.submitViewport`; the comment says capture is deferred. Until wired, INV-03/04
  have no producer and the runway never grows from reading.
- **M15 No media pipeline.** Nothing downloads candidate images; `MediaPreparation` is
  unused in production. `PresentationCard` carries no media key, so the UI cannot render
  images even when `layout == .hero/.thumbnail` (it only changes title font).
- **M16 Actions.** `primaryActionKind` reaches UI without a target and there is no
  executor (`InteractionCoordinator` is a scaffold). Tap does nothing.
- **M17** `FeedScreen` ignores `state.work` once a presentation exists (no in-feed
  pending/failed indicator).
- **M18** `.search` context throws in `CandidateProvider` and `SyndicationAcquisitionSnapshot`.
- Still scaffold: `FeedMineBootstrap`, `FeedMineEnvironment`, `FeedPlanResolver`,
  `MediaPolicy`, `MediaResolver`, `InteractionCoordinator`, `BackgroundFeedRefresh`,
  `FeedSessionReducer`, `FeedSessionEffects`, `FeedSessionUI`.

## M — Architecture debt

- **M19 Triplicated types/validation** caused by the dependency rules: media candidate
  (`AcquisitionMediaCandidateClaim` / `MediaCandidateCommand` / `MediaCandidate`),
  checkpoint (`AcquisitionCheckpoint` / `CheckpointRecord`), precedence, and observation
  validation (3 places). Conflicts with INV-15. Consider shared command values in Domain.
- **M20 Stringly-typed public records** in Persistence (`renderLayout`, `timestampKind`,
  `primaryActionKind`, target `state`, `anchorPlacement`). Invalid states are
  representable; validated only at runtime.
- **M21 Boundary leak.** `AcquisitionTargetAuthority` public API exposes
  `AcquisitionTargetStore.ReconfigurationCheckpoint` and `AcquisitionTargetStoreError`.
- **M22** `RunwayController` is 409 LOC (own alarm: 300).

## L — Docs and repo hygiene

- **L1 Docs drift.** `README.md` says "sem dependências externas" and "architecture
  scaffold" (GRDB + FeedKit are used). `ARCHITECTURE.md` says "dois targets de testes"
  (there are 11) and that no PublicationStore API may be implemented (it has 729 LOC).
  `Package.swift` header says "Architecture scaffold only". `MODULE_MAP.md` repeats "No
  imports are used by production scaffolds" for every module.
- **L2** No `.gitignore` (`.build/`, `.swiftpm/` at risk).
- **L3** No committed `Package.resolved` (app: transitive deps unpinned).
- **L4** No CI; ~13k LOC of tests never run automatically. Add a macOS GitHub Actions job
  running `swift build` and `swift test`.

---

## Strengths (keep)

- Schema-level invariants (CHECKs, composite FKs), atomic admission with checkpoint in the
  same transaction, byte-exact opaque text comparison, corruption detection on read.
- Bounded streaming HTTP body, manual redirect validation, credential-free endpoints.
- Content-addressed `AssetStore` with `renamex_np(RENAME_EXCL)` and file + directory `fsync`.
- Real Publication → Presentation → UI separation; UI does not import Publication.
- Extensive tests for rollback, reopen and overflow paths.
