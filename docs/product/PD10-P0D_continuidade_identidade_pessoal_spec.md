# PD10-P0D — Continuidade da identidade pessoal

**Spec de implementação autorizada pelo arquiteto — P0 bloqueante para certificação geral**

## 1. Repositório, base e entrega

**Repositório:** `github.com/wsmontes/feedmine_v2`

**HEAD de referência na elaboração:** `0be556e715e8b1ae24ead422b02a0bb464788169`.

**Branch:** `chatgpt/pd10-p0d-personal-identity-continuity`

O implementador deve confirmar o HEAD do `main` antes de criar a branch e registrar a base efetiva.

O P0B (`40bc9fa1`) ainda aguarda medição nativa e o P0C (`b0cab431`) já recebeu autorização condicional de merge técnico. **Não integrar nenhum deles por conta própria.**

A implementação do P0D pode começar agora, independentemente desses gates. Se a integração posterior mudar contratos relevantes, reconciliar sobre o `main` validado, sem copiar implementações paralelas.

**Entrega:** branch isolada, commits identificados, testes, auditoria de invariantes e instruções de validação no Mac.

**Proibidos:** merge, upload TestFlight, alteração do repositório público, modificação de evidências congeladas e publicação de release.

## 2. Objetivo

Garantir que **alterações do catálogo público nunca provoquem perda, duplicação ou reatribuição silenciosa da identidade pessoal de fontes e das associações que o leitor criou**.

Isso inclui:

- Fontes selecionadas ou seguidas;

- fontes adicionadas manualmente;

- fontes importadas por OPML;

- associações com coleções pessoais;

- salvos, caixas e histórico;

- contextos e presets persistidos;

- identidades de aquisição utilizadas pela sessão;

- relações entre chaves antigas, chaves novas e endpoints de aquisição.

A regra central é:

**O catálogo pode substituir sua representação editorial de uma fonte. Não pode substituir silenciosamente a identidade, as escolhas ou o histórico pessoal do leitor.**

A atualização do catálogo continua sendo não bloqueante para o feed. P0D não introduz dependência de rede para restaurar dados pessoais.

## 3. Evidência inicial no código

Os pontos abaixo foram confirmados no repositório e devem orientar a implementação.

### D-DEF1 — Seleção apagada por reconciliação de disponibilidade

`FeedMineApp/FeedMineApp/AppComposition.swift:220–226`

O startup resolve a seleção persistida por `TrustedFeed.resolveAvailable` e pode chamar `preferences.updateSources(resolved.map(\.principal))`.

Esse comportamento confunde duas coisas distintas:

1. Uma fonte que o leitor selecionou.

2. Uma fonte que o catálogo atualmente consegue resolver.

A segunda não autoriza apagar a primeira.

**Correção obrigatória:** disponibilidade operacional não pode ser usada como autorização implícita para substituir preferências duráveis.

### D-DEF2 — A autoridade muda a identidade de uma fonte

`FeedMineApp/FeedMineApp/TrustedFeeds.swift`

`resolveAvailable` prioriza a entrada do catálogo, depois a entrada importada pelo leitor, depois o fallback.

As duas origens utilizam namespaces distintos para SourceID, TargetID e BindingID.

O próprio código identifica o problema: quando o catálogo deixa de conter uma fonte também importada, a resolução pode passar do namespace do catálogo ao namespace pessoal.

**Correção obrigatória:** uma mudança de disponibilidade ou de representação editorial não pode remapear silenciosamente uma identidade pessoal já estabelecida.

### D-DEF3 — Importação e coleções dependem de igualdade literal

`ReaderLibraryStore.swift` utiliza:

- `reader_imported_sources.key`;

- `reader_collection_memberships.source_key`;

- `reader_preferences.source_keys`.

As operações atuais preservam esses valores, mas não têm um contrato completo para reconhecer uma mudança de chave canônica.

Uma chave nova pode passar a representar a mesma fonte sem ser reconhecida como tal.

### D-DEF4 — Chave de identidade e endpoint são distintos

`FeedAddress.identity` define a identidade canônica.

