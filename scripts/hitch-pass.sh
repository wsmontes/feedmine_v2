#!/usr/bin/env bash
#
# hitch-pass.sh — a corrida física que persiste o que a corrida de 2026-10-16 perdeu: o **console**.
#
# Por que existe
# --------------
# A passagem da build 48 pelo iPhone mediu engasgos reais (`docs/reviews/2026-10-16-build-48-aparelho-e-publicacao.md`
# §2.2, §6) e **não** deixou a correlação: a corrida dirigida por `xcodebuild test` no aparelho não persiste o
# console do app (medido: `/tmp/int48-physical-authorized.log` com 725.786 bytes e **zero** linhas `feedmine`), e
# uma tentativa por `devicectl --console` não foi guardada em arquivo (§3). Sem console não há linha de jornada nem
# série por segundo; sem isso, "o que estava acontecendo no segundo do travamento" não existe.
#
# O que esta corrida faz, em ordem
# --------------------------------
#   1. pré-voo: recusa `com.feedmine.app`, exige dispositivo, exige espaço em disco, exige diretório de saída novo;
#   2. build Debug do candidato para `iphoneos` (a árvore em que este script vive) e leitura da identidade do `.app`;
#   3. **fase A — jornada medida pelo `scripts/device-journey.sh`** (reusado, não reescrito): instala, lança com
#      `FEEDMINE_JOURNEY_CONSOLE=1` + `FEEDMINE_TRACE_CAPTURE=1` e `--console`, persiste `console.log`, puxa o
#      contêiner, dobra o WAL e imprime o censo;
#   4. **fase B — a jornada de rolagem no aparelho** (`-only-testing:FeedMineUITests/FluidityJourneyUITests`), com o
#      log inteiro em arquivo (`journey-test.log`), o result bundle (`journey.xcresult`) e o **syslog do aparelho**
#      capturado durante a corrida (`console-journey.log` por `idevicesyslog`) — porque o app fala duas línguas: o
#      `NSLog` (`feedmine frames=`, `feedmine journey`) chega por `devicectl --console`, e o `Logger`
#      (`[composition] installed cards=…`, `viewport forwarded …`, `Runway opportunity completed …`) **só** aparece
#      no log unificado do sistema;
#   5. coleta do contêiner inteiro depois da fase B (todos os namespaces, para pegar o namespace aleatório que o
#      teste cria), `wal_checkpoint(TRUNCATE)` nas cópias, censo de namespaces;
#   6. imprime o caminho de **cada** bruto e o comando de junção sugerido.
#
# O que ele não faz, por princípio
# --------------------------------
#   Nunca instala, lança, termina ou desinstala `com.feedmine.app` (o TestFlight do dono). Recusa-se a isso por
#   `--bundle` e pelo `CFBundleIdentifier` de dentro do `.app`, antes de tocar no aparelho. Não pede senha, não
#   liga Developer Mode, não reinicia, não apaga nada do aparelho e não apaga o app de desenvolvimento. Não declara
#   PASS de fluidez: ele mede e diz onde ficaram os brutos. Nenhum veredito de gate sai daqui.
#
# Uso
# ---
#   scripts/hitch-pass.sh --device <id-devicectl> [--udid <UDID-do-xcodebuild>] [--seconds N]
#                         [--out DIR] [--skip-build] [--app CAMINHO.app] [--derived-data DIR]
#                         [--skip-journey] [--skip-standalone] [--no-syslog] [--audit] [--build-only]
#   scripts/hitch-pass.sh --audit        # prova, sem tocar no aparelho, que o script não toca em com.feedmine.app
#   scripts/hitch-pass.sh --build-only   # compila o Debug iphoneos e sai: NENHUM comando de aparelho é executado
#
# `--build-only` existe para deixar a corrida armada sem tocar no telefone do dono (o build é a parte lenta e não
# precisa de aparelho). O GO então reusa o `.app` com `--skip-build --app … --derived-data …` e nenhum byte é
# recompilado.
#
# Exit: 0 a corrida rodou (mesmo que alguma fase declare NOT_RUN, o que fica dito no fim); 2 uso recusado antes de
# tocar no aparelho; 3 dispositivo ausente; 4 build; 5 instalação/lançamento; 6 coleta do contêiner.
set -euo pipefail

