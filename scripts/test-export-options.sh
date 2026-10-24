#!/bin/bash
# Cheap assertion for the export/upload selection in scripts/release-testflight.sh.
#
# Why this exists: scripts/ExportOptions.plist declares method=app-store-connect and
# destination=upload, so `xcodebuild -exportArchive` PUBLISHES the ipa as a side effect of
# exporting. The script therefore has an explicit --no-upload opt-in pointing at
# scripts/ExportOptions-export-only.plist (destination=export), and it refuses when the plist that
# would actually reach xcodebuild still says destination=upload.
#
# This test never runs a real export. It uses `--print-export-options` (resolve + check, then exit)
# and, for every case, a stubbed `xcodebuild` on PATH that records any invocation — so a passing
# refusal also proves xcodebuild was never reached.
#
# It also never writes a versioned file. Both plists are copied into a throwaway directory and the
# script resolves them there through FM_EXPORT_OPTS_UPLOAD / FM_EXPORT_OPTS_EXPORT_ONLY (its only
# test seam; unset, it uses the shipped paths). The cases below then mutate THOSE copies — including
# overwriting the export-only copy with the uploading plist, the hazardous input case (a). The
# sha256 of both versioned plists is recorded before the first case and re-checked at every exit,
# so an interrupted or failed run cannot leave the repository altered.
#
# `--interruption-proof` proves that last claim by measurement: it runs this same suite in a child,
# SIGTERMs it at the exact moment the throwaway export-only copy holds the uploading plist, then
# asserts the versioned hashes and `git status --porcelain` are exactly as they were before.
#
# Cases:
#   (a) uploading plist paired with --no-upload      -> REFUSED, message names destination=upload
#   (b) shipped export-only plist with --no-upload   -> accepted, destination=export
#   (c) default path (no flag)                       -> uploading plist, upload=yes
#   (d) --no-upload with the export-only plist gone  -> REFUSED, message names the missing path
#   (e) --export-only alias == --no-upload; a mistyped flag is refused (never falls back to upload)
#   (f) with the seam unset the shipped paths are used: the default path is unchanged
#
# Usage: scripts/test-export-options.sh [--interruption-proof]
#   (exit 0 = all cases hold, 1 = at least one failed)

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCRIPT="scripts/release-testflight.sh"
UPLOAD="scripts/ExportOptions.plist"
EXPORT_ONLY="scripts/ExportOptions-export-only.plist"

WORK="${EXPORT_TEST_WORK:-$(mktemp -d -t export-options)}"
mkdir -p "$WORK"
FAILED=0
ERRFILE="$WORK/err"
FAKEBIN="$WORK/fakebin"
MARKER="$FAKEBIN/xcodebuild-was-called"
PLISTS="$WORK/plists"
TMP_UPLOAD="$PLISTS/ExportOptions.plist"
TMP_EXPORT_ONLY="$PLISTS/ExportOptions-export-only.plist"
mkdir -p "$FAKEBIN" "$PLISTS"
cp "$UPLOAD" "$TMP_UPLOAD"
cp "$EXPORT_ONLY" "$TMP_EXPORT_ONLY"
export FM_EXPORT_OPTS_UPLOAD="$TMP_UPLOAD"
export FM_EXPORT_OPTS_EXPORT_ONLY="$TMP_EXPORT_ONLY"

hash() { shasum -a 256 "$1" | awk '{print $1}'; }
BEFORE_UPLOAD="$(hash "$UPLOAD")"
BEFORE_EXPORT="$(hash "$EXPORT_ONLY")"
STATUS_BEFORE="$(git status --porcelain)"

cleanup() {
  local now_upload now_export
  now_upload="$(hash "$UPLOAD" 2>/dev/null)"
  now_export="$(hash "$EXPORT_ONLY" 2>/dev/null)"
  if [ "$now_upload" != "$BEFORE_UPLOAD" ] || [ "$now_export" != "$BEFORE_EXPORT" ]; then
    echo "FAIL: a versioned plist changed during this run ($UPLOAD $BEFORE_UPLOAD -> $now_upload; $EXPORT_ONLY $BEFORE_EXPORT -> $now_export)" >&2
    FAILED=1
  fi
  if [ -z "${EXPORT_TEST_WORK:-}" ]; then rm -rf "$WORK"; fi
}
trap cleanup EXIT

