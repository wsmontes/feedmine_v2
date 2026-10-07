# Publication and session relational schema — Phase 2D

## 1. Scope

Design only, grounded in the approved Phase 2B identity/restore contract and Phase 2C frozen card baseline. Exactly four domain tables are proposed in runtime.sqlite: feed_editions, feed_segments, published_cards and session_checkpoint. Existing GRDB migration bookkeeping is not a domain table.

The DDL and queries below are review artifacts, not installed migrations or executable production SQL. Sources, tests, package graph and stores remain unchanged. No SQL is executed in this phase.

This baseline preserves retained published history without canonical supply, catalog, network, Selection, Acquisition or remote image fetch. It does not promise permanent history or asset retention.

## 2. Restore-first acceptance scenario

```text
published Edition exists
        ↓
user anchored on card P
        ↓
session checkpoint persisted
        ↓
process terminates; network unavailable
        ↓
runtime.sqlite opens
        ↓
checkpoint restored; same Edition loaded
        ↓
same card occurrence located
        ↓
finite local window materialized around P
        ↓
same published order
```

The first implementation acceptance test must create E1 atomically with S0 containing P0, P1, P2; append S1 containing P3, P4, P5; save checkpoint E1/P4/center; destroy all in-memory objects; close and reopen the database without network, canonical rows or catalog. Load the checkpoint and reconstruct a bounded ordered window around P4. With caller capacities covering this fixture, assert E1, P4, center, P0…P5 in published order and exact frozen text, attribution, timestamps, layout, action and media metadata. Smaller capacities must produce the corresponding bounded neighborhood, not a new editorial selection.

The acceptance proves logical history/anchor restoration, not identical pixels. Missing media bytes use the card's local placeholder contract.

## 3. Schema graph

```text
feed_editions ← feed_segments ← published_cards
      ↑                              ↑
      └──────── session_checkpoint ──┘
```

All arrows are child-to-parent foreign keys with ON DELETE RESTRICT. A card occurrence belongs to exactly one Segment. published_cards.segment_id plus ordinal represents ordered membership directly; no segment_cards join table is needed. Global ordering derives from (segment.ordinal, card.ordinal), without an absolute_ordinal, duplicated tail or card count.

| Table | Authority | Mutable? | Required for warm restore | Reconstructible? |
| --- | --- | --- | --- | --- |
| feed_editions | Publication history | append/create only | YES | NO while retained |
| feed_segments | Publication history | append only | YES | NO while retained |
| published_cards | Publication history | immutable | YES | NO while retained |
| session_checkpoint | Current restore position | replaceable checkpoint | YES | rebuildable only from active session, not after process death |

History immutability is a store API contract, not an UPDATE-blocking trigger. Explicit retention may eventually delete history in a controlled transaction.

## 4. feed_editions

```sql
CREATE TABLE feed_editions (
    id TEXT PRIMARY KEY NOT NULL,
    editorial_revision_id TEXT NOT NULL,
    context_kind TEXT NOT NULL,
    context_source_id TEXT,
    context_search_query TEXT,
    catalog_generation INTEGER NOT NULL,
    user_selection_version INTEGER NOT NULL,
    eligibility_policy_version INTEGER NOT NULL,
    scoring_policy_version INTEGER NOT NULL,
    sequencing_policy_version INTEGER NOT NULL,
    exposure_policy_version INTEGER NOT NULL,
    selection_schema_version INTEGER NOT NULL,
    publication_schema_version INTEGER NOT NULL,
    selection_seed INTEGER NOT NULL,
    created_at REAL NOT NULL,
    CHECK (
        (context_kind = 'main'
            AND context_source_id IS NULL AND context_search_query IS NULL)
        OR (context_kind = 'source'
            AND context_source_id IS NOT NULL AND context_search_query IS NULL)
        OR (context_kind = 'search'
            AND context_source_id IS NULL AND context_search_query IS NOT NULL)
    ),
    CHECK (catalog_generation >= 0),
    CHECK (user_selection_version >= 0),
    CHECK (eligibility_policy_version >= 0),
    CHECK (scoring_policy_version >= 0),
    CHECK (sequencing_policy_version >= 0),
    CHECK (exposure_policy_version >= 0),
    CHECK (selection_schema_version >= 0),
    CHECK (publication_schema_version >= 0)
);
```

