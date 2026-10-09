# Media and publication preparation architecture

## 1. Scope

Phase 3H closes the Media/publication preparation architecture gate after completed Phase 3G2. Phase 3H was design only. Phase 3I1 implemented canonical MediaCandidate facts, and Phase 3I2 implements durable local assets and image-container inspection. Phase 3I3 completes single-candidate local preparation and the pure Runtime publication-preparation value boundary. FeedSession/Runway orchestration and remote acquisition remain deferred. The first consumer is local visual card preparation, with text-only remaining independently publishable.

```text
OriginRevision + canonical MediaCandidate[]
→ MediaPreparation
→ prepared/local media facts
→ Runtime/orchestration combines SelectionResult,
  prepared media and other prepared presentation facts
→ PublicationCardDraft
→ PublicationCoordinator
```

> FeedMineMedia never publishes history.

> FeedMineMedia must not depend on FeedMinePublication.

> PublicationCoordinator never performs media preparation.

> The renderer never resolves remote media.

## 2. Existing module dependency constraint

Package.swift already declares FeedMinePublication → FeedMineMedia. FeedMineMedia currently depends on Domain and Persistence. Adding Media → Publication would create a cycle and is prohibited; the package graph must remain acyclic.

MediaPreparation returns Media-owned availability, suitability and durable local asset facts. It cannot return PublicationCardDraft, RenderContract, PublishedCard or PublicationReceipt. Runtime already depends on both Media and Publication and is the future orchestration owner that can combine their explicit values without adding a reverse dependency. No package change is needed for this design.

## 3. Legacy evidence: preserve/reject

Directed read-only review covered exactly these two files in `wsmontes/feedmine-dev`, branch `fix/release-1.0-final-hardening`, at commit `712a6ba93c6a8ab28c3b3c0e2b2777d1e3341d0c` (local ref matched the remote branch):

- `Packages/FeedRuntimeV2/Sources/FeedMedia/MediaPreparation.swift`.
- `Packages/FeedRuntimeV2/Tests/FeedMediaTests/MediaPreparationTests.swift`.

No legacy code was copied. Evidence and decisions:

| Evidence in the reviewed files | Preserve or reject |
| --- | --- |
| ContentDigest, MediaRecipeVersion and AssetVersionID derive identity from bytes and recipe; prepareCandidate hashes acquired bytes. Tests testCandidatePreparationDerivesIdentityFromDownloadedBytes and testAssetIdentityIsDigestPlusRecipeVersion distinguish byte identity from locator and recipe versions. | Preserve immutable prepared identity; a URL never becomes published asset identity. Do not freeze the legacy textual key format. |
| materializeLocal takes identity without URL, reads durable bytes and checks their digest. testLocalMaterializationReadsDurableBytesWithoutNetwork proves a fresh preparation instance reads local bytes with zero transport calls. | Preserve local durable bytes as sufficient input; omit cache and transport requirements from the first local slice. |
| ImageMetadata and ImageIODecoder inspect dimensions/MIME. testTheProductionDecoderReadsHeadersDecodesAndDownsamples and testAcceptedPayloadIsPublishedUnderItsDigestAndDownsampled exercise inspected facts. | Preserve measured asset metadata. Reject the hint-over-measurement behavior separately asserted by testTheMediaTypeHintWinsOverTheDecoderReport: upstream declarations must not masquerade as inspected MIME. |
| prepare/prepareCandidate call store.publish before returning the result; MediaAssetPublishing documents durable, atomic writes. The filesystem store writes a temporary file, syncs, renames and attempts directory sync; testTheFileSystemStoreIsContentAddressedIdempotentAndReclaimable checks local bytes, idempotence and no leftover temporary file. | Preserve durability-before-reference as a requirement, not a claim that these tests prove crash durability. The legacy directory-sync return value is ignored; future materialization must report required durability failure instead of emitting a usable reference. |
| MediaAssetDescriptor distinguishes descriptor identity from resident byte count; reclaim removes bytes. MediaAssetIdentity keeps dimensions for placeholders. | Preserve identity independently of byte residency; defer retention policy and do not adopt byteCount = 0 as a new public sentinel. |
| testNonImageRoleIsRefusedWithoutTouchingTheTransport rejects integral audio; testStalePreparationLeavesOnlyAQuotaBoundDownload asserts preparation pins nothing. The reviewed implementation imports no Publication module and returns PreparedMedia. | Preserve preparation separate from history. These files alone do not prove text-only publication, publication without integral audio/video, or late-media history immutability; those remain normative requirements supported by the current Publication boundary, not claimed legacy test coverage. |
| MediaPreparation owns HTTPTransport, budget, decoder, durable store, DecodedImageCache, EditorialClock and MediaWorkLimiter, with UnboundedMediaWorkLimiter as default. Deadline, timeout, limiter and cache behavior have dedicated tests. Corrupt local bytes are automatically refetched in testLocallyStoredBytesThatDoNotMatchTheirIdentityAreReplacedInsteadOfServed. | Reject the all-in-one baseline, first-slice HTTP transport, clock/deadline machinery, MediaWorkLimiter/default unbounded limiter, decoded cache, giant error taxonomy and automatic retry/refetch. Preserve refusal of corrupt bytes; future local preparation reports unavailable/corrupt instead of acquiring remotely. |
| materializeLocal describes a renderer-side recovery path, but deliberately has no URL/network. Neither reviewed file supplies a Publication coupling or general retry scheduler. | Preserve local-only presentation. Reject renderer-side remote recovery, Publication coupling and automatic retry as proposed baseline behaviors; do not attribute absent mechanisms to the reviewed files. |

