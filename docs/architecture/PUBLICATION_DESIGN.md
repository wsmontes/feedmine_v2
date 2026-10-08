# Publication input and lifecycle architecture

## 1. Scope

Phase 3F completed the design-only architecture gate. Phase 3G is complete: 3G1 implemented bounded publication-tail reads/append validation; 3G2 implemented immutable PublicationCardDraft and PublicationCoordinator. Phase 3E pure deterministic Selection is complete. This document closes the conceptual boundary:

```text
SelectionResult
→ publication preparation / media preparation
→ ready-to-freeze PublicationCardDraft values
→ PublicationCoordinator
→ FeedEdition + immutable FeedSegment + PublishedCard
→ PublicationStore
```

> SelectionResult is editorial intent. It is not yet a complete PublishedCard.

> PublicationCoordinator freezes already-prepared FeedMine semantic values. It does not perform Selection, canonical enrichment, media resolution or network work.

3F changed documentation only. The 3G implementation preserves this design with explicit requests and real temporary SQLite integration tests; no package, schema or migration change was needed.

## 2. Verified legacy evidence: preserve/reject

The supplied review already examined legacy `Packages/FeedRuntimeV2/Sources/FeedRuntime/Publication/PublicationCoordinator.swift` and related MediaPreparation/test behavior. This gate incorporates that evidence without repeating broad legacy investigation or copying legacy code.

Preserve:

- PublicationCoordinator is the sole producer of published history; Selection, Media and Acquisition do not publish.
- FeedEdition, FeedSegment and PublishedCard are immutable after commit.
- Editorial order reaches publication without reordering.
- First Edition and first Segment appear atomically.
- A concurrent tail must never be silently renumbered.
- Failure of a new publication never destroys earlier history.
- Late media never rewrites an already-published card.
- Publication can exist offline without remote bytes, and text-only is a valid representation.
- Once media assets are implemented, an asset reference may exist only after durable materialization.

Reject as baseline:

- PublicationEpoch and PublicationToken.
- Global active/draft/superseded Edition state and activeEdition lookups.
- absoluteOrdinal.
- PublicationSingleFlight actor.
- DraftPins.
- commitRetryLimit and retry loops.
- Repository hierarchy.
- `openEdition(.visible/.successor/.first)` state machine.
- Media composition inside PublicationCoordinator.
- Selection/canonical lookups inside Publication.
- Generation counters.

Rejected mechanisms require a concrete future invariant or consumer before reconsideration. Their legacy existence does not authorize them in 3G.

## 3. Selection is not a complete publication payload

Candidate contains editorial origin/revision identity, headline, summary, timestamp, language and provider attribution. It does not supply all fields frozen by PublishedCard: Source attribution, display-name snapshots, media, RenderContract, primary action and optional entity/cluster semantics are still missing.

PublicationCoordinator must not implement a direct Candidate → PublishedCard conversion that fills those gaps itself. A future upstream preparation boundary supplies sourceID, sourceDisplayName, providerDisplayName, contentEntityID, contentClusterID, media, RenderContract and primaryAction as appropriate. PublicationCoordinator performs no live ContentStore, catalog, Source, Provider, OriginRevision or media-candidate lookup.

## 4. PublicationCardDraft boundary

PublicationCardDraft is a conceptual immutable Publication-module value representing prepared FeedMine semantic payload without a PublicationCardID:

```text
PublicationCardDraft
    origin: PublishedOrigin
    contentEntityID?
    contentClusterID?
    text: PublishedText
    timestamp: PublishedTimestamp?
    media: PublishedMediaSet
    renderContract: RenderContract
    primaryAction: PublishedPrimaryAction?
```

It is ready to freeze, not a Persistence store record. It contains no PublicationCardID, FeedSegmentID, FeedEditionID, SQL row, CandidateProvider cursor, network URL as media identity or raw protocol evidence.

The future preparation boundary owns completing this payload. PublicationCoordinator owns validating and freezing it; 3G2 implements the ready-to-freeze draft and Coordinator; upstream preparation remains deferred.

> Publication freezes prepared semantic values into append-only history. It does not finish preparing them.

## 5. Selection/draft alignment

PublicationCoordinator receives SelectionResult and an ordered array of PublicationCardDraft values. Drafts correspond 1:1 by position to SelectionResult.orderedCandidates. Baseline alignment is exact:

