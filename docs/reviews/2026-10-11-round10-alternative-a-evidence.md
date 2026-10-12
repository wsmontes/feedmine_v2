# Rodada 10 — Alternativa A: evidência executada (2026-10-11)

Companheiro de `2026-10-11-round10-alternative-a-plan.md` (o plano registrado antes de editar). Aqui só há o que
foi **executado**, com o comando e o resultado; nada de aceite — o aceite é do PO.

Vocabulário, conforme o arquiteto (2026-10-11): uma **exposição** é um card que o app apresentou ao leitor; **não**
é prova de que ele leu. O orçamento é contado em *cards expostos/percorridos*, e é assim que este documento fala.

## Build utilizada

|Fato|Valor|
|---|---|
|HEAD|`609ced6d7f73e127b7cb0b5c818faaf4c341bacc` (main)|
|Árvore|trabalho das rodadas 1–10 **não commitado**; nada foi commitado nem empurrado|
|Aparelho das medições|iPhone 14 Plus físico, UDID `BBA4F656-A5EA-5D81-934E-E484ED71B8E2`|
|Transporte do gate|`192.168.1.76:8757` (variante de device do corpus congelado, `bench/device/`)|
|App de produto no aparelho|`com.feedmine.development` — **não** instalado nem desinstalado pelo gate; a build instrumentada vive em `com.feedmine.development.benchmark`|

**Achado de ambiente (QA):** o app fala o idioma do aparelho. Neste iPhone ele fala **inglês** (o item de menu é
`identifier: 'gearshape', label: 'Settings'`), então todo seletor por cópia em português — o que os testes do repo
fazem hoje — falha num aparelho que está funcionando. Os seletores deste trabalho passaram a usar
**identificadores** e, onde não há identificador, as duas línguas.

## 1. Compilação e testes

```
swift build  → Build complete
swift test   → Executed 1213 tests, with 1 test skipped and 0 failures
xcodebuild -scheme FeedMine -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build → BUILD SUCCEEDED
```

Os **8** testes de `ArchitectureSmokeTests/EditorialInvitationCadenceTests` fixam as regras R1–R8, incluindo as
correções vinculantes: voltar a um `ContextKey` já visitado **retoma** a sessão (o teto não se renova),
`reenabled()` **não** devolve um novo orçamento, e o ledger sabe dizer se um card **já foi exposto**.

O arquivo de aceitação é membro do alvo `FeedMineUITests` no `project.pbxproj` (projeto mantido à mão, sem grupos
sincronizados): quatro entradas coordenadas, e `xcodebuild -list` sai 0. Um passo anterior com
`-only-testing:FeedMineAppTests/…` executou **0 testes**: alvo errado, verde e falso.

## 2. Gate B01 (perfil A) no aparelho físico — `bench/run.sh`, exit 0

`bench/run/20261012T005435Z`:

```
neutral
answered:90_countries/brazil/food-drink/cooking-recipes
answered:90_countries/brazil/health-wellness/medicine-public-health
thematic-attempted
hide-stable:true
hide-frames:201->201
```

Oráculo: **PASS** em "a jornada vigente foi caminhada nas duas fases observáveis" (dois assuntos declarados
**dentro do feed**), **PASS** "≥50 fontes" = 193, **PASS** "≥20 fontes contribuindo" = 22. Perfil B: `NOT_RUN` —
registrado como **não executado**, nunca como validado (o PO reiterou essa distinção).

## 3. O orçamento medido no trace do próprio app

**Corpus (B01/A)** — `card_traversed` 4 → 16 → 28, intervalos 12 → 12 → 24, `answer_applied` no terceiro assunto.

**Catálogo real, no iPhone** (namespace `67F585D8…`, 573 s, 176 cards publicados, 93 com assunto):

