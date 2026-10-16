#!/usr/bin/env bash
#
# device-journey.sh — uma jornada medida em um iPhone físico (app de DESENVOLVIMENTO do FeedMine V2).
#
# Responsabilidade:
#   Uma jornada física só é julgável pelo que o aparelho deixa para trás: o **console** do app — com a linha de
#   jornada ligada por `FEEDMINE_JOURNEY_CONSOLE=1` — e o **container** de dados (`runtime.sqlite` + `-wal`, que é
#   onde os dados de fato vivem). Este script instala o `.app`, lança com o console em arquivo por um tempo
#   limitado, puxa o container, dobra o WAL e imprime: procedência, censo (cartas por tipo de mídia, blobs e bytes
#   de mídia, fontes, alvos, rastro), série de quadros, série de jornada e linhas de erro.
#
# Isolamento:
#   Por padrão a jornada roda em um NAMESPACE novo (`--namespace auto`): o app Debug cria o diretório de dados sob
#   `Library/Application Support/FeedMine/<uuid>` e nada existente é lido, tocado ou apagado — a jornada nasce fria
#   e o censo é o **deste** run. `--namespace <uuid>` reusa um namespace; `--namespace none` usa o container
#   compartilhado do bundle de desenvolvimento (aí o censo mistura todo o histórico daquele container, e o script
#   diz isso).
#
# Não faz (e não faz por princípio):
#   Nunca desinstala, nunca apaga, nunca "erase". Recusa-se a tocar em `com.feedmine.app` — o TestFlight do dono,
#   com o container pessoal dele — tanto pelo `--bundle` quanto pelo `CFBundleIdentifier` de dentro do `.app`. Não
#   injeta gesto nenhum na tela. Uma etapa que falha vira `NOT_RUN` com o motivo, nunca um palpite; um uso errado
#   vira `REFUSED` antes de tocar no aparelho.
#
# Uso:
#   scripts/device-journey.sh --device <ID> --app <CAMINHO.app> [--seconds N] [--out DIR] [--bundle ID]
#                             [--namespace auto|<uuid>|none] [--env JSON] [--skip-install]
#   scripts/device-journey.sh --help
#
# Variáveis de ambiente equivalentes: DEVICE, APP, BUNDLE, OUT, SECONDS_RUN, NAMESPACE, LAUNCH_ENV.
#
# Saída: um relatório em stdout; os arquivos brutos em --out (console.log, container/…, install.log, …).
set -euo pipefail

DEVICE="${DEVICE:-}"
APP="${APP:-}"
BUNDLE="${BUNDLE:-com.feedmine.development}"
SECONDS_RUN="${SECONDS_RUN:-240}"
OUT="${OUT:-}"
LAUNCH_ENV="${LAUNCH_ENV:-}"
NAMESPACE="${NAMESPACE:-auto}"
SKIP_INSTALL="${SKIP_INSTALL:-0}"

readonly OWNER_BUNDLE="com.feedmine.app"
readonly SUPPORT="Library/Application Support/FeedMine"
readonly NAMESPACE_KEY="FEEDMINE_RUNTIME_NAMESPACE"

usage() {
    cat <<'EOF'
device-journey.sh — jornada medida em um iPhone físico (app de DESENVOLVIMENTO).

Uso:
  scripts/device-journey.sh --device <ID> --app <CAMINHO.app> [opções]

Obrigatórios:
  --device <ID>       Identificador do devicectl (UUID, UDID, ECID, serial, nome ou DNS).
  --app <CAMINHO.app> Bundle .app já construído. O caminho TEM de terminar em `.app`.

Opções:
  --seconds <N>       Duração da jornada com o app em primeiro plano (default: 240; 0 = só instalar/lançar/coletar).
  --out <DIR>         Onde ficam os artefatos brutos (default: /tmp/fm-journey-<UTC>).
  --bundle <ID>       Bundle id do app sob teste (default: com.feedmine.development).
  --namespace <N>     `auto` (default) = UUID novo por corrida: jornada fria, censo só deste run, nada existente é
                      tocado. `<uuid>` = reusa aquele namespace. `none` = container compartilhado do bundle (o
                      censo passa a incluir todo o histórico dele; o script avisa).
  --env <JSON>        Variáveis de ambiente do lançamento, em JSON. `FEEDMINE_JOURNEY_CONSOLE=1` é acrescentada se
                      você não a declarar; `--namespace` governa FEEDMINE_RUNTIME_NAMESPACE.
  --skip-install      Não instala; usa o que já está no aparelho.
  --help              Esta ajuda.

Recusa, sempre: com.feedmine.app (o app do dono). Nunca desinstala, nunca apaga, nunca dá `erase`.

Exemplo:
  scripts/device-journey.sh --device BBA4F656-A5EA-5D81-934E-E484ED71B8E2 \
      --app /tmp/fm-derived/Build/Products/Debug-iphoneos/FeedMine.app --seconds 300
EOF
}

