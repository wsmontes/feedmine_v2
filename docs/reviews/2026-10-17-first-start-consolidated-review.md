# Primeira abertura — revisão consolidada V1/V2

Data: 2026-10-17, America/Vancouver. Revisão estática, sem build, teste ou comparação cronometrada nesta sessão. V2 inspecionada na linha de `6cbaa2fe` e commits documentais posteriores; V1: `wsmontes/feedmine-dev`, símbolos abaixo. Conferir linhas/SHAs no checkout antes de implementar. Direção do dono: reunir achados numa revisão, evitando commits fragmentados por detalhe.

## Veredito de produto

A V1 expressa melhor o requisito de uma primeira entrega pronta e editorialmente variada; a V2 tem um mecanismo útil de aquisição concorrente que permite progredir sem esperar a fonte mais lenta. Preservar ambas as propriedades, sem copiar quotas, timeouts e runtime da V1. Não há nesta revisão prova de qual app abre mais rápido ou de conformidade integral de qualquer um.

Primeira abertura não é reabertura: uma instalação limpa pode mostrar preparação honesta; uma sessão com publicação local válida deve restaurar sem aguardar descoberta ou rede. Não usar sucesso de warm start como prova de first start.

## 1. Critério de liberação da primeira entrega

V1: `feedmine/Services/FeedStore.swift`, `coldStartPageIsReady` (~1557), `startFirstLaunchBootstrapIfNeeded` (~1702) e o caminho frio de `start` (~2168–2192). A condição é uma página de `Reservoir.pageSize` (20) itens de fontes distintas; o objetivo de 100 fontes é preenchimento de fundo. O caminho pode terminar em vazio após prazo de 30 s sem página completa. São garantias de amplitude acompanhadas de políticas rígidas e risco de ocultar conteúdo aproveitável.

V2: `Sources/FeedMineComposition/ColdFeedBootstrap.swift`, `run`: cada aquisição concluída com mudança de supply permite tentar a primeira publicação; as fontes lentas não bloqueiam essa tentativa. `AppComposition.swift`, `FeedAssociation.launch` (~2749), instala o resultado e cresce a janela depois do fato de publicação. Não foi encontrada nesse caminho uma condição equivalente de amplitude editorial da primeira entrega. Isso é diferença de contrato, não prova de que toda instalação produz um único card.

Direção: não confundir "primeira publicação possível" com "primeira experiência satisfatória". Definir uma primeira entrega consumível, pronta e variada segundo fatos elegíveis e capacidade observada, conciliando contingências reais. Não copiar o número 20 nem esperar arbitrariamente 100 fontes. Preservar preparação concorrente e prontidão anterior à admissão. Referências normativas: os documentos de 2026-10-17 sobre render-ready e Interleave, INV-16/17.

## 2. Conclusão das boas-vindas pode esconder falha de persistência — achado direto

V2 `FeedMineApp/FeedMineApp/FeedMineApp.swift`, `onboardingCover.onSave` (~895): `showsOnboarding = false` acontece antes da `Task` com `completeFirstRun`. `AppComposition.completeFirstRun` (~960) usa leituras/escritas opcionais por `try?`, não devolve sucesso/erro e chama `try? await replaceSession()` mesmo sem confirmação de persistência. O caminho `completeOnboarding` (~947) também retorna silenciosamente se não conseguir ler/gravar; o host fecha a capa mesmo assim.

Consequência demonstrável pelo fluxo: falha de persistência não é comunicada por essa API à superfície que acabou de aceitar a escolha. Não afirmar que uma falha de disco específica já ocorreu. Riscos: respostas não aplicadas, boas-vindas reaparecendo no próximo launch e erro de reconstrução sem mensagem neste call site.

V1 `CuratedOnboardingView.save`: mantém `isSaving`, só chama `onSaved` depois de criar o feed e oferece alerta no catch. A V1 também tem custo de produto: cria/ativa um feed curado mesmo em "Start broad"; isso não deve ser copiado para o fluxo de descoberta da V2.

Direção: confirmação explícita do resultado e recuperação compreensível. A interface pode continuar responsiva sem declarar conclusão inexistente. Provar falha de gravação, falha de reconstrução após gravação bem-sucedida, nova tentativa e reabertura. Não apagar respostas ou reescrever histórico para simplificar a recuperação.

## 3. Opções de idioma truncadas — achado direto, impacto a verificar

