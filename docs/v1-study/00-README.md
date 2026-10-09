# FeedMine v1 study: lessons for v2

This is a study of FeedMine v1 (`wsmontes/feedmine-dev`, `main` @ `b5c2f59c`, 2026-09-17).
v1 is an iOS app of about 40k lines of Swift plus 188 Python catalog scripts, built over 1010
commits between 2026-06-30 and 2026-09-17. The study reviews v1's code and records what it
learned, so those lessons can be applied to v2 (`main` @ `b14a47a`).

The review is static. Neither project was built, and nothing from v1 was copied into v2.
Every code claim cites a file and line. Every history claim cites a commit hash or a doc path.

Readers: the v2 implementing agent and the product owner. Finding IDs:
FP = feed pipeline, IN = ingestion, MD = media, CE = catalog/editorial, UI = UI and quality.
H/M/L IDs refer to `docs/reviews/CODE_REVIEW_2026-10-08.md`.

## Documents

| File | Area | Findings |
| --- | --- | --- |
| [01-feed-pipeline.md](01-feed-pipeline.md) | FeedStore, runway, reservoir, prepared-card pipeline, schedulers | FP-1..13 |
| [02-ingestion-network.md](02-ingestion-network.md) | RSS fetch, HTTP sync, parsing, identity, sources | IN-1..12, plus the real-world feed quirks list |
| [03-media.md](03-media.md) | Image resolution, caches, preparation, audio | MD-1..12, plus the proposed v2 media pipeline |
| [04-catalog-editorial.md](04-catalog-editorial.md) | Catalog, curation, selection, diversity, taxonomy, search | CE-1..10 |
| [05-ui-app-quality.md](05-ui-app-quality.md) | Feed screen, viewport, states, tests, CI, release | UI-1.., plus the viewport and CI proposals |
| [06-history-lessons.md](06-history-lessons.md) | Timeline, why v1 became complex, bug classes, v1-vs-v2 table | — |

## Why v1 became confusing (one paragraph)

`FeedStore.swift` grew to 8,293 lines on the MainActor. It holds about 30 responsibilities and
is touched by 224 commits. Up to four feed pipelines coexisted behind flags; the Unified
Selection Engine (about 13k lines) was merged and then deleted without ever compiling
(`09acf5ea`). Migrations were left half-done: the FeedEngine catalog never fed the UI, and the
decomposition stopped with 210 references left. Ordering and diversity were mutable reservoir
state, repaired again downstream. Published cards changed after publication (text-only became
hero), which shifted layout during scroll. CI ran 1 of 30 test classes, and the Makefile used
`|| true`. 41% of commit subjects contain "fix".

v2's invariants (INV-01/02/03/07/08/09/12/14) block most of this by rule. The details are in
06 §6.

## What v2 must carry over

| Idea | Why | Source |
| --- | --- | --- |
| **"Feed is sacred."** No reorder near the reader, no head removal, no scroll jump, published IDs never change. | It is the top product promise, and the v1 build-16 review traces the main regressions to breaking it. | 06 §5, FP §4 |
| Terminal card before publication; contiguous-prefix promotion | A slow item never lets a later one jump ahead, and there is no placeholder→image swap. | FP §4, MD §4 |
| Hard per-item preparation deadline | A stuck image degrades to text-only or a placeholder instead of stalling the batch. | FP §4 |
| Source identity ≠ request URL (two-URL model) | Normalizing the fetch URL breaks signed feeds, while raw identity duplicates sources. 0 drift over 77,443 sources. | IN §4, 06 §5 |
| Sliding-window fetch concurrency | Per-completion refill instead of per-chunk, so the slowest feed cannot block the free slots. | IN §5 (`814b0a5e`) |
| Image safety primitives | ImageIO downsampling, dimension/pixel gate before decode, byte ceiling enforced while streaming, single-flight dedup. | MD §4 |
| Image candidate ranking | Feed image, then og:image, twitter:image, srcset 720–1600px, JSON-LD; decorative URLs filtered out. | MD §4, IN quirks |
| Measured targets | Warm relaunch 234 ms, cold first install 28.5 s for 20 cards (both iPhone 16, build 16). | 06 §5 |
| Release discipline | Every build maps to a SHA, clean container between runs, journeys certified by basename set. | 06 §5, UI §4 |
| Small assertive tests | These caught real bugs; tolerant XCUITests with `guard exists else return` did not. | UI §4–5 |

## What v2 must not repeat

