# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 027 · Vancouver, 24/out/2026, 19:39 PDT.** Canal consultivo monitor/architecture; o OMP precisa fazer fetch e ler o documento, sem notificação automática.

## Base, intervalo e escopo

**Anterior:** revisão 026, commit [859c34ce](https://github.com/wsmontes/feedmine_v2/commit/859c34ce925e6699411c950a4a2cb0bd89133a9c), blob 9c736c0b35f9abbf5290b473b31a95179e177936, 24/out 11:45 PDT. **Janela:** 24/out 11:45–19:39 PDT.

- **main** permanece em fb8e65ff5a5e83ae85c9061996aaa0ebf2b7ca48 (compare idêntico). **codex/feedmine-next-internal** permanece em d6a052667abfd478d5e09f13afe0e01685ef9344 (compare idêntico). O fato de ambas não avançarem NÃO significa ausência de trabalho corrente.
- **Nova linha ativa examinada:** [product/integrity-20261024@d6ef2452](https://github.com/wsmontes/feedmine_v2/tree/product/integrity-20261024), 13 commits à frente de d6a05266, incluindo código, testes, diretiva do dono e handoff ([diff](https://github.com/wsmontes/feedmine_v2/compare/d6a05266...d6ef2452)). Último commit 24/out 15:18 PDT.
- **Release ativa:** [release/build-56@cede37f6](https://github.com/wsmontes/feedmine_v2/tree/release/build-56), 13 commits à frente de d6a05266 ([diff](https://github.com/wsmontes/feedmine_v2/compare/d6a05266...cede37f6)). **Tag remota** [ios/1.0-build.56-1fe0afaf](https://github.com/wsmontes/feedmine_v2/tree/ios/1.0-build.56-1fe0afaf) resolve para 1fe0afaf811637307fcbc2dd73d1d5085028dc94. Branch de release e branch de produto estão **divergentes**, sete commits exclusivos de cada lado desde o ancestral comum da comparação ([compare](https://github.com/wsmontes/feedmine_v2/compare/release/build-56...product/integrity-20261024)).
- **PR [#5](https://github.com/wsmontes/feedmine_v2/pull/5):** único aberto, auditoria histórica da build 54, não candidato corrente. Linhas 54 (3eee1935, 15d8bbbc, 145d12a3, 77e9f7d1) e integration/candidate@1b990306, integration/chatgpt@8203d439 continuam históricas nesta janela.
- **Normas relidas:** [North Star](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_NORTH_STAR.md), [PD-1–PD-11](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz de execução](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [invariantes](https://github.com/wsmontes/feedmine_v2/blob/main/docs/architecture/PRODUCT_INVARIANTS.md), [B01–B06](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md), [novas frentes](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/docs/product/NOVAS_FRENTES_PARA_O_CODEX.md). A [diretiva de 24/out](https://github.com/wsmontes/feedmine_v2/blob/d6ef2452/coordination/DIRECTIVA-2026-10-24-shuffle-e-volume.md) é direção posterior do dono para imagem, volume e shuffle, não um blueprint antigo.

## Resumo executivo — impacto de produto

**Mudança relevante não capturada na revisão 026:** há uma build 56 interna e uma nova linha de integridade. A entrega corrigiu estaticamente o vazamento de manchetes cirílicas em canais declarados ingleses, traduções, a semântica de falhas de feed/biblioteca e plural. O [relatório da build 56](https://github.com/wsmontes/feedmine_v2/blob/cede37f6/docs/reviews/2026-10-24-build-56-internal.md) relata 1.653 testes SwiftPM (0 falhas, 1 skip), 118 CompositionTests, simulador e TestFlight VALID/IN_BETA_TESTING; **são evidências registradas pelo executor, não testes executados por este monitor**. B06 físico continua NOT_RUN.

**Achado novo de release:** a build 56 efetivamente tagueada em 1fe0afaf **NÃO contém** os commits posteriores de tolerância de mídia 12 s (70178f3f), separação do bootstrap da primeira tela (ea415ac2), remoção da cápsula que cobria cartas (2cde7f32) e limpeza do onboarding (ce8878e1). São correções da linha product/integrity **pós-corte**; não atribuí-las ao binário TestFlight 56. O handoff lista as correções como entregues no trabalho, mas precisa distingui-las explicitamente da distribuição. [Prova no código tagueado: 5 s](https://github.com/wsmontes/feedmine_v2/blob/1fe0afaf/FeedMineApp/FeedMineApp/AppComposition.swift#L3325-L3338) versus [12 s na linha atual](https://github.com/wsmontes/feedmine_v2/blob/d6ef2452/FeedMineApp/FeedMineApp/AppComposition.swift#L3332-L3349); [cápsula sempre presente na 56](https://github.com/wsmontes/feedmine_v2/blob/1fe0afaf/Sources/FeedMineUI/FeedScreen.swift#L123-L128) versus [condicional após correção](https://github.com/wsmontes/feedmine_v2/blob/d6ef2452/Sources/FeedMineUI/FeedScreen.swift#L123-L136).

**Nova direção do dono, mais importante que tuning de prazo:** nenhuma carta perde imagem declarada por pressa; adquirir/preparar muito mais que o consumo e passar adiante somente cartas completas; maximizar distância entre tipo, tema e fonte. A medição corrigida mostra **oferta declarada abundante, mas estoque efetivamente preparado limitado**. Não concluir que o scheduler está ignorando imagens já prontas: a seleção já suspende revisões não prontas antes do ranking.

## Mudanças verificadas e limites

1. [0d91b9f6](https://github.com/wsmontes/feedmine_v2/commit/0d91b9f6b67851d77468eb83872e8c1e230d8042) adiciona ContentScriptEligibility e o gate de script na admissão. [ReaderFilterEligibility.swift:36–74](https://github.com/wsmontes/feedmine_v2/blob/d6ef2452/Sources/FeedMineEditorial/ReaderFilterEligibility.swift#L36-L74). **Ganho:** manchete cirílica declarada como inglês é recusada antes da publicação; relato de instalação limpa: 26 adquiridas, zero publicadas. **Limite:** é detector de sistema de escrita, não de idioma; espanhol em alfabeto latino declarado inglês continua admitido por desenho. Não alegar filtro linguístico completo.
2. [95a3ec22](https://github.com/wsmontes/feedmine_v2/commit/95a3ec22) introduz semântica de falha de tentativa versus falha do feed e biblioteca vazia versus leitura falhada. [FeedFailurePresentation.swift](https://github.com/wsmontes/feedmine_v2/blob/d6ef2452/Sources/FeedMineUI/FeedFailurePresentation.swift). **Ganho:** não cobrir feed utilizável com falha global; relatório declara 13/13 testes focais e salvo após relaunch.
3. [e526b08f](https://github.com/wsmontes/feedmine_v2/commit/e526b08f), [6b27bca5](https://github.com/wsmontes/feedmine_v2/commit/6b27bca5) e [d8600f2c](https://github.com/wsmontes/feedmine_v2/commit/d8600f2c) corrigem tradução, plural e aviso V1. São melhorias reais, mas não substituem prova de continuidade ou diversidade.
4. [70178f3f](https://github.com/wsmontes/feedmine_v2/commit/70178f3fc2337031c4ef4aebbdf60e89b65482e8) altera apenas a tolerância **inicial não medida** de mídia, 5→12 s, preservando a derivação após medição. [ea415ac2](https://github.com/wsmontes/feedmine_v2/commit/ea415ac2175e01820efd34832c1865bb6ae0a5fd) separa bootstrap D4 em 5 s, mas **o limite de primeira tela continua acoplado a preparationWaitSeconds quando a associação existe** ([AppComposition.swift:127–134](https://github.com/wsmontes/feedmine_v2/blob/d6ef2452/FeedMineApp/FeedMineApp/AppComposition.swift#L127-L134)). Não declarar D4 resolvido.
5. [2cde7f32](https://github.com/wsmontes/feedmine_v2/commit/2cde7f32826c8de7f27cb79f0ddc960693eabc03) só mostra cápsula de trabalho quando não há cartas; [ce8878e1](https://github.com/wsmontes/feedmine_v2/commit/ce8878e1) remove skeletons decorativos no onboarding. Ambos **pós-build 56**.
6. [Diretiva de shuffle e volume](https://github.com/wsmontes/feedmine_v2/blob/d6ef2452/coordination/DIRECTIVA-2026-10-24-shuffle-e-volume.md) e [handoff](https://github.com/wsmontes/feedmine_v2/blob/d6ef2452/coordination/HANDOFF-2026-10-24-codex.md) foram lidos como novas evidências e orientação, **não alterados pelo monitor**. A diretiva corrigiu uma inferência anterior errada: 6.515 revisões com candidato de imagem são oferta **declarada**, não estoque pronto.

## Achados P0/P1/P2 — fato versus hipótese

### P0 PRODUTO — continuidade e runway ainda não demonstradas

**FATO relatado no iPhone 55:** o leitor alcança a cauda antes da reposição. **FATO novo:** na execução Debug limpa, 941 cartas publicadas, 558 tentativas com imagem declarada, 276 ready-image e 280 encerradas por deadline; **276/276 ready-image foram publicadas** após join por revisão com UUID normalizado. A execução Release limpa de 56 relatou 307/883 cartas com imagem (34,8%). [Relatório de mídia](https://github.com/wsmontes/feedmine_v2/blob/cede37f6/docs/reviews/2026-10-24-build-56-internal.md#L53-L108). **Consequência:** os dados NÃO demonstram descarte de imagem pronta entre preparação e publicação; apontam gargalo de preparo/estoque. **HIPÓTESE aberta:** o runway não sustenta estoque de cartas completas suficiente durante consumo rápido, especialmente quando mistura de tipos e temas é exigida. **Owner:** medir na mesma sessão demanda→aquisição→candidato declarado→ready-image→ativo local→publicação→admissão visual, com profundidade pronta à frente do cursor e consumo rápido/lento/repouso; usar owner existente, sem timer, fila ou retry paralelos.

### P0 SEGURANÇA — redirecionamento privado continua sem bloqueio pré-conexão

**FATO estático:** [FeedDiscoveryTransport.swift:75–90](https://github.com/wsmontes/feedmine_v2/blob/d6ef2452/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L75-L90) chama URLSession.bytes(for:) antes de validar host final. Arquivo não mudou na linha nova. **RISCO:** redirect automático pode contactar host vedado antes da recusa. **Prova necessária:** servidor privado instrumentado recebe zero requisições, inclusive redirect em cadeia; público permitido continua funcional. Não declarar exploração efetiva sem reprodução.

### P1 NOVO — identidade do binário 56 versus correções posteriores

**FATO confirmado por tag, ancestry e código:** tag 56=1fe0afaf, mediaWaitBootstrapSeconds=5; 12 s e UI corrigida vivem só em product/integrity. [Compare exato](https://github.com/wsmontes/feedmine_v2/compare/1fe0afaf...product/integrity-20261024). **RISCO:** atribuir ao TestFlight 56 testes e comportamento de commits que não estão nele; diagnosticar incorretamente D4 ou imagens. **Owner:** matriz por SHA/binário (56 tagueado, pós-56 não distribuído), anotar a proveniência em cada métrica, sem cortar outro build sem autorização. Não é evidência de bug adicional no binário.

### P1 NOVO — shuffle amplo não pode ser obtido apenas reordenando a oferta publicada

**FATO medido:** fila de 1.425 cartas = 936 áudio, 488 sem mídia, 1 vídeo; 104 fontes; repetição média de tipo 2,0 (mínima 1), fonte 19 (mínima 2). [Diretiva](https://github.com/wsmontes/feedmine_v2/blob/d6ef2452/coordination/DIRECTIVA-2026-10-24-shuffle-e-volume.md). **DEDUÇÃO MATEMÁTICA:** com 936 cartas de áudio e só 489 não áudio, mesmo a melhor permutação tem pelo menos **446 pares áudio-áudio adjacentes** (936 - (489 + 1)); não se pode exigir distância mínima >1 nessa mesma composição. **FATO de código:** [SelectionDiversity.swift:14–18](https://github.com/wsmontes/feedmine_v2/blob/d6ef2452/Sources/FeedMineEditorial/SelectionDiversity.swift#L14-L18) conhece source/provider/subjects, **não tipo**; [SelectionEngine.swift:116–144](https://github.com/wsmontes/feedmine_v2/blob/d6ef2452/Sources/FeedMineEditorial/SelectionEngine.swift#L116-L144) usa v5 como desempate suave depois da relevância. **Owner:** medir oferta **pronta por tipo/tema/fonte** e potencial de alternância antes de definir v6; ampliar aquisição/preparo para diversificar o conjunto elegível, depois maximizar distância condicional à oferta. Preservar PD-4 (zero fontes adjacentes, salvo contexto single-source), não reduzir runway artificialmente para satisfazer métrica impossível. Versão nova de sequenciamento e fatos congelados, sem reescrever v2–v5.

### P1 — mídia: alterar timeout sozinho tem retorno limitado e risco de confundir causas

**FATO relatado em três braços de Debug, três minutos:** tolerância ~5/20/60 s → cartas com imagem 32,2%/40,0%/41,1%; cortes por deadline 50,2%/30,6%/9,1% entre tentativas com imagem declarada. [Relatório: apêndice](https://github.com/wsmontes/feedmine_v2/blob/cede37f6/docs/reviews/2026-10-24-build-56-internal.md#L90-L108). **INTERPRETAÇÃO:** +1,1 ponto percentual de cobertura de 20→60 s apesar de 21,5 pontos de queda de deadline; uma espera maior não prova estoque pronto maior nem melhora de primeira tela. Tempos de primeira carta 6,1 s versus 1,9 s são não monotônicos entre braços e não estabelecem causalidade de latência. **Owner:** obedecer à diretiva posterior: imagem declarada não é sacrificada por pressa; medir estoque pronto e throughput por coorte antes de ajustar tolerâncias. A mudança de 12 s é pós-56 e não equivale a piso da derivação.

### P2 NOVO — script sérvio latino classificado como cirílico

**FATO de código:** [ContentScriptEligibility.swift:21–47](https://github.com/wsmontes/feedmine_v2/blob/d6ef2452/Sources/FeedMineDomain/ContentScriptEligibility.swift#L21-L47) contém case "sr-latn" como latino, mas [baseLanguage:50–57](https://github.com/wsmontes/feedmine_v2/blob/d6ef2452/Sources/FeedMineDomain/ContentScriptEligibility.swift#L50-L57) remove tudo depois de "-", de modo que "sr-Latn" vira "sr" e cai no ramo cirílico. **Consequência provável e discriminante:** texto sérvio em Latin declarado sr-Latn é recusado como incompatível mesmo com metadado correto; o ramo sr-latn é inalcançável. **Owner:** respeitar subtags de script antes de reduzir ao idioma base; testar sr-Latn versus sr-Cyrl e idioma regional sem subtag. Não transformar a heurística de escrita em detector semântico de idioma.

### P1 ANTERIORES — não encerrados por esta linha

**FATO por diff:** nenhum arquivo de filtro NF-03 mudou desde d6a05266; persistem os caminhos de preset salvo bloqueante e possível confirmação concorrente ([FilterSheetView.swift:151–166](https://github.com/wsmontes/feedmine_v2/blob/d6ef2452/Sources/FeedMineUI/Filters/FilterSheetView.swift#L151-L166), [AppComposition.swift:1021–1041](https://github.com/wsmontes/feedmine_v2/blob/d6ef2452/FeedMineApp/FeedMineApp/AppComposition.swift#L1021-L1041)). D4/scroll ±1 pt, reabertura offline, salvos V1→V2, catálogo PD-10, vídeo/YouTube e diversidade por tema continuam sem certificação end-to-end desta linha. As correções estáticas de adiamento A→B→A e retenção editorial da 55 continuam reconhecidas, sem nova contraprova.

## Release e testes: separar executado, relatado e não executado

- **Executado por este monitor:** leitura GitHub de branches, commits, diffs, código, documentos, tag e PR. **Nenhum** Swift, XCTest, xcodebuild, simulador, iPhone ou benchmark foi executado aqui.
- **Relatado pelo executor:** build 56 TestFlight VALID/IN_BETA_TESTING, 1.653 SwiftPM (0 falhas, 1 skip), 118 CompositionTests, 13 FeedPresentationStateTests e simulador Release. Evidências estão no relatório da build 56, não em artefatos reproduzidos independentemente.
- **Não demonstrado:** B01–B06/PD-10 completos no mesmo SHA/binário; B06 físico NOT_RUN; comportamento de pós-56 no TestFlight 56; throughput do novo volume/shuffle. Mudança anterior de driver B05 permanece sujeita a auditoria; não alterar oráculos congelados.
- **Risco de regressão de nova v6:** identidade e ordem de Editions já publicadas, PD-4 nas bordas de segmento, starvation por regra editorial impossível, persistência/posição após relaunch e gesto sem I/O. O versionamento deve preservar as edições anteriores.

## Handoff mínimo ao Mac — comandos e provas

    git fetch origin main monitor/architecture codex/feedmine-next-internal product/integrity-20261024 release/build-56 --tags
    git rev-parse origin/main origin/codex/feedmine-next-internal origin/product/integrity-20261024 origin/release/build-56
    git rev-parse ios/1.0-build.56-1fe0afaf
    git merge-base origin/product/integrity-20261024 origin/release/build-56
    git diff --check d6a05266..origin/product/integrity-20261024
    git diff --stat d6a05266..origin/product/integrity-20261024
    git diff ios/1.0-build.56-1fe0afaf..origin/product/integrity-20261024 -- FeedMineApp/FeedMineApp/AppComposition.swift Sources/FeedMineUI/FeedScreen.swift
    git show ios/1.0-build.56-1fe0afaf:FeedMineApp/FeedMineApp/AppComposition.swift | grep mediaWaitBootstrapSeconds
    # Em worktree isolada da linha atual, após checar espaço em disco:
    git worktree add --detach /tmp/feedmine-monitor-027 origin/product/integrity-20261024
    cd /tmp/feedmine-monitor-027
    swift build
    swift test
    xcrun simctl list devices available
    xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination 'platform=iOS Simulator,id=<UDID>' -parallel-testing-enabled NO -resultBundlePath /tmp/fm-monitor-027.xcresult CODE_SIGNING_ALLOWED=NO test

**Provas discriminantes para o owner, nesta ordem:** (1) duas coortes de consumo com profundidade pronta/cauda e traço completo até UI; (2) estoque pronto por tipo/tema/fonte, replay v5→v6 com mesmo supply e limite matemático explícito, PD-4 zero adjacentes; (3) teste de sr-Latn e de idiomas latinos declarados errados; (4) A→B→A e preset salvo durante replacement; (5) D4/scroll/posição/relaunch offline; (6) B01–B05 sem mexer em benchmark/oráculo e B06 físico; (7) redirect vedado sem conexão; (8) comparar archive/tag/recibo TestFlight antes de atribuir correções ao 56. Guardar logs/xcresult com SHA e dispositivo, não transportar PASS entre árvores.

## Memória compacta de pendências e SHAs

Monitor 023 039bf1d5 → 024 918a2c8b → 025 309c1d20 → 026 859c34ce → **027 (este texto)**. main fb8e65ff imóvel; 55 distribuída 3c5bdc11; codex/feedmine-next-internal d6a05266 imóvel; **produto novo d6ef2452**; **release/docs cede37f6**, **binário 56 tag 1fe0afaf**. Históricas 54: 3eee1935 / 15d8bbbc / 145d12a3 / 77e9f7d1. **Resolvido estaticamente:** A→B→A de mídia, elegibilidade editorial da 55, NF-03 botão Concluído, gate de script cirílico, falha tentativa≠feed, traduções. **Abertos:** P0 cauda/runway e SSRF; P1 proveniência pós-56, shuffle e volume pronto, presets/concorrência, D4/scroll/offline, B05 auditável, B06/PD-10 e multimídia; P2 sr-Latn. O OMP deve fazer fetch e ler, sem presumir notificação.

**Único arquivo autorizado ao monitor:** docs/reviews/ARCHITECTURE_MONITOR.md nesta branch.