#!/usr/bin/env python3
"""instruments/journey/journey.py — medições binárias lidas do que o app registrou sobre uma jornada real.

Duas fontes, nenhuma pergunta inventada:
  * `--run bench/run/<stamp>` — a corrida do bench: o `trace.jsonl` e o `runtime.sqlite` que o contêiner
    carrega (`<run>/container/.../FeedMine/<namespace>/`), escritos pelo próprio app
    (`FeedMineApp/FeedMineApp/RunwayTrace.swift`, chamadas em `AppComposition.swift`).
  * `--journey /tmp/fm-journey-<stamp>` — a jornada de aparelho de `scripts/device-journey.sh`: o
    `console.log` (uma linha `feedmine journey …` e uma `feedmine frames=…` por segundo) mais o contêiner
    puxado (banco, traço e `Media/`).

Cada medição imprime a pergunta do leitor, o campo do traço que a responde, o veredito binário e o número cru ao
lado — o número **informa**, não decide (régua de `docs/reviews/2026-10-15-medicoes-obvias-e-constantes-magicas.md`
§1). Instrumento **independente**, com hash próprio (`instruments/journey/journey.sha256`) e fora da régua: mora em
`instruments/journey/` e não em `bench/`, porque `bench/` é a referência **congelada** (B01–B06) e uma ferramenta
nova e evolutiva ali dentro pareceria ter autoridade sobre ela. Nada de `bench/` é lido para decidir nem escrito
por este arquivo, e este instrumento não substitui nem reescreve B01–B06 — é diagnóstico auxiliar, nunca oráculo.

**Código de saída** (o que uma automação lê; a tabela está no relatório §11):

===========  ==========================================================================
``0``        toda cláusula **aplicável** foi medida e deu `PASS`
``1``        pelo menos uma cláusula deu `FAIL` (violação **observada**)
``2``        erro de **entrada ou execução** — insumo inexistente, sem artefato, SQLite ilegível,
             argumentos inválidos, injeção impossível. **Nunca** se confunde com falha de medição:
             estes caminhos não imprimem veredito de cláusula, imprimem `ERRO DE ENTRADA`
``3``        nenhum `FAIL`, mas alguma cláusula aplicável ficou `NOT_RUN` (medição **incompleta**)
===========  ==========================================================================

`0` e `3` são caminhos distintos de propósito: sem isso, automação que só olha o código leria medição
incompleta como sucesso. Um veredito `NOT_RUN` **não** basta para `3` — só o `NOT_RUN` de cláusula *aplicável*
basta. **Aplicável** aqui é uma decisão do modelo de cláusula deste instrumento, não um sinônimo de "todo
`NOT_RUN`" (a cláusula de superfície, por exemplo, é `NOT_RUN` **por contrato** em todo insumo: nenhum evento a
mede). Cada sub-fato não medido carrega um **motivo**, de vocabulário fechado:

``sem_sujeito``          o insumo não tem o que medir (sem janela atribuída, sem carta, sem avanço, sem
                         série de quadros, sem linha durável). Cláusula **não aplicável**.
``nao_implementado``     nenhuma fonte de evidência existe, por desenho (o pixel desenhado de M5; as cláusulas
                         da lista "sem evidência hoje"). Cláusula **não aplicável**.
``evidencia_incompleta`` o sujeito existe, mas o traço anuncia perdas (`trace_truncated`) ou tem linha
                         ilegível: zero violação não prova nada. **Lacuna** → `3`.
``nao_resolvido``        o sujeito existe, mas uma referência não se resolve na ordem do leitor. **Lacuna** → `3`.
``nao_identificado``     o sujeito existe e o registro é ambíguo (0 ou ≥2 linhas duráveis para a edição
                         medida). **Lacuna** → `3`.
``nao_comparavel``       o sujeito existe, mas os dois registros não são do mesmo instante (linha durável mais
                         nova que o fim do traço, ou falta metade do par). **Lacuna** → `3`.

Os dois primeiros motivos deixam a cláusula **fora do escopo do insumo** e não forçam `3`; os quatro últimos são
**lacuna de medição** e forçam. O veredito agregado impresso continua sendo o do contrato 3 (`FAIL` > `NOT_RUN` >
`PASS`), então M5 imprime `NOT_RUN` pela metade visual mesmo em `0` — o código de saída diz que *aquela* metade
não é medição deste insumo, e a linha ``cláusula:`` ao lado diz qual dos dois casos é.

Três contratos de evidência, porque sem eles uma cláusula mente:

1. **Sem sujeito não há veredito.** Cláusula que não tem o que medir é `NOT_RUN` com a razão escrita, nunca
   `PASS` (a regra de `bench/oracle.py:357-378`).
2. **Ausência sobre evidência incompleta não é prova.** Se o próprio traço anuncia eventos perdidos
   (`trace_truncated`) ou há linha ilegível, uma cláusula que **contou zero** violações não pode concluir nada:
   `NOT_RUN`. Violação **observada** continua `FAIL` — o que se perdeu foi a chance de ver mais, não a
   legitimidade do que se viu.
3. **Fato obrigatório não observado contamina a afirmação composta.** Um veredito agregado com qualquer
   sub-fato não medido é `NOT_RUN` (`[PASS, NOT_RUN]` → `NOT_RUN`), inclusive porque é assim que
   `bench/oracle.py:624-631` decide.

Onde o traço não tem a informação, esta ferramenta diz `NOT_RUN` — não deriva o estado de outro campo parecido.
O caso concreto que já custou um falso vermelho: `preparation=done` na linha de jornada significa apenas que o
relé não recebeu nada (`AppComposition.swift:2363-2366`), **não** que a superfície declarou fim de feed
(`work == .endOfContent`); por isso não existe cláusula de "vazio declarado" aqui.

Uso::

    python3 instruments/journey/journey.py --help
    python3 instruments/journey/journey.py --selftest          # controles positivos dos quatro códigos de saída
    python3 instruments/journey/journey.py --run bench/run/20261014T173601Z
    python3 instruments/journey/journey.py --journey /tmp/fm-journey-20261016T075109Z --json
    python3 instruments/journey/journey.py --journey /tmp/fm-journey-20261016T075109Z --series
    python3 instruments/journey/journey.py --run bench/run/20261014T173601Z --inject m1 --out /tmp/inj-m1

`--inject` aplica a violação numa **cópia** do insumo (nunca no original), imprime o diff e mede a cópia: é o
controle positivo de cada cláusula.

`--selftest` monta insumos sintéticos num diretório temporário e roda **o próprio processo** uma vez por caminho
de saída, conferindo o código observado e a linha que o justifica: `0` (tudo aplicável medido e `PASS`), `0` de
novo com cláusulas **fora de escopo** (prova que "não aplicável" não vira `3`), `1` (uma cláusula `FAIL`, via
`--inject m2`), `2` (insumo inexistente, insumo sem artefato, SQLite ilegível, argumentos inválidos) e `3`
(cláusula aplicável com lacuna). Ele sai `0` se os controles valem, `1` se algum controle quebrou e `2` se não
soube montar o insumo — contrato próprio do modo, separado do contrato de medição acima. `--fixtures DIR` monta
os mesmos insumos num diretório que fica, para um revisor rodar cada caminho com o comando da linha de comando.

Leitura do banco: `runtime.sqlite` (com `-wal` e `-shm`) é copiado para um diretório temporário e aberto em
`mode=ro`. Ler no lugar cria `-shm`/`-wal` na árvore de quem lê (medido: suja o `identity.txt` de uma corrida em
andamento), e ler com `immutable=1` ignora o WAL — o que faz a posição durável do app parecer mais velha do que é
(medido: 43 s em `bench/run/20261014T214403Z`).
"""
from __future__ import annotations

import argparse
import atexit
import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

# `PresentationCardLayout` — Sources/FeedMineRuntime/PresentationCard.swift:11-15. `textOnly` é a carta sem slot.
SLOT_LAYOUTS = ("hero", "thumbnail")
TEXT_LAYOUT = "textOnly"
# A chave local do asset é `sha256:<digest>` e o arquivo mora em `Media/sha256/<digest>`
# (Sources/FeedMineMedia/AssetStore.swift:37-45,78-79).
MEDIA_KEY_PREFIX = "sha256:"

# A ordem do leitor **dentro de uma edição**: o ordinal do segmento, depois o ordinal da carta. Uma edição é um
# feed; cartas de edições diferentes não são vizinhas, e o mesmo ordinal existe em edições distintas
# (`feed_segments.edition_id` é o que separa as duas).
READER_ORDER = """
SELECT LOWER(c.id) AS id, c.source_id, c.primary_action_reference, c.media_key, c.render_layout,
       LOWER(s.edition_id) AS edition
FROM published_cards c
LEFT JOIN feed_segments s ON s.id = c.segment_id
ORDER BY LOWER(s.edition_id), COALESCE(s.ordinal, 2147483647), c.ordinal, c.segment_id
"""

JOURNEY_RE = re.compile(r"feedmine journey (.+)$")
FRAMES_RE = re.compile(r"feedmine frames=(\d+) late=(\d+) bad=(\d+) severe=(\d+) worst_ms=([0-9.]+)")

_TEMPORARY: list[str] = []


def _cleanup() -> None:
    for path in _TEMPORARY:
        shutil.rmtree(path, ignore_errors=True)


atexit.register(_cleanup)


