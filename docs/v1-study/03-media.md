# v1 study — Media (images, audio, thumbnails): resolution, caching, preparation

Static review of FeedMine v1 (`C:\workspace\feedmine-dev`). No Swift toolchain; no build was
run. Line numbers refer to the working tree copied at the paths below. This document feeds the
design of v2's missing media pipeline (review item **M15**) under `Sources/FeedMineMedia`.

## 1. Scope

| v1 file (under `feedmine/` unless noted) | LOC | Role |
| --- | ---: | --- |
| `Services/ImageCache.swift` | 911 | Two-tier cache + `CachedAsyncImage` view + `ArticleImageResolver` (og:image scraping) + `ImageUpgradePolicy` + `ImageURLCandidates` + download tracker. The live view path. |
| `Services/ImageLoader.swift` | 115 | View-free re-implementation of `CachedAsyncImage.load()`; used by the prepared pipeline. |
| `Services/ImagePrefetcher.swift` | 86 | Actor; sliding-window prefetch (16 concurrent) into `ImageCache`. |
| `Services/ImageResolutionQueue.swift` | 307 | Persistent SQLite-backed retry queue with exponential backoff. |
| `Services/MediaAssetStore.swift` | 277 | **Second** cache/download actor (single-flight, bounded, SQLite record). |
| `Services/DiskImageCache.swift` | 51 | Disk cache used only by `MediaAssetStore` (`FeedmineImageCache/`). |
| `Services/MemoryImageCache.swift` | 25 | NSCache wrapper used only by `MediaAssetStore`. |
| `Models/ImageResolutionRecord.swift` | ~95 | GRDB record + outcome enum + candidate fingerprint. |
| `Services/ReadyCardQueue.swift` | 101 | `@MainActor` publication gate; batch-prepare + order-preserving merge. |
| `Services/CardPreparationPipeline.swift` | 169 | Actor; prepares `FeedCardPresentation` via `ImageLoader` (8 concurrent, per-index deadline). |
| `Services/CardPreparationCoordinator.swift` | 635 | Rival coordinator using `MediaAssetStore`; does late text-only→hero upgrade. |
| `Services/AudioPlayerManager.swift` | 417 | AVFoundation playback + now-playing (no artwork prefetch found). |
| `Models/FeedItem.swift` (image accessors) | — | `bestImageURL`, `youTubeThumbnailURL`, `hasPotentialImage`, `canResolveArticleImage`. |
| `Services/RSSFetcher.swift` (image/enclosure extraction) | — | `extractImageURL` (`:1081`), `extractRSSEnclosures` (`:677`), `resolveImageURL`. |
| `scripts/diagnose_image_failures.py` | ~430 | Offline image-failure audit over a copied app DB; emits a failure taxonomy. |
| `docs/cards-resolvidos-antes-de-aparecer.md` | — | The "card resolved before appearing" design note. |
| `docs/code-review-testflight-build-16.md` | — | Review documenting dual pipelines + late upgrade regressions. |

## 2. How v1 works

v1 has **two coexisting image pipelines** feeding one shared on-disk cache concept but two
different cache directories, plus a persistent retry queue. Image candidate selection is a
fixed priority list; failures fall back to scraping the article page for `og:image`.

```text
RSSFetcher.extractImageURL  ──> FeedItem.imageURL        FeedItem.youTubeThumbnailURL
   media:content/thumbnail         (feed artwork)              (img.youtube.com)
   iTunes image, enclosure,                 \                 /
   first <img> in HTML                       FeedItem.bestImageURL  (YouTube first, else feed)
                                                     │
         ┌───────────────────────── PIPELINE A (live view) ─────────────────────────┐
         │  CachedAsyncImage.load()  /  ImageLoader.resolveImage()                   │
         │   mem(NSCache) → disk(ImageCache/) → wait-in-flight → network(2 tries,    │
         │   YouTube sd→hq candidates) → ArticleImageResolver og:image fallback      │
         │   → ImageCache.setImage(data:) downsample 800px → JPEG 0.85 to disk       │
         └──────────────────────────────────────────────────────────────────────────┘
         ┌──────────────── PIPELINE B (prepared / coordinator) ─────────────────────┐
         │  CardPreparationCoordinator → MediaAssetStore.resolve()                  │
         │   MemoryImageCache → DiskImageCache(FeedmineImageCache/) → bounded        │
         │   download(12MB, dim≤12k, ≤50MP) → downsample → ImageResolutionRecord     │
         └──────────────────────────────────────────────────────────────────────────┘
                                   │ on failure / timeout
                                   ▼
                 ImageResolutionQueue (SQLite image_retry_queue, backoff 30s/2m/10m/1h/6h)
                                   │ success
                                   ▼  delegate: must NOT rewrite a published card
   ReadyCardQueue (batch, 3s timeout) ──> FeedCardPresentation {.image|.placeholder|.none}
```

