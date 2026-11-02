# Faithful port of the v7 rule in Sources/FeedMineEditorial/MaximumDistanceSequencing.swift
# (sourceShareWindow != nil) next to v6 (sourceShareWindow == None), for controlled supplies.
# v7 = per choice: PD-4 compatible -> lowest source share in the last W positions (nil holes occupy
# slots, the share of a multi-source candidate is its most-used source, no source = neutral) ->
# v6 type -> subjects -> source distance -> base order.
# Runs both a single opportunity of 50 and the production shape: opportunities of 4 cards that read
# the Edition history (newest first) the previous opportunities published.
import sys
from collections import Counter
sys.stdout.reconfigure(encoding="utf-8")
INF = float("inf")
WINDOW = 32


def sequence(ordered, history=(), window=None, limit=None):
    # ordered: base order (ts DESC, id DESC). history: newest-first facts or None holes.
    type_seen, subj_seen, src_seen = {}, {}, {}
    for i, f in enumerate(history):
        if f is None:
            continue
        rel = -1 - i
        if f["type"] is not None:
            type_seen.setdefault(f["type"], rel)
        for s in f["subj"]:
            subj_seen.setdefault(s, rel)
        for s in f["srcs"]:
            src_seen.setdefault(s, rel)
    recent, usage = [], Counter()
    if window:
        for f in reversed(list(history)[:window]):
            srcs = set(f["srcs"]) if f else set()
            recent.append(srcs)
            usage.update(srcs)
    prev = set(history[0]["srcs"]) if history and history[0] else None
    remaining = list(range(len(ordered)))
    placed, cur = [], 0

    def dist(c, d):
        if d == 0:
            if c["type"] is None:
                return None
            return INF if c["type"] not in type_seen else cur - type_seen[c["type"]]
        if d == 1:
            if not c["subj"]:
                return None
            seen = [subj_seen[s] for s in c["subj"] if s in subj_seen]
            return INF if not seen else cur - max(seen)
        if not c["srcs"]:
            return None
        seen = [src_seen[s] for s in c["srcs"] if s in src_seen]
        return INF if not seen else cur - max(seen)

    def share(c):
        if not c["srcs"]:
            return None
        return max(usage[s] for s in c["srcs"])

    while remaining and (limit is None or len(placed) < limit):
        # PD-4 as SourceAlternation.compatible: no shared source with the previous card.
        comp = [i for i in remaining if prev is None or not (set(ordered[i]["srcs"]) & prev)]
        if not comp:
            break
        pool = comp
        if window:
            sc = [(i, share(ordered[i])) for i in pool]
            known = [v for _, v in sc if v is not None]
            if known:
                low = min(known)
                pool = [i for i, v in sc if v is None or v == low]
        for d in range(3):
            sc = [(i, dist(ordered[i], d)) for i in pool]
            known = [v for _, v in sc if v is not None]
            if not known:
                continue
            m = max(known)
            pool = [i for i, v in sc if v is None or v == m]
        ch = pool[0]
        c = ordered[ch]
        placed.append(c)
        remaining.remove(ch)
        prev = set(c["srcs"])
        if c["type"] is not None:
            type_seen[c["type"]] = cur
        for s in c["subj"]:
            subj_seen[s] = cur
        for s in c["srcs"]:
            src_seen[s] = cur
        if window:
            recent.append(set(c["srcs"]))
            usage.update(c["srcs"])
            if len(recent) > window:
                usage.subtract(recent.pop(0))
        cur += 1
    return placed


def base(cands):
    return sorted(cands, key=lambda c: (-c["ts"], c["id"]))


def items(src, n, typ, subj_fn=lambda i: set(), ts_fn=lambda i: 0.0):
    return [dict(id=f"{src}-{i:03d}", srcs=[src], type=typ, subj=subj_fn(i), ts=ts_fn(i)) for i in range(n)]


def batched(cands, window, batch=4, total=50):
    # Production shape: each opportunity sees the unpublished supply and the Edition history.
    history, out, pool = [], [], base(cands)
    while len(out) < total and pool:
        got = sequence(pool, history=list(reversed(out)), window=window, limit=batch)
        if not got:
            break
        out.extend(got)
        ids = {c["id"] for c in got}
        pool = [c for c in pool if c["id"] not in ids]
    return out


def report(name, seq, n=50):
    seq = seq[:n]
    cnt = Counter(s for c in seq for s in c["srcs"])
    types = Counter(c["type"] for c in seq)
    adjacent = sum(1 for a, b in zip(seq, seq[1:]) if set(a["srcs"]) & set(b["srcs"]))
    print(f"{name}: n={len(seq)} distinct={len(cnt)} top={cnt.most_common(2)} types={dict(types)} pd4_breaks={adjacent}")


# Newest-first adversarial timestamps: the dominant source is always the most recent supply.
A = items("POD", 40, "audio", ts_fn=lambda i: 1000 - i) + \
    sum((items(f"T{k:02d}", 5, "none", ts_fn=lambda i, k=k: 500 - i * 20 - k) for k in range(20)), [])
B = sum((items(f"P{k}", 10, "audio", ts_fn=lambda i, k=k: 1000 - i * 4 - k) for k in range(4)), []) + \
    sum((items(f"T{k:02d}", 5, "none", ts_fn=lambda i, k=k: 500 - i * 20 - k) for k in range(20)), [])
C = items("TAGGY", 30, "none", subj_fn=lambda i: {f"tag{i}a", f"tag{i}b"}, ts_fn=lambda i: 1000 - i) + \
    sum((items(f"T{k:02d}", 5, "none", subj_fn=lambda i, k=k: {f"cat{k % 3}"},
               ts_fn=lambda i, k=k: 500 - i * 20 - k) for k in range(19)), [])
D = items("BIG", 60, "none", ts_fn=lambda i: 1000 - i) + \
    sum((items(f"T{k:02d}", 3, "none", ts_fn=lambda i, k=k: 500 - i * 20 - k) for k in range(19)), [])

for name, supply in [("A 1 podcast + 20 text", A), ("B 4 podcasts + 20 text", B),
                     ("C per-post tagger + 19", C), ("D prolific + 19 small", D)]:
    print(f"=== {name} ===")
    report("  v6 one opportunity  ", sequence(base(supply)))
    report("  v7 one opportunity  ", sequence(base(supply), window=WINDOW))
    report("  v6 opportunities of 4", batched(supply, None))
    report("  v7 opportunities of 4", batched(supply, WINDOW))

# Late source: 200 positions of 10 sources, then a new source with 20 items joins.
hist = [dict(srcs=[f"S{i % 10}"], type="none", subj=set()) for i in range(200)]
late = items("NEW", 20, "none", ts_fn=lambda i: 1000 - i) + \
    sum((items(f"S{k}", 5, "none", ts_fn=lambda i, k=k: 500 - i * 20 - k) for k in range(10)), [])
got = sequence(base(late), history=hist, window=WINDOW, limit=20)
print("=== late source after 200 positions (v7, 20 cards) ===")
print("  NEW count:", sum(1 for c in got if c["srcs"] == ["NEW"]), " order:", " ".join(c["srcs"][0] for c in got))

# Determinism: input permutation does not change the v7 order.
p1 = [c["id"] for c in sequence(base(B), window=WINDOW)]
p2 = [c["id"] for c in sequence(base(list(reversed(B))), window=WINDOW)]
print("determinism under input permutation:", p1 == p2)
