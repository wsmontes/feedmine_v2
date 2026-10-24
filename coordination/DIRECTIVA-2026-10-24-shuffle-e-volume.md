# Diretiva do dono — 24/out/2026: imagem nunca se sacrifica; o shuffle é obrigatório e amplo

Repassada pelo OMP ao Codex a pedido do dono. Vale sobre qualquer plano anterior de tolerância/prazo de mídia.

## Palavras do dono (verbatim)

> "imagens sao muito necessarias para os cards. ir mais rapido deixando imagem para tras nao eh solucao. A solucao eh volume, vc ter aquisicao de quantidade de conteudo e cards em um volume muito superior ao necessario, de forma que vc possa passar na frente cards completos e deixar cards mais demorados perdendo lugar na fila, de forma dinamica. Lembrando que o shuffle de conteudo eh mandatorio, e nao significa alternar algumas dezenas de fontes. Quando a filtragem permite, o aplicativo deve circular entre temas, fontes e tipos de conteudo de forma ampla, nao repetindo tipo, tema e fonte com maior distancia possivel na fila."

Consequências diretas:

1. **Publicar carta sem a imagem declarada para ganhar tempo está proibido.** Nenhuma mudança futura de tolerância/prazo pode ter esse efeito.
2. **Volume é a alavanca.** A aquisição e a preparação precisam manter uma oferta muito maior que o consumo, para que uma carta que ainda não está completa simplesmente perca o lugar, dinamicamente, sem virar carta publicada pela metade.
3. **Shuffle amplo é requisito, não enfeite.** Distância máxima possível entre repetições de **tipo de conteúdo**, **tema** e **fonte**. Alternar algumas dezenas de fontes não conta como shuffle.

## Medição do estado atual (OMP, 24/out, fila publicada de 1.425 cartas)

| Dimensão | Distintos | Distância média entre repetições | Mínima |
|---|---|---|---|
| Tipo de mídia | 3 (audio, none, video) | **2,0** | **1** |
| Fonte | 104 | 19 | 2 |

Composição: 936 áudio, 488 sem mídia, 1 vídeo.

Diagnóstico de oferta, da mesma rodada: **7.900 revisões com candidato de imagem no supply contra 573 cartas publicadas**. A oferta sobrava; a fila passava por cima dela. Portanto o problema não é falta de imagem preparada — é a fila não usar o que existe.

## Onde está o código (levantado pelo OMP antes de passar a direção)

- `Sources/FeedMineEditorial/SourceAlternation.swift` — PD-4 e as versões de sequenciamento `apply` (v2), `applyBySupplyShare` (v3), `applyByWeightedSupplyShare` (v4). Edições antigas são restauradas com a própria revisão: **não alterar v2–v4**.
- `Sources/FeedMineEditorial/SelectionDiversity.swift` — `SelectionDiversityContext` / `SelectionDiversityDimension` com `.source`, `.provider`, `.subjects`. Já descarta uma dimensão desconhecida por qualquer candidato, e produz `repetitionKey` usado só como desempate depois do peso.
- `Sources/FeedMineEditorial/Candidate.swift` — **não existe tipo de mídia** no candidato; só `primaryMediaLocator`.
- `Sources/FeedMinePersistence/ContentStore.swift` — classes de mídia (`role`, `mediaClass`, `remoteURL`) existem por revisão; `CandidateRecord` não as carrega.
- `FeedMineApp/FeedMineApp/AppComposition.swift:2967-2975` — a identidade da revisão carrega `sequencingPolicyVersion`; v5 = `shapedSequencing`. Mudança de comportamento exige **versão nova**.

## O que fazer (escopo proposto)

1. Levar o tipo de mídia até quem decide a ordem, com **uma leitura em bloco por janela** (nunca uma consulta por candidato), como `mediaKind` opcional no `Candidate` — desconhecido nunca restringe.
2. Congelar o tipo nas `EditorialDiversityFact` de publicação e acrescentar a dimensão ao comparador.
3. Nova **v6** de sequenciamento: maximizar a distância mínima a ocorrências anteriores de tipo, depois tema, depois fonte, com PD-4 (sem fonte adjacente repetida) ainda como restrição dura; candidato que não pode entrar sem violar PD-4 é retido, nunca publicado adjacente.
4. Volume: garantir que a janela examinada e a oferta preparada fiquem à frente do cursor em profundidade suficiente para a carta incompleta ceder o lugar. Medir com o traço de preparação (`media_preparation_settled`, `ready-image`, `deadline`) e com a fila publicada.

## Restrições invioláveis

- Não alterar `docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md`, `bench/oracle.py` nem `bench/EVALUATOR.sha256`.
- Não publicar carta sem mídia declarada para acelerar.
- Não mexer no alinhamento um-para-um de `LocalPreparedPublication` (`inputs` × `cardIDs`).
- Commits pequenos, cada um com a métrica antes/depois que o justifica.

## Aceitação

- Distância de tipo na fila publicada medida antes/depois; a mínima deve deixar de ser 1 quando a oferta permitir.
- PD-4 continua com zero pares adjacentes da mesma fonte.
- Suítes relevantes verdes, sem relaxar teste de decisão congelada.
