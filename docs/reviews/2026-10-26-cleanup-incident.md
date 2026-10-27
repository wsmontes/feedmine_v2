# Incidente de limpeza — 2026-10-26

Revisão de 2026-10-26T14:37Z sobre o texto original deste arquivo (baseado no agregado
`/tmp/feedmine-cleanup-metadata-audit.json`). Fontes: `/tmp/feedmine-cleanup-forensic-audit.md`
(auditoria forense, somente leitura) e `/tmp/feedmine-cleanup-recovery.md` (verificação executada em
2026-10-26T14:33:12–14:37:32Z). O que segue substitui as afirmações do original que a medição
**corrigiu**; o histórico não é apagado, ele é datado.

## O erro real (com linha)

`/tmp/f1db.CfiKyZ` (116 MB) foi removido por `rm -rf` deliberado:

```
/tmp/feedmine-omp-final-integration/2026-10-26T06-45-00-395Z_01a176f4-….jsonl L778 (08:01:41Z)
rm -rf /tmp/omp-head-dd /tmp/f1db.CfiKyZ 2>/dev/null
```

Decisão, não digitação: 18min56s antes (L709, 07:41:36Z) a mesma sessão escrevera que os artefatos
de `/tmp` de outras sessões "belong to other agents — don't delete"; L712/L718 registram "free
other-session /tmp artifacts — forbidden". Duas sessões anteriores recusaram explicitamente apagar
esse diretório (`2026-10-25T02-19-19…/DiskCleanup.jsonl` L75/L81; `2026-10-25T02-26-26…jsonl` L412).
O erro de processo permanece: caminho não identificado no momento da exclusão.

## O que o original dava como desconhecido e agora está estabelecido

| Item | Original | Medido |
|---|---|---|
| criador | desconhecido; `create_temp: 0` | `mktemp -d /tmp/f1db.XXXXXX` + `tar -xzf` em
`<repo>/.build/omp-reader-controls-20261021/jobs/continuity-release-proof/sessions/2026-10-22T16-01-35-986Z_01a16458-….jsonl` L383/L385, 2026-10-22T16:48:29Z |
| conteúdo | desconhecido | extração de um **contentor de dados do simulador** (Release, jornada `continuity-release-proof`), copiado 16:48:02Z do device `00FED6E0-…`, container `A4888E45-…`; `Library/Application Support/FeedMine/runtime.sqlite` 22.011.904 B com `session_checkpoint`/`context_checkpoints`; 5 entradas de topo, 123,0 MB lógicos — não é cache de build |
| por que `create_temp: 0` era falso | — | artefato de **cobertura**: `allowed_roots()` do helper (`/tmp/feedmine_cleanup_metadata_audit.py:900-910`) varre `~/.omp/agent/sessions`, `~/.codex/sessions` e `/tmp/feedmine-omp-*`, e as sessões de *worker* ficam em `<repo>/.build/omp-*/jobs/<job>/sessions/*.jsonl` (150 arquivos, 800 MB), fora do escopo. O criador está exatamente ali |

## Recuperação histórica: destino, hash, integridade (executada)

Fonte sobrevivente: `.build/omp-reader-controls-20261021/jobs/continuity-release-proof/evidence/final-f1-db-20261022T164758Z/`
— `.build` é **gitignored**, não rastreado.

