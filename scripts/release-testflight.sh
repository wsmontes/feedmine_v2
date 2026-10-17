#!/bin/bash
# TestFlight delivery for the V2 iOS app, with a mandatory build ↔ commit pairing.
#
# Ported from the V1 pipeline (feedmine-dev/scripts/release-testflight.sh). The invariants are:
#   * refuses a dirty working tree — an uploaded binary must be reproducible from a commit;
#   * refuses archive unless current public inventory, compiler and bundled SQLite provenance agree;
#   * archives, then verifies the SHA/branch/build-date written inside the archive against this
#     clean HEAD and release run, aborting on any mismatch;
#   * signs the archive and uploads with the App Store Connect API key (the Xcode Apple-ID path
#     fails on this machine: no Apple identity, profile or account in Xcode); the same key drives
#     cloud signing at archive time and re-signing at export time, both with -allowProvisioningUpdates;
#   * snapshots the export-options plist before the archive, validates that private copy and hands
#     Xcode that same file — so the destination that was checked is the destination Xcode reads;
#   * creates the local annotated tag `ios/<version>-build.<build>-<sha>` and prints the pairing.
#
# It never pushes: `git tag` is local.
#
# Usage: scripts/release-testflight.sh [--dry-run] [--no-upload] [--print-export-options]
#   --dry-run               run the same preflight and archive checks (no ASC key, upload or tag)
#   --no-upload             export the archive without publishing it (alias: --export-only).
#                           Selects scripts/ExportOptions-export-only.plist, whose only difference
#                           from the default plist is `destination` = `export` instead of `upload`.
#                           Without the flag the default is unchanged: the normal plist is used and
#                           -exportArchive uploads to App Store Connect.
#   --print-export-options  print the export options plist that would be passed to xcodebuild plus
#                           its `destination`, then exit without running xcodebuild. Exists so the
#                           selection and the refusal below can be asserted cheaply
#                           (scripts/test-export-options.sh).

set -euo pipefail
# K-03 (Kiro): -e makes any unchecked failure stop the release instead of uploading or tagging
# with empty metadata. Expected non-zero commands are guarded explicitly with `|| true` / `if`.
trap 'echo "ABORTADO: comando falhou na linha $LINENO (exit $?)" >&2' ERR
# The export-options snapshot (see below) must not survive the run, not even an interrupted one.
EXPORT_SNAPSHOT=""
cleanup_snapshot() { [ -n "$EXPORT_SNAPSHOT" ] && rm -f "$EXPORT_SNAPSHOT"; }
trap cleanup_snapshot EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
DRY_RUN=0
NO_UPLOAD=0
PRINT_EXPORT_OPTS=0
usage_error() {
  echo "ABORTADO: $1" >&2
  echo "uso: scripts/release-testflight.sh [--dry-run] [--no-upload|--export-only] [--print-export-options]" >&2
  exit 2
}
# An unknown flag is refused rather than ignored: a typo such as `--no-uplaod` would otherwise
# fall back to the default path and upload, which is exactly the hazard this script guards.
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --dry-run) DRY_RUN=1 ;;
    --no-upload|--export-only) NO_UPLOAD=1 ;;
    --print-export-options) PRINT_EXPORT_OPTS=1 ;;
    *) usage_error "argumento desconhecido: $1" ;;
  esac
  shift
done

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
# Test seam, defaults unchanged: scripts/test-export-options.sh points these at throwaway copies
# so it can exercise the plist selection (including an uploading plist on the export-only path)
# without ever writing a file the repository tracks.
EXPORT_OPTS_UPLOAD="${FM_EXPORT_OPTS_UPLOAD:-scripts/ExportOptions.plist}"
EXPORT_OPTS_EXPORT_ONLY="${FM_EXPORT_OPTS_EXPORT_ONLY:-scripts/ExportOptions-export-only.plist}"
EXPORT_OPTS="$EXPORT_OPTS_UPLOAD"
if [ "$NO_UPLOAD" = "1" ]; then EXPORT_OPTS="$EXPORT_OPTS_EXPORT_ONLY"; fi
STAGING="${P0C_STAGING_ROOT:-build/catalog-bootstrap}"
EVIDENCE_DIR="${P0C_EVIDENCE_DIR:-.build}"

plist_destination() {
  /usr/libexec/PlistBuddy -c 'Print :destination' "$1" 2>/dev/null || echo '?'
}