V2 `AppComposition.onboardingOptions` (~974): `languageGroups().filter { !$0.isUndeclared }.prefix(12)` limita as opções entregues ao primeiro contato e a consumidores dessa mesma função. `ReaderOnboardingView` começa com o idioma do aparelho, mas isso não garante que a lista limitada permita selecioná-lo novamente ou escolher todos os outros idiomas elegíveis.

Direção: verificar a ordem real dos grupos e a experiência de um idioma fora dos 12. Não tratar esse limite como cobertura editorial suficiente. Expor os idiomas elegíveis por busca/navegação adequada sem transferir uma carga ilimitada para o desenho. Idioma, país/região e linguagem da interface são fatos diferentes.

## 4. Preferência nova e conteúdo preparado antes da resposta — risco, não defeito provado

O host apresenta a capa e executa `composition.launch` por baixo dela (`FeedMineApp.swift` ~542–580). `completeFirstRun` grava o perfil e chama `replaceSession`; seu comentário declara restauração da posição porque o contexto não muda. Logo, é necessário verificar o destino de uma edição preparada sob o perfil anterior enquanto a pessoa estava nas boas-vindas.

Não concluir por comentário que preferências são ignoradas. Seguir `sessionState`, revisão editorial, elegibilidade e restauração e provar: idioma/região escolhidos são respeitados; nenhuma conclusão antiga instala resultado no novo perfil; conteúdo já publicado não é reescrito silenciosamente. Resolver a fronteira com a hierarquia vigente, não com edição artificial ou reset indiscriminado.

## 5. Preparação e falha de conexão — preservar avanço da V2

`ColdFeedBootstrap` fornece fatos de contato, resposta, preparação e publicação. `FeedLoadingView` distingue preparação, ausência, adiamento, falha e conexão indisponível e oferece ações conforme o estado. A correção da primeira abertura offline já está integrada; não reabrir como se faltasse implementação.

Ainda exigir execução de instalação limpa: sem rede; rede que cai no meio; fontes vazias; uma lenta com outras úteis; mídia pendente; nova tentativa. O primeiro uso sem conteúdo baixado não pode prometer artigos offline inexistentes. Não transformar metadados do catálogo em conteúdo pronto nem usar progresso fictício.

V1 tem ambiguidade de progresso registrada no próprio `configureStartupProgress`: objetivo da barra e total do catálogo não representam a mesma conclusão. Não transportar essa superfície para a V2.

## 6. Importação e saída do primeiro contato

V2 permite OPML por fluxo opcional e retorna às boas-vindas após picker/preview. Essa capacidade é implementada, não uma pendência abstrata. Provar cancelamento, arquivo inválido, import parcial/duplicada e persistência do resultado. A importação não deve completar indevidamente o onboarding nem ser pré-requisito para descobrir conteúdo. Não confundir OPML com migração integral dos dados V1.

A capa de boas-vindas e Composer ainda existe nas duas versões. Confrontar a jornada efetiva com F02 e as decisões posteriores antes de propor mais formulário ou remover o fluxo: um comentário que cita F02 não é prova de conformidade.

## Prova consolidada antes da próxima candidata

Usar instalação limpa dedicada e registrar a identidade do binário e do catálogo. Caminhar: entrar sem responder; salvar preferências; falhar e repetir salvamento; escolher idioma fora da lista inicial; importar/cancelar; abrir offline e reconectar; receber fontes em tempos diferentes; interromper e relançar. Em cada caminho verificar a primeira sequência realmente entregue, prontidão visual, adequação às escolhas, continuidade e recuperação.

Separar resultados da main, da branch candidata e do TestFlight. Uma correção commitada não prova que chegou ao aparelho. Sem modificar a régua congelada, sem percentuais inventados e sem declarar PASS por teste que não executou a premissa.

## Ordem recomendada

1. Tornar observável o resultado de conclusão/persistência das escolhas.
2. Fechar o contrato de primeira entrega pronta e diversa, junto dos requisitos já registrados de mídia e Interleave.
3. Verificar transição de perfil e cobertura de idiomas.
4. Executar a matriz de falhas/retomada/importação na candidata integrada.

Nenhuma implementação é realizada ou certificada por este commit. A investigação deve reutilizar os donos existentes, preservar o feed publicado e respeitar a hierarquia de decisões do projeto.
