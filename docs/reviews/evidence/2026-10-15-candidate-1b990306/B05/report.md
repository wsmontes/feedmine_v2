# Run 20261015T063945Z

- device: FeedMine Bench (16DA3DB5-C9E0-4190-AF2F-AFAADC7EB7AE, dedicated to the benchmark) (simulator) · transport: 127.0.0.1:8757 · corpus: bench/corpus · commit: 1b9903067b52614863de682eb9a3a7e2407fdb02 · dirty files: 0
- corpus: {"behaviour_classes": {"intermittent": 265, "normal": 1622, "slow": 287, "timeout": 131}, "canonical_articles_shared": 270, "cross_publisher_duplicate_pairs": 270, "distinct_headlines": 15917, "eligible_items": {"A": 6885, "B": 8112}, "eligible_sources": {"A": 942, "B": 1123}, "empty_documents": 75, "item_topics": {"brazil-news": 6146, "other": 814, "photography": 14, "science": 1550, "technology": 4754, "world-news": 2639}, "items": 15917, "material_revision_items": 75, "media_kinds": {"audio": 2949, "image": 4785, "none": 3204, "video": 4979}, "protocols": {"atom": 587, "jsonfeed": 433, "rss": 1285}, "slow_media_sources": 231, "source_topics": {"brazil-news": 845, "other": 215, "photography": 2, "science": 215, "technology": 659, "world-news": 369}, "sources": 2305}
- database: /tmp/fm-gate-cand/bench/run/20261015T063945Z/container/Library/Application Support/FeedMine/73BE03AB-FBA7-4FB3-B77D-5CCC0D92A079/runtime.sqlite

## B05 — PASS

- estado — fontes no conjunto de aquisição: None
- estado — fontes efetivamente buscadas: None
- estado — fontes que chegaram aos cards: None
- estado — cards publicados: None
- PASS — o protocolo de B05 foi caminhado (salvar, A→B→A, reabrir, offline) (observed: ["b05-anchor-before", "b05-context-b-reached", "b05-offline-cards", "b05-offline-shows-local", "b05-reopen-keeps-saved", "b05-reopen-preserves-anchor", "b05-return-preserves-anchor", "b05-saved"])
- PASS — zero perda silenciosa de estado (observed: {"medidas": {"b05-saved": "true", "b05-anchor-before": "73430B6C-2078-4D8A-9354-568557C1FA6A", "b05-context-b-reached": "true", "b05-return-preserves-anchor": "true", "b05-reopen-preserves-anchor": "true", "b05-reopen-keeps-saved": "true", "b05-offline-shows-local": "true", "b05-offline-cards": "true"}, "registro_duravel": {"salvos": ["73430b6c-2078-4d8a-9354-568557c1fa6a"], "ancora_nomeada": "73430b6c-2078-4d8a-9354-568557c1fa6a", "posicao_na_reabertura": {"anchor": "73430B6C-2078-4D8A-9354-568557C1FA6A", "placement": "top"}, "checkpoints_duradouros": 1}, "falhas": []})

## Identidade dos insumos
1f642eaaf393a95b632ecea339139f9fdf04d7292193cf112f3c46b8a64b3bc8  bench/corpus/catalog.sqlite
4bb683a728ca2ffa99dbc7d47918ee008ee28e113d4cb2b7ee60b47182694cde  bench/corpus/items.json
57804e0bc354c26fe6010ae4070e9232ab2202dfb809a239f0fc468c68bce8b7  bench/oracle.py
08739fd38064019ed4042dba6bc912323b5b1efcbfc2358c6d81efb8db4aa496  FeedMineApp/FeedMineAppTests/DiscoveryBenchmarkTests.swift