| Verificação | Resultado |
|---|---|
| `shasum -a 256 -c SHA256SUMS` | **OK, exit 0**; `app-data-container.tar.gz` = `094fa8a5df10713d43dc424047fc42520b4ac5834673400689815a60ce59df08`, 103.290.387 B, mtime 2026-10-22T16:48:01Z (= `captured_at_utc` − 1 s) |
| segurança do tar | **362 membros** (24 dirs, 338 arquivos), 122.963.333 B lógicos; **0** nome com `..`/absoluto, **0** symlink/hardlink, **0** nó especial |
| extração | destino novo `/tmp/feedmine-cleanup-recovered-20261026T143317Z` (0700): **362/362**, **0** divergência membro×disco (tamanho), inventário SHA-256 por arquivo em `/tmp/feedmine-cleanup-recovered-inventory.json` |
| SQLite (cópia separada `/tmp/feedmine-cleanup-sqlitecheck-20261026T143325Z`) | `integrity_check` **ok**, `quick_check` **ok**, `journal_mode=wal`, 32 tabelas, 31 migrações; `published_cards` 2.314, `origin_records`/`origin_revisions`/`source_memberships`/`selection_supply` 4.887, `media_candidates` 6.630, `feed_segments` 665, `acquisition_targets` 492, `session_checkpoint` 1, `context_checkpoints` 1, `feed_editions` 1, `reader_preferences` 1; identidade `MCMMetadataIdentifier=com.feedmine.app` |
| estado histórico datável | `feed_editions.created_at` 2026-10-22T16:44:29Z; `session_checkpoint.updated_at` 16:47:20.662Z (`anchor_placement`, `anchor_height=211.0`, `anchor_top_delta=0.0`); mtime do DB 16:47:30Z → 42 s antes da captura |
| fonte durável | `/tmp/feedmine-cleanup-preserved-20261026T143339Z` (0700, **103.409.287 B**): 5 arquivos copiados byte-idênticos com hash reconferido + inventário + `PRESERVED-README.txt` + `SHA256SUMS.preserved`. Origem **intacta** |

Nuance de verificação que importa: o `SHA256SUMS` copiado contém o caminho **absoluto** em `.build`.
Rodá-lo dentro do diretório preservado também dá exit 0, mas valida o **original**, não a cópia — os
dois casos são indistinguíveis sem o arquivo novo, `SHA256SUMS.preserved` (`app-data-container.tar.gz`
→ `094fa8a5…59df08`, conferido em 14:37:12Z, exit 0).

`roundtrip-diff.txt` tem **0 byte** e **não** serve de prova: arquivo vazio é o mesmo artefato que um
verificador que não escreveu nada (classe de falha silenciosa já vista neste projeto).

## Limites da recuperação — o que ela NÃO prova

1. **Não prova igualdade com o diretório apagado.** `/tmp/f1db.CfiKyZ` nunca foi hasheado e não há
   snapshot APFS local (`tmutil listlocalsnapshots /` devolve só o cabeçalho: zero snapshots). O hash
   verificável é o do arquivo-fonte de **hoje**, não o estado de 2026-10-22T16:48:01Z.
2. **Não prova que o diretório apagado continha somente essa extração.** A sessão criadora mostra
   `mktemp -d` + `tar -xzf`; ausência de escrita posterior não está provada.
3. **Não prova ausência de perda em outro lugar.** A varredura tem buracos nomeados: 3 arquivos
   >32 MiB fora do agregado (58 MB, 55 MB e um `__advisor.jsonl` de 52 MB), logs não-JSONL,
   `.xcresult`, histórico do Codex fora dos rollouts, `CoreSimulator.prev.log` (109 MB) não varrido,
   21 sessões excluídas por cwd de outro projeto e 2 sem cwd. Nenhuma ausência de achado nesses
   recortes prova ausência de referência.
4. **O device de origem não existe mais**: `00FED6E0-…` foi removido em **2026-10-24T17:53:36Z**
   (`Removing device … from set`), dois dias antes da exclusão do `/tmp`. O tar preservado é a
   **única** cópia conhecida daquela captura; não há banco vivo para diff.

## `simctl erase` do `FeedMine Reserve 1024` (39EA1733-…)

Comando (L724, 2026-10-26T07:42:45Z), encadeado com `;` — sem `set -e`, sem checagem de exit code:

```
xcrun simctl shutdown 39EA1733…; xcrun simctl erase 39EA1733…; sleep 15; df -k /
```

O erase **executou**, e o instante/mecanismo estão estabelecidos pelo log do CoreSimulator
(174.835.304 B, ativo; timestamps **locais**, máquina em UTC−7):