Legacy evidence does not automatically become architecture. Publication can remain valid without integral audio/video bytes, and late media never rewrites prior publication; these are explicit boundaries here even where the two reviewed files do not establish them independently.

## 4. Canonical MediaCandidate semantics

MediaCandidate is a small immutable Domain semantic value describing an upstream media possibility tied to one exact OriginRevisionID. It is neither downloaded bytes, PublishedMediaRef nor published asset identity. Phase 3I1 implements this Domain value and its canonical Persistence boundary; local assets and preparation are complete through 3I2/3I3; resolver policy and remote acquisition remain deferred.

Identity decision: introduce a nominal MediaCandidateID for stable preparation-fact references independent of locator, and exact immutable replay/conflict checking. The admitting caller supplies the same identity on replay; identity is not generated by MediaPreparation, derived from a URL hash or recreated on every read. An ID identifies one candidate belonging to one revision and cannot be rebound to another revision. Locator/metadata changes under that ID conflict. A later upstream observation with different facts requires a new revision and its own candidate facts.

A tuple of locator/role/class would couple references to mutable remote location and duplicate declared facts in preparation associations. A positional tuple would require every consumer to use collection positions as identities. The nominal ID is chosen for these concrete immutable references, not for symmetry with other models; it adds no asset identity or protocol-specific ID.

| Candidate fact | First consumer and decision |
| --- | --- |
| mediaCandidateID | Stable exact reference for replay/conflict and future preparation results. |
| originRevisionID | Exact canonical ownership; never a live current-revision lookup. |
| role | Presentation purpose: baseline cardVisual, a possible visual for the card. This does not choose hero versus thumbnail. |
| mediaClass | Baseline image: what kind of bytes may be supplied. Distinct from presentation purpose; no audio/video capability is claimed. |
| remote locator | HTTP(S) URL locating possible bytes; future acquisition may use it, local preparation never fetches it. |
| declared mimeType? | Upstream type hint usable for candidate suitability, never authority over actual inspected MIME. |
| declared width/height? | Optional paired positive dimensions for preliminary visual suitability; absent means unknown and inspection remains authoritative. |
| declared duration? | Deferred: the baseline image consumer has no duration use. |

Keep role and class small, with only the visual/image baseline. Add further roles/classes through a consumer-driven gate, not a giant legacy enum or a generic extensibility registry. Canonical translation admits semantic values only: no connector JSON, RSS enclosure, ActivityPub attachment or protocol-specific types. Unsupported media capabilities are not advertised as prepared support.

## 5. Locator versus asset identity

> A remote locator tells FeedMine where bytes may be obtained. It is not the identity of prepared media.

The baseline locator is an HTTP(S) URL. It is not Origin identity and is not PublishedMediaKey. A URL hash cannot name immutable bytes: the same locator may serve different bytes. Candidate identity also does not claim byte identity. Non-HTTP acquisition requires a new architecture gate; no multiprotocol locator framework is proposed. Protocol-specific external representations never enter MediaPreparation.

## 6. Persistence/admission ownership

