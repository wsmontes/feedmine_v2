# Rodada 10 — relatório consolidado (2026-10-11)

Frente: F02 — sugestões editoriais no feed, com orçamento sobre exposições reais (Alternativa A).
Aceite: **concedido pelo PO em 2026-10-11** ("ACEITO — FRENTE ENCERRADA", §18 do documento de evidências).

Companheiros, em ordem de leitura: `2026-10-11-round10-alternative-a-plan.md` (plano e regras),
`2026-10-11-round10-alternative-a-evidence.md` (tudo o que foi executado, com os comandos e os números),
`2026-10-11-round10-changes-inventory.md` (o inventário arquivo por arquivo, para revisão e integração).

## 1. O que mudou no produto

|Regra|Estado|
|---|---|
|Orçamento em **cards realmente expostos** (não em janelas renderizadas, não em relógio)|implementado e medido|
|Primeira oferta depois de 4 cards; intervalo base 12; cada oferta ignorada **dobra** (teto 96); teto de 4 por sessão|implementado e medido (4/16/40/88; 12→24→48→96)|
|Responder **zera a penalidade**|implementado e testado|
|Primeira oferta com a pergunta completa; as seguintes **compactas**|implementado e medido (compacta < completa)|
|**Esconder** desenha **nada** da sugestão (nem controle, nem palavra) mantendo o slot|implementado e medido na árvore de acessibilidade|
|**Reativar** na página de preferências existente, persistente|implementado e medido (sobrevive à reabertura)|
|**Responder não reconstrói a sessão** (era o que movia o leitor)|implementado; a posição fica idêntica|
|A preferência vale na **próxima sessão do contexto** e num **refresh explícito**|implementado e testado|
|Oferta nunca cai num card **já percorrido**|implementado (correção exigida pelo arquiteto)|
|"Menos de X" intocado; inconsistência de linguagem registrada como **PD-11 (P1)**|registrado|

## 2. Evidência executada (o que sustenta cada linha acima)

- **No iPhone 14 Plus físico, catálogo real, fonte "Grande"**: teste de aceitação
  `FeedMineUITests/EditorialOfferBudgetUITests` — **PASS, 0 falhas**, com as capturas nomeadas por passo, a
  posição do mesmo card em 154,08 → 154,08 pt ao responder/desfazer/esconder, a asserção de conjunto (nenhum card
  da tela se move) e as três asserções de árvore (nenhum botão, nenhum texto de consequência, nenhum título
  "FeedMine sugere" anunciáveis).
- **Gate B04 no aparelho** (`bench/run/20261012T050627Z`): **PASS completo e mensurável** — responder 454 → 454,
  desfazer 454 → 454, esconder 454 → 454, ócio 122 → 122, rotação e background 256 → 256, com o bloco **acima**
  do leitor, todos com o **mesmo card** por identidade.
- **Gate B01 perfil A no aparelho** (`bench/run/20261012T005435Z`): exit 0, com as duas respostas dentro do feed e
  `hide-stable:true`.
- **Suítes**: `swift test` **1213 testes, 0 falhas**; `FeedMineAppTests/CompositionTests` **41 testes**, com
  apenas **as 2 falhas pré-existentes** (export de caixa salvos e S5 offline), registradas separadamente e **não**
  aprovadas.

## 3. Limitações declaradas (não aprovadas por omissão)

- Perfil B do B01: **NÃO executado**.
- Acessibilidade: a prova é sobre a **árvore** que o VoiceOver lê; **não** houve sessão humana com VoiceOver
  ligado.
- Vídeo: a corrida aprovada tem **capturas por passo e os logs do app** (`trace.jsonl`); não há vídeo contínuo
  (o XCTest só grava vídeo quando o teste falha).
- As duas falhas pré-existentes de `CompositionTests` seguem abertas e separadas.
- O inventário de disco do aparelho não foi medido nesta rodada.

## 4. Instrumento do benchmark (autorizado, com o critério de produto intacto)

`bench/EVALUATOR.sha256` foi **re-congelado** duas vezes porque o driver e o oráculo mudaram: a medição de
estabilidade passou a acompanhar o card **por identidade** e a registrar **três resultados** — estável, instável e
**não medível com motivo** — sendo que "não medível" deixa o gate **incompleto, nunca PASS** (regra explícita do
arquiteto), e o driver teve de preparar a própria cena (as sugestões ficam habilitadas e a jornada do B04 não
gasta as ofertas que o gate vai medir). O critério em si — `true` é estável — não foi alterado.

## 5. O que a frente deixa para quem vem depois

- `docs/reviews/2026-10-11-round10-changes-inventory.md` lista cada arquivo tocado, o que mudou e onde, para
  revisão e integração.
- PD-11: a linguagem de "Menos de X" deve refletir a exclusão que ela realmente faz; rótulos escolhidos pelo PO
  estão no registro.
- O canal do Kiro (`coordination/KIRO.md` §6) tem o handoff com os arquivos quentes e as duas asserções falhando
  que o K-13 pediu.