| Draft field | Required Candidate value |
| --- | --- |
| origin.originRecordID | originRecordID |
| origin.originRevisionID | originRevisionID |
| origin.providerID | providerID |
| text.title | headline |
| text.primaryText | summary |
| timestamp value | timestamp.value |
| timestamp kind | authored → authored; observed → observed |

Candidate timestamps must be preserved, including authored/observed meaning; the optional draft timestamp does not permit dropping a timestamp present in Candidate. Preserve nil versus empty text and optional provider attribution. Publication does not reinterpret editorial text or time.

The ordered PublicationCardIDs array also has exactly one ID per draft/candidate. Reject count mismatch, duplicate PublicationCardID and positional alignment mismatch. Do not generate replacement IDs, silently deduplicate, reorder drafts or repair mismatches.

> Publication preserves Selection order; it never fills, relaxes, reselects or reorders.

## 6. Text-only baseline and future media

A valid first-implementation draft may already contain `media = .none` and a textOnly RenderContract. This permits publication without real MediaPreparation, AssetStore or remote media bytes. Preparation chooses that representation before publication; PublicationCoordinator only validates and freezes the supplied contract. It does not choose textOnly as a fallback or synthesize a primary action.

The draft brings primaryAction or nil. PublicationCoordinator does not infer an externalURL action from content or perform action enrichment. It does not call MediaResolver, MediaPreparation, AssetStore or network. PublishedMediaSet and RenderContract are already prepared.

> Later media preparation can affect only future publication.

A published text-only card is never updated when media arrives. Using later media requires a new PublishedCard occurrence in a future publication. Once assets exist, preparation must complete durable materialization before publishing an asset reference; remote URLs are not media identities. Real media preparation and asset storage remain deferred after 3G.

## 7. Explicit identity/time/seed inputs

Future requests supply identity material explicitly; PublicationCoordinator constructs the semantic history objects. Callers do not construct or persist history directly.

| Create Edition request | Append request |
| --- | --- |
| FeedEditionID | Target FeedEditionID |
| PublicationSchemaVersion | No caller-selected schema version; use the target Edition's frozen version |
| selectionSeed | No replacement Edition seed |
| editionCreatedAt | No replacement Edition creation time |
| FeedSegmentID | FeedSegmentID |
| segmentSeed | segmentSeed |
| segmentCreatedAt | segmentCreatedAt |
| Ordered PublicationCardIDs | Ordered PublicationCardIDs |

Both operations also receive SelectionResult and the aligned drafts. No UUID(), Date.now or random() is called internally to compose history. All supplied IDs, times and seeds are preserved explicitly for reproducibility and tests.

FeedEdition.selectionSeed remains an explicit frozen publication input. Selection 3E has no exploration/randomness and does not claim to have used that seed. Do not generate or derive it magically. A future exploration policy can connect that contract deliberately when it exists.

## 8. Edition create semantics

Create freezes SelectionResult.editorialRevision exactly into FeedEdition and uses the explicit PublicationSchemaVersion. It constructs first FeedSegment at ordinal 0 and PublishedCards in the supplied editorial/draft/card-ID order.

Edition + first Segment + its cards commit in one transaction through the existing atomic createEdition/firstSegment store operation. Never create an empty Edition awaiting cards later.

Empty orderedCandidates yields the semantic outcome `nothingToPublish` and zero durable writes: no empty Edition, empty Segment, placeholder candidate or duplicated history. Short nonempty selection publishes exactly the prepared candidates supplied, even if there are only one, two or three. There is no requested segment size, minimum card count, fill-to-N or duplicate-to-fill behavior.

## 9. Append/tail semantics

Append names its target FeedEditionID explicitly. PublicationCoordinator never discovers a global active, current visible, latest or automatic successor Edition.

SelectionResult.editorialRevision must exactly equal the target Edition's frozen EditorialRevision; otherwise publication is refused. Append uses exactly the target Edition's PublicationSchemaVersion. The caller cannot select a different append schema version or mix editorial revisions in one Edition.

Composition needs only the target Edition's frozen metadata and tail to derive nextOrdinal. Phase 3G may add a narrow mechanical `tail(editionID)` read to PublicationStore if needed, returning only what nextOrdinal requires. Do not load all Segments to find the tail. Create always uses ordinal 0.

