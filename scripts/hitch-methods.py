#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/hitch-methods.py — as métricas **por método de gesto** de uma corrida do `hitch-pass.sh`.

Por que existe: a corrida do experimento roda vários métodos de gesto na mesma sessão (A: `swipeUp(.fast)`;
B: arrastos em etapas; C: `swipeUp(.slow)`), e cada método lança o **seu próprio** app — logo tem o seu
namespace, o seu `runtime.sqlite` e o seu `trace.jsonl`. O aglomerado da corrida inteira esconderia a
diferença entre os gestos, que é exatamente o que H3 mede.

O mapa método → namespace não é adivinhado: cada anexo do XCTest carrega o **carimbo do instante** em que foi
criado (`manifest.json`), e o namespace do método é o cujo traço contém aquele instante na sua janela de
relógio. A correspondência é **verificada**: a série que o próprio app publicou no anexo diz
`after=…;seconds=N`, e o número de eventos `frames` do traço daquele namespace tem de casar com N.

Uso:
    python3 scripts/hitch-methods.py --run /tmp/hx-run-control
    python3 scripts/hitch-methods.py --run /tmp/hx-run-control --run /tmp/hx-run-branch   # compara lado a lado

Exit 0 quando imprimiu; 2 para uso recusado; 1 quando não conseguiu mapear nenhum método.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys


def series_from_attachment(path: str) -> dict:
    """O que o anexo do método registra: a variante, a receita, as cartas e a série publicada."""
    fields = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.rstrip("\n")
        if "=" in line and not line.startswith(("before=", "after=")):
            key, value = line.split("=", 1)
            fields[key] = value
    for line in open(path, encoding="utf-8", errors="replace"):
        match = re.search(r"(after|before)=budget_ms=([0-9.]+);seconds=(\d+);series=(.*)$", line)
        if match and match.group(1) == "after":
            fields["budget_ms"] = match.group(2)
            fields["seconds"] = int(match.group(3))
            fields["series"] = [e for e in match.group(4).split("|") if e]
    return fields


def namespaces(run: str) -> list[dict]:
    """Todo namespace com traço no contêiner da corrida, com a janela de relógio e as métricas do traço."""
    root = os.path.join(run, "container", "Library", "Application Support", "FeedMine")
    found = []
    for entry in sorted(os.listdir(root)) if os.path.isdir(root) else []:
        directory = os.path.join(root, entry)
        trace = os.path.join(directory, "trace.jsonl")
        if not os.path.isdir(directory) or not os.path.exists(trace):
            continue
        events = []
        for line in open(trace, encoding="utf-8", errors="replace"):
            line = line.strip()
            if line:
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
        frames = [e for e in events if e.get("event") == "frames"]
        stamps = [e["at"] for e in events if isinstance(e.get("at"), (int, float))]
        if not frames or not stamps:
            continue
        def total(key: str) -> int:
            return sum(int(e["fields"].get(key) or 0) for e in frames)
        admitted = [e for e in events if e.get("event") == "admitted"]
        advances = [e for e in events if e.get("event") == "advance"]
        anchors = {a["fields"]["anchor"] for a in advances if a["fields"].get("anchor")}
        taxonomy = {"idêntica": 0, "só ordem": 0, "só âncora": 0, "conteúdo": 0, "primeira": 0}
        previous = None
        redundant = 0
        for e in admitted:
            f = e.get("fields") or {}
            if f.get("redundant") == "1":
                redundant += 1
            current = (f.get("sequence"), f.get("order"), f.get("head"), f.get("tail"), f.get("anchor"), f.get("cards"))
            if previous is None:
                taxonomy["primeira"] += 1
            else:
                ps, po, ph, pt, pa, pc = previous
                cs, co, ch, ct, ca, cc = current
                if (ps, ph, pt, pc) != (cs, ch, ct, cc):
                    taxonomy["conteúdo"] += 1
                elif po == co and pa == ca:
                    taxonomy["idêntica"] += 1
                elif pa == ca:
                    taxonomy["só ordem"] += 1
                else:
                    taxonomy["só âncora"] += 1
            previous = current
        found.append({
            "namespace": entry, "trace": trace, "start": min(stamps), "end": max(stamps),
            "windows": len(frames), "frames": total("frames"), "late": total("late"), "bad": total("bad"),
            "severe": total("severe"),
            "worst_ms": max(float(e["fields"].get("worst_ms") or 0) for e in frames),
            "advance": len(advances),
            "forward": sum(1 for a in advances if a["fields"].get("activity") == "forward"),
            "anchors": len(anchors), "admitted": len(admitted), "redundant": redundant, "taxonomy": taxonomy,
            "replenishment": sum(1 for e in events if str(e.get("event", "")).startswith("replenishment")),
            "journey_lines": sum(1 for e in events if e.get("event") == "journey"),
        })
    return found