def sha256_file(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def iso(moment: float | None) -> str:
    if moment is None:
        return "—"
    return datetime.fromtimestamp(moment, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def compact(value: dict) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def read_jsonl(path: str) -> tuple[list[str], list[dict], int]:
    """Linhas cruas, eventos e **quantas linhas não foram entendidas** — uma linha ilegível é evidência a menos."""
    lines: list[str] = []
    events: list[dict] = []
    invalid = 0
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            lines.append(line)
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                invalid += 1
    return lines, events, invalid


def as_int(value) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def write_file(path: str, content: str) -> None:
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)


class InputError(Exception):
    """Entrada ou execução — **nunca** uma medição: vira código de saída 2, com a razão impressa."""


# Motivo de cada sub-fato **não medido**. Os dois primeiros deixam a cláusula fora do escopo do insumo (não
# aplicável); os quatro últimos são lacuna de medição e forçam o código de saída 3 (tabela no docstring).
SEM_SUJEITO = "sem_sujeito"
NAO_IMPLEMENTADO = "nao_implementado"
EVIDENCIA_INCOMPLETA = "evidencia_incompleta"
NAO_RESOLVIDO = "nao_resolvido"
NAO_IDENTIFICADO = "nao_identificado"
NAO_COMPARAVEL = "nao_comparavel"
REASONS = (SEM_SUJEITO, NAO_IMPLEMENTADO, EVIDENCIA_INCOMPLETA, NAO_RESOLVIDO, NAO_IDENTIFICADO, NAO_COMPARAVEL)
GAP_REASONS = (EVIDENCIA_INCOMPLETA, NAO_RESOLVIDO, NAO_IDENTIFICADO, NAO_COMPARAVEL)

# Códigos de saída: a tabela que a automação lê.
EXIT_OK = 0
EXIT_FAIL = 1
EXIT_INPUT = 2
EXIT_INCOMPLETE = 3


class Insumo:
    """Um diretório de corrida ou de jornada. O que não está lá é `None`, e as cláusulas dizem `NOT_RUN`."""

    def __init__(self, path: str, kind: str) -> None:
        self.path = os.path.abspath(path)
        self.kind = kind  # "corrida" | "jornada"
        self.trace: str | None = None
        self.database: str | None = None
        self.console: str | None = None
        self.media_dir: str | None = None
        self.raw_lines: list[str] = []
        self.events: list[dict] = []
        self.invalid_lines = 0
        self.cards: list[dict] = []
        self.by_edition: dict[str, list[dict]] = {}
        self.index_by_edition: dict[str, dict[str, int]] = {}
        self.durable: dict = {"context": [], "session": []}
        self.journey: list[dict] = []
        self.frame_lines: list[dict] = []
        self._discover()
        self._load()

    # -- descoberta e leitura ---------------------------------------------------------------------------------

    def _candidates(self, name: str) -> list[str]:
        found = []
        for root, dirs, files in os.walk(self.path):
            dirs.sort()
            if name in files:
                found.append(os.path.join(root, name))
        return sorted(found)

    def _discover(self) -> None:
        if os.path.isfile(self.path):
            self.path = os.path.dirname(self.path)
        databases = self._candidates("runtime.sqlite")
        for database in databases:
            neighbour = os.path.join(os.path.dirname(database), "trace.jsonl")
            if os.path.exists(neighbour):
                self.database, self.trace = database, neighbour
                break
        if self.database is None and databases:
            self.database = databases[0]
        if self.trace is None:
            traces = self._candidates("trace.jsonl")
            self.trace = traces[0] if traces else None
        console = os.path.join(self.path, "console.log")
        if os.path.exists(console):
            self.console = console
        if self.database:
            media = os.path.join(os.path.dirname(self.database), "Media", "sha256")
            if os.path.isdir(media):
                self.media_dir = media
        if self.trace is None and self.database is None and self.console is None:
            raise InputError(f"{self.path}: nenhum artefato — sem `trace.jsonl`, sem `runtime.sqlite` e sem "
                "`console.log`. Insumo ausente ou vazio: erro de entrada, não medição vazia (código 2, não 0)")

    def _load(self) -> None:
        if self.trace:
            try:
                self.raw_lines, self.events, self.invalid_lines = read_jsonl(self.trace)
            except OSError as error:
                raise InputError(f"traço ilegível: {self.trace} ({error})") from error
        if self.database:
            self.cards, self.durable = self._read_database(self.database)
            for card in self.cards:
                self.by_edition.setdefault(card["edition"] or "", []).append(card)
            self.index_by_edition = {edition: {card["id"]: position for position, card in enumerate(rows)}
                for edition, rows in self.by_edition.items()}
        if self.console:
            try:
                with open(self.console, encoding="utf-8", errors="replace") as handle:
                    for line in handle:
                        match = JOURNEY_RE.search(line)
                        if match:
                            self.journey.append(dict(p.split("=", 1) for p in match.group(1).split() if "=" in p))
                            continue
                        match = FRAMES_RE.search(line)
                        if match:
                            self.frame_lines.append({"frames": int(match.group(1)), "late": int(match.group(2)),
                                "bad": int(match.group(3)), "severe": int(match.group(4)),
                                "worst_ms": float(match.group(5))})
            except OSError as error:
                raise InputError(f"console ilegível: {self.console} ({error})") from error

    @staticmethod
    def _read_database(path: str) -> tuple[list[dict], dict]:
        """Cópia (com `-wal`/`-shm`) aberta em `mode=ro`. Banco que não abre ou não tem o esquema do leitor é
        **erro de entrada** (código 2): sem ele toda cláusula ficaria `NOT_RUN` e a automação leria `0`."""
        workspace = tempfile.mkdtemp(prefix="journey-db-")
        _TEMPORARY.append(workspace)
        copy = os.path.join(workspace, "runtime.sqlite")
        for suffix in ("", "-wal", "-shm"):
            if os.path.exists(path + suffix):
                shutil.copy2(path + suffix, copy + suffix)
        try:
            connection = sqlite3.connect(f"file:{copy}?mode=ro", uri=True)
        except sqlite3.Error as error:
            raise InputError(f"SQLite não abre: {path} ({error})") from error
        connection.row_factory = sqlite3.Row
        durable: dict = {"context": [], "session": []}
        try:
            try:
                cards = [dict(row) for row in connection.execute(READER_ORDER).fetchall()]
            except sqlite3.DatabaseError as error:
                raise InputError(f"SQLite ilegível ou sem o esquema do leitor "
                    f"(`published_cards`/`feed_segments`): {path} ({error})") from error
            for table, key in (("context_checkpoints", "context"), ("session_checkpoint", "session")):
                try:
                    durable[key] = [dict(row) for row in connection.execute(f"SELECT * FROM {table}").fetchall()]
                except sqlite3.OperationalError as error:
                    # Tabela ausente é esquema antigo, não banco quebrado: a cláusula que a lê fica sem sujeito.
                    if "no such table" not in str(error).lower():
                        raise InputError(f"SQLite ilegível em `{table}`: {path} ({error})") from error
                except sqlite3.DatabaseError as error:
                    raise InputError(f"SQLite ilegível em `{table}`: {path} ({error})") from error
        finally:
            connection.close()
        return cards, durable

    # -- fatos derivados --------------------------------------------------------------------------------------

    def events_of(self, name: str) -> list[dict]:
        return [event for event in self.events if event.get("event") == name]

    def fields(self, event: dict) -> dict:
        return event.get("fields") or {}

    def position(self, card_id: str | None, edition: str | None) -> int | None:
        """A posição da carta na ordem do leitor **da edição dela**; `None` = não resolvida ali."""
        if not card_id or not edition:
            return None
        return self.index_by_edition.get(edition, {}).get(card_id.lower())

    def losses(self) -> dict | None:
        notices = [self.fields(event) for event in self.events_of("trace_truncated")]
        if not notices:
            return None
        last = notices[-1]
        return {"anúncios": len(notices), "teto": as_int(last.get("ceiling")),
            "escrito": as_int(last.get("written")), "perdidos_pelo_teto": as_int(last.get("dropped_by_ceiling")),
            "perdidos_pela_escrita": as_int(last.get("dropped_by_write")),
            "perdidos_pela_codificação": as_int(last.get("dropped_by_encoding"))}

    def complete(self) -> bool:
        """O traço é evidência completa? Sem perda anunciada e sem linha ilegível, sim."""
        losses = self.losses() or {}
        dropped = sum(value or 0 for key, value in losses.items() if key.startswith("perdidos_"))
        return dropped == 0 and self.invalid_lines == 0

    def absence(self, observed: int) -> bool | None:
        """Contrato 2: zero violação só é prova sobre evidência completa."""
        if observed:
            return False
        return True if self.complete() else None

    def installs(self) -> list[dict]:
        """A série de instalações, cada uma com a posição da cabeça, da cauda e da âncora **na sua edição**."""
        series = []
        for event in self.events_of("admitted"):
            fields = self.fields(event)
            edition = (fields.get("edition") or "").lower()
            series.append({"at": event.get("at"), "mono": event.get("mono"),
                "generation": (edition, fields.get("sequence")),
                "edition": edition, "cards": as_int(fields.get("cards")),
                "head": self.position(fields.get("head"), edition),
                "tail": self.position(fields.get("tail"), edition),
                "anchor": self.position(fields.get("anchor"), edition)})
        return series

    def media_files(self) -> set[str]:
        if not self.media_dir or not os.path.isdir(self.media_dir):
            return set()
        return set(os.listdir(self.media_dir))

    def provenance(self) -> dict:
        first = self.events[0] if self.events else None
        last = self.events[-1] if self.events else None
        editions = {(self.fields(event).get("edition") or "").lower() for event in self.events_of("admitted")}
        raw = {}
        if self.database:
            for suffix in ("", "-wal", "-shm"):
                path = self.database + suffix
                if os.path.exists(path):
                    raw[f"runtime.sqlite{suffix}"] = {"sha256": sha256_file(path),
                        "bytes": os.path.getsize(path)}
        return {"insumo": self.path, "tipo": "corrida do bench" if self.kind == "corrida" else "jornada de aparelho",
            "traco": self.trace,
            "traco_sha256": sha256_file(self.trace) if self.trace else None,
            "traco_linhas": len(self.raw_lines), "traco_ilegiveis": self.invalid_lines,
            "traco_janela": (iso(first.get("at")) if first else None, iso(last.get("at")) if last else None),
            "traco_perda": self.losses(), "traco_completo": self.complete() if self.trace else None,
            "banco": self.database, "banco_bruto": raw,
            "console": self.console, "console_sha256": sha256_file(self.console) if self.console else None,
            "console_linhas": len(self.journey) + len(self.frame_lines), "midia": self.media_dir,
            "cartas": len(self.cards), "edições": len({e for e in editions if e})}


# -- medições ---------------------------------------------------------------------------------------------------


def fact(name: str, observed, expected: str, passed, motivo: str | None = None) -> dict:
    """Um sub-fato: `pass` medido (`True`/`False`) ou `None` **com motivo**.

    O motivo é obrigatório quando não houve medição — é ele que separa "esta cláusula não tem sujeito neste
    insumo" de "esta cláusula é aplicável e ficou sem medição", e é o que o código de saída lê.
    """
    if (passed is None) == (motivo is None):
        raise ValueError(f"fato {name}: `pass=None` exige motivo, e `pass` medido não aceita motivo")
    if motivo is not None and motivo not in REASONS:
        raise ValueError(f"fato {name}: motivo fora do vocabulário: {motivo}")
    return {"fato": name, "observado": observed, "esperado": expected, "pass": passed, "motivo": motivo}


def _gap(passed, motivo: str):
    """`motivo` só vale quando não houve medição; medido, o motivo tem de sair de cena (o `fact` recusa os dois)."""
    return motivo if passed is None else None


def verdict_of(facts: list[dict]) -> str:
    """`bench/oracle.py:624-631`: FAIL manda; **qualquer** sub-fato não medido é NOT_RUN; senão PASS."""
    if any(item["pass"] is False for item in facts):
        return "FAIL"
    if any(item["pass"] is None for item in facts):
        return "NOT_RUN"
    return "PASS"


def clause_state(result: dict) -> dict:
    """O que o código de saída lê de uma cláusula, separado do veredito que o leitor lê.

    Aplicável = a cláusula tem sujeito neste insumo: ou algum sub-fato foi medido, ou a lacuna é de medição.
    Cláusula sem sujeito (ou cuja única metade não medida é `nao_implementado`) **não** é lacuna: é escopo.
    """
    gaps, outside = [], []
    for item in result["fatos"]:
        if item["pass"] is not None:
            continue
        (gaps if item["motivo"] in GAP_REASONS else outside).append(item["motivo"])
    return {"aplicavel": bool(gaps) or any(item["pass"] is not None for item in result["fatos"]),
        "lacunas": gaps, "fora_de_escopo": outside}


def exit_code_of(results: list[dict]) -> int:
    """A tabela: `FAIL` manda; senão lacuna de medição em cláusula aplicável; senão `0`."""
    if any(result["veredito"] == "FAIL" for result in results):
        return EXIT_FAIL
    return EXIT_INCOMPLETE if any(clause_state(result)["lacunas"] for result in results) else EXIT_OK


def exit_reason(results: list[dict]) -> str:
    """A frase que acompanha o código — por que este insumo sai com ele."""
    failures = [result["id"] for result in results if result["veredito"] == "FAIL"]
    if failures:
        return f"cláusula FAIL: {', '.join(failures)}"
    gaps = [f"{result['id']} ({', '.join(sorted(set(clause_state(result)['lacunas'])))})"
        for result in results if clause_state(result)["lacunas"]]
    if gaps:
        return f"sem FAIL, mas cláusula aplicável não medida: {'; '.join(gaps)}"
    outside = [f"{result['id']} ({', '.join(sorted(set(clause_state(result)['fora_de_escopo'])))})"
        for result in results if clause_state(result)["fora_de_escopo"]]
    head = "todas as cláusulas aplicáveis medidas e PASS"
    return f"{head}; fora de escopo neste insumo: {'; '.join(outside)}" if outside else head


def measurement(key: str, title: str, question: str, read_from: str, facts: list[dict], numbers: dict,
    notes: list[str] | None = None) -> dict:
    result = {"id": key, "titulo": title, "pergunta": question, "fato_lido": read_from, "fatos": facts,
        "numeros": numbers, "notas": notes or [], "veredito": verdict_of(facts)}
    result.update(clause_state(result))
    return result


def measure_m1(ins: Insumo) -> dict:
    """M1 — abrir: a superfície desenhou vazio e depois conteúdo **na mesma geração**?

    A geração de cada `window` é a do último `admitted` gravado antes dela (o `window` não carrega edição nem
    sequência — `AppComposition.swift:1356-1360`; o `admitted` carrega, `:2346-2350`). A janela vazia que cai
    entre a última instalação de uma sessão e a primeira da seguinte pertence, por essa regra, à sessão que saiu:
    a troca de contexto não vira violação, e o número aparece em `vazias_no_fim_da_geração`.
    """
    generation = None
    per_generation: dict[tuple, list[int]] = {}
    empty_attributed = empty_unattributed = 0
    for event in ins.events:
        if event.get("event") == "admitted":
            fields = ins.fields(event)
            generation = (fields.get("edition"), fields.get("sequence"))
        elif event.get("event") == "window":
            cards = as_int(ins.fields(event).get("cards"))
            if generation is None:
                empty_unattributed += 1 if cards == 0 else 0
                continue
            if cards == 0:
                empty_attributed += 1
            per_generation.setdefault(generation, []).append(cards or 0)
    empty_then_content = 0
    for series in per_generation.values():
        seen = False
        for cards in series:
            if cards == 0:
                seen = True
            elif seen:
                empty_then_content += 1
                break
    m1_verdict = None if not per_generation else ins.absence(empty_then_content)
    facts = [fact("empty_then_content == 0", empty_then_content, "0", m1_verdict,
        _gap(m1_verdict, SEM_SUJEITO if not per_generation else EVIDENCIA_INCOMPLETA))]
    cards_series = sorted({as_int(line.get("cards")) for line in ins.journey if as_int(line.get("cards")) is not None})
    rejects = [as_int(line.get("install_rejects")) for line in ins.journey]
    return measurement("M1", "A abertura entrega conteúdo na mesma geração",
        "Abri o app e o conteúdo apareceu — sem o app me dizer antes que o feed estava vazio?",
        "`window.cards` por geração, com o `window` atribuído ao último `admitted` anterior "
        "(AppComposition.swift:1356-1360, :2346-2350)",
        facts,
        {"janelas_gravadas": sum(len(series) for series in per_generation.values()) + empty_unattributed,
            "gerações_com_janela": len(per_generation),
            "vazias_atribuídas_a_uma_geração": empty_attributed,
            "vazias_antes_do_primeiro_install": empty_unattributed,
            "vazias_no_fim_da_geração": sum(1 for series in per_generation.values() if series and series[-1] == 0),
            "linhas_de_jornada_no_console": len(ins.journey),
            "cartas_na_linha_de_jornada": cards_series,
            "install_rejects_máximo": max([value for value in rejects if value is not None], default=None)},
        ["O vazio **declarado** (a superfície dizendo que acabou) não é medido aqui: o traço não grava o estado da "
         "superfície e `preparation=done` não é isso — ver a lista de NOT_RUN."])


def measure_m2(ins: Insumo) -> dict:
    """M2 — a primeira tela tem história: toda carta publicada tem fonte e destino resolvível."""
    cards = ins.cards
    without_source = sum(1 for card in cards if not (card.get("source_id") or "").strip())
    without_action = sum(1 for card in cards if not (card.get("primary_action_reference") or "").strip())
    source_verdict = (without_source == 0) if cards else None
    action_verdict = (without_action == 0) if cards else None
    return measurement("M2", "A primeira tela tem história",
        "Toda carta que eu vi pertence a uma fonte que existe e tem para onde me levar?",
        "`published_cards.source_id` e `.primary_action_reference` (a cláusula parcial do oráculo é "
        "bench/oracle.py:285-287)",
        [fact("cards_sem_fonte == 0", without_source, "0", source_verdict, _gap(source_verdict, SEM_SUJEITO)),
         fact("cards_sem_destino == 0", without_action, "0", action_verdict, _gap(action_verdict, SEM_SUJEITO))],
        {"cartas": len(cards), "edições": len({card["edition"] for card in cards if card["edition"]}),
            "fontes_distintas": len({card.get("source_id") for card in cards if card.get("source_id")}),
            "layouts": sorted({card.get("render_layout") for card in cards})},
        ["Lida do banco, não do traço: a perda de eventos do traço não contamina esta medição."])


def measure_m3(ins: Insumo) -> dict:
    """M3 — rolar: cada avanço atinge carta dentro da janela instalada, e `forward` não pousa atrás.

    Duas armadilhas fechadas aqui, as duas medidas:

    * a comparação é **dentro da geração** e usa a **última posição observada** (inclusive as observações
      `stationary`, que são posição relatada): sem isso, `forward=10, stationary=20, forward=15` passaria, e o
      primeiro avanço de uma sessão nova seria comparado com a posição da sessão anterior (falso vermelho);
    * a posição vem da ordem do leitor **da edição da carta**, não de um índice global: o mesmo ordinal existe em
      edições diferentes, e um índice global intercalava dois feeds.

    O estudo propõe `avanços == cartas_distintas`; medido em `bench/run/20261014T182436Z` (2026-10-16) isso é
    falso nos dados reais e **não** por defeito do produto — 230 avanços `forward` repetem a âncora anterior, 219
    deles logo depois de uma observação `stationary` no topo do feed. Cláusula que acusa gesto legítimo falha Q1.
    """
    generations: dict[tuple, tuple[int, int]] = {}
    generation = None
    advances = []
    for event in ins.events:
        fields = ins.fields(event)
        if event.get("event") == "admitted":
            edition = (fields.get("edition") or "").lower()
            generation = (edition, fields.get("sequence"))
            head, tail = ins.position(fields.get("head"), edition), ins.position(fields.get("tail"), edition)
            if head is not None and tail is not None:
                generations[generation] = (head, tail)
        elif event.get("event") == "advance":
            edition = (generation or ("", ""))[0]
            advances.append({"generation": generation, "edition": edition,
                "installed": generations.get(generation), "activity": fields.get("activity"),
                "anchor": ins.position(fields.get("anchor"), edition)})
    outside = forward_behind = backward_ahead = unresolved = comparable = 0
    previous: dict[tuple, int] = {}
    for advance in advances:
        if advance["anchor"] is None:
            unresolved += 1
            continue
        installed = advance["installed"]
        if installed is None or not (installed[0] <= advance["anchor"] <= installed[1]):
            outside += 1
        reference = previous.get(advance["generation"])
        if reference is not None:
            comparable += 1
            if advance["activity"] == "forward" and advance["anchor"] < reference:
                forward_behind += 1
            if advance["activity"] == "backward" and advance["anchor"] > reference:
                backward_ahead += 1
        previous[advance["generation"]] = advance["anchor"]
    activities: dict[str, int] = {}
    for advance in advances:
        activities[advance["activity"]] = activities.get(advance["activity"], 0) + 1
    # Sem janela instalada não há "dentro da janela" para medir; sem dois avanços na mesma geração não há "atrás
    # do anterior". Em ambos os casos é NOT_RUN, nunca PASS — e o motivo diz se é escopo ou lacuna.
    window_verdict = (ins.absence(outside) if not unresolved else None) \
        if (advances and generations) else None
    behind_verdict = (ins.absence(forward_behind) if not unresolved else None) if comparable else None
    window_motivo = SEM_SUJEITO if not (advances and generations) \
        else (NAO_RESOLVIDO if unresolved else EVIDENCIA_INCOMPLETA)
    behind_motivo = SEM_SUJEITO if not comparable else (NAO_RESOLVIDO if unresolved else EVIDENCIA_INCOMPLETA)
    return measurement("M3", "Rolar atinge carta que existe e para frente é para frente",
        "Rolei — e cheguei a cartas de verdade, sem o app me dizer que avancei para um lugar onde eu já estava?",
        "`advance.activity`/`.anchor` (AppComposition.swift:2577-2579) cruzados com a janela instalada "
        "(`admitted.head`/`tail`) e com a ordem do leitor dentro da edição "
        "(`feed_segments.edition_id`, `feed_segments.ordinal`, `published_cards.ordinal`)",
        [fact("âncora fora da janela instalada == 0", outside, "0", window_verdict,
            _gap(window_verdict, window_motivo)),
         fact("avanço forward atrás da posição observada anterior == 0", forward_behind, "0", behind_verdict,
            _gap(behind_verdict, behind_motivo))],
        {"avanços": len(advances), "por_atividade": activities,
            "avanços_com_posição_observada_anterior": comparable,
            "âncoras_distintas": len({advance["anchor"] for advance in advances if advance["anchor"] is not None}),
            "âncoras_não_resolvidas_na_edição": unresolved,
            "avanços_para_trás_que_pousam_à_frente": backward_ahead, "gerações": len(generations)},
        ["`avanços_para_trás_que_pousam_à_frente` = 1 em 5.390 avanços (`bench/run/20261014T200700Z`) e 0 nas "
         "outras corridas: número cru, não cláusula — o gesto ainda não foi julgado."])


def measure_m4(ins: Insumo) -> dict:
    """M4 — rolar com trabalho de fundo: nada acima da âncora muda.

    Quatro fatos sobre a janela que o app instalou, cada um resolvido na ordem do leitor **da edição da
    instalação**: a janela contém a âncora, não encolhe, a cauda não recua, e não ganha buraco. O cabeçalho
    avançar não é cláusula: medido, ele é a poda desenhada de `backwardWindowCards = 8`
    (`AppComposition.swift:1861`) — âncora 11 → cabeça 3 e âncora 14 → cabeça 6, nas duas ocasiões sem gesto
    entre as instalações.
    """
    series = ins.installs()
    unresolved = sum(1 for row in series if row["head"] is None or row["tail"] is None)
    contains_anchor = shrunk = tail_back = holes = measurable = head_forward = 0
    reference = None
    generation = None
    for row in series:
        if row["generation"] != generation:
            generation, reference = row["generation"], None
        if row["head"] is not None and row["tail"] is not None and row["anchor"] is not None:
            if not (row["head"] <= row["anchor"] <= row["tail"]):
                contains_anchor += 1
        if reference is not None:
            if row["cards"] is not None and reference["cards"] is not None and row["cards"] < reference["cards"]:
                shrunk += 1
            if row["tail"] is not None and reference["tail"] is not None and row["tail"] < reference["tail"]:
                tail_back += 1
            if row["head"] is not None and reference["head"] is not None and row["head"] > reference["head"]:
                head_forward += 1
        if row["cards"] is not None and row["head"] is not None and row["tail"] is not None:
            measurable += 1
            if row["tail"] - row["head"] + 1 != row["cards"]:
                holes += 1
        reference = row
    gate = (lambda observed: ins.absence(observed)) if not unresolved else (lambda observed: None)
    series_motivo = SEM_SUJEITO if not series else (NAO_RESOLVIDO if unresolved else EVIDENCIA_INCOMPLETA)
    holes_motivo = SEM_SUJEITO if not measurable else (NAO_RESOLVIDO if unresolved else EVIDENCIA_INCOMPLETA)
    anchored = gate(contains_anchor) if series else None
    shrunk_verdict = gate(shrunk) if series else None
    tail_verdict = gate(tail_back) if series else None
    holes_verdict = gate(holes) if measurable else None
    return measurement("M4", "Rolar com trabalho de fundo não move o que está acima da âncora",
        "Rolei e nada acima de mim mudou — o app não retirou, não encolheu e não remendou o feed sob a minha leitura?",
        "`admitted.cards`/`head`/`tail`/`anchor` na ordem do leitor da edição (AppComposition.swift:2346-2350; o "
        "instrumento de B04 mede o mesmo registro em bench/oracle.py:390-460)",
        [fact("janela instalada contém a âncora == 0", contains_anchor, "0", anchored,
            _gap(anchored, series_motivo)),
         fact("encolhimentos == 0", shrunk, "0", shrunk_verdict, _gap(shrunk_verdict, series_motivo)),
         fact("cauda recuou == 0", tail_back, "0", tail_verdict, _gap(tail_verdict, series_motivo)),
         fact("buracos na janela == 0", holes, "0", holes_verdict, _gap(holes_verdict, holes_motivo))],
        {"instalações": len(series), "instalações_não_resolvidas": unresolved,
            "cabeça_avançou": head_forward, "gerações": len({row["generation"] for row in series})},
        ["`cabeça_avançou` é número cru: numa corrida que rola, a cabeça seguir o leitor é a poda declarada "
         "(`backwardWindowCards = 8`). A cláusula congelada `head == first` (bench/oracle.py:449) só é "
         "aplicável onde o leitor não anda — proposta de revisão no relatório, não executada."])


def measure_m5(ins: Insumo) -> dict:
    """M5 — as imagens aparecem: **o que o asset local pode provar, e o que ele não pode**.

    O que ele prova: uma carta da janela instalada que declara mídia (`media_key = sha256:<digest>`) e não tem o
    arquivo `Media/sha256/<digest>` **não pode** ter sido desenhada com a imagem — o desenho local devolve
    placeholder (`Sources/FeedMineRuntime/PresentationImage.swift:48-65`). O que ele **não** prova: que a imagem
    apareceu — um arquivo presente pode falhar na decodificação e desenhar o placeholder
    (`PresentationImage.swift:48-65`; `PresentationCard.swift:50-51` distingue bitmap residente de slot), e o
    repo não guarda uma tela decodificada. Por isso a pergunta visual fica `NOT_RUN` e o censo de blobs é
    relatado ao lado.
    """
    installs = ins.installs()
    files = ins.media_files()
    window_cards: list[dict] = []
    if installs:
        last = installs[-1]
        rows = ins.by_edition.get(last["edition"], [])
        if last["head"] is not None and last["tail"] is not None:
            window_cards = rows[last["head"]:last["tail"] + 1]
    declared = [card for card in ins.cards if (card.get("media_key") or "").startswith(MEDIA_KEY_PREFIX)]
    missing_in_window = [card for card in window_cards
        if (card.get("media_key") or "").startswith(MEDIA_KEY_PREFIX)
        and (card["media_key"])[len(MEDIA_KEY_PREFIX):] not in files]
    missing_all = [card for card in declared if (card["media_key"])[len(MEDIA_KEY_PREFIX):] not in files]
    measurable = bool(window_cards) and ins.media_dir is not None
    asset_verdict = (len(missing_in_window) == 0) if measurable else None
    return measurement("M5", "As imagens aparecem (o que o asset local prova, e o que não prova)",
        "As imagens apareceram nos cartões — sem imagem quebrada?",
        "`published_cards.media_key` vs. `Media/sha256/<digest>` para as cartas da janela instalada "
        "(AssetStore.swift:37-45,78-79); `render_layout` em PresentationCard.swift:11-15",
        [fact("cartas da janela com mídia declarada e sem asset local == 0", len(missing_in_window), "0",
            asset_verdict, _gap(asset_verdict, SEM_SUJEITO)),
         fact("a imagem foi desenhada (pixel decodificado) — precisa de tela, não de arquivo", "sem evidência",
            "igualdade com a tela do cartão", None, NAO_IMPLEMENTADO)],
        {"cartas": len(cards_ := ins.cards), "edições": len({card["edition"] for card in cards_ if card["edition"]}),
            "cartas_na_última_janela": len(window_cards),
            "com_mídia_declarada": len(declared), "digests_distintos": len({card["media_key"] for card in declared}),
            "arquivos_em_Media/sha256": len(files),
            "declaradas_sem_asset_em_toda_a_publicação": len(missing_all),
            "layouts": sorted({card.get("render_layout") for card in cards_})},
        ["O censo de toda a publicação (`declaradas_sem_asset_em_toda_a_publicação`) é número cru: a limpeza de "
         "mídia evicta por orçamento por desenho (`Sources/FeedMineMedia/MediaHousekeeping.swift:6-7`), então "
         "ausência fora da janela não é defeito. A cláusula só olha a janela instalada.",
         "Sem `Media/sha256/` no contêiner puxado, nada disto é observável naquele insumo (as corridas do bench "
         "não materializam mídia e publicam `textOnly` em todas as cartas).",
         "O console do aparelho já publica `hero`/`thumb`/`media_resident` por segundo (AppComposition.swift:2340-2356);"
         " transformá-los em cláusula exige decidir o que `media_resident < thumb` significa no produtor — não "
         "decidido aqui."])


def measure_m7(ins: Insumo) -> dict:
    """M7 — fechar e reabrir: a âncora durável é a âncora relatada, no contexto que foi medido.

    Os dois registros que a restauração consome têm de concordar: a linha do **contexto medido**
    (`context_checkpoints`, que retém uma linha por contexto — `SessionStore.swift:91-106,130-134`) e a linha da
    **sessão** (`session_checkpoint`). O contexto medido é o da **edição do último `admitted` do traço**; se
    nenhuma linha (ou mais de uma) tem essa edição, o instrumento não sabe qual contexto foi medido e diz
    `NOT_RUN` — não escolhe a primeira linha.

    Comparabilidade: o evento `position_checkpoint` existe só quando a escrita durável aconteceu
    (AppComposition.swift:2680-2690). Se a linha durável é mais nova que o último evento do traço, ou o traço
    perdeu eventos, a "última âncora relatada" pode não ser a real: `NOT_RUN`, com os dois valores crus ao lado.
    """
    checkpoints = [{"anchor": (ins.fields(event).get("anchor") or "").lower(), "at": event.get("at")}
        for event in ins.events_of("position_checkpoint")]
    installs = [event for event in ins.events_of("admitted")]
    measured_edition = (ins.fields(installs[-1]).get("edition") or "").lower() if installs else None
    rows = [row for row in (ins.durable.get("context") or [])
        if (row.get("edition_id") or "").lower() == measured_edition]
    session_rows = ins.durable.get("session") or []
    session = (session_rows or [None])[0]
    reported = checkpoints[-1]["anchor"] if checkpoints else None
    reported_at = checkpoints[-1]["at"] if checkpoints else None
    stored = (rows[0].get("card_id") or "").lower() if len(rows) == 1 else None
    stored_at = rows[0].get("updated_at") if len(rows) == 1 else None
    last_event_at = ins.events[-1].get("at") if ins.events else None
    # As guardas abaixo são as mesmas da versão aprovada; o que mudou é que cada saída por `None` agora diz
    # **por que** — escopo do insumo (`sem_sujeito`) ou lacuna de medição (o resto). O código de saída lê isso.
    context_verdict, context_motivo = None, None
    if not rows:
        # Banco sem nenhuma linha durável tem menos sujeito que banco com linhas de outras edições: naquele, o
        # app não gravou âncora durável nenhuma; neste, gravou, mas não a do contexto medido.
        context_motivo = NAO_IDENTIFICADO if (ins.durable.get("context") or []) else SEM_SUJEITO
    elif len(rows) > 1:
        context_motivo = NAO_IDENTIFICADO
    elif last_event_at is None:
        context_motivo = SEM_SUJEITO
    elif not (reported and stored and stored_at is not None):
        context_motivo = NAO_COMPARAVEL
    elif not isinstance(stored_at, (int, float)):
        context_motivo = NAO_COMPARAVEL
    elif stored_at > last_event_at + 1.0:
        context_motivo = NAO_COMPARAVEL
    elif not ins.complete():
        context_motivo = EVIDENCIA_INCOMPLETA
    else:
        context_verdict = stored == reported
    session_verdict, session_motivo = None, None
    if stored and session and session.get("card_id"):
        session_verdict = (session["card_id"] or "").lower() == stored
    else:
        session_motivo = SEM_SUJEITO if not session_rows else NAO_IDENTIFICADO
    reported_index = ins.position(reported, measured_edition)
    stored_index = ins.position(stored, measured_edition)
    return measurement("M7", "A âncora que eu reabro é a âncora que o app gravou",
        "Fechei e reabri — o app me devolveu exatamente onde eu estava?",
        "último `position_checkpoint.anchor` do traço (AppComposition.swift:2689-2690) vs. "
        "`context_checkpoints.card_id` (a linha do contexto medido) e `session_checkpoint.card_id`",
        [fact("âncora durável do contexto medido == última âncora relatada", (stored == reported) if context_verdict
            is not None else "não comparável", "igualdade", context_verdict,
            _gap(context_verdict, context_motivo)),
         fact("a linha de sessão concorda com a do contexto medido", (session or {}).get("card_id"), stored,
            session_verdict, _gap(session_verdict, session_motivo))],
        {"edição_medida": measured_edition, "checkpoints_relatados": len(checkpoints),
            "âncora_relatada": reported, "âncora_relatada_índice": reported_index,
            "âncora_durável": stored, "âncora_durável_índice": stored_index,
            "linhas_de_contexto_do_medido": len(rows),
            "âncora_durável_em": iso(stored_at) if isinstance(stored_at, (int, float)) else stored_at,
            "último_evento_do_traço_em": iso(last_event_at),
            "traço_completo": ins.complete(),
            "regressão_da_âncora": (stored_index < reported_index
                if stored_index is not None and reported_index is not None else None)},
        ["O **pouso** da reabertura não é medido: o traço cobre uma sessão e a instalação que restaura a âncora "
         "é de outra. `admitted` grava a âncora instalada (AppComposition.swift:2346-2350) mas não grava o tipo "
         "de admissão — `.restore` existe em `Sources/FeedMineRuntime/FeedPresentationAdmission.swift:72` e é "
         "usado em AppComposition.swift:2709. Sem esse campo, o instrumento não sabe qual instalação é a "
         "reabertura e não afirma nada sobre o pouso."])


def measure_m10(ins: Insumo) -> dict:
    """M10 — rolar rápido: a série de quadros, relatada. Sem limiar por desenho.

    `FeedFrameMeter` escreve uma linha por segundo (`FeedMineApp/FeedMineApp/FeedFrameMeter.swift`) e o console do
    aparelho imprime a mesma linha. O limiar de fluidez é baseline de aparelho, não critério: o único fato
    binário aqui é a presença de amostras.
    """
    trace_rows = []
    for event in ins.events_of("frames"):
        fields = ins.fields(event)
        trace_rows.append({"frames": as_int(fields.get("frames")), "late": as_int(fields.get("late")),
            "bad": as_int(fields.get("bad")), "severe": as_int(fields.get("severe")),
            "worst_ms": fields.get("worst_ms"), "budget_ms": fields.get("budget_ms"), "mono": event.get("mono")})

    def totals(rows: list[dict]) -> dict:
        frames = sum(row["frames"] or 0 for row in rows)
        late = sum(row["late"] or 0 for row in rows)
        bad = sum(row["bad"] or 0 for row in rows)
        severe = sum(row["severe"] or 0 for row in rows)
        return {"segundos": len(rows), "quadros": frames, "late": late, "bad": bad, "severe": severe,
            "fora_do_orçamento": late + bad + severe,
            "razão_fora_do_orçamento": round((late + bad + severe) / frames, 5) if frames else None,
            "pior_intervalo_ms": max([float(row["worst_ms"]) for row in rows if row.get("worst_ms")], default=None),
            "segundos_com_severe": sum(1 for row in rows if (row["severe"] or 0) > 0)}

    seconds = len(trace_rows) or len(ins.frame_lines)
    series_verdict = True if seconds else None
    return measurement("M10", "Rolar rápido: a série de quadros, relatada",
        "Rolei rápido — o que o app mediu de cada segundo, quadro a quadro?",
        "`frames.frames/late/bad/severe/worst_ms/budget_ms` do traço (FeedFrameMeter.swift) e as linhas "
        "`feedmine frames=…` do console",
        [fact("série medida (segundos > 0)", seconds, "> 0", series_verdict, _gap(series_verdict, SEM_SUJEITO))],
        {"traço": totals(trace_rows), "console": totals(ins.frame_lines),
            "traço_completo": ins.complete()},
        ["Sem limiar por desenho: a razão fora do orçamento é impressa e não decide. `--series` imprime a série "
         "inteira, uma linha por segundo."])


NOT_RUN_MEASUREMENTS = [
    {"id": "M1/M6 (superfície)",
     "titulo": "O vazio e o fim **declarados** pela superfície",
     "falta": "Nenhum evento diz que a superfície declarou o feed vazio ou o fim de feed. `preparation=done` na "
              "linha de jornada **não** é isso: significa que o relé não recebeu nada "
              "(`FeedMineApp/FeedMineApp/AppComposition.swift:2363-2366`), e depois dele o host ainda agenda nova "
              "tentativa (`:2507-2535`). Sem essa evidência, a cláusula do vazio terminal fica não medida.",
     "onde": "`Sources/FeedMineUI/FeedPresentationState.swift:45` (o caso `endOfContent`), "
             "`Sources/FeedMineUI/FeedScreen.swift:200` (onde é desenhado), "
             "`FeedMineApp/FeedMineApp/AppComposition.swift:2431-2433` (onde é concluído) e `:2399-2400` (onde o "
             "app descobre que o fim mostrado era falso) — nenhum grava."},
    {"id": "M8",
     "titulo": "Sem rede: história local e a carta salva abre",
     "falta": "O app não grava que o transporte estava bloqueado (`FEEDMINE_BLOCK_RSS_NETWORK` é lido e não vira "
              "evento) nem que a carta salva abriu (o banco diz que foi salva).",
     "onde": "`FeedMineApp/FeedMineApp/AppComposition.swift:174-177`."},
    {"id": "M9",
     "titulo": "Primeiro uso sem assinatura",
     "falta": "Não implementada de propósito: exige o conjunto congelado `STARTER_KEYS`, que é régua congelada — "
              "duplicá-lo aqui criaria duas fontes para o mesmo fato. A cláusula já existe como B01.",
     "onde": "`bench/oracle.py:35-39,195-198`."},
    {"id": "M11",
     "titulo": "App aberto 30 min: fontes novas no fim das janelas",
     "falta": "O traço não tem o carimbo de fim de janela nem o conjunto de fontes por janela.",
     "onde": "`bench/expand.py:26` (o instrumento congelado que já mede isso)."},
    {"id": "M12",
     "titulo": "p50/p95 de lançamento → primeira carta",
     "falta": "O instante do lançamento não é gravado: o traço começa no primeiro `window`/`frames` e a linha de "
              "jornada conta `t=` do primeiro quadro desenhado. Um percentil exige ≥30 execuções.",
     "onde": "Um `record(\"launch\", …)` em `FeedMineApp/FeedMineApp/AppComposition.swift:71-72`/`:258` ou em "
             "`FeedMineApp/FeedMineApp/FeedMineApp.swift:23`."},
    {"id": "M7 (pouso)",
     "titulo": "O pouso da reabertura: a carta que o app instala no topo depois de relançar",
     "falta": "O traço cobre uma sessão e não diz qual instalação é a restauração. `admitted` grava a âncora "
              "instalada, mas não o tipo de admissão.",
     "onde": "`FeedMineApp/FeedMineApp/AppComposition.swift:2346-2350` (gravar o tipo) — `.restore` em "
             "`Sources/FeedMineRuntime/FeedPresentationAdmission.swift:72`, usado em `AppComposition.swift:2709`."},
]


# -- injeções (controle positivo) -------------------------------------------------------------------------------

INJECTIONS = ("m1", "m2", "m3a", "m3b", "m4", "m5", "m5b", "m7", "m7a", "m10")


def _copy_insumo(ins: Insumo, out: str) -> None:
    """Copia **tudo** o que o instrumento lê: traço, banco com sidecars, mídia e console.
    Sem o console, uma injeção tiraria da cópia evidência que não tem nada a ver com ela."""
    if os.path.exists(out):
        if os.listdir(out):
            raise InputError(f"REFUSED: --out {out} existe e não está vazio")
    os.makedirs(out, exist_ok=True)
    if ins.trace:
        shutil.copy2(ins.trace, os.path.join(out, "trace.jsonl"))
    if ins.database:
        for suffix in ("", "-wal", "-shm"):
            if os.path.exists(ins.database + suffix):
                shutil.copy2(ins.database + suffix, os.path.join(out, "runtime.sqlite" + suffix))
    if ins.media_dir and os.path.isdir(ins.media_dir):
        destination = os.path.join(out, "Media", "sha256")
        os.makedirs(destination, exist_ok=True)
        for name in os.listdir(ins.media_dir):
            source = os.path.join(ins.media_dir, name)
            if os.path.isfile(source):
                shutil.copy2(source, os.path.join(destination, name))
    if ins.console:
        shutil.copy2(ins.console, os.path.join(out, "console.log"))


def _rewrite_trace(path: str, mutate, cap: int = 4) -> dict:
    """Aplica `mutate` a cada evento (devolvendo `None` remove a linha). Linha intocada volta **byte a byte**:
    re-codificar tudo reescreveria a forma do app (`\\/` do JSONEncoder) e o diff acusaria milhares de linhas."""
    lines, events, _ = read_jsonl(path)
    changes: list[str] = []
    changed = removed = 0
    output: list[str] = []
    for number, (line, event) in enumerate(zip(lines, events), start=1):
        replacement = mutate(event, number)
        if replacement is None:
            removed += 1
            if len(changes) < cap:
                changes.append(f"linha {number} REMOVIDA: {line[:160]}")
            continue
        if replacement == event:
            output.append(line)
            continue
        encoded = compact(replacement)
        changed += 1
        if len(changes) < cap:
            changes.append(f"linha {number}:\n      antes:  {line}\n      depois: {encoded}")
        output.append(encoded)
    write_file(path, "\n".join(output) + ("\n" if output else ""))
    return {"changes": changes, "changed": changed, "removed": removed}


def _report(headline: str, record: dict) -> list[str]:
    lines = [headline]
    lines.extend(f"    {entry}" for entry in record["changes"])
    if record["changed"] > len(record["changes"]) or record["removed"] > len(record["changes"]):
        lines.append(f"    (total: {record['changed']} alteradas, {record['removed']} removidas)")
    return lines


def _sql(database: str, statement: str, arguments: tuple = ()) -> list:
    connection = sqlite3.connect(database)
    try:
        rows = connection.execute(statement, arguments).fetchall()
        connection.commit()
        return rows
    finally:
        connection.close()


def inject(ins: Insumo, which: str, out: str) -> list[str]:
    _copy_insumo(ins, out)
    trace = os.path.join(out, "trace.jsonl")
    database = os.path.join(out, "runtime.sqlite")

    if which == "m1":
        attributed: list[tuple] = []
        generation = None
        for event in ins.events:
            if event.get("event") == "admitted":
                fields = ins.fields(event)
                generation = (fields.get("edition"), fields.get("sequence"))
            elif event.get("event") == "window":
                attributed.append((generation, as_int(ins.fields(event).get("cards")), event))
        target = None
        for position, (gen, cards, event) in enumerate(attributed):
            if gen is None or not cards:
                continue
            if any(other_gen == gen and (other_cards or 0) > 0
                   for other_gen, other_cards, _ in attributed[position + 1:]):
                target = event
        if target is None:
            raise InputError("REFUSED: nenhuma janela com conteúdo seguida de outra na mesma geração")
        stamp = (target.get("at"), target.get("mono"))

        def mutate(event, number, stamp=stamp):
            if (event.get("at"), event.get("mono")) != stamp or event.get("event") != "window":
                return event
            fields = dict(event.get("fields") or {})
            fields.update({"cards": "0", "resolved_sources": "0", "with_subject": "0"})
            return {**event, "fields": fields}

        return _report("injeção m1: uma janela desenhada passa a declarar `cards=0` no meio da geração "
            "(o falso vazio que M1 proíbe)", _rewrite_trace(trace, mutate))

    if which == "m2":
        row = _sql(database, "SELECT id, primary_action_reference, primary_action_kind FROM published_cards "
            "WHERE primary_action_reference IS NOT NULL LIMIT 1")[0]
        # O esquema amarra as duas colunas: carta publicada **sem destino** tem as duas em NULL.
        _sql(database, "UPDATE published_cards SET primary_action_reference = NULL, primary_action_kind = NULL "
            "WHERE id = ?", (row[0],))
        after = _sql(database, "SELECT primary_action_reference, primary_action_kind FROM published_cards "
            "WHERE id = ?", (row[0],))[0]
        return [f"injeção m2: a carta {row[0]} perde o destino:",
            f"      antes:  reference={row[1]}  kind={row[2]}",
            f"      depois: reference={after[0]}  kind={after[1]}"]

    if which in ("m3a", "m3b"):
        series = ins.installs()
        generation = None
        windows: dict[tuple, tuple[int, int]] = {}
        for row in series:
            generation = row["generation"]
            if row["head"] is not None and row["tail"] is not None:
                windows[generation] = (row["head"], row["tail"])
        previous: dict[tuple, int] = {}
        target = None
        for event in ins.events:
            if event.get("event") != "advance":
                continue
            fields = ins.fields(event)
            edition = (generation or ("", ""))[0]
            anchor = ins.position(fields.get("anchor"), edition)
            installed = windows.get(generation)
            if which == "m3a" and installed and installed[0] > 0 and anchor is not None:
                target = (event, ins.by_edition[edition][0]["id"])
            if which == "m3b" and fields.get("activity") == "forward" and anchor is not None:
                reference = previous.get(generation)
                if reference is not None and reference >= 1 and anchor > reference:
                    target = (event, ins.by_edition[edition][reference - 1]["id"])
            if anchor is not None:
                previous[generation] = anchor
        if target is None:
            raise InputError(f"REFUSED: nenhum avanço adequado para a injeção {which}")
        stamp, replacement = (target[0].get("at"), target[0].get("mono")), target[1]

        def mutate(event, number, stamp=stamp, replacement=replacement):
            if (event.get("at"), event.get("mono")) != stamp or event.get("event") != "advance":
                return event
            fields = dict(event.get("fields") or {})
            fields["anchor"] = replacement.upper()
            return {**event, "fields": fields}

        return _report(f"injeção {which}: a âncora de um avanço passa a apontar para uma carta "
            + ("fora da janela instalada" if which == "m3a" else "atrás da posição observada anterior"),
            _rewrite_trace(trace, mutate))

    if which == "m4":
        series = ins.installs()
        target = None
        for row in series:
            if row["head"] is not None and row["head"] > 0:
                target = row
                break
        if target is None:
            raise InputError("REFUSED: nenhuma instalação com cabeça além da primeira carta")
        rows = ins.by_edition[target["edition"]]
        before, after = rows[target["head"]], rows[target["head"] + 1]
        stamp = (target["at"], target["mono"])

        def mutate(event, number, stamp=stamp):
            if (event.get("at"), event.get("mono")) != stamp or event.get("event") != "admitted":
                return event
            fields = dict(event.get("fields") or {})
            fields["head"] = after["id"].upper()
            fields["cards"] = str(max(0, (as_int(fields.get("cards")) or 1) - 1))
            return {**event, "fields": fields}

        return _report("injeção m4: a primeira carta da janela instalada sai da série de admissão "
            f"(cabeça {before['id']} → {after['id']}, `cards` − 1): a janela encolhe sob a leitura",
            _rewrite_trace(trace, mutate))

    if which in ("m5", "m5b"):
        files = ins.media_files()
        installs = ins.installs()
        window_cards = []
        if installs and installs[-1]["head"] is not None and installs[-1]["tail"] is not None:
            rows = ins.by_edition.get(installs[-1]["edition"], [])
            window_cards = rows[installs[-1]["head"]:installs[-1]["tail"] + 1]
        candidates = [card for card in window_cards if (card.get("media_key") or "").startswith(MEDIA_KEY_PREFIX)]
        if not candidates:
            raise InputError("REFUSED: nenhuma carta da janela declara mídia")
        if which == "m5":
            digest = candidates[0]["media_key"][len(MEDIA_KEY_PREFIX):]
            path = os.path.join(out, "Media", "sha256", digest)
            if not os.path.exists(path):
                raise InputError(f"REFUSED: o asset {digest} não está na cópia")
            size = os.path.getsize(path)
            os.remove(path)
            return [f"injeção m5: o asset local da carta {candidates[0]['id']} (na janela instalada) é apagado:",
                f"      removido: Media/sha256/{digest} ({size} B), e a carta continua declarando "
                f"{candidates[0]['media_key']}"]
        card = candidates[0]
        _sql(database, "UPDATE published_cards SET media_key = NULL, media_pixel_width = NULL, "
            "media_pixel_height = NULL, media_mime_type = NULL WHERE id = ?", (card["id"],))
        after = _sql(database, "SELECT media_key, render_layout FROM published_cards WHERE id = ?", (card["id"],))[0]
        return [f"injeção m5b: a carta {card['id']} deixa de declarar mídia e continua com slot:",
            f"      antes:  media_key={card['media_key']}  render_layout={card['render_layout']}",
            f"      depois: media_key={after[0]}  render_layout={after[1]}"]

    if which in ("m7", "m7a"):
        row = _sql(database, "SELECT card_id FROM context_checkpoints LIMIT 1")
        if not row:
            raise InputError("REFUSED: nenhuma linha em context_checkpoints")
        if which == "m7":
            anchors = [ins.fields(event).get("anchor", "").lower() for event in ins.events_of("position_checkpoint")]
            replacement = anchors[0] if anchors else None
            if not replacement or replacement == row[0][0]:
                raise InputError("REFUSED: nenhuma âncora relatada anterior serve de destino")
        else:
            replacement = "00000000-0000-4000-8000-000000000000"
        _sql(database, "UPDATE context_checkpoints SET card_id = ?", (replacement,))
        _sql(database, "UPDATE session_checkpoint SET card_id = ?", (replacement,))
        after = _sql(database, "SELECT card_id FROM context_checkpoints LIMIT 1")[0][0]
        return [f"injeção {which}: `context_checkpoints.card_id` e `session_checkpoint.card_id`:",
            f"      antes:  {row[0][0]}", f"      depois: {after}"
            + (" (uma âncora relatada anterior)" if which == "m7" else " (uma carta que o app nunca relatou)")]

    if which == "m10":

        def mutate(event, number):
            return None if event.get("event") == "frames" else event

        record = _rewrite_trace(trace, mutate)
        console = os.path.join(out, "console.log")
        removed_console = 0
        if os.path.exists(console):
            kept = []
            with open(console, encoding="utf-8", errors="replace") as handle:
                for line in handle:
                    if FRAMES_RE.search(line):
                        removed_console += 1
                        continue
                    kept.append(line)
            write_file(console, "".join(kept))
        return _report(f"injeção m10: a série de quadros sai do insumo ({record['removed']} linhas do traço, "
            f"{removed_console} do console)", record)

    raise InputError(f"REFUSED: injeção desconhecida {which}")


# -- impressão --------------------------------------------------------------------------------------------------


def clause_line(result: dict) -> str:
    """O que o código de saída vê nesta cláusula — separado do veredito que o leitor vê."""
    state = clause_state(result)
    if state["lacunas"]:
        return f"aplicável, com lacuna de medição: {', '.join(sorted(set(state['lacunas'])))}"
    if not state["aplicavel"]:
        return f"não aplicável neste insumo: {', '.join(sorted(set(state['fora_de_escopo'])))}"
    if state["fora_de_escopo"]:
        return ("aplicável e medida; fora de escopo: "
            + ", ".join(sorted(set(state["fora_de_escopo"]))))
    return "aplicável e medida"


def render_measurement(result: dict) -> str:
    lines = [f"[{result['id']}] {result['titulo']}",
        f"  pergunta do leitor: {result['pergunta']}", f"  fato lido: {result['fato_lido']}"]
    for item in result["fatos"]:
        if item["pass"] is None:
            scope = "lacuna de medição" if item["motivo"] in GAP_REASONS else "fora de escopo"
            label = f"NOT_RUN: {scope} — {item['motivo']}"
        else:
            label = {True: "PASS", False: "FAIL"}[item["pass"]]
        lines.append(f"    [{label}] {item['fato']} — esperado: {item['esperado']}, observado: {item['observado']}")
    lines.append("  números crus (informam, não decidem):")
    for key, value in result["numeros"].items():
        if isinstance(value, dict):
            lines.append(f"    {key}: " + ", ".join(f"{k}={v}" for k, v in value.items()))
        else:
            lines.append(f"    {key}: {value}")
    for note in result["notas"]:
        lines.append(f"  nota: {note}")
    lines.append(f"  veredito: {result['veredito']}")
    lines.append(f"  cláusula: {clause_line(result)}")
    return "\n".join(lines)


def render(ins: Insumo, results: list[dict], series: list[str] | None) -> str:
    provenance = ins.provenance()
    lines = ["=" * 96, f"insumo: {provenance['insumo']} ({provenance['tipo']})", "=" * 96, "proveniência:"]
    if provenance["traco"]:
        lines.append(f"  traço: {provenance['traco']}")
        lines.append(f"    sha256={provenance['traco_sha256']} linhas={provenance['traco_linhas']} "
            f"ilegíveis={provenance['traco_ilegiveis']} janela={provenance['traco_janela'][0]} → "
            f"{provenance['traco_janela'][1]} completo={provenance['traco_completo']}")
        if provenance["traco_perda"]:
            lines.append(f"    perda declarada pelo traço: {provenance['traco_perda']}")
    if provenance["banco"]:
        lines.append(f"  banco: {provenance['banco']}")
        for name, meta in provenance["banco_bruto"].items():
            lines.append(f"    {name}: sha256={meta['sha256']} bytes={meta['bytes']}")
    if provenance["console"]:
        lines.append(f"  console: {provenance['console']} sha256={provenance['console_sha256']} "
            f"linhas_de_medida={provenance['console_linhas']}")
    lines.append(f"  mídia: {provenance['midia'] or 'ausente'}")
    lines.append(f"  cartas na ordem do leitor: {provenance['cartas']}   edições: {provenance['edições']}")
    lines.append("")
    for result in results:
        lines.append(render_measurement(result))
        lines.append("")
    lines.append("sem evidência hoje (NOT_RUN por contrato, não por falha — cláusulas que este instrumento **não**\n"
        "implementa e que **não** são aprovação global; ficam fora do código de saída por declaração, e não por\n"
        "medição):")
    for entry in NOT_RUN_MEASUREMENTS:
        lines.append(f"[{entry['id']}] {entry['titulo']}\n  veredito: NOT_RUN\n  falta: {entry['falta']}\n"
            f"  onde: {entry['onde']}")
    lines.append("")
    if series:
        lines.append("série de quadros (uma linha por segundo; sem limiar):")
        lines.extend(series)
        lines.append("")
    verdicts = [result["veredito"] for result in results]
    overall = "FAIL" if "FAIL" in verdicts else ("NOT_RUN" if "NOT_RUN" in verdicts else "PASS")
    lines.append(f"veredito do insumo (sem substituir gate nenhum): {overall} "
        f"({', '.join(result['id'] + '=' + result['veredito'] for result in results)})")
    lines.append(f"código de saída do insumo: {exit_code_of(results)} — {exit_reason(results)}")
    return "\n".join(lines)


def series_of(ins: Insumo) -> list[str]:
    rows = []
    for event in ins.events_of("frames"):
        fields = ins.fields(event)
        rows.append(f"  traço mono={event.get('mono'):.1f} frames={fields.get('frames')} late={fields.get('late')} "
            f"bad={fields.get('bad')} severe={fields.get('severe')} worst_ms={fields.get('worst_ms')} "
            f"budget_ms={fields.get('budget_ms')}")
    for index, row in enumerate(ins.frame_lines):
        rows.append(f"  console t={index}s frames={row['frames']} late={row['late']} bad={row['bad']} "
            f"severe={row['severe']} worst_ms={row['worst_ms']}")
    return rows


# -- controles positivos dos quatro códigos de saída ------------------------------------------------------------
#
# Sem insumo real à mão (as corridas vivem em `bench/run/`, fora do git), os controles montam insumos sintéticos
# **mínimos** num diretório temporário — a mesma receita da §5.11 do relatório, agora com o banco escrito aqui em
# vez de copiado de uma corrida. Cada controle roda **o próprio processo** e confere o código de saída observado e
# a linha que o justifica: é o único jeito de provar o número que uma automação lê.

FIXTURE_EDITION = "11111111-1111-4111-8111-111111111111"
FIXTURE_DIGEST = "ab" * 32
FIXTURE_CARDS = 5


def _fixture_card(index: int) -> dict:
    return {"id": f"{index:08x}-0000-4000-8000-000000000000", "ordinal": index, "source_id": f"source-{index}",
        "primary_action_reference": f"https://example.test/card/{index}", "primary_action_kind": "openURL",
        "media_key": f"{MEDIA_KEY_PREFIX}{FIXTURE_DIGEST}" if index == 2 else None,
        "render_layout": "hero" if index == 2 else TEXT_LAYOUT, "media_pixel_width": 1200,
        "media_pixel_height": 800, "media_mime_type": "image/jpeg"}


def _fixture_trace(complete_series: bool, truncated: bool) -> list[dict]:
    """Duas instalações na mesma geração e dois avanços para frente — o mínimo que M1/M3/M4 leem, com a segunda
    instalação começando depois da primeira carta (é o que a injeção `m4` precisa para ter o que retirar) e a
    carta de mídia **dentro** da janela final (o que `m5`/`m5b` precisam). Com `complete_series=False` saem os
    avanços, a série de quadros e os checkpoints: M3/M7/M10 ficam sem sujeito."""
    cards = [_fixture_card(index) for index in range(1, FIXTURE_CARDS + 1)]
    events = [
        {"at": 1000.0, "mono": 1000.0, "event": "admitted", "fields": {"edition": FIXTURE_EDITION, "sequence": "1",
            "cards": "4", "head": cards[0]["id"], "tail": cards[3]["id"], "anchor": cards[0]["id"]}},
        {"at": 1000.5, "mono": 1000.5, "event": "window", "fields": {"cards": "4"}},
    ]
    if complete_series:
        events += [
            {"at": 1001.0, "mono": 1001.0, "event": "advance",
                "fields": {"activity": "forward", "anchor": cards[2]["id"]}},
            {"at": 1001.5, "mono": 1001.5, "event": "frames",
                "fields": {"frames": "60", "late": "0", "bad": "0", "severe": "0", "worst_ms": "12.0",
                    "budget_ms": "16.67"}},
        ]
    events += [
        {"at": 1002.0, "mono": 1002.0, "event": "admitted", "fields": {"edition": FIXTURE_EDITION, "sequence": "1",
            "cards": "4", "head": cards[1]["id"], "tail": cards[4]["id"], "anchor": cards[2]["id"]}},
        {"at": 1002.5, "mono": 1002.5, "event": "window", "fields": {"cards": "4"}},
    ]
    if complete_series:
        events += [
            {"at": 1002.75, "mono": 1002.75, "event": "position_checkpoint", "fields": {"anchor": cards[2]["id"]}},
            {"at": 1003.0, "mono": 1003.0, "event": "advance",
                "fields": {"activity": "forward", "anchor": cards[3]["id"]}},
            {"at": 1004.0, "mono": 1004.0, "event": "position_checkpoint", "fields": {"anchor": cards[3]["id"]}},
            {"at": 1005.0, "mono": 1005.0, "event": "frames",
                "fields": {"frames": "58", "late": "1", "bad": "0", "severe": "0", "worst_ms": "18.4",
                    "budget_ms": "16.67"}},
        ]
    if truncated:
        events.append({"at": 1005.5, "mono": 1005.5, "event": "trace_truncated",
            "fields": {"ceiling": "40000", "written": "40000", "dropped_by_ceiling": "2", "dropped_by_write": "0",
                "dropped_by_encoding": "0"}})
    return events


def _fixture_database(path: str, cards: list[dict], durable: bool) -> None:
    """O esquema que o instrumento lê, com as colunas que as injeções tocam. `durable=False` deixa as duas
    tabelas de posição **vazias** de propósito: nenhuma âncora durável, nenhum sujeito para M7."""
    connection = sqlite3.connect(path)
    try:
        connection.execute("CREATE TABLE feed_segments (id TEXT PRIMARY KEY, edition_id TEXT, ordinal INTEGER)")
        connection.execute("CREATE TABLE published_cards (id TEXT PRIMARY KEY, source_id TEXT, "
            "primary_action_reference TEXT, primary_action_kind TEXT, media_key TEXT, render_layout TEXT, "
            "media_pixel_width INTEGER, media_pixel_height INTEGER, media_mime_type TEXT, segment_id TEXT, "
            "ordinal INTEGER)")
        connection.execute("CREATE TABLE context_checkpoints (edition_id TEXT PRIMARY KEY, card_id TEXT, "
            "updated_at REAL)")
        connection.execute("CREATE TABLE session_checkpoint (card_id TEXT, updated_at REAL)")
        connection.execute("INSERT INTO feed_segments VALUES (?, ?, ?)", ("segment-1", FIXTURE_EDITION, 1))
        for card in cards:
            connection.execute("INSERT INTO published_cards VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (card["id"], card["source_id"], card["primary_action_reference"], card["primary_action_kind"],
                    card["media_key"], card["render_layout"], card["media_pixel_width"],
                    card["media_pixel_height"], card["media_mime_type"], "segment-1", card["ordinal"]))
        if durable:
            connection.execute("INSERT INTO context_checkpoints VALUES (?, ?, ?)",
                (FIXTURE_EDITION, cards[3]["id"], 1004.5))
            connection.execute("INSERT INTO session_checkpoint VALUES (?, ?)", (cards[3]["id"], 1004.5))
        connection.commit()
    finally:
        connection.close()


