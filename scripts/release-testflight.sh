#!/bin/bash
# TestFlight delivery for the V2 iOS app, with a mandatory build ↔ commit pairing.
#
# Ported from the V1 pipeline (feedmine-dev/scripts/release-testflight.sh). The invariants are:
#   * refuses a dirty working tree — an uploaded binary must be reproducible from a commit;
#   * refuses archive unless current public inventory, compiler and bundled SQLite provenance agree;
#   * archives, then verifies the git SHA stamped inside the archive against HEAD, aborting on mismatch;
#   * uploads with the App Store Connect API key (the Xcode Apple-ID path fails on this machine);
#   * creates the local annotated tag `ios/<version>-build.<build>-<sha>` and prints the pairing.
#
# It never pushes: `git tag` is local.
#
# Usage: scripts/release-testflight.sh [--dry-run]
#   --dry-run  run the same preflight and archive checks (no ASC key, upload or tag)

set -euo pipefail
# K-03 (Kiro): -e makes any unchecked failure stop the release instead of uploading or tagging
# with empty metadata. Expected non-zero commands are guarded explicitly with `|| true` / `if`.
trap 'echo "ABORTADO: comando falhou na linha $LINENO (exit $?)" >&2' ERR

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then DRY_RUN=1; fi

# App Store Connect API key identity comes only from the environment (no account defaults in Git):
#   ASC_KEY_ID     required, e.g. export ASC_KEY_ID=<key id from App Store Connect>
#   ASC_ISSUER_ID  required, e.g. export ASC_ISSUER_ID=<issuer uuid>
#   ASC_KEY_PATH   optional, default ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
# Unset and explicitly empty are both refused before anything is archived.
missing_env() {
  echo "ABORTADO: $1 ausente ou vazio — exporte $1 com o valor da chave App Store Connect antes de rodar"
  exit 9
}
# Credentials are intentionally checked only after a verified non-dry-run archive.
PROJECT="FeedMineApp/FeedMineApp.xcodeproj"
SCHEME="FeedMine"
INFO_PLIST="FeedMineApp/FeedMineApp/Info.plist"
RESOURCES="FeedMineApp/FeedMineApp/Resources"
CATALOG="$RESOURCES/catalog.sqlite"
DESCRIPTOR="$RESOURCES/catalog.manifest.json"
ARCHIVE=".build/feedmine-v2.xcarchive"
EXPORT_OPTS="scripts/ExportOptions.plist"
STAGING="${P0C_STAGING_ROOT:-build/catalog-bootstrap}"
EVIDENCE_DIR="${P0C_EVIDENCE_DIR:-.build}"

if [ -n "$(git status --porcelain)" ]; then
  echo "ABORTADO: working tree is dirty — commit first, or the uploaded binary maps to no SHA"
  git status --short | head -10 || true
  exit 9
fi

if [ ! -f "$CATALOG" ] || [ ! -f "$DESCRIPTOR" ]; then
  echo "ABORTADO: catalog.sqlite + catalog.manifest.json must both exist in Resources" >&2
  exit 9
fi

# Every value below names the uploaded binary or its tag; none may be empty.
require() {
  if [ -z "${2:-}" ]; then echo "ABORTADO: $1 vazio — não é possível parear build e commit"; exit 9; fi
}

SHA="$(git rev-parse HEAD)"
SHORT="$(git rev-parse --short HEAD)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
require "git SHA" "$SHA"
require "git short SHA" "$SHORT"
require "CFBundleVersion ($INFO_PLIST)" "$BUILD"
require "CFBundleShortVersionString ($INFO_PLIST)" "$VERSION"
TAG="ios/$VERSION-build.$BUILD-$SHORT"

