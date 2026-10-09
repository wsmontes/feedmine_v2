# v1 study — ingestion, networking, parsing and sources

Static review of FeedMine v1 (`C:\workspace\feedmine-dev`), area: ingestion/networking/parsing.
No Swift toolchain here; nothing was built or run. Every code claim cites `file:line` as read on
2026-10-09. v2 counterparts confirmed by reading `Sources/FeedMineSyndication` and
`Sources/FeedMineAcquisition`. Cross-references to the v2 review are to
`docs/reviews/CODE_REVIEW_2026-10-08.md`.

## 1. Scope

Files studied (LOC = file bytes/avg; line counts from the reads):

| File | LOC | Role |
| --- | --- | --- |
| `Services/RSSFetcher.swift` | ~1335 | FeedKit parse, metadata/media extraction, HTML sanitization, concurrency, audio probe |
| `Services/FeedHTTPSync.swift` | ~300 | Conditional GET, 304, Retry-After, http→https upgrade, bounded body |
| `Models/HTTPValidators.swift` | ~190 | Validators, `ParsedCacheControl`, `CadenceEstimator`, `SourceCapabilities` |
| `Models/FeedItem.swift` | ~560 | Item model + `generateID` (identity/dedup), media/URL resolution |
| `Models/FetchOutcome.swift` | ~70 | `HTTPOutcome`, `FeedFetchOutcome` |
| `Models/FeedFetchResult.swift` / `FeedFetchBatch.swift` | ~35 / ~15 | Per-fetch / per-batch aggregates |
| `Models/FeedSource.swift` | ~250 | Source model (skimmed) |
| `Services/InputParser.swift` | ~165 | Free-text URL extraction + classification |
| `Services/ImportFileStore.swift` | ~70 | Atomic file I/O for imports |
| `Services/OPMLParser.swift` | ~1030 | OPML + `normalizeURL`/`requestURL` identity vs request URL |
| `Services/AsyncLimiter.swift` | ~90 | Per-category bounded concurrency |
| `Services/NetworkMonitor.swift` | ~70 | Reachability with "unknown vs offline" distinction |
| `Services/BackgroundRefreshService.swift` | ~40 | Lightweight BGAppRefreshTask path |
| `feedmineTests/HTTPValidatorsTests.swift` | ~130 | Cache-Control / cadence / codable tests |
| Docs | — | `specs/2026-07-27-http-sync-layer-design.md`, `code-review-contador-sources.md` |

Not re-reviewed in depth (out of area or very large): `AdaptiveScheduler.swift`, `SourceRegistry.swift`,
`CatalogUpdateService.swift`, `URLResolver.swift`, `FeedStore.swift` (411 KB). `Fixtures/` directory
does **not** exist under `feedmineTests/` (only `Support/`, `Performance/`); feed quirks below are
derived from code, not fixture files.

## 2. How v1 works

```text
InputParser / OPMLParser ── FeedSource(url, category, region, language)
        │                         │ normalizeURL = identity key; requestURL = fetch URL
        ▼                         ▼
RSSFetcher.fetchAll / fetchStarter   (sliding-window concurrency, cap 5 / 15)
        │  per source
        ▼
FeedHTTPSync.fetch(source, validators)
   http→https upgrade · If-None-Match/If-Modified-Since · stream body ≤20 MB
   200 → Data · 304 → notModified · 429/503 → throttled(Retry-After) · else failed
        │  Data
        ▼
FeedKit FeedParser.parse() → extractItems (rss / atom / json branches)
   title/excerpt via FeedTextSanitizer (entity decode + CDATA unwrap + tag strip)
   image via media:* / itunes / enclosure / first <img> / channel fallback
   audio enclosure → validateAudio (bounded HEAD/ranged-GET probe, cached)
   FeedItem.generateID(sourceURL|guid?|link?|title+ts) = SHA256 identity
        ▼
FeedFetchResult(outcome, items, elapsedMs) ──► FeedFetchBatch(counts, sourceOutcomes)
        ▼
FeedStore.persist… (owns dedup-by-id, merge, language, sections)  [out of area]
```

