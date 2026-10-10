# R1 — Editorial diagnosis and V1→V2 parity map

Deliverable of REVIEW R1, requested by the architect on 2026-10-10. Every number below was
produced by a command run on this machine on 2026-10-10, against the checkout named in §A and
against a real simulator run. Nothing here is inferred from reading code alone.

| | |
|---|---|
| V2 base | `/Users/wagnermontes/Documents/GitHub/feedmine_v2` |
| V2 branch | `main` |
| V2 HEAD | `c2474c2caf54efb13583137d4467651ca79faefc` |
| `origin/main` | `372f4c5cb6df5110e25f49b74f65a34ea507d5a6` |
| V1 base | `/Users/wagnermontes/Documents/GitHub/feedmine`, branch `fix/release-1.0-final-hardening`, HEAD `712a6ba9` |
| TestFlight build visible to testers | **26** (`ios/1.0-build.26-372f4c5`, = `origin/main`) |
| Executed evidence | `swift test --filter FeedMineEditorialTests` → 43 tests, 0 failures; `swift test --filter SourceDiversityContractTests` → 2 tests, 6 failures (RED, §H) |

---

## A. Repository, branch, TestFlight and plan state

```
$ git status --short
 M FeedMineApp/FeedMineAppTests/FeedMineUITests.swift
 M docs/reviews/V1_V2_FRONTEND_TRANSFER_EVIDENCE.md
 M docs/v1-study/PORT_LOG.md
?? scripts/__pycache__/      ?? scripts/soak.py
$ git rev-parse HEAD          → c2474c2caf54efb13583137d4467651ca79faefc
$ git rev-parse origin/main   → 372f4c5cb6df5110e25f49b74f65a34ea507d5a6
$ git branch --show-current   → main
$ git log --oneline origin/main..HEAD | wc -l → 12
```

- **HEAD is 12 commits ahead of `origin/main` and none of them are pushed.** They are the T12
  close-out: the a11y pass on the source surfaces (`37498c0`), three comparison/soak documents, and
  the architect's T12 acceptance (`c2474c2`). No behavioural change to the pipeline sits in them.
- **The worktree is not clean**: the three modified files are the soak evidence and the UI-test
  scenario added for it; `scripts/soak.py` is new and untracked. Nothing conflicted with this review.
- **TestFlight**: `FeedMineApp/FeedMineApp/Info.plist` declares `CFBundleShortVersionString 1.0` and
  `CFBundleVersion 26`; tags run to `ios/1.0-build.26-372f4c5`, which is `origin/main`. Build 26 is
  therefore the build the owner sees — it does **not** contain the 12 local commits, but those are
  documentation, an accessibility improvement and a measurement script.
- **Transfer plan state** (`docs/v1-study/UI_TRANSFER_MATRIX.md` header): 49 rows `validado`,
  43 `em transferência`, 8 `inventariado`, and the file states plainly that no row claims visual
  parity because the screenshot comparison was never executed. `T12` is accepted *with documented
  exceptions* (no pixel diff, no physical iPhone, no heterogeneous network).

**Reconciliation of the two SHAs the architect named:** the architect verified `origin/main` at
`372f4c5`; the local `dd63c1a` it saw in the T12 report is 6 commits *below* HEAD and already
contained in it. Both are in the history of `c2474c2`; nothing was lost.

---

## B. The A–B–A symptom: reproduced, classified, and located

### B1. Reproduced in the simulator's own database

The booted simulator (`8871DCF5-0C06-4C7C-88D2-7B3DC36E8284`, iPhone 17 Pro Max, iOS 26.5) holds
the namespace the 30-minute soak left behind. Read-only queries (never a write) on
`…/Library/Application Support/FeedMine/B50A0000-0000-4000-8000-000000000030/runtime.sqlite`.

**An Edition is not one instant.** It is created once and then accumulates segments as the reader
moves; the 89-card main-context Edition was created at 08:49:59 and its last segment was appended at
09:58:00. Each segment must therefore be judged against the supply that existed when *it* was
appended, not against the supply of the whole run:

| edition | segment | appended | cards | distinct display names | source ids | eligible supply then | names inside the examined window |
|---|---|---|---|---|---|---|---|
| `500f3bf7` | 0 | 08:49:41 | 23 | **1** — `BBC News` 23 | 2 | 60 cand. / **2** sources | 1 |
| `d85447c1` | 0 | 08:49:59 | 31 | **3** — BBC 19, Guardian 6, NPR 6 | 4 | 102 cand. / **4** sources | 3 |
| `d85447c1` | 1 | 09:05:40 | 27 | 12 | 12 | 2,054 cand. / **107** sources | **12** |
| `d85447c1` | 2 | 09:58:00 | 31 | 19 | 20 | 11,479 cand. / **627** sources | **18** |

The last column is the number the segment could possibly show: **production examines a window of 32
candidates** (`localExaminedCapacity: 32`, `AppComposition.swift:1182`), and every published origin of
each segment sits at rank 0–31 of the recency order — one window per segment. Segments 1 and 2
published **every source their window contained** (12 of 12, and 18–19 of 18).

The very first screen of the run — 23 cards — was **100 % "BBC News"**: two distinct BBC feed
`SourceID`s alternating, so PD-4 was satisfied while the reader saw one name only.

The published sequence of the second segment, by display name:

```
BBC News, The Guardian, BBC News, BBC News, BBC News, The Guardian, BBC News, NPR,
BBC News, BBC News, BBC News, The Guardian, BBC News, The Guardian, BBC News, NPR, …
```

