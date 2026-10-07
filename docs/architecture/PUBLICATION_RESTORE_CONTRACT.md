# Publication identity and exact restore contract — Phase 2B

## 1. Purpose

This contract partially closes the former ADR-001: the minimum identity and in-memory structure needed to restore exactly a retained local published history and a logical position within it. Phase 2B is semantic-before-storage. It implements no SQL, stores or restore execution.

The restorable unit is published history, not canonical supply, Selection, pixels or an endpoint.

## 2. Identity hierarchy

```text
EditorialRevision
        ↓
FeedEditionID
        ↓
FeedSegmentID + ordinal
        ↓
PublicationCardID
        ↓
SessionCursor anchor
```

- EditorialRevision = rules.
- FeedEdition = concrete history produced under those rules.
- FeedSegment = immutable append unit.
- PublicationCardID = stable published occurrence.
- SessionCursor = logical position in retained history.

FeedEditionID, FeedSegmentID and PublicationCardID are independent FeedMine-owned UUID-backed nominal IDs. They live in FeedMineDomain because they cross Publication, Runtime, future persistence commands, exposure and presentation identity boundaries. Domain owns only nominal identity; Publication owns Edition/Segment/Card meaning. No SessionID is needed for this restore contract.

## 3. FeedEdition semantics

FeedEdition represents a concrete editorial history produced under an EditorialRevision. Its immutable metadata contains id, editorialRevision, publicationSchemaVersion, selectionSeed and createdAt. contextKey is derived exclusively from editorialRevision.contextKey; it is never duplicated as stored state.

Two Editions may share the same EditorialRevision and remain distinct. Explicit refresh may produce E11 under the same R4 as E10: rules are not the concrete history.

Edition metadata contains no mutable segments/cards collection, tail, active/superseded flags or successor reference. History grows conceptually through external append of Segments. Lifecycle and aggregate facts remain future responsibilities. No Edition reason enum is frozen here.

PublicationSchemaVersion identifies the persisted semantic publication format. It is distinct from SelectionSchemaVersion, EditorialRevision and database migration version. It is an explicit UInt64 value ordered by rawValue, without current/latest/supported/migration policy.

## 4. FeedSegment semantics

FeedSegment is an immutable ordered append unit with id, editionID, ordinal, segmentSeed, publicationSchemaVersion, createdAt and ordered cardIDs.

Its failable initializer rejects an empty cardIDs array and duplicate PublicationCardIDs within the Segment. It preserves supplied order exactly, without sorting or automatic deduplication. The isolated Segment does not validate duplicates across Segments or ordinal continuity: a future aggregate/coordinator/storage transaction must validate append.

A future valid append requires segment.publicationSchemaVersion == edition.publicationSchemaVersion. Storage/coordinator must reject inconsistency; no such coordinator exists in this phase.

After publication commit, Segment ordering cannot change, a PublicationCardID cannot be reassigned, and a historical card occurrence cannot point to a newer OriginRevision. Upstream mutation may affect future publication, never previous publication.

## 5. PublicationCard identity

PublicationCardID identifies a stable published occurrence. It is not OriginRecordID, OriginRevisionID, ContentEntityID or ContentClusterID. The same OriginRevision may appear in different Editions or theoretically multiple published occurrences with distinct PublicationCardIDs. Exposure attaches to the published occurrence.

Phase 2B proves Edition → ordered Segments → ordered PublicationCardIDs → Cursor. It left PublishedCard as a scaffold rather than introducing a temporary card model. Phase 2C now closes the self-contained baseline below; interaction summary remains explicitly deferred.

## 6. SessionCursor and logical anchoring

SessionCursor is immutable editionID + FeedWindowAnchor. The anchor is PublicationCardID + AnchorPlacement, with exactly top and center cases. It answers which history, which card and how the card should be relatively positioned.

The cursor is a persistible logical position inside published history. It stores no scrollOffset, pixelOffset, contentOffset, cardHeight, screenY or percentageScrolled. It is not an OriginRevision position, database row offset or RSS item index.

