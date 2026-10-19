# Run 20261018T094425Z

- device: FeedMine Bench (2906D038-FB23-4807-BAEF-0FA6B8F18225, dedicated to the benchmark) (simulator) · transport: 127.0.0.1:8757 · corpus: bench/corpus · commit: b0b961a049f82fece037363a6cb0e986d556330c · dirty files: 51
- corpus: {"behaviour_classes": {"intermittent": 265, "normal": 1622, "slow": 287, "timeout": 131}, "canonical_articles_shared": 270, "cross_publisher_duplicate_pairs": 270, "distinct_headlines": 15917, "eligible_items": {"A": 6885, "B": 8112}, "eligible_sources": {"A": 942, "B": 1123}, "empty_documents": 75, "item_topics": {"brazil-news": 6146, "other": 814, "photography": 14, "science": 1550, "technology": 4754, "world-news": 2639}, "items": 15917, "material_revision_items": 75, "media_kinds": {"audio": 2949, "image": 4785, "none": 3204, "video": 4979}, "protocols": {"atom": 587, "jsonfeed": 433, "rss": 1285}, "slow_media_sources": 231, "source_topics": {"brazil-news": 845, "other": 215, "photography": 2, "science": 215, "technology": 659, "world-news": 369}, "sources": 2305}
- database: /Users/wagnersilvamontes/.codex/worktrees/v2-fluidez-capacidade/feedmine_v2/bench/run/20261018T094425Z/container/Library/Application Support/FeedMine/6EC8F0C7-7762-4C77-B7BE-5860355E6DBA/runtime.sqlite

## B01 — FAIL

- estado — fontes no conjunto de aquisição: 475
- estado — fontes efetivamente buscadas: 0
- estado — fontes que chegaram aos cards: 0
- estado — cards publicados: 0
- NOT_RUN — a jornada vigente foi caminhada nas duas fases observáveis, nos dois perfis (observed: {"A": ["neutral"], "B": null, "subjects_declared_in_the_feed": []})
- FAIL — não depende das quatro fontes padrão (observed: [])
- PASS — ≥50 fontes distintas entram automaticamente no conjunto de aquisição (observed: 475)
- FAIL — ≥20 fontes distintas contribuem com os primeiros 300 cards (observed: 0)
- NOT_RUN — outro perfil muda as fontes consultadas (observed: null)

## Identidade dos insumos
1f642eaaf393a95b632ecea339139f9fdf04d7292193cf112f3c46b8a64b3bc8  bench/corpus/catalog.sqlite
4bb683a728ca2ffa99dbc7d47918ee008ee28e113d4cb2b7ee60b47182694cde  bench/corpus/items.json
57804e0bc354c26fe6010ae4070e9232ab2202dfb809a239f0fc468c68bce8b7  bench/oracle.py
08739fd38064019ed4042dba6bc912323b5b1efcbfc2358c6d81efb8db4aa496  FeedMineApp/FeedMineAppTests/DiscoveryBenchmarkTests.swift