def _fixture(root: str, name: str, *, complete_series: bool, durable: bool, media: bool,
    truncated: bool = False) -> str:
    path = os.path.join(root, name)
    os.makedirs(path)
    cards = [_fixture_card(index) for index in range(1, FIXTURE_CARDS + 1)]
    _fixture_database(os.path.join(path, "runtime.sqlite"), cards, durable)
    write_file(os.path.join(path, "trace.jsonl"),
        "".join(compact(event) + "\n" for event in _fixture_trace(complete_series, truncated)))
    if media:
        directory = os.path.join(path, "Media", "sha256")
        os.makedirs(directory)
        write_file(os.path.join(directory, FIXTURE_DIGEST), "fixture")
    return path


def _control(argv: list[str]) -> tuple[int, str]:
    """Roda este arquivo como **processo** e devolve (código de saída, saída crua). Filtra do ambiente o que
    não interessa ao controle: `PYTHONHASHSEED`/locale não mudam veredito, e nada aqui lê variável do app."""
    process = subprocess.run([sys.executable, os.path.abspath(__file__)] + argv,
        capture_output=True, text=True)
    return process.returncode, process.stdout + process.stderr


def build_fixtures(root: str) -> dict:
    """Monta os insumos sintéticos dos controles em `root` (que precisa não existir ou estar vazio).

    Os três insumos de medição e os dois de erro saem daqui, e não de `/tmp` de sessão: com `--fixtures DIR` um
    revisor monta os mesmos insumos e roda **cada caminho de saída** com o comando da linha de comando, sem
    depender da contabilidade deste arquivo.
    """
    if os.path.exists(root) and os.listdir(root):
        raise InputError(f"REFUSED: {root} existe e não está vazio")
    os.makedirs(root, exist_ok=True)
    vazio = os.path.join(root, "vazio")
    os.makedirs(vazio)
    quebrado = os.path.join(root, "sqlite-ilegivel")
    os.makedirs(quebrado)
    write_file(os.path.join(quebrado, "runtime.sqlite"), "isto não é um banco SQLite\n")
    return {"completo": _fixture(root, "completo", complete_series=True, durable=True, media=True),
        "fora-de-escopo": _fixture(root, "fora-de-escopo", complete_series=False, durable=False, media=False),
        "lacuna": _fixture(root, "lacuna", complete_series=True, durable=True, media=True, truncated=True),
        "vazio": vazio, "sqlite-ilegivel": quebrado}


