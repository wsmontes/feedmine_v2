# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 042 · Vancouver, 30/10/2026, 13:38 PDT.** Parecer externo consultivo; **não** certificação de release. O OMP deve executar `git fetch origin monitor/architecture` e ler este documento: nenhum agente recebe aviso automático.

## 1. Base e intervalo incremental

**Memória persistente lida antes da inspeção:** revisão 041 em `monitor/architecture@5842ce1c98168cf21bb77a3ca330238b69b09005`, blob `baa9109170138536686cc64ea85d80da8c882c99`. **Janela:** 30/out/2026 11:42 → 13:38 PDT. **Mudança corrente relevante:** [PR #9](https://github.com/wsmontes/feedmine_v2/pull/9), `audit/session-transition-failure-probe-20261030`, avançou **54 commits** desde `1c9b3a5ef4474f07a9206da7c2dc25e77ab02cd9` até **`3e863a1cfd065225262c6fcc2798370f6a7431ba`**. [Comparação exata da janela](https://github.com/wsmontes/feedmine_v2/compare/1c9b3a5ef4474f07a9206da7c2dc25e77ab02cd9...3e863a1cfd065225262c6fcc2798370f6a7431ba): 4 arquivos Swift modificados, **sem mudanças de docs nessa linha incremental**. O PR tem 59 commits e 5 arquivos no total sobre a main, permanece **draft**. Não confundir 54 commits novos com 54 funcionalidades aceitas.

**SHAs conferidos por comparação direta:** `main@fb8e65ff5a5e83ae85c9061996aaa0ebf2b7ca48` (idêntica); [PR #6 F13](https://github.com/wsmontes/feedmine_v2/pull/6) `product/nf04-tail-truth@c03927418ea28771d721763bdcaa3f21f3dab653` (idêntica, draft); [PR #8 render-ready](https://github.com/wsmontes/feedmine_v2/pull/8) `chatgpt/render-ready-contract-red-01@83f05671bd54c603bb6052589ab3d921152c2df5` (idêntica, draft); reserve `a8814282`, integrity `031b27d3`, next `d6a05266`, release/build-56 `cede37f6`, integration/chatgpt `8203d439`, integration/main-into-app-line `09a6e3a4` (todos idênticos). `integration/candidate@1b990306` permanece **histórica**, não candidata atual. O monitor antes desta atualização estava em `5842ce1c`. PR #5 é documentação histórica sem atividade nova. A busca de PRs abertos retornou #9, #8, #6 e #5; nenhuma nova PR ativa foi identificada.

**Conflito de integração, não continuidade de F13:** [comparação F13→audit](https://github.com/wsmontes/feedmine_v2/compare/product/nf04-tail-truth...audit/session-transition-failure-probe-20261030) retorna `diverged`, **59 commits exclusivos em audit e 424 em F13**. O PR #9 foi construído sobre a main antiga, não incorpora a preparação/promoção F13. Não fazer merge ou cherry-pick amplo sem reconciliar ownership e testes.

**Normas atuais consultadas na main:** [North Star](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_NORTH_STAR.md), [PD-1–PD-10](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz V2](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [INV-01–INV-18](https://github.com/wsmontes/feedmine_v2/blob/main/docs/architecture/PRODUCT_INVARIANTS.md), [benchmark B01–B06](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md) e [regra render-ready](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/2026-10-17-render-ready-admission-rule.md). Decisões vigentes prevalecem sobre blueprints antigos. A análise prioriza a leitura real e a fronteira de apresentação, não quantidade de asserts.

## 2. Resumo executivo: o que mudou para a pessoa

**Avanço de engenharia, não avanço perceptível certificado.** O PR #9 desenvolveu proteção para concorrência de transições: reserva FIFO cancelável, persistência atômica da seleção/versão/contexto/identidades, retries delimitados de conflitos de versão que preservam a intenção original, reconciliação de edições externas e recuperação quando a construção da nova associação falha. A última mudança trata um caso específico: um pedido editorial `replaceSession()` chega enquanto `toggleSource` detém a exclusividade; mesmo que o toggle falhe, o pedido pendente é drenado antes de devolver o erro original. Há testes de falha pré-commit, pós-commit e recuperação da recuperação.

**Mas a experiência A→B ainda não está protegida na linha audit.** O código **fecha A antes de construir B** em múltiplas rotas. Compensar reconstruindo A depois da falha não prova que o usuário não viu tela vazia, que seu offset não saltou, nem que a apresentação continuou local. A linha F13 possui preparação oculta que deve ser a base da solução, e não substituída por um segundo controlador. A correção recente pode preservar estado final em testes e ainda falhar no requisito de experiência.

**Release NÃO APROVADA.** P0 render-ready, B03/runway e redirects privados permanecem abertos; R4 completo não foi aceito; B06 físico NOT_RUN. Não há evidência nova de execução de XCTest/Xcode/simulador/iPhone/benchmark no PR #9. O PR declara apenas um modelo Swift isolado em Linux, mais inspeção lexical: isso **não** é compilação nem teste do app iOS. O conector retornou **nenhum status context e nenhuma execução de workflow acionada por PR** para o HEAD audit; ausência de status não prova falha, mas não permite alegar PASS.

## 3. Achados classificados, evidência e ação mínima

### P1-01 — Drenagem de rebuild editorial após falha de toggle: correção estática localizada (PARCIALMENTE RESOLVIDO)

**Fato comprovado no código:** [AppComposition.swift:673–696](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineApp/AppComposition.swift#L673-L696) mantém a exclusividade da transição no `toggleSource`, executa `rebuildSessionWhileTransitionLocked()` no `catch` quando `pendingRebuild` está ativo e propaga o erro original. [AppComposition.swift:698–811](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineApp/AppComposition.swift#L698-L811) contém version fence, commit de seleção e reconstrução. [CompositionTests.swift:4595–4758](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineAppTests/CompositionTests.swift#L4595-L4758) inclui cenários determinísticos pré-commit, pós-commit e falha dupla de construção/compensação; o último commit [3e863a1c](https://github.com/wsmontes/feedmine_v2/commit/3e863a1cfd065225262c6fcc2798370f6a7431ba) adiciona o cenário de terceira construção. **Fato de escopo:** esses testes estão versionados, **não executados no Xcode nesta revisão**.

**Risco/hipótese:** a sequência pode reconstruir duas vezes a sessão, custando aquisição, apresentação e posição; mesmo um estado final correto não demonstra ausência de tela vazia ou jitter. **Owner:** manter a semântica do pedido editorial, mas integrar a proteção no owner F13 que prepara B sem aposentar A; testar o efeito visual, não apenas `association.active`.

### P1-02 — Lacuna verificável: o drain de erro cobre toggle, não todas as transições (ABERTO)

**Fato de fluxo de controle:** [selectContext:814–855](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineApp/AppComposition.swift#L814-L855), [activateSavedPreset:979–1010](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineApp/AppComposition.swift#L979-L1010) e [openCollectionFeed:1156–1186](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineApp/AppComposition.swift#L1156-L1186) drenam `pendingRebuild` **somente após sucesso**; seus `catch` restauram A e lançam o erro antes desse ponto. [applyFilter:888–925](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineApp/AppComposition.swift#L888-L925) tem tratamento próprio e não demonstra drain no caminho de falha. O [rebuild:2034–2063](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineApp/AppComposition.swift#L2034-L2063) limpa `pendingRebuild` ao entrar, mas não garante consumir o pedido em caminhos que nunca o chamam.

**Hipótese a reproduzir:** uma resposta editorial durante falha de navegação pode ficar pendente até outro evento ou ser consumida no contexto errado. **Owner:** portar o mesmo oráculo de erro e pedido concorrente a todas as transições sob o único gate; definir se o rebuild pertence à seleção original ou à seleção efetivamente confirmada. Não espalhar novos schedulers ou retries.

### P1-03 — Continuidade visual A→B ainda quebrável pela arquitetura de compensação (ABERTO)

**Fato de código:** [selectContext:822–843](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineApp/AppComposition.swift#L822-L843), [toggleSource:764–785](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineApp/AppComposition.swift#L764-L785), [activateSavedPreset:987–1004](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineApp/AppComposition.swift#L987-L1004), [openCollectionFeed:1165–1181](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineApp/AppComposition.swift#L1165-L1181) e [rebuild:2040–2057](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineApp/AppComposition.swift#L2040-L2057) ainda aposentam A antes de B estar pronta. [restoreAfterFailedContextTransition:858–884](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineApp/AppComposition.swift#L858-L884) tenta reconstruir A **depois** da falha. A versão F13 contém handoff preparado e recuperação visível parcial, mas [F13:1187–1217](https://github.com/wsmontes/feedmine_v2/blob/c0392741/FeedMineApp/FeedMineApp/AppComposition.swift#L1187-L1217) também possui rotas ainda não migradas.

**Hipótese de regressão de produto:** tela vazia, deslocamento de card, aquisição duplicada e perda temporária de leitura mesmo quando a compensação termina verde. **Owner:** usar preparação/promoção F13 para todos os caminhos de troca; A permanece desenhada até B estar realmente pronta; falha mantém A e seu checkpoint. Portar testes de injeção do PR #9 como oráculos, não o método inteiro da main antiga.

### P1-04 — Concorrência/versionamento: melhoria de isolamento, risco de complexidade (PARCIALMENTE RESOLVIDO)

**Fato:** [AppComposition.swift:32–81](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineApp/AppComposition.swift#L32-L81) implementa espera FIFO cancelável e passagem direta do gate; [ReaderPreferencesStore.swift:95–137](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/Sources/FeedMinePersistence/ReaderPreferencesStore.swift#L95-L137) faz transação SQLite única com `expectedSelectionVersion`; [AppComposition.swift:715–766](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineApp/AppComposition.swift#L715-L766) limita conflitos de seleção a 3 tentativas preservando o desejo inicial do leitor. Testes de cancelamento e corrida externa estão versionados [CompositionTests.swift:3765–3820](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineAppTests/CompositionTests.swift#L3765-L3820), [4386–4520](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineAppTests/CompositionTests.swift#L4386-L4520).

**Risco/opinião arquitetural:** mais um gate, pending flag, continuation de adoção, compensação e retries numa linha paralela a F13 aumentam custo de integração e número de estados. A proteção transacional é útil; não assumir que toda a orquestração nova deve sobreviver. **Owner:** reter o contrato de intenção e versão no owner existente; reduzir os estados de transição após integração; testar seleção rápida, cancelamento, escrita externa, erro SQLite e relaunch.

### P0-01 — Render-ready ainda RED (ABERTO, sem mudança)

**Fato estático previamente verificado, PR #8 idêntico:** [FeedSession.swift:437–485](https://github.com/wsmontes/feedmine_v2/blob/83f05671/Sources/FeedMineRuntime/FeedSession.swift#L437-L485) mantém histórico projetado sem pixels decodificados para toda a região apresentada; [FeedScreenStore.swift:137–161](https://github.com/wsmontes/feedmine_v2/blob/83f05671/Sources/FeedMineUI/FeedScreenStore.swift#L137-L161) recebe a projeção. A [regra de 17/out](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/2026-10-17-render-ready-admission-rule.md) exige preparo **antes** da admissão. **Risco:** placeholders ou trabalho de mídia pela View, saltos ao filtrar ou alto uso de RAM se a solução decodificar toda a história. **Owner:** separar história durável da janela admitida render-ready na fronteira Runtime→Presentation existente; testar 750→1→750, scroll/restore e identidade no mesmo SHA de F13.

### P0-02 — B03/runway não demonstrado (ABERTO)

**Fato:** a janela audit muda transições e testes, não inclui prova B03. O último FAIL histórico (~5,70 s de pausa) não é revogado por PASS de baseline antiga. [B03 congelado](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md#L65-L90): **30 minutos de avanços reais**, 1 card/s, rajadas 3/s, **zero pausa visível ≥1 s** por falta de runway e sem fim artificial com oferta elegível. **Owner:** medir consumo, cards efetivamente apresentados, reserva, preparação, rede e mídia na mesma árvore integrada; B04/B05 no mesmo SHA. Não reduzir o trace para caber no runtime.

### P0-03 — Redirect privado validado tarde (ABERTO)

**Fato estático previamente verificado, sem avanço na main/F13:** [FeedDiscoveryTransport.swift:75–102](https://github.com/wsmontes/feedmine_v2/blob/c0392741/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L75-L102) valida a URL inicial, permite `session.bytes(for:)` seguir redirects e só depois confere destino final. **Risco inferido, não exploração demonstrada:** conexão privada antes do veto. **Owner:** verificar cada salto antes de conectar; prova público→privado com zero conexões privadas.

### P2-01 — Evidência de execução insuficiente na linha audit (ABERTO)

**Fato documental:** o [PR #9](https://github.com/wsmontes/feedmine_v2/pull/9) declara inspeção estática e um modelo isolado Swift 6.2.1/Linux, **não** build/XCTest do aplicativo. O HEAD `3e863a1c` não tem status contexts nem workflow de PR retornado na primeira página pelo conector. Testes versionados não são testes executados. **Fato histórico separado:** o PR #6 registra em artefatos 1.860 testes Swift macOS, 33 nativos iOS e duas jornadas XCUI com exit0, mas não prova a árvore audit nem a integração. **Owner:** exigir `xcodebuild` com `.xcresult`/logs/hashes e prova de frame/offset, sem declarar PASS de iPhone ou B03.

### Pendências P1/P2 transversais (mantidas)

**P1:** R4 integral, inventário/seleção de todas as Editions, recuperação sem singleton, transições A→B→A, filtros sem descartar supply reutilizável, scroll e identidade, reabertura offline, salvos/coleções/fontes, PD-4/PD-5/PD-9, catálogo público PD-10/INV-18, B02/B04/B05 integrados. **P2:** B06 iPhone físico NOT_RUN, logs independentes, memória e custo de restauração. INV-12/14/15 proíbem owners, pipelines, timers, caches ou filas paralelos como solução cosmética.

## 4. Provas e comandos para o Mac — NÃO EXECUTADOS PELO MONITOR

```bash
git fetch origin main monitor/architecture product/nf04-tail-truth chatgpt/render-ready-contract-red-01 audit/session-transition-failure-probe-20261030
git rev-parse origin/main origin/product/nf04-tail-truth origin/chatgpt/render-ready-contract-red-01 origin/audit/session-transition-failure-probe-20261030
git log --oneline 1c9b3a5ef4474f07a9206da7c2dc25e77ab02cd9..origin/audit/session-transition-failure-probe-20261030
git diff --check 1c9b3a5ef4474f07a9206da7c2dc25e77ab02cd9..origin/audit/session-transition-failure-probe-20261030
git worktree add --detach /tmp/feedmine-monitor-audit-042 3e863a1cfd065225262c6fcc2798370f6a7431ba
cd /tmp/feedmine-monitor-audit-042
swift test --filter ReaderPreferencesStoreTests
swift test --filter SessionStoreTests
swift test
xcodebuild -list -project FeedMineApp/FeedMineApp.xcodeproj
xcrun simctl list devices available
# Escolher scheme/destino reais, executar CompositionTests e XCUI com -resultBundlePath,
# preservar .xcresult, logs, binário SHA, banco/fixture e vídeos de viewport.
# Adaptar oráculos do PR #9 à árvore F13; NÃO misturar SHAs ao reportar PASS.
```

**Oráculos que não podem ser substituídos por asserts de estado final:** A continua visualmente estável enquanto B é preparada; falha pré-commit/pós-commit/compensação não produz tela vazia, nem perde checkpoint, card ou offset; `pendingRebuild` é consumido corretamente após falha de **cada** rota; cancelamento/seleção rápida e escritor externo não atropelam intenção; A→B→A e relaunch offline preservam IDs/posição/salvos; render-ready não entrega card incompleto; B03 real 30 minutos, B04 imutabilidade, B05 retorno e B06 físico. Capturar traces monotônicos e frames reais.

## 5. Memória compacta para próxima execução

- **Monitor:** 037 `34b39a53` → 038 `33cedde0` → 039 `2464c5dc` → 040 `e3524bcf` → 041 `5842ce1c` → **042 (este documento)**. Blob anterior `baa91091`.
- **SHAs:** main `fb8e65ff`; F13 PR #6 `c0392741`; render PR #8 `83f05671`; audit PR #9 **`3e863a1c`**, antes `1c9b3a5e` (**+54 commits**, quatro arquivos Swift); reserve `a8814282`; integrity `031b27d3`; next `d6a05266`; release `cede37f6`; integration/chatgpt `8203d439`; integration/main-into-app-line `09a6e3a4`; candidate histórica `1b990306`.
- **Avanço desta janela:** PR #9 adicionou gate FIFO cancelável, commit atômico com version fence, retries limitados de conflitos, reconciliação externa e drain editorial após falha de toggle. Há código e testes, **sem execução XCTest/Xcode**; não considerar integração aprovada.
- **Lacuna nova/precisada:** drain no caminho de erro só em toggle; outras rotas ainda podem descartar pedido pendente. Fechar A antes de B persiste em várias rotas; não aceitar compensação como garantia visual.
- **P0 abertos:** render-ready, B03/runway, redirects privados. **P1:** R4 integral/offline, UI de todas Editions, seleção/filtros/scroll, transições, integração #6/#8/#9, salvos e catálogo PD-10. **P2:** B06 físico e logs independentes.
- **Gates:** R4 completo NÃO ACEITO; B03 FAIL histórico; B06 NOT_RUN; B02/B04/B05 sem novo PASS integrado; release NÃO APROVADA. Nenhum XCTest, simulador, iPhone ou benchmark executado por este monitor.
- **Handoff:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. Monitor consultivo; não modificar main, produção, testes, benchmarks, coordenação, issues ou PRs.
