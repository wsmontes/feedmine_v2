# v1 Study 04 — Catalog, Source Curation, Editorial Selection, Taxonomy, Search, User State

Static review of FeedMine v1 (`C:\workspace\feedmine-dev`). No Swift toolchain; no build run.
Line numbers refer to the working-tree files read on 2026-10-09. Claims are limited to code I read.

## 1. Scope

v1 files reviewed (LOC = file size on disk, approximate line counts for the large ones):

| Area | File | LOC |
| --- | --- | --- |
| Catalog store/compiler | `FeedEngine/SQLiteCatalogStore.swift` | 817 |
| Catalog models | `FeedEngine/CatalogModels.swift` | ~290 |
| Catalog protocols | `FeedEngine/CatalogProtocols.swift` | ~230 |
| Catalog identity | `FeedEngine/CatalogIdentity.swift` | ~75 |
| Catalog input DTOs | `FeedEngine/CatalogInput.swift` | ~250 |
| OPML scanner | `FeedEngine/OPMLCatalogScanner.swift` | ~300 |
| Personalization engine | `Services/CuratedPreferenceEngine.swift` | 1008 |
| Taxonomy tree | `Services/TaxonomyStore.swift` | ~900 (read head) |
| Search | `Services/SearchEngine.swift` | ~430 |
| Editorial diversity | `Services/EditorialSequencer.swift` | ~140 |
| Preset multipliers | `Services/PresetScorer.swift` | ~110 |
| Recipe → profile | `Services/FeedRecipeResolver.swift` | ~90 |
| Circadian (presentation only) | `Services/CircadianEngine.swift` | ~390 |
| Catalog shipping/update | `Services/CatalogUpdateService.swift` | ~560 |
| Catalog diagnostics | `Services/FeedEngineCatalogDiagnostics.swift` | ~220 |
| User state (read for query/collection surface) | `Services/UserStateStore.swift` | 1267 (not fully read) |

Python side (summary level, from `editorial/feed-curation/README.md` + `source-experience.md`):
`scripts/reconcile_feed_corpus.py`, `curate_opml_catalog.py`, `build_catalog.py`,
`publish_catalog_update.py`, `catalog_identity.py`. Not opened line-by-line.

Docs read: `docs/audit-taxonomy-filtering-2026-07-16.md`, `docs/code-review-filtros-shake-source.md`,
`editorial/feed-curation/README.md`, `editorial/feed-curation/source-experience.md`.

## 2. How v1 works

### 2.1 Catalog pipeline (offline, pre-shipped)

```text
Parquet corpus (immutable)
  → reconcile_feed_corpus.py  (identity, dedup, quarantine)
  → curate_opml_catalog.py    (one editorial home per source → OPML tree)
  → build_catalog.py          (OPML → catalog.sqlite + manifest.json)
  → publish_catalog_update.py (re-validate, sign, snapshot)
  → bundled in app  (+ optional signed remote update, DEBUG only)
```

The runtime never crawls to build the catalog. `SQLiteCatalogCompiler.compile`
(`SQLiteCatalogStore.swift:49`) scans OPML (`OPMLCatalogScanner`) into
`CatalogSourceOccurrence[]`, folds occurrences by `SourceKey`, builds the node tree,
writes `catalog_source` / `catalog_node` / `catalog_placement` + an FTS5 table, atomically
replaces the DB file (`SQLiteCatalogStore.swift:71`).

Identity is a SHA-256 → `UInt32` digest of the normalized URL
(`CatalogIdentity.sourceID`, `CatalogIdentity.swift:25`; collision-reserved zero → 1).
`canonicalURLKey` delegates to `OPMLParser.normalizeURL` so the Swift runtime and the Python
identity (`catalog_identity.py`) share one normalization (README §Identity).

### 2.2 Reading the catalog

`SQLiteCatalogRepository` (actor, `SQLiteCatalogStore.swift:316`) serves keyset-paginated
browse (`browseSQL`, `:462`) and FTS search (`searchSQL`, `:521`). Search ordering mixes a
synthetic `sort_key` (default_enabled, 100−quality, title). The separate runtime `SearchEngine`
(`SearchEngine.swift`) uses `bm25()` weighting over the same FTS table plus tiers: sources →
saved items → local items.

### 2.3 Editorial selection / personalization

Two independent order owners exist:

