# F14 — Abrir artigos, ler e retornar sem perder o feed

**Status:** especificação de produto/UX candidata, 2026-10-10. Não é plano técnico nem evidência de execução.  
**Autoridades:** [North Star](PRODUCT_NORTH_STAR.md), [decisões PD](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md), [mapa de dependências F11–F20](PRODUCT_SPEC_DEPENDENCIES_F11_F20.md) e [inventário V1→V2](../v1-study/UI_TRANSFER_MATRIX.md).  

## 1. Promessa

O gesto simples de tocar uma história deve oferecer uma experiência de consumo real e saída previsível. O FeedMine não é um catálogo de cards que abre destinos errados; abrir, ler, encontrar falhas e voltar precisam fazer sentido sem destruir o que estava sendo lido.

**Produto pronto:** A jornada A–D funciona em interface real com artigo de origem verificável, zero destinação errada/dead tap/perda de posição, e todas as falhas têm saída sem destruir o feed. Cruzamento obrigatório com B04/B05.

## 2. Evidência e gargalo V1→V2

A V1 tinha leitor próprio com WKWebView, barra de carregamento e ação de Safari. Na V2, `InAppBrowser` usa SFSafariViewController; a mudança foi aceita na transferência. A matriz não registra prova de um teste de UI abrindo artigo real e voltando ao card. A decisão de usar SafariViewController pode permanecer: o benchmark não exige copiar o chrome antigo. A prova parcial de componentes não equivale a aprovação da experiência completa.

## 3. Requisitos de comportamento (não de arquitetura)

- **R1 — Destino inequívoco:** artigo/link publicado abre o destino do card/ação, não um item parecido nem URL obtida de outro contexto; quando a ação não existe, não mostrar affordance falsa.

- **R2 — Consumo efetivo:** abertura produz conteúdo utilizável quando fonte está disponível. Paywall, erro remoto, site incompatível, ausência de link e redirecionamento são identificados honestamente; não chamar uma página inacessível de leitura concluída.

- **R3 — Controle claro:** distinguir 'fechar leitor e voltar ao FeedMine' de 'abrir externamente'. Estado de carregamento/erro não bloqueia retorno.

- **R4 — Retorno sagrado:** a saída restaura o card anterior, a posição e o contexto, inclusive se houver aquisição, imagem pronta ou refresh em background durante a leitura.

- **R5 — Biblioteca e links:** artigo salvo reabre a ocorrência correta; links externos que mudaram desde a publicação não reescrevem texto/ordem do card original.

- **R6 — Áudio coexistente:** mini-player em reprodução mantém seu controle onde a experiência o oferecer; abrir e fechar artigo não pausa ou reinicia silenciosamente o feed.

## 4. Benchmark UX14 — oráculo externo

| Caso | Jornada observável com dados reais rotulados | Aceite verificável |
| --- | --- | --- |
| **UX14-A** | Abrir artigo real a partir do card X, navegar nele, fechar e abrir em navegador externo. | Destino correto, controle de saída visível, mesma âncora X e ausência de rerender desordenado. |
| **UX14-B** | Enquanto o artigo está aberto, admitir notícias/imagens novas; depois fechar. | Nenhuma atualização silenciosa move a edição/posição ao retornar (B04/B05). |
| **UX14-C** | Abrir artigo cujo URL está indisponível ou foi redirecionado. | Falha ou redirecionamento compreensível, retorno garantido, sem fingir sucesso. |
| **UX14-D** | Salvar card, reabrir pela biblioteca e voltar ao destino de origem. | Abrir a ocorrência pretendida e recuperar navegação/biblioteca sem mistura. |

Registre vídeo/captura, identidade do conteúdo, estado anterior e posterior, versão do app/dispositivo, e **PASS / FAIL / NOT_RUN / BLOCKED** por caso. Os gates [B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md) não são reduzidos nem substituídos. O benchmark não pressupõe quantidade fixa de páginas, tempos de retry ou algoritmo especial.

## 5. Dependências documentais e escopo

[F03 — integridade/consumibilidade](F03_ACQUISITION_FRESHNESS_STORY_INTEGRITY_PRD.md); [F06 — geometria e mídia publicada](F06_SACRED_FEED_CARD_READINESS_PRD.md); [F08 — ações/biblioteca](PRODUCT_AUDIT_10_FRONTS.md); [F09 — restore](PRODUCT_AUDIT_10_FRONTS.md); [F15 — áudio](F15_PODCAST_PLAYBACK_CONTINUITY_UX_PRD.md).

**Fronteira:** F03 decide **se** existe leitura válida; F08 controla a ação e o estado durável; F14 mede **se a pessoa de fato leu/voltou**. Não prescreve trocar SafariViewController por WKWebView.

**Não-objetivos:** copiar controles da V1 sem necessidade, promover componente existente a prova de UX, ou reescrever história já publicada.

## 6. Estado de aceitação

**NOT_RUN** como jornada UX14 integral. Relatórios de código/testes da matriz V1→V2 são evidência preliminar, não um PASS de produto. Toda divergência de escopo deve ser registrada explicitamente antes de ofertar o controle ao usuário.

---

## Referências técnicas externas — F14

Estas referências complementam o PRD e não alteram seus critérios de aceitação, nem comprovam funcionalidade já implementada.

**Aplicação:** Abrir destino certo e retornar à mesma história sem perda da posição.

- [SFSafariViewController](https://developer.apple.com/documentation/safariservices/sfsafariviewcontroller/) — Navegação web in-app.
- [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview) — Controle explícito quando necessário.
- [NavigationStack](https://developer.apple.com/documentation/swiftui/navigationstack) — Histórico de navegação.

**Índice integral:** [Pesquisa F01–F20](../research/FeedMine_V2_referencias_F01-F20_2026-10-10.md). Usar os responsáveis/pipelines já existentes; não criar um mecanismo concorrente por causa de uma API ou padrão de interface.

## Pesquisa Apple transversal — F14 (2026-10-10)

Cenários complementares iOS sobre estabilidade, background, offline, integrações e recursos: [F21](F21_IOS_SCENE_SESSION_CONTINUITY_PRD.md) · [F26](F26_IOS_SYSTEM_INTEGRATIONS_PRD.md). Referência direta: [Apple — SFSafariViewController](https://developer.apple.com/documentation/safariservices/sfsafariviewcontroller/). Visão geral: [Frentes Apple F21–F27](PRODUCT_AUDIT_APPLE_FRONTS_21_27.md) e [índice Apple](../research/APPLE_IOS_UI_UX_RELIABILITY_2026-10-10.md).

**Precedência:** esta pesquisa não substitui o PRD, decisões de produto, owners existentes ou B01–B06; referências de APIs não comprovam implementação ou teste.