Prefetch (`ImagePrefetcher`) runs ahead of scroll filling `ImageCache` only (pipeline A's dir),
16 concurrent, sliding window, deduped via a shared global `ImageDownloadTracker` actor.

## 3. Code review findings

Severity: **H** = user-visible breakage / correctness; **M** = architecture/perf debt; **L** = hygiene.

- **MD-1 (H) Two parallel media pipelines with two disk caches.**
  `ImageCache` writes to `Caches/ImageCache/` (`ImageCache.swift:506`); `DiskImageCache` writes
  to `Caches/FeedmineImageCache/` (`DiskImageCache.swift:12`). Pipeline A
  (`CachedAsyncImage`/`ImageLoader`/`ImagePrefetcher`) and pipeline B
  (`CardPreparationCoordinator`/`MediaAssetStore`) each have their own memory + disk cache and
  their own download/validation code. `MediaAssetStore` is wired in `FeedStore.swift:1134`;
  `ReadyCardQueue`+`CardPreparationPipeline` is wired at `FeedStore.swift:33`.
  Effect: the same URL can be downloaded and stored twice, budgets are doubled (two 100 MB disk
  caps, two 200 MB NSCaches), and warm-start reads one dir while the other filled it. The
  build-16 review names this directly ("ainda existem duas arquiteturas de feed convivendo").

- **MD-2 (H) Published cards mutate after appearing (late image upgrade).**
  `CachedAsyncImage.improveImageIfNeeded` (`ImageCache.swift:971`) replaces an already-shown
  image with a larger article-page image; `CardPreparationCoordinator` (per build-16 review)
  publishes text-only then upgrades to `.image/.hero` in place. Effect: layout/height shift
  under the reader and (per the review) `visibleCardsGeneration` bumps that invalidate
  filtering/date-section caches during scroll — the documented scroll-stutter regression. This
  is the exact anti-pattern `cards-resolvidos-antes-de-aparecer.md` was written to kill.

- **MD-3 (H) `CachedAsyncImage.body` does synchronous disk I/O to avoid placeholder flash.**
  `diskImageSync` (`ImageCache.swift:609`) reads a file and decodes `UIImage(data:)` on the
  MainActor; the doc comment admits "~2-5 ms" per call. Combined with the view starting its own
  `load()` from `.task` (`ImageCache.swift:860`), the card is an active stage of the loading
  pipeline — the problem statement of the design note.

- **MD-4 (M) `hasPotentialImage` reserves a hero slot for almost any HTTP item.**
  `FeedItem.canResolveArticleImage` (`FeedItem.swift`) returns true for any non–`news.google.com`
  http(s) URL, so `hasPotentialImage` is true even when no image exists. Effect: layout chosen
  from a *possibility*, not a *resolved* fact; wasted article fetches; false hero slots. The
  design note's Apontamento 7 flags exactly this.

- **MD-5 (M) Image identity is URL-keyed, not byte-keyed.**
  `ImageCache.stableHash` (`:714`) and `ImageCacheKey.forURL` (`MediaAssetStore.swift:305`) both
  key the cache by FNV-1a of the URL string. Effect: a URL that serves different bytes over time
  silently returns stale cached pixels; a 302 to a different image is still stored under the
  original key (`setImage(data:for: cacheURL)` in `load()`). Fingerprint in
  `ImageResolutionRecord` keys on URL strings + `policyVersion`, not content.

- **MD-6 (M) `persistResolution` stores pixelWidth/Height = 0.**
  `MediaAssetStore.persistResolution` (`MediaAssetStore.swift:229`) writes `pixelWidth: 0,
  pixelHeight: 0` even though it has the decoded image. Effect: the persisted record cannot
  drive aspect ratio or placeholder sizing; `loadAssetMetadata` then returns a 0×0 asset.

- **MD-7 (M) `failureClass` column overloaded as both source enum and NSError domain.**
  Success path writes `failureClass: source.rawValue` (`:231`); failure path writes
  `failureClass: nsError.domain` (`:267`); `loadAssetMetadata` parses `failureClass` back into
  `ImageResolutionSource` (`:207`). Effect: a stringly-typed field with two incompatible meanings;
  invalid states representable.

- **MD-8 (M) `MediaAssetStore.cancelAll()` is intentionally empty.**
  `MediaAssetStore.swift:86` — a no-op "because in-flight work is shared". Effect: no way to stop
  downloads on filter change/reset; combined with MD-1 the two pipelines cannot be coordinated.

- **MD-9 (M) `CachedAsyncImage` retries up to 3× on `.onAppear`.**
  `ImageCache.swift:870` resets `didAttempt` and re-runs `load()` when `loadFailed`; each scroll
  back onto a failed card re-attempts network + an article scrape. No persistent "no image
  confirmed" check guards it (that state exists only in pipeline B's record).

- **MD-10 (M) `ArticleImageResolver` miss cache is in-memory, TTL 300 s.**
  `ImageCache.swift:173` — misses are not persisted; after relaunch every text-only item re-scrapes
  its article page. 192 KB HTML pulled per article (`:171`), 4 concurrent (`:172`).

- **MD-11 (M) Two different magic-byte validators; neither verifies full decode.**
  `ImageLoader.isValidImageData` (`:101`) and `MediaAssetStore.isValidImageData` (`:281`) check only
  the first 3–4 bytes (JPEG/PNG/GIF/RIFF). A truncated or non-image RIFF (e.g. WAV) passes the
  prefix check; actual decodability is only discovered later at `downsample`.

- **MD-12 (L) Duplicated downsample/key/validation/HTML-entity logic across files.**
  `imagePixelSize` in `ImageUpgradePolicy` and `CachedAsyncImage`; FNV-1a in two places;
  `decodeHTMLEntities` in `ArticleImageResolver` and `RSSFetcher.resolveImageURL`. Divergence risk.

## 4. What worked (keep the idea)

- **The "resolve before publish" contract.** `cards-resolvidos-antes-de-aparecer.md` states the
  whole product rule: a card enters the feed only with a terminal presentation
  (`.image`/`.placeholder`/`.none`); after publication it must not download, swap placeholder for
  image, upgrade resolution, or change layout. `ReadyCardQueue` + `CardPreparationPipeline`
  implement this (`CardPreparationPipeline.prepareSingle` returns a terminal
  `ResolvedCardMedia`; the queue publishes batches, never per-image). This maps 1:1 onto v2's
  `MediaPreparation → PublicationPreparation` boundary and INV-08/INV-05.

- **Downsample-on-ingest via ImageIO, store the downsampled JPEG.** `ImageCache.downsample`
  (`:520`, `kCGImageSourceCreateThumbnailAtIndex`, max 800 px) keeps full-res originals out of
  memory and disk; disk stores the 0.85 JPEG, not the original (`setImage(data:)` `:657`). This is
  the right default for card display and matches v2's measured-metadata preserve decision in
  `MEDIA_DESIGN.md §3`.

- **Metadata-only safety gate before decode.** `MediaAssetStore.hasSafeImageDimensions` (`:166`)
  reads `kCGImagePropertyPixelWidth/Height` and rejects >12 000 px / >50 MP before asking ImageIO
  to rasterize — a decompression-bomb guard. v2 should keep this as a pre-store inspection.

- **Bounded streaming download with a hard byte ceiling enforced *during* transfer.**
  `MediaAssetStore.downloadImageData` (`:143`) and `ImageUpgradePolicy.firstDisplayable` (`:72`)
  iterate `session.bytes` and abort past the ceiling, so a lying/absent Content-Length cannot
  blow memory. v2's HTTP (deferred) should preserve this exact shape.

- **Single-flight download dedup.** The global `ImageDownloadTracker` actor (`:455`) lets a card
  wait for the prefetcher's in-flight download instead of racing it. The concept (not the global
  singleton) is worth keeping in v2's future resolver.

