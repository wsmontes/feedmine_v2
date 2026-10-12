#!/usr/bin/env python3
"""Variante de transporte do corpus congelado — substituição determinística e reversível.

Por que existe (decisão do arquiteto, 2026-10-11): o corpus congelado atende `http://127.0.0.1:8757`, e num aparelho
físico esse endereço é o loopback *do aparelho* — inalcançável, seja para a coluna de transporte, seja para as URLs
absolutas de mídia e artigo que moram **dentro** dos documentos servidos. Medido: 2.305 linhas de transporte, uma
chave de metadado e 2.309 arquivos (todos os `corpus/feeds/*` mais os três índices) carregam o endereço.

O que este script faz: reescreve **todas** as referências de transporte do corpus congelado para um endereço
alcançável, por uma transformação determinística, e grava o resultado com manifesto próprio — para ser executada
**antes** da corrida e verificada por ela.

A prova de preservação **não** é "os digests coincidem": eles não coincidem, porque os documentos contêm o endereço.
A prova é a **reversibilidade** — desfazer a substituição e comparar byte a byte com o congelado. Qualquer divergência
que não seja o token de transporte aborta o script. É essa invariante que sustenta dizer "o corpus foi preservado".

Uso:
    python3 bench/transport_variant.py --host 192.168.1.76:8757                  # gera bench/device/
    python3 bench/transport_variant.py --host 192.168.1.76:8757 --out DIR        # outro destino
    python3 bench/transport_variant.py --host 192.168.1.76:8757 --verify-only    # só re-verifica o que existe

Saída: o diretório da variante (com `manifest.json` + `MANIFEST.sha256` no mesmo formato do congelado), e no stdout os
números por superfície e o resultado da prova de reversibilidade.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sqlite3
import sys
from pathlib import Path

BENCH_DIR = Path(__file__).resolve().parent
CORPUS_DIR = BENCH_DIR / "corpus"
FROZEN_MANIFEST = BENCH_DIR / "manifest.json"
SCHEMA = "feedmine-bench-transport-variant/1"

# O token que identifica transporte, não conteúdo. Duas formas, porque as duas aparecem no corpus.
SOURCE_BASE_URL = "http://127.0.0.1:8757"
SOURCE_TOKEN = "127.0.0.1:8757"

# Só arquivos de texto são substituídos byte a byte. `catalog.sqlite` é reescrito por SQL (um patch de bytes corromperia
# páginas) e `media.pack` é binário — este script **falha** se o token aparecer lá, em vez de fingir que tratou.
TEXT_SUFFIXES = {".xml", ".json", ".html", ".atom", ".rss", ".txt", ".jsonl", ".csv", ".md"}
BY_SQL = {"catalog.sqlite"}
NEVER_TOUCH = {"media.pack"}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_frozen_manifest() -> dict:
    manifest = json.loads(FROZEN_MANIFEST.read_text(encoding="utf-8"))
    if not manifest.get("frozen"):
        raise SystemExit("manifest.json não está congelado (frozen != true) — recusando transformar")
    dirty = []
    for entry in manifest["artifacts"]:
        path = BENCH_DIR / entry["path"]
        if not path.exists():
            dirty.append(f"ausente: {entry['path']}")
        elif sha256_file(path) != entry["sha256"]:
            dirty.append(f"divergente: {entry['path']}")
    if dirty:
        raise SystemExit("corpus congelado divergiu do manifesto:\n  " + "\n  ".join(dirty))
    return manifest


def substitute_bytes(data: bytes, token: str, replacement: str) -> tuple[bytes, int]:
    needle = token.encode("utf-8")
    if needle not in data:
        return data, 0
    return data.replace(needle, replacement.encode("utf-8")), data.count(needle)


def substitute_sql(db_path: Path, source: str, target: str) -> dict:
    """Reescreve toda coluna TEXT das tabelas reais. Devolve contagem por (tabela, coluna)."""
    counts: dict[str, int] = {}
    db = sqlite3.connect(db_path)
    try:
        tables = [row[0] for row in db.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND sql NOT LIKE '%VIRTUAL%' ORDER BY name")]
        for table in tables:
            for column in [row[1] for row in db.execute(f"PRAGMA table_info({table})")]:
                before = db.execute(
                    f"SELECT COUNT(*) FROM {table} WHERE typeof({column}) = 'text' AND {column} LIKE ?",
                    (f"%{source}%",)).fetchone()[0]
                if not before:
                    continue
                db.execute(f"UPDATE {table} SET {column} = REPLACE({column}, ?, ?) WHERE typeof({column}) = 'text'",
                           (source, target))
                counts[f"{table}.{column}"] = before
        db.commit()
    finally:
        db.close()
    return counts


def vacuum_database(db_path: Path) -> int:
    """Reescreve o arquivo para que nenhum byte de página liberada carregue o token antigo.

    Uma substituição que **alonga** o valor realoca a linha e deixa o texto anterior em página livre — nunca lido por
    consulta alguma, mas presente no arquivo. `VACUUM` reescreve o banco do zero. Devolve o tamanho final em bytes.
    """
    db = sqlite3.connect(db_path)
    try:
        db.execute("VACUUM")
    finally:
        db.close()
    return db_path.stat().st_size


def scan_sql_token(db_path: Path, token: str) -> dict:
    """O que conta de verdade no banco: quantas **células** ainda carregam o token. Bytes de página livre não entram."""
    counts: dict[str, int] = {}
    db = sqlite3.connect(db_path)
    try:
        tables = [row[0] for row in db.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND sql NOT LIKE '%VIRTUAL%' ORDER BY name")]
        for table in tables:
            for column in [row[1] for row in db.execute(f"PRAGMA table_info({table})")]:
                found = db.execute(
                    f"SELECT COUNT(*) FROM {table} WHERE typeof({column}) = 'text' AND {column} LIKE ?",
                    (f"%{token}%",)).fetchone()[0]
                if found:
                    counts[f"{table}.{column}"] = found
    finally:
        db.close()
    return counts


def scan_token(root: Path, token: str) -> dict:
    """Onde o token ainda aparece — a medida de cobertura, e o que sobra é dito em voz alta."""
    remaining: dict[str, int] = {}
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if path.name in {"manifest.json", "MANIFEST.sha256"}:
            continue
        if path.name in BY_SQL | NEVER_TOUCH or path.suffix in {".sqlite", ".pack"}:
            continue
        data = path.read_bytes()
        if token.encode() in data:
            remaining[str(path.relative_to(root))] = data.count(token.encode())
    return remaining


def substitute_tree(source_dir: Path, target_dir: Path, source: str, target: str) -> dict:
    """Copia e substitui. O sqlite fica por conta do SQL; o pack binário é conferido, não tocado."""
    file_counts: dict[str, int] = {}
    copied = 0
    for path in sorted(source_dir.rglob("*")):
        relative = path.relative_to(source_dir)
        destination = target_dir / relative
        if path.is_dir():
            destination.mkdir(parents=True, exist_ok=True)
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        if path.name in NEVER_TOUCH:
            if source.encode() in path.read_bytes():
                raise SystemExit(f"o token aparece em {relative}, que é binário — a substituição não o cobre")
            shutil.copy2(path, destination)
            continue
        if path.name in BY_SQL or path.suffix not in TEXT_SUFFIXES:
            shutil.copy2(path, destination)
            copied += 1
            continue
        data, count = substitute_bytes(path.read_bytes(), source, target)
        destination.write_bytes(data)
        copied += 1
        if count:
            file_counts[str(relative)] = count
    return {"files": file_counts, "copied": copied}


def probe_reversibility(frozen_dir: Path, variant_dir: Path, source: str, target: str) -> dict:
    """Desfaz a substituição na variante e compara com o congelado. Byte a byte nos arquivos, célula a célula no banco."""
    mismatches: list[str] = []
    compared = 0
    for path in sorted(frozen_dir.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(frozen_dir)
        variant_path = variant_dir / relative
        if not variant_path.exists():
            mismatches.append(f"ausente na variante: {relative}")
            continue
        if path.name in BY_SQL:
            continue
        compared += 1
        restored, _ = substitute_bytes(variant_path.read_bytes(), target, source)
        if restored != path.read_bytes():
            mismatches.append(f"divergiu além do transporte: {relative}")

    # o banco: toda célula que carregava o transporte deve voltar ao valor congelado
    frozen_cells, variant_cells = [], []
    for db_path, bucket in ((frozen_dir / "catalog.sqlite", frozen_cells),
                            (variant_dir / "catalog.sqlite", variant_cells)):
        db = sqlite3.connect(db_path)
        try:
            tables = [row[0] for row in db.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND sql NOT LIKE '%VIRTUAL%' ORDER BY name")]
            for table in tables:
                for column in [row[1] for row in db.execute(f"PRAGMA table_info({table})")]:
                    try:
                        rows = db.execute(
                            f"SELECT rowid, {column} FROM {table} WHERE typeof({column}) = 'text' AND {column} LIKE ?",
                            (f"%{target if bucket is variant_cells else source}%",)).fetchall()
                    except sqlite3.OperationalError:
                        # tabelas-sombra do FTS5 não têm rowid: conteúdo derivado, sem linha identificável a comparar
                        continue
                    for rowid, value in rows:
                        bucket.append(f"{table}#{rowid}.{column}={value}")
        finally:
            db.close()
    compared += len(frozen_cells)
    if len(frozen_cells) != len(variant_cells):
        mismatches.append(f"banco: {len(frozen_cells)} células congeladas contra {len(variant_cells)} na variante")
    else:
        for left, right in zip(sorted(frozen_cells), sorted(variant_cells)):
            if left != right.replace(target, source):
                mismatches.append(f"banco divergiu: {left[:120]}")
                break
    return {"compared": compared, "mismatches": mismatches}


def main() -> None:
    parser = argparse.ArgumentParser(description="Variante de transporte do corpus congelado.")
    parser.add_argument("--host", required=True, help="host:porta alcançável (ex.: 192.168.1.76:8757)")
    parser.add_argument("--out", type=Path, default=BENCH_DIR / "device")
    parser.add_argument("--verify-only", action="store_true", help="não regera; re-verifica o destino existente")
    arguments = parser.parse_args()

    target_base_url = f"http://{arguments.host}"
    corpus_out = arguments.out / "corpus"
    manifest = load_frozen_manifest()
    print(f"congelado: {FROZEN_MANIFEST}")
    print(f"  transporte de origem : {manifest['transport_base_url']}")
    print(f"  transporte de destino: {target_base_url}")
    print(f"  fontes: {manifest['totals']['sources']} | itens: {manifest['totals']['items']}")

    if not arguments.verify_only:
        if corpus_out.exists():
            shutil.rmtree(corpus_out)
        file_counts = substitute_tree(CORPUS_DIR, corpus_out, SOURCE_TOKEN, arguments.host)
        # No banco, as duas formas: a URL completa primeiro (a forma curta está dentro dela) e depois a curta, que
        # pegaria uma célula que guardasse só host:porta. O scan de arquivos não cobre o sqlite, então isto é a
        # cobertura do banco — não uma redundância.
        sql_counts = substitute_sql(corpus_out / "catalog.sqlite", SOURCE_BASE_URL, target_base_url)
        for key, value in substitute_sql(corpus_out / "catalog.sqlite", SOURCE_TOKEN, arguments.host).items():
            sql_counts[key] = sql_counts.get(key, 0) + value
        # Alongar o valor realoca a linha e deixa o texto antigo em página livre: nunca lido por consulta, mas presente
        # no arquivo. `VACUUM` reescreve o banco do zero para que "todas as referências" seja verdade também em bytes.
        vacuum_database(corpus_out / "catalog.sqlite")
        sql_remaining = scan_sql_token(corpus_out / "catalog.sqlite", SOURCE_TOKEN)
        if sql_remaining:
            raise SystemExit("sobrou loopback em células do banco: " + json.dumps(sql_remaining, indent=2))
        remaining = scan_token(corpus_out, SOURCE_TOKEN)
        if remaining:
            raise SystemExit("sobrou loopback depois da substituição: " + json.dumps(remaining, indent=2)[:400])

        probe = probe_reversibility(CORPUS_DIR, corpus_out, SOURCE_BASE_URL, target_base_url)
        if probe["mismatches"]:
            raise SystemExit("prova de reversibilidade falhou:\n  " + "\n  ".join(probe["mismatches"]))

        artifacts = []
        for path in sorted(corpus_out.rglob("*")):
            if path.is_file():
                artifacts.append({
                    "path": str(path.relative_to(arguments.out)).replace(os.sep, "/"),
                    "sha256": sha256_file(path),
                    "bytes": path.stat().st_size,
                })
        # O manifesto da variante lista só o que vive DENTRO do diretório da variante: `shasum -c` roda com
        # `cd bench/device`, e um caminho de fora falha na verificação (foi assim que o runner recusou a primeira
        # corrida — o próprio instrumento pegou o erro). O transform entra no contexto congelado, com o runner e o
        # oráculo, que é onde os arquivos de fora pertencem.
        frozen_context = {
            "transform": {"path": "transport_variant.py", "sha256": sha256_file(BENCH_DIR / "transport_variant.py")},
            "runner": {"path": "run.sh", "sha256": sha256_file(BENCH_DIR / "run.sh")},
            "oracle": {"path": "oracle.py", "sha256": sha256_file(BENCH_DIR / "oracle.py")},
            "expansion": {"path": "expand.py", "sha256": sha256_file(BENCH_DIR / "expand.py")},
            "oracle_inputs": {},
        }
        for name in ("items.json", "criteria.json", "profiles.json"):
            variant_input = corpus_out / name
            frozen_context["oracle_inputs"][name] = {
                "sha256": sha256_file(variant_input),
                "source_sha256": sha256_file(CORPUS_DIR / name),
                "bytes": variant_input.stat().st_size,
            }
        feed_digest = hashlib.sha256("".join(sorted(
            entry["sha256"] for entry in artifacts if entry["path"].startswith("corpus/feeds/"))).encode()).hexdigest()

        variant_manifest = {
            "schema": SCHEMA,
            "frozen": True,
            "generated_by": "bench/transport_variant.py",
            "note": ("Variante de transporte do corpus congelado, para destinos que não compartilham o loopback do host "
                     "(aparelho físico). Não substitui `bench/manifest.json`: a corrida continua ancorada no corpus "
                     "congelado, e esta variante é verificada por reversibilidade contra ele."),
            "source_manifest_sha256": sha256_file(FROZEN_MANIFEST),
            "source_transport_base_url": manifest["transport_base_url"],
            "transport_base_url": target_base_url,
            "source_feed_document_digest": manifest["feed_document_digest"],
            "feed_document_digest": feed_digest,
            "substitutions": {
                "database": sql_counts,
                "database_cells": sum(sql_counts.values()),
                "files": {k: v for k, v in file_counts["files"].items()},
                "file_count": len(file_counts["files"]),
                "file_occurrences": sum(file_counts["files"].values()),
            },
            "preservation": {
                "rule": ("a substituição muda somente o token de transporte; desfazê-la reproduz o congelado byte a "
                         "byte nos arquivos e célula a célula no banco, o que cobre conteúdo editorial, atrasos, "
                         "classes de falha e identidades"),
                "media_pack_identical": sha256_file(corpus_out / "media.pack") == sha256_file(CORPUS_DIR / "media.pack"),
                "media_pack_sha256": sha256_file(corpus_out / "media.pack"),
                "reversibility_compared": probe["compared"],
                "reversibility_mismatches": 0,
            },
            "frozen_context": frozen_context,
            "reversibility": {"compared": probe["compared"], "mismatches": [], "rule":
                              "desfazer a substituição reproduz o congelado byte a byte (arquivos) e célula a célula (banco)"},
            "totals": manifest["totals"],
            "artifacts": artifacts,
        }
        (arguments.out / "manifest.json").write_text(
            json.dumps(variant_manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        (arguments.out / "MANIFEST.sha256").write_text(
            "\n".join(f"{entry['sha256']}  {entry['path']}" for entry in artifacts) + "\n", encoding="utf-8")

        print(f"\nbanco: {sum(sql_counts.values())} células em {len(sql_counts)} colunas")
        for key, value in sorted(sql_counts.items()):
            print(f"  {key}: {value}")
        print(f"arquivos substituídos: {len(file_counts['files'])} (ocorrências: {sum(file_counts['files'].values())})")
        print(f"prova de reversibilidade: {probe['compared']} comparações, 0 divergências")
        print(f"feed_document_digest: congelado {manifest['feed_document_digest'][:16]} -> variante {feed_digest[:16]}")
    else:
        if not (arguments.out / "manifest.json").exists():
            raise SystemExit(f"não há variante em {arguments.out}")
        probe = probe_reversibility(CORPUS_DIR, corpus_out, SOURCE_BASE_URL, target_base_url)
        print(f"reversibilidade: {probe['compared']} comparações, {len(probe['mismatches'])} divergências")
        if probe["mismatches"]:
            print("\n".join(probe["mismatches"][:10]))
            sys.exit(1)

    print(f"\nvariante em {arguments.out} — sirva-a com: python3 bench/serve.py --host 0.0.0.0 --corpus {corpus_out}")


if __name__ == "__main__":
    main()
