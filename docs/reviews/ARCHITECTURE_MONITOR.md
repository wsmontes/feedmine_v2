# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 048 · Vancouver, 31/10/2026, aproximadamente 01:43 PDT (início da revisão).** Parecer consultivo, **não certificação de release**. O OMP precisa executar `git fetch origin monitor/architecture` e ler este documento; não há notificação automática.

## 1. Memória persistente, escopo e SHAs

**Memória efetivamente lida primeiro:** [revisão 047](https://github.com/wsmontes/feedmine_v2/blob/b8b942e2c47bddfaf6703eecfc2171ccee550006/docs/reviews/ARCHITECTURE_MONITOR.md), branch `monitor/architecture@b8b942e2c47bddfaf6703eecfc2171ccee550006`, blob `cb20adddc66aae5bffa71df4499fcb582e36b66d`. **Janela incremental:** 30/out 23:42 → 31/out ~01:43 PDT (31/out 06:42 → 08:43 UTC); datas de commits conferidas no GitHub. Comparação [`fb8e65ff...2eca5b4f`](https://github.com/wsmontes/feedmine_v2/compare/fb8e65ff5a5e83ae85c9061996aaa0ebf2b7ca48...2eca5b4f925141e5fdd3653e523c3663972d4310): **main avançou 676 commits**, zero behind, para **`main@2eca5b4f925141e5fdd3653e523c3663972d4310`**. Comparação retorna até 300 arquivos (lista truncada pelo endpoint); não interpretar 300 como inventário completo.

**Mudança de estado principal:** [consolidação](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/reviews/2026-10-30-consolidacao-de-branches.md) promovida à main, branch `integration/main-consolidated-20261030` no mesmo SHA. Das **21 PRs abertas anteriormente**, **16 constam merged** (#5, #6, #10–#12, #15–#17, #19–#24, #26, #28) e **5 closed/unmerged** (#8, #9, #13, #14, #25). Conferência REST individual: #6, #17, #20, #26 e #28 `merged=true`; #8, #9, #13, #14 e #25 `merged=false`. Portanto, os HEADs antigos dos PRs não são mais linhas candidatas concorrentes por padrão: a **main integrada** passou a ser a árvore a validar. Branches históricas ainda existentes não são evidência de trabalho ativo.

**Memória dos HEADs anteriores:** #6 `c0392741`, #17 `93e6cbbe`, #20 `e02879b1`, #26 `dc9bb42a`, #28 `dbf5f334`; todos agora têm PRs encerradas e sua integração **não implica identidade bit a bit de comportamento**, pois houve resolução semântica. `monitor/architecture@b8b942e2` estava inalterada no início desta revisão. A main também passou a conter a revisão 047 por merge `eb0f0f68` feito pelos executores; isso **não** substitui o canal próprio do monitor nem representa alteração da main por este revisor.

**Autoridade relida na main atual:** [North Star](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/PRODUCT_NORTH_STAR.md), [PD-1–PD-10](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [INV-01–INV-18](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/architecture/PRODUCT_INVARIANTS.md), [B01–B06](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md), [render-ready](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/2026-10-17-render-ready-admission-rule.md), [README/handoff](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/README.md) e [relatório de consolidação](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/reviews/2026-10-30-consolidacao-de-branches.md). A regra **INV-17/PD-5 da main** prevalece sobre o antigo mecanismo `hiddenTail` do PR #26; não recomendar reintroduzi-lo para satisfazer fixtures obsoletas.

## 2. Resumo executivo e consequências de produto

**Grande avanço de integração, não de certificação.** A main reúne F13 (histórico/continuidade), política PD-5 sem cauda oculta, admissão render-ready, distinção entre checkpoint e exposição visual, recorrência editorial por high-water, regressões de scroll/Safari, correções de persistência, filtros e infraestrutura de release. O relatório da consolidação descreve a resolução de conflitos e os cherry-picks; a verificação externa confirmou HEAD, PRs e pontos críticos de código, **não reproduziu** a suíte no Mac.

**Novo resultado importante:** a suspeita da revisão 047 sobre #28 deixou de ser hipótese: [Actions run 41171997800](https://github.com/wsmontes/feedmine_v2/actions/runs/41171997800), HEAD exato `dbf5f334`, **FAIL**. Logs reais: [`EditedArticleRecurrenceTests.swift:68`](https://github.com/wsmontes/feedmine_v2/blob/dbf5f334/Tests/ArchitectureSmokeTests/EditedArticleRecurrenceTests.swift#L68) e [`CandidateProviderTests.swift:575,713`](https://github.com/wsmontes/feedmine_v2/blob/dbf5f334/Tests/FeedMineEditorialTests/CandidateProviderTests.swift#L575-L713) ainda esperavam recorrência sem exposição. **A main integrou a correção das fixtures**: [`EditedArticleRecurrenceTests.swift:60–73`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Tests/ArchitectureSmokeTests/EditedArticleRecurrenceTests.swift#L60-L73) agora faz `markSeen` antes da edição, e o relatório registra correção também de K15. O FAIL pertence ao SHA antigo #28, **não é automaticamente um FAIL da main**.

**Evidência de execução na main, de terceiros:** [relatório de consolidação `4](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/reviews/2026-10-30-consolidacao-de-branches.md) registra `swift test` **1.891 testes, 0 falhas, 3 skipped** e `xcodebuild` app **BUILD SUCCEEDED** em macOS/Xcode. Registra também **229 testes do app com 17 falhas (4 unexpected)**, reproduzidas no F13 original com os mesmos insumos. O `catalog.sqlite` local (`42e60234…`) **não** corresponde ao manifesto (`1825fdae…`); não há par íntegro de catálogo de release no ambiente. A introdução do documento menciona 4 skipped, enquanto `4 registra 3: preferir saída bruta do teste, não arredondar a divergência. **Não há run de CI da main no HEAD `2eca5b4f`** entre os runs consultados. Os 1.891 PASS são **relatados por executores**, não reproduzidos por este monitor.

**Outro FAIL Apple verificado, restrito a branch pré-consolidação:** [run 41179478779](https://github.com/wsmontes/feedmine_v2/actions/runs/41179478779), `fix/atomic-viewport-readiness@761214e1`, falhou com **7 asserções de runtime**, inclusive hero sem pixels em restore/warm start ([`RenderReadyAdmissionContractTests.swift:81–95`](https://github.com/wsmontes/feedmine_v2/blob/761214e1/Tests/FeedMineRuntimeTests/RenderReadyAdmissionContractTests.swift#L81-L95)), e **app build falhou por ausência de `catalog.sqlite`** no runner. A main deliberadamente descartou parte desses testes ao resolver o conflito PD-5, então não transportar o FAIL mecanicamente para ela; tampouco usar a remoção dos testes como prova de comportamento resolvido.

**Veredito de produto/release: NÃO APROVADO.** O app compilar e 1.891 testes de pacote passarem não demonstra feed contínuo, travessia física entre runs, retorno exato do Safari, B03, catálogo PD-10, reabertura offline real ou B06. [Issues #7](https://github.com/wsmontes/feedmine_v2/issues/7), [#18](https://github.com/wsmontes/feedmine_v2/issues/18) e [#27](https://github.com/wsmontes/feedmine_v2/issues/27) permaneciam abertas na consulta; #27 tem código integrado, mas não validação de jornada.

## 3. Achados, prioridades e decisão mínima para o owner

### P0-01 — A main só desenha run contíguo pronto; handoff físico entre gaps segue sem integração (ABERTO)

**Fato verificado no HEAD:** [`FeedReadyVisualWindow.initial`, linhas 26–44](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineUI/FeedReadyWindowOwnership.swift#L26-L44) retorna **nil** quando a âncora não está pronta e, caso esteja, recorta **um único run contíguo**. [`FeedScreenStore.install`, linhas 288–332](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineUI/FeedScreenStore.swift#L288-L332) instala esse run, só aceita automaticamente lista de IDs com prefixo anterior e mantém a lista antiga em mudanças que exigiriam rebase físico. [`FeedScreen.swift:68–88,154–163`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineUI/FeedScreen.swift#L68-L88) desenha `renderedItems`/held, não um host de transação de `FeedNativeReadyWindowHandshake`. [`FeedNativeReadyWindowHandshake.swift:45–82`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineUI/FeedNativeReadyWindowHandshake.swift#L45-L82) implementa a transação **como componente**, mas não aparece como wiring no `FeedScreen`/`FeedScreenStore` consultados. **Os testes de handoff físico foram removidos** durante a reconciliação (`2 da consolidação).

**Consequência provável, não reproduzida no aparelho:** `texto A → imagem deferred → texto B` pode mostrar só A sem travessia até B; se a âncora física é deferred, `renderedItems=[]` e a tela cai na superfície de preparação/ausência. No restore, a camada runtime pode substituir explicitamente a âncora por card próximo e emitir toast ([`RenderReadyAdmissionTests.swift:170–189`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Tests/FeedMineRuntimeTests/RenderReadyAdmissionTests.swift#L170-L189)); isso **não** é preservação exata da posição física. O produto precisa preservar a posição durável original para eventual retorno, sem fabricar pixels.

**Owner — mínimo:** conectar o handshake **existente** ao host SwiftUI/UIScrollView, sem outro ownership/cache/timer; instalar apenas pixels prontos, medir witness do mesmo card antes/depois, corrigir offset real apenas em idle, rollback IDs+offset sob gesto/erro. Testar `A–gap–B`, âncora deferred, 750→1→750, prepend/append sob gesto e volta ao checkpoint após mídia reconstituída. **Gate P0 não fechado.**

### P0-02 — Runway adaptativa B03 não revalidada na árvore integrada (ABERTO)

**Fato:** o benchmark [B03](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md) exige 30 minutos de avanços reais, 1 card/s e rajadas 3/s, zero fim artificial e zero espera visível ≥1 s causada por reserva insuficiente. O FAIL histórico ~5,70 s permanece referência de bloqueio; nenhum B03 do `main@2eca5b4f` foi apresentado ou localizado nesta revisão. **Hipótese/risco:** integração massiva e novo recorte visual podem piorar disponibilidade física mesmo com runway lógica cheia. **Owner:** executar B03 A/B com corpus/oráculo/driver congelados na main atual e coletar IDs consumidos, latência visível e prontidão física, mais B04/B05 para imutabilidade/memória.

### P0-03 — Redirecionamento público→privado é validado tarde demais (ABERTO)

**Fato de ordem:** [`FeedDiscoveryTransport.swift:69–91`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L69-L91) chama `session.bytes(for:)` **antes** de validar o host final. A sessão pode seguir o redirect e conectar-se a destino privado antes do veto. Não há exploração comprovada. **Owner:** validar cada salto no delegate de redirecionamento antes da conexão; teste com URL pública redirecionando para IP privado deve provar **zero conexão** ao destino, não apenas ausência de body lido.

### P1-01 — Consolidação muda contrato PD-5 e remove testes críticos; regressão visual ainda não medida (NOVO, ABERTO)

**Fato:** [consolidação `2](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/reviews/2026-10-30-consolidacao-de-branches.md) elimina `hiddenTail`, `edition_position_protection` e quatro famílias de testes P0, privilegiando `INV-17` e a admissão embarcada F13. Isso pode ser a **decisão correta de produto**, porque PD-5 proíbe reescrever publicação imutável; mas **38/78 testes vermelhos na tentativa inicial e remoção posterior** não demonstram a experiência física. **Owner:** manter PD-5, substituir os testes obsoletos por uma única prova de aceitação no host integrado, cobrindo readiness, identidade, geometria, retorno e restart. Não reintroduzir a cauda oculta.

### P1-02 — App com 17 falhas e catálogo incompatível; gate de release não existe (NOVO, COMPROVADO COMO RELATO DE EXECUÇÃO)

**Fato de evidência versionada:** [consolidação `4.1](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/reviews/2026-10-30-consolidacao-de-branches.md) declara **229 testes, 17 falhas**, reproduzidas no F13, em `CatalogueUpdateAcceptTests`, `FilterConfirmationBoundaryTests`, `CompositionTests` e `ReadingCompositionTests.K15`. O catálogo local não coincide com o manifesto versionado. Reproduzir falha em ancestral mostra **não introduzida por esta consolidação**, mas **não torna aceitável a candidata atual**. **Owner:** primeiro instalar par `catalog.sqlite/catalog.manifest.json` válido e repetir suíte do app; separar falhas de fixture de falhas funcionais, preservar dados pessoais e reabertura offline. Não marcar PASS por equivalência com F13.

### P1-03 — Editorial #28: hipótese anterior virou FAIL real, fixture foi corrigida na main (PARCIALMENTE RESOLVIDO)

**Fato:** run [41171997800](https://github.com/wsmontes/feedmine_v2/actions/runs/41171997800) mostrou 3 falhas: uma em `EditedArticleRecurrenceTests` e duas K15, exatamente porque a edição exigia exposição ainda não confirmada. A main faz `markSeen` explícito na fixture ([arquivo:linha](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Tests/ArchitectureSmokeTests/EditedArticleRecurrenceTests.swift#L60-L73)); [`PublicationStore+History.swift`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMinePersistence/PublicationStore%2BHistory.swift) continua sendo a autoridade de exposição. **Resolvido estaticamente:** expectativa antiga de teste. **Ainda não provado em jornada:** retorno offline/restore C sem declarar B visto, edição B bloqueada até visualização real e publicada depois, sem perder o histórico. **Owner:** executar caso em UI real e restart; não fazer checkpoint contar como visto.

### P1-04 — Safari, troca de contexto e persistência requerem teste na árvore única (ABERTO)

**Fato:** #10/#11/#12 e runner #15/#19 entraram, mas #13/.overFullScreen e #14 ficaram fora por ausência de A/B. [Issue #18](https://github.com/wsmontes/feedmine_v2/issues/18) permanece aberta. O F13 agora está na main, porém não há prova no SHA final de Safari A→mesmo card ±1 pt, com publicação ativa/inativa, nem A→B→A com falha SQLite e filtros sem descartar trabalho reutilizável. **Owner:** executar A/B no mesmo simulador com catálogo validado; instrumentar cardID/offset antes/depois; testar reabertura offline com salvos, coleções, fontes, contexto e checkpoint. Não promover uma hipótese de apresentação UIKit sem evidência.

### P2 — CI, observabilidade e B06 (ABERTO)

**Fatos:** [run 41179478779](https://github.com/wsmontes/feedmine_v2/actions/runs/41179478779) falhou em testes de branch e build por catálogo ausente; [run 41171997800](https://github.com/wsmontes/feedmine_v2/actions/runs/41171997800) falhou no #28 antigo; [run 41171145208](https://github.com/wsmontes/feedmine_v2/actions/runs/41171145208) passou no #26 antigo. **Nenhum deles é PASS da main integrada**. A suíte local relatada tem divergência de skipped (3 versus 4 no documento), e o catálogo de release não está vinculado ao build. B06 **NOT_RUN**, R4 integral **NÃO ACEITO**. **Owner:** anexar `xcresult`/logs com SHA exato, hashes do catálogo e versão de Xcode; só declarar PASS de cada gate quando executado integralmente na mesma candidata.

## 4. Comandos e provas necessários no Mac (NÃO EXECUTADOS POR ESTE MONITOR)

```bash
git fetch origin main monitor/architecture
git rev-parse origin/main
git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md
git diff --stat fb8e65ff5a5e83ae85c9061996aaa0ebf2b7ca48..origin/main
git worktree add --detach /tmp/feedmine-monitor-048 origin/main
cd /tmp/feedmine-monitor-048
swift package describe
swift build
swift test
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -list
xcrun simctl list devices available
# Providenciar o par real e íntegro conforme README e Resources/CATALOG.md:
python3 scripts/bootstrap_catalog.py --help
# Validar os bytes do catálogo efetivamente instalado antes de aceitar a experiência:
scripts/verify_product_catalogue.sh "$(xcrun simctl get_app_container booted com.feedmine.development app)"
xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -destination 'platform=iOS Simulator,id=<UDID>' -parallel-testing-enabled NO \
  -resultBundlePath /tmp/FeedMine048.xcresult CODE_SIGNING_ALLOWED=NO
# Exercitar o app: texto–hero deferred–texto, 750→1→750, retorno Safari
# (publicação ativa/inativa), filtro A→B→A com falha, reabertura offline,
# salvos/coleções/fontes; medir cardID e offset, não só contagem de células.
scripts/run-browser-return-ab.sh --help
scripts/run-discovery-benchmark.sh --gate B03 --profile A --profile B
# B04/B05/B06 no ambiente prescrito pelo benchmark, sem alterar fixtures/oráculos.
```

**Aceitação:** cards image-bearing só com pixels locais decodificados; ausência temporária de mídia não encerra artificialmente a navegação; IDs, posição e histórico preservados; scroll não aguarda rede; high-water só por viewport; filtro reutiliza trabalho; offline e dados pessoais persistem; B03 medido; redirects vetados antes de conectar. Falta de execução = **NOT_RUN**; FAIL observado não vira PASS por cherry-pick.

## 5. Memória compacta para próxima revisão e handoff

- Revisões 043 `53d43097` → 044 `d069a366` → 045 `8c1e9e24` → 046 `13ef6baa` → 047 `b8b942e2` → **048 (este documento)**.
- **Base anterior:** main `fb8e65ff`; **base atual:** main/integration consolidada `2eca5b4f`, +676 commits; 16 PRs merged, 5 closed/unmerged; monitor anterior `b8b942e2`/blob `cb20addd`.
- **Resolvido parcialmente:** F13 + contratos P0 + exposição visual agora em uma árvore; testes de recorrência #28 corrigidos estaticamente; persistência endurecida; scroll/diagnóstico/locale integrados. **Não resolvido:** handoff físico entre runs, B03, redirect, Safari aceito, 17 falhas do app/catálogo PD-10, migração/reabertura offline e B06.
- **CI histórico:** #26 `dc9bb42a` PASS Apple `41171145208`; #28 `dbf5f334` FAIL Apple `41171997800` (3 falhas confirmadas); branch `761214e1` FAIL Apple `41179478779` (7 asserções + catálogo ausente). Nenhum desses é veredito da main `2eca5b4f`.
- **Próximo foco do owner:** não abrir mais mecanismos paralelos; fechar uma travessia física render-ready com prova nativa, instalar catálogo íntegro, corrigir/explicar 17 falhas, rodar Safari e B03 na main, depois release.
- **Handoff explícito:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. Este revisor só escreve este arquivo nesta branch, sem alterar main, produto, testes, scripts, benchmarks, issues ou PRs.
