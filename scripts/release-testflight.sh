#!/bin/bash
# TestFlight delivery for the V2 iOS app, with a mandatory build ↔ commit pairing.
#
# Ported from the V1 pipeline (feedmine-dev/scripts/release-testflight.sh). The invariants are:
#   * refuses a dirty working tree — an uploaded binary must be reproducible from a commit;
#   * refuses to archive without the bundled V1 catalog (the release build hard-fails on it anyway);
#   * archives, then verifies the git SHA stamped inside the archive against HEAD, aborting on mismatch;
#   * uploads with the App Store Connect API key (the Xcode Apple-ID path fails on this machine);
#   * creates the local annotated tag `ios/<version>-build.<build>-<sha>` and prints the pairing.
#
# It never pushes: `git tag` is local.
#
# Usage: scripts/release-testflight.sh [--dry-run]
#   --dry-run  stop after verifying the archived SHA (no upload, no tag)

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_H3U55Z9WZ7.p8"
KEY_ID="H3U55Z9WZ7"
ISSUER_ID="0e1bd229-1284-4916-91d2-7bf989859bcc"
PROJECT="FeedMineApp/FeedMineApp.xcodeproj"
SCHEME="FeedMine"
INFO_PLIST="FeedMineApp/FeedMineApp/Info.plist"
CATALOG="FeedMineApp/FeedMineApp/Resources/catalog.sqlite"
ARCHIVE=".build/feedmine-v2.xcarchive"
EXPORT_OPTS="scripts/ExportOptions.plist"

if [ -n "$(git status --porcelain)" ]; then
  echo "ABORTADO: working tree is dirty — commit first, or the uploaded binary maps to no SHA"
  git status --short | head -10
  exit 9
fi

if [ ! -f "$CATALOG" ]; then
  echo "ABORTADO: $CATALOG ausente — rode scripts/fetch-catalog.sh primeiro"
  exit 9
fi

if [ ! -f "$KEY_PATH" ]; then
  echo "ABORTADO: API key ausente em $KEY_PATH"
  exit 9
fi

SHA="$(git rev-parse HEAD)"
SHORT="$(git rev-parse --short HEAD)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
TAG="ios/$VERSION-build.$BUILD-$SHORT"

echo "== archiving $VERSION ($BUILD) from $SHORT =="
rm -rf "$ARCHIVE" .build/tf-export
if xcodebuild archive -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination "generic/platform=iOS" -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  > /tmp/fm-v2-tf-archive.log 2>&1; then
  :
else
  echo "ABORTADO: archive falhou"; grep -aE 'error:' /tmp/fm-v2-tf-archive.log | head -5; exit 8
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
echo "PAIRING OK: TestFlight build $VERSION ($ARCHIVED_BUILD) = $SHA"

if [ "$DRY_RUN" = "1" ]; then
  echo "DRY RUN: archive verificado, nada foi enviado e nenhuma tag criada"
  exit 0
fi

if xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$EXPORT_OPTS" \
  -exportPath .build/tf-export -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER_ID" > /tmp/fm-v2-tf-upload.log 2>&1; then
  grep -aE "Upload succeeded|Uploaded" /tmp/fm-v2-tf-upload.log | tail -1
else
  echo "ABORTADO: export/upload falhou"; grep -aE "error:" /tmp/fm-v2-tf-upload.log | head -5; exit 8
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "tag $TAG already exists"
else
  git tag -a "$TAG" -m "TestFlight $VERSION ($BUILD) [$SHORT]" "$SHA" && echo "tag $TAG created (local, not pushed)"
fi
echo "BUILD $VERSION ($BUILD) = $SHA  (tag $TAG)"
