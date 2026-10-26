# B03 — calibração de cadência do instrumento (2026-10-26)

Nota de **instrumento**, não de produto. Nenhum veredito de gate é produzido, alterado ou reclassificado
aqui. A corrida `bench/run/20261026T143646Z` continua **B03 = FAIL** (1 parada ≥1 s), e a régua congelada
— `bench/**`, `bench/oracle.py`, `bench/corpus/**`, driver `DiscoveryBenchmarkTests.swift`,
`bench/EVALUATOR.sha256` — ficou **byte a byte** intocada. Nenhum código de produção foi tocado.
`capacity-ready.json` não foi lido nem alterado.

## 1. Pergunta e hipótese

**Pergunta.** O contrato (§3, B03) exige *replay de 30 min de avanços efetivos, 1 carta/s, com rajadas de
até 3 cartas/s por 20 s a cada 300 s, usando gestos/scroll nativos*, e diz que o total consumido deve
corresponder ao trace, **não a um contador de gestos disparados**. O driver congelado não consegue
expressar nenhuma das duas taxas: mediu-se 679 gestos em 1 844 s = **0,373 gestos/s** (intervalo mediano
**2,66 s**), cada gesto valendo 5,10 eventos `advance`, dos quais 34,3 % repetem a âncora e 19,1 % são
`stationary` (inflação 1,52×).

**Hipótese H1.** O ciclo de 2,66 s não é piso da plataforma: é custo do **evento sintetizado pelo XCTest**
(injeção ≈0,44 s + espera de quiescência/deceleração ≈2,15 s, tempos do próprio log do XCTest). Se a
injeção sair do XCTest e entrar por eventos HID nativos no `Simulator.app`, a cadência de gestos passa a
ser o que o driver mandar.

**Hipótese H2 (dependente).** A quantidade de cartas por gesto é controlável por **velocidade de release**,
não por distância: um arrasto que termina sem velocidade não tem momentum e consome ~1 carta; um flick
veloz coasta por várias.

**Negativo exigido.** O mesmo injetor, com a cadência antiga (intervalo 2 660 ms, flick estilo XCTest), tem
de ser **reprovado** pelo detector — senão o detector mede nada.

## 2. Métricas

| Métrica | Definição |
|---|---|
| cadência de intenção | gestos agendados ÷ duração, do log do próprio injetor |
| cadência efetiva | âncoras **distintas em ordem de travessia** ÷ duração, dos `advance` do app |
| cartas por gesto | âncoras distintas ÷ gestos |
| repetição | eventos `advance` que repetem a âncora anterior (nunca contam consumo) |
| stationary | eventos com `activity=stationary` (nunca contam consumo) |
| rajada | taxa de âncoras distintas/s na janela de rajada, exigida ≥80 % do nominal |

"Distinta" = unicidade de âncora, a mesma proxy da revisão de fidelidade; âncora não é identidade estável
de carta (limite §6 daquele documento, mantido aqui).

## 3. Instrumento construído

`tools/b03-pacing/` — identidade própria, `SHA256SUMS` próprio, fora de `bench/`:

- **`inject.swift`** — posta eventos HID (`CGEvent`, `.cghidEventTap`) com carimbo explícito no
  `Simulator.app`: mouse-down, N `mouseDragged` interpolados em `drag-ms`, mouse-up. Um arrasto de mouse no
  Simulator **é** toque no device, então a interação atravessa a UI real e os reconhecedores reais. Não há
  XCTest no caminho, nem hook de avanço/publicação, nem escrita no banco. `AXIsProcessTrusted = true`
  (medido), que é o que permite o post.
- **`pacing_probe.py`** — julga **cadência apenas**. Cruza intenção (log do injetor) com efeito (`advance`
  do app), conta âncoras distintas e reprova repetição/stationary.

Geometria medida (não suposta): device `FeedMine Bench` = iPhone 17 Pro Max 440×956 pt; janela (931,113)
494×1054 pt; screenshot 988×2108 px = 2× pontos; tela do device na janela com origem ≈(962,197) e escala
≈0,975 pt de janela por pt de device; passo de carta ≈360 px ≈180 pt. Nada de `simctl erase/delete`;
nenhum bundle de produto instalado ou removido.

## 4. O que foi medido

### 4.1 A cadência de gestos é resolvida (H1 confirmada)

