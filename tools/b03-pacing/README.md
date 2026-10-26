# B03 pacing calibration — external native gesture instrument

**Not the benchmark.** Nothing here produces a B03 verdict, and nothing here may be used as one. This is
a *calibration instrument*, separate from the frozen evaluator in `bench/` (whose files, hashes, criteria,
corpus and durations are untouched). Its purpose is one question the frozen driver cannot answer:

> Can the three-minute shape become the thirty-minute shape — 1 card/s, with 3 cards/s for 20 s every
> 300 s — through real UI, without the rating of "consumed" being inflated by gesture count?

## Why a second instrument exists

The frozen driver calls `feed.swipeUp()` once per simulated second (three times inside a burst window).
Measured on `bench/run/20261026T143646Z`: **679 gestures over 1 844 s = 0.373 gestures/s**, median
interval **2.66 s**. Each swipe also coasts: 5.10 `advance` events per gesture, of which 34.3 % repeat the
previous anchor and 19.1 % are `stationary`. The replay therefore cannot express either requested rate,
and the event counter it feeds is inflated 1.52× over distinct anchors.

## What this instrument is

`inject.swift` posts **HID mouse events with explicit timestamps** into the Simulator window. A mouse drag
in Simulator.app is a touch on the device, so the interaction crosses the real UI and the real gesture
recognizers; there is no XCTest in the loop, no app-side hook, no publication call, no database write.
`AXIsProcessTrusted` is `true` for this host (measured), which is what allows the post.

`pacing_probe.py` is the judge of *pacing only*. It reads two independent records:

- **intent** — the injector's own log: when each gesture was scheduled and when it was actually sent;
- **effect** — the app's `advance` events, filtered to **distinct anchors in traversal order**. A repeated
  anchor or an `activity: stationary` submission is never counted as a card consumed.

## Geometry (measured, not assumed)

| Item | Value |
|---|---|
| device | `FeedMine Bench` = iPhone 17 Pro Max, 440 × 956 pt |
| window | (931, 113), 494 × 1054 pt |
| screenshot | 988 × 2108 px = 2× window points |
| device screen in window | origin ≈ (962, 197), scale ≈ 0.975 window pt per device pt |
| card pitch in screenshots | ≈ 360 px ≈ 180 window pt |

## Usage

```bash
swiftc -O inject.swift -o inject
# base: one gesture per second, 180 pt slow drag
./inject --label base --count 12 --interval-ms 1000 --drag-ms 300 --y0 900 --y1 720
# burst: three gestures per second
./inject --label burst --count 18 --interval-ms 333 --drag-ms 120 --y0 900 --y1 720
# effect, counted in distinct cards
python3 pacing_probe.py --trace <namespace>/trace.jsonl --phases phases.jsonl
```

`phases.jsonl` is one JSON record per phase: `label`, `started_at`, `ended_at`, `gestures`, `expect`
(`base_distinct_per_s`, `base_gesture_per_s`, `max_cards_per_gesture`, `burst_distinct_per_s`,
`require_no_repeat`, `require_no_stationary`).

## Negative control: the frozen run, rejected 17/17

The detector was validated against the **real old instrument**, not a synthetic replay: the frozen driver's
own 679 `Swipe up` timestamps from `bench/run/20261026T143646Z/B03-A.log`, sliced into 10 base windows of
10 s and 7 burst windows of 20 s at the 300 s marks, judged against the frozen run's own trace.

**All 17 windows MISS.** The finding worth keeping:

| window | distinct cards/s | gestures/s | cards/gesture | why it misses |
|---|---|---|---|---|
| base 100–1100 s | 1.1 – 1.5 | 0.3 – 0.4 | 2.0 – 4.2 | gesture rate and yield, not the card rate |
| burst at 300/600/900/1200/1500/1800 s | 0.35 – 1.45 | 0.35 – 0.45 | 1.4 – 4.1 | burst target 3/s |

Six of the ten base windows land **inside** a naive 1 card/s band on card rate while consuming 2.75–4.0
cards per gesture at a third of a gesture per second. That is precisely the inflation the contract excludes
("not a counter of gestures fired"), and it is why `base_gesture_per_s` and `max_cards_per_gesture` exist as
clauses: without them the old instrument would read as a perfect 1/s replay.

## Measured so far (2026-10-26, deliberately small)

| Fact | Evidence |
|---|---|
| Gesture *rate* is solved: 1.005 gestures/s and 2.869 gestures/s, scheduled and sent | injector log: 12 gestures / 11.94 s; 18 / 6.27 s |
| …i.e. the 2.66 s XCTest cycle is **not** a platform floor | 7.7× the frozen driver's 0.373/s on the same device |
| Gestures reach the app as real forward advances with distinct anchors | 6 gestures → 5 distinct anchors, `activity: forward` |
| **A dwell before lift turns the gesture into a tap** | 200 ms hold → release hit the card, iOS handed `127.0.0.1:…` to Safari, and all three following profiles read **0 advances** with cadence still exact |
| **Card yield is not controlled by distance** | one 180 pt drag on a live, growing window produced 47 `advance` events / 42 `cards_traversed` |
| **`advance` ≠ consumption, again** | same probe: `DB023E67…` forward → stationary → forward, `672B4AB8…` twice |
| **A feed at its tail consumes nothing at any cadence** | `cards: 2000`, repeated `runway_completed admitted_cards: 2000`, last advance `stationary` |

**Card yield per gesture is NOT controlled by distance. That is the headline.** One 180 pt / 300 ms drag
coasted **42 distinct cards** on a live, growing window; the *same* profile read ~1 card/gesture on the
clamped B03 tail. Distance is not the control variable — release velocity and the window's growth are — so
no 1/s or 3/s shape is claimed here, and phase 2 must run with `bench/serve.py` up and a stable window.

So: **injection rate is proven; card-yield control is not.** No 1-card/s or 3-card/s claim is made here,
and nothing in this directory has been run for 30 minutes.

## Next measurement (precise, before any B03)

1. **Bed.** Run `bench/serve.py` against the corpus on `127.0.0.1:8757`, fresh namespace copied from a run
   whose reader is at the **head**, so admissions are rate-limited by the transport instead of the tail.
   A growing window re-submits the viewport on every admission, which is what makes `advance` fire without
   a gesture; the bed must hold that effect constant.
2. **Velocity sweep, not distance sweep.** For `v ∈ {0.15, 0.3, 0.6, 1.2, 2.4}` pt/ms, with motion through
   release (no dwell), 10 gestures each: measure distinct anchors per gesture. Pick the velocity whose
   median is 1 for the base and 3 for the burst.
3. **Tap assertion.** After every burst, a screenshot must still show FeedMine frontmost; a URL opening or
   a session loss invalidates the phase.
4. **Compose** 60 s of 1/s + a 10 s burst, require distinct cards/s within ±25 % of intent and ≥95 % of
   gestures producing a new anchor.
5. **Negative control.** Replay the old cadence (2 660 ms interval, XCTest-like fling). The probe must
   reject it — measured gesture rate 0.446/s, so at ~1 card/gesture it lands far under 1 card/s.
6. Only then freeze it as a **separate revision** (`bench/revisions/`, `EVALUATOR-pre-*.sha256`, dated note)
   and run a 30-minute B03 with independent review. The FAIL of `20261026T143646Z` stands until then.
