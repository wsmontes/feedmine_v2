# FeedMine — plano de aproveitamento dos estudos de UX/UI e mídia

**Data:** 18/10/2026, America/Vancouver.  
**Objetivo:** escolher aprendizados que melhorem descoberta, leitura e consumo de mídia com retorno proporcional ao custo e sem comprometer a continuidade local.  
**Arquitetura:** evoluir os contratos e owners existentes, mantendo cards locais, publicação imutável, player independente da lista e dados pessoais duráveis.  
**Tecnologia existente:** Swift 6, SwiftUI, GRDB/SQLite, AVFoundation/MediaPlayer.  
**Status:** recomendações e experimentos; não são decisões de produto aprovadas nem autorização de implementação.

## 1. Recomendação executiva

O maior benefício dos estudos está em três mudanças graduais: **clareza editorial dos cards**, **ações e estados compreensíveis** e **continuidade do player já existente**. Não é necessário reconstruir navegação, aquisição ou playback para colher esses ganhos.

A sequência recomendada é: concluir os bloqueadores do [plano de pendências](2026-10-18-feedmine-estado-atual-e-pendencias.md); corrigir semântica e acessibilidade; comparar composições editoriais com o mesmo conteúdo; consolidar áudio/vídeo autorizado; depois avaliar transcrições e marcações temporais. YouTube embutido é uma integração separada, sujeita a requisitos próprios. IA ampla, fingerprinting, downloads preditivos e redesign integral têm retorno incerto para o estágio atual.

## 2. Como os quatro documentos foram usados

| Insumo | O que aproveitar | Limitação que afeta a decisão |
|---|---|---|
| [Benchmark UX/UI](../../../FeedMine_Benchmark_Design_Feed_UX_UI_2026-10-18.md) | Hierarquia editorial, quatro composições, contextos claros, estados honestos, protocolo UXD-01–16 | Propostas de design não foram aprovadas nem comparadas com leitores; status técnico precisa ser reconciliado com o WIP |
| [Estudo completo de mídia](../../../FeedMine_Estudo_Completo_Midia_2026-10-18.md) | Separar feed/player, retomar progresso, transcrição versionada, bookmarks duráveis e sequência incremental | Exemplos Swift e nomes propostos não são APIs implementadas; confirmar tipos e contratos reais antes de codificar |
| [Pesquisa de mídia 2](../../../deep-research-report%20-%20midia%202.md) | Lista de capacidades, cenários de dispositivo e distinção entre mídia nativa e YouTube | Benchmark tem incertezas e contradições; seção arquitetural admite ausência de acesso ao código e contém suposições. Não serve como evidência de V1/V2 |
| [Pesquisa inicial de mídia](../../../deep-research-report%20-midia.md) | Direção AVFoundation para mídia autorizada e IFrame para YouTube | Curta, fontes genéricas e recomendação de helper arquivado; não copiar dependências ou promessas sem checagem |

O pedido do usuário é revisar e produzir dois planos. Textos imperativos dentro dos anexos foram tratados como propostas do autor. Nenhuma instrução embutida foi usada para disparar implementação, instalar bibliotecas, alterar critérios de aceite ou publicar conteúdo.

Referências de concorrentes são inspirações documentadas, não medições nossas de desempenho ou garantia de capacidades atuais. A checagem externa desta revisão concentrou-se nos contratos Apple/YouTube e na manutenção do helper; não foi uma nova auditoria completa de mercado.

## 3. O que a base atual já oferece

Inventário conferido na worktree `codex/v2-fluidez-capacidade`, sobre `b0b961a0` com modificações locais em 18/10. Existência de código não equivale a jornada aprovada.

