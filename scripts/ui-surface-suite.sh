#!/usr/bin/env bash
# File: ui-surface-suite.sh
# Purpose: the single entry point for the published-surface journeys. It is only orchestration over the existing
#          Xcode build and XCTest runner: one build, then one test-without-building per journey class, then a
#          summary. It does not define a DSL, a driver or a second reporter.
#
# Profiles:
#   smoke    the short set of journeys that covers the reported controls (target: under five minutes after build)
#   journeys every deterministic Debug journey, including the reader's own class (pre-release coverage)
#   release  the Release app and its no-fixture journeys through FeedMineSurfaces (permanent scheme)
#   reader   the deterministic reader class alone (Debug, fixtures)
#   seed     the opt-in seeded public-content journey (Debug, real catalogue/network)
#   live     the opt-in reader/surface proof in Release over the public catalogue and network
#
# Exit status is non-zero when any journey fails, including a build failure. Build and simulator boot time are
# reported separately; they are not hidden inside a journey's duration.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="smoke"
DESTINATION="platform=iOS Simulator,id=59CF88B8-273F-4CCF-BD2C-122D80BFFC4C"
OUT=""
DERIVED=""

usage() {
    printf 'usage: %s [--profile smoke|journeys|release] [--destination <xcodebuild destination>] [--out <dir>] [--derived <dir>]\n' "$0"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --profile) PROFILE="$2"; shift 2 ;;
        --destination) DESTINATION="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --derived) DERIVED="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; usage; exit 2 ;;
    esac
done

case "$PROFILE" in
    smoke) JOURNEYS=(SourcesAndFilterJourneyUITests CuratedFeedJourneyUITests) ;;
    journeys) JOURNEYS=(SourcesAndFilterJourneyUITests CuratedFeedJourneyUITests CardActionJourneyUITests
                        LibraryJourneyUITests SettingsAndDiscoveryJourneyUITests PortabilityJourneyUITests
                        ReadingSurfaceUITests) ;;
    release) JOURNEYS=(ReleaseSurfaceJourneyUITests) ;;
    reader) JOURNEYS=(ReadingSurfaceUITests) ;;
    seed) JOURNEYS=(ReaderContentSeedJourneyUITests) ;;
    live) JOURNEYS=(ReadingSurfaceUITests) ;;
    *) printf 'unknown profile: %s\n' "$PROFILE" >&2; exit 2 ;;
esac

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${OUT:-$ROOT/.build/ui-surface-suite/$PROFILE-$STAMP}"
DERIVED="${DERIVED:-$OUT/derived}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
DERIVED="$(cd "$DERIVED" 2>/dev/null && pwd || (mkdir -p "$DERIVED" && cd "$DERIVED" && pwd))"

CONFIGURATION="Debug"
SCHEME="FeedMine"
TARGET="FeedMineUITests"
LIVE_FILTER=""
if [ "$PROFILE" = "release" ] || [ "$PROFILE" = "live" ]; then
    CONFIGURATION="Release"
    SCHEME="FeedMineSurfaces"
fi
if [ "$PROFILE" = "live" ]; then
    LIVE_FILTER="-only-testing:$TARGET/ReadingSurfaceUITests/testLiveReaderControlsOnTheRealCatalogueAndNetwork"
fi
if [ "$PROFILE" = "reader" ]; then
    LIVE_FILTER="-skip-testing:$TARGET/ReadingSurfaceUITests/testLiveReaderControlsOnTheRealCatalogueAndNetwork"
fi

PROJECT="$ROOT/FeedMineApp/FeedMineApp.xcodeproj"
IDENTITY="$OUT/identity.txt"
{
    printf 'head=%s\n' "$(git -C "$ROOT" rev-parse HEAD)"
    printf 'dirty=%s\n' "$(git -C "$ROOT" status --porcelain | wc -l | tr -d ' ')"
    printf 'profile=%s configuration=%s target=%s destination=%s\n' "$PROFILE" "$CONFIGURATION" "$TARGET" "$DESTINATION"
    printf 'started=%s\n' "$STAMP"
} > "$IDENTITY"

BUILD_LOG="$OUT/build.log"
printf 'building %s for %s\n' "$CONFIGURATION" "$PROFILE"
BUILD_STARTED=$(date +%s)
xcodebuild build-for-testing \
    -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" -derivedDataPath "$DERIVED" > "$BUILD_LOG" 2>&1
BUILD_STATUS=$?
BUILD_SECONDS=$(( $(date +%s) - BUILD_STARTED ))
printf 'build=%s seconds=%s log=%s\n' "$([ $BUILD_STATUS -eq 0 ] && echo pass || echo fail)" "$BUILD_SECONDS" "$BUILD_LOG"
if [ $BUILD_STATUS -ne 0 ]; then
    printf 'RESULT build=FAIL exit=%s\n' "$BUILD_STATUS"
    exit "$BUILD_STATUS"
fi

SUMMARY="$OUT/summary.tsv"
: > "$SUMMARY"
ANY_FAIL=0