step() { printf '\n=== %s\n' "$1"; }
refused() { printf 'REFUSED: %s\n' "$1" >&2; exit "${2:-2}"; }
not_run() { printf 'NOT_RUN: %s\n' "$1" >&2; exit "${2:-3}"; }

# O console é a única medição que existe mesmo quando a coleta do container falha (CoreDeviceError 7000 visto em
# 2026-10-16: o app escreveu a jornada e o caminho pedido não existia), então ele é analisado ANTES do container:
# uma medição que existe não pode ser perdida porque outra etapa falhou. Vive aqui, com os outros helpers, porque
# o bash só conhece uma função depois de executar a sua definição.
analyse_console() {
    step "console"
    python3 - "$OUT/console.log" <<'PY'
import re, sys

path = sys.argv[1]
lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
frame_re = re.compile(r"feedmine frames=(\d+) late=(\d+) bad=(\d+) severe=(\d+) worst_ms=([0-9.]+)")
journey_re = re.compile(r"feedmine journey (.*)$")

frames = []
for line in lines:
    match = frame_re.search(line)
    if match:
        frames.append(tuple(float(x) for x in match.groups()))

print(f"console_lines={len(lines)} frame_windows={len(frames)}")
if frames:
    print(f"frames_total={int(sum(f[0] for f in frames))} late={int(sum(f[1] for f in frames))} "
          f"bad={int(sum(f[2] for f in frames))} severe={int(sum(f[3] for f in frames))}")
    worst = sorted(frames, key=lambda f: -f[4])[:5]
    print("worst_windows=" + ", ".join(
        f"{int(f[4])}ms(late{int(f[1])}/bad{int(f[2])}/sev{int(f[3])})" for f in worst))
else:
    print("NOT_RUN: nenhuma linha 'feedmine frames=' — o app não chegou a medir quadros neste run")

journeys = [m.group(1) for m in (journey_re.search(line) for line in lines) if m]
print(f"journey_lines={len(journeys)}")
if journeys:
    # Os fatos, não 300 repetições deles: o que muda aparece como uma faixa de `t=`, e o que fica igual é dito uma
    # vez, com o `t=` em que começou e em que terminou. Uma jornada parada é lida em três linhas, não em trezentas.
    runs = []
    for entry in journeys:
        clock, _, rest = entry.partition(" ")
        if runs and runs[-1][0] == rest:
            runs[-1][2] = clock
            runs[-1][3] += 1
        else:
            runs.append([rest, clock, clock, 1])
    print(f"journey_changes={len(runs)}")
    for rest, first, last, count in runs:
        span = first if first == last else f"{first}..{last}"
        print(f"  {span} ({count}s): {rest}")
elif frames:
    print("NOT_RUN: a linha de jornada está ausente com o app medindo quadros — "
          "a chave FEEDMINE_JOURNEY_CONSOLE não chegou ao app")

others = [line for line in lines
          if "feedmine frames=" not in line and "feedmine journey " not in line and line.strip()]
suspect = [line for line in others
           if re.search(r"error|fail|fault|assert|fatal|crash|denied|timeout|unreachable|refused|reject",
                        line, re.IGNORECASE)]
print(f"non_telemetry_lines={len(others)} suspect_lines={len(suspect)}")
for line in suspect[:20]:
    print("  ! " + line)
if len(suspect) > 20:
    print(f"  ! ... +{len(suspect) - 20} linhas suspeitas (todas em {path})")
rest = [line for line in others if line not in suspect]
for line in rest[:10]:
    print("  | " + line)
if len(rest) > 10:
    print(f"  | ... +{len(rest) - 10} linhas (todas em {path})")
PY
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --device) DEVICE="${2:-}"; shift 2 ;;
        --app) APP="${2:-}"; shift 2 ;;
        --bundle) BUNDLE="${2:-}"; shift 2 ;;
        --seconds) SECONDS_RUN="${2:-}"; shift 2 ;;
        --out) OUT="${2:-}"; shift 2 ;;
        --namespace) NAMESPACE="${2:-}"; shift 2 ;;
        --env) LAUNCH_ENV="${2:-}"; shift 2 ;;
        --skip-install) SKIP_INSTALL=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'argumento desconhecido: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