| Evento | Local (PDT) | UTC |
|---|---|---|
| `simctl shutdown` | Oct 26 00:42:45 | 2026-10-26T07:42:45Z |
| `erase_contents_and_settings` — **única** linha com "erase" no log inteiro | 00:42:46 | **07:42:46Z** |
| reboot pelo `xcodebuild` | 00:43:10–11 | 07:43:10Z |
| data containers recriados | 00:43:16–00:43:28 | 07:43:16–07:43:28Z (146 dos 148; +2 em 00:43:46 e 00:50:53) |

Consequência: **zero** contentor anterior a 07:42:46Z sobrevive — wipe integral da árvore de data
containers. O log registra o **pedido**, não uma linha de "erase concluído": a conclusão é inferida do
reboot + ausência de contentor pré-erase.

**Anomalia retirada (era misdating).** O texto anterior concluía, a partir de
`/tmp/feedmine-omp-reserve-review/2026-10-26T07-55-17-886Z_…jsonl` L90–L92 (07:56:51Z), que
"estado pré-erase ainda legível". Falso: a própria saída imprime o mtime do contentor `C258F592` —
00:43:46 local = **07:43:46Z**, ~1 min **depois** do erase; o `tmp/` lido em L95–L98 tem arquivos das
00:44–00:49 (53 run dirs, `feedmine-playback-*.wav`) e L99 registra "container mtime 00:43:46. So all
prior tmp is gone". Corroboração por epoch explícito (`os.stat`, não a string do log) nos arquivos que
o `reserve-review` copiou para `/tmp/feedmine-reserve-review/`: `84603E46.sqlite` e
`trace-84603E46.jsonl` = `1793000763` = **07:46:03Z**; `84603E46.sqlite-shm` = `1793001819` =
08:03:39Z. Nada ali é anterior a 07:42:46Z. A "hipótese de deleção em segundo plano" e a janela
"04:40–05:05 local" caem.

Preservado e verificável hoje: `ui-journey-runtime-000810` e `ui-journey-runtime-truepair`
(`runtime.sqlite`, `-wal`, `-shm`, `trace.jsonl`, `catalogue/`), `/tmp/reserve-evidence` (55,0 MB DB +
2,8 MB trace), `reserve-evidence2` (51,4 MB + 2,5 MB), `reserve-evidence3` (51,8 MB + 2,4 MB),
`/tmp/f12-review` (348 KB + 104 KB). Device mantido (`name=FeedMine Reserve 1024`, `state=1`
Shutdown) e recriável por nome; ele voltou a rodar `reserve-fix` (08:21) e `b03-validation` (08:54).

Perdido sem inventário: os demais contentores de app do device (r9/r10 etc.). Nenhuma sessão varrida
produziu inventário do device antes do erase; o único contentor citado nominalmente em evidência é
`C258F592-9EA6-40BF-A89A-8E5BFD42D903`, e ele é **pós**-erase. Os dados pré-erase foram destruídos e
não são reconstruíveis a partir de cópia conhecida. Para o futuro: `simctl listapps` + `du` por
contentor **antes** de qualquer erase é o único registro que serve.

## `simctl delete` do `iPhone 17` (D9A4DBB7-…)

Comando (L257–L258, 2026-10-26T06:50:07Z): `xcrun simctl delete D9A4DBB7-72F3-452E-8295-84BD9937C5D4`,
decidido como "stock não usado (shutdown)". O log confirma `Delete device request` +
`Removing device (D9A4DBB7…)` em **23:50:07 local = 06:50:07Z**. Device ausente hoje.

A premissa "não usado" está **refutada por fato**, não por GB. O log sobrevivente do próprio device —
`~/Library/Logs/CoreSimulator/D9A4DBB7-…/MobileInstallation/mobile_installation.log.0` (162.060 B,
mtime 04:23:52.829Z, sobrevive ao delete) — mostra, em horário local:

