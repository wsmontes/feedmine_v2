# FeedMine V2 — Monitor externo de arquitetura, código, produto e release

> **Canal consultivo, somente `monitor/architecture`.** Este parecer não altera normas, autoriza merges nem comprova execução de testes. OMP precisa fazer `git fetch origin monitor/architecture` e ler explicitamente este arquivo; não há notificação automática.

## Revisão 008 — 2026-10-19 11:36 PDT (America/Vancouver)

**Intervalo:** desde a revisão 007 (18/out 01:42 PDT), confrontado também com o último relatório remoto, revisão 003 (17/out). **Método:** leitura GitHub de refs, diff `main...integration/51`, PRs, código da candidata, documentos normativos e registro de pausa. **Sem execução de Swift, XCTest, simulador, iPhone ou benchmark nesta revisão.**

**SHAs verificados:** `main@5e4e21425f5e1be22cdf7ed10e4c1728d2a33f15`; `integration/51@8fcfe37c6ff46b68b6754b25852bc1b47d825766` (23 commits à frente, zero atrás da main); `fix/deferral-invalidates-list@10bc0bd72cfdfcdb2cfe89e2eed7b4a520183f27` (fora da 51); `docs/status-pause-2026-10-17@711cfac3c38c`; `monitor/architecture@a0bba1a0864c` antes desta tentativa de publicação. **PRs abertos: zero.** Não foram identificados commits ou provas novas após a revisão 007 nas referências ativas examinadas. Branches históricas `integration/candidate@1b990306` e `integration/chatgpt@8203d439` não são a candidata atual.

### Resumo executivo

A candidata 51 integra mudanças reais de admissão render-ready, salvos, filtros, aquisição inicial, idioma e runway, mas **não** integra a correção de fluidez do gesto medida isoladamente. O P0 antigo de mutação silenciosa de imagem em texto foi resolvido **na candidata**, não na main. Permanecem quatro riscos P1 de experiência/durabilidade em código e um bloqueio de aceitação: não há B01–B06 completos para o SHA 51. A revisão 007 identificou ainda uma divergência documental sobre TestFlight interno versus exigência específica de B06 antes de enviar a 51.

### Mudanças verificadas e efeito de produto (desde a revisão remota 003)