# Stub: any real xcodebuild invocation proves the refusal came too late.
cat > "$FAKEBIN/xcodebuild" <<EOF
#!/bin/bash
echo "\$@" >> "$MARKER"
echo "fake xcodebuild: $MARKER" >&2
exit 1
EOF
chmod +x "$FAKEBIN/xcodebuild"
export PATH="$FAKEBIN:$PATH"

OUT=""
ERR=""
CODE=0
run() {
  rm -f "$MARKER"
  OUT="$(./"$SCRIPT" "$@" 2>"$ERRFILE")"
  CODE=$?
  ERR="$(cat "$ERRFILE")"
}
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; FAILED=1; }
no_xcodebuild() { [ ! -f "$MARKER" ]; }

suite() {
  echo "versioned plists before: $UPLOAD $BEFORE_UPLOAD"
  echo "versioned plists before: $EXPORT_ONLY $BEFORE_EXPORT"
  echo "throwaway copies: $TMP_UPLOAD $TMP_EXPORT_ONLY"

  # The shipped export-only plist must be the upload plist with exactly that one key changed.
  if sed 's|<string>export</string>|<string>upload</string>|' "$EXPORT_ONLY" | cmp -s - "$UPLOAD"; then
    pass "plist differs from $UPLOAD only in destination"
  else
    fail "$EXPORT_ONLY is not $UPLOAD with destination=export"
  fi

  # (a) The hazard itself: an uploading plist selected by the export-only path. The upload plist is
  # copied over the THROWAWAY export-only copy; the versioned file is never written.
  cp "$UPLOAD" "$TMP_EXPORT_ONLY"
  if [ -n "${EXPORT_TEST_HOLD_AFTER_SWAP:-}" ]; then
    # The throwaway export-only copy is now the uploading plist: the exact state the old test
    # reached by overwriting the versioned file. Announce it and hold so a driver can interrupt.
    { echo "$TMP_EXPORT_ONLY"; echo "$(hash "$TMP_EXPORT_ONLY")"; } > "$EXPORT_TEST_HOLD_AFTER_SWAP"
    while [ -e "$EXPORT_TEST_HOLD_AFTER_SWAP" ]; do sleep 0.05; done
  fi
  run --print-export-options --no-upload
  if [ "$CODE" -ne 0 ] && printf '%s' "$ERR" | grep -q 'destination=upload' && no_xcodebuild; then
    pass "(a) upload plist + --no-upload refused before xcodebuild: $(printf '%s' "$ERR" | head -1)"
  else
    fail "(a) expected non-zero naming destination=upload and no xcodebuild; got code=$CODE xcodebuild_called=$([ -f "$MARKER" ] && echo yes || echo no) err=$ERR"
  fi
  cp "$EXPORT_ONLY" "$TMP_EXPORT_ONLY"

  # (d) The export-only plist missing while the flag is given.
  mv "$TMP_EXPORT_ONLY" "$TMP_EXPORT_ONLY.gone"
  run --print-export-options --no-upload
  mv "$TMP_EXPORT_ONLY.gone" "$TMP_EXPORT_ONLY"
  if [ "$CODE" -ne 0 ] && printf '%s' "$ERR" | grep -q "$TMP_EXPORT_ONLY" && no_xcodebuild; then
    pass "(d) missing export-only plist refused before xcodebuild: $(printf '%s' "$ERR" | head -1)"
  else
    fail "(d) expected non-zero naming $TMP_EXPORT_ONLY and no xcodebuild; got code=$CODE err=$ERR"
  fi

  # (b) The real export-only plist.
  run --print-export-options --no-upload
  if [ "$CODE" -eq 0 ] && printf '%s' "$OUT" | grep -qx "EXPORT_OPTS=$TMP_EXPORT_ONLY" \
     && printf '%s' "$OUT" | grep -qx "destination=export" \
     && printf '%s' "$OUT" | grep -qx "upload=no" && no_xcodebuild; then
    pass "(b) --no-upload selects the export-only plist (destination=export)"
  else
    fail "(b) expected resolved export-only plist; got code=$CODE out=[$OUT] err=$ERR"
  fi

  # (c) The default path: no flag, uploading plist, unchanged.
  run --print-export-options
  if [ "$CODE" -eq 0 ] && printf '%s' "$OUT" | grep -qx "EXPORT_OPTS=$TMP_UPLOAD" \
     && printf '%s' "$OUT" | grep -qx "destination=upload" \
     && printf '%s' "$OUT" | grep -qx "upload=yes" && no_xcodebuild; then
    pass "(c) default still selects $UPLOAD (destination=upload): a real release is one step"
  else
    fail "(c) default no longer resolves to the uploading plist; got code=$CODE out=[$OUT] err=$ERR"
  fi

  # (e) Alias, and a typo must not silently fall back to uploading.
  run --print-export-options --export-only
  if [ "$CODE" -eq 0 ] && printf '%s' "$OUT" | grep -qx "EXPORT_OPTS=$TMP_EXPORT_ONLY"; then
    pass "(e1) --export-only is an alias of --no-upload"
  else
    fail "(e1) --export-only did not select the export-only plist; got code=$CODE out=[$OUT] err=$ERR"
  fi
  run --print-export-options --no-uplaod
  if [ "$CODE" -ne 0 ] && printf '%s' "$ERR" | grep -q 'argumento desconhecido' && no_xcodebuild; then
    pass "(e2) mistyped flag refused instead of uploading"
  else
    fail "(e2) mistyped flag was not refused; got code=$CODE err=$ERR"
  fi

  # (f) The seam is a test seam only: unset, the shipped paths are what reach xcodebuild.
  rm -f "$MARKER"
  OUT="$(unset FM_EXPORT_OPTS_UPLOAD FM_EXPORT_OPTS_EXPORT_ONLY; ./"$SCRIPT" --print-export-options 2>"$ERRFILE")"
  CODE=$?
  ERR="$(cat "$ERRFILE")"
  if [ "$CODE" -eq 0 ] && printf '%s' "$OUT" | grep -qx "EXPORT_OPTS=$UPLOAD" \
     && printf '%s' "$OUT" | grep -qx "destination=upload" \
     && printf '%s' "$OUT" | grep -qx "upload=yes" && no_xcodebuild; then
    pass "(f1) with the seam unset the default path is $UPLOAD (destination=upload)"
  else
    fail "(f1) with the seam unset the default path changed; got code=$CODE out=[$OUT] err=$ERR"
  fi
  rm -f "$MARKER"
  OUT="$(unset FM_EXPORT_OPTS_UPLOAD FM_EXPORT_OPTS_EXPORT_ONLY; ./"$SCRIPT" --print-export-options --no-upload 2>"$ERRFILE")"
  CODE=$?
  ERR="$(cat "$ERRFILE")"
  if [ "$CODE" -eq 0 ] && printf '%s' "$OUT" | grep -qx "EXPORT_OPTS=$EXPORT_ONLY" \
     && printf '%s' "$OUT" | grep -qx "destination=export" && no_xcodebuild; then
    pass "(f2) with the seam unset --no-upload resolves to $EXPORT_ONLY"
  else
    fail "(f2) with the seam unset --no-upload did not resolve to the shipped export-only plist; got code=$CODE out=[$OUT] err=$ERR"
  fi

  # The versioned plists must be byte-identical after every case above.
  AFTER_UPLOAD="$(hash "$UPLOAD")"
  AFTER_EXPORT="$(hash "$EXPORT_ONLY")"
  echo "versioned plists after:  $UPLOAD $AFTER_UPLOAD"
  echo "versioned plists after:  $EXPORT_ONLY $AFTER_EXPORT"
  if [ "$AFTER_UPLOAD" != "$BEFORE_UPLOAD" ] || [ "$AFTER_EXPORT" != "$BEFORE_EXPORT" ]; then
    fail "a versioned plist changed during the suite"
  else
    pass "both versioned plists unchanged by the suite (sha256 equal before and after)"
  fi
  if [ -n "$(git status --porcelain -- "$UPLOAD" "$EXPORT_ONLY")" ]; then
    fail "git status reports the versioned plists as modified"
  else
    pass "git status clean for both versioned plists"
  fi
}