```
editorial_offer cards_traversed=4  interval=12 offers_shown=1 subject=…/nigeria/fashion-beauty
editorial_offer cards_traversed=16 interval=24 offers_shown=2 subject=…/world-news
editorial_offer cards_traversed=40 interval=48 offers_shown=3 subject=…/law-ideas
editorial_offer cards_traversed=88 interval=96 offers_shown=4 subject=…/society-communities
```

Leitura: a primeira oferta vem depois de **4** cards expostos; cada oferta **ignorada dobra** a espera
(12 → 24 → 48 → 96, o teto); a quarta fecha o **teto de quatro por sessão**. Nenhum timer participa: a unidade é
card exposto/percorrido. Responder zera a penalidade (no corpus: 4 → 16 com o intervalo de volta em 12).

## 4. Achado de conteúdo/produto e a correção exigida pelo arquiteto

**Achado 1 — o pool segue a resposta.** Depois de o leitor responder, a descoberta passa a trazer o **assunto
respondido**, que a regra "assunto respondido não se repete" recusa: com o mesmo namespace, 54 cards expostos, 14
com assunto, **zero ofertas**. Não é defeito de código; é reportável, e é por isso que a validação de "a cadência
volta depois da resposta" se observa **antes** de responder a primeira oferta (no corpus ela aparece: a oferta 2
vem de outro assunto).

**Achado 2 — oferta em card já percorrido.** A janela que o app renderiza alcança **atrás** do leitor, e a oferta
podia ser colocada num card que ele já tinha passado: no catálogo real, o trace mostra **quatro ofertas feitas**
(4/16/40/88) enquanto uma caminhada só-para-frente não encontrava a segunda.

**Correção (arquiteto, 2026-10-11: "não adapte o teste para procurar para trás como solução de produto").**
Implementada no produto: `EditorialExposureLedger.wasExposed(_:)` + uma guarda em `editorialInvitation` —
**uma oferta nova só pode ser colocada num card que o leitor ainda não viu**. O bloco de uma oferta já feita
continua no card dele (o caminho de volta e o esconder seguem ali). O teste voltou a caminhar **só para frente**.

## 5. Correções vinculantes, implementadas e testadas

|Correção|Onde|
|---|---|
|exposição ≠ leitura — "cards expostos/percorridos"|tipo, app, testes e documentos|
|voltar a um `ContextKey` visitado não renova o teto|sessões por `ContextKey`; `testASessionBeginsOnlyWhereTheContextChangesAndIsResumedWhenItComesBack`|
|reativar não fura o limite de quatro|`reenabled()` limpa a penalidade mas não zera `offersShown`; `testReenablingNeverTakesTheSessionPastItsCap`|
|oferta nunca em card já exposto|`wasExposed` + guarda na decisão; o teste caminha só para frente|

## 6. Teste de aceitação no aparelho (catálogo real, fonte ampliada, árvore de acessibilidade)

`FeedMineUITests/EditorialOfferBudgetUITests`: leitor novo por corrida, portão da primeira execução caminhado,
texto no maior tamanho ("Grande"/"Large"), leitura contínua e, então:

|Passo|O que afirma|
|---|---|
|1|a primeira oferta traz a **pergunta completa** (frase de consequência presente) — fotografada|
|2|a oferta seguinte, de **outro assunto**, é **compacta** e ocupa **menos altura** que a completa|
|3|responder mantém a posição do leitor (mesmo card, medida assentada) e **desfazer** também|
|4|esconder **remove os controles da árvore de acessibilidade** e não move o leitor|
|5|lendo adiante com as sugestões escondidas, **nenhuma** oferta aparece|
|6|o interruptor "Mostrar sugestões do FeedMine" (página existente) **reativa** as ofertas, sem mover o leitor|
|7|a preferência **sobrevive a uma reabertura** do app|

Status: instrumento em iteração no aparelho; o passo 1 passou e as capturas existem. O que falta é a corrida que
atravessa todos os passos com a correção do §4 aplicada.

