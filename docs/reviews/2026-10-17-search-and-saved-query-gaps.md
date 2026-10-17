# Busca e pesquisas salvas — divergências de contrato V1/V2

Data: 2026-10-17 (America/Vancouver). Revisão estática solicitada pelo dono; somente documentação. Não houve build, execução de testes ou correção do app nesta sessão. Símbolos conferidos na main acessível nesta rodada; revalidar linhas no checkout antes de implementar.

## Contratos existentes

Reutilizar `docs/product/F11_UNIFIED_SEARCH_RESULTS_UX_PRD.md`, `F16_PERSONAL_LIBRARY_SMART_FEEDS_UX_PRD.md` e `docs/superpowers/specs/2026-10-09-reader-filters-and-context-identity.md`. Eles já definem termos positivos/negativos, escopo explícito, retorno à consulta e ao contexto anterior, resultados locais honestos e Smart Feed como regras reutilizáveis, não snapshot estático. Não criar outra especificação ou SearchEngine concorrente.

## 1. A interface promete exclusão; a consulta executada é literal

V2 `Sources/FeedMineUI/Reader/ReaderShell.swift`, `searchBar`, mostra "Adicionar um termo · use -termo para excluir" e entrega a string ao store. `AppComposition.submitSearch` constrói `SearchContext` e chama `selectContext(.search(...))`. `SearchContext` em `Sources/FeedMineDomain/FeedContext.swift` só valida string não vazia.

`Sources/FeedMineEditorial/CandidateProvider.swift`, ramo `.search`, usa a query inteira trimmed em `range(of: query, options: [.caseInsensitive, .diacriticInsensitive])` sobre título ou resumo. Nesse caminho:

- `astronomia -astrologia` é substring literal, não requisito positivo combinado com exclusão;
- `astronomia ciência` exige a sequência literal num dos campos, não termos positivos independentes em AND;
- consulta exclusivamente negativa não recebe a validação semântica da V1; isso não prova, por si, aquisição ilimitada, mas prova que o hífen não é interpretado como a UI promete.

Referência V1: `feedmine/Services/SearchEngine.swift`, `SearchTerm`, `SearchExpression`, `canSearch`, `matches` e `contentFTSQuery`. O hífen inicial marca exclusão, hífens internos permanecem texto; palavras da query legada são combinadas por AND e uma consulta sem termo positivo não inicia a busca unificada.

Direção: estabelecer a expressão semântica no owner apropriado existente e usá-la coerentemente na consulta, interface e persistência. Preservar consultas antigas explicitamente; não trocar significado silenciosamente nem adicionar parser independente em cada camada. Não copiar limites e políticas arbitrárias da V1.

## 2. Cancelar a barra não restaura o contexto anterior

`ReaderShell.searchBar` chama `store.cancelSearch()`. `Sources/FeedMineUI/FeedScreenStore.swift`, `cancelSearch`, apenas define `isSearching = false` e `searchQuery = ""`; não encaminha intenção de retorno. Enviar uma busca, ao contrário, troca o contexto via `AppComposition.submitSearch`/`selectContext`.

O caminho inspecionado não implementa na ação Cancelar o retorno ao contexto original exigido por F11-R4. Não confundir fechar o campo com sair do contexto de busca. Definir a intenção explícita e preservar contexto completo, edição, âncora e posição anteriores; abrir um resultado e voltar deve recuperar a consulta, e cancelar a consulta deve recuperar a leitura de origem. Não presumir que origem é sempre main sem filtros.

## 3. Escopo e resultados unificados não são certificados por tipos existentes

V1 `SearchEngine.unifiedSearch` produz grupos distintos de fontes, salvos e outros artigos locais, com consulta de fontes no catálogo e conteúdo local. V2 possui `ReaderSearchScope`/`ContextKey` e uma busca de fontes em `AppComposition.searchSources`, mas esse método abastece a gestão/seleção de fontes; não demonstrou nesta inspeção um painel unificado ligado à barra de leitura.

No ramo de busca de `CandidateProvider`, o predicado examina título/resumo de candidatos; não usa `searchScope` para construir grupos de resultados Sources/Salvos/Local. Não declarar ausência global de todo suporte a scope sem conferir os demais call sites; a lacuna é a jornada unificada ainda não demonstrada por esse caminho.

Direção: resultados com tipo/origem legíveis, escopos que de fato afetam a consulta e destinos corretos. Visitar uma fonte é a lista interna definida no commit de Ver fonte, não o site. Não prometer busca universal/remota quando apenas catálogo ou dados locais foram consultados.

## 4. Pesquisas salvas existem; não reimplementar

`Sources/FeedMineComposition/ReaderLibraryCoordinator.swift`, `savePreset`, persiste o `ContextKey` e cria uma identidade própria de preset preservando request, filter e searchScope. `AppComposition.saveCurrentContextAsPreset` salva e ativa a chave. Esse mecanismo é implementação existente, não funcionalidade ausente.

Guardar a string corretamente não corrige a interpretação literal da busca. Uma pesquisa salva precisa reproduzir o significado aprovado de termos, exclusões, filtros e escopo depois de reinício e offline, em vez de apenas conservar texto. Não converter Smart Feed em lista fixa de resultados nem criar outro runtime para atualizá-lo.

## 5. Falhas descartadas no caminho da ação

`FeedMineApp/FeedMineApp/FeedMineApp.swift`, confirmação de `.saveSmartBookmark`, usa `try? await composition.saveCurrentContextAsPreset(...)`. `AppComposition.submitSearch` também usa `Task { try? await selectContext(...) }`. Os erros não são encaminhados por esses call sites a uma mensagem de falha.

Separar falha ao salvar de falha posterior ao ativar um preset já salvo. Não dizer "nada foi salvo" se persistiu; não aparentar sucesso se a gravação falhou. Permitir recuperação preservando a expressão e evitando duplicação em nova tentativa. A leitura identifica supressão de erro; não reproduziu falha de disco ou de ativação nesta sessão.

## Provas discriminantes após implementação

- Positivos independentes, exclusão inicial e hífen interno; case/diacríticos e consulta só negativa conforme contrato aprovado. Incluir exemplo com positivo no título e outro no resumo para definir o escopo textual da expressão.
- Incluir/remover/inverter termos e mudar escopo sem resultados obsoletos; consultas concorrentes com conclusão invertida.
- Abrir fonte/artigo/salvo, voltar à consulta e cancelar para o contexto original com sua posição preservada.
- Salvar pesquisa, alterar o contexto corrente e reabrir a salva após reinício/offline: significado e escopo conservados.
- Falhar gravação ou ativação em etapas distintas, comunicar o resultado verdadeiro e repetir sem duplicação.

Usar os contratos F11/F16 e owners atuais; não alterar benchmarks congelados para obter aprovação. A presença de teste ou tipo não equivale a execução de jornada. Este commit registra achados de código, limites da inspeção e direcionamento; não certifica defeitos visuais reproduzidos nem correção implementada.