- **Candidate fallback chain + og:image scraping as a *resolution-time* fallback.**
  `ImageURLCandidates` (YouTube sddefault→hqdefault, `:4`) and `ArticleImageResolver`
  (og:image > twitter:image > srcset hero 720–1600 px > JSON-LD > first `<img>`, with decorative
  filtering, `:281`) materially raise hit rate. Keep the *ranking*, run it before publish only.

- **Offline failure taxonomy tool.** `diagnose_image_failures.py` probes a sample per feed and
  buckets failures: `missing_url`, `invalid_url`, `http_4xx/5xx`, `timeout`, `redirect_loop`,
  `connection_error`, `response_too_large`, `too_small`, `undecodable_image`,
  `non_image_response`, `invalid_data_url` (see `inspect_image`/`probe_sample`). It emits
  per-feed failure rates. v2 should keep an equivalent audit to set MediaPolicy thresholds from
  data. (The repo contains the tool and report scaffolding; I did **not** find a committed run
  with a specific failure fraction, so no numeric "% of images fail" is claimed here.)

## 5. What failed and why

Root causes, with commit and doc evidence
(`git -C C:\workspace\feedmine-dev log --oneline -- <path>`).

- **Incremental accretion produced two pipelines (MD-1, MD-8).** The media code grew by patches:
  `ImageCache.swift` history includes `65947900 fix: image pipeline resilience — logging, retry,
  TTL, parsing`, `b9fc062f perf: UI performance — 4 high-impact fixes`, `332a6b93 Fix empty image
  frame for articles with no discoverable image`, and finally `81dda55e fix: consolidate prepared
  feed pipeline — single-path publication`. `MediaAssetStore.swift` history: `335ecc5e fix(images):
  bound downloads and reject unsafe dimensions`, `136272e0 fix(feed): decouple card presentation
  from filtering invalidation (review P0.4)`. The build-16 review's P1 section ("ainda existem duas
  arquiteturas de feed convivendo") lists `ReadyCardQueue` + legacy + `CardPreparationCoordinator`
  + a `preparedFeedPipelineEnabled` flag as a *known* source of real bugs (startup draining the
  reservoir, legacy `cardQueue` overwriting `visibleCards`, truncation to 20). Root cause: no single
  owner for media preparation (violates INV-12) and no gate forbidding a second pipeline (INV-14).