Edition metadata includes a flattened EditorialRevision snapshot. These few rule fields may repeat across distinct Editions under the same revision; this avoids another aggregate, join, repository and retention dependency. This is a baseline decision, not a universal normalization rule. Reusing a revision ID with conflicting rule values is invalid; future write mapping must preserve the supplied immutable revision rather than silently reconcile it.

There is no editorial_revisions table or serialized context_key column. Context is represented once within the flattened revision using kind/source/query. The read mapper reconstructs FeedContextRequest and then ContextKey with canonical constructors. For search it must use SearchContext(query:) and preserve the exact original query; blank/whitespace-only queries are invalid. Source contexts preserve the original SourceID without catalog lookup.

## 5. feed_segments

```sql
CREATE TABLE feed_segments (
    id TEXT PRIMARY KEY NOT NULL,
    edition_id TEXT NOT NULL,
    ordinal INTEGER NOT NULL,
    segment_seed INTEGER NOT NULL,
    publication_schema_version INTEGER NOT NULL,
    created_at REAL NOT NULL,
    FOREIGN KEY (edition_id) REFERENCES feed_editions(id) ON DELETE RESTRICT,
    UNIQUE (edition_id, ordinal),
    CHECK (ordinal >= 0),
    CHECK (publication_schema_version >= 0)
);
```

Segment metadata is immutable. card_count is derived. SQL does not enforce nonempty membership or ordinal continuity by trigger. PublicationStore must commit Segment plus all cards together and reject empty Segments. Initial Segment ordinal is 0; subsequent normal appends use checked current maximum + 1. Every Segment's schema version must equal its Edition's version, validated within the write transaction.

## 6. published_cards

```sql
CREATE TABLE published_cards (
    id TEXT PRIMARY KEY NOT NULL,
    segment_id TEXT NOT NULL,
    ordinal INTEGER NOT NULL,
    origin_record_id TEXT NOT NULL,
    origin_revision_id TEXT NOT NULL,
    source_id TEXT,
    provider_id TEXT,
    source_display_name TEXT,
    provider_display_name TEXT,
    content_entity_id TEXT,
    content_cluster_id TEXT,
    title TEXT,
    primary_text TEXT,
    timestamp_value REAL,
    timestamp_kind TEXT,
    media_key TEXT,
    media_pixel_width INTEGER,
    media_pixel_height INTEGER,
    media_mime_type TEXT,
    render_layout TEXT NOT NULL,
    render_media_aspect_ratio REAL,
    primary_action_kind TEXT,
    primary_action_reference TEXT,
    FOREIGN KEY (segment_id) REFERENCES feed_segments(id) ON DELETE RESTRICT,
    UNIQUE (segment_id, ordinal),
    CHECK (ordinal >= 0),
    CHECK (
        (timestamp_value IS NULL AND timestamp_kind IS NULL)
        OR (timestamp_value IS NOT NULL AND timestamp_kind IS NOT NULL
            AND timestamp_kind IN ('authored', 'modified', 'observed'))
    ),
    CHECK (
        (media_key IS NULL AND media_pixel_width IS NULL
            AND media_pixel_height IS NULL AND media_mime_type IS NULL)
        OR (media_key IS NOT NULL AND media_key != ''
            AND (
                (media_pixel_width IS NULL AND media_pixel_height IS NULL)
                OR (media_pixel_width IS NOT NULL AND media_pixel_height IS NOT NULL
                    AND media_pixel_width > 0 AND media_pixel_height > 0)
            ))
    ),
    CHECK (render_layout IN ('hero', 'thumbnail', 'textOnly')),
    CHECK (render_media_aspect_ratio IS NULL OR render_media_aspect_ratio > 0),
    CHECK (render_layout != 'textOnly'
        OR (media_key IS NULL AND render_media_aspect_ratio IS NULL)),
    CHECK (
        (primary_action_kind IS NULL AND primary_action_reference IS NULL)
        OR (primary_action_kind IS NOT NULL
            AND primary_action_kind = 'localContentDetail'
            AND primary_action_reference IS NULL)
        OR (primary_action_kind IS NOT NULL
            AND primary_action_kind IN ('externalURL', 'mediaPlayback')
            AND primary_action_reference IS NOT NULL)
    )
);
```