That is the owner's A–B–A, reproduced. It is **not** the algorithm violating its rule: `same
SourceID adjacent = 0` across all 89 cards — PD-4 holds exactly as specified.

### B2. Three independent mechanisms produce the visible symptom

| # | Mechanism | Evidence |
|---|---|---|
| 1 | **The first screens held only the sources that had supply.** The very first publication (23 cards) had `2` sources admitted; the next one (31 cards), `4`. No sequencing rule can show a source that does not exist yet. | per-segment table in §B1 |
| 2 | **Two distinct `SourceID`s share the display name "BBC News"** — 28 and 32 candidates respectively in that same window. PD-4 compares `SourceID` ("Provider is not a PD-4 criterion", `PRODUCT_DECISIONS_2026-10-09.md:82`), so cards from the two BBC feeds may stand adjacent and the reader sees `BBC News, BBC News`. This is precisely the "separate presentation question" already recorded in `FEEDMINE_V2_RELEASE_EVIDENCE.md` §5. The catalog explains it: **12** distinct `catalog_source` rows are titled `BBC News` (11 BBC feeds — news, uk, business, health, politics, scotland, wales, northern ireland, technology, science, india — plus one YouTube channel); `857` titles across the 77,443-source catalog are duplicated. | `select count(distinct source_id) … group by source_display_name`; `catalog.sqlite` |
| 3 | **The sequencing policy is greedy and has no fairness term.** `SourceAlternation.apply` takes, at each step, the *earliest* remaining candidate compatible with the previous one. It never asks how many cards each source has already taken, so the head of the recency order returns to the screen as soon as it is compatible again. | `Sources/FeedMineEditorial/SourceAlternation.swift:32-40`; §C |

### B3. What actually limits diversity: two independent ceilings

Replaying each segment through the algorithm as written, against the supply that existed when it was
appended, at the production window size (`examinedCapacity = 32`) and at larger ones:

| segment | names available in a 32 / 64 / 128 / 256-candidate window | names `SourceAlternation` shows in the published prefix | names least-used RR would show |
|---|---|---|---|
| 0 (31 cards) | 3 / 3 / 3 / 3 | 3 | 3 |
| 1 (27 cards) | **12** / 12 / 17 / 32 | **11** | 12 / 12 / 17 / 27 |
| 2 (31 cards) | **18** / 25 / 41 / 58 | **18** | 18 / 25 / 31 / 31 |

Two ceilings, and they are independent:

1. **The window caps what is available at all.** With 32 examined candidates a segment can only ever
   show the sources that happen to sit in the newest 32 items: 12 names for segment 1, 18 for
   segment 2 — even though 107 and 627 sources were eligible in the wider supply. Raising the window
   to 128 candidates would make 17 and 41 names available; to 256, 32 and 58.
2. **The greedy rule caps what is shown, independently of the window.** With a 256-candidate window
   the algorithm still shows only **11** names in 27 cards (segment 1) and **18** in 31 (segment 2),
   because it returns to the head source as soon as it is compatible again. Least-used round-robin on
   the very same 256-candidate window shows **27 names in 27 cards** and **31 in 31**.

Measured against what was published: the alternation already delivers every name its window holds
(12 of 12, 18 of 18), but concentrates the share — segment 1 published Río Negro 9 of 27 cards while
least-used would place 6. So the reader's perception, "the same few sources over and over", is
produced by the two ceilings compounding: a narrow window feeds a rule that spends every second slot
on the same feed.

**Conclusion.** Neither cause alone explains the symptom, and neither fix alone removes it:
enlarging the window without a fairness term keeps `11`/`18` names; adding fairness without enlarging
the window tops out at 12/18. The first screen additionally suffers a coverage failure (2 sources at
23 cards) that no sequencer can repair.

---

## C. V1 mechanism vs V2 mechanism

| | V1 | V2 |
|---|---|---|
| Files | `feedmine/Services/EditorialSequencer.swift` (enum, pure), `feedmine/Services/Reservoir.swift` (`@MainActor`), orchestrated by `FeedStore` | `Sources/FeedMineEditorial/SelectionEngine.swift`, `SourceAlternation.swift`, `EditorialPolicy.swift`, `CandidateProvider.swift` |
| Who owns order | **Two owners.** `Reservoir.interleaveImpl` builds the seed (per-source weights → slots → country spread → round-robin → freshness spread → `frontLoadUniqueProvidersImpl(100)`), then `EditorialSequencer.sequence` repairs it. `04-catalog-editorial.md` FP-11 records this as the cause of V1's ordering regressions. | **One owner.** `SelectionEngine` sorts and alternates; nothing downstream reorders (`PublicationStore` freezes `ordinal`, reads `ORDER BY ordinal`). Verified. |
| Grouping key | `Reservoir.providerKey` = the **feed URL** (`return sourceURL`, `Reservoir.swift:572`), with all `news.google.com` feeds collapsed into one `aggregator:` key | `SourceID` (a `Set<SourceID>` per candidate). `ProviderID` travels with the candidate and is explicitly *not* a PD-4 criterion |
| Fairness | **Least-used round-robin**: each step takes the provider with the fewest cards so far, tie-broken by earliest position in the input; `maxConsecutivePerProvider = 1`; a run is legal only when no other provider has a candidate left (`consecutiveRunIssues`, `EditorialSequencer.swift:101-116`) | **None.** Greedy earliest-compatible; the only rule is "do not repeat the previous card's source" (`SourceAlternation.swift:24-27`) |
| Freshness | `spreadForFreshnessImpl`: look-ahead of 96 live candidates, provider penalty strongest (100000/sourceMultiplier), then category, media, region | Total order by weight, then timestamp, then `OriginRecordID`, then `OriginRevisionID` — recency is preserved but never traded against fairness |
| Randomness | Yes: `Array.shuffled()` in `Reservoir` (`:332-334, :411-412, :416, :434, :437, :627`), not seeded, so not reproducible | None. Deterministic and reproducible |
| Diversity contract tested in V1 | `ContentDistributionTests`: `testFirst100VisibleFromDistinctSources`, `testNoConsecutiveSameSourceInFirst50`, `testSourceSpacingWithin3CardWindow`, `testCountrySpreadingAvoidsAdjacentSameCountry`, `testMediaTypesAreSpreadNotClustered`; `leadingProviderCount` = distinct providers on page 1 | `SelectionEngineTests`: adjacency only. `testPD4NoTwoAdjacentCardsShareASourceWhileAlternativesExist` **asserts `A1 B4 A2 C5 A3` as the expected result** — the A–B–A shape the owner reports is currently pinned as correct behaviour |
| Where diversity was deferred | — | `SELECTION_DESIGN.md` §13: *"Provider diversity: ProviderID attribution does not imply providerQuota, balancing or diversity behavior."* `PORT_LOG.md`: *"diversity beyond PD-4 are not started"*; `OMP_ROUND4_VERIFICATION_2026-10-09.md:191`: *"Decisão de produto pendente … diversidade além do PD-4"* |

The V2 gained one owner and lost the fairness term. That trade is documented nowhere as a product
decision — it is a side effect of collapsing two mechanisms into one.

---

## D. Repetition: four different phenomena in the same edition

Classification per the architect's DUP/DIV/NORMAL taxonomy, applied to the 89 published cards:

| Class | Observed | Evidence |
|---|---|---|
| **DUP-1** (same occurrence twice) | **0** | `published_cards` new per segment; `UNIQUE (segment_id, ordinal)`; no `PublicationCardID` repeats |
| **PD-1 re-occurrence** (same origin, materially edited) | **2** | origin `a667ea3a…` (BBC tiger story) at `0.2` and `1.5`; origin `da31364c…` (Christa Pike, BBC) at `0.6` and `2.6`. Different `origin_revision_id` each time (3 and 4 revisions recorded). The title changed between the two occurrences ⇒ *material* by PD-1 rule 1, so the mechanism is compliant |
| **DUP-3** (different origins, equivalent content) | **1 cluster, 3 sources** | The Christa Pike story published from BBC (`da31364c…`, `bbc.co.uk/news/articles/cmlyle97pqd7o#1`), Clarin (`e151a5bd…`, `clarin.com/…/christa-pike-la-mujer-que-sobrevivio-a-dos-inyecciones-letales…`) and Río Negro (`abded0ad…`, `rionegro.com.ar/?p=4754826`). All three cards carry `content_entity_id NULL` and `content_cluster_id NULL` |
| **Near-duplicate inside one source** | 1 pair | `Yuridia - Bajón Emocional (Letra)` (1.0) and `Yuridia - Bajón Emocional` (2.29), same source `imferse -`, different origins |
| **DIV-1** (variety insufficient with eligible supply) | **yes, measured** | §B3: `15/8/7` where `10/10/10` was available |
| **DIV-2** (different SourceIDs, one newsroom) | **yes** | 6 display-name adjacencies in the edition, all `BBC News`; two BBC `SourceID`s active |
| **SUP-1** (supply inadequate) | **yes, at the first screens only** | 2 sources at the first publication, 4 at the second; 106 and 625 sources at segments 1 and 2 |
| **PD-4 compliance** | holds everywhere | same-`SourceID` adjacency = 0 in all 89 cards; `maxrun = 1` per source id |

