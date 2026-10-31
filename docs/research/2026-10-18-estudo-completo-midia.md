---
title: "FeedMine | Estudo completo de experiências multimídia e arquitetura de playback"
subtitle: "Inoreader · Pocket Casts · Readwise Reader · Snipd | Evidências, UX, protocolos, Swift 6 e proposta de aplicação"
date: "18 de outubro de 2026"
lang: pt-BR
---

# FeedMine — Estudo completo de experiências multimídia e arquitetura de playback

**Benchmark técnico e de produto:** Inoreader, Pocket Casts, Readwise Reader e Snipd
**Data de corte da investigação:** 18 de outubro de 2026
**Aplicação-alvo:** FeedMine iOS, local-first/offline-first, sem servidor próprio de conteúdo
**Natureza:** estudo externo e proposta de engenharia, **não** especificação aprovada nem auditoria do HEAD do repositório
**Bases internas:** *Unified Architecture Blueprint v0.4* [F01], *Feed Runtime V2 — Technical Architecture Specification v0.1* [F02] e princípios de produto [F03].

> **Resumo da tese.** O FeedMine deve apresentar mídia heterogênea sem fazer da reprodução uma dependência da interface do feed. Um card preparado é um artefato local e estável; uma sessão de playback é uma atividade distinta, iniciada pelo usuário, que pode acessar a rede segundo a política aplicável. A maior contribuição dos produtos estudados não está em seus players isolados, mas na preservação de contexto, identidade, progresso, escolha de representação e navegação sobre conteúdo temporal.

## Sumário executivo

1. **Inoreader:** integra podcasts e YouTube ao mesmo modelo editorial de feeds; suas quatro representações de episódio — descrição, transcrição, tópicos e artigo — demonstram como um conteúdo longo pode oferecer consumo rápido e aprofundado. A interface e o anúncio oficial são verificáveis; o mecanismo interno de cache, reprodução e extração não é público [S01].
2. **Pocket Casts:** é o benchmark técnico mais importante porque seu cliente iOS é aberto. O repositório expõe `PlaybackManager`, apresentação do `AVPlayer`, capítulos, transcrições, posição de reprodução, integração com Now Playing e instrumentos de rede. Uma documentação técnica detalha inclusive o alinhamento por *audio fingerprinting* contra inserção dinâmica de anúncios [S02–S10].
3. **Readwise Reader:** transforma vídeos do YouTube em documentos navegáveis e anotáveis; seu diferencial está em transcrição sincronizada, *autoscroll* controlável, destaque, escolha de idioma e melhorias de formatação. O risco exemplificado é perder a posição visual de highlights quando uma transcrição é reformatada [S11–S13].
4. **Snipd:** demonstra uma interação de baixíssima fricção: salvar um trecho usando o comando de voltar dos fones, enriquecendo-o com transcrição e resumo. Também oferece downloads dirigidos pela fila e hábitos de escuta. Seu pipeline de IA e distribuição entre cliente/servidor não são publicamente auditáveis [S14–S17].
5. **Para o FeedMine:** o MVP recomendado é descoberta canônica de mídia + poster/placeholder local + ação Play explícita + sessão única de reprodução nativa + progresso persistente + tratamento separado e conforme políticas do YouTube. Transcrições publicadas, capítulos e bookmarks entram na evolução seguinte. Fingerprinting e IA ampla **não** entram no MVP.

**Decisão recomendada:** aproveitar os owners já existentes no V2 e criar/expandir **um** owner de playback apenas se não houver um equivalente. Não adicionar outro engine de feed, outra fila de aquisição, cache paralelo de cards ou dependência de rede no renderizador. A arquitetura de mídia deve satisfazer as invariantes do Blueprint v0.4 e não competir com elas [F01–F03].

---

# PARTE I — Método, evidência e comparação

## 1. Escopo, método e limites

O estudo cobre quatro produtos e seis dimensões: (a) aquisição/identificação de mídia; (b) UI de feed e player; (c) continuidade, background e offline; (d) transcrições, capítulos e bookmarks; (e) arquitetura observável e código público; (f) tradução para FeedMine. Inclui documentação oficial dos fornecedores, guias de produto, documentação Apple/YouTube, padrão Podcasting 2.0 e arquivos específicos do repositório Pocket Casts iOS. Não inclui testes instrumentados do aplicativo instalado em um dispositivo; fluxos descritos devem ser lidos como **comportamento documentado**, não como medições de campo.

**Classificação de evidência usada neste relatório:**

| Classe | Significado | Como interpretar |
|---|---|---|
| **E1 — Código público** | Arquivo ou PR inspecionável com funções/contratos reais | Forte para o código daquela revisão; não garante release de produção |
| **E2 — Documentação oficial** | Declarações explícitas de fornecedor, Apple ou padrão | Forte para produto/política; não revela automaticamente o mecanismo interno |
| **E3 — Inferência controlada** | Proposta ou conclusão compatível com evidências | Não atribuir ao código fechado de outros aplicativos |
| **E4 — Proposta FeedMine** | Decisão recomendada ou código ilustrativo | Requer validação em repo, Xcode, dispositivos e testes |

**Cuidados temporais:** o Pocket Casts lançou destaque sincronizado de transcrição em junho de 2026 e *Smart Bookmarks* em setembro de 2026 [S03, S04]. O PR #5336, consultado para esta análise, estava **aberto em 18/10/2026**; sua melhoria de streaming áudio/vídeo é uma proposta em revisão, não uma funcionalidade cuja distribuição esteja comprovada [S08]. Esse status deve ser reavaliado antes de usar o PR como evidência de release.

## 2. Matriz executiva de comparação

| Eixo | Inoreader | Pocket Casts | Readwise Reader | Snipd |
|---|---|---|---|---|
| Unidade editorial | Artigo/entrada de feed | Episódio na biblioteca/fila | Documento, inclusive vídeo | Episódio e trecho capturado |
| Áudio em background | Sim, documentado | Sim, solução central | Não é foco desta pesquisa | Sim, experiência de escuta |
| Vídeo RSS | YouTube e vídeo em feeds | Videocasts, HLS/arquivos | Principalmente URL do YouTube | Importação de YouTube para áudio |
| Miniplayer independente | Player associado à leitura | Implementação pública de player/superfície separada | Player e transcript no documento | Player orientado à escuta |
| Transcrição temporal | Sim; geração no Pro | Sim; cues e destaque para transcrições geradas | Sim; navegação e anotação | Sim; base dos snips |
| Capítulos | Topics gerados | Embed, Podcast Index, Podlove, IA | Navegação por trechos | IA e metadados de episódio |
| Controle pelos fones | Playback convencional | Integração de comandos | Não é diferencial documentado | Criar snip com comando de voltar |
| Código iOS público | Não localizado | **Sim** [S02] | Não localizado | Não localizado |
| Maior lição para FeedMine | Multimodalidade integrada | Ownership e continuidade | Navegação temporal | Captura sem fricção |

**Leitura correta da tabela:** a ausência de informação em código não prova ausência de funcionalidade. Também não se deve confundir “vídeo minimizado com áudio audível” com “substituição de um stream de vídeo por um stream somente de áudio”.

## 3. Critérios de avaliação para um feed local-first

Para um feed tradicional, “funciona” costuma significar que tocar em Play reproduz a mídia. Para o FeedMine, esse critério é incompleto. Uma solução adequada deve preservar simultaneamente:

- **Runway local e adaptativo:** cards publicados e apresentação não aguardam vídeo, transcrição ou stream remoto para sustentar o scroll.
- **Identidade e imutabilidade:** mudança de rota, filtro, origem ou asset não altera silenciosamente um card já publicado.
- **Independência operacional:** a sessão de reprodução continua enquanto novos segmentos são admitidos, preparados ou publicados.
- **Direitos e políticas:** YouTube embutido não é tratado como MP3 direto, nem tem áudio extraído ou playback oculto por conveniência.
- **Recursos limitados:** mídia cara somente quando há intenção clara; capas e placeholders são recursos de apresentação, vídeo completo é recurso de consumo.
- **Dados pessoais duráveis:** progresso, bookmarks e notas sobrevivem à remoção de caches/revisões reconstruíveis.

---

# PARTE II — Investigação dos quatro produtos

## 4. Inoreader: áudio e vídeo como formas de leitura

### 4.1. Comportamento funcional comprovado

Em setembro de 2025, o Inoreader documentou a renovação do player de podcasts e melhorias para vídeos do YouTube. O áudio pode começar dentro da página do artigo e continuar em background; existem controles de velocidade, salto para frente/atrás e fila de episódios. Assinar um podcast envolve pesquisa ou colagem de URL; depois ele aparece ao lado dos demais feeds [S01]. Isso importa: a mídia é uma entrada editorial, não uma categoria inteiramente desconectada do leitor.

O produto também apresentou quatro abas associadas ao episódio: **Description** (texto fornecido pela origem), **Transcript** (transcrição com pontos clicáveis), **Topics** (assuntos derivados com timestamps) e **Article** (transcrição reestruturada como artigo). A documentação coloca esses recursos enriquecidos no plano Pro [S01]. Não é apropriado inferir que toda publicação tenha uma transcrição disponível ou que os temas sejam gerados localmente no dispositivo.

### 4.2. Modelo mental de UX

