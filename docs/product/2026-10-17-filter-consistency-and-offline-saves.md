# Filtros consistentes e salvos offline — encaminhamento consolidado

Data: 2026-10-17 (America/Vancouver).
Origem: solicitação explícita do dono para reunir o achado reservado de filtros com a especificação do significado de salvar/offline. Somente documentação; não altera app, banco, testes ou benchmarks.

## 1. Reutilizar o contrato de filtros existente

Não criar outra arquitetura de contextos. As specs `docs/superpowers/specs/2026-10-09-reader-contexts.md` e `2026-10-09-reader-filters-and-context-identity.md` já definem identidade completa por combinação, checkpoints próprios, retorno A→B→A, rejeição de callbacks antigos e expiração aplicada em transição explícita. Existem implementação e testes correspondentes, incluindo `ContextIdentityPersistenceTests` e `ReaderFilterStore`.

### Achado de integração a resolver/verificar

Na base inspecionada `6cbaa2fee3445e92957f9172d756cbbed4609108`, `AppComposition.applyFilter` (~665–674) atribui `currentContextKey` antes de concluir `preferences.setContext`, depois grava expiração em outra operação e chama `replaceSession`. A leitura demonstra etapas distintas e alteração antecipada da memória; **não demonstra uma falha de disco reproduzida**.

Contrato exigido: a conclusão de aplicar filtro deve distinguir seleção confirmada de falha de persistência e falha posterior de apresentação. Não deixar filtro indicado, seleção durável e sessão exibida divergirem silenciosamente. Falha anterior à confirmação preserva ou restaura o estado coerente anterior; seleção já confirmada seguida de falha na apresentação deve continuar identificável e recuperável, sem afirmar falsamente que nada foi salvo. Não exigir uma transação de banco que englobe rede ou operações assíncronas; a solução deve preservar os owners existentes e ter fronteira explícita de confirmação.

Não reabrir o vermelho histórico A→B→A de 12/out como defeito atual sem conferir as correções/evidências posteriores. Este item não substitui os contratos T6 nem altera o comportamento de aplicar ao dispensar a folha.

## 2. Especificar primeiro o significado de salvo offline

**Salvar deve preservar uma unidade durável de leitura local, e não apenas marcar uma referência cujo conteúdo dependa do cache descartável.** A especificação antecede a escolha de teste e de implementação: não decidir o significado de "salvo" pelo que o código atual consegue reabrir.

### Conteúdo da unidade salva

- Identidade do artigo/ocorrência e da caixa, título, origem, URL, datas e demais metadados disponíveis necessários para reconhecer e abrir o salvo.
- Texto local efetivamente disponível na confirmação, preservado como snapshot consistente. Se o app só possui resumo ou metadados, não afirmar que conservou o artigo completo. Ausência de corpo integral deve ser informada; este requisito não autoriza inventar texto nem promete recuperar qualquer página remota.
- Arquivos locais de mídia integrantes da apresentação salva, quando presentes, com referências duráveis e integridade preservada. Eles não podem continuar sujeitos à mesma eliminação indiscriminada do cache temporário.
- Se a apresentação offline ainda não está disponível, distinguir explicitamente o vínculo salvo da disponibilidade do conteúdo: "salvo" não pode simular uma conclusão de preparação/download que não ocorreu. Uma falha de preparação deve permanecer visível e recuperável, sem perder a intenção de salvar.

A ausência de rede na reabertura não pode tornar inacessível o snapshot que já foi confirmado como disponível offline. Abrir no site permanece ação explícita e distinta de ler a cópia local.

### Cache, memória e limpeza

**Imagem decodificada em RAM não é dado durável.** Não é requisito conservar `CGImage`/`UIImage` entre execuções, nem impedir liberação de memória. O que precisa sobreviver é o arquivo local e a informação necessária para reconstruir a apresentação.

Decodificar uma imagem local antes de admitir sua apresentação é compatível com offline. Expor uma apresentação incompleta e completá-la depois continua proibido pela diretriz `2026-10-17-render-ready-admission-rule.md`.

Limpeza de cache, pressão de memória e limpeza automática de disco não removem silenciosamente o conteúdo protegido dos salvos. A política pode compartilhar blobs por referências em vez de duplicar arquivos; precisa distinguir referências protegidas e descartáveis. Falta de espaço deve produzir falha/estado parcial explícito antes de prometer disponibilidade, sem apagar salvos antigos como efeito colateral.

Se houver comando explícito para remover downloads de salvos mantendo vínculos, ele deve declarar essa consequência antes da ação e atualizar a disponibilidade apresentada. "Limpar cache" não deve ocultar uma operação destrutiva sobre a biblioteca offline. Excluir um salvo e excluir sua caixa também exigem semântica definida para mídia compartilhada e referências em outras caixas.

### Consistência e recuperação

A confirmação de disponibilidade offline vincula registro e conteúdo local consistente. Interrupção, falha de gravação e relançamento não podem produzir sucesso falso ou perda silenciosa. Preferir referências e transações dos owners atuais a um segundo banco/pipeline de salvos.

Não confundir: bookmark, conteúdo disponível offline, cache de navegação e migração V1→V2. São promessas relacionadas, mas nenhuma implica automaticamente que as outras estão satisfeitas.

## 3. Correção de precisão da conversa

A fala anterior atribuiu superioridade global à V1 em salvos/offline e sugeriu que perder uma imagem **decodificada** ao limpar cache contrariaria offline. Essa conclusão não foi sustentada nesta sessão por inspeção completa dos caminhos de salvamento e limpeza das duas versões. Não a usar como achado técnico confirmado.

A inspeção anterior de `FeedSession`/`PresentationImageDecoder` trata residência de pixels e reconstrução a partir de assets locais; por si só não demonstra perda de arquivos protegidos de bookmarks. Este commit registra a especificação solicitada pelo dono, não uma reprodução dessa perda nem certificação histórica da V1.

## 4. Encaminhamento único aos implementadores

1. Reconciliar este contrato com as specs vigentes de biblioteca, offline, armazenamento e migração antes de criar código ou mais especificações. Citar o documento existente quando o requisito já estiver coberto.
2. Mapear o caminho real de salvar → snapshot → proteção/retenção de arquivos → leitura offline → limpeza. Declarar exatamente o que já está implementado, o que falta e quais promessas a UI faz hoje.
3. Fechar a fronteira de confirmação dos filtros e a semântica durável de salvar nos donos existentes. Sem reescrever histórico publicado, sem nova seleção paralela e sem modificar benchmarks congelados.
4. Depois de definido e implementado o contrato, produzir provas discriminantes de falha/recuperação, reinício offline e limpeza de cache. Testes verificam o contrato; não escolhem retroativamente o que "salvo" significa.

Este commit não afirma que houve execução no Mac/iPhone, perda real de conteúdo ou correção implementada. As decisões de produto são explícitas; suspeitas de integração e lacunas de inspeção permanecem identificadas como tais.