- **The late-upgrade feature fought its own contract (MD-2).** The same tree holds both the design
  note demanding immutability after publish and `improveImageIfNeeded` /
  `CardPreparationCoordinator` doing in-place `text-only → hero`. Root cause: media was treated as a
  live property of a visible card instead of a frozen input to publication. The build-16 review
  traces the scroll regression to this upgrade bumping `visibleCardsGeneration` and invalidating
  derived caches (P0.4). Fix shipped partially via `136272e0` (decouple presentation from filtering
  invalidation), but the upgrade path still exists in `ImageCache.swift`.

- **URL-as-identity (MD-5) and 0×0 persisted metadata (MD-6).** Convenient hashing of the URL made
  the cache simple but means neither pipeline can guarantee the bytes behind a key, and the
  persisted record cannot size a placeholder. Root cause: identity was derived from the *locator*,
  the precise mistake `MEDIA_DESIGN.md §5` ("A URL hash cannot name immutable bytes") forbids in v2.

- **Card-as-pipeline-stage (MD-3, MD-9) and possibility-as-layout (MD-4).** The view both decided
  and executed media work, retried on reappearance, and reserved hero slots speculatively. Root
  cause: no `ResolvedCardMedia` boundary early enough; `cards-resolvidos-antes-de-aparecer.md`
  Apontamentos 1–7 enumerate each symptom and prescribe moving the decision before publication.

## 6. Applying to v2

v2 today has **no download pipeline** (M15). `MediaPreparation` only accepts
`bytes(Data)`/`localAsset(key)`/`unavailable` (`MEDIA_DESIGN.md §9/§11`); `AssetStore` +
`ImageMaterializer` provide durable content-addressed storage; `MediaResolver` and `MediaPolicy`
are doc-only scaffolds; `PresentationCard` (`Sources/FeedMineRuntime/PresentationCard.swift`)
carries `layout` and `mediaAspectRatio` but **no media key**, so UI cannot render an image even
for `.hero`. Below is a concrete proposal that respects the acyclic module graph
(`Media → Domain, Persistence`; Media must **not** import Publication) and the deferral list in
`MEDIA_DESIGN.md §13`.