`FeedAddress.request` mantém o endereço efetivamente consultado, inclusive parâmetros necessários à requisição.

`LegacyCatalogImport` deriva identificadores estáveis da chave canônica.

**Não alterar a identidade para acompanhar cada mudança de URL.** A URL de aquisição pode mudar sem que a fonte editorial deixe de ser a mesma.

### D-DEF5 — O catálogo não publica atualmente um mapa explícito de aliases

O manifesto público contém revisão, inventário e hashes dos OPMLs. Não contém um contrato separado de migração de chaves.

Portanto, o P0D não pode assumir que toda mudança de identidade seja verificável automaticamente.

Quando não houver prova suficiente para estabelecer equivalência entre chaves, **preservar a associação antiga como não resolvida é obrigatório; adivinhar uma equivalência é proibido**.

## 4. Allowlist

### Arquivos de produção

**Persistência**

1. `Sources/FeedMinePersistence/ReaderLibraryStore.swift`

2. `Sources/FeedMinePersistence/RuntimeMigrations.swift` — somente uma migração aditiva, se comprovadamente necessária.

**Composição e identidade**

1. `Sources/FeedMineComposition/ReaderSourceIdentity.swift`

2. `Sources/FeedMineComposition/LegacyCatalogImport.swift`

3. `Sources/FeedMineComposition/ReaderImportExportCoordinator.swift`

4. `Sources/FeedMineComposition/ReaderAddFeedAdapter.swift`

5. `Sources/FeedMineComposition/ReaderLibraryCoordinator.swift`

**Integração no aplicativo**

1. `FeedMineApp/FeedMineApp/TrustedFeeds.swift`

2. `FeedMineApp/FeedMineApp/AppComposition.swift`

O implementador não precisa modificar todos esses arquivos. A preferência é pelo menor conjunto que satisfaça os invariantes.

### Testes

1. `Tests/FeedMinePersistenceTests/ReaderLibraryStoreTests.swift`

2. `Tests/FeedMinePersistenceTests/RuntimeMigrationTests.swift`

3. `Tests/FeedMineCompositionTests/ReaderSourceIdentityTests.swift`

4. `Tests/FeedMineCompositionTests/ReaderImportExportCoordinatorTests.swift`

5. `Tests/FeedMineCompositionTests/ReaderAddFeedAdapterTests.swift`

6. `FeedMineApp/FeedMineAppTests/CompositionTests.swift` — exclusivamente novos casos de aceitação de identidade pessoal.

Um arquivo novo de testes dentro desses alvos poderá substituir um dos arquivos de teste existentes, desde que o alvo reconheça o arquivo sem alterar o projeto Xcode.

### Documentação

1. `docs/reviews/PD10-P0D_IDENTITY_CONTINUITY_EVIDENCE.md` — novo.

**Allowlist máxima: 16 arquivos, contando a evidência.** Não há obrigação de utilizar todas as entradas.

### Arquivos protegidos

Não modificar:

- `bench/`;

- `ReaderPreferencesStore.swift`, atualmente envolvido no P0B;

- `SourceManagementCoordinator.swift`, atualmente envolvido no P0B;

- `CatalogInstallation.swift`;

- `CatalogUpdater.swift`;

- `RuntimeDatabase.swift`;

- `Package.swift`;

- `project.pbxproj`;

- mecanismos de runway, aquisição, mídia e publicação.

Uma migração aditiva poderá utilizar `RuntimeMigrations.swift`, mas nunca reescrever migrações antigas nem reconstruir tabelas históricas desnecessariamente.

Se um defeito exigir outro owner, apresentar o arquivo, a linha e o menor ajuste necessário para autorização específica.

## 5. Contratos de aceite

### D1 — Seleção pessoal é durável, mesmo quando uma fonte desaparece

Dada uma seleção persistida com A, B e C:

- Revisão 5 contém A, B e C.

- Revisão 6 remove B do catálogo gerenciado.

- A sessão passa a enxergar a revisão 6.

**Resultado obrigatório:**

- `reader_preferences.source_keys` continua contendo a escolha B.

- A versão da seleção não aumenta somente por essa mudança de disponibilidade.

- A e C continuam utilizáveis.

