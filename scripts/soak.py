#!/usr/bin/env python3
"""Measure a real, persistent simulator reader; never write its SQLite database.

From the repository root:
  python3 scripts/soak.py --prepare --minutes 30 --output /tmp/feedmine-soak-30m          # the run's own device
  python3 scripts/soak.py --device <UDID> --prepare --minutes 30 --output /tmp/...        # a device you choose

With no --device, the run creates or reuses a simulator of its own ('FeedMine Bench') and measures there. The UI
test installs the app it built under the exclusive benchmark identifier
(com.feedmine.development.benchmark, rewritten into the built product before installation), never under the
product identifier com.feedmine.development, so an instrumented build is not left where a product evaluation would
launch it. FEEDMINE_BENCH_SHARED_DEVICE=1 keeps the older device choice (the single booted simulator) with the same
exclusive identifier. Either way the script prints, at the end and on failure, how to reinstall the product build.

--prepare runs ONLY the country-cascade UI test, on that same simulator (no clones),
then launches the Debug app with the SAME namespace and real RSS transport. Without
--prepare, reuse the selection previously made by that test. Debug is required:
Release ignores FEEDMINE_RUNTIME_NAMESPACE. No fixture or development feeds are used.

When SCROLL NOW appears, scroll the reader for the whole measurement, including
occasional backwards movement. The script samples the app PROCESS (not simulator
or host totals) every 30 seconds and saves Runtime counts/integrity/checkpoints.
It does not synthesize swipes or assert 30 minutes of real consumption from elapsed
wall time. runway.ndjson preserves the app's viewport/runway logs for that review.
Hitches require a separate Instruments Animation Hitches recording of this process;
RSS/CPU sampling cannot measure hitches. Exhausted supply must be reported as partial.

At the end, stop gestures. The script backgrounds the app by opening Settings,
waits for its lifecycle checkpoint, captures it BEFORE termination, terminates and
relaunches with the same environment, and compares edition/card/anchor placement
(timestamp is allowed to change). No database resets, preferences writes or SQL
mutations occur. Output must be a new directory so earlier evidence is preserved.
Exit 1 means a missing process/sample, PID discontinuity, duplicate, missing or
changed restart checkpoint, or other execution failure; exit 0 is NOT a T12 pass.
"""

import argparse
import csv
import json
import os
from pathlib import Path
import plistlib
import shutil
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timezone

# Keep in sync with FeedMineUITests.soakRuntimeNamespace; persistent across runs.
NAMESPACE = "B50A0000-0000-4000-8000-000000000030"
# The identifier the *instrumented* build carries while this run measures, and the one every simctl address below
# uses (review 2026-10-11, round 5 item 4). Xcode installs the app it tests under the identifier the bundle
# declares, so --prepare rewrites the built product's CFBundleIdentifier to this before installing it: a soak never
# installs anything under the product identifier a product evaluation launches. The device paths differ only in
# which simulator they pick (the run's own, or the single booted one with FEEDMINE_BENCH_SHARED_DEVICE=1); the
# identifier is exclusive in both.
BUNDLE_ID = "com.feedmine.development.benchmark"
# The product's own identifier: what a product evaluation launches, and what this script must put back (it is never
# installed by a soak).
PRODUCT_BUNDLE_ID = "com.feedmine.development"
ROOT = Path(__file__).resolve().parent.parent
TEST = "FeedMineUITests/FeedMineUITests/testPreparePersistentScaleSoakThroughCountryCascade"
# The simulator an unnamed run owns, and the product build a run's device has to be restored to afterwards.
BENCH_DEVICE_NAME = "FeedMine Bench"
PRODUCT_APP = "/tmp/feedmine-product-derived/Build/Products/Debug-iphonesimulator/FeedMine.app"
# Set by main() as soon as the device is known, so the restore hint can be printed on any way out.
DEVICE = None


