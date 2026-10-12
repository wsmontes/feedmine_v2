# Rodada 6 — materialização entre segmentos: correção com medição

Data: 2026-10-11. Autor: sessão OMP. Nenhum commit (a restrição da rodada 5 continua valendo).

## 1. Correção do diagnóstico (o Codex pediu para verificar a causa)

A consulta **já atravessa segmentos**. Prova em duas frentes:

- `Sources/FeedMinePersistence/PublicationStore.swift:540-544` ordena e filtra por
  `(s.ordinal, c.ordinal)` sobre **toda a edição**: `WHERE s.edition_id = ? AND (s.ordinal, c.ordinal) > (?, ?)`
  com `ORDER BY s.ordinal ASC, c.ordinal ASC LIMIT ?` — não há corte por segmento.
- No store real da corrida de primeira abertura com o catálogo real, o âncora do checkpoint é
  `(segmento 0, card 0)` e a mesma consulta, executada direto no SQLite, devolve **21 cards** seguintes
  (edição com segmentos `1 + 1 + 20`).

Logo, **P0 e S5 não têm a mesma causa** (Codex item 2: "o sintoma semelhante ainda não comprova isso"). O S5 é
igualdade de janela na **restauração** (9 contra 17, âncora idêntica) e continua aberto com o caminho de
quem materializa a restauração; o P0 era **gatilho**, não consulta.

## 2. O defeito real: nada relê a reserva depois da primeira publicação

Medido: `cold bootstrap settled` e, a partir daí, nenhum `install` novo; a rajada de 20 cards chega segundos
depois e ninguém a materializa, porque depois de uma publicação bem-sucedida o app **não agenda mais
oportunidades** (o `coldRetryAt` só existe quando nada foi publicado) e o leitor não fez gesto nenhum.
Agravante medido: `driver.activateCurrentPresentation` pode esperar **minutos** com o catálogo real (numa
corrida a primeira tentativa de crescimento só apareceu 4,5 min depois do settle).

## 3. Correção

- `startGrowthFollowUp()`: cadeia **limitada** (8 tentativas, 0,75 s entre elas) iniciada **no fato da
  publicação** — logo depois de instalar o resultado do cold bootstrap e **antes** do await do driver (que é
  quem demora) — e repetida como rede de segurança ao fim do `launch()`.
- Cada tentativa é um fato: pergunta à sessão pelos cards **já publicados** além da cauda; se não há nada
  novo, nada é instalado; a janela só cresce; nada acima da âncora muda.
- O crescimento continua **append-only** e limitado pela janela congelada da âncora
  (`anchorIndex + forwardCapacity + 1`), o que o torna idempotente: repetir nunca anda a cauda além do limite
  (isso já tinha sido corrigido na rodada 5, depois de duas asserções de composição reprovarem uma cauda sem
  limite).
- Os gatilhos por evidência dentro de `receive(_:)` saíram: eles cancelavam uns aos outros
  (`growthTask?.cancel()`), então a rajada ficava sem leitura nenhuma.

## 4. Evidência (catálogo real, primeira abertura, sem gesto)

```
16:15:05.949  published growth: admitted 1 -> 1
16:15:06.754  published growth: admitted 1 -> 1
16:15:07.546  published growth: admitted 1 -> 1
16:15:08.299  published growth: admitted 1 -> 2     <- a rajada começa a chegar
16:15:09.195  published growth: admitted 2 -> 17    <- a janela se preenche sozinha
```

`testFirstRunOverTheRealCatalogueExpandsWithoutAGesture` — **PASS (16,9 s)**, sem gesto (contadores
`received=0 completed=0 backward=0`). O defeito P0 da rodada 5 está fechado.

## 5. Regressões (Codex item 4)

|Regressão exigida|Onde|
|---|---|
|Crescimento sem gesto atravessando segmentos|teste de aceitação com catálogo real (verde) + `testFirstOpenExpandsTheAdmittedWindowWithoutAGesture` (fixtures, verde)|
|Sem duplicatas|`testPublishedGrowthAppendsWithoutAGestureAndKeepsTheAnchor` afirma `Set(ids).count == items.count`|
|Posição preservada|o mesmo teste afirma âncora, contexto, edição e o prefixo já admitido idêntico|
|Crescimento repetido como no-op|o mesmo teste afirma que repetir devolve a mesma janela; o limite da âncora é verificado|
|Restauração de 17 sem cair para 9 (S5)|**continua vermelho** — pertence ao caminho de restauração da outra sessão (§1); não toquei nele|

## 6. Coordenação entre sessões

Não alterei `Sources/FeedMinePublication/**` nem `Sources/FeedMinePersistence/**`: a medição do §1 mostrou que
não eram necessários. Portanto não há edição concorrente nessas funções. O caso mínimo para quem possui o S5:
edição com segmentos `1 + 1 + 20`, checkpoint com âncora `(0, 0)`; a restauração devolve 9 cards onde a janela
do leitor tinha 17 — a consulta de janela devolve 21 no mesmo estado, então a diferença está em como a
restauração **pede** a janela (capacidade/cursor), não na consulta.

## 7. Portões executados

|Portão|Resultado|
|---|---|
|Pacote (`swift test`)|**1186 testes, 1 pulado, 0 falhas**|
|Bateria de UI do app (`xcodebuild test`, esquema FeedMine)|**101 verdes, 1 vermelho, 6 pulados** (result bundle `Test-FeedMine-2026.10.11_16-16-09`)|

Classificação exigida (esperadas × inesperadas):

- **Esperada e já conhecida:** `testS5OfflineReopenRestoresEditionWithFreshProvenance` — restauração devolve 9
  onde a janela tinha 17; pelo §1 é materialização de restauração (outra sessão), não a consulta de janela.
- **Esperada e agora resolvida:** o aceite da rodada 5 (`testFirstRunOverTheRealCatalogueExpandsWithoutAGesture`)
  **passou** — era ele o vermelho esperado e o P0 do primeiro uso está fechado.
- **Inesperadas:** nenhuma.
- **Pulados:** os 6 são a suíte de benchmark com portão (`DiscoveryBenchmarkTests` B01–B05 e a preparação do
  soak), que exige `FEEDMINE_BENCHMARK=1` e o corpus congelado — pulam por projeto, não por regressão.

Testes desta rodada que passaram e cobrem o defeito: aceite do catálogo real (sem gesto), alcançabilidade por
scroll no catálogo real, continuidade na reabertura (transporte controlado), expansão sem gesto (fixtures),
superfície sem histórias com as duas ações, e o caso de runtime do crescimento (limite, âncora, no-op, sem
duplicatas).