# --- pré-voo: o que é recusado antes de tocar no aparelho --------------------------------
[[ -n "$DEVICE" ]] || refused "--device é obrigatório (ou DEVICE=...)"
[[ -n "$APP" ]] || refused "--app é obrigatório (ou APP=...)"
[[ "$BUNDLE" != "$OWNER_BUNDLE" ]] \
    || refused "--bundle $OWNER_BUNDLE é o app do dono (TestFlight, container pessoal): esta ferramenta nunca o toca"
[[ "$APP" == *.app ]] \
    || refused "--app precisa terminar em .app (o devicectl recusa outro caminho: CoreDeviceError 3002)"
[[ -d "$APP" ]] || refused "--app não existe: $APP"
[[ "$SECONDS_RUN" =~ ^[0-9]+$ ]] || refused "--seconds precisa ser um inteiro (recebido: $SECONDS_RUN)"
[[ "$SKIP_INSTALL" == 0 || "$SKIP_INSTALL" == 1 ]] \
    || refused "--skip-install é uma flag, não um valor (recebido: $SKIP_INSTALL)"

plist="$APP/Info.plist"
[[ -f "$plist" ]] || refused "$APP não tem Info.plist: não é um bundle construído"
app_bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"
[[ "$app_bundle" != "$OWNER_BUNDLE" ]] \
    || refused "recusado: este .app É o app do dono ($OWNER_BUNDLE); instalá-lo substituiria o TestFlight dele"
[[ "$app_bundle" == "$BUNDLE" ]] \
    || refused "o .app declara CFBundleIdentifier=$app_bundle, não $BUNDLE"

for cmd in xcrun sqlite3 python3 uuidgen; do
    command -v "$cmd" >/dev/null || refused "$cmd não está no PATH"
done

# 1 GB: puxar o container (mídia inclusive) e o checkpoint do WAL escrevem no disco local. Um run que morre por
# ENOSPC produz um censo vazio lido como produto vazio — a checagem é barata e evita esse erro.
free_kb="$(df -k / | awk 'NR==2 {print $4}')"
(( free_kb >= 1048576 )) \
    || refused "menos de 1 GB livre em / (${free_kb} KB): o censo pode sair vazio por disco, não por conteúdo"

xcrun devicectl list devices 2>/dev/null | grep -q -- "$DEVICE" \
    || not_run "o dispositivo $DEVICE não aparece em 'devicectl list devices'" 3

app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || echo '?')"
app_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || echo '?')"
app_sha="$(/usr/libexec/PlistBuddy -c 'Print :FeedmineGitSHA' "$plist" 2>/dev/null || echo '?')"
app_branch="$(/usr/libexec/PlistBuddy -c 'Print :FeedmineGitBranch' "$plist" 2>/dev/null || echo '?')"
devicectl_version="$(xcrun devicectl --version 2>/dev/null | tr '\n' ' ' || echo '?')"

# --- namespace e ambiente ---------------------------------------------------------------
# O app (Debug) só aceita um namespace quando ele é um UUID: qualquer outro valor é ignorado em silêncio e a
# jornada cairia no container compartilhado, com o censo apontando para o diretório errado. Por isso a validação.
case "$NAMESPACE" in
    auto) NS="$(uuidgen)" ;;
    none) NS="" ;;
    *) NS="$NAMESPACE" ;;