# No repair/download after HEAD has been fixed. Both calls must succeed before archive.
echo "== P0C release preflight: $VERSION ($BUILD) from $SHORT =="
scripts/verify_product_catalogue.sh "$RESOURCES" || {
  echo "ABORTADO: product catalogue verification failed before archive" >&2; exit 9;
}
python3 scripts/verify_catalog_release.py preflight --resources "$RESOURCES" \
  --head "$SHA" --staging "$STAGING" --evidence-dir "$EVIDENCE_DIR" || {
  echo "ABORTADO: public catalogue provenance could not be verified before archive" >&2; exit 9;
}
echo "== archiving $VERSION ($BUILD) from $SHORT =="
rm -rf "$ARCHIVE" .build/tf-export
if xcodebuild archive -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination "generic/platform=iOS" -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  > /tmp/fm-v2-tf-archive.log 2>&1; then
  :
else
  echo "ABORTADO: archive falhou"; grep -aE 'error:' /tmp/fm-v2-tf-archive.log | head -5 || true; exit 8
fi

APP="$ARCHIVE/Products/Applications/FeedMine.app"
ARCHIVED_SHA="$(/usr/libexec/PlistBuddy -c 'Print :FeedmineGitSHA' "$APP/Info.plist" 2>/dev/null || echo 'absent')"
ARCHIVED_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist" 2>/dev/null || echo '?')"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null || echo '?')"
echo "archived: bundle=$BUNDLE_ID version=$VERSION build=$ARCHIVED_BUILD sha=$ARCHIVED_SHA"

if [ "$BUNDLE_ID" != "com.feedmine.app" ]; then
  echo "ABORTADO: bundle id '$BUNDLE_ID' != com.feedmine.app (record ASC 6793279758)"
  exit 8
fi
if [ "$ARCHIVED_SHA" != "$SHORT" ]; then
  echo "ABORTADO: the archive carries SHA '$ARCHIVED_SHA' but HEAD is '$SHORT' — the pairing is not proven"
  exit 8
fi
# The final archive is the authority on what would be distributed, not Resources.
scripts/verify_product_catalogue.sh "$APP" || {
  echo "ABORTADO: archive contains an unverified or benchmark catalogue" >&2; exit 8;
}
python3 scripts/verify_catalog_release.py archive --resources "$RESOURCES" \
  --archive "$ARCHIVE" --head "$SHA" --version "$VERSION" --build "$BUILD" \
  --staging "$STAGING" --evidence-dir "$EVIDENCE_DIR" || {
  echo "ABORTADO: archive bytes/provenance differ from preflight" >&2; exit 8;
}
echo "PAIRING OK: TestFlight build $VERSION ($ARCHIVED_BUILD) = $SHA"

if [ "$DRY_RUN" = "1" ]; then
  echo "DRY RUN: archive verificado, nada foi enviado e nenhuma tag criada"
  exit 0
fi

# Only an actual upload needs App Store Connect secrets.
if [ -z "${ASC_KEY_ID:-}" ]; then missing_env ASC_KEY_ID; fi
if [ -z "${ASC_ISSUER_ID:-}" ]; then missing_env ASC_ISSUER_ID; fi
KEY_ID="$ASC_KEY_ID"
ISSUER_ID="$ASC_ISSUER_ID"
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8}"
if [ ! -f "$KEY_PATH" ]; then
  echo "ABORTADO: API key ausente em $KEY_PATH" >&2
  exit 9
fi

if xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$EXPORT_OPTS" \
  -exportPath .build/tf-export -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER_ID" > /tmp/fm-v2-tf-upload.log 2>&1; then
  # A log without the marker must not abort after a successful upload (the tag still records it).
  grep -aE "Upload succeeded|Uploaded" /tmp/fm-v2-tf-upload.log | tail -1 || true
else
  echo "ABORTADO: export/upload falhou"; grep -aE "error:" /tmp/fm-v2-tf-upload.log | head -5 || true; exit 8
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "tag $TAG already exists"
else
  git tag -a "$TAG" -m "TestFlight $VERSION ($BUILD) [$SHORT]" "$SHA"
  echo "tag $TAG created (local, not pushed)"
fi
echo "BUILD $VERSION ($BUILD) = $SHA  (tag $TAG)"