| Local (PDT) | UTC | Linha |
|---|---|---|
| Oct 25 21:17:57 | 04:17:57Z | `simctl[92262]: Boot requested: iPhone 17 (D9A4DBB7…)` |
| 21:18:12 → 21:20:09 | 04:18:12→04:20:09Z | `xcodebuild[92408]` attach / `device_bootstrap_lookup` |
| 21:20:01 | 04:20:01Z | `Install successful (…FeedMineUITests.xctrunner)` |
| 21:20:15 | 04:20:15Z | `Installing … ID=com.feedmine.development … Version=55, ShortVersion=1.0` → data containers `1749DEE7-…` e `4DB8F53A-…` |
| 21:23:51 | **04:23:51Z** | `Uninstall requested … for CoreSimulatorBridge (pid 93575)` → `MIUninstaller … Destroying container … Data/Application/4DB8F53A-…` e `Bundle/Application/189B37DA-…` |
| 21:23:52 | 04:23:52Z | tentativas para `.xctrunner` e `com.feedmine.app`: `No bundle container found` |

Três consequências medidas:

1. O device rodou UI da build 55 entre 21:18 e 21:23 local (04:18–04:23Z). O rótulo "stock não
   usado" estava errado.
2. O `simctl delete` das 06:50:07Z **não** destruiu dados da v55: o uninstall disparado pelo próprio
   `xcodebuild` (`CoreSimulatorBridge` pid 93575) já destruíra os data containers às **04:23:51Z**,
   2 h 26 min antes. O delete apagou **resíduo** (containers vazios, resto do device).
3. O `du` de 2,2 GB foi medido às 04:23:00Z, **51 s antes** desse uninstall: era o dado da própria
   run, e o `rm -rf "$D/data/Library/Caches/"*` ocorreu **antes** da remoção, não depois.

Reconstrução: `xcrun simctl create "iPhone 17" "iPhone 17" "iOS 26.5"` produz um stock equivalente
(UDID novo). Perdeu-se o resíduo pós-uninstall, não uma captura da build 55. Limite:
`mobile_installation.log.0` é rotativo e cobre até 04:23:52Z — não há garantia de que instalações
anteriores do mesmo device estejam nele.

## Sobre "nenhum dado alheio foi apagado"

Segue **não provado** como afirmação genérica, e agora com o motivo certo: a varredura por referências
tem os buracos listados acima e nenhum inventário foi feito antes das exclusões. O que está provado
é o que está acima: criador e conteúdo do `/tmp` (com limites), execução do erase e do delete nos
instantes UTC citados, o que sobreviveu em cópia e o que não tem cópia conhecida.

## Agregado de metadados (varredura original, mantido como registro)

- 321 arquivos candidatos; 296 sessões aceitas; 21 de outros projetos excluídas; 2 sem cwd; 3 acima do limite.
- 11 pares chamada/resultado correlacionados; 0 chamadas sem par; 13 resultados de referência órfãos.
- Referências: 24 a diretório temporário (7 sessões); 3 a `sim_iphone` e 3 a `sim_reserve` (2 sessões cada);
  1 `delete_temp` explícito; 1 referência de backup (hipótese).
- Contagens de **referências/arquivos**, não de ações distintas; classificação **heurística**;
  `first_seen` é global da varredura, **não** data de criação do temporário.
- `create_temp: 0` — **falso por cobertura**, ver a tabela acima.

## Auditoria bruta cruzada: bloqueada (mantido)

A varredura bruta de logs de outras sessões foi bloqueada pela revisão automática antes de sair ao
provedor; uma pergunta específica foi enviada e aguarda aprovação. Nada foi contornado. O trabalho de
código (D1/D2, par de catálogo, suítes) não depende dela.

## Próximos passos seguros

1. Manter artefatos: `/tmp/feedmine-cleanup-preserved-20261026T143339Z/`,
   `/tmp/feedmine-cleanup-recovered-20261026T143317Z/`, inventários, logs, result bundles, backups das jornadas.