## 7. Exact restore

While the Edition and card anchor still exist, restore(SessionCursor) means the same FeedEditionID, same PublicationCardID and same logical surrounding history, with the same published ordering.

It does not rerun Selection, find similar content, find the nearest timestamp or jump to the current version of an OriginRecord. Warm/offline first presentation follows the restore-first contract in PERSISTENCE_DESIGN.md and needs no network/catalog/acquisition. Retention fallback and restore execution are not implemented here.

## 8. Refresh and successor Editions

```text
E10 remains visible
        ↓
future work
        ↓
successor E11 becomes sufficiently publishable
        ↓
explicit swap E10 → E11
```

Refresh does not mutate E10. E11 may share E10's EditorialRevision. If successor production fails, E10 continues unchanged: do not empty the feed or transform E10 into partial E11. Refresh execution and publishability policy remain deferred.

## 9. Render-environment independence

Changes in Dynamic Type, screen width, render environment, local image availability or SwiftUI tree do not modify FeedEditionID, PublicationCardID or SessionCursor. Layout may rematerialize around the same anchor. Visual geometry can change; editorial history cannot.

## 10. Persistence implications

Future mechanical storage must represent Edition metadata; Segment metadata including edition, ordinal, seed and schema version; ordered card occurrence identity; and SessionCursor containing EditionID, PublicationCardID and placement.

No table names, columns, foreign keys or indexes are defined here. Phase 2C closes the baseline semantic PublishedCard payload. After review and merge, publication/session relational schema design may begin. PublicationStore and SessionStore remain scaffolds and runtime migrations remain unchanged.

Nominal IDs retain their existing Codable convention. Publication semantic aggregates and PublicationSchemaVersion are not Codable blobs; persistence will use an explicit mechanical representation.

## 11. Phase 2B handoff and remaining deferred publication semantics

The Phase 2B handoff identified the following payload concepts for Phase 2C:

- PublishedOrigin.
- PublishedText.
- PublishedTimestamp.
- PublishedMediaSet.
- PublishedMediaRef.
- RenderContract concrete form.
- FeedPrimaryAction.
- PublishedInteractionSummary.
- Final PublishedCard frozen payload.

Phase 2C closes the baseline described below. PublishedInteractionSummary is explicitly deferred because counts are not required by the first restore/read flow; future UI requirements may evolve PublicationSchemaVersion.

FeedWindow remains a scaffold for a finite projection over potentially large published history; window materialization belongs to a future Runtime/session slice even with the card baseline available. Phase 2C implements RenderContract values only. PublicationCoordinator remains unchanged. Append, single-flight, PublicationToken, persistence calls, Runtime session behavior and restore execution remain unimplemented.

## 12. Acceptance invariants

- Publication IDs are independent UUID-backed nominal identities crossing module boundaries.
- Edition context derives from EditorialRevision, with immutable metadata and no mutable segment collection.
- Editions sharing a revision may have distinct identities.
- A Segment is nonempty, rejects duplicate occurrence IDs and preserves exact supplied order.
- Cross-Segment uniqueness, append continuity and schema-version consistency require a future aggregate/storage authority.
- Cursor points to Edition + published card occurrence + top/center placement, without pixels.
- Retained history restores exactly; render changes preserve history identity.
- Refresh creates a successor and preserves the visible predecessor on failure.
- No PublishedCard payload, window, coordinator behavior, SQL or store implementation begins in Phase 2B.

## 13. Frozen PublishedCard baseline

Phase 2C implements the smallest self-contained semantic snapshot needed for local deterministic presentation after canonical eviction. PublishedCard is not a live OriginRevision projection, database row, FeedItem DTO, rendered image, SwiftUI model or connector object. Every field serves restore/presentation behavior; no legacy serialization, digest machinery or metadata dictionary is copied.

### What survives canonical eviction

PublishedOrigin stores required OriginRecordID and OriginRevisionID as historical provenance, separate optional SourceID/ProviderID and exact optional frozen source/provider display names. Source is an editorial unit; Provider is attribution/producer. Catalog or provider renames do not rewrite attribution: a card published as "Example News" retains that value after a rename to "Example Media".