| Necessidade citada nos estudos | Base concreta | Implicação para custo-benefício |
|---|---|---|
| Player nativo único | `FeedMineApp/FeedMineApp/MediaPlaybackAdapter.swift`, `AVPlayer`, geração de callbacks e observadores | Estender e testar; não criar outro `PlaybackCenter` só para reproduzir os exemplos |
| Intenção Play separada da view | `Sources/FeedMineComposition/ReaderMediaCoordinator.swift` e `ReaderActionCoordinator` | Reusar resolução de payload da ocorrência; classificar novos provedores na fronteira correta |
| Mini-player e detalhe | `Sources/FeedMineUI/Media/MiniPlayerBar.swift` | A barra já reserva altura 56; falta provar também inserção/remoção durante a leitura, não só ticks com barra presente |
| Background e controles do sistema | `UIBackgroundModes=audio`, `AVAudioSession.playback`, Now Playing e Remote Commands | Já implementados em parte; teste no aparelho e tratamento de falhas são mais valiosos que refazer wiring |
| Retomada | `PlaybackPositionStore`, `ReaderPlaybackPositionsAdapter`, regras de progresso | Hoje a chave é `PublicationCardID`; progresso compartilhado entre ocorrências ainda requer identidade canônica e migração |
| Mídia declarada por fonte | `MediaCandidate` distingue image/audio/video; tradutor e locator tratam payload reproduzível | Não supor suporte completo a duração, alternativas, capítulos ou transcrições: não aparecem no contrato atual inspecionado |
| Contexto e biblioteca | `ReaderShell`, stores de filtros/busca, ações de fonte e salvos | Melhorar achabilidade e linguagem antes de introduzir tab bar ou novos stores |
| Estabilidade de apresentação | Publicação/snapshot, slots, gate de destino e residência | Toda composição nova deve ser compatível com imutabilidade, âncora e readiness |

**Lacuna técnica relevante já observável:** `ReaderPlaybackPositionsAdapter` é MainActor, faz leitura/escrita síncronas e usa `try?`. O player salva por cadência e em ações. Isso comprova I/O síncrono e erros silenciados nesse caminho; não comprova que ele já causou um hitch. Medir e adaptar o writer existente, mantendo ordenação e erro recuperável, antes de ampliar uso intensivo.

## 4. Critério de custo-benefício

As classificações são **julgamento desta revisão**, sem dados de retenção, receita ou tempo real de implementação. Evitam uma pontuação numérica que daria falsa precisão.

- **Aderência alta:** melhora descoberta sem configuração, leitura contínua, controle explícito ou retorno local. Média: útil para parte dos formatos/usuários. Baixa: aproxima o produto de outro aplicativo sem ganho demonstrado.
- **Esforço baixo:** mudança localizada aproveitando contratos. Médio: vários owners, UI e persistência/integração. Alto: nova capacidade de plataforma, migração complexa, processamento ou validação extensa.
- **Custo recorrente:** considerar bytes, disco, bateria, APIs, manutenção e revisão de políticas, além do desenvolvimento. Ausência de servidor próprio não elimina custo de dispositivo.
- **Risco:** combina chance de regressão, gravidade para o leitor e incerteza externa; não é uma probabilidade medida.

Primeiro corrigir comportamento obrigatório que já falha. Entre melhorias opcionais, preferir alto benefício, alta aderência, baixo custo recorrente e rollback simples.

## 5. Matriz de oportunidades