O valor da interface é reconhecer que “consumir mídia” não implica necessariamente “assistir do começo ao fim”. Um vídeo longo, localizado durante a leitura do feed, pode ser: examinado pela capa e título; escaneado pela descrição; consultado pelos tópicos; lido por transcrição; reproduzido quando o usuário decide aprofundar. O mesmo episódio preserva a identidade editorial nas diferentes apresentações.

**Aplicação ao FeedMine:** publicar o card com sua melhor representação local; disponibilizar ações contextuais condicionadas à existência de dados — “Ouvir”, “Assistir”, “Ler transcrição”, “Ver capítulos” — sem exigir todas elas como pré-condição de publicação. A existência de quatro possibilidades **não** autoriza baixar e processar toda a mídia antecipadamente.

### 4.3. Comportamento quando rede/IA falham

A documentação consultada não detalha política de revalidação de cache, desduplicação de transcrição, cancelamento de tarefas ou prevenção de *stale work*. Não há base pública suficiente para afirmar detalhes dessas implementações. A alternativa de produto mais segura para o FeedMine é preservar um card legível mesmo quando os enriquecimentos ainda não foram materializados.

### 4.4. O que copiar e o que não copiar

**Copiar o princípio:** mídia aparece onde o conteúdo editorial já está; playback, transcrição e resumo são formas de consumo complementares. **Não copiar sem evidência:** suposto uso de um player universal, arquitetura em nuvem, modelo de filas ou estratégias internas de extração. **Risco de imitação superficial:** criar uma aba “Transcript” vazia que depende de gerar texto em tempo real ao tocar no card, provocando latência imprevisível e exigindo rede para algo que deveria ser opcional.

## 5. Pocket Casts: fonte primária de engenharia e produto

### 5.1. Repositório e componentes identificados

O cliente iOS é aberto sob a organização Automattic [S02]. A revisão de código inspecionada nesta pesquisa foi `c234167db1c380972d97823ceaafcf2b01bb595e` (referência de leitura), enquanto links `trunk` da bibliografia acompanham o desenvolvimento e podem mudar. Os arquivos abaixo constituem um mapa de implementação real; os links apontam para caminhos públicos, cuja revisão exata pode evoluir.

| Componente público | Responsabilidade evidenciada | Risco de adaptação literal |
|---|---|---|
| `podcasts/PlaybackManager.swift` | Episódio atual, fila, estado, posição, source switching | Grande componente: não transplantar inteiro |
| `podcasts/PlaybackProtocol.swift` | Abstração de capacidades de player | Interfaces dependem dos engines existentes |
| `podcasts/VideoPlayerView.swift` | `UIView` com `AVPlayerLayer` | Layout e KVO precisam respeitar ciclo de vida |
| `podcasts/FloatingVideoView.swift` | Superfície flutuante com proporção e fullscreen | Não confundir superfície com sessão |
| `podcasts/TranscriptManager.swift` | Seleção e carregamento de transcrição | Parte depende de metadados do serviço |
| `podcasts/TranscriptModel.swift` | Conversão de formatos em cues de texto | Avaliar casos malformed e idiomas |
| `podcasts/TranscriptsDataRetriever.swift` | Actor para deduplicação e revalidação | Não adicionar cache redundante ao FeedMine |
| `podcasts/PodcastChapterParser.swift` | Capítulos locais/remotos/Podlove/Podcast Index | URLs e metadados requerem validação |
| `podcasts/NowPlayingHelper.swift` | Centro de mídia do iOS, tempo e artwork | Erros sutis de sincronização com sistema |
| `podcasts/StreamingCellularTracker.swift` | Logs de bytes, classificação Wi-Fi/celular | Instrumentação não substitui política de rede |
| `docs/transcripts.md` | Fingerprints e mapeamento entre dois tempos | Alto custo; não copiar para o MVP |

Referências: [S02, S05–S10].

### 5.2. Ownership do player: o ponto arquitetural mais transferível

`PlaybackManager` concentra responsabilidades que não pertencem às linhas de UI. A tela pede que um episódio comece; o owner mantém episódio, posição, estado e conexão com a fila. Quando o usuário navega, a sessão é preservada. Há operações para registrar posição, atualizar Now Playing, atender mudanças de rota de áudio e trocar a fonte de reprodução [S05].

**Invariante FeedMine proposta:** nenhuma `FeedCardView`, `LazyVStack`, `FeedPresentationSnapshot` ou reducer do feed é dona de uma instância durável de `AVPlayer`. O owner de playback existe na composição do aplicativo e recebe intenções explícitas. Ele não refaz selection nem altera `FeedEdition`.

### 5.3. AVPlayer versus superfície de vídeo

`VideoPlayerView.swift` implementa uma `UIView` cuja camada principal é `AVPlayerLayer`; o player é injetado como propriedade. `FloatingVideoView.swift` ajusta geometria e oferece retorno ao modo fullscreen [S06]. A separação é relevante: pode-se montar, desmontar e reposicionar a superfície sem abandonar a sessão nativa.

Não confundir três operações: **(1)** ocultar `AVPlayerLayer`; **(2)** pausar `AVPlayer`; **(3)** trocar o asset/stream de um `AVPlayer`. A primeira não garante economia de transferência. A segunda altera estado. A terceira exige política de sincronização e pode causar rebuffers ou pequenas diferenças de tempo.

### 5.4. Videocasts: HLS e áudio alternativo

Na revisão inspecionada de `PlaybackManager`, ocultar vídeo em uma transmissão HLS podia ser apenas uma mudança visual, enquanto episódios com cópia local de áudio podiam recarregar o player para alternar entre arquivo local e stream [S05]. O PR **#5336** propõe corrigir a seleção da fonte quando existe enclosure de áudio: com “Audio only” ou “Hide Video”, escolher áudio progressivo no lugar do HLS de vídeo; ao reativar vídeo, mudar de volta preservando posição e estado. Também contempla fallback para HLS quando não existe enclosure válido. A PR estava **aberta**, não mesclada, na data de corte [S08].

**Conclusão:** não alegar que o Pocket Casts lançado já oferece exatamente esse comportamento de economia de banda. O que o código e a PR provam é a distinção operacional entre ocultação visual e troca real de fonte — excelente contrato para o FeedMine.

### 5.5. Transcrições: o que funciona e para quem

O anúncio de 24/06/2026 confirma destaque sincronizado de frases e toque para seek [S03]. A documentação de suporte acrescenta restrições relevantes: no recurso lançado, o destaque sincronizado se aplica a transcrições geradas pelo próprio Pocket Casts, associadas ao plano Plus/Patron, requer conexão, e **não** se aplica do mesmo modo a transcrições fornecidas externamente pelos criadores [S04]. Uma implementação FeedMine que parte de VTT/SRT próprio poderia ter destaque temporal simples **offline**, mas isso seria uma solução nova, não equivalência funcional certificada ao Pocket Casts.

`TranscriptModel.swift` normaliza partes do texto em intervalos com `startTime`, `endTime` e `characterRange`. Ele também reconhece várias sintaxes, incluindo VTT, SRT, JSON do Podcast Index e alternativas do Flightcast [S09]. É um bom precedente para normalizar formato na borda e apresentar um único modelo de cues.

### 5.6. Duas linhas do tempo: o problema de anúncios dinâmicos

Transcrições produzidas a partir de um áudio “de referência” podem divergir do stream recebido por um usuário. Inserção dinâmica de anúncios, silêncio de abertura ou encodings distintos deslocam offsets. A documentação `docs/transcripts.md` explica um mecanismo de *audio fingerprinting* que estabelece pares `(playbackTime, referenceTime, score)` e consulta o mapeamento antes de iluminar o texto [S07].

O mecanismo descrito processa áudio em janelas e estabelece checkpoints de confiança. Ele recusa saltos sem sequência consistente, desliga o destaque quando está sobre uma região não reconhecida (como anúncio ausente da referência) e retoma quando encontra áudio correspondente. Há tratamento para cache do mapeamento, invalidação por hash/versão e trabalho em fila utilitária em vez de bloquear a consulta da interface.

**Lição geral:** destacar texto exige evidência positiva de correspondência, não uma suposição permanente de que “relógio da transcrição = relógio do player”. **Decisão de escopo:** no FeedMine, VTT/SRT explicitamente atrelados à mídia e sem sinais de drift admitem navegação temporal básica; fingerprinting fica fora do MVP. Se o usuário encontrar anúncios dinâmicos, a UI deve permitir marcação “sincronização aproximada” ou simplesmente deixar de acompanhar quando não houver confiança.

### 5.7. Capítulos, cache e controle de dados

`PodcastChapterParser.swift` distingue capítulos embutidos, Podlove, Podcast Index e fontes geradas [S10]. Em 07/07/2026, o serviço anunciou capítulos gerados por IA como fallback quando os fornecidos pelo criador não existem; o anúncio ressalta que títulos automáticos podem estar incorretos [S18]. Portanto, os capítulos do publicador devem manter precedência sobre enriquecimentos inferidos.

`TranscriptsDataRetriever.swift` utiliza um actor e mapa de tarefas por URL para evitar múltiplas requisições concorrentes para a mesma transcrição. Usa resposta em cache e revalidação. `StreamingCellularTracker.swift` conta bytes de acesso do player e observa mudanças de conectividade [S09, S10]. A lição para FeedMine é **usar a desduplicação e o governor já existentes**, não introduzir uma segunda camada genérica de armazenamento.

