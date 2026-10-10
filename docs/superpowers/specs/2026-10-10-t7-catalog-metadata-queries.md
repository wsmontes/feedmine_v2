# T7 — catalog metadata queries (measured brief)

Written 2026-10-09 from the actual bundled catalog
(`FeedMineApp/FeedMineApp/Resources/catalog.sqlite`, 117,940,224 bytes, release asset `catalog-v1`), because T6's
filter sheet, T7's source management and T8's presets all need metadata that only this file can answer.

## 1. What the file actually contains (measured, not assumed)

| Table | Rows | Columns that matter |
| --- | --- | --- |
| `catalog_source` | 77,443 | `id`, `key`, `title`, `declared_url`, `request_url`, `display_host`, `media_kind`, `language`, `site_url`, `description`, `tags`, `nature`, `activity`, `latest_item_at`, `quality_score`, `default_enabled`, `type` |
| `catalog_node` | 6,450 | `id`, `key`, `parent_id`, `name`, `kind`, `source_count`, `child_count`, `language` |
| `catalog_placement` | 77,443 | `id`, `source_id`, `node_id`, `node_name`, `opml_file`, `sort_order`, `title_override`, `language_override`, `media_kind_override` |
| `catalog_metadata` | 9 | `schema_version = 2`, `catalog_version = 1789618085179441`, `source_count = 77,443`, `node_count = 6,450`, `placement_count = 77,443`, `file_count = 118`, zero duplicates/failures |
| `catalog_source_fts` | 50k+ | FTS5 index over sources (title/description) — available if search needs it |

Indexes already present: `idx_catalog_source_title(title COLLATE NOCASE, id)`,
`idx_catalog_node_parent_name(parent_id, name COLLATE NOCASE, id)`,
`idx_catalog_placement_node_order(node_id, sort_order, source_id)`, `idx_catalog_placement_source(source_id)`.

Measured samples that the queries must respect:

- Language is **declared, dirty and primary-subtag mixed**: `und` 27,741, `en` 17,962, `en-US` 7,028, `es` 3,982,
  `fr` 1,171, `pt` 1,125, `en-GB` 1,013. A language filter must compare the primary subtag (as T6's
  `ReaderFilterEligibility` already does) and the UI must not pretend `und` is a language a reader can pick.
- The node tree is rooted at `id = 0, key = 0, name = "Root"`, and `kind` **is** the discriminator (measured over
  all 6,450 nodes): `kind = 0` are the 19 sections that sit under the root (`Arts & Culture`, `Business &
  Industry`, `Countries`, `Education & Knowledge`, …), `kind = 1` are the **101 countries** (children of the
  `Countries` section, which alone carries 63,894 sources), and `kind = 3` are the 6,330 topic leaves. So
  "countries" is a real subtree, not a separate table, and no second region source is needed.
- A source can sit in several nodes (`catalog_placement` is many-to-many, with `sort_order` per node and optional
  `title_override`/`language_override`/`media_kind_override`).

## 2. The three query families T7 must expose

All three live in `Sources/FeedMinePersistence/LegacyCatalogReader.swift` (read-only, one connection per call,
`SQLITE_OPEN_READONLY` — the file is a release asset and must never be written) and surface as UI-facing values
through a Composition coordinator (`SourceManagementCoordinator`), never as GRDB/rows in UI.

1. **Languages** (unblocks T6's sheet): `SELECT language, COUNT(*), SUM(default_enabled) FROM catalog_source
   GROUP BY language`. Produce V1's value shape — `code`, localized `name`, `flag`, `feedCount` (enabled),
   `totalFeedCount` — mapping `und`/empty to a single explicit "undeclared" bucket the UI shows last.
2. **Taxonomy**: children of a node ordered by `name COLLATE NOCASE` (`WHERE parent_id = ?`), search by name
   (`WHERE name LIKE ? OR key LIKE ?` with the index), ancestors by walking `parent_id`, and the placement count
   per node from `catalog_node.source_count`. Values carry `id` (the catalog's own integer id — map to a stable
   V2 key, never reuse the integer as identity), `name`, `kind`, `sourceCount`, `hasChildren`.
3. **Countries and regions**: the countries are the `kind = 1` children of the `Countries` section (101 of them,
   each with its own `source_count`); a country's own children are its `kind = 3` topics. Derive from the node
   tree — there is no region table, and `catalog_placement.opml_file` is grouping metadata, not identity.

## 3. Rules that already cost time in this repository

- **Read-only, and never the V1 database.** `LegacyCatalogReader` opens a *copy*; do not open
  `/Users/wagnermontes/Documents/GitHub/feedmine`'s base with the V2 migrator (plan constraint).
- **Identity**: v1 `sourceID` is a truncated 32-bit hash; V2 uses UUIDs derived by
  `LegacyCatalogImport.stableUUID`. New queries must return the same derived identities, not the catalog integers.
- **No full catalogue enumeration on the main thread**: page by parent/cursor and keep the queries indexed
  (`idx_catalog_node_parent_name` exists for exactly this).
- **UI never sees rows**: the coordinator returns values (`SourceSummary`, language options, node values).

## 4. Tests that must exist

1. `availableLanguages()` on the real bundled snapshot: `und` is bucketed and last, the counts sum to the enabled
   total, and a primary-subtag filter (T6) matches `en` for `en-US`.
2. Taxonomy: children of the root and of a section are ordered and paged; a deep node's ancestors come back in
   order; a search matches by name and by key without scanning the whole table (assert the plan uses an index).
3. Regions: every derived region has a non-zero source count and a stable key across two calls.
4. Performance: one query on the 77k-row release asset stays under the budget the UI needs (measure and record the
   number; the FTS table exists if a text search needs it).
"""
