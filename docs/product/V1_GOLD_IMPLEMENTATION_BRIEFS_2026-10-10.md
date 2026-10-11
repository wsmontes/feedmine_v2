# Implementação orientada a produto — V1 Gold Backlog

**Estado:** proposta de execução e critérios de comportamento; nenhum código modificado. **Base:** [garimpo com provas](../v1-study/V1_HIDDEN_GEMS_PRODUCT_MINING_2026-10-10.md). **V2:** `71bd2e03c`. **Data:** 2026-10-10.

## Regra de execução para agentes
Cada item é uma *jornada de usuário*, não módulo Swift. Antes de alterar código, identificar se já há fluxo correspondente e executá-lo; fechar a lacuna mais curta no owner existente. Se já estiver operante, registrar evidência e encerrar a tarefa sem reescrever. Se estiver parcialmente operante, preservar o que funciona. Não sacrificar B01–B06 nem inventar contagem de cards, timers, gestão de scene ou listas alternativas.

## Matriz de integração mínima

| Itens | Origem/causa | Owners V2 existentes a verificar | Resultado observável |
|---|---|---|---|
| G01 | F12/F14: navegação de origem ≠ carregamento de histórico | `ReaderActionCoordinator`, `SourceManagementCoordinator`, `AcquisitionCoordinator`, `FeedSession` | Source específica abre com histórico local + oportunidade de atualização explícita |
| G05/G06 | F11/F16: expressão editável, escopo e salvos | `ReaderShell`, `FeedScreenStore`, `ReaderLibraryCoordinator`, `ReaderFilter` | Query de tokens/negação reproduzível como Smart Feed |
| G07/G14 | F07/F13: filtro invisível ou confundido com exclusão durável | `ReaderShell.Lens`, `ReaderFilterStore`, `FeedSession` | Remoção pontual e reversível, nenhuma alteração do card visível |
| G02/G03/G04 | F02/F04: curação e aprendizado explicável | `FeedRecipeDefinition`, `CuratedFeedCoordinator`, `SelectionEngine`, UI `CuratedFeedInspectorView` | Escolha voluntária influencia apenas futuro, com feedback/evidência honesta |
| G08 | F12/F16/F26: card→origem→coleção | `ReaderCardAction`, `ReaderActionCoordinator`, `ReaderLibraryCoordinator` | Mesma Source, coleção e Edition preservadas |
| G09/G10 | F01/F03/F12: catálogo e provenance | `wawasoft/feed-repository` (autoridade de publicação); import/reconcile V2 | Revision e quarantine audíveis sem misturar dados do usuário |
| G15 | F20: notícias novas ≠ reset do feed | `PublicationHistory`, `FeedSession`, `BackgroundFeedRefresh` | Novidades prontas, sem segundo carrossel/booster |
| G11/G12/G13 | F17/F19: delight, publicação imutável | `ReaderSharePayload`, `ReaderAppearance`, `ReaderSettingsStore` | Ações opcionais sem download ou deslocamento involuntário |

## Recortes executáveis sugeridos

### S1 — Jornada Source real, sem bypass de publicação (G01 + G08)
**Pré-condições:** card já publicado com SourceID resolvido; corpus com Source dormiente, Source sem rede e Source com histórico local. **Gesto:** long press → Ver Fonte → explorar itens → opcional adicionar Source à coleção → voltar ao card original.

**Resultado:** ver Source correta, conteúdos locais imediatamente e novas histórias apenas via caminho de admission/materialização apropriado. Abrir não reabilita o endpoint automaticamente nem substitui a Edition ativa. Explicitar limite real de RSS (não um arquivo completo). Se Source não puder ser resolvida, botão não conduz a tela vazia falsa.

**Contratos:** G01/G08, F03, F05, F06, F12, F14, F21. **Evidência:** origem normalizada, PublishedCardID/SourceID, requests feitos por ação explícita, capturas antes/depois; **sem** `View.task` de HTTP.