esac
if [[ -n "$NS" ]]; then
    [[ "$NS" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] \
        || refused "--namespace precisa ser um UUID, 'auto' ou 'none' (recebido: $NAMESPACE)"
    # O diretório é nomeado com a forma canônica do UUID — MAIÚSCULA —, não com o que foi digitado. Medido no
    # aparelho (2026-10-16): lançar com `FEEDMINE_RUNTIME_NAMESPACE=<uuid minúsculo>` cria
    # `Library/Application Support/FeedMine/<UUID MAIÚSCULO>`, e puxar o caminho minúsculo falha com
    # CoreDeviceError 7000 ("file node not found") — que se lê como "o app não escreveu nada" quando o app
    # escreveu tudo. A normalização é do instrumento, para o caminho do censo não depender do caixa digitada.
    NS="$(printf '%s' "$NS" | tr 'a-z' 'A-Z')"
fi

env_json="$(python3 - "$LAUNCH_ENV" "$NS" "$NAMESPACE_KEY" <<'PY'
import json, sys
raw, namespace, key = sys.argv[1].strip(), sys.argv[2], sys.argv[3]
env = json.loads(raw) if raw else {}
if not isinstance(env, dict):
    raise SystemExit("--env precisa ser um objeto JSON")
if namespace:
    declared = env.get(key)
    if declared not in (None, namespace):
        raise SystemExit(f"--env declara {key}={declared}, mas este run usa {namespace}: procedência ambígua")
    env[key] = namespace
else:
    if env.get(key):
        raise SystemExit(f"--env declara {key}={env[key]} com --namespace none: procedência ambígua")
    env.pop(key, None)
# A linha de jornada é o motivo de existir deste instrumento; quem quiser desligá-la declara 0 explicitamente.
env.setdefault("FEEDMINE_JOURNEY_CONSOLE", "1")
print(json.dumps(env, sort_keys=True))
PY
)" || refused "--env inválido ou em conflito com --namespace: $LAUNCH_ENV"

OUT="${OUT:-/tmp/fm-journey-$(date -u +%Y%m%dT%H%M%SZ)}"
# Os brutos de duas corridas no mesmo diretório se misturam em silêncio: os nomes fixos são sobrescritos, mas o que
# tem outro nome fica, e o censo passa a parecer ter vindo de uma corrida só. Medido em 2026-10-16, quando um
# diretório reusado trouxe três arquivos de mídia de uma jornada anterior para dentro da evidência nova.
if [[ -d "$OUT" ]] && [[ -n "$(ls -A "$OUT" 2>/dev/null)" ]]; then
    refused "--out $OUT já existe e não está vazio: use um diretório novo (ou apague-o) para não misturar duas jornadas"
fi
mkdir -p "$OUT" 2>/dev/null || refused "não foi possível criar $OUT"
DB="$OUT/container/$SUPPORT/${NS:+$NS/}runtime.sqlite"

step "proveniência"
cat <<EOF
device=$DEVICE
bundle=$BUNDLE
app=$APP
app_version=$app_version build=$app_build git=$app_sha branch=$app_branch
devicectl=$devicectl_version
out=$OUT
seconds=$SECONDS_RUN
namespace=${NS:-none (container compartilhado do bundle)}
env=$env_json
host_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

# --- instalação -------------------------------------------------------------------------
if [[ "$SKIP_INSTALL" != 1 ]]; then
    step "install"
    if ! xcrun devicectl device install app --device "$DEVICE" "$APP" >"$OUT/install.log" 2>&1; then
        sed -n '1,20p' "$OUT/install.log" >&2
        not_run "a instalação falhou (log: $OUT/install.log)" 4
    fi
    grep -E "installationURL|App installed" "$OUT/install.log" | sed -n '1,3p' || true
else
    step "install (pulado por --skip-install)"
fi

# --- lançamento com o console em arquivo -------------------------------------------------
step "launch (console em $OUT/console.log)"

# O container do bundle sob teste, dito pelo próprio devicectl: um bundle id existe uma vez só no aparelho, então
# este caminho identifica o processo do app sob teste sem ambiguidade. Casar pelo NOME do executável seria
# perigoso — o app do dono também é `FeedMine.app/FeedMine`, e terminá-lo por engano é exatamente o que esta
# ferramenta não faz.
app_url="$(xcrun devicectl device info apps --device "$DEVICE" \
    --json-output "$OUT/apps-installed.json" >/dev/null 2>&1 && \
    python3 - "$OUT/apps-installed.json" "$BUNDLE" <<'PY' || true
import json, sys
try:
    document = json.load(open(sys.argv[1]))
except Exception:
    raise SystemExit(1)
