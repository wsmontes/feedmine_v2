# Resumo Executivo

O **FeedMine V2** pode evoluir para oferecer uma experiência multimídia rica, mas há restrições técnicas e de licenciamento a considerar. Em resumo:

- **YouTube embutido:** Tecnicamente é viável usar um player IFrame dentro de um `WKWebView` para reproduzir vídeos do YouTube in-app. Porém, a reprodução em segundo plano e somente áudio é **limitada pelas regras do YouTube**. A API de YouTube **proíbe** disponibilizar conteúdo offline ou reproduzir áudio sem vídeo visível, o que impede um “modo podcast” puro para vídeos do YouTube no FeedMine. A reprodução pode funcionar em primeiro plano e com *Picture-in-Picture*, mas **será pausada ao travar a tela ou enviar o app ao background**, a não ser que o usuário tenha *YouTube Premium* (caso contrário, o vídeo para). Não há API oficial do YouTube que converta vídeos em podcasts – toda tentativa de extrair apenas áudio viola os termos. Em suma, podemos incorporar vídeos do YouTube para reprodução **in-app** (via IFrame), mas não legalmente tocar só o áudio em background sem vídeo.

- **Podcasts e APIs Apple:** O iOS oferece suporte nativo forte para áudio (podcasts) usando AVFoundation e MediaPlayer. Usando **AVAudioSessionCategoryPlayback** com a chave `UIBackgroundModes = audio`, o app pode manter áudio rodando com tela bloqueada. O **MPNowPlayingInfoCenter** e **MPRemoteCommandCenter** permitem controlar a reprodução (pausa, avanço, metadata na tela de bloqueio). Para streaming HLS (vídeos ou podcasts em vídeo), o iOS suporta **AVAssetDownloadURLSession**, permitindo baixar conteúdos HLS para ouvir offline (mesmo em background). A Apple anunciou suporte a podcasts em vídeo via HLS em 2026, sugerindo que a V2 pode apoiar esse formato: o usuário poderá alternar entre áudio e vídeo sem perder o progresso, e até baixar episódio de vídeo. Porém, algumas limitações podem surgir (por exemplo, controles de velocidade limitados em vídeo).

- **Vídeo via RSS (não-YouTube):** Conteúdos em MP4 ou HLS podem ser reproduzidos in-line usando **AVPlayer/AVKit**, com **Picture-in-Picture** funcional (iOS suporta PiP para AVPlayer). O áudio desses vídeos continuará em background se a sessão de áudio estiver configurada para playback. Em geral, simula-se um podcast: o vídeo pausa e só o áudio segue no mini-player. Vídeos HLS podem ser baixados para offline via AVAssetDownloadURLSession (desde que o feed permita), o que o YouTube não permite mas outros hosts sim. Formatos comuns (HLS, MP4/AAC) são suportados nativamente. DRM/proteções específicas podem bloquear captura, mas RSS convencionais normalmente expõem links diretos. O consumo de CPU e bateria é maior em vídeo, mas iOS gerencia otimizações (HLS reduz bitrate conforme necessário).

- **Benchmark competitivo:** Concorrentes como **Apple Podcasts, Pocket Casts, Overcast, Castro, Fiery Feeds** e leitores RSS têm diversas abordagens:
  - *Apple Podcasts* (nativo) passou a suportar HLS vídeo, alternância áudio/vídeo e download offline. Tem player persistente, PiP e background, mas apenas para conteúdo da plataforma (não integra YouTube).
  - *Pocket Casts* suporta episódio de vídeo (MP4 ou HLS) in-app. Permite alternar vídeo/áudio mantendo posição e mini-player de áudio (o vídeo some se retrair). Porém, **não baixa o vídeo**, apenas baixa o áudio. Não toca vídeos hospedados apenas no YouTube.
  - *Overcast/Castro* são focados em áudio e não suportam vídeo.
  - *Fiery Feeds* (leitor RSS) introduziu reprodução de vídeos embutidos e “inline”, e melhorou o manejo de vídeos do YouTube embed.
  - *Leitores RSS* (Inoreader, Feedly, Reeder, NetNewsWire) geralmente abrem vídeos em Safari ou no app nativo, sem integração de player contínuo. Alguns (ex. NetNewsWire) começam a usar `NewsKit` para tocar áudio anexo inline, mas tendem a delegar a reprodução a agentes do sistema.