Limites do instrumento, declarados: a fonte ampliada é afirmada pela opção escolhida (o `value` da linha do picker
é `nil` nesta plataforma) e comprovada onde é desenhada — nas capturas do run; a comparação absoluta com os
128 pt anteriores exige o tamanho padrão, e esta corrida mede no tamanho ampliado (por isso a afirmação é
**relativa**: compacto < completo, medidos do mesmo jeito).

## 7. Decisões do PO recebidas nesta rodada

- **Aceite final:** pendente da validação no aparelho; a implementação foi **aprovada**.
- **Perfil B:** não deve ser apresentado como validado (segue `NOT_RUN`).
- **"Menos de X":** não alterar nesta rodada; registrar a inconsistência de linguagem como **P1**. Registrado
  como **PD-11** em `docs/product/PRODUCT_DECISIONS_2026-10-09.md`, com os rótulos escolhidos por ele
  ("Não quero mais sobre X" / "Entendido. Vamos excluir X das próximas descobertas." / "Desfazer") e a distinção
  futura (reduzir frequência ≠ excluir). Motor e ranking **intocados**.

## 8. Disco

Autorizado pelo usuário limpar caches do computador; de **917 MB para ~4,9 GB** antes do gate. `bench/` não foi
tocado; `/tmp/feedmine-r5-derived` (build de outra sessão) ficou de pé. Os bundles de resultado dos runs de
iteração foram removidos depois de extraídas as evidências (cada run com falha traz um vídeo de ~300 MB).

## 9. O que ficou de fora, declarado

- **VoiceOver** de verdade: a prova executada é sobre a **árvore de acessibilidade** (o material que o VoiceOver
  consome); uma sessão humana com o VoiceOver ligado não foi feita.
- **Vídeo contínuo**: o XCTest grava `.mp4` quando a corrida falha; a corrida bem-sucedida gera capturas por passo.
- **Perfil B do B01** e os gates B02–B05: não executados.
- A janela do Chrome usada para mediar quebrou duas vezes ("Aw, Snap") e não entrega teclado em background; o relé
  exigiu reconduzir a página e usar `takeover` na colagem e no clique de envio.

---

## 10. Correção da posição ao responder (adendo do arquiteto, 2026-10-11)

**O que o aparelho mostrou.** Responder uma oferta movia o leitor: o card âncora (mesma identidade, medida
assentada) foi de minY 152,08 para -760,58 numa corrida (≈912 pt) e ~139 pt em outra. O "esconder" nem chegava a
rodar: o bloco saía da tela quando o feed se movia.

**Causa (código).** `voteOnTopic` chamava `replaceSession()`; o cursor gravado por `checkpointCurrentPosition`
guarda card + placement mas **nenhum offset dentro do card**, e a restauração re-ancorava como podia. O
`ViewportObservation` também não carrega offset — o offset do leitor não existia em lugar nenhum persistível.

**Correção (instrução do arquiteto: avaliar primeiro aplicar a preferência sem reconstruir).** `voteOnTopic`
persiste, registra `answer_applied` e **não reconstrói mais a sessão**. A resposta é uma preferência sobre a
**descoberta futura** — é o que o bloco promete — e a janela admitida, sua edição e sua ordem ficam intactas por
construção. Um caso preservado: se uma construção **já está em curso**, a resposta marca o rebuild pendente
(`pendingRebuild`), para a associação sendo construída ler o perfil que já contém a resposta (o teste
`testAnswerDuringContextTransitionIsApplied` fixa isso).

**Regressões adicionadas.**
- `CompositionTests.testAnsweringInTheFeedChangesDiscoveryWithoutMovingTheReader` agora exige a invariante forte:
  **a mesma associação** depois de responder (além de mesma edição, janela anterior como prefixo, perfil como
  interesse/exclusão e "Desfazer" removendo a resposta).
- O teste de aceitação no aparelho afirma a posição do **mesmo card por identidade** ao responder e ao desfazer.

