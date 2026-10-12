#!/usr/bin/env python3
# File: bench/serve.py
# Owns: the local HTTP transport that serves the frozen benchmark corpus (feed documents, media, article pages),
# reproducing the corpus's own delays and failure classes, and logging every request.
# Does not own: the corpus (produced by bench/build_corpus.py, loaded read-only), the criteria, or any gate result.
# It never regenerates or edits anything: if the corpus is missing, it fails and points at build_corpus.py.
#
# Usage:
#   python3 bench/serve.py                 # 127.0.0.1:8757, prints the corpus totals, then serves
#   python3 bench/serve.py --totals        # print the corpus totals (what an evaluator reads before a run) and exit
#   python3 bench/serve.py --port 8760 --verbose
#
# Endpoints:
#   GET/HEAD /                 plain-text index and totals
#   GET/HEAD /_totals          the corpus totals as JSON
#   GET/HEAD /health           liveness
#   GET/HEAD /s/<source-key>   the source's frozen feed document (RSS 2.0, Atom or JSON Feed), percent-encoded key
#   GET/HEAD /m/<item-uid>     the frozen media bytes (PNG / MP3 / MP4) — supports Range
#   GET/HEAD /a/<item-uid>     the item's local article page (deterministic render of the frozen item record)
#
# Every request appends one JSON line to bench/run/server.log: source key, path, status, bytes, milliseconds
# (plus method, kind, delay applied and a note).

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import threading
import time
from datetime import datetime, timezone
from email.utils import formatdate, parsedate_to_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote

BENCH_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(BENCH_DIR))
from build_corpus import BASE_URL, article_html  # noqa: E402  (shared frozen renderers, no import side effects)

CORPUS_DIR = BENCH_DIR / "corpus"
RUN_DIR = BENCH_DIR / "run"
LOG_PATH = RUN_DIR / "server.log"
FIXED_LAST_MODIFIED = datetime(2026, 10, 9, 0, 0, 0, tzinfo=timezone.utc)


def http_date(moment: datetime) -> str:
    return formatdate(moment.timestamp(), usegmt=True)


LAST_MODIFIED_HEADER = http_date(FIXED_LAST_MODIFIED)


class Corpus:
    """The frozen corpus, loaded read-only."""

    def __init__(self, corpus_dir: Path = CORPUS_DIR) -> None:
        if not (corpus_dir / "sources.json").exists():
            raise SystemExit("bench/corpus is missing — build it first: python3 bench/build_corpus.py")
        sources_document = json.loads((corpus_dir / "sources.json").read_text(encoding="utf-8"))
        self.totals = sources_document["totals"]
        self.criteria = json.loads((corpus_dir / "criteria.json").read_text(encoding="utf-8"))
        self.profiles = json.loads((corpus_dir / "profiles.json").read_text(encoding="utf-8"))
        self.plan_by_key: dict[str, dict] = sources_document["sources"]
        self.plan_by_feed_sha1 = {plan["feed_key_sha1"]: plan for plan in self.plan_by_key.values()}
        items_document = json.loads((corpus_dir / "items.json").read_text(encoding="utf-8"))
        self.items: list[dict] = items_document["items"]
        self.items_generated_at = items_document.get("generated_at")
        self.item_by_uid: dict[str, dict] = {item["id"]: item for item in self.items}
        self.items_by_source: dict[str, list[dict]] = {}
        for item in self.items:
            self.items_by_source.setdefault(item["source_key"], []).append(item)
        for source_items in self.items_by_source.values():
            source_items.sort(key=lambda entry: (entry["published_at"], entry["id"]), reverse=True)
        self.media_pack = (corpus_dir / "media.pack").open("rb")
        self.media_lock = threading.Lock()
        self.feed_bytes: dict[str, bytes] = {}
        items_per_protocol: dict[str, int] = {}
        for item in self.items:
            plan = self.plan_by_key.get(item["source_key"])
            if plan is None:
                continue
            items_per_protocol[plan["protocol"]] = items_per_protocol.get(plan["protocol"], 0) + 1
        self.items_per_protocol = {name: items_per_protocol.get(name, 0)
                                   for name in sorted(items_per_protocol)}

    def feed_document(self, plan: dict) -> bytes:
        cached = self.feed_bytes.get(plan["key"])
        if cached is None:
            cached = (CORPUS_DIR / plan["feed_path"]).read_bytes()
            self.feed_bytes[plan["key"]] = cached
        return cached

    def media_bytes(self, item: dict) -> bytes:
        span = item["media"].get("bytes") or {}
        with self.media_lock:
            self.media_pack.seek(span["offset"])
            return self.media_pack.read(span["length"])

    def resolve_source(self, remainder: str) -> dict | None:
        """Percent-encoded keys arrive once-encoded; tolerate a client that encoded them again."""
        for candidate in (remainder, unquote(remainder), unquote(unquote(remainder))):
            plan = self.plan_by_key.get(candidate)
            if plan is not None:
                return plan
        return None


