# FeedMine V2 — Monitor externo de código, arquitetura e produto

> **Canal consultivo:** este documento é atualizado apenas na branch `monitor/architecture`. Não revoga o Norte/PDs/invariantes, não autoriza merges e não é resultado de testes executados pelo revisor.

## Índice de handoff — documentos de trabalho de 17/out/2026

- [**Intenções, entregas, lacunas e decisões de integração**](FEEDMINE_INTENTIONS_VS_DELIVERIES_2026-10-17.md): inventário e fila de decisão; `main@5e4e2142`.
- [**Estudo arquitetural do engasgo na rolagem**](FEEDMINE_SCROLL_ARCHITECTURAL_STUDY_2026-10-17.md): caminho visual→MainActor→atores→instalação, distinção entre correlação e causa, medição discriminante e critérios de correção.
- Ambos são **consultivos e somente na branch `monitor/architecture`**; não equivalem a nova regra do produto, aprovação de merge ou prova no Mac. OMP deve lê-los expressamente antes de considerar a próxima candidata.

## Revisão 003 — 2026-10-17, tarde (America/Vancouver)

**Escopo e baseline:** GitHub `wsmontes/feedmine_v2`, leitura de `main@5e4e21425f5e1be22cdf7ed10e4c1728d2a33f15`, comparação com a base do monitor `37633bb3e4b6342ae89a9f58d78b90f3182ab14a`, inspeção das branches ativas `fix/deferral-invalidates-list@10bc0bd72cfd`, `fix/render-ready-admission@3c741ce53d4a`, `fix/filter-confirmation-boundary@2c642abcd514`, `feat/durable-saves@ab5c6067fa61`, `fix/reader-availability-language@faf8256af2b2`, além das branches de UI/testes e docs normativos. Nenhuma compilação/teste foi realizada **nesta** revisão.

### Veredito

**A direção melhorou, mas a implementação ainda não está integrada nem certificada.** Entre `37633bb3` e `5e4e2142` há dez commits na `main`, todos documentais (incluído README do monitor). Em paralelo surgiram mudanças funcionais relevantes e uma medição física reportada em branches. Não inferir que o monitor produziu essas mudanças: seu documento remoto estava somente no baseline de configuração, sem revisões publicadas, portanto o consumo pelo OMP **não foi comprovado**. O avanço corresponde de forma demonstrável às novas diretivas do PO, independentemente da causa.

### Achados e recomendações

