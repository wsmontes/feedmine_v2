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

---

## Registro de execução — 2026-10-25

**UX12-B, fatia da linha da taxonomia.** Implementado: a linha de uma fonte abre o feed **daquela** fonte quando ela
faz parte da seleção do leitor (`NodeSourceRowView.onOpen`, `node-source-<chave>`), com o `Toggle` em área própria e
sem navegação acidental; o host adota a seleção pendente e resolve a chave pelo `TrustedFeed` do próprio owner. Uma
fonte fora da seleção não desenha o controle e não navega para o feed principal — habilitar continua sendo o ato do
toggle (R4), e o contexto de fonte única fora da seleção não existe no modelo de sessão (registrado como lacuna).
O oráculo de UX12-B (só memberships de S) permanece provado no provider editorial; a rota tem teste integrado no app.
A fonte catalogada **não selecionada** também abre (identidade canônica pelo owner; sessão mantém os feeds do
leitor, então nada é habilitado; só as memberships locais dela são elegíveis), e o relançamento conserva esse
contexto. No caminho, o modo degradado do catálogo foi corrigido: sem snapshot verificado, a superfície de Fontes
agora lê o **catálogo empacotado** que a composição já servia, em vez de declarar o catálogo indisponível
(antes/depois em `docs/reviews/evidence/2026-10-25-f12-source-feed/`).
A jornada XCUITest completa está preservada e **skipada com medição**: neste device a árvore de acessibilidade do
sheet não expõe as linhas mesmo com elas desenhadas (captura no diretório de evidência). Evidência e limites:
`docs/reviews/evidence/2026-10-25-f12-source-feed/README.md`. UX12-A/C/D seguem sem prova nesta rodada.

## Referências técnicas externas — F12

Estas referências complementam o PRD e não alteram seus critérios de aceitação, nem comprovam funcionalidade já implementada.

**Aplicação:** Navegação card→Source→país/taxonomia com retorno correto.

- [HIG Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) — Hierarquia legível.
- [Understanding NavigationStack](https://developer.apple.com/documentation/swiftui/understanding-the-navigation-stack) — Rotas estáveis.
- [HIG Collections](https://developer.apple.com/design/human-interface-guidelines/collections) — Quando usar visualização em grade.

**Índice integral:** [Pesquisa F01–F20](../research/FeedMine_V2_referencias_F01-F20_2026-10-10.md). Usar os responsáveis/pipelines já existentes; não criar um mecanismo concorrente por causa de uma API ou padrão de interface.

## Pesquisa Apple transversal — F12 (2026-10-10)

Cenários complementares iOS sobre estabilidade, background, offline, integrações e recursos: [F21](F21_IOS_SCENE_SESSION_CONTINUITY_PRD.md) · [F26](F26_IOS_SYSTEM_INTEGRATIONS_PRD.md). Referência direta: [Apple — SwiftUI State Restoration](https://developer.apple.com/documentation/swiftui/restoring-your-app-s-state-with-swiftui). Visão geral: [Frentes Apple F21–F27](PRODUCT_AUDIT_APPLE_FRONTS_21_27.md) e [índice Apple](../research/APPLE_IOS_UI_UX_RELIABILITY_2026-10-10.md).

**Precedência:** esta pesquisa não substitui o PRD, decisões de produto, owners existentes ou B01–B06; referências de APIs não comprovam implementação ou teste.

## Ouro V1 relacionado — abrir uma Source, não só ativar um toggle (G01/G08/G09)

No [Garimpo V1: 15 oportunidades com prova no código](../v1-study/V1_HIDDEN_GEMS_PRODUCT_MINING_2026-10-10.md) há evidência de acesso explícito a Source dormente, sua história local, contrato de arquivo limitado do RSS e ações do menu do card. Os [Briefs de implementação por jornada](V1_GOLD_IMPLEMENTATION_BRIEFS_2026-10-10.md) (S1) definem a navegação e retorno, sem criar loader de imagens na View ou ativar a Source automaticamente. Catálogo/editorial segue no repo público e na PD-10.