### 5.8. Smart Bookmarks: descoberta importante de setembro de 2026

Em 03/09/2026, Pocket Casts publicou *Smart Bookmarks*: a anotação pode conter um título sugerido automaticamente e um trecho falado da transcrição, inclusive recuperando alguns instantes anteriores ao toque porque, na vida real, o usuário reage depois da frase de interesse. O texto pode ser editado e ajustado; a função enriquecida depende da transcrição gerada pelo serviço [S19]. Esse detalhe corrige uma simplificação comum: bookmark útil não é apenas `(mediaID, seconds)`, mas um objeto durável que pode receber contexto textual e evolução sem perder a âncora temporal.

### 5.9. Avaliação

**Transferir já:** um owner inequívoco de playback; posição durável; fonte explícita; separar player/surface; capítulos de origem; comandos do iOS. **Transferir depois:** alternância real de fontes com resync, download sob política, smart bookmarks com texto. **Não transferir no MVP:** fingerprinting Rust/UniFFI, heurísticas complexas de drift, IA geradora e backend de transcrições. O objetivo do FeedMine é consumo editorial fluido, não replicar a plataforma Pocket Casts.

## 6. Readwise Reader: vídeo como documento temporal

### 6.1. Interações comprovadas

O Reader aceita links do YouTube e apresenta vídeo junto de transcrição sincronizada. O usuário pode selecionar fragmentos da transcrição para navegar temporalmente, destacar passagens, ajustar o tamanho do player e alternar o autoscroll. A documentação inclui um comando explícito para voltar ao ponto atual depois de explorar outra passagem [S11]. Isso é importante: quem lê a transcrição não deve ser sequestrado pelo avanço do áudio.

Na experiência desktop, são documentados atalhos de play/pause, velocidade, skip temporal, ativação/desativação do autoscroll e retorno ao trecho atual; no mobile, o produto disponibiliza controles equivalentes por menu, com possíveis diferenças de gesto [S11]. A recomendação para FeedMine é preservar **dois estados independentes**: posição do playback e viewport da transcrição. Somente o usuário decide voltar ao acompanhamento automático.

### 6.2. Texto original versus transcrição enriquecida

O Reader documenta transformação das legendas automáticas do YouTube em texto mais legível, com pontuação e parágrafos reparados. Em janeiro de 2025, o produto anunciou aperfeiçoamento automatizado por GPT [S12]. O ganho de leitura tem um custo: destaques produzidos sobre o texto original podem não se sobrepor corretamente à versão enriquecida. A documentação afirma que os destaques originais são mantidos no Notebook mesmo que não apareçam sobre o texto reformatado [S11].

**Consequência para FeedMine:** tratar cada transcrição como uma representação versionada com idioma, proveniência, esquema de cues e versão de texto. Preservar highlights pelo conjunto de identidade da mídia + tempo + trecho/contexto + identidade da versão; offsets de caracteres não podem ser a única chave durável. Reprocessar texto é uma nova representação, não sobrescrever silenciosamente a anterior.

### 6.3. Idiomas

A seleção de idioma no Reader depende de opções publicadas no YouTube. A documentação observa que escolher outro idioma pode criar um novo documento na biblioteca com idioma no título [S11]. Para o FeedMine, proponho o inverso: manter o `OriginRecord`/mídia como identidade única e oferecer **transcrições alternativas por idioma**. Isso evita duplicar cards por alteração do idioma de leitura, sem impedir que diferentes edições editoriais existam quando a origem realmente publica documentos distintos.

### 6.4. API e limites da evidência

A API pública do Reader distingue a categoria `video` de `article`, `rss`, `pdf` etc., e permite salvar/consultar documentos [S13]. Isso comprova uma classificação de conteúdo exposta a integrações, mas não revela tecnologia interna do player, cache de legendas nem extração do YouTube. Não atribuir arquitetura proprietária sem código ou documentação correspondente.

### 6.5. Avaliação

**Transferir:** transcrição como superfície de navegação; scroll automático controlável; retorno ao trecho atual; evidência de idioma/proveniência; tolerância a reformatação. **Não transferir sem necessidade:** duplicação automática de um mesmo vídeo por idioma, transformações de texto para todos os itens e dependência de serviços externos para um card aparecer.

## 7. Snipd: capturar conhecimento durante a escuta

### 7.1. O gesto pelos fones — detalhe técnico verificado

O Snipd publica que o usuário pode criar um snip sem tocar no celular: utiliza o comando de fones normalmente associado a **skip backward**. Em AirPods compatíveis, esse comando costuma corresponder a três pressões; o app o interpreta como captura e toca um sinal de confirmação. O controle é configurável nas preferências [S14]. Não é prova de que o aplicativo receba um evento abstrato chamado “triple tap”; é evidência de uso de comandos de transporte enviados pelos acessórios.

O iOS oferece `MPRemoteCommandCenter` e comandos como `skipBackwardCommand` e `bookmarkCommand` [S20]. É possível oferecer uma opção de “usar voltar como bookmark”, mas a mudança de significado não deve ser imposta silenciosamente, porque usuários esperam que voltar realmente retroceda a reprodução.

### 7.2. Natureza do snip

O snip inclui a âncora temporal e pode receber transcrição, identificação de falante, trecho relevante, resumo e exportação. O centro da experiência é **capturar primeiro, organizar depois**. O gesto interrompe pouco a escuta; a elaboração da anotação é uma etapa posterior [S14]. Isso inspira um recurso de alto valor com custo inicial baixo no FeedMine: bookmark com `mediaID`, timestamp, data e nota opcional; enriquecimentos assíncronos jamais apagam a âncora original.

### 7.3. Conteúdo importado do YouTube e arquivos do usuário

O Snipd oferece importação de vídeos do YouTube para experiência orientada ao áudio e permite carregar arquivos próprios, inclusive vídeo, do qual sua experiência preserva o áudio [S17]. Essas são declarações sobre **o produto Snipd**. Não provam autorização para outro aplicativo extrair o áudio de qualquer vídeo do YouTube. A política do YouTube para API/embeds restringe separar tracks e reproduzir conteúdo em background por players ocultos [S21]. Para FeedMine, embutir oficialmente ou abrir o YouTube são rotas adequadas; não criar um “YouTube MP3” improvisado.

### 7.4. Downloads e operação offline

A documentação descreve três políticas: smart downloads por preferência/hábito, downloads da fila e downloads de episódios novos de podcasts selecionados. O usuário pode limitar quantos arquivos manter, restringir a Wi-Fi e remover conteúdo antigo conforme armazenamento; os episódios baixados permitem escuta e criação de highlights sem rede [S15]. O Snipd também possui app independente para Apple Watch, com fila limitada e downloads locais [S16].

**Aplicação FeedMine:** não confundir “estoque preparado de cards” com “biblioteca de arquivos de áudio baixados”. São budgets diferentes. Download de episódio é ato explícito ou preferência clara de usuário, com limites e revogação verificável. O runway editorial nunca deve adquirir gigabytes de mídia para parecer infinito.

### 7.5. Limites de transparência

Não há, nas fontes verificadas, implementação pública abrangente do pipeline de transcrição, resumo e capítulos do Snipd. Não atribuir o processamento à nuvem, ao telefone, a um modelo específico ou a uma fila interna sem evidência. Para FeedMine, IA deve ser tratada como enriquecimento opcional e claramente identificado, com privacidade, custo e conectividade próprios.

---
# PARTE III — Contratos externos: RSS, YouTube e iOS

## 8. RSS, Atom, HTML e mídia de podcast

### 8.1. Descoberta não é reprodução

Ao ingerir uma entrada, o conector deve registrar **fatos oferecidos pela origem**, e não tomar decisões antecipadas de player. São exemplos: enclosure primário, alternativas, MIME declarado, duração aproximada, imagem, links externos, capítulo remoto, idioma de transcrição e IDs de plataforma. A escolha final de representação pertence às fronteiras de preparação/publicação ou, quando se trata de reprodução explícita, ao resolvedor de playback.

**RSS 2.0:** `enclosure` fornece URL, tipo e tamanho declarados; iTunes Podcast costuma publicar imagem e duração. **Podcasting 2.0:** `podcast:transcript`, `podcast:chapters`, `podcast:alternateEnclosure` e `podcast:source` acrescentam representações e arquivos externos [S22]. **Atom/YouTube:** pode identificar vídeo e metadados sem fornecer arquivo AVPlayer livremente reproduzível. **HTML/Open Graph:** `og:image`, `og:video` e `twitter:player` são pistas de apresentação; não garantem autorização ou compatibilidade de player nativo.

Os campos fornecidos por fontes são **declarações não confiáveis**. MIME pode estar incorreto, URL pode redirecionar, conteúdo pode exigir autorização, `Content-Length` pode faltar, duração pode ser desconhecida e servidores podem bloquear hotlink ou byte-range. A normalização precisa preservar o que é *declarado* e aquilo que foi *verificado*, sem promover automaticamente palpites a fatos.

### 8.2. Exemplo RSS com representações alternativas