`contentEntityID`/`contentClusterID` confirmed `nil` at the only production call site:

```swift
// FeedMineApp/FeedMineApp/AppComposition.swift:1144
contentEntityID: nil, contentClusterID: nil,
```

so DUP-3 has no mechanism today. PD-1's material rule (normalized title/summary or primary media
changed) is enforced — `EditedArticleRecurrenceTests`, `OriginExposureIntegrationTests` — but it
cannot see the same story arriving through two different publishers.

---

## E. Available supply vs published diversity

The architect's question — *"when many sources are eligible but the newest items cluster in two of
them, can the system reach the others?"* — has a measured answer: **no, not with the window it is
given, and not with the rule it applies.**

| Window examined | Distinct sources **available** | Distinct sources **shown** | Largest share |
|---|---|---|---|
| 32 newest candidates, current supply | 23 | 23 | 7 of 32 |
| 64 newest candidates, current supply | 44 | 44 | 7 of 64 |
| 128 newest candidates, current supply | 62 | 62 | 11 of 128 |
| 256 newest candidates, current supply | 91 | 91 | 17 of 256 |
| segment 1, real run, **32** examined (production) | **12** of 107 eligible | 12 of 27 cards | 9 of 27 |
| segment 1, real run, **256** examined | **32** | still 11 (greedy) / 27 (fair) | 9 of 27 |
| segment 2, real run, **32** examined (production) | **18** of 627 eligible | 18 of 31 cards | 5 of 31 |
| segment 2, real run, **256** examined | **58** | still 18 (greedy) / 31 (fair) | 5 of 31 |

Two things this table settles:

- **Widening the window is not optional.** At `examinedCapacity = 32` the run's segments could never
  have shown more than 12 and 18 names, whatever the sequencer did. The 107 and 627 eligible sources
  were real, but they sit *below* rank 32 in a globally recency-ordered supply
  (`ORDER BY sort_date DESC, origin_record_id DESC LIMIT ?`, `ContentStore.swift:76-94`, cut before
  the per-source eligibility filter).