| perfil | gestos | duração | gestos/s |
|---|---|---|---|
| base (`--interval-ms 1000`) | 12 | 11,94 s | **1,005** |
| rajada (`--interval-ms 333`) | 18 | 6,27 s | **2,869** |
| antiga (`--interval-ms 2660`) | 5 | 11,22 s | **0,446** |

Os carimbos de envio são do injetor, não do app. **7,7× o driver congelado no mesmo device.** O ciclo de
2,66 s do XCTest não é limite da plataforma.

### 4.2 Os gestos chegam ao app como avanços reais

Namespace de teste (cópia de estado, ver §5), 6 gestos lentos de 180 pt: 5 âncoras distintas, todas
`activity: forward` — `D3F7090F`, `B17FED55`, `B330369A`, `F118239C`, `7626891D`. A interação atravessa a
UI real e produz consumo; isso está provado.

### 4.3 Três modos de falha medidos — e por que zero leitura não é "injecão quebrada"

**(a) Pausa antes do lift vira TAP.** Com `hold-ms 200` (a tentativa de zerar velocidade), o
reconhecedor de pan não valida; o release é interpretado como toque na carta, o iOS entrega a URL do corpus
ao Safari (`127.0.0.1`) e **todos os gestos seguintes são engolidos pelo Safari**. Medido: três perfis
consecutivos com cadência exata (1,005 e 2,869 gestos/s) e **zero** `advance`. Consequência de projeto:
zero-momentum **não existe** por dwell — a velocidade tem de ser baixa mas contínua até o release.

**(b) O rendimento por gesto não é controlado por distância.** Um único arrasto de 180 pt numa janela viva
e crescente produziu **47 eventos `advance` e 42 `cards_traversed`** (cartas 0→62). O contraste que fecha o
argumento: **o mesmo perfil** (180 pt, 300 ms) leu ~1 carta por gesto no bed *clampado* na cauda do B03. Ou
seja, a variável não é a distância — é a velocidade de release e o crescimento da janela. Nenhuma das duas
observações, isolada, estabelece controle de rendimento.

**(c) `advance` continua ≠ consumo.** No mesmo probe: `DB023E67…` aparece `forward` → `stationary` →
`forward`, e `672B4AB8…` duas vezes. Filtrar âncora distinta não é refinamento: é o que separa consumo de
re-submissão de viewport.

**(d) Feed na cauda consome zero em qualquer cadência.** Estado copiado da corrida B03: `cards: 2000`,
`runway_completed admitted_cards: 2000` repetido, último `advance` `stationary`. Nenhum gesto pode avançar
— a leitura zero desse bed é **esgotamento**, não falha do injetor. Foi o que invalidou o primeiro conjunto
de perfis.

### 4.4 Negativo contra o instrumento real: a corrida congelada, reprovada 17/17

O detector não foi validado contra um replay sintético, e sim contra o **próprio driver congelado**: os 679
carimbos `Swipe up` de `bench/run/20261026T143646Z/B03-A.log` (t=24,65 s → 1844,85 s), fatiados em 10
janelas-base de 10 s e 7 janelas de rajada de 20 s nas marcas de 300 s, julgados contra o `trace.jsonl`
daquela corrida (alinhamento: primeiro `advance` = primeiro swipe; spans 1 833,8 s vs 1 820,2 s conferem).

**As 17 janelas reprovam.** O achado que importa:

| janela | cartas distintas/s | gestos/s | cartas/gesto | por que reprova |
|---|---|---|---|---|
| base 100–1100 s | 1,1 – 1,5 | 0,3 – 0,4 | 2,0 – 4,2 | taxa de gesto e rendimento, não a taxa de cartas |
| rajada 300/600/900/1200/1500/1800 s | 0,35 – 1,45 | 0,35 – 0,45 | 1,4 – 4,1 | alvo de rajada é 3/s |

Seis das dez janelas-base caem **dentro** de uma banda ingênua de 1 carta/s na taxa de cartas, consumindo
2,75–4,0 cartas por gesto a um terço de gesto por segundo. É exatamente a inflação que o contrato exclui
("não um contador de gestos disparados") — e é por isso que `base_gesture_per_s` e `max_cards_per_gesture`
existem como cláusulas: sem elas o instrumento antigo leria como replay perfeito de 1/s. Um detector de
taxa de cartas sozinho teria aprovado a cadência antiga.

## 5. Bed de piloto (e o que ele não é)

