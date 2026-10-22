# FeedMine V2 — mapa de produto e estado real

Data: 20/out/2026, America/Vancouver. Reconciliação inicial do produto, feita para responder o que o leitor deve conseguir, o que já existe e o que falta entregar. Não é certificação nem novo PRD.

## Diagnóstico executivo

O FeedMine já tem uma implementação ampla de leitor, descoberta e biblioteca. A build 1.0 (53), commit `568098db`, foi distribuída para avaliação interna pelo TestFlight. Ainda não temos evidência suficiente de que a promessa central seja cumprida: abrir e explorar conteúdo interessante, diverso e multimídia, com primeira tela pronta, rolagem fluida e retorno confiável no aparelho.

A fase é **beta funcional para avaliação**, com problemas observados e lacunas de experiência. Não é apenas acabamento nem somente instrumentação B06 pendente. Disponibilidade no TestFlight e quantidade de testes não mudam esse diagnóstico.

## Base e limites desta reconciliação

- Produto inspecionado: `/Users/wagnersilvamontes/.codex/worktrees/v2-fluidez-capacidade/feedmine_v2`, HEAD `568098db0571dda630b19ef5d11ee4323c5df150`.
- UI completa registrada em `4baf9045`: 76 testes, 9 skips, zero falhas. B01–B05 registrados como PASS nesse produto. O delta de produto até `568098db` é vazio; só mudou o script B06.
- A distribuição ASC foi relatada como `VALID` / `IN_BETA_TESTING`. O log local de upload contém `Uploaded FeedMine` e `EXPORT SUCCEEDED`.
- Corrida física `bench/run/20261020T152325Z`: B03 FAIL, 1.155/1.800 avanços; B06 INCOMPLETE. Recorders de energia **e hitches** terminaram antes do esperado. Nenhum desses resultados prova desempenho multimídia.
- O usuário observou no aparelho: feed só de texto; exposição inicial de um card com preenchimento posterior; mensagem “Falha ao atualizar o feed”. São relatos de produto em aberto, a reproduzir e correlacionar com a build/execução. Não os reclassificar como problemas de teste sem diagnóstico.
- Os testes novos `FeedVisibleExperienceUITests` e `FeedMediaJourneyUITests` foram anunciados como trabalho em andamento. Ainda não há resultado aceito nesta reconciliação.
- Esta análise leu código, requisitos, inventários e artefatos existentes, com revisões independentes por domínio. Não executou outra suíte longa nem manipulou o aparelho.
- A análise é do conjunto de requisitos **documentados e conhecidos**. Não alega descobrir todos os defeitos nem substituir uma avaliação humana do produto.

## O produto que estamos tentando entregar

Uma pessoa que não conhece RSS abre o aplicativo, orienta sua curiosidade sem administrar dezenas de assinaturas, encontra histórias interessantes de fontes diferentes, lê/ouve/assiste, guarda algo, muda de assunto e continua. Ao voltar, reconhece o lugar e aproveita o conteúdo local, inclusive offline.

As sete jornadas que definem sucesso são:

1. **Começar:** entrar em descoberta útil, com preferências opcionais e preparação honesta; quando o feed aparece, a área útil de leitura já está preenchida com conteúdo pronto.
2. **Explorar:** obter variedade relevante de fontes, assuntos, idiomas escolhidos e formatos, com oferta preparada adiante do consumo.
3. **Consumir:** imagem de verdade, artigo correto e legível, episódio audível e vídeo efetivamente visível; retornar sem perder o ponto.
4. **Controlar:** buscar, filtrar, mudar contexto, responder convites, excluir e desfazer, compreendendo o efeito.
5. **Guardar:** salvar e organizar conteúdo, perceber o que estará disponível offline e recuperar depois.
6. **Retomar:** reabrir, voltar do background ou retornar A→B→A preservando conteúdo e posição; erros recuperáveis não destroem a leitura.
7. **Confiar:** instalação e atualização preservam dados pessoais; catálogo tem origem conhecida; acessibilidade, recursos e integrações funcionam nas condições reais do aparelho.

## Como ler os estados

- **Funcional com evidência focal:** caminho implementado e exercitado em cenários identificados; não significa toda a experiência aprovada.
- **Parcial:** parte implementada/provada, mas faltam comportamentos exigidos ou provas importantes.
- **Problema observado:** usuário ou artefato mostra desvio; causa e alcance podem continuar em investigação.
- **Não demonstrado:** há requisito/código, mas não evidência suficiente da experiência.
- **Lacuna funcional identificada:** caminho necessário não foi localizado ou é explicitamente incompleto; confirmar o escopo antes de anunciar entregue.
- **Disponível:** estado de distribuição, sem significado de aprovação pública.

