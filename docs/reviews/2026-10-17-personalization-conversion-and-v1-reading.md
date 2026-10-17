# Personalização — conversões, efeitos e leitura dirigida da V1

Data: 2026-10-17 (America/Vancouver). Revisão estática e encaminhamento solicitado pelo dono. Este commit é somente documental: não corrige o app nem afirma testes executados.

## Contratos e precedência

Ler F02, F13 e PD-11 antes de implementar. F02 descreve preferências leves; a decisão posterior PD-11 reconhece a exclusão efetivamente implementada e exige texto honesto: "Não quero mais sobre X", confirmação de exclusão e desfazer. `FeedEditorialInvitationView` já aplica essa linguagem. Não apresentar a correção de copy como pendente nem introduzir ranking novo para justificar o texto antigo.

Preservar o feed publicado: mudanças de preferências não reordenam, removem ou enriquecem ocorrências existentes. Separar essa proteção da capacidade de orientar preparação futura.

## Achados V2, por caminho

### 1. Normal explicitamente gravado vira exclusão — erro lógico direto

`Sources/FeedMineUI/Onboarding/ReaderDiscoveryControls.swift`, `topicControl`, grava `level.next()` no dicionário. O ciclo em `ReaderPreferenceLevel.next` é neutral → more → less → neutral.

`FeedMineApp/FeedMineApp/AppComposition.swift`, `discoveryProfile(from:)`, converte `topicPreferences` com `if level == .more { interested.insert(node) } else { excluded.insert(node) }`. Logo `.neutral` presente no dicionário entra em `excludedTopicNodeKeys`, embora signifique Normal na interface.

O caminho de `voteOnTopic(..., .neutral)` remove a entrada, mas o controle de configuração não usa esse mesmo caminho: o bug não pode ser descartado porque o desfazer do convite remove a chave.

Direção: tratar explicitamente more/less/neutral com a semântica aprovada; neutral não é exclusão. Considerar valores neutros já persistidos sem transformar preferências antigas silenciosamente em bloqueios.

### 2. Duas mídias selecionadas não cabem no filtro produzido

`Sources/FeedMineDomain/FeedRecipeDefinition.swift`, `contentTypeCriterion`, retorna o tipo quando só um foi escolhido, mas retorna `.all` quando dois estão selecionados. `FeedRecipeResolution.filter(for:)` consome esse valor. A representação do filtro perde a seleção exata de dois formatos.

Há ponderação adicional em feeds curados; portanto não afirmar que desligar mídia não tem efeito em nenhum caminho. Porém penalização por peso não equivale a exclusão rígida. Definir e cumprir a promessa dos switches; não alegar que a V1 bloqueava absolutamente formatos desmarcados, pois seu resolver também apenas penaliza.

### 3. Vocabulário editorial usado como nó temático

`ReaderDiscoveryControls.balanceControl` usa `editorial:reference`, `editorial:specialist`, `editorial:distinctive`. `AppComposition.discoveryProfile(from:)` põe entradas negativas de `editorialPreferences` em `excludedTopicNodeKeys`, removendo somente prefixo `topic:` quando existe. Assim uma chave `editorial:specialist` atravessa a fronteira como se fosse identidade de assunto do catálogo.

`Sources/FeedMineEditorial/FeedEditorialAssessment.swift` e `FeedRecipeResolution.featureKeys` já possuem o vocabulário editorial correto. Não criar uma segunda classificação; respeitar a diferença entre peso editorial e exclusão temática. Verificar o efeito real da chave no catálogo; não afirmar que ela necessariamente exclui fontes especializadas.

### 4. Descoberta geral e ranking curado leem receitas diferentes

`AppComposition.discoveryProfile(for:)` prioriza perfil global quando `namesAnything` retorna true; idioma preenchido já basta. Só depois tenta a receita do preset curado. `scoring(for:)`, por sua vez, calcula pesos com a receita curada.

O caminho pode usar perfil global para exploração e receita curada para ranking. A precedência é verificável no código; sua classificação como defeito depende da reconciliação com o contrato vigente de descoberta global versus feed nomeado. Não fundir receitas nem substituir escolhas explicitamente sem decisão. Tornar a precedência compreensível e consistente.

### 5. Voto persistido não atualiza a descoberta da associação corrente

`voteOnTopic` persiste a resposta e não reconstrói sessão, exceto pedido de novo passe quando já existe reconstrução em curso. A associação guarda seu próprio `discoveryProfile`; o perfil novo é adotado quando outra associação é construída. `refreshFromTheReader` pode provocar isso explicitamente.