for JOURNEY in "${JOURNEYS[@]}"; do
    RESULT="$OUT/$JOURNEY.xcresult"
    LOG="$OUT/$JOURNEY.log"
    rm -rf "$RESULT"
    STARTED=$(date +%s)
    if [ "$PROFILE" = "live" ] || [ "$PROFILE" = "reader" ]; then
        ONLY=("$LIVE_FILTER")
    else
        ONLY=(-only-testing:"$TARGET/$JOURNEY")
    fi
    SIM_UDID="${DESTINATION##*id=}"
    if [ "$PROFILE" = "release" ] || [ "$PROFILE" = "live" ]; then
        # The Release app's identifier; the scheme builds it from scratch and the journey starts clean.
        xcrun simctl uninstall "$SIM_UDID" com.feedmine.app >/dev/null 2>&1 || true
    fi
    if [ "$PROFILE" = "seed" ]; then
        xcrun simctl uninstall "$SIM_UDID" com.feedmine.development >/dev/null 2>&1 || true
    fi
    if [ "$PROFILE" = "live" ]; then
        # The runner reads the opt-in from its own environment. `simctl launchctl setenv` is the simulator's
        # environment; it reaches the test runner before the app is launched (a build setting does not).
        xcrun simctl spawn "$SIM_UDID" launchctl setenv FEEDMINE_LIVE_SURFACES 1
        xcodebuild test-without-building \
            -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
            -destination "$DESTINATION" -derivedDataPath "$DERIVED" \
            "${ONLY[@]}" -resultBundlePath "$RESULT" > "$LOG" 2>&1
        xcrun simctl spawn "$SIM_UDID" launchctl unsetenv FEEDMINE_LIVE_SURFACES || true
    elif [ "$PROFILE" = "seed" ]; then
        SEED="${FEEDMINE_CONTENT_SEED:-reader-surface-20261021}"
        xcrun simctl spawn "$SIM_UDID" launchctl setenv FEEDMINE_REAL_CONTENT_SEEDED 1
        xcrun simctl spawn "$SIM_UDID" launchctl setenv FEEDMINE_CONTENT_SEED "$SEED"
        xcodebuild test-without-building \
            -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
            -destination "$DESTINATION" -derivedDataPath "$DERIVED" \
            "${ONLY[@]}" -resultBundlePath "$RESULT" > "$LOG" 2>&1
        xcrun simctl spawn "$SIM_UDID" launchctl unsetenv FEEDMINE_REAL_CONTENT_SEEDED || true
        xcrun simctl spawn "$SIM_UDID" launchctl unsetenv FEEDMINE_CONTENT_SEED || true
    else
        xcodebuild test-without-building \
            -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
            -destination "$DESTINATION" -derivedDataPath "$DERIVED" \
            "${ONLY[@]}" -resultBundlePath "$RESULT" > "$LOG" 2>&1
    fi
    STATUS=$?
    SECONDS_TAKEN=$(( $(date +%s) - STARTED ))
    printf '%s\tstatus=%s\tduration=%ss\tlog=%s\tresult=%s\n' \
        "$JOURNEY" "$([ $STATUS -eq 0 ] && echo pass || echo fail)" "$SECONDS_TAKEN" "$LOG" "$RESULT" | tee -a "$SUMMARY"

    COUNTS="$(python3 - "$RESULT" <<'PY'
import json, subprocess, sys
path = sys.argv[1]
try:
    raw = subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", "summary",
                                   "--path", path, "--compact"], text=True)
    summary = json.loads(raw)
    passed = summary.get("passedTests", 0)
    failed = summary.get("failedTests", 0)
    skipped = summary.get("skippedTests", 0)
    total = summary.get("totalTestCount", passed + failed + skipped)
    print(f"pass={passed}\tfail={failed}\tskip={skipped}\ttotal={total}")
except Exception as error:
    print(f"pass=0\tfail=0\tskip=0\ttotal=0\terror={error}")
PY
)"
    printf '  %s\n' "$COUNTS" | tee -a "$SUMMARY"
    PASSED="$(printf '%s\n' "$COUNTS" | sed -n 's/.*pass=\([0-9][0-9]*\).*/\1/p')"
    if [ $STATUS -ne 0 ]; then ANY_FAIL=1; fi
    if [ "${PASSED:-0}" -eq 0 ]; then
        # A profile that produced no passing test did not verify anything: "success" from a skip is NOTRUN.
        printf '  NOTRUN %s produced 0 passing tests; not a verification\n' "$JOURNEY" | tee -a "$SUMMARY"
        ANY_FAIL=1
    fi
done

printf 'summary=%s identity=%s derived=%s\n' "$SUMMARY" "$IDENTITY" "$DERIVED"
if [ $ANY_FAIL -ne 0 ]; then
    printf 'RESULT profile=%s FAIL\n' "$PROFILE"
    exit 1
fi
printf 'RESULT profile=%s PASS\n' "$PROFILE"