def selftest() -> int:
    """Os controles positivos dos quatro códigos. Sai `0` se todos valem, `1` se algum quebrou, `2` se não
    consegui montar os insumos (erro de execução do próprio controle, nunca veredito de medição)."""
    workspace = tempfile.mkdtemp(prefix="journey-selftest-")
    _TEMPORARY.append(workspace)
    try:
        built = build_fixtures(workspace)
    except (InputError, OSError) as error:
        print(f"ERRO DE EXECUÇÃO: não montei os insumos sintéticos ({error})", file=sys.stderr)
        _cleanup()
        return EXIT_INPUT

    # Grupo 1: os quatro códigos de saída. Grupo 2: os dez controles de injeção que já existiam — as oito que
    # medem violação têm de continuar virando `1`, e `m5b`/`m10` continuam `0` (elas mexem em número cru e em
    # guarda de vacuidade, não em cláusula). "Só a cláusula-alvo muda" é conferido em `=FAIL` por saída.
    controls = [
        {"nome": "passe-limpo", "espera": EXIT_OK, "argv": ["--run", built["completo"]], "falhas": 0,
         "linha": "código de saída do insumo: 0 — todas as cláusulas aplicáveis medidas e PASS"},
        {"nome": "fora-de-escopo", "espera": EXIT_OK, "argv": ["--run", built["fora-de-escopo"]], "falhas": 0,
         "linha": "fora de escopo neste insumo: M3 (sem_sujeito)"},
        {"nome": "falha", "espera": EXIT_FAIL, "falhas": 1,
         "argv": ["--run", built["completo"], "--inject", "m2", "--out", os.path.join(workspace, "copia-falha-m2")],
         "linha": "código de saída do insumo: 1 — cláusula FAIL: M2"},
        {"nome": "entrada-sqlite-ilegivel", "espera": EXIT_INPUT, "argv": ["--run", built["sqlite-ilegivel"]],
         "falhas": None, "linha": "ERRO DE ENTRADA"},
        {"nome": "entrada-sem-artefato", "espera": EXIT_INPUT, "argv": ["--journey", built["vazio"]],
         "falhas": None, "linha": "ERRO DE ENTRADA"},
        {"nome": "entrada-inexistente", "espera": EXIT_INPUT, "argv": ["--run", os.path.join(workspace, "nao-existe")],
         "falhas": None, "linha": "ERRO DE ENTRADA"},
        {"nome": "entrada-argumentos", "espera": EXIT_INPUT, "falhas": None,
         "argv": ["--run", built["completo"], "--out", os.path.join(workspace, "sem-inject")],
         "linha": "só faz sentido com --inject"},
        {"nome": "lacuna", "espera": EXIT_INCOMPLETE, "argv": ["--run", built["lacuna"]], "falhas": 0,
         "linha": "código de saída do insumo: 3 — sem FAIL, mas cláusula aplicável não medida: M1 "
             "(evidencia_incompleta)"},
    ]
    for injection, clause, espera in (("m1", "M1", EXIT_FAIL), ("m2", "M2", EXIT_FAIL), ("m3a", "M3", EXIT_FAIL),
        ("m3b", "M3", EXIT_FAIL), ("m4", "M4", EXIT_FAIL), ("m5", "M5", EXIT_FAIL), ("m7", "M7", EXIT_FAIL),
        ("m7a", "M7", EXIT_FAIL), ("m5b", None, EXIT_OK), ("m10", None, EXIT_OK)):
        controls.append({"nome": f"injeção {injection}", "espera": espera, "falhas": 1 if clause else 0,
            "argv": ["--run", built["completo"], "--inject", injection, "--out",
                os.path.join(workspace, f"copia-{injection}")],
            "linha": f"cláusula FAIL: {clause}" if clause else "código de saída do insumo: 0"})

    observed: dict[str, int] = {}
    failures: list[str] = []
    for position, control in enumerate(controls):
        if position == 8:
            print("=" * 96)
            print("os dez controles de injeção que já existiam (nenhum pode ter mudado de veredito)")
            print("=" * 96)
        code, output = _control(control["argv"])
        observed[control["nome"]] = code
        line = next((row for row in output.splitlines() if control["linha"] in row), "")
        counted = output.count("=FAIL")
        good = code == control["espera"] and bool(line) \
            and (control["falhas"] is None or counted == control["falhas"])
        if not good:
            failures.append(control["nome"])
        print(f"controle `{control['nome']}`: esperado {control['espera']}, observado {code} — "
            f"{'OK' if good else 'FALHOU'}"
            + ("" if control["falhas"] is None else f" (cláusulas FAIL na saída: {counted}, "
                f"esperadas: {control['falhas']})"))
        print(f"  comando: {os.path.abspath(__file__)} {' '.join(control['argv'])}")
        print(f"  linha: {line if line else '(a linha esperada não apareceu)'}")
    for code in (EXIT_OK, EXIT_FAIL, EXIT_INPUT, EXIT_INCOMPLETE):
        names = [control for control in controls if control["espera"] == code]
        hits = sum(1 for control in names if observed[control["nome"]] == code)
        print(f"caminho {code}: {hits}/{len(names)} controles OK — "
            f"{', '.join(control['nome'] for control in names)}")
    print("controles: " + ("todos OK" if not failures else f"QUEBRARAM: {', '.join(failures)}"))
    _cleanup()
    return EXIT_OK if not failures else EXIT_FAIL