```xml
<rss version="2.0"
     xmlns:podcast="https://podcastindex.org/namespace/1.0">
  <channel>
    <title>Exemplo FeedMine</title>
    <item>
      <guid>episode-42</guid>
      <title>Uma conversa sobre ciência</title>
      <enclosure url="https://example.org/ep42.mp3"
                 length="42700123" type="audio/mpeg" />
      <podcast:transcript
          url="https://example.org/ep42.vtt"
          type="text/vtt" language="pt-BR" />
      <podcast:chapters
          url="https://example.org/ep42-chapters.json"
          type="application/json" />
      <podcast:alternateEnclosure type="video/mp4"
          title="Versão em vídeo">
        <podcast:source uri="https://example.org/ep42.mp4" />
      </podcast:alternateEnclosure>
    </item>
  </channel>
</rss>
```

O exemplo é didático. Em produção, validar o XML, respeitar namespace, preservar URLs e não presumir equivalência temporal perfeita entre enclosures. O padrão `alternateEnclosure` admite não só áudio versus vídeo, mas qualidade, codec, largura de banda e múltiplos mecanismos de transporte [S22].

### 8.3. Estratégia de seleção da mídia

Para **card visual**, a seleção usa disponibilidade local, geometria, custo de materialização, tamanho de tela e política editorial. Para **playback**, usa compatibilidade de plataforma, intenção do usuário, custo de rede, arquivo local, preferência de áudio/vídeo e possíveis direitos. Essas seleções não precisam ser idênticas: uma capa JPEG é excelente representação para um episódio que será reproduzido por MP3; um poster local é suficiente para um HLS remoto.

Hierarquia inicial recomendada para vídeo: referência oficial de plataforma → stream remoto suportado por AVFoundation → arquivo progressivo reproduzível → URL externa. A decisão exata muda conforme disponibilidade, licença, conectividade e ação solicitada. Não colocar lógica `if source == YouTube` dentro da `FeedCardView`.

### 8.4. Identidade e integridade

Um `enclosure` muda de URL quando o fornecedor troca CDN; isso **não** significa necessariamente um novo episódio. O `SourceID` também não deve derivar do endpoint operacional. Identidade de mídia e publicação devem preservar a revisão observada e a proveniência, conforme o Blueprint v0.4 [F01]. Um hash de arquivo só existe quando calculado/fornecido; não inventar hash a partir de URL. Para recursos imutáveis locais, usar a versão do asset e referência verificável; para URLs remotas, preservar locator canônico e metadados validados.

## 9. YouTube: delimitação técnica e de políticas

O YouTube distingue API/metadata de reprodução. A IFrame Player API permite embutir e controlar o player dentro das condições oficiais [S23]. Uma URL do YouTube ou uma referência de vídeo no feed **não** autoriza converter esse vídeo em URL de mídia para `AVPlayer` nem separar seu áudio.

As políticas oficiais proíbem, no contexto dos serviços de API, práticas como isolar áudio/vídeo, substituir funções do player, download fora das permissões aplicáveis e player oculto em background [S21]. Os requisitos mínimos também incluem visibilidade, UI do player, atribuição e regras para autoplay [S24]. Essas regras são externas e podem evoluir; revisão jurídica e de conformidade é necessária antes de lançar integrações inovadoras.

**Comportamento FeedMine recomendado:** card com poster/identidade local; gesto explícito abre player oficial via `WKWebView` adequadamente identificado ou abre aplicativo/site do YouTube; a experiência de áudio persistente do FeedMine aplica-se a streams próprios/autorizados, **não** automaticamente a esse embed. Se o vídeo não permite incorporação, mostrar ação externa com erro claro. Não gerar áudio derivado de YouTube por mecanismos de download ou extração não autorizados.

**Observação de UX:** se o usuário fecha a visualização de YouTube, não prometer continuação do som como no player nativo. São contratos diferentes, que devem ser comunicados por interface e capability, não por uma exceção invisível.

## 10. iOS: áudio, vídeo, PiP, downloads e limites reais

### 10.1. AVAudioSession e background

`AVAudioSession` informa a intenção de áudio ao sistema. A categoria `.playback`, somada à capacidade de background apropriada, suporta continuidade de áudio quando compatível, mas exige responder a interrupções, route changes e media services reset [S25]. O owner deve tratar saída de fones, ligação, Siri e mudança Bluetooth, além de diferenciar pausa voluntária de suspensão externa.

### 10.2. MPNowPlayingInfoCenter e MPRemoteCommandCenter

Metadados da mídia atual, artwork, duração e posição alimentam lock screen, Control Center e acessórios. `MPRemoteCommandCenter` contém comandos de play/pause, skip, seek, mudança de posição e bookmark [S20]. A implementação deve registrar handlers uma vez no owner de reprodução, não em cada card. Handler de UI nunca deve bloquear aguardando rede ou SQLite síncrono; a ação remota confirma rapidamente e entrega a intenção ao coordenador.

### 10.3. Picture in Picture

PiP é uma capability de mídia nativa suportada em combinações apropriadas de player, conteúdo e dispositivo. Não é sinônimo de “player flutuante dentro do app”, que pode ser apenas uma view reposicionável. YouTube embed deve obedecer às próprias condições; não inferir suporte universal nem forçar PiP por artifícios.

### 10.4. Background URLSession e downloads de HLS

O sistema oferece `URLSessionConfiguration.background` para transferências de arquivos e `AVAssetDownloadURLSession` para assets HLS apropriados [S26, S27]. Downloads podem continuar fora do processo, mas o SO gerencia início, retomada e budget. **Não há garantia de manter o motor completo do feed processando indefinidamente em background**. O FeedMine deve reencontrar trabalho durável, movimentar o arquivo concluído para storage gerenciado e reconstruir o contexto na volta ao foreground.

### 10.5. Energia, thermal state e dados móveis

O governor já proposto no V2 é o dono adequado de decisões transversais de pressão de recursos [F02]. Recomendação: poster/thumbnail tem custo pequeno e valor alto para runway; transcrição publicada em texto tem custo médio; stream de mídia apenas após Play; download offline apenas por preferência; fingerprinting e transcrição por IA são custos altos. Em rede celular ou Low Data Mode, permitir playback explícito, mas não iniciar download preditivo pesado sem política clara.

---

# PARTE IV — Projeto de UX/UI para FeedMine

## 11. Objetos visuais e estados de interação

### 11.1. Card de episódio

**Estado pronto para apresentação:** thumbnail/poster local ou placeholder determinístico; título; origem; duração, quando confiável; tipo “Podcast”, “Vídeo” ou “YouTube”; ação Play adequada. A view não abre URL na inicialização, não mede duração por request remoto e não cria `AVPlayerItem` apenas por aparecer no `LazyVStack`. Uma capa ausente não impede o card de existir.

**Estado em playback:** card pode indicar “Em reprodução” e “Retomar”; essa informação é consultada por identidade na sessão de playback, não armazenada como mutação editorial do `PublishedCardPayload`. O feed publicado mantém o mesmo conteúdo e a mesma ordem.

**Estado após consumo:** registrar posição e bookmark fora da história imutável. A leitura progressiva não exige incrementar contadores ou reiniciar media preparation a cada repaint.

### 11.2. Detalhe multimídia

A tela de detalhe pode alternar: descrição da origem, capítulos, transcrição publicada, notas/bookmarks, recursos alternativos. A navegação por transcrição entrega `seek(to:)` ao owner. Se não há texto temporal, mostrar “Transcrição indisponível”, não um spinner indefinido. Se mídia está offline e texto local existe, a transcrição continua legível.

### 11.3. Mini-player

**Regra central:** mini-player é uma superfície da sessão ativa, não o lugar onde a sessão nasce. O comportamento esperado para mídia nativa: scroll do feed, troca de filtro, abertura de outro artigo e publicação de novos segmentos não interrompem áudio; trocar entre tela cheia e mini-player também não recria player. Para vídeo, a apresentação pode ser reposicionada quando apropriado; ocultação visual e modo somente áudio são decisões distintas. Um embed YouTube não deve ganhar o contrato de áudio background por associação visual.

Evitar salto no scroll ao mostrar/ocultar player: reservar área de interface de forma estável quando possível ou ajustar geometria preservando âncora por `PublicationCardID` e offset. Não usar mudança de identidade do `LazyVStack` para animar player; não recolocar a view do stream dentro de um card que será reciclado.

### 11.4. Controles e acessibilidade

Ações prioritárias: play/pause, expandir, avançar/voltar, velocidade para áudio nativo, salvar trecho, capítulos, transcrição e sair. Todos os controles exigem labels VoiceOver, estado acessível e área de toque adequada. Se houver autoplay de UI, ele deve ser **não sonoro** e somente de poster/preview autorizado, sem custo de rede ou reprodução inesperada. Transcrição pode substituir necessidade de escuta para alguns usuários; tolerar texto grande e Dynamic Type.

### 11.5. Transcrição como segunda navegação

Adotar o padrão do Reader: rolagem automática opcional; tocar trecho faz seek; rolar manualmente desativa temporariamente acompanhamento; botão “Voltar ao momento atual” retorna sem perder a seleção; alternância de idioma não cria duplicata editorial. Destacar cue com evidência temporal; se mídia e texto perderam sincronização, permitir desativar highlight até realinhamento.

## 12. Matriz de estados e mensagens