def map_methods(run: str) -> list[dict]:
    """Mapeia cada anexo de série a um namespace pela **janela de relógio**, e verifica o casamento."""
    manifest = os.path.join(run, "attachments", "manifest.json")
    if not os.path.exists(manifest):
        raise SystemExit(f"REFUSED: {run} não tem attachments/manifest.json")
    document = json.load(open(manifest, encoding="utf-8"))
    available = namespaces(run)
    mapped = []
    for entry in document:
        for attachment in entry.get("attachments", []):
            name = attachment.get("suggestedHumanReadableName", "")
            if not (name.endswith(".txt") and "series" in name):
                continue
            path = os.path.join(run, "attachments", attachment["exportedFileName"])
            fields = series_from_attachment(path)
            stamp = attachment.get("timestamp")
            # O namespace do método é o cujo **fim** está a poucos segundos do carimbo do anexo: o anexo é criado no
            # fim da jornada daquele método, logo depois de o app ser encerrado. Contenção por janela (±30 s) dava
            # ambiguidade entre métodos vizinhos — medido em 2026-10-16, quando B e C casaram com o mesmo namespace.
            # Segundo critério, verificado: a série publicada diz `seconds=N` e o traço daquele namespace tem de ter
            # **no máximo** N eventos `frames` (a cauda do traço se perde no encerramento, medido em 260 vs 299).
            plausible = [n for n in available
                         if fields.get("seconds") is None or n["windows"] <= fields["seconds"]]
            best = min(plausible, key=lambda n: abs(stamp - n["end"])) if plausible else None
            if best is not None and abs(stamp - best["end"]) > 120:
                best = None
            verified = None
            if best is not None and fields.get("seconds") is not None:
                verified = (best["windows"] == fields["seconds"])
            mapped.append({"test": entry.get("testIdentifier", "").split("/")[-1],
                           "variant": fields.get("variant", "?"), "recipe": fields.get("recipe", ""),
                           "seconds": fields.get("seconds"), "initial": fields.get("initial_card"),
                           "final": fields.get("final_card"),
                           "reader_moved": fields.get("initial_card") != fields.get("final_card"),
                           "namespace": best, "verified": verified})
    mapped.sort(key=lambda m: m["namespace"]["start"] if m["namespace"] else 0)
    return mapped


def line(label: str, m: dict) -> str:
    n = m["namespace"]
    if n is None:
        return f"{label:22s} {m['variant'][:22]:22s} SEM NAMESPACE (o traço não casou com o carimbo)"
    fora = n["late"] + n["bad"] + n["severe"]
    ratio = f"{100*fora/n['frames']:.2f}%" if n["frames"] else "n/d"
    per_obs = f"{n['severe']/n['advance']:.4f}" if n["advance"] else "n/d"
    return (f"{label:22s} {n['windows']:>6} {n['frames']:>7} {n['late']:>4} {n['bad']:>4} {n['severe']:>6} "
            f"{ratio:>7} {n['worst_ms']:>7.1f} {n['advance']:>4} {n['forward']:>4} {n['anchors']:>4} "
            f"{n['admitted']:>5} {per_obs:>8} {n['replenishment']:>4}")


def main() -> int:
    parser = argparse.ArgumentParser(prog="hitch-methods.py",
        description="As métricas por método de gesto de uma corrida do hitch-pass.sh.")
    parser.add_argument("--run", action="append", required=True, metavar="DIR")
    parser.add_argument("--json", action="store_true")
    arguments = parser.parse_args()

    documents = {}
    for run in arguments.run:
        if not os.path.isdir(run):
            print(f"REFUSED: {run} não é um diretório", file=sys.stderr)
            return 2
        documents[run] = map_methods(run)
        if not documents[run]:
            print(f"NOT_RUN: nenhum método mapeado em {run}", file=sys.stderr)
            return 1
    if arguments.json:
        print(json.dumps(documents, indent=2, ensure_ascii=False))
        return 0

    for run, mapped in documents.items():
        print("=" * 118)
        print(f"corrida: {run}   ({len(mapped)} métodos)")
        print(f"{'método (variante)':22s} {'janel':>6} {'quadros':>7} {'late':>4} {'bad':>4} {'severe':>6} "
              f"{'%fora':>7} {'pior':>7} {'adv':>4} {'fwd':>4} {'ânc':>4} {'admis':>5} {'sev/obs':>8} {'repl':>4}")
        for m in mapped:
            print(line(m["variant"][:22], m))
            if not m["reader_moved"]:
                print(f"    REFUTAÇÃO: o leitor NÃO se moveu neste método (initial == final); as métricas "
                      f"deste gesto não valem como custo de rolagem")
            if m["verified"] is False:
                print(f"    AVISO: a série publicada diz seconds={m['seconds']} e o traço tem "
                      f"{m['namespace']['windows']} janelas — o mapa método→namespace pode estar trocado")
            if m["verified"] is True:
                print(f"    verificado: a série do anexo diz seconds={m['seconds']} e o traço daquele "
                      f"namespace tem exatamente {m['namespace']['windows']} janelas")
        print("  taxonomia das admissões por método (idênticas / só âncora / conteúdo) e redundantes marcadas:")
        for m in mapped:
            if m["namespace"]:
                t = m["namespace"]["taxonomy"]
                print(f"    {m['variant'][:22]:22s} idênticas={t['idêntica']:3d} só âncora={t['só âncora']:3d} "
                      f"conteúdo={t['conteúdo']:3d} marcadas redundant=1: {m['namespace']['redundant']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
