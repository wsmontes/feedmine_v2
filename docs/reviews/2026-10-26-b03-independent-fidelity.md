# B03 — fidelidade independente do instrumento, depois da corrida (2026-10-26)

Revisão do **instrumento** de B03, não do produto. Base: `/tmp/feedmine-b03-independent-review.md`
(observação parcial durante a corrida) confrontada com a **corrida encerrada**
`bench/run/20261026T143646Z`, remedida no container que o próprio `run.sh` puxa (não no container vivo
do simulador) e com o veredito congelado ao lado. Nada foi editado: nem `bench/`, nem driver, nem
critério, nem hash, nem produto. Nenhum número de produto é afirmado aqui.

## 0. Identidade e veredito, sem reinterpretação

| Item | Valor |
|---|---|
| run | `bench/run/20261026T143646Z`, `--gate B03 --full-trace`, perfil A |
| commit | `c9942340` (árvore suja em 1 arquivo não rastreado, `capacity-ready.json`, **não lido nem alterado**) |
| veredito congelado | **B03 = FAIL** — 1 parada visível ≥1 s; as outras quatro cláusulas PASS |
| selo | `run.sh` `b027007d…160b80`, `oracle.py` `57804e0b…ce8b7`, driver `c3ae03a4…eaac7e`, `shasum -c` do `EVALUATOR.sha256` = 6/6 |
| entradas do oráculo | `container/…/runtime.sqlite` (11.583.488 B) + `trace.jsonl` (8.632.216 B, 35.640 eventos, 0 ilegíveis) |
| execução | XCUITest `TEST EXECUTE SUCCEEDED`; jornada de 30 min percorrida |

O FAIL **fica**. Esta revisão não reclassifica a corrida, não propõe novo limiar em vigor e não
sugere repetir até passar.

## 1. Fatos remedidos no container puxado (números finais, não amostra)

Os números do relatório independente eram snapshot aos ~21 min (≈07:59Z). Remedidos no fim:

| Medida | Snapshot (21 min) | Final (container) |
|---|---|---|
| eventos `advance` | 2.390 | **3.465** (1,889/s em 1.833,83 s) |
| `advance` repetindo a âncora anterior | 814 (34,1 %) | **1.187 de 3.464 (34,3 %)** |
| `advance` com `activity=stationary` | 457 (19,1 %) | **663 (19,1 %)**; forward 2.784, backward 15, explicitTailApproach 3 |
| âncoras distintas | 1.557 | **2.257**; transições distintas 2.277; inflação 3.465/2.277 = **1,522×** |
| `admitted` | 6.415+ | **9.033** |
| candidatos / prontidão | — | 2.531, **0 pendentes, 2.531 `textOnly`** |
| gestos `Swipe up` | 472 | **679** (log: t=24,65 s → 1.844,85 s; 0,373 gestos/s; intervalo mediano 2,66 s, p10 2,62 s, p90 2,83 s, 8 intervalos <2 s, nenhum <1 s, máximo 12,47 s) |
| `advance` por gesto | 5,2 | **5,10** |
| eventos de parada (regra congelada) | 1 | **1** |

Amostragem de `advance` duplicado, confrontada: **34,3 %** dos eventos repetem a âncora do evento
anterior e **19,1 %** são `stationary` — por definição sem troca de carta. A distribuição por âncora é
1× (1.600), 2× (129), 3× (526), 10× (1), 19× (1). O contador que o oráculo consome está inflado em
**1,52×** em relação a passos distintos. Aritmética direta do limiar: 1.800 eventos ÷ 1,52 ≈ **1.183
cartas distintas**, contra as **2.000–2.040 cartas distintas** que `bench/corpus/criteria.json:trace`
congela. Nesta corrida as âncoras distintas (2.257) ficam acima dessa faixa, mas isso **não
conserta o critério** e **não** significa "corpus satisfeito": a faixa 2.000–2.040 codifica a **forma**
(1.800 de base + 200–240 de rajadas), e a corrida entregou fluxo liso — 1,889 `advance`/s e 1,231
âncoras distintas/s, máx 28 `advance` por 10 s, zero bins ≥30. O total só passou de 1/s por **excesso
uniforme**, não por 1/s + rajadas. Além disso, a cláusula conta eventos, âncoras distintas contam
revisitas uma única vez e não medem ordem nem salto (ver §3), e não existe cláusula de duração em
`gate_b03` (`bench/oracle.py:334-385` não usa os `at` para exigir 1.800 s).