DEVICE="${DEVICE:-BBA4F656-A5EA-5D81-934E-E484ED71B8E2}"       # id do devicectl
UDID="${UDID:-00008110-00067D861486201E}"                       # id do xcodebuild (-destination id=…)
BUNDLE="${BUNDLE:-com.feedmine.development}"
SECONDS_RUN="${SECONDS_RUN:-90}"
OUT="${OUT:-}"
SKIP_BUILD="${SKIP_BUILD:-0}"
SKIP_JOURNEY="${SKIP_JOURNEY:-0}"
SKIP_STANDALONE="${SKIP_STANDALONE:-0}"
NO_SYSLOG="${NO_SYSLOG:-0}"
APP_OVERRIDE="${APP_OVERRIDE:-}"
DERIVED_OVERRIDE="${DERIVED_OVERRIDE:-}"
BUILD_ONLY="${BUILD_ONLY:-0}"
AUDIT=0

readonly OWNER_BUNDLE="com.feedmine.app"
readonly SUPPORT="Library/Application Support/FeedMine"
readonly PROJECT="FeedMineApp/FeedMineApp.xcodeproj"
readonly SCHEME="FeedMine"
readonly JOURNEY_TEST="FeedMineUITests/FluidityJourneyUITests"
readonly MIN_FREE_KB=2097152        # 2 GB: abaixo disto o trabalho para (regra da frente)

step() { printf '\n=== %s\n' "$1"; }
refused() { printf 'REFUSED: %s\n' "$1" >&2; exit 2; }
not_run() { printf 'NOT_RUN: %s\n' "$1" >&2; exit "${2:-3}"; }
warn() { printf 'AVISO: %s\n' "$1" >&2; }

# A prova, mecânica e sem aparelho, de que este script não toca no app do dono: onde o bundle aparece, onde um verbo
# destrutivo aparece e quais comandos escrevem no aparelho. Roda com `--audit`, sem tocar em nada, e o relatório cita
# a saída. A auditoria **não audita a si mesma**: as linhas desta função ficam fora da varredura (senão o padrão
# procurado se encontra e a prova se anula).
audit_self() {
    local self="$0"
    printf '=== prova, sem tocar no aparelho, de que esta corrida não toca em %s\n' "$OWNER_BUNDLE"
    audit_file "$self" yes
    if [[ -f scripts/device-journey.sh ]]; then
        printf '\n=== o instrumento que a fase A reusa, auditado do mesmo jeito\n'
        audit_file scripts/device-journey.sh no
    fi
    printf '\n=== a terceira perna: o .app construído é conferido pelo CFBundleIdentifier antes de instalar\n'
    grep -n 'app_bundle' "$self" | sed -n '1,8p'
    printf '\nnenhuma linha acima instala, lança, termina ou desinstala %s.\n' "$OWNER_BUNDLE"
    return 0
}