**Medição corrigida (instrução 5 do arquiteto).** O helper do driver comparava botões de salvar — identificador
igual em todos os cards — e não distinguia um card de outro. O driver passou a acompanhar o card **por
identidade**. Como o driver é arquivo congelado, `bench/EVALUATOR.sha256` foi **re-congelado** (os seis arquivos
verificam `OK`); o critério de estabilidade não mudou. Efeito esperado: cláusulas que antes passavam por
compararem "algum card" podem agora falhar onde o leitor realmente se move.

**Continuidade dos logs (instrução 6).** `answer_applied` é escoado logo depois de registrado, para uma corrida
que termina antes do próximo evento de viewport ainda poder provar que a resposta foi aplicada.

---

## 11. Validação visual no aparelho: **PASSOU** (2026-10-11)

`FeedMineUITests/EditorialOfferBudgetUITests` — iPhone 14 Plus físico, catálogo real, fonte no maior tamanho
("Large"), leitor novo por corrida. Resultado: **1 teste, 0 falhas** (exit 0). Os sete passos passaram, com as
capturas nomeadas no bundle de resultado (`/tmp/fm-accept-shots`):

|Captura|O que ela mostra|
|---|---|
|`first-offer-full`|a primeira oferta do sessão com a pergunta completa (frase de consequência presente)|
|`second-offer-compact`|a oferta seguinte, de outro assunto, **sem** a frase e com **menos altura** que a completa|
|`answered-in-place` / `answer-taken-back-in-place`|responder e desfazer no mesmo lugar|
|`hidden-offers-gone-from-the-tree`|depois de esconder, nenhum controle de convite na árvore|
|`re-enable-in-the-existing-preferences`|o interruptor "Mostrar sugestões do FeedMine" na página de preferências existente|
|`offers-restored`|as ofertas de volta depois de reativar|
|`preference-survives-relaunch`|a escolha do leitor depois de reabrir o app|

**Posição do MESMO card (por identidade), medida no aparelho:**

```
POSITION_ANSWER before=189.0833282470703 after=189.0833282470703
POSITION_UNDO   before=189.0833282470703 after=189.0833282470703
POSITION_HIDE   before=189.0833282470703 after=189.0833282470703
```

Ou seja: **0,0 pt** de deslocamento ao responder, ao desfazer e ao esconder (a asserção do teste é ±1 pt).

**Achado de acessibilidade (muda o remédio, em três medições).** `.accessibilityElement(children: .ignore)` +
`.accessibilityHidden(true)` — aplicados de fora (sobre `AnyView`) e depois dentro da view concreta — **não**
removeram os botões da árvore: com o bloco escondido, a consulta ainda devolvia
`feed-invitation-more-…@y=659,99 h=34,33`, `-less-…@y=648,99 h=56,33` e `-hide-…@y=669,85 h=14,33`, com frames
reais. O remédio adotado é o que o critério do PO pede de fato: com as sugestões escondidas, **não existe
controle nenhum** — os rótulos viram texto sem identificador e sem ação, o bloco mantém forma e slot, e não há
nada para tocar, para o VoiceOver alcançar ou para uma consulta encontrar.

**Nota honesta.** A prova acima é sobre a **árvore de acessibilidade** — o material que um leitor com VoiceOver
consome — e não sobre uma sessão humana de VoiceOver ligado, que não foi feita nesta rodada.

---

## 12. O refresh explícito (critério do PO, 2026-10-11)

O parecer do PO acrescentou: *"um refresh explícito que produza uma nova edição também deve considerar a
preferência"*. Implementado: `AppComposition.refreshFromTheReader()` compara o perfil **armazenado** com o perfil
de que o pool desta sessão foi construído (a associação passou a guardar esse perfil). Se são o mesmo, o refresh é
o de sempre (nada reconstrói); se a resposta mudou o perfil, a sessão é reconstruída — aqui o leitor **pediu**
movimento, e a resposta precisa alcançar a descoberta.

Coberto por `CompositionTests.testAnExplicitRefreshHonoursAnAnswerGivenAfterTheSessionWasBuilt`: verde, e o mesmo
teste afirma que um segundo refresh sem resposta pendente **não** reconstrói nada e que a edição/janela que o
leitor tinha não é retratada.