Para não mutar evidência, o estado do app **nunca** foi alterado no lugar: copiei `runtime.sqlite` (+`-wal`,
`-shm`) de um namespace existente para um UUID novo e lancei o bundle de benchmark já instalado
(`com.feedmine.development.benchmark`) com `SIMCTL_CHILD_FEEDMINE_RUNTIME_NAMESPACE`. Os namespaces
originais (`6D600274…` = corrida B03, `6DE8A6EC…` = resíduo de `20261026T100032Z`) ficaram intactos; o
traço do B03 já estava preservado em `bench/run/20261026T143646Z/container/`.

O bed **não** é fiel ao ensaio: o transporte (`bench/serve.py`, `127.0.0.1:8757`) não estava no ar, então
admissões e janela variaram por conta própria. Isso é causa direta de (b) e (d) e é o primeiro item do
plano abaixo.

Disco: 1,2–1,3 GiB livres medidos no início e no fim. Nenhum build foi executado — o app instalado foi
reusado, então `DerivedData` (1,2 GB) e os `xcresult`/traces/backups existentes não foram tocados. Nenhum
`simctl erase/delete`, nenhum push/merge/deploy.

## 6. Veredito desta etapa

**H1 confirmada. H2 não demonstrada.** A taxa de injeção é resolvida e medida (1,005 e 2,869 gestos/s reais,
atravessando UI real). O **controle de cartas por gesto não está calibrado**: não existe ainda uma forma
medida de 1 carta/s nem de 3 cartas/s, e nada aqui foi rodado por 30 minutos. A única observação de ~1
carta/gesto veio de um feed *clampado* na cauda, onde o momentum era absorvido — não conta como controle de
rendimento. **Nenhum PASS é declarado** — nem com base em contador de eventos (inflado), nem em bitmap não
observado. O FAIL de `20261026T143646Z` permanece, sem reinterpretação.

O detector, por outro lado, **está validado pelo lado negativo**: reprova 17/17 janelas da corrida
congelada, inclusive as seis cujas taxas de cartas cairiam numa banda ingênua de 1/s (§4.4). Defeito de
projeto corrigido junto: `inject.swift` sai com `holdMs = 0` por padrão, porque o dwell é o defeito medido
em §4.3a, não um parâmetro de ajuste.

## 7. Próxima medição — plano preciso

1. **Bed fiel.** Subir `bench/serve.py` sobre o corpus em `127.0.0.1:8757` e usar namespace novo copiado de
   uma corrida cujo leitor esteja na **cabeça** do feed. Sem transporte, a janela cresce e re-submete o
   viewport sem gesto (medido em §4.3b), o que contamina a contagem.
2. **Varredura de velocidade, não de distância.** `v ∈ {0,15; 0,3; 0,6; 1,2; 2,4}` pt/ms, com movimento
   contínuo até o release (sem dwell, por §4.3a), 10 gestos por ponto: medir âncoras distintas/gesto e
   escolher a velocidade cuja mediana seja 1 (base) e 3 (rajada).
3. **Asserção anti-tap.** Screenshot após cada rajada: FeedMine tem de continuar em primeiro plano; URL
   aberta ou perda de sessão invalida a fase.
4. **Composição.** 60 s a 1/s + rajada de 10 s a 3/s, exigindo cartas distintas/s dentro de ±25 % da
   intenção e ≥95 % dos gestos produzindo âncora nova.
5. **Negativo — feito em §4.4, manter como regressão.** A cadência antiga já é reprovada 17/17 contra a
   corrida congelada (0,3–0,45 gestos/s, 2,0–4,2 cartas/gesto). Toda mudança no detector tem de continuar
   reprovando essas 17 janelas; um detector que as aprove não mede cadência.
6. **Congelamento separado**, só então: cópia verbatim em `bench/revisions/`, `EVALUATOR-pre-*.sha256`,
   nota datada, e uma medição causal antes/depois (um caso que reprove pelo motivo novo). Depois disso — e
   não antes — uma B03 de 30 min com revisão independente.

## 8. Limites honestos

- Âncora não é identidade estável de carta; a contagem pode superestimar reancoragem e não mede salto.
- `advance` não carrega ordinal, então contiguidade carta-a-carta continua não medível (mantido da revisão
  de fidelidade).
- O piloto rodou em simulador, com o app real, mas **sem** o transporte do corpus; conclusões de *produto*
  não saem daqui.
- Amostras pequenas (12/18/6 gestos). Servem para provar mecanismo e reprovar cadência, não para medir
  distribuição.
