# RETOMAR AQUI (iMac) — feedmine_v2, continuação da rodada de 2026-10-16

Este arquivo é o primeiro passo da sessão no iMac. Ele pressupõe que o clone do GitHub já existe em
`~/Documents/GitHub/feedmine_v2` e que a pasta `_migration_feedmine_2026-10-16/` chegou ao lado dele.

## 0. Antes de tudo: trazer as refs locais que o GitHub não tem

```sh
cd ~/Documents/GitHub/feedmine_v2
git fetch ../_migration_feedmine_2026-10-16/git/feedmine_v2-local-refs.bundle \
  'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'
git bundle verify ../_migration_feedmine_2026-10-16/git/feedmine_v2-local-refs.bundle   # "complete history"
git log --oneline main -3        # deve terminar em d605a335
git branch | wc -l               # ~41
```
Sem isso faltam **40 branches** (os gates, os splits, o instrumento, o HS-02) e as tags `ios/*`.

## 1. Ambiente: a ordem importa

```sh
df -h /                                        # piso do gate: 2,5 GB; abaixo disso, parar
xcrun simctl list devices available            # precisa haver um iPhone com runtime iOS 26.5
xcrun simctl create "FeedMine Gate" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5
```
Se o SDK 26.5 não existir no iMac, **pare e traga a mensagem literal** — não contorne.

Worktree nova a partir de árvore que tem `.build` precisa de `rm -rf .build` **antes** do primeiro `swift build`
(o cache clonado carrega o caminho de origem e o build falha com *precompiled file … was compiled with module cache
path*). Insumos gitignored que a worktree nova não traz e que os testes exigem:
`FeedMineApp/FeedMineApp/Resources/catalog.sqlite` (sha256 `42e60234…`) e `bench/corpus/profiles.json`
(sha256 `24109941…`) — conferir contra `catalog.manifest.json` e `bench/MANIFEST.sha256:6`.

## 2. HS-02 — a correção do compartilhamento (o defeito está medido, a correção não)

```sh
git switch fix/hs-02          # commit 090b8352, pai = c9d599eb; mensagem diz "ainda NÃO compilado"
rm -rf .build
swift build
swift test                    # esperado: Executed 1400 tests, with 3 tests skipped and 0 failures
xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -destination 'platform=iOS Simulator,id=<novo>' -derivedDataPath /tmp/fm-hs02-dd \
  -parallel-testing-enabled NO \
  -only-testing:FeedMineUITests/FeedMineUITests/testSharingTheExportOpensTheSystemSurfaceAndKeepsTheReadingPoint
```
Esperado no último: `Executed 1 test, with 0 failures` **e** as linhas `export-share: … s after the tap` impressas —
com a folha do app no ar, o tempo tem de cair para a ordem dos ~4 s medidos quando nada bloqueia. As três saídas brutas
vão para o §6 do relatório `docs/reviews/2026-10-16-share-do-export-na-folha-que-o-pede.md`, e o commit final é
`git commit --amend` do `090b8352` (nada foi publicado) tirando o "ainda NÃO compilado" da mensagem.

**O defeito, para quem duvidar:** tocar Compartilhar (e Salvar arquivo) não abre a superfície do sistema enquanto a
folha de exportação do app está no ar — 4 reproduções, sempre em
`FeedMineUITests.swift:662: XCTAssertTrue failed - Compartilhar must open the system's own share surface over the app's
own sheet`. Causa por leitura: cinco `.sheet` irmãos no mesmo apresentador, com uma máquina explícita de
uma-superfície-por-vez já existente (`FeedMineApp.swift:120-140`).

## 3. B06 — a corrida de 45 minutos (o gate que nunca rodou)

O instrumento **exige o aparelho livre de qualquer processo FeedMine**, e os dois bundles instalam
`FeedMine.app/FeedMine`: para distinguir, use `devicectl device info apps` (dá o
`file:///…/Bundle/Application/<UUID>/FeedMine.app/` de cada bundle) contra o `executable` de `device info processes`.
**Só o bundle de desenvolvimento** (`96462AC0…`) é de agente; o de produção (`C78B92AD…`) só o dono encerra.

```sh
bash scripts/b06-evidence.sh --udid <physical-device-udid> --host 192.168.1.76:8757
```
Declarar no relatório, por escrito: (i) **energia `NOT_MEASURED`** — o template `Energy Log` não existe nesta
instalação (26 templates *Standard*; os *instrumentos* de energia existem); (ii) **hitches 0 linhas por dois métodos
independentes** (minha validação curta e uma gravação por attach que fechou limpa), com a causa **INDETERMINADA** e
explicitamente **não** usado como prova de suavidade; (iii) **B06 nunca é PASS pelo instrumento** — o veredito se
escreve contra a régua congelada. Bateria e térmica iniciais também são `NOT_MEASURED` (o `devicectl` não tem
subcomando para elas). O registro completo está em `docs/reviews/2026-10-16-b06-registro-de-ambiente.md`.

## 4. O que espera verdict (não integrar por conta própria)

| Branch / commit | O que é | Estado |
|---|---|---|
| `gate/pd8-r1-coalesced-discovery-opportunity` `6d02dfa1` | oportunidade coalescida chega à descoberta; vermelho/verde na mesma régua; só toca `FeedRunwayDriver.swift` | fechado, aguardando verdict de integração; R6-E depois |
| `refactor/feed-screen-split` `af9f8515` | `FeedScreen.swift` 807→207 + 3 arquivos; 179 testes 0 falhas | aguardando verdict próprio |
| `refactor/publication-store-split` `c5cda2af` | `PublicationStore.swift` 1166→165 + 4 arquivos; 722 testes, 1 skipped, 0 falhas | aguardando verdict próprio |
| `instruments/journey-measurements` `870634c3` | `bench/journey.py` com hash próprio, vereditos binários | fora da régua congelada; aguardando verdict |
| dedup local | WIP `c25acf57` | **depois** do split de `PublicationStore` (mesmo arquivo) e com `AppComposition.swift` livre |
| `fix/reopen-journey` | já integrado na `main` (`baf10e2d`) | feito |

Cláusulas da régua com número escolhido (`≥80%` de 200 cards, `≥1 s` de paralisação, 1800 avanços, `≥50` fontes) só se
aposentam pelo **protocolo de revisão do oráculo** (autorização registrada + `bench/revisions/` + hash novo + controle
positivo) — o arquiteto marcou `NOT AUTHORIZED` para mexer no congelado. Não patche o oráculo para produzir verde.

## 5. O que não está medido, e não deve ser apresentado como se estivesse

- **B06 `NOT_RUN`** — o gate que trava a release externa.
- **Fluidez `NOT_CERTIFIED`** — o engasgo está localizado (gesto; acompanha as observações do app) e a causa óbvia foi
  refutada, mas **nenhuma correção de produto** foi implementada.
- **Release externa não autorizada**, e a build 48 distribuída (`03d05f5f`) **não** carrega a reabertura nem a remoção do
  banner; ela também tem o Compartilhar quebrado.
- **A validação da versão distribuída** depende de o dono instalar a 48 pelo TestFlight (o iPhone estava na build 44).