A precomposition tail read is not correctness authority. PublicationStore.appendSegment continues to revalidate the proposed ordinal against the actual tail inside its serialized write transaction. A stale append is refused rather than silently recalculated or fitted into a later tail.

## 10. Failure and concurrency semantics

If another append wins the race, the stale append fails. Do not renumber it, automatically retry it, reuse its draft at a new ordinal or hide the refusal. The caller decides whether to recompose.

Storage failure remains failure; tail movement remains failure/refusal. No commitRetryLimit, retryCount, backoff or retry loop belongs in 3G. SQLite/store transactions are correctness authority; no baseline single-flight actor is required. Future single-flight work requires demonstrated orchestration cost or concurrency need and would be an optimization, not a replacement for transactional correctness.

No DraftPins are introduced while retention/GC is absent. Exact OriginRevision IDs may become explicit retention roots only in a future retention design.

> A failed future publication can leave supply unused. It can never rewrite already-published history.

Earlier immutable history stays available after failure. Alignment or revision refusal performs no partial publication; atomic store failure does not leave a half-created Edition/Segment/card set.

## 11. Visibility / successor ownership

Do not add active, visible, draft, superseded or currentEdition flags to feed_editions. An Edition is immutable history. FeedSession/Runtime chooses which Edition is presented.

A future explicit refresh may create a new Edition and first Segment, then let Runtime/Session switch presentation only after successful creation. If creation fails, the predecessor remains intact and naturally presentable. PublicationCoordinator does not perform the session swap or own a visible/successor/first Edition state machine.

> Edition visibility belongs to the session/runtime, not to a global publication flag.

## 12. Publication output

PublicationCoordinator remains the sole producer of semantic FeedEdition, FeedSegment and PublishedCard history. Selection, Media and Acquisition do not publish. PublicationStore mechanically persists the constructed objects through the established semantic mapping/store boundary; it does not select or enrich them.

A small future semantic outcome/receipt distinguishes `nothingToPublish` from successfully committed publication and identifies the committed Edition/Segment/cards. It must not imply visibility, a session swap, acquisition demand or automatic retry. No implementation or enlarged receipt hierarchy is proposed in 3F.

Selection's examinedCount, nextCursor and exhausted are supply/orchestration facts and are not persisted in Edition, Segment or Card. Publication freezes what was selected, not how the candidate window was traversed. No absoluteOrdinal, generation counter or global publication token is added.

## 13. Explicitly deferred behavior

After the minimal 3G gate, these still remain outside scope:

- Real MediaPreparation and asset storage.
- Canonical attribution enrichment and source/provider catalog lookup.
- External-action enrichment.
- Exposure and retention/GC, including draft pins.
- Global active Edition state.
- Session refresh swap and successor orchestration.
- Adaptive Runway and acquisition.
- Single-flight orchestration and automatic retry machinery.

PublicationCoordinator does not absorb any of these responsibilities merely because it needs a prepared payload.

## 14. Phase 3G implementation gate

The completed minimal 3G2 implementation includes in Publication:

- PublicationCardDraft.
- PublicationCoordinator with explicit create and append requests.
- A small semantic outcome/receipt.
- Positional candidate/draft/card-ID alignment validation and Selection revision validation.
- Deterministic semantic construction preserving order, IDs, timestamps, seeds and frozen schema.
- Text-only-capable prepared drafts without media infrastructure.

Persistence may add only a narrow mechanical Edition-tail read to PublicationStore if necessary. No schema change is authorized.

Tests must prove atomic Edition + Segment 0 creation, empty selection with zero writes, exact selection order, rejected draft/candidate mismatch and duplicate card IDs, next-tail append, rejected revision mismatch, stale concurrent tail refusal without renumbering, exact history after reopen, late future drafts unable to mutate earlier PublishedCards and text-only publication without media infrastructure.

Phase 3F is complete. Phase 3G1 bounded publication tail, Phase 3G2 immutable PublicationCoordinator and Phase 3G are complete. The hot append path uses an indexed tail row instead of scanning all retained Segments; full-history materialization still audits historical gaps. Tests prove exact create/append/reopen, empty and short supply, alignment refusal, late-collision rollback and unchanged earlier occurrences. Coordinator does not prepare media, perform canonical enrichment, retry or discover a global active Edition. Text-only is a valid prepared baseline; Runtime/Session still owns Edition visibility. Preparation, retention, exposure, session swaps, Runway and acquisition remain deferred.