def command(args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def sim(device, *args, **kwargs):
    return command(["xcrun", "simctl", *args[:1], device, *args[1:]], **kwargs)


def simctl_devices():
    return json.loads(command(["xcrun", "simctl", "list", "devices", "--json"]))["devices"]


def device_named(devices, name):
    for entries in devices.values():
        for entry in entries:
            if entry["name"] == name and entry.get("isAvailable", True):
                return entry
    return None


def template_profile(devices):
    """The device type and runtime to model the dedicated device on: the single booted device when there is one,
    otherwise the newest available runtime's first available iPhone."""
    booted = [entry for entries in devices.values() for entry in entries if entry.get("state") == "Booted"]
    if len(booted) == 1:
        for runtime, entries in devices.items():
            if booted[0] in entries:
                return booted[0]["deviceTypeIdentifier"], runtime
    for runtime, entries in sorted(devices.items(), reverse=True):
        for entry in entries:
            if entry.get("isAvailable", True) and entry["name"].startswith("iPhone"):
                return entry["deviceTypeIdentifier"], runtime
    return None


def dedicated_device():
    """Create or reuse the simulator this run owns, boot it, and return its UDID.

    The UI test installs the app it built as BUNDLE_ID, and this script launches that same installed app: leaving it
    on the simulator a person evaluates is how a benchmark build gets read as the product. Two measures: the build
    carries that exclusive identifier (rewritten into it before installation, above) and this run uses a device of
    its own whenever the operator named none.
    """
    devices = simctl_devices()
    existing = device_named(devices, BENCH_DEVICE_NAME)
    if existing is None:
        profile = template_profile(devices)
        if profile is None:
            raise RuntimeError(f"no available simulator to model '{BENCH_DEVICE_NAME}' on; pass --device UDID")
        device_type, runtime = profile
        udid = command(["xcrun", "simctl", "create", BENCH_DEVICE_NAME, device_type, runtime])
        print(f"created the simulator '{BENCH_DEVICE_NAME}' ({udid}); later runs reuse it", flush=True)
    else:
        udid = existing["udid"]
    # Already booted is the normal case: `boot` refuses it, and `bootstatus` then just reports it ready.
    subprocess.run(["xcrun", "simctl", "boot", udid], capture_output=True, check=False)
    command(["xcrun", "simctl", "bootstatus", udid, "-b"])
    return udid


def restore_command(device):
    """Say how to put the product build back — printed whether the run passed, failed or raised."""
    print(f"""
RESTORE THE PRODUCT BUILD BEFORE ANY PRODUCT EVALUATION
  The benchmark's instrumented build is installed on {device} as {BUNDLE_ID} (never as {PRODUCT_BUNDLE_ID}), by this
  run's preparation or an earlier one. Outside a benchmark run its transport does not exist, so the reader appears
  to publish nothing. {PRODUCT_BUNDLE_ID} holds whatever was installed there before, so put the product build back:
    xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination 'platform=iOS Simulator,id={device}' -derivedDataPath /tmp/feedmine-product-derived build
    xcrun simctl install {device} {PRODUCT_APP}
  then prove the device carries the product catalogue (exit 0), not the corpus (exit 1):
    scripts/verify_product_catalogue.sh "$(xcrun simctl get_app_container {device} {PRODUCT_BUNDLE_ID} app)"
  the instrumented build under {BUNDLE_ID} is not the product; it can be removed with:
    xcrun simctl uninstall {device} {BUNDLE_ID}
""", flush=True)


def runtime_snapshot(database):
    # mode=ro honors live WAL contents; immutable=1 would miss them. Never migrate/checkpoint.
    with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True, timeout=10) as db:
        db.execute("PRAGMA query_only = ON")
        db.execute("BEGIN")  # one consistent read transaction across all metrics
        counts = {table: db.execute("SELECT count(*) FROM " + table).fetchone()[0]
                  for table in ("published_cards", "origin_records", "feed_segments")}
        # Include retained history: the same occurrence must not appear in active + retired storage.
        cards = "(SELECT id, segment_id, origin_revision_id FROM published_cards UNION ALL SELECT id, segment_id, origin_revision_id FROM retired_published_cards)"
        counts["duplicate_revisions_per_segment"] = db.execute(
            "SELECT count(*) FROM (SELECT segment_id, origin_revision_id FROM " + cards +
            " GROUP BY segment_id, origin_revision_id HAVING count(*) > 1)").fetchone()[0]
        counts["duplicate_card_ids"] = db.execute(
            "SELECT count(*) FROM (SELECT id FROM " + cards + " GROUP BY id HAVING count(*) > 1)").fetchone()[0]
        checkpoint = db.execute(
            "SELECT edition_id, card_id, anchor_placement FROM session_checkpoint WHERE singleton_id = 1").fetchone()
        counts["checkpoint"] = list(checkpoint) if checkpoint else None
        return counts