Design in one picture (all new work owned by Media + Runtime; UI stays pure):

```text
MediaCandidate[] (per OriginRevision, already canonical)
     │  MediaResolver.choose(candidates, policy, device/network ctx) → ChosenCandidate?   (pure, no I/O)
     ▼
MediaPolicy: min dims, max bytes, allowed MIME, cost class, og:image-allowed  (value, Domain-driven)
     │  (Runtime orchestration owns the download — the ONE acquisition owner, INV-12/INV-14)
     ▼
RuntimeMediaAcquisition: bounded streaming GET → ImageMaterializer (inspect→AssetStore) → PublishedMediaKey
     │  on unavailable/unsuitable → MediaPreparationState.unavailable/unsuitable (text-only allowed)
     ▼
PublicationPreparation builds PublishedMediaRef from ACTUAL measured dims (never declared hints)
     ▼
PublishedCard.renderContract + PublishedMediaSet.primary(key,w,h,mime)
     ▼
PresentationCard gains an opaque media handle; UI resolves it via a Runtime-provided
local byte reader (AssetStore.localAsset) — no network, INV-01/INV-02.
```

Per-lesson table:

| # | Lesson from v1 | v2 file | Current state | Recommendation | Review IDs | Priority |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | One owner, one pipeline | `Sources/FeedMineRuntime/*` (new `RuntimeMediaAcquisition`), `FeedMineMedia` | No download path; Media can't fetch (by design) | Put the single download owner in Runtime (already depends on Media+Publication). Never add a second cache/pipeline; no feature flag. | MD-1, MD-8 | P0 |
| 2 | Immutable after publish | `PublicationPreparation.swift`, `PresentationCard.swift` | Draft assembly is pure; late media leaves prior publication unchanged (`§12`) | Keep. Expose media on `PresentationCard` as a *frozen* key; forbid any post-publish upgrade API. Late/better media only improves a *future* occurrence. | MD-2 | P0 |
| 3 | Byte identity, not URL | `AssetStore.swift`, `PublishedMedia.swift` | `PublishedMediaKey` is opaque; AssetStore keys `sha256:<hex>` (`§8`) | Keep sha256 identity; the resolver's candidate URL is an inert locator only. Never hash URLs for identity. | MD-5 | P0 |
| 4 | Carry real dimensions | `PublishedMedia.swift`, `PublicationPreparation` | `PublishedMediaRef` already requires positive paired dims or both nil | Build ref from `ImageMaterializer`-measured W×H/MIME; never persist 0×0; never use declared candidate hints. | MD-6, MD-7 | P0 |
| 5 | Resolve before layout; no speculative hero | `MediaResolver.swift`, `MediaPolicy.swift` | Scaffolds only | `MediaResolver.choose` is pure selection over `MediaCandidate[]` using `MediaPolicy` (min dims, max bytes, MIME allow-list, cost). Layout (hero/thumbnail/textOnly) is chosen from the *resolved* result, not a possibility. | MD-4 | P1 |
| 6 | Candidate ranking + og:image fallback | `MediaResolver.swift` (rank) + a Runtime scraper step | None | Port the ranking order (feed/YouTube first, then og:image > twitter:image > srcset 720–1600 px > JSON-LD) as *resolution-time* candidate generation that runs before publish, bounded + deduped. Keep decorative-URL filtering. | MD-4 | P1 |
| 7 | Decode-bomb + byte ceiling | `ImageMaterializer.swift`, future HTTP in Runtime | Materializer inspects container pre-store (`§8`) | Keep the pre-store dimension/pixel caps; enforce the byte ceiling *during* streaming in the Runtime download. | MD-11 | P1 |
| 8 | Budget + eviction, single-owned | `AssetStore.swift` + new retention gate | No retention (deferred `§13`) | One durable byte budget with bounded eviction behind a future gate; evicting bytes must not rewrite `PublishedCard` (`§8`); fallback via frozen RenderContract. | MD-1 | P2 |
| 9 | Persistent "no image" + bounded retry | new `MediaPreparationState` consumer in Runtime | `unavailable`/`unsuitable` are facts; no retry ledger (by design) | Record terminal unavailability so the UI never re-attempts; any retry lives in Runtime async orchestration, not the view, and is bounded. | MD-9, MD-10 | P2 |
| 10 | Audit-driven thresholds | `scripts/` (port `diagnose_image_failures.py`) | Not ported | Keep an offline failure-taxonomy audit; use real failure buckets to set `MediaPolicy` min-dims / MIME allow-list rather than guessing. | — | P2 |