# Auditoria de um arquivo. Quando `skip_self` é "yes", as linhas da própria função `audit_file` ficam fora da
# varredura — senão o padrão procurado se encontra e a prova se anula (foi o que aconteceu na primeira versão).
audit_file() {
    local target="$1" skip_self="${2:-no}" start end
    start=""; end=""
    if [[ "$skip_self" == "yes" ]]; then
        start="$(grep -n '^audit_file() {' "$target" | cut -d: -f1 || true)"
        if [[ -n "$start" ]]; then
            end="$(awk -v s="$start" 'NR >= s && /^\}/ {print NR; exit}' "$target" || true)"
        fi
    fi
    outside() {
        if [[ -z "$start" ]]; then
            cat
        else
            awk -F: -v s="$start" -v e="${end:-$start}" '$1 < s || $1 > e'
        fi
    }
    printf '%s\n' "-- $target: onde o bundle do dono aparece"
    grep -n -- "$OWNER_BUNDLE" "$target" | outside || true
    printf '%s\n' "-- $target: comandos que de fato apagam/desinstalam/reiniciam (comentário não executa e fica fora)"
    local offenders
    # A varredura procura **comandos**, não a palavra solta: um comentário ou o texto de ajuda que diz "nunca
    # desinstala" não é um comando, e uma varredura por palavra toma os dois por ofensa (medido na primeira versão
    # desta auditoria, que acusou a própria prosa de `scripts/device-journey.sh`).
    offenders="$(grep -nEi 'devicectl +(device +)?(uninstall|erase)|simctl +(device +)?(erase|uninstall|delete)|(^|[^a-zA-Z-])rm +-[a-zA-Z]*[rf]' "$target" \
        | grep -vE '^[0-9]+:[[:space:]]*#' | outside || true)"
    if [[ -n "$offenders" ]]; then
        printf '%s\n' "$offenders"
        printf 'REFUSED: verbo destrutivo presente em %s\n' "$target" >&2
        return 2
    fi
    printf '   (nenhum)\n'
    printf '%s\n' "-- $target: comandos que falam com o aparelho (todos usam \$BUNDLE/\$APP, nunca o bundle do dono)"
    grep -nE 'xcrun devicectl device|xcrun xcodebuild|xcodebuild ' "$target" | outside || true
    return 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --device) DEVICE="$2"; shift 2 ;;
        --udid) UDID="$2"; shift 2 ;;
        --bundle) BUNDLE="$2"; shift 2 ;;
        --seconds) SECONDS_RUN="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --app) APP_OVERRIDE="$2"; shift 2 ;;
        --derived-data) DERIVED_OVERRIDE="$2"; shift 2 ;;
        --build-only) BUILD_ONLY=1; shift ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        --skip-journey) SKIP_JOURNEY=1; shift ;;
        --skip-standalone) SKIP_STANDALONE=1; shift ;;
        --no-syslog) NO_SYSLOG=1; shift ;;
        --audit) AUDIT=1; shift ;;
        --help) sed -n '1,45p' "$0"; exit 0 ;;
        *) refused "opção desconhecida: $1 (use --help)" ;;
    esac
done

if (( AUDIT )); then
    audit_self
    exit $?
fi

# --- pré-voo (nada de aparelho antes disto) ----------------------------------------------
[[ "$BUNDLE" != "$OWNER_BUNDLE" ]] \
    || refused "--bundle $OWNER_BUNDLE é o app do dono (TestFlight, container pessoal): esta ferramenta nunca o toca"
[[ "$SECONDS_RUN" =~ ^[0-9]+$ ]] || refused "--seconds precisa ser um inteiro (recebido: $SECONDS_RUN)"
[[ -f "$PROJECT/project.pbxproj" ]] || refused "não achei $PROJECT — rode este script da raiz da árvore de trabalho"
[[ -f scripts/device-journey.sh ]] \
    || refused "scripts/device-journey.sh não está nesta árvore: a fase A reusa aquele instrumento, não o reescreve"
[[ -f "FeedMineApp/FeedMineAppTests/FluidityJourneyUITests.swift" ]] \
    || refused "FeedMineApp/FeedMineAppTests/FluidityJourneyUITests.swift não está nesta árvore: sem ele não há jornada de rolagem"
# `catalog.sqlite` é **gitignored** (`.gitignore:20`) e o build o empacota como recurso: uma árvore nova (worktree)
# não o tem, e o `xcodebuild` falha em `CpResource` com «The file "catalog.sqlite" couldn't be opened because there is
# no such file» — medido nesta frente em 2026-10-16, num build de 150 s desperdiçado. É melhor recusar antes.
if (( SKIP_BUILD == 0 )); then
    [[ -f "FeedMineApp/FeedMineApp/Resources/catalog.sqlite" ]] \
        || refused "falta FeedMineApp/FeedMineApp/Resources/catalog.sqlite (gitignored, exigido pelo build): copie da árvore principal, ex.: cp ../feedmine_v2/FeedMineApp/FeedMineApp/Resources/catalog.sqlite FeedMineApp/FeedMineApp/Resources/"
fi
# O alvo de teste copia `../../bench/corpus/profiles.json` como recurso (única referência a `bench/corpus/` no
# `project.pbxproj`). `bench/corpus/` é gitignored (`.gitignore:32`), então uma worktree nova não o tem e a fase B
# morre em `CpResource` **antes** de rodar qualquer teste — medido nesta frente em 2026-10-16: `xcodebuild test`
# exit 65 com 2 falhas, e nenhum teste executado. Recusar antes custa zero.
if (( SKIP_JOURNEY == 0 )); then
    [[ -f "bench/corpus/profiles.json" ]] \
        || refused "falta bench/corpus/profiles.json (gitignored, recurso do alvo FeedMineUITests): copie da árvore principal, ex.: cp ../feedmine_v2/bench/corpus/profiles.json bench/corpus/"