Canonical media facts belong to runtime.sqlite, the existing canonical authority. Phase 3I1 adds structured `media_candidates` linked to the exact OriginRevision, with candidate identity and the semantic fields above. Do not create a separate media/cache database, second canonical store, generic metadata blob or large SQLite media blobs.

ContentStore canonical changes require explicit `mediaCandidates` without a default and admit a revision and the complete translated candidate facts from the same accepted external observation in one transaction: both commit or neither commits. The complete ordered collection is an immutable revision-owned fact: [A, B] differs from [B, A], and identity remains independent of position. Admission rejects wrong-revision ownership and duplicate IDs. Same-ID factual comparison uses exact UTF-8 bytes for locator/MIME before whole-collection comparison. Identical replay leaves the collection unchanged; changed facts produce mediaCandidateConflict, and added/removed/replaced/reordered candidates produce mediaCandidateCollectionConflict, not incremental enrichment. An empty candidate collection is legitimate. Exact reads name OriginRevisionID and preserve the admitted facts without following a mutable current pointer.

Do not alter OriginRevision payload to add measured properties. Candidate rows remain immutable upstream declarations. Byte inspection or preparation availability never updates a candidate into an asset. New preparation facts are separate from revision admission. 3H was design only. 3I1 implements exactly one new migration, canonical-media-candidates-v1, after canonical-supply-v1, and one new table. Its revision FK has NO ACTION update/delete, ordinals are nonnegative and unique within each revision, and only the visual/image baseline and paired positive optional dimensions are admitted. The constraint autoindex serves ordered exact reads; no additional index is added. Revisions predating this migration have an immutable empty collection; nonempty replay conflicts. Public mediaCandidates(originRevisionID:) returns nil for missing revision, [] for admitted empty collection, or exact stored order in one read snapshot, validating contiguous ordinals, IDs, owner, locator, role/class and dimensions. There is no public candidate-ID or current-media lookup. This fifth canonical structured-semantic table has a concrete Media consumer; the four 3A tables remain the selection hot path and CandidateProvider performs no media join.

## 7. Preparation facts

A candidate fact says a remote possibility was declared, with role/class and optional upstream metadata. A preparation fact says explicitly supplied or already-local bytes were inspected, actual MIME/dimensions are known, a durable local representation exists, or this attempt found the candidate unavailable/unsuitable.

Phase 3I3 implements MediaPreparationResult with exact candidateID, originRevisionID and MediaPreparationState: usable(LocalImageAsset), unavailable or unsuitable. Its initializer remains internal; MediaPreparation produces results from a single explicit candidate and local input. Storage/integrity failures remain factual errors rather than states. No durable association, failure ledger or retry state is added. Missing local bytes do not invalidate canonical candidate facts. Declared dimensions and measured dimensions are separate; declared MIME never replaces inspected MIME. Values carried for publication describe the actual representation referenced by its key.

## 8. Local asset identity/durability

PublishedMediaKey remains a local opaque identity outside FeedMineMedia. Publication and downstream values never receive filesystem paths or remote URLs as media identity. Phase 3I2 freezes the first durable produced key format: `sha256:<64 lowercase hexadecimal characters>`. The SHA-256 authenticates the exact final stored bytes. Downstream continues to treat the key as opaque. There is no recipe version: future transformations that produce different bytes produce different keys, and identical final bytes share one key regardless of how they were produced. URLs, candidate IDs, filenames, MIME and dimensions do not participate in identity.

Phase 3I2 stores exact local bytes at `<assetRoot>/sha256/<digest>` after strict key parsing; raw key strings are never appended as paths. AssetStore is an internal concrete Sendable value owning only durable exact bytes. A temporary file in the destination directory is written and explicitly synced, then exclusively atomically installed and its containing directory synced before success. Failed required sync throws without returning a key. Temporary files are removed on failure where possible. A directory-sync failure may leave the destination physically present; a later explicit call authenticates and syncs it before returning the key. Same-content concurrent installers authenticate the winning destination and complete durability rather than overwriting it or creating another copy. Existing corrupt content is refused without replacement, deletion or repair. There is no actor/global mutex or automatic retry.

ImageMaterializer is a synchronous public concrete Sendable value. It inspects an image container before storage, requiring positive actual dimensions and measuring MIME through ImageIO/UTType when available; no full pixel decode is required. It passes the same bytes to AssetStore without resize, downsampling, transcoding, rotation, metadata stripping or recompression. LocalImageAsset returns only key, positive dimensions and optional actual MIME, never paths, decoded pixels or published presentation values. Each localAsset lookup reads exact local bytes, validates their digest and re-inspects image metadata; missing bytes return nil, and authentic non-image stored payload is corruption.