# H-EXPORT (measured 2026-10-17): $EXPORT_OPTS_UPLOAD declares method=app-store-connect and
# destination=upload, so -exportArchive PUBLISHES the ipa as a side effect of exporting. A
# rehearsal had to hand-edit a copy to destination=export to avoid the upload.
#
# Validate and use must be the SAME bytes. The selection above is a path, and the archive takes
# minutes: if that file changed between validation here and -exportArchive below, the validated
# destination would no longer describe what Xcode reads. So the selected plist is snapshotted once,
# now, into a private 600 temporary file; THAT copy is validated, THAT copy is handed to xcodebuild,
# and "nothing was sent" below is derived from the destination recorded here, never from the flag.
if [ ! -f "$EXPORT_OPTS" ]; then
  if [ "$NO_UPLOAD" = "1" ]; then
    echo "ABORTADO: --no-upload exige $EXPORT_OPTS, que não existe — sem esse plist o export não tem como recusar destination=upload" >&2
  else
    echo "ABORTADO: plist de export ausente: $EXPORT_OPTS" >&2
  fi
  exit 9
fi
if ! EXPORT_SNAPSHOT="$(mktemp -t fm-export-options)" || ! cp "$EXPORT_OPTS" "$EXPORT_SNAPSHOT"; then
  echo "ABORTADO: não foi possível copiar $EXPORT_OPTS para um arquivo temporário privado" >&2
  exit 9
fi
chmod 600 "$EXPORT_SNAPSHOT"
EXPORT_DEST="$(plist_destination "$EXPORT_SNAPSHOT")"
if [ "$NO_UPLOAD" = "1" ]; then
  if [ "$EXPORT_DEST" != "export" ]; then
    echo "ABORTADO: --no-upload com $EXPORT_OPTS, mas o plist diz destination=$EXPORT_DEST — exportar publicaria a build. A chave destination precisa ser 'export' (nenhuma outra) para esta opção" >&2
    exit 9
  fi
fi

if [ "$PRINT_EXPORT_OPTS" = "1" ]; then
  echo "EXPORT_OPTS=$EXPORT_OPTS"
  echo "destination=$EXPORT_DEST"
  case "$EXPORT_DEST" in
    upload) echo "upload=yes" ;;
    *) echo "upload=no" ;;
  esac
  exit 0
fi

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
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
BUILD_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
require "git SHA" "$SHA"
require "git short SHA" "$SHORT"
require "git branch" "$BRANCH"
require "build date" "$BUILD_DATE"
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
# Signing flags for BOTH xcodebuild calls (archive below, -exportArchive further down): defined
# once, so the export cannot drift from the archive. The archive gets the ASC key too — on a clean
# machine that is what mints/renews the signing identity, and the export must re-sign with the very
# same credentials; otherwise export fails by signing only after the ~130 s archive. A dry run
# never exports and is documented to run without secrets, so it stays on -allowProvisioningUpdates.
SIGNING_FLAGS=(-allowProvisioningUpdates)
if [ "$DRY_RUN" != "1" ]; then
  if [ -z "${ASC_KEY_ID:-}" ]; then missing_env ASC_KEY_ID; fi
  if [ -z "${ASC_ISSUER_ID:-}" ]; then missing_env ASC_ISSUER_ID; fi
  KEY_ID="$ASC_KEY_ID"
  ISSUER_ID="$ASC_ISSUER_ID"
  KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8}"
  if [ ! -f "$KEY_PATH" ]; then
    echo "ABORTADO: API key ausente em $KEY_PATH" >&2
    exit 9
  fi
  SIGNING_FLAGS+=(-authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$KEY_ID" \
    -authenticationKeyIssuerID "$ISSUER_ID")
fi

echo "== archiving $VERSION ($BUILD) from $SHORT =="
rm -rf "$ARCHIVE" .build/tf-export
# Pass available ASC credentials to archive-time provisioning as well as export-time re-signing.
# Without them, dry-run can still use local signing assets.
# The guarded array expansion supports an empty array under Bash 3.2 with `set -u`.
KEY_ID="${ASC_KEY_ID:-}"
ISSUER_ID="${ASC_ISSUER_ID:-}"
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8}"
SIGN_ARGS=()
if [ -n "$KEY_ID" ] && [ -n "$ISSUER_ID" ]; then
  SIGN_ARGS=(-authenticationKeyPath "$KEY_PATH"
             -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER_ID")
fi
# The app's Info.plist carries FEEDMINE_GIT_SHA/BRANCH/BUILD_DATE placeholders, expanded by
# ProcessInfoPlistFile. They are passed as command-line build settings, not exported environment:
# xcodebuild only turns the NAME=VALUE arguments into build settings. This makes the plist writer
# own the identity, so no run-script phase can race with/after it (see
# docs/reviews/FEEDMINE_V2_RELEASE_EVIDENCE.md). Defaults in the project are "unknown", so a build
# without these overrides fails the archive checks below instead of storing a stale SHA.
if xcodebuild archive -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination "generic/platform=iOS" -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  FEEDMINE_GIT_SHA="$SHORT" FEEDMINE_GIT_BRANCH="$BRANCH" FEEDMINE_BUILD_DATE="$BUILD_DATE" \
  ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} \
  > /tmp/fm-v2-tf-archive.log 2>&1; then
  :
