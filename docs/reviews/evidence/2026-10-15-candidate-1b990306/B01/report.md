# Run 20261015T061907Z

- device: FeedMine Bench (16DA3DB5-C9E0-4190-AF2F-AFAADC7EB7AE, dedicated to the benchmark) (simulator) · transport: 127.0.0.1:8757 · corpus: bench/corpus · commit: 1b9903067b52614863de682eb9a3a7e2407fdb02 · dirty files: 0
- corpus: {"behaviour_classes": {"intermittent": 265, "normal": 1622, "slow": 287, "timeout": 131}, "canonical_articles_shared": 270, "cross_publisher_duplicate_pairs": 270, "distinct_headlines": 15917, "eligible_items": {"A": 6885, "B": 8112}, "eligible_sources": {"A": 942, "B": 1123}, "empty_documents": 75, "item_topics": {"brazil-news": 6146, "other": 814, "photography": 14, "science": 1550, "technology": 4754, "world-news": 2639}, "items": 15917, "material_revision_items": 75, "media_kinds": {"audio": 2949, "image": 4785, "none": 3204, "video": 4979}, "protocols": {"atom": 587, "jsonfeed": 433, "rss": 1285}, "slow_media_sources": 231, "source_topics": {"brazil-news": 845, "other": 215, "photography": 2, "science": 215, "technology": 659, "world-news": 369}, "sources": 2305}
- database: /tmp/fm-gate-cand/bench/run/20261015T061907Z/container/Library/Application Support/FeedMine/7DDAC7EC-9DD1-46B0-9D1B-B9FB437BEA8A/runtime.sqlite

## B01 — PASS

- estado — fontes no conjunto de aquisição: 237
- estado — fontes efetivamente buscadas: 298
- estado — fontes que chegaram aos cards: 32
- estado — cards publicados: 212
- PASS — a jornada vigente foi caminhada nas duas fases observáveis, nos dois perfis (observed: {"A": ["neutral", "answered:90_countries/brazil/health-wellness/mental-health", "answered:90_countries/brazil/food-drink/cooking-recipes", "thematic-attempted", "hide-stable:true", "hide-frames:224->224"], "B": ["neutral", "answered:04-technology-science/software-computing", "answered:04-technology-science/earth-life-sciences", "thematic-attempted", "hide-stable:true", "hide-frames:167->167", "negative:not-offered"], "subjects_declared_in_the_feed": ["90_countries/brazil/food-drink/cooking-recipes", "90_countries/brazil/health-wellness/mental-health"]})
- PASS — não depende das quatro fontes padrão (observed: [])
- PASS — ≥50 fontes distintas entram automaticamente no conjunto de aquisição (observed: 237)
- PASS — ≥20 fontes distintas contribuem com os primeiros 300 cards (observed: 32)
- PASS — outro perfil muda o conjunto de aquisição de modo explicável (observed: {"a": 237, "b": 365, "iguais": 0})

## Identidade dos insumos
1f642eaaf393a95b632ecea339139f9fdf04d7292193cf112f3c46b8a64b3bc8  bench/corpus/catalog.sqlite
4bb683a728ca2ffa99dbc7d47918ee008ee28e113d4cb2b7ee60b47182694cde  bench/corpus/items.json
57804e0bc354c26fe6010ae4070e9232ab2202dfb809a239f0fc468c68bce8b7  bench/oracle.py
08739fd38064019ed4042dba6bc912323b5b1efcbfc2358c6d81efb8db4aa496  FeedMineApp/FeedMineAppTests/DiscoveryBenchmarkTests.swift
