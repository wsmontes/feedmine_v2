# T4 — Fontes e contextos locais

Objetivo: escolher fontes do catálogo, persistir escolha e retornar main→source/search→main offline preservando histórico e posição. UI emite intenções; Persistence guarda preferências/checkpoints; Editorial filtra fontes e busca texto legível; a associação atual mantém os owners existentes.

## Contratos

- ReaderPreferencesStore em Persistence: Record(sourceKeys:[String], selectionVersion:UInt64, activeContext:FeedContextRequest); load(), initialize(sourceKeys:), updateSources(_:), setContext(_:), todos throws. Versão inicial 2 distingue a nova seleção explícita da composição anterior; alterações efetivas de keys incrementam a versão, a mesma seleção não incrementa. Lista vazia é recusada sem alterar estado.
- SessionStore: activateContext(_ request:FeedContextRequest) throws seleciona checkpoint durável próprio e arquiva o anterior; clearActiveCheckpoint() mantém checkpoints contextuais e história. saveCheckpoint/insertInitialCheckpoint também escrevem checkpoint contextual na mesma transação. Migração aditiva copia o singleton antigo.
- PublicationHistory.restore(backwardCapacity:forwardCapacity:contextKey:) e FeedSession.restoreLocalPresentation com contextKey opcional; comportamento antigo sem argumento preservado.
- ResolvedSelectionPolicy.EligibilityBehavior.selectedSources(Set<SourceID>): filtra apenas por memberships, num único owner Editorial. Nova eligibilityPolicyVersion=2 na composição; history só restaura se ContextKey/userSelectionVersion/eligibility forem compatíveis.
- Busca local é substring de título/summary legíveis, sem diferenciar case/diacríticos, query trimmed apenas para matching. ContextKey conserva a query original. Cada janela canônica mantém capacidade/cursor/examinedCount; não busca HTTP. Não cria FTS paralelo nesta entrega. Consultas vazias são recusadas por SearchContext.
- LegacyCatalogReader.matchingSources(query:limit:) consulta nomes de fontes text, limita linhas e trata query literalmente com bind/escape. Picker apresenta fontes selecionadas e resultados; callback de escolha identifica SourceID, composição resolve key/endpoint pelo catálogo.
- AppComposition.selectContext(_:), toggleSource(_:) e searchSources(_:) fecham associação anterior após checkpoint e descartam callbacks antigos. source desativada não entra na publicação main; nenhum conteúdo canônico é apagado. Troca incompatível inicia Edition nova sem apagar anteriores.

## Persistência

Migração reader-contexts-v1 acrescenta reader_preferences(singleton_id, source_keys, selection_version, active_context) e context_checkpoints(context_key, edition_id, card_id, anchor_placement, updated_at). Context identifier usa prefixos main/source/search e UUID lowercase/query original. Foreign keys apontam para cards/editions já duráveis. Global checkpoint continua sendo ponte de compatibilidade e posição ativa; context_checkpoints guarda posição de reentrada.

## Provas

Preferências persistem no reopen; mesma escolha é idempotente; vazio é recusado atomicamente. main→source→main offline retorna Edition/anchor anteriores. source apresenta sua própria fonte e é isento de PD-4; main filtra fontes selecionadas. Busca encontra texto legível e preserva cursor/bounds. Callback de associação antiga não instala no novo store. Banco anterior migra sem apagar histórico.

## Decisões

Implementação local e sequencial autorizada pela execução do plano; não acrescentar ranking/recomendação de feed. Exceção registrada (rodada 4/5): a ordem dos *resultados da busca de fontes* usa a sort key do catálogo V1 (prefixo do título, default_enabled, quality_score desc, título; `04-catalog-editorial.md`); não afeta seleção editorial. Busca bounded scan usa owner/cursor existentes; medir sua escala em T7. Catálogo de recursos permanece read-only; source_keys são preferências do usuário em runtime.sqlite.
