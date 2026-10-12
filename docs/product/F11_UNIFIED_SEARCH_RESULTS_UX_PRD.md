# F11 — Busca unificada: encontrar fontes, histórias e salvos

**Status:** especificação candidata de produto/UX, 2026-10-10; nenhuma validação integral alegada. **Não contém desenho de implementação.**  
**Autoridade transversal:** [North Star](PRODUCT_NORTH_STAR.md), [decisões PD](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md), [mapa de impacto](PRODUCT_SPEC_DEPENDENCIES_F11_F20.md), [inventário V1→V2](../v1-study/UI_TRANSFER_MATRIX.md).  

## 1. Promessa e definição de pronto

Pesquisar uma curiosidade deve ser uma porta de entrada para a internet aberta, não um modo especial que interrompe a leitura. A pessoa precisa entender o que encontrou, por que aquele resultado aparece e para onde vai ao tocar.

**Definição de produto pronto:** **PASS UX11** somente após percorrer os quatro casos com conteúdo real rotulado, capturas de resultado/destino e prova de restauração, sem navegação errada, callbacks obsoletos ou falso resultado; além de B04/B05 onde aplicáveis. O botão pesquisar isoladamente não basta.

## 2. Evidência da V1, estado conhecido na V2 e gargalo

Na V1, `FeedScreen.unifiedSearchPanel` distinguia Sources, conteúdo local e salvos e permitia alterar o escopo da busca. Na V2, a busca como contexto e a barra foram transferidas, mas o inventário registra **painel de resultados unificados não entregue**. Ter busca no contexto não prova que a experiência unificada existe. Estas evidências orientam a especificação, **não certificam** paridade de experiência.

## 3. Contrato observável da experiência

- **R1 — Escopo explícito.** A pessoa distingue buscar **histórias** de buscar **fontes** e de encontrar itens **salvos**. A interface informa quais escopos estão ativos e se o resultado vem de conteúdo local. Ausência de busca remota deve ser honesta; não fingir que o catálogo inteiro foi consultado.

- **R2 — Resposta significativa.** Resultados exibem identidade/tipo e origem suficientes para decidir entre abrir história, visitar fonte ou recuperar salvo. Título e fonte não devem ser confundidos.

- **R3 — Termos previsíveis.** Incluir/remover termos positivos e negativos e mudar escopo produz respostas consistentes e reversíveis; limpar busca tem consequência legível.

- **R4 — Continuidade.** Entrar em resultado e voltar recupera busca e rolagem anterior; cancelar recupera contexto original. Busca não reinicializa à força a história publicada do feed.

- **R5 — Erros e vazio.** Distinguir nenhum resultado no escopo escolhido, indisponibilidade de material pesquisável, termo inválido e operação ainda em andamento, sem spinner interminável nem resultados de outra busca.

- **R6 — Relevância verificável.** Quando resultado vem de catálogo de fontes, seu nome e classificação são verdadeiros; quando vem de um card publicado, a referência leva à ocorrência correta.

## 4. Benchmark adicional (black-box)

**Não modifica a baseline B01–B06.** Usar corpus independente com entradas conhecidas, app real e gestos de usuário; registrar estado inicial, identidade de cada item/destino, versão e observações.

| Caso | Jornada real | Oráculo de aprovação |
| --- | --- | --- |
| **UX11-A — Escopos** | Preparar uma fonte e um artigo com mesmo nome, outro salvo de termo comum; pesquisar e alternar fontes/conteúdo/salvos. | Tipos corretos, contagem/ausência coerente por escopo e nenhum resultado cuja categoria esteja desativada. |
| **UX11-B — Navegação/volta** | Partir do card X no contexto A, pesquisar, abrir uma fonte, retornar, abrir um artigo e cancelar. | Volta à query depois de cada resultado e ao mesmo card/âncora de A ao cancelar; nenhuma troca silenciosa. |
| **UX11-C — Corrida de consultas** | Disparar consultas A e B com tempos de resposta invertidos; cancelar durante retorno de A. | Somente resultados da consulta e do escopo atuais são mostrados; nenhum retorno antigo contamina a UI. |
| **UX11-D — Offline e vazio** | Buscar localmente com rede cortada e depois termo sem correspondência. | Itens locais continuam encontráveis; o vazio explica escopo/disponibilidade e oferece recuperação real. |