- **Widening it is not sufficient either.** Over a 256-candidate window the greedy rule still shows
  11 and 18 names where least-used shows 27 and 31. The two defects are multiplicative, not
  alternative.

Not a supply-capacity problem: 22,186 candidates across 1,347 sources were present, and the
per-source cap in `selection_supply` (145, 128×4, …, 64) left every source with far more than the
32 candidates the window examines. The constraint is entirely in how the window is chosen and in
what the sequencer does with it.

---

## F. V1→V2 parity map (first pass, with confidence)

Status: `BETTER` / `PARITY` / `GAP` / `REPLACED` / `RETIRED` / `UNVERIFIED`. Confidence: `high`
(executed test or measurement), `medium` (code + doc evidence), `low` (inventory only).

| Area | V1 capability | V2 today | Status | Conf. |
|---|---|---|---|---|
| Feed ordering | least-used round-robin + provider weights + country/type spread (`Reservoir`, `EditorialSequencer`) | recency order + PD-4 adjacency, single owner | **GAP** | high |
| Feed ordering owner | two owners (FP-11) | one owner, verified | **BETTER** | high |
| Feed determinism | `shuffled()`, unseeded | deterministic, reproducible | **BETTER** | high |
| Adjacent-source rule | repair pass, not an invariant of what is published | PD-4 hard rule, held card + rewind | **BETTER** | high |
| Publication history / identity | `FeedDisplayState.publishCards`, card id per item | immutable history, `PublicationCardID`, `UNIQUE` ordinals | **BETTER** | high |
| Recurrence of an edited article | RSS rewrite produced duplicates (IN-3) | PD-1 material rule, tested | **BETTER** | high |
| Same story via different publishers | not deduplicated | not deduplicated (`contentClusterID nil`) | **PARITY** (both absent) | high |
| Presentation identity of a source | provider = feed URL; V1 could also show two "BBC News" feeds | `SourceID` only; 12 catalog rows titled BBC News | **PARITY** (both weak) | high |
| Continuous feed / artificial end | scroll-triggered fetch, fixed watermarks | adaptive runway, demand-driven acquisition | **BETTER** | medium |
| Preparation barrier (T2/T3) | terminal card before publish; contiguous prefix | admission barrier, tested | **PARITY** | high |
| Reader (open/close/share) | WKWebView in-app + explicit Safari link | `SFSafariViewController` | **REPLACED** | high |
| Offline body of an article | absent | `localContentDetail` for published text | **BETTER** | medium |
| Saved / bookmark boxes | multiple boxes, default box, box-as-context | boxes, collections, presets | **PARITY** | medium |
| Sources (add/enable/search/import) | InputParser/URLResolver, region & country toggles, OPML in/out | catalog-backed source surface, OPML import/export | **PARITY** (OPML round-trip not executed end-to-end) | medium |
| Catalog (countries/taxonomy/counts/search) | embedded catalog + FTS5 + counts from the compile | `LegacyCatalogReader` + surfaces; catalog search not yet FTS | **GAP** | medium |
| Personalization (recipes/curated/presets) | recipes + curated onboarding + learned profile | recipes + curated coordinator, explicit weights | **PARITY / REPLACED** (learned engine not ported) | medium |
| Filters (media/language/taxonomy/country) | combined AND, persisted, 4h auto-expiry | reader filter, draft committed at one moment | **UNVERIFIED** | low |
| Search (sources / saved / local) | three tiers, committed terms, relevance | source + local substring filter; surface pending (U3) | **GAP** | medium |
| Playback (audio, mini/full player, continuity) | one global player, position restore, now-playing | mini-player bar + adapter, played from the card's own enclosure | **UNVERIFIED** (no full player) | low |
| Interface (branding/cards/sheets/a11y/DynamicType/iPad) | V1 visual language + accessibility audit suite | ported tokens, cards, sheets; a11y identifiers added; **no screenshot comparison executed** | **UNVERIFIED** | low |
| Settings (applied preferences, destructive actions) | typed keys, granular resets | typed settings, import/export | **PARITY** | medium |
| Data (export/import/backup/update over V1) | OPML/JSON/CSV export; one-time migrations | export + import preview; update-over-V1 leaves V1 untouched and unread | **GAP** (decision open, §8 of the release evidence) | high |
| Resilience (offline/slow/endpoint failure/disk/memory/relaunch) | per-source isolation, fast-lane session, recoverable demotion | backoff, bounded concurrency, warm restore | **PARITY** | medium |
| Feature completeness gate | — | no CI; the suite is run by hand | **GAP** | high |

---

## G. The five product GAPs that evidence supports, in priority order

1. **The examined window is 32 candidates of one global recency order (P0).** A segment can only
   show the sources that sit inside that slice: measured 12 of 107 and 18 of 627 eligible sources.
   The window is cut before the per-source eligibility filter, so a few prolific feeds fill it.
   — §B1, §B3, §E; `AppComposition.swift:1182`, `ContentStore.swift:76-94`.
2. **Fairness beyond PD-4 does not exist in V2 (P0).** Even given a wide window the greedy rule shows
   11 and 18 names where least-used round-robin shows 27 and 31 on the same candidates, and it takes
   a third of a segment from one source. V1 had the mechanism and the tests; V2 has neither, and the
   deferral is recorded as "not started, needs a product decision". — `SourceDiversityContractTests`
   (RED); §B3, §C; `PORT_LOG.md:116-128`.