```text
CuratedPreferenceEngine         EditorialSequencer
(onboarding + ranking weights)  (final anti-clustering pass)
   source multipliers ─────────▶ FeedStore fetch pipeline
                                     candidates ─▶ sequence() ─▶ publish
```

- `CuratedPreferenceEngine` (`CuratedPreferenceEngine.swift`): pure on-device preference
  elicitation. `makeCandidates` (`:620`) gates items, detects language via `NaturalLanguage`,
  then round-robins across `language|style|scope|mediaKind|topic` buckets for a diverse
  onboarding pool. `nextPair` (`:760`) builds comparison pairs by information gain;
  `applying` (`:850`) updates a `[featureKey: weight]` profile; `sourceMultiplier` (`:960`)
  converts the profile to a per-source scoring multiplier.
- `editorialAssessment` (`:200`) scores a source as reference / specialist / distinctive
  from hardcoded publisher/institution/specialist signal lists and an `evidenceFloor` on
  technical quality.
- `EditorialSequencer.sequence` (`EditorialSequencer.swift:60`) is a stable least-used
  round-robin that guarantees "no provider twice in a row while another has candidates".
- `PresetScorer.buildMultipliers` and `FeedRecipeResolver.effectiveProfile` combine presets,
  recipes and learned evidence into the final profile/multiplier dictionaries.

### 2.4 Taxonomy and filtering

`TaxonomyStore` (`TaxonomyStore.swift:31`) builds a single-home tree from OPML structure,
with a reverse index `nodeToFeedURLs` and a disk cache (`taxonomy_cache.json`, schema v3).
Filtering is subtree union over normalized source URLs.

### 2.5 Shipping/update

`CatalogUpdateService` (`CatalogUpdateService.swift`): release 1.0 is bundled-only
(`CatalogReleasePolicy`, `:48`, remote off in release). The remote channel verifies an
Ed25519-signed manifest, downloads changed OPML by SHA-256 + size, recompiles, verifies
source count, then atomically swaps `current/` with a `backup/` rollback.

## 3. Code review findings

### CE-1 — Catalog `sourceID` is a 32-bit truncated hash — collision risk at corpus scale. HIGH
- `CatalogIdentity.sourceID` → `stableUInt32Digest` takes **only the first 4 bytes** of SHA-256
  (`CatalogIdentity.swift:62`), yielding a 32-bit space.
- README reports 77,443 published sources (and up to ~90k runtime identities). By the birthday
  bound, ~77k identities in a 2^32 space gives a collision probability on the order of ~50%.
- Effect: `register` throws `identityCollision` (`SQLiteCatalogStore.swift:191`) during compile,
  aborting the whole catalog build for an otherwise valid corpus; the probability grows with the
  corpus. The Python identity uses full SHA-256 (README §Identity), so Swift narrows a 256-bit
  identity to 32 bits only for the DB primary key. Mechanism verified; collision not reproduced here.

### CE-2 — FTS `MATCH` ordering/ranking inconsistency between the two search paths. MEDIUM
- `SQLiteCatalogRepository.searchSQL` orders by a synthetic `sort_key` (default_enabled,
  100−quality, title) with no relevance term (`SQLiteCatalogStore.swift:534`), while
  `SearchEngine.searchSources` orders by `bm25(... 9,2.5,6,1,1,1,3)` then enabled/quality
  (`SearchEngine.swift:300`). Two code paths over the same FTS table return different source
  orderings for the same query.
- Effect: two "source search" surfaces disagree; the repository path never ranks by match
  quality. Duplicated search logic (INV-15 smell for v2).

### CE-3 — Post-FTS Swift re-filtering with substring `contains`, no bound. MEDIUM
- Both search paths run `expression.matches(...)` in Swift after SQLite FTS
  (`SearchEngine.swift:260`, `:330`), re-checking diacritic-folded `contains`. FTS token matching
  and substring matching differ (prefix/CJK/compound), so results can be silently dropped after
  the DB already matched them. `localItems` capped at 180 rows fetched then filtered.
- Effect: inconsistent recall; "found by DB, hidden by Swift". Also double work.

