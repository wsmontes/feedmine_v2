# Rodada 10 — plano de implementação da Alternativa A (orçamento das sugestões)

Autorizado pelo arquiteto (Codex, 2026-10-11 17:35) e pelo PO (§8 do diagnóstico da rodada 10).
Este documento é o **plano curto com regras verificáveis** exigido antes de qualquer edição de código.
Ele não substitui o diagnóstico: `docs/reviews/2026-10-11-round10-reading-rhythm-and-hints.md`.

## 1. O que muda, em uma frase

A sugestão continua **depois do card** (é ali que a resposta e o "Desfazer" vivem), mas deixa de ser ilimitada:
passa a ter **orçamento sobre exposições reais**, forma compacta depois da primeira e um caminho de volta.

## 2. Regras verificáveis (cada uma com o instrumento que a mede)

| # | Regra | Como se verifica |
|---|---|---|
| R1 | Uma oferta só existe depois de **cards efetivamente percorridos**, não de cards renderizados numa janela | o contador vem de `ViewportObservation` aceitas (`AppComposition.viewport`), não do tamanho da janela |
| R2 | Sugestões expostas **sem resposta** aumentam progressivamente o intervalo | `ignoredOffers`: intervalo = `base × 2^n`, teto `maximum` |
| R3 | Sugestão **respondida** libera nova oportunidade com intervalo mínimo confortável | resposta zera `ignoredOffers`; próxima oferta exige `base` cards novos |
| R4 | Assunto já respondido nunca é repetido | guarda existente (`declaredLevel`/`inFeedAnswers`) + `offeredSubjects` |
| R5 | Existe teto por sessão | `offersShown < sessionOfferCap` |
| R6 | O leitor **esconde** → nenhuma oferta nova até reativar | `hidden` recusa antes de qualquer oferta |
| R7 | Reativar **restaura** o comportamento **sem furar o teto** | reativação limpa a penalidade e devolve a distância, mas não zera `offersShown` (arquiteto, 2026-10-11) |
| R8 | Nova sessão **não** reinicia por foreground, por reconstrução interna, **nem por voltar a um contexto já visitado** | sessões são guardadas por `ContextKey`; voltar a uma **retoma** o que o leitor deixou (o teto não se renova) |
| R9 | Primeira oferta pergunta completa; seguintes **compactas** (< 128 pt) | forma compacta não tem a pergunta longa nem a consequência |
| R10 | Esconder **remove** os controles da árvore de acessibilidade | `.accessibilityHidden(true)` no caminho de esconder |
| R11 | Nenhuma ação move a posição do leitor nem o feed visível | `hide-stable` / `b04-*-stable` já medidos pelo driver |
| R12 | "Menos" **não** muda nesta rodada | sem redução de ranking, sem alteração de semântica |

## 3. Parâmetros de calibração (valores iniciais conservadores, em um único tipo)

| Parâmetro | Valor | Por quê |
|---|---|---|
| `firstOfferAfterCards` | 4 | o antigo `index >= 3` tinha exatamente esta intenção; agora conta cards lidos, não admitidos |
| `baseInterval` | 12 | uma oferta a cada doze cards novos ≈ uma a cada poucas telas |
| `ignoredMultiplier` | 2 | oferta ignorada dobra o intervalo (progressivo, não linear) |
| `maximumInterval` | 96 | teto do crescimento: o intervalo nunca vira "nunca" |
| `sessionOfferCap` | 4 | proteção de volume por sessão (30 min de B03 admitem milhares de cards) |

Restrições que a escolha respeita: o driver de aceitação procura ações com uma caminhada limitada (20 swipes por
tentativa) e exige **duas** respostas dentro do feed; `baseInterval = 12` cabe nessa caminhada, `maximumInterval`
não.

## 4. Sessão: definição declarada

**Sessão = a `ContextKey` que o leitor está lendo, dentro de uma execução do app — e uma sessão já visitada é
retomada, não renovada.** Trocar para outro contexto começa a sessão **daquele** contexto; voltar a um contexto
já lido devolve exatamente o que o leitor deixou lá (o teto gasto continua gasto, os assuntos já oferecidos
continuam oferecidos, os blocos continuam nos seus cards). Foreground e reconstrução interna pelo mesmo contexto
não são eventos: `replaceSession` (responder uma sugestão) e voltar do segundo plano não mudam nada.