def app_process(executable):
    matches = []
    for line in command(["ps", "-axo", "pid=,rss=,%cpu=,command="]).splitlines():
        fields = line.strip().split(None, 3)
        if len(fields) == 4 and (fields[3] == str(executable) or fields[3].startswith(str(executable) + " ")):
            matches.append({"pid": int(fields[0]), "rss_kib": int(fields[1]), "cpu_percent": float(fields[2])})
    if len(matches) != 1:
        raise RuntimeError(f"Expected exactly one app process at {executable}; found {len(matches)}")
    return matches[0]


def launch(device, restart=False):
    # Launches the instrumented build by its exclusive identifier, the only one this run installs.
    env = os.environ.copy()
    env["SIMCTL_CHILD_FEEDMINE_RUNTIME_NAMESPACE"] = NAMESPACE
    env["SIMCTL_CHILD_FEEDMINE_SKIP_ONBOARDING"] = "1"
    for name in ("USE_DEVELOPMENT_FEEDS", "LOCAL_FEEDS", "BLOCK_RSS_NETWORK", "EMPTY_SELECTION", "MEDIA_SIMULATION"):
        env["SIMCTL_CHILD_FEEDMINE_" + name] = "0"
    if restart:
        # Root cause, corrected by review (Codex, 2026-10-10): the original form passed `--terminate-running-process`
        # after the device, where simctl reads it as the bundle id — hence FBSOpenApplicationServiceErrorDomain
        # code 4 naming the flag itself as the app to open. Stopping explicitly and launching plainly is equivalent,
        # order-independent, and works whether or not the app is already running. Cleanup failure must never abort
        # the run: the app may legitimately not be running.
        subprocess.run(["xcrun", "simctl", "terminate", device, BUNDLE_ID], capture_output=True, check=False)
    sim(device, "launch", BUNDLE_ID, env=env)


