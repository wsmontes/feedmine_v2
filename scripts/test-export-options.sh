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
# Cases:
#   (a) uploading plist paired with --no-upload      -> REFUSED, message names destination=upload
#   (b) shipped export-only plist with --no-upload   -> accepted, destination=export
#   (c) default path (no flag)                       -> uploading plist, upload=yes
#   (d) --no-upload with the export-only plist gone  -> REFUSED, message names the missing path
#   (e) --export-only alias == --no-upload; a mistyped flag is refused (never falls back to upload)
#
# Usage: scripts/test-export-options.sh   (exit 0 = all cases hold, 1 = at least one failed)

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCRIPT="scripts/release-testflight.sh"
UPLOAD="scripts/ExportOptions.plist"
EXPORT_ONLY="scripts/ExportOptions-export-only.plist"

FAILED=0
PRISTINE="$(mktemp -t export-only-plist)"
ERRFILE="$(mktemp -t export-opts-err)"
FAKEBIN="$(cd "$(mktemp -d -t fakebin)" && pwd)"
MARKER="$FAKEBIN/xcodebuild-was-called"

cp "$EXPORT_ONLY" "$PRISTINE" || { echo "FAIL: cannot read $EXPORT_ONLY"; exit 1; }

cleanup() {
  restore_plist
  rm -rf "$PRISTINE" "$ERRFILE" "$FAKEBIN"
}
restore_plist() { cp "$PRISTINE" "$EXPORT_ONLY" 2>/dev/null; }
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
fail() { echo "FAIL: $1"; FAILED=1; }
no_xcodebuild() { [ ! -f "$MARKER" ]; }

# The shipped export-only plist must be the upload plist with exactly that one key changed.
if sed 's|<string>export</string>|<string>upload</string>|' "$EXPORT_ONLY" | cmp -s - "$UPLOAD"; then
  pass "plist differs from $UPLOAD only in destination"
else
  fail "$EXPORT_ONLY is not $UPLOAD with destination=export"
fi

# (a) The hazard itself: an uploading plist selected by the export-only path.
cp "$UPLOAD" "$EXPORT_ONLY"
run --print-export-options --no-upload
if [ "$CODE" -ne 0 ] && printf '%s' "$ERR" | grep -q 'destination=upload' && no_xcodebuild; then
  pass "(a) upload plist + --no-upload refused before xcodebuild: $(printf '%s' "$ERR" | head -1)"
else
  fail "(a) expected non-zero naming destination=upload and no xcodebuild; got code=$CODE xcodebuild_called=$([ -f "$MARKER" ] && echo yes || echo no) err=$ERR"
fi
restore_plist

# (d) The export-only plist missing while the flag is given.
mv "$EXPORT_ONLY" "$EXPORT_ONLY.gone"
run --print-export-options --no-upload
mv "$EXPORT_ONLY.gone" "$EXPORT_ONLY"
if [ "$CODE" -ne 0 ] && printf '%s' "$ERR" | grep -q "$EXPORT_ONLY" && no_xcodebuild; then
  pass "(d) missing export-only plist refused before xcodebuild: $(printf '%s' "$ERR" | head -1)"
else
  fail "(d) expected non-zero naming $EXPORT_ONLY and no xcodebuild; got code=$CODE err=$ERR"
fi

# (b) The real export-only plist.
run --print-export-options --no-upload
if [ "$CODE" -eq 0 ] && printf '%s' "$OUT" | grep -qx "EXPORT_OPTS=$EXPORT_ONLY" \
   && printf '%s' "$OUT" | grep -qx "destination=export" \
   && printf '%s' "$OUT" | grep -qx "upload=no" && no_xcodebuild; then
  pass "(b) --no-upload selects the export-only plist (destination=export)"
else
  fail "(b) expected resolved export-only plist; got code=$CODE out=[$OUT] err=$ERR"
fi

# (c) The default path: no flag, uploading plist, unchanged.
run --print-export-options
if [ "$CODE" -eq 0 ] && printf '%s' "$OUT" | grep -qx "EXPORT_OPTS=$UPLOAD" \
   && printf '%s' "$OUT" | grep -qx "destination=upload" \
   && printf '%s' "$OUT" | grep -qx "upload=yes" && no_xcodebuild; then
  pass "(c) default still selects $UPLOAD (destination=upload): a real release is one step"
else
  fail "(c) default no longer resolves to the uploading plist; got code=$CODE out=[$OUT] err=$ERR"
fi

# (e) Alias, and a typo must not silently fall back to uploading.
run --print-export-options --export-only
if [ "$CODE" -eq 0 ] && printf '%s' "$OUT" | grep -qx "EXPORT_OPTS=$EXPORT_ONLY"; then
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

if [ "$FAILED" -eq 0 ]; then
  echo "OK: export-only path is explicit, default path still uploads"
else
  echo "FALHOU: at least one case above did not hold" >&2
fi
exit "$FAILED"