This row freezes the Phase 2C payload and membership position. Its global primary key prevents reuse of an occurrence ID across Segments or Editions. The same origin/revision may appear with distinct card IDs; no uniqueness is imposed on provenance IDs.

Origin/revision/source/provider/entity/cluster IDs have no canonical/catalog foreign keys. They are historical provenance, not lifecycle dependencies. catalog.sqlite is physically separate. Frozen attribution names are owned values, never reconstructed by live join. Optional names need not depend on presence of attribution IDs. Title/primary text remain exact nullable values; there is no published_text table, normalization or title requirement.

One optional primary media reference is flattened in this row; no media/asset table is needed. media_key is opaque TEXT, not path, URL, row ID or FK. A whitespace-only key remains valid; only the empty string is rejected. Byte absence does not change the row or destroy the card. The future AssetStore handles resolution; missing bytes fall back to RenderContract geometry.

Render ratio must additionally be finite in both write and read mapping; the positive SQL CHECK alone does not reject positive infinity. Slot geometry may differ from asset dimensions. Hero/thumbnail allow no media and nil ratio (deterministic renderer default); textOnly allows neither primary media nor ratio. No placeholder identity or rendering execution is stored.

## 7. session_checkpoint

```sql
CREATE TABLE session_checkpoint (
    singleton_id INTEGER PRIMARY KEY CHECK (singleton_id = 1),
    edition_id TEXT NOT NULL,
    card_id TEXT NOT NULL,
    anchor_placement TEXT NOT NULL,
    updated_at REAL NOT NULL,
    FOREIGN KEY (edition_id) REFERENCES feed_editions(id) ON DELETE RESTRICT,
    FOREIGN KEY (card_id) REFERENCES published_cards(id) ON DELETE RESTRICT,
    CHECK (anchor_placement IN ('top', 'center'))
);
```

The singleton key is always explicitly written as 1. This is a checkpoint slot, not an integer surrogate for a UUID-backed entity. Zero rows means no saved visible checkpoint; at most one row represents the current persisted SessionCursor. It has no SessionID, multi-session framework, context fields, Segment ID, ordinals or pixels. updated_at is checkpoint-write metadata supplied by the future caller, not an authored-content date or a fallback for missing stored time.

Independent FKs do not prove card membership in the referenced Edition. SessionStore must verify card → Segment → Edition inside checkpoint-write transaction and again during restore. A mismatch is corruption on read or an invalid checkpoint write, never a trigger-driven approximation.

## 8. Representation mappings

