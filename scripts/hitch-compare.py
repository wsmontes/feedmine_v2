#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/hitch-compare.py — compara duas corridas medidas e devolve o veredito **por experimento** do F48-HITCH-X.

Por que existe: o gate F48-HITCH-X precisa decidir duas coisas com números, e as duas são comparações:
  * **H3** — o custo acompanha as **observações do app** ou a **síntese do gesto**? Compara dois gestos com a mesma
    instrumentação (fast swipes × slow multi-step drags) **normalizando pelo deslocamento alcançado**, porque os
    dois não movem o leitor a mesma distância por construção;
  * **H4a** — coalescer só a publicação redundante muda os quadros, e a mudança é legítima? Compara o controle e o
    ramo com os **mesmos gestos** e exige que âncora, janela e reposição se comportem igual — um experimento que
    "melhora" porque o app deixou de acompanhar o leitor é refutação de si mesmo.

Nenhuma cláusula aqui escolhe limiar: as razões que ele imprime são fatos das duas corridas (quadros, severos,
observações, admissões), e o veredito é o sinal da comparação, com o número ao lado.

Uso:
    python3 scripts/hitch-compare.py --a <dir-da-corrida-A> --b <dir-da-corrida-B> [--json]
    python3 scripts/hitch-compare.py --a <dir> --b <dir> --label-a "controle" --label-b "coalescido"

Cada `--a`/`--b` é o `--out` de `scripts/hitch-pass.sh` (ou o diretório da fase, com `console*.log` +
`container/.../trace.jsonl`) — o mesmo insumo que `scripts/hitch-join.py` come. O script lê os dois pelo join e
compara; ele não mede nada por conta própria.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

JOIN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hitch-join.py")


def joined(path: str) -> dict:
    """Uma corrida, pelo join (mesmo leitor da frente — nenhuma leitura paralela inventada aqui)."""
    out = subprocess.run([sys.executable, JOIN, "--journey", path, "--select", "any", "--json"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        print(out.stdout[-1500:] or out.stderr[-1500:], file=sys.stderr)
        raise SystemExit(f"REFUSED: o join não conseguiu ler {path}")
    return json.loads(out.stdout)[0]


def metrics(doc: dict) -> dict:
    """Os fatos de uma corrida: quadros, buckets, observações do leitor, admissões e a taxonomia delas."""
    totals = doc["totais"]
    summary = doc["resumo_do_insumo"]
    return {
        "janelas": totals["janelas"], "quadros": totals["quadros"], "late": totals["late"], "bad": totals["bad"],
        "severe": totals["severe"], "pior_ms": totals["pior_ms"], "segundos_com_severe": totals["segundos_com_severe"],
        "fora_do_orcamento": totals["late"] + totals["bad"] + totals["severe"],
        "advance": summary["advance"], "advance_forward": summary["advance_forward"],
        "admissões": summary["admissoes"],
        "admissões_redundantes_marcadas": summary["admissoes_redundantes"],
        "posicoes_de_ancora_distintas": summary["ancoras_distintas"],
        "taxonomia": summary["taxonomia"],
        "trabalho": {k: v for k, v in sorted(summary["eventos"].items()) if k != "frames"},
    }


def ratio(a: float, b: float) -> str:
    if not b:
        return "n/d"
    return f"{a / b:.2f}×"


def main() -> int:
    parser = argparse.ArgumentParser(prog="hitch-compare.py",
        description="Compara duas corridas medidas e imprime o veredito por experimento (F48-HITCH-X).")
    parser.add_argument("--a", required=True, metavar="DIR", help="corrida A (tipicamente o controle)")
    parser.add_argument("--b", required=True, metavar="DIR", help="corrida B (o outro lado)")
    parser.add_argument("--label-a", default="A")
    parser.add_argument("--label-b", default="B")
    parser.add_argument("--json", action="store_true")
    arguments = parser.parse_args()

    a, b = metrics(joined(arguments.a)), metrics(joined(arguments.b))

    if arguments.json:
        print(json.dumps({arguments.label_a: a, arguments.label_b: b}, indent=2, ensure_ascii=False))
        return 0

    print(f"{'':26s} {arguments.label_a:>22s} {arguments.label_b:>22s} {'B/A':>8s}")
    for key, label in (("quadros", "quadros"), ("fora_do_orcamento", "fora do orçamento"),
                       ("severe", "quadros severos"), ("pior_ms", "pior intervalo (ms)"),
                       ("segundos_com_severe", "segundos com severo"), ("janelas", "janelas medidas"),
                       ("advance", "observações do app (advance)"), ("advance_forward", "delas, para frente"),
                       ("admissões", "admissões"), ("admissões_redundantes_marcadas", "marcadas `redundant=1`"),
                       ("posicoes_de_ancora_distintas", "âncoras distintas")):
        print(f"{label:26s} {a[key]:>22} {b[key]:>22} {ratio(b[key], a[key]):>8s}")

    print("\nnormalizado por deslocamento (posições de âncora distintas):")
    for key, label in (("severe", "severos por âncora"), ("fora_do_orcamento", "fora do orçamento por âncora"),
                       ("quadros", "quadros por âncora")):
        av = a[key] / a["posicoes_de_ancora_distintas"] if a["posicoes_de_ancora_distintas"] else float("nan")
        bv = b[key] / b["posicoes_de_ancora_distintas"] if b["posicoes_de_ancora_distintas"] else float("nan")
        print(f"  {label:34s} {av:>10.2f} {bv:>10.2f} {ratio(bv, av):>8s}")

    print("\nseveros por observação do app (o que H3 decide):")
    for name, m in ((arguments.label_a, a), (arguments.label_b, b)):
        per = m["severe"] / m["advance"] if m["advance"] else float("nan")
        print(f"  {name:26s} severos/observação = {per:.4f}  ({m['severe']} severos / {m['advance']} observações)")

    print("\ntaxonomia das admissões (o que H4a decide):")
    for name, m in ((arguments.label_a, a), (arguments.label_b, b)):
        t = m["taxonomia"]
        total = sum(t.values()) or 1
        print(f"  {name:26s} idênticas={t['idêntica']} ({100*t['idêntica']/total:.0f}%)  "
              f"só ordem={t['só ordem']}  só âncora={t['só âncora']}  conteúdo={t['conteúdo']}  "
              f"primeira={t['primeira']}")

    print("\ntrabalho de fundo por evento (a continuidade que não pode mudar):")
    keys = sorted(set(a["trabalho"]) | set(b["trabalho"]))
    for key in keys:
        print(f"  {key:28s} {a['trabalho'].get(key, 0):>10} {b['trabalho'].get(key, 0):>10}")

    print("\nâncoras distintas por corrida (o leitor andou?):")
    print(f"  {arguments.label_a}: {a['posicoes_de_ancora_distintas']} distintas | "
          f"{arguments.label_b}: {b['posicoes_de_ancora_distintas']} distintas")
    if min(a["posicoes_de_ancora_distintas"], b["posicoes_de_ancora_distintas"]) == 0:
        print("  REFUTAÇÃO: uma das corridas não moveu o leitor — a comparação de quadros não vale como ganho.")

    print("\nleitura do veredito:")
    print("  * H3: se `severos por observação do app` for ~igual nos dois gestos, o custo acompanha o APP; se a")
    print("    razão B/A dos severos seguir a razão dos avanços sem seguir os severos/observação, é o HARNESS.")
    print("  * H4a: o ganho só conta se `admissões` e `âncoras distintas` ficarem ~iguais entre as duas corridas;")
    print("    `marcadas redundant=1` diz quantas publicações o ramo pulou.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