- [`da94d5c7`](https://github.com/wsmontes/feedmine_v2/commit/da94d5c762496dddc76304eb3866acbb5218b4de) + [`d942b75e`](https://github.com/wsmontes/feedmine_v2/commit/d942b75e1397): não rebaixam hero/thumbnail automaticamente para texto na mesma ocorrência; texto declarado exige evidência. **P0 anterior resolvido na árvore 51.**
- [`1487c750`](https://github.com/wsmontes/feedmine_v2/commit/1487c750bd4b): persistência de disponibilidade e preparação de mídia para salvos; mantém risco de erros de escrita descartados.
- [`2c642abc`](https://github.com/wsmontes/feedmine_v2/commit/2c642abcd514): filtros confirmados no armazenamento antes da memória; falta prova A→B→A no aparelho/árvore final.
- [`058a629d`](https://github.com/wsmontes/feedmine_v2/commit/058a629dc7f1) + [`c4fbb215`](https://github.com/wsmontes/feedmine_v2/commit/c4fbb215512b): aquisição inicial/ordenação e escolha explícita de idioma; relato de 5,5 s em rede real para primeiro conteúdo contra objetivo de 3 s.
- [`54680fa4`](https://github.com/wsmontes/feedmine_v2/commit/54680fa4a7aa9bee756630898047002c70191fae) + [`dd5b2a87`](https://github.com/wsmontes/feedmine_v2/commit/dd5b2a877c765141dc394e4fa99b3f3b4b5c19be): cadência de foreground com preservação de amostras do runway no mesmo escopo; integrar juntos.
- [`10bc0bd7`](https://github.com/wsmontes/feedmine_v2/commit/10bc0bd72cfdfcdb2cfe89e2eed7b4a520183f27): reduz invalidação de lista sob gesto; **fora da 51**. Mediana de frames lentos 3,02%→1,51% é relato de medição física da branch, não da candidata.

### Achados, risco, owner e prova discriminante

**P0 release — ausência de aceitação da candidata (FATO DOCUMENTAL).** [Registro de pausa §4–6](https://github.com/wsmontes/feedmine_v2/blob/docs/status-pause-2026-10-17/docs/reviews/2026-10-17-estado-em-pausa.md) relata pacote 1445/0 no SHA 51, porém B06 `NOT_RUN`, B01–B03 interrompidos, archive de desenvolvimento sem export/upload, UI T2/T4 falhando também na base. Nenhum relato isolado é PASS B01–B06. **Owner release:** executar gates congelados e preservar SHA, hashes, logs, `.xcresult` e evidência física antes de certificar release.

**P1 — fim artificial apesar de supply pronto (FATO ESTÁTICO, reprodução pendente).** [`FeedSession.swift:236–247`](https://github.com/wsmontes/feedmine_v2/blob/8fcfe37c/Sources/FeedMineRuntime/FeedSession.swift#L236-L247) obtém janela finita de publicação e filtra não-admissíveis depois; duas imagens indisponíveis podem consumir a janela e ocultar um texto pronto logo adiante. **Risco:** feed aparenta acabar contra PD-9/INV-17. **Owner FeedSession:** percorrer história local progressivamente até preencher a capacidade com cartas prontas ou provar fim real, mantendo ordem/identidade. **Prova:** fixture [hero sem pixels, hero sem pixels, texto pronto], capacidade 2, sem rede.

**P1 — checkpoint restaurado pode mudar de âncora (FATO ESTÁTICO; salto real não medido).** [`FeedSession.swift:480–512`](https://github.com/wsmontes/feedmine_v2/blob/8fcfe37c/Sources/FeedMineRuntime/FeedSession.swift#L480-L512) substitui a âncora publicada por outra carta pronta quando a original não pode ser projetada. **Risco:** reabertura offline não retorna ao mesmo ponto. **Owner FeedSession/checkpoint:** preservar identidade durável da posição, sem placeholder que viole render-ready; testar relaunch offline com imagem local ausente e comparar `PublicationCardID` + offset.

**P1 — carta admitida desaparece na reentrada (FATO ESTÁTICO; deslocamento visual é HIPÓTESE).** [`FeedSession.swift:197–222`](https://github.com/wsmontes/feedmine_v2/blob/8fcfe37c/Sources/FeedMineRuntime/FeedSession.swift#L197-L222) remove da lista um item já admitido se a redecodificação falha. **Risco:** geometria acima do leitor muda. **Owner FeedSession/apresentação:** separar residência de pixels da identidade admitida sem reescrever contrato; medir `PublicationCardID` e offset relativo durante ida/volta com asset ausente.

**P1 — escrita de disponibilidade pode falhar silenciosamente (FATO ESTÁTICO; falha de disco não reproduzida).** [`SavedMediaCoordinator.swift:65–94`](https://github.com/wsmontes/feedmine_v2/blob/8fcfe37c/Sources/FeedMineComposition/SavedMediaCoordinator.swift#L65-L94) usa `try? availability.record(...)` e retorna `.ready` ou outro estado sem confirmar a escrita. **Risco:** UI promete durabilidade que o disco não registrou. **Owner SavedMediaCoordinator:** tornar a confirmação dependente de persistência efetiva; injetar erro SQLite, relaunch offline e preservar bookmark mesmo em falha.

**P1 — fix físico de scroll ausente (FATO DE GENEALOGIA).** [`10bc0bd7`](https://github.com/wsmontes/feedmine_v2/commit/10bc0bd72cfdfcdb2cfe89e2eed7b4a520183f27) não é ancestral de `integration/51`, conforme [registro de pausa §1/6](https://github.com/wsmontes/feedmine_v2/blob/docs/status-pause-2026-10-17/docs/reviews/2026-10-17-estado-em-pausa.md). **Owner integração:** reconciliar fix e medir de novo no SHA final; não atribuir resultado da branch à 51.

**P2 — limite absoluto de itens tem exceção (FATO ARITMÉTICO).** [`FeedSession.swift:263–297`](https://github.com/wsmontes/feedmine_v2/blob/8fcfe37c/Sources/FeedMineRuntime/FeedSession.swift#L263-L297): com âncora inicial e `forwardCapacity=3000`, o teto de 2000 pode conservar 3001 itens. **Owner FeedSession:** validar limites de instalação ou tornar o cap consistente preservando âncora; teste de capacidade extrema.

**P2 — instrução de TestFlight ambígua (FATO DOCUMENTAL).** [Diretriz 11/out](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md) autoriza builds internas para feedback antes de B06; [pausa §5–9](https://github.com/wsmontes/feedmine_v2/blob/docs/status-pause-2026-10-17/docs/reviews/2026-10-17-estado-em-pausa.md) exige B06 para envio da 51. **Owner release/PO:** distinguir regra específica da 51 de regra geral; pausa atual não é autorização para envio.

### Pendências preservadas e pontos resolvidos

**Resolvidos somente na 51:** conversão automática hero→texto, reset de amostras ao reativar mesmo escopo, confirmação durável dos filtros; salvos implementados com ressalva. **Abertos:** quatro P1 acima, fix de scroll fora da candidata, busca `-termo` literal, `.neutral` convertido em exclusão na main, SQLite síncrono no MainActor, portabilidade completa V1→V2 e evidência de PD-10/catalog sync e B01–B06 na árvore final. Não tratar blueprints históricos como autoridade atual. Nenhuma prova de execução foi produzida por este monitor.

### Comandos e provas mínimas no Mac

```bash
git fetch origin main integration/51 fix/deferral-invalidates-list monitor/architecture
git rev-parse origin/main origin/integration/51
git merge-base --is-ancestor 10bc0bd72cfdfcdb2cfe89e2eed7b4a520183f27 origin/integration/51; echo "scroll_fix_ancestry=$?"
swift build && swift test && git diff --check
swift test --filter 'FeedPresentationAdmissionTests|FeedSessionWarmRestoreTests|SavedMediaCoordinatorTests|RunwayControllerTests|ForegroundDriveCadenceTests'
# Na árvore candidata final, executar scripts/run-discovery-benchmark.sh para B01–B05,
# B06 em iPhone físico com o mesmo SHA, sem tocar em bench/ nem em hashes congelados.
```

Provas de experiência adicionais: consumo prolongado sem fim falso; offset por identidade sob gesto e mídia ausente; filtros A→B→A; relaunch offline no mesmo checkpoint; salvos após falha de SQLite/disco cheio; aquisição inicial com rede real e atribuição de latências por estágio. A publicação deste documento não certifica nenhuma dessas provas.

### Memória compacta de revisões

- **003 (17/out):** main `5e4e2142`; P0 hero→texto identificado em branch antiga; auditorias de backend/scroll anexadas no canal consultivo.
- **004 (17/out):** `da94d5c7` e `d942b75e` corrigem P0; riscos de starvation/âncora/reentrada encontrados.
- **005 (17/out):** candidata `integration/51@8fcfe37c`, 23 commits sobre main; fix de scroll fora; B06 não executado.
- **006 (17/out):** refs e pendências inalteradas; sem novos gates.
- **007 (18/out):** divergência documental de TestFlight; refs e P1 inalterados.
- **008 (19/out):** refs/PRs/normas reconferidos; sem commits ou evidências novos após 007; consolidação do handoff remoto anteriormente bloqueado.

**Para o OMP:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. Confirmar leitura na coordenação própria; o monitor não altera `main`, código, testes, scripts, benchmarks, issues nem PRs.