Não calcular percentual de produto pronto a partir destas linhas ou do número de testes.

## Inventário das 27 frentes conhecidas

### A. Descobrir e consumir — F01 a F10

| Frente / funcionalidades incluídas | Estado do produto | O que sustenta / o que falta |
|---|---|---|
| **F01 Descoberta e catálogo:** idiomas, países, temas; descoberta automática; fontes seguidas; catálogo público embarcado e atualização | **Parcial, com evidência focal forte de descoberta controlada** | Catálogo de 77.443 fontes/revisão 5 embarcado e validado no archive; B01 com perfis distintos; Brasil real com perfil `pt`/Brazil e alvos comprovados. Faltam avaliação da descoberta real sem pré-configuração e cobertura percebida em mais idiomas/formatos; grande catálogo não comprova exploração útil de todo o universo elegível. |
| **F02 Primeira experiência:** entrada opcional por interesses, preparação factual, primeira tela, convites, respostas/desfazer/ocultar/reabilitar | **Parcial; primeira exposição com problema observado** | Convites e reabilitação corrigidos; teste de oferta no catálogo real passou. O usuário vê um card antes do restante. A condição atual de entrada admite feed não vazio, sem provar preenchimento da área útil. Falta jornada neutra convincente e inspeção visual do primeiro conteúdo. |
| **F03 Histórias válidas:** RSS/Atom/JSON Feed, redirects, datas, texto legível, originalidade, link consumível, acesso real | **Parcial** | Parsing, identidade, texto e links têm implementação; há regressões de deduplicação e abertura. Frescor contextual, acesso sem paywall e integridade em ampla variedade real não estão demonstrados integralmente. Datas disponíveis não provam todas as regras editoriais de envelhecimento. |
| **F04 Qualidade editorial:** relevância, diversidade, alternância de fontes, idioma rígido, evitar repetição, preferências explícitas | **Funcional com evidência focal; qualidade percebida aberta** | B02 controlado: 200/200 relevantes, 79 fontes, máximo 4,5%, sem adjacências/duplicatas; diversidade e fatos persistidos presentes. Falta avaliar interesse, surpresa e monotonia com histórias reais e perfis variados. Rótulo sintético não equivale a qualidade de leitura. |
| **F05 Exploração contínua:** abastecimento antecipado, chegada tardia sem gesto, fontes lentas isoladas, adaptação a consumo/recursos | **Parcial; falha física medida sem causa fechada** | Correções de ownership/coalescência e regressões específicas; B03 simulador PASS. B03 físico 1.155/1.800 FAIL; driver emitiu cerca de 0,55 gesto/s. Separar custo do XCTest, UI e abastecimento antes de atribuir causa. Falta validar com mídia e uso real. |
| **F06 Apresentação:** textos, imagens/hero/thumbnail, identidade da fonte, cards estáveis, prontidão antes da exposição | **Parcial; carga representativa não demonstrada** | Código de imagem local e contratos de não mudar cards presentes. Corrida física foi toda textual, sem qualquer candidato de mídia persistido. Faltam imagens reais compostas, tamanhos/aspectos variados, mistura de conteúdo e retomada sob pressão. |
| **F07 Controle de contexto:** pesquisa, filtros combinados, idiomas/temas/tipo/região, lentes, A→B→A | **Funcional com evidência focal** | Identidades persistidas, filtros confirmados no disco, escopos e retorno têm provas. Falta exercício integrado com escolhas variadas, conteúdo multimídia, todos os caminhos de limpar/cancelar e entendimento do efeito pelo leitor. |
| **F08 Leitura e ações:** abrir artigo, site, fonte; voltar; salvar; copiar/compartilhar; organizar | **Funcional com evidência focal** | Leitor local e Safari interno; três testes físicos de site passaram após corrigir Close/Fechar. Não repetir a antiga alegação de chrome ausente. Falta amostragem ampla de páginas reais, mídia, paywall/destino inválido e retorno em todas as rotas. |
| **F09 Local/offline:** história, posição, salvos e catálogo local; recuperação; atualização íntegra e preservação pessoal | **Parcial** | B05 e busca após relançamento offline; mídia removida deixa de ser prometida como pronta; catálogo validado/rollback presente. Faltam garantias físicas completas de conteúdo/mídia salvos, purges do sistema, morte durante escrita e atualização V1→V2 real. |
| **F10 Qualidade de entrega:** aparelho, acessibilidade, pressão, escala, segurança de dados e distribuição | **Beta interna disponível; certificação aberta** | Build 53 no TestFlight, smoke e sites no físico, UI focal/completa identificada. B06 incompleto e B03 físico vermelho; experiência multimídia, VoiceOver e situações de pressão ainda não aprovadas. |

