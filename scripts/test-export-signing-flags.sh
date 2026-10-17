#!/bin/bash
# Cheap assertion that `-exportArchive` receives the SAME signing flags as `archive` in
# scripts/release-testflight.sh, from the same single definition.
#
# Why this exists: the export re-signs the archive. If the export call lacks the flags the archive
# used, a real release fails by signing only after the ~130 s archive — the failure arrives too late
# to be useful, and on a clean machine it is the difference between a re-signed ipa and no release.
#
# Nothing real runs here: `xcodebuild` is a stub that records the argv of BOTH calls (NUL-separated)
# and exits 0, the two catalogue verifiers are stubs on the same fixture, `--no-upload` keeps the
# export from tagging, and everything happens in a throwaway git fixture under $TMPDIR. The
# developer's own ASC_* environment is unset for every case, so a shell that exports a real key
# cannot change the result.
#
# Cases:
#   (1) release run (--no-upload): exit 0; exactly `archive` then `-exportArchive`; BOTH argv carry
#       -allowProvisioningUpdates and the three -authenticationKey* flags with equal values; the
#       export key path is the one the script resolves from $HOME; no tag is created.
#   (2) --dry-run with no ASC key: exit 0, archive only (never an export), archive carries
#       -allowProvisioningUpdates and NO -authenticationKey* — the documented keyless path.
#   (3) release run with ASC_KEY_ID unset: exit 9 before ANY xcodebuild call (fail closed before
#       the archive, since the archive now signs with those credentials).
#   (4) release run with the .p8 missing: exit 9 before any xcodebuild call, message names the path.
#
# Usage: scripts/test-export-signing-flags.sh [--script PATH]
#   --script PATH runs the same assertions against another copy of the script; that is how the
#   red/green pair is produced:
#     git show main:scripts/release-testflight.sh > /tmp/pre.sh
#     scripts/test-export-signing-flags.sh --script /tmp/pre.sh   # (1) FAILS: export lacks the flag
#     scripts/test-export-signing-flags.sh                        # all cases PASS
# Exit status: 0 when every case holds, 1 otherwise.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCRIPT="scripts/release-testflight.sh"
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --script)
      [ $# -ge 2 ] || { echo "uso: $0 [--script PATH]" >&2; exit 2; }
      SCRIPT="$2"; shift ;;
    *) echo "uso: $0 [--script PATH]" >&2; exit 2 ;;
  esac
  shift
done
if [ ! -f "$SCRIPT" ]; then echo "ABORTADO: script inexistente: $SCRIPT" >&2; exit 2; fi
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"

FAILED=0
WORK="$(mktemp -d -t export-signing)"
trap 'rm -rf "$WORK"' EXIT

FIX="$WORK/fixture"
ARGV="$WORK/argv"
HOME_DIR="$WORK/home"
BIN="$WORK/bin"
KEY_ID="TESTKEY1"
ISSUER_ID="00000000-0000-0000-0000-000000000000"
KEY_PATH="$HOME_DIR/.appstoreconnect/private_keys/AuthKey_$KEY_ID.p8"

fail() { echo "FAIL: $1" >&2; FAILED=1; }
pass() { echo "PASS: $1"; }

# --- fixture: a minimal repository the script accepts up to the export step -----------------------
mkdir -p "$FIX/scripts" "$FIX/FeedMineApp/FeedMineApp/Resources" "$ARGV" "$BIN" "$HOME_DIR/.appstoreconnect/private_keys"
cp "$SCRIPT" "$FIX/scripts/release-testflight.sh"
chmod +x "$FIX/scripts/release-testflight.sh"
printf '#!/bin/sh\nexit 0\n' > "$FIX/scripts/verify_product_catalogue.sh"
printf 'import sys\nsys.exit(0)\n' > "$FIX/scripts/verify_catalog_release.py"
chmod +x "$FIX/scripts/verify_product_catalogue.sh"
cp scripts/ExportOptions.plist scripts/ExportOptions-export-only.plist "$FIX/scripts/"
printf 'SQLite format 3 stub\n' > "$FIX/FeedMineApp/FeedMineApp/Resources/catalog.sqlite"
printf '{"revision": 1}\n' > "$FIX/FeedMineApp/FeedMineApp/Resources/catalog.manifest.json"
cat > "$FIX/FeedMineApp/FeedMineApp/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleVersion</key><string>49</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
</dict>
</plist>
PLIST
printf '*.log\n.build/\n' > "$FIX/.gitignore"
printf 'private key stub\n' > "$KEY_PATH"
git -C "$FIX" init -q
git -C "$FIX" -c user.email=test@example.invalid -c user.name="Export Flags Test" add -A
git -C "$FIX" -c user.email=test@example.invalid -c user.name="Export Flags Test" commit -qm fixture

