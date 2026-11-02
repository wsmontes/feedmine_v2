# Faithful port of Sources/FeedMineEditorial/MaximumDistanceSequencing.swift (v6) for controlled supplies.
# Base order = SelectionEngine's: weight DESC (all 1 here), timestamp DESC, id DESC.
import sys, random
from collections import Counter
sys.stdout.reconfigure(encoding="utf-8")
INF = float("inf")

def sequence(cands, history=()):
    # cands: list of dict(id, src, type, subj:set, ts) ; history newest-first list of facts
    ordered = sorted(cands, key=lambda c: (-c["ts"], c["id"]), reverse=False)
    type_seen, subj_seen, src_seen = {}, {}, {}
    for i, f in enumerate(history):
        rel = -1 - i
        if f["type"] is not None: type_seen.setdefault(f["type"], rel)
        for s in f["subj"]: subj_seen.setdefault(s, rel)
        src_seen.setdefault(f["src"], rel)
    prev = history[0]["src"] if history else None
    remaining = list(range(len(ordered))); placed = []; cur = 0
    def dist(c, d):
        if d == 0:
            if c["type"] is None: return None
            return INF if c["type"] not in type_seen else cur - type_seen[c["type"]]
        if d == 1:
            if not c["subj"]: return None
            seen = [subj_seen[s] for s in c["subj"] if s in subj_seen]
            return INF if not seen else cur - max(seen)
        seen = src_seen.get(c["src"])
        return INF if seen is None else cur - seen
    while remaining:
        comp = [i for i in remaining if ordered[i]["src"] != prev]
        if not comp: break
        pool = comp
        for d in range(3):
            sc = [(i, dist(ordered[i], d)) for i in pool]
            known = [v for _, v in sc if v is not None]
            if not known: continue
            m = max(known)
            pool = [i for i, v in sc if v is None or v == m]
        ch = pool[0]; c = ordered[ch]; placed.append(c); remaining.remove(ch); prev = c["src"]
        if c["type"] is not None: type_seen[c["type"]] = cur
        for s in c["subj"]: subj_seen[s] = cur
        src_seen[c["src"]] = cur; cur += 1
    return placed, [ordered[i] for i in remaining]

def report(name, placed, first=50):
    seq = placed[:first]
    srcs = [c["src"] for c in seq]
    cnt = Counter(srcs)
    gaps, last = [], {}
    for i, s in enumerate(srcs):
        if s in last: gaps.append(i - last[s])
        last[s] = i
    top = cnt.most_common(3)
    print(f"{name}: first{len(seq)} distinct={len(cnt)} top={top} "
          f"min_gap={min(gaps) if gaps else '-'} mean_gap={sum(gaps)/len(gaps):.1f}" if gaps else f"{name}: distinct={len(cnt)}")
    print("   ", " ".join(s for s in srcs[:30]))

rng = random.Random(7)
def items(src, n, typ=None, subj_fn=lambda i: set(), ts_fn=None):
    return [dict(id=f"{src}-{i:03d}", src=src, type=typ, subj=subj_fn(i),
                 ts=(ts_fn(i) if ts_fn else rng.random())) for i in range(n)]

# A: one prolific podcast among 20 text feeds (the 24/out measurement had 936 audio of 1425).
A = items("POD", 40, "audio") + sum((items(f"T{k:02d}", 5, "none") for k in range(20)), [])
report("A one podcast + 20 text feeds", sequence(A)[0])

# B: four podcasts among 20 text feeds.
B = sum((items(f"P{k}", 10, "audio") for k in range(4)), []) + sum((items(f"T{k:02d}", 5, "none") for k in range(20)), [])
report("B four podcasts + 20 text feeds", sequence(B)[0])

# C: text only; one blog tags every post with fresh tags, 19 feeds use 2 stable categories each.
C = items("TAGGY", 30, "none", subj_fn=lambda i: {f"tag{i}a", f"tag{i}b"}) + \
    sum((items(f"T{k:02d}", 5, "none", subj_fn=lambda i, k=k: {f"cat{k%3}"}) for k in range(19)), [])
report("C one per-post-tagger + 19 categorised feeds", sequence(C)[0])

# D: text only, no subjects anywhere, one prolific source (60) + 19 small (3): recency decides.
D = items("BIG", 60, "none") + sum((items(f"T{k:02d}", 3, "none") for k in range(19)), [])
report("D one prolific + 19 small, no facts", sequence(D)[0])

