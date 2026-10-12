#!/bin/bash
# Harness for scripts/release-testflight.sh with stubbed xcodebuild and PlistBuddy (no Apple tools, no upload,
# no real credentials). Usage: bash k03-release-script-harness.sh <path-to-release-testflight.sh>
# Exit status: 0 only when every scenario passes; 1 otherwise.
# Portable to macOS /bin/bash 3.2: no possibly-empty "${array[@]}" under `set -u` (unbound before bash 4.4),
# no associative arrays, no ${var,,}, no mapfile.
set -u
if [ $# -lt 1 ]; then echo "usage: $0 <path-to-release-testflight.sh>" >&2; exit 2; fi
SRC="$1"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
STUB="$WORK/stub"; mkdir -p "$STUB"
cat > "$STUB/PlistBuddy" <<'EOF'
#!/bin/bash
key="${2#Print :}"
case "$key" in
  CFBundleVersion) echo "${FAKE_BUILD-42}";;
  CFBundleShortVersionString) echo "${FAKE_VERSION-2.0}";;
  CFBundleIdentifier) echo "com.feedmine.app";;
  FeedmineGitSHA) git -C "$FAKE_REPO" rev-parse --short HEAD;;
esac
EOF
cat > "$STUB/xcodebuild" <<'EOF'
#!/bin/bash
if [ "$1" = "archive" ]; then mkdir -p .build/feedmine-v2.xcarchive/Products/Applications/FeedMine.app; exit "${FAKE_ARCHIVE_RC:-0}"; fi
echo "${FAKE_UPLOAD_LOG:-Upload succeeded}"; exit "${FAKE_UPLOAD_RC:-0}"
EOF
chmod +x "$STUB/PlistBuddy" "$STUB/xcodebuild"
PASSED=0
FAILED=0
# run <name> <expected exit> [UNSET=VAR ...] [VAR=value ...]
run() {
  local name="$1" want="$2"; shift 2
  # UNSET=VAR arguments become `env -u VAR`; kept in a string, never an empty array expansion.
  local unset_opts="" unset_names=" "
  while [ $# -gt 0 ]; do
    case "$1" in
      UNSET=*) unset_opts="$unset_opts -u ${1#UNSET=}"; unset_names="$unset_names${1#UNSET=} "; shift;;
      *) break;;
    esac
  done
  local R="$WORK/repo-$name"
  mkdir -p "$R/scripts" "$R/FeedMineApp/FeedMineApp/Resources" "$R/home/.appstoreconnect/private_keys"
  sed "s#/usr/libexec/PlistBuddy#$STUB/PlistBuddy#g" "$SRC" > "$R/scripts/release-testflight.sh"
  printf '*.log\n.build/\n' > "$R/.gitignore"
  touch "$R/FeedMineApp/FeedMineApp/Info.plist" "$R/FeedMineApp/FeedMineApp/Resources/catalog.sqlite" \
    "$R/home/.appstoreconnect/private_keys/AuthKey_TESTKEY.p8"
  git -C "$R" init -q
  git -C "$R" add -A
  git -C "$R" -c user.name=t -c user.email=t@t -c core.autocrlf=false commit -qm init
  local key_id="ASC_KEY_ID=TESTKEY" issuer="ASC_ISSUER_ID=test-issuer"
  case "$unset_names" in *" ASC_KEY_ID "*) key_id="FAKE_UNUSED_1=1";; esac
  case "$unset_names" in *" ASC_ISSUER_ID "*) issuer="FAKE_UNUSED_2=1";; esac
  local out rc
  # $unset_opts is intentionally unquoted: it is empty or a list of `-u NAME` words.
  out="$(cd "$R" && env $unset_opts HOME="$R/home" FAKE_REPO="$R" PATH="$STUB:$PATH" "$key_id" "$issuer" \
    ${1+"$@"} bash scripts/release-testflight.sh ${ARGS:-} 2>&1)"; rc=$?
  local tags; tags="$(git -C "$R" tag)"
  if [ "$rc" = "$want" ]; then
    PASSED=$((PASSED + 1)); echo "PASS $name rc=$rc tags=[$tags]"
  else
    FAILED=$((FAILED + 1)); echo "FAIL $name rc=$rc want=$want tags=[$tags]"
  fi
  echo "$out" | sed 's/^/    /' | tail -2
}
ARGS="--dry-run" run dryrun 0
run upload_ok 0
run upload_log_without_marker 0 FAKE_UPLOAD_LOG="something else"
run upload_fails 8 FAKE_UPLOAD_RC=1
run archive_fails 8 FAKE_ARCHIVE_RC=1
run empty_version 9 FAKE_VERSION=
run empty_build 9 FAKE_BUILD=
run key_file_missing 9 ASC_KEY_ID=OTHERKEY
run key_id_unset 9 UNSET=ASC_KEY_ID
run key_id_empty 9 ASC_KEY_ID=
run issuer_unset 9 UNSET=ASC_ISSUER_ID
run issuer_empty 9 ASC_ISSUER_ID=
run custom_key_path 0 ASC_KEY_ID=ELSEWHERE ASC_KEY_PATH=home/.appstoreconnect/private_keys/AuthKey_TESTKEY.p8
echo "SUMMARY passed=$PASSED failed=$FAILED"
[ "$FAILED" -eq 0 ]