Ausência de rajadas, confrontada: bins de 10 s de `advance` no traço inteiro (183 bins) → mínimo 3,
**mediana 20**, máximo **28**, **zero bins ≥30**; nas marcas de 5 min (280/580/880/1.180/1.480/1.780 s)
os `advance` são 18/17/21/21/18/21 e as admissões 51/48/56/55/50/43 — planos, sem degrau. O contrato
pede 3 cartas/s por 20 s a cada 300 s; isso exigiria um degrau visível. O driver
(`DiscoveryBenchmarkTests.swift:1126-1140`) implementa a rajada como **3 `swipeUp()` consecutivos e
bloqueantes**, e cada gesto custa ~2,66 s: a rajada sai a ~0,38 gestos/s, ~1/8 do nominal. Nenhum
comando foi alterado para "melhorar" isso.

O único autocheque do driver é `XCTAssertGreaterThan(lastBurstEnd, started)` (`:1145`), e ele **não
pode detectar** a ausência de rajada: `burstStarted` é fixado na **primeira** iteração (em `t≈0`,
`elapsed < 20` ⇒ `inBurst` verdadeiro, `:1128-1132`) e `lastBurstEnd = began` assim que o laço sai da
primeira janela (`:1133-1136`), em ~20 s de parede. A asserção passa, portanto, a partir dessa primeira
transição, sem exigir nenhum gesto efetivo a 3/s — ela só prova "o laço rodou até atravessar uma
fronteira de rajada". O mecanismo medido (3 swipes bloqueantes, máximo 28 `advance`/10 s) é
indistinguível da linha de base, e é por isso que o assert não o vê.

## 2. A parada: o que o traço mostra e o que ele não mostra

O único evento que cruza o limiar, verificado nas linhas do `trace.jsonl` do container (t relativo ao
`advance`; valores absolutos ≈1793025560,9):

| t | evento | campos relevantes |
|---|---|---|
| +0,775 s | `reserve_depth` | `ready=4`, `preparing=0`, `pending=0`, `exhausted=0`, `published=655` |
| +0,896 s | `admitted` / `runway_completed` | `order=109`, `cards=63`, `anchor=2654C80F-…`; `admitted_cards=63` |
| +0,904 s | **`advance`** | `activity=forward`, `anchor=910BAD0D-5C38-40F1-BE61-6C5078C1A313` |
| +1,140 s | `replenishment_requested` | `lane=head_reconsideration`, `kind=local` |
| +1,185 s | `replenishment_arrived` | `result=window`, `candidates=128`, `exhausted=false` |
| +1,328 s | `reserve_depth` | `ready=4`, `preparing=0`, `pending=0`, `exhausted=0` |
| +1,967 s | `admitted` | `order=110`, `cards=63`, `anchor=910BAD0D-…` (a mesma âncora do `advance`) |

No laço inteiro: 3.465 avanços, **3.465 com admissão posterior** (nenhum órfão); espera mediana
**0,0077 s**, segunda pior **0,3395 s**, pior **1,0635 s**. `reserve_depth` tem 473 amostras dentro do
alcance dos avanços, **0** com `exhausted != 0` e 0 com `pending != 0`; `ready` entre 0 e 96, com **94
amostras em `ready=0` — e nessas 94 o `preparing` também é 0** (não "sempre com `preparing > 0`",
como dizia a nota de transporte; corrigido lá).

**Os contadores do `reserve_depth` não são auto-consistentes, e isso é limite do campo.** Nas 94
amostras com `ready=0`, além de `preparing=0`, também `pending=0` e `exhausted=0` (93 delas com
`outstanding=0` e `deferred=0`; uma com 96 em ambos). Ou seja: reserva vazia, nada preparando, nada
pendente, nada em voo — e o app **não** se declara esgotado. As 94 amostras aparecem de +3,4 s a
+1.689,9 s do primeiro avanço e não produziram nenhuma parada de ≥1 s além da única contabilizada.
Consequência de leitura, sem reinterpretar o veredito: **nem `exhausted=0` nem `ready=4` sustentam
"oferta sadia"**. O que os campos dão é o que dizem literalmente (contadores da reserva naquele
instante); a coerência entre eles e o estado real da oferta não está estabelecida, e portanto eles não
servem como prova de saúde nem de escassez.

O que está **medido** aqui: o app **registrou** oferta no lado do suprimento (`ready=4`, reabastecimento
pedido e concluído antes da admissão) e a admissão seguinte chegou 1,063 s depois do avanço — 63 ms
acima do limiar, com admissões correndo a ~4,9/s no traço. Com a ressalva acima, isso é registro de
oferta, não atestado de saúde do suprimento.

O que **não** está medido, e por isso não é afirmado:

