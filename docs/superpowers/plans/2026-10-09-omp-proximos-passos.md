# FeedMine V2 — Plano dos próximos passos para OMP

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Executar sequencialmente; este pedido é de planejamento, não de implementação nem de envio a outro chat.

**Goal:** Tornar verificável a rodada atual e fechar as lacunas de catálogo, contextos, preparação e mídia antes de avaliar uma versão para usuários.

**Architecture:** Evoluir AcquisitionCoordinator, Editorial, Publication, FeedSession e FeedRunwayDriver existentes. SQLite mantém autoridade durável; Runtime produz projeções e UI apresenta estado local. Mudanças em cauda não vista exigem contrato transacional próprio em Publication, preservando história vista e proveniência.

**Tech Stack:** Swift 6, SwiftUI, actors, GRDB 7.11.1, FeedKit 10.9.4, XCTest/XCUITest, Xcode; iOS 18/macOS 14.

**Spec:** `docs/product/PRODUCT_DECISIONS_2026-10-09.md`, `docs/architecture/PRODUCT_INVARIANTS.md`, `docs/reviews/CODE_REVIEW_COMPARATIVO_2026-10-09.md` (especialmente tabela Resposta), `docs/v1-study/PORT_LOG.md` e contratos arquiteturais relacionados.

## Base e leitura obrigatória

Base inspecionada: `fe91c0f`, igual a `origin/main`. Branch local: `phase/3r11a-media-acquisition-durable-asset`. O plano anterior `2026-10-09-feedmine-v2-correcao-implementacao.md` está baseado em `a259e96`; este plano substitui sua ordem de execução. As decisões PD-1..PD-7 prevalecem sobre propostas anteriores conflitantes.

F01, F03–F10 e F16 estão marcados como corrigidos por código, ainda sem build/test da rodada. Não refazer automaticamente essas implementações. F02 e F15 permanecem pendentes; F11–F14 dependem de medição. PD-5 ainda não tem substituição da cauda publicada não vista. PD-1 exige que edição nova substitua uma ocorrência futura, além de limitar sua quantidade.

Há arquivos não rastreados: `Package.resolved`, `Sources/FeedMineMedia/MediaAcquisition.swift`, `Tests/FeedMineMediaTests/MediaAcquisitionTests.swift` e `docs/superpowers/`. Os arquivos Swift são trabalho anterior e podem interferir na compilação. Este planejamento não executou build/test. Swift 6.3.3 está disponível localmente; isso não comprova compatibilidade do código.

## Global Constraints

- PD-7: sem CI hospedada, PR obrigatório ou aprovação por incremento; docs acompanham o código.
- Antes de push para main: `swift build && swift test && git diff --check`, com SHA e contagem real de testes registrados.
- Manter `Package.resolved` versionado e artefatos de build fora do Git.
- Sem servidor próprio, outro pipeline, cache paralelo ou scheduler paralelo.
- UI não adquire conteúdo, consulta SQLite nem decide ordenação editorial.
- Warm restore local precede HTTP; migrações preservam bancos existentes.
- PD-4: adjacência por SourceID, inclusive entre segmentos; contexto de uma fonte é isento.
- PD-1: mudança material inclui mídia principal; churn de data, whitespace e tracking não é edição material; no máximo uma ocorrência futura por origem, substituível pela mais nova.
- PD-5: cards vistos e posição preservados; atualização de cauda não vista somente com app não visível.
- PD-6: recursos medidos, proteção de bookmarks e limites operacionais; não transformar 16 cards em definição universal de reserva suficiente.
- Nenhum push, TestFlight ou mensagem ao OMP faz parte da criação deste documento.

## Review Focus

1. Cold com uma única fonte rápida: PD-4 continua válida sem esperar todos os feeds (T2).
2. Background ou troca de contexto durante callback suspenso: escopo antigo não instala nem publica no novo (T2/T4).
3. Scroll backward depois de leitura: visto deriva do high-water real, não apenas do anchor atual (T5).
4. Encerramento durante troca da cauda/eviction: banco reabre sem referências inválidas e bookmarks são preservados (T5/T6).
5. Catálogo ausente/corrompido e edição sob tracking churn: erro de distribuição explícito e identidades estáveis (T3/T5).

## Ordem e condição de avanço

T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8. T1/T2 são o primeiro lote obrigatório. Correções encontradas nesses gates precedem novas funcionalidades. Cada lote termina com evidência própria e commit pequeno; não acumular toda a entrega num único commit.

### T1 — Estabelecer baseline limpo e reproduzível

**Files:** `Package.resolved`, arquivos não rastreados de Media, `docs/IOS_RUN.md`, `docs/v1-study/PORT_LOG.md`.
**Interfaces:** nenhuma API nova; produz SHA testado, inventário e relatório de execução.

