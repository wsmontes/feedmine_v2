# FeedMine architecture

## Tese central

FeedMine é local-first/offline-first, sem servidor próprio de conteúdo. Sistemas externos repõem supply em runtime. Quando o usuário move o dedo, ele navega conteúdo local já publicado; ele não pilota a internet.

## Global adaptive operating policy

O FeedMine explora progressivamente **todo o catálogo elegível** e aproveita folga real de rede, armazenamento, memória e capacidade do dispositivo. Limites de uma operação protegem recursos; não encerram a exploração nem impõem quantidade permanente de conteúdo local. O feed visível e seu runway têm prioridade sobre trabalho especulativo.

**Sem números mágicos em decisões de volume, velocidade ou retenção:** descoberta, Acquisition, Editorial, Media, Runtime, Persistence e apresentação usam fatos observados do contexto, do sistema operacional e do próprio pipeline para priorizar e ajustar trabalho. Reavaliar em oportunidades legítimas, sem sondagem excessiva, sem prometer background ilimitado e sem criar um segundo mecanismo de coordenação. Limites numéricos são permitidos quando necessários para segurança, recursos físicos, protocolos ou testes de aceitação; não servem como estratégia para restringir o universo editorial. Idiomas explicitamente escolhidos são elegibilidade rígida, não peso.

Autoridade normativa: [norte de produto](../product/PRODUCT_NORTH_STAR.md) e [INV-16](PRODUCT_INVARIANTS.md). As descrições de fases históricas abaixo não revogam esta política de produto.

## Catálogo público: autoridade, bootstrap e reconciliação