### B. Funcionalidades de apoio à descoberta — F11 a F20

| Frente / funcionalidades incluídas | Estado do produto | O que sustenta / o que falta |
|---|---|---|
| **F11 Busca unificada:** fontes, artigos, salvos, escopos, exclusões textuais, paginação, erro parcial, abrir/cancelar/restaurar | **Funcional com evidência focal** | Busca pela UI até resultados e relançamento offline demonstrada; tokens/paginação/escopo durável corrigidos; destinos reais cobertos. Falta variedade de consultas, idiomas, homônimos e todas as combinações de abrir/voltar/teclado. |
| **F12 Explorar fontes:** países, taxonomia, assuntos, fonte própria, seguir/desseguir, saúde e seleção | **Parcial** | Hierarquia e seleção implementadas; card e busca podem abrir contexto de fonte. A linha de fonte na taxonomia inspecionada oferece toggle, sem ação própria de abrir seu feed. Falta circuito completo de explorar e consumir uma fonte por essa superfície. |
| **F13 Conteúdo indesejado:** regras globais, palavras/templates, exclusões, edição, persistência e desfazer | **Funcional com evidência focal; alcance incompleto** | Editor e controles presentes. Falta jornada criar regra→efeito na próxima descoberta→desfazer→reabrir, sem remover história publicada. Não anunciar controles completos de mute de Source/Provider que não foram encontrados. Semântica de reduzir frequência e excluir são distintas. |
| **F14 Consumir artigo:** texto local versus resumo, abrir site explicitamente, links, fechar e recuperar posição | **Funcional com evidência focal** | Decisão local/site e teste físico das três jornadas Safari corrigidas. Falta matriz ampla de texto incompleto, paywall, 404, redirecionamentos e navegação secundária em conteúdo real. |
| **F15 Podcast e outras mídias:** play/pause, seek, saltos, mini/full player, progresso, posição persistida, interrupção, tela bloqueada e vídeo | **Áudio implementado, experiência real parcial; vídeo visual não demonstrado** | Adapter AVFoundation e controles reais presentes; integração de posição/interrupção/comandos remotos existe. Falta episódio real longo com fones/rota/tela bloqueada/reabertura. Não foi localizada superfície `VideoPlayer`/`AVPlayerViewController`/`AVPlayerLayer`; presença de payload/tipo `.video` não comprova assistir a vídeo. Confirmar caminho real antes de anunciar suporte completo. |
| **F16 Biblioteca:** caixas de salvos, organizar/renomear/ordenar/excluir, coleções, feeds curados, marcadores inteligentes, editar/ativar | **Funcional com evidência focal; jornada composta parcial** | Stores, UI, coleções e presets presentes; salvar/offline/reabertura exercitados. Salvar usa caixa preferida; picker de múltiplas caixas diretamente no card não localizado. Falta avaliar a biblioteca como destino completo, com relações e ações compostas. |
| **F17 Conforto e acessibilidade:** aparência, fontes/tamanho, tema/noturno/relógio, traduções, Dynamic Type, leitor de tela | **Parcial** | String Catalog pt-BR/en, aparência e controles presentes; geometria/XXXL/rotação têm provas focais. VoiceOver falado, cobertura integral de tradução/RTL e todas as telas não demonstrados. Idioma dos artigos e idioma da interface são funções diferentes; seletor próprio de idioma da UI não localizado. |
| **F18 Trazer/levar fontes:** URL/colar, descoberta/prévia/confirmar, coleção, importar OPML, exportar e Files/share | **Funcional com evidência focal** | Fluxos e testes de adicionar/importar/exportar presentes. Falta roundtrip representativo com duplicatas, inválidos, cancelamento e organização. Exportar fontes não equivale a backup completo de artigos, mídia e posições. |
| **F19 Compartilhar:** link correto, copiar, share sheet, origem e título, podcast/fonte/artigo | **Funcional básico; qualidade completa não demonstrada** | Ações e integrações do sistema presentes. Falta conferir payload por tipo com conteúdo real. Card visual exportável e estatísticas compartilháveis são oportunidades opcionais, não dívida automaticamente obrigatória. |
| **F20 Voltar e perceber novidades:** abrir rápido com conteúdo local, mesma leitura, atualização futura sem salto, saber que há algo novo | **Continuidade focalmente comprovada; descoberta do novo parcial** | Checkpoints, foreground e restauração presentes. Retorno distante ainda desloca 16 pt no cenário E03. Affordance completa de novidades/nova edição não demonstrada. Não ressuscitar carrossel/booster da V1 por conveniência. |

