# Garimpo V1 → V2 — ouro de produto com evidência no código

**Data-base:** 2026-10-10. **V1 inspecionada:** [`feedmine-dev` @ `b5c2f59c5`](https://github.com/wsmontes/feedmine-dev/tree/b5c2f59c55babb672c81dd978d201f98c5909934). **V2 comparada:** [`feedmine_v2` @ `71bd2e03c`](https://github.com/wsmontes/feedmine_v2/tree/71bd2e03c6174cde258111e258f29e92b613c539). **Estado:** análise de código e documentação, **não** testes de interface executados nem revisão de todas as linhas do repositório.

**Objetivo:** resgatar valor comportamental da V1 para a V2 sem transportar mecanismo antigo, arquitetura concorrente, timers arbitrários, engessamento por lotes, restore quebradiço nem UI que dispara rede. **Nenhuma nova frente F28+ foi criada:** os achados cabem nas responsabilidades F01–F27 já existentes.

## Como interpretar a evidência

- **V1 — código executável:** View/service/model contém comportamento observável, mas presença de símbolo não prova que o fluxo funcionava sem bugs.
- **V1 — contrato editorial/doc:** documento ou artefato de curadoria descreve regra; seu funcionamento histórico não foi medido por este garimpo.
- **V2 — parte existente:** classes, endpoints e enum de ações podem estar presentes; a lacuna indicada é uma jornada/semântica **a validar**, não ausência automaticamente comprovada.
- **Prioridade P0/P1/P2:** P0 protege o North Star e catálogo; P1 tem benefício alto e depende de gates; P2 é opcional, só após estabilidade. A nomenclatura não muda os gates **B01–B06**.
- **Implementar significa:** melhorar owners atuais, não copiar `FeedStore`, `FeedLoader`, `Reservoir`, `CachedAsyncImage`, `WhatsNewManager` ou scripts editoriais para dentro do aplicativo.

**Autoridade:** [North Star](../product/PRODUCT_NORTH_STAR.md) · [Decisões 2026-10-09](../product/PRODUCT_DECISIONS_2026-10-09.md) · [Invariantes](../architecture/PRODUCT_INVARIANTS.md) · [B01–B06](../product/DISCOVERY_ACCEPTANCE_BENCHMARK.md) · [F01–F20](../product/PRODUCT_AUDIT_10_FRONTS.md) · [F11–F20](../product/PRODUCT_AUDIT_FRONTS_11_20.md) · [F21–F27](../product/PRODUCT_AUDIT_APPLE_FRONTS_21_27.md).

## Inventário com pontuação editorial

| ID | Ouro encontrado | Prioridade | Aplicação Fxx | Interpretação correta |
|---|---|---|---|---|
| [G01](#g01) | Abrir a fonte de verdade, mesmo dormente | P0/P1 | F01, F03, F05, F12, F14, F21 | Implementar jornada existente |
| [G02](#g02) | Duelo opcional com histórias reais: gosto explícito e desfazer | P1 | F02, F04, F06, F16 | Aproveitar a ideia, nunca o funil antigo |
| [G03](#g03) | Capô explicável: aprendizado verificável e controle de aprender | P1 | F02, F04, F16, F17 | Lacuna específica comprovada |
| [G04](#g04) | Mistura editorial de tipos de fontes sem confundir qualidade de fetch | P1 | F03, F04, F05, F12 | Refinar critérios no owner editorial |
| [G05](#g05) | Busca por chips positivos e negativos, com escopos legíveis | P1 | F07, F11, F13 | Concluir UI + semântica, não novo engine |
| [G06](#g06) | Smart Bookmark de uma pesquisa realmente reproduzível | P1 | F07, F11, F16 | Fechar o ciclo UI→consulta→biblioteca |
| [G07](#g07) | Lentes visíveis que explicam e deixam desfazer cada filtro | P1 | F07, F13, F17, F25 | UX microinteração de alto valor |
| [G08](#g08) | Atalho contextual: fonte, coleção e cópia a partir do card | P1 | F08, F12, F14, F16, F26 | End-to-end de ações já modeladas |
| [G09](#g09) | Um catálogo com proveniência, quarentena e uma casa editorial | P0 | F01, F03, F09, F12 | Recuperar disciplina de publicação externa |
| [G10](#g10) | Descoberta geográfica multifuente na cadeia de curadoria | P2 | F01, F03, F12 | Ferramenta editorial, não runtime do app |
| [G11](#g11) | Compartilhar um card visual preparado e fiel | P2 | F06, F19, F26 | Produto opcional, paridade visual não automática |
| [G12](#g12) | Estatísticas pessoais locais compartilháveis | P2 | F08, F17, F19 | Experimento discreto e consentido |
| [G13](#g13) | Design com personalidade, mas geometria invariável | P2 | F06, F17, F25 | Portar expressão visual com limite |
| [G14](#g14) | Preferências negativas: distinguir bloqueio durável de lente casual | P1 | F07, F13, F20 | Refinar UX existente |
| [G15](#g15) | Sinais honestos de retorno e novidade, sem feed paralelo | P1 | F05, F06, F20, F23 | Recuperar intenção e rejeitar mecanismo |

## Achados, provas e decisão

<a id="g01"></a>

### G01 — Abrir a fonte de verdade, mesmo dormente

**Prioridade:** P0/P1. **Frentes atuais:** F01, F03, F05, F12, F14, F21. **Tipo:** Implementar jornada existente.

**Prova V1:** [V1 `source-experience.md` L37–54](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/editorial/feed-curation/source-experience.md#L37-L54) · [V1 `FeedItemView.swift` L79–96](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedItemView.swift#L79-L96).

**Checagem V2:** [V2 `ReaderCardAction.swift` L8–16](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineUI/Cards/ReaderCardAction.swift#L8-L16) · [V2 `SourceManagementView.swift` L47–96](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineUI/Sources/SourceManagementView.swift#L47-L96).

**O que o repositório mostra:** A V1 distinguia Source View de seleção automática; explicitamente abrir uma fonte podia recuperar conteúdo da origem mesmo desativada/dormente, mesclar o endpoint corrente com história local e não ativá-la para background futuro. O contrato reconhecia que feed não é arquivo histórico universal.

**Diferença ou incerteza V2:** V2 possui ação tipada `.viewSource` e navegação de catálogo, mas a existência de botão/row não comprova jornada de histórico e refetch explícito; os PRDs F12/F14 exigem teste de destino.

**Adaptar na V2:** Abertura explícita usa identidade canônica da Source, projection local pronta primeiro e pedido de aquisição prioritário *somente para essa fonte* pelo Coordinator existente, sem mexer no feed principal. Se rede falhar, manter história local e informar limite temporal do feed; nunca ativar assinatura automaticamente.

**Oráculo de produto G01:** Abrir Source desabilitada/dormente de um card, offline e online; verificar posts do endpoint + retenção local, sem indicar arquivo completo inexistente. Voltar ao mesmo PublicationCardID; verificar não mudança da seleção automática nem download em View.

**Não copiar:** Não transportar SourceFeedView com query SQLite e `CachedAsyncImage` direto na tela nem criar segundo runtime ou nova política de retenção baseada em 30 dias fixos.

<a id="g02"></a>

### G02 — Duelo opcional com histórias reais: gosto explícito e desfazer

**Prioridade:** P1. **Frentes atuais:** F02, F04, F06, F16. **Tipo:** Aproveitar a ideia, nunca o funil antigo.

**Prova V1:** [V1 `StoryDuelScene.swift` L3–110](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/Onboarding/StoryDuelScene.swift#L3-L110) · [V1 `CuratedPreferenceEngine.swift` L706–786](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/CuratedPreferenceEngine.swift#L706-L786) · [V1 `CuratedPreferenceEngine.swift` L1022–1053](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/CuratedPreferenceEngine.swift#L1022-L1053).

**Checagem V2:** [V2 `FeedRecipeDefinition.swift` L98–117](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineDomain/FeedRecipeDefinition.swift#L98-L117) · [V2 `CuratedFeedCoordinator.swift` L23–51](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineComposition/CuratedFeedCoordinator.swift#L23-L51).

**O que o repositório mostra:** V1 oferecia pares de histórias com escolha de lado, ambas, nenhuma, skip e Undo. A preferência dependia de traços distintivos e a ação Skip não ensinava. O estado de Undo restaurava perfil e pares usados.

**Diferença ou incerteza V2:** V2 já tem `FeedRecipeDefinition` e CuratedFeedCoordinator, mas o contrato F02 atual rejeita o funil obrigatório Welcome→Composer; um teste do onboarding antigo não prova boa primeira experiência.

**Adaptar na V2:** Reaproveitar como convite **opcional** dentro ou a partir do feed real, quando houver dois candidatos legítimos e prontos. Escolhas afetam somente seleção futura de feed curado, com undo real e opção de pular sem custo. Exibir retorno ao feed sem alterar a Edition publicada.

**Oráculo de produto G02:** Abrir feed real sem responder pergunta; encontrar convite opcional, votar ambos/nenhum/esquerda, desfazer e comparar a receita antes/depois. Skip mantém preferências. Permanecer offline com candidatos locais e abandonar sem bloquear scroll.

**Não copiar:** Não copiar minimumAnswers/maximumAnswers, progresso de ‘confiança’ fabricado, prompts que interrompem scroll nem cards escolhidos antes da barreira de mídia.

<a id="g03"></a>

### G03 — Capô explicável: aprendizado verificável e controle de aprender

**Prioridade:** P1. **Frentes atuais:** F02, F04, F16, F17. **Tipo:** Lacuna específica comprovada.

**Prova V1:** [V1 `CuratedPreferenceEngine.swift` L788–817](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/CuratedPreferenceEngine.swift#L788-L817) · [V1 `CuratedFeedInspectorView.swift` L3–16](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/CuratedFeedInspectorView.swift#L3-L16) · [V1 `CuratedFeedInspectorView.swift` L222–277](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/CuratedFeedInspectorView.swift#L222-L277).

**Checagem V2:** [V2 `CuratedFeedInspectorView.swift` L1–22](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineUI/Onboarding/CuratedFeedInspectorView.swift#L1-L22) · [V2 `FeedRecipeDefinition.swift` L209–241](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineDomain/FeedRecipeDefinition.swift#L209-L241).

**O que o repositório mostra:** A V1 tinha evidência de perguntas/opções e aberturas explícitas no perfil; abrir um artigo voluntariamente recebia influência menor que escolher num duelo. Não se aprendia de visibilidade/scroll. O capô mostrava evidência e permitia desligar aprendizado.

**Diferença ou incerteza V2:** V2 tem inspector e resumo de respostas explícitas; comentário na própria UI diz que **não dispõe de histórico de evidências aprendido** e portanto não deve inventar confiança. Este é ouro faltante, não uma tela ausente inteira.

**Adaptar na V2:** Adotar apenas eventos intencionais que já atravessam InteractionCoordinator; quando produto oferecer ‘aprender com minhas aberturas’, registrar evidência mínima, consentida e revisável nos dados pessoais existentes; ensinar sobre *origens e temas*, não traços de identidade. No capô mostrar ‘o que escolhi’ separado de ‘o que aprendeu’, permitir desativar e limpar esses efeitos.

**Oráculo de produto G03:** Scroll de 50 cards sem abrir nenhum não muda perfil; abrir uma história muda somente o perfil que autorizou aprendizado; desligar aprender congela pesos; reabrir offline exibe evidência disponível; editar a receita não reordena conteúdo já publicado.

**Não copiar:** Não migrar pontuações arbitrárias da V1 nem reconstruir o engine de duelos; não criar histórico artificial para justificativas. Qualquer proposta de sinais automáticos exige decisão explícita.

<a id="g04"></a>

### G04 — Mistura editorial de tipos de fontes sem confundir qualidade de fetch

**Prioridade:** P1. **Frentes atuais:** F03, F04, F05, F12. **Tipo:** Refinar critérios no owner editorial.

**Prova V1:** [V1 `CuratedPreferenceEngine.swift` L71–160](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/CuratedPreferenceEngine.swift#L71-L160) · [V1 `EditorialBalanceControl.swift` L3–66](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/Onboarding/EditorialBalanceControl.swift#L3-L66).

**Checagem V2:** [V2 `FeedRecipeDefinition.swift` L98–117](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineDomain/FeedRecipeDefinition.swift#L98-L117) · [V2 `SelectionEngine.swift` L68–103](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineEditorial/SelectionEngine.swift#L68-L103).

**O que o repositório mostra:** A V1 diferenciava reconhecidas/institucionais/especialistas/comerciais/agregadoras de sinais técnicos de liveness e oferecia equilíbrio editorial Less/Balanced/More por estilo.

**Diferença ou incerteza V2:** A V2 tem pesos editoriais e seleção por fonte, mas não se pode inferir diversidade editorial de pesos apenas; a medida de diversidade requer corpus e prova de distribuição.

**Adaptar na V2:** Definir atributos editoriais de Source separados de `fetchHealth` e `recency`; expor controle explícito de mistura quando a taxonomia suportar o fato. Testar variedade por Providers/temas e alcance do catálogo sem excluir silenciosamente autores pequenos.

**Oráculo de produto G04:** Cenário com pesquisadores, mídia pública, independentes, comerciais e agregadores; ajustar balanço e observar tendência na cauda nova, sem alterar o histórico, com nenhuma fonte saudável eliminada por um rótulo desconhecido.

**Não copiar:** Não copiar lista rígida de ‘marcas confiáveis’, blacklist editorial opaca, score global novo, nem usar saúde HTTP como qualidade intelectual.

<a id="g05"></a>

### G05 — Busca por chips positivos e negativos, com escopos legíveis

**Prioridade:** P1. **Frentes atuais:** F07, F11, F13. **Tipo:** Concluir UI + semântica, não novo engine.

**Prova V1:** [V1 `SearchEngine.swift` L4–109](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/SearchEngine.swift#L4-L109) · [V1 `FeedScreen.swift` L1176–1203](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedScreen.swift#L1176-L1203).

**Checagem V2:** [V2 `ReaderShell.swift` L80–102](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineUI/Reader/ReaderShell.swift#L80-L102) · [V2 `ReaderFilter.swift` L122–129](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineDomain/ReaderFilter.swift#L122-L129).

**O que o repositório mostra:** Busca V1 acrescentava tokens, aceitava `-term` como exclusão e permitia inverter polaridade sem duplicar; ignorava query apenas negativa para não disparar busca ilimitada. Havia seleção de Sources/Contents e resultados separados.

**Diferença ou incerteza V2:** A V2 apresenta placeholder ‘-termo’ na barra e enum de escopo, mas um TextField de uma submissão não comprova edição incremental, polaridade, nem resultados Sources/Salvos/Local.

**Adaptar na V2:** Usar ContextKey/ReaderSearchScope já existentes e apresentação explícita de chips, abrangência e estado parcial por resultado. Negação de termo é predicado editorial/SQL local, não filtro global durável; manter restrições da consulta separadas do F13.

**Oráculo de produto G05:** Pesquisar `astronomia`, acrescentar `-astrologia`, substituir por positivo, remover chip; resultados anteriores não ‘vazam’; query só negativa não provoca aquisição indiscriminada; abrir Source/salvo e voltar à busca sem perder anchor.

**Não copiar:** Não criar SearchEngine paralelo, polling de rede por digitação, nem afirmar resultados remotos que nunca foram buscados.

<a id="g06"></a>

### G06 — Smart Bookmark de uma pesquisa realmente reproduzível

**Prioridade:** P1. **Frentes atuais:** F07, F11, F16. **Tipo:** Fechar o ciclo UI→consulta→biblioteca.

**Prova V1:** [V1 `FeedScreen.swift` L1066–1110](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedScreen.swift#L1066-L1110) · [V1 `UserStateStore.swift` L620–665](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/UserStateStore.swift#L620-L665).

**Checagem V2:** [V2 `ReaderNavigation.swift` L57–78](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineUI/Reader/ReaderNavigation.swift#L57-L78) · [V2 `ReaderLibrary.swift` L47–86](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineDomain/ReaderLibrary.swift#L47-L86).

**O que o repositório mostra:** Salvar pesquisa como Smart Bookmark guardava expressão/escopo e virava preset nomeado, distinto de bookmark estático. Banco mantinha metadados de smart feed.

**Diferença ou incerteza V2:** A V2 possui identidade tipada de Smart Feed e menu de criar, mas testes de backend não garantem gesto completo da busca, interpretação de termos excluídos e resultados navegáveis.

**Adaptar na V2:** Uma busca válida oferece Salvar como Smart Feed, prévia do nome/escopo e destino na biblioteca; persistir identidade/contexto único já existente. Ao reabrir, consultar o índice local e demandar futuro supply pela mesma política, sem cache/scheduler próprio.

**Oráculo de produto G06:** Criar feed `economia -cripto` em escopo Sources/Content, fechar/reabrir offline; obter mesmos filtros e resultados locais. Alterar o Smart Feed sem alterar o histórico publicado de outro contexto.

**Não copiar:** Não copiar as tabelas/caches `smart_feed_item` V1 nem refrescar todos os Smart Feeds como jobs independentes.

<a id="g07"></a>

### G07 — Lentes visíveis que explicam e deixam desfazer cada filtro

**Prioridade:** P1. **Frentes atuais:** F07, F13, F17, F25. **Tipo:** UX microinteração de alto valor.

**Prova V1:** [V1 `TaxonomyChipBar.swift` L3–108](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/TaxonomyChipBar.swift#L3-L108) · [V1 `FeedScreen.swift` L1205–1278](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedScreen.swift#L1205-L1278).

**Checagem V2:** [V2 `ReaderShell.swift` L19–48](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineUI/Reader/ReaderShell.swift#L19-L48) · [V2 `FeedScreenStore.swift` L93–104](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineUI/FeedScreenStore.swift#L93-L104).

**O que o repositório mostra:** A barra da V1 mostrava contexto: busca, região, tipo, tópico, idioma e humor; cada chip removia *seu* filtro. A barra podia ser dispensada por gesto ou ao ler, sem apagar elegibilidade. A V1 também tinha task de auto-colapso.

**Diferença ou incerteza V2:** O ReaderShell da V2 tem slot genérico `Lens`, não demonstra por si todos os chips. A semântica de filtro é tipada, mas UX visível e comportamento de scroll ainda requerem prova.

**Adaptar na V2:** Preencher slot com chips semanticamente derivados do ContextKey ativo; remover só a restrição indicada. Reduzir chrome ao consumir, preservar acessibilidade e priorizar imobilidade da âncora. O usuário deve distinguir 'ocultar barra' de 'limpar filtro'.

**Oráculo de produto G07:** Combinar região+idioma+termo+tipo; dispensar barra e verificar filtro idêntico; remover só termo, ir A→B→A e restaurar; VoiceOver lê escopo/estado; nenhuma inserção da barra move o card central.

**Não copiar:** Não copiar timer de quatro segundos, assinatura persistente de dismiss sem necessidade nem .padding de FeedScreen que desloca cards durante leitura.

<a id="g08"></a>

### G08 — Atalho contextual: fonte, coleção e cópia a partir do card

**Prioridade:** P1. **Frentes atuais:** F08, F12, F14, F16, F26. **Tipo:** End-to-end de ações já modeladas.

**Prova V1:** [V1 `FeedItemCardView.swift` L467–506](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedItemCardView.swift#L467-L506) · [V1 `FeedItemView.swift` L79–119](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedItemView.swift#L79-L119).

**Checagem V2:** [V2 `ReaderCardAction.swift` L8–25](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineUI/Cards/ReaderCardAction.swift#L8-L25) · [V2 `FeedItemCardView.swift` L334–367](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineUI/Cards/FeedItemCardView.swift#L334-L367).

**O que o repositório mostra:** Pressionar card abria View Source, Add Source to Collection, Copy Link e Share além de bookmark; ações pertenciam ao item publicado.

**Diferença ou incerteza V2:** A V2 já modela `viewSource`, `addSourceToCollection`, `copyLink`, `share` e as mostra condicionalmente; não classificar como recurso inexistente, mas validar destino/feedback/identidade após ação real.

**Adaptar na V2:** Completar as ações via ReaderActionCoordinator existente, com IDs de PublishedCard/Source. Mostrar opção apenas se ação tem executor; coleções usam identidade de origem, sem alterar a taxonomia canônica.

**Oráculo de produto G08:** Long press em card publicado; abrir a Source correta, adicionar à coleção 1 e 2, copiar URL real, voltar sem deslocar; se ação indisponível, não mostrar controle morto.

**Não copiar:** Não usar `UIApplication.shared.connectedScenes.first` aleatoriamente, criar action handlers em cada View ou copiar URL fallback fictícia.

<a id="g09"></a>

### G09 — Um catálogo com proveniência, quarentena e uma casa editorial

**Prioridade:** P0. **Frentes atuais:** F01, F03, F09, F12. **Tipo:** Recuperar disciplina de publicação externa.

**Prova V1:** [V1 `README.md` L6–74](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/editorial/feed-curation/README.md#L6-L74) · [V1 `source-experience.md` L6–17](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/editorial/feed-curation/source-experience.md#L6-L17).

**Checagem V2:** [V2 `LegacyCatalogImport.swift` L1–45](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineComposition/LegacyCatalogImport.swift#L1-L45) · [V2 `Source.swift` L1–45](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineDomain/Source.swift#L1-L45).

**O que o repositório mostra:** Os artefatos da V1 tinham canonical identities, aliases, quarentena, uma colocação editorial por Source e facetas virtuais; README do audit de 2026-08-03 registra 77.443 fontes publicáveis e 158.547 memberships, com checagens de consistência.

**Diferença ou incerteza V2:** A autoridade da V2 passou a `wawasoft/feed-repository` (PD-10); o snapshot V1 local não deve ser confundido com revisão pública atual. Quarentena/proveniência são ouro de ferramenta de publicação, não feature do renderer.

**Adaptar na V2:** Auditar a pipeline do repositório público com checks equivalentes de ID/URL, provenance/redirects, facetas e quarantine; versionar revision/hash/schema e publicar atomicamente. O app V2 só reconcilia catálogo validado oportunamente e preserva dados pessoais.

**Oráculo de produto G09:** Corpus contendo alias válido, URL HTML escaped, redirect semântico, Source sem membership; rejeições determinísticas e comprovadas antes da publicação. A V2 conserva catálogo anterior se manifest inválido e mostra facetas sem duplicar Source.

**Não copiar:** Não importar 77.443 linhas como autoridade atual sem revision/hash da fonte pública; não rodar scripts Python/curadoria dentro do app nem misturar catálogo e bookmarks.

<a id="g10"></a>

### G10 — Descoberta geográfica multifuente na cadeia de curadoria

**Prioridade:** P2. **Frentes atuais:** F01, F03, F12. **Tipo:** Ferramenta editorial, não runtime do app.

**Prova V1:** [V1 `adaptive_pipeline.py` L22–76](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/scripts/feed_discovery/adaptive_pipeline.py#L22-L76) · [V1 `country_profiler.py` L1–65](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/scripts/feed_discovery/country_profiler.py#L1-L65) · [V1 `2026-07-08-feed-discovery-design.md` L1–75](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/docs/superpowers/specs/2026-07-08-feed-discovery-design.md#L1-L75).

**Checagem V2:** [V2 `AcquisitionPlanner.swift` L1–55](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineAcquisition/AcquisitionPlanner.swift#L1-L55).

**O que o repositório mostra:** A V1 tinha ferramentas Python para pesquisar feeds por países/sub-regiões usando múltiplas origens e perfis de confiabilidade; candidatos passavam por dedupe e revisão antes de integrar OPML de produção.

**Diferença ou incerteza V2:** V2 precisa explorar todo o catálogo elegível em execução; isso não implica descobrir toda a web arbitrariamente no iPhone. Ferramenta de curadoria é separada de aquisição de conteúdos do app.

**Adaptar na V2:** Reusar ideias de busca multilíngue, staged candidates, provenance, liveness e cobertura regional no pipeline de `wawasoft/feed-repository`, após verificar licença/limites de cada origem; registrar fontes novas sem duplicação de identidades.

**Oráculo de produto G10:** Piloto de 2 países e sub-regiões com relatório de cobertura por tema, taxa de duplicação, rejeições e publicação revisada. FeedMine instalada não passa a fazer web search paga nem scraping ilimitado.

**Não copiar:** Não copiar APIs pagas, scrapers bloqueados, prioridades hardcoded por país ou profiles adaptativos como segundo governor do runtime.

<a id="g11"></a>

### G11 — Compartilhar um card visual preparado e fiel

**Prioridade:** P2. **Frentes atuais:** F06, F19, F26. **Tipo:** Produto opcional, paridade visual não automática.

**Prova V1:** [V1 `ShareCardImageView.swift` L3–106](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/ShareCardImageView.swift#L3-L106) · [V1 `FeedItemCardView.swift` L487–505](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedItemCardView.swift#L487-L505).

**Checagem V2:** [V2 `ReaderSharePayload.swift` L12–30](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineRuntime/ReaderSharePayload.swift#L12-L30) · [V2 `ReaderCardAction.swift` L8–16](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineUI/Cards/ReaderCardAction.swift#L8-L16).

**O que o repositório mostra:** A V1 gerava imagem social de manchete, foto, resumo e atribuição via ImageRenderer, no contexto do menu do card.

**Diferença ou incerteza V2:** V2 compartilha link e payload congelado, mas a versão em imagem foi diferença deliberada na transferência. O render da V1 empregava CachedAsyncImage remoto no próprio ImageRenderer, portanto não é seguro copiar.

**Adaptar na V2:** Se o usuário escolher formato imagem, compor artefato apenas de PublishedCardPayload e asset já persistido, sem fetch, com URL/atribuição verificáveis; folha ShareLink/Transferable gerenciada pela superfície do app.

**Oráculo de produto G11:** Compartilhar offline duas vezes o mesmo card, comparar texto, source e imagens; zero URLSession triggered pelo render; content length/attribution acessíveis; falha de mídia produz fallback honesto.

**Não copiar:** Não transformar imagem em substituto da URL nem compartilhar texto alterado após publicação; não atrasar scroll/render para montar share.

<a id="g12"></a>

### G12 — Estatísticas pessoais locais compartilháveis

**Prioridade:** P2. **Frentes atuais:** F08, F17, F19. **Tipo:** Experimento discreto e consentido.

**Prova V1:** [V1 `StatsShareCard.swift` L3–81](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/StatsShareCard.swift#L3-L81) · [V1 `SettingsSheetView.swift` L218–242](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/SettingsSheetView.swift#L218-L242).

**Checagem V2:** [V2 `ReaderSettingsView.swift` L61–101](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineUI/Settings/ReaderSettingsView.swift#L61-L101).

**O que o repositório mostra:** A V1 construía cartão visual com contagens de uso/biblioteca e tinha gesto explícito 'Share My Stats' em ajustes.

**Diferença ou incerteza V2:** V2 tem dados pessoais locais, mas não há prova de paridade nem decisão de produto de compartilhar métricas. Vantagem de delight tem risco de irrelevância para launch.

**Adaptar na V2:** Opcional, só após North Star funcionar: prévia, escolha explícita de exportar, números locais verificáveis e sem envio automático. Nenhum analytics server necessário.

**Oráculo de produto G12:** Somas conferem com dados locais conhecidos, recurso funciona offline, cancelamento não compartilha nada e estado pessoal não é exposto sem gesto.

**Não copiar:** Não medir streak compulsório, instrumentar servidor, compartilhar fonte lida sem consentimento ou usar o painel para justificar mais um banco.

<a id="g13"></a>

### G13 — Design com personalidade, mas geometria invariável

**Prioridade:** P2. **Frentes atuais:** F06, F17, F25. **Tipo:** Portar expressão visual com limite.

**Prova V1:** [V1 `CircadianEngine.swift` L6–107](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/CircadianEngine.swift#L6-L107) · [V1 `SettingsSheetView.swift` L75–120](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/SettingsSheetView.swift#L75-L120).

**Checagem V2:** [V2 `ReaderSettingsView.swift` L115–165](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineUI/Settings/ReaderSettingsView.swift#L115-L165) · [V2 `FeedItemCardView.swift` L67–120](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineUI/Cards/FeedItemCardView.swift#L67-L120).

**O que o repositório mostra:** A V1 permitia cinco famílias de paleta, paleta adaptativa e tipografia dependente do horário, com font family configurable.

**Diferença ou incerteza V2:** A V2 já oferece parte da superfície de aparência; não afirmar ausência total. Conflito: na V1 o horário também alterava paddings e gap, potencialmente perturbando histórico visível.

**Adaptar na V2:** Preservar apenas atributos cosméticos que não reclassificam, repaginam nem deslocam card; paleta/fonte opcional devem respeitar Dynamic Type e modo de acessibilidade.

**Oráculo de produto G13:** Mudar hora/tema/fonte e retornar ao mesmo card e âncora; redução de movimento/alto contraste; zero nova Edition, zero linha de texto truncada indevidamente.

**Não copiar:** Não copiar timer de hora cheia, calendário paralelos ou densidade circadiana que cause shifts enquanto o usuário lê.

<a id="g14"></a>

### G14 — Preferências negativas: distinguir bloqueio durável de lente casual

**Prioridade:** P1. **Frentes atuais:** F07, F13, F20. **Tipo:** Refinar UX existente.

**Prova V1:** [V1 `ContentFilterView.swift` L14–103](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/ContentFilterView.swift#L14-L103) · [V1 `SettingsSheetView.swift` L128–152](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/SettingsSheetView.swift#L128-L152).

**Checagem V2:** [V2 `ReaderFilter.swift` L82–113](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineDomain/ReaderFilter.swift#L82-L113) · [V2 `ReaderFilter.swift` L175–218](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineDomain/ReaderFilter.swift#L175-L218).

**O que o repositório mostra:** A V1 distinguia conteúdo oculto por keyword/template de critérios casuais e tinha uma opção de auto-limpeza de filtros transitórios após ficar ausente.

**Diferença ou incerteza V2:** V2 já define `ReaderContentExclusions` duráveis e ContextKey para filtros, mas a promessa depende de clareza na UI e persistência exata. Reset invisível após quatro horas entra em tensão com restauração de contexto F20.

**Adaptar na V2:** Exibir claramente ‘excluir sempre’ versus ‘aplicar nesta exploração’; permitir desfazer cada regra e verificar efeito somente em futuras seleções. Se houver auto-expiração, exigir escolha explícita e informação legível, sem reset da Edition em uso.

**Oráculo de produto G14:** Criar exclusão persistente e lente local, fechar e reabrir offline; verificar o que persiste segundo contrato. Desfazer altera só próxima seleção, nunca pula card visível.

**Não copiar:** Não copiar TTL de quatro horas como comportamento oculto, nem rotina que limpa filtros no scenePhase.

<a id="g15"></a>

### G15 — Sinais honestos de retorno e novidade, sem feed paralelo

**Prioridade:** P1. **Frentes atuais:** F05, F06, F20, F23. **Tipo:** Recuperar intenção e rejeitar mecanismo.

**Prova V1:** [V1 `WhatsNewManager.swift` L23–70](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/WhatsNewManager.swift#L23-L70) · [V1 `WhatsNewManager.swift` L110–168](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/WhatsNewManager.swift#L110-L168).

**Checagem V2:** [V2 `FeedSession.swift` L1–50](https://github.com/wsmontes/feedmine_v2/blob/71bd2e03c6174cde258111e258f29e92b613c539/Sources/FeedMineRuntime/FeedSession.swift#L1-L50).

**O que o repositório mostra:** A V1 mantinha baseline de novidades persistida e cartão/carrossel de recém-chegados, mas usava pool próprio e ‘booster’ para buscar outros itens.

**Diferença ou incerteza V2:** V2 quer novidades como oportunidade real e retorno à leitura, nunca competição com runway ou substituição de Edition visível.

**Adaptar na V2:** Reaproveitar somente conceito de baseline e affordance explícita ‘há X novidades prontas’ a partir da publicação/supply locais já contabilizados. Tocar decide entrar em sequência futura legítima, com retorno à âncora anterior.

**Oráculo de produto G15:** Sair, admitir novos cards em background, voltar: mesmo card/posição; sinal condizente com fatos; 0 novidades não gera carrossel nem fetch de booster; offline continua coerente.

**Não copiar:** Não copiar WhatsNewPool, threshold de cards, `.shuffled().prefix(30)`, booster paralelo, troca de carousel no topo nem `markSurfaced` por aparição implícita.


## Pilha de trabalho — sequência recomendada, não lotes fixos

1. **G09** antes de aceitar revisão pública: autoridade, reconciliação e quarantine; bloquear release se catálogo não validado (F01/PD-10).
2. **G01 + G05 + G08** cadeia natural: buscar → abrir Source → visitar conteúdo → guardar a origem, usando V2 editorial/acquisition/persistence; proteger F05/F06.
3. **G07 + G06 + G14** contexto visível e persistente: filtros → Smart Bookmark → biblioteca pessoal e exclusões reversíveis.
4. **G02 + G03 + G04** gosto explícito, capô e diversidade; não colocar formulário antes do feed real.
5. **G15** novidades honestas; **G10** exclusivamente pipeline do catálogo público; **G11–G13** só se valor real e custo justificarem.

A sequência **não** é dependência rígida de arquitetura. O runtime deve continuar preparando o runway mesmo quando uma jornada secundaria está aberta.

## Critério obrigatório de aceite para qualquer item

Relatar para cada Gxx: `NOT_RUN | PASS | FAIL | BLOCKED`, commit testado, setup do corpus, iPhone/iOS, cenário executado por gestos reais, IDs do card/source/contexto, captura/traces e regressões B03/B04/B05 associadas. Teste de método, arquivo Swift presente ou README ‘implemented’ **não são** PASS de produto.

## Ligações para implementação
- [Briefs executáveis e estratégia de integração](../product/V1_GOLD_IMPLEMENTATION_BRIEFS_2026-10-10.md)
- [O que NÃO transportar da V1](V1_GOLD_DO_NOT_PORT_2026-10-10.md)
- [Matriz de UI V1→V2 histórica](UI_TRANSFER_MATRIX.md)
- [Audit trail do catálogo V1](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/editorial/feed-curation/README.md)