| ID / aprendizado | Origem | Benefício e aderência | Esforço / recorrência | Risco | Recomendação |
|---|---|---|---|---|---|
| O01 — Estados factuais de preparação, escassez e offline | UX §§10/13; mídia §12 | Alto / alta | Baixo–médio / baixo | Médio: copy afirmar fim ou disponibilidade sem fatos | Priorizar junto das correções existentes; não criar progresso fictício |
| O02 — Separar salvar, seguir, ver fonte e explorar tema | UX §11; Reeder/Pinterest | Alto / alta | Baixo–médio / baixo | Médio: ação alterar preferência além do rótulo | Auditar efeito real e Desfazer antes de polir o menu |
| O03 — Título/fonte legíveis e text-first digno | UX §§6/14; Unread/Flipboard | Alto / alta | Médio / baixo | Médio: geometria e Dynamic Type | Primeiro experimento editorial depois da base estável |
| O04 — Hero, text-first, compact e media | UX §7; feeeed/Tapestry | Alto potencial / alta | Médio / baixo–médio | Alto se mudar card publicado ou proliferar templates | Prototipar quatro, implementar uma diferença comprovada por vez |
| O05 — Contexto ativo e retorno claros | UX §§5/9/10; Reeder | Alto / alta | Médio / baixo | Médio–alto: perder A ao entrar em B | Preferir chip/saída explícita nos owners existentes |
| O06 — Biblioteca encontrável | UX §5; Readwise | Médio–alto / alta | Baixo–médio / baixo | Médio: chrome ocupar feed e mini-player | Testar acesso a Salvos antes de trocar navegação inteira |
| O07 — Continuidade de áudio e progresso confiável | Mídia §§10/14–16; Pocket Casts | Alto / alta | Médio / baixo–médio | Alto: perda de progresso, áudio duplo e I/O na UI | Consolidar o que existe; prioridade de mídia mais alta |
| O08 — Vídeo RSS MP4/HLS sob ação explícita | Pesquisas iniciais; mídia §§8–10 | Médio–alto / média–alta | Médio–alto / tráfego/bateria | Alto: superfície, interrupções, PiP e URL expirada | Ampliar o adapter atual após corpus e teste no aparelho |
| O09 — Bookmark temporal com nota | Mídia §§7/25; Snipd | Alto para escuta / média–alta | Médio / baixo | Médio: identidade e retenção | Próxima fatia após O07; começar com botão explícito |
| O10 — Capítulos e transcrição publicados pela origem | Mídia §§6/8/24; Reader/Pocket Casts | Alto para conteúdo longo / média–alta | Médio–alto / baixo–médio | Alto: versão, formato, drift e idioma | Começar pelos capítulos; transcrição sem geração por IA |
| O11 — Download manual de episódio autorizado | Mídia §§10/16; Snipd | Médio–alto / alta | Alto / disco e bytes | Alto: purge, cancelamento, quota, arquivo parcial | Depois de identidade/retentores; áudio antes de HLS offline |
| O12 — YouTube oficial visível | Todas as pesquisas de mídia | Médio / média | Médio–alto / manutenção externa | Alto: embed bloqueado, identificação, privacidade | Handoff externo como baseline; embed em entrega separada e medida |
| O13 — Alternar áudio/vídeo equivalente | Mídia §§19–22 | Médio / média | Alto / médio | Alto: anúncios e timelines diferentes | Adiar até corpus comprovar alternativas e equivalência |
| O14 — Header recolhível, tab bar, densidade configurável | UX §§5/8/9/22 | Incerto / média | Médio–alto / manutenção de variantes | Alto: achabilidade, viewport e âncora | Só protótipo comparativo inicialmente |
| O15 — Smart downloads por hábitos/fila | Mídia §7 | Incerto / média | Alto / alto | Alto: storage, energia e consentimento | Adiar até uso recorrente e orçamento demonstrarem valor |
| O16 — IA de transcrição/resumo/fingerprinting | Mídia §§3/7/29 | Incerto / média | Alto / alto ou variável | Alto: custo, privacidade, drift e operação | Fora do MVP; não tornar condição de publicação ou playback |

## 6. Plano incremental recomendado

### Fase A — absorver aprendizados sem expandir o runtime

**Entrada:** fotografar a candidata e usar o mesmo corpus nas comparações. Capturas/protótipos podem ocorrer enquanto os bloqueadores são resolvidos; mudanças de layout/playback entram após estabilidade suficiente.

- [ ] **A1 — O01/O02:** inventariar labels e efeitos de salvar, seguir, feedback negativo, ver fonte e explorar. Documentar consequências, persistência e caminho de desfazer. Validar após relaunch e offline.
- [ ] **A2 — O03:** reunir títulos longos, artigos sem imagem legítima, imagens lentas, conteúdos antigos, MP3, MP4/HLS e YouTube. Comparar legibilidade, atribuição e ação primária em tamanhos normais/acessíveis.
- [ ] **A3 — O05/O06:** pedir ao leitor para identificar contexto atual, voltar ao anterior e encontrar um salvo sem instrução. Alterar primeiro rótulo/posição do controle que falhar.

**Owners de partida:** `ReaderShell`, `ReaderHeader`, `FeedScreenStore`, `ReaderActionCoordinator`, `ReaderLibraryCoordinator` e componentes de card. Confirmar caminhos no candidato; não criar banco/estado paralelo de UX.