### CE-4 — Hardcoded editorial authority lists bias ranking by name/host. MEDIUM
- `recognizedPublisherSignals` / `institutionalSignals` / `specialistSignals`
  (`CuratedPreferenceEngine.swift:95`–`:160`) are static English/Latin-script substrings.
  `editorialAssessment` boosts `editorialAuthority` to 1.0 for a title/host containing e.g.
  "reuters" (`:245`), and `isEligible`/`evidenceFloor` (`:270`) gate the onboarding showcase on
  these. `onboardingShowcaseDomains` (`:430`) is a hand-maintained allowlist for en/pt/es only.
- Effect: non-listed, non-English, and smaller-language sources are structurally down-weighted and
  largely excluded from first-run; the list is unversioned and unauditable. Editorial policy baked
  into code, not data.

### CE-5 — Two independent "order owners" with a documented regression history. MEDIUM
- `EditorialSequencer` exists specifically because the Reservoir/`CardPreparationPipeline` order is
  overwritten by filters/reloads/appends — its own doc cites the "Gato Galáctico" five-in-a-row case
  (`EditorialSequencer.swift:3`–`:20`). Diversity is thus a *repair pass* bolted after ranking, not a
  property of selection. `isDiversityRespected` is asserted at the pipeline boundary.
- Effect: diversity depends on a separate corrective stage that can be bypassed by any later mutation
  of `visibleItems`. INV-12 (one owner per responsibility) is violated for ordering.