fi

for cmd in xcrun xcodebuild python3 uuidgen sqlite3 awk; do
    command -v "$cmd" >/dev/null || refused "$cmd não está no PATH"
done

OUT="${OUT:-/tmp/fm-hitch-pass-$(date -u +%Y%m%dT%H%M%SZ)}"
if [[ -d "$OUT" ]] && [[ -n "$(ls -A "$OUT" 2>/dev/null)" ]]; then
    refused "--out $OUT já existe e não está vazio: duas corridas no mesmo diretório se misturam em silêncio"
fi

free_kb="$(df -k / | awk 'NR==2 {print $4}')"
(( free_kb >= MIN_FREE_KB )) \
    || refused "menos de 2 GB livre em / (${free_kb} KB): um build Debug iphoneos mais o contêiner não cabem, e um run que morre por ENOSPC produz medida vazia lida como produto vazio"
printf 'disco livre em /: %s KB\n' "$free_kb"

if (( BUILD_ONLY == 0 )); then
    # O aparelho desaparece do `devicectl` por alguns segundos quando o USB re-enumera — medido nesta frente em
    # 2026-10-16, entre a fase A e a fase B, com `xcdevice` e `idevicesyslog` respondendo segundos depois. Uma espera
    # limitada e **impressa** não é contorno: é não queimar a janela do dono por um hiccup de 5 s. Se o aparelho não
    # voltar em ~1 min, o pass sai com NOT_RUN e diz por quê.
    device_seen=0
    for attempt in $(seq 1 7); do
        if xcrun devicectl list devices 2>/dev/null | grep -q -- "$DEVICE"; then
            device_seen=1
            printf 'dispositivo %s presente (tentativa %s)\n' "$DEVICE" "$attempt"
            break
        fi
        printf 'tentativa %s/7: %s ainda não aparece em "devicectl list devices"\n' "$attempt" "$DEVICE"
        sleep 10
    done
    (( device_seen == 1 )) \
        || not_run "o dispositivo $DEVICE não apareceu em 'devicectl list devices' em ~1 min" 3
fi

mkdir -p "$OUT" 2>/dev/null || refused "não foi possível criar $OUT"
step "proveniência"
cat <<EOF
device=$DEVICE  udid=$UDID
bundle=$BUNDLE (o app do dono, $OWNER_BUNDLE, nunca é tocado)
out=$OUT
seconds=$SECONDS_RUN
git=$(git rev-parse HEAD 2>/dev/null || echo '?') branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')
git_dirty=$(git status --porcelain | wc -l | tr -d ' ') arquivos_sujos
xcode=$(xcodebuild -version 2>/dev/null | head -1 || echo '?')
devicectl=$(xcrun devicectl --version 2>/dev/null | tr '\n' ' ' || echo '?')
host_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
if (( BUILD_ONLY == 0 )); then
    xcrun devicectl device info lockState --device "$DEVICE" 2>&1 | sed -n '1,4p' || true
fi

# --- 1. build Debug do candidato para iphoneos -------------------------------------------
# O `.app` sai de onde o `-derivedDataPath` mandar: quando `--derived-data` é informado, o produto mora lá (e não sob
# o `--out`), para um GO poder reusar um build já feito sem recompilar nem trocar de caminho.
DERIVED="${DERIVED_OVERRIDE:-$OUT/derived}"
if [[ -n "$APP_OVERRIDE" ]]; then
    APP="$APP_OVERRIDE"
else
    APP="$DERIVED/Build/Products/Debug-iphoneos/FeedMine.app"
fi
if (( SKIP_BUILD == 0 )); then
    step "build (Debug, iphoneos) → $OUT/build.log"
    # `generic/platform=iOS` é o que produz o `.app` sem escolher aparelho no build: o aparelho entra na instalação,
    # e o destino do teste é o UDID na fase B.
    if ! xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
        -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
        >"$OUT/build.log" 2>&1; then
        tail -25 "$OUT/build.log" >&2
        not_run "o build falhou (log: $OUT/build.log)" 4
    fi
    grep -E '^\*\* BUILD|error:' "$OUT/build.log" | tail -5 || true