No SQLite asset metadata, sidecar JSON or manifest exists in this baseline. Key authenticates bytes; bytes supply actual MIME/dimensions; future PublishedCard freezes presentation metadata. Reopen requires only the content-addressed file, with no memory state. A future retention/query consumer must justify durable metadata in a new gate. Phase 3I2 adds no schema, cache, retention or network behavior. Phase 3I3 associates a candidate with an explicit prepared result; no durable association table or resolver policy is added.

> Publication may reference a local media key only after that asset identity is durably materialized enough to satisfy the published presentation contract.

Published identity and byte residency are separate. Future byte eviction does not rewrite PublishedCard or its key/layout metadata. Missing bytes lead to the deterministic local fallback provided by the frozen RenderContract; no renderer-side remote resolution is implied. Retention/eviction policy and alternate published representations are deferred.

## 9. MediaPreparation responsibility

MediaPreparation owns only candidate/local asset facts → availability, suitability and durable local media facts. It may inspect actual dimensions/MIME, determine candidate suitability, identify an immutable prepared asset and report whether a usable local representation exists. Phase 3I3 implements one explicit MediaCandidate per prepare call with MediaPreparationInput.bytes(Data), localAsset(PublishedMediaKey) or unavailable. Valid bytes produce usable actual assets; only invalidImage becomes unsuitable. Missing local bytes produce unavailable, and explicit unavailable returns immediately without filesystem work. Directory/write/install/sync/read/integrity/unsupported-key failures propagate unchanged. No network or decoded-image cache is needed; the candidate locator and declared facts remain untouched and inert.

It does not rank editorial content, reselect another editorial candidate, manage Edition lifecycle, generate PublishedCard identity, change session visibility or respond to runway demand. It does not publish history or construct Publication values. Local representation suitability is distinct from editorial selection and from choosing the card's final layout. No candidate collection, best-image choice or policy layer is introduced; MediaResolver/MediaPolicy remain deferred.

## 10. RenderContract/publication boundary

RenderContract remains a Publication-owned semantic value. Media supplies facts such as a prepared image and measured W×H; the caller explicitly chooses hero, thumbnail or textOnly, and the pure Runtime PublicationPreparation namespace constructs PublicationCardDraft values from explicit aligned inputs.

PublicationCardDraft belongs to Publication. Its assembly now belongs to Runtime PublicationPreparation.drafts(selection:inputs:), combining SelectionResult with positional PublicationPreparationInput values carrying frozen origin/attribution, optional entity/cluster, primary action and explicit PublicationPresentation. This is a stateless semantic namespace, not a builder/factory/protocol service. Neither SelectionEngine, MediaPreparation nor PublicationCoordinator fills those gaps. No PublicationDraftBuilder service, DraftFactory hierarchy or cross-module construction protocol is proposed for a single future consumer.

PublicationCoordinator validates alignment and freezes already-prepared values through its existing atomic history boundary. It never calls MediaPreparation or resolves media; prepared inputs do not let Runtime construct or persist history directly. Publication identities/times/seeds remain explicit caller inputs to the Coordinator. Runtime preparation requires exact count and positional origin record/revision/provider alignment, preserves exact Selection text including nil/empty and UTF-8 semantics, maps authored/observed timestamps without changing their Date, and preserves Selection order without sort/dedupe/refill. It performs no DB/canonical lookup or publication execution.

## 11. Network ownership

First local MediaPreparation requires network: NO. Explicitly supplied bytes and already-local assets are sufficient for the first implementation; remote locators are inert canonical facts on that path. Missing/corrupt local assets report unavailability instead of automatically downloading or refetching.

> MediaPreparation must not become a parallel AcquisitionPlanner.

Future remote media acquisition shares Runtime supply/resource/network orchestration. No second acquisition engine, media frontier, HTTP transport, retry/redirect policy, per-host limiter, periodic fetching or background media scheduler is proposed here. Cancellation/resource policy belongs with future async orchestration; no deadline Date, timeout, retryAfter or periodic refresh baseline is introduced for local preparation.

The first implementation works without a decoded cache. Any future cache requires measured repeated work, a clear owner and bounded eviction policy.