def wait_for_snapshot(database, executable, timeout=120):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            app_process(executable)
            snapshot = runtime_snapshot(database)
            if snapshot["checkpoint"]:
                return snapshot
        except (RuntimeError, sqlite3.Error):
            pass
        time.sleep(1)
    raise RuntimeError("No live process with a saved session checkpoint in the requested namespace")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--device", default="booted",
                        help="UDID, or booted for the dedicated simulator this run creates or reuses")
    parser.add_argument("--prepare", action="store_true", help="Run the legitimate country-cascade UI preparation")
    parser.add_argument("--minutes", type=float, default=30)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.minutes <= 0:
        parser.error("--minutes must be positive")
    global DEVICE
    device = args.device
    if device == "booted" and os.environ.get("FEEDMINE_BENCH_SHARED_DEVICE") != "1":
        # The operator named no device: this run owns one, so the build the UI test installs stays off the shared
        # simulator. FEEDMINE_BENCH_SHARED_DEVICE=1 keeps the behaviour in the branch below.
        device = dedicated_device()
        print(f"measuring on the run's own simulator '{BENCH_DEVICE_NAME}' ({device}); pass --device UDID to choose another",
              flush=True)
    elif device == "booted":
        devices = json.loads(command(["xcrun", "simctl", "list", "devices", "booted", "--json"]))["devices"]
        booted = [d["udid"] for group in devices.values() for d in group if d["state"] == "Booted"]
        if len(booted) != 1:
            parser.error("Specify --device UDID: exactly one booted simulator is required")
        device = booted[0]
    DEVICE = device
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    if args.prepare:
        env = os.environ.copy()
        # Xcode forwards TEST_RUNNER_* to the UI test runner without that prefix.
        env["TEST_RUNNER_FEEDMINE_PREPARE_SCALE_SOAK"] = "1"
        # Build, rewrite the identifier, then run. The rewrite has to happen between the two steps: the test installs
        # the app under whatever identifier the built bundle declares, and installing it is the point of no return.
        # `xcodebuild test` builds and installs in one command, so the preparation is split into build-for-testing
        # and test-without-building — the same split bench/run.sh uses for the same reason.
        derived = output / "derived"
        with (output / "preparation.log").open("w") as log:
            subprocess.run(["xcodebuild", "build-for-testing", "-project", str(ROOT / "FeedMineApp/FeedMineApp.xcodeproj"),
                            "-scheme", "FeedMine", "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={device}",
                            "-derivedDataPath", str(derived)],
                           env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
            app = next(iter(derived.glob("Build/Products/*-iphonesimulator/FeedMine.app")), None)
            if app is None:
                raise RuntimeError(f"the built app was not found under {derived}/Build/Products")
            # A simulator build is ad-hoc signed with its Info.plist unbound (`Info.plist=not bound`, measured on
            # this build), so rewriting the identifier does not invalidate its signature. The UI test launches the
            # app under test with a plain XCUIApplication(), and the build's .xctestrun records it by *path*
            # (`UITargetAppPath`, with no `UITargetAppBundleIdentifier` — measured 2026-10-11), which is why the
            # rewrite above is expected to be the identifier the runner launches; that launch was not executed to
            # confirm it. If a future Xcode records the identifier instead, that launch fails and this preparation
            # fails loudly (check=True just below, and the container lookup requires the app under the exclusive
            # identifier) rather than falling back to the product identifier.
            subprocess.run(["plutil", "-replace", "CFBundleIdentifier", "-string", BUNDLE_ID, str(app / "Info.plist")],
                           check=True)
            written = subprocess.check_output(
                ["plutil", "-extract", "CFBundleIdentifier", "raw", str(app / "Info.plist")], text=True).strip()
            if written != BUNDLE_ID:
                raise RuntimeError(f"the built app declares {written}, not the exclusive {BUNDLE_ID}")
            print(f"preparing the instrumented build as {BUNDLE_ID}; the product identifier {PRODUCT_BUNDLE_ID} is untouched",
                  flush=True)
            subprocess.run(["xcodebuild", "test-without-building", "-project", str(ROOT / "FeedMineApp/FeedMineApp.xcodeproj"),
                            "-scheme", "FeedMine", "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={device}",
                            "-derivedDataPath", str(derived),
                            "-parallel-testing-enabled", "NO", "-only-testing:" + TEST,
                            "-testLanguage", "pt", "-testRegion", "BR",
                            "-resultBundlePath", str(output / "preparation.xcresult")],
                           env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
        # The build products are rebuildable and cost about a gigabyte; the evidence is the log and the result bundle.
        shutil.rmtree(derived, ignore_errors=True)
        preparation = json.loads(command(["xcrun", "xcresulttool", "get", "test-results", "summary",
                                          "--path", str(output / "preparation.xcresult"), "--compact"]))
        (output / "preparation-summary.json").write_text(json.dumps(preparation, indent=2) + "\n")
        if preparation["passedTests"] != 1 or preparation["skippedTests"] or preparation["failedTests"]:
            raise RuntimeError("The country-cascade preparation must execute and pass, not skip; inspect preparation.xcresult")
    try:
        container = Path(sim(device, "get_app_container", BUNDLE_ID, "data"))
        bundle = Path(sim(device, "get_app_container", BUNDLE_ID, "app"))
    except subprocess.CalledProcessError as error:
        raise RuntimeError(
            f"{BUNDLE_ID} is not installed on {device} ({error}); a device this run creates is empty, and the app is "
            f"installed under that exclusive identifier only, so run with --prepare first (the product identifier "
            f"{PRODUCT_BUNDLE_ID} is never measured), or pass --device UDID of a simulator prepared by an earlier run"
        ) from error
    with (bundle / "Info.plist").open("rb") as info:
        executable = bundle / plistlib.load(info)["CFBundleExecutable"]
    database = container / "Library/Application Support/FeedMine" / NAMESPACE / "runtime.sqlite"
    if not database.is_file():
        raise RuntimeError(f"Persistent namespace not prepared: {database}. Run with --prepare using Debug.")
    # Establish the namespace/environment and bring the reader to the foreground BEFORE measurement.
    # An existing process could belong to the default namespace; do not silently sample that session.
    launch(device, restart=True)
    initial = wait_for_snapshot(database, executable)
    failures = []
    rows = []
    log_file = (output / "runway.ndjson").open("w")
    logger = subprocess.Popen(["xcrun", "simctl", "spawn", device, "log", "stream", "--level", "info",
                               "--style", "ndjson", "--predicate",
                               # The subsystem is the product's own constant
                               # (Sources/FeedMineUI/FeedScreen.swift, AppComposition.swift), not the bundle
                               # identifier, so the exclusive identifier above does not change this predicate.
                               'process == "FeedMine" AND subsystem == "com.feedmine.development"'],
                              stdout=log_file, stderr=subprocess.STDOUT)
    try:
        fields = ["utc", "elapsed_seconds", "pid", "rss_kib", "cpu_percent", "published_cards", "origin_records",
                  "feed_segments", "duplicate_revisions_per_segment", "duplicate_card_ids", "checkpoint", "error"]
        with (output / "samples.csv").open("w", newline="") as csv_file:
            writer = csv.DictWriter(csv_file, fieldnames=fields)
            writer.writeheader()
            started = time.monotonic()
            duration = args.minutes * 60
            next_sample = started
            print(f"SCROLL NOW: {args.minutes:g} minutes, real content; output {output}", flush=True)
            while True:
                time.sleep(max(0, next_sample - time.monotonic()))
                row = {"utc": datetime.now(timezone.utc).isoformat(), "elapsed_seconds": round(time.monotonic() - started, 2)}
                try:
                    row.update(app_process(executable))
                    row.update(runtime_snapshot(database))
                    row["checkpoint"] = json.dumps(row["checkpoint"])
                except (RuntimeError, sqlite3.Error) as error:
                    row["error"] = str(error)
                    failures.append(str(error))
                writer.writerow(row)
                csv_file.flush()
                rows.append(row)
                if time.monotonic() - started >= duration:
                    break
                next_sample = min(next_sample + 30, started + duration)
        print("STOP SCROLLING: capturing the lifecycle checkpoint and checking relaunch", flush=True)
        # A normal background transition gives the real Runtime the opportunity to save its position.
        sim(device, "launch", "com.apple.Preferences")
        time.sleep(10)
        before_restart = runtime_snapshot(database)
        sim(device, "terminate", BUNDLE_ID)
        launch(device)
        after_restart = wait_for_snapshot(database, executable)
        # Allow the restored UI/foreground lifecycle to settle before the comparison.
        time.sleep(10)
        after_restart = runtime_snapshot(database)
        pids = {r["pid"] for r in rows if "pid" in r}
        if len(pids) != 1:
            failures.append(f"Process continuity broken: {len(pids)} PIDs during sampling")
        for metric in ("duplicate_revisions_per_segment", "duplicate_card_ids"):
            if any(r.get(metric, 0) > 0 for r in rows) or before_restart[metric] or after_restart[metric]:
                failures.append(metric)
        same_checkpoint = bool(before_restart["checkpoint"]) and before_restart["checkpoint"] == after_restart["checkpoint"]
        if not same_checkpoint:
            failures.append("Missing or changed checkpoint across terminate/relaunch")
        if logger.poll() is not None:
            failures.append("Runway log capture ended unexpectedly; inspect runway.ndjson")
        summary = {"device": device, "namespace": NAMESPACE, "database": str(database), "executable": str(executable),
                   "minutes_requested": args.minutes, "elapsed_seconds": rows[-1]["elapsed_seconds"],
                   "sample_interval_seconds": 30, "initial": initial, "before_restart": before_restart,
                   "after_restart": after_restart, "same_restart_checkpoint": same_checkpoint,
                   "failures": failures, "hitches": "Not measured; record separately with Instruments Animation Hitches",
                   "acceptance": "Not inferred: review real scroll duration, runway logs and hitch trace"}
        (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(json.dumps(summary, indent=2))
        return 1 if failures else 0
    finally:
        logger.terminate()
        try:
            logger.wait(timeout=5)
        except subprocess.TimeoutExpired:
            logger.kill()
            logger.wait()
        log_file.close()


if __name__ == "__main__":
    status = 1
    try:
        status = main()
    except (RuntimeError, subprocess.CalledProcessError, OSError, sqlite3.Error) as error:
        print(f"Soak failed: {error}", file=sys.stderr)
    finally:
        # Whatever happened — pass, failure or an exception — the device this run touched must be restorable, and the
        # operator has to know how. Before the device is known there is nothing to restore, so this stays silent.
        if DEVICE:
            restore_command(DEVICE)
    sys.exit(status)
