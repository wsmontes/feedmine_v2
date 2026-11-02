# SPEC — identidade de vídeo para feeds Atom no formato YouTube

Worktree: `/Users/wagnersilvamontes/.codex/worktrees/feedmine-video/feedmine_v2`, branch
`product/video-identity-20261024`, base `2dfa3f9a`.

## 1. O defeito, com evidência

O catálogo publicado tem **77.443 fontes**, das quais **30.241 são `www.youtube.com`**. A fila publicada de
629 cartas não tem **nenhuma** carta de vídeo (`media_identity`: 498 áudio, 131 nenhum, 0 vídeo).

A causa foi medida no tradutor. Um feed real do YouTube responde assim (amostra:
`https://www.youtube.com/feeds/videos.xml?channel_id=UCg60QRUSvLZMF4zHv2ajBqA`):

```xml
<entry>
  <id>yt:video:jcBji3EovfI</id>
  <link rel="alternate" href="https://www.youtube.com/watch?v=jcBji3EovfI"/>
  <media:group>
    <media:content url="https://www.youtube.com/v/jcBji3EovfI?version=3"
                   type="application/x-shockwave-flash" width="640" height="390"/>
    <media:thumbnail url="https://i3.ytimg.com/vi/jcBji3EovfI/hqdefault.jpg" width="480" height="360"/>
  </media:group>
</entry>
```

`SyndicationTranslator.contents(_:base:)` (linha ~296) só aceita `media:content` quando
`attributes.medium == "image"` ou o tipo é MIME de imagem. `playback(_:base:mimeType:)` (linha ~280) exige um
MIME que `MediaCandidateClass.playback(forMIME:)` reconheça como áudio/vídeo. O `type` acima
(`application/x-shockwave-flash`) não é reconhecido e não há `medium`, então **o vídeo é descartado antes de
virar candidato**. `PublishedMediaDecision.resolve` só produz `.video` a partir de um `MediaCandidate` com
`role == .playback` e `mediaClass == .video`; sem candidato, a carta sai com identidade `none`.

Consequência: 30 mil fontes de vídeo do catálogo publicam como texto, e a interface nunca pode nomear um
vídeo. D2 (PD-2026-10-20) já define o comportamento desejado: identidade `.video`, ação abre o link do item no
navegador (nada de player interno).

## 2. Correção pedida

**Escopo de escrita (só estes caminhos):**
- `Sources/FeedMineSyndication/SyndicationTranslator.swift`
- `Tests/FeedMineSyndicationTests/**`

**Não toca:** `Sources/FeedMinePublication/**` (a decisão de identidade já está correta), `Sources/FeedMineRuntime/**`,
`Sources/FeedMineEditorial/**`, `FeedMineApp/**`, `bench/**`, `docs/**`.
**Não roda `xcodebuild`** — outro dono usa o simulador nesta rodada. Verifique com `swift test`.

Regras da correção:
1. Um `media:content` (ou `media:group/media:content`) é candidato de **playback de vídeo** quando:
   - `medium == "video"`, **ou**
   - `type` começa com `video/`, **ou**
   - `type == "application/x-shockwave-flash"` (o formato que o YouTube emite até hoje para o media:content).
   Nesses casos produza `AcquisitionMediaCandidateClaim(role: .playback, mediaClass: .video, remoteURL: …,
   declaredMimeType: type)`.
2. **No máximo um `role == .playback` por revisão.** Se já existe um playback vindo de `enclosure`
   (`rel="enclosure"` no Atom, `<enclosure>` no RSS), ele **vence** — é o payload canônico do item. O vídeo
   de `media:content` só entra quando não há playback. Ordem determinística, nunca duas claims.
3. Imagens continuam exatamente como estão: `medium="image"`, MIME de imagem, `media:thumbnail`, `itunes:image`,
   imagem do HTML. Não converta imagem em vídeo nem vídeo em card visual.
4. Áudio continua exatamente como está: `enclosure type="audio/*"` vira playback de áudio; `media:content`
   `medium="audio"` deve seguir a mesma regra de (1) para áudio — se você não tiver certeza, **não mexa em
   áudio** e diga no relatório.
5. Nada de rede nos testes: use fixtures XML inline no formato da amostra acima.

## 3. Testes obrigatórios

1. **YouTube Atom**: entrada com `media:group/media:content type="application/x-shockwave-flash"` +
   `media:thumbnail` → exatamente uma claim `.playback/.video` e uma claim `.cardVisual/.image`; o link do item
   é preservado.
2. **medium="video" com type="video/mp4"** → uma claim de playback de vídeo.
3. **Enclosure de áudio + media:content de vídeo** → só o playback de áudio (regra 2).
4. **Regressão**: RSS com `enclosure type="audio/mpeg"` continua com uma claim de playback de áudio; entrada só
   com imagem continua sem playback; `SyndicationTranslator` não muda fingerprints de material para entradas
   que não tenham `media:content` de vídeo (o fingerprint usa as URLs das claims — se a claim nova entrar, o
   fingerprint muda **de propósito** para essas entradas; diga isso no relatório).
5. Se existir um teste de integração `PublishedMediaDecision.resolve(playback:link:)`, adicione um caso que
   prove `.video` + `.externalURL`.

## 4. Aceitação

- `swift test --filter Syndication` verde, com a contagem antes/depois.
- `swift test` do pacote sem novas falhas (base: 1.672 testes / 1 skip / 0 falhas).
- Relatório curto: o que mudou, as claims produzidas para a amostra real do YouTube, o efeito no fingerprint e
  o SHA final.
- Commit único ou dois pequenos, mensagem no formato do repo. Não faça push.