### Acessibilidade: o que só uma medição podia decidir

O critério do PO é que **nenhuma parte** da sugestão escondida seja alcançável. Medido no aparelho, em ordem:

1. `.accessibilityHidden(true)` no caminho de esconder (a primeira tentativa): com o bloco escondido, os três
   botões continuavam na árvore, com frames reais.
2. `+ .accessibilityElement(children: .ignore)`, aplicado **de fora** (sobre `AnyView`) e depois **dentro** da view
   concreta: os botões continuavam lá.
3. Folha a folha (`.accessibilityHidden(isInert)` em cada `Text` e nos rótulos sem ação): os botões saíram, mas
   **dois títulos "FeedMine sugere" continuavam anunciáveis** — a asserção nova do arquiteto pegou exatamente isso
   (`count == 2`, esperado 0).

**Remédio final:** quando o leitor esconde as sugestões, o app **não desenha nada** delas — nem controle, nem
palavra. O espaço é preservado porque o bloco informa a altura que ocupa enquanto está de fato na tela
(`onGeometryChange` → `EditorialInvitationCadence.remember(height:of:)`), e o slot escondido é um
`Color.clear.frame(height:)` com essa medida. O que nunca foi desenhado não se anuncia — nem para o VoiceOver, nem
para uma consulta.

### Aceitação final (com as asserções de acessibilidade do arquiteto): **PASSOU**

Depois do remédio do §"Acessibilidade", a corrida no iPhone 14 Plus, catálogo real, fonte Large, fechou:

```
Test Case '...testTheOfferBudgetHoldsOnTheRealCatalogue' passed
Executed 1 test, with 0 failures
POSITION_ANSWER before=383.75 after=383.75
POSITION_UNDO   before=383.75 after=383.75
POSITION_HIDE   before=383.75 after=383.75
```

E as três asserções de árvore passam juntas: **nenhum botão** de convite (`feed-invitation-*`), **nenhum texto**
de consequência (`feed-invitation-consequence-*`) e **nenhum título** "FeedMine sugere" — ou seja, nada da
sugestão escondida é anunciado. O que fecha o critério não é marcar como oculto: é não desenhar.

---

## 13. O invariante forte, medido no aparelho: **nenhum card se move**

O benchmark mede "o card do leitor não se move" pela âncora. Isso não cobre o caso que ele mesmo expôs: com o
bloco **acima** do leitor, encolher o bloco (a forma respondida é mais baixa que a pergunta) puxa tudo o que está
abaixo — e a âncora está abaixo. Correção no produto: o bloco é desenhado **dentro do slot que ele ocupou quando
foi medido**, e o slot **nunca encolhe** (`EditorialInvitationCadence.remember` guarda o máximo; um tamanho de
texto maior pode crescer o slot).

Medição, no iPhone 14 Plus, catálogo real, fonte Large, comparando **todos** os cards da árvore por identidade
antes e depois de cada ação:

```
Test Case '...testTheOfferBudgetHoldsOnTheRealCatalogue' passed   (0 falhas)
POSITION_ANSWER before=123.75 after=123.75
POSITION_UNDO   before=123.75 after=123.75
POSITION_HIDE   before=123.75 after=123.75
```

Mais as asserções de conjunto: **nenhum card mudou de posição** ao responder e ao esconder (e as três de árvore
do §"Acessibilidade" seguem passando: nenhum botão, nenhum texto, nenhum título anunciáveis).

## 14. B04 com o avaliador corrigido: o que as quatro execuções mostram

|Execução|Resultado|
|---|---|
|1ª (helper por identidade, com filtro de viewport)|FAIL: answer/undo/hide/idle + order false|
|2ª (helper sem o filtro — falso negativo corrigido)|FAIL: answer/undo/order false; idle/rotação/background true|
|3ª (com o slot que não encolhe)|FAIL, com o passeio do dia escondendo as dicas antes: `b04-invitation:not-offered` (correto: nada é oferecido escondido) e `b04-idle-frames:-9999->-9999`|
|4ª (com os frames registrados)|a linha `-9999->-9999` mostra o problema: o card **não estava na árvore**, e o booleano diz "false" sem ter medido movimento nenhum|

