# Next experience — the page that is made before the feed

Status: implemented on `codex/next-experience-build-58` (build 58 candidate). Companion evidence:
`/tmp/feedmine-next-experience-progress.md` and `/tmp/feedmine-testflight-build58-release.md`.

Scope of this document: **loading** (first load and filter change). The reader sheet and the podcast parity are
owned by their own changes and documented separately.

## 1. What the reader gets

A **page**, not a delay and not a scrim.

- **First load of a new context.** While the first Edition is being made, the app draws an opaque preparation page:
  the wordmark, one status line built from real pipeline facts, a mosaic of **prepared images** (decoded from the
  media pipeline's own assets, through the same decoder admission uses), a deck of **admitted headlines**, and the
  source chips. If nothing has arrived yet, three frozen-aspect slots carry the geometry and the motion instead —
  no text, no identity, no invented story.
- **Filter change.** A filter/source change is a **new feed being made**, so the same page is drawn even when the
  new context restores a cached Edition on the first pass; its headlines and images come from what was really
  published. An ordinary relaunch on an unchanged context never shows it: the persisted Edition is on screen before
  any HTTP, exactly as before.
- **Under the page.** The feed is mounted (that is how the layout is measured) but visually covered, out of the
  accessibility tree, and not hit-testable. Nothing scrolls under an opaque page.
- **Motion.** Insertion transitions and a slow drift; all of it collapses to a plain opacity change under Reduce
  Motion.

Deliberately **not** done: a translucent scrim over incomplete cards, a percentage bar (there is no honest
denominator), any headline/image not produced by the pipeline, and any "loading" text that outlives the work.

## 2. Requirements (final, after the owner's corrections)

- **L1** A persisted Edition is shown immediately on an ordinary resume; no preparation page, no wait.
- **L2** A **filter change** (context change with an association already on screen) draws the preparation page, even
  when the new context has a cached Edition.
- **L3** The page states only real facts: admitted headlines, prepared pixels, source states, prepared-card count.
  No fabricated headline, image, percentage or identity.
- **L4** While the page is up, the feed is not reachable: opaque cover, `accessibilityHidden`, `allowsHitTesting(false)`.
- **L5** Readiness is decided from the **installed/published snapshot**, never from the number of laid-out cards
  (a lazy list lays out ~3 cards; the page can hold 32).
- **L6** Engineering targets, in order: ≥12 published cards **ahead of the anchor**; ≥6 image-bearing cards among
  the **first 12** published; ≥3 distinct providers **when the selection can supply 3** (capped by the eligible
  source count); the reserve's own 32-card floor as a batch target **while a producer is active**; geometry covering
  the viewport (the existing 1 pt rule) stays its own independent condition.
- **L7** The first publication waits, bounded, for the images of the window it is about to examine. **One** budget
  for the whole first publication, fixed at the first window that has something to wait for, so eight empty windows
  cannot renew it and media acquired later still gets a real opportunity inside it. The target is clamped to the
  window's own candidate count.
- **L8** The 5 s stall measures **meaningful progress including media**: a new card, a lower bottom or a newly
  prepared image resets it, and it cannot fire while media work is pending. Only legitimacy (offer ended, proven
  transport failure), the stall with no work left, or the **total ceiling (30 s)** end the hold.
- **L9** "No publication while media is pending" is `preparing`, never `unavailable`. `unavailable` is stated only
  when no eligible stories exist and no media work is scheduled.
- **L10** A retired association installs nothing: counters and preview pixels carry the same context fence.
- **L11** The first exposure is recorded with its real counts and the reason it was exposed (`initial`, `filter`,
  `stall`, `ceiling`, `resume`). A fallback is recorded as a fallback — never as a page that met its targets.

## 3. Where each requirement lives

| Requirement | Owner |
|---|---|
| L1, L2 | `AppComposition.replaceSession` → `preparationRequestedContext` + `takePreparationRequest`; `FeedMineApp.prepareFirstScreen` |
| L3, L4 | `FeedPreparationView`, `FeedScreen.preparationSurface` + `accessibilityHidden`/`allowsHitTesting` |
| L5, L6 | `FeedFirstScreenContent` (published snapshot) + `FeedFirstScreenGate.surface` ordered exits |
| L7 | `ColdFeedBootstrap` (`PublicationMediaBudget`, one deadline) + `MediaReadiness.waitForPrepared` |
| L8 | `FeedFirstScreenGate` stall rule + `FeedFirstScreenHold.noteProgress` |
| L9 | `AppComposition.launch` (media-pending → `.preparing`) |
| L10 | `AppComposition.refreshPreparationMedia` (`active` fence) |
| L11 | `FeedLaunchWitness.noteFirstExposure` + `FeedScreenStore.exposureReason` |

## 4. Engineering targets: why these numbers

- **12 ahead.** The admitted window already carries up to 16 cards ahead of the anchor; 12 is the buffer that keeps
  a normal scroll from reaching the tail. It is not conditioned on the current publication being large — a
  three-card page with a producer active is exactly the case that must keep buffering. A feed whose offer really
  ended says so (`endOfContent`) and leaves the hold through that exit.
- **6 of the first 12.** Measured PM-018: at ~5 s only 32,2 % of published cards carried an image, at 20 s 40,0 %;
  the first screen is the one that must not read as text-only. The distribution is measured on the first page, not
  diluted over a 96-card reserve. With fewer than six cards installed the target is the page itself.
- **3 providers, capped.** The floor is V1's own measured `coldStartMinimumPageSources = 3`; it is capped by the
  eligible source count, so a single-source context has a target of one and is never held for two more.
- **32 while producing.** The reserve's own floor (`runwayMinimumReserveCards`), applied only while a producer is
  active. With no producer left it is not a hold at all.
- **30 s ceiling.** 2.5× the 12 s bootstrap tolerance: an outer bound, not a target. Expiry is recorded as
  `reason=ceiling`, never as quality.
- **Media budget.** `min(derived tolerance, 20 s)`: the derived value is 12 s cold and `p95 × 1.2 + 2 s` afterwards;
  20 s is where PM-018 stopped improving the image ratio.

## 5. Review findings and their fixes (primary review, 2026-10-27)

| Finding | Fix | Pinned by |
|---|---|---|
| `waitForPrepared` read `ready`/`settled` outside the lock while `record` mutated them | every read/write is under the same `NSLock`; no recursive locking (resume and timer cancellation happen after unlock) | `MediaReadinessWaitTests` (8 waits, cancellation, duplicates) |
| Cancellation arriving **before** registration left a waiter until the deadline | the waiter is a reference whose `cancelled` flag is set under the lock; registration checks it in the same critical section and resumes immediately; `finished` makes every path exactly-once | `testCancellationBeforeRegistrationLeavesNoWaiter`, `testCancellationDuringWaitResumesAndUnregisters` |
| The deadline task was neither retained nor cancelled although the comment claimed it | the task is stored on the waiter and cancelled by `finishWaiter`; the comment now states what the code does | `outstandingWaiterCount == 0` after every path |
| `preparedAmongLocked` counted `unsuitable` and text-only decisions as images | counting uses `fit != .unsuitable`; a text-only/unsuitable decision can only end a wait through "nothing more can arrive" | `testTextOnlySettlementEndsTheWaitWithoutCountingAsAnImage`, `testUnsuitableBitmapIsNotAnImage` |
| `needsAhead` required ≥12 published cards, so a small page never buffered | the buffer holds whenever ahead < 12; a real end of offer exits through `endOfContent`, and the stall/ceiling bound the rest | `testThreeCardsUnderAnActiveProducerHoldsForTheBuffer`, `testBatchTargetDoesNotApplyWithoutAProducer` |
| Image declaration inferred only from published images | the host states the scoped producer fact (`firstScreenDeclaresImages`), and the media counters state it while preparing | `testTextOnlyContextIsNotHeldForImages` |
| The bootstrap's deadline started before acquisition and could expire before acquired candidates existed | `PublicationMediaBudget.instant()` fixes the deadline at the **first window with candidates**, and every window shares it | `ColdFeedBootstrapTests` (delayed-media publication) |
| A stall could bypass an active image wait | the stall requires `!mediaPending`, and prepared images reset its clock | `testActiveMediaWaitIsNotAStall` |
| Preview images/counters had no context fence | `refreshPreparationMedia` guards `active` before decoding and before installing | code + integration journey |
| A pending filter change could show the old feed interactively | the page is opaque, the feed is accessibility-hidden and not hit-testable; the filter request is explicit and its page is drawn at least once | `testFilterChangeDrawsThePageWhenItsContentIsNotReadyYet` + the filter UI journey |

## 5b. Second review (integrated build) and its fixes

The first UI run measured the page with `record cards=9 images=9 providers=2 ahead=8 reason=initial hold=2648 ms`.
That record exposed three real defects, not a fixture problem:

| Finding | Root cause | Fix |
|---|---|---|
| `ahead` was 8 while the publication held more | `ahead` was counted on the **admitted window** (forward capacity 16, anchor near its middle), and `supplyProducing` was derived from `work`, which returns to `.idle` right after the first publication | the composition now accumulates the **receipts' own card identities** (`publishedOrder`, fed by the driver's receipts **and** by the cold bootstrap's first publication via the new `ColdFeedEvidence.publishedCards`), states `FirstScreenSupplyFacts` to the screen, and `producing` is true while the publication is under its batch floor, media is undecided, or the admitted window has not caught up. The window is only the fallback |
| the exposure was recorded as `initial` although the page fell short | the reason vocabulary had no case for "exposed with a content target unmet" | `ExposureReason.partialContent` (`reason=partial`), checked before the stall/filter/initial cases: a fallback is recorded as a fallback |
| the filter change never drew its page (`filter_page=0`) | with a cached Edition the new association restored it on the first pass, so the gate released immediately | the gate draws the requested filter page for at least **one measured pass** (`filterPageShown`, set on the first layout callback while the page is up). It is a real page over the new context, not a delay and not an environment flag |
| the filter journey did not prove the criterion was applied | Xcode 26 exposes the SwiftUI picker option as a different element type | the journey queries `descendants(matching: .any)`, asserts the option's own `selected` value, and asserts the lens **disappears** after removal |

Still true and deliberately unchanged: the 12-card buffer floor, the 6-image floor on the first 12, the
`min(3, eligible)` provider target, the no-stall-while-media-pending rule, the 30 s ceiling, immediate ordinary
resume, and the publication batch (32) as a target — now measured on the publication instead of the window.

### Podcast: what is *not* claimed

`ReaderCardAction.addSourceToCollection` has no host executor in this build (`ReaderActionCoordinator` refuses it by
design and `AppComposition` maps it to `openCard`); it is therefore **not** offered in the player's menu. Menu =
save, view source, and — only for a card that really froze an external page URL — copy link and share. That is the
honest limit of V1 action parity in build 58 and is recorded in the release note.

## 5c. UI round: what the first real runs measured (2026-10-27)

Two UI tests failed; three of the four causes were product/instrument defects, not fixture noise.

| Observation | Cause | Fix |
|---|---|---|
| the record read `cards=17 … content_bottom=n/a reason=n/a images=0` at 67 s | the witness label is a plain `Text` evaluated once per body pass, and SwiftUI does not re-render for a `static var` write; the exposure is written **after** the last pass of a settled feed, so every later read saw the old string | `FeedLaunchWitnessProof` re-reads the record once a second through `TimelineView(.periodic)` (DEBUG only, still invisible and non-interactive) |
| same test judged the launch before the exposure existed | `launchRecord(waitForCards:)` waited only for `cards=[1-9]` and ignored the wait's result | it gained `waitForExposure:`, which **asserts** that `content_bottom` + a reason + `published` really appeared, and the first-exposure test uses it. The quality assertions (`images>=6`, `providers>=2`, `ahead>=12`, `published>=12`, `reason=initial`) are unchanged |
| the filter change never recorded a page (`filter_page=0`) | the witness was recorded in `install(_:)`, which can run **before** the host consumes the preparation request (a cached Edition is installed during construction) | recording moved to where the page is really drawn: a measured layout pass while it is up, or a settle over an already-readable context (`markFilterPageIfNeeded(measuredPass:)`). A pending context still keeps its page; a cached one is not held to the ceiling |
| the filter journey waited 30 s for `lens-preset-chip-removal` | that control does not exist: `ReaderFilterLens` draws one button per chip and the chip's own action removes its criterion | the journey taps `lens-chip-preset` and asserts it disappears |

Gate ordering: the terminal exits (`endOfContent`, `unreachable`, `failed`) were evaluated **before** the filter-page
rule, so a filter change into a context that ends immediately showed the previous feed's cards under the new lens.
The filter rule now precedes them; two regressions pin both halves (`testFilterChangePagePrecedesATerminalWorkState`,
`testTerminalWorkReleasesAfterTheFilterPageWasDrawn`).

## 5d. Round 4: the bound that could not be reached, and the player's release

| Observation | Cause | Fix |
|---|---|---|
| a fixture feed took >3 min to publish while the page was up | `mediaPending` counted **every** requested revision, including text-only ones that a text feed never settles as images, so the stall could never fire; and the host's wait loop **returned** after the stall expiry, so the 30 s ceiling was never reached | `mediaPending` is only true when the context declares images; the host loop keeps advancing after the stall expiry (250 ms ticks) until the ceiling expires |
| the ceiling also had to bound the filter page | `ceilingExpired` was checked after the terminal switch and after the filter rule | the ceiling is checked **first**; `testCeilingBoundsTheFilterPage` pins it |
| the reader sheet journeys waited 3 min for cards | same cover/stall cause | same fix |
| `first publication` held small feeds to the ceiling | `producing` included "publication under the 32-card batch", which a 12-candidate feed can never reach — and the batch is a **cap** (the bootstrap's `publicationLimit`), not a floor | `producing` is a fact about work in flight: the launch, the bootstrap run, an acquisition execution, undecided media among **image-declaring** revisions, or an admitted window behind the publication |
| `mediaPending` was tautological | `declaresImages` included `imagesPending > 0`, and the window was treated as image-bearing because every candidate is requested | the image-declaring set is read from the canonical media candidates (`ContentStore.mediaCandidates`), and only those revisions count as prepared/pending; the composition re-states the fact when the evidence arrives |
| `filter_page` could be claimed without a drawn page | the cached-context release marked the page as shown *and* incremented the counter | only the page's own `onAppear` marks it (`FeedScreen.notePreparationPageDrawn`); a settle or install cannot |
| `±15 s` did nothing at `0:17` in the player | SwiftUI's `Slider` never delivered its release callback for the drag, so the draft never committed and the thumb kept a position the player never took | the scrub is a real `UISlider`: `touchDown`/`valueChanged`/`touchUpInside`/`touchUpOutside`/`touchCancel` state the release, and an assistive-technology step (a value change with no touch) commits at once. No time-based inference. `±15 s` drops the draft as a separate intent |
| the podcast journey asserted `Pausar` while the app ran in English | the test relied on the host locale | `launched(...)` passes `-AppleLanguages (pt_BR) -AppleLocale pt_BR`, like the other journeys; the shared helper's defaults are untouched |
| the journey tapped `full-player-close` after choosing Save | the host now closes the player itself and runs the action on dismissal | the journey waits for the player to disappear and asserts the card's bookmark, then stops |
| the audio-image fixture never showed `card.play` | the feed was never published (above), not a parse failure: the document carries the audio enclosure **and** `media:content medium="image"` under the `media:` namespace | same cover/stall fix; the document shape is unchanged |

## 5e. Round 8: the request belongs to the association, not to a global stamp

Measured (2026-10-27): the criterion was applied, the lens appeared, and `filter_page` stayed **0**. Two races, both
structural:

1. the composition stamped the **applied** key (`next.contextKey`) while the host consumed it with the **raw**
   `currentContextKey` — a selection carrying a global exclusion never matched, so the request was never taken;
2. a warm projection could lay out and set the sticky reading surface **before** the host's `onAppear` delivered the
   request, and "already exposed" then bypassed the page forever.

The request and the first-screen policy facts are now bound to the **next association's own store**, synchronously,
**before** the association is published (`prepareFirstScreen(of:previous:)` in `replaceSession`, both branches;
search excluded). The host's appearance pass re-states policy only and cannot clear a bound request
(`FeedScreenStore.noteFirstScreenPreparationRequested`). An ordinary resume still has no request and stays immediate.

Regressions: `FirstScreenPreparationRequestTests` (a requested page is not bypassed by an early measurement; an
appearance that restates policy keeps the request; an ordinary resume is immediate).

## 5f. Live catalogue: missing podcast covers (patch awaiting root verification)

The owner's live measurement (`/tmp/fm58-root-real-catalogue-11.log`) passed viewport geometry but recorded
`images=2 providers=6 ahead=509 published=510 reason=ceiling hold_ms=34161`. This is **not** a passing
image-rich first exposure; the controlled quality test cannot substitute for it.

`SyndicationTranslator` previously read only item artwork. RSS now offers the source-declared channel iTunes
cover, then an admitted RSS image, **only** to an item with admitted audio playback and no admitted item visual.
Relative show artwork uses the channel link, resolved against the feed endpoint, or that endpoint when no web
channel link exists; the episode permalink is not its base. Both declarations pass the existing locator and
dimension admission. No downloader, invented artwork, news-logo fallback or second playback is introduced.
The cover is an ordinary canonical media claim under the existing target/source membership, so discovering or
changing it is material for that episode; an unchanged replay or a show-cover change hidden by item art is not.
Historical revisions and already published cards are not rewritten.

`SyndicationPodcastArtworkTests` adds priority, audio-only eligibility, RSS fallback, relative-base, security,
decorative/tiny-image and canonical revision/replay regressions. The live geometry UI test now prints structured
image/provider/ahead/publication/reason facts and requires a complete exposure witness in Debug. It explicitly
does **not** assert live quality success; Release AX-only geometry does not measure those quality counts.
The existing controlled first-exposure quality assertions remain unchanged.

Remaining prepublication risk: `waitForPrepared` correctly ends when the **current window** has all settled,
including text-only decisions. `attemptFirstPublication` ignores its image count and can publish that ready
text-only window before image-bearing supply from another acquisition arrives. Later publication cannot repair
the frozen first page. This patch fixes missing declarations first; it does not change that policy, selection,
image thresholds, published order or wait budgets. Root must rerun the live catalogue and inspect the first
12 images, provider variety, ahead count and exposure reason before considering release.

No commands or tests were executed by this patch session (read/write/edit/grep only). Root owns package,
simulator and real-catalogue verification; the handoff is `/tmp/fm58-live-image-quality-ready.json`.

## 6. Tests

Package (fast, no UI):
- `Tests/ArchitectureSmokeTests/FirstScreenReadinessTests.swift` — the decision table: buffer under an active
  producer, small pages, single vs multi-source variety, the image floor, text-only design, an active media wait,
  the stall with no work, the ceiling, end/failure exits, filter change vs resume, geometry independence, absence,
  already exposed.
- `Tests/FeedMineRuntimeTests/MediaReadinessWaitTests.swift` — 10 waits: target reached, text-only, unsuitable,
  all-settled early exit, deadline, cancel-before-registration (40 iterations), cancel-during, several waits with
  exactly-once resume, duplicate revisions, preview pixels.
- `Tests/FeedMineRuntimeTests/PreparationProgressTests.swift` — media facts monotonic/current, preview merge,
  dedup and capacity.
- `Tests/FeedMineRuntimeTests/ReaderMediaArtworkTests.swift`, `Tests/FeedMineCompositionTests/ReaderMediaArtworkCoordinatorTests.swift`
  (podcast lane) — persisted-bytes-only decoding, scrub commit rules, finite progress, one cover per play.

App:

- `FeedMineAppTests/PlaybackTests` + `FeedMineAppTests/ReaderHostTests` — 32 executed tests (20 + 12): real player,
  artwork on the lock screen, refusal preservation, sheet presentation/dismissal semantics, opener context.
- `FeedMineUITests/FeedVisibleExperienceUITests.testFirstExposureIsImageRichBufferedAndNotAFallback` — the real
  fixture production path (`FEEDMINE_FIXTURE_MEDIA=image`, 16 items, one feed 2 s late) asserts the app's own first
  exposure record: ≥1 laid-out card, ≥6 image cards among the first 12, ≥2 providers (the fixture supply), **≥12
  cards ahead in the publication**, reason `initial`, geometry at the viewport bottom. `reason=partial`,
  `stall` or `ceiling` fails on purpose. The laid-out count is recorded as information and never asserted: a lazy
  list draws ~3 cards.
- `FeedMineUITests/SourcesAndFilterJourneyUITests.testFilterChangeDrawsThePreparationPageForTheNewFeed` — applies the
  sheet's criterion (asserting the option really became `selected`), asserts the new context's page was drawn
  (`filter_page=1`), that the lens names the criterion, then removes it and asserts a second page (`filter_page=2`)
  and the lens's disappearance.
- `FeedMineUITests/ReaderSheetDismissalUITests` — local and publisher pages: a page scrolled down does not dismiss,
  a pull at the top does, the opener returns to the same card at the same y (±1 pt), and `reading.close` remains a
  working fallback.
- `FeedMineUITests/PodcastExperienceUITests` — a published podcast card (artwork, program, menu, stop) and a real
  simulated playback (clock, scrub released once, ±15 s, stop).

## 7. Evidence

Executed by the orchestrator (single build owner). Numbers and command lines are recorded in
`/tmp/feedmine-next-experience-progress.md`; the release evidence file is
`/tmp/feedmine-testflight-build58-release.md` when the build is uploaded.

## Root verification before build 58 publication

Fresh package run: `/tmp/fm58-root-package-tests-12.log`, exit 0, 1,805 tests, one skipped, zero failures.
The final parser test source (after removal of three redundant default assertions) was rebuilt and rerun in
`/tmp/fm58-root-podcast-artwork-13.log`: nine tests, zero failures, exit 0. App build-for-testing round 13
also exited 0 (`/tmp/fm58-root-appbuild-13.log`).

Final acceptance bundle `/tmp/fm58-root-release-acceptance-13.xcresult` is complete: four UI journeys,
zero failures, exit 0. It covers an eight-second delayed controlled source with image/buffer/provider quality
assertions, real-catalogue cold onboarding, and both podcast artwork/actions and actual playback/scrub/skip.
The prior complete `/tmp/fm58-root-final-playback-reader-11.xcresult` retains the 33 passing app unit tests
and six passing reader/playback/podcast UI journeys. Native sheet scrolling, top pull, close anchoring and
filter application/removal also retain their passing dedicated rounds 6 and 9; the channel parser patch did
not change those implementations.

Two fresh-namespace public-catalogue exposures after the parser patch met the requested quality floors:

| Round | First-12 images | Providers | Published ahead | Publication | Exposure reason | Hold |
| --- | ---: | ---: | ---: | ---: | --- | ---: |
| 12 | 9 | 5 | 12 | 13 | initial | 12,354 ms |
| 13 | 7 | 3 | 12 | 13 | initial | 13,956 ms |

Raw frozen witnesses and screenshots are retained under `/tmp/fm58-real-catalogue-12-visuals/` and
`/tmp/fm58-real-catalogue-13-visuals/`. The live test's geometry PASS alone is not used as quality evidence;
the independent recorded image/provider/buffer/reason facts above are the basis. Public supply varies:
this is measured internal-beta evidence, not a guarantee of images on genuinely text-only or failed sources.
No already published card was repaired or reordered. Catalogue and descriptor hashes remain unchanged;
the six frozen evaluator files still verify against `bench/EVALUATOR.sha256`.

B03 retains its previously recorded FAIL; B06 on a physical device remains NOT_RUN. This delivery is an
internal TestFlight evaluation, not a public-release gate approval.
