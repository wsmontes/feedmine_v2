#!/usr/bin/env python3
"""Progressive exploration, measured from a run's transport log.

F05 promises two complementary obligations: a runway that stays ahead of consumption, and **progressive expansion of
the eligible universe when there is capacity** — including while the runway is healthy. The second one is invisible
to the gate clauses that only look at the first 300 cards, so it gets its own instrument.

What this prints, per run: how many distinct sources were contacted overall, and how that set grew over time. A
budget that is a fixed slice stops growing; a budget that is genuinely progressive keeps finding sources it had not
visited.

Usage: python3 bench/expand.py bench/run/<stamp> [bench/run/<stamp> ...]
"""
import json
import os
import sys


def curve(log_path: str, window_seconds: float = 300.0) -> dict:
    if not os.path.exists(log_path):
        return {"error": "no transport log"}
    first_seen: dict[str, float] = {}
    for line in open(log_path, encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        source = entry.get("source")
        # The transport logs `t_ms` (epoch milliseconds) and `t` (ISO). Either identifies when a source was first
        # asked for; the instrument must not assume a field name it never checked (it did, and printed nothing).
        moment = entry.get("t_ms")
        # `t_ms` is **milliseconds**: reading it as seconds made the first instrument report 55 windows of nonsense.
        if moment is not None:
            moment = float(moment) / 1000.0
        elif entry.get("t") is not None:
            moment = entry["t"]
        if not source or moment is None:
            continue
        first_seen.setdefault(source, float(moment))
    if not first_seen:
        return {"error": "no source contacts"}
    start = min(first_seen.values())
    buckets: dict[int, int] = {}
    for moment in first_seen.values():
        index = int((moment - start) // window_seconds)
        buckets[index] = buckets.get(index, 0) + 1
    cumulative, running = [], 0
    for index in sorted(buckets):
        running += buckets[index]
        cumulative.append((index, buckets[index], running))
    return {
        "distinct_sources": len(first_seen),
        "windows": cumulative,
        "last_window_new": cumulative[-1][1] if cumulative else 0,
    }


def main() -> int:
    for run in sys.argv[1:]:
        print(f"== {run}")
        for name in ("server.log", "server-b.log"):
            result = curve(os.path.join(run, name))
            if "error" in result:
                continue
            windows = ", ".join(f"{index}:+{new}(={total})" for index, new, total in result["windows"])
            print(f"  {name}: {result['distinct_sources']} distinct sources over {len(result['windows'])} windows")
            print(f"    per 5 min (new = cumulative): {windows}")
            print(f"    new sources in the last window: {result['last_window_new']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
