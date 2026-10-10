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
   - publish other prepared stories while image-dependent candidates remain deferred; use text-only when intentionally suitable or supported by failure evidence (PD-5/PD-9);
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

## PD-5 — Per-story media readiness; late assets never block or rewrite the feed (revised 2026-10-10)

**Decision.** A story whose expected image is still arriving or being prepared leaves the current **ready-to-publish opportunity**, not the pool of eligible stories. Other ready stories must advance without waiting. The deferred story retains its identity and reusable acquisition/preparation facts, and returns to consideration when ready. Its previous position is not reserved.

**Rules.**
1. **Pending is not broken.** A slow image, temporary failure, pending decode, unknown condition or network restriction does not by itself justify converting the story into text-only.
2. **Text-only is an evidence-based presentation decision, not a timeout.** Use a purposefully designed text-only card when it is editorially appropriate from the outset, or when available evidence establishes that a usable image is not reasonably obtainable (e.g. definitively broken, unsupported, invalid, or realistic alternatives have been tried under measured cost and failure conditions). No fixed waiting time or magic retry count decides this automatically.
3. **Independent bounded work.** Deferred preparation proceeds or is reconsidered on legitimate availability/resource/retry opportunities as budget allows, alongside other stories, using existing owners. Do not busy-poll, block the whole selection, discard eligible items or create a second scheduler. An attempt's transient/definitive outcome and media readiness must not be silently conflated.
4. **Before versus after publication.** Before publication, candidate priority, representation and resources may improve. **After publication**, occurrence ID, selected text/action, layout and referenced media contract remain immutable whether the user has seen the card or not. The admitted reader sequence additionally preserves position, order and geometry. Re-decoding the same frozen local asset into its reserved slot may change pixels, not shape; a published text-only card cannot silently acquire a hero image. A later legitimate Edition may publish a new occurrence under existing editorial rules; late media alone never rewrites history.
5. A story deferred for an image re-enters ordinary editorial selection, including current freshness, relevance, eligibility and PD-4 alternation. Legitimately image-free stories remain first-class; image absence alone is not proof of bad editorial quality.

**Supersedes** the old permission to re-prepare published-but-unseen cards while the app is inactive. The immutable publication boundary stays strict; **the visible/admitted prefix is sacred**. See PD-9 for image, link, content and other preparation failures alike.
---

## PD-6 — Media budget is dynamic and device-aware

**Decision.** Ideal: wonderful images and infinite space. Reality: old iPhones, little free space,
slow or unstable networks. The budget is computed, not configured.

**Inputs (all measured at runtime).** Free disk for important usage, physical memory, thermal
state, Low Power Mode, network path (expensive / constrained / Low Data Mode), measured
throughput and latency per host, actual slot size × screen scale.

**Rules.**
1. Never fetch or keep pixels larger than the slot actually rendered on this device.
2. Choose image resources that fit the network and slot; slow or costly image-dependent stories defer while other cards advance. Text-only is a legitimate editorial choice or evidence-based unusable-media decision under PD-5, never an arbitrary time limit.
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

---

## PD-8 — Progressive coverage and resource-relative operation (2026-10-10)

**Decision.** The full eligible catalog is a progressive exploration universe. Source priority determines visit order and revisit frequency, never a permanently limited shortlist. Given sufficient available opportunities across use, each eligible source must eventually get a contact opportunity. Language selected by the reader is a hard content eligibility rule. Thematic preferences guide relevance and nearby discovery, not an arbitrary exploration quota; an explicitly restricted context remains restricted.

**Applies everywhere.** Acquisition, editorial candidate examination, sequencing, runway, media preparation, local storage, retention and cleanup adapt to measured demand and available capabilities: actual consumption, supply, network throughput and latency, data cost, memory and disk pressure, power, thermal state and iOS execution permission. Spare capacity permits more discovery and useful retention; pressure reduces speculative work. Existing visible cards and continuity take precedence.

**No magic numbers as strategy.** A fixed per-operation work bound may protect memory, I/O, safety or platform rules but cannot permanently cap discoverable sources, available stories or retained articles. Frozen benchmark thresholds remain acceptance checks, not runtime quotas. Reconsider opportunities through existing owners and actual events rather than introducing an extra polling scheduler or duplicating state. This extends PD-2, PD-3, PD-6 and INV-16 without changing the contracts of earlier phases.

---

## PD-9 — Nonblocking per-story preparation for all card dependencies (2026-10-10)

**Decision (product owner).** A story may be unable to become presentation-ready because of image, link, body text, media, decode or another required preparation step. **One unready story never blocks other ready stories.** Remove it from the immediate publication opportunity without deleting its identity or reusable work. Independent resource-bounded work continues; when the missing requirement is genuinely resolved, the story returns to future editorial consideration, with no guaranteed old rank or insertion into already admitted reading history.

**Different failure meanings.** Transient/unknown means deferred and recoverable. Definitively broken image may justify a designed text-only presentation when the article can still be consumed. A broken article link never becomes a fake viable card: try a verified legitimate alternative or authorized complete local content; otherwise hold as unavailable and trace the reason. Final editorial exclusion and temporary deferral must be distinguishable in observed outcomes.

**No magic retries.** Operational connection timeouts or per-operation safety bounds are allowed; they do not by themselves classify a story as unusable or dictate a fixed count of attempts before downgrading. Reconsider retries with the observed error, source history, cost, resource permission and real opportunities; no spin loop, indefinite head-of-line blocking, silently forgotten candidate, fabricated readiness or new parallel scheduling engine.

**Acceptance.** In a mixed corpus with slow image, permanently broken image, transient link failure, dead link and several ready stories, ready content progresses independently; recoverable candidates remain reachable and may later enter the feed, broken image becomes text-only only when justified, dead links never publish without real consumption, and previously published/admitted cards remain unchanged. This is not yet implementation evidence.