else
    step "build (pulado por --skip-build): usando $APP"
fi
[[ -d "$APP" ]] || not_run "o build não produziu $APP (log: $OUT/build.log)" 4

plist="$APP/Info.plist"
[[ -f "$plist" ]] || not_run "$APP não tem Info.plist: não é um bundle construído" 4
app_bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"
[[ "$app_bundle" != "$OWNER_BUNDLE" ]] \
    || refused "recusado: o .app construído É o app do dono ($OWNER_BUNDLE)"
[[ "$app_bundle" == "$BUNDLE" ]] \
    || refused "o .app declara CFBundleIdentifier=$app_bundle, não $BUNDLE"
printf 'app=%s\nversão=%s build=%s git=%s branch=%s\n' "$APP" \
    "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || echo '?')" \
    "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || echo '?')" \
    "$(/usr/libexec/PlistBuddy -c 'Print :FeedmineGitSHA' "$plist" 2>/dev/null || echo '?')" \
    "$(/usr/libexec/PlistBuddy -c 'Print :FeedmineGitBranch' "$plist" 2>/dev/null || echo '?')"

if (( BUILD_ONLY == 1 )); then
    step "build-only: nada foi tocado no aparelho"
    cat <<EOF
.app construído: $APP
derived data:    $DERIVED
log do build:    $OUT/build.log
NENHUM comando de aparelho foi executado neste modo (nem 'device info', nem instalação, nem lançamento).

o GO usa este build sem recompilar:
  scripts/hitch-pass.sh --skip-build --app '$APP' --derived-data '$DERIVED' --out /tmp/fm-hitch-pass-\$(date -u +%Y%m%dT%H%M%SZ)
EOF
    printf 'disco livre depois do build: %s KB\n' "$(df -k / | awk 'NR==2 {print $4}')"
    exit 0
fi

# O censo do app do dono ANTES, para o "depois" provar que ele não foi alterado (nem desinstalado).
xcrun devicectl device info apps --device "$DEVICE" --json-output "$OUT/apps-owner-before.json" >/dev/null 2>&1 || true

# --- 2. fase A: a jornada medida pelo instrumento existente -------------------------------
if (( SKIP_STANDALONE == 0 )); then
    step "fase A — jornada medida (scripts/device-journey.sh: instala, lança com --console, puxa o contêiner)"
    # `--namespace auto` (default) = UUID novo: jornada fria, censo só desta fase. O `device-journey.sh` acrescenta
    # `FEEDMINE_JOURNEY_CONSOLE=1` sozinho; `FEEDMINE_TRACE_CAPTURE=1` vai por `--env`, e `--namespace` governa
    # `FEEDMINE_RUNTIME_NAMESPACE` (o script recusa um `--env` que conflite com ele).
    if bash scripts/device-journey.sh --device "$DEVICE" --app "$APP" --seconds "$SECONDS_RUN" \
        --out "$OUT/journey-standalone" \
        --env '{"FEEDMINE_SKIP_ONBOARDING":"1","FEEDMINE_USE_DEVELOPMENT_FEEDS":"1","FEEDMINE_TRACE_CAPTURE":"1"}' \
        >"$OUT/journey-standalone-report.txt" 2>&1; then
        printf 'fase A: ok — relatório em %s\n' "$OUT/journey-standalone-report.txt"
        grep -E 'console_lines|frame_windows|journey_lines|journey_changes|non_telemetry|runtime.sqlite' \
            "$OUT/journey-standalone-report.txt" | sed -n '1,12p' || true
    else
        printf 'NOT_RUN: a fase A falhou (relatório: %s)\n' "$OUT/journey-standalone-report.txt" >&2
        sed -n '1,12p' "$OUT/journey-standalone-report.txt" >&2 || true
    fi
else
    step "fase A (pulada por --skip-standalone)"
fi

# --- 3. fase B: a jornada de rolagem, com o console em arquivo ---------------------------
syslog_pid=""
cleanup() {
    [[ -n "$syslog_pid" ]] && kill "$syslog_pid" 2>/dev/null || true
}
trap cleanup EXIT

