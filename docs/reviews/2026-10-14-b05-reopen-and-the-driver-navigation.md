# B05 FAIL — a reabertura restaura o início da edição, e o A→B→A do driver está morto (2026-10-14)

Corrida `bench/run/20261014T091824Z`, commit `6c02387b` (build 42 + docs), corpus e oráculo
congelados, device dedicado `FeedMine Bench`.

## Veredito: FAIL — 1 de 2 cláusulas, 2 medidas falsas

| Medida | Valor |
|---|---|
| `b05-saved` | true |
| `b05-return-preserves-anchor` | true (**vacuamente** — ver abaixo) |
| `b05-reopen-preserves-anchor` | **false** |
| `b05-reopen-keeps-saved` | **false** |
| `b05-offline-shows-local` / `b05-offline-cards` | true / true |
| `b05-context-b-reached` | **ausente do registro de fases** |

## O que NÃO é o defeito

- **O app não perde o salvo.** `reader_bookmark_memberships` tem 1 linha: lista `saved`, card
  `bc73989f-7b06-402e-9d1e-edeee86cd5d6` — exatamente o `b05-anchor-before` do driver.
- **O app não falha em restaurar.** O contexto é persistido (`reader_preferences.active_context` =
  `{"request":{"main":{}}}`), a edição é restaurada, e a releitura offline desenhou o feed local
  (`b05-offline-shows-local` e `b05-offline-cards` verdadeiros).
- **Não é regressão de commit.** O caminho restore/cursor (`PublicationHistory.restore`,
  `SessionStore.checkpoint(for:)`, `FeedSession.checkpointCurrentPosition`) está idêntico ao de
  2026-10-11, e nenhum commit da janela toca esses arquivos.

É **restauração de uma posição diferente**, não perda.

## Por que uma posição diferente

Três fatos distintos na mesma edição `0fd847d0`:

| Fato | Card | Onde |
|---|---|---|
| checkpoint durável do contexto | `45c35e6e` = **card #1 da edição** | `context_checkpoints.card_id`, `updated_at == feed_editions.created_at` |
| marca de visto (high water) | `0c436420` = card #7 | `edition_reading_state.high_water_card_id` |
| card que o driver seguia | `bc73989f` = **card #12** | `b05-anchor-before` |

O restore lê o **checkpoint do contexto** — um milestone do âncora *lógico* (card + posicionamento,
sem offset dentro do card), escrito **só** por `checkpointCurrentPosition`: troca de contexto,
substituição de sessão, ida para background e criação da edição. Nada disso aconteceu nesta corrida
depois da criação da edição, então o checkpoint continuou no primeiro card. O card salvo (#12) fica
**admitido** (capacidade à frente 16) mas nunca **desenhado** — e é por isso que nenhum card na tela
aparece como salvo.

## O A→B→A do driver congelado está morto

O driver (`DiscoveryBenchmarkTests.swift:658-669`) toca `more-menu` e exige
`app.buttons["Salvos"]`. O menu é `ReaderMenuEntry.standard` e **não tem** nenhum item "Salvos"; o
único rótulo "Salvos" é o botão do cabeçalho (`bookmark-boxes-button`), que a query não encontra com
o menu aberto. Provas: a fase `b05-context-b-reached` é gravada incondicionalmente no ramo e **não
existe** no registro; e `B05-A.log:407-427` mostra 10 s de verificações de existência falhando.

Consequências honestas:

- `b05-return-preserves-anchor:true` é **vacuamente verdadeiro** — nada navegou, então a âncora
  "voltou" por não ter saído.
- Sem troca de contexto, **nenhum checkpoint** seria gravado mesmo se o driver achasse o botão: a
  superfície de salvos é uma **navegação**, não um contexto.

## O que fecharia B05

O driver é congelado (`bench/EVALUATOR.sha256`), então a decisão é do produto, e ela é de
**durabilidade da posição**: hoje um leitor que **fecha à força** o app volta para o último
*milestone* — no limite, o início da edição. `RUNTIME_PRESENTATION_CONTRACT.md:77-79` faz o
movimento de viewport ser memória-local com `checkpointCurrentPosition` como fronteira explícita de
durabilidade, e o único gancho de saída é `background()` — medido: **0 linhas de "lifecycle
checkpoint"** em duas mortes por `terminate()`.

Opções, para o PO decidir:

1. **Checkpoint com cadência** (por avanço ou com debounce): a posição do leitor sobrevive a um kill.
   Custo: escrita em banco no caminho de consumo — precisa ser desenhada contra o orçamento de
   performance/energia que a fluidez exige.
2. **Manter a fronteira** e registrar que o gate não fecha: o B05 continuaria FAIL por causa de um
   A→B→A que o próprio driver não caminha.

## O que esta corrida NÃO prova

- Nada sobre o A→B→A real (não foi caminhado) nem sobre retorno do background (não exercitado).
- `b05-return-preserves-anchor` não deve ser lido como prova de preservação de âncora entre contextos.
