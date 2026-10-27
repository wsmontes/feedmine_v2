# FeedMine V2 — build 57 interna (TestFlight)

Data: 2026-10-26 (PDT). Escopo: build interna de TestFlight a partir de `ef5d7999f02650dcd8ca9334ccce7443718f9574`
(`product/nf04-tail-truth`), no worktree de release `.codex/worktrees/testflight-build-57/feedmine_v2`.
Build **1.0 (57)**; o commit pareado é este commit de bump sobre `ef5d7999`.

## O que esta build é

- Candidata de **beta interna** (grupo `WawaTesters`), não release pública.
- Código de produto igual a `ef5d7999` — a única alteração deste commit é `CFBundleVersion 55 → 57`
  e este documento.
- Catálogo de produção verificado, os mesmos bytes das builds anteriores:
  `catalog.sqlite` 117.993.472 B sha256 `1825fdae1d68fc5f6c22f1c1574d9930b8e6e88947f841519c12a9d1554d01b8`,
  `catalog.manifest.json` sha256 `4cc9cba6a85497d22aba3ef05fbca99b56d2c30616b5642307ec6b53ea8ea4de`
  (P0C revision 5). Nenhuma recompilação de catálogo, nenhuma reescrita do descritor.

## Limites honestos (inalterados por esta build)

- **B03**: último resultado medido é **FAIL mecânico** (run `20261026T143646Z`, commit `c9942340`,
  1 parada ≥ 1 s; as outras quatro cláusulas PASS). Não é reclassificado aqui.
- **B06**: **NOT_RUN** — exige iPhone físico.
- **Nenhum gate foi reexecutado em `ef5d7999`**: não existe corrida de gold gate neste commit.
- Portanto: esta build **não** certifica release pública. App Store externo segue **NÃO-GO** até
  B01–B06 com PASS no head publicado e verdict do arquiteto (`docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md` §1).

## Assinatura e envio

- Assinatura gerenciada na nuvem: `-allowProvisioningUpdates` + chave ASC no archive **e** no
  `-exportArchive` (não há identidade de distribuição local nesta máquina).
- Envio: `scripts/release-testflight.sh` (caminho padrão, `destination=upload`), app `6793279758`,
  bundle `com.feedmine.app`, team `955573A4YH`.
- Tag local criada pelo script (`ios/1.0-build.57-<sha>`), não empurrada.

## Evidência

- `/tmp/feedmine-testflight-release.md` — relatório da execução (archive, upload, ASC).
- `.build/pd10-p0c-preflight.json` e `.build/pd10-p0c-1.0-build-57-<sha>.json` — proveniência pré e pós-archive.
- `/tmp/fm-v2-tf-archive.log`, `/tmp/fm-v2-tf-upload.log` — logs do archive e do export/upload.
- `.build/feedmine-v2.xcarchive`, `.build/tf-export/` — artefatos (ignorados por Git).
