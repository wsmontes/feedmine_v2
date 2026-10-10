# Reader filters and context identity — design for T6

Source: Codex design review, 2026-10-09 (thread *Replicate stable Feedmine 1 UI*), answering the four open
questions of plan task T6. Verified against the tree at `2ae76bb`. This document is the specification the
implementation follows; where it contradicts the plan's T6 wording, the plan is wrong and the correction is
recorded in §5.

## 1. Scope decision (plan T6 question 1)

**Chosen: (c) — an honest intermediate delivery, with T7's metadata import/query support brought forward before
T6 is called complete.**

- Enforce in the supply what the canonical data can already answer: **language**, **source membership** and
  **keyword exclusions** (`Candidate` carries `language`, `sourceIDs`, and the publication text carries the
  keywords — see `Sources/FeedMineEditorial/Candidate.swift:22-36` and
  `Sources/FeedMineEditorial/CandidateProvider.swift:42`).
- Criteria the data cannot answer yet (**mood**, **content type**, **taxonomy**, **region**) must be **visibly
  unavailable** — the control states that it cannot be applied. They must never be accepted and then silently
  ignored, and a filter must never be applied only to cards already drawn (`plan:147`).
- Identity-only work (the context key) is useful infrastructure but **does not complete a filter**.
- Full T7 does not have to precede T6: pull its *metadata import/query* forward. Catalog taxonomy alone does not
  establish article mood or content type; those need their own truthful derivation reproducing V1 semantics, so
  whoever implements them owns that derivation, not the catalog import.

## 2. Data shapes (plan T6 question 3)

### `ContextKey` (Domain)

```text
ContextKey =
    identitySchemaVersion : Int          // bump when the identity semantics change
    surface               : Surface      // .main | .source(SourceID) | .search(SearchContext)
    presetID              : PresetID     // .everything | .lastClicked | .editorial(FeedPreset)
                                         // | .collection(SourceCollectionID) | .smartFeed(SmartFeedID)
                                         // | .curatedFeed(CuratedFeedID)
    filter                : ReaderFilter // normalized
    searchScope           : SearchScope? // .sources | .contents | .both — absent outside `.search`
```

Search keeps the *meaningful* terms/query semantics; normalize only equivalences V1 demonstrated. Reordered
equivalent sets must produce identical keys **and identical persisted identifiers**.

### `ReaderFilter` (Domain)

```text
ReaderFilter =
    regionIDs       : Set<String>        // sorted canonical order
    taxonomyNodeIDs : Set<String>
    languages       : Set<String>
    contentType     : ContentTypeSelection        // .all | .one(ContentType)
    mood            : MoodSelection               // .all | .one(Mood)
    exclusions      : ContentExclusionSelection   // enabled flag + normalized active rules
```