3. **Coverage at first presentation (P0, different owner).** The first screen of a real main-context
   run was 23 cards of a single display name from 2 admitted sources; the next was 3 names from 4.
   No sequencer can repair this; it belongs to acquisition scheduling and to what the first
   presentation promises. — §B1; `origin_records` timeline.
4. **One newsroom shown as several sources (P1).** 12 catalog rows are titled `BBC News`; PD-4 is
   `SourceID`-only by explicit decision; the app never populates `providerID`
   (`published_cards.provider_id` is NULL for all 89 cards). The reader therefore sees
   `BBC News, BBC News` — 22 times in the first 23 cards, 6 times in the 89-card edition — while
   every test stays green. — §B2, §D, appendix.
5. **The same story from several feeds of one publisher (P1).** 166 strict cross-source duplicate
   pairs among 22,183 candidates, dominated by mirror feeds (iVoox + its blog, two Blogger feeds of
   one blog, two YouTube channel feeds of one video). PD-1 covers the same *origin* edited; nothing
   covers the same *story* arriving twice. — §D, appendix.
6. **Parity is asserted, not certified (P1/P2).** No screenshot comparison was ever executed, the
   catalog/search/filter/playback rows are `UNVERIFIED` above, U3 remains open (search surface,
   filters actually supported, pull-to-refresh with a safe Edition transition, honest offline
   indicators), and the suite is run by hand. "Looks finished because the tests pass" is the exact
   failure mode the architect named. — `UI_TRANSFER_MATRIX.md` §11; `IOS_RUN.md` U3; §F.

---

## H. First small correction, with the RED tests that demonstrate the defect

> **Superseded by Appendix A (R2, 2026-10-10).** The architect withdrew the equal-share criterion this
> section proposed for unequally supplied windows and approved proportional, scarcity-aware sequencing;
> the tests below were rewritten to that contract and the version split (v2 greedy, v3 proportional) is
> documented in Appendix A. The reproduction and the RED evidence in this section still stand.

**New file, uncommitted: `Tests/FeedMineEditorialTests/SourceDiversityContractTests.swift`.**

```
$ swift test --filter SourceDiversityContractTests
error: testNoSourceTakesMoreThanItsFairShareOfThePrefixWhileThreeSourcesHaveSupply
        ("15") is greater than ("11") - source 1 took 15 of the first 30 cards; counts=[1: 15, 2: 8, 3: 7]
        ("8") is less than ("9")   - source 2 took only 8 of the first 30 cards
        ("7") is less than ("9")   - source 3 took only 7 of the first 30 cards
error: testTheMostRecentSourceCannotStarveAnEquallySuppliedSource
        ("6") is greater than ("5") - source 1 took 6 of the first 12 cards; counts=[1: 6, 2: 6]
        ("6") is greater than ("5") - source 2 took 6 of the first 12 cards
        ("0") is less than ("3")   - source 3 took only 0 of the first 12 cards  ← starvation
 Executed 2 tests, with 6 failures (0 unexpected)
```

Test 1 uses the window exactly as the supply delivered it at 08:49:59 (A 60, B 32, C 10, order
verified against the database). Test 2 is the minimal reproduction: three sources with equal supply,
one of them the most recent.

**Proposed change — one function, one behaviour.** Replace greedy-earliest with
**least-used round-robin under PD-4 as a hard constraint**: at each step, among the remaining
candidates whose source set is disjoint from the previous card, take the one whose source has the
fewest cards placed so far; break ties by the earliest position in the priority order; if none is
compatible, stop and hold the rest exactly as today.

Verified offline on the real windows before proposing it — at the production window size **and** at a
wider one, because the two ceilings interact:

| window | today (greedy) | proposed (least-used ⊂ PD-4) |
|---|---|---|
| segment 0, 32 examined, 3 sources → 31 cards | BBC 13, G 6, NPR 6 | BBC 7, G 6, NPR 6 |
| segment 1, **32 examined** → 27 cards | 11 names, Río Negro 9 | **12 names, Río Negro 6** |
| segment 1, **256 examined** → 27 cards | 11 names, Río Negro 9 | **27 names, 1 each** |
| segment 2, **32 examined** → 31 cards | 18 names, Río Negro 5 | 18 names, Río Negro 5 |
| segment 2, **256 examined** → 31 cards | 18 names, Río Negro 5 | **31 names, 1 each** |
| minimal fixture (3 sources, 6 candidates each) → 12 cards | 1: 6, 2: 6, 3: **0** | 1: 4, 2: 4, 3: 4 |

PD-4 still holds in every window, the result stays deterministic, and the order stays a
permutation-plus-holds. **Two costs, measured, and both belong in the decision:**

- **Cards held** because no compatible candidate remains: segment 0 is a genuine three-source window
  (27 of 102 held against 17 today — PD-4 rule 2 already accepts a shorter runway over a repeated
  source); with the production 32-candidate window the difference is small, and over the wide windows
  it is 1.5 % (segment 1) and 0.15 % (segment 2).
- **The window still caps the outcome.** In the production window the fairness term moves 11 names to
  12 and rebalances the share; it cannot move 12 names to 27. If the product promise is "the reader
  should meet many sources", the window must be enlarged **as well**, and that is a candidate-supply
  design decision (`SELECTION_DESIGN.md`), not a sequencing one.

**Two consequences the architect must decide, not the OMP:**