- [ ] Registrar `git status --short --branch`, `git rev-parse HEAD` e inventário dos arquivos não rastreados.
- [ ] Preservar os dois arquivos Swift não rastreados e o plano anterior em diretório de evidência externo; comparar com MediaHTTPFetcher/MediaPrefetcher antes de incorporá-los. Testar a base rastreada em checkout isolado a partir de fe91c0f. Não apagar trabalho nem compilar baseline misturado com esses arquivos.
- [ ] Conferir pins 7.11.1/10.9.4 e versionar o lockfile raiz no incremento apropriado.
- [ ] Executar `swift package describe`, `swift build`, `swift test`, `git diff --check`. Guardar saída completa, duração e contagem real; corrigir erros reproduzíveis sem excluir testes.
- [ ] Descobrir destino com `xcrun simctl list devices available`; executar build e test do scheme FeedMine conforme os comandos ao final.
- [ ] Atualizar docs separando resultado histórico 3R10, rodada ainda não validada e resultado atual. README ainda afirma mídia fora do gate e deve refletir o código comprovado.

**Aceite:** pacote e app compilam/testam a base identificada; falhas ambientais não são registradas como PASS. Nenhuma feature nova antes desse resultado.

### T2 — Provar as correções da rodada 3

**Files:** `Tests/FeedMineRuntimeTests/{MediaPrefetcherTests,RunwayPolicyTests,RunwayControllerTests}.swift`, `Tests/FeedMineCompositionTests/{ColdFeedBootstrapTests,FeedRunwayDriverTests,RunwayAcquisitionCycleTests}.swift`, `FeedMineApp/FeedMineAppTests/{CompositionTests,FeedMineUITests}.swift`; corrigir apenas os owners envolvidos em falhas reproduzidas.
**Interfaces:** preservar interfaces atuais de prefetch, driver, cold e lifecycle. Produz matriz F01/F03–F10/F16 com evidência executada.

- [ ] Verificar testes existentes antes de acrescentar casos equivalentes; acrescentar somente provas ausentes abaixo.
- [ ] F03/F04: fetch suspenso até sinal explícito; deadline libera chamador antes desse sinal; falha transitória permite retry e falha permanente termina sem looping. Usar tempo controlado quando suportado, tolerância documentada para tempo real.
- [ ] F05/F07: prefetch usa candidatos editoriais do contexto; edição de mídia principal reaparece, churn não reaparece e não há duas ocorrências futuras da mesma origem.
- [ ] F01/F06: leitor parado abastece até a reserva atual configurada de 16 quando supply elegível existe; primeira publicação aproveita fonte rápida sem esperar lenta, mas não publica adjacência proibida.
- [ ] F08/F09/F16: todas as fontes falham e recuperam sem gesto; cooldown expira uma vez; background impede oportunidade agendada; foreground recupera sem duplicação.
- [ ] F10: toque resolve o PublicationCardID para o artigo correto; callback de associação encerrada é ignorado.
- [ ] Executar filtros afetados e depois regressão completa; registrar também offline relaunch, backward e estabilidade visual.

**Aceite:** cada finding tem teste/log verificável; corrigido por código e confirmado por execução são estados distintos. Não usar contagens históricas como resultado atual.

### T3 — Distribuir o catálogo real (F02 / PD-2)

**Files:** `FeedMineApp/FeedMineApp/TrustedFeeds.swift`, `FeedMineApp/FeedMineApp.xcodeproj/project.pbxproj`, `Sources/FeedMinePersistence/LegacyCatalogReader.swift`, `Sources/FeedMineComposition/LegacyCatalogImport.swift`, testes LegacyCatalogReaderTests/LegacyCatalogImportTests; recurso `FeedMineApp/FeedMineApp/Resources/catalog.sqlite` caso escolhido empacotamento.
**Interfaces existentes:** `LegacyCatalogReader.init(catalogURL:)`, `sourceCount()`, `sources(after:limit:onlyDefaultEnabled:mediaKinds:)`; `LegacyCatalogImport.entry(_:)` conserva derivação estável.

- [ ] Localizar o catálogo V1 autorizado no ambiente/repositório V1; registrar origem, checksum, tamanho e schema. Não fabricar catálogo nem substituir o conjunto real por lista inventada.
- [ ] Resolver distribuição antes de implementar: bundle/LFS ou download versionado verificável. Bundle é a proposta inicial para manter primeiro uso offline; LFS exige confirmar suporte do remoto. Se arquivo ou decisão faltar, marcar apenas esta tarefa bloqueada e seguir provas independentes.
- [ ] Testar recurso ausente/corrompido/schema incompatível; fallback BBC permitido em desenvolvimento, ausência explícita em build para usuários.
- [ ] Testar que recompilar catálogo preserva SourceID/BindingID/TargetID para a mesma key, inclusive quando request_url muda.
- [ ] Adicionar recurso à distribuição escolhida e verificar bytes reais no app instalado; não basta um pointer LFS nem uma referência no projeto.
- [ ] Provar consultas paginadas e registro de targets limitado à seleção ativa; não registrar 88 mil fontes na inicialização.