**Aceite:** intenção compreendida antes do toque, estados correspondem a fatos e retorno preserva edição/âncora. Acessibilidade e offline são obrigatórios. Se já estiver correto, registrar e preservar.

### Fase B — melhorar a composição editorial

- [ ] **B1 — O04:** protótipos das quatro composições com exatamente as mesmas histórias, fontes e ordem. O experimento mede apresentação, sem misturar alteração do ranking.
- [ ] **B2:** comparar títulos de 2/3 linhas e text-first; observar identificação de assunto, origem e ação, além de truncamento, erro de toque e preferência explicada.
- [ ] **B3:** implementar a menor variante que melhore as tarefas. Definir geometria/readiness pelo contrato de apresentação; não mudar layout de uma ocorrência publicada quando a imagem chegar.
- [ ] **B4:** repetir retorno do artigo, A→B→A, chegada tardia, repouso, modo escuro, rotação e Dynamic Type; medir custo de decode/memória.

**Owners:** `FeedItemCardView`, `FeedItemRowView`, `FeedItemView`, `PresentationCard`, `RenderContract` e preparação/publicação somente quando o contrato realmente exigir.

**Aceite:** melhora observável de compreensão, ausência de composição quebrada e nenhuma regressão de estabilidade. Uma rodada qualitativa informa a decisão; não permite alegar significância estatística ou maior retenção.

### Fase C — consolidar mídia sobre o que existe

- [ ] **C1 — O07:** mapa de capacidades reais por formato e origem; identificar local/remoto, duração conhecida/desconhecida e fallback. Testar a cadeia conector → publicação → ação → adapter → progresso.
- [ ] **C2:** exercitar Play, scroll distante, troca de contexto, pause/seek, várias seleções rápidas, fim natural e retorno. Só uma reprodução autorizada; callback antigo não altera a sessão atual.
- [ ] **C3:** testar ligação/Siri, saída de fones, Bluetooth, lock screen, background e relaunch no iPhone. Tratar falha de sessão de áudio de modo visível; configuração de capability não é prova de som contínuo.
- [ ] **C4:** medir persistência síncrona e falhas de storage no caminho atual. Se adaptado, preservar checkpoint ordenado e drenagem no lifecycle, sem fila ilimitada ou segundo banco.
- [ ] **C5 — O08:** adicionar/completar superfície de vídeo nativo e PiP somente para fontes suportadas. Validar formato e redirecionamentos; falha de mídia conserva o card e oferece saída.

**Owners:** `ReaderMediaCoordinator`, `MediaPlaybackAdapter`, `ReaderMediaState/Item`, `ReaderPlaybackPositionsAdapter`, `PlaybackPositionStore` e `MiniPlayerBar`. Metadados de artwork podem vir do asset local existente; não buscar imagem no tick do player.

**Aceite:** M-02/03/04/12/13/14/16 do estudo de mídia demonstrados na candidata, mini-player sem deslocamento ao aparecer/desaparecer e nenhum stream iniciado pela mera renderização do card.

### Fase D — enriquecer escuta sem custo de IA obrigatório

- [ ] **D1 — pré-requisito de O09/O10/O11:** decidir se progresso é por ocorrência ou por mídia canônica. Projetar equivalência verificável e migração do estado atual por `PublicationCardID`; não unificar reuploads por título/URL.
- [ ] **D2 — O09:** bookmark de tempo e nota opcional, duráveis após purge, cancelamento e relaunch; depois avaliar exportação no mecanismo pessoal existente.
- [ ] **D3 — O10:** capítulos fornecidos pela fonte; em seguida VTT/SRT publicados, idioma/proveniência/versão, seek e autoscroll optativo. Texto sem tempo não promete sincronização.
- [ ] **D4 — O11:** download manual de áudio com consentimento de rede, tamanho/erro explícitos, retomada, cancelamento, arquivo atômico e retenção. Validar offline real; só depois avaliar HLS autorizado.

**Aceite:** dados pessoais sobrevivem à evicção; transcrição atualizada não desloca âncoras antigas; só arquivos efetivamente locais recebem promessa offline. O pipeline de cards continua independente dos downloads de episódios.

### Fase E — integrações opcionais e experimentos de maior risco