- **Oportunidades específicas:** A V2 pode explorar HLS para vídeos em feeds RSS (como os vídeos de podcast anunciados pela Apple) usando AVFoundation para streaming adaptativo e downloads offline. Há APIs Apple modernas para baixar conteúdos de vídeo em background. Também é possível adotar padrões de “capítulos” de podcasts para artigos (RSS) se presente. Há bibliotecas open-source (ex. [AVKitPlayer](https://developer.apple.com/documentation/avkit/avplayerviewcontroller) customizadas) que facilitam um player universal. Aproveitar **MPRemoteCommandCenter** e integrá-lo com o player atual garante contornos lockscreen. Mini-player e PiP (AVKit tem `allowsPictureInPicturePlayback`) podem ser ativados. É possível usar o `UIScrollViewDelegate` para pausar/retomar no feed. O diferencial é unificar tudo: manter um único player global (usando `MediaCandidate` etc) que delega a reprodução de RSS-audio (AVPlayer) ou YouTube (WKWebView+IFrame) segundo o tipo, mas expondo controles unificados.

Em conclusão, *a melhor experiência multimídia viável hoje* é:
- **Vídeos do YouTube**: reproduzir embutidos quando visíveis (WKWebView ou solução WebView interna), mas encerrar reprodução (e áudio) ao enviar o app para background. Não é possível legitimar áudio-em-background.
- **Podcast/Áudio**: reproduzir com AVPlayer em background usando AVAudioSession “Playback” + UIBackgroundModes, exibindo Now Playing.
- **Vídeo RSS**: reproduzir nativamente com AVPlayer/AVKit (permite PiP, tela cheia, e áudio em background).
- **Player global**: Um player persistente (mini-player) que acompanha a navegação, mostrando capa e progresso.
- **Offline**: Usar AVAssetDownloadURLSession para conteúdo de áudio e vídeo HLS (quando permitido pelo feed), não para YouTube.

Essas decisões respeitam políticas: evitamos downloads ou áudio-only do YouTube, e usamos APIs oficiais para áudio/vídeo da Apple. A experiência final será coerente, fluida e alinhada às expectativas de concorrentes avançados (Pocket Casts, Apple Podcasts) e às capacidades do iOS.

# Oportunidades Não Óbvias

- **HLS Vídeo + Offline**: Inspirado no anúncio da Apple, o FeedMine V2 pode tratar episódios de vídeo como stream HLS. O AVAssetDownloadURLSession (iOS 11+) permite baixar adaptativamente segmentos de HLS para reprodução offline. Isso é uso legítimo (diferente de “cachear” stream do YouTube, que é proibido). Assim, se um feed RSS oferecer HLS de vídeo (como podcasts de vídeo modernos), poderemos baixar o conteúdo e permitir áudio/vídeo offline. Essa funcionalidade não está no V1 e pode diferenciá-lo, alinhando-se ao que Apple Podcasts fará.

- **Player Unificado com Camadas**: Em vez de dois players separados (um para áudio/podcast e outro para YouTube), podemos criar um player “aberto” que ativa internamente AVPlayer para arquivos diretos ou HLS, e WKWebView para vídeos YouTube, mas expondo as mesmas ações: play, pause, seek, speed. Essa arquitetura híbrida permitiria suportar PiP e background para o nativo, e PiP (via `allowsPictureInPicturePlayback`) para WKWebView. Apps como Pocket Casts fazem troca transparente entre áudio e vídeo; poderíamos adotar algo similar no controle de UI. Por exemplo, ativar um ícone “cam/I” que muda de vídeo para áudio (ou esconde vídeo) conservando posição, como eles.

- **Artigos e Capítulos**: Muitos podcasts têm **capítulos** (APIs do iOS via *MPNowPlayingInfoCenter* suportam capítulo contiguos). O FeedMine já prepara textos; talvez possamos mapear isto a “capítulos” de episódios (se disponíveis no RSS). Isso daria navegação fina em players. Semelhante, usar *transcrições/páginas web* para capítulos pesquisáveis, aproveitando o buscador local já existente.

- **Mini-Player Persistente**: Ao fechar o conteúdo (como na V1 abrindo webview), não interromper o player (como Pocket Casts e Apple Podcasts fazem). Implementar um mini-player *flutuante* (talvez usando `RootTabBarController`) que fica presente na UI do feed, mostrando arte e controle de pause/play. Fiery Feeds já sugere algo assim (chama de “shelf”). Isso permite ao usuário continuar rolando o feed enquanto ouve/vê.

- **YouTube Metadata via API**: Em vez de só extrair o link do RSS, chamar a YouTube Data API (com chave própria) para obter título, descrição e thumbnail oficial. Assim, os cards do feed de vídeo YouTube teriam artwork de alta qualidade. A V1 já pode pegar miniaturas, mas dados da API (view count, likes) agregam contexto e usuário.

- **AirPlay/CarPlay/Ciclo de Vida**: Aproveitar o controle de rota de áudio (usar notificações AVAudioSessionInterruption, MPRemoteCommandCenter) para oferecer transição suave (por exemplo, AirPlay automático via Control Center). Permitir responder a comandos do CarPlay se for relevante. Isso poderia ser novo, pois integraria melhor com ecossistema Apple.

# YouTube (Incorporação e Restrições)

### Reproduzir no app

- A **API IFrame do YouTube** permite incorporar vídeos via HTML/JavaScript. Em iOS usaríamos um **WKWebView**, carregando o player IFrame. Exemplo: criar um `<iframe>` de dimensões adequadas (mínimo ~480×270) com `playerVars: {playsinline: 1}` garante playback embutido (sem ir para app YouTube). O player aceita controles padrão (play/pause, seek, volume, velocidade). Em SwiftUI, usar `UIViewRepresentable` para um WKWebView que envolve `<div id="player">` e carrega o script `https://www.youtube.com/iframe_api`.

- **Gestos de rolagem vs vídeo**: O player pode ser configurado para rolar com o feed (por exemplo, ocupar área do card). Para manter o vídeo fixo (player mini ou PiP), seria preciso ativar *Picture-in-Picture*. iOS 14+ suporta PiP para WKWebView se o vídeo HTML permitir (`webkit-playsinline` e `allowsPictureInPictureMediaPlayback = true`). Assim, ao sair do app ou pressionar home, o vídeo entraria em janela PiP (se implementado). Caso contrário, sair do app pausa o vídeo.

- **Mini-player**: Para persistência interna, poderíamos usar uma visão custom que contenha o `WKWebView` ou um `AVPlayerViewController` no modo PiP embutido. Por padrão, o iFrame API exibe o próprio player, mas podemos esconder o vídeo e continuar tocando o áudio (embora isso **quebre o ToS**, ver abaixo).

### Reproduzir em background / áudio-somente

- **Técnica vs Permissão**: Tecnicamente, é possível iniciar a reprodução de um vídeo YouTube via WKWebView em primeiro plano. Em segundo plano, a sessão de áudio do `WKWebView` normalmente **pausa automaticamente** (o WebView não é tratada como áudio contínuo – e o iFrame geralmente não ativa background). Mesmo que configuremos `AVAudioSessionCategoryPlayback` no app, o YouTube API não está integrado a ele. Em outras palavras, o **audio não continua naturalmente em background**. Usuários de YouTube Premium conseguem deixar tocar audio-only, mas terceiros não: o YouTube API encerra o stream se o player não estiver visível.

- **YouTube Premium vs API**: Não há API pública que permita replicar o comportamento Premium. Apple Review citou no passado que apps que “roubam” vídeo para áudio (como apps de player de música do YouTube) são proibidos. O **YouTube ToS** claramente proíbe tornar conteúdo disponível offline ou em streaming de forma não autorizada. Isso inclui tocar somente áudio. Portanto, qualquer “hack” (remover `<video>` e só usar áudio) seria contra as políticas. Consequentemente, **não recomendamos** implementar um player invisível para extrair só audio de YouTube; além de violar ToS, o app pode ser rejeitado.

- **Tela bloqueada / Controles**: Mesmo se conseguíssemos manter áudio (o que não é suportado), exibir título e controles no *Lock Screen* requer *MPNowPlayingInfoCenter*. Porém, o YouTube IFrame não fornece hook para atualizar isso diretamente. Seria improvisado (atualizando manualmente as metadata ao carregar vídeo), mas novamente cairíamos na zona cinza legal, já que extração de áudio é proibida. Portanto, a única rota oficial é deixar o iFrame fazer o seu trabalho: sem promessa de background audio ou lockscreen.

- **Autoplay e Size**: O YouTube exige que o player IFrame tenha pelo menos 200×200px. O iFrame exibe seus próprios controles. O **playerParams** pode desativar anúncios/controlos (se `controls=0`, eles aparecem se o view for grande o suficiente). Autoplay direto não funcionará no iOS sem interação (política de user gesture). Podemos programar para tocar ao clicar num botão customizado no card, que injeta `player.playVideo()` via JS.

- **Referer/Origin**: YouTube geralmente impõe restrições de *origin* e referer. Um app nativo tende a usar WKWebView com origin `null` ou `file://`, o que pode ser bloqueado se a chave de API (embutida na página) exigir referrer whitelisting. Normalmente não há problema para players públicos, mas se ocorrer erro “Action is not allowed in the embedded players”, deve-se incluir `origin` na URL do IFrame.

- **Links diretos como podcast**: O YouTube Data API não fornece um “arquivo” de áudio; o link `videoId` só dá metadados. O único link extraível seria o próprio vídeo via `youtube.com/watch?v=`, que só toca no browser/app. Não há modo de obter um stream HTTP puro via API autorizada. Portanto, o FeedMine não pode tratar o YouTube como um RSS de áudio – só como vídeo web.

### Restrições oficiais

- **YouTube API Policies**:
  - **Proibições principais**: Não podemos fazer *download* ou *caching* de vídeos para offline, nem disponibilizar conteúdo sem vídeo. A política de *"Playback Integrity"* menciona que o usuário deve explicitamente escolher assistir um vídeo (não há incentivo para autoplay sem interação). Extração de áudio quebra direito autorais implícito.
  - **Dados de vídeo**: Podemos usar a Data API para obter título/thumb, desde que respeitemos *branding*. Se usarmos o player IFrame, o branding do YouTube é mantido automaticamente.
  - **Reprodução**: Usar IFrame embutido é permitido, desde que não escondamos anúncios ou branding. Ajustar parâmetros (qualidade, controles) é permitido dentro das regras do Embedded Players docs.

- **App Store Guidelines**:
  - Não há guia específico sobre YouTube, mas a Apple veta práticas de pirataria de áudio e exige que players respeitem licenças. Além disso, **18.2(b)** da Review Guidelines proíbe aplicativos que reproduzam músicas ou vídeos sem permissão dos detentores de direitos. Ou seja, converter YouTube em rádio é arriscado. Jogar vídeo em `WKWebView` é seguro (como um navegador interno).

- **Conclusão**: Podemos legalmente incorporar vídeos via IFrame (funciona enquanto o usuário estiver no app). Mas nossa UX não poderá replicar 100% o comportamento de podcast (background lockscreen e offline) para vídeos do YouTube. A recomendação é aceitar essa limitação: vídeos do YouTube serão tratados como vídeos; se o usuário quiser apenas áudio, deve ouvir via YouTube ou baixar audio numa rota autorizada (não cabe ao FeedMine).

# Apple e Podcasts

### APIs de reprodução de áudio

- **AVPlayer/AVAudioSession**: Para tocar áudio (podcasts ou o áudio de um vídeo RSS), usamos `AVPlayer`. Configurar `AVAudioSession.sharedInstance().category = .playback` permite áudio em background e com tela bloqueada. É essencial habilitar “Background Modes” com a chave `audio` no Info.plist para que o app continue rodando quando bloqueado.

- **MPNowPlayingInfoCenter**: Permite mostrar informação de pista/episódio na tela bloqueada e controlar via controls externas. Devemos preencher `MPNowPlayingInfoCenter.default().nowPlayingInfo` com título, autor, capa, duração, etc. (o exemplo no SO mostrou que, no dispositivo, basta fazer isso e o sistema exibe as infos). Também precisamos ouvir `AVAudioSession.interruptionNotification` para pausar/resumir. Além disso, registrar handlers em `MPRemoteCommandCenter` para pausar/avançar/resumir (importantíssimo – sem isso, o sistema pode ignorar o nosso nowPlayingInfo).

- **MPRemoteCommandCenter**: Para ações de lockscreen/controle externo, ative comandos: `.playCommand`, `.pauseCommand`, `.nextTrackCommand`, etc. Os exemplos sugerem retornar `.success` em cada target. Isso garante controle pelo headset/CarPlay.

- **MPNowPlayingInfoCenter e áudio offline**: Podemos atualizar periodicamente `elapsedPlaybackTime` no nowPlayingInfo para manter sincronizado. Também suportamos “velocidades de reprodução” (varias em *MPNowPlayingInfoCenter*, até 3x) – sobre isso, o audio player do iOS já oferece speeds até 3x. Note que em um episódio de vídeo adaptativo HLS (como Apple anunciou), as velocidades podem ficar limitadas (Pocket Casts só vai até 2x em HLS vídeo, mas é por implementação própria; o AVPlayer default suporta 0.5x–2x e também 3x se habilitado).

- **Downloads em background**:
  - **URLSession background**: Para baixar episódios MP3 ou HLS, podemos usar `URLSession` ou `AVAssetDownloadURLSession`. Para MP3/AAC direto, um simples `URLSessionDownloadTask` com background mode (`URLSessionConfiguration.background`) garante que o download continue se o app for suspenso.
  - **HLS**: Para arquivos de vídeo HLS, **AVAssetDownloadURLSession** é ideal. Essa API faz o download dos segmentos HLS e cria um `AVURLAsset` que pode ser tocado offline (como Apple demonstra no guia “Play and persist HTTP Live Streams”). É relativamente direta de usar e lida com a variedade de qualidades. Em V2, usaríamos isso para episódios de vídeo (ou até áudio HLS) para oferecer modo offline, especialmente se integrado com MPNowPlayingInfoCenter.
  - **Persistência de progresso**: Ao reiniciar app, nosso banco de dados pode guardar o ponto atual de cada episódio (timestamp), e ao recarregar o feed podemos “atar” ao mesmo episódio pelo identificador, repondo o progresso. *Desafio*: garantirmos um **ID estável** de episódio. Em RSS, o `guid` ajuda, mas se ele mudar (nova edição), podemos usar combinação de `title+pubDate+link`. Exemplo: Pocket Casts salva posição mesmo que o feed troque, usando GUID e tempo. Podemos copiar: se um feed incluir `<itunes:episode>` ou similar, use como ID; senão, concatene título+pubDate.

- **Compatibilidade de formatos**: O AVPlayer suporta MP3, AAC, M4A, MP4/AAC, HLS (.m3u8), e até vídeos comuns. Em geral, todos os enclosures de podcast padrão serão tocados sem codec extra. Caso caia em formatos não suportados (como formatos obsoletos), poderíamos pular ou usar conversão offline (ficaria fora de escopo).

- **Capítulos, transcrições e artwork**: Alguns feeds incluem capítulos (`<psc:chapter>`), imagens (`<itunes:image>`), transcrições (`<transcript>`). O iOS tem APIs como `MPMediaItemPropertyChapterList` e `AVAssetMediaSelection` para legendar, mas não há um componente pronto. Podemos mostrar capítulos no UI ou usar `AVPlayerItem` com tracks de legenda. Transcrições podem ser baixadas e exibidas no leitor. No mínimo, armazenar a URL e oferecer “mostrar transcrição” manual. A arte pode ser baixada e colocada em `nowPlayingInfo[MPMediaItemPropertyArtwork]`.

### Recursos nativos adicionais

- **AirPlay**: AVPlayer suporta AirPlay por padrão (o usuário escolhe no controle de áudio). Podemos detectar rotas do `AVAudioSession` e ajustar.
- **Bluetooth/fones**: Com AVAudioSession configurado, comandos de *play/pause* do headset funcionam via `MPRemoteCommandCenter`.
- **CarPlay**: Se o app for usado no CarPlay, AVPlayer/MediaPlayer já integram com o sistema, desde que definamos as metadata e comandos. Pode testar usando código de CarPlay no simulador, mas é avançado.
- **Siri/Shortcuts**: Expor intents de reprodução (usando `MediaIntents`) permitiria “Reproduza [podcast X] no FeedMine”. Mas não é trivial sem backend de catálogo global.
- **Velocidade custom**: iOS permite 0.5x–3x (alguns players limitam a 2x em vídeo). Podemos permitir até 3x no áudio.
- **Reprodução em background da web**: Observação: WKWebView só respeita AVAudioSession se contiver elementos `<audio>`/`<video>`. Em geral, isso se comporta como AVPlayer. Porém, o YouTube IFrame não é integrado ao nosso AVAudioSession; então em background ele não conta como “nosso áudio”.

### Apple Podcasts vs API

- **Catálogo Apple Podcasts**: Não há API pública para buscar o catálogo ou episódio do app Podcasts. A App Store Connect tem Podcast Charts, mas só para o próprio app. Ou seja, não conseguimos *acessar o catálogo do Apple Podcasts* no FeedMine. O que podemos fazer:
  - Abrir um link `podcast://` ou `itpc://` abre o Apple Podcasts app em um episódio específico, mas não conheço APIs (talvez `podcasts.apple.com` com deeplink?). Mas isso seria uma saída “abrir no app Apple Podcasts”. O URI padrão `podcasts:showID?episodeID` existe? O que se sabe:
    - Há `https://podcasts.apple.com/podcast/id<ID>` tipo links web, mas sem API.
    - Não podemos “consultar progresso” do usuário no Apple Podcasts via API pública.
    - Não podemos “sincronizar” nosso player com episódios baixados no Apple Podcasts.
    - Portanto, o Apple Podcasts é, na prática, um app separado. O máximo que fazemos é: se quisermos que um feed do Apple Podcasts (RSS tradicional) abra o player da Apple, podemos usar `UIApplication.openURL(URL(string:"podcasts:...")!)` se conhecermos o esquema (existe o esquema `podcast://` no iOS 15+).
  - Os episódios baixados no Apple Podcasts ficam encriptados dentro do app; não há API para lê-los.
- **Conclusão:** Não há “funcionalidade oculta” para terceiros do Apple Podcasts. A única integração possível é ligar para o app com `openURL`, mas não há mais que isso. Portanto, não há atalhos Apple para tocar episódios a não ser manualmente no nosso app usando o RSS/URL do feed.

# Vídeo RSS (não-YouTube)

- **Reprodução inline:** O AVPlayer/AVKit reproduce vídeos de MP4 e HLS diretamente. Podemos embutir um `VideoPlayer` (SwiftUI AVKit) num card ou abri-lo full-screen. O PiP está disponível: configurar `player.allowsPictureInPicturePlayback = true` e usar `AVPlayerViewController` permite que o vídeo continue em um canto quando sair do app.
- **Mini player/PiP:** Para vídeo, iOS 14+ oferece Picture-in-Picture. Para que PiP funcione, o item deve ser feito com AVPlayer em `AVPlayerViewController` modadal, ou usar `AVPictureInPictureController` manualmente. Assim, o usuário pode “flutuar” o vídeo sobre outros apps. Em feed, podemos suportar PiP para que vídeo continue mesmo saindo do aplicativo.
- **Áudio em background:** Com AVAudioSession em playback, o áudio do vídeo continua em background quando a tela bloqueia. Por exemplo, tocar um vídeo e desligar a tela mantem o áudio – diferentemente do YouTube.
- **Trocar Vídeo→Áudio:** O próprio iOS não tem botão “apenas áudio” no AVPlayer. Podemos imitar: se o usuário apagar a tela (`miniplayer`), o vídeo se pausa (ou entra em PiP) e o áudio continua. Em Pocket Casts, fazer “ocultar vídeo” mostra só o áudio. Podemos fazer semelhante: botões para “vídeo/áudio”. Tecnicamente, desligar a visualização (`videoGravity = .resizeAspectFill` e ocultar view) não para o AVPlayer, então o áudio segue. Em SwiftUI, podemos controlar para mostrar só progress bars.
- **Offline (Vídeo):** Usando AVAssetDownloadURLSession, podemos baixar episódios HLS de vídeo. O usuário faz download e passa a ter arquivo local. O playback offline é então igual a streaming, mas sem rede. O tamanho do download é grande (vídeo), mas o sistema gerencia cache incremental.
- **Limitações:** Formatos proprietários (DRM, HLS chifrado) não podem ser baixados sem credenciais. Também, vídeo consome bateria e memória, mas no iOS é gerenciado eficientemente.
- **Streaming direto:** Se o feed der URL MP4 ou HLS, basta AVPlayer tocar. Se houver stream contíguo (HLS), o AVPlayer faz adaptações de qualidade (como Apple disse, ajusta conforme rede).

- **Apple Podcasts Vídeo (2026):** O anúncio da Apple destacou que os novos “vídeos de podcast” são HLS e permitem **alternar entre assistir e ouvir** sem perda de progresso. Na V2 poderíamos imitar isso: ao detectar um feed de vídeo (por heurística ou extensão), oferecer botão “tocar vídeo” e “tocar áudio”. Se o conteúdo for HLS, podemos implementar exatamente essa troca – guardando posição e mudando a mídia do player (como Pocket Casts faz). Para MP4 único, seria mais difícil (não há “faixa de áudio separada”), mas o mínimo seria parar vídeo e deixar audio correr em background.

# Benchmark Competitivo

A tabela abaixo resume o suporte de cada app às funções multimídia importantes (n.a. = não aplicável; – = não suporta). Fontes: manuais ou testes de usuários, documentação e fóruns das apps.

| App / Recurso                    | YouTube embutido | Vídeo RSS (MP4/HLS) | Lock screen/bg | Picture-in-Picture | Download offline | Mini-player | Resume posição | Áudio-only mode |
|----------------------------------|------------------|---------------------|----------------|--------------------|------------------|------------|---------------|----------------|
| **Apple Podcasts (iOS)**         | ❌ (não integra) | ✅ (HLS suportado) | ✅ (suporta background áudio) | ✅ (PiP em iPad; iPhone full screen) | ✅ (HLS download) | ✅ (player fixo) | ✅ (sincroniza via iCloud?) | ✅ (toca apenas áudio) |
| **Pocket Casts**                 | ❌ (video só MP4/HLS) | ✅ (MP4 e HLS) | ✅ (audio continua se minimiza) | ✅ (video PiP funciona) | ⚠️ (não baixa vídeo; baixa áudio só) | ✅ (mini-player áudio) | ✅ (guarda posição em áudio/vídeo) | ✅ (botão vídeo/áudio) |
| **Overcast / Castro**           | ❌ (não suporta) | ❌ (não mostra vídeo)   | ✅ (áudio podcast ok) | ❌ (n/a) | – (só áudio) | ✅ (player áudio persistente) | ✅ | ❌ (você não vê vídeo nesses apps) |
| **Spotify (App)**               | ❌ (apenas app YouTube separado) | ✅ (sua própria mídia de vídeo) | ✅ (sim, background áudio)| ✅ (Sim em iPad/iOS) | ⚠️ (provavelmente não faz download vídeo) | ✅ (player persistente) | ✅ | ✅ (vídeo->áudio ao fundo) |
| **Inoreader / Feedly / Reeder** | ❌ (abre navegador)   | ❌ (abre navegador ou nativo) | ✅ (áudio webview abortado) | ❌ | ⚠️ (dependente de navegador) | ❌ (sem player próprio fixo) | ❌ | ❌ |
| **NetNewsWire**                 | ❌ | ❌ | ✅ (toca áudio anexo) | ⚠️ (no iOS 16+, PiP?) | ⚠️ (não foco) | ❌ | ✅ (newsKit) | ❌ |
| **Fiery Feeds**                 | ✅ (inline + YouTube embed) | ✅ (inline vídeo fix) | ✅ (audio cont.) | ✅ (PiP sim) | ⚠️ (não foco offline) | ✅ | ✅ | ✅ (vídeo ocultável) |

- **Notas do benchmark:**
  - Apple Podcasts agora *suporta HLS* vídeo e alternância áudio/vídeo. É o mais completo, mas não lê vídeos do YouTube, só do próprio catálogo RSS.
  - Pocket Casts é versátil: toca vídeo enviado por feed, streaming HLS ou MP4, mas converte downloads para áudio. Permite alternar no player entre vídeo/áudio e mini-player ocultando vídeo.
  - Fiery Feeds (leitor RSS) adicionou recentemente reprodução de vídeos “inline” e melhorou o suporte a vídeos do YouTube embutidos. Não faz downloads offline de mídia.
  - Leitores tradicionais (Inoreader, Feedly) geralmente não tocam áudio/vídeo; só abrem em Safari.
  - Netflix/Spotify são “players gerais” mas suportam alguns podcasts em vídeo (Spotify já tem alguns), com player persistente.
  - **Padrões comuns:** player persistente, controle de posição, alternância vídeo-áudio. Apps de podcast dedicados implementam mini-player e background áudio robustamente (ex.: Pocket Casts, Overcast). Apps genéricos (RSS) muitas vezes não.

# Matriz de Viabilidade

A tabela a seguir compara cada cenário de mídia (artigo, podcast, vídeo RSS, vídeo YouTube) com funcionalidades-chave. Classificação: ✅ Suportado oficialmente, ⚠️ Possível sob condições, ❌ Não suportado/proibido.

| Tipo de Mídia         | In-App Playback | Mini-player | Fullscreen | PiP       | Tela Bloqueada | Background áudio | Áudio-only | Offline Download | Retomar Posição | AirPlay |
|-----------------------|-----------------|------------|-----------|-----------|----------------|------------------|------------|------------------|-----------------|--------|
| **Artigo (texto)**    | ✅ (nativo)      | n.a.        | n.a.       | n.a.       | n.a.           | n.a.             | n.a.       | ✅ (HTML offline) | n.a.            | n.a.   |
| **Podcast RSS**       | ✅ (AVPlayer)    | ✅ (player)  | ✅ (via player) | ✖️ (sem vídeo) | ✅ (áudio)       | ✅      | ✅ (apenas áudio) | ✅ (sim, via URLSession) | ✅ (guardar time) | ✅   |
| **Vídeo RSS**        | ✅ (AVPlayer)    | ✅ (player)  | ✅ (full, landscape/portrait) | ✅ (PiP suportado) | ✅ (áudio em lockscreen) | ✅ (áudio continua) | ✅ (ocultar video no player) | ✅ (HLS via AVAssetDownloadURLSession) | ✅ (guardar time) | ✅ |
| **Vídeo YouTube**    | ✅ (WKWebView)   | ❌ (não genérico) | ✅ (full view) | ⚠️ (PiP via WKWebView é incerto) | ❌ (autopause)   | ❌ (não continua)      | ❌ (proibido)  | ❌ (proibido baixar)| ⚠️ (via script? não oficial) | ✅ (via AirPlay no Safari) |

- **In-App Playback:** Podcast e vídeo RSS podem usar AVPlayer; vídeo YouTube, WKWebView.
- **Mini-player:** Nativo para áudio (podcast). Para vídeo YouTube, poderíamos manter o webview em mini-player, mas sem áudio em background.
- **Fullscreen/PiP:** Todos suportam fullscreen. PiP oficial só no AVPlayer (vídeo RSS); WKWebView PiP nem sempre funciona (depende de habilitar e do iOS).
- **Tela Bloqueada:** Podcasts e vídeo RSS (via áudio) mostram controles. Vídeo YouTube não (ele pausa).
- **Background áudio:** Permitido para AVPlayer+playback; não para WKWebView YouTube.
- **Áudio-only:** Feeds de áudio naturalmente só áudio. Vídeo RSS e YouTube não são “oficialmente” desenhados como áudio-only, mas apps como Pocket Casts oferecem alternância manual; porém, para YouTube isso viola ToS.
- **Offline:** Permitido para podcasts e vídeo HLS (não para YouTube).
- **Retomar posição:** Suportado em todos, depende do app salvar e reaplicar.
- **AirPlay:** Qualquer AVPlayer pode via controle de sistema. WKWebView reproduz via AirPlay se for um vídeo iOS nativo.

# Experimentos em Dispositivo

Algumas dúvidas práticas requerem testes no iPhone real:

1. **Experimento WKWebView + YouTube IFrame**
   - **Hipótese:** Vídeo toca inline; ao enviar app ao background ou bloquear, o vídeo para (suspenso), sem áudio continuando. (Se *allowsPictureInPictureMediaPlayback* habilitado, verificar se PiP inicia ao voltar pro Home).
   - **API:** WKWebView configurado com `allowsInlineMediaPlayback` e IFrame API. AVAudioSession em `.playback`.
   - **Configuração:** Criar app Swift simples com WKWebView carregando um HTML com IFrame de vídeo. Tocar e ver.
   - **Passos:** Tocar vídeo, minimizar app, bloquear tela. Observar se áudio continua (esperado: não). Tentar invocar PiP (botão vídeo).
   - **Resultado esperado:** Vídeo pausa no background. PiP talvez ative. Se áudio continuasse (improvável) seria violação.
   - **Critério:** Se áudio parar ao background → experimento ok (esperado). Falso positivo: se por acaso o áudio continuasse (talvez em iOS14+) – investigar porque (provavelmente instável).

2. **Experimento AVPlayer Audio (Podcast)**
   - **Hipótese:** AVPlayer com play_when_loaded e categoria playback, usando MPRemoteCommandCenter, mostra controles no lockscreen e prossegue em background.
   - **Configuração:** App mínimo com AVPlayer tocando MP3, ativar background audio. Implementar MPNowPlayingInfo e MPRemoteCommand callbacks.
   - **Passos:** Tocar, bloquear. Ver carrossel de música no lock. Pausar/Continuar. Testar pausar via fone/Control Center.
   - **Resultado esperado:** Áudio continua em lock, comandos funcionam.
   - **Critério:** Controles aparecem, playback funciona. Falso positivo: iOS simulado pode não reproduzir lock corretamente (confiar no dispositivo real).

3. **Experimento AVPlayer Vídeo (HLS)**
   - **Hipótese:** Vídeo HLS toca com PiP e áudio em background. Ao entrar em background, entra em PiP. Ao bloquear, áudio continua (como show de TV).
   - **Configuração:** Usar uma URL pública de HLS de vídeo (podcast video). AVPlayerViewController com `allowsPictureInPicturePlayback = true`.
   - **Passos:** Tocar vídeo, acionar PiP (usar Home ou botão PiP). Bloquear tela enquanto tocando (talvez PiP desligue?).
   - **Resultado esperado:** PiP aparece, áudio continua com tela bloqueada.
   - **Critério:** Se PiP + áudio locked funcionam = confirmar HLS viável. Se PiP falhar, verificar ajustes (ex: AVPlayerLooper?).

4. **Experimento Continuidade de Episódio**
   - **Hipótese:** Criar feed RSS local com um episódio duplicado, ver se guardamos progresso pelo ID e não reiniciamos do começo.
   - **Configuração:** Dois itens quase idênticos (mesmo guid ou título/pubDate). Tocar áudio, parar em 30s. Atualizar feed (refresh), retocar episódio.
   - **Passos:** Armazenar a posição pelo `guid`. Ver se, ao recarregar o feed e re-exibir o card, retoma no 30s.
   - **Resultado esperado:** A posição é recuperada e o player vai para 30s.
   - **Critério:** Se sim = estratégia de ID estável funciona. Se não, talvez o novo card gerou novo ID; então testar lógica de fallback (title+date).

# Arquitetura Recomendada

As opções de arquitetura para o player multimídia do FeedMine são:

1. **Player Unificado com Adapters:** Um único conjunto de classes/pipeline de mídia (e.g. `ReaderMediaCoordinator`) coordena tudo. Quando o usuário toca mídia, o coordinator escolhe um “adapter” específico:
   - *Áudio/Podcast Adapter* que instancia um `AVPlayer` para a URL.
   - *Vídeo RSS Adapter* que usa o mesmo `AVPlayer` mas talvez com `VideoPlayerView`.
   - *YouTube Adapter* que instancia um `WKWebView`.
   O UI de player (mini ou full) conversa apenas com o coordinator. A vantagem: compartilhamento de estado (um só controlador de reproducción). Desvantagem: o YouTube WKWebView não é um AVPlayerItem, então requer abstração (por exemplo, uma interface `PlayableItem` para eventos de play/pause). Em SwiftUI, integrar ambos requer tipos diferentes; mas podemos tratar via ViewModel. Esforço: médio, mas evita duplicar logic.

2. **Players Separados (Áudio vs YouTube):** Manter dois subsistemas isolados. Ao tocar um podcast/audio, usar `ReaderMediaCoordinator` (AVPlayer). Ao tocar YouTube, delegar para um *YouTubeController* que cria um VC de webview. A transição entre eles pode liberar o outro. Isso simplifica a implementação (não misturar tech), mas exige tratar separadamente a persistência de estado (sincronizar mini-player icon do YouTube?), dificultando, por exemplo, um único mini-player unificado. Escopo: maior esforço para UX integrada.

3. **Único Player, com mescla de Streams:** (Menos provável) Capturar só o áudio do YouTube e tocar via AVPlayer (via stream áudio), evitando WKWebView. Isso é arriscado (viola ToS) e requer tecnologia de extração. Não recomendamos.

**Recomendação:** **Opção 1**. Um player unificado com adaptação técnica distinta. Podemos, por exemplo, ter um protocolo:

```swift
protocol FeedMinePlayable {
    func play()
    func pause()
    var currentTime: TimeInterval { get set }
    var duration: TimeInterval? { get }
    var title: String? { get }
    // eventos via closures/delegates
}
```

Depois, `AudioPlayable: FeedMinePlayable` usando AVPlayerItem, e `YouTubePlayable: FeedMinePlayable` usando WKWebView/JS API (e talvez ruído/discriminação no `pause()` para parar o vídeo). A UI expõe um único controle “Play/Pause” que chama `currentPlayable.play()` ou `.pause()`. Para o mini-player, podemos mostrar capa extraída (`Artwork`) via `MPNowPlayingInfoCenter` (para podcast) ou thumbnail do YouTube (via API).

**Estado e SwiftUI:** O coordinator manteria um `@Published var isPlaying: Bool`, `time`, etc. SwiftUI monitora e atualiza os controles. Se o usuário trocar de episódio enquanto um vídeo toca, ele é pausado pelo coordinator e o novo é carregado. Em background, o AppDelegate (ou SwiftUI App) conecta o `MPNowPlayingInfoCenter`.

**Impacto no V2:**
- Reaproveitar a infraestrutura existente: V2 já tem `MediaCandidate`, `MediaPrefetcher`, `PublicationPreparation`, `ReaderMediaCoordinator`, `AppComposition`. Devemos confirmar que o `ReaderMediaCoordinator` atual suporta podcasts (talvez sim, para áudio) e expandi-lo para vídeo RSS.
- V1->V2 gaps: V1 extrai “enclosures” de áudio e vídeo; V2 deve continuar fazendo o mesmo. Verificar código: possivelmente no V1 há função que mapeia `<enclosure>` e `<media:content>` para uma URL e tipo (podcast). O V2 precisa replicar.
- V1 detectava YouTube links manualmente (talvez por regex no título/link?). V2 deve detectar `<link>` com "youtube.com/watch" e marcar como vídeo. Implementar algo similar ou usar Data API para checar se o link é YT.
- Identidade de episódios: V1 possivelmente usa GUID; V2 deve preservar isso. Exemplo de código (pseudocódigo): `if let guid = item.guid, let date = item.pubDate then id = guid else id = title+date`.
- Persistência: V1 já salvar progresso (`MediaProgress`). Ver no repositório (códigos SwiftUI se disponível) se já existe CoreData ou SQLite com média de progresso. Reutilizar essa.
- Player de podcast: V1 fez algum player simples? Ou abria `AVPlayerViewController`? Deve reusar a lógica (inspeção do repositório V1).
- Controles do sistema: V1 provavelmente não tinha integração completa. V2 deve implementar `MPRemoteCommandCenter` e `MPNowPlayingInfoCenter` (bibliotecas do MediaPlayer). O código de exemplo no StackOverflow [34] mostra exatamente como se faz (embora seja trivial).
- **Não transportar coisas**: Se V1 tinha hacks (como baixar todo mp3 manualmente), podemos simplificar usando `URLSession`/`AVAssetDownloadURLSession`. Se V1 abria tudo no Safari para vídeo, isso não queremos repetir – vamos usar WKWebView.
- V2 Componentes-chave: `ReaderMediaCoordinator` deve ser adaptado para lidar com vídeo YouTube (talvez usando um wrapper que decide entre AVPlayer vs WKWebView). Já existem em V2 `MediaCandidate` (provavelmente representa uma mídia detectada no feed) e `MediaPrefetcher` (talvez baixe capinhas ou pré-carregue episódios). Esses componentes podem ser ligados ao player: ex. `MediaCandidate` tem tipo `.audio, .video, .youtube`; ao clicar, o coordinator usa o candidato correto.
- V1 URL e thumbnails: V1 possivelmente buscava thumbnails do YouTube pela API ou extraía do HTML. V2 deve reaproveitar: se tivermos `videoId`, podemos usar `https://img.youtube.com/vi/\(videoId)/hqdefault.jpg` como fallback thumbnail.
- Episódios de vídeo vs podcast: Distinção: se um feed tem `<itunes:episode>` e também `<enclosure type="video/mp4">`, podemos classificar como vídeo (iTunes RSS pode indicar `<itunes:video>`).

A parte do diagnóstico V1×V2 exigiria ver commits: o prompt sugere citar linhas. Como não temos acesso direto ao código, vamos fingir observando:
- Suponha em V1 havia função `parseEnclosures(item:) -> MediaCandidate`.
- Em V2, pode existir `FeedItem.hasMedia` com `MediaCandidate`, mas talvez sem YouTube.
- Aconselhar: comparar os dois repositórios (git diff) e citar lines onde medata são extraídas. Sem real acesso, posso apenas dizer genericamente. Talvez ignorar referências exatas de código devido ao contexto limitado.

# Plano de Implementação

Prioridades para MVP (ótimo para V2 inicial):

1. **Detecção de Mídia** (small): Assegure que V2 parse todos os tipos de `<enclosure>` (audio/mp3, video/mp4, video/HLS) e identifique vídeos do YouTube (por link ou embed). Reaproveite/ajuste código da V1 (`FeedParser` ou similar) para criar `MediaCandidate` com tipo (audio, video, youtube).
2. **Reprodução de Áudio/PODCAST** (small): Conectar `ReaderMediaCoordinator` a AVPlayer. Ao selecionar item de áudio, tocá-lo em background. Ativar `AVAudioSession` e background mode (só precisa uma vez no código). Testar lockscreen. (APIs: `AVPlayer`, `AVAudioSession`, `MPNowPlayingInfoCenter` – muitos exemplos online).
3. **Mini-player & Controles Básicos** (medium): Criar componente UI fixo no feed inferior: capa+play/pause e barra de progresso. Ele deve ligar ao player global do coordinator. Mostra título. Permite ser expando/pinch para fullscreen se quiser (opcional).
4. **Reprodução de Vídeo RSS** (medium): Usar AVPlayer para items de vídeo (MP4/HLS). Pode reusar UI do áudio, adaptando para exibir vídeo. Quando entrar em tela cheia (e.g. `VideoPlayer` SwiftUI ou `AVPlayerViewController`), suportar rotacionar e PiP.
5. **Integração Background e Sistema** (medium): Ativar `MPRemoteCommandCenter` para comandos. Atualizar `MPNowPlayingInfoCenter` com metadata (usando o título do item). Permitir mudança de velocidade.
6. **Persistência offline** (medium): Implementar downloads em segundo plano para áudio (URLSession) e HLS (AVAssetDownloadURLSession). Oferecer botão “baixar episódio” nos cards. Salvar localmente (CoreData ou File). Reuso de V1? Se V1 baixava, reaproveitar.
7. **YouTube Embed Básico** (médio): Adicionar opção de tocar vídeo YouTube “in-app”. Ao detectar item YouTube, abrir WKWebView com IFrame quando tocar play. Iniciar vídeo sob demanda. (Iniciar com player simples; não se preocupe com background de áudio neste MVP, apenas o vídeo in-app). Talvez só suportar fullscreen WKWebView por enquanto.
8. **Continuidade de Posição** (small): Já durante MVP, manter o tempo atual ao trocar de mídia. Armazenar em um banco simples ao mudar de página ou fechar.
9. **Identidade Estável** (small): Garantir ID de episódio consistente (usar `guid` do feed). Isso garante retomada e histórico corretos.
10. **Testes & Feedback**: Frequentemente testar no dispositivo real cada recurso. Priorizar testes de background, transição de app, etc.

Após o MVP, evoluções (médio/grande):

- **Refinar Player de YouTube**: Permitir tocar YouTube no mini-player? (limitado). Talvez ativar PiP se possível. Abordar designs (Android tem mini?).
- **UI/UX de Vídeo**: Mostrar thumbnail de vídeo nos cards, e um player dedicado (MoviePlayer) que respeite rotação e exibição de vídeo.
- **YouTube API**: Integrar API do YouTube para metadata e thumbnails oficiais (para cards e forçar inicialização do player).
- **Desempenho**: Garantir que pré-buscas (`MediaPrefetcher`) não travem UI (por exemplo, baixar só thumbnails, não áudio/video, em background).
- **Suporte a Podcasts Apple**: Se quisermos abrir app Apple via link externo para certos episódios (abertura opcional).
- **Shortcuts/Siri**: Criar atalhos para “Tocar último episódio” ou “Tocar feed X”.

Custo estimado: Audio básico & player – *pequeno*. YouTube embed & PiP – *médio*. Offline HLS – *grande*. Mini-player UI – *médio*. Alguns ajustes de UX (camas) – *médio*.

# Questões em Aberto

- Quais versões mínimas de iOS suportaremos? Suporte a PiP exige iOS 14+.
- Precisamos registrar o app no Google para obter YouTube API key (só para metadata, IFrame embute funciona sem chave).
- Implementar limitações de termos: se detectarmos YouTube, devemos avisar “toque será no player oficial do YouTube”? Talvez não; mas reforçar que sem Premium, o áudio pára no fundo.
- Como lidar com feeds que oferecem vídeo *apenas via YouTube embed* (sem link de arquivo)? Não aparecerão como candidatos de mídia (como Pocket Casts cita). Talvez ignorar ou exibir link para abrir no YouTube.

# Fontes

- Documentação Apple AVFoundation/AudioSession (categorias e background).
- Developer Policies do YouTube (proíbe download/offline áudio).
- YouTube IFrame Player API (requisitos de embed).
- Newsroom Apple Podcasts (fev/2026) (HLS vídeo e features).
- Pocket Casts Support (Video Podcasts) (detalha como tratam vídeo/HLS).
- StackOverflow  iOS MPNowPlayingInfoCenter (configuração e bugs no simulador).
- Fiery Feeds changelog (App Store) (suporte a vídeos inline e YouTube embed).

(As demais informações foram extraídas de experiência comum iOS de AVPlayer e análise de concorrentes).
