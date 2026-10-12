# DOC CORRECTION — Auditoria de consistência documental da V2 (2026-10-10)

**Estado:** auditoria documental de `main`, com correções comitadas e verificação de presença dos trechos essenciais; **não** é validação de release nem prova de implementação.  
**Base inspecionada:** árvore Git `dc2bb7d` de 2026-10-10 (antes da rodada), com SHA de blob obtido novamente antes de cada edição. Outros agentes podem editar `main` em paralelo; verificar o `HEAD` atual antes de qualquer implementação.  
**Escopo de leitura:** os **63 documentos Markdown** existentes no repositório na árvore inspecionada (raiz, `docs/architecture`, `docs/product`, `docs/reviews`, `docs/superpowers`, `docs/v1-study` e `FeedMineApp/FeedMineApp/Resources/CATALOG.md`), mais o comentário de status em `Package.swift`, confrontados com o repositório público [wawasoft/feed-repository](https://github.com/wawasoft/feed-repository) e amostras diretas de código/configuração atuais. Não houve build, simulação iOS nem execução B01–B06 nesta auditoria.

## Hierarquia de autoridade para agentes

1. **Intenção e aceitação de produto:** [PRODUCT_NORTH_STAR](../product/PRODUCT_NORTH_STAR.md), [PRODUCT_DECISIONS](../product/PRODUCT_DECISIONS_2026-10-09.md) (especialmente PD-8, PD-9, **PD-10**), [PRODUCT_INVARIANTS](../architecture/PRODUCT_INVARIANTS.md) (INV-16, INV-17, **INV-18**), [PRODUCT_AUDIT_10_FRONTS](../product/PRODUCT_AUDIT_10_FRONTS.md), PRDs F02/F03/F05/F06 e o benchmark B01–B06 **sem diminuição dos critérios**.
2. **Arquitetura vigente:** [ARCHITECTURE](../architecture/ARCHITECTURE.md), mapa de responsabilidades e regras de dependência, confrontados com o **código atual**. Material de design por fases descreve o que foi projetado/construído à época; não reverte decisões de produto posteriores.
3. **Estudos V1, planos, handoffs, relatórios de revisão/teste:** fontes históricas para entender por que algo existe, o que foi tentado e o que **efetivamente foi medido naquele commit**. Não são um backlog imperativo nem um PASS global de lançamento.
4. **Implementação:** inspecionar `main`/commit e testes reais. Nem PRD nem nota de documentação provam feature implementada.

## Erros ou ambiguidades confirmados e corrigidos

| Tipo | Evidência antes da correção | Resolução |
| --- | --- | --- |
| **Autoridade do catálogo** | README, planos e estudos tratavam `catalog-v1` como solução suficiente ou ainda deixavam o update remoto em aberto | Autoridade do catálogo público gerenciado agora explícita em [PD-10](../product/PRODUCT_DECISIONS_2026-10-09.md), [INV-18](../architecture/PRODUCT_INVARIANTS.md), [ARCHITECTURE](../architecture/ARCHITECTURE.md), [CATALOG](../../FeedMineApp/FeedMineApp/Resources/CATALOG.md) e README. |
| **Status factual errado do código** | `ACQUISITION_DESIGN.md` dizia `catalog.sqlite is not implemented`; `PERSISTENCE_DESIGN.md` dizia `Catalog and asset storage remain unimplemented` | Corrigidas afirmações para **baseline de fase antiga**; a V2 possui `LegacyCatalogReader` e `AssetStore`. Sync do repositório público **continua pendente**. |
| **Arquitetura descrita como Phase 0** | `ARCHITECTURE.md` afirmava só dois targets de testes, nenhum pacote externo, publicação mecânica não resolvida, Syndication ainda futura | Corrigido contra `Package.swift`, `PublicationStore`, `PublicationHistory`, `FeedMineSyndication`, e owners existentes. `MODULE_MAP.md` e comentário de `Package.swift` corrigidos. |
| **Planos induziam regressão de produto** | Plano de transferência V1 prescrevia Welcome→Composer→duelos como onboarding obrigatório; plano geral propunha classes novas e gates de aprovação humanos superados | Avisos de prevalência de [F02](../product/F02_DISCOVERY_FEED_ONBOARDING_PRD.md), F05/F06/PD-8/9/10 e de não criar mecanismos paralelos foram adicionados aos planos e handoffs. Histórico mantido. |
| **PASS técnico confundível com PASS de produto** | Relatórios TestFlight/T12 indicavam `PASS WITH PHYSICAL-DEVICE WAIVER`; `IOS_RUN.md` listava `COMPLETE` e identificação antiga da app | Avisos explícitos de que **B06 não aceita waiver de simulador**; B01–B06 inteiros seguem não aprovados. `IOS_RUN.md` distingue configurações Debug e Release e a baseline original. |
| **Transferência V1 confundível com produto F02 atual** | Matriz e port log marcavam como validada a UI antiga de onboarding e catálogo empacotado | Matriz e port log agora apontam o PRD F02 e a exigência posterior de sync de catálogo. Status antigo foi conservado como dado histórico. |
| **Arquitetura de mídia com leitura ambígua** | `MEDIA_DESIGN.md` pode ser interpretado como permissão para converter falha temporária de imagem em text-only | Aviso explícito: PD-5/PD-9/INV-17/F06 prevalecem; candidato pendente sai da fila atual sem perder identidade/supply, jamais reescreve histórico. |
| **Desenho inicial usado como limite permanente** | `IMPLEMENTATION_ORDER`, `FILE_RESPONSIBILITIES`, `CONTINUOUS_FEED_RUNWAY_DESIGN`, `SELECTION_DESIGN` incluem baselines e propostas antigas | Cabeçalhos de correção esclarecem autoridade atual, PD-8 (sem quota fixa de fonte/runway), PD-9 e PD-10. |

## Conteúdo auditado que continua válido como histórico

- Estudos de `docs/v1-study/01..` a `06..` com evidência delimitada por commit e respectivas análises de bugs V1;
- reviews de código/OMP, U1/U2, diagnósticos editoriais R1 e comparações F05/F06 datadas — medições e reproduções não foram apagadas;
- contratos de identidade, canonical supply, persistence/publication/restore, dependências de módulos e boundaries de rede/apresentação — onde tratam fatos de fases anteriores, mantêm valor histórico;
- benchmark B01–B06, PRDs F02/F03/F05/F06 e as decisões recentes foram usados como **réguas**, não rebaixados para adaptar o código.

Não foram reescritos todos os relatórios históricos apenas para substituir termos antigos por nomenclatura nova. **Correções são concentradas onde uma afirmação poderia levar um agente a implementar algo errado hoje**; relatórios seguem com commit/data/contexto originais.

## P0/P1 de implementação identificados, **não corrigidos por esta rodada documental**

1. **Catálogo autoritativo e distribuição (F01/F09/F10):** `wawasoft/feed-repository` possui `manifest.json` de revisão 5 e 77.443 fontes no snapshot inspecionado. O script V2 `scripts/fetch-catalog.sh` ainda baixa `catalog.sqlite` da release **do próprio repositório V2**, derivado da V1; contagem igual não prova identidade de revisão. Implementar release a partir da revisão pública validada e verificação regular (~24h em oportunidade legítima de launch/foreground) não bloqueante, staging/validação SHA-256/tamanho/esquema e ativação atômica. Suportar adição/remoção/edição de URLs e metadados, sem perder `runtime.sqlite` nem fonte pessoal; não prometer execução garantida com app encerrado.
2. **Exploração do catálogo (F01/F05):** `TrustedFeeds.swift` resolve apenas quatro keys no starter set, e a cobertura atual de aquisição observa as fontes selecionadas; falta demonstrar expansão progressiva de todo o catálogo elegível, com idioma como filtro rígido e prioridades adaptativas. Atualização de metadados do catálogo **não substitui** essa exploração runtime.
3. **Runway/admissão (F05/F06):** `AppComposition.swift` mantém `reserveCards: 16`, entre outros limites operacionais; `MediaPrefetcher.presentation(for:)` pode representar como `.textOnly` mídia apenas ainda não preparada, levando à publicação indevida. Não fazer um simples filtro pós-seleção que perca o candidato do cursor/alternância; reparar no pipeline existente.
4. **Prova do produto (F01–F10):** B01–B06 precisam ser executados completos, com B03 real de 30 minutos e B06 em iPhone físico. `swift test`, TestFlight técnico, screenshots parciais e 4 minutos/135 cards não satisfazem esses gates.

## Regra de colaboração e validação de futuras correções

- Commits desta rodada usam **`DOC CORRECTION:`** no assunto de forma visível para agentes em paralelo; não houve commit de alteração de lógica de produção. `Package.swift` recebeu apenas uma correção de comentário de status, sem mudança na definição do pacote.
- Não sobrescrever conteúdo modificado em paralelo: reler SHA do arquivo antes de gravar, deixar o GitHub rejeitar gravações concorrentes e conciliar diferenças caso necessário.
- Quando um agente implementar PD-10/F01/F05, atualizar a documentação **na mesma alteração** com testes e evidência factual. Não transformar requisito em PASS sem execução real.
- O canal público é fonte de **metadados gerenciados**, não de artigos. Artigos são buscados nas fontes externas; o catálogo local é bootstrap e snapshot atualizado, dados pessoais e publicação têm autoridade local durável distinta.