class Transport:
    """Per-resource request counters so the corpus's failure classes stay reproducible within one server run."""

    def __init__(self) -> None:
        self.counters: dict[str, int] = {}
        self.lock = threading.Lock()

    def next_count(self, resource: str) -> int:
        with self.lock:
            count = self.counters.get(resource, 0) + 1
            self.counters[resource] = count
            return count


def plan_delay_ms(plan: dict) -> int:
    behaviour = plan["behaviour"]
    return behaviour.get("delay_ms", 0) if behaviour["class"] == "slow" else 0


def failure_for(plan: dict, count: int, behaviour: dict | None = None) -> tuple[int | None, float, str]:
    """Returns (status to fail with or None, seconds to hang, note). Deterministic in `count`."""
    behaviour = behaviour or plan["behaviour"]
    kind = behaviour["class"]
    if kind == "intermittent":
        every = behaviour["fail_every"]
        if count % every == 0:
            statuses = behaviour["statuses"]
            status = statuses[(count // every - 1) % len(statuses)]
            return status, 0.0, f"intermittent failure {count}%{every}"
    elif kind == "timeout":
        every = behaviour["hang_every"]
        if count % every == 0:
            return behaviour["status"], float(behaviour["hang_seconds"]), f"timeout hang {count}%{every}"
    return None, 0.0, ""


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "FeedMineBenchTransport/1.0"
    corpus: Corpus
    transport: Transport
    log_path: Path
    verbose: bool
    log_lock = threading.Lock()
    sequence = 0

    # -- logging ------------------------------------------------------------------------------------------
    def log_message(self, format: str, *args) -> None:  # silence the stdlib stderr log
        return

    def record(self, source: str | None, kind: str, status: int, length: int, started: float,
               delay_ms: int, note: str) -> None:
        now = datetime.now(timezone.utc)
        elapsed_ms = int(round((time.perf_counter() - started) * 1000))
        with Handler.log_lock:
            Handler.sequence += 1
            line = json.dumps({
                # the runner's acquisition oracle reads: t_ms, method, source, path, status, bytes, ms
                "t_ms": int(now.timestamp() * 1000),
                "method": self.command,
                "source": source,
                "path": self.path,
                "status": status,
                "bytes": length,
                "ms": elapsed_ms,
                # additive context for auditing
                "seq": Handler.sequence,
                "t": now.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
                "kind": kind,
                "delay_ms": delay_ms,
                "note": note,
            }, ensure_ascii=False, sort_keys=True)
            with Handler.log_path.open("a", encoding="utf-8") as handle:
                handle.write(line + "\n")
        if Handler.verbose:
            print(line, flush=True)

    # -- HTTP plumbing ------------------------------------------------------------------------------------
    def send_payload(self, status: int, content_type: str, payload: bytes, etag: str,
                     source: str | None, kind: str, started: float, delay_ms: int, note: str = "",
                     total_length: int | None = None, extra_headers: dict | None = None) -> None:
        body = payload if self.command != "HEAD" else b""
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload) if total_length is None else total_length))
        self.send_header("ETag", etag)
        self.send_header("Last-Modified", LAST_MODIFIED_HEADER)
        self.send_header("Accept-Ranges", "bytes")
        for header, value in (extra_headers or {}).items():
            self.send_header(header, value)
        self.end_headers()
        if body:
            self.wfile.write(body)
        # `bytes` is what actually left the socket (a HEAD or a 304 carries no body); Content-Length states the
        # full representation size.
        self.record(source, kind, status, len(body), started, delay_ms, note)

    def send_bytes(self, content_type: str, payload: bytes, etag: str, source: str | None, kind: str,
                   started: float, delay_ms: int, note: str = "", allow_range: bool = True) -> None:
        """One path for every byte payload: conditional 304, Range with 206/416, then 200."""
        if self.conditional_holds(etag):
            self.not_modified(etag, source, kind, started, (note + " conditional").strip())
            return
        window = self.parse_range(len(payload)) if allow_range else None
        if window == "invalid":
            self.send_payload(416, "text/plain; charset=utf-8", b"range not satisfiable\n", etag, source, kind,
                              started, 0, "range not satisfiable",
                              extra_headers={"Content-Range": f"bytes */{len(payload)}"})
            return
        if window is None:
            self.send_payload(200, content_type, payload, etag, source, kind, started, delay_ms, note)
            return
        start, end = window
        chunk = payload[start:end + 1]
        self.send_payload(206, content_type, chunk, etag, source, kind, started, delay_ms,
                          (note + f" range={start}-{end}").strip(),
                          extra_headers={"Content-Range": f"bytes {start}-{end}/{len(payload)}"})

    def not_modified(self, etag: str, source: str | None, kind: str, started: float, note: str = "") -> None:
        self.send_response(304)
        self.send_header("ETag", etag)
        self.send_header("Last-Modified", LAST_MODIFIED_HEADER)
        self.send_header("Content-Length", "0")
        self.end_headers()
        self.record(source, kind, 304, 0, started, 0, note)

    def conditional_holds(self, etag: str) -> bool:
        if_none_match = self.headers.get("If-None-Match")
        if if_none_match:
            tags = [tag.strip() for tag in if_none_match.split(",")]
            if "*" in tags or etag in tags or etag.lstrip("W/") in [tag.lstrip("W/") for tag in tags]:
                return True
            return False
        if_modified_since = self.headers.get("If-Modified-Since")
        if if_modified_since:
            try:
                since = parsedate_to_datetime(if_modified_since)
            except (TypeError, ValueError):
                return False
            if since is not None and since.tzinfo is None:
                since = since.replace(tzinfo=timezone.utc)
            if since is not None and FIXED_LAST_MODIFIED <= since:
                return True
        return False

    @staticmethod
    def etag_for(payload: bytes) -> str:
        return '"' + hashlib.sha256(payload).hexdigest()[:32] + '"'

    def parse_range(self, total: int) -> tuple[int, int] | None | str:
        """Returns (start, end) inclusive, None when no range was asked, or "invalid" for a 416."""
        header = self.headers.get("Range")
        if not header or not header.startswith("bytes="):
            return None
        spec = header[len("bytes="):].split(",")[0].strip()
        if "-" not in spec:
            return "invalid"
        first, _, last = spec.partition("-")
        try:
            if first == "":
                suffix = int(last)
                if suffix <= 0:
                    return "invalid"
                start = max(0, total - suffix)
                end = total - 1
            else:
                start = int(first)
                end = int(last) if last else total - 1
        except ValueError:
            return "invalid"
        if start > end or start >= total:
            return "invalid"
        return start, min(end, total - 1)

    # -- routing ------------------------------------------------------------------------------------------
    def do_GET(self) -> None:
        self.handle_request()

    def do_HEAD(self) -> None:
        self.handle_request()

    def handle_request(self) -> None:
        started = time.perf_counter()
        path = self.path.split("?", 1)[0]
        try:
            if path in ("/", "/index.html"):
                self.serve_index(started)
            elif path in ("/totals", "/_totals"):
                self.serve_totals(started)
            elif path == "/health":
                self.serve_health(started)
            elif path.startswith("/s/"):
                self.serve_feed(path[len("/s/"):], started)
            elif path.startswith("/m/"):
                self.serve_media(path[len("/m/"):], started)
            elif path.startswith("/a/"):
                self.serve_article(path[len("/a/"):], started)
            else:
                self.send_payload(404, "text/plain; charset=utf-8", b"not found\n",
                                  '"missing"', None, "other", started, 0, "unknown path")
        except (BrokenPipeError, ConnectionResetError):
            self.record(None, "aborted", 0, 0, started, 0, "client disconnected")

    def serve_index(self, started: float) -> None:
        totals = self.corpus.totals
        lines = [
            "FeedMine discovery acceptance benchmark transport",
            f"base url            : {BASE_URL} (this server)",
            f"sources             : {totals['sources']}",
            f"eligible sources    : A={totals['eligible_sources']['A']} B={totals['eligible_sources']['B']}",
            f"items               : {totals['items']}",
            f"eligible items      : A={totals['eligible_items']['A']} B={totals['eligible_items']['B']}",
            f"protocols           : {json.dumps(totals['protocols'], sort_keys=True)}",
            f"behaviour classes   : {json.dumps(totals['behaviour_classes'], sort_keys=True)}",
            f"empty documents     : {totals['empty_documents']}",
            f"slow-media sources  : {totals['slow_media_sources']}",
            f"shared canonical ids: {totals['canonical_articles_shared']}",
            "",
            "GET /_totals | /health | /s/<source-key> | /m/<item-uid> | /a/<item-uid>",
            "This transport serves a frozen evaluator corpus. It is not production code.",
        ]
        payload = ("\n".join(lines) + "\n").encode("utf-8")
        self.send_payload(200, "text/plain; charset=utf-8", payload, self.etag_for(payload), None, "meta",
                          started, 0)

    def serve_totals(self, started: float) -> None:
        totals = self.corpus.totals
        payload = json.dumps({
            "transport_base_url": BASE_URL,
            "sources_per_profile": {"A": totals["eligible_sources"]["A"], "B": totals["eligible_sources"]["B"]},
            "items_per_profile": {"A": totals["eligible_items"]["A"], "B": totals["eligible_items"]["B"]},
            "items_total": totals["items"],
            "sources_total": totals["sources"],
            "sources_per_protocol": totals["protocols"],
            "items_per_protocol": self.corpus.items_per_protocol,
            "profiles": self.corpus.profiles,
            "totals": totals,
            "criteria_thresholds": self.corpus.criteria["thresholds"],
            "trace": self.corpus.criteria["trace"],
            "items_generated_at": self.corpus.items_generated_at,
        }, ensure_ascii=False, indent=2, sort_keys=True).encode("utf-8")
        self.send_payload(200, "application/json; charset=utf-8", payload, self.etag_for(payload), None, "meta",
                          started, 0)

    def serve_health(self, started: float) -> None:
        payload = json.dumps({"status": "ok", "sources": self.corpus.totals["sources"],
                              "items": self.corpus.totals["items"]}, sort_keys=True).encode("utf-8")
        self.send_payload(200, "application/json; charset=utf-8", payload, self.etag_for(payload), None, "meta",
                          started, 0)

    def serve_feed(self, remainder: str, started: float) -> None:
        plan = self.corpus.resolve_source(remainder)
        if plan is None:
            self.send_payload(404, "text/plain; charset=utf-8", b"unknown source key\n", '"unknown"', None,
                              "feed", started, 0, "unknown source key")
            return
        count = self.transport.next_count(plan["key"])
        status, hang, note = failure_for(plan, count)
        if hang:
            time.sleep(hang)
            payload = f"upstream timeout for {plan['key']}\n".encode("utf-8")
            self.send_payload(status or 504, "text/plain; charset=utf-8", payload, '"timeout"', plan["key"],
                              "feed", started, int(hang * 1000), note)
            return
        if status:
            payload = f"upstream error {status} for {plan['key']}\n".encode("utf-8")
            self.send_payload(status, "text/plain; charset=utf-8", payload, f'"{status}"', plan["key"], "feed",
                              started, 0, note)
            return
        delay_ms = plan_delay_ms(plan)
        if delay_ms:
            time.sleep(delay_ms / 1000.0)
        payload = self.corpus.feed_document(plan)
        self.send_bytes(plan["content_type"], payload, self.etag_for(payload), plan["key"], "feed", started,
                        delay_ms, f"count={count}")

    def serve_media(self, uid: str, started: float) -> None:
        item = self.corpus.item_by_uid.get(uid)
        if item is None or not (item["media"].get("bytes") or {}):
            self.send_payload(404, "text/plain; charset=utf-8", b"unknown media id\n", '"unknown"', None, "media",
                              started, 0, "unknown media id")
            return
        plan = self.corpus.plan_by_key.get(item["source_key"], {"key": item["source_key"],
                                                               "behaviour": {"class": "normal"}})
        count = self.transport.next_count(f"media:{uid}")
        status, hang, note = failure_for(plan, count)
        if hang:
            time.sleep(hang)
            payload = b"upstream media timeout\n"
            self.send_payload(status or 504, "text/plain; charset=utf-8", payload, '"timeout"', plan["key"],
                              "media", started, int(hang * 1000), note)
            return
        if status:
            payload = f"upstream error {status}\n".encode("utf-8")
            self.send_payload(status, "text/plain; charset=utf-8", payload, f'"{status}"', plan["key"], "media",
                              started, 0, note)
            return
        delay_ms = plan.get("media_delay_ms", 0)
        if delay_ms:
            time.sleep(delay_ms / 1000.0)
        payload = self.corpus.media_bytes(item)
        span = item["media"]["bytes"] or {}
        etag = '"' + (span.get("sha256") or self.etag_for(payload).strip('"'))[:32] + '"'
        content_type = item["media"]["content_type"] or "application/octet-stream"
        self.send_bytes(content_type, payload, etag, plan["key"], "media", started, delay_ms,
                        f"count={count} kind={item['media']['kind']}")

    def serve_article(self, uid: str, started: float) -> None:
        item = self.corpus.item_by_uid.get(uid)
        if item is None:
            self.send_payload(404, "text/plain; charset=utf-8", b"unknown item\n", '"unknown"', None, "article",
                              started, 0, "unknown item")
            return
        payload = article_html(item)
        etag = self.etag_for(payload)
        if self.conditional_holds(etag):
            self.not_modified(etag, item["source_key"], "article", started, "conditional")
            return
        self.send_payload(200, "text/html; charset=utf-8", payload, etag, item["source_key"], "article",
                          started, 0)


