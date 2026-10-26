#!/usr/bin/env python3
"""Cadence detector for the B03 pacing calibration.

Separate instrument, own identity: it reads (a) the injector's own record of *intent* — what was
scheduled and when — and (b) the app's `advance` events as *effect* — what the reader actually
consumed. It judges pacing only. It is not the frozen oracle and it does not produce a B03 verdict.

Consumption is counted in distinct anchors, never in advance events: a repeated anchor or an
`activity: stationary` submission is not a card consumed.
"""
import argparse
import json
import os
import sys


def load_phases(path):
    phases = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if line:
                phases.append(json.loads(line))
    return phases


def load_advances(trace, since):
    out = []
    with open(trace) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if rec.get("event") != "advance":
                continue
            at = rec.get("at")
            if not isinstance(at, (int, float)) or at < since:
                continue
            fields = rec.get("fields") or {}
            out.append({"at": at, "anchor": fields.get("anchor"), "activity": fields.get("activity")})
    return out


def measure(phase, advances):
    start, end = phase["started_at"], phase["ended_at"]
    window = [a for a in advances if start <= a["at"] < end]
    duration = end - start
    sequential = []
    previous = None
    for a in window:
        if a["anchor"] != previous:
            sequential.append(a)
            previous = a["anchor"]
    # Distinct anchors in traversal order: revisits collapse, so a run that returns to a card is not
    # counted twice as new consumption.
    seen, distinct = set(), 0
    for a in sequential:
        if a["anchor"] not in seen:
            seen.add(a["anchor"])
            distinct += 1
    repeats = 0
    prev_anchor = None
    for a in window:
        if a["anchor"] == prev_anchor:
            repeats += 1
        prev_anchor = a["anchor"]
    stationary = sum(1 for a in window if a["activity"] == "stationary")
    gestures = phase.get("gestures") or 1
    return {
        "label": phase.get("label"),
        "duration_s": round(duration, 2),
        "gestures": gestures,
        "gesture_rate_per_s": round(gestures / duration, 3) if duration else None,
        "advance_events": len(window),
        "advance_per_s": round(len(window) / duration, 3) if duration else None,
        "repeated_anchor_events": repeats,
        "stationary_events": stationary,
        "distinct_anchors": distinct,
        "distinct_anchors_per_s": round(distinct / duration, 3) if duration else None,
        "anchors_per_gesture": round(distinct / gestures, 2) if gestures else None,
        "sequential_anchor_steps": len(sequential),
    }


def judge(m, expect):
    """Classify the measured shape against the requested one. A miss is a miss."""
    problems = []
    base = expect.get("base_distinct_per_s")
    burst = expect.get("burst_distinct_per_s")
    if base is not None:
        lo, hi = base * 0.75, base * 1.30
        if not lo <= m["distinct_anchors_per_s"] <= hi:
            problems.append(f"base {m['distinct_anchors_per_s']} distinct cards/s outside [{round(lo,2)}, {round(hi,2)}]")
    if burst is not None:
        if m["distinct_anchors_per_s"] < burst * 0.80:
            problems.append(f"burst {m['distinct_anchors_per_s']} distinct cards/s below {round(burst*0.8,2)}")
    # Consumption rate alone cannot tell "one card per gesture at one gesture per second" from "three cards
    # per gesture at a third of a gesture per second". The contract asks for a reader who advances one card
    # per second *through gestures*, so the gesture rate is judged too, and the yield per gesture is
    # reported. Without these two clauses a run of 0.37 gestures/s each coasting three cards reads as a
    # perfect 1 card/s — which is exactly the inflation the contract excludes.
    gesture_target = expect.get("base_gesture_per_s")
    if gesture_target is not None and m["gesture_rate_per_s"] is not None:
        lo, hi = gesture_target * 0.75, gesture_target * 1.30
        if not lo <= m["gesture_rate_per_s"] <= hi:
            problems.append(f"{m['gesture_rate_per_s']} gestures/s outside [{round(lo,2)}, {round(hi,2)}]")
    max_per_gesture = expect.get("max_cards_per_gesture")
    if max_per_gesture is not None and m["anchors_per_gesture"] is not None:
        if m["anchors_per_gesture"] > max_per_gesture:
            problems.append(f"{m['anchors_per_gesture']} distinct cards per gesture above {max_per_gesture}")
    if expect.get("require_no_repeat") and m["repeated_anchor_events"] > 0:
        problems.append(f"{m['repeated_anchor_events']} advance events repeated the previous anchor")
    if expect.get("require_no_stationary") and m["stationary_events"] > 0:
        problems.append(f"{m['stationary_events']} stationary advance events")
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--trace", required=True)
    ap.add_argument("--phases", required=True, help="JSONL: one record per phase (label, started_at, ended_at, gestures, expect)")
    ap.add_argument("--since", type=float, default=0.0)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    if not os.path.exists(args.trace):
        print(f"trace missing: {args.trace}", file=sys.stderr)
        return 2
    phases = load_phases(args.phases)
    advances = load_advances(args.trace, args.since)
    results = []
    for phase in phases:
        m = measure(phase, advances)
        problems = judge(m, phase.get("expect") or {})
        m["expect"] = phase.get("expect")
        m["verdict"] = "MISS" if problems else "HIT"
        m["problems"] = problems
        results.append(m)
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        for m in results:
            print(f"[{m['verdict']}] {m['label']}: {m['distinct_anchors_per_s']} distinct cards/s, "
                  f"{m['gesture_rate_per_s']} gestures/s, {m['anchors_per_gesture']} cards/gesture, "
                  f"repeats={m['repeated_anchor_events']}, stationary={m['stationary_events']}")
            for p in m["problems"]:
                print(f"    - {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
