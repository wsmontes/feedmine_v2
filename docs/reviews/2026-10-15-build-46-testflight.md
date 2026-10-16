# Build 1.0 (46) no TestFlight interno — 2026-10-15

Envio de uma build interna instalável do app V2, depois da integração do lote de aplicação dos dois
relatórios de pesquisa e dos dois gates de dependência (`main` = `5f3c7473`).

## 1. Resultado

| Item | Valor |
|---|---|
| Envio | `PAIRING OK: TestFlight build 1.0 (46) = c99eff344d95a919126abf78587ef228c79848ba`, `Uploaded FeedMine`, exit **0** |
| Commit pareado | `c99eff344d95a919126abf78587ef228c79848ba` (branch `release/1.0-build.46`, cortada de `main` `5f3c7473`) |
| Tag | `ios/1.0-build.46-c99eff34`, anotada, **publicada** em `origin` |
| App | `com.feedmine.app`, versão **1.0**, build **46**, ASC app `6793279758` |
| Grupo | **WawaTesters** (interno) |
| Credencial | chave `H3U55Z9WZ7` + issuer `0e1bd229-1284-4916-91d2-7bf989859bcc`, **por ambiente** (o script não tem default; `ASC_KEY_PATH` default `~/.appstoreconnect/private_keys/AuthKey_H3U55Z9WZ7.p8`) |

O `--dry-run` rodou primeiro e passou inteiro (preflight P0C + archive + verificação do catálogo dentro
do archive), e só depois o envio real repetiu o mesmo caminho e fez o upload. Nenhuma tag foi criada
no dry-run.

## 2. Comandos executados

```sh
python3 scripts/bootstrap_catalog.py \
  --compiler /Users/<user>/Documents/GitHub/feedmine/scripts/build_catalog.py \
  --compiler-sha256 e3c9fcf21ee30ab7dfc282def733ba4838337bb83c95d4d234b2e8a3e9a48df5 \
  --identity-sha256 2a83b83356d757ab49cb22e6bd75dafd78888754b27f5e4bf32fab0d2f6ee578
cp build/catalog-bootstrap/{catalog.sqlite,catalog.manifest.json} FeedMineApp/FeedMineApp/Resources/
ASC_KEY_ID=<key> ASC_ISSUER_ID=<issuer> scripts/release-testflight.sh --dry-run
ASC_KEY_ID=<key> ASC_ISSUER_ID=<issuer> scripts/release-testflight.sh
git push origin ios/1.0-build.46-c99eff34
```

**Ambiente:** macOS arm64, Xcode 26.6, Python 3.12.13, compilador V1 do checkout
`feedmine@712a6ba9` (a referência auditada). Evidência do próprio gate: `.build/pd10-p0c-1.0-build-46-c99eff344d95.json`.

## 3. Catálogo embarcado

O staging em disco (de 11/10) foi **recusado** pelo preflight do PD10-P0C: o `provenance.json` dele não
tem `compiler.dependency` nem `compiler.gitCommit`, e `scripts/verify_catalog_release.py:113-115`
exige os dois. Regenerado com os **mesmos 118 OPMLs já verificados em disco** (0 baixados), a mesma
revisão pública 5 e o mesmo build-report (118 arquivos, 77.443 fontes, 6.450 nós, 117.993.472 bytes).

O par recompilado **difere em bytes** do que as builds ≤45 embarcaram, sob a mesma revisão pública:

| | builds ≤ 45 | build 46 |
|---|---|---|
| `catalog.sqlite` sha256 | `72f066227958b482f365c88dd58320e75bc9ade9268b4e2ddaac9173908ecf71` | `42e602341d18f47290b06615eb9d49a25a693e36f3e9a4c327bbecd83e923b66` |
| `catalog_version` | `1791736083355950` | `1792122546765159` |

`CATALOG.md` foi atualizado no mesmo commit. O archive contém exatamente o par de `Resources`
(o script verifica os bytes antes e depois de arquivar; os dois relatórios de verificação apontam o
mesmo sha256).

## 4. Achados levados ao arquiteto

**(a) Gap de migração do PD10-P0C — nenhum staging pré-P0C é reutilizável.** O portão de reuso compara
`old_compiler.get("dependency", {}).get("sha256") != identity["dependency"]["sha256"]`
(`scripts/bootstrap_catalog.py:377-381`). Num estado gravado antes do P0C esse campo não existe, então
`None != <sha>` → `return None` → **recompila**, mesmo com o sha do compilador idêntico ao registrado
(`e3c9fcf2…` nos dois). Isso contraria o intent declarado três linhas acima — *"must not trigger a
timestamped SQLite recompile"* (`:374-376`) — e o desenho (`:45-47`, *"an unnecessary rebuild would
mint a new .sqlite checksum for identical inputs"*). Consequência medida: um `.sqlite` novo para
insumos idênticos, e o `catalog_version`, que é relógio de parede, muda junto.

**(b) Efeito colateral esperado na atualização 45 → 46, por causa de (a).** O ponteiro ativo de uma
build ≤45 aponta para o **caminho do bundle** (`CatalogInstallation.swift:294`,
`pointer = CatalogPointer(… cataloguePath: catalogue.path …)` no ramo `if bundled`). Numa atualização,
esse caminho passa a conter os bytes novos enquanto o fingerprint guardado é o antigo, então
`verifiedSnapshot(for:)` (`:467-470`) re-hasheia, reprova e grava

> `active catalogue pointer or snapshot failed integrity verification` (outcome `deferred`, kind `recovery`)

(`:153-154`; `CatalogRevisionRecord.deferred` é documentado como *"Never a pass"*, `:39-40`). Em
seguida o app se recupera **pelo próprio bundle**, com `replacingUnusableActive: true`
(`:176-177` → `recoverBundled()` `:185-199` → `:193-194`), e registra
`restored the verified bundled snapshot after missing or unusable active` (`:196-197`). Ou seja: o
leitor vê o catálogo e o feed normalmente; o que aparece é **uma linha de ledger por tester** que não
significa corrupção — é consequência deste release, não de um defeito do app. Isso é novo: as builds
≤45 embarcaram bytes idênticos justamente porque o bootstrap reusava o staging.

## 5. Estado na Apple (consulta somente-leitura pela API)

Builds `VALID` na conta: 45 (`2026-10-15T08:18:00-07:00`), 44, 43, 42, 41, 40. Grupo interno:
`WawaTesters` (`isInternalGroup = true`).

**Build 46: `processingState = VALID`, `expired = false`, enviada em 2026-10-15T20:57:45-07:00, e
presente no grupo interno `WawaTesters`** (confirmado por
`/v1/builds?filter[betaGroups]=WawaTesters`, que devolve 41–46). A consulta é somente-leitura, por JWT
ES256 gerado da chave `H3U55Z9WZ7`; nenhum token foi guardado. Evidência sanitizada:
`docs/reviews/evidence/2026-10-15-build-46/testflight-status.jsonl`.

**Um upload não é instalação:** a instalação num aparelho de tester não foi observada nesta sessão.
O que está provado é que a build está `VALID` na Apple e oferecida ao grupo interno.

## 6. Limites deste registro

- **Não é certificação de release.** Os gates B01–B06 e o PD-10 ponta-a-ponta seguem como estavam;
  `B06` continua exigindo iPhone físico e `NOT_RUN`.
- O `--dry-run` e o envio usaram a mesma árvore e o mesmo preflight; o que difere é o upload e a tag.
- O par de catálogo embarcado mudou de bytes nesta build (seção 3) — quem compara hashes entre builds
  precisa considerar as duas colunas daquela tabela.
