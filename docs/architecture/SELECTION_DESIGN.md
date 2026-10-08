# Selection architecture design

## 1. Scope

Phase 3D is a design-only gate for the pure Editorial selection boundary. Phase 3C already provides Main + Source structural canonical candidates through one bounded ContentStore window per CandidateProvider call. Search remains explicitly unavailable pending canonical FTS.

Phase 3D completed the design-only gate. Phase 3E implements the approved pure deterministic baseline: one explicit ResolvedSelectionPolicy value, nominal guard, duplicate-origin rejection, total ordering and preserved supply facts. Persistence continues to own canonical authority and examined-work bounds.

## 2. Verified legacy evidence

The directed legacy review was already performed and verified by the operator. The preserve/reject evidence below is supplied by the Phase 3D prompt; no new legacy inspection or code copying was performed for this gate.

Preserve:

- Determinism that is byte/semantically reproducible from explicit inputs.
- Hard eligibility that never relaxes.
- Honest supply exhaustion.
- Short supply that never duplicates cards.
- Zero connector, network or raw protocol evidence in Selection.
- Editorial ordering downstream of supply retrieval.
- Deterministic tie-breaks ending in durable identity.
- Explicit, auditable soft relaxation when a future policy actually introduces it.
- Exploration only with an explicit seed.

Reject:

- Selection-owned repository walks.
- `poolLimit`, `cardLimit`, `scanRowsPerStep` and `maxScanSteps`.
- Exponential scan growth and page/refill loops.
- Query-plan/read-report mechanics inside Selection.
- Three-pass “relax until full” assembly.
- Baseline `providerQuota`.
- Union-Find clustering.
- Repetition machinery.
- Large revision fingerprint recomputation.

These findings preserve semantic invariants, not the legacy implementation machinery. Deferred behavior is not implicitly enabled by its appearance in this evidence.

## 3. Deliberate responsibility inversion from legacy

The new architecture deliberately inverts the legacy repository-walk responsibility:

> Selection receives one finite CandidateSupplyWindow.
> Selection never obtains another window itself.

CandidateProvider owns one bounded structural retrieval call. The caller supplies its resulting window to Selection. Selection does not own CandidateProvider, ContentStore, a repository or any cursor walk. It cannot obtain a second window, enlarge capacity, refill, inspect a query plan or perform I/O.

> A caller may obtain another CandidateSupplyWindow, but SelectionEngine itself never does.

A future caller's continuity decision does not become an implicit loop or scan policy in Selection.

## 4. Ownership

| Boundary | Responsibility |
| --- | --- |
| FeedPlanResolver | Future owner of resolving FeedPlan together with a matching ResolvedSelectionPolicy. Its implementation is outside 3D/3E. |
| CandidateProvider | Exactly one bounded structural local supply window for Main or Source, with Editorial-owned Candidate/cursor values. |
| Persistence | Canonical authority, schema, source membership checks, keyset mechanics and bounded examined work. |
| SelectionEngine | Pure deterministic execution of the supplied policy and explicit total ordering over one finite window. |
| Publication | Freezes semantic selection into immutable published history. |
| Runtime / Runway | Determines future supply need and whether received supply facts represent insufficiency. |
| Acquisition | Fulfills future supply demand; Selection neither creates nor executes that demand. |

SelectionEngine.swift must not import FeedMinePersistence, consult a database or call CandidateProvider. No connector/network/raw evidence enters its input or output.

## 5. Policy identity vs executable policy

The normative distinction is:

```text
FeedPlan / EditorialRevision = identity of resolved editorial behavior
ResolvedSelectionPolicy     = executable pure editorial behavior
SelectionEngine             = executes the supplied policy
```

PolicyVersion alone is never executable. Selection must never interpret `PolicyVersion(rawValue: 3)` as a behavior definition or look it up in a protocol registry.

ResolvedSelectionPolicy carries nominal identity sufficient to compare these exact fields against FeedPlan.revision:

- ContextKey.
- userSelectionVersion.
- eligibilityPolicyVersion.
- scoringPolicyVersion.
- sequencingPolicyVersion.
- exposurePolicyVersion.
- selectionSchemaVersion.