### C. Confiança no aparelho — F21 a F27

| Frente / funcionalidades incluídas | Estado do produto | O que sustenta / o que falta |
|---|---|---|
| **F21 Ciclo de vida:** interrupções, troca de app, sessão, morte de processo e retorno | **Parcial** | Restore/checkpoints/A→B→A e casos de relaunch presentes. Falta combinação física com mídia em andamento, encerramento pelo sistema, reboot/bloqueio e recuperação. |
| **F22 Rede e offline:** conexão lenta/intermitente, perda/retorno, modos restritos, mensagens e recuperação | **Parcial; erro visível observado** | Caminhos `.failed` e `.unreachable` separados; offline local focalmente provado. O usuário viu “Falha ao atualizar o feed”; registrar a causa real e a recuperação. Wi-Fi/celular/Low Data/portal e navegação mista ainda não demonstrados integralmente. |
| **F23 Background:** atualização e preparo oportunistas, expiração, cancelamento e retorno ao foreground | **Implementado; execução física integral não demonstrada** | BGTask e fences de autorização têm código/testes. Falta comprovar oportunidades reais concedidas/negadas pelo iOS, expiração, retenção útil e ausência de interferência na leitura, incluindo mídia. |
| **F24 Dados e armazenamento:** transações, recuperação, falta de espaço, purge, proteção de arquivos, salvos e migração | **Parcial; atualização pessoal é risco aberto** | Persistência V2, falhas de escrita/retry e purge simulado cobertos. Importador legado inspecionado exclui artigos salvos/alguns tipos; não foi encontrada ligação de produção para a importação completa nem prova de upgrade V1→V2 no mesmo container. Falta SIGKILL/disco cheio real/proteção após reboot. |
| **F25 Apresentação estável:** primeira exposição, gestos, rotação, teclado, sheets, retorno e fontes/tamanhos | **Parcial** | Diversas jornadas UI verdes e repouso de 10 min estável. E03: retorno desloca 16 pt; `16±1` comprova o desvio, não fecha preservação `±1`. Primeira tela preenchida e erro visível são prioridades atuais. |
| **F26 Integrações iOS:** Safari, share/Files, importação, clipboard explícito, player remoto, interrupção | **Funcional com evidência focal** | Safari físico 3/3, compartilhamento/importação e adapter de áudio existem. Falta cruzar essas integrações com conteúdo real, tela bloqueada, áudio ativo e retorno ao mesmo card. |
| **F27 Recursos/performance:** fluidez, CPU, memória/RSS, energia, térmica, crescimento sustentado e carga multimídia | **Não certificado; resultados físicos abertos** | B03 físico FAIL, B06 INCOMPLETE; tendências registradas requerem perfilamento, sem inventar teto de CPU. A coleta incompleta de hitches não prova ausência em toda a sessão. Carga de imagens/fotos, episódios/vídeos reais e pressão não foi comprovada pelos ensaios textuais. |

## O que podemos considerar bom hoje, com limites claros

- Há um aplicativo distribuível e instalável, com muitas superfícies conectadas; não é somente um conjunto de módulos ou mockups.
- A busca deixou de ser apenas um contexto de feed e tem resultados tipados, paginação, erros e restauração demonstrados.
- Fontes, filtros, coleções, caixas, importação/exportação e leitura têm caminhos funcionais e evidência focal identificável.
- O catálogo da build 53 tem proveniência e bytes verificados; não depende de baixar tudo antes de operar localmente.
- Falhas importantes de busca, coalescência, autorização e cache de settings foram corrigidas com regressões discriminantes.
- A suíte UI completa ficou verde após corrigir instrumentos e o defeito de reabilitação das ofertas. Isso melhora confiança nesses caminhos, mas não certifica a promessa multimídia nem os cenários omitidos.
- Os testes físicos de gesto e de leitura do site passaram. Não chamar o Safari de indisponível com base nos relatos antigos.