for app in (document.get("result") or {}).get("apps") or []:
    if app.get("bundleIdentifier") == sys.argv[2]:
        url = app.get("url")
        if isinstance(url, str) and url:
            print(url)
            raise SystemExit(0)
raise SystemExit(1)
PY
)"
[[ -n "$app_url" ]] \
    || not_run "não foi possível identificar o container de $BUNDLE em 'device info apps'" 5
printf 'container do app=%s\n' "$app_url"

launch_pid=""
app_pid=""
cleanup() {
    [[ -n "$launch_pid" ]] && kill "$launch_pid" 2>/dev/null || true
    # Um run interrompido não deixa o app em primeiro plano no telefone do dono: o pid é o do app sob teste, nunca
    # o de outro app (resolvido pelo prefixo do container dele).
    [[ -n "$app_pid" ]] && xcrun devicectl device process terminate --device "$DEVICE" --pid "$app_pid" \
        >/dev/null 2>&1 || true
}
trap cleanup EXIT

launch_epoch="$(date -u +%s)"
# `terminate` do devicectl só aceita --pid (medido); `--terminate-existing` encerra instâncias anteriores DESTE
# bundle antes de lançar, e é o caminho que existe para não precisar de um terminate por bundle id.
xcrun devicectl device process launch --device "$DEVICE" --console --terminate-existing \
    --environment-variables "$env_json" "$BUNDLE" >"$OUT/console.log" 2>&1 &
launch_pid=$!

for _ in $(seq 1 15); do
    sleep 3
    xcrun devicectl device info processes --device "$DEVICE" \
        --json-output "$OUT/processes.json" >/dev/null 2>&1 || true
    app_pid="$(python3 - "$OUT/processes.json" "$app_url" <<'PY' 2>/dev/null || true
import json, sys
try:
    document = json.load(open(sys.argv[1]))
except Exception:
    raise SystemExit(0)
prefix = sys.argv[2]
for process in (document.get("result") or {}).get("runningProcesses") or []:
    executable = process.get("executable") or ""
    if executable.startswith(prefix) and isinstance(process.get("processIdentifier"), int):
        print(process["processIdentifier"])
        raise SystemExit(0)
PY
)"
    [[ -n "$app_pid" ]] && break
done
if [[ -z "$app_pid" ]]; then
    not_run "o app não apareceu entre os processos do aparelho em ~45 s (console: $OUT/console.log)" 5
fi
printf 'pid no aparelho=%s\n' "$app_pid"

remaining=$(( SECONDS_RUN - ($(date -u +%s) - launch_epoch) ))
(( remaining > 0 )) || remaining=0
printf 'jornada por %ss\n' "$remaining"
sleep "$remaining"

step "terminate"
if xcrun devicectl device process terminate --device "$DEVICE" --pid "$app_pid" >"$OUT/terminate.log" 2>&1; then
    sed -n '1,3p' "$OUT/terminate.log"
else
    printf 'aviso: terminate falhou; o console segue até o app sair (log: %s)\n' "$OUT/terminate.log" >&2
fi
app_pid=""
wait "$launch_pid" || true
launch_pid=""
printf 'console: %s linhas\n' "$(wc -l <"$OUT/console.log" | tr -d ' ')"

# O console é analisado antes do container, de propósito: ver a nota de `analyse_console`.
analyse_console

# --- container --------------------------------------------------------------------------
# O container inteiro é puxado de uma vez, com a forma que ele tem no aparelho (precedente do modo device do
# bench): `runtime.sqlite` chega junto com o `-wal`, que é onde os dados de fato estão (medido: 4 KB no principal
# e 832 KB no WAL), e a mídia baixada chega junto com os bytes reais — sem inventário remoto a interpretar.
step "container"
dest_rel="$SUPPORT/${NS:+$NS}"
mkdir -p "$OUT/container/$dest_rel"
if xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
    --domain-identifier "$BUNDLE" --source "$dest_rel" --destination "$OUT/container/$dest_rel" \
    >"$OUT/container-copy.log" 2>&1; then
    printf 'puxado: %s\n' "$dest_rel"