Every field must match before policy execution; a mismatch is `policyMismatch`. No fingerprint, digest or large revision recomputation participates in this guard. catalogGeneration is not an executable-policy version and is excluded from the guard. The resolved behavior is supplied as a value, not inferred from a catalog generation or revision identifier.

The full EditorialRevision from the supplied FeedPlan is preserved in the result, including its identity and catalog generation. Excluding catalogGeneration from the policy guard does not discard it from publication-facing semantic provenance.

## 6. Baseline ResolvedSelectionPolicy

Use one small pure value, ResolvedSelectionPolicy, with the nominal identity above and explicit baseline executable semantics. Do not create separate EligibilityPolicy, ScoringPolicy, SequencingPolicy or ExposurePolicy services, a service hierarchy or a protocol registry. The value may grow only when concrete rules require it.

| Behavior | First executable baseline |
| --- | --- |
| Source/user eligibility | Accept the structurally supplied Candidate values. |
| Additional hard eligibility | None. |
| Soft eligibility | None. |
| Scoring | None; all candidates are equivalent for scoring. |
| Sequencing | `recencyDescending`, using the total order in section 8. |
| Exposure | None. |

These no-ops are explicit behavior, not secret placeholders for personalization. Nominal identity guards the supplied policy; version numbers do not invent filters, weights or exposure behavior. Source eligibility has already been applied by the bounded Persistence path and is not reimplemented by Selection.

## 7. Candidate input contract

SelectionEngine receives exactly:

- FeedPlan.
- A matching ResolvedSelectionPolicy.
- One CandidateSupplyWindow.

The input window is finite. Candidate remains the Phase 3C semantic value: originRecordID, originRevisionID, headline, summary, timestamp, language and providerID. Do not add bodyText, searchProjection, primaryLink, external identities, memberships, score/rank, media or Persistence row types to reproduce legacy filters.

A structurally valid input has one Candidate per OriginRecordID. Duplicate identity means duplicate OriginRecordID, even if the two values name different revisions or have different payloads. Reject the entire input explicitly as `duplicateCandidateIdentity`; do not deduplicate silently, choose first/last wins or publish a partial result.

The provider's current ordering is not sequencing authority. Selection must apply its own total order explicitly.

## 8. Deterministic total ordering

The baseline order is lexicographic:

```text
Candidate.timestamp.value DESC
OriginRecordID canonical identity DESC
OriginRevisionID canonical identity DESC
```

Canonical identity comparison uses lowercase canonical UUID text, compared deterministically in its binary/UTF-8 order. Both ID tie-breaks are durable and independent of process or collection iteration. Duplicate OriginRecordID rejection still applies; the revision tie-break completes the stated candidate ordering contract rather than permitting multiple revisions of one origin.

CandidateTimestampKind preserves authored/observed meaning but does not affect baseline ordering. Selection explicitly applies `recencyDescending` even if CandidateProvider happened to deliver the same order. Array input order, Dictionary/Set iteration, hash values and randomized UUID generation are not sequencing rules.

The same complete inputs and policy produce the same semantic result. Permuting a valid candidate array with otherwise identical input facts does not change orderedCandidates. No Date.now, implicit clock, global RNG, hidden state or mutable cache participates.

## 9. SelectionResult / supply facts

The proposed semantic output is:

```text
SelectionSupplyReport
    examinedCount
    nextCursor
    exhausted

SelectionResult
    editorialRevision
    orderedCandidates: [Candidate]
    supplyReport
```

editorialRevision is the supplied FeedPlan.revision. orderedCandidates contains Candidate values directly, ordered by the explicit baseline sequencing rule. Do not introduce an empty SelectedCandidate wrapper without metadata of its own.

SelectionSupplyReport preserves the input window's examinedCount, Editorial-owned nextCursor and exhausted exactly. These are received supply facts, not a query-plan report, count recomputation or an editorial exhaustion decision. examinedCount can exceed the number of candidates, and an empty candidate array can still carry a progress cursor with exhausted false.

