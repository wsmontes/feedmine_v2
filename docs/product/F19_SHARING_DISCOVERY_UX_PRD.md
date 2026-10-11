# F19 — Compartilhar histórias sem perder contexto e atribuição

**Status:** especificação de produto/UX candidata, 2026-10-10. Não é implementação, prova executada ou autorização para substituir B01–B06.  
**Referências comuns:** [norte](PRODUCT_NORTH_STAR.md), [decisões](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [benchmark vigente](DISCOVERY_ACCEPTANCE_BENCHMARK.md), [mapa de impactos](PRODUCT_SPEC_DEPENDENCIES_F11_F20.md), [matriz V1→V2](../v1-study/UI_TRANSFER_MATRIX.md).

## 1. Promessa e o que é produto pronto

Compartilhar deve transmitir a descoberta certa — título, origem e destino correto — por um gesto compreensível. Uma imagem bonita é opcional; um link errado ou uma ação que não responde nunca é aceitável.

**Pronto significa:** UX19-A/B obrigatórios se copy/share forem expostos; C/D somente se recursos opcionais forem publicamente oferecidos. Nenhum controle morto, atribuição errada ou alteração de feed; B04 continua exigido.

## 2. Evidência V1/V2 e gargalo

Na V1 havia `ShareCardImageView` e `StatsShareCard`, além de copiar link e compartilhar. A V2 trouxe payload de link/atribuição e ações de cópia/partilha em graus distintos, mas imagem compartilhável e cartão de estatísticas foram registrados como diferenças aceitas, **não funcionalidades entregues**. A especificação não presume retorno desses recursos.

## 3. Contrato de experiência

- **R1 — Link correto:** copiar/compartilhar o card utiliza o destino realmente associado à publicação; título e nome da fonte vêm da atribuição verdadeira e não de uma query atual.

- **R2 — Affordances honestas:** cada ação visível faz algo distinto e alcançável; ausência de destino compartilhável não produz botão falso ou link inventado.

- **R3 — Compartilhar sem deslocar:** abrir o share sheet, cancelar ou concluir nunca reordena a Edition, muda o card selecionado nem interrompe o player desnecessariamente.

- **R4 — Opcional imagem de card:** se oferecida, o artefato usa texto/atribuição/visual publicados e não faz nova aquisição ou substituição de imagem no card visível.

- **R5 — Privacidade nas estatísticas:** caso se decida oferecer cartão de estatísticas pessoais, o usuário vê seu conteúdo antes de compartilhar, escolhe conscientemente e nenhuma telemetria pessoal é enviada por padrão.

- **R6 — Feedback útil:** cópia, impossibilidade, cancelamento e envio distinguem-se com sinais adequados; não exibir 'compartilhado' somente por ter aberto o seletor de destino.

## 4. Benchmark UX19 (provas black-box)

| Caso | Cenário e gesto reais | Oráculo de aprovação |
| --- | --- | --- |
| **UX19-A** | Copiar URL de um artigo com fonte A e URL de uma fonte B e comparar com destino da ocorrência. | Identidades e destinos certos, texto da atribuição correto. |
| **UX19-B** | Abrir share sheet de artigo e podcast; cancelar e voltar. | Feed permanece no card/âncora, nenhum duplo disparo ou confirmação falsa. |
| **UX19-C (condicional)** | Se arte de card for oferecida, compartilhar artigo text-only e com mídia offline. | A imagem tem título/atribuição corretos e não altera apresentação original. |
| **UX19-D (condicional)** | Se stats forem oferecidas, inspecionar preview e compartilhar/cancelar. | Somente métricas exibidas e autorizadas seguem; não há divulgação automática. |

Executar com dados/versão/dispositivo identificados, evidências de gestos reais, capturas e identidades de entrada/saída. Cada caso recebe **PASS / FAIL / NOT_RUN / BLOCKED** e motivo. Os gates B01–B06 não são substituídos nem reduzidos; percentuais e durações do benchmark vigente não são convertidos em cotas de produção.

## 5. Documentos conectados e limites

[F03 qualidade do destino](F03_ACQUISITION_FRESHNESS_STORY_INTEGRITY_PRD.md); [F06 imutabilidade do card](F06_SACRED_FEED_CARD_READINESS_PRD.md); [F08 ações](PRODUCT_AUDIT_10_FRONTS.md); [F17 visual e textos](F17_LOCALIZATION_APPEARANCE_ACCESSIBILITY_UX_PRD.md); [matriz V1→V2](../v1-study/UI_TRANSFER_MATRIX.md).

**Fronteira:** F08 garante a execução da ação; F19 especifica **qual payload faz sentido, qual feedback dizer e o que não expor**. Não impõe share-as-image ou stats como requisito de release sem decisão explícita.

**Não-objetivos:** copiar automaticamente a V1, exigir conta/servidor próprio, criar UI com ações mortas, quebrar o prefixo publicado ou definir soluções técnicas nesta etapa.

## 6. Estado e conflitos em aberto

**Jornada UX19 integral: NOT_RUN.** O que existe nos componentes/testes do repositório é evidência de capacidade, não certificação desta promessa. Diferenças deliberadas da V1 devem ser aceitas ou revertidas **por decisão de produto explícita** e não por presunção de paridade.

---

## Referências técnicas externas — F19

Estas referências complementam o PRD e não alteram seus critérios de aceitação, nem comprovam funcionalidade já implementada.

**Aplicação:** Compartilhar texto, link e atribuição da publicação congelada.

- [ShareLink](https://developer.apple.com/documentation/swiftui/sharelink) — Compartilhamento do sistema.
- [LPLinkMetadata](https://developer.apple.com/documentation/linkpresentation/lplinkmetadata) — Rich preview local.
- [HIG Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) — Confirmações discretas e acessíveis.

**Índice integral:** [Pesquisa F01–F20](../research/FeedMine_V2_referencias_F01-F20_2026-10-10.md). Usar os responsáveis/pipelines já existentes; não criar um mecanismo concorrente por causa de uma API ou padrão de interface.

## Pesquisa Apple transversal — F19 (2026-10-10)

Cenários de plataforma complementares: [F26](F26_IOS_SYSTEM_INTEGRATIONS_PRD.md). Fonte primária: [Apple — ShareLink](https://developer.apple.com/documentation/swiftui/sharelink). Consultar [matriz Apple F21–F27](PRODUCT_AUDIT_APPLE_FRONTS_21_27.md) e [índice de documentação Apple](../research/APPLE_IOS_UI_UX_RELIABILITY_2026-10-10.md).

Estas referências não modificam este PRD, não autorizam outro engine/store e não comprovam os benchmarks B01–B06.