Module-rule guardrails for this design: the download owner lives in **Runtime** (the only module
that already depends on both Media and Publication), so no `Media → Publication` edge and no
second acquisition engine is introduced (INV-12/INV-14, `MEDIA_DESIGN.md §2/§11`). Feed scrolling
never triggers media acquisition (INV-03). First warm launch renders from local assets only
(INV-01/INV-07): the UI's media handle resolves through a Runtime-provided local byte reader, never
a URL.

## 7. Open questions for the product owner

1. **og:image scraping at acquisition vs. resolution.** v1 scrapes the article page at image-
   resolution time. v2's `MediaCandidate` facts come from the connector/admission boundary (INV-13).
   Should an og:image discovered by scraping become a canonical `MediaCandidate` (new revision), or
   stay a Runtime-only resolution fallback that never enters canonical supply?
2. **Edited image under unchanged version (ties to MD-5).** When a publisher swaps the image bytes
   behind the same URL without a new revision, should v2 ever refresh a published card's image, or
   is "frozen forever, new bytes only affect future occurrences" the intended rule? (`MEDIA_DESIGN.md
   §12` implies the latter — confirm.)
3. **Audio/video thumbnails.** v1 derives YouTube thumbnails by URL convention and shows podcast
   now-playing with no artwork prefetch. v2 defers audio/video preparation (`§13`). Is a video/audio
   *poster image* in scope for the first media slice (as an image candidate), or fully deferred?
4. **Budget numbers.** v1 used 100 MB disk + 200 MB memory *per pipeline*. What single durable byte
   budget and eviction trigger should v2 target, and should it be device-adaptive per INV-04?
5. **Placeholder policy.** v1 has `.placeholder` vs `.none` vs text-only. Does v2 want a sized
   placeholder (needs dims before bytes) or only text-only when media is unavailable?

---

### 10-line summary

1. v1 ships **two** image pipelines over two disk caches (MD-1): `CachedAsyncImage`/`ImageLoader`/
   `ImagePrefetcher` (live view) and `CardPreparationCoordinator`/`MediaAssetStore` (prepared).
2. The best idea — "resolve media before the card is published, immutable after" — is written in
   `cards-resolvidos-antes-de-aparecer.md` and realized by `ReadyCardQueue`+`CardPreparationPipeline`.
3. That contract is violated in the same tree by late `text-only→hero` upgrades (MD-2), which the
   build-16 review ties to scroll stutter via cache-generation invalidation.
4. Image identity is the **URL hash**, not bytes (MD-5); persisted metadata is 0×0 (MD-6) — both
   exactly what v2's `MEDIA_DESIGN.md` forbids with `sha256:` keys and measured dims.
5. Good primitives to keep: ImageIO downsample-on-ingest, decode-bomb dimension gate, byte-ceiling
   streaming download, single-flight dedup, candidate ranking + og:image fallback.
6. `hasPotentialImage` reserves hero slots speculatively (MD-4); the card view itself runs network
   work and retries on reappear (MD-3, MD-9) — layout must follow a resolved fact, not a possibility.
7. v2 has no downloader (M15); `MediaResolver`/`MediaPolicy` are scaffolds; `PresentationCard`
   carries layout + aspect ratio but no media key.
8. Proposed v2 design: put the **single** download owner in Runtime (keeps Media acyclic), pure
   `MediaResolver.choose` + value `MediaPolicy`, materialize to sha256 `AssetStore`, build
   `PublishedMediaRef` from measured dims, expose a frozen media handle on `PresentationCard`.
9. Guardrails: no second pipeline/flag (INV-14), one owner (INV-12), scroll never fetches (INV-03),
   warm launch resolves local bytes only (INV-01/INV-07), late media only improves future cards.
10. Open with the PO: og:image→canonical-candidate vs resolution-only, byte-swap refresh policy,
    audio/video posters, a single adaptive byte budget, and placeholder sizing.