- **Nada aqui prova bitmap, layout ou renderização.** `ready` é um contador da reserva; `order`,
  `anchor`, `cards` são campos de escrituração. Não há captura de frame no instante da parada — o único
  artefato visual é `b03-end-of-trace_0_….png` (400.729 B), tirado no **fim** do laço
  (`DiscoveryBenchmarkTests.swift:1141-1144`).
- **Não é possível afirmar "o próximo card estava alcançável" a partir de ordinal ou reserva.** Nem
  `order` nem `anchor` sustentam correspondência carta-a-carta: 9.033 admissões distribuem-se em
  `order` 1..4.524 e a **mesma** âncora aparece com vários ordinais (`45217818-…` → 4, 5, 8, 10, 12,
  `C80FDF2C-…` → 6, 7, 9, 11, 13, 15); há 2.245 âncoras admitidas para 2.531 candidatos e 2.257
  âncoras de `advance` (2.244 delas também em `admitted`). Corolário de método: a medição que fiz de
  deltas de `order` entre passos distintos (mediana **+2**, 2.224 de 2.252 transições) **não** pode ser
  lida como "pula uma carta" nem como "cartas consecutivas". Essa uniformidade quase perfeita (só 28
  exceções em 2.252) é **assinatura de campo definicional** — `order` é atribuído por evento de
  admissão, ~2 por transição —, não comportamento observado: se fosse salto real de cartas, a
  distribuição seria dispersa. O achado fica **não resolvido**, e o motivo é de instrumento: o
  `advance` **não carrega ordinal**, então contiguidade/reachability carta-a-carta **não é medível com
  este trace**. O que o instrumento sustenta é apenas: houve **um** intervalo de 1,063 s entre um
  avanço e a admissão seguinte, e nada além disso.

Consequência para o texto de transporte: a frase que respondia "sim" à pergunta "havia próximo card
pronto e alcançável?" foi corrigida — a evidência mostra oferta e admissão, não um card pronto e
renderizado no viewport.

Reprodutibilidade, medida: a timeline por-evento citada na nota de transporte (`runway_completed` em
+0,896 s, `reserve_depth ready=4` em +0,775 s e +1,328 s, `replenishment_requested`/`arrived` em
+1,140/+1,185 s, `admitted order=110` em +1,967 s) foi **reproduzida linha a linha** no
`trace.jsonl` do container puxado — nenhuma daquelas citações ficou sem reprodução. Nota de método para
quem repetir a consulta: os `at` do traço são epoch absoluto (≈1.793.025.560), e um filtro por janela
relativa (ex.: 5560–5562) devolve **vazio** — resultado vazio ali é erro de filtro, não ausência de
evento (`runway_completed` = 3.445 e `replenishment_arrived` = 956 no arquivo inteiro).

## 3. O que este instrumento mede e o que ele deixa de fora

| Camada | Definição no código | Medido no fim | Prova que dá |
|---|---|---|---|
| gesto | `swipeUp()` sintetizado pelo XCTest | 679 | que o replayer emitiu gestos, a 0,373/s |
| `advance` | evento escrito a cada submissão de viewport que não é reconciliação de posição (`AppComposition.swift:4420-4427`) | 3.465, dos quais 34,3 % repetem âncora e 19,1 % `stationary` | que a viewport foi submetida |
| passo distinto | mudança de `anchor` entre `advance` consecutivos | 2.277 | que a âncora mudou |
| carta distinta | não implementado como identidade estável | 2.257 âncoras únicas | nada além de unicidade de UUID |
| carta renderizada | não medido | — | — |

O contrato (`docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md` §3, B03) exige replay de avanços
**efetivos** e diz que "o total de cards efetivamente consumidos deve corresponder ao trace, **não a um
contador de gestos disparados**". O instrumento congelado:
`oracle.py:348-362` conta `event == "advance"` com limiar 1.800, sem exigir âncora nova, sem exigir
duração, sem exigir correspondência com `expected_advances_min/max` do corpus. A contradição fica
registrada sem ser resolvida: um produto que avançasse exatamente **1 carta por gesto** entregaria
~679 passos em 30 min e leria FAIL na cláusula de contagem. O PASS de contagem desta corrida só existe
porque cada gesto atravessa ~5 eventos / ~3 âncoras — exatamente o que a cláusula textual exclui como
prova.

## 4. Risco `mv` falho + `rm -rf derived` (registrado, não alterado)

Cadeia, com linhas do selo vigente: `bench/run.sh:427` resolve o bundle por
`ls -dt "$OUT/derived/Logs/Test/"*.xcresult | head -1`; `:435-449` exporta anexos e extrai `phases`;
`:462-463` move o bundle para `$OUT/<gate>-<profile>.xcresult` **sem verificar o destino**;
`:625` apaga `rm -rf "$OUT/derived"` incondicionalmente (o comentário em `:619-624` afirma que a linha
"cannot take the runner's own account of the run with it" — verdadeiro só no caminho de sucesso).

