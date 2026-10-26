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