O12 entra como projeto pequeno separado, depois das provas de continuidade: player oficial visível, identidade do app, erro/fallback e privacidade. O13–O16 precisam de demanda observada, custo de operação e evidência de ganho antes de entrar na fila. Uma falha de embed não pode bloquear o feed ou criar uma tentativa de extrair o stream.

## 7. Pontos dos anexos que não devem ser copiados literalmente

| Afirmação ou sugestão | Avaliação nesta revisão | Consequência para o plano |
|---|---|---|
| Adotar `youtube-ios-player-helper` como dependência oficial padrão | Repositório arquivado pelo mantenedor em 05/12/2024 | Evitar nova dependência por autoridade histórica; avaliar IFrame em WKWebView usando documentação vigente [W1] |
| Controles do embed permitem desligar anúncios; referência a “18.2(b)” da App Store | `controls` não é autorização para bloquear anúncios; a citação de App Store não foi validada | Excluir ambas como justificativa; usar políticas oficiais do YouTube e verificar diretrizes Apple na implementação [W2] |
| Basta informar `origin` em qualquer WebView | Requisitos atuais detalham identificação por `HTTP Referer` ou alternativa específica ao ambiente | Seguir configuração oficial; tratar erro 153 e não confundir identificação com API key [W3, W4] |
| Ocultar vídeo economiza tráfego / equivale a trocar para áudio | Ocultar a superfície não demonstra mudança de representação ou economia | Só prometer redução após confirmar fonte/variant e medir bytes; timelines alternativas podem divergir |
| Premium autoriza app terceiro a oferecer áudio de YouTube em background | Assinatura do usuário não foi demonstrada como permissão para essa integração | Não oferecer player oculto, separar áudio ou download não autorizado [W2] |
| Vídeo/podcast demanda player, mini-player e controles do zero | A V2 já tem essas partes em código | Custear lacunas de integração e testes, não reconstrução |
| Concorrentes RSS “só abrem no navegador” | A pesquisa 2 conflita com exemplos oficiais descritos no estudo completo | Não usar tabela antiga como verdade do mercado nem base de prioridade |
| AVPlayer tem `allowsPictureInPicturePlayback` | Configuração pertence à superfície/controlador AVKit apropriado, não ao AVPlayer em si | Revisar exemplos no SDK real; não transportar pseudocódigo para produção |
| Descrição de classes V1/V2 na pesquisa 2 | A seção declara que não teve acesso ao código e faz suposições | Excluir do diagnóstico factual; usar os owners inspecionados no §3 |
| Transcrição e capacidade de concorrente revelam seu pipeline interno | Produto fechado não oferece essa prova | Reutilizar o padrão de experiência, sem inventar arquitetura/licença de implementação |

O plano usa a rota de YouTube documentada: embed oficial visível ou abertura externa. As políticas restringem isolamento de áudio/vídeo e background player oculto, além de download fora das permissões aplicáveis [W2]. Mídia nativa autorizada usa AVFoundation com sessão e modos apropriados; áudio em background e downloads HLS são capacidades distintas, com configuração e limites próprios [W5, W6].

## 8. Riscos transversais e mitigação

| Risco | Onde aumenta | Mitigação / sinal de recusa |
|---|---|---|
| Regressão da publicação e âncora | Cards, header, barra e vídeo | Medir IDs/bounds/offset antes/depois; recusar mudança que reorganize história publicada |
| Duplicação de ownership | Exemplos de `PlaybackCenter`, filas e caches | Mapear obrigação para owner atual antes de criar tipo; separar superfície de player |
| Explosão de tráfego/disco/energia | Offline, transcrição, smart download | Cards preparam visual local; Play/download explícitos; orçamento e revogação de downloads separados |
| Perda de dados pessoais | Migração de progresso, notas e bookmarks | Chaves canônicas verificadas, migração testada, retenção enquanto referenciado e erro explícito |
| Drift temporal | Alternativas, anúncios dinâmicos e transcrição | Não transferir tempo sem evidência de equivalência; sinalizar sincronização indisponível |
| Dependência externa/política | YouTube, SDK arquivado e APIs | Integração isolada, fallback externo, documentação primária e testes de erro |
| Acessibilidade e excesso de controles | Densidade, truncamento e barra fixa | VoiceOver falado, texto grande e tarefas reais; evitar inventar preferência antes de testar |
| Manutenção e licença | Código aberto de player concorrente | Usar como referência; antes de copiar código verificar licença, atribuição e compatibilidade |
| Distração da entrega central | Recursos novos antes de B03/B06 | Financiamento de execução primeiro no plano de pendências; experimentos pequenos com condição de parada |