if (( SKIP_JOURNEY == 0 )); then
    step "fase B — jornada de rolagem ($JOURNEY_TEST), com o syslog do aparelho em arquivo"
    # O syslog do aparelho é o que carrega o log unificado do app. Ele é capturado **sem filtro** durante a corrida
    # (as linhas `feedmine` na saída de `idevicesyslog` vêm do mesmo relay; o filtro é aplicado depois, no arquivo
    # derivado, para o bruto ficar bruto). `-K`/`--no-kernel` corta o kernel, que é o maior volume e o menos útil.
    if (( NO_SYSLOG == 0 )); then
        if command -v idevicesyslog >/dev/null; then
            idevicesyslog -u "$UDID" --no-colors -K >"$OUT/console-journey.log" 2>"$OUT/console-journey.err" &
            syslog_pid=$!
            sleep 3
            if [[ -s "$OUT/console-journey.log" ]]; then
                printf 'syslog do aparelho capturado em %s (pid %s)\n' "$OUT/console-journey.log" "$syslog_pid"
            else
                printf 'NOT_RUN: idevicesyslog não produziu linha nenhuma em 3 s (erro: %s)\n' \
                    "$(head -c 300 "$OUT/console-journey.err" 2>/dev/null)" >&2
                kill "$syslog_pid" 2>/dev/null || true
                syslog_pid=""
            fi
        else
            printf 'NOT_RUN: idevicesyslog não está no PATH — o log unificado do app (Logger) não será capturado;' >&2
            printf ' alternativa registrada: `log collect --device-udid %s --output %s/device-logs.logarchive`\n' \
                "$UDID" "$OUT" >&2
        fi
    else
        printf 'syslog do aparelho: pulado por --no-syslog\n'
    fi

    # `TEST_RUNNER_FEEDMINE_JOURNEY_CONSOLE=1` põe `FEEDMINE_JOURNEY_CONSOLE=1` no processo do **runner** de teste.
    # Se o app sob teste herda o ambiente do runner, a linha de jornada aparece também durante a rolagem; se não
    # herda, ela **não** aparece e isso fica medido (o script procura a linha no log persistido e diz o que achou) —
    # é a diferença entre "o app não disse" e "a captura não guardou", e ela é reportada, não presumida.
    set +e
    xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -destination "id=$UDID" \
        -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
        -resultBundlePath "$OUT/journey.xcresult" -only-testing:"$JOURNEY_TEST" \
        TEST_RUNNER_FEEDMINE_JOURNEY_CONSOLE=1 2>&1 | tee "$OUT/journey-test.log" | tail -3
    journey_status="${PIPESTATUS[0]}"
    set -e
    printf 'xcodebuild test exit=%s (log: %s)\n' "$journey_status" "$OUT/journey-test.log"

    if [[ -n "$syslog_pid" ]]; then
        kill "$syslog_pid" 2>/dev/null || true
        wait "$syslog_pid" 2>/dev/null || true
        syslog_pid=""
    fi
    printf 'console da jornada: %s linhas em %s (%s bytes)\n' \
        "$(wc -l <"$OUT/console-journey.log" 2>/dev/null | tr -d ' ' || echo 0)" \
        "$OUT/console-journey.log" "$(wc -c <"$OUT/console-journey.log" 2>/dev/null | tr -d ' ' || echo 0)"

    # O recorte é por **processo** (`FeedMine(` / `FeedMine[`), não por vocabulário de mensagem: o log unificado põe
    # a categoria no nome do processo (`FeedMine(Foundation)`, `FeedMine(composition)`) e o texto da linha é só o que
    # o app disse — procurar `[composition]` literal no texto não acha `installed cards=… ids=[…]` nem
    # `published growth: …`. Medido nesta frente em 2026-10-16: o mesmo arquivo tinha **0** linhas com
    # `[composition]` e **113** `installed cards=` (os `ids=[…]` moram ali, não no traço). O vocabulário de pressão
    # entra junto porque a dimensão (e) da junção vive dele.
    grep -aE 'FeedMine[\(\[]|memorystatus|jetsam|low memory|memory warning|thermal state|cpu_speed_limit|watchdog (hang|stuck|timeout)|panic|Terminated due to|ENOSPC|no space left|malloc:' \
        "$OUT/console-journey.log" >"$OUT/console-journey-focus.log" 2>/dev/null || true
    printf 'recorte de foco: %s linhas (frames=%s journey=%s installed=%s viewport=%s runway=%s)\n' \
        "$(wc -l <"$OUT/console-journey-focus.log" 2>/dev/null | tr -d ' ' || echo 0)" \
        "$(grep -c 'feedmine frames=' "$OUT/console-journey-focus.log" 2>/dev/null || echo 0)" \
        "$(grep -c 'feedmine journey' "$OUT/console-journey-focus.log" 2>/dev/null || echo 0)" \
        "$(grep -c 'installed cards=' "$OUT/console-journey-focus.log" 2>/dev/null || echo 0)" \
        "$(grep -c 'viewport forwarded' "$OUT/console-journey-focus.log" 2>/dev/null || echo 0)" \
        "$(grep -c 'Runway opportunity completed' "$OUT/console-journey-focus.log" 2>/dev/null || echo 0)"
    if ! grep -q 'feedmine journey' "$OUT/console-journey-focus.log" 2>/dev/null; then
        printf 'NOTA (a causa exata, medida e não suposta): a linha `feedmine journey` NÃO está no console da\n' >&2
        printf 'jornada. Causas possíveis, todas verificáveis no bruto: (a) o runner de teste não propaga\n' >&2
        printf 'FEEDMINE_JOURNEY_CONSOLE ao app sob teste (o teste só declara FEEDMINE_TRACE_CAPTURE em\n' >&2
        printf 'launchEnvironment — FluidityJourneyUITests.swift); (b) `idevicesyslog` não estava disponível e o\n' >&2
        printf 'log unificado não foi capturado; (c) o app sob teste não é o desta corrida.\n' >&2
        printf 'A linha EXISTE na fase A (console.log do device-journey.sh) se ela estiver lá.\n' >&2
    fi

    # Os anexos do XCTest: é por aqui que sai a série publicada pelo próprio app (o que a corrida de hoje tinha).
    if [[ -d "$OUT/journey.xcresult" ]]; then
        mkdir -p "$OUT/attachments"
        if xcrun xcresulttool export attachments --path "$OUT/journey.xcresult" \
            --output-path "$OUT/attachments" >"$OUT/attachments.log" 2>&1; then
            printf 'anexos do XCTest exportados em %s\n' "$OUT/attachments"
            grep -o 'scroll-journey-frame-series' "$OUT/attachments/manifest.json" 2>/dev/null | head -1 || true
        else
            printf 'NOT_RUN: a exportação dos anexos falhou (log: %s)\n' "$OUT/attachments.log" >&2
        fi
    fi
