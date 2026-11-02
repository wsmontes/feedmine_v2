# Revisão de aleatorização e diversidade — 2026-11-02

Base: `origin/main` `2eca5b4` (o código de seleção é o mesmo no branch `kiro/review-fixes-20261102`).
Leitura de código mais uma simulação fiel do sequenciamento v6 em Python
(`evidence/2026-11-02-v6-sequencing-sim/`). Nada foi rodado no app; nenhum número abaixo vem de aparelho,
exceto a medição do OMP de 24/out citada.

## Resposta curta

- **Não há aleatorização nenhuma.** Os seeds existem no schema e são a constante `1`
  (`AppComposition.swift:4061`, `:4538`); nenhum código de ordem os lê. A ordem é uma função pura de
  (oferta, histórico): mesma oferta, mesma ordem em toda Edition nova. Isso é parcialmente intencional
  ("sem aleatoriedade opaca", `NOVAS_FRENTES_PARA_O_CODEX.md:211`; pool "determinístico",
  `ReaderDiscoveryPool.swift:122-125`), mas a diretiva do dono de 24/out exige shuffle amplo.
- **O v6 implementa a diretiva de forma lexicográfica, e isso produz o oposto do pedido.** A diretiva pede a
  maior distância possível entre repetições de tipo, tema e fonte. O v6 elimina candidatos por TIPO, depois
  ASSUNTO, e só então FONTE (`MaximumDistanceSequencing.swift:57-65`). Fonte vira desempate. A única regra
  dura de fonte é PD-4 (não adjacente).
- **A oferta já chega estreita e previsível.** A descoberta percorre o catálogo em ordem alfabética de chave,
  com cursor em memória que recomeça a cada abertura, e o pool é um top-120 fixo por qualidade. A janela de
  candidatos é o "128 mais novos globais".

## Simulação do v6 (porta fiel, 50 primeiros cards)

| Oferta | Fontes distintas | Fonte dominante | Padrão |
|---|---|---|---|
| A: 1 podcast (40 itens) + 20 feeds de texto (5 cada) | 21 | **POD 25/50** | `T06 POD T02 POD T11 POD …` |
| B: 4 podcasts (10) + 20 textos (5) | 24 | P0 7/50 | áudio em 1 de cada 2 posições (oferta: 29%) |
| C: 1 blog com tags novas por post + 19 feeds com 2 categorias estáveis | 20 | **TAGGY 24/50** | `TAGGY` a cada 2 |
| D: 1 fonte prolífica (60) + 19 pequenas (3), sem tipo/assunto | 20 | 3/50 | rotação perfeita (gap 20) |
| E: itens mais novos com fatos desconhecidos | 21 | 3/50 | rotação perfeita |
| F: mesma oferta em ordem de entrada diferente | — | — | saída idêntica |

A e C reproduzem a medição de 24/out (1.425 cartas: 936 áudio, distância média de tipo 2,0, mínima 1).
Quando há um tipo ou um assunto minoritário, quem o fornece aparece em toda segunda posição: PD-4 permite
`A x A x`, e o tipo/assunto tem prioridade sobre a fonte. Sem diferenças de tipo e assunto (D, E), a distância
de fonte funciona bem.

## Achados

### Ordem (Editorial)

1. **Alta — tipo e assunto antes da fonte.** `MaximumDistanceSequencing.swift:57-65`. A rotação de tipo
   iguala a participação dos tipos independentemente da oferta: um tipo raro (um podcast, um canal de vídeo)
   impõe sua fonte a cada k posições. O mesmo vale para assuntos: uma fonte que inventa tags por post sempre
   tem distância infinita e ganha. Os testes `testNovelTypeBeatsHeavyRepeatedType` e
   `testBalancedABCABC` (`MaximumDistanceSequencingTests.swift`) fixam esse comportamento como correto.
2. **Alta — sem teto de participação por fonte.** O v3/v4 tinha rotação por participação na oferta
   (`SourceAlternation.swift`); o v6 não usa isso (`AppComposition.swift:3673`, `:3501`). Os contratos de
   "toda fonte antes de repetir" (`SourceDiversityContractTests`) rodam só em v3.