- Criterion groups combine with **AND**; within a group V1's semantics are preserved.
- Empty/default selection means **unrestricted** (so the default key equals today's key for the same surface).
- Persist with sorted set values and deterministic encoding.

### `ReaderFilterDraft` (UI)

Mutable copies of the selections plus the preset/search-scope choices, carrying the **base applied-selection
generation** so a stale draft can be detected. Validation errors and dirty flags are UI state — not identity,
not persisted.

### `EditorialRevision`

Full context key plus the effective source-selection/preset definition, exclusion policy, catalog generation and
eligibility/scoring/sequencing versions. Use **semantic fingerprints or reusable versions**, never a
monotonically increasing "filter changed" counter: returning to an identical A must recover a *compatible* A
history.

### Expiry record (persisted preferences)

Persisted selection generation, the expiry-enabled preference, and per-group `expiresAt` where V1 keeps separate
lifetimes. **Exclusions have no expiry.** Timestamps and pending-expiry status are *not* `ContextKey` fields.

## 3. Where state lives (plan T6 questions 3 and 4)

- A filter combination is **its own context key with its own checkpoint** — that is what makes A→B→A recover A's
  position and what makes a delayed A callback inert during B (the existing identity fences reject it).
- **Canonical persistence must migrate**: checkpoint identifiers currently serialize only `main|source|query`
  (`Sources/FeedMinePersistence/SessionStore.swift:125` and `:133`) and edition persistence derives the same
  reduced identity. Updating `ContextKey` alone is insufficient — both must move to the complete key, with a
  migration that preserves existing main/source/search history without key collisions.
- **Expiry**: a clock check marks expiry *pending*. It never changes the active plan or the presentation
  (`AppComposition.swift:358` is where revision compatibility is checked today and must be widened). At an
  **explicit context transition** the coordinator resolves expired groups, persists the resulting selection and
  activates its key. Reselecting a criterion renews it.
- The reader's interaction stays V1's: the filter sheet commits its draft on dismissal (§5).

## 4. Tests that must exist

1. Reordered equivalent sets produce identical keys and identical persisted identifiers.
2. A→B→A offline restores A's compatible edition and position; a changed policy rejects incompatible
   restoration.
3. Delayed A callbacks during B — and during the new A — cannot install a presentation, change bookmarks or
   admit cards.
4. Four-hour expiry while the reader is stationary leaves snapshot and provenance byte-identical; an explicit
   transition applies the expiry; content exclusions survive it; renewal and relaunch behave correctly.
5. Legacy checkpoint migration preserves main/source/search history without key collisions.
6. A criterion the supply cannot answer is **visibly unavailable** and cannot be applied (no silent no-op), and
   nothing filters only the drawn cards.

## 5. Corrections this review forces

- **The plan's T6 requirement of explicit apply/cancel is wrong.** V1's `FilterSheetView` has no Cancel: it
  hydrates a local draft on appear and commits the dirty parts on `onDisappear`, so dismissing the sheet applies
  (`/Users/wagnermontes/Documents/GitHub/feedmine/feedmine/Views/FilterSheetView.swift:220-297`, with
  `presetIsDirty`/`overlayFiltersAreDirty` tracked separately). The transfer keeps **dismiss-applies**; the V2
  API therefore needs `ReaderFilterStore.apply(_ draft:)` for the *coordinator* but no Cancel affordance, and
  the plan's "apply/cancel/reset" test row becomes apply/dismiss-applies/reset.
- Delivered V1 inventory beats plan prose whenever they disagree; this is the first such conflict, recorded here
  and in `docs/v1-study/PORT_LOG.md`.

## 6. Persistence migration (next step, concrete)

Landed so far: `ReaderFilter` with its canonical identity text (`47d7c19`) and `ContextKey` as the whole
request with `canonicalIdentity` + identity-based equality and the legacy-decode path (`4ac3f79`). What remains
is the durable half, because today the durable identity is *reduced*:

- `SessionStore.contextIdentifier(_:)` builds `main` / `source:<uuid>` / `search:<query>`
  (`Sources/FeedMinePersistence/SessionStore.swift`), the `context_checkpoints.context_key` column stores that
  text, and `persistContext` derives it back from the edition's columns with a SQL `CASE`.
- An Edition therefore has no way to say *which* identity it belongs to beyond its surface.

Steps, in this order (each with its own test, all additive):

1. **`feed_editions.context_identity TEXT NOT NULL DEFAULT ''`**, written from
   `edition.editorialRevision.contextKey.canonicalIdentity` (`PublicationPersistenceMapping.record(edition:)`).
   No lookup changes yet.
   *Representation (decided here, before writing it):* the readable canonical text is the **identity used for
   matching**, and the full key is persisted alongside it as **sorted-keys JSON** (`ContextKey` is already
   `Codable`, and `.sortedKeys` makes it deterministic). Two columns, one job each: `context_identity` answers
   "is this my context?" and `context_key_json` reconstructs `EditorialRevision.contextKey` faithfully, which
   the driver's scope validation needs for a filtered context. Reconstructing the key from the reduced
   `context_kind`/`source`/`query` columns alone would silently degrade every filtered Edition back to the
   default surface on read (`decodeEdition` does exactly that today, `PublicationStore.swift:881-895`).
   Do **not** write a parser for the readable text: JSON is the reversible form.
2. **`context_checkpoints.context_identity TEXT NOT NULL DEFAULT ''`**, written by `persistContext` by *copying*
   the edition's column instead of re-deriving the reduced key.
3. **Backfill in the same migration, in Swift** (not in SQL): for every row with an empty `context_identity`,
   set it to `ContextKey(request:)`'s canonical text derived from the existing reduced columns — i.e. the
   default-surface identity for that surface. This is what preserves pre-T6 main/source/search history instead
   of orphaning it.
4. **Switch the lookups**: `activateContext` and `checkpoint(for:)` match on `context_identity`; keep
   `context_key` written as well for one release so an older build reading the same database still works, and
   record when it can be dropped.
5. **Tests**: a pre-T6 database (rows with only the reduced key) keeps its checkpoint after migration; two
   different filters on the same surface get different checkpoints and neither collides with the default one;
   a reordered-equivalent selection reuses the *same* checkpoint; `FeedEdition` round-trips its
   `context_identity`; the migration is idempotent (running it twice changes nothing).

Only after step 4 should the reader see filter-driven contexts: until then `ReaderFilter` and the extended
`ContextKey` are values with identity and tests, not yet durable behaviour.