1. **The criterion is a product rule.** "Three sources each holding at least a third of the first
   screen take a third each" is a proposal; PD-4 says nothing about shares, and
   `SELECTION_DESIGN.md` §13 defers exactly this. Without an approved criterion there is nothing for
   the OMP to implement against, and the two RED tests stay red on purpose.
2. **Fairness needs per-Edition state across segments.** `SourceAlternation.apply` is currently
   stateless per call and receives only the tail neighbour. Least-used accounting restarts at every
   segment unless the caller passes the counts already published in this Edition — a small signature
   change on `SelectionNeighbor` (or an added input on `select`), not a new mechanism. Because the
   code comment on `select` says *"a behavior change is a new EditorialRevision"*, the landing patch
   must also bump `sequencingPolicyVersion` and re-cut the Editorial revision.

**Preferred alternative, if the criterion above is rejected:** keep greedy and add a recency penalty
for a source already used within the last *k* cards (V1's `spreadForFreshnessImpl` idea). Smaller
conceptual change, but it needs a tuned constant and does not guarantee a share; it also weakens the
"no magic numbers" stance of PD-3.

---

## I. OMP recommendation

**Two separate pieces of work, only one of which is the OMP's to start.**

**(1) The examined window — architect's decision, not a patch.** The measurement puts the strongest
ceiling there: 32 candidates of a global recency order, cut before the source filter, is what allows
a segment to show 12 of 107 eligible sources. Raising the constant is cheap to try but wrong to
assume: it changes how much supply a drive consumes per segment and interacts with the runway
budget, and making the window source-aware (for example a per-source slice instead of a global
recency slice) is a change to the candidate-supply contract that `SELECTION_DESIGN.md` owns. This is
the first thing to decide; the OMP will not guess it.

**(2) The fairness term — small, in `FeedMineEditorial`, and ready once the criterion is approved.**
`SourceAlternation.apply` is 43 lines; the change is least-used selection inside its existing loop,
one input for cross-segment counts, one `sequencingPolicyVersion` bump. Codex's stated triggers are
absent: no failed OMP attempt, no delicate local transformation, no concurrency or lifecycle bug.
Not Codex.

**(3) The first-screen coverage failure is a third owner** (acquisition scheduling and the
first-presentation promise) and must not be folded into either patch.

**What blocks is a product decision, not capability** — which is why this report asks instead of
implementing.

**Open questions for the architect, in one block:**

1. **What is the window?** Keep the 32-candidate global recency slice, enlarge it, or make it
   source-aware? This single answer sets the diversity ceiling regardless of any sequencing change.
2. Approve, reject or reshape the fair-share criterion. If reshaped: what is the promised
   distribution, in terms a test can assert?
3. Is first-screen coverage a product promise to be measured at launch, or an accepted consequence of
   a cold start?
4. Should two `SourceID`s of one publisher (12 catalog rows titled `BBC News`) be one identity for
   PD-4 and for the reader? That is the "separate presentation question" the release evidence already
   recorded.
5. Is "same story from several feeds of one publisher" (166 strict pairs measured) in scope, and if
   so, is the route catalog identity or editorial clustering? `contentClusterID` is `nil` today, so
   nothing can implement either.
6. Should a re-occurrence of the same origin inside one Edition (PD-1, headline-only edit) stay
   allowed? Measured: 2 such pairs in 89 cards, both compliant with PD-1 today.

---

## Appendix A — R2: proportional sequencing, versioned

The architect's R2 decision (2026-10-10) approved **proportional, scarcity-aware selection** and revoked
the equal-share reading of the uneven fixture; it required sequencing v2 to keep its greedy behavior and
v3 to have its own revision identity; it put the first-publication question out of scope and authorized
the DUP-3 dataset only. What landed follows that decision exactly.

### A1. Two behaviors, two versions, one identity each

| sequencing version | behavior | case | who runs it |
|---|---|---|---|
| v1 (or absent) | recency, no alternation | `.recencyDescending` | pre-PD-4 revisions |
| **v2** | PD-4 alternation, earliest compatible candidate (the rule the run was published with) | `.recencyAlternatingSources` | **Editions already persisted** and restored from disk |
| **v3** | PD-4 alternation, the candidate whose sources consumed the smallest share of what the window offers them | `.recencyAlternatingSourcesBySupplyShare` | fresh revisions of this build |

`PublicationStore.insertEditionAndFirstSegment` rejects a second Edition whose `editorial_revision_id`
matches an existing row while the decoded revision differs (`editorialRevisionConflict`). The revision
identity in `AppComposition` therefore now carries every version that changes what an Edition was
published under — `contextKey | selectionVersion | scoring:<v> | sequencing:<v>` — so a v3 Edition gets a
distinct stable identity and an installation that already holds a v2 Edition can still publish. No
checkpoint is cleared, no published card is rewritten, and nothing in Persistence changed.

### A2. Measurements on the run's own windows

| window (verbatim from the run) | greedy (v2) | equal share (rejected) | **proportional (v3, landed)** |
|---|---|---|---|
| 102 candidates A 60 / B 32 / C 10 — first 30 | 15/8/7 | 10/10/10 | **15/11/4** |
| … same window, cards placed of 102 | 85 | 75 | **84** |
| production 32, 12 sources, largest 10 | 31 placed, 5 of 12 met before a repeat | 30, 12/12 | **32 placed, 12/12** |
| production 32, 18 sources, largest 7 | 30 placed, 6 of 18 | 30, 18/18 | **32 placed, 18/18** |
| tail 256, 32 sources, largest 64 | 256 placed, 5 of 32 | 223, 32/32 | **255 placed, 32/32** |
| A=B=C=6 — first 12 | 6/6/0 | 4/4/4 | **4/4/4** |

Equal share was withdrawn by the architect: with 60 A candidates and 42 others, spending B and C early to
reach 10/10/10 leaves the A surplus without the separators PD-4 needs (measured: 75 placed against 84).
The proportional rule keeps the reserve, meets every source before repeating one on all three real
windows, and places as many cards as the greedy rule did (32 vs 31, 32 vs 30, 255 vs 256, 84 vs 85).

### A3. Evidence executed

```
$ swift build                                                    → Build complete
$ swift test                                                     → 1029 tests, 0 failures
$ swift test --filter SourceDiversityContractTests|SelectionEngineTests → 32 tests, 0 failures
$ swift test --filter SourceDiversityContractTests (v2 rule)     → RED: 3 of 10 expectations fail
$ xcodebuild test -scheme FeedMine -only-testing:FeedMineAppTests → 27 tests, 0 failures, ** TEST SUCCEEDED **
$ xcodebuild test -scheme FeedMine -only-testing:FeedMineUITests → 21 passed, 1 failed, 1 skipped
$ git diff --check                                               → clean
```

The one XCUI failure is `testOnboardingWelcomeComposerAndSave`: re-run against the **baseline** (the R2
changes stashed and the new test file removed) it fails with the same three assertions, so it is
pre-existing and not attributable to this patch. The skip is
`testPreparePersistentScaleSoakThroughCountryCascade`, which requires the soak's opt-in environment by
design.

**Production path (simulator, Debug build, real RSS, fresh namespace):** launched
`com.feedmine.development` with `FEEDMINE_RUNTIME_NAMESPACE` set and the development/network flags
off; the store it created declares **`sequencing_policy_version = 3`** — the new behavior is what the
application actually runs. Its first segment is 21 cards from the two BBC feeds (4 targets enabled at
that moment, 103 supply candidates), with **zero adjacent cards sharing a `SourceID`**. The single
display name in that prefix is the coverage fact R2-D3 put out of scope: the same shape the v2 build
produced (23 cards, one name), which is why the first-publication question is a separate cycle.

**Existing installation (the previously installed v2 build, its own default namespace):** it restored
its persisted v2 Edition with its checkpoint and kept running under v2 — the behavior its revision
names — with no `editorialRevisionConflict`, which is what R2-D2 asked to be preserved. That same store
is the evidence that a v2 Edition and a v3 Edition can coexist for one context under the new identity
derivation.

### A4. The real end-to-end proof (R2-P10, final gate)

Run on the simulator with the Debug build, real RSS, the project's own persistent namespace (the
soak store: 1,415 enabled targets and 22k candidates of supply), driving the reader through the
product's own flow:

| step | observation |
|---|---|
| launch | the existing installation restored its **v2** Edition and its checkpoint — no conflict, no reset |
| selection change (Fontes → seção *Entertainment*, 1,342 feeds → Concluir) | `reader_preferences.selection_version` 3 → 4, targets 1,415 → 2,757 — a legitimate product flow, not a script |
| publication | a **new Edition under `sequencing_policy_version = 3`**, created 11:11:36, with **three segments appended under v3** (11:11:36, 11:12:12, 11:12:13) |
| scroll | two forward gestures advanced the reader and drove the appends |
| checkpoint | moved to the new v3 Edition (`fb19e69b`); the two v2 Editions and their cards remain in the store |

Measured on those v3 segments, against the effective window each was given (the first 32 eligible
candidates after the cursor — not the whole supply):

| segment | published | window | names published / in window | PD-4 | repeated origins |
|---|---|---|---|---|---|
| 0 | 32 cards | 32 candidates, 13 names | 13 / 13 | 0 | 0 |
| 1 | 2 cards | 32 candidates, 21 names | 2 / 21 | 0 | 0 |
| 2 | 31 cards | 32 candidates, 21 names | **20 / 21** | 0 | 0 |

Replaying the same windows: v3 places 32 of 32 in every one (0 held) and meets **21 of 21** sources
in segment 2's first 31 cards, where the greedy rule meets 20.

#### A4.1 Reconciliation of the two-card append (architect's request)

The window-level replay (32 placed) and the published per-append counts (32, 2, 31) measure different
things, and the two-card append is now explained by evidence rather than inference:

- **The cursor is not persisted.** There is no receipt table and no logged candidate list, so the
  window above is a *reconstruction*: the eligible order at the segment's newest observation, minus the
  Edition's published origins, first 32. It is validated by ranks — every published origin of segments
  0 and 2 sits at rank 0–31 of its reconstruction, none beyond.
- **Segments 1 and 2 are one window, not two selections.** Their published origins occupy ranks 0–31
  of a single order — a contiguous 32-rank span split into two appends 1.6 s apart (11:12:12.15 and
  11:12:13.76). Nothing was held and nothing was lost; the runway chunked its publication.
- **The other card of segment 1 is a PD-1 re-occurrence.** Origin `43883822` (BBC, *Man dies after
  tiger attack*) was published in segment 0 (card 25, revision `4a225507`) and again in segment 1
  (card 0, revision `6d6bf27f`) — two revisions of the same origin, hours apart, which
  `.excludePublishedMaterial` admits by design. It is the only origin published twice in that Edition.
  The exposure rule therefore let it back in *after* the window, which is why it does not appear in the
  reconstructed order.

So the sequence is: 32 eligible candidates in the window, all of them published across two appends,
plus one materially-updated origin admitted by PD-1. The Editorial did not receive 32 candidates and
publish 2. PD-4 held: zero adjacent cards sharing a `SourceID`, zero repeated origins inside any
segment.