else
    step "fase B (pulada por --skip-journey)"
fi

# --- 4. o contêiner inteiro, depois das duas fases ---------------------------------------
step "contêiner (todos os namespaces do bundle, com o WAL dobrado nas cópias)"
mkdir -p "$OUT/container/$SUPPORT"
if xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
    --domain-identifier "$BUNDLE" --source "$SUPPORT" --destination "$OUT/container/$SUPPORT" \
    >"$OUT/container-copy.log" 2>&1; then
    printf 'puxado: %s\n' "$SUPPORT"
else
    printf 'NOT_RUN: a cópia do contêiner falhou (log: %s)\n' "$OUT/container-copy.log" >&2
    xcrun devicectl device info files --device "$DEVICE" --domain-type appDataContainer \
        --domain-identifier "$BUNDLE" --subdirectory "$SUPPORT" --no-recurse 2>&1 | sed -n '1,20p' >&2 || true
fi

python3 - "$OUT" <<'PY'
import glob, os, sqlite3, sys
out = sys.argv[1]
root = os.path.join(out, "container", "Library", "Application Support", "FeedMine")
rows = []
for database in sorted(glob.glob(os.path.join(root, "*", "runtime.sqlite"))):
    namespace = os.path.basename(os.path.dirname(database))
    wal = database + "-wal"
    if os.path.exists(wal):
        # O tamanho é lido **antes** do checkpoint de propósito: o SQLite apaga o `-wal` quando a última conexão
        # fecha (medido nesta frente em 2026-10-16, e o `getsize` depois do close estourou `FileNotFoundError` e
        # derrubou o censo inteiro). O número que importa é quanto estava pendente, não quanto sobrou.
        before = os.path.getsize(wal)
        try:
            connection = sqlite3.connect(database)
            connection.execute("pragma wal_checkpoint(TRUNCATE)")
            connection.close()
            after = os.path.getsize(wal) if os.path.exists(wal) else None
            rows.append(f"  {namespace}: wal {before} B → "
                        + (f"{after} B" if after is not None else "removido pelo SQLite ao fechar a conexão"))
        except sqlite3.Error as error:
            rows.append(f"  {namespace}: checkpoint falhou ({error})")
    trace = os.path.join(os.path.dirname(database), "trace.jsonl")
    lines = sum(1 for _ in open(trace, encoding="utf-8", errors="replace")) if os.path.exists(trace) else 0
    rows.append(f"    runtime.sqlite={os.path.getsize(database)} B  trace.jsonl={lines} linhas  "
                f"mtime_runtime={int(os.path.getmtime(database))}")
