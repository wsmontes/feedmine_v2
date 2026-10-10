#!/bin/bash
# generate_build_info.sh — stamp the git identity into the built app's Info.plist.
#
# Ported from the V1 release pipeline (feedmine-dev). The reason for the pairing is unchanged:
# without it, no uploaded binary can be traced back to a commit. `scripts/release-testflight.sh`
# refuses to upload unless the archive carries the exact HEAD here.
#
# Usage (Xcode Run Script phase, AFTER "Copy Bundle Resources", app target only):
#   bash "${PROJECT_DIR}/scripts/generate_build_info.sh" "${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"
#
# Never fails the build: an unavailable git is recorded as "unknown", not as an error.

set -uo pipefail

INFO_PLIST="${1:-}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"

GIT_SHA=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_BRANCH=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
GIT_TAG=$(git -C "$REPO" describe --tags --exact-match 2>/dev/null || echo "")
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [ -n "$INFO_PLIST" ] && [ -f "$INFO_PLIST" ]; then
  /usr/libexec/PlistBuddy -c "Add :FeedmineGitSHA string ${GIT_SHA}" "$INFO_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :FeedmineGitSHA ${GIT_SHA}" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :FeedmineGitBranch string ${GIT_BRANCH}" "$INFO_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :FeedmineGitBranch ${GIT_BRANCH}" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :FeedmineBuildDate string ${BUILD_DATE}" "$INFO_PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :FeedmineBuildDate ${BUILD_DATE}" "$INFO_PLIST"
  echo "→ build info stamped: SHA=${GIT_SHA} branch=${GIT_BRANCH} date=${BUILD_DATE}"
else
  echo "→ build info: SHA=${GIT_SHA} branch=${GIT_BRANCH} tag=${GIT_TAG:-none} date=${BUILD_DATE}"
  echo "  (no Info.plist at '${INFO_PLIST:-<unset>}' — nothing stamped)"
fi