## 9. Decisões de produto necessárias quando a fase correspondente chegar

Estas questões não impedem concluir a revisão nem justificam refazer o que já existe.

| Decisão | Recomendação inicial desta revisão | Evidência para confirmar |
|---|---|---|
| Navegação principal | Manter estrutura atual enquanto melhora labels e acesso a Salvos | Achabilidade sem tutorial e retorno à leitura |
| Densidade e destaque hero | Política editorial simples; sem opção adicional inicialmente | Comparação do mesmo corpus, texto grande e custo de decode |
| Fila de áudio | Apenas ações explícitas; não derivar automaticamente do viewport | Uso repetido e entendimento de “próximo episódio” |
| Progresso entre cards do mesmo episódio | Compartilhar apenas com equivalência canônica demonstrada | Reedição, mudança de CDN, reupload e dois contextos |
| Bookmark por comando dos fones | Botão explícito primeiro; remapeamento opcional depois | Consentimento claro e preservação do retrocesso esperado |
| Downloads | Manual de áudio primeiro; Wi-Fi como preferência proposta, não regra já aprovada | Uso offline, limites e consentimento de dados móveis |
| YouTube | Abertura externa como baseline, embed se benefício justificar | Play→imagem, erros, retorno, privacidade e revisão de políticas |
| IA e enriquecimento | Optativos, fora do caminho de publicação | Demanda, custo por uso e tratamento de dados definidos |

## 10. Verificação e condição de parada dos experimentos

Para cada entrega: registrar hipótese, base/SHA, corpus, mudança mínima, resultado e custo observado. Os UXD-01–16 e M-01–18 dos estudos oferecem casos complementares, sem substituir B01–B06.

**Continuar** quando há ganho observável de compreensão/controle e nenhum prejuízo de continuidade. **Reduzir ou reverter** quando não houver ganho perceptível, aumentar erro de toque, perder posição, produzir I/O visual, duplicar playback ou elevar tráfego sem consentimento. Definir metas de latência/bytes após a linha de base, antes de comparar resultados; não inventar metas depois do teste para obter aprovação.

Não usar contagem de recursos, aparência isolada ou tempo bruto no feed como prova de sucesso. Medir se a pessoa encontrou algo interessante, entendeu a origem/ação, conseguiu consumir e retomou de onde parou.

## 11. Fontes externas verificadas nesta revisão

Consulta em 18/10/2026. Conferir novamente ao implementar ou lançar, pois requisitos externos podem mudar.

- **W1:** [repositório youtube-ios-player-helper](https://github.com/youtube/youtube-ios-player-helper) — arquivado em 05/12/2024.
- **W2:** [YouTube Developer Policies](https://developers.google.com/youtube/terms/developer-policies) — especialmente restrições de conteúdo audiovisual, anúncios e background player.
- **W3:** [YouTube Required Minimum Functionality](https://developers.google.com/youtube/terms/required-minimum-functionality) — identificação de API Client, Referer e integração WebView.
- **W4:** [YouTube IFrame Player API](https://developers.google.com/youtube/iframe_api_reference) — contrato/eventos/erros, incluindo 153; [parâmetros do player](https://developers.google.com/youtube/player_parameters) — dimensões e opções suportadas.
- **W5:** [Apple: Configuring your app for media playback](https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback) — sessão e background audio.
- **W6:** [Apple: AVAssetDownloadURLSession](https://developer.apple.com/documentation/avfoundation/avassetdownloadurlsession) — persistência de HLS para reprodução offline.

**Primeira entrega de evolução recomendada:** auditoria de ações/estados + experimento text-first + prova integrada do player existente. A implementação deve ser planejada em detalhe sobre a candidata estabilizada; os exemplos dos anexos não substituem esse passo.