| Estado observável | Mensagem/ação preferida | Nunca fazer |
|---|---|---|
| Card sem poster | Placeholder estável; mostrar texto | Buscar thumbnail em `body` da view |
| Stream carrega após Play | Player mostra buffering e cancelamento | Bloquear todo o feed |
| URL expirada/403 | “Não foi possível reproduzir”; abrir origem | Marcar feed como sem conteúdo |
| Sem rede, áudio não baixado | “Precisa de conexão para ouvir” | Remover card ou apagar bookmark |
| Sem rede, arquivo local | Tocar arquivo; progresso local | Forçar revalidação remota |
| Transcrição não publicada | Ocultar ação ou informar ausência | Esperar geração de IA antes de publicar |
| YouTube não incorporável | Abrir no YouTube/navegador | Extrair arquivo de mídia alternativo |
| Alternância de fonte falha | Permanecer na fonte atual; manter posição | Criar segundo player simultâneo |
| App retorna de background | Reconciliar áudio e metadados reais | Assumir que timers continuaram rodando |
| Filtro muda durante playback | Preservar mídia e UI de player | Derrubar session porque card desapareceu |

## 13. Runway editorial versus demanda de reprodução

São duas curvas de demanda distintas. O **runway editorial** antecipa quantos pontos de apresentação prontos são necessários para suportar scroll sob latência variável de aquisição e seleção. A **demanda de playback** nasce quando o usuário escolhe ouvir/assistir e pode consumir muito mais rede, energia e disco. Misturá-las implicaria baixar arquivos pesados simplesmente porque o card está a quinze telas de distância.

O backlog de preparação de posters deve responder a consumo visual, viewport, custo de decodificação e disponibilidade local. O backlog de downloads de episódios deve responder a pedidos explícitos, filas de escuta ou uma preferência de download automático separada e consentida. O primeiro não pode ser artificialmente limitado a “20 cards”; o segundo não pode usar “o feed precisa de 200 cards” como desculpa para 200 downloads de vídeos.

**Exemplo de orçamento adaptativo (proposta, não especificação existente):**

```text
preparedVisualRunwayPoints =
    alreadyPreparedVisualPointsAhead

requiredVisualRunwayPoints =
    max(
        viewportSafetyFloorPoints,
        observedScrollVelocityP95PointsPerSecond
          * observedPreparationLatencyP95Seconds
          * safetyFactor
    )

visualDeficitPoints =
    max(0, requiredVisualRunwayPoints
          - preparedVisualRunwayPoints)
```

Os limites de memória, pressão térmica, conectividade e prioridades da sessão devem restringir a execução; a fórmula não é convite a aumentar throughput a qualquer custo. Playback não substitui o runway, e transcrição não deve concorrer indiscriminadamente com posters para a mesma fila de trabalho urgente.

---

# PARTE V — Integração específica ao Blueprint v0.4 / Runtime V2

## 14. Invariantes que a implementação não pode violar

Os documentos do FeedMine estabelecem uma sequência explícita `Connectors → AcquisitionBatch → transactional admission → Canonical Supply → Selection → MediaPreparation → Publication → FeedSession → FeedPresentationSnapshot → SwiftUI` [F01, F02]. `MediaCandidate[]` nasce na revisão canônica; `MediaPreparation` decide suitability/asset version; a publicação congela media identity/render contract. O renderer só usa recursos locais e nunca inicia network; **playback explicitamente pedido pelo usuário pode usar network segundo policy** [F01].

É importante reproduzir o significado exato desses limites:

1. **MediaCandidate não é `URL?`**: carrega papel, classe, MIME, dimensões, duração, locator e alternativas; dados de protocolos são traduzidos na borda.
2. **PublishedMediaSet não é uma fila de downloads**: pode escolher uma representação visual primária e alternates. Não obriga baixar áudio/vídeo integral antes da publicação.
3. **Publicado é imutável**: atualizar CDN, transcrição ou estado de playback não muta segmento antigo nem reordena cards expostos.
4. **User data é durável**: bookmarks/progresso são transações em storage apropriado; sua vida útil não acompanha cache reconstruível.
5. **UI não conhece protocolo**: `isYouTube`, `podcast:chapters` e detalhes RSS pertencem ao conector/resolvedor de ação, não ao renderer de cards.
6. **Um só owner**: reutilizar ou estender o player existente se houver; não introduzir uma segunda engine de playback sem defeito de propriedade claramente demonstrado.

### 14.1. Fluxo recomendado para ação Play

```text
FeedCardView (somente RenderContract + action)
    │ usuário toca Play
    ▼
FeedScreenStore entrega intenção semântica
    ▼
ActionExecutor / PlaybackIntentResolver
    │ resolve PublishedMediaID -> identidade + fontes permitidas
    │ aplica permissões, offline, preferência e políticas
    ▼
PlaybackCenter (único owner)
    ├─ arquivo/MP3/MP4/HLS autorizado -> AVPlayer
    ├─ YouTube -> player/embed oficial visível ou handoff externo
    └─ indisponível -> erro recuperável + opção abrir origem
    │
    ├─ progresso/bookmarks -> store durável local
    ├─ MPNowPlayingInfoCenter / MPRemoteCommandCenter
    └─ PlaybackPresentation -> mini-player / detalhe
```

O caminho de playback **não** chama `Selection`, não provoca nova edição, não escolhe uma nova origem editorial e não transforma `FeedSession` em player. Um poster preparado continua válido mesmo que a URL do stream falhe.

## 15. Identidades e contratos de persistência

Separar obrigatoriamente:

| Identidade | Uso | Duração |
|---|---|---|
| `OriginRecordID` | Conteúdo canônico entre observações | Durável conforme fatos |
| `OriginRevisionID` | Versão exata observada | Imutável/referenciada |
| `PublicationCardID` | Identidade do card na edição | Imutável e adequada à âncora de UI |
| `PublishedMediaID` | Mídia escolhida e versionada para publicação | Imutável como referência publicada |
| `PlaybackMediaKey` (proposto) | Retomar a mesma mídia através de cards/contextos | Durável independente da visualização |
| `TranscriptRepresentationID` (proposto) | Versão, idioma e proveniência de cues | Durável enquanto citada por usuário |
| `BookmarkID` (proposto) | Anotação pessoal temporal | Durável, mesmo após evicção |

O documento não impõe novos tipos se equivalentes já existem no V2. Nomes acima são **contratos conceituais de integração**. A entidade de playback deve permitir mapear várias publicações de um mesmo episódio para um progresso compartilhado **apenas quando** a identidade canônica prova equivalência. Dois reuploads diferentes não devem compartilhar tempo por coincidência de título.

## 16. Dados duráveis versus dados reconstruíveis

**Duráveis:** progressos de escuta, conclusão manual, bookmarks, notas e preferências de download. **Reconstruíveis:** thumbnails, posters, metadados temporários de buffer, dados de media analysis não anotados, transcrições obtidas novamente sob licenças apropriadas. **Versionados/referenciados:** representações de transcrição sobre as quais há highlights; não remover sem migração ou retenção das âncoras textuais.

A persistência deve usar a autoridade SQLite já estabelecida pelo runtime. Actors coordenam execução efêmera, não se tornam outra verdade de dados duráveis [F01, F02]. Para crash safety, registrar progresso ao pausar, trocar de episódio, entrar em background e checkpoints de reprodução definidos pelo próprio owner. Não persistir cada frame nem vincular escrita ao scroll.

## 17. Novas responsabilidades mínimas — sem reescrever o runtime

**Conector:** extrai enclosures, alternate enclosures, capítulos e transcrições; identifica YouTube e publica capacidades semânticas. **MediaPreparation:** prepara thumbnail/poster e geometria; não inicia media stream. **Publication:** congela `PublishedMediaSet`, action e render contract. **Action resolver:** mapeia ação Play para descriptor permitido, verifica availability, rights e fallback. **Playback owner:** mantém sessão única, progresso, interrupções e comandos remotos. **Presentation:** mostra mini-player a partir de estado do playback sem alterar conteúdo editorial.

Essa delimitação não exige nova geração de cache, outro `RunwayController` nem timer arbitrário. Se o runtime já contém objetos equivalentes, centralizar neles. Qualquer implementação que crie `AVPlayer` dentro de uma `FeedCardView` ou faça `HEAD` no remote media durante body é incompatível com a arquitetura-alvo.

---
# PARTE VI — Referências de implementação Swift 6 / iOS

## 18. Convenções para os trechos de código

Os exemplos seguintes são **propostas de desenho FeedMine (E4)**, não transcrições de código de Inoreader/Readwise/Snipd. Os arquivos do Pocket Casts identificados na bibliografia são **código real (E1)**. Os snippets aqui são deliberadamente pequenos, para orientar integração em owners existentes; **não foram compilados nem validados com testes iOS neste ambiente**. Ajustes de deployment target, assinaturas concretas dos stores, isolamento Swift 6, permissões e execução Xcode são obrigatórios.

## 19. Contrato canônico para fontes de mídia

```swift
import Foundation

// O conector traduz protocolos; o domínio não conhece RSS ou YouTube.
enum MediaClass: String, Codable, Sendable {
    case image, audio, video, platformVideo, transcript
}

enum MediaRole: String, Codable, Sendable {
    case artwork, poster, playable, alternate, transcript, chapters
}

enum MediaLocator: Codable, Sendable, Hashable {
    case remoteURL(URL)
    case platformVideo(provider: String, externalID: String)
    case localAsset(key: String)
}

struct MediaCandidate: Codable, Sendable {
    let candidateID: String
    let role: MediaRole
    let mediaClass: MediaClass
    let mimeType: String?        // declarado ou verificado em campo distinto
    let durationSeconds: Double?
    let locator: MediaLocator
    let languageTag: String?
    let sourceEvidence: String   // caminho/atributo de proveniência
}
```