MEASUREMENTS = [measure_m1, measure_m2, measure_m3, measure_m4, measure_m5, measure_m7, measure_m10]

USAGE_EPILOG = """
o que cada medição mede:
  M1  abertura: a superfície desenhou vazio e depois conteúdo na MESMA geração (window.cards por geração).
  M2  primeira tela: toda carta publicada tem fonte e destino (source_id, primary_action_reference).
  M3  rolar: cada avanço atinge carta dentro da janela instalada, e um avanço forward não pousa atrás da posição
      observada anterior, dentro da mesma geração (advance.anchor/activity + admitted.head/tail).
  M4  rolar com trabalho de fundo: a janela instalada contém a âncora, não encolhe, a cauda não recua e não há
      buraco (admitted.cards/head/tail/anchor), na ordem do leitor da edição.
  M5  as imagens: cartas da janela instalada que declaram mídia e não têm o asset local. A pergunta visual
      (pixel desenhado) NÃO é medida: um arquivo presente pode falhar na decodificação (NOT_RUN).
  M7  fechar e reabrir: a âncora durável do contexto medido é a última âncora relatada, e a linha de sessão
      concorda com ela (position_checkpoint + context_checkpoints + session_checkpoint).
  M10 rolar rápido: a série de quadros, relatada SEM limiar (frames.*; guarda de vacuidade apenas).

sem evidência hoje: M1/M6 (superfície: vazio/fim declarados), M8 (rede bloqueada), M9 (conjunto congelado de
B01), M11 (bench/expand.py), M12 (instante de lançamento) e M7-pouso (tipo de admissão).

contratos de evidência: sem sujeito é NOT_RUN; zero violação sobre traço incompleto é NOT_RUN (o traço anuncia
suas perdas em `trace_truncated`); qualquer sub-fato não medido torna o agregado NOT_RUN.

código de saída (o que a automação lê):
  0  toda cláusula aplicável medida e PASS
  1  pelo menos uma cláusula FAIL
  2  erro de entrada ou execução — insumo inexistente, insumo sem artefato, SQLite ilegível, argumentos
     inválidos, injeção impossível. Nunca se confunde com falha de medição: não imprime veredito de cláusula
  3  sem FAIL, mas cláusula aplicável NOT_RUN (lacuna de medição)

aplicável x fora de escopo: cada sub-fato não medido traz um motivo. `sem_sujeito` (o insumo não tem o que
medir) e `nao_implementado` (nenhuma fonte de evidência existe, por desenho) são fora de escopo e NÃO forçam 3;
`evidencia_incompleta`, `nao_resolvido`, `nao_identificado` e `nao_comparavel` são lacuna de medição e forçam.
As cláusulas da lista "sem evidência hoje" são `nao_implementado`: continuam identificadas no relatório e no
bloco abaixo, **não** são medida deste instrumento e não são aprovação global de nada.

--selftest monta insumos sintéticos e roda os controles dos quatro códigos num processo por caminho; sai 0 se
todos valem, 1 se algum quebrou, 2 se não soube montar o insumo. --fixtures DIR monta os mesmos insumos num
diretório que fica, para rodar cada caminho à mão (sai 0 se montou, 2 se não pôde).

injeções (controle positivo, sempre numa cópia; `--out` precisa não existir ou estar vazio):
  m1  uma janela desenhada declara cards=0 no meio da geração
  m2  uma carta perde o destino (reference e kind em NULL)
  m3a a âncora de um avanço vai para uma carta fora da janela instalada
  m3b a âncora de um avanço forward vai para atrás da posição observada anterior
  m4  a primeira carta da janela instalada sai da série de admissão (a janela encolhe)
  m5  o asset local de uma carta da janela é apagado
  m5b uma carta com slot deixa de declarar mídia
  m7  a posição durável vira uma âncora relatada anterior
  m7a a posição durável vira uma carta que o app nunca relatou
  m10 a série de quadros sai do insumo
"""