**Aceite:** instalação obtém catálogo real verificável e não cai silenciosamente em duas BBC; identidade e limites comprovados.

### T4 — Seleção de fontes e contextos reutilizáveis (F15)

**Files:** `Sources/FeedMineDomain/FeedContext.swift`, `FeedMineApp/FeedMineApp/AppComposition.swift`, `Sources/FeedMineRuntime/FeedSession.swift`, `Sources/FeedMineUI/{FeedScreen,FeedScreenStore}.swift`; novos componentes de seleção em FeedMineUI e armazenamento de preferências em FeedMinePersistence, com nomes/interfaces definidos em subplano antes de implementação.
**Interfaces existentes:** `FeedContextRequest.main`, `.source(SourceID)`, `.search(SearchContext)`; `SearchContext.init?(query:)`; `ContextKey` mantém semântica atual, inclusive query original.

- [ ] Escrever subplano com contrato de preferências duráveis, fonte habilitada, revisão editorial, seleção ativa e lifecycle de associação. Usar requisitos existentes; não introduzir ranking ou filtros sem significado definido.
- [ ] Testar A→B→A offline: mesmo histórico compatível e posição restaurada; preferências sobrevivem relaunch.
- [ ] Testar callback tardio de A após B: não instala em B, sem descartar supply canônico válido já adquirido.
- [ ] Integrar UI de fontes, contexto main/source e busca local pelo pipeline existente. Busca vazia/whitespace é recusada pelo contrato; nenhum HTTP disparado pela View.
- [ ] Testar PD-4 no main e exceção source; alteração de seleção invalida somente planos incompatíveis, preservando histórico.
- [ ] Executar testes de contrato, persistência e XCUI da troca/reentrada.

**Aceite:** usuário escolhe fontes, troca contexto e retorna offline sem perda de posição ou instalação fora de escopo.

### T5 — Completar sucessão da cauda não vista (PD-1 / PD-5)

**Files:** `Sources/FeedMinePersistence/PublicationStore.swift` e migrações existentes; `Sources/FeedMinePublication/{PublicationCoordinator,PublicationHistory}.swift`, `Sources/FeedMineRuntime/{FeedSession,MediaTidy}.swift`; testes Publication/Persistence e `Tests/ArchitectureSmokeTests/EditedArticleRecurrenceTests.swift`.
**Interfaces:** contrato novo exige subplano antes do código; Publication é único owner. Entradas obrigatórias: Edition/Context, high-water visto durável, estado de visibilidade, versão esperada da cauda e candidatos preparados; resultado deve distinguir applied/stale/ineligible. Definir assinatura concreta após revisar schema.

- [ ] Auditar F07: impedir duplicata futura não comprova substituição pela edição mais nova. Testar E1 publicada não vista, E2/E3 recebidas e leitor parado; a cauda deve conter somente E3.
- [ ] Testar leitura avançada seguida de backward: cards já vistos não ficam elegíveis a alteração pelo anchor menor.
- [ ] Testar mídia tardia com app visível: IDs, conteúdo, geometria e posição vistos permanecem iguais.
- [ ] Definir sucessão transacional da cauda no subplano, incluindo identidades novas, fences e compatibilidade de restore; atualizar conflitos INV-08/09 com PD-5 explicitamente.
- [ ] Implementar substituição apenas não visível, mantendo PD-4 nas fronteiras; foreground concorrente invalida operação ainda não aplicada.
- [ ] Testar rollback/crash/reopen e proveniência; edição material no histórico visto continua criando nova ocorrência conforme PD-1.

**Aceite:** edição mais nova substitui futuro não visto; mídia tardia melhora somente cauda autorizada; história vista e posição são preservadas após relaunch.

### T6 — Retenção por fatos reais (F12 / PD-6)

**Files:** `Sources/FeedMineRuntime/MediaTidy.swift`, `Sources/FeedMineMedia/{MediaRetention,MediaHousekeeping}.swift`, consultas de PublicationStore; testes MediaHousekeepingTests e MediaPolicyResolverTests.
**Interfaces existentes:** `MediaTidy.run(visibleKeys:supplyHeadLimit:deadline:)`; ampliar em subplano para fatos de uso persistidos, sem dependência Media→Publication.