| Semantic value | Mechanical representation | Write/read rule |
| --- | --- | --- |
| UUID-backed Domain IDs | TEXT | Write rawValue.uuidString.lowercased(); read canonical lowercase hyphenated UUID text and reconstruct nominal ID. Reject malformed/noncanonical persisted text. No UUID BLOBs or integer surrogates. |
| ContextKey | kind + optional source/query | main/source/search discriminant, exact query, canonical FeedContextRequest → ContextKey constructors; no JSON/hash/custom context serialization. |
| CatalogGeneration, PolicyVersion, SelectionSchemaVersion, PublicationSchemaVersion, Segment/card ordinals | INTEGER | Checked UInt64 → nonnegative Int64; above Int64.max is a storage representation error. On read reject negative, noninteger or out-of-range values. Never truncate/overflow. |
| selectionSeed, segmentSeed | INTEGER | Write Int64(bitPattern: seed); read UInt64(bitPattern: stored). All 64 bits preserved; negative stored values are valid seeds, not ordering. |
| createdAt, timestamp.value, updatedAt | REAL | Date.timeIntervalSince1970; reconstruct Date(timeIntervalSince1970:). Require finite representable values; preserve optional absence. No strings, timezone conversion, integer-second rounding or Date() fallback. |
| PublishedText / attribution | nullable TEXT | Preserve exact values and NULL, including empty strings; no normalization or joins. |
| PublishedTimestamp | nullable value + kind pair | Both absent, or finite Date value plus authored/modified/observed; no fabricated authorship. |
| PublishedMediaSet.primary | nullable flattened reference group | No key means every media column NULL. Otherwise nonempty opaque key, paired absent/positive dimensions and optional exact MIME. Checked Int ↔ Int64 mapping for dimensions. |
| RenderContract | layout + optional REAL ratio | Known layout; nil or finite positive ratio; textOnly excludes ratio/media. Reconstruct through its failable initializer. |
| PublishedPrimaryAction | nullable kind + reference | nil → NULL/NULL; localContentDetail → kind/NULL; externalURL or mediaPlayback → kind/URL.absoluteString. |
| SessionCursor | EditionID + PublicationCardID + placement | Reconstruct via Publication's anchor/cursor values after membership validation; no pixel or duplicate position/context state. |

Action read mapping must reject unknown kinds, inconsistent NULL groups and unparsable URL references. Parse the exact stored string using Foundation URL without inventing a base URL; do not impose new scheme/host requirements beyond the approved semantic URL value. Failed reconstruction is corruption, not a silently dropped action. A future URL target becoming unavailable is different from malformed stored representation and does not erase the card.

Validate SQLite storage classes and checked scalar conversions; affinity alone is not an assurance of correct persisted types. REAL fields may be returned as finite numeric values by SQLite, but TEXT-coercion fallback is forbidden. Unknown enum strings are never converted to nil/defaults. Nonfinite numbers, invalid UUIDs, blank search query, invalid dimensions or empty media key must fail typed validation. SQL constraints complement, rather than replace, mechanical read validation and semantic constructor validation.

## 9. Constraints and foreign keys

The only foreign keys are Segment → Edition, card → Segment, checkpoint → Edition and checkpoint → card, all RESTRICT. Foreign-key enforcement must remain enabled on runtime connections, as established in Phase 2A. There is no CASCADE. Explicit retention must consciously move/remove a checkpoint before deleting protected history, then delete cards, Segments and Edition in dependency order in one transaction. No history parent deletion silently removes children.

The persisted checkpoint is a retention root; its Edition and anchor are protected, and the Edition's immutable surrounding history must remain coherent while retained. FK restrictions are a destruction guard, not a full retention policy. Retention must not treat non-anchor cards as expendable independently inside a retained Edition.

SQL guarantees referential existence, ID/position uniqueness, nonnegative ordinals/versions and specified local nullable-group/layout checks. Future stores additionally guarantee nonempty Segment, contiguous positions, matching Edition/Segment schema versions, same-Edition checkpoint membership, immutable payloads and numeric/string representation validity. No triggers are introduced.

