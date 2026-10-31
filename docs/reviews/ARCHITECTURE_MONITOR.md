# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 047 · Vancouver, 30/10/2026, 23:42 PDT (horário de início da revisão).** Parecer externo consultivo; **NÃO é certificação de release**. O OMP precisa fazer `git fetch origin monitor/architecture` e ler explicitamente este arquivo; não há notificação automática.

## 1. Memória, janela incremental e autoridade

**Memória persistente efetivamente lida primeiro:** revisão 046, `monitor/architecture@13ef6baae61f994c3bbdd0848bbe3d38221bd557`, blob `7f778c7fbdd57ce313ee890e9acce2264d6b9ce4`. **Janela:** 30/out 21:45–23:42 PDT (31/out 04:45–06:42 UTC). Conector GitHub: relatório anterior, PRs, diffs, arquivos e testes, issues, branches, documentação normativa, jobs e logs reais de Actions. Sem checkout Mac, testes próprios, iPhone, B03 ou B06.

**Mudanças verificadas:** [PR #26](https://github.com/wsmontes/feedmine_v2/pull/26) avançou **4 commits**, `29153ea2` → **`dc9bb42ac4df87ba14114fec2091385ea7b2c135`**, com [diff incremental](https://github.com/wsmontes/feedmine_v2/compare/29153ea24035d8bb8b65db145b66237eb9d5f6fa...dc9bb42ac4df87ba14114fec2091385ea7b2c135). Novo [issue #27](https://github.com/wsmontes/feedmine_v2/issues/27) (P1 editorial) e [PR #28](https://github.com/wsmontes/feedmine_v2/pull/28), draft empilhado em #26, **9 commits**, HEAD **`dbf5f334a4c0ab28fac97de9a06d953212a0bc96`**, [diff #26→#28](https://github.com/wsmontes/feedmine_v2/compare/dc9bb42ac4df87ba14114fec2091385ea7b2c135...dbf5f334a4c0ab28fac97de9a06d953212a0bc96) (7 arquivos, incluindo 5 fontes de produção e 2 de testes, além do workflow). #27 é **issue**, não PR. Não houve merge na main.

**SHAs de referência, consultados novamente:** `main@fb8e65ff5a5e83ae85c9061996aaa0ebf2b7ca48` (idêntica); #6 F13 `c0392741`, #8 `83f05671`, #9 `3e863a1c`, #10 `f4f041c0`, #11 `9bd7b345`, #12 `95b894f7`, #13 `cf2ce6a8`, #14 `e02a69ae`, #15 `18ad774b`, #16 `72d067bf`, #17 `93e6cbbe`, #19 `7b3018d3`, #20 `e02879b1`, #21 `267e121f`, #22 `3bc00208`, #23 `c7f54745`, #24 `91dc980f`, #25 `67e8d4cf`, **#26 `dc9bb42a` e #28 `dbf5f334`**. Os PRs examinados continuam draft. Comparações explícitas confirmaram **identical** em `integration/candidate@1b990306`, `integration/chatgpt@8203d439`, `integration/main-into-app-line@09a6e3a4`, `product/reserve-20261024@a8814282`, `product/integrity-20261024@031b27d3`, `codex/feedmine-next-internal@d6a05266`, `release/build-56@cede37f6`, F13 e #17. Branches históricas não foram tratadas como candidatas atuais.

**Autoridade normativa relida, sem mudança de main:** [North Star](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_NORTH_STAR.md), [PD-1–PD-10](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz executiva](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [INV-01–INV-18](https://github.com/wsmontes/feedmine_v2/blob/main/docs/architecture/PRODUCT_INVARIANTS.md), [benchmark B01–B06](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md), [regra absoluta render-ready](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/2026-10-17-render-ready-admission-rule.md), [PRD F02](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F02_DISCOVERY_FEED_ONBOARDING_PRD.md), [arquitetura atual](https://github.com/wsmontes/feedmine_v2/blob/main/docs/architecture/ARCHITECTURE.md), [matriz de entrega](https://github.com/wsmontes/feedmine_v2/blob/main/docs/reviews/2026-10-13-production-delivery.md) e [README de handoff](https://github.com/wsmontes/feedmine_v2/blob/main/README.md#L1-L8). Planos/blueprints antigos não prevalecem sobre essas regras.

## 2. Resumo executivo — mudança de comportamento e evidência

**Avanço verificado, restrito:** #26 ajustou `HiddenTailMaintenance` para trabalhar **depois do prefixo protegido**, não depois do último card visto. A posição salva C pode proteger A–C de substituição sem declarar B/C visualmente vistos. Isso é importante para reabertura offline e integridade do histórico. [Fonte #26, `HiddenTailMaintenance.swift:16–29`](https://github.com/wsmontes/feedmine_v2/blob/dc9bb42a/Sources/FeedMineRuntime/HiddenTailMaintenance.swift#L16-L29). A #26 adicionou regressões de manutenção com fronteira protegida mas ainda não lida. **Não** corrige a instalação física de runs render-ready.

**Novo avanço P1, ainda não validado em Apple:** #28 remove a âncora **lógica** de `FeedRunwayDriver`, `LocalProductionSlice` e `PublicationHistory.exposure` como suposta prova de leitura. `PublicationStore.exposure` agora usa **somente o high-water visual durável**: sem ele, todas as origens já publicadas solicitadas são unseen; com ele, apenas ocorrências posteriores continuam unseen. Evita republicar prematuramente artigo editado quando o app apenas restaurou C. [#28, `PublicationStore+History.swift:234–274`](https://github.com/wsmontes/feedmine_v2/blob/dbf5f334/Sources/FeedMinePersistence/PublicationStore%2BHistory.swift#L234-L274), [`FeedRunwayDriver.swift:373–388`](https://github.com/wsmontes/feedmine_v2/blob/dbf5f334/Sources/FeedMineComposition/FeedRunwayDriver.swift#L373-L388), [`LocalProductionSlice.swift:65–102`](https://github.com/wsmontes/feedmine_v2/blob/dbf5f334/Sources/FeedMineRuntime/LocalProductionSlice.swift#L65-L102). É correção coerente com PD-1, mas a confirmação física de viewport continua sendo pré-condição para o high-water.

**Nova evidência Apple concreta para #26:** [GitHub Actions run #41171145208](https://github.com/wsmontes/feedmine_v2/actions/runs/41171145208), job `p0-xctest` ID `124449170126`, executou checkout explícito do **SHA `dc9bb42ac4df87ba14114fec2091385ea7b2c135`** em macOS 15.8.2. Logs reais lidos (não só descrição do PR): etapa `Run full SwiftPM XCTest suite including history and visual admission` **success**, término `** TEST SUCCEEDED **`, suítes reportam zero failures; artefato `p0-ready-window-apple-xcresult` ID `13031018931` disponível. **PASS limitado à suíte SwiftPM iOS Simulator desse SHA**, não ao app com catálogo, gesto nativo, benchmark ou iPhone. Corrige a lacuna de evidência apontada na revisão 046 para #26. O #28 mudou o workflow para seu próprio branch, mas **não foi obtido PASS Apple para `dbf5f334`**: consulta de runs associadas ao commit via conector (limitada a eventos PR) vazia e status contexts vazios; isso **não exclui** push-runs não listados pelo conector.

**Parecer de release: NÃO APROVADA.** [P0 #7](https://github.com/wsmontes/feedmine_v2/issues/7) permanece aberta; transição física entre runs, âncora deferred, offset/rollback, F13, Safari e árvore integrada sem prova. B03 mantém **FAIL histórico ~5,70 s**, B06 **NOT_RUN**, R4 integral **NÃO ACEITO**, redirecionamento público→privado ainda precisa ser vetado antes de conectar. Não promover o PASS isolado de #26 a certificação do #28 ou do produto.

## 3. Achados priorizados, prova versus hipótese e orientação mínima

### P0-01 — Feed contínuo / render-ready ainda não atravessa gaps sem interrupção (ABERTO; progresso parcial anterior)

**Fato de código:** a [#20, `FeedReadyWindowOwnership.swift:25–49`](https://github.com/wsmontes/feedmine_v2/blob/e02879b1/Sources/FeedMineUI/FeedReadyWindowOwnership.swift#L25-L49) instala só o run contíguo pronto contendo a âncora; a [#20, `FeedScreenStore.swift:137–189`](https://github.com/wsmontes/feedmine_v2/blob/e02879b1/Sources/FeedMineUI/FeedScreenStore.swift#L137-L189) não efetua handoff físico para outro run e pode entregar lista vazia se a âncora histórica não tem pixels. #21/#22 acrescentam contratos de witness comum, prepend/offset e rollback, não implementação no host. #26/#28 **não modificaram a UI**.

**Risco de produto (inferência estática, não reproduzida no iPhone):** `texto A → hero deferred → texto B` pode ficar em A sem acesso a B; checkpoint deferred pode produzir tela vazia. A regra de não desenhar placeholders é correta, mas não pode virar fim artificial. **Owner:** implementar **um único** handoff físico na view existente, witness do mesmo card/frame, troca apenas em gesto idle e rollback completo de IDs/offset; reidratar por banda local sem copiar histórico inteiro para RAM. Demonstrar 750→1→750, âncora deferred, normal/held, append/prepend simultâneo e ausência de salto.

### P1-01 — #28 corrige recorrência editorial baseada em posição lógica (NOVO; código verificado, gate aberto)

**Fato:** [issue #27](https://github.com/wsmontes/feedmine_v2/issues/27) identifica que `readerAnchorCardID` podia vir de projeção/restauração antes da observação real; em #26 a [consulta de exposição:235–270](https://github.com/wsmontes/feedmine_v2/blob/dc9bb42a/Sources/FeedMinePersistence/PublicationStore%2BHistory.swift#L235-L270) inicializava unseen vazio sem âncora e tomava `max(anchor, highWater)` quando havia âncora. #28 elimina essa falsa autoridade em **ambos** os caminhos (pré-seleção e publicação) e adiciona [regressões DAO](https://github.com/wsmontes/feedmine_v2/blob/dbf5f334/Tests/FeedMinePersistenceTests/PublicationRunwayStoreTests.swift#L139-L165) e [slice editorial](https://github.com/wsmontes/feedmine_v2/blob/dbf5f334/Tests/FeedMineRuntimeTests/LocalProductionSliceTests.swift#L143-L195).

**Consequência positiva prevista:** artigo editado B não reaparece antes de B ter sido realmente visto; checkpoint C não é falsamente exposição, e a proteção durável do #26 continua separada. **Limite:** as novas regressões chamam `markSeen` programaticamente, não medem o viewport SwiftUI. **Owner:** manter a fronteira única de seen em `submitViewport` aceito e validar a decisão editorial após restore, troca de contexto, restart e scroll real, sem outro contador de vistos.

### P1-02 — Contrato antigo da suíte contradiz a nova regra; provável FAIL no HEAD #28 (NOVO, alta confiança estática, NÃO executado)

**Fato diretamente verificável:** [`EditedArticleRecurrenceTests.testEditedArticleIsPublishedAgainButReplayAndWhitespaceAreNot`, linhas 20–75](https://github.com/wsmontes/feedmine_v2/blob/dbf5f334/Tests/ArchitectureSmokeTests/EditedArticleRecurrenceTests.swift#L20-L75) publica a primeira ocorrência, **não chama `markSeen`**, depois exige que a edição material seja publicada imediatamente. O teste é **idêntico** no #26 e no #28 (mesmo blob `ae814470...`); #26 passava porque seu cálculo de unseen não protegia origem sem âncora. A nova regra da #28 [inicializa unseen com todas as origens publicadas](https://github.com/wsmontes/feedmine_v2/blob/dbf5f334/Sources/FeedMinePersistence/PublicationStore%2BHistory.swift#L243-L255). A publicação inicial [`InitialProductionSlice.swift:100–122`](https://github.com/wsmontes/feedmine_v2/blob/dbf5f334/Sources/FeedMineRuntime/InitialProductionSlice.swift#L100-L122) cria checkpoint, não prova visual.

**Hipótese forte, não resultado observado:** com o novo predicado, a edição material permanece unseen e a expectativa `.published` antiga deve falhar; isso torna **provável** um XCTest vermelho no #28, mesmo que a nova regressão esteja correta. **Owner:** alinhar a fixture antiga ao contrato de produto: primeiro afirmar que a edição **não** reaparece sem leitura; depois emitir `markSeen` explícito da ocorrência anterior e afirmar que a edição material reaparece uma vez. **Não** reverter a proteção editorial só para deixar o teste verde. Rodar a suíte completa e anexar o log do SHA exato.

### P1-03 — Proteção durável e manutenção de cauda evoluíram com prova Apple, mas migração real ainda não certificada (PARCIALMENTE RESOLVIDO)

**Fato:** #26 usa [`protectedThroughCardID` em `HiddenTailMaintenance.swift:16–29`](https://github.com/wsmontes/feedmine_v2/blob/dc9bb42a/Sources/FeedMineRuntime/HiddenTailMaintenance.swift#L16-L29), respeitando prefixo salvo mas não visto; [teste `testHiddenTailMaintenanceStartsAfterProtectedButUnreadCard`](https://github.com/wsmontes/feedmine_v2/blob/dc9bb42a/Tests/ArchitectureSmokeTests/EditedArticleRecurrenceTests.swift#L166-L234) verifica A visto, B salvo, C editável. O run Apple #41171145208 passou no HEAD #26. **Não demonstrado:** migração sobre cópia de banco legado com dados pessoais, reabertura offline com catálogo de produto e gesto nativo. **Owner:** executar migração/relaunch em banco de teste preservando salvos, coleções, fontes, múltiplos contextos, checkpoint e fence; verificar rollback de transação e que high-water visto não avança por restore.

### P1-04 — F13, Safari, filtros e concorrência seguem separados (ABERTO)

**Fato:** F13 [#6](https://github.com/wsmontes/feedmine_v2/pull/6), recuperação de transições [#9](https://github.com/wsmontes/feedmine_v2/pull/9), A/B Safari [#19](https://github.com/wsmontes/feedmine_v2/pull/19), host ready-only #20–#22 e editorial/persistência #26–#28 não estão numa árvore única. [Issue #18](https://github.com/wsmontes/feedmine_v2/issues/18) continua aberta; o relato Safari é histórico, **não reprodução atual**. **Risco:** integrar mecanicamente pode encerrar A antes de B estar pronta, criar escritor de offset paralelo ou perder dados de filtros. **Owner:** integrar a partir da composição F13, preservar A até B pronta, testar A→B→A sob falha SQLite, Safari A/B com mesmo cardID e offset ±1pt, filtro sem descarte do runway, reabertura offline e dados pessoais. Não criar novas filas/caches/timers/retries/ownership paralelos.

### P0-02 — Runway B03 (ABERTO, FAIL histórico; sem nova prova)

[B03, regra vigente](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md#L68-L90): 30 min de **avanços reais**, 1 card/s, rajadas 3/s, zero fim artificial e zero espera visível ≥1 s por reserva insuficiente em corpus elegível. O histórico ~5,70 s não foi revogado. **Owner:** executar avaliador externo congelado, perfis A/B, logs de IDs consumidos, sem mudar corpus/oráculo; B04/B05 juntos para preservar imutabilidade e memória.

### P0-03 — Redirect público→privado (ABERTO; fato de ordem, exploração não observada)

[`FeedDiscoveryTransport.swift:75–90` na main](https://github.com/wsmontes/feedmine_v2/blob/fb8e65ff/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L75-L90) valida destino depois de `URLSession.bytes(for:)`; redirects podem ocorrer antes da checagem. **Owner:** vetar cada salto antes da conexão, com fixture público→privado comprovando zero conexão ao destino privado.

### P2 — Release/CI/documentação (ABERTO)

O PASS Apple #26 é de **SwiftPM em simulador**, sem app build, catálogo PD-10, teste UI de gesto, iPhone físico ou benchmark. #28 altera workflow branch-specific e precisa resultado Apple no próprio HEAD; a consulta disponível ao conector não lista exaustivamente push-runs. Nenhum documento normativo da main mudou; não há release integrada nova. B06 **NOT_RUN**, R4 integral **NÃO ACEITO**. A build TestFlight 32 é histórica e não representa essas branches.

## 4. Comandos e provas no Mac — sugestões, NÃO EXECUTADOS PELO MONITOR

```bash
git fetch origin main monitor/architecture product/nf04-tail-truth \
  fix/durable-position-fence-20261030 fix/editorial-visual-seen-boundary-20261030 \
  experiment/ready-physical-first-install-20261030 \
  test/overlap-prepend-native-witness-20261030 chore/browser-return-ab-runner-20261030
git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md
git diff --check origin/fix/durable-position-fence-20261030..origin/fix/editorial-visual-seen-boundary-20261030
git diff --stat origin/fix/durable-position-fence-20261030..origin/fix/editorial-visual-seen-boundary-20261030
git worktree add --detach /tmp/feedmine-monitor-047 origin/fix/editorial-visual-seen-boundary-20261030
cd /tmp/feedmine-monitor-047
swift package describe
swift test --filter EditedArticleRecurrenceTests
swift test --filter LocalProductionSliceTests
swift test --filter PublicationRunwayStoreTests
swift test --filter RenderReadyAdmissionContractTests
swift test
xcodebuild -list -json
xcrun simctl list devices available
xcodebuild test -scheme FeedMine-Package -destination 'platform=iOS Simulator,id=<UDID>' \
  -parallel-testing-enabled NO -resultBundlePath /tmp/FeedMine047.xcresult CODE_SIGNING_ALLOWED=NO
# O app real requer catalog.sqlite + catalog.manifest.json íntegros conforme README/PD-10:
python3 scripts/bootstrap_catalog.py --help
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -destination 'platform=iOS Simulator,id=<UDID>' CODE_SIGNING_ALLOWED=NO build
# Com app e catálogo de produto válidos: texto–hero deferred–texto; âncora deferred;
# 750→1→750; prepend com gesto, rollback físico; Safari 3x; A→B→A com fault;
# restart offline; persistência de salvos/coleções/fontes; filtro com runway reutilizado.
# Na árvore INTEGRADA e com corpus/avaliador congelados:
scripts/run-discovery-benchmark.sh --gate B03 --profile A --profile B
```

**Gate de aceitação:** sem card image-bearing sem pixels no normal/held; sem tela vazia/fim falso por gap; identidade e offset preservados; checkpoint/fence não equivalem a seen; recorrência editada só após high-water visual; sem perda de dados offline; B03 com trace e critérios congelados. Evidência ausente = **NOT_RUN**, falha medida = **FAIL**.

## 5. Memória compacta para próxima revisão / OMP

- Monitores recentes: 043 `53d43097` → 044 `d069a366` → 045 `8c1e9e24` → 046 `13ef6baa` → **047 (este documento)**.
- HEADs novos: #26 `29153ea2` → **`dc9bb42a`** (4 commits); **#28 `dbf5f334`** (9 commits sobre #26); issue #27 P1 editorial. Main `fb8e65ff`, F13 #6 `c0392741`, ready #17 `93e6cbbe`, #20 `e02879b1`, #21 `267e121f`, #22 `3bc00208`, #25 `67e8d4cf` sem avanço.
- **Resolvido com evidência limitada:** #26 manutenção após fence protegido e **PASS Apple SwiftPM** run `41171145208` no SHA exato `dc9bb42a`; falso seen em checkpoint/restore já mitigado na stack. **Ainda sem prova:** #28 Apple, migração real, UI/scroll, B03/B06, Safari, integração F13 e release.
- **Achado novo crítico para testes:** #28 corrige `exposure` por high-water real, mas `EditedArticleRecurrenceTests.testEditedArticleIsPublishedAgainButReplayAndWhitespaceAreNot` exige publicação antes de `markSeen`; provável RED por fixture antiga. Não reverter a regra; atualizar a fixture e executar Apple.
- **Prioridade:** alinhar contrato editorial/teste #28 e obter Apple no SHA final; depois entregar handoff físico ready-only, integrar F13 e medir Safari/B03. Sem multiplicar coordenadores.
- **Handoff:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. Monitor consultivo, nenhuma alteração a main/código/testes/benchmarks/scripts/coordenação/issues/PRs.
