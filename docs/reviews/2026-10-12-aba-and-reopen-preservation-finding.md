# Achado — a edição e a janela não sobrevivem a A→B→A nem à reabertura

Medido em 2026-10-12, ao escrever a verificação que o Kiro pediu (K-06, achado 5) e o arquiteto confirmou
("Conclua também o B05 com resposta entre A e B"). **Não é hipótese: é teste vermelho, com reprodução.**

## O que o teste faz e o que ele encontrou

`FeedMineAppTests/CompositionTests.testK06AnsweringInABetweenAAndBKeepsTheWindowAndTheSaves`:

1. abre A, salva um card e posiciona a âncora nele;
2. **responde** em A (`voteOnTopic(..., .more)`);
3. vai para B (`selectContext`), volta para A;
4. exige: mesma **edição**, mesma **janela** (âncora), mesmo **nível declarado**, mesmos **salvos**.

Resultado, com dois de quatro verdes:

|Verificação|Resultado|
|---|---|
|Nível declarado sobrevive|**verde** — a resposta dada em A continua `.more` depois da ida a B e da volta|
|Salvos do leitor sobrevivem|**verde**|
|Mesma edição ao voltar|**VERMELHO** — `editionID 9A20F484…` ≠ `5F880826…`|
|Mesma janela (âncora)|**VERMELHO** — a janela restaurada é outra|

## Por que isto não é ruído de teste

`CompositionTests.testS5OfflineReopenRestoresEditionWithFreshProvenance` (linha 687) afirma **a mesma classe de
propriedade** no caminho de **reabrir** — `XCTAssertEqual(restored.window, snapshot.window)` — e **falha desde antes
desta frente**. São dois caminhos independentes (troca de contexto e reabertura) acusando a mesma perda, o que
aponta para uma causa comum na restauração de edição/janela, não para um teste mal escrito em cada lugar.

Isso também qualifica o que eu havia reportado antes: as "2 falhas pré-existentes" do alvo do app **incluem um
defeito de produto**, não são apenas herança de árvore. Foi por isso que o arquiteto pediu para mantê-las separadas —
e agora há evidência de que pelo menos uma delas é comportamento, não ambiente.

## O que **não** está em causa

- O critério do PO que já foi aceito ("abrir e fechar o leitor preserva o mesmo card e a posição exata") é outro
  caminho e continua provado: medida de 0,0 pt no cartão ancorado, com o leitor abrindo e fechando.
- A resposta e os salvos **sobrevivem** — a parte de estado durável está correta.
- Não é efeito do disco nem de ambiente: a corrida foi limpa (`Executed 1 test, with 2 failures`, 1,0 s) e ambos os
  vermelhos são asserções de identidade, não erros de I/O.

## O que fica pedido

O teste **fica no repositório** como regressão do defeito (o arquiteto decide a correção; é mudança de produto).
Corrigir significa: ao voltar a um contexto (ou reabrir), restaurar **a edição e a janela** do checkpoint daquele
contexto, não construir uma edição nova — preservando o comportamento de proveniência que o `testS5` também exige.

Verificação de que a correção funcionou: este teste e o `testS5` verde ao mesmo tempo, sem afrouxar nenhum dos dois.
