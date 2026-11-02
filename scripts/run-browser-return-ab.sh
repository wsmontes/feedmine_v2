#!/usr/bin/env bash
# FeedMine issue #18: compare the same Safari return UI test on PR #10 and PR #13.
# Run on a Mac with Xcode, an iOS simulator, and the already prepared PRODUCT
# catalog.sqlite/catalog.manifest.json pair. Does not regenerate the catalogue.
set -euo pipefail
if [[ "$#" -ne 3 && "$#" -ne 4 ]]; then
  echo "usage: $0 CATALOG_SQLITE CATALOG_MANIFEST SIMULATOR_UDID [RESULTS_DIR]" >&2
  exit 2
fi
for tool in git python3 xcodebuild xcrun cmp; do
  command -v "$tool" >/dev/null || { echo "REFUSED: missing $tool" >&2; exit 2; }
done
ROOT="$(git rev-parse --show-toplevel)"
CATALOG="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).expanduser().resolve())' "$1")"
MANIFEST="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).expanduser().resolve())' "$2")"
UDID="$3"
CONTROL_SHA=f4f041c04c4502f8e43bce8bec72b841dbe01ebc
EXPERIMENT_SHA=cf2ce6a8045d5446abaf92a85a8da10c9f80b12c
TEST_BLOB=b94cfaa074dacf74c023427674ca9e10d4796ab3
[[ -f "$CATALOG" && -f "$MANIFEST" ]] || { echo "REFUSED: catalogue pair missing" >&2; exit 2; }
cmp -s "$MANIFEST" "$ROOT/FeedMineApp/FeedMineApp/Resources/catalog.manifest.json" || {
  echo "REFUSED: descriptor differs from product descriptor" >&2; exit 2;
}
python3 - "$CATALOG" "$MANIFEST" <<'PY'
import hashlib,json,os,sys
database,manifest=sys.argv[1:]
with open(manifest) as handle: descriptor=json.load(handle)
matches=[x for x in descriptor["files"] if x.get("role")=="catalogue" and x.get("path")=="catalog.sqlite"]
if len(matches)!=1: sys.exit("REFUSED: invalid catalogue entry")
entry=matches[0]
digest=hashlib.sha256()
with open(database,"rb") as handle:
    for chunk in iter(lambda:handle.read(1048576),b""): digest.update(chunk)
if os.path.getsize(database)!=entry["bytes"] or digest.hexdigest()!=entry["sha256"]:
    sys.exit("REFUSED: catalogue size/hash differs from product manifest")
print("Verified catalogue SHA-256:",digest.hexdigest())
PY
xcrun simctl list devices available | grep -F "$UDID" >/dev/null || {
  echo "REFUSED: simulator not available: $UDID" >&2; exit 2;
}
RESULTS="$ROOT/build/browser-return-ab-$(date -u +%Y%m%dT%H%M%SZ)"
if [[ "$#" -eq 4 ]]; then RESULTS="$4"; fi
mkdir -p "$RESULTS"
RESULTS="$(cd "$RESULTS" && pwd)"
[[ ! -e "$RESULTS/control.xcresult" && ! -e "$RESULTS/experiment.xcresult" ]] || {
  echo "REFUSED: existing result bundle; choose another directory" >&2; exit 2;
}
git -C "$ROOT" fetch --no-tags origin \
  '+refs/heads/audit/browser-return-identity-regression-20261030:refs/remotes/origin/audit/browser-return-identity-regression-20261030' \
  '+refs/heads/experiment/reader-host-over-full-screen-20261030:refs/remotes/origin/experiment/reader-host-over-full-screen-20261030'
[[ "$(git -C "$ROOT" rev-parse refs/remotes/origin/audit/browser-return-identity-regression-20261030)" == "$CONTROL_SHA" ]] || {
  echo "REFUSED: PR #10 HEAD moved" >&2; exit 2;
}
[[ "$(git -C "$ROOT" rev-parse refs/remotes/origin/experiment/reader-host-over-full-screen-20261030)" == "$EXPERIMENT_SHA" ]] || {
  echo "REFUSED: PR #13 HEAD moved" >&2; exit 2;
}
SCRATCH="$(mktemp -d)"
cleanup() {
  git -C "$ROOT" worktree remove --force "$SCRATCH/control" 2>/dev/null || true
  git -C "$ROOT" worktree remove --force "$SCRATCH/experiment" 2>/dev/null || true
  rmdir "$SCRATCH" 2>/dev/null || true
}
trap cleanup EXIT
git -C "$ROOT" worktree add --detach "$SCRATCH/control" "$CONTROL_SHA"
git -C "$ROOT" worktree add --detach "$SCRATCH/experiment" "$EXPERIMENT_SHA"
echo "control=$CONTROL_SHA experiment=$EXPERIMENT_SHA testBlob=$TEST_BLOB simulator=$UDID" > "$RESULTS/provenance.txt"
for arm in control experiment; do
  tree="$SCRATCH/$arm"
  resource="$tree/FeedMineApp/FeedMineApp/Resources"
  testfile=FeedMineApp/FeedMineAppTests/ReadingSurfaceUITests.swift
  [[ "$(git -C "$tree" hash-object "$testfile")" == "$TEST_BLOB" ]] || {
    echo "REFUSED: tests are not byte-identical" >&2; exit 2;
  }
  cmp -s "$resource/catalog.manifest.json" "$MANIFEST" || {
    echo "REFUSED: branch product manifest differs" >&2; exit 2;
  }
  cp "$CATALOG" "$resource/catalog.sqlite"
  "$tree/scripts/verify_product_catalogue.sh" "$resource" > "$RESULTS/$arm-catalogue.log" 2>&1 || {
    cat "$RESULTS/$arm-catalogue.log" >&2; exit 2;
  }
done
for arm in control experiment; do
  echo "Testing $arm..."
  if (cd "$SCRATCH/$arm" && xcodebuild test \
    -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -configuration Debug \
    -destination "platform=iOS Simulator,id=$UDID" -parallel-testing-enabled NO \
    -derivedDataPath "$RESULTS/DerivedData-$arm" \
    -resultBundlePath "$RESULTS/$arm.xcresult" \
    -only-testing:FeedMineUITests/ReadingSurfaceUITests/testClosingSitePreservesScrolledCardIdentityAndFrameWithDeepHistory \
    -only-testing:FeedMineUITests/ReadingSurfaceUITests/testOpeningTheSiteFromTheLocalReaderIsAnExplicitRequestAndComesBackToTheFeed \
    CODE_SIGNING_ALLOWED=NO > "$RESULTS/$arm-build.log" 2>&1); then
    echo "$arm exit=0" | tee -a "$RESULTS/provenance.txt"
  else
    status="$?"
    echo "$arm exit=$status" | tee -a "$RESULTS/provenance.txt"
  fi
done
echo "Inspect $RESULTS/{control,experiment}.xcresult and per-arm logs."
echo "This does not exercise the separate publication-during-Safari acceptance case."