Leitura honesta: a cláusula de estabilidade do B04 **hoje não distingue "não medível" de "moveu"** — quando o card
sai da árvore (reciclagem do `LazyVStack`), o registro lê `false`. O invariante forte que ela quer medir foi medido
no aparelho pelo teste de aceitação (§13) e está preservado. Decidir se o driver deve tratar "não medível"
explicitamente é do arquiteto; eu não mexi nisso.

---

## 15. Instrumento do B04 corrigido (autorizado pelo arquiteto, 2026-10-11)

O arquiteto autorizou corrigir o instrumento com a regra: *"distinguir 'não medível' de 'instável'. Frames
-9999 → -9999 não demonstram movimento e também não comprovam estabilidade."* Feito, com o hash do avaliador
atualizado (`bench/EVALUATOR.sha256`) e **o critério de produto intacto** — `true` continua sendo estável.

**Driver (`DiscoveryBenchmarkTests`).**
1. Três resultados por medição: `true` (estável), `false` (instável) e `not-measurable` (com motivo: o card saiu da
   árvore, ou o controle não foi oferecido).
2. O mesmo card é seguido por identidade; **nunca** se substitui por outro. Quando ele sai da árvore, a preparação
   é refeita (`bringIntoView`) e o ciclo é repetido uma vez, com os fatos do retry registrados como `b04-retry-*`
   (informativos, não decidem o gate).
3. A jornada do B04 roda **sem esconder as sugestões** (`hidesTheTips: false`): as preferências ficam habilitadas e
   há oferta disponível para o gate medir, no namespace isolado da corrida — nada fora dele é tocado.
4. O cenário é preparado para cobrir explicitamente **o bloco acima do leitor**: entre as ofertas visíveis escolhe-se
   a que tem um card publicado **abaixo** dela que caiba na tela; a posição e a ordem são medidas nesse card.
5. O ócio faz `bringIntoView` antes de medir e registra `not-measurable` (com motivo) quando não consegue.

**Oráculo (`bench/oracle.py`, `gate_b04`).** `false` = falha do gate; `not-measurable` = **gate incompleto**
(`pass: None`, nunca PASS); `true` em tudo = PASS. O estado passa a relatar as três contagens.

Efeito esperado, declarado: uma corrida em que o card sai da árvore **não** vira PASS por omissão — ela fica
incompleta e diz por quê.

---

## 16. O ócio do B04 revelou um defeito meu: o slot do bloco escondido colapsava

Medição, no aparelho, com o instrumento corrigido: depois de responder, desfazer e esconder (o card do leitor em
559 → 559 pt, ordem intacta ✓, bloco **acima** dele ✓), o ócio de 12 s lia `not-measurable` com o motivo exato
`card-absent(on-screen=<outros dois ids>)` — o card do leitor **não estava mais na árvore**, e os dois cards na tela
eram outros.

Causa: um bloco oferecido que **nunca foi disposto em tela** (card além da margem de instanciação da
`LazyVStack`) não tem altura medida — e eu usava `height ?? 0` no slot escondido. Slot de altura **zero** = o feed
colapsa aquele trecho e o card do leitor sai da tela. Zero era o único valor que o slot nunca podia ter.

Correção: o slot escondido usa a altura da própria medida, e — quando não há medida — a altura do bloco **mais alto
já visto na mesma forma** (completa/compacta). `EditorialInvitationCadence.remember(height:of:isCompact:)` guarda a
altura por forma; `slotHeight(of:isCompact:)` devolve a medida própria, a da forma, ou a da outra forma — **nunca
zero** depois que qualquer bloco daquela forma foi visto.

