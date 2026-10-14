# Build 40 no TestFlight interno, e a reconciliação de `main` (2026-10-13)

## O que foi enviado

`1.0 (40)` = `6e9b02d82cfbf6f8a128a7997cad30c55aac2a04`, tag anotada `ios/1.0-build.40-6e9b02d8`
(empurrada para `origin`). Upload em 2026-10-13 23:51 PDT por `scripts/release-testflight.sh`
(`PAIRING OK` antes da exportação: SHA do archive conferido contra `HEAD`; SHA embutido no
`Info.plist` do archive = `6e9b02d8`).

Estado Apple confirmado pela API (`/v1/builds`, `/builds/<id>/buildBetaDetail`),
consulta em 2026-10-13:

| Campo | Valor |
|---|---|
| build id | `9aa7e0d5-818b-489d-903d-75d73c698214` |
| versão | `1.0 (40)` |
| `processingState` | **VALID** |
| `expired` | false |
| `internalBuildState` | **IN_BETA_TESTING** |
| `externalBuildState` | READY_FOR_BETA_SUBMISSION |
| grupo | **WawaTesters** (interno, `hasAccessToAllBuilds: true`) |

Build anterior no canal era `1.0 (33)`. Nenhuma build entre 34 e 39 foi enviada; a numeração
saltou porque `CFBundleVersion` vinha sendo incrementado nas instalações locais no aparelho.

**Instalação observada: não.** Nenhuma sessão viu a build 40 rodando no iPhone do dono. O que
está provado é a disponibilidade interna.

## O que a build contém (9 commits, todos anteriores a esta sessão)

`e0459944` era a última publicada. Desde então:

- `6a04d9d2` — a cabeça admitida nunca é podada: nada acima do leitor é removido da lista.
- `9f217bfe`, `93cc8f1a`, `16595665` — trabalho por avanço sai do main actor; fronteiras de
  residência; piso de reserva no runway.
- `7a848c91` — o app mede os próprios intervalos de frame (`FeedFrameMeter`).
- `c4edf3bc` — o scroll deixa de responder ao backend: a lista observa a **projeção publicada**
  (`renderedItems`/`renderedEditionID`/`renderedContextKey`/`work`), não a posição.
- `85c65074` — o handoff de projeção precoce falha localmente, não em silêncio.
- `f91121b9` — a instalação por avanço volta (a supressão havia estancado a produção: `advance`
  caiu de 60 para 1, `replenishment_requested` de 40 para 1), preservando a fluidez.

Medido no aparelho pelo dono (build 39 local): 60 fps, 0,1 % de hitch.

## O que esta sessão corrigiu antes de enviar

`HEAD` estava **vermelho**: 3 assertions dos smoke tests de arquitetura
(`FeedScreenStoreTests` S11/S12) falhavam desde `c4edf3bc`, que passou a publicar no
`FeedScreenStore` uma cópia da apresentação — exatamente o que aquele teste proíbe. O commit
`6e9b02d8` admite a projeção **explicitamente**, nomeia os quatro campos publicados e substitui a
proibição genérica de `[PresentationCard]` por "uma única linha pode nomeá-lo, e é a declaração de
`renderedItems`". Acrescenta `testS11ThePublishedProjectionCannotDrift`: depois de uma instalação
aceita e de uma instalação só-de-relato, a projeção tem de ser igual ao que `state` guarda.

Suíte do pacote: **1.254 testes, 1 skipped, 0 falhas** (`swift test`, 2026-10-13).

## Revisão independente (QA, terminal OMP)

- A não-deriva está provada **para `install`**, que hoje é o único escritor de `state` — provado
  por varredura do arquivo, não pelo teste.
- Existe um **segundo detentor de janela desenhada** fora do `Mirror` que o S11 varre:
  `FeedInteractionPresentation.held: FeedPresentationSnapshot?` (`FeedVisualCapture`), que congela
  a janela durante um gesto e é reconciliado com o estado. Não é derivado da projeção.
- `renderedItems` é escrito antes de `renderedEditionID`/`renderedContextKey`/`work` dentro de
  `install`: a tupla fica transitoriamente inconsistente até o fim da mesma volta no main actor; o
  único consumidor que cruza os dois lados tem guarda explícita. Sem ação.

## Pendências que esta build NÃO fecha

- **B01–B06 não foram reexecutados**; a build não certifica gate algum. B03 (30 min) e B06
  (memória/energia/térmica/hitches em iPhone físico) seguem `NOT_RUN`.
- B01: o último percurso A+B deu `NOT_RUN` só na cláusula 1 (o perfil A declarou um assunto; o
  oráculo exige dois). Diagnóstico e correção em curso — ver o relatório da rodada.

## Fluxos prioritários para o dono testar

1. Flings rápidos e rajadas: a lista não pode saltar nem voltar.
2. Passar um card ainda desenhado, abrir artigo, voltar à âncora.
3. Troca A→B→A, reopen, salvos, retorno offline.
4. Deixar rolando por vários minutos: o feed não pode terminar sozinho.

## B01 A+B no HEAD — FAIL (medido depois do envio)

Corrida `bench/run/20261014T065023Z`, commit `6e9b02d8`, `dirty files: 0`, corpus e oráculo
congelados, dispositivo dedicado `FeedMine Bench`.

| Cláusula | Resultado |
|---|---|
| 1 — jornada caminhada nas duas fases | NOT_RUN (A: `["neutral"]`; B: `["neutral","negative:not-offered"]`; nenhum assunto declarado) |
| 2 — não depende das quatro fontes padrão | PASS (`[]`) |
| 3 — ≥50 fontes no conjunto de aquisição | PASS (180) |
| 4 — ≥20 fontes contribuindo nos primeiros 300 cards | **FAIL (5)** |
| 5 — outro perfil muda o conjunto | PASS (a:180 b:176 iguais:0) |

Estados: 180 registradas · 240 consultadas · **5 contribuindo** · **34 cards publicados**.

Referência comparável, mesmo corpus congelado: corrida `20261014T004301Z` (commit
`da2b59fd`, worktree `codex/feed-layout-hang`, 2026-10-13 17:48) publicou **537 cards** com
**83 fontes** contribuindo. Driver, oráculo, corpus, duração e dispositivo são os mesmos.

Leitura do traço do próprio app nessa corrida: ~150 s de rolagem contínua produziram
**1 evento `advance`** e 6 mudanças de janela, com o medidor de frames registrando ~60 fps o
tempo inteiro (`frames: 59–60`, `late: 0–1`). A interface está fluida; o backend não está vendo
o leitor. Sem posição não há reposição: o feed publica o bootstrap e para, e nenhum convite
chega a ser colocado (por isso a cláusula 1 ficou NOT_RUN).

O delta de código desde a corrida de referência é pequeno e nomeado:
`FeedScreen.swift` (302 linhas) e `FeedMineApp.swift` (12 linhas) — nada mais do app mudou.

Esta é a prioridade corrente e substitui a correção de cadência de convites, que não pode ser
medida enquanto o leitor não avança.