No PublishedCard, FeedSegment, PublicationCardID, fetch command or acquisition demand appears in the result. Publication owns the later conversion into frozen history.

## 10. Hard/soft semantics

The future hard-rule invariant is normative: once hard eligibility rejects a candidate, subsequent soft behavior must never readmit it. Hard rules never relax to fill output.

When a future concrete policy introduces soft behavior, that behavior and any relaxation must be explicit and auditable in semantic output. Phase 3E has no soft rule, progressive relaxation, soft-pass assembly or relaxation metadata placeholder. It applies the supplied baseline once over the finite input.

Prohibited flow:

```text
few selected → relax policy → re-run → request another window → relax quota
```

## 11. Insufficient supply semantics

There is no target count in Selection. It does not declare “need 20”, “missing 8” or “shortfall 8”, and has no requested count, card limit, pool limit, minimum candidate count or refill budget.

Selection reports only supplied facts. Empty or short supply is an honest successful result when input and policy are valid; it is not concealed by duplicate candidates, extra scans, policy relaxation or acquisition. A full examined batch with exhausted false stays false, and an empty eligible window retains its supplied progress cursor. Runtime / Runway or future orchestration determines whether those facts imply a need for more supply.

> Selection must never hide insufficient local supply by scanning unboundedly, relaxing hard rules, duplicating candidates, or initiating acquisition.

## 12. Failure behavior

Baseline semantic failures are only:

- `policyMismatch`: nominal policy identity differs from the FeedPlan guard fields.
- `duplicateCandidateIdentity`: OriginRecordID occurs more than once in the supplied input.

Validate policy identity before execution, then reject duplicate origin identity before producing ordered output. No partial result or silent corrective deduplication is returned. Do not introduce generic SelectionError(String).

Storage/network failures are absent from this boundary because Selection performs no I/O. Honest supply exhaustion or an empty candidate array is not a failure.

## 13. Explicitly deferred behavior

- Exposure/history: no ExposureInput, ExposureStore, empty exposure snapshot or seen filtering in 3E. A real exposure consumer requires its own phase.
- Provider diversity: ProviderID attribution does not imply providerQuota, balancing or diversity behavior.
- Language policy: no automatic language filter or preference.
- Scoring: no weights, ranking personalization or invented score values.
- Soft relaxation: no progressive passes or relax-until-full assembly.
- Clustering: no Union-Find or relation/entity/cluster queries.
- Repetition: no published-history window/counter and no duplicate occurrences to fill output.
- Exploration: no random-seed API until a concrete exploration policy exists; any future seed must be an explicit/versioned input, never global RNG.
- Retrieval/refill policy: no Selection-owned repository walk, page size, requested count, pool/card limit or multi-window policy.
- Acquisition, network, FTS, media preparation and Runtime / Runway supply-demand execution remain outside Selection and this gate.

## 14. Phase 3E implementation gate

Phase 3E implemented only:

- EditorialPolicy.swift: one ResolvedSelectionPolicy value with nominal identity and explicit baseline strategy/value semantics.
- SelectionEngine.swift: pure deterministic execution, nominal policy guard, duplicate-input rejection and the explicit total ordering.
- Semantic SelectionResult and SelectionSupplyReport values carrying ordered Candidate values and preserved supply facts.
- Editorial unit tests for the nominal guard, duplicate-origin rejection, ordering independent of input permutation, durable timestamp ties, authored/observed meaning and honest empty/short supply metadata.

It must not call CandidateProvider, import Persistence in SelectionEngine.swift, implement history/exposure, scoring weights, soft relaxation, quotas, language personalization, clustering, repetition or acquisition. It must not introduce requested count, card limit, pool limit, a seed without exploration semantics or a refill loop.

FeedPlanResolver remains the future owner of resolving both plan identity and executable policy; this gate does not authorize implementing that resolver. Phase 3E pure deterministic baseline Selection is complete. SelectionEngineTests construct values directly with @testable import FeedMineEditorial, without SQLite, ContentStore or CandidateProvider. The implementation performs no I/O, no refill, no target-count handling, no history/exposure, no scoring weights and no acquisition. No package or CandidateProvider API change was required.
