# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 036 · Vancouver, 29/10/2026, 13:45 PDT.** Parecer consultivo, **não certificação de release**. O OMP precisa executar `git fetch origin monitor/architecture` e ler este documento explicitamente; nenhuma notificação automática é enviada aos executores.

## 1. Base, janela, SHAs e fontes de autoridade

**Memória persistente:** revisão 035, [commit 9cb92778](https://github.com/wsmontes/feedmine_v2/commit/9cb92778c6cd4b8f6bc837a84c07ea4a35ea7425), blob **62032beee22323507a65e9d002c0a8d279d4980a**. **Intervalo incremental:** 28/out ~23:46 → 29/out 13:45 PDT. Monitor verificado em **9cb92778** antes da publicação desta revisão.

**Mudança corrente comprovada:** [PR #6 (draft)](https://github.com/wsmontes/feedmine_v2/pull/6), `product/nf04-tail-truth`, avançou **124edecc8574ac35ba950061c0d1a5876c9ac103 → 0a064a4fd91c72a44a921ffd53d723e20f876abe**, **2 commits à frente, zero atrás**: [fdbd4c10](https://github.com/wsmontes/feedmine_v2/commit/fdbd4c10c555c47fd28da18d1acfaf095d0c2cd4) (fence da limpeza de checkpoint após rollover) e [0a064a4f](https://github.com/wsmontes/feedmine_v2/commit/0a064a4fd91c72a44a921ffd53d723e20f876abe) (transporte de ownership pelo pipeline). [Diff exato entre revisões](https://github.com/wsmontes/feedmine_v2/compare/124edecc8574ac35ba950061c0d1a5876c9ac103...0a064a4fd91c72a44a921ffd53d723e20f876abe): 4 arquivos de produção, 4 de testes, documentação de checkpoint/planos e novos manifestos/logs de evidência. A descrição do PR foi atualizada em 29/out às 13:28 PDT.

**Sem avanço confirmado por comparação direta:** `main@fb8e65ff5a5e83ae85c9061996aaa0ebf2b7ca48`; `chatgpt/render-ready-contract-red-01@83f05671bd54c603bb6052589ab3d921152c2df5` ([PR #8 draft](https://github.com/wsmontes/feedmine_v2/pull/8)); `product/reserve-20261024@a88142820e49dde7225fdf60776187c2306ae044`; `product/integrity-20261024@031b27d3bfc0355c5fc3be72d03c57cde0f0f91f`; `codex/feedmine-next-internal@d6a052667abfd478d5e09f13afe0e01685ef9344`; `release/build-56@cede37f6e925dc19e54a2d67416abd9569559e01`. `integration/candidate@1b990306` continua **127 commits atrás de main e zero exclusivos**; `integration/chatgpt@8203d439` não é candidata comprovada. Foram inspecionadas **176 branches** (duas páginas da API), PRs e issues recentes; PR #5 segue aberto e histórico. [Comparação PR #6...PR #8](https://github.com/wsmontes/feedmine_v2/compare/product/nf04-tail-truth...chatgpt/render-ready-contract-red-01) agora diverge por **408/17 commits próprios** desde o ancestral comum; não prova conflito de merge, mas impede transferir testes de uma linha à outra.

**Autoridade atual consultada na main, sem mudanças no intervalo:** [North Star](https://github.com/wsmontes/feedmine_v2/blob/fb8e65ff/docs/product/PRODUCT_NORTH_STAR.md), [decisões PD-1–PD-10](https://github.com/wsmontes/feedmine_v2/blob/fb8e65ff/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz de execução](https://github.com/wsmontes/feedmine_v2/blob/fb8e65ff/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [invariantes](https://github.com/wsmontes/feedmine_v2/blob/fb8e65ff/docs/architecture/PRODUCT_INVARIANTS.md), [benchmark congelado B01–B06](https://github.com/wsmontes/feedmine_v2/blob/fb8e65ff/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md), [regra de admissão render-ready de 17/out](https://github.com/wsmontes/feedmine_v2/blob/fb8e65ff/docs/product/2026-10-17-render-ready-admission-rule.md#L6-L36) e documentos recentes F13. Blueprints antigos não prevalecem sobre essas decisões.

## 2. Resumo executivo e consequência para o leitor

**Progresso técnico real, mas R4 ainda FAIL.** Os dois commits corrigem um caso de perda de posição após rollover de Edition no mesmo binding e passam a transportar a expectativa de ownership desde os pedidos de produção até os quatro escritores de publicação. Isso reduz o risco de uma preparação antiga publicar na leitura nova e fecha uma lacuna identificada na revisão 034. **Ainda não há restauração/salvamento semântico por Edition na fronteira PublicationHistory/FeedSession nem injeção do token nos responsáveis frio/ativo e no host nativo**. O próprio PR #6 mantém **R4 FAIL**. Portanto, não classificar o fluxo A→editar regras→B→A como resolvido.

**Evidência nova relevante, escopo limitado:** o repositório adicionou [relatório de suíte completa](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/docs/reviews/2026-10-29-f13-owned-publication-pipeline.md) e [manifesto de proveniência](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/docs/reviews/evidence/2026-10-27-source-exclusions/r4-owned-pipeline-provenance.json) que registram **1813 testes do pacote Swift macOS Debug, 1 ignorado, 0 falhas na execução final, exit 0**. A primeira execução completa falhou com três asserções em inventários explícitos de schema; o código de teste foi atualizado e a execução completa final foi reportada verde. Há logs comprimidos e hashes declarados, mas **o monitor não executou nem reproduziu XCTest/Swift tests, nem inspecionou independentemente os bytes dos logs comprimidos**. A suíte macOS **não certifica** iOS, render-ready do PR #8, B03, R4 ou release.

**Maior impedimento de produto permanece:** P0 render-ready da revisão 035 (cartas image-bearing apresentadas sem pixels fora da banda decodificada), P0 B03 (continuidade adaptativa sem prova integrada) e P0 de redirects privados. Não sacrificar scroll, histórico, reabertura offline ou simplicidade arquitetural para fechar um teste isolado.

## 3. Achados priorizados — fatos, hipóteses, riscos e orientação mínima

### P1-01 — Ownership finalmente atravessa coordenador e slices, mas não chega ao host (PARCIAL; antes lacuna aberta)

**Fato comprovado no diff:** [PublicationCoordinator.swift:58–78,116–139,151–165,219–226](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/Sources/FeedMinePublication/PublicationCoordinator.swift#L58-L78) agora leva `bindingPublication` na criação e `bindingActivation` no append, repassando-os ao PublicationStore. [InitialProductionSlice.swift:54–57,171–177](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/Sources/FeedMineRuntime/InitialProductionSlice.swift#L54-L57) e [LocalProductionSlice.swift:95–98,230–236](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/Sources/FeedMineRuntime/LocalProductionSlice.swift#L95-L98) preservam a expectativa capturada durante a preparação. [Testes de coordenador](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/Tests/FeedMinePublicationTests/PublicationCoordinatorTests.swift#L445-L506) e [de produção real](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/Tests/FeedMineCompositionTests/SourceExclusionProductionTests.swift#L426-L487) cobrem writers válidos e rejeição de ativação aposentada no meio da preparação, preservando edição e posição anteriores.

**Fato ainda aberto:** os campos novos continuam opcionais com default `nil`; a [documentação do checkpoint](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/docs/reviews/2026-10-29-f13-owned-publication-pipeline.md#L1-L22) e [proveniência](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/docs/reviews/evidence/2026-10-27-source-exclusions/r4-owned-pipeline-provenance.json) reconhecem `native_binding_injection: false`, sem passagem pela restauração semântica. A proteção end-to-end do app **não está concluída**. **Hipótese de risco:** ao conectar apenas parte da composição, o writer pode rejeitar publicações que antes eram aceitas, ou o host pode continuar exibindo a Edition errada; testes do slice não cobrem a UI.

**Owner mínimo:** ligar a **mesma** ativação do contexto lógico a PublicationHistory/FeedSession, cold/live e composição nativa, sem outro cache/owner. Cobrir `nil`/stale nos wrappers quando há binding ativo e a expectativa de `expectedActiveEditionID` durante rollover. Provar A→editar exclusão global→B→A, callback tardio, reabertura offline, identidade/posição, salvos/coleções/fontes e nenhuma publicação antiga reapropriada. **R4 permanece FAIL** até prova no host.

### P2-01 — Limpeza tardia de checkpoint após rollover agora protegida (RESOLVIDO no escopo do store; regressão a vigiar)

**Fato comprovado:** antes, um callback A atrasado podia limpar o singleton de B quando A e B compartilhavam o token de ativação após rollover. [SessionStore.swift:147–166](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/Sources/FeedMinePersistence/SessionStore.swift#L147-L166) exige `expectedEditionID` em `clearActiveCheckpoint(bindingActivation:)`, verifica o owner corrente e a Edition efetivamente armazenada **dentro da transação**. [ReaderHistoryCheckpointTests.swift:118–155](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/Tests/FeedMinePersistenceTests/ReaderHistoryCheckpointTests.swift#L118-L155) exige rejeitar A tardio e preservar B/histórico. [Relatório RED→GREEN](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/docs/reviews/2026-10-29-f13-checkpoint-clear-rollover.md): cinco testes, dois erros no RED, cinco verdes e 243 afetados verdes segundo evidência versionada. **Conclusão:** lacuna específica corrigida estaticamente e respaldada por evidência de teste fornecida; **não** equivale a R4 aprovado.

**Risco de regressão (hipótese):** algum caller legado ainda usar `clearActiveCheckpoint()` sem ativação e tentar limpar após a instalação do binding, ou falhar ao informar a Edition esperada. **Owner:** ao fazer wiring nativo, revisar todos os callers e preservar testes de rollover, ausência de checkpoint e restauração offline; não relaxar o fence para evitar exceções.

### P0-01 — Render-ready viola a fronteira de apresentação (ABERTO; sem commits novos no PR #8)

**Fato estático herdado, reconfirmado pelo HEAD idêntico:** [FeedSession.swift:437–485](https://github.com/wsmontes/feedmine_v2/blob/83f05671/Sources/FeedMineRuntime/FeedSession.swift#L437-L485) conserva cabeça histórica completa mas só decodifica a banda próxima à âncora; [FeedScreenStore.swift:137–161](https://github.com/wsmontes/feedmine_v2/blob/83f05671/Sources/FeedMineUI/FeedScreenStore.swift#L137-L161) passa a lista integral à UI. [Teste discriminante](https://github.com/wsmontes/feedmine_v2/blob/83f05671/Tests/FeedMineRuntimeTests/ProjectionDecodeMeasurementTests.swift#L70-L150) constrói 800 cartas, 766 IDs históricos e apenas 25 bitmaps na âncora 750; a asserção de zero image-bearing sem pixels é RED intencional, **não executada aqui**. Contradição com a [regra vigente](https://github.com/wsmontes/feedmine_v2/blob/fb8e65ff/docs/product/2026-10-17-render-ready-admission-rule.md#L8-L29).

**Risco (hipótese):** remover cartas sem bitmap na UI quebra offsets/B05; decodificar todo o histórico destrói memória; decodificar sob scroll torna a apresentação dependente de I/O. **Owner:** distinguir história publicada de valores efetivamente readmitidos com pixels prontos, na fronteira Runtime/Presentation existente, mantendo âncora e identidade; testar ida ao card 1 e retorno ao 750, sem salto, placeholder ou nova Edition. Integrar conscientemente com F13, não promover PR #8 sozinho.

### P0-02 — B03, runway contínua e independência da rede (ABERTO)

**Fato estático herdado:** [AppComposition.swift:4572–4590](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/FeedMineApp/FeedMineApp/AppComposition.swift#L4572-L4590) ativa o driver cedo após publicação enquanto o cold bootstrap ainda aguarda outras fontes; [4161–4218](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/FeedMineApp/FeedMineApp/AppComposition.swift#L4161-L4218) ativa novamente após cold.run. **Hipótese, não defeito reproduzido:** sobreposição de ativações pode causar corrida ou instalação fora de ordem. B03 FAIL e atraso de ~5,70 s são evidências históricas, não medida desta árvore.

**Owner:** traço monotônico de cold→publication→runway→local admission→viewport com IDs de Edition/segmento, origem de cada oportunidade e uma só autoridade; rodar **30 minutos de avanços reais** a 1 card/s com rajadas 3/s por 20 s a cada 5 min, no corpus congelado. Exigir zero pausa ≥1 s por falta de runway, zero fim artificial e zero deslocamento da leitura; repetir B04/B05 na mesma árvore.

### P0-03 — Redirect privado validado depois da conexão (ABERTO)

**Fato estático herdado:** [FeedDiscoveryTransport.swift:69–101](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L69-L101) valida o host final após chamada que pode seguir redirects. **Hipótese de exploração:** conexão a host privado pode ocorrer antes do veto; não foi executado ataque nesta revisão. **Owner:** validar cada salto **antes** de conectar, com teste público→privado exigindo **zero conexões** ao destino privado.

### P1-02 — Outras invariantes de produto e integração ainda sem prova (ABERTAS)

**Fatos de estado:** PRs #6 e #8 são drafts divergentes, main/build-56 não avançaram. [PreparedReserve.swift:188–258](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/Sources/FeedMineRuntime/PreparedReserve.swift#L188-L258) e [333–343](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/Sources/FeedMineRuntime/PreparedReserve.swift#L333-L343) permanecem pontos de reprodução dos contraexemplos 112+1 e 3×5xx→recuperação da memória anterior. Persistem sem prova integrada: conclusões concorrentes invertidas, diversidade/PD-4, mudança de filtros sem destruir trabalho reutilizável, estabilidade de scroll/posição, salvos/coleções/fontes, reabertura offline, PD-10 e B06. **Não interpretar ausência de commits como correção.**

**Owner:** escolher uma única árvore de integração, comparar PR #8 com F13 em três vias, preservar invariantes de imutabilidade e reuso, e executar B02/B04/B05/PD-10 e jornadas offline nela. Não criar filas, retries, timers, caches ou owners paralelos para contornar os sintomas.

### P2-02 — Evidência de suíte macOS melhorou; release não certificada (PARCIAL)

**Fato documental:** [relatório F13](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/docs/reviews/2026-10-29-f13-owned-publication-pipeline.md#L8-L22) declara execução completa **1813 testes, 1 skipped, 0 falhas**; [JSON final](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/docs/reviews/evidence/2026-10-27-source-exclusions/r4-owned-pipeline-full-final.json) registra `exit_code: 0` e [proveniência](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/docs/reviews/evidence/2026-10-27-source-exclusions/r4-owned-pipeline-provenance.json) lista hashes de fontes, executável e logs. O primeiro full run tinha 3 asserções falhas nos inventários de schema; [PublicationRunwayStoreTests.swift:274–279,516–610](https://github.com/wsmontes/feedmine_v2/blob/0a064a4f/Tests/FeedMinePersistenceTests/PublicationRunwayStoreTests.swift#L516-L610) acrescenta duas migrações, quatro tabelas e seis autoíndices às listas exatas, preservando os oráculos anteriores. Isso é **evidência registrada**, não execução deste monitor.

**Limites:** o teste de catálogo de referência continua ignorado; GitHub Actions retornou zero runs no repositório e o HEAD F13 zero status checks/workflow runs consultados. Isso não prova inexistência de execução local. **Não há PASS independente de XCTest, simulador, iPhone, R4, B01–B06 ou benchmark.** B03 FAIL histórico, R4 FAIL conforme PR, B06 NOT_RUN; B02/B04/B05 sem nova certificação integrada. Release pública **não aprovada**.

## 4. Comandos/provas necessários no Mac — NÃO EXECUTADOS NESTE MONITOR

~~~bash
git fetch origin main monitor/architecture product/nf04-tail-truth chatgpt/render-ready-contract-red-01 release/build-56
git rev-parse origin/main origin/product/nf04-tail-truth origin/chatgpt/render-ready-contract-red-01 origin/monitor/architecture
git log --oneline 124edecc8574ac35ba950061c0d1a5876c9ac103..origin/product/nf04-tail-truth
git diff --check 124edecc8574ac35ba950061c0d1a5876c9ac103..origin/product/nf04-tail-truth
git diff --stat 124edecc8574ac35ba950061c0d1a5876c9ac103..origin/product/nf04-tail-truth
git diff 124edecc8574ac35ba950061c0d1a5876c9ac103..origin/product/nf04-tail-truth -- Sources/FeedMinePersistence/SessionStore.swift Sources/FeedMinePublication/PublicationCoordinator.swift Sources/FeedMineRuntime/
git worktree add --detach /tmp/feedmine-monitor-036 0a064a4fd91c72a44a921ffd53d723e20f876abe
cd /tmp/feedmine-monitor-036
swift test --filter ReaderHistoryCheckpointTests
swift test --filter PublicationCoordinatorTests
swift test --filter SourceExclusionProductionTests
swift test --filter PublicationRunwayStoreTests
swift test
xcodebuild -list -project FeedMineApp/FeedMineApp.xcodeproj
xcrun simctl list devices available
# Escolher scheme/destino real e guardar .xcresult, logs de tempo monotônico, vídeo e frames.
scripts/run-discovery-benchmark.sh --gate B03 --profile A --profile B
scripts/run-discovery-benchmark.sh --gate B04 --profile A --profile B
scripts/run-discovery-benchmark.sh --gate B05 --profile A --profile B
~~~

**Provas discriminantes:** (1) capturar token de binding/Edition uma vez e demonstrar rejeição de callback aposentado em cold/live/host sem retomar ativação; (2) A→regra global→B→A→relaunch offline com mesma posição e salvos/coleções/fontes; (3) limpar A depois do rollover para B, mantendo B e checkpoint histórico de A; (4) 800 cartas/âncora 750, voltar ao 1 e 750, zero image-bearing exposto sem pixels, sem decodificar tudo; (5) B03 completo com contagem de **cards distintos efetivamente consumidos**, não tempo de tela; (6) B04 sem alteração de prefixo/posição por rede, B05 offline, B06 no iPhone físico. Fixar SHA, corpus, aparelho, iOS, rede e artefatos. Não alterar a régua.

## 5. Memória compacta de progresso e pendências

- **Histórico do monitor:** 025 309c1d20 → 026 859c34ce → 027 c6aee149 → 028 6885ed5d → 029 5efa2afb → 030 31d01b64 → 031 8f608791 → 032 a5303254 → 033 365a5498 → 034 a0df2ec7 → 035 9cb92778 → **036 (este documento)**.
- **Últimos HEADs verificados:** main **fb8e65ff**; PR #6/F13 **0a064a4f** (anterior 124edecc); PR #8/render-ready **83f05671**; reserve **a8814282**; integrity **031b27d3**; next **d6a05266**; build-56 **cede37f6**; integration/candidate **1b990306** (histórica).
- **Resolvido nesta janela (escopo preciso):** P2 de limpeza após rollover com fence por Edition e transporte de ownership por coordenador/initial/local até quatro writers. **Não resolvido:** binding no host, restauração semântica, R4 e gates de produto. Evidência macOS de suíte completa adicionada, não repetida pelo monitor.
- **P0 abertos:** render-ready, B03/runway, redirects. **P1 abertos:** R4/F13 ponta a ponta, integração PR #6/#8, reserva/liveness, concorrência, diversidade, filtros, scroll/identidade/posição, offline, persistência de salvos/coleções/fontes, PD-10, B06. **P2:** teste de catálogo ignorado, validação em dispositivo, callers legados do clear e prova independente de CI/bench.
- **Prioridade mínima:** fechar fronteira render-ready sem destruir B05; concluir ownership F13 na sessão/host e provar R4; medir B03; corrigir redirect e reproduzir reserva; executar B02/B04/B05/B06 e PD-10 na **mesma** candidata antes de qualquer promoção.
- **Limites deste monitor:** somente este Markdown na branch `monitor/architecture`. Nenhum arquivo de produção, teste, benchmark, script, coordenação, issue, PR ou `main` é alterado. O OMP deve fazer fetch e ler o arquivo, sem presumir handoff automático.