**Regra:** adicionar `MediaCandidate` ao `OriginRevision` sem exportar `remoteURL` ao renderer. O card usa media published local / placeholder; o descriptor remoto só é resolvido após a ação Play. Em produção, diferenciar `mimeDeclared` de `mimeVerified` e preservar identidade/versão exata de cada origem. O snippet simplifica detalhes de esquema e não substitui o contrato aprovado do Blueprint.

## 20. Descriptor de playback e fallback explícito

```swift
import Foundation

enum NativeMediaSource: Sendable, Hashable {
    case localFile(URL)
    case progressiveAudio(URL)
    case progressiveVideo(URL)
    case hls(URL)
}

enum PlaybackTarget: Sendable, Hashable {
    case native(primary: NativeMediaSource,
                audioAlternate: NativeMediaSource?)
    case youtube(videoID: String)
    case externalURL(URL)
}

struct MediaPlaybackDescriptor: Sendable {
    let playbackMediaKey: String
    let originRevisionID: String
    let publishedMediaID: String
    let title: String
    let target: PlaybackTarget
    let expectedDurationSeconds: Double?
}

struct PlaybackCheckpoint: Sendable {
    let playbackMediaKey: String
    let seconds: Double
    let updatedAt: Date
    let completed: Bool
}
```

**Fonte alterna não implica timeline idêntica.** Uma troca `MP3 ↔ MP4` só pode reaproveitar segundos diretamente quando os arquivos representam cronologias equivalentes ou quando existe um mapa de tempos válido. Caso contrário, pedir confirmação ou reiniciar de ponto seguro é melhor que avançar para a cena errada.

## 21. Owner único de AVPlayer — esqueleto de integração

```swift
import AVFoundation
import Observation

protocol PlaybackProgressWriting: Sendable {
    func save(mediaKey: String, seconds: Double) async throws
    func load(mediaKey: String) async throws -> Double?
}

@MainActor
@Observable
final class NativePlaybackCenter {
    private(set) var mediaKey: String?
    private(set) var player: AVPlayer?
    private(set) var isPlaying = false

    private let progress: any PlaybackProgressWriting

    init(progress: any PlaybackProgressWriting) {
        self.progress = progress
    }

    func play(
        mediaKey: String,
        sourceURL: URL,
        autoplay: Bool = true
    ) async throws {
        let previous = player
        let oldKey = self.mediaKey
        let oldSeconds = currentSeconds()
        previous?.pause()

        if let oldKey {
            try await progress.save(mediaKey: oldKey,
                                    seconds: oldSeconds)
        }

        // Retomar por identidade de mídia, não por posição do card.
        let resume = try await progress.load(mediaKey: mediaKey) ?? 0
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .default)
        try audio.setActive(true)

        let next = AVPlayer(url: sourceURL)
        self.player = next
        self.mediaKey = mediaKey
        self.isPlaying = false

        let target = CMTime(seconds: max(0, resume),
                            preferredTimescale: 600)
        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in
            next.seek(to: target, toleranceBefore: .zero,
                      toleranceAfter: .zero) { _ in
                continuation.resume()
            }
        }
        // Proteção contra conclusão de seek de player substituído.
        guard player === next else { return }
        if autoplay {
            next.play()
            isPlaying = true
        }
    }

    func pause() async throws {
        player?.pause()
        isPlaying = false
        if let mediaKey {
            try await progress.save(mediaKey: mediaKey,
                                    seconds: currentSeconds())
        }
    }

    func currentSeconds() -> Double {
        let value = player?.currentTime().seconds ?? 0
        return value.isFinite ? max(0, value) : 0
    }
}
```

**O que falta para produção:** nenhum snippet assim é um player completo. Implementar observação do estado de `AVPlayerItem`, buffer/erro, interrupções do `AVAudioSession`, mudanças de rota, remote commands, background/foreground, seek coalescing, atualização de Now Playing, volume/velocidade, cancellation, controle de concorrência para `play(A)` e `play(B)`, progress checkpoints e estratégia de conclusão. Antes de aprovar esse desenho, verificar o player que já existe no FeedMine: a orientação é estender o owner, não criar uma duplicata.

**Nota de concorrência:** o exemplo usa `@MainActor` para tornar a manipulação de `AVPlayer` e estado observável consistente com SwiftUI. Storage é assíncrono; o `MainActor` não deve realizar decodificação ou I/O bloqueante. Requisições simultâneas precisam de política de substituição por identidade da ação, não simplesmente um contador de gerações adicional em cada camada.

## 22. Protocolo de troca áudio/vídeo com preservação de contexto

```text
1. Receber intenção explícita “Ouvir apenas áudio” ou “Voltar ao vídeo”.
2. Verificar se a mídia oferece as duas representações legalmente utilizáveis.
3. Capturar posição exata, playing/paused, velocidade e identidade da mídia.
4. Resolver a nova fonte: preferir arquivo local quando solicitado e válido.
5. Aplicar mapeamento de timeline, quando necessário.
6. Abrir nova fonte e buscar posição; manter UI em estado transitório claro.
7. Confirmar sucesso antes de descartar a fonte antiga, se orçamento permitir.
8. Se falhar, retornar à fonte anterior e preservar posição.
9. Persistir a escolha do usuário apenas no escopo pertinente.
```

Não usar esse fluxo para YouTube: reprodução embutida tem outro contrato, imposto pelo provedor. Para HLS sem enclosure de áudio, “Ocultar vídeo” não deve ser rotulado como “Economizar dados” a menos que exista seleção de rendition realmente somente áudio confirmada.

## 23. Integração UIKit/SwiftUI: superfície, não owner

```swift
import SwiftUI
import AVFoundation

struct InlineNativeVideoSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerHost {
        let view = PlayerLayerHost()
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: PlayerLayerHost,
                      context: Context) {
        // Não chama play(), seek() nem faz rede.
        view.playerLayer.player = player
    }
}

final class PlayerLayerHost: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }
    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}
```

A superfície recebe uma referência estável do owner. A view pode ser retirada/reatribuída conforme navegação; a lógica de desmontagem não pausa automaticamente o player. O layout deve preservar proporção e continuidade de identidade visual. Para PiP, avaliar o caminho oficial `AVPlayerViewController`/`AVPictureInPictureController` de acordo com o tipo de mídia, requisitos do deployment target e comportamento do player; não simular PiP usando uma view fora do app.

## 24. Transcrição temporal canônica

```swift
import Foundation

struct TimedCue: Codable, Sendable {
    let startSeconds: Double
    let endSeconds: Double
    let text: String
    let speaker: String?
}

struct TranscriptRepresentation: Codable, Sendable {
    let representationID: String
    let playbackMediaKey: String
    let languageTag: String?
    let sourceRevision: String
    let cues: [TimedCue]
}

func cueIndex(at time: Double, in cues: [TimedCue]) -> Int? {
    var low = 0
    var high = cues.count
    while low < high {
        let mid = (low + high) / 2
        if cues[mid].endSeconds < time {
            low = mid + 1
        } else {
            high = mid
        }
    }
    guard low < cues.count,
          cues[low].startSeconds <= time,
          time <= cues[low].endSeconds else { return nil }
    return low
}
```

A busca é adequada quando os cues estão ordenados e os intervalos são razoavelmente não sobrepostos; validar isso ao importar. Não colocar parse VTT, HTML e XML dentro da tela de transcrição. O importador cria o modelo canônico; a tela consulta a posição do owner.

**Dois cursores separados:** `(playbackSeconds)` é propriedade do player; `(visibleCue/readingOffset)` é propriedade da tela de transcrição. Se o usuário rola manualmente, suspender autoscroll, sem interromper reprodução. O botão “Voltar ao momento atual” reinicia acompanhamento.

## 25. Bookmark temporal durável

```swift
import Foundation

struct PlaybackBookmark: Codable, Sendable, Identifiable {
    let id: UUID
    let playbackMediaKey: String
    let createdAt: Date
    let positionSeconds: Double
    let transcriptRepresentationID: String?
    let capturedText: String?
    let note: String?
}
```

O timestamp é a âncora mínima. `capturedText` e `transcriptRepresentationID` são opcionais porque um usuário deve poder marcar uma ideia mesmo sem transcrição. Enriquecimentos futuros podem produzir **revisão de nota** ou sugestão, mas não alterar silenciosamente o ponto original. Se a mídia tem inserções dinâmicas, capturar contexto próximo e sinalizar que a navegação pode ser aproximada.

A lição do Snipd/Pocket Casts é capturar alguns segundos **anteriores** à ação, se há transcrição confiável e o usuário consentiu: a frase marcante geralmente terminou quando o botão foi acionado. Não inferir palavra exata por uma janela fixa aplicada a qualquer podcast; preferir limites de cue/contexto.

## 26. Comandos remotos do iOS: integração mínima

