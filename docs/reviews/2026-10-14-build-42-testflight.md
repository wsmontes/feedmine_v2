# Build 42 no TestFlight interno — o fim do conteúdo elegível (2026-10-14)

## O que foi enviado

`1.0 (42)` = `7fa07b3e48542769c7a449d731caf88467c8c5e2`, tag anotada
`ios/1.0-build.42-7fa07b3e` (empurrada). `PAIRING OK` antes da exportação, `Uploaded FeedMine`.
Build anterior no canal: `1.0 (41)`.

## O que mudou desde a 41

O **estado de fim de conteúdo elegível**, ratificado pelo PO a partir do critério do cliente:

- A frase **“Você chegou ao fim das histórias disponíveis para sua seleção.”** e as três rotas
  **“Explore outros assuntos”**, **“Ampliar fontes”** e **“Voltar ao início”**.
- Desenhado como **último filho da lista**, depois da última carta, nos dois ramos de layout: nunca
  substitui a tela, nunca entra no meio, e os cards anteriores ficam onde estavam.
- O fim só é afirmado com a **evidência completa**: uma tentativa de aquisição que não achou alvo
  elegível, o episódio local esgotado sem reconsideração pendente, nada em produção local e nenhuma
  aquisição pendente capaz de repor. **Janela local vazia, rodada concluída e fonte indisponível**
  continuam sendo os estados provisórios, com mensagem e ações próprias — é assim que os dois ficam
  distinguíveis pelo leitor.
- `FeedPresentationHandoff` é o único lugar que decide o estado, e um drain que não é o fim só pode
  **retirar** o fim: nenhum estado provisório é sobrescrito. O driver registra a aquisição que o
  próprio drain settleu e a lê ao lado dos fatos do runway — sem dono, cache, agendador ou token novos.

## Prova que acompanha este envio

| Prova | Resultado |
|---|---|
| Suíte do pacote | **1.262 testes, 1 skipped, 0 falhas** (`swift test`, verificado pelo team lead) |
| Regra `FeedEligibleOfferTests` | o fim só com a evidência completa; cada um dos quatro fatos exigido por si; janela local → `unavailable`, rodada concluída → `idle`, fonte indisponível/`deferred` → provisório |
| Render (macOS, OCR) | o bloco depois da última carta com as ações ratificadas |
| **Jornada no iOS, tela real** | `EndOfContentUITests`: **Executed 1 test, 0 failures** — a frase, as três rotas, nada acima retratado, e “Voltar ao início” move o leitor |

## Limites declarados

- A evidência real só settleia depois de o motor esgotar um corpus, o que uma corrida única não
  alcança: a jornada no iOS injeta a **evidência** por um gancho **DEBUG-only**
  (`FEEDMINE_END_ELIGIBLE_OFFER`). A regra, o handoff, a loja e a superfície são os do produto.
- “Voltar ao início” depende do ramo de posição de scroll do iOS 18+.
- **Os gates estão sendo re-rodados neste commit** (B01, B05, B02 e o aceite da cadência pelo QA);
  este documento não afirma nenhum veredito que ainda não tenha saído.
- B04 segue **INCOMPLETO** (a medida do ócio não foi possível), e B06 exige iPhone físico.

## Fluxos prioritários para o dono testar

1. Rolagem longa: o feed continua produzindo (era o defeito que parava tudo).
2. Responder a um convite: a próxima sugestão chega em poucos cards; “Desfazer” e “Meus interesses”
   funcionam.
3. Chegar ao fim: a frase e as três rotas aparecem **depois da última carta**, sem nada acima se mover.
4. Troca A→B→A, reopen, salvos, retorno offline.