else
    # O erro 7000 do CoreDevice ("file node not found") é indistinguível de "o app não escreveu nada". Dizer o que
    # o container REALMENTE tem é o que separa as duas coisas — foi assim que o caminho em CAIXA ALTA do namespace
    # apareceu (2026-10-16).
    printf 'NOT_RUN: não foi possível copiar %s do container de %s\n' "$dest_rel" "$BUNDLE" >&2
    printf 'conteúdo real de %s no aparelho:\n' "$SUPPORT" >&2
    xcrun devicectl device info files --device "$DEVICE" --domain-type appDataContainer \
        --domain-identifier "$BUNDLE" --subdirectory "$SUPPORT" --no-recurse 2>&1 | sed -n '1,20p' >&2 || true
    sed -n '1,10p' "$OUT/container-copy.log" >&2
    not_run "log: $OUT/container-copy.log" 6
fi
[[ -f "$DB" ]] || not_run "o container copiado não tem $DB: a jornada não escreveu banco nenhum" 6
printf 'runtime.sqlite=%s bytes\n' "$(wc -c <"$DB" | tr -d ' ')"

if [[ -f "$DB-wal" ]]; then
    # Sem dobrar o WAL, o censo diz "vazio" com 40 cartas na tela — o erro mais fácil de cometer aqui. O checkpoint
    # é feito na CÓPIA; o arquivo do aparelho não é tocado.
    sqlite3 "$DB" "pragma wal_checkpoint(TRUNCATE)" >/dev/null \
        || not_run "o checkpoint do WAL falhou em $DB" 6
    printf 'wal_checkpoint: TRUNCATE em %s bytes\n' "$(wc -c <"$DB-wal" | tr -d ' ')"
fi

# --- censo ------------------------------------------------------------------------------
step "censo (cartas, fontes, alvos, mídia)"
if ! sqlite3 "$DB" "select count(*) from published_cards" >/dev/null 2>&1; then
    not_run "o runtime.sqlite copiado não tem o esquema esperado (só migrações?)" 6
fi

q() { sqlite3 -header -column "$DB" "$1"; }
qraw() { sqlite3 "$DB" "$1"; }

echo "-- edições e segmentos (all = o container inteiro; run = criado depois do launch)"
q "select count(*) as editions_all,
          (select count(*) from feed_editions where created_at >= $launch_epoch) as editions_run,
          min(created_at) as first_edition_epoch
   from feed_editions"
first_run="$(qraw "select coalesce(min(created_at), 0) from feed_editions where created_at >= $launch_epoch")"
if python3 -c "import sys; sys.exit(0 if float('$first_run') > 0 else 1)"; then
    printf 'time_to_first_edition_s=%s (relógio do host, contra launch_epoch=%s)\n' \
        "$(python3 -c "print(f'{float('$first_run') - $launch_epoch:.1f}')")" "$launch_epoch"
else
    printf 'time_to_first_edition_s=NOT_RUN (nenhuma edição criada depois do launch)\n'
fi
q "select count(*) as segments_all,
          (select count(*) from feed_segments where created_at >= $launch_epoch) as segments_run
   from feed_segments"

echo "-- cartas por tipo de mídia (all = histórico do container; run = publicadas nesta jornada)"
q "select c.render_layout, count(*) as cards_all, sum(c.media_key is not null) as with_media_key_all
   from published_cards c group by c.render_layout order by c.render_layout"
q "select c.render_layout, count(*) as cards_run, sum(c.media_key is not null) as with_media_key_run
   from published_cards c join feed_segments s on s.id = c.segment_id
   where s.created_at >= $launch_epoch
   group by c.render_layout order by c.render_layout"

echo "-- alternância de fontes na ordem em que o leitor percorre (PD-4: tem de ser 0 pares)"
q "with ordered as (
     select s.ordinal as seg, c.ordinal as ord, c.source_id as src
     from published_cards c join feed_segments s on s.id = c.segment_id
   ), pairs as (
     select src, lag(src) over (order by seg, ord) as prev from ordered
   )
   select count(*) as adjacent_same_source_pairs_all from pairs where prev is not null and prev = src"
q "with ordered as (
     select s.ordinal as seg, c.ordinal as ord, c.source_id as src
     from published_cards c join feed_segments s on s.id = c.segment_id
     where s.created_at >= $launch_epoch
   ), pairs as (
     select src, lag(src) over (order by seg, ord) as prev from ordered
   )
   select count(*) as adjacent_same_source_pairs_run from pairs where prev is not null and prev = src"