2. Não apagar simuladores, bancos ou diretórios temporários desconhecidos; só caches próprios comprovados.
3. Antes de qualquer `erase`/`delete` de simulador: `simctl listapps` + `du` por contentor, e cópia do
   que importa para fora do device.
4. Exposição de conteúdo de outras sessões só com a autorização explícita pendente.

## Method notes (para não repetir o erro)

- Timestamps de `~/Library/Logs/CoreSimulator/CoreSimulator.log` são **locais**; cruzados com três
  eventos e com o JSONL das sessões antes de qualquer conclusão UTC.
- A presença de um arquivo de verificação vazio não é evidência de aprovação; um verificador que não
  escreve produz o mesmo artefato.
- Contagem de cobertura (`create_temp: 0`) só vale junto com os `allowed_roots` que a produziram.

## Cache de build de `/tmp/f12-ex2-dd`: a prova citada pelo F12 foi removida (registro adicional)

Segundo registro de perda, independente dos dois acima (`/tmp/f1db.CfiKyZ` e os simuladores). Fonte:
`/tmp/feedmine-owned-build-cache-reclamation.md` (executada por outra lane, 2026-10-26) e o que sobrou no próprio
diretório.

### O que foi removido

Quatro caminhos, todos saídas de compilação do DerivedData da lane `/tmp/feedmine-omp-f12-completion`
(`info.plist` do próprio DerivedData declara `WorkspacePath = …/feedmine_v2/FeedMineApp/FeedMineApp.xcodeproj`,
`LastAccessedDate = 2026-10-26T16:17:47Z`):

```
rm -rf /tmp/f12-ex2-dd/Build
rm -rf /tmp/f12-ex2-dd/ModuleCache.noindex
rm -rf /tmp/f12-ex2-dd/CompilationCache.noindex
rm -rf /tmp/f12-ex2-dd/SDKStatCaches.noindex
```

`rm_exit=0`; 748.324 KB removidos; disco livre `df -k /` 510.576 → 1.266.192 KB (**+755.616 KB ≈ +738 MiB**).
Não houve erro de execução. O erro é de **escopo**: `Build/Products` carregava uma prova que outro relatório citava.

### Impacto específico: uma prova citada, não um cache qualquer

`/tmp/feedmine-f12-completion.md:49-51` cita como prova anti-staleness o bundle de teste **compilado**:

```
/tmp/f12-ex2-dd/Build/Products/Debug-iphonesimulator/FeedMine.app/PlugIns/FeedMineAppTests.xctest/FeedMineAppTests
```

A alegação dependia de `strings` nesse binário mostrar a mensagem nova
(`enabling a source is a management act, not a navigation`), provando que o log de green2 vinha de compilação
**anterior** à edição. O binário vivia em `Build/Products` e foi removido junto com o cache. **Essa prova está
perdida**, e a alegação de staleness que dependia dela fica mais fraca.

### Preservado × perdido

|Item|KB|Estado|
|---|---|---|
|`Build/Products` (inclui `FeedMineAppTests.xctest`)|351.712|**perdido** — é a prova acima|
|`Build/Intermediates.noindex`; `ModuleCache.noindex` (197.528); `CompilationCache.noindex` (28); `SDKStatCaches.noindex` (1.508)|396.612|perdidos (cache de compilação, regenerável)|
|`SourcePackages`|403.632|**preservado** (checkout/artifacts SPM, regenerável só com rede)|
|`Logs/` (5 `xcactivitylog`, 2 `LogStoreManifest.plist`), `TestResults/metadata.db`, `info.plist`|152|**preservados**, hash antes == depois|
|`/tmp/f12b-*.xcresult` (6) e `/tmp/f12b-*.log` (7)|—|preservados, fora do DerivedData|

Hashes dos sobreviventes (SHA-256, conferidos antes e depois da remoção):