Resultado por caso: **PASS / FAIL / NOT_RUN / BLOCKED** com evidência. Uma tela desenhada ou unit test isolado não substitui a jornada.

## 5. Ganchos documentais e limites

Documentos relacionados: [F01 descoberta e catálogo](PRODUCT_AUDIT_10_FRONTS.md); [F07 busca/filtros/contexto](PRODUCT_AUDIT_10_FRONTS.md); [F08 leitura/biblioteca](PRODUCT_AUDIT_10_FRONTS.md); [especificação de contextos e busca](../superpowers/specs/2026-10-09-reader-filters-and-context-identity.md); [F12 destinos de fonte](F12_SOURCE_TAXONOMY_NAVIGATION_UX_PRD.md); [F16 salvos](F16_PERSONAL_LIBRARY_SMART_FEEDS_UX_PRD.md).

**Limite de responsabilidade:** F07 é dono da semântica de filtros/contextos e F01 da cobertura do catálogo; esta frente é dona de **resultados compreensíveis, navegação e recuperação do estado da consulta**. Não demanda busca universal na internet em tempo real.

**Não-objetivos:** reimplementar mecanismos da V1, mover trabalho remoto para renderização, alterar regras de publicação já decididas, ou criar cotas/timers artificiais para o benchmark.

## 6. Pendências de escopo e evidências

A especificação fixa comportamento verificável, mas **não afirma que a UI V2 já o entrega**. A execução deve registrar implementação efetiva, lacunas, falhas e risco residual sem alterar a régua. Se uma diferença aceita na antiga transferência V1→V2 não atende a promessa atual, registrar a decisão de produto de forma explícita, em vez de presumir paridade.

---

## Referências técnicas externas — F11

Estas referências complementam o PRD e não alteram seus critérios de aceitação, nem comprovam funcionalidade já implementada.

**Aplicação:** Interface de resultados por tipo com volta à query e ao feed.

- [HIG Searching](https://developer.apple.com/design/human-interface-guidelines/searching) — Busca compreensível e escopos claros.
- [Scoping a search operation](https://developer.apple.com/documentation/swiftui/scoping-a-search-operation) — Escopos de fontes, artigos e salvos.
- [SQLite FTS5](https://www.sqlite.org/fts5.html) — Snippet/highlight/ranking local.

**Índice integral:** [Pesquisa F01–F20](../research/FeedMine_V2_referencias_F01-F20_2026-10-10.md). Usar os responsáveis/pipelines já existentes; não criar um mecanismo concorrente por causa de uma API ou padrão de interface.

## Pesquisa Apple transversal — F11 (2026-10-10)

Cenários complementares iOS sobre estabilidade, background, offline, integrações e recursos: [F21](F21_IOS_SCENE_SESSION_CONTINUITY_PRD.md) · [F25](F25_SWIFTUI_PRESENTATION_STABILITY_UX_PRD.md). Referência direta: [Apple — ScrollPosition](https://developer.apple.com/documentation/swiftui/scrollposition). Visão geral: [Frentes Apple F21–F27](PRODUCT_AUDIT_APPLE_FRONTS_21_27.md) e [índice Apple](../research/APPLE_IOS_UI_UX_RELIABILITY_2026-10-10.md).

**Precedência:** esta pesquisa não substitui o PRD, decisões de produto, owners existentes ou B01–B06; referências de APIs não comprovam implementação ou teste.

## Ouro V1 relacionado — termos positivos/negativos e Smart Bookmarks (G05/G06)

O [Garimpo V1: 15 oportunidades com prova no código](../v1-study/V1_HIDDEN_GEMS_PRODUCT_MINING_2026-10-10.md) documenta `SearchTerm`/`SearchExpression`, `-termo`, substituição de polaridade e escopos. Os [Briefs de implementação por jornada](V1_GOLD_IMPLEMENTATION_BRIEFS_2026-10-10.md) (S2) exigem resultados Sources/Salvos/Locais e salvar busca reproduzível sem segundo SearchEngine. Não tomar placeholder de texto atual por semântica completa implementada.