| Modo de falha | `.phases` | `.attachments/` | `.xcresult` | Visível no `report.md` |
|---|---|---|---|---|
| sem bundle (runner morreu antes) | não | não | não | sim |
| export de anexos falha | não | vazio/ausente | sim | sim |
| export ok, sem anexo `phases` | não | sim | sim | sim |
| export ok, **`mv` falha** | sim | sim | **não** (vai com `derived`) | sim (mensagem `tee`ada em `transport.log`) |
| destino já é diretório | sim | sim | **aninhado** em `<gate>-<profile>.xcresult/<bundle>.xcresult` | silencioso |

Nesta corrida o caminho bom ocorreu: `B03-A.xcresult/` presente (8,2 MB), `B03-A.attachments/` com 2
anexos (`phases_0_….txt` 198 B + `b03-end-of-trace_0_….png`), `B03-A.transport.log` com
`phases: 6 lines,198 bytes`, e `B03-A.phases` não vazio — 6 linhas (`neutral`, `answered:` ×2,
`thematic-attempted`, `hide-stable:true`, `hide-frames:252->252`). As entradas das cláusulas **não**
dependem do bundle: o oráculo lê banco e `trace.jsonl` puxados do container (`run.sh:527-570`). O risco
é perder o relato cru do runner, não o veredito.

Correção nomeada e **não aplicada** (mudaria o selo depois do veredito, e o selo tem de ser o
instrumento que produziu o resultado): (1) verificar o destino após o `mv` e `cp -R` quando ele falhar;
(2) condicionar o `rm -rf "$OUT/derived"` à existência do bundle de cada portão/perfil; (3) recusar
aninhamento (remover o destino antes, ou nome com carimbo); (4) escrever caminho do bundle e status do
transporte no `report.md`. Congelamento do resolvedor de bundle por `-resultBundlePath` segue pendente
(registrado na nota de transporte).

## 5. Critérios: nada enfraquecido, nada reclassificado

- Não foram tocados: `bench/oracle.py`, `bench/corpus/criteria.json`, `bench/corpus/**`, `bench/serve.py`,
  `bench/run.sh`, driver, limiares, duração, gestos, semântica de cláusula, `bench/EVALUATOR.sha256`.
  Esta nota é documentação.
- **B03 = FAIL** continua sendo o veredito desta corrida, por regra mecânica única (1 parada).
- **Nenhum gate é declarado verde.** B03 é FAIL; a corrida B01 `20261026T143118Z` tem fases, anexos e
  `.xcresult` presentes, o que é evidência de transporte, não de aprovação global. O achado P2 da nota
  de transporte (B02 pode ler PASS sem `.phases`, por desenho do `gate_b02`) segue aberto e é
  pré-existente.
- Repetir a corrida para "ver se passa" não é proposta: a única parada está localizada, o mecanismo é
  aritmético (1,0635 s contra limiar de 1,0 s) e a resolução do proxy é de 1 s. Um rerun só muda a
  amostra, não o significado.
- Alterações de instrumento aqui discutidas (contar passos distintos, exigir duração, registrar a
  intenção do driver, alinhar 1.800 eventos com 2.000–2.040 cartas distintas, corrigir `mv`/`rm`
  acima) exigem **congelamento separado**: cópia verbatim em `bench/revisions/`, `EVALUATOR-pre-….sha256`,
  nota datada, e medição **causal** antes/depois (um caso que reprove pelo motivo novo, não só um run
  que passe). Vereditos anteriores deixam de ser comparáveis. Nenhuma delas está aplicada nesta árvore.

## 6. Limites

- A atribuição de `advance` a gesto é por janela entre gestos consecutivos (±1 gesto na fronteira).
- "Carta distinta" aqui é unicidade de `anchor`; se o app reancorar sem trocar de carta, a contagem
  superestima, e o inverso (pular cartas sem evento) não foi medido — e, com os campos atuais,
  **não é medível** (§2).
- Não medi frame/offset do scroll nem o instante do `Synthesize` no eixo do traço: a divisão
  ~0,44 s + ~2,15 s vem dos tempos do próprio log do XCTest.
- Toda a aritmética do §1 vem do `trace.jsonl` copiado em `bench/run/20261026T143646Z/container/`, não
  do container do simulador. O banco foi lido somente para identidade (2.531 cartas, 2.305 chaves de
  catálogo, 15.917 itens de corpus).
- Nenhum build, teste, `simctl` mutante ou comando de git foi executado por esta revisão; nenhum dado
  ou artefato em `/tmp` foi apagado.