## O que não está bom ou ainda não podemos afirmar

1. **Primeira impressão:** leitor vê um card e o resto chega depois; contrato de primeira área útil pronta não demonstrado.
2. **Erros durante uso:** mensagem genérica visível sem que a sessão longa a reprove. Ainda falta causa, contexto e prova de recuperação desse caso.
3. **Riqueza real de conteúdo:** ensaios longos não exercitaram imagens/áudio/vídeo. Podcast tem implementação; experiência visual de vídeo continua sem demonstração funcional.
4. **Fluidez no aparelho:** o número de avanços falhou, com baixa cadência de gestos emitidos. Diagnóstico de UI/harness/abastecimento aberto; nenhum dos três está absolvido.
5. **Continuidade perfeita:** retorno distante com 16 pt de diferença permanece parcial, mesmo havendo muitos testes de âncora verdes.
6. **Confiança nos dados:** migração integral V1→V2, durabilidade de mídia sob condições físicas reais e recuperação de armazenamento continuam abertas.
7. **Acessibilidade e interrupções:** não há demonstração completa de VoiceOver falado, mídia com tela bloqueada e mudanças de rota/execução real de background.
8. **Qualidade editorial percebida:** relevância de corpus rotulado não responde se a descoberta real é interessante, diversa e surpreendente ao longo do uso.

## Por que os testes antigos não respondiam à pergunta de produto

No corpus há imagens, mas os feeds gerados declaram URLs locais. `SyndicationMediaLocator` rejeita hosts não públicos no caminho de mídia. Na corrida física inspecionada: 3.470 origens, **zero candidatos de mídia persistidos**, **zero requisições de mídia**, 1.652 cards publicados **textOnly**. A existência de mídia no arquivo de entrada não chegou à experiência exercitada.

Mesmo se fossem carregadas, as imagens sintéticas são PNGs de 160×96 com aproximadamente 238–243 bytes; áudio é silêncio de 2 s e vídeo um padrão de 1 s. Isso é útil para controles de parsing/transporte, não para demonstrar o custo ou a qualidade de fotos/episódios/vídeos reais.

O teste longo repete gestos e o avaliador aceita candidatos textuais. Ele não tem um critério geral que reprove a mensagem inesperada `.failed`. Existência de card/elemento, frame não zero, player aberto e relógio avançando não comprovam imagem composta, áudio audível ou vídeo visível.

Preservar esses resultados com seu alcance real. Não substituir a política de segurança do produto nem enfraquecer o avaliador para fazer mídia artificial passar.

## Fila de entrega por resultado para o leitor

### Agora — fazer o feed parecer e funcionar como o produto prometido

1. **Abertura e erro:** reproduzir a primeira exposição incompleta e a mensagem observada; mostrar a primeira área útil pronta e recuperação honesta de falha, mantendo o conteúdo já lido.
2. **Descoberta real com mídia:** demonstrar fotos/imagens desenhadas, artigos consumíveis, episódio real com progresso e vídeo com imagem efetiva. Identificar e fechar a lacuna funcional de vídeo se o caminho atual não permitir assistir.
3. **Exploração representativa:** jornada curta que varia idiomas, fontes, temas e ações por semente registrada; registra dados/respostas e sequência para reproduzir defeitos. Cobertura dirigida a funções ainda não exercitadas, não puro toque aleatório.
4. **Fluidez e retorno:** medir o custo de gestos e abastecimento com essa carga; preservar posição de volta e resolver E03. Só depois fazer nova corrida física longa e completa.

### Antes de ampliar a distribuição

5. **Não perder a biblioteca:** verificar instalação/upgrade V1→V2, salvos reais offline e mídia interrompida, distinguindo backup integral de exportação de fontes.
6. **Confiança física:** concluir B06, energia/hitches válidos, acessibilidade falada e principais interrupções de áudio/background.
7. **Fechar jornadas já oferecidas:** explorar uma fonte a partir do catálogo; busca→conteúdo→salvar→biblioteca→retorno; importação/exportação e filtros com efeito compreensível. Problemas concretos têm prioridade sobre novas superfícies opcionais.

### Depois da promessa central estabilizada

8. Aperfeiçoar affordances de novidades, navegação da biblioteca e acabamento/traduções com validação de uso.
9. Avaliar oportunidades adicionais da V1 por valor real; não assumir que todas são requisitos obrigatórios.

## Escopo adicional que não deve inflar a definição de pronto