interruption_proof() {
  local hold="$WORK/hold" child status swap_copy swap_hash tmp_in_repo=0
  echo "== interruption proof: SIGTERM the suite while the throwaway copy holds the upload plist =="
  echo "versioned plists before: $(hash "$UPLOAD") $(hash "$EXPORT_ONLY")"
  echo "git status --porcelain before: [$(git status --porcelain)]"
  rm -f "$hold"
  EXPORT_TEST_HOLD_AFTER_SWAP="$hold" EXPORT_TEST_WORK="$WORK/child" bash "$0" > "$WORK/child.log" 2>&1 &
  child=$!
  for _ in $(seq 1 600); do
    [ -e "$hold" ] && break
    kill -0 "$child" 2>/dev/null || break
    sleep 0.05
  done
  if [ ! -e "$hold" ]; then
    fail "(i) the suite never reached the swap point; child log: $(tail -3 "$WORK/child.log")"
    wait "$child" 2>/dev/null
    return
  fi
  swap_copy="$(sed -n 1p "$hold")"
  swap_hash="$(sed -n 2p "$hold")"
  case "$swap_copy" in
    "$ROOT"/*) tmp_in_repo=1 ;;
  esac
  if [ "$tmp_in_repo" -eq 1 ]; then
    fail "(i) the mutated copy lives inside the repository: $swap_copy"
  elif cmp -s "$swap_copy" "$UPLOAD" && [ "$swap_hash" = "$(hash "$UPLOAD")" ]; then
    pass "(i) the throwaway copy $swap_copy had been overwritten with the uploading plist when the signal arrived"
  else
    fail "(i) the throwaway copy is not the uploading plist; the interrupted step was not the hazard"
  fi
  kill -TERM "$child"
  wait "$child"
  status=$?
  echo "interrupted child exit status: $status (143 = killed by SIGTERM)"
  rm -f "$hold"

  local after_upload after_export after_status
  after_upload="$(hash "$UPLOAD")"
  after_export="$(hash "$EXPORT_ONLY")"
  after_status="$(git status --porcelain)"
  if [ "$after_upload" = "$BEFORE_UPLOAD" ] && [ "$after_export" = "$BEFORE_EXPORT" ]; then
    pass "(ii) versioned plists unchanged after the forced interruption: $after_upload $after_export"
  else
    fail "(ii) a versioned plist changed across the forced interruption: $(hash "$UPLOAD") $(hash "$EXPORT_ONLY")"
  fi
  if [ "$after_status" = "$STATUS_BEFORE" ] && [ -z "$after_status" ]; then
    pass "(iii) git status --porcelain clean after the forced interruption"
  elif [ "$after_status" = "$STATUS_BEFORE" ]; then
    fail "(iii) tree was already dirty before the interruption; unchanged, but the clean-tree claim is untested: [$after_status]"
  else
    fail "(iii) git status changed across the forced interruption: before=[$STATUS_BEFORE] after=[$after_status]"
  fi
}

if [ "${1:-}" = "--interruption-proof" ]; then
  interruption_proof
fi
suite

if [ "$FAILED" -eq 0 ]; then
  echo "OK: export-only path is explicit, default path still uploads, versioned plists untouched"
else
  echo "FALHOU: at least one case above did not hold" >&2
fi
exit "$FAILED"
