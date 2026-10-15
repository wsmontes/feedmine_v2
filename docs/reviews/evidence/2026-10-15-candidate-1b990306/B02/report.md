# Run 20261015T062751Z

- device: FeedMine Bench (16DA3DB5-C9E0-4190-AF2F-AFAADC7EB7AE, dedicated to the benchmark) (simulator) · transport: 127.0.0.1:8757 · corpus: bench/corpus · commit: 1b9903067b52614863de682eb9a3a7e2407fdb02 · dirty files: 0
- corpus: {"behaviour_classes": {"intermittent": 265, "normal": 1622, "slow": 287, "timeout": 131}, "canonical_articles_shared": 270, "cross_publisher_duplicate_pairs": 270, "distinct_headlines": 15917, "eligible_items": {"A": 6885, "B": 8112}, "eligible_sources": {"A": 942, "B": 1123}, "empty_documents": 75, "item_topics": {"brazil-news": 6146, "other": 814, "photography": 14, "science": 1550, "technology": 4754, "world-news": 2639}, "items": 15917, "material_revision_items": 75, "media_kinds": {"audio": 2949, "image": 4785, "none": 3204, "video": 4979}, "protocols": {"atom": 587, "jsonfeed": 433, "rss": 1285}, "slow_media_sources": 231, "source_topics": {"brazil-news": 845, "other": 215, "photography": 2, "science": 215, "technology": 659, "world-news": 369}, "sources": 2305}
- database: /tmp/fm-gate-cand/bench/run/20261015T062751Z/container/Library/Application Support/FeedMine/955FD52A-5212-41CA-9108-F1DD3528A5D4/runtime.sqlite

## B02 — PASS

- PASS — ≥80% dos 200 cards correspondem ao perfil (observed: {"relevantes": 200, "com rótulo": 200, "cards": 200})
- PASS — ≥20 fontes distintas (observed: 40)
- PASS — nenhuma fonte >15% (observed: 0.045)
- PASS — zero pares consecutivos da mesma fonte (observed: 0)
- PASS — zero duplicatas de artigo canônico (observed: 0)

## Identidade dos insumos
1f642eaaf393a95b632ecea339139f9fdf04d7292193cf112f3c46b8a64b3bc8  bench/corpus/catalog.sqlite
4bb683a728ca2ffa99dbc7d47918ee008ee28e113d4cb2b7ee60b47182694cde  bench/corpus/items.json
57804e0bc354c26fe6010ae4070e9232ab2202dfb809a239f0fc468c68bce8b7  bench/oracle.py
08739fd38064019ed4042dba6bc912323b5b1efcbfc2358c6d81efb8db4aa496  FeedMineApp/FeedMineAppTests/DiscoveryBenchmarkTests.swift
