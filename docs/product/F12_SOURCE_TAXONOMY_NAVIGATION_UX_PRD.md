# F12 — Explorar origens, países, regiões e assuntos

**Status:** especificação candidata de produto/UX, 2026-10-10; nenhuma validação integral alegada. **Não contém desenho de implementação.**  
**Autoridade transversal:** [North Star](PRODUCT_NORTH_STAR.md), [decisões PD](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md), [mapa de impacto](PRODUCT_SPEC_DEPENDENCIES_F11_F20.md), [inventário V1→V2](../v1-study/UI_TRANSFER_MATRIX.md).  

## 1. Promessa e definição de pronto

Uma descoberta deve levar a mais descobertas: saber de onde veio uma matéria, entrar naquela fonte, explorar seu assunto ou localidade e voltar. O leitor não precisa saber o que é RSS.

**Definição de produto pronto:** **PASS UX12** requer rotas de ponta a ponta em hierarquia real, fonte individual correta, escolha persistente e retorno ao mesmo card. Confirmar B01/B02/B05 nos cruzamentos; ausência de teste da tela individual significa NOT_RUN, não PASS.

## 2. Evidência da V1, estado conhecido na V2 e gargalo

A V1 oferecia `SourceFeedView`, `TaxonomyBrowseView`, telas de países/regiões e gestão de fontes. A V2 contém navegação de catálogo/nós e dados de Source, mas a matriz registra falta de prova da abertura do feed individual e das rotas de detalhe. O explorador técnico DEBUG-only da V1 não é requisito de UX. Estas evidências orientam a especificação, **não certificam** paridade de experiência.

## 3. Contrato observável da experiência

- **R1 — Origem editorial clara.** Card pode indicar Source/Provider sem confundir quem publicou com onde foi descoberto. Tocar a origem leva ao destino declarado; link externo não se passa por Source do FeedMine.

- **R2 — Exploração progressiva.** Fonte, assunto, país e região são caminhos compreensíveis para encontrar mais conteúdo. Uma Source sem material preparado exibe estado honesto; não inventa matérias.

- **R3 — Orientação espacial.** Nome da seção atual, hierarquia, seleção vigente e retorno são visíveis e compreensíveis, incluindo categorias profundas ou com nomes repetidos.

- **R4 — Gestão opcional.** Seguir/habilitar/desabilitar fonte explícita afeta oportunidades futuras; não é pré-requisito para uso do primeiro feed (F02/B01).

- **R5 — Sem interpretação geográfica falsa.** Local de publicação e assunto geográfico da notícia não são equivalentes. Idiomas da leitura continuam restrição rígida.

- **R6 — Histórico protegido.** Visitar fonte e voltar não substitui a Edition original nem muda posição; alterações no catálogo público não apagam listas pessoais.

## 4. Benchmark adicional (black-box)

**Não modifica a baseline B01–B06.** Usar corpus independente com entradas conhecidas, app real e gestos de usuário; registrar estado inicial, identidade de cada item/destino, versão e observações.

| Caso | Jornada real | Oráculo de aprovação |
| --- | --- | --- |
| **UX12-A — Percurso navegável** | Card da fonte S → detalhes de S → assunto → país/região → lista de fontes → S. | Em cada passo o caminho e entidade são corretos, retornar reconstitui navegação e card inicial. |
| **UX12-B — Feed de fonte** | Abrir Source S contendo itens de S e de outras fontes no banco. | O feed de S contém somente memberships legítimas de S; não há contaminação por outra Source. |
| **UX12-C — Seleção futura** | Habilitar/desabilitar S enquanto um feed contendo S está publicado. | Escolha aparece claramente, altera produção futura e não remove/reordena os cards já publicados. |
| **UX12-D — Falha/catálogo** | Fonte sem conteúdo, país sem seleção ou atualização pública de metadados, inclusive offline. | Mensagens explicam ausência; Source pessoal e navegação anterior permanecem; nenhum título artificial. |

Resultado por caso: **PASS / FAIL / NOT_RUN / BLOCKED** com evidência. Uma tela desenhada ou unit test isolado não substitui a jornada.

## 5. Ganchos documentais e limites

Documentos relacionados: [F01 fontes/catálogo](PRODUCT_AUDIT_10_FRONTS.md); [F02 primeiro contato](F02_DISCOVERY_FEED_ONBOARDING_PRD.md); [F04 variedade editorial](PRODUCT_AUDIT_10_FRONTS.md); [F07 contextos](PRODUCT_AUDIT_10_FRONTS.md); [PD-10 e autoridade do catálogo](PRODUCT_DECISIONS_2026-10-09.md); [revisão de catálogo da V1](../v1-study/04-catalog-editorial.md); [F11 resultados de busca](F11_UNIFIED_SEARCH_RESULTS_UX_PRD.md).

**Limite de responsabilidade:** F01 assegura a exploração progressiva e a autoridade pública do catálogo; F12 especifica **navegação humana no catálogo**. Não reintroduzir uma interface de debug como funcionalidade do leitor.

**Não-objetivos:** reimplementar mecanismos da V1, mover trabalho remoto para renderização, alterar regras de publicação já decididas, ou criar cotas/timers artificiais para o benchmark.

## 6. Pendências de escopo e evidências

A especificação fixa comportamento verificável, mas **não afirma que a UI V2 já o entrega**. A execução deve registrar implementação efetiva, lacunas, falhas e risco residual sem alterar a régua. Se uma diferença aceita na antiga transferência V1→V2 não atende a promessa atual, registrar a decisão de produto de forma explícita, em vez de presumir paridade.
