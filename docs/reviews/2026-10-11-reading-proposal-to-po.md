# Proposta ao PO — experiência de leitura (FeedMine V2, 2026-10-11)

Origem: ordem do arquiteto ("próxima prioridade de UX: leitura de um artigo real … leve ao PO uma proposta") e o
diagnóstico medido em `docs/reviews/2026-10-11-article-reading-diagnosis.md`. **Nenhuma linha do produto foi
alterada**: tudo abaixo é observação, e a decisão é sua.

## 1. O que temos hoje (medido, não opinado)

Quando o leitor toca na manchete, o app abre a **página do site** dentro dele, num `SFSafariViewController`:

|Medida|Resultado|
|---|---|
|Superfície aparece|**0,07 s**|
|Fechar e voltar ao feed|**0,12 s**|
|Posição ao voltar|**exata** — mesmo cartão, delta 0,0 pt, `high_water_card_id` inalterado|
|O que o app controla lá dentro|nada: barra do Safari, tipografia do site, anúncios, "Subscribe/Sign in"|
|Funciona sem rede|não|
|Idioma|o do aparelho (o app é localizado `en` + `pt-BR` e segue o aparelho — coerente, não é defeito)|

Ou seja: **a mecânica está boa** (abre e volta instantaneamente, sem perder o lugar). O que não está resolvido é a
**leitura em si**: o leitor sai da tipografia, do idioma e do controle do FeedMine no momento em que começa a ler.

## 2. O ativo que já pagamos e não usamos

O app **já guarda o texto** que recebe, e já o indexa para busca (FTS5). Medido no banco real do aparelho
(namespace de aceitação):

|Medida|Valor|
|---|---|
|Revisões de conteúdo guardadas|3.403|
|Com texto integral do feed (`body_text`)|**0** — o catálogo real não publica corpo|
|Com resumo|3.139 (92%)|
|Tamanho do resumo|média **681** caracteres; maior **51.122**|
|Cartões publicados|173|
|Destes, com **3.000+ caracteres** guardados|**22**|
|Destes, com 801–3.000 caracteres|12|
|Destes, com 201–800 (um parágrafo)|37|

Traduzindo: **34 dos 173 cartões (20%) já carregam texto suficiente para uma leitura dentro do app**, e mais 49
carregam pelo menos um parágrafo. Hoje **isso é descartado**: o app abre a página e joga fora o texto que tem.

## 3. As três opções, com o custo de cada uma

**A — Leitor de texto do FeedMine (o app lê o que já guardou).**
Manchete, fonte, data e o texto guardado, com a tipografia do app (as preferências de leitura já existem), busca
por texto já indexada, **funciona com a rede desligada**, acessibilidade nossa. O Safari deixa de ser a leitura e
passa a ser uma **saída explícita** ("Abrir no site").
*Limite honesto:* vale para os 34 cartões com texto longo e mostra chamada + saída nos demais — os 80% restantes só
teriam texto integral com uma frente nova (buscar a página e extrair o artigo), que **não** está nesta proposta.
*Custo:* baixo — é apresentação do que já existe no store; nenhuma mudança na aquisição.

**B — Manter o Safari, com moldura do app.**
Mantém a página como está (o que abre e volta em 0,07 s/0,12 s já está certo) e acrescenta **cabeçalho nosso** —
título, fonte, data, ações — e a saída explícita para o navegador. Nada de leitura offline.
*Custo:* o menor dos três; ganho real, mas a leitura continua sendo a página de outro.

**C — Leitor próprio sobre a página (web view com leitura limpa).**
Controlamos a barra e podemos injetar um modo de leitura, mas continuamos dependendo da rede e da página, e o app
passa a carregar a superfície e o risco de um navegador.
*Custo:* o maior; duplica o navegador que já temos.

## 4. O que eu recomendaria (a decisão é sua)

**A, com a moldura de B.** Uma única superfície de leitura: ela mostra o texto guardado quando ele é substancial e,
quando não é, mostra o que existe (título, resumo, fonte, data) com a **saída explícita** para o site — sem nunca
precisar de duas telas diferentes para o leitor entender onde está.

Por que A primeiro: é o único caminho que faz a leitura pertencer ao FeedMine **sem** depender de rede, sem
reforma de aquisição, e que aproveita texto que já está no banco. É também o único que sobrevive ao metrô.

## 5. Como isso seria provado (para não repetirmos a Rodada 1)

O mesmo instrumento do diagnóstico, isolado do produto (alvo de testes), estendido com três fatos observáveis:
abrir um cartão com 3.000+ caracteres guardados e **ver o texto na tipografia do app**; repetir com a **rede
desligada** e ver o mesmo texto; e abrir um cartão sem texto suficiente e ver a saída para o site **onde o leitor
espera**. Mais o que já está provado e não deve regredir: leitor em ≤0,1 s, volta em ≤0,1 s, posição idêntica
(delta 0,0 pt e `high_water_card_id` inalterado).

## 6. A decisão pedida

1. Leitura **dentro do FeedMine** (A) ou **moldura sobre a página** (B) ou **navegador próprio** (C)?
2. Se A: a saída para o site fica no cabeçalho da leitura, no fim do texto, ou nos dois?
3. Se A: o texto integral dos 80% restantes (buscar e extrair a página) entra como frente própria agora, ou fica
   para depois?