print("namespaces no contêiner copiado:")
print("\n".join(rows) if rows else "  (nenhum runtime.sqlite — a jornada não escreveu banco)")
PY

# --- 5. estado final e prova de que o app do dono ficou como estava ----------------------
step "estado final"
xcrun devicectl device info apps --device "$DEVICE" --json-output "$OUT/apps-owner-after.json" >/dev/null 2>&1 || true
python3 - "$OUT" "$OWNER_BUNDLE" "$BUNDLE" <<'PY'
import json, os, sys
out, owner, tested = sys.argv[1], sys.argv[2], sys.argv[3]

def installed(path):
    try:
        document = json.load(open(path, encoding="utf-8"))
    except Exception:
        return None
    found = {}
    for app in (document.get("result") or {}).get("apps") or []:
        found[app.get("bundleIdentifier")] = app.get("url") or ""
    return found

before, after = installed(os.path.join(out, "apps-owner-before.json")), installed(os.path.join(out, "apps-owner-after.json"))
if before is None or after is None:
    print("NOT_RUN: não foi possível ler 'device info apps' antes e depois")
else:
    verdict = [f"instalado[{owner}] antes={'sim' if owner in before else 'não'} depois={'sim' if owner in after else 'não'}",
               f"instalado[{tested}] antes={'sim' if tested in before else 'não'} depois={'sim' if tested in after else 'não'}"]
    if owner in before and owner in after and before[owner] == after[owner]:
        verdict.append(f"container de {owner} INALTERADO ({after[owner]}) — esta corrida não instalou, não lançou, "
                       "não terminou e não desinstalou o app do dono")
    else:
        verdict.append(f"ATENÇÃO: o container de {owner} mudou de {before.get(owner)} para {after.get(owner)} — "
                       "investigar antes de usar esta corrida como evidência")
    print("\n".join(verdict))
PY

# --- 6. onde ficaram os brutos ------------------------------------------------------------
step "artefatos (brutos, em $OUT)"
ls -la "$OUT" 2>/dev/null | sed -n '2,40p'
printf '\nos diretórios de bruto:\n'
for item in build.log journey-standalone journey-test.log journey.xcresult attachments console-journey.log \
            console-journey-focus.log console-journey.err container; do
    [[ -e "$OUT/$item" ]] && printf '  %s\n' "$OUT/$item"
done
printf '\njunção por segundo (o que a corrida de hoje não pôde fazer):\n'
printf '  python3 scripts/hitch-join.py --journey %s/journey-standalone --select severe\n' "$OUT"
printf '  python3 scripts/hitch-join.py --console %s/console-journey-focus.log \\\n' "$OUT"
printf '      --trace  "$(ls -d "$OUT"/container/*/FeedMine/*/ 2>/dev/null | head -1)trace.jsonl" \\\n'
printf '      --db     "$(ls -d "$OUT"/container/*/FeedMine/*/ 2>/dev/null | head -1)runtime.sqlite" \\\n'
printf '      --series %s/attachments/*frame-series* --select severe\n' "$OUT"
printf 'nenhum PASS de fluidez sai desta corrida: ela mede e deixa o bruto.\n'
