# Integração das branches do ChatGPT — 2026-10-14

**Tipo:** relatório de coordenação de uma rodada de execução. **Não é veredito de gate** e não certifica
release. Registra o que foi implementado, verificado e revisado, e o que ainda falta.

**Base:** `efefd193` (`main` == `origin/main`; árvore limpa no início).
**Branch de integração:** `integration/chatgpt` — **`main` não avançou**.

## Como esta rodada foi executada

Seis frentes de código foram implementadas por instâncias do ChatGPT (conector GitHub) a partir de
`efefd193`, **uma branch por item, um commit por branch**, nunca em `main`. A verificação local
(`swift build` + suíte completa) rodou num **worktree separado** (`/tmp/fm-verify`) para não sujar a
árvore do repositório, que é o insumo do `identity.txt` das corridas de gate. Três revisões
independentes (somente leitura) foram feitas sobre as branches de maior risco.

| Papel | Instância | O que fez |
|---|---|---|
| Workers | 7 conversas ChatGPT | implementaram K-14, K-15, K-10, R3, R4, D2, B06 (cada uma numa branch própria) |
| Revisores | 3 agentes de revisão (somente leitura) | auditaram K-15, K-10 e B06 contra os invariantes e o desenho |
| Arquiteto de integração | esta sessão | mediu, revisou, integrou e roda os gates |

## Branches entregues

| Item | Branch | Commit | Estado nesta rodada |
|---|---|---|---|
| K-14 — lease da cauda oculta protege até o último card **admitido** | `chatgpt/k-14-hidden-tail` | `b2d22bb7` | verificado (build + testes novos) e **integrado** |
| R3 — consumo aprendido sobrevive ao background | `chatgpt/r3-preserve-consumption-runway` | `9fb199e2` | verificado (suíte completa) e **integrado** |
| R4 — fronteira usa a atribuição congelada, não memberships mutáveis | `chatgpt/r4-frozen-editorial-boundary` | `944e6678` | verificado (suíte completa) e **integrado** |
| D2 — elegibilidade de idioma estrita sem encolher a aquisição | `chatgpt/d2-strict-acquisition-language` | `c90a67da` | verificado (suíte completa) e **integrado** |
| K-10 — A01/A02/A05 em `AppComposition` | `chatgpt/k10-composition-a01-a02-a05` | `44d63697` | revisão independente: resolvido, sem achado novo; **falta compilar o alvo de app** |
| K-15 — corpo de RSS/Atom vira `bodyText` sem churn de identidade | `chatgpt/k-15-body` | `edcde1e1` (1ª versão) → rework em andamento | **não integrado** |
| B06 — coletor de evidência física | `chatgpt/b06-evidence` | `92c76812` (rework) | **não verificado** ainda |

## Verificação executada (worktree `/tmp/fm-verify`, `~1300` testes por rodada)

| Branch | `swift build` | Suíte completa | `git diff --check` |
|---|---|---|---|
| `r3` | 0 | Executed 1286, 4 skipped, **0 failures** | limpo |
| `r4` | 0 | Executed 1286, 4 skipped, **0 failures** | limpo |
| `d2` (rework) | 0 | Executed 1290, 4 skipped, **0 failures** | limpo |
| `k14` | 0 | 2 testes novos passam (`PublicationHiddenTailLeaseTests`) | limpo |

**Integração passo a passo** (`integration/chatgpt`, HEAD **`aaeda956d0c0b8f0773d2ddadc374f0ab3b38c53`**),
com build + suíte completa depois de **cada** merge:

| Merge | HEAD depois | Suíte |
|---|---|---|
| `r3` | `86978b98` | 1286 testes, 0 falhas |
| `r4` | `15710eb0` | 1287 testes, 0 falhas |
| `d2` | `035cc1e7` | 1292 testes, 0 falhas |
| `k14` | `aaeda956` | 1294 testes, 0 falhas |

## Revisões independentes e o que elas mudaram