| v1 failure | v2 status | Guard |
| --- | --- | --- |
| God object / one MainActor owner | Prevented by modules and size alarms | `RunwayController` is already 409 LOC against its own 300 alarm (M22). Enforce the alarms in review. |
| Competing pipelines and feature flags | Prevented (INV-14) | Do not add a "search pipeline" or "legacy media" path as an exception. |
| Diversity enforced twice (reservoir + sequencer) | One owner (`SelectionEngine`) | Keep all ordering in Editorial; no downstream re-interleave (FP-11, CE-5). |
| Late media mutating a visible card | Prevented (INV-08/09) | When media lands, a better image belongs to a future occurrence only (MD-2). |
| Hand-rolled continuations/waiters (double-resume crashes) | Mostly avoided | Bound the `drive` loop and run a single `drive` at a time (M2, M5). |
| Hand-maintained HTML entity table, regex tag strip | **Not addressed**: raw HTML is rendered (M11) | Use a complete decoder plus a parser-based strip at the connector boundary (IN-6/7). |
| One bad feed stalls everything | **Partly addressed** (3R1/3R2) | Map the remaining errors to operational failure, add backoff and bounded parallelism (H2 residuals). |
| No CI / masked failures | **Not addressed** (L4) | CI from now on (UI Lesson B). |
| Doc drift (README said 34k sources, actual 88k) | **Happening already** (L1) | Docs are updated in the same commit as code. |

## Consolidated v2 action plan

Ordered by risk to the user-visible feed. "Lesson" names the v1 study item that informs the action.

| # | Action | v2 location | Lesson | Review ID | When |
| --- | --- | --- | --- | --- | --- |
| 1 | Decide the edit policy, then exclude by origin (or record "edit = new occurrence" in PRODUCT_INVARIANTS). Normalize guid/link; give RSS a content-fingerprint version. | `SelectionEngine`, `SyndicationTranslator` | IN L1, CE Lesson E | H3, H1 follow-up 1 | Now |
| 2 | Convert description HTML to plain text (complete entity decoder, strip `script`/`style` bodies) | `SyndicationTranslator` (new text helper) | IN L3, quirks 1–4 | M11 | Now: blocks readable cards |
| 3 | Clamp `authoredAt` to `observedAt`; refuse https→http redirects | `SyndicationTranslator`, `SyndicationHTTP` | IN L2, L4 | M12, M13 | Now (small) |
| 4 | Map the remaining remote/target errors to operational failure; add per-target backoff and bounded parallelism | `SyndicationConnector`, `AcquisitionCoordinator`, composition cycle | IN L5 | H2 residuals | Before scaling targets |
| 5 | Capture the viewport on iOS 18 (`onScrollVisibilityChange`/`onScrollGeometryChange`, already used by v1 at `FeedScreen.swift:887,917`); gate macOS 15. Wire it to `submitViewport`. | `FeedMineUI/FeedScreen` | UI Lesson A | M14 | Now: the runway has no producer |
| 6 | Single-flight the driver: new observations mark it dirty instead of starting a second loop; bound the iterations | `FeedRunwayDriver` | FP-5, FP-12 | M2, M5 | Now |
| 7 | Add CI (macOS: `swift build`, `swift test`), `.gitignore`, and a committed `Package.resolved` | `.github/workflows` | UI Lesson B | L2–L4 | Now |
| 8 | Show pending/failed work while a presentation exists; honest empty/first-launch states | `FeedScreen`, `FeedPresentationState` | UI Lesson E, FP-4 | M17 | Before the feed screen ships |
| 9 | Media pipeline: pure `MediaResolver` plus `MediaPolicy`; one download owner in Runtime; measured dims; media handle on `PresentationCard` | Media, Runtime, UI | MD §6 design | M15 | Before the "images in cards" feature |
| 10 | Diversity beyond `recencyDescending` (provider spacing, "no repeat while alternatives exist", tested as an invariant) | `EditorialPolicy`, `SelectionEngine` | CE Lesson B, FP-11 | — | Before expanding editorial |
| 11 | Catalog / SourceBinding materialization with a separate source lifecycle and ≥64-bit identity (v1 used a truncated 32-bit id) | Domain, Persistence, Composition | CE Lesson A, CE-1 | — | Before importing the v1 catalog |
| 12 | Media retention and byte budget; record terminal "no image"; port the image failure-taxonomy audit | `AssetStore`, Runtime | MD lessons 8–10 | M10 | Later |

## Consolidated questions for the product owner

1. **Edited article:** is a publisher's edit a new card or a silent update of the existing one?
   This blocks items 1 and H3, and v1 never decided it either.
2. **Supply source:** does v2 reuse v1's 118 MB catalog (88k sources) plus its Python tooling,
   rebuild discovery, or run pure RSS at runtime? This decides item 11 and the identity width.
3. **Cold start:** what is the maximum honest preparation time on first launch (v1 measured
   28.5 s)? Is a "publish whatever is ready after N s" fallback ever acceptable? (v1's 12 s
   `prefix(20)` fallback was judged wrong.)
4. **First-screen breadth vs freshness:** is "one card per provider on the first screen" a
   promise, and should it be tested as an invariant?
5. **Late or better image after publication:** confirm that it only affects future
   occurrences, even if the reader never sees it.
6. **Media limits and retention:** maximum bytes and dimensions (v1 used 12 MB and 50 MP);
   retention window (v1 used 30 days, permanent for read or bookmarked items).
7. **Process:** is CI mandatory before merge, and does every TestFlight build carry a SHA/tag?

Area-specific questions are in section 7 of each document.
