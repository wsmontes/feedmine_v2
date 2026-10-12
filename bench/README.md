# FeedMine discovery acceptance benchmark — corpus, transport and criteria

This directory is the **evaluator's own reference** for the discovery acceptance benchmark described in
[`docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md`](../docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md) §2.

It is **not production code**. It does not ship with the app, it is not imported by the app, and the app does not
know it exists. Nothing outside `bench/` was changed to build it. A run's PASS/FAIL/NOT_RUN/BLOCKED verdicts belong
in a **separate report**, never in these files; this directory contains inputs and oracles only, never a result.

## What is here

| Artifact | Is what |
| --- | --- |
| `build_corpus.py` | Generator. Reads the repository's real bundled catalog **read-only**, selects rows by their own labels, writes the frozen corpus. Deterministic: fixed seed, fixed base timestamp, stable ordering, no wall clock in the data. |
| `serve.py` | Local HTTP transport (`127.0.0.1:8757` by default). Serves each source's feed document, its media and its local article page; reproduces the corpus's delays and failure classes; appends every request to `run/server.log`. Prints the corpus totals at startup. |
| `manifest.json` | Frozen manifest: SHA-256 of every artifact, `frozen: true`, `generated_at`, the seed, the totals, the transport base URL, the feed-document digest, and the frozen criteria (profiles, the B01/B02/B03 thresholds quoted verbatim, the trace description). |
| `MANIFEST.sha256` | The same hashes in `sha256sum` format (one line per artifact, feed documents included). |
| `corpus/catalog.sqlite` | The benchmark catalog: real rows from the bundled snapshot, **same schema `LegacyCatalogReader` reads**, with `request_url` rewritten to `http://127.0.0.1:8757/s/<percent-encoded key>`. Every other label column (`title`, `language`, `media_kind`, `quality_score`, `default_enabled`, `tags`, `nature`, `activity`, `site_url`, `declared_url`, placements, taxonomy) is exactly what the real catalog had. |
| `corpus/items.json` | One JSON object: `{"generated_at", "seed", "profiles", "items": [...]}`. Each item: `id`, `source_key`, `canonical` (shared by deliberate cross-publisher duplicates), `revision` (0 = original edition, 1 = the material revision), `headline`, `summary`, `topic` (the source's most specific real catalog node key), `language` (primary subtag), `region`, `published_at`, `media` (`kind`, `url`, `content_type`, `duration_seconds`, `bytes` = its frozen slice of `media.pack`). Additive fields the oracles use: `topic_bucket`, `topic_node_keys`, `source_title`, `language_code`, `link`, `eligible_profiles`, `origin` (`own`/`syndicated`/`material-revision`), `material_revision`, `revision_of`, `duplicate_of`. |
| `corpus/profiles.json` | The profiles as data, for driving onboarding with the answers the corpus was labelled for: `{"A": {"interests": [...node keys...], "languages": ["pt"], "region": "<node key>"}, "B": {...}}`, plus `source_tags`, `interest_notes` and the eligible counts. |
| `corpus/sources.json` | The transport plan per source: protocol, content type, feed file and hash, behaviour class (normal / slow / intermittent / timeout) with its exact parameters, media delay, item count, profile membership, taxonomy keys, region. |
| `corpus/criteria.json` | The frozen criteria: profiles and their real-label selection rules, the eligibility rule, the B01/B02/B03 thresholds **quoted verbatim** from the benchmark document (with the document's own SHA-256), and the B03 trace description. |
| `corpus/feeds/*` | The frozen feed documents (RSS 2.0, Atom, JSON Feed) exactly as served. |
| `corpus/media.pack` | Frozen media bytes (PNG card visuals, MP3 audio, MP4 video) served by byte range. |
| `run/server.log` | Created at run time: one JSON object per line. The acquisition oracle reads `t_ms` (epoch ms), `method`, `source` (the catalog key for `/s/<key>` requests, else null), `path`, `status`, `bytes` (body bytes actually sent, so 0 for `HEAD`/`304`), `ms` (integer milliseconds). Additive context: `seq`, `t` (ISO 8601), `kind` (`feed`/`media`/`article`/`meta`), `delay_ms`, `note`. |

## Profiles (chosen by the real catalog's own labels)

* **Profile A** — reader interested in science, technology, photography and Brazil news: `pt`/`pt-BR` sources placed
  under the `04-technology-science` section or under the `90_countries/brazil` country node, or carrying the
  `photography` value in the catalog's real `tags` column.
* **Profile B** — English reader of world news and technology: `en*` sources placed under `04-technology-science` or
  `01-news-current-affairs/world-news`.

The exact rule is in `corpus/criteria.json` (`eligibility_rule`) and is computable from `corpus/catalog.sqlite`
alone, so it can be recomputed independently:

```sql
-- eligible sources for profile A
SELECT COUNT(DISTINCT s.id) FROM catalog_source s
  JOIN catalog_placement p ON p.source_id = s.id
  JOIN catalog_node n ON n.id = p.node_id
 WHERE s.language IN ('pt','pt-BR')
   AND (n.key LIKE '04-technology-science%' OR n.key LIKE '90_countries/brazil%'
        OR s.tags LIKE '%photograph%');
```

The catalog also carries deterministic **noise** rows (real `es`/`fr`/`de` sources outside both profiles) so that a
recipe's own filtering is actually exercised; they are not eligible for either profile.

## Build

```bash
python3 bench/build_corpus.py            # first build; refuses to overwrite a frozen corpus
python3 bench/build_corpus.py --rebuild  # deliberate regeneration — rewrites corpus and manifest
```

`--rebuild` is the only way to regenerate: a frozen corpus is otherwise left untouched (see
[`DISCOVERY_ACCEPTANCE_BENCHMARK.md`](../docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md) §1 — the evaluator's
fixture must not be edited to favour a build). Build-time dependencies: Python 3 (stdlib only) and `ffmpeg`
(for the audio/video media templates). No network access is needed.

The build verifies itself before freezing anything and exits non-zero, writing nothing, if a precondition fails:
≥300 eligible sources per profile, ≥5,000 eligible items per profile, ≥5,000 items overall, globally distinct
headlines, cross-publisher duplicates present, all three protocols and all four behaviour classes present inside
each profile.

## Serve

```bash
python3 bench/serve.py --totals     # print what the evaluator reads before any run
python3 bench/serve.py              # serve on 127.0.0.1:8757
curl -s http://127.0.0.1:8757/s/<percent-encoded source key> | head -c 200
curl -s http://127.0.0.1:8757/totals
```

Endpoints: `/` (index + totals), `/totals` (JSON — `sources_per_profile`, `items_per_profile`, `items_total`,
`sources_total`, `sources_per_protocol`, `items_per_protocol`, `profiles`, `criteria_thresholds`, `trace`; `/_totals`
is the same payload), `/health`, `/s/<key>` (feed document), `/m/<asset>` (media, supports `Range`,
`ETag`/`Last-Modified`, `304`), `/a/<uid>` (local article page). `HEAD` is supported everywhere. Run the corpus
**locally**: item links, media URLs and article pages all point at this transport, so a run needs no internet.

Byte-frozen and served verbatim: the feed documents and the media pack. Generated by the frozen server from frozen
item records: the article page at `/a/<uid>` (a fixed HTML template around the item's own frozen fields). Both the
generator and the server are hashed in the manifest.

Failure classes are deterministic **within one server run**: per-resource counters start at zero when the server
starts, so the same sequence of requests produces the same sequence of outcomes. Restarting the server resets the
counters; `corpus/sources.json` records every class and its exact parameters.

## What this corpus deliberately contains

RSS 2.0 / Atom / JSON Feed documents; slow sources (2.5–6.0 s); intermittently failing sources (every 3rd or 4th
request answers 500/503); sources that hang for 12 s and then answer 504 every 4th request; valid documents with
zero items; slow media responses (2.5–7.0 s); cross-publisher duplicates (the same canonical article reachable from
two different feeds, retitled by the second publisher) and PD-1 material revisions of a duplicated canonical
article, flagged separately.

## Measured (2026-10-10, this machine)

`python3 bench/build_corpus.py` then `python3 bench/serve.py --totals` printed, verbatim:

```
profile A rows    : 942                       # real catalog rows selected for profile A
profile B rows    : 1123
noise rows        : 240
selected rows     : 2305
catalog written   : sources=2305 nodes=505 placements=2305
items generated   : 15917 (duplicate pairs=270, material revisions=75)

verification
  eligible sources     : A=942 B=1123
  eligible items       : A=6885 B=8112
  items total          : 15917
  distinct headlines   : 15917
  canonical shared ids : 270
  protocols            : {'atom': 587, 'rss': 1285, 'jsonfeed': 433}
  behaviour classes    : {'intermittent': 265, 'normal': 1622, 'slow': 287, 'timeout': 131}
  empty documents      : 75
  slow-media sources   : 231
```

`sqlite3 bench/corpus/catalog.sqlite "select count(*) from catalog_source"` → **2305**; eligible rows, counted with
the frozen rule: **A = 942, B = 1123** (≥300 each). `bench/corpus/items.json` → **15917 items**, **6885** eligible for
profile A and **8112** for profile B (≥5,000 each; the B03 trace needs 2,000–2,040). Item topics: brazil-news 6,146,
technology 4,754, world-news 2,639, science 1,550, other 814, photography 14.

Transport, exercised with `curl`: feed `GET`/`HEAD` (RSS 2.0, Atom, JSON Feed, correct `Content-Type`), `ETag` /
`Last-Modified` with `200`/`304`, `Range` → `206` and `416`, per-source media (PNG 160×96, MP4, MP3) with the same
conditional/range semantics, article page `200 text/html`. Reproduced classes: intermittent source `200,200,200,503,
200` (fails every 4th request); timeout source `200,200,200,504` with a 12.0 s hang; slow source `200` in 5.81 s;
slow-media source `200` in 6.29 s; unknown key `404`. Every request appeared in `run/server.log`.

Rebuilds are deterministic: `--rebuild` produced byte-identical `catalog.sqlite`, `media.pack`, every feed document
and a byte-identical `items` array (compared with SHA-256). The only values that change between rebuilds are the two
metadata timestamps — `generated_at` in `items.json` and in `manifest.json`; no timestamp enters the corpus data
itself (every `published_at` is derived from the fixed base `2026-10-09T00:00:00Z`).

Artifact sizes: `catalog.sqlite` 3,719,168 B · `items.json` 16,312,873 B · `sources.json` 3,246,428 B ·
`profiles.json` 964 B · `criteria.json` 5,222 B · `media.pack` 52,743,855 B · `feeds/` 2,305 files
(11,263,518 B) · `manifest.json` 452,089 B, listing all 2,314 artifacts · `MANIFEST.sha256` 2,314 lines.
`run/server.log` is run-time output and is deliberately not hashed.

## Honest gaps

Recorded rather than papered over (the same list is reported by the build):

1. **No photography node exists.** The bundled taxonomy (6,450 nodes) has no photography node at all, so profile
   A's photography interest is carried by the catalog's real `tags` column. In the real catalog only a handful of
   `pt`/`pt-BR` rows carry that tag: profile A therefore ends up with **2 eligible sources / 14 items** labelled
   `photography`. The interest is real but genuinely thin in this catalog; the other profile-A interests
   (brazil-news 6,146 items, science 1,550, technology 4,754) carry the volume.
2. **No real article text.** Only the catalog's own labels are real (key, title, declared/request URL, display host,
   language, media kind, quality score, default-enabled flag, taxonomy placements, tags, nature, activity). Headlines,
   summaries and article bodies are synthesised from frozen word banks; the article page is a fixed HTML template
   around the item's own frozen fields. Nothing was copied from the live internet.
3. **Generated media, not real episodes.** Card visuals are unique per item (deterministic PNG). Audio and video
   payloads are one- and two-second generated templates (silent MP3, small MP4) shared by every item of that kind,
   so their ETag is shared too.
4. **A filtered slice, not the whole catalog.** 2,305 of the real 77,443 rows: the union of both profiles plus 240
   real `es`/`fr`/`de` noise rows. `catalog_metadata` reports this catalog's own counts and keeps
   `bench_corpus_real_catalog_source_count = 77443` for provenance. Each selected source has exactly one placement in
   the real catalog, so placement fan-out variety is limited by the source data.
5. **Failure counters are per server run.** The same request sequence reproduces the same outcomes within one run;
   restarting the server resets them. Class parameters are frozen in `corpus/sources.json`.
6. **Build-time dependency on `ffmpeg`** for the two media templates (nothing else, and no network).
7. **This fixture does not run any gate.** It is the input side of the benchmark; environment B (live internet,
   physical device) and every PASS/FAIL/NOT_RUN/BLOCKED verdict belong to a separate run report.