# --- stub xcodebuild: records argv of both calls, fabricates a passable archive -------------------
cat > "$BIN/xcodebuild" <<STUB
#!/bin/bash
# \$1 is 'archive' or '-exportArchive'; each call overwrites its own NUL-separated argv file.
case "\${1:-}" in
  archive)
    printf '%s\0' "\$@" > "$ARGV/archive.argv"
    echo archive >> "$ARGV/calls.log"
    APP="$FIX/.build/feedmine-v2.xcarchive/Products/Applications/FeedMine.app"
    mkdir -p "\$APP"
    cat > "\$APP/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.feedmine.app</string>
  <key>CFBundleVersion</key><string>49</string>
  <key>FeedmineGitSHA</key><string>\$(git -C "$FIX" rev-parse --short HEAD)</string>
</dict>
</plist>
PL
    ;;
  -exportArchive)
    printf '%s\0' "\$@" > "$ARGV/export.argv"
    echo export >> "$ARGV/calls.log"
    ;;
  *) echo export-UNEXPECTED >> "$ARGV/calls.log" ;;
esac
exit 0
STUB
chmod +x "$BIN/xcodebuild"

# --- helpers -------------------------------------------------------------------------------------
# Presence of a bare flag in a NUL-separated argv file.
argv_has() {
  [ -f "$1" ] && xargs -0 -n1 < "$1" 2>/dev/null | grep -Fxq -- "$2"
}
# Value following a flag in a NUL-separated argv file.
argv_value() {
  [ -f "$1" ] || return 0
  xargs -0 -n1 < "$1" 2>/dev/null | awk -v f="$2" '$0 == f { getline; print; exit }'
}