- B permanece identificável como escolha pessoal não resolvida, ou utilizável por uma entrada importada válida.

- B não é substituída por um feed de fallback sem relação comprovada.

- Nenhuma fonte é automaticamente desselecionada.

O leitor pode remover B explicitamente depois. O catálogo não pode tomar essa decisão por ele.

### D2 — Chaves canônicas diferentes podem representar uma identidade contínua

Dados:

- Uma chave antiga A.

- Uma chave nova B.

- Evidência verificável de que ambas representam a mesma fonte.

- Uma seleção ou associação pessoal que já utilizava A.

**Resultado obrigatório:** a fonte permanece logicamente selecionada e não se transforma em duas fontes independentes.

A equivalência deve ter procedência explícita, fundamentada em revisões verificadas ou evidência inequívoca dos registros. Identidade de URL canonicalizada pode ajudar na verificação, mas igualdade de host, nome ou título não basta.

O mecanismo deve recusar ou deixar sem resolução:

- Equivalência ambígua;

- alias conflitante;

- dois destinos incompatíveis;

- ciclos de aliases;

- evidência de revisão incompatível;

- associação sem prova suficiente.

Uma nova revisão pública não pode transformar uma suposição editorial em alteração durável de dados pessoais.

### D3 — Alias é uma relação durável, não uma nova autoridade

Se for necessário persistir aliases, utilizar a autoridade de dados pessoais já existente.

Uma única estrutura aditiva mínima poderá registrar:

- Chave anterior;

- chave reconhecida na revisão atual;

- identidade/procedência da equivalência;

- revisão ou fingerprint utilizado para verificar a associação.

A forma exata deve ser definida pelo owner de persistência e comprovada nos testes.

**Não criar cache de catálogos, índice alternativo do feed, controlador de migrações ou scheduler de reconciliação.**

Um mapa durável de aliases, se necessário, existe para preservar referências pessoais, não para substituir o catálogo público.

A resolução deve ser determinística, finita e segura contra ciclos.

### D4 — Fonte importada e fonte gerenciada coincidentes não geram duas assinaturas

Cenário:

1. O leitor importa `https://example.com/feed` por OPML.

2. A fonte também existe no catálogo público.

3. A seleção inclui a fonte.

4. O catálogo é atualizado, removido ou restaurado.

**Resultado obrigatório:**

- Uma única fonte lógica selecionada;

- uma única oportunidade de aquisição equivalente para essa fonte no contexto;

- nenhuma duplicação de TargetID/BindingID ativos por mudança de autoridade;

- importação idempotente;

- título e endereço de requisição próprios preservados na biblioteca pessoal;

- nenhuma exclusão da entrada pessoal pelo simples fato de existir representação gerenciada.

A solução deve preservar a identidade historicamente estabelecida. Não trocar indiscriminadamente o namespace atual de todas as importações para obter deduplicação.

Se a representação gerenciada desaparecer, a fonte importada continua disponível por seu endpoint válido sem sofrer remapeamento silencioso de identidade.

### D5 — Endpoint pode mudar sem destruir identidade

A mudança de `request_url` não é, isoladamente, uma mudança de fonte.

O implementador deve demonstrar:

- Identidade editorial estável quando a chave permanece a mesma;

- endpoint atualizado para trabalho futuro quando a origem gerenciada o declara;

- preservação do endpoint pessoal importado quando ele pertence ao usuário;

- retenção de parâmetros necessários à requisição;

- não utilização de URL assinada como identidade de usuário;

- ausência de fusão automática entre fontes diferentes apenas porque compartilham host, título ou redirecionamento aparente.

Não executar rede apenas para decidir identidade no cold launch.

### D6 — Coleções e seleções continuam apontando para as mesmas fontes lógicas

Uma coleção contendo A continua contendo essa fonte após uma substituição canônica A → B comprovada.

A implementação poderá manter a chave antiga com resolução por alias ou realizar uma alteração transacional explícita dos dados pessoais, desde que preserve integralmente as associações.

A decisão deve ser única e consistente.

**Não aceitar um híbrido em que a seleção usa B, a coleção mantém A e apenas uma das duas superfícies sabe resolver o alias.**

