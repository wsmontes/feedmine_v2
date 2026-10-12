#!/usr/bin/env bash
# Which catalogue does this FeedMine build carry — the product's or the benchmark's — and is it the one the
# descriptor declares for it?
#
# bench/run.sh copies the corpus's reduced catalogue into the *built* FeedMine.app and rewrites the
# catalog.manifest.json beside it, and the test run installs that build on the run's device. Nothing restored the
# product build afterwards, so a later manual or product evaluation could silently run the benchmark build: outside
# a run its transport is a server that does not exist, and the reader appears to publish nothing.
#
# The verdict is by identity, never by a number remembered in this file:
#   * `catalog_metadata` must not carry a `bench_corpus` key — the benchmark's own declaration of what it is;
#   * the catalogue beside the descriptor must be the one that descriptor declares: same byte count, same SHA-256,
#     and the descriptor's `sourceCount` must be the `source_count` the catalogue declares about itself;
#   * the catalogue's own claims must be sane: `catalog_version` a positive 64-bit microsecond stamp (the value the
#     app's compiler stamps), `schema_version` the one this build reads;
#   * that descriptor must be the descriptor the repository ships beside its own catalogue — same `revision`, same
#     `sourceCount`, same `fileCount`, same `files[0]` and same catalogue entry — so a *different* catalogue cannot
#     masquerade as the expected one by carrying a descriptor that agrees with itself.
#
# Handed a `.app`, it checks the bundle. Handed a data container for which no product bundle resolves, it verifies
# the catalogue that container actually carries (the snapshot the app activated, or the catalogue its pointer names)
# by byte count and SHA-256 against the repository descriptor.
#
# Read-only: it writes to neither the bundle, the container, the simulator nor the repository.
#
#   scripts/verify_product_catalogue.sh /path/to/FeedMine.app
#   scripts/verify_product_catalogue.sh "$(xcrun simctl get_app_container booted com.feedmine.development app)"
#   scripts/verify_product_catalogue.sh "$(xcrun simctl get_app_container booted com.feedmine.development data)"
#   scripts/verify_product_catalogue.sh 8871DCF5-0C06-4C7C-88D2-7B3DC36E8284
#   scripts/verify_product_catalogue.sh booted
#
# Exit 0: the product catalogue, verified against the descriptor the repository ships.
# Exit 1: refused — the benchmark corpus, a catalogue that does not match its descriptor, or a corrupted one.
# Exit 2: usage, or nothing to read.
set -euo pipefail

BUNDLE_ID="com.feedmine.development"
UUID_RE='^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# The descriptor the product build ships and this repository holds: the authority for what the product catalogue is
# (revision, sourceCount, the catalogue entry's byte count and SHA-256). Everything below is compared against it.
REPO_MANIFEST="$ROOT/FeedMineApp/FeedMineApp/Resources/catalog.manifest.json"

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "usage: $(basename "$0") <FeedMine.app | app data container | simulator UDID|booted>" >&2
  exit 2
fi
if [[ ! -f "$REPO_MANIFEST" ]]; then
  echo "REFUSED: the repository descriptor is missing: $REPO_MANIFEST" >&2
  echo "  it is the expected identity every build is compared against; without it nothing can be verified" >&2
  exit 2
fi
command -v sqlite3 >/dev/null 2>&1 || { echo "REFUSED: sqlite3 is not available to read a catalogue" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "REFUSED: python3 is not available to read the descriptors" >&2; exit 2; }

# The expected identity, read from the repository descriptor rather than remembered here.
REPO_IDENTITY="$(python3 -c '
import json, sys
descriptor = json.load(open(sys.argv[1]))
entries = [entry for entry in descriptor["files"] if str(entry["path"]).lower().endswith(".sqlite")]
if len(entries) != 1:
    sys.exit("the repository descriptor declares %d catalogue entries" % len(entries))
entry = entries[0]
print(descriptor["schemaVersion"], descriptor["revision"], descriptor["sourceCount"], descriptor["fileCount"],
      entry["bytes"], entry["sha256"], entry["path"])
