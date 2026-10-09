# Product decisions — 2026-10-09

Source: product owner answers to the open questions in `docs/v1-study/00-README.md`.
These are binding product rules. Where a rule conflicts with an existing invariant or a
landed phase, the conflict is named explicitly below and must be resolved by the next gate.

---

## PD-1 — An edited article reappears as a new card

**Decision.** When a publisher materially edits an article that was already published, the
edited version is published again as a **new occurrence** (new `PublicationCardID`) so the
reader sees it again. The old card stays in history unchanged.

Chosen over "same card with visualization reset" because v2 history is immutable and has no
per-card view state; a new occurrence keeps INV-08 intact and needs no mutation.

**Rules.**
1. *Material edit* = the normalized plain-text title or summary changed, or the chosen primary
   media changed. Normalization removes HTML, entities, whitespace and tracking parameters.
   Whitespace, entity, tracking-param and date-only churn are **not** material (this is what
   made v1/RSS produce duplicates — see `02-ingestion-network.md` IN-3).
2. At most **one future (not yet seen) occurrence per origin** at any time. A newer edit
   supersedes a not-yet-seen re-occurrence instead of adding another.
3. A re-occurrence obeys PD-4 (source alternation) like any other card.
4. An edit carried under an unchanged external version identity (Atom `updated`, JSON
   `date_modified`) must still be admitted as a new revision when material. Rejecting it loses
   the edit (review H1 follow-up 1).

**Conflicts to resolve.**
- `PRODUCT_INVARIANTS.md` "Phase 3R5" says an Edition admits at most one occurrence per
  `OriginRecordID` and a new revision is not a new occurrence. Amend it: uniqueness becomes
  per `(OriginRecordID, materially distinct revision)`, with rule 2.
- `AcquisitionAdmissionStore` known-version conflict rejection (3R1): turn material conflicts
  into new revisions; keep rejecting only non-material or corrupt input.

---

## PD-2 — v2 reuses the v1 catalog

**Decision.** v2 uses v1's catalog (`catalog.sqlite` plus Python tooling; 77,443 sources in the bundled snapshot).

**Consequences.**
- Catalog / SourceBinding materialization is now required work (`04-catalog-editorial.md`
  Lesson A). Sources have their own lifecycle, separate from runtime supply.
- v1 `sourceID` is a truncated 32-bit hash (`CatalogIdentity.swift:55`); v2 IDs are UUIDs.
  Map with a stable, recorded v1-key → v2-UUID derivation; never reuse the 32-bit value as identity.
- Keep v1's two-URL model (identity URL ≠ request URL) and its identity contract vectors.
- At this scale, acquisition fairness, backoff and bounded parallelism (review H2 residuals)
  are mandatory, not optional.

---

## PD-3 — First launch: honest, adaptive, entertaining

**Decision.** No magic numbers. The program must know, from measured facts, whether
preparation will be fast or slow, and choose its strategy. The preparation screen entertains
with **real** content arriving — feed names, headlines, cards assembling/flying — never just a
progress bar. "We are not installing software; we are going after the good content the user
wants."

**Rules.**
1. Estimate from facts: eligible targets, measured per-target latency, admission rate,
   prepared-card rate. The estimate drives the strategy; it is not a fixed timeout.
2. Everything shown is real evidence from the pipeline (INV-06: never fake instantaneity, never
   fake content). Runtime must expose a preparation-evidence surface to UI: source being
   contacted, admitted headlines, sources that contributed, cards prepared.
3. Available subterfuges, chosen dynamically:
   - start with targets measured fastest/most reliable (without breaking fairness over time);
   - publish the first screen as soon as a PD-4-valid prefix exists for the actual viewport;
   - prefer cards designed text-only when media would delay the first screen (PD-5);
   - keep entertaining while work continues after the first cards (INV-05).
4. "Ready" counts contributing sources and prepared cards, never HTTP successes (v1 `100/43556` bug).

---

## PD-4 — Source alternation is a rule

**Decision.** Two consecutive cards from the same source are forbidden. Fetch or media speed
must never degrade the shuffle.

**Rules.**
1. Adjacent cards differ by `SourceID`. Applies across segment boundaries, re-occurrences (PD-1)
   and re-entered withheld cards (PD-5). Provider is not a PD-4 criterion.
2. If supply cannot satisfy the rule, **do not publish the violating card**: hold it and emit
   acquisition demand for other sources. A shorter runway is acceptable; a repeated source is not.
3. Order is decided by Editorial from candidates, never by arrival order of network or media.
4. Exception: a single-source context (`FeedContextRequest.source`) is exempt by definition.
5. Tested as an invariant on the final published sequence.

Owner: `FeedMineEditorial` (single ordering owner, `04-catalog-editorial.md` Lesson B, FP-11).

---

## PD-5 — Missing image: designed text-only card or withhold; late image never touches the screen

**Decision.** If the image is not ready, the program decides per card, continuously:
- publish a card **designed** without image (a real text-only layout, not a card missing its image), or
- take the content out of the queue until it is complete.

If the image arrives after publication, **the visible screen does not change**. Only when the app
loses focus or is closed may the program "tidy the house" quickly.

**Rules.**
1. Withholding defers the item to a later selection; it re-enters as a normal candidate under PD-4.
2. Seen cards are immutable forever (INV-08).
3. Published-but-unseen cards may be re-prepared with late media **only while the app is not
   visible** (background, inactive, closed). "Seen" is derived from real viewport observations
   (high-water mark), not from publication.
4. On return, the reader's position and every seen card are exactly as left.

**Conflict to resolve.** INV-08/INV-09 currently forbid any change to published history. Amend:
"seen history is immutable; unseen published runway may be re-prepared only while the app is not
visible." Publication needs a mechanism for this (e.g. a successor for the unseen tail); choose it
in the media gate.

---

## PD-6 — Media budget is dynamic and device-aware

**Decision.** Ideal: wonderful images and infinite space. Reality: old iPhones, little free space,
slow or unstable networks. The budget is computed, not configured.

**Inputs (all measured at runtime).** Free disk for important usage, physical memory, thermal
state, Low Power Mode, network path (expensive / constrained / Low Data Mode), measured
throughput and latency per host, actual slot size × screen scale.

**Rules.**
1. Never fetch or keep pixels larger than the slot actually rendered on this device.
2. Choose the candidate (srcset size, og:image vs feed image) that fits network and slot; when
   cost is high, prefer a designed text-only card (PD-5) over a slow image.
3. Disk budget scales with free space and shrinks under pressure; eviction order:
   far-future unseen → old seen → recent seen; bookmarked never evicted.
4. Safety ceilings (decode-bomb dimensions, byte cap while streaming) are operational bounds,
   allowed by INV-04; they are not the strategy.

Design reference: `docs/v1-study/03-media.md` §6.

---

## PD-7 — Lightweight local quality practice

No hosted CI. Practices must speed development up, not slow it down.

1. Before pushing to `main`: `swift build && swift test && git diff --check` locally (the agent
   already does this; keep reporting the test count in the commit/doc).
2. Add `.gitignore` (`.build/`, `.swiftpm/`, `DerivedData/`, `xcuserdata/`) and keep
   `Package.resolved` committed.
3. Docs change in the same commit as the code they describe (prevents v1-style drift).
4. Keep `FeedMineApp.xcodeproj` a thin shell over the SwiftPM package; all code lives in the package.
5. Every TestFlight build carries the git SHA (build number or tag).
6. No mandatory PRs, no approval gates. Async review via `docs/reviews/`.