Nota de honestidade: quando o card do leitor sai da árvore, o ócio **não** é medido — e o registro diz o motivo, com
os ids que estavam na tela. O oráculo marca o gate como **incompleto** nesse caso (nunca PASS), conforme a regra do
arquiteto.

---

## 17. B04 com o instrumento corrigido: **PASS completo e mensurável**

`bench/run/20261012T050627Z` (iPhone físico, corpus, avaliador re-congelado com o instrumento novo):

```
b04-block-above-reader:true
b04-anchor0:454
b04-after-answer-stable:true      454->454
b04-after-answer-order:true
b04-after-undo-stable:true        454->454
b04-after-hide-stable:true        454->454
b04-idle-stable:true              122->122      (medido na 1ª tentativa)
b04-rotation-holds:true
b04-background-same-topmost:true
b04-background-stable:true        256->256
verdict: PASS
```

Nenhum fato `not-measurable` e nenhum `false`: o gate está **completo**. O cenário cobre explicitamente o bloco
**acima** do leitor, que é o caso que a medição por âncora não via.

O que foi preciso, em ordem, para chegar aqui (todas as quatro correções são de instrumento, com o hash do
avaliador atualizado e o critério de produto intacto):
1. acompanhar o card **por identidade** em vez de um botão igual em todos os cards;
2. três resultados — estável / instável / **não medível** com motivo (e "não medível" deixa o gate incompleto);
3. repetir a medição (reposicionando a preparação) quando o card sai da árvore — e **a repetição é o fato**;
4. `bringIntoView` pedir **na tela**, não "na árvore": um card disposto fora do viewport é encontrado pela consulta,
   então a checagem antiga nunca rolava e o ócio nunca se tornava mensurável (o motivo registrado traía isso:
   `card-not-laid-out(height=185)` para um card que tinha frame).

E uma correção de **produto** que só o ócio revelou: o slot de um bloco escondido ia para zero quando aquele bloco
nunca tinha sido disposto em tela, e o feed colapsava sob o leitor; agora o slot usa a altura da forma (completa/
compacta) e nunca zero (§16).

---

## 18. Parecer final do PO — ACEITE CONCEDIDO (2026-10-11)

Registrado literalmente do parecer do PO (ChatGPT, thread "Assumir papel de PO"):

> **Parecer final do PO — Rodada 10 — ACEITO — FRENTE ENCERRADA**
>
> | Item | Resultado |
> |---|---|
> | Cadência adaptativa | ACEITO |
> | Formato compacto | ACEITO |
> | Preservação de posição | ACEITO |
> | Esconder e acessibilidade | ACEITO |
> | Reativação e persistência | ACEITO |
> | Aplicação futura das preferências | ACEITO |
> | B04 no dispositivo físico | PASSOU |
> | Rodada 10 | ENCERRADA |
>
> *"Autorizo o Codex a encerrar esta frente e avançar para a próxima prioridade de UX. A Rodada 10 resolveu um
> problema importante de produto: o FeedMine consegue aprender sobre os interesses do leitor sem sequestrar sua
> atenção nem desestabilizar sua leitura. Esse é exatamente o comportamento que queremos preservar na V2.
> PO FeedMine V2 — ACEITE FINAL CONCEDIDO."*

O que sustenta cada item, neste documento: cadência adaptativa e teto (§3, §11), forma compacta (§11), posição
(§11, §13), esconder e acessibilidade (§15 da seção de acessibilidade, §11), reativação e persistência (§11),
aplicação futura das preferências (§12 e os testes novos em `CompositionTests`), B04 no aparelho (§17).

Pendências declaradas, que **não** foram aprovadas por omissão: perfil B do B01 segue NÃO executado; a prova de
acessibilidade é sobre a árvore que o VoiceOver lê, não uma sessão humana com VoiceOver; e a corrida aprovada tem
capturas por passo e os logs do app, não vídeo contínuo. As duas falhas pré-existentes de `CompositionTests`
seguem registradas separadamente.
