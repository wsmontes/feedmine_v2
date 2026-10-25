# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 033 · Vancouver, 25/10/2026, 07:41 PDT.** Parecer consultivo, não certificação. O OMP deve fazer fetch de `monitor/architecture` e ler este documento; não há notificação automática aos executores.

## Base, intervalo e autoridade

- **Memória anterior:** [revisão 032](https://github.com/wsmontes/feedmine_v2/commit/a5303254e394ecdc2dd5b1270346bae1bc5f327a), 25/out 05:41 PDT, blob `6f374dfe472535b213aca583b8ea01312912b573`. **Janela:** 25/out/2026, 05:41–07:41 PDT.
- **Linha técnica ativa:** `product/reserve-20261024`, **`38387ace6d3be886899b4dc57ead10b912ebfdcb → a88142820e49dde7225fdf60776187c2306ae044`**, um commit. [Diff exato](https://github.com/wsmontes/feedmine_v2/compare/38387ace...a8814282). Saldo: **somente `docs/reviews/2026-10-25-candidata-validacao.md` (+6/-2); nenhum arquivo de produção, teste ou benchmark alterado**. [Commit](https://github.com/wsmontes/feedmine_v2/commit/a88142820e49dde7225fdf60776187c2306ae044).
- **Refs conferidas e sem avanço:** `main@fb8e65ff5a5e83ae85c9061996aaa0ebf2b7ca48`; `product/integrity-20261024@031b27d3bfc0355c5fc3be72d03c57cde0f0f91f`; `codex/feedmine-next-internal@d6a052667abfd478d5e09f13afe0e01685ef9344`; `release/build-56@cede37f6e925dc19e54a2d67416abd9569559e01`. A tag da build 56 distribuída permanece `1fe0afaf` conforme memória anterior, não revalidada contra TestFlight nesta rodada. `integration/candidate` e `integration/chatgpt` são refs históricas/divergentes, não candidatas atuais sem prova adicional. PR [#5](https://github.com/wsmontes/feedmine_v2/pull/5) aberto, HEAD `5b252eaa858d444f61e4a4acfec1f389286683eb`, sem nova atividade desde 22/out.
- **Normas relidas na candidata atual:** [PRODUCT_NORTH_STAR](https://github.com/wsmontes/feedmine_v2/blob/a8814282/docs/product/PRODUCT_NORTH_STAR.md), [PRODUCT_DECISIONS_2026-10-09](https://github.com/wsmontes/feedmine_v2/blob/a8814282/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11](https://github.com/wsmontes/feedmine_v2/blob/a8814282/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [PRODUCT_INVARIANTS](https://github.com/wsmontes/feedmine_v2/blob/a8814282/docs/architecture/PRODUCT_INVARIANTS.md) e [DISCOVERY_ACCEPTANCE_BENCHMARK](https://github.com/wsmontes/feedmine_v2/blob/a8814282/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md). Norte: descoberta contínua e diversa, PD-4/5/8/9/10, INV-01/03/04/05/07/08/10/11/12/15/17/18, sem pipelines ou owners paralelos. Blueprints antigos não prevalecem.

## Resumo executivo — experimento negativo relevante, hipótese causal refinada

**P0 B03 segue FAIL.** O único commit novo documenta uma tentativa **temporária e revertida** de acordar o runway na publicação inicial via `noteLocalSupplyCommitted`. O executor relata que a primeira fatia permaneceu em **t=15,94 s** (antes **15,93 s**) e **seis paradas** permaneceram. **Classificação:** fato comprovado **no diff**: a documentação relata esse experimento; **evidência de execução apenas relatada**, sem patch experimental, trace bruto, artefato ou `.xcresult` anexado/inspecionado por este monitor. A árvore final **não contém** essa correção. [Documento: linhas 43–54](https://github.com/wsmontes/feedmine_v2/blob/a8814282/docs/reviews/2026-10-25-candidata-validacao.md#L43-L54).

**Revisão crítica da explicação:** a documentação conclui que o vão é a “cadência de observação após a primeira apresentação”. Isso é **mais específico do que as evidências disponíveis autorizam**. O código demonstra que `reconsider` não trabalha sem `latestObservation`, mas **o próprio driver sintetiza uma observação `.stationary` em `activateCurrentPresentation`**; não depende necessariamente de uma medição geométrica da UI. A ativação só ocorre **depois de `await cold.run(...)` retornar**. Assim, o atraso pode decorrer da sequência **publicação antecipada → conclusão do cold bootstrap → ativação do driver/observação sintética**, não apenas da frequência das observações visuais. Sem timestamps de `cold.run` e `activateCurrentPresentation`, **não atribuir causa fechada ao capture/scroll**.

**Consequência de produto:** os primeiros cards podem estar na tela e serem consumidos enquanto o único runway ainda não tem fatos/ativação para produzir a próxima fatia. Ajustar limite 16/32/48, piso 32/64 ou emitir um aviso isolado não corrigiu o episódio relatado. Não introduzir timers, filas ou segundo produtor. **Nenhuma mudança de produto foi feita nesta janela.**

## Mudança verificada e julgamento

### Commit `a8814282` — documentação de experimento descartado

[Diff do commit](https://github.com/wsmontes/feedmine_v2/commit/a88142820e49dde7225fdf60776187c2306ae044): substitui a recomendação genérica de “acordar após bootstrap” por evidência de que o aviso isolado não bastou. **Fato comprovado:** só o relatório mudou; nenhum patch funcional ficou na branch. **Fato relatado pelo executor:** 15,94 s para a primeira fatia e seis stalls após a tentativa; revertida. **Hipótese ainda aberta:** a ausência de `latestObservation` no momento do aviso explica o resultado da tentativa, mas não prova que a UI demorou a observar o viewport nem que a ativação anterior ao fim de `cold.run` seja segura.

**Ponto de precisão adicional:** `RunwayController.reconsider` exige `scope` e `latestObservation` em [RunwayController.swift:372–379](https://github.com/wsmontes/feedmine_v2/blob/a8814282/Sources/FeedMineRuntime/RunwayController.swift#L372-L379); `RunwayController.submitObservation` instala a observação em [343–352](https://github.com/wsmontes/feedmine_v2/blob/a8814282/Sources/FeedMineRuntime/RunwayController.swift#L343-L352). `FeedRunwayDriver.activateCurrentPresentation` ativa o scope e **envia `.stationary` sem gesto da UI** em [353–363](https://github.com/wsmontes/feedmine_v2/blob/a8814282/Sources/FeedMineComposition/FeedRunwayDriver.swift#L353-L363). Já o host só chama essa ativação após `cold.run` em [AppComposition.swift:3813–3844](https://github.com/wsmontes/feedmine_v2/blob/a8814282/FeedMineApp/FeedMineApp/AppComposition.swift#L3813-L3844), enquanto a publicação antecipada é instalada em [4160–4207](https://github.com/wsmontes/feedmine_v2/blob/a8814282/FeedMineApp/FeedMineApp/AppComposition.swift#L4160-L4207). **Isso é confirmado estaticamente; a duração causal de cada etapa não está medida aqui.**

## Achados priorizados: evidência, regressão, orientação mínima

### P0-01 — Continuidade: janela publicada sem runway pronto (aberto, hipótese causal estreitada)

**Evidência relatada:** bootstrap publica 12 cartas em t=10,04 s, admite em t=10,23 s, primeira fatia em t=15,93/15,94 s; intervalo de **5,70 s** entre admissão e primeira fatia. Seis paradas numa rajada de 3 cards/s, sem publicação/instalação no intervalo; fatias usuais ≤340 ms. [Relatório: linhas 24–54](https://github.com/wsmontes/feedmine_v2/blob/a8814282/docs/reviews/2026-10-25-candidata-validacao.md#L24-L54). **Prova estática:** publicação antecipada ocorre antes do fim de `cold.run`, e ativação cria a observação sintética apenas depois; ver referências acima. **Não comprovado:** que a UI é a origem da demora, que o aviso testado tinha scope válido, que não houve outro callback ou que toda pausa vem desse mesmo intervalo.

**Risco de regressão da correção:** antecipar `activateCurrentPresentation` enquanto `cold.run` ainda executa aquisição/preparação pode criar **duas oportunidades concorrentes** para o mesmo supply/Edition, violar ownership (INV-12), duplicar contato com fontes ou instalar recibos fora de ordem. **Owner mínimo:** antes de editar, instrumentar cinco marcos monotônicos na **mesma Edition**: `cold.published`, `cold.run returned`, `driver.activate entered`, `runway.submitObservation(.stationary)`, `first runLocalSlice`; acrescentar `viewport first captured/forwarded` para distinguir a hipótese UI. Depois, coordenar a transição pelo **driver/runway existente**, com uma única autorização e fence de scope; não criar um wake/scheduler paralelo. Reexecutar B03+B04+B05 na mesma árvore, com volta ao navegador e abertura offline.

### P0-02 — Segurança de redirecionamento na descoberta (herdado, não corrigido)

[FeedDiscoveryTransport.swift:69–101](https://github.com/wsmontes/feedmine_v2/blob/a8814282/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L69-L101): `URLSession.bytes(for:)` pode seguir redirect **antes** da verificação do host final. **Fato estático:** validação do destino final é tardia; **não** foi demonstrado tráfego real a um host proibido. **Owner:** recusar cada redirect antes da conexão (delegate/política por hop) e comprovar zero requisições ao destino privado em teste discriminante. Sem mudança nesta janela.

### P1-01 — Reserva cheia e liveness PD-4 (herdado, contraexemplo estático)

[PreparedReserve.swift:188–258](https://github.com/wsmontes/feedmine_v2/blob/a8814282/Sources/FeedMineRuntime/PreparedReserve.swift#L188-L258): limite de preparação `targetDepth + 16` não prova progresso se o estoque extra também for incompatível com a última fonte publicada. **Hipótese de starvation**, não ocorrência reproduzida. Provar 112+1 com última fonte adversarial e uma alternativa posterior, preservando PD-4; não resolver publicando fontes adjacentes iguais.

### P1-02 — Falha temporária de mídia e concorrência (herdado)

[PreparedReserve.swift:333–343](https://github.com/wsmontes/feedmine_v2/blob/a8814282/Sources/FeedMineRuntime/PreparedReserve.swift#L333-L343): três falhas podem marcar `exhausted` apesar de INV-17/PD-9 exigirem recuperabilidade de transitórios. [239–303](https://github.com/wsmontes/feedmine_v2/blob/a8814282/Sources/FeedMineRuntime/PreparedReserve.swift#L239-L303): janelas concorrentes ainda sem prova discriminante de conclusão invertida. **Fato estático do estado/limite, impacto ainda hipotético**. Provar 3×5xx → recuperação, e duas conclusões invertidas sobre a mesma revisão; reaproveitar o owner de mídia.

### P1-03 — Filtros, scroll, offline, biblioteca e catálogo (herdados)

A confirmação NF-03 do botão Concluído e a retenção de adiamentos A→B→A têm **correções estáticas reconhecidas**, mas presets salvos e confirmações concorrentes seguem sem prova integrada. Identidade/posição ao rolar, reabertura offline, salvos/coleções/fontes, migração V1→V2 e reconciliação não bloqueante do catálogo público (PD-10/INV-18) exigem jornada real numa mesma árvore. **Não declarar resolvido por B05 de corpus limitado**. O retorno do Safari que a revisão 031 tratara como regressão foi reclassificado na 032 como **falha do gesto do teste**; duas execuções verdes são apenas relatadas.

### P1-04 — Diversidade e vídeo no catálogo amplo (herdados)

Medição relatada: 1.159 publicações/180 s, 488 com imagem, 335,4 MB de mídia, nenhum vídeo publicado na janela de catálogo amplo; 2 vídeos em feed isolado. Não inferir boa descoberta a partir do número bruto de cartas. [Relatório: linhas 55–99](https://github.com/wsmontes/feedmine_v2/blob/a8814282/docs/reviews/2026-10-25-candidata-validacao.md#L55-L99). Avaliar variedade do **supply preparado** antes de mexer no shuffle. **Hipótese de impacto de produto**, não nova regressão.

### P2 — Telemetria e robustez do instrumento (herdados)

`coverage=healthy` durante uma fatia não é contradição automática: [RunwayController.swift:392–395](https://github.com/wsmontes/feedmine_v2/blob/a8814282/Sources/FeedMineRuntime/RunwayController.swift#L392-L395) permite uma oportunidade por supply novo mesmo quando a política responde `.hold`. Separar `freshSupplyOpportunity` de déficit no trace antes de atribuir o excesso de publicação a uma política defeituosa. O fechamento do Safari por coordenada corrigiu o falso negativo relatado, mas deve provar que o modal efetivamente desapareceu antes de aceitar a asserção de âncora. Sem mudança nesta janela.

## Release e provas no Mac

**Matriz do executor, na base indicada `ca532f25` (não transferível automaticamente a qualquer binário):** B01 PASS relatado; B02 PASS relatado; **B03 FAIL relatado**; B04 PASS relatado; B05 PASS relatado; **B06 NOT_RUN**, aparelho físico bloqueado. A tentativa de wake não mudou o B03 e foi revertida; o SHA atual `a8814282` modifica somente docs. Nenhum `swift build`, `swift test`, XCTest, simulador, iPhone ou benchmark foi executado **por este monitor**. Status combinados do HEAD sem checks; isso não prova aprovação ou reprovação. Build 57 **não certificada**; build 56 distribuída é outra árvore.

**Comandos sugeridos para o Mac — NÃO executados nesta revisão:**

```bash
git fetch origin main monitor/architecture product/reserve-20261024 product/integrity-20261024 release/build-56 --tags
git rev-parse origin/main origin/product/reserve-20261024 origin/product/integrity-20261024 origin/release/build-56
git log --oneline 38387ace..origin/product/reserve-20261024
git diff --check 38387ace..origin/product/reserve-20261024
git diff --stat 38387ace..origin/product/reserve-20261024
git worktree add --detach /tmp/feedmine-monitor-033 a88142820e49dde7225fdf60776187c2306ae044
cd /tmp/feedmine-monitor-033
(cd bench && shasum -a 256 -c MANIFEST.sha256)
swift build && swift test
bash bench/run.sh --gate B03 --full-trace
bash bench/run.sh --gate B04 --profile A --profile B
bash bench/run.sh --gate B05 --profile A --profile B
```

**Prova discriminante solicitada ao owner:** preservar corpus/hash, relógio monotônico, IDs de Edition e operação, trace bruto e xcresult; imprimir em uma linha temporal `cold.published`, `cold.run returned`, `activate.enter`, `observation.submitted` (sintética versus viewport real), `runway.requested`, `publicationConcluded`, `admitted`, `advance`. Se a primeira observação sintética coincidir com t≈15,9 s, o atraso é **anterior ao driver**, não falta de callback de geometria. Se existir em t≈10,2 s, investigar o que retardou a primeira decisão apesar da observação. Repetir B03/B04 no mesmo SHA da correção, e depois B05/offline e B06 em aparelho físico. Não alterar a régua congelada.

**Ordem concreta:** (1) medir a fronteira `cold.run`→ativação e provar causalidade; (2) fazer a menor coordenação possível no owner existente; (3) B03/B04/B05 + navegador/offline na mesma candidata; (4) corrigir redirect P0 e contraexemplos da reserva; (5) validar PD-10, diversidade, mídia e B06 antes de release. Não substituir isso por tuning de constantes.

## Memória compacta e histórico de SHAs

- **Monitor remoto:** 025 `309c1d20` → 026 `859c34ce` → 027 `c6aee149` → 028 `6885ed5d` → 029 `5efa2afb` → 030 `31d01b64` → 031 `8f608791` → 032 `a5303254` → **033 presente**.
- **SHAs técnicos:** main `fb8e65ff`; integrity `031b27d3`; next `d6a05266`; release/build-56 `cede37f6`; tag build 56 `1fe0afaf` (histórico); reserve `7a5d555d → 38387ace → a8814282`; PR #5 `5b252eaa`. Intervalo novo: **somente `38387ace..a8814282`**.
- **Novo nesta revisão:** tentativa de wake relatada **sem efeito** (15,94 s; 6 stalls), revertida; nenhuma correção de produto. Reclassificação crítica: a hipótese “somente cadência da observação visual” **não está provada**, pois o driver gera observação sintética quando ativado, depois de `cold.run`.
- **Resolvidos anteriormente:** falso bloqueador de retorno Safari = gesto do instrumento; correções estáticas de adiamentos A→B→A, publicação editorial retida e confirmação NF-03 parcial. **Não** equivale a certificação de release.
- **Abertos:** **P0 B03 bootstrap/runway e redirect**; **P1 liveness da reserva, mídia transitória, concorrência, diversidade, filtros/presets, posição/offline, salvos/coleções/fontes, PD-10, B06**; **P2 telemetria e robustez de gesto**. B03 FAIL; B06 NOT_RUN; demais PASS apenas relatados em base indicada. Sem PASS independente.

Este monitor só pode alterar este arquivo na branch `monitor/architecture`; nenhuma outra árvore, issue ou PR é modificada. O OMP precisa fazer fetch e ler este documento.