Também não aceitar duplicação de memberships quando ambas as chaves já existiam na mesma coleção.

A ordem, o nome e o ID da coleção permanecem iguais.

### D7 — Salvos, caixas, histórico e cards publicados são intocáveis

Atualizações do catálogo e reconciliações de identidade não devem modificar:

- `published_cards`;

- `feed_editions`;

- segmentos e ordem publicados;

- estado de leitura;

- checkpoints e âncoras;

- memberships de bookmarks;

- IDs de cards salvos;

- caixas pessoais e suas posições;

- histórico de consumo;

- conteúdo e mídia já associados a ocorrências publicadas.

Uma ocorrência histórica mantém sua identidade e atribuição congeladas.

A equivalência entre chaves serve à resolução futura, não à reescrita retroativa da publicação.

A prova deve comparar dados reais antes e depois, não apenas verificar se algumas contagens permanecem iguais.

### D8 — Atualização e reconciliação são atômicas na fronteira correta

Uma reconciliação que precise alterar dados pessoais utiliza a transação já existente em `RuntimeDatabase.write`, por intermédio de seu owner de persistência.

Exigir:

- Todas as relações pessoais pertinentes preservadas ou atualizadas juntas;

- erro antes do commit sem alteração parcial;

- reexecução idempotente;

- ausência de alteração quando a revisão e as relações não mudaram;

- nenhuma substituição de seleção por resultado de leitura de catálogo;

- nenhuma destruição de dados para facilitar recuperação.

A instalação do catálogo e a transação pessoal têm autoridades diferentes. O P0D não deve incorporá-las numa transação impossível entre SQLite e arquivos do catálogo.

A reconciliação pessoal falha de forma segura, com os dados anteriores intactos. Uma falha não autoriza rollback destrutivo do catálogo nem interrupção do feed já publicado.

### D9 — Abertura offline e reabertura preservam as escolhas

Testar os seguintes estados:

1. Instalação limpa com catálogo válido.

2. Biblioteca pessoal preenchida.

3. Catálogo atualizado.

4. Reabertura offline.

5. Nova tentativa com a mesma revisão.

6. Falha de atualização ou dados de alias inválidos.

7. Restauração de uma revisão anterior, quando oferecida pelo mecanismo existente.

As preferências, importações, coleções e salvos devem continuar disponíveis.

Uma fonte não resolvida deve ser tratada como tal, não como fonte que o leitor jamais selecionou.

Nenhuma dessas etapas pode exigir baixar o catálogo antes de restaurar a apresentação local.

### D10 — Importação e exportação preservam a identidade pessoal

Para uma fonte importada que também aparece no catálogo:

- Importar duas vezes não duplica a fonte lógica.

- A seleção continua correta.

- Uma coleção opcional recebe a fonte uma única vez.

- Exportar a seleção ou a coleção preserva um endereço efetivamente utilizável.

- Exportar e importar novamente não produz outra identidade sem necessidade.

- Um alias antigo não se transforma numa URL inventada.

- Parâmetros necessários para buscar o feed permanecem no `requestURL`, sem virar indevidamente identidade.

Uma equivalência que não possa ser comprovada deve continuar distinta ou não resolvida, com comportamento explícito, em vez de ser fundida silenciosamente.

## 6. Política de resolução

O implementador deverá propor e testar uma única política de resolução com as seguintes propriedades:

**Primeiro:** identificar a escolha pessoal armazenada, sem modificá-la.

**Segundo:** consultar relações de identidade já comprovadas.

**Terceiro:** resolver a representação atual usando o catálogo instalado e a entrada importada do leitor.

**Quarto:** produzir no máximo uma representação ativa por fonte lógica, preservando identidade e endpoint conforme a autoridade aplicável.

**Quinto:** se a resolução falhar, manter a escolha durável sem fabricar equivalência ou fallback.

Não usar a disponibilidade da fonte para determinar se o usuário continua seguindo-a.

Não usar número de revisão como parte da identidade permanente da fonte.

Não usar um ID numérico interno do SQLite do catálogo como ID pessoal.

