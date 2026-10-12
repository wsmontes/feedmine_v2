# Decisão do PO — experiência de leitura (2026-10-11)

Registro verbatim da decisão do PO (thread "Assumir papel de PO", ChatGPT web), tomada sobre o diagnóstico medido
em `docs/reviews/2026-10-11-article-reading-diagnosis.md` e a proposta em
`docs/reviews/2026-10-11-reading-proposal-to-po.md`. Nada foi alterado no produto para obter esta decisão.

## Decisão

- **A + B: APROVADA.** Leitor de texto sobre o conteúdo já guardado, com a moldura do app.
- **Abrir no site: cabeçalho e final**, conforme o conteúdo.
- **Extração integral: FORA DO ESCOPO.**
- Orientação: "aproveitar o armazenamento e os componentes existentes. Não quero outro sistema de cache ou uma
  segunda arquitetura de conteúdo apenas para construir o leitor."
- Princípio declarado: "o FeedMine deve permitir descobrir conteúdo e, sempre que possível, consumi-lo dentro do
  próprio aplicativo. A internet deve enriquecer a experiência, não ser uma dependência obrigatória quando o
  conteúdo já está disponível localmente."

## Critérios de aceite do PO (verbatim)

1. Artigos com texto substancial podem ser lidos localmente, sem rede.
2. Conteúdo parcial nunca é apresentado como completo.
3. Artigos sem texto suficiente continuam tendo acesso simples e rápido ao site.
4. Fonte, título e data são apresentados corretamente.
5. Abrir e fechar o leitor preserva o mesmo card e a posição exata.
6. O leitor respeita Dynamic Type, inclusive fonte Grande.
7. Falha de conexão não impede a leitura do conteúdo local disponível.
8. **Nenhuma aquisição de conteúdo é iniciada pela renderização do leitor.**

## Sobre o critério 2 (importante contra a leitura errada dos números)

O PO foi explícito: "3.000 caracteres não comprovam que o artigo está completo. Não devemos apresentar conteúdo
parcial como se fosse integral." A medida de 3.000+ caracteres guardados (§5 do diagnóstico) serve para decidir
**quando vale abrir a leitura local**, não para afirmar que o texto ali é o artigo inteiro. A superfície tem de
dizer o que tem — texto do feed, parcial sempre que for parcial.

## Estado dos critérios contra o que já foi medido

|Critério|Estado hoje|
|---|---|
|5 — posição exata ao voltar|**já provado** em duas camadas: delta 0,0 pt no cartão ancorado e `high_water_card_id` inalterado (diagnóstico §1)|
|3 — acesso rápido ao site|o caminho existe (`SFSafariViewController`), mas sem a ação "Ler no site" nem a moldura do app|
|1, 2, 4, 6, 7, 8|dependem da superfície nova — nenhum foi exercitado ainda|

O instrumento para provar 1/2/4/6/7 é o mesmo do diagnóstico, isolado no alvo de testes
(`ArticleReadingDiagnosisUITests.swift`); o critério 8 é uma invariante de produto (a renderização do leitor não
inicia aquisição) e pede uma verificação própria.
