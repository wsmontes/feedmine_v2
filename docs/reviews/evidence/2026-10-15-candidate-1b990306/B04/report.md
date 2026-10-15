# Run 20261015T063457Z

- device: FeedMine Bench (16DA3DB5-C9E0-4190-AF2F-AFAADC7EB7AE, dedicated to the benchmark) (simulator) · transport: 127.0.0.1:8757 · corpus: bench/corpus · commit: 1b9903067b52614863de682eb9a3a7e2407fdb02 · dirty files: 0
- corpus: {"behaviour_classes": {"intermittent": 265, "normal": 1622, "slow": 287, "timeout": 131}, "canonical_articles_shared": 270, "cross_publisher_duplicate_pairs": 270, "distinct_headlines": 15917, "eligible_items": {"A": 6885, "B": 8112}, "eligible_sources": {"A": 942, "B": 1123}, "empty_documents": 75, "item_topics": {"brazil-news": 6146, "other": 814, "photography": 14, "science": 1550, "technology": 4754, "world-news": 2639}, "items": 15917, "material_revision_items": 75, "media_kinds": {"audio": 2949, "image": 4785, "none": 3204, "video": 4979}, "protocols": {"atom": 587, "jsonfeed": 433, "rss": 1285}, "slow_media_sources": 231, "source_topics": {"brazil-news": 845, "other": 215, "photography": 2, "science": 215, "technology": 659, "world-news": 369}, "sources": 2305}
- database: /tmp/fm-gate-cand/bench/run/20261015T063457Z/container/Library/Application Support/FeedMine/0E9E13A7-6857-4D0A-8197-745A59F33C11/runtime.sqlite

## B04 — PASS

- estado — fontes no conjunto de aquisição: None
- estado — fontes efetivamente buscadas: None
- estado — fontes que chegaram aos cards: None
- estado — cards publicados: None
- PASS — o protocolo de B04 foi caminhado (âncora, convite, ócio, rotação, background) (observed: ["b04-after-answer-frames", "b04-after-answer-order", "b04-after-answer-stable", "b04-after-hide-frames", "b04-after-hide-stable", "b04-after-undo-frames", "b04-after-undo-stable", "b04-anchor0", "b04-background-frames", "b04-background-same-topmost", "b04-background-stable", "b04-block-above-reader", "b04-cycle-attempts", "b04-idle-frames", "b04-idle-stable", "b04-rotation-counters", "b04-rotation-holds"])
- PASS — nada do que o leitor já tinha se moveu, reordenou ou retratou (observed: {"instalacoes": 223, "cartas": 75, "violacoes": {"head_forward": 0, "shrunk": 0, "tail_back": 0, "holes": 0}, "medidas_do_driver": {"b04-after-answer-stable": "true", "b04-after-answer-order": "true", "b04-after-undo-stable": "true", "b04-after-hide-stable": "true", "b04-idle-stable": "not-measurable", "b04-rotation-holds": "true", "b04-background-stable": "true"}, "instaveis_do_driver": [], "nao_mediveis_do_driver": ["b04-idle-stable"]})

## Identidade dos insumos
1f642eaaf393a95b632ecea339139f9fdf04d7292193cf112f3c46b8a64b3bc8  bench/corpus/catalog.sqlite
4bb683a728ca2ffa99dbc7d47918ee008ee28e113d4cb2b7ee60b47182694cde  bench/corpus/items.json
57804e0bc354c26fe6010ae4070e9232ab2202dfb809a239f0fc468c68bce8b7  bench/oracle.py
08739fd38064019ed4042dba6bc912323b5b1efcbfc2358c6d81efb8db4aa496  FeedMineApp/FeedMineAppTests/DiscoveryBenchmarkTests.swift