|Arquivo|SHA-256|
|---|---|
|`/tmp/f12-ex2-dd/info.plist`|`dbd7f61ee56374d5c3a67da2c7480b43700058038b44de78779f6ade72cd660c`|
|`Logs/Build/4EF72E75-….xcactivitylog`|`007a51c57a644c3c6e55a50753ddd8766de5ad06301f18c999ab858512bca494`|
|`Logs/Build/B6AC06F1-….xcactivitylog`|`d4c22057a400efa48c73697a31255ee19a4c05dba59157d06661f68ca445b71e`|
|`Logs/Build/C095AA41-….xcactivitylog`|`7d4510b787e4896e3485df673b3a486fb5450947e2b780c4281e585e0f5394c7`|
|`Logs/Build/LogStoreManifest.plist`|`11b4b5a138bb1eebf8a19313f2ae4c8d7aab35af813da0798fc85aadfd1e0fd2`|
|`Logs/Package/2A34ACE2-….xcactivitylog`|`55059365f9e554ec618b78420827f6c819ad8d2df72c5bc83b4570084dbee4ab`|
|`Logs/Package/81BB0D6F-….xcactivitylog`|`fbf80ff6803e760b94e82ca6b0d708ee7262ca96aa45330a1742ff485b09a44a`|
|`Logs/Package/BDB6691E-….xcactivitylog`|`e261fd30c3343caa4b66e827090299715c6123ff1b5f593166ff664f0c872389`|
|`Logs/Package/LogStoreManifest.plist`|`94240004a8f7c1627760b5679780fd0481ac1035c9d42c2b3688612b1ada562f`|
|`TestResults/metadata.db`|`c2e60bdccaeb3f0bb0762b2db7fd9c8a8d711af76ca8d1541c6215be564be542`|

Verificado nesta revisão: `/tmp/f12-ex2-dd/` contém apenas `Logs`, `SourcePackages`, `TestResults` e `info.plist`;
os 6 `.xcresult` e 7 `.log` de `/tmp/f12b-*` continuam no lugar.

### Limite: rebuild não recupera o binário histórico

Um `xcodebuild` novo produz um binário **novo**, não aquele objeto de 16:12Z. A prova que sobrevive é de outra
natureza e precisa ser lida como tal:

|Evidência sobrevivente|Local|SHA-256|
|---|---|---|
|Literal canônico no fonte|`FeedMineApp/FeedMineAppTests/CompositionTests.swift:5139` (era `:5009`)|—|
|Red, linhas antigas 5517/5006/5352|`/tmp/f12b-green2.log` (16:12:26Z)|`3d9b20f439a0a252b25f0c25a3d6163ac021d9152fab40eb3c70219c3afc5ccf`|
|Green após a edição, `Executed 4 tests, with 0 failures` (16:14:47Z)|`/tmp/f12b-green3.log`|`5ced363dd1c0f3d8e9e1aed888b203759a5a6766f20552128cd9a259509bf4c1`|
|Relatório F12|`/tmp/feedmine-f12-completion.md`|`e0d5c7cda13c2fdcc13403678ff223b23e9b9a585069b1430a8c238491643903`|

Ressalva medida: o hash de `CompositionTests.swift` registrado na tarefa de reclamação
(`64cf5d392af62e17bc2d19144886a51d9e353e9df1561297edc86c9ab293c15f`) **já não corresponde** ao arquivo — ele
recebeu nesta data uma regressão de contrato PD-5 (teste de ciclo de vida), e o hash atual é
`4f29baef8d2a58178b8ba3aff5be9d77ce9f1db42a216d218c9877b15885bc9c`. O literal citado continua presente (agora na
linha 5139). Na mesma sessão em que o hash foi tirado, o mtime do arquivo já era **posterior** a green3, então
mtime nunca serviu como prova de ordem; o que resta é o par de logs e os dois `.xcresult`.

Nada foi apagado nesta tarefa: nenhuma nova limpeza, nenhum simulador restaurado, nenhum log ou `xcresult`
removido. Disco no início da tarefa: 1.298.764 KB livres.