### CE-6 — Catalog browse `source_count`/`child_count` are compile-time snapshots. LOW
- Counts are computed during compile and stored on `catalog_node` (`SQLiteCatalogStore.swift:154`),
  then read verbatim into summaries. They reflect the catalog, not the user's enabled set or local
  supply, so a node can show "20 sources" while filtering yields 0 locally (consistent with the
  taxonomy audit's "category with no items" case).

### CE-7 — Taxonomy warm-start silently disables filtering (confirmed in v1's own audit). HIGH (in v1)
- `audit-taxonomy-filtering-2026-07-16.md` §4.1: `loadFromCache` restores `flatIndex`/`feedToNodeID`
  but **not** `nodeToFeedURLs`, so `feedURLs(inSubtreesOf:)` returns `[]` on warm start — taxonomy
  filtering silently off. Marked CRITICAL and *not yet fixed* in that audit. I did not read past
  `TaxonomyStore.swift:180`, so I cite the audit as the evidence, not the current line.

### CE-8 — Language is detected per-item at render-time cost and used as a hard gate. MEDIUM
- `makeCandidates` runs `NLLanguageRecognizer` per surviving item (`:700`, min length 24, confidence
  0.80/0.65) and *hard-drops* items whose detected language is not in the selected set. Declared
  language is only a fallback. This is correctness-positive (mislabeled sources) but expensive and
  can discard short-headline items in valid languages. No caching of the detection result.

### CE-9 — `duplicate_occurrence_count` only counts OPML placement duplication, not story dedup. LOW
- The compiler records `placements − canonical sources` as `duplicate_occurrence_count`
  (`SQLiteCatalogStore.swift:174`). This is *source placement* duplication. There is no
  cross-source article/story deduplication anywhere in the catalog or selection path I read; the
  "same story from many outlets" problem is unaddressed at the catalog layer.

### CE-10 — Remote update verification is correct but gated behind an empty public key. LOW
- `CatalogUpdateManifest.verifySignature` returns early (accepts unsigned) when `publicKeyHex == ""`
  (`CatalogUpdateService.swift`, `verifySignature`), and `publicKeyHex` is `""`. In release the
  remote channel is disabled, so this is latent, but if the channel is ever enabled before a key is
  set, manifests are accepted unsigned.

## 4. What worked (keep the idea)

- **Catalog as a shipped, immutable, versioned SQLite artifact.** Compile is atomic (temp file +
  `replaceItemAt`, `SQLiteCatalogStore.swift:71`), read is a read-only actor, and a
  `logicalDigest` (`:300`) gives a reproducible content hash. Offline-first by construction —
  aligns with INV-07/INV-11.
- **Separation of identity (declaredURL) from request URL.** `CatalogSourceOccurrence` keeps
  `declaredURL` vs `requestURL` (`CatalogInput.swift`), and README §Identity stores request URL
  separately so redirect evidence never changes identity. This is exactly the v2
  `ExternalIdentity`(object) vs locator split.
- **One shared normalization contract** across Python (`catalog_identity.py`) and Swift
  (`OPMLParser.normalizeURL`), documented and enforced. Prevents identity drift.
- **Single editorial home + virtual facets** (`source-experience.md`): tags/media/language/activity
  are facets, not copies; personal collections reference identity, never duplicate placement. Maps
  cleanly to v2 `SourceMembership` (one origin, many sources) without OPML copying.
- **Deterministic, explicit diversity round-robin** (`CuratedPreferenceEngine.makeCandidates`,
  `showcaseSources`): bucket by editorial dimensions, least-used first, stable tie-breaks. Same
  input → same pool. This is the diversity idea v2 SELECTION_DESIGN defers but will need.
- **`EditorialSequencer`'s honesty rule**: "no repetition while there are alternatives", never
  "manufacture diversity the candidate set cannot supply" (`EditorialSequencer.swift:12`). This is a
  good invariant to port even if the mechanism changes.
- **Signed, checksummed, atomically-swapped catalog updates with rollback**
  (`CatalogUpdateService.activate`, backup/restore). The *shape* is right for a future supply channel.

## 5. What failed and why

- **Diversity was retrofitted, not designed in.** `EditorialSequencer`'s own header documents two
  earlier rules that failed and the "Gato Galáctico" five-in-a-row regression that forced a third
  (`EditorialSequencer.swift:3`–`:40`). Root cause: ranking (CuratedPreferenceEngine/Reservoir) and
  ordering (Sequencer) are separate owners, and any mutation between them (filter change, reload,
  append) can reintroduce clustering. The `code-review-filtros-shake-source.md` verdict shows the
  same class of problem: partial local subsets published as READY (single-card feed on filter
  change), empty-state shown before preparation finished — all because presentation state and
  composition state were conflated.
- **Taxonomy correctness was fragile.** The 2026-07-16 audit lists a stale parse-cache fingerprint
  that put sources under the wrong node, a warm-start path that disabled filtering (CE-7), and
  URL-variant mismatches (`www.`/`http`) in the SQL IN-clause — a cascade of identity/normalization
  edge cases around a mutable cache. Root cause: taxonomy identity derived from file paths + a
  separately-cached reverse index that could desync from `flatIndex`.
- **Editorial authority encoded as code constants** (CE-4). The signal lists and showcase domains
  (`CuratedPreferenceEngine.swift:95`, `:430`) are English-centric and unversioned, so quality
  policy could not be reviewed, A/B'd, or shipped independently of the binary.
- **Identity width mismatch** (CE-1): the catalog narrowed a 256-bit canonical identity to 32 bits
  for a DB key, re-introducing collision risk the Python reconciliation had carefully eliminated.
- **No cross-outlet story dedup** (CE-9): the "same story, many outlets" problem was never solved;
  the only dedup was placement-level and title-level inside onboarding (`seenTitles`,
  `CuratedPreferenceEngine.swift:660`).

## 6. Applying to v2

### Lesson A — Catalog / SourceBinding materialization (sources have a separate lifecycle)
- v2 file: `Sources/FeedMineDomain/Source.swift`, `SourceBinding`; `CANONICAL_SUPPLY_DESIGN.md:233`.
- Current state: runtime.sqlite has **no** `sources`/`source_bindings` table yet; "catalog has its
  separate lifecycle and user-created Source durability requires its own consumer slice"
  (`CANONICAL_SUPPLY_DESIGN.md:233`). SourceID is opaque, never derived from URL/hash (`:133`).
- Recommendation:
  1. Keep the v1 win: ship the catalog as an immutable, versioned, signed artifact; keep
     identity (object `ExternalIdentity`) separate from locator. But **do not** truncate identity —
     use the full canonical ID; v2 already mandates opaque full-width SourceID (fixes CE-1).
  2. Materialize the catalog as a *display/binding directory* consumed to create `Source` +
     `SourceBinding(externalPrincipal:aliases:)` rows. Model v1 redirect aliases as binding
     `aliases` (same connector kind, already validated in `SourceBinding.init?`).
  3. Keep facets (tags/language/media/activity/quality) as catalog metadata feeding selection
     policy, not as duplicated placements — mirror `source-experience.md` single-home + virtual
     facets with v2 `SourceMembership` (one origin → many sources).
  4. Treat the catalog generation as `catalogGeneration` provenance only; SELECTION_DESIGN §5
     already excludes it from the executable-policy guard — keep it out of the guard.
- Review IDs: CE-1, CE-6, CE-9. Priority: High (unblocks a real source directory; prevents the
  32-bit collision regression).

### Lesson B — Selection diversity beyond `recencyDescending`
- v2 file: `Sources/FeedMineEditorial/SelectionEngine.swift`, `EditorialPolicy.swift`;
  `SELECTION_DESIGN.md` §6, §13.
- Current state: baseline sequencing is `recencyDescending` only; scoring `.equal`; provider
  diversity, scoring and clustering explicitly deferred (`SELECTION_DESIGN.md:§13`). `Candidate`
  already carries `providerID` and `language` (`Candidate.swift`), so the inputs for diversity exist
  without schema change.
- Recommendation — add an explicit, versioned `sequencing` case (e.g. `.diverseRecency`) that:
  1. Keeps determinism and the existing total order as the tie-break/stable base (no RNG; v1's
     deterministic round-robin proves this is feasible — `CuratedPreferenceEngine.makeCandidates`).
  2. Applies a **stable least-used round-robin over `providerID`** as the first key, degrading to
     pure recency when only one provider has candidates — exactly `EditorialSequencer`'s honesty rule
     ("no repetition while alternatives exist"), but *inside* SelectionEngine so there is one order
     owner (fixes CE-5 / INV-12). Keep it a pure function over the one finite window — do **not**
     reintroduce refill/relax loops (SELECTION_DESIGN §13 prohibits them).
  3. Carry the diversity decision in `ResolvedSelectionPolicy` nominal identity so it is auditable
     and guarded, not implied by a version number.
  - Do **not** port `CuratedPreferenceEngine`'s learned weights into this gate; personalization is a
    later, explicit policy with its own phase. Diversity here is structural (provider/language),
    not preference-based.
- Review IDs: CE-5, CE-4. Priority: High (it is the first case where v1 shipped visible breakage).

### Lesson C — One search path, ranked in the store, no Swift re-filter
- v2 file: Editorial `CandidateProvider` (search context currently throws,
  `CandidateProvider.swift`; CODE_REVIEW M18); future canonical FTS.
- Current state: `.search` is unavailable pending canonical FTS (SELECTION_DESIGN §1).
- Recommendation: when FTS lands, define a single ranked query (bm25 or equivalent) in Persistence
  and have Editorial consume ordered candidates — never re-filter with Swift `contains` (fixes CE-2,
  CE-3). Keep ranking in one owner; Selection applies its own total order on top only if policy says
  so.
- Review IDs: CE-2, CE-3. Priority: Medium (search is deferred).

### Lesson D — Editorial authority / quality as data, not code
- v2 file: `EditorialPolicy.swift` (`ResolvedSelectionPolicy`); catalog metadata.
- Current state: policy is a value with nominal identity; scoring `.equal` (SELECTION_DESIGN §6).
- Recommendation: when scoring arrives, source quality/authority must be a **catalog-shipped,
  versioned facet** feeding a `scoring` policy case, not hardcoded name lists. This fixes CE-4's
  English bias and makes quality reviewable/updatable via the catalog channel. Language preference
  likewise must be an explicit policy input (SELECTION_DESIGN defers language policy — honor that).
- Review IDs: CE-4, CE-8. Priority: Medium.

### Lesson E — Cross-outlet story dedup via ContentEntity/ContentCluster (and H3)
- v2 file: `Sources/FeedMineDomain/Content.swift` (`ContentEntity`, `ContentCluster`);
  `SelectionEngine.swift:66` (H3); `CANONICAL_SUPPLY_DESIGN.md:233` (clusters deferred).
- Current state: `ContentEntity` (hard equivalence) and `ContentCluster` (soft, confidence+method+
  version) exist as domain values but are **not** consumed in the selection hot path (`:233`).
  Review H3: exposure exclusion compares `originRevisionID`, so an edited unversioned RSS revision
  is republished as a new card; M8 flags source-scoped candidate windows.
- Recommendation:
  1. v1 never solved "same story, many outlets" (CE-9). v2 already has the right primitive
     (`ContentCluster`). When a dedup/diversity policy is introduced, collapse a cluster to one
     representative *inside* a future policy that receives cluster membership as an explicit input —
     not a Union-Find walk in Selection (SELECTION_DESIGN §13 rejects clustering in Selection).
  2. For H3: exclude by `originRecordID` within an Edition unless "edited revision = new occurrence"
     is a product decision; the exposure path already compares revision IDs
     (`SelectionEngine.swift:66`) and `SelectionExposure` is wired — the probe needs origin-record
     granularity. This is the v2 equivalent of v1's `seenTitles` guard, but done on durable identity.
- Review IDs: CE-9, H3, M8. Priority: Medium (needs the cluster-producing phase first).

### Lesson F — One composition/presentation state machine (never publish partial as ready)
- v2 file: `PRODUCT_INVARIANTS.md` (INV-08/09/10), Runtime (out of this area's scope).
- Current state: INV-08 immutable published history and INV-10 reprioritize-not-destroy already
  encode the fix v1 lacked.
- Recommendation: honor `code-review-filtros-shake-source.md`'s rule — a new composition starts
  PREPARING, no partial subset is published READY, EMPTY only after the operation confirms no
  content. v2 invariants already say this; the lesson is to **never** add a v1-style
  `immediatelyCullVisibleItemsForActiveFilter` shortcut.
- Review IDs: CE-5. Priority: High as a guardrail (prevents reintroducing v1's worst UX bug).

## 7. Open questions for the product owner

1. **Edited revisions (H3):** is an edited RSS item a *new card* or the *same story updated*?
   This decides whether exposure excludes by `originRecordID` or `originRevisionID`.
2. **Cross-outlet dedup:** should the same story from many outlets collapse to one card
   (ContentEntity/Cluster) or appear once per outlet with a "also covered by" affordance?
3. **Editorial authority:** is a curated quality/authority score part of the product, and if so may
   it be shipped as catalog data (reviewable) rather than code? What replaces v1's English-centric
   recognized-publisher list for non-Latin languages?
4. **First-run diversity target:** v1 forced topic/style/language/media breadth on the first page.
   Does v2 want structural provider/language diversity as a *default* sequencing policy, or only on
   an explicit "mix" plan?
5. **Language filtering:** hard gate (v1 dropped off-language items) or soft down-weight? SELECTION
   defers language policy; the product needs to state intent before scoring is designed.
6. **Catalog channel:** will v2 ship a signed remote catalog/supply update (v1 built but disabled it
   with an empty key, CE-10)? If yes, a real signing key and key-rotation policy are prerequisites.
7. **User-created sources:** v1 personal collections referenced identity without touching the
   catalog. Confirm v2 keeps user sources in a separate durable slice (`CANONICAL_SUPPLY_DESIGN.md`
   notes it "requires its own consumer slice") rather than in the shipped catalog.

---

### Summary (10 lines)
1. v1 ships the catalog as an immutable, versioned, signed SQLite artifact compiled offline from OPML — a genuine offline-first win to keep.
2. Source identity is split declaredURL vs requestURL and shares one Python/Swift normalization — maps directly onto v2 ExternalIdentity + locator.
3. CE-1 (HIGH): catalog `sourceID` truncates SHA-256 to 32 bits, risking ~50% collision at the 77k-source corpus; v2's full-width opaque SourceID fixes it.
4. CE-5/Lesson B (HIGH): diversity in v1 is a retrofitted repair pass (`EditorialSequencer`) with a documented five-in-a-row regression; v2 should fold a deterministic provider round-robin into SelectionEngine as one order owner.
5. v2 baseline sequencing is `recencyDescending` only; `Candidate` already carries providerID/language, so diversity needs no schema change — add a versioned `.diverseRecency` policy case.
6. CE-4/CE-8: editorial authority and language are English-centric code constants in v1; v2 should ship quality/language as catalog data feeding explicit policy, not hardcode them.
7. CE-9 + H3: v1 never deduped "same story, many outlets"; v2 has ContentEntity/ContentCluster primitives and should exclude exposure by originRecordID (pending the product's edited-revision decision).
8. CE-2/CE-3: two divergent FTS search paths plus Swift `contains` re-filtering drop DB-matched results; v2 should have one ranked store query and no post-filter.
9. CE-7 (v1 audit): a cached reverse index that desynced silently disabled taxonomy filtering — v2 should keep filter membership derivable, not a separately-cached mutable index.
10. Lesson F: never publish a partial local subset as READY (v1's single-card-on-filter-change bug); v2 INV-08/10 already encode the fix and must not be shortcut.
