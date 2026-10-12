# Resposta ao K-06 — pacote da rodada 10 (OMP, 2026-10-12)

Resposta à revisão `k06_review.md`, achado por achado. O arquivo que faltava está aqui:
**`k06_missing-feed-screen.diff`** (o diff de `Sources/FeedMineUI/FeedScreen.swift` entre `origin/main` e a
árvore da rodada 10). Ele responde as duas perguntas que a revisão deixou em aberto.

## O arquivo que faltava

O inventário da rodada 10 **omitiu** `Sources/FeedMineUI/FeedScreen.swift` — falha minha ao montar o pacote: eu
listei os arquivos que criei, não o que a rodada *modificou* na UI que hospeda o bloco. O diff anexo corrige isso
(35 inserções, 11 remoções). Com ele:

### K06-3 — **FECHADO como correto** (era hipótese)
O bloco editorial **não** é item de `window.items`. Ele é desenhado dentro da própria iteração do `ForEach` do
card:

```swift
ForEach(Array(presentation.window.items.enumerated()), id: \.element.id) { index, card in
    …
    if let row = editorial?(card, index, index > 0 ? presentation.window.items[index - 1] : nil) { row }
}
```

Logo o bloco não tem identidade de card, não entra em `capture.observeCard`, não pode virar `anchor.cardID` e não
dispara `isLast` cedo. A âncora é sempre um `PublicationCardID` publicado, como você supôs que deveria ser.

### K06-2 — **CONFIRMADO como defeito** (e o seu raciocínio sobre o meu teste está certo)
O bloco é um filho **irmão dentro da mesma iteração**: o card e o bloco são dois filhos do `LazyVStack`, que
aplica `spacing: Spacing.section` entre filhos. Quando o bloco está **escondido**, o host devolve
`AnyView(Color.clear.frame(height: slotHeight ?? 0))` — ou seja, **ainda existe um filho** e o vão de
`Spacing.section` **continua sendo inserido**. Esconder não devolve a geometria de "sem bloco".

Você previu também por que a minha medição não pega isso: `assertNothingMoved` compara o `minY` do card âncora por
identidade, e o vão extra fica **abaixo** dele — delta 0,0 pt com vão duplo permanente. A prova que vale é a que
você propôs: medir `next.minY - prev.maxY` em três estados (sem oferta / oferta visível / oferta escondida), com o
escondido igualando o "sem oferta".

**Correção mínima proposta** (é mudança de produto, então depende do arquiteto): o host devolver `nil` — o tipo do
closure já é `AnyView?` — quando não houver bloco, em vez de devolver uma altura 0; e/ou agrupar card+bloco num
`VStack(spacing: 0)` para que o `LazyVStack` veja um filho só.

## Ack dos demais achados

- **K06-1** (custo de `recordWindowFacts` por mudança de janela): aceito como P1 de custo, sem disputa. O mérito é
  seu: `editorialSubject` lê dicionário já computado, mas o `.task(id: window)` roda em cada passo do
  `growthFollowUp`. Fica registrado para medição instrumentada (contar chamadas numa corrida B03), não como
  correção de corretude.
- **K06-4** (orçamento high-water por identidade; A→B→A não zera; relaunch zera): sua leitura confere com o
  desenho — o ledger é único por `AppComposition` e nunca resetado, e as sessões são por `ContextKey`. O reinício
  no relaunch é **decisão pendente do PO** (definição de sessão), exatamente como você classificou: relato, não
  defeito.
- **K06-6** (oráculo): aceito integralmente, incluindo a distinção que você fez — a mudança não transforma FAIL em
  PASS, torna o gate **incompleto** quando a medição não pode ser tomada. É o que o inventário declara e é o que a
  regra do benchmark exige.
- **K06-7** (`editorialTipsHidden` sem migração): **fechado como seguro, por medição**.
  `Sources/FeedMineDomain/ReaderSettings.swift:98-121` decodifica com `decodeIfPresent` **todos** os campos (o novo
  inclusive, `:121`) e aplica default (`?? standard.x`). Uma base antiga sem a chave decodifica e sobe.
- **K06-8** (rebaixado por você): concordo com a nota — `voteOnTopic` não suspende antes de persistir, então não há
  intercalação. O risco volta se aparecer um `await` antes da persistência; a correção mínima que você indicou
  (serializar por `subject`, última intenção vence) fica anotada.
- **K06-9** (volta redundante de `replaceSession`): aceito como P2 de custo; a comparação de perfil que você
  sugere é a correção certa.
- **K06-10** (locale): obrigado por fechar como verificado correto — os testes usam identificadores, não copy.

## K06-5 — é uma lacuna da minha evidência, e você está certo

Não existe, no meu pacote, um teste B05 com resposta entre A e B. O que eu tinha era o UITest de orçamento, que não
cobre A→B→A. Registro como verificação pendente minha: estender o driver B05 com um `vote` entre A e B e afirmar
`return-preserves-anchor` e `reopen-keeps-saved`.

## K-15 (RSS `content:encoded` e Atom `content` ignorados como `bodyText`)

Confirmo o achado e traigo a medida que ele produz no catálogo real, colhida no aparelho: **`body_text` é vazio em
todas as 3.403 revisões** do catálogo real, porque todas as fontes são RSS e o ramo RSS da sindicação passa apenas
`summary: item.description`. Consequência prática: hoje o efeito é **zero** (não há corpo para ignorar); o efeito
aparece **se** decidirmos capturar corpo de RSS, porque `bodyText` participa do fingerprint material da versão — e
aí toda revisão já admitida ganharia uma versão nova. É decisão de produto: levei ao arquiteto.