The candidate optional-group CHECKs deliberately include explicit IS NOT NULL guards. SQLite accepts a CHECK whose result is NULL; without these guards a missing timestamp kind, partial dimensions or missing action kind can escape rejection. The direct empty-string comparison enforces the frozen nonempty-key invariant without trimming or interpreting key contents. See [SQLite CREATE TABLE: CHECK constraints](https://www.sqlite.org/lang_createtable.html). Finite ratios remain mapper/semantic-constructor checks.

## 10. Minimal indexes

Only primary-key/unique constraint structures are proposed:

| Table | Required structures |
| --- | --- |
| feed_editions | PRIMARY KEY(id) |
| feed_segments | PRIMARY KEY(id); UNIQUE(edition_id, ordinal) |
| published_cards | PRIMARY KEY(id); UNIQUE(segment_id, ordinal) |
| session_checkpoint | PRIMARY KEY(singleton_id) |

No speculative origin/revision/source/provider/timestamp index, duplicate index or denormalized global position is introduced. Primary keys locate exact records; unique compound keys support Edition Segment traversal and ordered cards within a Segment. Future concrete query plans may justify additional indexes after measurement, without changing this baseline.

## 11. Window query shapes

All parameters are bound. Read checkpoint, Edition, anchor and both neighborhoods within one consistent read snapshot; do not mix reads across retention/checkpoint transactions. Validate nonnegative bounded caller capacities before executing LIMIT; a negative SQLite LIMIT must never become an unbounded request. Persistence chooses no page/card count. Capacities are materialization bounds supplied by Runtime/future FeedWindow materializer, not conceptual feed size.

Locate and verify the anchor:

```sql
SELECT c.segment_id, c.ordinal AS card_ordinal,
       s.ordinal AS segment_ordinal, s.edition_id
FROM published_cards AS c
JOIN feed_segments AS s ON s.id = c.segment_id
WHERE c.id = :card_id AND s.edition_id = :edition_id;
```

No row for a persisted checkpoint is corruption, not a nearest-card search. Anchor payload is read by its exact ID and included once.

Forward neighborhood:

```sql
SELECT c.*, s.ordinal AS segment_ordinal
FROM feed_segments AS s
JOIN published_cards AS c ON c.segment_id = s.id
WHERE s.edition_id = :edition_id
  AND (s.ordinal, c.ordinal) > (:anchor_segment_ordinal, :anchor_card_ordinal)
ORDER BY s.ordinal ASC, c.ordinal ASC
LIMIT :forward_capacity;
```

Backward neighborhood:

```sql
SELECT c.*, s.ordinal AS segment_ordinal
FROM feed_segments AS s
JOIN published_cards AS c ON c.segment_id = s.id
WHERE s.edition_id = :edition_id
  AND (s.ordinal, c.ordinal) < (:anchor_segment_ordinal, :anchor_card_ordinal)
ORDER BY s.ordinal DESC, c.ordinal DESC
LIMIT :backward_capacity;
```

Reverse the backward result, then concatenate backward + anchor + forward. Strict comparisons exclude the anchor from neighbors. Capacity 0 gives no rows on that side. Total materialization is bounded by backward capacity + 1 + forward capacity; missing neighbors at history boundaries do not fabricate content. Placement top/center is preserved for future presentation; it does not alter history order. No OFFSET or absolute ordinal is used.

Exact card lookup requires only published_cards by id; Segment join is needed for Edition/position verification, never canonical/catalog joins. Exact Edition lookup reads feed_editions by id and reconstructs its flattened revision/context. Ordered Segment diagnostics use WHERE edition_id = :edition_id ORDER BY ordinal; card membership for each Segment uses ORDER BY ordinal. The hot window path does not need all Segments or the entire Edition materialized.

## 12. Atomic publication writes

Creation and append use the existing serialized runtime writer transaction primitive; do not start a transaction with a stale read from another connection. The initial history operation is:

```text
BEGIN writer transaction
validate Edition representation and first Segment ordinal 0
validate nonempty cards, matching schema version and occurrence IDs
insert Edition
insert first Segment
insert every frozen card with ordinal 0…count-1
validate the complete operation
COMMIT
```

Any failure rolls back everything. A metadata-only Edition must not be committed as visible history through this baseline API. Segment card order determines mechanical ordinals; no sorting/deduplication is allowed. Card membership fields belong to the mechanical write envelope, not additional PublishedCard semantic properties.

Append is:

```text
BEGIN writer transaction
re-read Edition and current maximum Segment ordinal
validate expected new ordinal == checked maximum + 1
validate Segment schema version == Edition schema version
validate nonempty complete ordered cards and their representations
insert Segment
insert ALL cards with contiguous ordinals 0…count-1
COMMIT
```

Reject a missing Edition/tail, overflow of representable next ordinal, mismatched caller expectation, schema mismatch, duplicate ID or malformed representation. No partial Segment/card commits. An ordinal gap/reordering in retained history is invalid, not repaired by the mapper. Segment retrieval validates ordered membership/nonemptiness; integrity reads validate append continuity. A bounded window must not silently skip detected missing/malformed rows.

SQLite writer serialization plus transaction-time tail reread is the storage primitive. Semantic single-flight belongs to future PublicationCoordinator. Persistence adds no tail/generation counter, lock table, token or append state machine. Plain insert semantics reject collisions; do not use replace/upsert to rewrite immutable history.

## 13. Session checkpoint semantics

SessionStore saves and loads one exact logical checkpoint with Domain Edition/card IDs and a mechanical placement value. Context derives exclusively from the checkpoint's Edition → EditorialRevision → ContextKey. The checkpoint duplicates no Segment/card position or pixel geometry.

```text
BEGIN writer transaction
verify Edition exists
verify card → Segment → Edition matches requested Edition
validate placement and supplied updatedAt representation
UPSERT singleton_id = 1 with EditionID, cardID, placement, updatedAt
COMMIT
```

UPSERT is allowed only for this replaceable checkpoint, not history. Restore validates membership again and reconstructs the exact anchor in a consistent read snapshot. Missing checkpoint alone means no saved checkpoint; an existing invalid checkpoint is corruption. The higher layer determines no-checkpoint presentation, never silently treats failed database opening as empty first launch.

Publication commit and checkpoint swap are deliberately separate transactions. E10 remains visible while E11 is produced. E11 must be fully committed before checkpoint E10 → E11 is written. If production fails, E10 and its checkpoint are unchanged. A crash between complete E11 commit and swap leaves the valid old checkpoint; E11 exists but is not the selected persisted visible history. Retention must preserve E10 until an explicit successful swap. No active-Edition table, lifecycle flags or successor column are required.

## 14. Publication/Persistence boundary

The module graph stays FeedMinePersistence → FeedMineDomain. Persistence must not import/depend on FeedMinePublication; Publication already depends on Persistence and owns semantic reconstruction/mapping.

Future nested mechanical values may be PublicationStore.EditionRecord, PublicationStore.SegmentRecord and PublicationStore.CardRecord. They contain only Domain IDs/values and scalars, belong to Persistence, have no editorial behavior, are not Runtime/UI models and do not replace FeedEdition/FeedSegment/PublishedCard. Do not introduce PersistedPublishedCard, DatabasePublishedCard, PublishedCardDTO or StoredFeedEdition as a second semantic domain.

```text
PublishedCard
  → FeedMinePublication mapping
  → mechanical CardRecord (including Segment ID + card ordinal envelope)
  → PublicationStore
  → published_cards row

row
  → mechanically validated CardRecord
  → FeedMinePublication validates/reconstructs PublishedCard
```

Persistence never constructs PublishedCard, RenderContract, PublishedMediaRef or PublishedPrimaryAction. Mechanical validation covers discriminants, nullable groups and representation constraints; Publication uses frozen semantic constructors and rejects failed reconstruction. Neither layer silently substitutes values. EditionRecord may use EditorialRevision directly because it belongs to Domain; its SQL row stays flattened without PersistedEditorialRevision. SegmentRecord exposes metadata plus ordered Domain PublicationCardIDs derived from rows, not a second publication aggregate.

SessionStore mechanical checkpoint values contain FeedEditionID, PublicationCardID, scalar placement and updatedAt. They need no FeedWindow, SessionCursor import or Runtime state machine. Publication maps top/center and reconstructs FeedWindowAnchor/SessionCursor for a future consumer. No repository protocol/facade/manager or new production type is implemented in this phase.

## 15. Corruption behavior

Invalid persisted representation or inconsistent retained relationships must surface as a typed corruption error identifying the record/field or invariant. Mechanical validation belongs to Persistence; failed semantic reconstruction belongs to Publication mapping and must preserve typed failure to the caller. Valid but unrepresentable write input (for example UInt64 above Int64.max) is a typed storage representation error, not overflow or a fabricated row. SQLite open/transaction failures retain the Phase 2A failure contract.

Do not skip malformed cards, drop invalid actions, convert invalid enums to nil, replace invalid layouts, ignore a missing Segment or move an anchor. Do not regenerate history with Selection, choose a nearby timestamp, follow current OriginRevision or erase/reset the database. Unknown unsupported publication formats fail explicitly; no current/latest/migration policy is invented here. A higher layer may decide future recovery, but Persistence does not invent content.

Absent media bytes with a valid stored reference are an expected fallback condition, not storage corruption. The valid RenderContract supplies a deterministic local placeholder. textOnly remains valid without any media slot.

## 16. Failure scenarios

| Event | Required outcome |
| --- | --- |
| Crash while creating Edition before commit | No Edition/first Segment/cards from the operation committed. |
| Crash while appending before commit | No partial Segment/cards committed; previous history unchanged. |
| Crash after complete Edition commit, before checkpoint swap | Old checkpoint remains valid; complete successor is not selected by it. |
| Checkpoint references missing card/Edition, missing Segment or wrong Edition | Typed corruption; no approximate restore. |
| Canonical OriginRevision removed | Frozen published card restore unaffected. |
| Catalog unavailable or attribution renamed | Restore unaffected; frozen names remain. |
| Network unavailable | Restore unaffected; no remote fetch needed for scroll/render. |
| Media bytes missing | Card materializes via RenderContract placeholder; no network obligation. |
| Invalid action/enum/dimensions or nonfinite ratio | Typed corruption, never silent dropping/replacement. |
| Append schema mismatch, stale position or occurrence collision | Entire write fails/rolls back; no history rewrite. |
| Checkpoint write fails | Prior persisted checkpoint remains intact. |
| runtime.sqlite cannot open safely | Explicit failure plus Retry in future UI, not empty launch, memory fallback or automatic reset. |

Crash statements refer to operations interrupted before their atomic commit; after a successful commit the complete operation persists. No custom partial-commit recovery state is introduced.

## 17. Explicitly deferred schema

No editorial_revisions, segment_cards, publication_card_media/published_media, publication_heads, publication_tokens, active_editions/current_edition_by_context, context_sessions, asset_versions/assets/asset_references, origin_records/origin_revisions, sources/providers, bookmarks/read_state/exposure/opened/consumed tables are proposed.

No publication JSON blob, generic metadata dictionary, absolute ordinal, card_count, tail/generation counter, integer surrogate history key, successor_edition_id/superseded_by/is_active/is_superseded, expires_at/protected/pin_count/last_accessed_at/retention_priority or other retention columns are proposed. No triggers, alternate media slots, connector write actions, lifecycle state machine or multi-session framework.

User-state, canonical supply, asset durability, retention, multi-context reuse and interactions require independent slices with concrete consumers. Missing canonical/catalog/asset tables do not prevent exact offline publication restore; provenance/media keys are deliberately not lifecycle FKs.

## 18. Implementation gate

Phase 2D designs but does not implement the first domain schema. Only this document, PERSISTENCE_DESIGN.md and IMPLEMENTATION_ORDER.md change. RuntimeMigrations, RuntimeDatabase, PublicationStore, SessionStore, ContentStore, every production Swift/test file and Package.swift remain intact. No DDL has been executed and no persistence test or mapper/store code has begun.

After architectural review and merge, a separately authorized implementation phase may add this schema and the explicit mechanical boundary. Its gate includes four-table migration verification; UInt64 boundary/seed bit-pattern/date/UUID round trips; invalid nullable groups and semantic inputs rejected without silent defaults; atomic first publication/append rollback; exact E1/P4/center close/reopen window restoration with no canonical/catalog/network; checkpoint membership validation on write/read; restricted deletes protecting retained history; and scope/graph verification. These are future acceptance requirements, not tests implemented now.