O levantamento de 15 oportunidades da V1 é material de priorização, não autorização automática para implementar tudo. Estatísticas pessoais compartilháveis, card visual exportável, enriquecimento editorial do catálogo e novos atalhos podem ser úteis depois. Não exigir nem portar automaticamente carrossel/booster paralelo, shake com flush ou onboarding obrigatório. Distinguir esses itens de funções já anunciadas ao leitor, que precisam cumprir a promessa agora.

## Regra operacional de acompanhamento

Uma entrega do OMP deve atualizar a **jornada do leitor** afetada: comportamento antes/depois, estado atual, evidência observável e pendência seguinte. Contagem de testes e referência ao commit acompanham essa entrega, mas não são a conclusão de produto.

- Um responsável pela primeira tela/erros; outro pela mídia/consumo; revisão e confiança de dados em paralelo sem disputa de arquivos/dispositivo.
- Não repetir campanhas longas textuais antes de provar a carga pretendida.
- Uma função só pode mudar para “experiência comprovada” quando a sequência e os dados efetivamente exercitados sustentam essa afirmação. Sem sinal suficiente, fica “não demonstrado”.
- Atualizar esta fotografia em marcos funcionais, não criar outro relatório a cada rodada de teste.

## Fontes e rastreabilidade

Requisitos (worktree de produto, caminhos relativos à sua raiz):

- `docs/product/PRODUCT_NORTH_STAR.md`, `PRODUCT_DECISIONS_2026-10-09.md` e `DISCOVERY_ACCEPTANCE_BENCHMARK.md`.
- `docs/product/PRODUCT_AUDIT_10_FRONTS.md`, `PRODUCT_AUDIT_FRONTS_11_20.md`, `PRODUCT_AUDIT_APPLE_FRONTS_21_27.md` e os PRDs F02/F03/F05/F06/F11–F27 correspondentes.
- `docs/product/MIG-V1V2-B_migracao_pessoal_spec.md` e `PD10-P0D_continuidade_identidade_pessoal_spec.md`.
- `docs/v1-study/UI_TRANSFER_MATRIX.md`, `V1_HIDDEN_GEMS_PRODUCT_MINING_2026-10-10.md`, `V1_GOLD_DO_NOT_PORT_2026-10-10.md`.

Código inspecionado e referências de evidência:

- `Sources/FeedMineUI/Reader/ReaderNavigation.swift`: inventário de destinos e entradas de menu.
- `Sources/FeedMineUI/FeedScreen.swift`: entrada no feed quando há itens; não mede primeira área útil preenchida.
- `FeedMineApp/FeedMineApp/AppComposition.swift`, `reportFailure`: `.failed`/`.unreachable`, primeiro conteúdo, busca/settings e ciclo de vida.
- `Sources/FeedMineUI/Sources/NodeSourcesView.swift`: linha de fonte com toggle, sem navegação própria.
- `FeedMineApp/FeedMineApp/MediaPlaybackAdapter.swift` e `Sources/FeedMineUI/Media/MiniPlayerBar.swift`: capacidades e limites de reprodução.
- `Sources/FeedMineComposition/LegacyUserStateImport.swift`: tipos/importação parcial e dados explicitamente não carregados.
- `Sources/FeedMineSyndication/SyndicationMediaLocator.swift`: regra de host público para mídia.
- `bench/build_corpus.py`, `bench/README.md`, `bench/oracle.py`, `FeedMineApp/FeedMineAppTests/DiscoveryBenchmarkTests.swift`: composição e alcance do benchmark.
- `bench/run/20261020T152325Z/B03.verdict.json`, `b06/summary.json`, `server.log` e SQLite/trace exportados: resultado físico e ausência de mídia nessa corrida.
- `docs/reviews/evidence/2026-10-18-e03-rest/README.md`: retorno distante parcial; `2026-10-18-e07-e08/README.md`: provas de busca/salvos e limites.
- `/private/tmp/fm-ui-cert-20261020T081324Z.xcresult`: UI completa em `4baf9045`, conforme resultado reportado; `/private/tmp/feedmine-reading-20261020T064016Z/reading.log`: três testes físicos de site PASS, log conferido.

Relatórios e matrizes antigas contêm estados superados. Em particular: ausência de busca unificada, ausência de String Catalog, falha de chrome Safari e iPhone Offline não são descrições confiáveis da build 53. As correções acima não tornam automaticamente aprovados todos os cenários dos PRDs.
