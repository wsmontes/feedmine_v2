# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 049 · Vancouver, 31/10/2026, 11:39 PDT (início da consulta; UTC−07).** Parecer consultivo, **não certificação de release**. O OMP deve fazer `git fetch origin monitor/architecture` e ler este arquivo; a branch não notifica executores automaticamente.

## 1. Memória, autoridade, SHAs e intervalo

**Memória persistente lida primeiro:** [revisão 048](https://github.com/wsmontes/feedmine_v2/blob/4fa767d7a423f2ea2a7c09f768570bedb7df6d8e/docs/reviews/ARCHITECTURE_MONITOR.md), `monitor/architecture@4fa767d7a423f2ea2a7c09f768570bedb7df6d8e`, blob `681b955cbf49ebfcc4b2bd8a002a59c1a83f4b1c`. Última verificação sem mudança: 31/out ~09:41 PDT. **Janela desta revisão:** atividade nova observada de ~09:52 a ~11:09 PDT, verificada a partir de ~11:39 PDT; histórico relevante desde a revisão 048 de ~01:43 PDT.

**Main verificada:** `2eca5b4f925141e5fdd3653e523c3663972d4310`. [Comparação do SHA anterior com main](https://github.com/wsmontes/feedmine_v2/compare/2eca5b4f925141e5fdd3653e523c3663972d4310...main): **identical, zero commits e zero arquivos**. `integration/main-consolidated-20261030` permanece idêntica; `integration/candidate` está 803 commits atrás, `release/build-56` 406 atrás, `integration/main-into-app-line` 873 atrás e `integration/chatgpt` divergente (6 ahead/814 behind): **não são candidatas novas**. Há **seis PRs draft novos, #29, #30, #31, #33, #34, #35**, todos baseados na main consolidada, e uma nova [issue #32](https://github.com/wsmontes/feedmine_v2/issues/32). PR #32 não existe; #32 é número de issue. Nenhum PR novo foi integrado. Branches temporárias `ci/*` contêm provas combinadas; não são a main nem candidatas de release.

**Autoridade relida na main, sem alteração de SHA nesta janela:** [North Star](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/PRODUCT_NORTH_STAR.md), [decisões PD-1–PD-10](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz de execução](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [invariantes INV-01–INV-18](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/architecture/PRODUCT_INVARIANTS.md), [benchmark B01–B06](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md), [admissão render-ready](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/2026-10-17-render-ready-admission-rule.md), [README/handoff](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/README.md) e [consolidação](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/reviews/2026-10-30-consolidacao-de-branches.md). **Não houve mudança de docs na main**; a documentação antiga de blueprint não substitui PD-5/INV-17/PD-10.

## 2. Resumo executivo — o que mudou para o leitor

**Agora há um RED de host real para o defeito de troca física, e um GREEN restrito para o primeiro estágio da correção.** O [PR #33](https://github.com/wsmontes/feedmine_v2/pull/33) adicionou um teste com `NSHostingView`/`NSScrollView` que exige substituir as células físicas de `[A,B,C]` por `[B,C,D]`. O [Actions 41226687119](https://github.com/wsmontes/feedmine_v2/actions/runs/41226687119), HEAD `a4c5313ac7401988ed62ec88d132cca2ba04aed9` da branch de CI, executou **1 XCTest macOS e falhou exatamente no assert de IDs físicos**, em `FeedViewportCaptureTests.swift:839`. A projeção semântica avançou, mas a lista desenhada continuou antiga. **É um FAIL reproduzido no host macOS, não uma reprodução no iPhone nem prova de qual sintoma o usuário vê em todos os contextos.**

O [PR #35](https://github.com/wsmontes/feedmine_v2/pull/35), HEAD `4f7040efbc23429751d4b3ab2b558b05c4453e02`, implementa **apenas staging seguro** de uma janela não prefixada: expõe o candidato derivado da projeção semântica, liga uma instância do handshake ao mesmo writer nativo de offset e revoga propostas obsoletas. Não executa `begin`, não publica células novas, não mede witness depois do layout e não conclui commit/rollback físico. O [Actions 41227305036](https://github.com/wsmontes/feedmine_v2/actions/runs/41227305036) concluiu **SUCCESS com 14/14 XCTest iOS** (13 handshake + 1 staging) no SHA **`7f42d6af5c8b42d55825f71200e7a24e16038e4e`**, **branch temporária combinada** com os reparos dos PRs #30 e #34. Log e `xcresult` [artefato 13052625939](https://github.com/wsmontes/feedmine_v2/actions/runs/41227305036). **Não é PASS do PR #35 isolado, da main, do host RED, nem da jornada física.**

**Outra evidência nova:** [Actions 41225997714](https://github.com/wsmontes/feedmine_v2/actions/runs/41225997714) executou a suíte SwiftPM iOS na branch combinada `ci/full-swiftpm-ui-legacy-20261031@1960365d47de163e59be8df4d2ad089b5b060f10`: `xcresulttool` confirmou **1.891 testes totais, 1.887 PASS, 4 skipped, zero FAIL**. A branch tem quatro commits sobre a main (workflows de CI + correção Swift 6 #30 + fixture #34), **não** contém o staging #35. A evidência não compila o app com catálogo de produto, não resolve as **17 falhas anteriores de FeedMineAppTests**, nem certifica B03/Safari/B06. É avanço real de CI; não promover seu resultado ao HEAD da main.

**Veredito: RELEASE NÃO APROVADA.** O P0 de prontidão visual e travessia física, B03 no HEAD integrado, veto de redirect antes da conexão, retorno Safari, catálogo íntegro e jornada offline ainda não foram aceitos.

## 3. Achados priorizados, fatos, hipóteses e ação mínima

### P0-01 — Handoff físico entre janelas render-ready continua ausente (CONFIRMADO EM HOST; ABERTO)

**Fato na main:** [`FeedScreenStore.install:304–329`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineUI/FeedScreenStore.swift#L304-L329) só instala automaticamente uma janela cujos IDs começam pelos IDs físicos anteriores; fora disso mantém a lista antiga. [`FeedScreen.swift:68–88,154–185`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineUI/FeedScreen.swift#L68-L88) monta `renderedItems`/itens emprestados pelo gesto, não a projeção semântica completa. O [teste host PR #33:~782–850](https://github.com/wsmontes/feedmine_v2/blob/393e0bc94f77c717c1550c70cd47a744990876b8/Tests/ArchitectureSmokeTests/FeedViewportCaptureTests.swift#L782-L850) falhou no assert exato de troca de IDs no [run 41226687119](https://github.com/wsmontes/feedmine_v2/actions/runs/41226687119): `[A,B,C]` continuou físico quando o novo snapshot era `[B,C,D]`. Uma tentativa anterior usou premissa errada de altura de card; **o RED revisado eliminou essa premissa**, portanto esta falha de identidade é discriminante.

**Fato novo, mas não resolução:** [PR #35, `FeedScreenStore.swift:347–370`](https://github.com/wsmontes/feedmine_v2/blob/4f7040efbc23429751d4b3ab2b558b05c4453e02/Sources/FeedMineUI/FeedScreenStore.swift#L347-L370) deriva `pendingNativeReadyWindow` sem duplicar cursor. [`FeedNativeViewport.swift:39–80`](https://github.com/wsmontes/feedmine_v2/blob/4f7040efbc23429751d4b3ab2b558b05c4453e02/Sources/FeedMineUI/FeedNativeViewport.swift#L39-L80) faz `stage` e usa o `FeedNativeScrollOffset` existente, mas **não** publica o candidato nem executa transação. O teste [`FeedScreenStoreTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/4f7040efbc23429751d4b3ab2b558b05c4453e02/Tests/ArchitectureSmokeTests/FeedScreenStoreTests.swift) exige corretamente que a lista física permaneça antiga enquanto só houve staging. O CI de 14 testes confirma essa segurança restrita.

**Risco de produto (inferência):** trims, prepend, reentrada de mídia e cap de janela podem deixar o leitor vendo um recorte obsoleto; a ausência de pixels na âncora pode gerar superfície vazia. A frequência real e a severidade no iPhone dependem de ensaio. A issue [#32](https://github.com/wsmontes/feedmine_v2/issues/32) tem rótulo P2, mas **a aceitação do comportamento é bloqueador de release P0** quando afeta continuidade/posição — prioridade de produto não é equivalente ao rótulo da tarefa de implementação.

**Owner — mínimo:** concluir a etapa 2 no **mesmo** owner/`UIScrollView`/writer: witness de card comum e geometria **antes**; `handshake.begin` em idle; publicar IDs provisórios no mesmo `LazyVStack`; medir após layout nativo; confirmar offset/identidade/token e `commit`; se gesto/cancelamento, restaurar IDs e offset e quitar dívida de rollback antes de outra transição. Não usar `renderedItems = next.cards` direto, segundo writer, timer, cache ou altura presumida. Tornar o RED host GREEN, depois repetir em `UIHostingController` iOS com gesto, card imagem, cap real, histórico profundo e Safari. **Ainda aberto.**

### P0-02 — Runway B03 e continuidade integrada não revalidadas (ABERTO; CORREÇÃO DE MEMÓRIA)

**Correção factual importante à revisão 048:** a [norma de benchmark, linha 124](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md#L124) **registra B03 PASS histórico em 20/10/2026** no commit `4baf9045`: 3.157 avanços/30 min, zero paradas ≥1 s. A revisão 048 mencionava um “FAIL histórico ~5,70 s” como referência principal, sem incorporar este resultado posterior. **O último status histórico documentado do B03 no simulador é PASS**, embora o registro bruto `docs/evidence/ACCEPTANCE_RECORD.md` apontado pelo documento não esteja versionado/acessível neste checkout (404). Não transformar esse relato em execução independente deste monitor.

**Fato atual:** não foi encontrada execução B03 do `main@2eca5b4f` nem das branches de PR atuais; a mudança de janela física exige revalidar disponibilidade **percebida** mesmo se o supply lógico está cheio. **Owner:** executar B03 com corpus/driver/oráculo congelados, 30 min, 1 card/s e rajadas, incluindo IDs efetivamente desenhados, offset, mídia pronta e pausas; B04/B05 no mesmo SHA. **Sem PASS transferível à main.**

### P0-03 — Redirect público→privado pode ocorrer antes do veto (RISCO ESTÁTICO ABERTO)

[`FeedDiscoveryTransport.swift:69–91`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L69-L91): `session.bytes(for:)` (linha 85) antecede a validação do host final (linha 88). **Fato:** ordem de código; **hipótese de risco:** com redirects habilitados na sessão, conexão ao destino privado pode ocorrer antes da recusa. Não há exploração demonstrada. **Owner:** validar cada redirect **antes de seguir** no delegate da sessão, mantendo a mesma política de hosts; teste com servidor público→IP privado deve comprovar zero conexão ao destino. Nenhuma mudança nesta janela.

### P1-01 — Baseline Apple ganhou prova completa, mas main ainda não compila sob o mesmo gate (NOVO, PARCIAL)

**FAIL real:** [run 41221785827](https://github.com/wsmontes/feedmine_v2/actions/runs/41221785827) no PR [#29](https://github.com/wsmontes/feedmine_v2/pull/29) encontrou erro Swift 6 em [`FeedItemRowView.swift:20`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineUI/Cards/FeedItemRowView.swift#L20): closure `onPlay` MainActor-isolada acessada por igualdade `nonisolated`; o teste nem começou. O [PR #30](https://github.com/wsmontes/feedmine_v2/pull/30/files) introduz `hasPlayAction` imutável para a comparação, preservando a distinção visual do botão Tocar. **Prova combinada:** [run 41225997714](https://github.com/wsmontes/feedmine_v2/actions/runs/41225997714), SHA `1960365d`, 1.891 total/1.887 PASS/4 skipped/0 FAIL, no iOS Simulator iOS 26.2, Xcode 16.4/Swift 6.1.2. **Não é PASS do HEAD `beffb21d` isolado nem da main**, mas confirma que o patch participa de uma árvore compilável e testável.

**Owner:** revisar #30 e #34 juntos, evitar conflito de fixture, promover via fluxo normal de PR se o conjunto corresponder à candidata; então ativar o [workflow PR #29](https://github.com/wsmontes/feedmine_v2/pull/29/files) e exigir run do SHA efetivo na main. Não usar o CI do pacote como gate do app/PD-10.

### P1-02 — Migração V1: fixture Apple corrigida, não prova importação real (NOVO, PARCIAL)

**FAIL real:** [run 41222193742](https://github.com/wsmontes/feedmine_v2/actions/runs/41222193742), `LegacyUserStateImportTests.testCandidateUserStateURLsAlwaysIncludeAResolvableLocation`, falhou ao criar `Application Support/feedmine` depois de `FeedMine` no simulador: `NSCocoaErrorDomain 512`/`NSPOSIXErrorDomain 5`. O [PR #34](https://github.com/wsmontes/feedmine_v2/pull/34/files) usa a localização colapsada `FeedMine/user.sqlite` na fixture, sem mudar o importador. [Run 41225259158](https://github.com/wsmontes/feedmine_v2/actions/runs/41225259158): **1/1 XCTest PASS**; a suíte completa combinada [41225997714](https://github.com/wsmontes/feedmine_v2/actions/runs/41225997714) também passou. **Limite:** corrigiu premissa de teste em volume case-insensitive; não valida migração de usuário real nem preservação de salvos/coleções/fontes após restart. **Owner:** manter a correção mínima e fazer ensaio de importação V1→V2 com banco real/cópia descartável, reabertura offline e comparação de dados pessoais.

### P1-03 — Checkpoint não é exposição: teste de integração passou, UI ainda sem aceite (NOVO, PARCIAL)

O [PR #31](https://github.com/wsmontes/feedmine_v2/pull/31/files) amplia [`EditedArticleRecurrenceTests.swift:125–275`](https://github.com/wsmontes/feedmine_v2/blob/aecd6748147bd0d994cb4fcde0d28a2c9b4ae722/Tests/ArchitectureSmokeTests/EditedArticleRecurrenceTests.swift#L125-L275) com A/B/C: checkpoint lógico em C, só A visto, B/C permanecem unseen após reabrir banco; `markSeen` efetivo libera recorrência. [Run 41224254306](https://github.com/wsmontes/feedmine_v2/actions/runs/41224254306), SHA `521cc0ff` de branch de CI, executou **5/5 XCTest iOS PASS**, incluindo `testRestoredLogicalCDoesNotPromoteUnseenBOrC`. **Fato de teste de persistência**, não observação física do viewport; a [issue #27](https://github.com/wsmontes/feedmine_v2/issues/27) continua aberta. **Owner:** após integrar, provar que restore lógico nunca chama exposição sem witness nativo e que a edição reaparece só depois de visualização efetiva, inclusive offline.

### P1-04 — Safari, filtros, persistência e catálogo ainda sem gate do aplicativo (ABERTO)

[Issue #18](https://github.com/wsmontes/feedmine_v2/issues/18) permanece aberta. O teste UI de retorno por cardID/±1 pt existe na main, mas **não foi executado no HEAD integrado** com catálogo válido. O [README](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/README.md) exige par `catalog.sqlite/catalog.manifest.json` com hashes coerentes; o catálogo local usado na consolidação divergia do manifesto. A [consolidação `4.1](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/reviews/2026-10-30-consolidacao-de-branches.md) registra **229 FeedMineAppTests, 17 falhas**, reproduzidas na linha anterior, **não resolvidas por esta suíte SwiftPM**. **Owner:** obter bytes exatos do catálogo de release e executar o app no mesmo simulador/commit: Safari sem/com publicação durante navegação, cardID/offset antes/depois, filtros A→B→A, deep history 750→1→750, salvos/coleções/fontes e reabertura offline. Não presumir que #32 causa #18.

### P2 — CI, documentação de evidências e B06 (ABERTO)

O PR #29 cria gate `push/main` e `pull_request/main` para SwiftPM, mas está draft e a main ainda não contém esse workflow. A [suite completa 41225997714](https://github.com/wsmontes/feedmine_v2/actions/runs/41225997714) e a [suite parcial 41227305036](https://github.com/wsmontes/feedmine_v2/actions/runs/41227305036) são **evidência de branches temporárias**, não certificado de main. O [benchmark `124](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md#L124) registra **B06 executado e INCOMPLETE em iPhone 14 Plus em 20/10** (cadência do driver e energia não medida); **B06 no HEAD atual é NOT_RUN**, não “nunca foi tentado”. O link relativo do benchmark a `docs/evidence/ACCEPTANCE_RECORD.md` não resolve no repositório atual; solicitar artefatos brutos ao Mac do executor antes de elevar confiança em gates históricos. Não alterar benchmark congelado para obter verde.

## 4. Provas necessárias no Mac — NÃO EXECUTADAS por este monitor

```bash
git fetch origin main monitor/architecture \
  ci/full-swiftpm-ui-legacy-20261031 \
  ci/native-handoff-staging-swift6-20261031 \
  ci/native-host-nonprefix-red-20261031
git rev-parse origin/main
git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md

# Reproduzir PASS do pacote em SHA exato (branch temporária, não main):
git worktree add --detach /tmp/fm-monitor-049-package origin/ci/full-swiftpm-ui-legacy-20261031
cd /tmp/fm-monitor-049-package
xcodebuild test -scheme FeedMine-Package \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -parallel-testing-enabled NO -resultBundlePath /tmp/FeedMine049Package.xcresult \
  CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool get test-results summary --path /tmp/FeedMine049Package.xcresult

# Reproduzir RED físico discriminante do host macOS:
cd -
git worktree add --detach /tmp/fm-monitor-049-red origin/ci/native-host-nonprefix-red-20261031
cd /tmp/fm-monitor-049-red
xcodebuild test -scheme FeedMine-Package -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -only-testing:ArchitectureSmokeTests/FeedViewportCaptureTests/testNativeHostedNonPrefixTrimReplacesActualPhysicalIDs \
  -resultBundlePath /tmp/FeedMine049HostRed.xcresult CODE_SIGNING_ALLOWED=NO

# Etapa 2: repetir o mesmo teste após conectar commit/rollback nativo;
# no iOS, medir ID, geometria, offset, gesto, cancelamento e readmissão.
# NÃO considerar 14 testes de staging como prova de troca física.

# Gate real do app: worktree da candidata final, par de catálogo íntegro:
python3 scripts/bootstrap_catalog.py --help
scripts/verify_product_catalogue.sh "$(xcrun simctl get_app_container booted com.feedmine.development app)"
xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -parallel-testing-enabled NO -resultBundlePath /tmp/FeedMine049App.xcresult \
  CODE_SIGNING_ALLOWED=NO
scripts/run-browser-return-ab.sh --help
scripts/run-discovery-benchmark.sh --gate B03 --profile A --profile B
# Repetir B04/B05, B06 físico no ambiente prescrito, sem mudar corpus/oráculo.
```

**Critério de aceitação:** cards com imagem somente com pixels locais decodificados; atravessar janelas prontas sem buracos artificiais; nenhuma troca física sem witness e rollback; scroll/retorno preservam mesmo cardID e posição; publicação em background não move o leitor; A→B→A reutiliza trabalho; dados pessoais e histórico reabrem offline; B03 e demais gates executados na **mesma** candidata; redirect privado recusado antes de conectar. `NOT_RUN` não equivale a `PASS`.

## 5. Memória compacta e handoff ao OMP

- Revisões anteriores: 043 `53d43097` → 044 `d069a366` → 045 `8c1e9e24` → 046 `13ef6baa` → 047 `b8b942e2` → 048 `4fa767d7`. **Revisão atual: 049**, apenas no canal `monitor/architecture`.
- **Main:** `2eca5b4f` inalterada; integração consolidada idêntica. **PRs draft novos:** #29 `d8e7e5ea` (workflow), #30 `beffb21d` (Swift 6), #31 `aecd6748` (exposição), #33 `393e0bc9` (RED host), #34 `9e9ab275` (fixture V1), #35 `4f7040ef` (staging). **Issue nova:** #32.
- **CI novo confirmado:** `41221785827` FAIL compilação main no Swift 6; `41222193742` FAIL fixture V1; `41224254306` 5/5 editorial PASS; `41225259158` 1/1 fixture PASS; `41225997714` 1.891 total, 1.887 PASS, 4 skipped, 0 FAIL (SHA `1960365d` combinado); `41226687119` 1/1 RED host FAIL esperado (SHA `a4c5313a`); `41227305036` 14/14 staging+handshake PASS (SHA `7f42d6af` combinado). **Nenhum é CI do SHA main.**
- **Histórico corrigido:** benchmark documenta B03 PASS em `4baf9045`/20-out, não apenas FAIL antigo; B06 histórico INCOMPLETE com tentativa física, não PASS; no `2eca5b4f` ambos carecem de nova prova. `docs/evidence/ACCEPTANCE_RECORD.md` referenciado pelo benchmark não foi encontrado neste Git checkout.
- **Parcialmente resolvidos:** compilação Swift 6 e fixture case-insensitive em branch combinada; separação editorial checkpoint/seen coberta em integração; staging nativo seguro. **Permanecem:** commit físico do handoff (host RED), B03/B04/B05 no HEAD, redirect preventivo, 17 falhas do app/catálogo PD-10, Safari, offline/salvos/fontes, B06.
- **Ação mínima do owner:** primeiro fechar o RED host com o writer/handshake existente; integrar correções pequenas #30/#34 com CI de main; depois app com catálogo íntegro e jornadas Safari/B03. Evitar novo cache, timer, scheduler ou segunda camada de ownership.
- **Handoff explícito:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. O monitor não escreve em main, código, testes, benchmarks, scripts, coordenação, issues ou PRs.
