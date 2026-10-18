# Estado em pausa — 2026-10-17 (America/Vancouver)

Pausa pedida pelo dono. Nada em execução: os trabalhos em lote foram encerrados, e os `swift test`/`xcodebuild`
descritos abaixo **já foram executados** antes da pausa; nenhum veredito aqui é antecipação de execução futura.

`main` = `5e4e2142` (`origin/main` idem). `git status --short` na árvore canônica: apenas o documento
`Especificação do FeedMine V2 -  Estabilidade de coleta e UI.md` não rastreado. Todas as branches de trabalho
estão em `origin`; nenhuma foi mergeada em `main`.

## 1. Especificação (Estabilidade de coleta e UI): A–H

Cada item foi implementado em branch própria, com prova executada. Nenhum item foi declarado cumprido por existência
de teste.

| Item | Branch | Base | O que foi feito | Prova |
|---|---|---|---|---|
| A cold-start | `feat/spec-collection-ui` `058a629d` | `5e4e2142` | `initialParallelism` configurável (48 planejadas, teto de 8 concorrentes) no ponto único que escolhe orçamentos | `12 cards, first_cards_ms=46` em transporte de fixture — **teto sintético**; aparelho com rede mediu 5,5 s, acima da régua de 3 s |
| B callback de mídia | idem | idem | `onReadinessChanged` ligado ao `noteLocalSupplyChanged`: transição de prontidão agenda o drive | teste de transição publicando mídia pendente |
| C idioma | `feat/onboarding-language` `c4fbb215` | `5e4e2142` | pergunta explícita no primeiro run ("Em quais idiomas você quer ler?"), nada pré-selecionado, "Todos" é o pular; `Locale.current` removido do caminho | `14/0` (11 SPM + 2 app + 1 UI) |
| D scores | `feat/spec-collection-ui` | idem | ordenação do lado da composição (qualidade/atividade), planejador intacto ("supplied order remains priority") | `131/0` |
| E estabilidade de UI | `fix/deferral-invalidates-list` `10bc0bd7` | — | conserto de frames; A/B atribuiu as falhas de UI | 3,02% → **1,51%** em Release/aparelho (janela do A/B; não é certificação contínua) |
| F teto | `feat/foreground-cadence` `54680fa4` | `5e4e2142` | `maxAdmittedItems = 2000`, FIFO, nunca remove a carta do leitor | `3/0` + `2/0`; 2100 cartas → `[94…2093]` |
| G produção contínua | idem | idem | cadência de primeiro plano ≥10 s enquanto visível; para em `.inactive`/`.background`; desenho emendado | 30 drives em 5 min, zero em segundo plano; `3/0` |
| H provas | — | — | critérios A/B/C/D/F/G pinados | pacotes citados nas linhas acima |

## 2. Diretrizes do dono (docs-only) e o que virou código

| Diretriz | Branch | Prova |
|---|---|---|
| Prontidão render-ready (`2026-10-17-render-ready-admission-rule.md`) | `fix/render-ready-admission` `da94d5c7` | carta sem pixels **não atravessa** a admissão e nunca é reescrita como texto sob a mesma identidade; vermelho de 9 falhas antes; `3/0 · 175/0 · 181/0 · 340/0` |
| Blindagem do flag | `fix/readiness-text-declared` `d942b75e` | `textDeclared` **obrigatório** — omitir é erro de compilação; `7/0 · 176/0 · 340/0` |
| Salvos offline (`2026-10-17-filter-consistency-and-offline-saves.md` §2) | `feat/durable-saves` `1487c750` (sobre `d942b75e`) | disponibilidade persistida (`textOnly/pending/ready/failed/insufficientSpace`), salvar dispara preparação, re-preparação sem alterar a ocorrência, texto puro declarado final; disco cheio provado com `insufficientSpace` e salvo intacto; **1420/0** |
| Filtros (§1) | `fix/filter-confirmation-boundary` `2c642abc` | quatro casos com gatilho SQLite real; upsert único; gravação antes da memória; erros distintos; `4/0 · 38/0 · 7/0` |
| Leitor / disponibilidade (`2026-10-17-reader-local-text-and-availability.md`) | `fix/reader-availability-language` `faf8256a` | frase honesta ("Texto fornecido pela fonte…"), saída local para resumo curto sem endereço, limiar 3000 intocado; `14/0` |

## 3. Regressão de runtime encontrada e corrigida

`RunwayController.activate` chamava `deactivate()` incondicionalmente; com a cadência de 10 s isso apagaria
`consumptionSamples`/`latencySamples` a cada tique e desligaria a adaptação F05-R2/R3. Corrigido em
`fix/activate-preserves-samples` `dd5b2a87`: a ativação só reseta quando o `RunwayScope` **inteiro** muda
(edição + contexto + revisão editorial). Vermelho de 124 falhas com o conserto removido; `74/0`, pacote `1412/0`.
Documento emendado em `CONTINUOUS_FEED_RUNWAY_DESIGN.md`.

## 4. Candidato de aceitação — build 51