Não alterar os namespaces históricos de `LegacyCatalogImport` e `ReaderSourceIdentity` sem demonstrar como os identificadores previamente persistidos continuam resolvíveis.

A política deve distinguir claramente **identidade pessoal**, **chave canônica gerenciada**, **representação editorial**, **endpoint de aquisição** e **identidade de ocorrência publicada**.

## 7. Provas determinísticas obrigatórias

Preparar fixtures locais com dois catálogos compilados válidos, de revisões distintas, sem HTTP público e sem depender de dados ao vivo.

A suíte deve provar, no mínimo:

| Caso | Cenário | Resultado obrigatório |
|---|---|---|
| P1 | A selecionada desaparece na revisão seguinte | Seleção durável preservada |
| P2 | A → B com equivalência comprovada | Uma identidade lógica, associações preservadas |
| P3 | A → B sem prova suficiente | Nenhuma fusão inventada; A preservada |
| P4 | Dois candidatos B/C para A | Ambiguidade recusada |
| P5 | Alias conflitante ou cíclico | Recusa sem alteração parcial |
| P6 | Fonte importada também existe no catálogo | Uma representação ativa coerente |
| P7 | Fonte importada deixa de existir no catálogo | Identidade pessoal preservada |
| P8 | Endpoint muda, chave permanece | Identidade igual; aquisição futura usa endpoint correto |
| P9 | Coleção contém chave antiga | Membership e resolução preservados |
| P10 | Salvos e caixas anteriores à mudança | IDs, vínculos e conteúdo idênticos |
| P11 | Falha transacional durante reconciliação | Nenhuma alteração parcial |
| P12 | Repetição após sucesso | Idempotência; nenhuma duplicação |
| P13 | Reabertura offline após atualização | Biblioteca preservada e utilizável |
| P14 | Importação OPML repetida após mudança | Sem duplicação de seleção ou coleção |
| P15 | Exportação → importação | Endpoints pessoais e identidades preservados |
| P16 | Atualização durante sessão com cards publicados | Nenhuma mudança na apresentação existente |

As provas negativas precisam demonstrar que o caso realmente chegou à fronteira testada.

Quando a característica depende do app, apresentar teste de composição nativo, e não somente teste unitário de uma função de mapeamento.

Não introduzir `sleep`, timer ou polling para forçar ordem de execução. Utilizar fixtures, barreiras controladas ou continuations quando necessário.

## 8. Limitações e fronteiras

### Migração V1 → V2

**Fora do escopo.**

Importar bancos históricos da V1 é diferente de preservar referências pessoais da V2 diante de mudanças do catálogo.

P0D não pode declarar resolvida a migração V1 → V2.

### Histórico publicado

Preservar o histórico é obrigatório. Reescrever IDs antigos para simplificar aliases é proibido.

### Autoridade pública

Não modificar `wawasoft/feed-repository` nem inventar um campo de aliases no manifesto público nesta tarefa.

Quando faltar evidência pública suficiente para reconhecer uma mudança de chave, preservar dados pessoais como não resolvidos é o resultado correto.

A implementação não pode declarar que identificou automaticamente equivalências que o canal ainda não documenta.

### Continuidade do feed

A reconciliação não pode interromper o feed já apresentado, cancelar aquisições válidas por mera troca de metadados, deslocar cards ou forçar reconstrução de uma Edition.

Novas fontes e endpoints afetam oportunidades futuras, nos limites do fluxo já existente.

### Orçamento arquitetural

Não criar novo scheduler, sincronizador, cache de catálogo, fila, timer, pipeline de importação ou mecanismo de retry.

Uma relação durável mínima de aliases é admissível somente se necessária para preservar a identidade pessoal, com owner e transação definidos.

## 9. O que `main` deve passar a garantir

Após integrar P0D, qualquer revisão do catálogo deve respeitar estes invariantes:

**G1.** Nenhuma fonte selecionada é excluída das preferências apenas por não constar no catálogo atual.

**G2.** Uma importação pessoal não desaparece quando a versão gerenciada da fonte é removida.

**G3.** A mesma fonte lógica não cria duas assinaturas operacionais por coexistir na biblioteca pessoal e no catálogo público.