- **K-10 (A01/A02/A05):** a primeira versão foi **reprovada** — `A05` quebrava três transições
  (seleção adotada fora da coleção mantinha o preset; coleção removida/esvaziada derrubava a abertura;
  fonte exclusiva da coleção era invalidada no lançamento seguinte) e os testes de A01/A02 eram
  asserções sobre o **texto-fonte**, que não provam comportamento. Reconstruída: `sessionState(for:)`
  e `presetAfterSelectionChange()` reconciliam contexto e seleção, os testes de grep foram
  removidos e três testes comportamentais cobrem os cenários. Re-revisão: **resolvido, nenhum achado
  novo**.
- **K-15:** a revisão encontrou três defeitos de integração — (P1) alteração de corpo não cria
  ocorrência publicável porque a fronteira editorial e a identidade de publicação só veem
  título/resumo; (P2) o enriquecimento é gravado mas `originRevision(id:)` não o devolve, então o
  corpo nunca chega ao leitor; (P2) `Atom type="text"`/`text/plain` passa pelo removedor de HTML e
  perde texto literal. Rework solicitado.
- **B06:** a revisão encontrou que o script cairia em `NOT_MEASURED` em quase todas as medidas
  (nomes de schema/coluna de `activity-monitor-process-live` e de Animation Hitches inventados),
  e que uma gravação interrompida poderia ser promovida a evidência completa. Rework solicitado;
  branch atualizada (`92c76812`), re-verificação pendente.

## Incidente: disco cheio invalidou uma corrida

Durante a rodada o volume chegou a **155 MB livres**. Consequências medidas e o que foi feito:

- A verificação de branches rodou em paralelo com uma corrida de gate e falhou por `ENOSPC`
  (`ld: write() failed, errno=28`; e "Executed 1286 tests, with 547 failures", todas
  `couldNotCreateDirectory … out of space`). Essas falhas eram **de disco, não de código** — as
  branches foram reverificadas depois, com o disco livre, e passaram.
- A corrida **`bench/run/20261014T200700Z` (B03)** foi produzida sob disco cheio e **não é
  evidência válida**; deve ser descartada, não citada.
- Espaço recuperado de `bench/run/*/derived` (cache de build, ~1 GB por corrida, ~7,4 GB no total).
  `report.md`, `*.verdict.json`, `*.log`, `*.phases`, `.png` e `identity.txt` **não** foram tocados.

**Regra que fica:** verificação de branch e corrida de gate **não** podem rodar ao mesmo tempo; medir
`df -h /` antes de cada etapa.

## Evidência de gate que continua valendo (base `efefd193`)

| Gate | Veredito | Artefato bruto | Observação |
|---|---|---|---|
| B01 (A+B) | **PASS** | `bench/run/20261014T195740Z/B01.verdict.json` | `dirty: 0`, 5 cláusulas, 237 fontes no conjunto de aquisição |
| B02 | **PASS** | `bench/run/20261014T192902Z/` | `dirty: 0` |
| B05 | **PASS** | `bench/run/20261014T193624Z/` | `dirty: 0` |

Esses veredictos descrevem **`efefd193`**, não o commit candidato. Como K-14, R3, R4, D2, K-10 e
K-15 mudam comportamento, **não são transferíveis**: a certificação tem de ser rodada de novo sobre
o commit candidato, com B01–B06 no mesmo commit.

## O que falta (honesto)

1. **K-15** e **B06**: reworks em andamento; não integrados.
2. **K-10**: revisado, mas o alvo de app (`FeedMineAppTests`) ainda não foi compilado com ele.
3. **Certificação**: B01–B06 (incluindo B06 no iPhone 14 Plus físico, pareado e disponível) sobre o
   commit candidato — **ainda não rodada**. Nada aqui autoriza release.
4. **Backfill do K-15** (seção 3 do desenho): frente separada, ainda não iniciada.
5. `main` **não** avançou.

## Ambiente

macOS (arm64, 10 cores); Xcode 26.6 (17F113); simulador dedicado `FeedMine Bench`
(`16DA3DB5-C9E0-4190-AF2F-AFAADC7EB7AE`); iPhone 14 Plus físico pareado
(`BBA4F656-A5EA-5D81-934E-E484ED71B8E2`, iOS 18.6.2, Developer Mode habilitado);
congelamento vigente em `bench/EVALUATOR.sha256` (oráculo `57804e0b…`, driver `08739fd3…`).