`integration/51` = **`8fcfe37c`**. Nove merges (`--no-ff`), **zero conflitos textuais**; as regras novas foram
verificadas semanticamente: `textDeclared` sem default, `maxAdmittedItems = 2000` sem remover a âncora,
`activate` preservando amostras no mesmo escopo, exclusão em vez de conversão, onboarding/coleta/salvos/cadência
coexistindo.

- Pacote no SHA com bump: **`1445/0`** (4 skips pré-existentes de catálogo de referência).
- Bump da build **51 dentro do SHA** (`chore(release): build 51 — acceptance candidate bump`, `8fcfe37c`), não depois.
- Arquivo Release: `/tmp/fm-build51/FeedMine.xcarchive` (187 MB), `CFBundleVersion 51`, `1.0`, time `955573A4YH`,
  `FeedmineGitSHA = 8fcfe37c`, `FeedmineGitBranch = integration/51`. **Nenhum export, nenhum upload, nenhuma tag.**
  O archive é assinado para desenvolvimento (`get-task-allow=true`); a re-assinatura de distribuição acontece só no export.
- Hashes registrados em `/tmp/fm-build51/BUILD-INFO.txt`.

## 5. TestFlight — estado real da conta (lido pela API, não suposto)

| Item | Valor |
|---|---|
| App | `Feedmine` (`com.feedmine.app`, id `6793279758`) |
| Grupo | `WawaTesters` — **interno**, **2 testadores** (sem Beta App Review) |
| Build 49 | `VALID`, enviada 17/10 14:15, **já associada ao grupo** |
| Build 51 | **não enviada** — depende da B06 no mesmo SHA |

Distinção de conta: endereço de membro da equipe ASC vira testador **interno**; qualquer outro endereço cria
testador **externo** e o build só instala após Beta App Review.

## 6. Gates e o que não está provado

- **B06: NOT_RUN.** O iPhone 14 Plus (`BBA4F656-…`) está `unavailable` (desconectado). O run existente em
  `bench/run/20261017T162333Z/` mediu **`d8d2f26e…`**, não `8fcfe37c` — **não** é evidência para a 51.
- **B01–B03: NÃO EXECUTADOS nesta pausa.** Foram disparados no SHA de aceitação e interrompidos pelo pedido de pausa;
  nenhum veredito deve ser citado.
- Regra a manter, verbatim do proxy do dono: **nenhum build cujo B06 nomeie outro SHA, e nenhum bump de número
  substituindo um gate.**
- Provas em aparelho ainda pendentes por item: salvos (limpeza, reinício offline, retenção de mídia, troca de versão,
  disco cheio) e filtros (interrupção entre fases, disco falhando, A→B→A, posição e edição, reinício offline).
- A/B de UI: T1/T3 atribuídos ao ambiente; **T2/T4 falham também na base** (pré-existentes), e a suíte de UI não é
  verde em nenhuma das árvores.

## 7. Achados de terceiros ainda abertos

- `RunwayController` — resolvido em branch (§3); `main` ainda tem o comportamento antigo.
- `CandidateProvider` trata `-term` como substring literal — documentado, não corrigido (busca).
- `cacheRead: 0` reportado em Z.ai e Alibaba — dois provedores, mesmo sintoma; limitação do harness ao reportar.
- Auditoria de kernel do monitor (`a0bba1a0`, K-01..K-10): consultiva; a aceitação é a árvore final com B01–B05 e
  B06 em aparelho sob a régua congelada, não benchmark sintético.

## 8. Pendências do dono

1. **Veredito do arquiteto** sobre as branches — `main` fica em `5e4e2142` até ele; a integração é `integration/51`.
2. **B06** com o iPhone conectado/desbloqueado, no SHA `8fcfe37c`, com diretório de run novo chaveado a esse SHA.
3. Depois da B06: export com `destination=export`, upload e associação ao `WawaTesters` — só então a 51 existe no
   TestFlight. `scripts/release-testflight.sh` **faz upload como efeito** e cria tag; não rodá-lo antes da B06.

## 9. Como retomar

```bash
# estado
git rev-parse --short origin/main origin/integration/51      # 5e4e2142 / 8fcfe37c
git for-each-ref --format='%(refname:short) %(objectname:short)' refs/remotes/origin | grep -E 'fix/|feat/|integration/51'

# B06 (com o aparelho conectado e desbloqueado)
FEEDMINE_BENCH_DEVICE_UDID=BBA4F656-A5EA-5D81-934E-E484ED71B8E2 \
FEEDMINE_BENCH_TRANSPORT_HOST=<mac>:8757 \
bench/run.sh --gate B06

# publicação (somente com a B06 nomeando 8fcfe37c)
xcodebuild -exportArchive -archivePath /tmp/fm-build51/FeedMine.xcarchive \
  -exportOptionsPlist /tmp/fm-release-evidence/ExportOptions-export.plist \
  -exportPath /tmp/fm-build51/export -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_H3U55Z9WZ7.p8 \
  -authenticationKeyID H3U55Z9WZ7 -authenticationKeyIssuerID 0e1bd229-1284-4916-91d2-7bf989859bcc
```