# E: undeclared type (None) items from one source mixed with typed others: unknown survives every filter.
E = items("UNK", 30, None, ts_fn=lambda i: 1.0 + i) + sum((items(f"T{k:02d}", 5, "none") for k in range(20)), [])
report("E newest items with unknown facts", sequence(E)[0])

# F: determinism: same supply twice -> identical order (no seed is read).
p1 = [c["id"] for c in sequence(B)[0]]; p2 = [c["id"] for c in sequence(list(reversed(B)))[0]]
print("F same supply, different input order -> identical output:", p1 == p2)

# --- V1 EditorialSequencer (feedmine-dev b5c2f59c, EditorialSequencer.swift:42-91): least-used round-robin by provider,
# never the provider taken just before while another has candidates; ties by earliest input index.
def v1_sequence(cands):
    ordered = sorted(cands, key=lambda c: (-c["ts"], c["id"]))
    buckets, order = {}, []
    for i, c in enumerate(ordered):
        if c["src"] not in buckets: order.append(c["src"]); buckets[c["src"]] = []
        buckets[c["src"]].append((i, c))
    cur = {k: 0 for k in order}; taken = {k: 0 for k in order}; last = None; out = []
    while len(out) < len(ordered):
        best = None; bt = None; bi = None
        others = lambda k: any(o != k and cur[o] < len(buckets[o]) for o in order)
        for k in order:
            if cur[k] >= len(buckets[k]): continue
            if k == last and others(k): continue
            idx = buckets[k][cur[k]][0]
            if best is None or taken[k] < bt or (taken[k] == bt and idx < bi):
                best, bt, bi = k, taken[k], idx
        out.append(buckets[best][cur[best]][1]); cur[best] += 1; taken[best] += 1; last = best
    return out

def types(seq, n=50):
    return dict(Counter(c["type"] for c in seq[:n]))

print()
print("=== V1 EditorialSequencer on the same supplies ===")
for name, supply in [("A", A), ("B", B), ("C", C), ("D", D)]:
    v1 = v1_sequence(supply); v6 = sequence(supply)[0]
    report(f"{name} v1", v1)
    print(f"    types v6={types(v6)} v1={types(v1)}")

# --- Hybrid sketch (not production code): V1's least-used provider share is the hard first filter;
# among providers tied at the minimum share (and not the previous one), v6's type -> subject distance
# chooses; the earliest input item breaks the remaining tie.
def hybrid_sequence(cands):
    ordered = sorted(cands, key=lambda c: (-c["ts"], c["id"]))
    buckets, order = {}, []
    for i, c in enumerate(ordered):
        if c["src"] not in buckets: order.append(c["src"]); buckets[c["src"]] = []
        buckets[c["src"]].append((i, c))
    cur = {k: 0 for k in order}; taken = {k: 0 for k in order}; last = None; out = []
    type_seen, subj_seen = {}, {}; pos = 0
    def dist_type(c):
        if c["type"] is None: return None
        return INF if c["type"] not in type_seen else pos - type_seen[c["type"]]
    def dist_subj(c):
        if not c["subj"]: return None
        seen = [subj_seen[s] for s in c["subj"] if s in subj_seen]
        return INF if not seen else pos - max(seen)
    while len(out) < len(ordered):
        live = [k for k in order if cur[k] < len(buckets[k])]
        allowed = [k for k in live if k != last] or live
        low = min(taken[k] for k in allowed)
        pool = [k for k in allowed if taken[k] == low]
        for fn in (dist_type, dist_subj):
            sc = [(k, fn(buckets[k][cur[k]][1])) for k in pool]
            known = [v for _, v in sc if v is not None]
            if known:
                m = max(known); pool = [k for k, v in sc if v is None or v == m]
        k = min(pool, key=lambda k: buckets[k][cur[k]][0])
        c = buckets[k][cur[k]][1]; out.append(c); cur[k] += 1; taken[k] += 1; last = k
        if c["type"] is not None: type_seen[c["type"]] = pos
        for s in c["subj"]: subj_seen[s] = pos
        pos += 1
    return out

def type_gaps(seq, n=50):
    last, gaps = {}, {}
    for i, c in enumerate(seq[:n]):
        t = c["type"]
        if t in last: gaps.setdefault(t, []).append(i - last[t])
        last[t] = i
    return {t: round(sum(g)/len(g), 1) for t, g in gaps.items()}

print()
print("=== Hybrid sketch: V1 share first, v6 type/subject distance within ties ===")
for name, supply in [("A", A), ("B", B), ("C", C), ("D", D)]:
    h = hybrid_sequence(supply)
    report(f"{name} hybrid", h)
    print(f"    types={types(h)} mean_type_gap={type_gaps(h)}")