3. **Média — nenhuma aleatoriedade, nem semeada.** Uma Edition nova sobre a mesma oferta sai igual.
   O seed por Edition/segmento já é persistido; usá-lo como desempate determinístico e registrado não seria
   "aleatoriedade opaca".
4. **Média — mesma história de vários veículos.** `contentClusterID`/`contentEntityID` são sempre `nil`
   (`AppComposition.swift:4241`) e o Editorial não os lê; deduplicação só por `originRecordID`. Atenção ao F03
   (`F03_…PRD.md:73`): não reduzir diversidade de opinião por assunto parecido; separar só a mesma história.
5. **Média — pesos do leitor quase inertes.** Peso entra só na ordem base; tipo e assunto o anulam.
6. **Baixa — emenda de segmento usa só a fonte de atribuição** (`LocalProductionSlice.swift:266`), enquanto
   dentro do segmento o PD-4 usa todas as fontes do candidato.
7. **Baixa — atribuição por `Set.first`** quando nenhuma fonte tem nome (`AppComposition.swift:4233`): varia
   por processo (hash seeding do Swift).

### Oferta (descoberta, aquisição, janela)

8. **Alta — descoberta recomeça na primeira chave alfabética a cada abertura.** Cursor em memória
   (`ReaderDiscoveryTraversal.swift:27`), `ORDER BY s.key` (`LegacyCatalogReader.swift:257`), páginas de 32
   (bootstrap) e 120 (runway). As mesmas fontes de início alfabético abrem toda sessão; perfis estreitos
   descobrem devagar.
9. **Alta — pool fixo de 120.** `discoverySourceLimit = 120` (`AppComposition.swift:2714`); só idiomas: top-120
   por qualidade entre os 480 primeiros em ordem alfabética; tópicos: união cortada em 4.000 chaves em ordem
   alfabética. Sem amostragem nem rotação.
10. **Alta — sem cota por tópico, região ou idioma.** União seguida de uma ordenação global por qualidade:
    com vários interesses, o de maior pontuação domina.
11. **Média — janela global "128 mais novos"** (`ContentStore.swift:123`), com data de observação como
    fallback: fontes prolíficas e sem data enchem a janela; cursor só anda para trás no tempo.
12. **Média — primeira rodada de aquisição igual a cada abertura**, depois um anel por UUID que ignora
    qualidade (`AcquisitionPlanner.swift:103-109`); `preferUnattempted` só vale na cobertura de fontes
    selecionadas.

## Trabalho existente

O branch `origin/codex/discovery-variety-build-59` (WIP, base `ef5d799` de 26/out, **não está no main**) tem
o plano `docs/superpowers/plans/2026-10-27-feed-variety.md`: v7 "amplitude de fornecedores antes de repetição
de formato", descoberta ampla antes de truncar, coorte pronta antes da primeira publicação, e metas (50
primeiros com ≥40 fornecedores, ≥10 nos 12 primeiros, ≥30 distintos em qualquer janela de 50, nenhum tópico
acima de 40%). O diagnóstico do plano coincide com o desta revisão. No branch, a mudança em
`ReaderDiscoveryPool` até agora só inclui vídeo.

## Recomendação (para o v7 do plano)

1. Fonte como restrição de distância mínima, não desempate: uma fonte não volta antes de
   `min(K, fontes compatíveis disponíveis − 1)` posições; tipo e assunto escolhem **dentro** desse conjunto.
2. Tipo e assunto proporcionais à oferta (distância alvo ∝ 1/participação), não rotação igualitária; um tipo
   raro aparece na proporção em que existe, espalhado.
3. Desempate final por um seed da Edition já persistido (determinístico e reprodutível por Edition, muda entre
   Editions), em vez de UUID.
4. Descoberta: cursor persistido ou ponto de partida semeado, e cota por interesse (round-robin entre
   tópicos/regiões/idiomas) antes do corte por qualidade.
5. Mesma história: preencher `contentClusterID` com uma identidade conservadora (URL canônica/GUID), e
   separar ou deduplicar só por ela.
6. Testes: trocar as fixações de "tipo antes de peso/fonte" por métricas da meta do plano sobre ofertas
   controladas como A–E acima.

Todas as mudanças de ordem exigem versão nova de sequenciamento; v2–v6 continuam valendo para Editions
restauradas.