- [ ] Inventariar suporte real a bookmarks; não declarar proteção sem estado durável. Se inexistente, especificar marcação mínima com persistência ou registrar dependência explícita.
- [ ] Testar classes reais: far-future unseen → old seen → recent seen; bookmarked nunca sai, inclusive quando referências compartilham asset.
- [ ] Substituir aproximação por data de arquivo por fatos de publicação/leitura/uso; preservar janela atual e assets protegidos.
- [ ] Testar pressão de espaço, erro de remoção e reopen com asset faltante; renderer conserva geometria e não inicia download.

**Aceite:** eviction demonstrável por fatos, sem referências quebradas silenciosas nem perda de bookmark.

### T7 — Medir antes de otimizar (F11/F13/F14 e adaptividade)

**Files:** `Sources/FeedMineRuntime/{FeedSession,PresentationImage,PreparationProgress,RunwayPolicy}.swift`, `Sources/FeedMinePersistence/ContentStore.swift`; testes correspondentes, `docs/reviews/OMP_VALIDATION_2026-10-09.md`.
**Interfaces:** preservar owners; métricas de teste/DEBUG não são autoridade semântica.

- [ ] Medir projeção/decode repetido em ida/volta: latência, contagem de decode, CPU e memória, no mesmo aparelho e corpus.
- [ ] Medir candidateWindow com corpus pequeno e catálogo real/contexto específico: consultas por janela, linhas examinadas e p50/p95; usar plano de consultas antes de alterar índices.
- [ ] Verificar F13: feed HTTP bem-sucedido sem conteúdo elegível não significa pronto; estimate depende também de cards preparados e fontes contribuintes.
- [ ] Medir reserve=16 com viewport grande, scroll rápido e aquisição lenta; se insuficiente, derivar meta dos fatos reais de viewport/consumo/latência, mantendo teto de recursos.
- [ ] Para cada alteração justificada, adicionar regressão comportamental ou benchmark comparável e registrar antes/depois. Não introduzir cache global por intuição.

**Aceite:** F11–F14 possuem dados e conclusão; desempenho e reserva satisfazem cenários medidos sem degradar invariantes.

### T8 — Fechamento integrado e documentação

**Files:** `docs/IOS_RUN.md`, `docs/v1-study/PORT_LOG.md`, `docs/reviews/CODE_REVIEW_COMPARATIVO_2026-10-09.md`, `README.md` e relatório OMP acima.
**Interfaces:** nenhuma API nova; produz pacote de evidência e lista explícita de bloqueios restantes.

- [ ] Executar pacote completo e app build/test no SHA final; incluir teste de migração de banco anterior sem apagar runtime.sqlite.
- [ ] Executar checklist do PORT_LOG no simulador e casos de recursos/rede em iPhone: cold, slow image/feed, recuperação autônoma, idle reserve, background, offline relaunch, A→B→A, edição/material, bookmarks e scroll prolongado.
- [ ] Guardar logs/xcresult/screenshots fora do repo; relatório registra SHA, dispositivo/OS, comandos, contagens, resultados, limitações e referências às evidências.
- [ ] Atualizar tabela F01–F16 com estados comprovados, PD-1..PD-7 com pendências e README/IOS_RUN com comportamento atual.
- [ ] Se faltar catálogo/dispositivo ou prova de invariantes, concluir entregas verificadas e declarar bloqueio específico; não classificar release como pronto.

**Aceite:** funcionamento integrado reproduzível e documentação coerente. Publicação/push/TestFlight somente quando solicitado; cada build de distribuição leva SHA.

## Comandos de execução

Executar no checkout de trabalho; substituir SIMULATOR_UUID por destino descoberto e usar diretório de evidência exclusivo. Não reutilizar o UUID histórico sem confirmação.

```sh
swift package describe
swift build
swift test
swift test --filter MediaPrefetcherTests
swift test --filter ColdFeedBootstrapTests
swift test --filter FeedRunwayDriverTests
swift test --filter EditedArticleRecurrenceTests
git diff --check
xcrun simctl list devices available
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' -derivedDataPath /tmp/feedmine-omp-derived CODE_SIGNING_ALLOWED=NO build
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' -derivedDataPath /tmp/feedmine-omp-derived -parallel-testing-enabled NO -resultBundlePath /tmp/feedmine-omp-validation.xcresult CODE_SIGNING_ALLOWED=NO test
```

## Instrução curta para iniciar o OMP

Leia este plano e as decisões PD-1..PD-7. Execute primeiro T1/T2 sobre fe91c0f ou descendente identificado; preserve os arquivos não rastreados sem incorporar automaticamente a implementação antiga de MediaAcquisition. Confirme por build/test as correções já integradas antes de novas features. Prossiga na ordem do plano, com commits pequenos, docs e evidência por entrega. Para T4/T5, escreva primeiro o subplano das interfaces e migrações. Não refaça o plano antigo, não crie pipelines paralelas e não declare PASS sem execução. Relate bloqueios específicos e continue trabalho independente autorizado.