def combined_exit(codes: list[int]) -> int:
    """Vários insumos: `FAIL` de qualquer um manda; depois lacuna; depois `0`."""
    if EXIT_FAIL in codes:
        return EXIT_FAIL
    return EXIT_INCOMPLETE if EXIT_INCOMPLETE in codes else EXIT_OK


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="journey.py",
        description="O instrumento de jornada: medições binárias lidas do traço do app e do console do aparelho.",
        epilog=USAGE_EPILOG, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--run", action="append", default=[], metavar="DIR",
        help="diretório de uma corrida do bench (bench/run/<stamp>)")
    parser.add_argument("--journey", action="append", default=[], metavar="DIR",
        help="diretório de uma jornada de aparelho (o --out de scripts/device-journey.sh)")
    parser.add_argument("--json", action="store_true", help="saída só em JSON")
    parser.add_argument("--series", action="store_true", help="imprime a série de quadros inteira")
    parser.add_argument("--inject", choices=INJECTIONS, metavar="NOME", help="injeta a violação NOME numa cópia")
    parser.add_argument("--out", metavar="DIR", help="destino da cópia injetada (exige --inject)")
    parser.add_argument("--selftest", action="store_true",
        help="roda os controles positivos dos quatro códigos de saída (0, 1, 2, 3)")
    parser.add_argument("--fixtures", metavar="DIR",
        help="monta os insumos sintéticos dos controles em DIR e imprime os caminhos")
    arguments = parser.parse_args(argv)
    if arguments.fixtures:
        if arguments.run or arguments.journey or arguments.inject or arguments.out or arguments.json:
            parser.error("--fixtures não combina com --run/--journey/--inject/--out/--json")
        try:
            built = build_fixtures(arguments.fixtures)
        except (InputError, OSError) as error:
            print(f"ERRO DE ENTRADA: {error}", file=sys.stderr)
            return EXIT_INPUT
        print(f"insumos sintéticos em {os.path.abspath(arguments.fixtures)} "
            "(controles; nenhum deles é medição de produto):")
        for name, path in built.items():
            print(f"  {name}: {path}")
        print("  os quatro caminhos de saída: --run completo (0) · --run completo --inject m2 --out DIR/copia (1) · "
            "--run nao-existe | --journey vazio | --run sqlite-ilegivel | --run completo --out DIR/x (2) · "
            "--run lacuna (3)")
        return EXIT_OK
    if arguments.selftest:
        if arguments.run or arguments.journey or arguments.inject or arguments.out or arguments.json:
            parser.error("--selftest não combina com --run/--journey/--inject/--out/--json")
        return selftest()
    if not arguments.run and not arguments.journey:
        parser.error("informe --run <bench/run/<stamp>> e/ou --journey <dir>")
    if arguments.inject and not arguments.out:
        parser.error("--inject exige --out <DIR>")
    if arguments.out and not arguments.inject:
        parser.error("--out só faz sentido com --inject")

    payload = []
    codes: list[int] = []
    reasons: list[str] = []
    try:
        for kind, paths in (("corrida", arguments.run), ("jornada", arguments.journey)):
            for path in paths:
                if not os.path.isdir(path):
                    raise InputError(f"{path} não é um diretório: insumo inexistente")
                try:
                    ins = Insumo(path, kind)
                    if arguments.inject:
                        changed = inject(ins, arguments.inject, arguments.out)
                        print("=" * 96)
                        print(f"injeção {arguments.inject} em {arguments.out} (o original {ins.path} não foi tocado)")
                        print("=" * 96)
                        print("\n".join(changed))
                        print()
                        ins = Insumo(arguments.out, kind)
                    results = [measure(ins) for measure in MEASUREMENTS]
                    payload.append({"insumo": ins.provenance(), "medicoes": results,
                        "sem_evidencia_hoje": NOT_RUN_MEASUREMENTS,
                        "codigo_de_saida": exit_code_of(results),
                        "razao_do_codigo": exit_reason(results)})
                    if not arguments.json:
                        print(render(ins, results, series_of(ins) if arguments.series else None))
                    codes.append(exit_code_of(results))
                    reasons.append(f"{ins.path}: {exit_reason(results)}")
                finally:
                    _cleanup()
    except InputError as error:
        print(f"ERRO DE ENTRADA: {error}", file=sys.stderr)
        return EXIT_INPUT
    except Exception as error:
        # Leitura ou execução que não completou é código 2 — nunca 1, que afirmaria violação medida.
        print(f"ERRO DE EXECUÇÃO: {type(error).__name__}: {error}", file=sys.stderr)
        return EXIT_INPUT
    if arguments.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    exit_code = combined_exit(codes)
    if not arguments.json:
        print(f"código de saída do processo: {exit_code} — " + " | ".join(reasons))
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