reset_case() { rm -rf "$ARGV"/*; git -C "$FIX" tag --list | head -1 | grep -q . && fail "a tag survived into a new case"; }
run_release() {
  # $@ = flags; env: ASC key present/absent is chosen by the caller through RELEASE_ENV.
  local out_file="$WORK/out" err_file="$WORK/err"
  ( cd "$FIX" && env -u ASC_KEY_ID -u ASC_ISSUER_ID -u ASC_KEY_PATH \
      -u FM_EXPORT_OPTS_UPLOAD -u FM_EXPORT_OPTS_EXPORT_ONLY \
      HOME="$HOME_DIR" PATH="$BIN:$PATH" $RELEASE_ENV \
      bash scripts/release-testflight.sh "$@" > "$out_file" 2> "$err_file" )
  CODE=$?
  OUT="$(cat "$out_file")"
  ERR="$(cat "$err_file")"
}
release_env_ok() { RELEASE_ENV="ASC_KEY_ID=$KEY_ID ASC_ISSUER_ID=$ISSUER_ID"; }
release_env_none() { RELEASE_ENV=""; }

# --- (1) release run: both calls carry the same four signing flags --------------------------------
reset_case; release_env_ok
run_release --no-upload
CALLS="$(cat "$ARGV/calls.log" 2>/dev/null | tr '\n' ' ')"
if [ "$CODE" -eq 0 ] && [ "$CALLS" = "archive export " ]; then
  pass "(1a) --no-upload exported after archiving (calls: $CALLS)"
else
  fail "(1a) expected exit 0 and archive then export; got code=$CODE calls=[$CALLS] err=[$(printf '%s' "$ERR" | tail -2)]"
fi

export_flags_ok=1
for flag in -allowProvisioningUpdates -authenticationKeyPath -authenticationKeyID -authenticationKeyIssuerID; do
  argv_has "$ARGV/archive.argv" "$flag" || { fail "(1) archive argv lacks $flag"; export_flags_ok=0; }
  argv_has "$ARGV/export.argv" "$flag" || { fail "(1) export argv lacks $flag"; export_flags_ok=0; }
done

for flag in -authenticationKeyPath -authenticationKeyID -authenticationKeyIssuerID; do
  a="$(argv_value "$ARGV/archive.argv" "$flag")"
  e="$(argv_value "$ARGV/export.argv" "$flag")"
  if [ -n "$a" ] && [ "$a" = "$e" ]; then
    pass "(1b) $flag is identical on archive and export: $a"
  else
    fail "(1b) $flag differs (or is empty): archive=[$a] export=[$e]"
    export_flags_ok=0
  fi
done

if [ "$(argv_value "$ARGV/export.argv" -authenticationKeyPath)" = "$KEY_PATH" ]; then
  pass "(1c) export uses the key path the script resolved from \$HOME: $KEY_PATH"
else
  fail "(1c) export key path != $KEY_PATH: [$(argv_value "$ARGV/export.argv" -authenticationKeyPath)]"
  export_flags_ok=0
fi

if [ "$export_flags_ok" -eq 1 ]; then
  pass "(1d) -exportArchive receives exactly the archive's signing flags"
fi

if printf '%s' "$OUT" | grep -q 'NO UPLOAD' && [ -z "$(git -C "$FIX" tag --list)" ]; then
  pass "(1e) --no-upload path intact: nothing sent, no tag"
else
  fail "(1e) --no-upload path changed: out=[$(printf '%s' "$OUT" | tail -1)] tags=[$(git -C "$FIX" tag --list)]"
fi
if ! argv_has "$ARGV/export.argv" -exportOptionsPlist || ! argv_has "$ARGV/export.argv" -exportPath; then
  fail "(1f) the export lost its plist/path arguments"
else
  pass "(1f) the export keeps -exportOptionsPlist and -exportPath"
fi

# --- (2) dry run: archive only, keyless, no authentication flags ---------------------------------
reset_case; release_env_none
run_release --dry-run
if [ "$CODE" -eq 0 ] && [ "$(cat "$ARGV/calls.log" 2>/dev/null)" = "archive" ]; then
  pass "(2a) --dry-run without ASC key archives and never exports"
else
  fail "(2a) --dry-run expected exit 0 + archive only; got code=$CODE calls=[$(cat "$ARGV/calls.log" 2>/dev/null | tr '\n' ' ')]"
fi
if argv_has "$ARGV/archive.argv" -allowProvisioningUpdates \
   && ! argv_has "$ARGV/archive.argv" -authenticationKeyPath \
   && ! argv_has "$ARGV/archive.argv" -authenticationKeyID \
   && ! argv_has "$ARGV/archive.argv" -authenticationKeyIssuerID; then
  pass "(2b) the keyless dry-run archive keeps -allowProvisioningUpdates and adds no key flags"
else
  fail "(2b) dry-run archive flags changed: [$(xargs -0 -n1 < "$ARGV/archive.argv" 2>/dev/null | tr '\n' ' ')]"
fi

# --- (3) missing ASC_KEY_ID: refused before archiving --------------------------------------------
reset_case; release_env_none
run_release --no-upload
if [ "$CODE" -eq 9 ] && [ ! -f "$ARGV/calls.log" ] && printf '%s' "$OUT$ERR" | grep -q 'ASC_KEY_ID'; then
  pass "(3) missing ASC_KEY_ID refuses with exit 9 before xcodebuild: $(printf '%s' "$OUT$ERR" | grep -m1 'ASC_KEY_ID')"
else
  fail "(3) expected exit 9 naming ASC_KEY_ID and no xcodebuild; got code=$CODE calls=[$(cat "$ARGV/calls.log" 2>/dev/null)] err=[$ERR]"
fi

# --- (4) missing .p8: refused before archiving ---------------------------------------------------
reset_case; release_env_ok
mv "$KEY_PATH" "$KEY_PATH.gone"
run_release --no-upload
mv "$KEY_PATH.gone" "$KEY_PATH"
if [ "$CODE" -eq 9 ] && [ ! -f "$ARGV/calls.log" ] && printf '%s' "$ERR" | grep -q 'API key ausente'; then
  pass "(4) missing .p8 refuses with exit 9 before xcodebuild: $(printf '%s' "$ERR" | head -1)"
else
  fail "(4) expected exit 9 naming the missing key and no xcodebuild; got code=$CODE calls=[$(cat "$ARGV/calls.log" 2>/dev/null)] err=[$ERR]"
fi

if [ "$FAILED" -eq 0 ]; then
  echo "OK: archive and -exportArchive share one signing-flags definition, --no-upload and --dry-run intact"
else
  echo "FALHOU: at least one case above did not hold" >&2
fi
exit "$FAILED"