> Feed scrolling never triggers media network acquisition directly.

## 12. Text-only and failure semantics

When presentation policy permits, media = none and render = text-only is a first-class prepared result. Unavailable, unsuitable or failed media materialization does not automatically make otherwise valid content impossible to publish. The caller chooses the representation explicitly before pure Runtime draft assembly; the Coordinator never invents a fallback. textOnly requires no MediaPreparationResult or filesystem work and emits media none with a textOnly/nil-ratio contract. Image choice accepts only usable preparation for the exact selected revision with explicit hero/thumbnail layout; unavailable/unsuitable, mismatched revision and image + textOnly layout are typed errors, never silent text-only fallback. Runtime builds PublishedMediaRef and aspect ratio from actual prepared asset dimensions/MIME, never declared candidate hints.

> Media improves future presentation; it does not own the existence of feed history.

> Media work may improve future cards, but it must never make already-published cards unstable.

> A card that is already locally presentable must not wait on speculative remote media merely to become publishable.

File failure cannot yield a false asset reference; text-only remains an alternative when policy allows it. Publication may remain valid without integral audio/video bytes. Media arriving later can improve only a future PublishedCard occurrence in another Edition, according to its editorial policy; no prior draft commit, published key, layout, text or history is rewritten. Local fallback after loss of resident bytes follows the existing frozen presentation contract.

## 13. Explicitly deferred behavior

- Remote media acquisition and HTTP implementation.
- Media retries, redirect policy and per-host budgets.
- Background media scheduler and media frontier.
- Decoded image cache.
- Retention/asset eviction policy.
- Audio/video download policy and non-image preparation capabilities.
- Alternate published representations.
- Sophisticated layout policy.
- SwiftUI materialization.
- Adaptive runway integration.
- Timer/deadline machinery and future async cancellation/resource orchestration.

## 14. Implementation gates 3I1/3I2/3I3

Keep three distinct gates; ownership separation is more valuable than reducing commit count. 3I1, 3I2 and 3I3 are complete below. Later macro-phase work requires separate authorization.

**3I1 — canonical MediaCandidate facts.** Completed in Phase 3I1: the minimal Domain value and nominal candidate identity from §4, a structured revision-linked Persistence schema, atomic ContentStore admission with the owning OriginRevision and exact ordered reads by revision. Tests prove identical replay, changed-fact/collection conflicts, exact historical ownership, empty and pre-media revision collections, corruption rejection and transaction rollback of revision + candidates on failure after reopen. No assets or network.

**3I2 — durable content-addressed local assets — complete.** AssetStore implements final-byte SHA-256 identity, exact-byte file storage, strict persistent key parsing, file sync, exclusive atomic installation and directory sync. ImageMaterializer implements pre-store container inspection and authenticated local re-inspection, returning LocalImageAsset. Tests prove the known abc digest/key, same/different content identity, idempotency and concurrent installation, deterministic file/directory-sync failure, corrupt/unsupported keys, exact reopen, measured PNG metadata and rejected non-image input. No metadata table, transformation, HTTP, retries, cache or retention policy.

**3I3 — local preparation + publication preparation integration — complete.** MediaPreparation prepares one explicitly supplied candidate/local input into Media-owned usable/unavailable/unsuitable facts, propagating storage/integrity errors. Pure Runtime PublicationPreparation assembles aligned ordered drafts using exact Selection text/time, explicit presentation and actual prepared image metadata. Tests prove text-only without media work, positional count/origin/revision/provider validation, no fallback, hero/thumbnail actual ratio and a later local-media occurrence in another Edition that leaves the earlier text-only publication unchanged after reopen. PublicationCoordinator remains sole history producer. MediaResolver/MediaPolicy, FeedSession/Runway integration, remote acquisition, UI loading and retention remain deferred.

Phase 3H — complete (design only). Phase 3I1 — canonical MediaCandidate facts — complete. Phase 3I2 — durable content-addressed local assets — complete. Phase 3I3 — local preparation + publication preparation integration — complete. Phase 3I — complete. Network, resolver policy and FeedSession/Runway integration remain deferred.


### Phase 3R5 product boundary

Late media may update canonical resources and future preparation. It never changes a published card, its key, revision, layout or position, and never creates a second occurrence of that origin in the same Edition. A later Edition may publish the origin with newly available media or enrichment. No new Edition is automatically created to display late media, and the Media pipeline is unchanged.