def print_totals(corpus: Corpus) -> None:
    totals = corpus.totals
    print("FeedMine discovery acceptance benchmark — frozen corpus totals")
    print(f"  transport base url    : {BASE_URL}")
    print(f"  sources in corpus     : {totals['sources']}")
    print(f"  eligible sources      : profile A={totals['eligible_sources']['A']}  "
          f"profile B={totals['eligible_sources']['B']}")
    print(f"  items in corpus       : {totals['items']}")
    print(f"  eligible items        : profile A={totals['eligible_items']['A']}  "
          f"profile B={totals['eligible_items']['B']}")
    print(f"  protocols             : " + ", ".join(
        f"{name}={count}" for name, count in sorted(totals["protocols"].items())))
    print(f"  behaviour classes     : " + ", ".join(
        f"{name}={count}" for name, count in sorted(totals["behaviour_classes"].items())))
    print(f"  empty documents       : {totals['empty_documents']}")
    print(f"  slow-media sources    : {totals['slow_media_sources']}")
    print(f"  shared canonical ids  : {totals['canonical_articles_shared']}")
    print(f"  profiles              : " + "; ".join(
        f"{profile} = {corpus.criteria['profiles'][profile]['description']} "
        f"(languages {corpus.criteria['profiles'][profile]['language_codes']})"
        for profile in sorted(corpus.criteria["profiles"])))


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve the frozen FeedMine benchmark corpus over local HTTP.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8757)
    parser.add_argument("--log", type=Path, default=LOG_PATH)
    parser.add_argument("--corpus", type=Path, default=CORPUS_DIR)
    parser.add_argument("--totals", action="store_true", help="print the corpus totals and exit")
    parser.add_argument("--verbose", action="store_true", help="also print one line per request")
    arguments = parser.parse_args()

    corpus = Corpus(arguments.corpus)
    print_totals(corpus)
    if arguments.totals:
        print(json.dumps({"totals": corpus.totals, "transport_base_url": BASE_URL}, ensure_ascii=False,
                         indent=2, sort_keys=True))
        return

    arguments.log.parent.mkdir(parents=True, exist_ok=True)
    Handler.corpus = corpus
    Handler.transport = Transport()
    Handler.log_path = arguments.log
    Handler.verbose = arguments.verbose
    Handler.log_path.touch(exist_ok=True)

    server = ThreadingHTTPServer((arguments.host, arguments.port), Handler)
    server.daemon_threads = True
    if arguments.port != 8757:
        print(f"warning: the frozen catalog rewrites request_url to port 8757; this server is on "
              f"{arguments.port}. Request URLs from the catalog will not reach it.")
    print(f"  serving               : http://{arguments.host}:{arguments.port}/  (Ctrl-C to stop)")
    print(f"  request log           : {arguments.log}")
    print("  note: results of a run belong in a separate report; this transport claims no gate result.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopping")
    finally:
        server.server_close()
        corpus.media_pack.close()


if __name__ == "__main__":
    main()
