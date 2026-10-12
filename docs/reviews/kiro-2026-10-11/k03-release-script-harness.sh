#!/bin/bash
# Harness for scripts/release-testflight.sh with stubbed xcodebuild and PlistBuddy (no Apple tools, no upload).
set -u
SRC="$1"            # path to release-testflight.sh
WORK="$(mktemp -d)"
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
chmod +x "$STUB"/*
run() { # name, expected exit, env...
  local name="$1" want="$2"; shift 2
  local R="$WORK/repo-$name"; mkdir -p "$R/scripts" "$R/FeedMineApp/FeedMineApp/Resources" "$R/home/.appstoreconnect/private_keys"
  sed "s#/usr/libexec/PlistBuddy#$STUB/PlistBuddy#g" "$SRC" > "$R/scripts/release-testflight.sh"
  echo "*.log" > "$R/.gitignore"; echo ".build/" >> "$R/.gitignore"
  touch "$R/FeedMineApp/FeedMineApp/Info.plist" "$R/FeedMineApp/FeedMineApp/Resources/catalog.sqlite" "$R/home/.appstoreconnect/private_keys/AuthKey_H3U55Z9WZ7.p8"
  git -C "$R" init -q; git -C "$R" add -A; git -C "$R" -c user.name=t -c user.email=t@t commit -qm init
  out="$(cd "$R" && env HOME="$R/home" FAKE_REPO="$R" PATH="$STUB:$PATH" "$@" bash scripts/release-testflight.sh ${ARGS:-} 2>&1)"; rc=$?
  tags="$(git -C "$R" tag)"
  if [ "$rc" = "$want" ]; then echo "PASS $name rc=$rc tags=[$tags]"; else echo "FAIL $name rc=$rc want=$want"; fi
  echo "$out" | sed 's/^/    /' | tail -3
}
ARGS="--dry-run" run dryrun 0
run upload_ok 0
run upload_log_without_marker 0 FAKE_UPLOAD_LOG="something else"
run upload_fails 8 FAKE_UPLOAD_RC=1
run archive_fails 8 FAKE_ARCHIVE_RC=1
run empty_version 9 FAKE_VERSION=
run empty_build 9 FAKE_BUILD=
run missing_key 9 ASC_KEY_ID=OTHERKEY
run empty_issuer_uses_default 0 ASC_ISSUER_ID=
rm -rf "$WORK"