echo "-- fontes"
q "select count(distinct c.source_id) as publishing_sources_all from published_cards c"
q "select count(distinct c.source_id) as publishing_sources_run
   from published_cards c join feed_segments s on s.id = c.segment_id
   where s.created_at >= $launch_epoch"
q "select count(distinct object_namespace) as source_namespaces, count(*) as admitted_items from origin_records"
q "select state, count(*) as targets from acquisition_targets group by state order by state"
q "select connector_kind, count(*) as targets from acquisition_targets group by connector_kind order by connector_kind"

echo "-- candidatos de mídia que as fontes declararam"
q "select count(*) as candidates, count(distinct origin_revision_id) as revisions,
          sum(declared_pixel_width is not null) as with_declared_size
   from media_candidates"

echo "-- quem publicou (as que mais contribuíram, histórico do container)"
q "select coalesce(source_display_name,'(sem nome)') as source, count(*) as cards
   from published_cards group by source_id
   order by cards desc, source limit 8"

echo "-- mídia localmente disponível (bytes reais no container puxado)"
if [[ -d "$OUT/container/$dest_rel/Media" ]]; then
    python3 - "$OUT/container/$dest_rel/Media" <<'PY'
import os, sys
root = sys.argv[1]
blobs = []
for base, _, names in os.walk(root):
    for name in names:
        path = os.path.join(base, name)
        if os.path.isfile(path):
            blobs.append((os.path.getsize(path), os.path.splitext(name)[1] or "(sem extensão)"))
total = sum(size for size, _ in blobs)
kinds = {}
for size, ext in blobs:
    entry = kinds.setdefault(ext, [0, 0])
    entry[0] += 1
    entry[1] += size
print(f"media_blobs={len(blobs)} media_bytes={total} media_mb={total / 1048576:.1f}")
for ext, (count, size) in sorted(kinds.items(), key=lambda item: -item[1][1]):
    print(f"  {ext}: {count} blobs, {size} bytes")
PY
else
    printf 'NOT_RUN: nenhuma mídia em Media/ do container puxado (nada foi baixado nesta jornada)\n'
fi

echo "-- rastro da F05 (trace.jsonl)"
trace="$OUT/container/$dest_rel/trace.jsonl"
if [[ -f "$trace" ]]; then
    python3 - "$trace" <<'PY'
import collections, json, sys
path = sys.argv[1]
lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
events = collections.Counter()
for line in lines:
    try:
        events[json.loads(line).get("event", "?")] += 1
    except Exception:
        events["(ilegível)"] += 1
print(f"trace_lines={len(lines)} trace_events={len(events)}")
for event, count in events.most_common(15):
    print(f"  {count:6d}  {event}")
PY
else
    printf 'NOT_RUN: sem trace.jsonl no container puxado\n'
fi

# --- estado final e honestidade ---------------------------------------------------------
step "estado final"
xcrun devicectl device info processes --device "$DEVICE" \
    --json-output "$OUT/processes-end.json" >/dev/null 2>&1 || true
python3 - "$OUT/processes-end.json" "$app_url" "$BUNDLE" <<'PY'
import json, sys
try:
    document = json.load(open(sys.argv[1]))
except Exception:
    print("processos: NOT_RUN (não foi possível listar)")
    raise SystemExit(0)
left = [p for p in (document.get("result") or {}).get("runningProcesses") or []
        if (p.get("executable") or "").startswith(sys.argv[2])]
print(f"processos_restantes_do_app_sob_teste={len(left)}  (bundle {sys.argv[3]})")
PY

xcrun devicectl device info apps --device "$DEVICE" --json-output "$OUT/apps.json" >/dev/null 2>&1 || true
python3 - "$OUT/apps.json" <<'PY'
import json, sys
try:
    document = json.load(open(sys.argv[1]))
except Exception:
    print("app_do_dono: NOT_RUN (não foi possível listar os apps instalados)")
    raise SystemExit(0)
installed = {"com.feedmine.app": False, "com.feedmine.development": False}
for app in (document.get("result") or {}).get("apps") or []:
    if app.get("bundleIdentifier") in installed:
        installed[app["bundleIdentifier"]] = True
for bundle, present in installed.items():
    print(f"instalado[{bundle}]={'sim' if present else 'não'}")
PY

step "artefatos"
printf 'todos os brutos em: %s\n' "$OUT"
