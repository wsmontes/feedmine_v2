#!/usr/bin/env python3
"""FeedMine acceptance-benchmark oracle (baseline 1.0).

This file is the evaluator, not the product. It reads only what a run leaves behind — the corpus's own labels, the
local transport's request log and the app's database — and it judges against the thresholds the benchmark fixes.
It never imports app code, and it must not be edited to accommodate a build: its hash is part of the frozen
manifest, and `bench/run.sh` refuses to run when the manifest no longer matches.

Gates implemented here (see docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md §3):
  B01  discovery without a subscription
  B02  relevance, variety and editorial identity
  B03  runway over the benchmark's own trace — its clause set is reported, with the clauses this oracle cannot
       measure named as such rather than guessed.

Usage:
  python3 bench/oracle.py --run <bench/run/<stamp>> --corpus bench/corpus --database <runtime.sqlite> \
      [--database-b <runtime-b.sqlite>] --gate B01
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3
import sys
import uuid

CATALOG_SOURCE_NAMESPACE = "feedmine.v1-catalog.source"
CATALOG_TARGET_NAMESPACE = "feedmine.v1-catalog.target"
CATALOG_BINDING_NAMESPACE = "feedmine.v1-catalog.binding"

# The four sources the app shipped as its starter set: the benchmark names them as the thing discovery must not
# depend on.
STARTER_KEYS = {
    "https://feeds.bbci.co.uk/news/rss.xml",
    "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml",
    "https://feeds.npr.org/1001/rss.xml",
    "https://theguardian.com/world/rss",
}


def stable_uuid(namespace: str, key: str) -> str:
    """The identity derivation the catalogue mapping uses (PD-2): SHA-256(namespace NUL key), first 16 bytes,
    version 8. Recomputing it here is what lets the oracle join the app's own rows back to the corpus's keys
    without asking the app anything."""
    digest = bytearray(hashlib.sha256(f"{namespace}\0{key}".encode("utf-8")).digest()[:16])
    digest[6] = (digest[6] & 0x0F) | 0x80
    digest[8] = (digest[8] & 0x3F) | 0x80
    return str(uuid.UUID(bytes=bytes(digest))).upper()


def load_corpus(corpus_dir: str) -> dict:
    with open(os.path.join(corpus_dir, "items.json"), encoding="utf-8") as handle:
        items = json.load(handle)
    item_by_reference: dict[str, dict] = {}
    for item in items.get("items", []):
        for reference in {item.get("url"), item.get("link"), item.get("media", {}).get("url")}:
            if reference:
                item_by_reference[reference] = item
    return {"items": items.get("items", []), "by_reference": item_by_reference,
            "profiles": items.get("profiles", {})}


def load_log(log_path: str) -> list[dict]:
    entries = []
    if not os.path.exists(log_path):
        return entries
    with open(log_path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return entries


def cards(database: str) -> list[dict]:
    if not os.path.exists(database):
        # The run left no readable state (the device went away, the app never started). That is a missing
        # measurement: the gate is NOT_RUN with the reason stated, never a crash that loses the report.
        return []
    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        rows = connection.execute(
            """
            SELECT c.segment_id, c.ordinal, c.source_id, c.source_display_name, c.title,
                   c.primary_action_reference, c.origin_record_id, c.origin_revision_id, c.timestamp_value
            FROM published_cards c
            ORDER BY c.segment_id, c.ordinal
            """
        ).fetchall()
    finally:
        connection.close()
    return [dict(row) for row in rows]


def declared_subjects(settings_json: str | None, place: str | None) -> list[str]:
    """The subjects the reader declared inside the feed, read from the app's own preferences: every `.more` topic
    that is not the place the first run answered."""
    if not settings_json:
        return []
    try:
        settings = json.loads(settings_json)
    except json.JSONDecodeError:
        return []
    topics = (settings.get("discoveryProfile") or {}).get("topicPreferences") or {}
    declared = []
    for key, level in topics.items():
        if level != "more":
            continue
        node = key[6:] if key.startswith("topic:") else key
        # Only the **place itself** is the first run's answer: a deeper node under it is a subject the reader
        # declared in the feed, and treating it as the place hid a real answer (measured).
        if place and node == place:
            continue
        declared.append(node)
    return sorted(declared)


def walked_phases(run_dir: str, gate: str, profile: str) -> list[str]:
    """The phases the driver really walked, as it recorded them. Absent file = no phase claimed."""
    path = os.path.join(run_dir, f"{gate}-{profile}.phases")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as handle:
        return [line.strip() for line in handle if line.strip()]


def registered(database: str) -> list[str]:
    if not os.path.exists(database):
        return []
    """The pool: every source the app itself registered as an acquisition target.

    Kept apart from the other two states on purpose (the review's requirement): a source can be **registered**
    and never contacted, and contacted without reaching a card. Only the third state is what the reader sees.
    """
    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    try:
        rows = connection.execute("SELECT DISTINCT source_id FROM acquisition_target_sources").fetchall()
    finally:
        connection.close()
    return sorted(row[0] for row in rows)


def key_of(source_id: str, keys: list[str]) -> str | None:
    """The catalogue key a v2 source identity came from, recomputed rather than asked for."""
    wanted = (source_id or "").upper()
    for key in keys:
        if stable_uuid(CATALOG_SOURCE_NAMESPACE, key).upper() == wanted:
            return key
    return None


def gate_b01(run: dict, corpus: dict, catalog_keys: list[str]) -> dict:
    log = run["log"]
    contacted = sorted({entry.get("source") for entry in log if entry.get("source")})
    # Three states, never conflated: what the app registered, what the transport was asked for, what reached cards.
    pool = run.get("registered")
    published = run["cards"]
    contributing: dict[str, int] = {}
    for card in published:
        key = key_of(card.get("source_id"), catalog_keys)
        if key:
            contributing[key] = contributing.get(key, 0) + 1
    first_300 = published[:300]
    contributing_first_300 = sorted({key_of(card.get("source_id"), catalog_keys) for card in first_300} - {None})

    walked = run.get("phases")
    # The second pass is a journey of its own: a phase it never walked is a protocol that did not run there, and
    # reading only the first profile's record hid exactly that.
    walked_b = run.get("phases_b") if run.get("cards_b") is not None else None
    # B01's thematic phase, judged where it is a fact and not a claim: the reader's own stored answers. Two
    # subjects declared **inside the feed** are two `.more` topics that are not the place the first run answered.
    answers = declared_subjects(run.get("settings"), corpus.get("profiles", {}).get("A", {}).get("region"))
    clauses = [
        {
            "clause": "a jornada vigente foi caminhada nas duas fases observáveis, nos dois perfis",
            "observed": {"A": walked, "B": walked_b, "subjects_declared_in_the_feed": answers},
            "expected": "neutral e thematic (o feed neutro, e o feed após as duas respostas dentro dele)",
            # A phase the app does not offer yet is a protocol that did not run, not a criterion the app failed:
            # the report states which phases were walked, and the gate stays NOT_RUN (never a quiet pass).
            "pass": (True if (walked is not None and "neutral" in walked and len(answers) >= 2
                and (walked_b is None or "neutral" in walked_b)) else None),
        },
        {
            "clause": "não depende das quatro fontes padrão",
            "observed": sorted(set(contributing) & STARTER_KEYS),
            "expected": "as fontes padrão não são a única origem do feed",
            "pass": bool(contributing) and bool(set(contributing) - STARTER_KEYS),
        },
        {
            "clause": "≥50 fontes distintas entram automaticamente no conjunto de aquisição",
            "observed": len(pool) if pool is not None else None,
            "expected": ">=50 registradas no conjunto de aquisição",
            "pass": (len(pool) >= 50) if pool is not None else None,
        },
        {
            "clause": "≥20 fontes distintas contribuem com os primeiros 300 cards",
            "observed": len(contributing_first_300),
            "expected": ">=20",
            "pass": len(contributing_first_300) >= 20,
        },
    ]
    if run.get("cards_b") is not None:
        # The two passes share one transport and one log, so the log cannot tell them apart. What each pass
        # decided to consult is per-database, and that is the registry: it is the measurement that is
        # per-profile by construction.
        registered_b = list(run.get("registered_b") or [])
        clauses.append({
            "clause": "outro perfil muda o conjunto de aquisição de modo explicável",
            "observed": {"a": len(pool or []), "b": len(registered_b),
                         "iguais": len(set(pool or []) & set(registered_b))},
            "expected": "os dois perfis não adquirem o mesmo conjunto",
            "pass": (bool(registered_b) and set(pool or []) != set(registered_b)) if pool is not None else None,
        })
    else:
        clauses.append({"clause": "outro perfil muda as fontes consultadas", "observed": None,
                        "expected": "segunda passagem com o perfil B", "pass": None})

    return {
        "gate": "B01",
        "clauses": clauses,
        "states": {
            "registered_in_the_acquisition_set": len(pool) if pool is not None else None,
            "contacted_over_the_wire": len(contacted),
            "published_sources": len(contributing),
            "published_cards": len(published),
        },
        "contacted_sources": contacted,
        "contributing_sources": contributing,
        "cards": len(published),
    }


def gate_b02(run: dict, corpus: dict, catalog_keys: list[str]) -> dict:
    published = run["cards"][:200]
    profile = corpus.get("profiles", {}).get("A", {})
    interests = set(profile.get("interests", []))
    languages = set(profile.get("languages", []))
    relevant = 0
    matched = 0
    for card in published:
        item = corpus["by_reference"].get(card.get("primary_action_reference"))
        if not item:
            continue
        matched += 1
        topic = item.get("topic")
        language = item.get("language")
        if (not interests or any(topic == interest or (topic or "").startswith(interest + "/") for interest in interests)) \
                and (not languages or language in languages):
            relevant += 1
    sources = [key_of(card.get("source_id"), catalog_keys) for card in published]
    counts: dict[str, int] = {}
    for key in sources:
        if key:
            counts[key] = counts.get(key, 0) + 1
    adjacency = sum(1 for left, right in zip(sources, sources[1:]) if left and left == right)
    canonical = [card.get("origin_revision_id") for card in published]
    duplicates = len(canonical) - len(set(canonical))
    share = max(counts.values(), default=0) / max(1, len(published))
    lane = len([value for value in sources if value])

    clauses = [
        {"clause": "≥80% dos 200 cards correspondem ao perfil",
         "observed": {"relevantes": relevant, "com rótulo": matched, "cards": len(published)},
         "expected": ">=80%", "pass": matched > 0 and relevant >= 0.8 * len(published)},
        {"clause": "≥20 fontes distintas", "observed": len(counts), "expected": ">=20",
         "pass": len(counts) >= 20},
        {"clause": "nenhuma fonte >15%", "observed": round(share, 3), "expected": "<=0.15",
         "pass": share <= 0.15},
        {"clause": "zero pares consecutivos da mesma fonte", "observed": adjacency, "expected": "0",
         "pass": adjacency == 0},
        {"clause": "zero duplicatas de artigo canônico", "observed": duplicates, "expected": "0",
         "pass": duplicates == 0},
    ]
    if lane < len(published):
        clauses.append({"clause": "toda carta publicada tem uma fonte conhecida",
                        "observed": lane, "expected": len(published), "pass": False})
    # The phase is judged by **evidence**: the reader's own stored answers, exactly as B01 judges it. A phase name
    # in the trail is not proof that the reader declared subjects.
    if len(declared_subjects(run.get("settings"), corpus.get("profiles", {}).get("A", {}).get("region"))) < 2:
        # B02's subject is the feed the reader gets **after** answering in it. Until that phase is walked, its
        # thresholds are NOT_RUN — the neutral feed is a different measurement, and calling it a pass here would
        # be the benchmark judging something it never saw.
        for clause in clauses:
            clause["pass"] = None
            clause["expected"] = "as duas respostas temáticas dentro do feed"
    return {"gate": "B02", "clauses": clauses, "source_counts": counts, "cards": len(published),
        "phases": run.get("phases")}


def read_settings(database: str) -> str | None:
    """The reader's stored preferences: B01's thematic phase is a fact about what they declared, not a UI claim."""
    if not os.path.exists(database):
        return None
    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    try:
        row = connection.execute("SELECT settings_json FROM reader_preferences LIMIT 1").fetchone()
    finally:
        connection.close()
    if not row or row[0] is None:
        return None
    value = row[0]
    return value.decode("utf-8", "replace") if isinstance(value, (bytes, bytearray)) else value


def trace_events(database: str) -> list[dict]:
    """The app's own evidence, written beside the runtime database: F05 asks for facts, not for a feeling."""
    path = os.path.join(os.path.dirname(database), "trace.jsonl")
    if not os.path.exists(path):
        return []
    events = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return events


def gate_b03(run: dict, corpus: dict, catalog_keys: list[str]) -> dict:
    published = run["cards"]
    segments: dict[str, list[dict]] = {}
    for card in published:
        segments.setdefault(card.get("segment_id") or "?", []).append(card)
    ordered = [card for _, rows in sorted(segments.items()) for card in sorted(rows, key=lambda r: r["ordinal"])]
    duplicates = len(ordered) - len({card.get("origin_revision_id") for card in ordered})
    adjacency = sum(1 for left, right in zip(ordered, ordered[1:])
                    if left.get("source_id") and left.get("source_id") == right.get("source_id"))
    # The trace: the reader's own advances and the content each one actually produced.
    events = run.get("trace") or []
    advances = [event["at"] for event in events if event.get("event") == "advance"]
    admissions = [event["at"] for event in events if event.get("event") == "admitted"]
    # A visible stall: the reader advanced and nothing new was admitted for a full second afterwards.
    stalls = 0
    for moment in advances:
        following = [at for at in admissions if at >= moment]
        if not following or following[0] - moment >= 1.0:
            stalls += 1
    # The readiness lives in the event's own fields (the trace nests them), not at the top level: reading the
    # wrong key made 871 candidates look like a distribution of zeros.
    candidates = [event.get("fields", {}).get("readiness") for event in events
                  if event.get("event") == "candidate"]
    clauses = [
        {"clause": "trinta minutos de avanço com oferta suficiente", "observed": len(advances) or None,
         "expected": "1.800 avanços efetivos", "pass": (len(advances) >= 1_800) if advances else None},
        {"clause": "zero repetição para disfarçar falta de oferta", "observed": duplicates, "expected": "0",
         "pass": duplicates == 0},
        {"clause": "zero pares consecutivos da mesma fonte no trace inteiro", "observed": adjacency,
         "expected": "0", "pass": adjacency == 0},
        # The rule, stated: the reader advanced, and the app gained nothing new in the following second.
        {"clause": "zero paralisação visível ≥1 s por falta de runway",
         "observed": {"paradas": stalls, "regra": "avanço sem admissão em 1 s"} if advances else None,
         "expected": "0", "pass": (stalls == 0) if advances else None},
        {"clause": "a prontidão de cada candidato foi registrada", "observed": {
            "candidatos": len(candidates), "pendentes": candidates.count("pending"),
            "texto": candidates.count("textOnly"), "preparados": candidates.count("prepared")},
         "expected": "todo candidato examinado tem sua prontidão medida",
         # A clause that passes while measuring nothing is the one thing this oracle cannot do, and it did: measured
         # `20261011T043906Z`, this clause returned PASS with 871 candidates and 0/0/0 labels. Two rules, in order:
         # with no examined candidate at all there is no measurement to judge, so the verdict is NOT_RUN (None);
         # with candidates examined, every one of them must carry one of the three readiness labels, or the clause
         # FAILS — a gap found is not the same thing as nothing measured.
         "pass": (candidates.count("pending") + candidates.count("textOnly")
                  + candidates.count("prepared") == len(candidates)) if candidates else None},
    ]
    return {"gate": "B03", "clauses": clauses, "cards": len(ordered), "states": {
        "advances": len(advances), "admissions": len(admissions), "stalls": stalls,
        "candidates": len(candidates), "pending": candidates.count("pending")}}




def gate_b04(run: dict, corpus: dict, catalog_keys: list[str]) -> dict:
    """B04 — the presented feed is sacred. The driver measured; the oracle judges the measurements, never the
    driver's opinion: every stability fact it recorded must be true, and a full protocol must have run."""
    walked = run.get("phases") or []
    facts = {}
    for phase in walked:
        if ":" not in phase:
            continue
        name, value = phase.split(":", 1)
        if name.startswith("b04-"):
            facts[name] = value
    stability = {name: value for name, value in facts.items() if name.endswith(("stable", "order", "holds"))}
    # Three outcomes, and they are not the same thing (architect, 2026-10-11): `false` is movement and fails the
    # gate; `not-measurable` is a measurement that could not be taken — it is never a pass (the gate is incomplete)
    # and it is never a failure of the product either. The product criterion is unchanged: `true` is stable.
    unstable = sorted(name for name, value in stability.items() if value == "false")
    unmeasurable = sorted(name for name, value in stability.items() if value not in ("true", "false"))
    clauses = [
        {
            "clause": "o protocolo de B04 foi caminhado (âncora, convite, ócio, rotação, background)",
            "observed": sorted(facts.keys()) or None,
            "expected": "as medições de B04 no registro de fases",
            "pass": True if facts else None,
        },
        {
            "clause": "nada do que o leitor já tinha se moveu, reordenou ou retratou",
            "observed": {"medidas": stability, "instaveis": unstable, "nao_mediveis": unmeasurable},
            "expected": "todas estáveis; instável falha, não medível deixa o gate incompleto",
            "pass": (not unstable) if stability and not unmeasurable else None,
        },
    ]
    return {"gate": "B04", "clauses": clauses,
            "states": {"measurements": len(stability), "unstable": len(unstable),
                       "not_measurable": len(unmeasurable)}}


def gate_b05(run: dict, corpus: dict, catalog_keys: list[str]) -> dict:
    """B05 — A → B → A, local memory and the offline return. Zero silent loss of state is the whole clause: every
    fact the driver recorded must be true, and the app's database must show the reading position persisted."""
    walked = run.get("phases") or []
    facts = {}
    for phase in walked:
        if ":" not in phase:
            continue
        name, value = phase.split(":", 1)
        if name.startswith("b05-"):
            facts[name] = value
    checks = {name: value for name, value in facts.items()
              if name.endswith(("saved", "anchor", "local", "cards", "reached", "anchor-before"))}
    failed = sorted(name for name, value in checks.items() if value not in ("true", "none") and not value.startswith("b05-"))
    # `anchor-before` carries an identity, not a verdict: it is evidence, not a check.
    failed = [name for name in failed if name != "b05-anchor-before"]
    clauses = [
        {
            "clause": "o protocolo de B05 foi caminhado (salvar, A→B→A, reabrir, offline)",
            "observed": sorted(facts.keys()) or None,
            "expected": "as medições de B05 no registro de fases",
            "pass": True if facts else None,
        },
        {
            "clause": "zero perda silenciosa de estado",
            "observed": {"medidas": checks, "falhas": failed},
            "expected": "todas verdadeiras",
            "pass": (not failed) if checks else None,
        },
    ]
    return {"gate": "B05", "clauses": clauses, "states": {"measurements": len(checks), "failed": len(failed)}}


def verdict(clauses: list[dict]) -> str:
    if any(clause["pass"] is False for clause in clauses):
        return "FAIL"
    if any(clause["pass"] is None for clause in clauses):
        return "NOT_RUN"
    return "PASS"


GATES = {"B01": gate_b01, "B02": gate_b02, "B03": gate_b03, "B04": gate_b04, "B05": gate_b05}

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", required=True)
    parser.add_argument("--corpus", default="bench/corpus")
    parser.add_argument("--database", required=True)
    parser.add_argument("--database-b")
    parser.add_argument("--gate", required=True, choices=sorted(GATES))
    args = parser.parse_args()

    corpus = load_corpus(args.corpus)
    connection = sqlite3.connect(f"file:{os.path.join(args.corpus, 'catalog.sqlite')}?mode=ro", uri=True)
    try:
        catalog_keys = [row[0] for row in connection.execute("SELECT key FROM catalog_source").fetchall()]
    finally:
        connection.close()

    run = {"cards": cards(args.database), "log": load_log(os.path.join(args.run, "server.log")),
        "registered": registered(args.database), "trace": trace_events(args.database)}
    run["settings"] = read_settings(args.database)
    run["phases"] = walked_phases(args.run, args.gate, "A")
    run["phases_b"] = walked_phases(args.run, args.gate, "B")
    if args.database_b:
        run["cards_b"] = cards(args.database_b)
        run["log_b"] = load_log(os.path.join(args.run, "server-b.log"))
        run["registered_b"] = registered(args.database_b)
        run["phases_b"] = walked_phases(args.run, args.gate, "B")

    if not os.path.exists(args.database):
        result = {"gate": args.gate, "clauses": [{
            "clause": "a execução deixou um banco de leitura do app",
            "observed": args.database,
            "expected": "um banco em modo leitura com o que a jornada publicou",
            "pass": None,
        }], "states": {}}
    else:
        result = GATES[args.gate](run, corpus, catalog_keys)
    result["verdict"] = verdict(result["clauses"])
    result["identity"] = {"database": args.database, "corpus_items": len(corpus["items"]),
                          "catalog_keys": len(catalog_keys)}
    with open(os.path.join(args.run, f"{args.gate}.json"), "w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2)
    print(json.dumps({"gate": result["gate"], "verdict": result["verdict"],
                      "clauses": [{k: clause[k] for k in ("clause", "observed", "expected", "pass")}
                                  for clause in result["clauses"]]}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