### S2 — Busca com restrições e Smart Bookmark (G05 + G06 + G07)
**Pré-condições:** três resultados conhecidos no SQLite (Source, salvo, história local), termos discriminativos e dois contextos A/B. **Gesto:** buscar `astronomia -astrologia`, remover só o termo negativo, ver tipos de resultado, salvar contexto como Smart Feed e voltar offline.

**Resultado:** escopo e polaridade explícitos; nenhuma query negativa isolada dispara aquisição; Smart Feed reabre com a mesma intenção e dados locais; A→B→A conserva posição/contexto e histórico visível; filtro não é convertido silenciosamente em exclusão global.

**Contratos:** G05/G06/G07, F07, F11, F13, F16, F25. **Evidência:** query normalizada, ContextKey, Smart Feed ID, contagem/categorias, vídeos de retorno.

### S3 — Curadoria explicável e opcional (G02 + G03 + G04)
**Pré-condições:** duas histórias reais prontas, perfis de tópicos e estilos de Source conhecidos; usuário começou lendo sem onboarding obrigatório. **Gesto:** aceitar convite opcional de preferência, escolher, desfazer; abrir história; acessar capô do feed curado.

**Resultado:** apenas escolha explícita altera receita; abertura só ajusta peso se a função estiver conscientemente ativada; scroll e exposição não alteram perfil; capô distingue respostas próprias de aprendizado e permite desligar, revisar/limpar. Nunca falsificar confiança ou ‘intenção’ inferida.

**Contratos:** G02/G03/G04, F02, F04, F06, F16. **Evidência:** eventos de escolha, antes/depois da receita, histórico exibido, distância ao tail B03/B04.

### S4 — Biblioteca e exclusões conscientes (G06 + G08 + G14)
**Pré-condições:** bookmark, duas coleções e duas lentes num contexto. **Gesto:** adicionar a Source à coleção, estabelecer exclusão durável, aplicar filtro transitório, navegar, reiniciar offline e desfazer.

**Resultado:** membership many-to-many sem duplicar Source, exclusão durável sobre futuro, lente transitória visualmente reconhecível; nenhum reset silencioso após período em background. Salvos continuam nas caixas corretas.

**Contratos:** G06/G08/G14, F13, F16, F18, F20. **Evidência:** banco pessoal/IDs, caminho de gestures e checks do histórico publicado.

### S5 — Catálogo público confiável (G09 + G10)
**Pré-condições:** manifest com SHA/schema e corpus de aliases/redirects/quarantine. **Gesto:** instalar/reabrir com snapshot válido, oportunidade de atualização válida, outra inválida. **Resultado:** revisão pública é a autoridade; falha preserva último snapshot válido e dados pessoais. Relatório de preparação externo exibe normalizações/quarentena; não roda discovery via Python no aparelho.

**Contratos:** G09/G10, PD-10/INV-18, F01, F03, F09. **Evidência:** revision, hashes, IDs canônicos, quarantine ledger, teste offline/invalid-manifest.

### S6 — Encanto não disruptivo (G11 + G12 + G13 + G15)
**Pré-condições:** B01–B06 em andamento ou aprovado; card publicado, app offline, opções de aparência, retorno com supply novo. **Gesto:** compartilhar card/estatísticas (se ofertado), mudar paleta/tipografia, sair/voltar.

**Resultado:** sharing reproduz conteúdo congelado e não baixa imagem; tema não move âncora; novidades não empurram top e não criam carrossel paralelo. Funções não essenciais permanecem ocultas caso indisponíveis.

**Contratos:** F06, F17, F19, F20, F25–F27. **Evidência:** IDs antes/depois, zero request em share/render, screenshot/VoiceOver e checkpoint estável.

## Done de uma mudança
1. Comparação atualizada de V1 evidência→V2 lacuna, citando commit.
2. Um único owner de execução confirmado; nada de nova camada por conveniência.
3. Teste unitário para semântica **e** prova black-box da jornada que realmente é ofertada.
4. Idempotência, off-line, não destruição de Edition, estabilidade de âncora e comportamento em rede restrita.
5. Ações não suportadas não aparecem na UI; inconsistências são FAIL/NOT_RUN, não ‘validado’ por código.