**P0 — Mutação de layout na admissão, contrária à imutabilidade. FATO ESTÁTICO; não integrar sem correção.** Em `fix/render-ready-admission`, [`PresentationCard.swift:88–102`](https://github.com/wsmontes/feedmine_v2/blob/3c741ce53d4a/Sources/FeedMineRuntime/PresentationCard.swift#L88-L102) transforma um `PublishedCard` com contrato `.hero`/`.thumbnail` em `.textOnly` quando a decodificação falha, conservando o mesmo `PublicationCardID`. [`RenderReadyAdmissionTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/3c741ce53d4a/Tests/FeedMineRuntimeTests/RenderReadyAdmissionTests.swift) **exige** essa conversão. Conflita com [PD-5](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_DECISIONS_2026-10-09.md) e com a [diretriz de prontidão 17/out](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/2026-10-17-render-ready-admission-rule.md): falha transitória/ausência local não autoriza reescrever apresentação publicada. Se não há pixels para um contrato com imagem, conservar publicação e adiar a admissão daquela apresentação ou implementar política explícita anterior à publicação, nunca mutação silenciosa de layout. **A branch `feat/durable-saves` descende desse commit**, portanto integrações de salvos carregam essa mesma decisão a menos que ela seja corrigida.

**P1 — Melhoria de fluidez com medição real reportada, AINDA FORA DA MAIN.** [`fix/deferral-invalidates-list@10bc0bd72cfd`](https://github.com/wsmontes/feedmine_v2/commit/10bc0bd72cfdfcdb2cfe89e2eed7b4a520183f27) desloca leitura da janela segurada e contagem de adiamentos para evitar invalidação da lista sob gesto (`FeedInteractionPresentation.swift`, `FeedScreen.swift`, `FeedNativeViewport.swift`). Mensagem do commit relata três corridas antes (2,89/3,90/3,02%) e depois (1,75/1,51/1,27%) de frames acima de 1,5× o orçamento numa jornada física de 14 arrastadas, mediana 3,02% → 1,51%. **Evidência reportada pelo autor, não logs auditados aqui;** não chamar fluidez geral certificada. Revalidar na integração real, mantendo mesmas condições, além de gesto/âncora, viewport, concorrência e relaunch.

**P1 — Salvos duráveis: boa implementação inicial, provas completas pendentes.** [`feat/durable-saves@ab5c6067`](https://github.com/wsmontes/feedmine_v2/commit/ab5c6067fa61af41a3e517f388a072591d51513a) introduz `SavedMediaCoordinator`, estado persistido separado para disponibilidade, erros explícitos, recuperação/tentativa de mídia salva e testes de falhas. [`SavedMediaCoordinator.swift:60–127`](https://github.com/wsmontes/feedmine_v2/blob/ab5c6067fa61/Sources/FeedMineComposition/SavedMediaCoordinator.swift#L60-L127). **Fato:** esses caminhos e testes existem; **não comprovado:** prova no Mac/aparelho com limpeza/restart offline e todas as promessas de texto/mídia duráveis. Verificar retentores de mídia, troca de versão, falta de espaço, bookmarks em múltiplas caixas e falha de gravação. A dependência da branch com P0 acima é obstáculo concreto antes do merge.

**P1 — Filtros: correção candidata com confirmação durável.** [`fix/filter-confirmation-boundary@2c642abcd514`](https://github.com/wsmontes/feedmine_v2/commit/2c642abcd514145da92f15a7090f45e42b1d029b) muda `AppComposition.applyFilter` para gravar contexto/expiração antes de alterar memória, diferenciando falha de persistência e de apresentação. [`AppComposition.swift:661–695`](https://github.com/wsmontes/feedmine_v2/blob/2c642abcd514/FeedMineApp/FeedMineApp/AppComposition.swift#L661-L695). Testar interrupção entre fases, disco falhando, retorno A→B→A, posição/edição e restart offline; não inferir PASS da presença de testes.

**P1 — Aprendizagem do runway ainda descartada no foreground da main.** [`RunwayController.swift:283–305`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineRuntime/RunwayController.swift#L283-L305) executa `deactivate()` em `activate(scope)`, apagando `consumptionSamples` e `latencySamples`; [`AppComposition.swift:3049–3057`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/FeedMineApp/FeedMineApp/AppComposition.swift#L3049-L3057) reativa a apresentação em foreground. **Fato do caminho; impacto quantitativo não medido aqui.** Teste reproduzindo consumo aprendido → background → retorno à MESMA edição e compare política de reserva, não resetar aprendizado sem mudança de escopo.

**P1 — Busca/personalização continuam divergentes na main.** [`CandidateProvider.swift:84–93`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineEditorial/CandidateProvider.swift#L84-L93) trata expressão com `-termo` como substring literal; [análise de personalização](https://github.com/wsmontes/feedmine_v2/blob/main/docs/reviews/2026-10-17-personalization-conversion-and-v1-reading.md) registra `.neutral` explícito convertido em exclusão. Esses problemas estão documentados mas não corrigidos na `main`; priorizar depois dos invariantes de admissão/fluidez/durabilidade.

**P1 — Gate de release:** a evidência mais recente encontrada na `main` ainda diferencia testes no simulador de B06 físico, não certifica fluidez nem uma release externa ([build 48](https://github.com/wsmontes/feedmine_v2/blob/main/docs/reviews/2026-10-16-build-48-validacao.md)). O bump da build 49 não prova execução B06. Não alegar alteração do status sem nova evidência.

### Próxima decisão recomendada ao OMP

1. **Bloquear merge da cadeia `render-ready-admission` → `durable-saves`** enquanto texto automático não respeitar o contrato congelado; ajustar no owner existente.
2. Integrar isoladamente a melhoria de rolagem com revalidação física e checagem de âncora/gesto.
3. Validar filtros e salvos como jornadas end-to-end, após reconciliar a árvore de integração.
4. Corrigir regressões semânticas ainda na main (runway de foreground, neutral e busca).
5. Executar o B06 sem alterar benchmark e atualizar status de release com provas.

### Estado de handoff

Esta edição é consultiva. OMP deve executar `git fetch origin monitor/architecture` e `git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md` e confirmar a leitura em sua própria coordenação; uma publicação no GitHub, sozinha, **não notifica** o processo local.

---

## Baseline anterior — 2026-10-17

- Branch de monitor criada a partir de `main@37633bb3e4b6342ae89a9f58d78b90f3182ab14a`.
- Revisões 001 e 002 foram apresentadas no ChatGPT, **não publicadas** no GitHub; não tratar o estado inicial deste documento como memória desses achados. A revisão 003 acima reconfirmou os pontos centrais que permanecem.