Key design: HTTP semantics isolated in `FeedHTTPSync`; parsing/metadata in `RSSFetcher`; `Data`
is the only thing crossing the boundary (`specs/2026-07-27-http-sync-layer-design.md`, "Separate
HTTP from parsing"). Identity (`normalizeURL`) and request URL (`requestURL`) are deliberately
different strings (`OPMLParser.swift:740`, `753`).

## 3. Code review findings

Severity: **H** can stall/corrupt visible feed with real feeds; **M** correctness/perf; **L** hygiene.

### IN-1 (H) — Transparent redirects discard the canonical URL for 301/308
`FeedHTTPSync.swift:134-140`: the comment states redirects are "followed transparently by
URLSession, so only the final response reaches this branch", and `canonicalURL =
httpResponse.url?.absoluteString` is only set on the 200 branch. There is **no manual redirect
handling and no distinction between temporary (302/307) and permanent (301/308) redirects**. The
canonical URL is captured but, per the design doc §6, is only "stored" — the catalog URL is never
rewritten, so a permanently-moved feed is re-resolved through the redirect on every single fetch
forever. Effect: wasted round-trips and a latent duplicate-source risk if the same feed is reachable
under two URLs. Mechanism verified; the "auto-fix catalog URLs" is explicitly deferred ("Later")
in the design doc §6 table.

### IN-2 (H) — Unconditional http→https upgrade with silent fallback to http on redirect
`FeedHTTPSync.swift:95-104`: every `http://` request URL is rewritten to `https://` before sending.
The 200-branch comment at `:135` admits "a redirect back to http is likewise followed by
URLSession." So the upgrade is cosmetic: a server that 301s https→http is silently downgraded and
accepted. There is no scheme-downgrade refusal. Effect: a MITM-capable network can force plaintext;
also conflicts with the v2 decision in review item **M13** ("Refuse downgrade"). v1 never refuses.

### IN-3 (H) — `guid`/`link` identity has no normalization; trivial changes mint a new item
`FeedItem.generateID` (`FeedItem.swift:542-556`) hashes `"\(sourceURL)|\(token)"` where `token` is the
raw `guid` else raw `link` else `title|timestamp`. The guid/link is **not** normalized (no
`normalizeURL`, no case/trailing-slash/query folding) and `sourceURL` is the raw source string. So:
(a) a feed that emits `?utm_source=…` on its `<link>` (and no `<guid>`) produces a new id on every
publish; (b) the title-based fallback uses `publishedAt.timeIntervalSince1970` as a string, so a
re-published item with a drifting timestamp duplicates. Effect: duplicate cards for one article —
the same class of bug the v2 review raises as **H3** (unversioned revisions reselected). v1's only
guard is that `guid`/`link` are usually stable; when they are not, dedup fails.

### IN-4 (M) — Future `pubDate` is accepted verbatim and becomes `publishedAt`
`RSSFetcher.swift:makeItem` sets `itemPubDate = metadata.publishedAt ?? metadata.updatedAt` and
`publishedAt: itemPubDate ?? Date()` (`FeedItem.swift` init). There is **no clamp against the fetch
time**. A feed with a future `<pubDate>` (common with scheduled posts and timezone bugs) sorts to
the top permanently in any recency ordering. This is exactly v2 review **M12**. Verified: no
`min(date, now)` anywhere in `makeItem` or `extractItems`.

### IN-5 (M) — Date parsing is entirely delegated to FeedKit with no fallback or validation
There is no date-parsing code in the ingestion layer at all — `item.pubDate`, `entry.published`,
`entry.updated`, `jsonItem.datePublished/dateModified` come straight from FeedKit
(`RSSFetcher.swift` extractItems branches). Effect: any format FeedKit cannot parse yields `nil`,
which silently falls back to `Date()` at persist time (IN-4 path), stamping "now". Malformed or
locale-specific dates (e.g. non-POSIX month names) are therefore indistinguishable from fresh
content. No test covers date robustness (none in `HTTPValidatorsTests`; no fixtures dir).

### IN-6 (M) — HTML entity table is hand-maintained and lossy; some entities map to ASCII
`FeedTextSanitizer.namedHTMLEntities` (`RSSFetcher.swift`) is a hand-rolled dictionary. Several
mappings are **lossy transliterations**, not the real character: `bull`→`*`, `hellip`→`...`,
`laquo`→`<<`, `mdash`/`ndash`→`-`, `copy`→`(c)`, `trade`→`TM`, `euro`→`EUR`, `pound`→`GBP`. Numeric
entities are decoded correctly (`decodedHTMLEntity`), but any named entity outside the table is left
as the literal token (`decodeHTMLEntities` appends `token` on miss). Commit history shows this was
patched twice (`f1ac4b75`, `382b9546` "add full HTML4 named entity table"), i.e. the table was
repeatedly found incomplete in practice. Effect: typographic corruption in titles/excerpts.

### IN-7 (M) — Description HTML is stripped by regex, not a parser
`FeedTextSanitizer.sanitizedHTMLText` decodes entities, unwraps CDATA, then strips tags with
`"<[^>]+>"` (`RSSFetcher.swift` `htmlTagRegex`). This is adequate for display text but will mangle
content containing `<` in text (e.g. `a < b` or unescaped math), and `<script>`/`<style>` bodies are
left as text (only the tags are removed). Effect: residual script/style text in excerpts for sloppy
feeds. v1 accepts this because excerpts are capped at 200 chars (`extractExcerpt`), limiting blast
radius. This is the plain-text-at-the-boundary concern v2 raises as **M11**.

### IN-8 (M) — `fetchAll` isolates failures per source, but there is NO backoff and NO fairness
`RSSFetcher.fetchAll` (`:200-260`) uses a correct sliding window and records each source's outcome
into `sourceOutcomes` — a single slow/failed feed cannot stall the batch (good, see §4). **But**:
there is no per-source failure backoff inside the fetcher, and no rotation/fairness — ordering is the
caller's `sources` array order. Repeated-failure backoff lives only in `AdaptiveScheduler`
(design doc §3, "Backoff (preserved from SourceScheduler)"), i.e. outside this layer. Effect: if the
scheduler is bypassed (e.g. `fetchStarter` cold start always takes the first N), a permanently broken
feed is retried every cold start. This maps to v2 review **H2 residuals 3 (no backoff)** and
**4 (inconsistent order)**.

### IN-9 (M) — Audio-playability probe can issue a full GET and strip legitimate podcasts
`RSSFetcher.probeAudio`/`probeAudioRanged` (`:430-470`): HEAD first; on 405/501 or any error it
retries a ranged GET (`bytes=0-0`). The ranged path drains up to 64 KB (`asyncBytes.prefix(65_000)`)
if the server ignores `Range`. `classify` treats a 2xx with `text/`|`image/` content-type as
`.notAudio` and **caches that false** (`isPlayableAudio`), permanently stripping audio. A server that
returns an HTML error page with `200 text/html` for a transient outage therefore permanently demotes a
real podcast. Mitigation present: transient 3xx/403/429/5xx → `.unknown` → kept, not cached (commit
`87de7440` "don't strip podcast audio on transient probe failures"). The residual risk is the
`200 text/html` case.

### IN-10 (M) — No charset/encoding handling; relies on FeedKit + implicit UTF-8
The body is accumulated as raw `Data` (`FeedHTTPSync.swift:150-175`) and handed to `FeedParser(data:)`.
There is no inspection of the `Content-Type` charset or the XML declaration's `encoding=`. FeedKit
handles common cases, but Windows-1252 / ISO-8859-1 feeds that omit a BOM and are mislabeled can
mis-decode. The entity table (IN-6) partially compensates for Latin-1 named entities but not for raw
high bytes. No test covers non-UTF-8 feeds.

### IN-11 (L) — Two independent `URLSession`/`User-Agent` definitions drift
`FeedHTTPSync.swift:17-20` sends `User-Agent: FeedMine/1.0 (https://feedmine.app/bot)` and a rich
`Accept`; `RSSFetcher.init` (`:34-38`) builds its **own** sessions with `User-Agent: Feedmine/1.0`
(different casing, no bot URL) and a shorter `Accept`, then passes those sessions into `FeedHTTPSync`.
So the headers that actually ship depend on which session the injected `FeedHTTPSync` holds — the
documented bot UA may never be sent. Effect: inconsistent server-side identification; the "real bot
page" hygiene in the design doc §7 is undermined.

### IN-12 (L) — `Retry-After` only parsed for 429/503; `Cache-Control`/`Expires` captured but gating lives elsewhere
`FeedHTTPSync.parseRetryAfter` is solid (seconds or HTTP-date, clamped 0–24 h, `:200-230`). But the
validators it stores (`ttl`, `expires`, `cacheControl`, `skipHours/Days`) are only *acted upon* by
`AdaptiveScheduler`. Within the fetch layer there is no honoring of `no-store`. Minor; noting the
split so v2 keeps the gate in one owner.

## 4. What worked (keep the idea)

- **Clean HTTP/parse split.** `FeedHTTPSync` owns transport; `RSSFetcher` owns formats; `Data`
  crosses (`FeedHTTPSync.swift` whole; design doc "Design Decisions #2"). v2 keeps this
  (`SyndicationHTTP` vs `SyndicationTranslator`) — the boundary proved correct.
- **Sliding-window concurrency with per-source isolation.** `RSSFetcher.fetchAll:200-260` refills a
  freed slot immediately so one slow feed occupies only its own slot; `fetchStarter:300-360` adds a
  wall-clock deadline + "enough content" early exit. Commit `814b0a5e` ("sliding-window concurrency")
  replaced a chunked approach that "idled up to 14 others". Evidence: the explanatory comment at
  `:210-218`. Keep the *shape*; v2 must add bounded parallelism (it is currently sequential — review
  **H2 residual 2**).
- **Bounded body with hard ceiling.** 20 MB cap streamed in 16 KB chunks (`FeedHTTPSync.swift:150-175`)
  — rejects HTML dumps/binaries masquerading as feeds. v2 reproduces this (`SyndicationHTTP.swift`
  `bodyTooLarge`, declared-length pre-check).
- **Conditional GET round-trip.** `If-None-Match`/`If-Modified-Since` out, re-extract `ETag`/
  `Last-Modified` on 200/304 (`FeedHTTPSync.swift:107-114`, `extractValidators`). Tested indirectly by
  `HTTPValidatorsTests` (cache-control/codable). Keep.
- **"Unknown vs offline" reachability.** `NetworkMonitor.isKnownOffline` gates offline fast-paths on
  `!isConnected && hasReceivedFirstPath` (`NetworkMonitor.swift:19-33`) — avoids misclassifying an
  online cold launch whose first path callback hasn't fired. Subtle and correct; worth carrying into
  v2's acquisition gating.
- **Atomic import file writes + size ceiling.** `ImportFileStore.saveJSON` writes temp then
  `replaceItemAt`; `read` enforces `maxBytes` (`ImportFileStore.swift:14-30`). Keep for OPML import.
- **Per-category concurrency limiter with cancellation-safe waiters.** `AsyncLimiter` /
  `AsyncSemaphore.wait` returns `false` (no slot) on cancellation instead of leaking a signal
  (`AsyncLimiter.swift:20-70`). Good primitive if v2 needs category limits.
- **Tracking-pixel / favicon / logo rejection at the source.** `resolveImageURL` and
  `isLikelyFaviconOrLogo`/`isLikelyDecorativeImageURL` (`RSSFetcher.swift`) reject spacers, 1x1 gifs,
  tiny-dimension logos, and nested-proxy garbage before anything is persisted. Commits `99df7f9b`,
  `71fa05bb`, `42ecf862`, `ee1375ab` show these were all production-driven. Carry the *rules* (as a
  media-admission policy) even though v2's `SyndicationTranslator` currently takes thumbnails naively.
- **Identity URL vs request URL separation.** `OPMLParser.normalizeURL` strips www, default ports,
  trailing slashes, and tracking/`x-amz-*` query params for the dedup key, while `requestURL`
  preserves signed params for fetching (`OPMLParser.swift:672-756`). This is the right model and
  directly answers IN-3's gap for *source* identity.

## 5. What failed and why (root causes, with commits)

- **HTML entity decoding was repeatedly wrong.** The named-entity table was added/expanded in
  `f1ac4b75` and `382b9546` ("add full HTML4 named entity table to FeedTextSanitizer") and an earlier
  `d361e360` ("fix Atom HTML entity bug") and `bf0ba32b` ("podcast XML entities"). Root cause: a
  hand-maintained table instead of a real entity decoder; every feed that used an unlisted entity
  surfaced a bug (IN-6). Lesson: use a complete decoder, don't curate a table.
- **Images were a long tail of production fixes.** `b42d9a40` (resolve relative image URLs),
  `99df7f9b` (reject tracking pixels), `bb9b4e84` (http→https for ATS), `71fa05bb`/`42ecf862` (skip
  channel favicons/logos), `ee1375ab` (don't reject large artwork), `389a7492` (Blogspot thumbnail
  upgrade regex), `dfbf13b6` (podcast channel artwork fallback). Root cause: real feeds put the wrong
  image everywhere; a naive "first image" picks favicons, spacers, and avatars. Lesson: image
  selection needs an explicit policy, not an inline heuristic — and v2 currently has none (M15).
- **Podcast audio false-strips.** `4316c5ec` ("don't tag non-audio enclosures as podcasts"),
  `0f349c71` ("validate podcast audio is playable"), `87de7440` ("don't strip podcast audio on
  transient probe failures"). Root cause: enclosures lie about type; probing is necessary but a naive
  probe permanently demotes good feeds on transient errors (IN-9). Lesson: only a *definitive* negative
  may be cached.
- **Concurrency stalls.** `814b0a5e` ("sliding-window concurrency in fetchAll"), `0884ba52` ("memory
  caps, auto-retry on reconnect, task cancellation"), `6e10c438` (maxConcurrent tuning). Root cause: a
  chunked task group let the slowest feed in a chunk block all free slots. Lesson: refill per-completion,
  never per-chunk — and give cold start its own short-timeout session (`RSSFetcher.init` starterSession).
- **Source-identity collisions at catalog scale.** `65614c6a` ("P0-01 identity/request URL
  separation"), `193518db` ("entity recrawl collision detection"), `5c27f3f3` ("cross-language identity
  contract"), `77dedbd2` ("identity impact assessment — 77,443 unchanged, 0 changed"). Root cause:
  normalizing the request URL for identity broke signed/auth feeds; using the raw URL for identity
  caused duplicate sources. The two-URL model (§4) was the fix. Lesson: *source* identity ≠ fetch URL;
  **item** identity (IN-3) never got the same rigor and remains weak.
- **Source counter semantics drift** (`docs/code-review-contador-sources.md`). The startup "ready"
  checkmark counted HTTP successes (incl. 304) against the full catalog denominator, declaring runway
  ready at `100/43556`. Root cause: conflating "responded" with "contributed items", and mixing three
  different numerators/denominators. Lesson for v2: define runway-readiness from *contributing* sources
  and keep one explicit status model — relevant to v2's adaptive runway (INV-04) and review **M14**.

## 6. Applying to v2

Per lesson: v2 location, current v2 state (read), recommendation, review link, priority.

### L1 — Item identity must be normalized and version-aware (IN-3)
- v2 location: `SyndicationTranslator.swift` (`identity(...)`, `rss(...)`, atom/json branches).
- Current state (read): object identity = raw `guid`→raw `link` (`rss`), raw `item.id`→`link` (atom),
  raw `item.id` (json); **no normalization** of the value before it becomes `ExternalIdentity.value`.
  Version identity exists for atom (`atom-updated`) and json (`json-modified`) but **RSS has none**.
- Recommendation: normalize the link/guid value (lowercase host, strip tracking params, trailing
  slash) with a shared helper before building `ExternalIdentity`; for RSS with no stable guid, derive
  a content fingerprint as the version identity so an unchanged item is recognized. Keep the two-URL
  model from v1's `OPMLParser` for *target* endpoints.
- Review link: **H1** (version identity from dates), **H3** (reselection of unversioned revisions).
- Priority: **now** (H3 is an open visible-duplicate bug).

### L2 — Clamp future dates at the boundary (IN-4, IN-5)
- v2 location: `SyndicationTranslator.swift` `observation(... authored:, modified: ...)`.
- Current state (read): `authored`/`modified` are passed straight from FeedKit; `observedAt` is
  already a parameter but is only used for `observedAt`, not as a clamp.
- Recommendation: `authoredAt = min(parsedDate, observedAt)` (and treat `nil`/unparseable explicitly,
  not as `now`); keep raw dates in a side field if provenance matters. Add translator tests for
  future-date and unparseable-date feeds.
- Review link: **M12**.
- Priority: **now** (one-line clamp; currently pins bad items to the top).

### L3 — Convert description HTML to plain text at the connector boundary (IN-6, IN-7)
- v2 location: `SyndicationTranslator.swift` (`summary:`/`body:`), honoring INV-13.
- Current state (read): `summary` = `item.description` (RSS) / `item.summary?.text` (atom) raw;
  `body` = `item.contentText`/`contentHtml` raw. No sanitization. Review **M11** confirms raw HTML
  reaches `primaryText` and is now rendered verbatim.
- Recommendation: port a *complete* entity decoder (not v1's hand table) + tag strip into a
  `SyndicationText` helper; strip `<script>`/`<style>` bodies, not just tags. Keep the raw HTML only if
  a later reader view needs it, in a separate field.
- Review link: **M11**.
- Priority: **before the feed renders real text to users** (shipping blocker for readable cards).

### L4 — Refuse scheme downgrade; decide redirect-canonicalization policy (IN-1, IN-2)
- v2 location: `SyndicationHTTP.swift` (`SyndicationHTTPClient.fetch` redirect loop) and
  `SyndicationConnector.swift`.
- Current state (read): v2 **already** does manual redirects with a capacity, refuses userinfo, and
  requires http/https (`SyndicationHTTP.swift` `301,302,303,307,308` branch). It does **not** refuse
  https→http downgrade, and the review notes these redirect errors are not yet mapped to operational
  failure (**H2 residual 1**). v1's canonical-URL rewrite is still absent in both.
- Recommendation: in the redirect branch, reject a destination whose scheme is "weaker" than the
  current request's (https→http); map `invalidRedirectTarget`/`redirectCapacityExceeded`/
  `missingRedirectLocation` to `ConnectorOperationalFailure` so one bad feed doesn't abort the cycle.
- Review link: **M13**, **H2 residual 1**.
- Priority: **now** for downgrade refusal; **before multi-feed cold start** for the error mapping.

### L5 — Per-target failure isolation + backoff + fair rotation (IN-8)
- v2 location: `AcquisitionPlanner.swift`, `AcquisitionCoordinator.swift`, and the composition cycle.
- Current state (read): review says execution is still sequential, aborts on error, no backoff,
  inconsistent ordering (**H2 residuals 1–4**). v1's `fetchAll` already settles per source into
  `sourceOutcomes` — the shape to copy.
- Recommendation: collect per-target success/failure (do not throw out of the loop), add bounded
  parallelism (`withThrowingTaskGroup` + limit, mirroring v1's sliding window), add per-target backoff
  keyed on consecutive failures, and rotate target order across cycles.
- Review link: **H2**.
- Priority: **before enabling more than a handful of targets** (starvation risk at catalog scale).

### L6 — Media/image selection needs an explicit admission policy (IN-9 + §5 image fixes)
- v2 location: `SyndicationTranslator.thumbnails(...)` / `media(...)`, and `FeedMineMedia` (future).
- Current state (read): `SyndicationTranslator` takes `item.media?.thumbnails` and
  itunes/image/bannerImage naively, with only a web-URL scheme/host check (`webURL`). No favicon/
  spacer/logo rejection, no size preference, no audio probe. Review **M15**: no media pipeline exists.
- Recommendation: port v1's rejection *rules* (tracking pixels, 1x1, tiny-dimension logos, nested
  proxies, SVG/non-raster) as a `MediaCandidate` admission policy; prefer largest declared width;
  defer the audio-playability probe to media preparation and cache only definitive negatives.
- Review link: **M15**, media handling.
- Priority: **before feature "images in cards"** (later than text, but the rules are hard-won).

### L7 — One owner for HTTP identity/headers and cache gating (IN-11, IN-12)
- v2 location: `SyndicationHTTP.swift` (request construction), `SyndicationConnector.swift`.
- Current state (read): v2 builds requests in one place (`SyndicationHTTPClient.fetch`) with
  `reloadIgnoringLocalCacheData` and conditional headers only when `nextItemIndex == 0`. No duplicate
  session/UA definitions — v2 already avoids IN-11. There is no User-Agent set at all currently.
- Recommendation: set a single documented `User-Agent` (with a real bot URL) and `Accept` in one
  place; keep cache/TTL gating in Acquisition's planner, not the connector.
- Review link: (hygiene; relates to **H2 residual 5** placement).
- Priority: **later** (set UA before public crawling).

### L8 — Runway-readiness measured by contributing sources, not HTTP 200s (§5 contador doc)
- v2 location: `AcquisitionPlanner.swift` / runway in `FeedMineRuntime` (`RunwayController`).
- Current state (read): out of this area's code; review **M14** notes scroll is not wired to the
  runway yet, so readiness has no producer.
- Recommendation: when readiness UI exists, define "ready" from admitted/contributing supply, never
  from fetch success count; never show a fraction whose numerator and denominator are different
  universes (the v1 `100/43556` bug).
- Review link: **M14**, INV-04/INV-06.
- Priority: **before first-launch preparation UI**.

### Real-world feed quirks v2's `SyndicationTranslator` must handle (from v1 code/commits)
1. CDATA-wrapped **and** entity-escaped CDATA in titles (`&lt;![CDATA[…]]&gt;`) — v1 `unwrapCDATA`.
2. Named HTML entities beyond the base set, incl. Latin-1 accents (`&eacute;` etc.) — v1 table, fixed
   twice (`f1ac4b75`/`382b9546`).
3. Numeric entities decimal and hex, incl. `&#160;`/`&#xA0;` → space — v1 `decodedHTMLEntity`.
4. `description`/`content:encoded` containing full HTML markup, incl. `<img>`, `<script>`, lazy
   `data-src`/`data-srcset`/`srcset` — v1 `extractFirstImageFromHTML`.
5. Relative, protocol-relative (`//host/...`), and entity-escaped (`&amp;`) media URLs — v1
   `resolvedMediaURL`/`resolveImageURL`.
6. Tracking pixels, 1x1 spacers, `count.gif`, favicons, tiny `-32x32`/`-150x150` logos as the only
   image — v1 rejection rules.
7. Channel-level artwork reused per item (and the Google News aggregator logo special-case) — v1
   `feedImage` fallback + `news.google.com` guard.
8. Enclosures mislabeled: audio served as `octet-stream`/`video/mp4`; non-audio tagged as enclosure —
   v1 `isAudioCandidate`/`classifyMedium`.
9. Future `pubDate` and missing/unparseable dates — IN-4/IN-5.
10. Missing `guid`: must fall back to `link`, then title+date; links carrying `utm_*` churn — IN-3.
11. `media:group/media:content` vs item-level `media:content`/`media:thumbnail` (FeedKit maps these
    inconsistently) — v1 `bestMediaImageURL`.
12. Atom entries with multiple `<link>`s: must pick `rel="alternate"`/no-rel non-feed link, not the
    `self`/`enclosure`/feed link — v1 atom `entryLink` logic (v2 does a simpler variant).
13. 304 Not Modified, 429/503 with `Retry-After` (seconds or HTTP-date, absurd values) — v1
    `parseRetryAfter` clamp.
14. Blogspot/Blogger thumbnail size tokens (`/s72/`→`/s1200/`) — v1 `upgradedKnownThumbnailURL`
    (optional; a media-quality nicety).

## 7. Open questions for the product owner

1. **Edited-article policy.** If a publisher edits a title/summary without changing a version date,
   is that a *new* occurrence (new card) or an in-place update of the existing card? v1 effectively
   makes a new card when guid/link changes (IN-3); v2 **H1/H3** need an explicit decision in
   `PRODUCT_INVARIANTS.md`.
2. **Redirect canonicalization.** Should a permanent (301/308) redirect rewrite the stored target
   endpoint, or keep re-resolving every fetch (v1 behavior, IN-1)? Rewriting risks collapsing two
   catalog entries into one.
3. **Future/absent dates.** Clamp to `observedAt` (recommended), drop the item, or keep the future
   date? Affects ordering and "newest" semantics (IN-4).
4. **Non-UTF-8 feeds.** Is honoring declared charset / Windows-1252 in scope for v1 of v2, or accept
   FeedKit's default and mojibake the long tail (IN-10)?
5. **Audio/podcasts.** Are podcast enclosures in scope for the first v2 release? If yes, the
   playability-probe policy (definitive-negative-only, IN-9) needs a home in `FeedMineMedia`.
6. **Crawler identity.** Is `https://feedmine.app/bot` a real page? A public crawler should ship a
   stable, documented User-Agent before scale (IN-11).

---

### Top 10 findings (summary)
1. IN-3 (H): item `generateID` hashes raw guid/link with no normalization → duplicate cards (ties to v2 H3).
2. IN-1 (H): transparent redirects never rewrite the canonical URL → permanent re-resolution of moved feeds.
3. IN-2 (H): unconditional http→https upgrade but https→http redirects silently accepted → no downgrade refusal (v2 M13).
4. IN-4 (M): future `pubDate` accepted verbatim, no clamp to fetch time → bad items pinned to top (v2 M12).
5. IN-6 (M): hand-maintained HTML entity table, lossy ASCII transliterations; fixed twice in history.
6. IN-8 (M): fetch layer isolates failures (good) but has no backoff/fairness; backoff lives only in the scheduler (v2 H2).
7. IN-9 (M): audio probe can permanently strip a real podcast on a `200 text/html` error page.
8. IN-5/IN-10 (M): dates and charset fully delegated to FeedKit; unparseable → silent `Date()`/mojibake, untested.
9. Keep: HTTP/parse split, sliding-window per-source isolation, 20 MB bounded body, identity-vs-request-URL model.
10. v2 now: normalize+version item identity, clamp future dates, sanitize description HTML at the connector, refuse downgrade, add per-target isolation+backoff.