**G4.** Mudanças de chave comprovadas preservam associações pessoais.

**G5.** Mudanças de chave não comprovadas não produzem equivalências inventadas nem exclusões silenciosas.

**G6.** Coleções, salvos, caixas e histórico continuam íntegros após uma atualização, rollback ou reabertura offline.

**G7.** Reconciliações são transacionais, idempotentes e recuperáveis.

**G8.** O runtime continua local-first, e nenhuma reconciliação interfere na geometria ou identidade das ocorrências já publicadas.

**G9.** Importar/exportar fontes não perde endpoints pessoais nem introduz duplicações desnecessárias.

**G10.** A identificação de uma fonte não depende de um número fixo de revisão ou do ID interno do SQLite do catálogo.

## 10. Sequência de implementação

O trabalho deve seguir esta ordem:

**Etapa A — contrato de identidade**

Mapear exatamente como `TrustedFeed`, `LegacyCatalogImport`, `ReaderSourceIdentity`, `ReaderLibraryStore` e `AppComposition` decidem as identidades atuais.

Documentar com casos concretos as diferenças entre chave gerenciada, fonte pessoal e endpoint.

**Etapa B — eliminar a perda destrutiva**

Corrigir primeiro o caminho de startup que substitui `source_keys` pela lista resolvida.

Introduzir regressões que demonstram a preservação das escolhas quando uma fonte fica indisponível.

**Etapa C — continuidade de aliases e importações**

Implementar a menor relação durável necessária para reconhecer equivalências comprovadas e preservar fontes não resolvidas.

Corrigir a duplicidade de representações gerenciadas/pessoais sem trocar silenciosamente IDs estabelecidos.

**Etapa D — integração de coleções e exportação**

Garantir que a política seja a mesma em seleção, coleção, importação e exportação.

Não criar reconciliações independentes para cada superfície.

**Etapa E — aceitação nativa**

Executar as provas de atualização, reabertura offline e preservação da publicação existente.

Conferir o resultado depois de uma nova inicialização, não apenas na mesma instância do store.

## 11. Validação

Obrigatório, conforme recursos disponíveis:

- `git diff --check`;

- `swift build`;

- `swift test`;

- filtros relevantes de identidade, biblioteca, importação e persistência;

- testes nativos de composição;

- regressões de publicação e restauração afetadas pelo diff.

A medição no Mac deve registrar SHA, árvore, testes executados, exit codes, falhas, skipped e condições de espaço.

Não declarar PASS para testes não executados.

A execução deverá permanecer serializada enquanto o disco estiver pressionado. A barra de 10 GB do B03 não será alterada para facilitar esta tarefa.

## 12. Auditoria de encerramento

Entregar uma matriz para cada contrato D1–D10:

- `ATENDE`;

- `PARCIAL`;

- `NÃO ATENDE`;

- `NOT_RUN`;

- `BLOCKED`.

Cada classificação deve citar arquivo, linha, teste e asserção relevante.

O revisor independente deverá verificar especialmente:

1. Se a seleção antiga continua durável mesmo quando não pode ser resolvida.

2. Se um alias ambíguo pode fundir fontes diferentes.

3. Se importações gerenciadas/pessoais podem duplicar aquisição.

4. Se o sistema troca IDs históricos quando muda a autoridade.

5. Se uma migração pode alterar apenas metade das associações.

6. Se os testes realmente reabrem o mesmo banco pessoal após a atualização.

7. Se algum caminho ainda interpreta ausência no catálogo como autorização para apagar dados.

**Critério de encerramento:** nenhuma atualização de catálogo pode causar perda silenciosa, fusão sem prova ou duplicação operacional de identidade pessoal; onde não houver prova suficiente de equivalência, as relações anteriores permanecem duráveis e recuperáveis.

**Não confundir P0D tecnicamente aceito com certificação geral de release.** B03, B06 e os demais bloqueios continuam independentes.

---

**Decisão do arquiteto:** implementação autorizada dentro da allowlist. Nenhum merge sem auditoria independente e evidências de preservação durável dos dados pessoais.