else
  echo "ABORTADO: archive falhou"; grep -aE 'error:' /tmp/fm-v2-tf-archive.log | head -5 || true; exit 8
fi

APP="$ARCHIVE/Products/Applications/FeedMine.app"
ARCHIVED_SHA="$(/usr/libexec/PlistBuddy -c 'Print :FeedmineGitSHA' "$APP/Info.plist" 2>/dev/null || echo 'absent')"
ARCHIVED_BRANCH="$(/usr/libexec/PlistBuddy -c 'Print :FeedmineGitBranch' "$APP/Info.plist" 2>/dev/null || echo 'absent')"
ARCHIVED_DATE="$(/usr/libexec/PlistBuddy -c 'Print :FeedmineBuildDate' "$APP/Info.plist" 2>/dev/null || echo 'absent')"
ARCHIVED_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist" 2>/dev/null || echo '?')"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null || echo '?')"
echo "archived: bundle=$BUNDLE_ID version=$VERSION build=$ARCHIVED_BUILD sha=$ARCHIVED_SHA branch=$ARCHIVED_BRANCH date=$ARCHIVED_DATE"

if [ "$BUNDLE_ID" != "com.feedmine.app" ]; then
  echo "ABORTADO: bundle id '$BUNDLE_ID' != com.feedmine.app (record ASC 6793279758)"
  exit 8
fi
if [ "$ARCHIVED_SHA" != "$SHORT" ]; then
  echo "ABORTADO: the archive carries SHA '$ARCHIVED_SHA' but HEAD is '$SHORT' — the pairing is not proven"
  exit 8
fi
if [ "$ARCHIVED_BRANCH" != "$BRANCH" ]; then
  echo "ABORTADO: the archive carries branch '$ARCHIVED_BRANCH' but this build is from '$BRANCH'"
  exit 8
fi
if [ "$ARCHIVED_DATE" != "$BUILD_DATE" ]; then
  echo "ABORTADO: the archive carries build date '$ARCHIVED_DATE' but this release started at '$BUILD_DATE'"
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

# Export re-signs the archive and may need cloud-managed provisioning assets.
if [ -z "$KEY_ID" ]; then missing_env ASC_KEY_ID; fi
if [ -z "$ISSUER_ID" ]; then missing_env ASC_ISSUER_ID; fi
if [ ! -f "$KEY_PATH" ]; then
  echo "ABORTADO: API key ausente em $KEY_PATH" >&2
  exit 9
fi

if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$EXPORT_SNAPSHOT" \
  -exportPath .build/tf-export -allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER_ID" > /tmp/fm-v2-tf-upload.log 2>&1; then
  echo "ABORTADO: export/upload falhou"; grep -aE "error:" /tmp/fm-v2-tf-upload.log | head -5 || true; exit 8
fi

if [ "$EXPORT_DEST" != "upload" ]; then
  # Derived from the validated snapshot's own destination, not from the flag: if that destination
  # is not `upload` nothing was published, so neither the upload marker nor the delivery tag
  # applies — the tag names an uploaded TestFlight build, and creating it here would claim a
  # delivery that never happened. The ipa stays in .build/tf-export for inspection/hand-off.
  echo "NO UPLOAD: export em .build/tf-export a partir de $EXPORT_OPTS (destination=$EXPORT_DEST, o snapshot validado) — nada enviado e nenhuma tag criada"
  ls -1 .build/tf-export/*.ipa 2>/dev/null || true
  exit 0
fi

# A log without the marker must not abort after a successful upload (the tag still records it).
grep -aE "Upload succeeded|Uploaded" /tmp/fm-v2-tf-upload.log | tail -1 || true

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "tag $TAG already exists"
else
  git tag -a "$TAG" -m "TestFlight $VERSION ($BUILD) [$SHORT]" "$SHA"
  echo "tag $TAG created (local, not pushed)"
fi
echo "BUILD $VERSION ($BUILD) = $SHA  (tag $TAG)"