PublishedText preserves the selected optional title and primaryText exactly, without trimming, sanitizing or normalization. Either or both may be absent; the baseline does not assume article/RSS content. Optional PublishedTimestamp carries a Date and explicit authored/modified/observed meaning. An observed date never becomes a fabricated authored date.

The card also retains optional ContentEntityID/ContentClusterID, media reference, RenderContract and optional primary action. It needs no mandatory join to OriginRevision, Source, Provider, raw connector payload or canonical search projection. Later upstream updates, catalog changes and canonical eviction do not alter the snapshot. Two cards may share origin/revision and payload while having distinct PublicationCardIDs; exposure/history follow the occurrence ID.

### Media reference and asset eviction fallback

PublishedMediaKey is an opaque stable local asset identity understood by FeedMineMedia. It rejects only an empty string and interprets no format. It is neither a filesystem path nor a remote URL. Future AssetStore resolves PublishedMediaKey → local bytes/materialization; generation and resolution remain unimplemented.

PublishedMediaRef contains key, optional pixelWidth/pixelHeight and optional mimeType. Dimensions must both be absent or both positive; partial, zero or negative dimensions are rejected. aspectRatio is derived, never duplicated. PublishedMediaSet contains only an optional primary reference, with .none for absence. No alternates, poster, waveform or responsive variants are added.

A reference can survive byte eviction without destroying the card:

```text
asset resolves → show local asset
asset missing → deterministic placeholder using RenderContract
no media slot → text-only
```

Scroll/render requires no network or permanent byte retention. Hero/thumbnail with absent or unresolvable primary media uses a deterministic local placeholder. PublicationCardID supplies stable occurrence identity and RenderContract preserves slot geometry; no separate placeholder identity/model is needed. A placeholder-only card is publication-ready without later download. Future policy may permit asset filling without breaking history/layout; healing is not implemented here.

### Render contract semantics

PublishedCardLayout has exactly hero, thumbnail and textOnly. RenderContract freezes layout and optional mediaAspectRatio; a supplied ratio must be finite and positive. textOnly requires a nil ratio. Hero/thumbnail may use a nil ratio, meaning the future renderer's deterministic default for that layout.

RenderContract freezes editorial/presentation slot structure, not RenderEnvironment. Screen width, Dynamic Type, device, orientation, pixel height and color scheme remain outside it. Slot/crop geometry may differ from the source asset aspect ratio; no equality constraint or crop model is added.

PublishedCard rejects textOnly with primary media. It accepts hero/thumbnail with or without primary media and textOnly with none. There is no title, text, timestamp, link or image requirement, and no URL/image is synthesized.

### Baseline primary actions

PublishedPrimaryAction has exactly externalURL(URL), mediaPlayback(URL) and localContentDetail. External URL opens the frozen external target. Media playback is an explicit user-initiated target and may use network: explicit interaction may use network; scroll/render may not. Local detail opens this same PublishedCard and does not repeat its ID.

An action URL is a target, not PublicationCard identity. Future URL changes or failure do not destroy the card. The action is optional; these values implement no interaction or network execution.

### Immutability, storage and explicitly deferred interactions

All snapshot fields are let. There are no update/heal/refresh methods, live lookups or retrospective OriginRevision replacement. Edition/Segment IDs, ordinals, EditorialRevision and PublicationSchemaVersion are not duplicated in the card; ordered occurrence relations own those facts. Origin IDs exist only in card.origin.

No Codable blob contract is introduced for card, origin, text, timestamp, media, RenderContract or action. Future persistence will design an explicit relational representation only after review and merge.

PublishedInteractionSummary, reply/repost/reaction counts, connector write actions, ActionID, InteractionHandle and generic metadata remain deferred until concrete consumers require them. FeedWindow, PublicationCoordinator, Selection/MediaPreparation execution, AssetStore, SQL, stores and restore execution remain unimplemented.