Isso protege a apresentação, mas não comprova adaptação do trabalho futuro durante a sessão corrente. Reconciliar o momento de efeito com as decisões já registradas: não chamar um atraso deliberadamente autorizado de regressão sem conferir o histórico, nem prometer efeito imediato que não ocorre. Não mover o leitor para aplicar preferência.

### 6. Falha no convite e desfazer têm recuperação inferior às configurações

`FeedMineApp.swift`, `invitation`, altera `inFeedAnswers` antes de persistir e limpa a entrada em falha, sem mensagem ao leitor nesse callback. `editorialSlot` consulta também `composition.declaredLevel`; resposta persistida sem entrada local pode ser tratada como de sessão anterior e suprimir o bloco. Portanto há risco de perder a oportunidade local de repetir um desfazer que falhou.

Não chamar isso de "desfazer falso" comprovado: a preferência persistida antiga continua disponível e não houve execução de UI nesta revisão. Preservar confirmação verdadeira, explicação de falha e possibilidade de repetir sem perder o contexto.

`Sources/FeedMineUI/Settings/ReaderSettingsStore.swift`, `update`, já tem comportamento melhor: grava, relê a verdade persistida e, em erro, recarrega e mantém `errorMessage`. Reutilizar a disciplina existente; não generalizar o problema para todas as configurações.

## Leitura dirigida da V1 — o que o dono pediu que os implementadores leiam

Repositório: `wsmontes/feedmine-dev`. Referências são símbolos inspecionados nesta sessão; registrar o SHA efetivo no checkout antes de implementação. Não copiar o runtime legado.

### A. `feedmine/Models/FeedRecipeDefinition.swift`

Ler `PreferenceLevel.profileWeight`, `FeedRecipeDefinition` e `neutral(languages:)`.

Extrair: significado separado de níveis, idiomas, conjunto de formatos e intensidade de descoberta. Normal tem peso zero, não uma exclusão implícita. Conferir que campos parecidos entre V1/V2 conservam significado, não apenas nome.

### B. `feedmine/Services/FeedRecipeResolver.swift`

Ler integralmente `effectiveProfile(recipe:evidence:)` e `mediaFeatureKey(for:)`.

Extrair:

- pesos de assuntos e editoriais são mapeados separadamente, em seus namespaces;
- escolhas explícitas formam a base, evidência é combinada separadamente;
- idiomas, nível de descoberta e habilitação de aprendizado vêm da receita quando ela existe;
- article/podcast/video têm tradução explícita para media:text/media:audio/media:video;
- mídia removida recebe peso negativo: isso é penalização, não prova de proibição absoluta.

Aproveitar a clareza da tradução e da precedência. Não transportar automaticamente números de pesos, confidence, aprendizado de aberturas ou a política antiga para V2. PD-11 continua governando a ação negativa atual da descoberta.

### C. `feedmine/Services/CuratedPreferenceEngine.swift`

Ler `sourceMultiplier(for:profile:)` e a construção de `featureKeys`: como pesos editoriais, assunto e mídia chegam ao cálculo com identidades correspondentes.

Ler também `OnboardingSession.answer` e `undo` como referência de restauração do estado anterior. Limite: os duelos não têm caller de produção no fluxo atual examinado; presença desse código não certifica a experiência V1 nem justifica reintroduzir onboarding de duelos.

### D. Confrontar com responsáveis já existentes na V2

`Sources/FeedMineEditorial/FeedRecipeResolution.swift`, `Sources/FeedMineEditorial/FeedEditorialAssessment.swift`, `Sources/FeedMineComposition/CuratedFeedCoordinator.swift` e `ReaderSettingsStore.update` já entregam parte dessas responsabilidades. Primeiro corrigir as ligações e conversões; não duplicar engine, perfil ou mecanismo de persistência.

## Resultado esperado

Uma matriz por controle: intenção declarada → valor persistido → consumidor efetivo → momento de aplicação → efeito → desfazer/erro. Separar descoberta geral, feed curado, filtro contextual e bloqueio de fonte.

Priorizar o erro neutral→exclusão, a perda de subconjunto de mídia e o namespace editorial/temático. Depois resolver precedência, momento do efeito e recuperação de falhas conforme contratos vigentes. Demonstrar os casos com controles discriminantes no ambiente nativo, sem alterar régua congelada ou histórico publicado.

Este documento não certifica uma auditoria integral de bloqueio de fonte nem que todos os achados afetam todas as rotas. As conclusões se limitam aos símbolos e caminhos descritos.