Correção vinculante do arquiteto (2026-10-11): *"voltar a um ContextKey já visitado não deve renovar o teto
inadvertidamente"* e *"reativar pode liberar ofertas, mas não deve permitir ultrapassar silenciosamente o limite
de quatro por sessão"*. Consequência no código: as sessões vivem num dicionário por `ContextKey`, e `reenabled()`
limpa a penalidade e devolve a distância, mas **não** zera `offersShown`.

Trade-off declarado: um leitor que alterna entre muitos contextos tem, no total, mais ofertas do que um que lê um
só — mas nenhuma troca de tela renova o teto de um contexto já visitado, que era o risco apontado.

## 5. Exposição: qual sinal é usado

O app já tem o instrumento: o `FeedVisualCapture` publica, por `onGeometryChange`, a **prova visual** do card que
o leitor está de fato atravessando, e a entrega como `ViewportObservation` aceita em
`AppComposition.viewport(_:activity:)`. O orçamento conta **essas** âncoras (cards distintos), nunca o tamanho da
janela apresentada. Nenhum instrumento novo é criado.

## 6. Instrumentação para o gate

- `window`: ganha `cards_traversed` (exposições reais) e `offers_shown`.
- `editorial_offer`: uma linha por oferta — `subject`, `cards_traversed`, `offers_shown`, `interval`.
- Sem isso, a cláusula de frequência da rodada 10 não teria o que medir. O oráculo congelado
  (`bench/oracle.py`, sob `EVALUATOR.sha256`) **não** é tocado nesta rodada.

## 7. Fora de escopo (declarado)

- Semântica/língua da ação "Menos de X" (exclusão de assunto): o arquiteto mandou confirmar com o PO **antes** de
  alterar. Pergunta encaminhada, nada alterado.
- Remoção das sugestões do fluxo (Alternativa B): o PO decidiu não implementar nesta rodada.
- Validação visual no simulador: obrigatória antes do aceite final; este plano só a antecede.

## 8. Verificação executada neste round

1. `swift test --filter ArchitectureSmokeTests` com os testes novos do orçamento.
2. `swift build` (pacote) e build do alvo do app.
3. Sem declaração de aceite: o aceite é do PO, e a validação visual é do simulador.

---

## 10. Adendo (2026-10-11, arquiteto): a posição ao responder

O arquiteto ampliou o escopo **apenas** para o caminho de aplicação da preferência, com a instrução de avaliar
primeiro se a descoberta futura pode ser atualizada **sem reconstruir a sessão**.

**Achado (medido no aparelho, catálogo real).** Responder uma oferta chamava `replaceSession()`: a sessão se
aposentava, o cursor era gravado por `checkpointCurrentPosition` — que guarda **card + placement, sem nenhum
offset dentro do card** — e a nova associação restaurava a partir dele. O leitor era movido: 139 pt numa corrida,
912 pt em outra; e o bloco que ele tinha acabado de responder saía da tela antes mesmo de o "esconder" rodar. O
`ViewportObservation` também não carrega offset, então hoje o offset do leitor não existe em lugar nenhum
persistível (o cursor com offset seria mudança de contrato do Runtime + esquema persistido + migração).

**Decisão.** A resposta é uma preferência sobre a **descoberta futura** — é o que o próprio bloco promete
("…nas próximas descobertas"). Portanto `voteOnTopic` persiste, registra e **não reconstrói mais a sessão**:
a janela admitida, sua edição e sua ordem ficam intactas por construção, e a preferência alcança a descoberta na
próxima sessão construída para aquele contexto. Nada de retratação, nada de reordenação, nada de movimento.

**Regressões.**
- `CompositionTests.testAnsweringInTheFeedChangesDiscoveryWithoutMovingTheReader` passa a exigir a invariante
  forte: **a mesma associação** (`after === association`) depois de responder — além das já existentes (mesma
  edição, janela anterior como prefixo, perfil lido como interesse/exclusão, "Desfazer" removendo a resposta).
- O teste de aceitação no aparelho afirma a posição do **mesmo card** (por identidade) ao responder e ao desfazer.

**Medição do B04 (instrução do arquiteto).** O helper do driver comparava botões de salvar, cujo identificador é
igual em todos os cards — ele não distinguia um card de outro e reportava "estável" o que tivesse se movido. O
driver passou a acompanhar o **card específico por identidade**. Como o driver é arquivo congelado, o
`bench/EVALUATOR.sha256` foi **re-congelado** (linha do driver atualizada; os seis arquivos verificam). O critério
de estabilidade não mudou.

**Continuidade dos logs.** `answer_applied` passou a ser escoado (`trace?.flush()`) logo depois de registrado:
uma corrida que termina antes do próximo evento de viewport precisa poder mostrar que a resposta foi aplicada.
