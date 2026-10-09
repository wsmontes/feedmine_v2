#!/bin/sh
# Downloads the bundled V1 catalog (PD-2 / review F02) into the app resources and verifies it.
# The catalog is a GitHub release asset, not Git/LFS content: run this once after cloning.
# Idempotent: a file that already has the expected checksum is kept as is.
set -eu

TAG="catalog-v1"
URL="https://github.com/wsmontes/feedmine_v2/releases/download/${TAG}/catalog.sqlite"
SHA256="c2ae483a7525fd2b6797855149eb6fb312abbed788549a90a7754121eb5c8629"
SIZE=117940224

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/FeedMineApp/FeedMineApp/Resources/catalog.sqlite"

# OMP K7: check tools before a 118 MB download, so a missing tool is not blamed on the download.
if command -v shasum >/dev/null 2>&1; then SHA_TOOL="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then SHA_TOOL="sha256sum"
else echo "error: shasum or sha256sum is required" >&2; exit 1; fi
command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 1; }

sha256_of() {
    $SHA_TOOL "$1" | cut -d ' ' -f 1
}

valid() {
    [ -f "$1" ] && [ "$(wc -c < "$1" | tr -d ' ')" = "$SIZE" ] && [ "$(sha256_of "$1")" = "$SHA256" ]
}

if valid "$DEST"; then
    echo "catalog.sqlite already present and verified"
    exit 0
fi

TMP="${DEST}.download"
trap 'rm -f "$TMP"' EXIT
echo "downloading ${URL}"
curl --fail --location --silent --show-error --output "$TMP" "$URL"
if ! valid "$TMP"; then
    echo "error: downloaded catalog does not match size ${SIZE} / sha256 ${SHA256}" >&2
    exit 1
fi
mv -f "$TMP" "$DEST"
echo "catalog.sqlite installed and verified"