```swift
import MediaPlayer

@MainActor
final class RemoteCommandBridge {
    private let center = MPRemoteCommandCenter.shared()

    func install(onPlay: @escaping () -> Void,
                 onPause: @escaping () -> Void) {
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true

        center.playCommand.addTarget { _ in
            Task { @MainActor in onPlay() }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in onPause() }
            return .success
        }
    }
}
```

Este é **apenas um exemplo didático**: produção exige remover/reutilizar registrations em vez de acumulá-las, publicar Now Playing, tratar bookmarks/seek e retornar status fiel. Registrá-los em múltiplas views duplicaria comandos. Avaliar `bookmarkCommand` como preferência, mantendo `skipBackward` com semântica habitual por padrão [S20].

## 27. YouTube em WKWebView: fronteira de integração

```swift
import WebKit

// Exemplo de geração da URL oficial. Não baixa nem extrai mídia.
func youtubeEmbedURL(videoID: String) -> URL? {
    guard videoID.range(of: "^[A-Za-z0-9_-]{11}$",
                        options: .regularExpression) != nil else {
        return nil
    }
    return URL(string:
        "https://www.youtube.com/embed/\(videoID)?playsinline=1")
}
```

Na integração real, consultar a IFrame Player API e requisitos atuais de identificação de cliente, origem/referrer, interface visível e autorização de autoplay. O uso de `WKWebView` com URL oficial não elimina requisitos de política. Essa função **não** representa acesso direto a arquivo audiovisual e não deve ser passada a `AVPlayer` [S21, S23, S24].

## 28. Validação de URL e mídia remota

A verificação de um descriptor deve rejeitar esquemas inesperados, URLs malformadas, tipos não suportados e políticas de origem incompatíveis. Redirecionamentos podem cruzar hosts, expirar ou depender de tokens; essas mudanças devem ser geridas pelo resolvedor de playback. Evitar `HEAD` universal: alguns servidores de mídia não o implementam ou retornam metadados enganosos. `AVURLAsset` / `AVPlayerItem` devem tratar erros de carregamento de maneira assíncrona, com timeout e saída clara. Não disparar verificação “só para confirmar” de todos os cards durante scroll.

---

# PARTE VII — Plano de implementação e testes

## 29. Sequência de entrega mínima e cumulativa

### Fase 0 — Inventário do código existente

**Entregáveis:** mapa de owners atuais para media preparation, player, asset storage, interação e persistência; contratos existentes de `PublishedMediaRef`, `InteractionOffer` e `FeedPrimaryAction`; lacunas por formato/protocolo. **Condição:** nenhum novo coordinator/cache/timer antes de comprovar que o owner atual não atende. Avaliar regressões conhecidas de scroll, publicação e reabertura antes de introduzir mídia.

### Fase 1 — MVP multimídia sem acoplamento

**Entregáveis:** normalização de `enclosure`/poster/identidade YouTube; card com poster local ou placeholder e ação Play; player nativo único para MP3/MP4/HLS autorizado; resolução oficial do YouTube sob demanda; persistência de progresso local; UI que sobrevive a filtro/scroll; erro de mídia que não vira “fim do feed”. **Não objetivos:** baixar vídeos de rotina, transcrição por IA, fingerprinting, vídeo autoplay em cada card.

### Fase 2 — Experiência de escuta completa

**Entregáveis:** mini-player persistente, velocidade, salto/seek, capítulos fornecidos pela origem, lock screen, remote controls, interrupções, AirPlay/PiP nativo quando apropriado e opção de download explícita. **Critério:** trocar contexto, sair/voltar e bloquear telefone não perde posição ou causa múltiplas reproduções simultâneas.

### Fase 3 — Navegação por conteúdo temporal

**Entregáveis:** parsers VTT/SRT/Podcast Index e representação canônica de cues; transcrição com seek por linha e autoscroll controlável; seleção de idioma; bookmarks pessoais duráveis; busca local em texto já materializado. **Critério:** funciona offline para arquivos/transcrições locais e degrada graciosamente sem dados.

### Fase 4 — Alternativas, downloads inteligentes e enriquecimento

**Entregáveis:** fonte áudio/vídeo alternável com mapeamento temporal seguro; download da fila sob orçamento/consentimento; capítulo ou nota enriquecida opcional; análise de drift se surgirem casos reais; políticas granulares de privacidade e armazenamento. **Portão:** somente após medir benefício de produto e custos do telefone/dispositivo.

## 30. Cenários de teste de aceitação — invariantes de produto

| ID | Caso | Critério de aprovação |
|---|---|---|
| M-01 | 500 cards, 20 mídias heterogêneas | `rendererNetworkRequests == 0`; rolagem fluida; sem streaming automático |
| M-02 | Play em episódio, scroll longe do card | Reprodução continua com 1 player e mesma posição |
| M-03 | Play, troca de filtro, volta | Sem recomeçar o episódio, sem mexer no segmento publicado |
| M-04 | Publicação adiciona cards durante reprodução | Sem salto visual ou interrupção de áudio |
| M-05 | App reabre offline após playback anterior | Progresso e bookmarks disponíveis; só mídia local é tocada |
| M-06 | YouTube embed não permitido | Fallback externo claro, sem extração de áudio |
| M-07 | Vídeo HLS com audio enclosure | Troca de fonte somente se suportada, sem tempo arbitrário |
| M-08 | HLS sem áudio alternativo | Ocultar renderização não promete redução de banda |
| M-09 | Áudio + transcrição VTT baixados | Navegação e destaques simples funcionam offline |
| M-10 | Transcrição com anúncio dinâmico | Não destacar frase errada quando drift detectado/indeterminado |
| M-11 | Texto da transcrição é enriquecido | Bookmarks antigos continuam duráveis por identidade/tempo |
| M-12 | Vários Play em sequência rápida | Apenas a última sessão autorizada toca; não há áudio simultâneo |
| M-13 | Fones desconectados e ligação entra | Sem tocar em alto-falante inesperadamente; estado recuperável |
| M-14 | App volta do background | Now Playing e posição refletem estado real, não timer presumido |
| M-15 | Imagem local evictada | Card continua com placeholder e geometria determinística |
| M-16 | URLs remotas expiram | Falha do playback não vira feed starvation |
| M-17 | Download cancelado em dados móveis | Não corrompe mídia válida, posição nem histórico publicado |
| M-18 | Muitas fontes RSS com MIME errado | Normalização tolera erro sem travar admission/publication |

**Oráculo de teste:** resultados relevantes são comportamento visível e invariantes, não somente microbenchmarks. Um teste verde de `play()` que não detecta interrupção após mudança de filtro não prova a experiência correta. Medir controle do usuário, runway, identidade, scroll, ausência de rede em rendering e persistência após término inesperado [F03].

## 31. Métricas e observabilidade

Métricas recomendadas por sessão, agregadas localmente quando possível, sem tracking individual sensível: latência Play→áudio, falhas por classe de fonte, quantidade de players ativos, time-to-first-frame de vídeo nativo, falhas de seek, rebuffers, posição persistida, memória de posters, bytes por rede e bloqueios do MainActor. Separar métricas de scroll/publicação das de reprodução; playback não deve degradar meta de runway. Perfis Instruments em dispositivo real são mais importantes que extrapolar somente do simulador.

Os budgets numéricos da v0.4, por exemplo **network initiated by renderer = 0**, **blocking disk I/O in View body = 0** e **post-publication editorial mutation = 0**, continuam invariantes explícitas [F01]. Os novos indicadores de mídia não devem relativizá-las.

## 32. Decisões pendentes que precisam de produto, não de palpite técnico

1. O feed mostrará botão Play sempre, inclusive com metadados incompletos, ou só quando a fonte for confirmada como reproduzível?
2. A fila de áudio será uma lista manual e independente ou um fluxo derivado de uma coleção de usuário? Evitar fila implícita baseada em cards visíveis.
3. “Esconder vídeo” significa ocultar superfície ou efetivamente trocar fonte, e como isso será comunicado quando só há HLS?
4. Quais arquivos podem ser baixados por padrão? Qual consentimento se aplica em dados móveis, rotação de storage e fontes protegidas?
5. Em YouTube, quando usar embed versus handoff para aplicativo externo? Qual fluxo de consentimento de privacidade/cookies?
6. Bookmarks devem guardar notas privadas apenas no device ou participar de exportações portáteis? O requisito de portabilidade pessoal é importante para o FeedMine.
7. Quais formatos de transcrição terão suporte inicial: VTT e SRT são candidatos fortes; HTML puro não oferece seek por cue.
8. Qual comportamento de prioridade adotar quando áudio está ativo e o runtime precisa preencher o runway após filtro rápido?

Esses pontos são perguntas de decisão para uma futura spec, **não** justificativa para bloquear o MVP. As invariantes de arquitetura já permitem construir um baseline sem resolvê-los todos.

## 33. Recomendação final

A comparação sugere um núcleo simples: **feed de leitura é local; player nativo é contínuo; YouTube é uma integração regulada; transcrição é conteúdo versionado; bookmark é dado pessoal durável**. São cinco contratos diferentes e complementares.

O Pocket Casts oferece o melhor material para implementação. O Inoreader mostra a integração editorial desejável. O Reader revela como navegar sobre tempo e texto sem perder a liberdade de leitura. O Snipd ensina a marcar momentos sem exigir uma interrupção. A diferença entre produto maduro e demonstração impressionante não está na quantidade de recursos, mas em continuidade, degradação previsível e ausência de regressão quando o usuário muda de contexto.

