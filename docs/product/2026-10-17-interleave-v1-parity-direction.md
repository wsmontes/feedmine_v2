# Interleave: direção de paridade comportamental V1 → V2

Data: 2026-10-17 (America/Vancouver).
Status: encaminhamento solicitado explicitamente pelo dono após comparação de código. Documento de requisito e investigação; não implementa uma política, não certifica paridade e não altera benchmarks.

## Comportamento a preservar

O feed deve oferecer uma sequência editorial variada, considerando conjuntamente fontes/provedores, assuntos, geografia, formatos e contexto temporal, respeitando a seleção e as preferências do leitor e a diversidade efetivamente disponível. Alternar apenas IDs de fontes não demonstra essa paridade: fontes diferentes podem entregar repetidamente o mesmo assunto, formato ou origem editorial.

A composição dessa sequência acontece **antes da publicação**. Conteúdo novo é preparado e ordenado para publicação futura; não autoriza reembaralhar, substituir ou enriquecer a sequência já publicada, inclusive sua parte ainda não vista. O gesto de rolagem não executa um reequilíbrio editorial do feed existente. Preservar INV-08/09/17 e a diretriz de prontidão anterior à admissão.

Não fabricar diversidade nem violar filtros do usuário quando não existem alternativas elegíveis. Não inferir assunto por história ou natureza temporal sem evidência autorizada.

## O que foi encontrado na V1

Referência: repositório `wsmontes/feedmine-dev`, arquivos inspecionados nesta sessão em 2026-10-17. Os símbolos abaixo identificam a implementação observada; conferir a revisão efetiva antes de transportar comportamento.

`feedmine/Services/Reservoir.swift`:

- `interleaveImpl`: agrupa por fonte; considera leitura/exposição prévia e recência; distingue conteúdo `isTimeless` de notícia; aplica pesos influenciados por presets; intercala fontes e espalha geografia.
- `interleaveByTypeCategoryImpl`: mistura combinações de tipo e categoria.
- `spreadForFreshnessImpl`: procura reduzir repetição recente de provedor, categoria, região e mídia. Aqui "freshness" inclui variedade da sequência, não apenas data.
- `frontLoadUniqueProvidersImpl`: amplia a variedade de provedores no início.
- `computeSeed`/`interleaveOffMain`: há cálculo inicial fora do MainActor; não assumir que todos os caminhos da V1 são assim — `append` ainda chama o interleave síncrono.
- `append`: intercala somente o lote novo e o acrescenta à reserva; não reintercala toda a reserva.
- `moveToVisible`: transfere a ordem definida sem reshuffle periódico durante a rolagem.

`feedmine/Services/EditorialSequencer.swift`:

- `sequence`: reforça a diversidade de fontes na sequência final com rotação por menor contribuição acumulada, desempate pela posição de entrada e preservação da ordem interna de cada fonte.
- `consecutiveRunIssues` e `leadingProviderCount`: verificam aspectos da sequência produzida, em vez de apenas a intenção do algoritmo.

Cuidado na interpretação: o Reservoir e o EditorialSequencer usam definições diferentes de identidade de provedor; as heurísticas, pesos e quotas da V1 não constituem automaticamente contrato aprovado para V2. Este registro não certifica todos os call sites da V1 nem afirma ausência de defeitos nela.

## Diferença observada na V2

Na árvore examinada durante a conversa (`6cbaa2fee3445e92957f9172d756cbbed4609108`), `Sources/FeedMineEditorial/SelectionEngine.swift` ordena por peso e valor de timestamp e aplica variantes de `SourceAlternation`. Esse caminho não aplica a mistura multidimensional descrita acima.

Os contratos de evidência temática e temporal já integrados não equivalem, por si só, a políticas de diversidade temática e frescor contextual ativas. `Tests/FeedMineEditorialTests/ContextualFreshnessCharacterizationTests.swift` declara explicitamente caracterização, não implementação: data de observação ainda pode superar publicação conhecida na ordenação. Não chamar esse teste verde de prova de requisito implementado.

Esta é uma diferença de comportamento a analisar e fechar, não autorização para introduzir um segundo selector ou portar o runtime legado.

## Encaminhamento de implementação

1. Mapear cada dimensão da V1 para fatos realmente disponíveis no supply canônico e políticas vigentes da V2: provedor/fonte, assunto por história, geografia, formato, exposição/leitura e natureza temporal. Distinguir disponível, ambíguo e ausente.
2. Registrar lacunas de evidência antes de inventar classificação. Categoria da fonte não prova assunto de toda história; observação recente não prova publicação recente; URLs diferentes não provam provedores editoriais diferentes.
3. Definir a política no dono editorial existente, conciliando preferências, relevância, diversidade e continuidade entre lotes/segmentos. Evitar diversidade que reinicia sua memória a cada append e produz repetições nas emendas.
4. Aplicar a ordem somente a candidatos para publicação futura. Preparação de mídia e admissão devem respeitar essa política sem modificar ocorrências publicadas.
5. Retirar o cálculo editorial do caminho síncrono do gesto e do desenho. Não copiar a dependência de MainActor de caminhos legados, timers, pesos arbitrários, cotas ou limites fixos da V1 como política da V2; preservar INV-16.

## Provas esperadas

- Fontes diferentes com o mesmo assunto/formato não devem ser tomadas como demonstração suficiente de diversidade multidimensional. Um corpus controlado deve oferecer alternativas reais e mostrar que a política as aproveita.
- Presets e filtros influenciam a sequência de forma explicável, sem inventar alternativas ou romper restrições explícitas do leitor.
- Fontes/provedores representáveis não ficam permanentemente ocultos pela concentração de oferta de outros; avaliar o resultado produzido e não só contagem de candidatos.
- Conteúdo já lido/mostrado e idade contextual usam fatos legítimos; desconhecido continua desconhecido, sem fabricar novidade a partir de `observedAt`.
- A emenda entre duas publicações mantém o contrato editorial, sem precisar reordenar a primeira.
- Chegada de novos candidatos, fim de preparação de mídia e rolagem não alteram ordem, conteúdo ou geometria de cards já publicados/admitidos.
- Os controles devem distinguir uma implementação que só alterna fontes de outra que realmente satisfaz as dimensões aprovadas. Não inventar percentuais para declarar sucesso nem alterar a régua congelada.

## Limite do commit

Somente orientação de produto e referência de código. Nenhum build, teste, profiling ou mudança no app foi realizado por este documento. A política concreta e sua integração permanecem sujeitas à hierarquia vigente e às provas de execução.