' "$REPO_MANIFEST")" || {
  echo "REFUSED: $REPO_MANIFEST is not a readable catalogue descriptor or names no single catalogue" >&2
  exit 2
}
read -r REPO_SCHEMA REPO_REVISION REPO_SOURCE_COUNT REPO_FILE_COUNT REPO_CATALOGUE_BYTES REPO_CATALOGUE_SHA256 REPO_CATALOGUE_PATH <<< "$REPO_IDENTITY"

# A data container holds no catalogue of its own: the app's catalogue lives in its bundle, so a container path or a
# bare device is first resolved to the bundle the simulator installed. CoreSimulator lays a container out as
# …/Devices/<UDID>/data/Containers/Data/Application/<UUID>, which names the device the bundle belongs to.
bundle_from_device() {
  local path="$1" rest udid=""
  if [[ "$path" == */Devices/*/data/Containers/* ]]; then
    rest="${path#*/Devices/}"
    udid="${rest%%/data/Containers/*}"
  elif [[ "$path" == "booted" || "$path" =~ $UUID_RE ]]; then
    udid="$path"
  else
    return 1
  fi
  [[ -n "$udid" ]] || return 1
  xcrun simctl get_app_container "$udid" "$BUNDLE_ID" app 2>/dev/null
}

# The catalogue a data container carries: the byte count and SHA-256 of the snapshot the app activated, or of the
# copy its active pointer names, against the repository descriptor. Only a file that can be read and hashed is
# evidence; the app's own recorded fingerprint is reported, never trusted on its own.
verify_container_catalogue() {
  local container="$1"
  python3 - "$container" "$REPO_MANIFEST" <<'PY'
import glob, hashlib, json, os, sys

container, repository = sys.argv[1:3]
namespace_root = os.path.join(container, "Library/Application Support/FeedMine")


def load(path):
    with open(path) as handle:
        return json.load(handle)


def sha256_and_size(path):
    hasher = hashlib.sha256()
    size = 0
    with open(path, "rb") as handle:
        while True:
            chunk = handle.read(1 << 20)
            if not chunk:
                break
            hasher.update(chunk)
            size += len(chunk)
    return size, hasher.hexdigest()


try:
    expected = load(repository)
    expected_entry = [entry for entry in expected["files"]
                      if str(entry["path"]).lower().endswith(".sqlite")][0]
except Exception as error:
    print(f"REFUSED: the repository descriptor is unreadable: {error}")
    sys.exit(1)

candidates = []
for pointer in sorted(glob.glob(os.path.join(namespace_root, "*", "catalogue", "active.json"))):
    try:
        recorded = load(pointer)
    except Exception as error:
        candidates.append((pointer, None, f"unreadable pointer: {error}"))
        continue
    named = recorded.get("cataloguePath") or ""
    candidates.append((pointer, named if os.path.isfile(named) else None,
                       f"pointer fingerprint {recorded.get('fingerprint')}, names {named!r}"))
for snapshot in sorted(glob.glob(os.path.join(namespace_root, "*", "catalogue", "snapshots", "*", "catalog.sqlite"))):
    candidates.append((snapshot, snapshot, "snapshot the app activated"))

readable = [(label, path, detail) for label, path, detail in candidates if path]
if not readable:
    print(f"REFUSED: {container} carries no catalogue to verify")
    print(f"  neither a snapshot under {namespace_root}/*/catalogue/snapshots nor a readable copy named by a pointer")
    print(f"  the repository descriptor declares {expected_entry['bytes']} bytes, sha256 {expected_entry['sha256']},"
          f" revision {expected['revision']}, sourceCount {expected['sourceCount']}")
    sys.exit(2)

for label, path, detail in readable:
    size, digest = sha256_and_size(path)
    if size == expected_entry["bytes"] and digest == expected_entry["sha256"]:
        print("product catalogue: OK")
        print(f"  container: {container}")
        print(f"  catalogue: {path} ({size} bytes, sha256 {digest})")
        print(f"  identity: revision {expected['revision']}, sourceCount {expected['sourceCount']},"
              f" schemaVersion {expected['schemaVersion']}, catalogue entry sha256 {expected_entry['sha256']}")
        print("  checked: the carried catalogue against the repository descriptor (bytes + sha256), and the"
              " descriptor's own structure")
        sys.exit(0)

print(f"REFUSED: the catalogue this container carries is not the one the repository descriptor declares")
print(f"  container: {container}")
print(f"  expected: {expected_entry['bytes']} bytes, sha256 {expected_entry['sha256']}"
      f" (revision {expected['revision']}, sourceCount {expected['sourceCount']})")
for label, path, detail in readable:
    size, digest = sha256_and_size(path)
    print(f"  found: {label} ({detail}) — {size} bytes, sha256 {digest}")
sys.exit(1)
PY
}

APP=""
CONTAINER=""
if [[ -f "$TARGET/catalog.sqlite" ]]; then
  APP="$TARGET"
else
  if [[ -d "$TARGET" && "$TARGET" == */data/Containers/* ]]; then
    CONTAINER="$TARGET"
  fi
  RESOLVED="$(bundle_from_device "$TARGET" || true)"
  if [[ -n "$RESOLVED" && -f "$RESOLVED/catalog.sqlite" ]]; then
    APP="$RESOLVED"
  fi
fi
if [[ -z "$APP" && -n "$CONTAINER" ]]; then
  # No product bundle resolves for that container, so the catalogue under test is the one the container carries.
  verify_container_catalogue "$CONTAINER"
  exit 0
fi
if [[ -z "$APP" ]]; then
  echo "REFUSED: no catalog.sqlite at '$TARGET', and no installed $BUNDLE_ID bundle carrying one" >&2
  echo "  pass a FeedMine.app path, an app data container, or a simulator UDID (or 'booted')" >&2
  exit 2
fi
DB="$APP/catalog.sqlite"
if [[ ! -f "$DB" ]]; then
  echo "REFUSED: $DB does not exist" >&2
  exit 2
fi

# The table is the app's own declaration of what it carries: read it, never infer it from the descriptor, which the
# injection rewrites too.
ROWS="$(sqlite3 -readonly "$DB" "SELECT key || '=' || value FROM catalog_metadata ORDER BY key;" 2>&1)" || {
  echo "REFUSED: $DB is not a readable catalogue (corrupted): $ROWS" >&2
  exit 1
}
if [[ -z "$ROWS" ]]; then
  echo "REFUSED: $DB declares no catalog_metadata, so its catalogue cannot be identified" >&2
  exit 1
fi

BENCH_ROWS=""
SOURCE_COUNT=""
CATALOG_VERSION=""
SCHEMA_VERSION=""
while IFS='=' read -r key value; do
  case "$key" in
    source_count) SOURCE_COUNT="$value" ;;
    catalog_version) CATALOG_VERSION="$value" ;;
    schema_version) SCHEMA_VERSION="$value" ;;
  esac
  case "$key" in
    bench_corpus*) BENCH_ROWS+="${key}=${value}"$'\n' ;;
  esac
done <<< "$ROWS"

if [[ -n "$BENCH_ROWS" ]]; then
  echo "REFUSED: LEAK — this build carries the benchmark corpus, not the product catalogue" >&2
  echo "  bundle: $APP" >&2
  echo "  catalogue: $DB" >&2
  while IFS= read -r row; do
    [[ -n "$row" ]] && echo "  $row" >&2
  done <<< "$BENCH_ROWS"
  echo "  source_count: ${SOURCE_COUNT:-(not declared)} (the corpus slice; the repository descriptor declares $REPO_SOURCE_COUNT)" >&2
  echo "  bench/run.sh injected this catalogue into the build it installed, and outside a run its transport" >&2
  echo "  (bench/serve.py on 127.0.0.1:8757) does not exist, so this app publishes nothing. Put the product" >&2
  echo "  build back before evaluating UX:" >&2
  echo "    xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath /tmp/feedmine-product-derived build" >&2
  echo "    xcrun simctl install booted /tmp/feedmine-product-derived/Build/Products/Debug-iphonesimulator/FeedMine.app" >&2
  echo "  then run this script again: exit 0 means the product catalogue is in place." >&2
  exit 1
fi

# The descriptor beside the catalogue is what makes the copy verifiable, so the identity, integrity and structure
# checks all happen in one place and print what they compared.
if python3 - "$APP" "$REPO_MANIFEST" "$SOURCE_COUNT" "$CATALOG_VERSION" "$SCHEMA_VERSION" <<'PY'
import hashlib, json, os, sys

app, repository, source_count, catalog_version, schema_version = sys.argv[1:6]
catalogue = os.path.join(app, "catalog.sqlite")
descriptor_path = os.path.join(app, "catalog.manifest.json")
CATALOGUE_NAME = "catalog.sqlite"
READER_SCHEMA_VERSION = 2
INT64_MAX = 9223372036854775807
MICROSECONDS_2015 = 1420070400000000
MICROSECONDS_2100 = 4102444800000000


def load(path):
    with open(path) as handle:
        return json.load(handle)


def sha256_and_size(path):
    hasher = hashlib.sha256()
    size = 0
    with open(path, "rb") as handle:
        while True:
            chunk = handle.read(1 << 20)
            if not chunk:
                break
            hasher.update(chunk)
            size += len(chunk)
    return size, hasher.hexdigest()


def catalogue_entry(descriptor):
    entries = [entry for entry in descriptor.get("files") or []
               if str(entry.get("path", "")).lower().endswith(".sqlite")]
    return entries[0] if len(entries) == 1 else None


def declared_integer(value):
    return isinstance(value, str) and value.isdigit() and int(value) > 0


try:
    expected = load(repository)
    expected_entry = catalogue_entry(expected)
except Exception as error:
    print(f"REFUSED: the repository descriptor {repository} is unreadable: {error}")
    sys.exit(1)
if expected_entry is None:
    print(f"REFUSED: {repository} declares no single catalogue entry, so no identity can be compared")
    sys.exit(1)

if not os.path.isfile(descriptor_path):
    print(f"REFUSED: {app} carries a catalogue with no catalog.manifest.json beside it")
    print("  the descriptor is what declares which catalogue the build ships: without it the copy cannot be")
    print(f"  verified as the product catalogue (revision {expected['revision']}, sourceCount {expected['sourceCount']},")
    print(f"  catalogue sha256 {expected_entry['sha256']})")
    sys.exit(1)
try:
    declared = load(descriptor_path)
except Exception as error:
    print(f"REFUSED: {descriptor_path} is not readable JSON (corrupted): {error}")
    sys.exit(1)

reasons = []
size, digest = sha256_and_size(catalogue)
entry = catalogue_entry(declared)

if declared.get("schemaVersion") != expected.get("schemaVersion"):
    reasons.append(f"descriptor schemaVersion {declared.get('schemaVersion')!r} is not {expected.get('schemaVersion')!r}")
if declared.get("revision") != expected.get("revision"):
    reasons.append(f"descriptor revision {declared.get('revision')!r} is not the repository's {expected.get('revision')!r}")
if declared.get("sourceCount") != expected.get("sourceCount"):
    reasons.append(f"descriptor sourceCount {declared.get('sourceCount')!r} is not the repository's"
                   f" {expected.get('sourceCount')!r}")
files = declared.get("files") or []
if declared.get("fileCount") != len(files):
    reasons.append(f"descriptor fileCount {declared.get('fileCount')!r} is not its own inventory's size {len(files)}")
if entry is None or entry.get("path") != CATALOGUE_NAME:
    reasons.append(f"the descriptor declares no single {CATALOGUE_NAME} entry (found"
                   f" {[entry.get('path') for entry in files if str(entry.get('path', '')).lower().endswith('.sqlite')] if files else []})")
else:
    if entry.get("bytes") != size:
        reasons.append(f"{CATALOGUE_NAME} is {size} bytes; the descriptor declares {entry.get('bytes')!r}")
    if str(entry.get("sha256", "")).lower() != digest:
        reasons.append(f"{CATALOGUE_NAME} sha256 is {digest}; the descriptor declares {entry.get('sha256')!r}")

if not declared_integer(source_count):
    reasons.append(f"catalog_metadata.source_count is {source_count!r}, not a positive integer")
elif declared.get("sourceCount") != int(source_count):
    reasons.append(f"descriptor sourceCount {declared.get('sourceCount')!r} is not the catalogue's own"
                   f" source_count {int(source_count)}")

if not declared_integer(catalog_version):
    reasons.append(f"catalog_metadata.catalog_version is {catalog_version!r}, not a positive integer")
else:
    stamp = int(catalog_version)
    if stamp > INT64_MAX:
        reasons.append(f"catalog_metadata.catalog_version {stamp} does not fit the 64-bit value this build persists")
    elif not MICROSECONDS_2015 <= stamp <= MICROSECONDS_2100:
        reasons.append(f"catalog_metadata.catalog_version {stamp} is not a plausible microsecond stamp")
if schema_version != str(READER_SCHEMA_VERSION):
    reasons.append(f"catalog_metadata.schema_version is {schema_version!r}; this build reads"
                   f" {READER_SCHEMA_VERSION}")

if files and expected.get("files"):
    if files[0].get("sha256") != expected["files"][0].get("sha256") or files[0].get("path") != expected["files"][0].get("path"):
        reasons.append(f"descriptor files[0] is {files[0].get('path')!r}/{files[0].get('sha256')!r}; the repository's"
                       f" is {expected['files'][0].get('path')!r}/{expected['files'][0].get('sha256')!r}")
if not files:
    reasons.append("the descriptor declares no files")
if entry is not None and entry.get("bytes") != expected_entry.get("bytes"):
    reasons.append(f"descriptor catalogue entry is {entry.get('bytes')!r} bytes; the repository's is"
                   f" {expected_entry.get('bytes')!r}")
if entry is not None and str(entry.get("sha256", "")).lower() != str(expected_entry.get("sha256", "")).lower():
    reasons.append(f"descriptor catalogue sha256 is {entry.get('sha256')!r}; the repository's is"
                   f" {expected_entry.get('sha256')!r}")

if reasons:
    print(f"REFUSED: what {app} carries is not the catalogue the repository descriptor declares")
    print(f"  bundle: {app}")
    print(f"  catalogue: {catalogue} ({size} bytes, sha256 {digest})")
    for reason in reasons:
        print(f"  - {reason}")
    sys.exit(1)

print("product catalogue: OK")
print(f"  bundle: {app}")
print(f"  catalogue: {catalogue} ({size} bytes, sha256 {digest})")
print(f"  descriptor (bundle, beside the catalogue): {descriptor_path}")
print(f"  descriptor (repository, the expected identity): {repository}")
print(f"  identity: schemaVersion {declared.get('schemaVersion')}, revision {declared.get('revision')},"
      f" sourceCount {declared.get('sourceCount')}, fileCount {declared.get('fileCount')},"
      f" catalogue entry {CATALOGUE_NAME} {entry.get('bytes')} bytes sha256 {entry.get('sha256')}")
print(f"  declared by the catalogue: source_count {int(source_count)}, catalog_version {int(catalog_version)},"
      f" schema_version {int(schema_version)}")
print("  checked: descriptor schema and structure · catalogue bytes and sha256 against the descriptor's entry ·"
      " descriptor sourceCount against the catalogue's own source_count · catalog_version a positive microsecond"
      " stamp · descriptor files[0] and catalogue entry against the repository descriptor · no bench_corpus key")
sys.exit(0)
PY
then
  exit 0
fi

# The verifier already said why; only the way back is missing.
echo "  put the product build back before evaluating UX:" >&2
echo "    xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -derivedDataPath /tmp/feedmine-product-derived build" >&2
echo "    xcrun simctl install booted /tmp/feedmine-product-derived/Build/Products/Debug-iphonesimulator/FeedMine.app" >&2
echo "  the expected identity is in $REPO_MANIFEST (revision $REPO_REVISION, sourceCount $REPO_SOURCE_COUNT, $REPO_CATALOGUE_PATH $REPO_CATALOGUE_BYTES bytes, sha256 $REPO_CATALOGUE_SHA256)" >&2
echo "  then run this script again: exit 0 means the product catalogue is in place." >&2
exit 1