**Method caveat, stated because it caused the apparent inconsistency:** earlier tables mixed
window-level placement counts with per-append published counts. Window-level figures describe what a
rule *would* place given a window; a segment publishes whatever the runway asks for at that moment,
which can be a fraction of the same window.

**The honest reading, and it is not the report I expected:** on the windows this selection produces,
both rules are already near the window's ceiling (13 of 13 names), so the difference is 0–1 name.
The large differences measured earlier appear only on *skewed* windows — 5 of 12 names, 6 of 18 and
5 of 32 under greedy against 12, 18 and 32 under v3. The mechanism is proven end to end; its
magnitude depends on how dominated the examined window is, and richer selections produce windows that
are already diverse.

### A5. First-screen investigation (architect's question 5, out of scope for R2)

- **The viewport is ~2 cards.** Screenshot of the running app on iPhone 17 Pro Max (394×853 pt
  window, iOS 26.5): a hero card occupies about 40 % of the screen, a text card about 13 %. Publishing
  23 cards is therefore not the same as showing 23.
- **Coverage, from the two feeds' own timestamps:** 2 sources admitted at the first publication (60
  candidates, all BBC), 4 at +5 s, **36 at +30 s, 107 at +60 s**, 627 at +30 min. The first
  publication was 23 cards because the first 32 examined candidates were *all* BBC — 12 cards from
  one BBC feed, 11 from the other, alternating: the reader saw one display name 23 times while PD-4
  was perfectly satisfied.
- **Would a shorter first publication have been more diverse?** Only from ~+30 s: at +18 s there were
  still 4 sources. Bounding the first segment to the viewport would cut the single-publisher run from
  23 cards to about 4, and the next segment (3 display names at +18 s) would arrive 19 cards sooner.
  Before +30 s no policy can help — two sources existed.
- The lever is the coverage ramp, not the segment extent; the extent only decides how long the reader
  stays inside one window's composition — and that is a publication-policy decision, not Editorial's.

### A6. Known defects recorded by this round, not fixed here

- **`testOnboardingWelcomeComposerAndSave` (XCUI) fails on the baseline.** Reproduced with the R2
  changes stashed and the new test file removed: the same three assertions fail without this patch, so
  it is an independent UI defect in the onboarding composer, not a regression of R2. It stays in the
  parity backlog rather than being absorbed into this round. `swift test` (1029) and
  `FeedMineAppTests` (27) are green; the XCUI suite is therefore *not* fully green, and the R2-relevant
  XCUI subset (scroll admission, native swipe runway, offline relaunch, saved list + reader) is green
  on the final build (4 tests, 0 failures).
- **The persistent soak namespace carries this round's selection change.** The E2E drove a legitimate
  product flow (Fontes → *Entertainment* → Concluir) inside namespace `B50A0000-…-0030`, so that store
  now has `selection_version = 4`, 2,757 enabled targets, a v3 Edition and a checkpoint pointing at it;
  the two earlier v2 Editions and their cards are untouched. Any future soak inherits that selection
  until the section is switched off again.

### A7. Scope, as granted

R2's allowlist was `SourceAlternation.swift`, `SelectionEngine.swift`, `EditorialPolicy.swift`,
`SourceDiversityContractTests.swift`, `SelectionEngineTests.swift`, plus `AppComposition.swift`
conditionally and app-level tests for versioning/restore proofs. The architect granted the composition
exception on the condition that v2 keeps its behavior, v3 has its own revision identity, and existing
Editions, checkpoints and published cards stay intact — all three are implemented and proven above. The
only file touched outside Editorial is `AppComposition.swift` (the version map plus the revision
identity key); Persistence, Publication, Runtime, Acquisition, Media and UI were not modified.

**Not done, and deliberately:** the first-publication extent (R2-D3 says out of scope) and any code for
DUP-3 (R2-D4 authorizes the dataset only, delivered in `R1_DUP3_EXAMPLES.md`).

## Appendix B — how widespread DUP-3 is at supply scale

Measured after the report was sent, on the same database: all 22,183 supply candidates with a
headline, bucketed by their three longest tokens and compared pairwise (Jaccard ≥ 0.7 over tokens of
four or more characters, at least three shared tokens, sources disjoint):

- **166 pairs** of the same story held by two sources with no `SourceID` in common — with a 776-pair
  count under a looser rule (0.6, two shared tokens), which also matches templated series such as
  dated daily posts.
- The largest clusters are **mirror feeds of one publisher**, not independent syndication:

| pairs | example |
|---|---|
| 32 | an iVoox episode and its own blog feed publishing the identical headline |
| 23 | two Blogger feeds of the same blog (`blog-97099331`) |
| 18 | `Córdoba Patrimonio Gastronómico 18 junio 2026` / `Córdoba, patrimonio gastronómico (08/10/2026)` |
| 10 | the same daily rosary from two feeds, casing and icons apart |
| 9 | the same YouTube video carried by two different channel feeds |
| 7 | two Substack paths of one publication carrying one post |

Genuine cross-publisher syndication exists too (a Río Negro story also carried by another
publisher's feed), but it is a minority of the 166.

**Consequence for the open question 3:** the cheapest real win is not semantic clustering of
arbitrary stories but recognising that two sources are the same publication — which is a catalog
identity question (the 12 `BBC News` rows are the same problem), not an editorial one. The
editorial layer cannot fix it: `contentEntityID`/`contentClusterID` are `nil` at
`AppComposition.swift:1144`, and no supply fact distinguishes "two feeds, one publisher" today.