**Autoridade editorial única:** [`wawasoft/feed-repository`](https://github.com/wawasoft/feed-repository) é o canal público versionado do catálogo *gerenciado*. O app busca **histórias diretamente das fontes externas**, nunca desse GitHub. O repositório público publica OPMLs e `manifest.json` com revisão monotônica, inventário, tamanho e hashes; não é backend de conteúdo nem recebe estado de leitura ou preferências pessoais.

**Cadeia de distribuição sem dependência na abertura:**

```text
wawasoft/feed-repository (catálogo gerenciado autoritativo)
    ├─ pipeline de release → snapshot local validado no bundle do app
    └─ atualização opcional de rede → verificação de manifest em background
                                      → download de revisão nova + validação
                                      → snapshot local staged → ativação atômica
snapshot local ativo + catálogo pessoal do usuário
    → descoberta/eligibilidade → registro gradual de targets → aquisição externa
    → supply local → seleção → preparação → publicação
```

- **Release:** empacotar a última revisão pública validada disponível durante o build; registrar revisão, procedência e integridade. O executável sempre começa com o snapshot local e deve operar sem rede. Na V2 atual, o asset `catalog.sqlite` vem da V1 e é buscado de uma *release do repositório do código V2*, não do canal público da Wawasoft: **essa reconciliação ainda precisa ser implementada e validada**, não pode ser declarada pronta só por ter 77.443 entradas.
- **Runtime:** na primeira oportunidade de launch/foreground com rede, se a última verificação bem-sucedida tiver aproximadamente 24 horas, consultar somente o manifesto em trabalho de background oportunista. Se uma sessão continuar ativa após o prazo, aproveitar uma oportunidade legítima; sem busy loop, timer arbitrário nem novo scheduler. Repetidos launches dentro da janela não baixam tudo; revisão igual é no-op. iOS offline/suspenso/encerrado adia para a próxima oportunidade, sem promessas irreais de execução fora do app.
- **Troca do catálogo:** se `revision` avançar, preparar somente uma cópia candidata completa e validá-la contra inventário, SHA-256, tamanho, formato/esquema e consistência. A entrada do catálogo público ainda não prova assinatura criptográfica; não confundir revisão manifestada, hashes e autenticação de origem. Falha preserva a última cópia válida, e a ativação deve permitir recuperação de interrupção, sem tocar `runtime.sqlite`.
- **Semântica de diff:** inserções, remoções, mudanças de URL, taxonomia, idioma, qualidade e metadados mudam descoberta/registro de aquisição **para o futuro**. Remover uma fonte gerenciada não reescreve cards publicados nem remove fontes importadas pelo usuário, salvos, históricos, coleções ou conteúdo local; a identidade estável e chaves alteradas exigem migração/reconciliação explícita. Reavaliar elegibilidade e alvos pelos donos existentes, preservando posição e runway.
- **Ownership:** leitura/staging/troca do catálogo junto da fronteira de Persistence/catálogo; decisão de disparo e composição junto do ciclo existente em Composition; descoberta e aquisição usam o fluxo normal. Não introduzir servidor, segundo catálogo editorial, segundo acquisition scheduler ou sincronizador paralelo. O catálogo público é autoridade das **fontes gerenciadas**, nunca da publicação já congelada nem do estado pessoal local.

**Gate:** testes end-to-end de snapshot empacotado, revisão igual, delta com adição/remoção/edição, falha de integridade/rede, upgrade, preservação de dados e lançamento local sem bloqueio. Requisito vinculante [PD-10](../product/PRODUCT_DECISIONS_2026-10-09.md), [INV-18](PRODUCT_INVARIANTS.md); frentes F01/F09/F10 e invariantes F05/F06. Não confundir contrato aqui descrito com implementação já entregue.

## Canonical pipeline

```text
External Systems
        ↓
Connectors
        ↓
Acquisition
        ↓
Canonical Local Supply
        ↓
Editorial Selection
        ↓
Media Preparation
        ↓
Publication
        ↓
Immutable Feed History
        ↓
Feed Session
        ↓
Presentation Snapshot
        ↓
UI
```

Acquisition adquire evidence externa e coordena admission. Supply é conteúdo canônico durável e consultável localmente, ainda sem promessa de aparecer no feed. Selection escolhe e ordena candidatos dessa supply. Media preparation transforma evidência de mídia em recursos locais que satisfazem o presentation contract. Publication congela essa seleção preparada em história imutável. Session é dona do consumo, restauração, intenções e observações. Presentation é um snapshot finito, local e imediatamente renderizável pela UI.

## Module graph

As arestas abaixo significam dependências diretas de compilação, não fluxo de dados.

```text
FeedMineDomain -> (none)
FeedMinePersistence -> FeedMineDomain
FeedMineAcquisition -> FeedMineDomain, FeedMinePersistence
FeedMineSyndication -> FeedMineDomain, FeedMineAcquisition
FeedMineEditorial -> FeedMineDomain, FeedMinePersistence
FeedMineMedia -> FeedMineDomain, FeedMinePersistence
FeedMinePublication -> FeedMineDomain, FeedMinePersistence, FeedMineEditorial, FeedMineMedia
FeedMineRuntime -> FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineEditorial, FeedMineMedia, FeedMinePublication
FeedMineUI -> FeedMineDomain, FeedMineRuntime
FeedMineComposition -> FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineSyndication, FeedMineEditorial, FeedMineMedia, FeedMinePublication, FeedMineRuntime, FeedMineUI
```

O pacote atual contém dez targets de produção e **vários** targets de testes (ver `Package.swift` vigente; a contagem inicial de dois é histórica). Utiliza Swift tools 6.0 com dependências externas **GRDB 7.11.1 somente em Persistence e FeedKit 10.9.4 somente em Syndication**, conforme `Package.swift` e `Package.resolved`. Os modelos Domain deixaram de ser o único código implementado: a V2 já tem persistência, aquisição, seleção, mídia, publicação, runtime, UI e composição. FeedMineDomain pode depender apenas de Swift standard library/Foundation, sem dependência de outro módulo FeedMine. O grafo acima continua sendo a fronteira normativa de dependências entre módulos. Veja [Domain model](DOMAIN_MODEL.md).

## Local presentation and immutable publication

A UI navega uma janela bounded de história publicada; memória limitada não limita a extensão da história. Warm launch restaura publicação e sessão e materializa uma janela local sem esperar rede, refresh de catálogo, download ou nova seleção. Offline usa o melhor estado local disponível. No primeiro launch sem supply suficiente, preparação pode legitimamente levar tempo e deverá mostrar evidência e progresso reais.

PublishedCard é um snapshot congelado, não uma projeção viva de OriginRecord. FeedSegment é ordenado e imutável. Nova acquisition modifica supply e publicação futuras, sem reordenar segmentos antigos. FeedEdition pode ter sucessoras quando a realidade editorial muda. A durabilidade publicada independe de evidence bruta temporária. Background prepara capacidade futura sem perturbar história visível.

## Publication / presentation boundary

```text
Publication
    │
    │ immutable publication semantics
    ▼
PublishedCard
    │
    │ Runtime projection
    ▼
PresentationCard
    │
    ▼
FeedPresentationSnapshot
    │
    ▼
FeedScreenStore
    │
    ▼
FeedCardView
```

Publication models are not UI models.

PresentationCard is a projection, not a second source of truth.

PublishedCard permanece estado da história publicada interna e imutável. Runtime projeta esse estado em PresentationCard local, finito e presentation-ready. FeedPresentationSnapshot apresenta esses valores pela superfície FeedSessionUI. A UI conhece PresentationCard, não PublishedCard, e não realiza a tradução. Alterações do ambiente de apresentação podem mudar a projeção sem mudar a história publicada.

## Publication / persistence boundary

FeedMinePublication owns publication semantics: PublishedCard, FeedEdition and FeedSegment.

FeedMinePersistence owns storage mechanics and local durability. Persistence must not create a parallel publication domain.

**Histórico (Phase 0):** a representação de publicação ainda estava em aberto e não podia ser criada sem resolver a fronteira. **Estado atual:** a decisão foi implementada em `PublicationStore`/`PublicationHistory` com semântica em FeedMinePublication e persistência mecânica em FeedMinePersistence. A restrição que permanece válida é não introduzir domínio paralelo de publicação, DTOs substitutos, protocolos genéricos desnecessários nem novas dependências circulares. Ver [Dependency rules](DEPENDENCY_RULES.md) e [Publication/Restore](PUBLICATION_RESTORE_CONTRACT.md).

## Adaptive runway

Scroll emite ViewportObservation, nunca loadMore ou fetchNextPage. RunwayController compara runway publicado, supply local, observação e condições operacionais e emite demanda futura. RunwayPolicy responde a velocidade de consumo, quantidade disponível, custo de acquisition, rede, background, mídia, histórico recente, contexto editorial, memória, energia e capacidade do device. Quantidades podem limitar operação, mas fixed page sizes, timers ou thresholds fixos não definem a estratégia. Após os primeiros cards, preparação continua enquanto houver benefício e orçamento. Mudanças de contexto repriorizam trabalho futuro e preservam trabalho local reutilizável quando válido.

## Confined connectors

FeedConnector pertence a Acquisition. FeedMineSyndication **já implementa** o conector concreto de RSS, Atom, JSON Feed e HTTP específico. A tradução/admission encerra representações específicas de protocolo; Selection, Publication, Session e UI recebem conceitos canônicos. Selection não busca candidatos remotamente: supply insuficiente gera demanda upstream. Publication não resolve mídia remota. A UI consome a superfície Runtime e não importa Publication para renderizar presentation cards.

## Composition root

FeedMineComposition é o único composition root e o único lugar que conhece o conjunto das implementações concretas. `FeedMineEnvironment`/`FeedMineBootstrap` registram a composição por initializer e a aplicação faz seu wiring concreto também em `AppComposition.swift`: database → stores → connector → acquisition → editorial → media → publication → runtime/session → screen store. Não existe framework de DI, container dinâmico ou service locator global. Nenhum módulo depende de Composition.

## Clean rewrite and simplicity

Existe apenas FeedMine nos nomes de produção. O projeto histórico não é base arquitetural; nenhum código foi copiado. Não há runtime de compatibilidade, caminhos alternativos ou pipeline de background separado. Cada responsabilidade possui um único owner. Não criar FeedStore, FeedRuntime monolítico, event bus, registries, managers genéricos ou protocols por testability. FeedConnector é a boundary de protocolo intencional para conectores de aquisição, já implementada e tipada. Não criar interfaces de serviços genéricos adicionais só para testabilidade.

Alarmes de tamanho futuros: FeedSession idealmente < 300 LOC; SelectionEngine < 400; PublicationCoordinator < 400; RunwayController < 300. São sinais para revisar ownership, não limites mecânicos nem justificativa para divisão artificial. (`FeedSessionReducer` foi um scaffold sem código, removido em 2026-10-15: [SCAFFOLDS.md](SCAFFOLDS.md).)

## Architecture references

- [Product invariants](PRODUCT_INVARIANTS.md)
- [Module map](MODULE_MAP.md)
- [Dependency rules](DEPENDENCY_RULES.md)
- [File responsibilities](FILE_RESPONSIBILITIES.md)
- [Implementation order](IMPLEMENTATION_ORDER.md)
