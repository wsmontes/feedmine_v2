# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 054 · Vancouver, 02/11/2026, ~16:38 PST (UTC−08).** Parecer consultivo: **RELEASE NÃO APROVADA**. O OMP deve fazer fetch de `monitor/architecture` e ler este documento; o monitor não envia notificações aos executores.

## 1. Memória, autoridade, intervalo e SHAs

**Memória persistente lida antes da inspeção:** [revisão 053](https://github.com/wsmontes/feedmine_v2/blob/3d1b6aecfc9dd1d88a21c7223e6b1eb9e3039b9f/docs/reviews/ARCHITECTURE_MONITOR.md), commit `3d1b6aecfc9dd1d88a21c7223e6b1eb9e3039b9f`, blob `0ea5a15a7161f7c30a9b16e321728909506dace8`. **Intervalo analisado:** 02/11, ~14:39–16:38 PST, desde Kiro `48a69cb95158c4a340620fd5517cb89c823c3e56`.

- **main:** `2eca5b4f925141e5fdd3653e523c3663972d4310`, [compare](https://github.com/wsmontes/feedmine_v2/compare/2eca5b4f925141e5fdd3653e523c3663972d4310...main) `identical`: zero commits, zero arquivos (incluindo docs). **Integração consolidada** `integration/main-consolidated-20261030`: mesmo SHA.
- **Trabalho ativo:** `kiro/review-fixes-20261102` **`48a69cb9` → `68b620554fad5778c8405b3518ceefd6c42b0bed`**, [diff incremental](https://github.com/wsmontes/feedmine_v2/compare/48a69cb95158c4a340620fd5517cb89c823c3e56...68b620554fad5778c8405b3518ceefd6c42b0bed): **2 commits / 34 arquivos** (33? conferir contagem no compare: 34 entradas), incluindo código, testes e handoff. [Compare com main](https://github.com/wsmontes/feedmine_v2/compare/2eca5b4f925141e5fdd3653e523c3663972d4310...68b620554fad5778c8405b3518ceefd6c42b0bed): **41 à frente, zero atrás, 91 arquivos acumulados**. Commit `139040ca` corrige codificação de docs; `68b62055` implementa paridade de podcasts. Nenhum PR Kiro aberto; nenhuma candidata integrada/validada.
- **PRs:** #29–#31, #33–#37: oito drafts com HEADs inalterados. **Issues:** #7, #18, #27, #32 abertas. Inspecionadas as três páginas de branches (100+100+83); referências `integration/candidate`, `release/build-56` e `kiro/review-build54` têm commits antigos (outubro), não são tratadas como trabalho corrente.
- **CI:** 36 runs, sem novo run desde a revisão 053. Último [#41497618804](https://github.com/wsmontes/feedmine_v2/actions/runs/41497618804), **FAIL**, SHA intermediário `146915e5`, 1.886 testes aprovados / 2 reprovados / 4 ignorados; falhas SQLite e scripts a isolar. **Nenhum XCTest/CI do HEAD `68b62055`**; nenhum simulador, iPhone, archive ou benchmark executado por este monitor.

**Normas atuais consultadas na main:** [North Star](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/PRODUCT_NORTH_STAR.md), [decisões PD-1–PD-11](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz de execução](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [invariantes INV-01–INV-18](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/architecture/PRODUCT_INVARIANTS.md), [arquitetura](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/architecture/ARCHITECTURE.md), [regras de dependência](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/architecture/DEPENDENCY_RULES.md), [benchmark B01–B06](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md) e [admissão render-ready](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/2026-10-17-render-ready-admission-rule.md). Essas normas prevalecem sobre blueprints, relatórios e estudos Kiro.

## 2. Resumo executivo — podcasts mais completos, feed contínuo ainda bloqueado

**Avanço factual em código, ainda não aceito em aparelho:** o commit [68b62055](https://github.com/wsmontes/feedmine_v2/commit/68b620554fad5778c8405b3518ceefd6c42b0bed) adiciona duração declarada de episódio desde RSS/JSON Feed até o card publicado, capa do programa como alternativa, inferência de áudio pela extensão quando MIME é ausente/genérico, apenas um anexo tocável por item em Atom/JSON, capa e fonte no mini-player/tocador/tela bloqueada e ação de play em paisagem. A migração é aditiva e a duração é congelada com a ocorrência. Isso corrige lacunas perceptíveis em podcasts, mas **não melhora comprovadamente a continuidade do feed, runway, scroll ou reabertura offline**. O commit declara explicitamente Swift não compilado na máquina autora; os testes novos não têm execução Apple no HEAD.

**Risco novo mais relevante:** o player lê bytes locais e cria `UIImage` de modo síncrono durante acesso a `currentArtwork` no caminho da UI. É correto **não depender da rede**, mas não está demonstrado que a leitura/decodificação não introduza hitch ou trabalho visual tardio ao abrir o player. A nova captura de `UIImage` no callback `MPMediaItemArtwork` também requer compilação Swift 6 e prova no dispositivo. Não declarar bug ou violação render-ready sem trace; medir.

**Decisão:** release não aprovada; tratar a melhoria de podcasts como trabalho de branch não validado. O owner deve priorizar handoff físico + B03 e corrigir SQLite antes de integração; paridade visual de podcast não substitui a experiência principal.

## 3. Mudanças verificadas, consequências e riscos (fato × hipótese)

1. **RSS/Atom/JSON Feed e identidade de mídia — FATO DE CÓDIGO.** [SyndicationTranslator.swift:92–121, 153–170, 198–211, 312–344](https://github.com/wsmontes/feedmine_v2/blob/68b62055/Sources/FeedMineSyndication/SyndicationTranslator.swift#L92-L121) adiciona `itunes:duration`, `duration_in_seconds`, inferência por extensão para MIME genérico e primeiro anexo tocável. [SyndicationPodcastTranslationTests.swift:33–100](https://github.com/wsmontes/feedmine_v2/blob/68b62055/Tests/FeedMineSyndicationTests/SyndicationPodcastTranslationTests.swift#L33-L100) acrescenta fixtures. **Hipótese P2:** provedores com URL sem extensão ou MIME incorreto podem continuar sem áudio reconhecido; não inventar heurística sem corpus. Testar RSS real com query string, MIME genérico, Atom/JSON multi-anexo e declaração de duração ausente/inválida.
2. **Persistência de duração — FATO DE CÓDIGO.** [RuntimeMigrations.swift:781–797](https://github.com/wsmontes/feedmine_v2/blob/68b62055/Sources/FeedMinePersistence/RuntimeMigrations.swift#L781-L797) registra `media-candidate-duration-v1` e `publication-playback-duration-v1`; `published_cards` e `retired_published_cards` ganham coluna anulável. [PublicationStore.swift:106–150](https://github.com/wsmontes/feedmine_v2/blob/68b62055/Sources/FeedMinePersistence/PublicationStore.swift#L106-L150), [PresentationCard.swift:48–115](https://github.com/wsmontes/feedmine_v2/blob/68b62055/Sources/FeedMineRuntime/PresentationCard.swift#L48-L115) congelam/projetam a duração. **Risco P1 (não observado):** migração e leitura de histórico antigo não foram executadas no HEAD; reproduzir upgrade com DB real, `PRAGMA integrity_check`, leitura de cards arquivados e rollback de falha. A duração não entra em `sameMediaCandidate` por decisão explícita: episódio antigo pode permanecer sem duração até nova revisão, não reescrever histórico para maquiar paridade.
3. **Capa do programa — FATO DE CÓDIGO.** [SyndicationTranslator.swift:97–116, 132–135](https://github.com/wsmontes/feedmine_v2/blob/68b62055/Sources/FeedMineSyndication/SyndicationTranslator.swift#L97-L116) coloca capa de canal após imagens próprias e antes do playback; [SyndicationTranslator.swift:346–358](https://github.com/wsmontes/feedmine_v2/blob/68b62055/Sources/FeedMineSyndication/SyndicationTranslator.swift#L346-L358) exclui alguns logos por nome. **Hipótese P2:** heurística por substring pode rejeitar capa legítima ou aceitar logo; validar com fontes reais e falha da primeira imagem, sem rebaixar silenciosamente um card image-bearing.
4. **Player e lock screen — FATO DE CÓDIGO; desempenho e concorrência NÃO MEDIDOS.** [AppComposition.swift:650–667](https://github.com/wsmontes/feedmine_v2/blob/68b62055/FeedMineApp/FeedMineApp/AppComposition.swift#L650-L667) usa `ImageMaterializer.localBytes` e `UIImage(data:)` no loader local. [MediaPlaybackAdapter.swift:53–76, 268–300](https://github.com/wsmontes/feedmine_v2/blob/68b62055/FeedMineApp/FeedMineApp/MediaPlaybackAdapter.swift#L53-L76) mantém **um** cache por chave no adapter, passa `UIImage` ao callback não isolado e publica artwork/resumo. [MiniPlayerBar.swift:22–68](https://github.com/wsmontes/feedmine_v2/blob/68b62055/Sources/FeedMineUI/Media/MiniPlayerBar.swift#L22-L68) exibe capa/fonte com altura fixa. **Hipótese P1:** leitura de arquivo e materialização da imagem no MainActor podem competir com apresentação/scroll; callback de MediaPlayer pode ter exigências Swift 6 de isolamento. Medir latência, CPU/memória e compilar; não adicionar outro cache ou pipeline por precaução.
5. **Landscape play — FATO DE CÓDIGO; possível inconsistência P2.** [FeedItemCardView.swift:163–191](https://github.com/wsmontes/feedmine_v2/blob/68b62055/Sources/FeedMineUI/Cards/FeedItemCardView.swift#L163-L191) faz o tap na miniatura enviar `.openMedia` quando `isAudio`, **sem** verificar `availableActions.contains(.openMedia)`; o botão play e a ação acessível fazem essa checagem. **Hipótese:** um card de áudio temporariamente não tocável pode receber intenção recusada no tap da miniatura. Teste com ação indisponível e VoiceOver; alinhar apenas a decisão do tap ao mesmo contrato, sem criar owner paralelo.
6. **Docs alterados — FATO.** [139040ca](https://github.com/wsmontes/feedmine_v2/commit/139040ca206fb406e7679a2b917c7cc4b4ef2e12) restaura acentos no handoff; [handoff Kiro:178–220](https://github.com/wsmontes/feedmine_v2/blob/68b62055/docs/reviews/2026-11-02-kiro-review-handoff.md#L178-L220) documenta paridade, limites e testes propostos. Não é ADR normativo nem evidência de execução. Comentário introdutório de `MediaPlaybackAdapter.swift` ainda descreve ausência de capa/resumo (linhas 17–20), agora desatualizado; limpeza P2, não gate de release.

## 4. Achados P0/P1/P2 — resolução e pendências

### P0-01 — Handoff físico não prefixado / estabilidade de scroll: ABERTO (fato de código)

[FeedScreenStore.swift:304–329](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineUI/FeedScreenStore.swift#L304-L329) ainda exige `nextIDs.starts(with: previousIDs)`; `[A,B,C] → [B,C,D]` não troca a janela física. Os dois commits Kiro não tocam o writer. [CI #41375292900](https://github.com/wsmontes/feedmine_v2/actions/runs/41375292900): 9 provas geométricas pré-binding, zero pós-binding. **Risco:** fim visual artificial e perda de âncora. **Owner:** provar geometry/identity/offset pós-binding real; commit/rollback da troca pelo único writer, inclusive gesto interrompido. Não usar retry como substituto.

### P0-02 — Runway adaptativa, B03 e integração: ABERTO/NOT_RUN

Sem nova prova B03 30 minutos com scroll real, B04 estabilidade, B05 A→B→A/offline, nem B06 iPhone físico na mesma candidata. Novos podcasts não são prova de runway. **Owner:** congelar corpus/driver/oráculo, executar o trace completo após handoff, registrar oferta, consumo, cards admitidos, pixels locais, network/scroll e continuidade; NOT_RUN não é PASS.

### P0-03 — Redirect público→privado: ABERTO (ordem comprovada, exploração não comprovada)

[FeedDiscoveryTransport.swift:75–91](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L75-L91) chama `session.bytes(for:)` antes de validar host final. Sem diff novo. **Owner:** vetar antes de conectar ao IP/host privado; teste que prova **zero conexões** ao destino vetado.

### P1 — Integração, persistência, experiência e editorial: ABERTO

- **SQLite:** [run #41497618804](https://github.com/wsmontes/feedmine_v2/actions/runs/41497618804) mantém duas falhas, sem nova execução; migrações de podcast aumentam a superfície a validar, não explicam retroativamente o FAIL.
- **Salvos:** [AppComposition.swift:3138–3155 no SHA 9498d165](https://github.com/wsmontes/feedmine_v2/blob/9498d165/FeedMineApp/FeedMineApp/AppComposition.swift#L3138-L3155) remove membership por caixa sem transação abrangente visível no chamador; risco de remoção parcial requer falha injetada.
- **Primeira tela/filtros:** [ColdFeedBootstrap.swift:238–260](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Sources/FeedMineComposition/ColdFeedBootstrap.swift#L238-L260), [CandidateProvider.swift:104–167](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Sources/FeedMineEditorial/CandidateProvider.swift#L104-L167): mecanismos confirmados, fome de filtro/diversidade da primeira tela ainda **hipóteses**. Medir corpus, não fixar K ou timeout.
- **v7:** [MaximumDistanceSequencing.swift:82–95](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Sources/FeedMineEditorial/MaximumDistanceSequencing.swift#L82-L95) prioriza share antes de peso de receita; possível neutralização de preferência requer fixture ponderada. Simulação 3/50 vs 25/50 não é execução Swift.
- **Sheet/retorno, Safari, catálogo PD-10, fontes/coleções/salvos, reabertura offline e 17 falhas históricas do app:** sem aceitação atual numa candidata única. Novos controles de podcast exigem jornada com áudio, rede desligada, dismiss/retorno à mesma `PublicationCardID` e offset.

### P2 — Recursos, UI e release: ABERTO/NOT_RUN

Memória do teto nominal de feed 4 MB, falsos positivos de imagem, player artwork/gestos, export/signing, B06 e archive/TestFlight no HEAD continuam sem prova. A mini-player bar tem altura constante, mas isso não prova que o player não bloqueia o MainActor. Não priorizar cosmética sobre os P0.

**Resolvido em código na Kiro, não aceito em release:** source-share v7, teto nominal 4 MB, filtro de beacons, reader sheet, melhorias UX anteriores e agora duração/capa/áudio de podcasts. **Resolvido em release nesta rodada: nenhum item P0/P1 comprovado.**

## 5. Provas no Mac — comandos PROPOSTOS, NÃO EXECUTADOS

```bash
git fetch origin main monitor/architecture kiro/review-fixes-20261102
git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md
git rev-parse origin/main origin/kiro/review-fixes-20261102
git diff --check 48a69cb95158c4a340620fd5517cb89c823c3e56..68b620554fad5778c8405b3518ceefd6c42b0bed
git diff --stat 48a69cb95158c4a340620fd5517cb89c823c3e56..68b620554fad5778c8405b3518ceefd6c42b0bed
git worktree add --detach /tmp/feedmine-monitor-054 68b620554fad5778c8405b3518ceefd6c42b0bed
cd /tmp/feedmine-monitor-054
xcrun simctl list devices available
# Preparar par catalog.sqlite + manifest conforme README antes do teste do app.
# Substituir <UDID> por simulador iOS 18+ disponível; preservar logs/xcresult.
xcodebuild test -scheme FeedMine-Package -destination 'platform=iOS Simulator,id=<UDID>' -parallel-testing-enabled NO -resultBundlePath /tmp/FeedMine054Package.xcresult CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool get test-results summary --path /tmp/FeedMine054Package.xcresult
xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination 'platform=iOS Simulator,id=<UDID>' -parallel-testing-enabled NO -resultBundlePath /tmp/FeedMine054App.xcresult CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool get test-results summary --path /tmp/FeedMine054App.xcresult
bash scripts/test-export-signing-flags.sh
python3 -m unittest discover -s Tests/ReleaseScripts -p 'test_*.py' -v
# Inspecionar SQLite pré/pós-migração: PRAGMA integrity_check, table_info,
# index_list/index_xinfo, EXPLAIN QUERY PLAN; reproduzir as duas falhas do run 41497618804.
# Podcast: RSS iTunes/JSON/Atom multi-anexo, duração, MIME genérico/ausente,
# upgrade de banco com cards ativos/arquivados, abertura offline e lock screen real.
# Instruments: tempo de localBytes/UIImage(data:), hitches, memória e troca de item.
# XCUI: landscape thumbnail com .openMedia indisponível; VoiceOver; retorno ao mesmo offset.
# Handoff físico pós-binding; depois B03 30min, B04, B05, PD-10 e B06 físico.
scripts/run-discovery-benchmark.sh --gate B03 --profile A --profile B
```

**Aceitação de produto:** feed contínuo sem esgotamento artificial; runway adaptativa; pixels preparados antes da admissão; scroll/identidade/posição estáveis; filtros que reutilizam trabalho; reabertura offline; salvos, coleções e fontes duráveis; descoberta real; uma autoridade por responsabilidade. Testes unitários ou simulações isoladas não certificam esses comportamentos.

## 6. Memória compacta para a próxima execução / handoff

- **Monitor:** 050 `992721f9` → 051 `525b1be2` → 052 `c37cc5e6` → 053 `3d1b6aec` (blob `0ea5a15a`) → **054 (este documento)**.
- **SHAs verificados:** main/integration `2eca5b4f`; Kiro `b610bf7d` → `9498d165` → `48a69cb9` → **`68b62055`** (41 à frente da main); #35 `4f7040ef`, #36 `7afa2571`, #37 `b671147c`; oito PRs draft; issues #7/#18/#27/#32 abertas.
- **CI:** 36 runs; último `41497618804` FAIL no `146915e5`; 1.886 PASS/2 FAIL/4 skipped; sem CI do `68b62055`. Prova host real #37: 9 pré-binding/0 pós-binding.
- **Mudança desta rodada:** 2 commits, 34 arquivos no compare; correção de encoding de handoff e paridade podcasts (duração, capa, player, MIME genérico, Atom/JSON único payload). Sem compile/test Apple. Riscos novos: artwork síncrono/concorrência, migração, gesto landscape sem checagem de disponibilidade.
- **P0 abertos:** handoff físico, B03/B04/B05 integrado, redirect privado pré-conexão. **P1:** SQLite, v7 ponderado, primeira tela/filtros, salvos parciais, sheet/Safari, offline/PD-10, player/migração. **P2:** memória 4 MB, imagem, assinatura, B06.
- **Sequência mínima do owner:** (1) compilar/testar Kiro e isolar SQLite + migrações de podcast + player/gestos; (2) concluir handoff físico único com prova pós-binding; (3) validar B03/B04/B05 e descoberta/catalogo/offline na candidata integrada; (4) B06 no iPhone e release. Não criar caches, filas, timers, retries ou ownership paralelos.
- **Leitura obrigatória pelo OMP:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. O monitor é consultivo, não sincroniza nem notifica executores.