A maior recomendação é **não transportar para FeedMine a complexidade desses produtos inteiros**. Fazer primeiro o mínimo necessário para sustentar a experiência: artefato visual local, botão de reprodução explícito, sessão independente e progresso durável. Depois adicionar riqueza ao item temporal sem comprometer a história publicada.

---

# PARTE VIII — Referências, rastreabilidade e lacunas

## 34. Bibliografia externa (URLs verificáveis)

**Inoreader**

- **[S01]** Inoreader. *Podcast and YouTube video updates* (01/09/2025). https://www.inoreader.com/blog/2025/09/podcast-and-youtube-video-updates.html

**Pocket Casts — produto e código**

- **[S02]** Automattic. *Pocket Casts iOS — public repository*. https://github.com/Automattic/pocket-casts-ios ; revisão usada no exame de código: `c234167db1c380972d97823ceaafcf2b01bb595e`.
- **[S03]** Pocket Casts Blog. *Read along as you listen: Highlighted Transcripts are here!* (24/06/2026). https://blog.pocketcasts.com/2026/06/24/highlighted-transcripts/
- **[S04]** Pocket Casts Support. *Episode Transcripts* (restrições para sync, internet, proveniência e planos). https://support.pocketcasts.com/knowledge-base/episode-transcripts/
- **[S05]** Automattic. *PlaybackManager.swift*. https://github.com/Automattic/pocket-casts-ios/blob/trunk/podcasts/PlaybackManager.swift
- **[S06]** Automattic. *VideoPlayerView.swift / FloatingVideoView.swift*. https://github.com/Automattic/pocket-casts-ios/blob/trunk/podcasts/VideoPlayerView.swift ; https://github.com/Automattic/pocket-casts-ios/blob/trunk/podcasts/FloatingVideoView.swift
- **[S07]** Automattic. *docs/transcripts.md — Synced Transcript Highlighting*. https://github.com/Automattic/pocket-casts-ios/blob/trunk/docs/transcripts.md
- **[S08]** Automattic. *PR #5336 — Stream the audio enclosure when video is turned off* (aberta na data de corte). https://github.com/Automattic/pocket-casts-ios/pull/5336
- **[S09]** Automattic. *TranscriptModel.swift / TranscriptsDataRetriever.swift / TranscriptManager.swift*. https://github.com/Automattic/pocket-casts-ios/blob/trunk/podcasts/TranscriptModel.swift ; https://github.com/Automattic/pocket-casts-ios/blob/trunk/podcasts/TranscriptsDataRetriever.swift ; https://github.com/Automattic/pocket-casts-ios/blob/trunk/podcasts/TranscriptManager.swift
- **[S10]** Automattic. *PodcastChapterParser.swift / NowPlayingHelper.swift / StreamingCellularTracker.swift*. https://github.com/Automattic/pocket-casts-ios/blob/trunk/podcasts/PodcastChapterParser.swift ; https://github.com/Automattic/pocket-casts-ios/blob/trunk/podcasts/NowPlayingHelper.swift ; https://github.com/Automattic/pocket-casts-ios/blob/trunk/podcasts/StreamingCellularTracker.swift
- **[S18]** Pocket Casts Blog. *AI Generated Chapters Are Here* (07/07/2026). https://blog.pocketcasts.com/2026/07/07/ai-generated-chapters-are-here/
- **[S19]** Pocket Casts Blog. *Smart Bookmarks: save the words, not the timestamp* (03/09/2026). https://blog.pocketcasts.com/2026/09/03/smart-bookmarks/

**Readwise Reader**

- **[S11]** Readwise. *YouTube Videos — FAQ*. https://docs.readwise.io/reader/docs/faqs/videos
- **[S12]** Readwise. *Reader Public Beta Update #11 — YouTube v2* (jan/2025). https://blog.readwise.io/update-jan2025/
- **[S13]** Readwise. *Reader Public API*. https://readwise.io/reader_api

**Snipd**

- **[S14]** Snipd Help Center. *Create Snips with Your Headphones*. https://support.snipd.com/en/articles/10225450-create-snips-with-your-headphones
- **[S15]** Snipd Help Center. *Auto Downloads*. https://support.snipd.com/en/articles/10226016-auto-downloads
- **[S16]** Snipd Help Center. *How to Use Snipd on Apple Watch*. https://support.snipd.com/en/articles/10225462-how-to-use-snipd-on-apple-watch
- **[S17]** Snipd Help Center. *Upload Your Own Audio Files / Features & How-To Guides*. https://support.snipd.com/en/articles/10226381-upload-your-own-audio-files ; https://support.snipd.com/en/collections/11062826-features-how-to-guides

**Normas, políticas, Apple**

- **[S20]** Apple. *MPRemoteCommandCenter; bookmarkCommand*. https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter ; https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter/bookmarkcommand
- **[S21]** YouTube. *Developer policies guide* (restrições de extração/background). https://developers.google.com/youtube/terms/developer-policies-guide
- **[S22]** Podcast Index. *Podcasting 2.0 namespace; example.xml*. https://podcastindex.org/namespace/1.0 ; https://github.com/Podcastindex-org/podcast-namespace/blob/main/example.xml
- **[S23]** Google. *YouTube IFrame Player API*. https://developers.google.com/youtube/iframe_api_reference
- **[S24]** Google. *YouTube Required Minimum Functionality*. https://developers.google.com/youtube/terms/required-minimum-functionality
- **[S25]** Apple. *AVAudioSession*. https://developer.apple.com/documentation/avfaudio/avaudiosession
- **[S26]** Apple. *Downloading files in the background*. https://developer.apple.com/documentation/foundation/downloading-files-in-the-background
- **[S27]** Apple. *AVAssetDownloadURLSession*. https://developer.apple.com/documentation/avfoundation/avassetdownloadurlsession

## 35. Fontes internas usadas como autoridade arquitetural

- **[F01]** *FeedMine Feed Runtime — Unified Architecture Blueprint v0.4*, 17/09/2026. Seções especialmente relevantes: 11–16 (ação e UI), 28–30 (identidade/revisão), 45–49 (MediaCandidate/MediaPreparation/PublishedMediaSet/playback), 53–58 (publicação), 105–107 (metas e dependências).
- **[F02]** *FeedMine Feed Runtime V2 — Technical Architecture Specification v0.1*. Contratos de canonical supply, immutable published log, FeedSession e owners como `ImageBroker`, `MediaPreparation` e `ResourceGovernor`.
- **[F03]** *Sobre-o-feedmine.txt* e *How unusual FeedMine really is*. Tese de produto: feed contínuo, runway local que se mantém à frente do consumo, latência gerenciada, reaproveitamento de contextos e rejeição de otimizações que não consertam falhas evidentes de uso.

Estas fontes estavam anexadas ao projeto. Este relatório **não** afirma que as propostas arquiteturais já estão implementadas no HEAD, nem que aprovam automaticamente mudanças de código.

## 36. Matriz de afirmações críticas e seu lastro

| Afirmação | Evidência | Grau |
|---|---|---|
| Inoreader integra podcasts/YouTube e oferece quatro abas | [S01] | E2 |
| Pocket Casts iOS é open source | [S02] | E1 |
| Pocket Casts sincroniza transcrições geradas; não genericamente todas/offline | [S03, S04] | E2 |
| Pocket Casts separa player AVPlayer de superfície visual | [S05, S06] | E1 |
| PR #5336 propõe troca real de source quando áudio alternativo existe | [S08] | E1 — **PR não mesclada** |
| Fingerprints mitigam drift de anúncios dinâmicos | [S07] | E1/documentação do código |
| Readwise oferece autoscroll controlável e seek por transcrição | [S11] | E2 |
| Reformatar transcrição pode impedir overlay do highlight original | [S11, S12] | E2 |
| Snipd mapeia skip-backward dos fones para capturar trecho | [S14] | E2 |
| Snipd oferece auto-download por fila/hábito | [S15] | E2 |
| YouTube restringe extração de áudio e reprodução oculta/background | [S21, S24] | E2 — política |
| Renderer FeedMine não acessa rede e publication é imutável | [F01, F02] | Fonte interna normativa |
| Um player único independente da tela é adequado ao FeedMine | Síntese de [S05, F01, F02] | E3/E4 |

## 37. Lacunas e validação antes de codificar

**Não verificado externamente:** implementação real do cache/stream de Inoreader; arquitetura de backend de IA do Snipd; player/extração internos do Reader; direitos operacionais específicos de cada vídeo YouTube; performance em dispositivo do FeedMine. **Não verificado neste trabalho:** estado exato de branches, módulos já existentes, compatibilidade Swift 6 de todos os snippets, layout do app atual, coverage real de formatos de RSS e aprovação de uma ADR de playback.

**Próxima validação de engenharia recomendada:** ler o código atual do FeedMine V2, inventariar um único owner de media playback, comparar seus contratos com os definidos aqui e elaborar uma alteração pequena com testes de continuidade em scroll/filtro/background. Não iniciar uma nova engine de player nem implementar AI/fingerprinting antes desse inventário.

---

*Fim do relatório — FeedMine, pesquisa técnica e de produto, 18 de outubro de 2026.*
