#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scripts/hitch-join.py — junta **por segundo** a série de quadros, a linha de jornada e o traço do app, e diz
o que estava acontecendo na janela em que o quadro travou.

Para que este arquivo existe, e o que ele **não** é
-----------------------------------------------
O relato do dono ("engasgos reais durante a rolagem") e a série crua da jornada de 2026-10-16 dizem *quando* o
quadro atrasou: `docs/reviews/2026-10-16-build-48-aparelho-e-publicacao.md` §2.2 encerra com "sem correlação não há
causa". Este instrumento é a associação temporal que falta: para cada segundo com quadro severo, ele imprime, lado
a lado e com o `arquivo:linha` de origem,

  (a) o intervalo monotônico e a duração do quadro (medido pelo próprio app);
  (b) a posição e o movimento do leitor naquele intervalo;
  (c) o estado da janela admitida;
  (d) o trabalho de aquisição/publicação/mídia no intervalo;
  (e) evidência de pressão do sistema **quando a captura a carrega** — e a declaração explícita quando não carrega.

Ele **não** decide causa: nenhuma cláusula daqui compara a razão fora do orçamento contra um número escolhido, e
não existe veredito de fluidez. A seleção de janelas usa o vocabulário do **próprio medidor** do app (`severe` =
três orçamentos ou mais, `FeedMineApp/FeedMineApp/FeedFrameMeter.swift`), não um teto inventado — `--select`
escolhe qual balde do medidor abre a janela, e os totais de todos os baldes são impressos junto.

Relação com `bench/journey.py` (branch `instruments/journey-measurements`, `870634c3`)
----------------------------------------------------------------------------------------
Aquele instrumento responde perguntas **binárias** sobre um insumo inteiro (M1..M12, `bench/journey.py:486` para
M4 "rolar com trabalho de fundo", `:650` para M10 "a série de quadros, relatada"). Este aqui não repete nenhuma
delas e não emite veredito: ele responde uma pergunta que aquelas não fazem — *o que estava em curso no segundo em
que o quadro travou* — e devolve as linhas cruas para que a resposta seja conferível. Onde os dois olham o mesmo
fato (a série de `frames`), o número é o mesmo porque a fonte é a mesma (o traço do app e as linhas
`feedmine frames=` do console do aparelho); M10 agrega e julga, este imprime a janela.

As três fontes, e por que a chave de junção é o **ordinal**, não o relógio
-------------------------------------------------------------------------
  * **console** (`scripts/device-journey.sh` / `scripts/hitch-pass.sh`): uma linha por segundo, com carimbo de
    relógio do aparelho —
    `2026-10-16 00:51:12.355 FeedMine[7062:1309677] feedmine frames=1 late=1 bad=0 severe=0 worst_ms=25.3`
    e, sob `FEEDMINE_JOURNEY_CONSOLE=1`, `feedmine journey t=<s> cards=… media_prepared=… sources_responded=…`
    (`FeedMineApp/FeedMineApp/RunwayTrace.swift`, `enum FeedJourneyConsole`).
  * **traço do app** (`container/.../FeedMine/<ns>/trace.jsonl`, objeto por linha):
    `{"at": <epoch>, "mono": <sistema ligado>, "event": "...", "fields": {...}}` — é ele que diz posição
    (`advance`), janela (`window`, `admitted`), mídia (`candidate`/`suspended`, `media_ready`), reposição
    (`replenishment_requested|arrived|concluded`) e posição durável (`position_checkpoint`).
  * **série publicada pelo app** (anexo do XCTest `scroll-journey-frame-series`, o
    `after=budget_ms=…;seconds=N;series=a/b/c/d/worst|…` de `FluidityJourneyUITests.swift`): a série **sem** o
    console, que é o que existe quando a corrida perdeu o console (medido em 2026-10-16).

Os três carregam uma contagem de segundos que **o próprio app mantém** (o `t=` da linha de jornada, o `seconds=`
da série, o índice do k-ésimo evento `frames` do traço, todos do mesmo tique de `FeedFrameMeter`). Por isso a
junção é por **ordinal** e o relógio entra como conferência, nunca como chave: o console diz a hora local do
aparelho sem fuso, e uma junção por relógio dependeria de o host e o aparelho concordarem sobre o fuso — o que não
é um fato medido. Cada janela imprime o ordinal, o `mono`, o `at` (UTC) e o carimbo do console verbatim, então a
associação é auditável linha a linha.

Não-vacuidade: quando uma dimensão não tem insumo, ela diz `NOT_AVAILABLE` **com o nome do arquivo que falta** —
nunca um valor derivado de outro campo parecido. E o que não é por segundo (o estado do banco, a mídia no disco)
sai numa seção separada e rotulada, porque atribuí-lo a um segundo seria inventar.

Uso
---
    python3 scripts/hitch-join.py --journey /tmp/fm-hitch-pass-<stamp>
    python3 scripts/hitch-join.py --console /tmp/console-journey.log --trace <card>/trace.jsonl --db <card>/runtime.sqlite
    python3 scripts/hitch-join.py --series /tmp/int48-physical-evidence/62CB9727-….txt
    python3 scripts/hitch-join.py --journey <dir> --select bad --context 2 --json

Saída: um bloco por insumo, com proveniência (caminho, sha256, contagens e o que faltou) e uma entrada por janela
selecionada. Exit 0 quando imprimiu; exit 1 quando não havia nada mensurável; exit 2 para uso recusado.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sqlite3
import sys
import tempfile
from datetime import datetime, timezone

# --------------------------------------------------------------------------------------------------------------
# Vocabulário de leitura (nenhum destes é critério: a seleção usa os baldes do medidor do app)

# `FeedMineApp/FeedMineApp/FeedFrameMeter.swift` — a linha do console, uma por segundo. `budget_ms` passou a ser
# impresso junto quando o orçamento virou o do próprio display; a captura antiga não o traz, então é opcional.
FRAMES_RE = re.compile(
    r"feedmine frames=(?P<frames>\d+) late=(?P<late>\d+) bad=(?P<bad>\d+) severe=(?P<severe>\d+) "
    r"worst_ms=(?P<worst>[0-9.]+)(?: budget_ms=(?P<budget>[0-9.]+))?")

# `enum FeedJourneyConsole` (`RunwayTrace.swift`) — `t=<s>s` é o ordinal do próprio app.
JOURNEY_RE = re.compile(r"feedmine journey (?P<body>.+)$")

# A série publicada: `budget_ms=16.67;seconds=27;series=49/0/0/3/128.5|45/0/0/2/213.6|…`
SERIES_RE = re.compile(r"budget_ms=(?P<budget>[0-9.]+);seconds=(?P<seconds>\d+);series=(?P<entries>.*)$")

# O carimbo que precede a linha: `devicectl --console` e o NSLog do aparelho (`YYYY-MM-DD HH:MM:SS.mmm`), e o
# formato do `idevicesyslog` (`Mon DD HH:MM:SS[.ffffff][±zzzz]`). Nenhum dos dois é usado como chave (ver o
# cabeçalho) — ele é impresso verbatim.
CLOCK_PREFIX_RE = re.compile(
    r"^(?P<clock>(?:\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{4})?)"
    r"|[A-Z][a-z]{2} +\d{1,2} \d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{4})?)")

# O relógio do aparelho, como **hora do dia em segundos**. Nenhum fuso é aplicado: todas as linhas de um console
# vêm do mesmo relógio, então a diferença entre duas delas é um intervalo real, e é isso que se usa. A conversão
# para epoch só é tentada na conferência contra o traço, e aí o palpite de fuso é declarado.
HMS_RE = re.compile(r"(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d+))?")

# O que o app escreve no **log unificado** (`Logger(subsystem:category:)`, não `NSLog`): `[composition]`, o avanço do
# leitor e o trabalho de fundo por segundo. Numa jornada física ele não aparece em `devicectl --console` (medido:
# 605 linhas de console, nenhuma `[composition]`) e aparece no syslog do sistema — é por isso que a corrida física
# precisa das duas capturas.
APP_NOTE_MARKERS = ("[composition]", "Runway opportunity", "viewport forwarded",
                    "viewport opportunity", "published growth", "rendered position", "cold bootstrap",
                    "local restore", "early publication", "obsolete viewport", "settled position",
                    "install attempt", "install accept", "window proof")


def is_app_note(line: str) -> bool:
    """Uma linha do app no console: ou o emissor é o próprio FeedMine, ou o texto é de um dono que só ele escreve.

    O nome do processo é checado porque o host também imprime `com.feedmine.development` em linhas suas
    ("Launched application with … bundle identifier") — casar a palavra `feedmine` no texto puro tomaria uma linha
    do host por uma linha do app.
    """
    if re.search(r"\bFeedMine(?:\(|\[)", line):
        return True
    return any(marker in line for marker in APP_NOTE_MARKERS)

# Os eventos do traço que falam de **posição e movimento** e os que falam de **trabalho de fundo**. A lista é o
# contrato do que este instrumento sabe atribuir a um segundo; evento fora dela é contado em "outros do traço" para
# não sumir em silêncio.
POSITION_EVENTS = ("advance", "runway_completed", "position_checkpoint", "position_kept_exact", "window")
WORK_EVENTS = ("admitted", "candidate", "suspended", "media_ready", "replenishment_requested",
               "replenishment_arrived", "replenishment_concluded", "answer_applied", "answer_failed",
               "editorial_offer", "editorial_refusal", "trace_truncated")

# Vocabulário de pressão do sistema: o que um console de aparelho pode carregar e que indica que o travamento
# pode ser do sistema. Ausência **não** é prova de ausência — o texto abaixo é explícito sobre isso.
PRESSURE_TERMS = ("malloc", "memory warning", "low memory", "jetsam", "highwater", "thermal", "watchdog",
                  "hang", "stuck", "no space", "enospc", "disk", "signal", "terminated due to",
                  "acquired tunnel", "usage assertion", "coredeviceerror", "respring", "spinlock")


def sha256_file(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def iso(epoch: float | None) -> str | None:
    if epoch is None:
        return None
    return datetime.fromtimestamp(epoch, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def as_int(value) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def as_float(value) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def time_of_day(text: str) -> float | None:
    """A hora do dia das linhas do console, em segundos — a chave que atribui uma linha ao segundo em que ela saiu.

    Só a **diferença** entre duas linhas do mesmo console é usada, então o fuso nunca entra na conta.
    """
    match = CLOCK_PREFIX_RE.match(text)
    if not match:
        return None
    stamp = HMS_RE.search(match.group("clock"))
    if not stamp:
        return None
    hours, minutes, seconds, fraction = stamp.groups()
    return int(hours) * 3600 + int(minutes) * 60 + int(seconds) + (float("0." + fraction) if fraction else 0.0)


# --------------------------------------------------------------------------------------------------------------
# As janelas


class Window:
    """Um segundo medido. `index` é o ordinal do app (1 = primeiro segundo desenhado)."""

    def __init__(self, index: int):
        self.index = index
        self.frames: int | None = None
        self.late: int | None = None
        self.bad: int | None = None
        self.severe: int | None = None
        self.worst_ms: float | None = None
        self.budget_ms: float | None = None
        self.worst_at: float | None = None
        self.mono: float | None = None
        self.at: float | None = None
        self.frames_origin: str | None = None       # `arquivo:linha` da linha crua do quadro
        self.clock: str | None = None               # carimbo verbatim do console
        self.day: float | None = None               # hora do dia do carimbo, em segundos (só diferenças importam)
        self.pressure: list[tuple[int, str]] = []   # linhas do console desta janela no vocabulário de pressão
        self.notes_app: list[tuple[int, str]] = []  # linhas do app desta janela (log unificado, não o NSLog)
        self.notes_other = 0                        # linhas de outros processos nesta janela (só contadas)
        self.journey: dict | None = None
        self.journey_line: str | None = None
        self.journey_origin: str | None = None
        self.events: list[tuple[int, dict]] = []    # (linha do traço, evento de fora do balde `frames`)

    @property
    def off_budget(self) -> int:
        return (self.late or 0) + (self.bad or 0) + (self.severe or 0)

    def as_dict(self) -> dict:
        return {"index": self.index, "frames": self.frames, "late": self.late, "bad": self.bad,
                "severe": self.severe, "worst_ms": self.worst_ms, "budget_ms": self.budget_ms,
                "worst_at": self.worst_at, "mono": self.mono, "at": iso(self.at),
                "clock": self.clock, "frames_origin": self.frames_origin,
                "console_pressao": [{"linha": number, "texto": text} for number, text in self.pressure],
                "console_do_app": [{"linha": number, "texto": text} for number, text in self.notes_app],
                "console_de_outros": self.notes_other,
                "journey": self.journey, "journey_origin": self.journey_origin,
                "events": [{"trace_line": line, "event": event.get("event"), "fields": event.get("fields"),
                            "at": iso(event.get("at")), "mono": event.get("mono")} for line, event in self.events]}


# --------------------------------------------------------------------------------------------------------------
# As fontes


class Console:
    """As linhas `feedmine frames=` e `feedmine journey` de um log de console, com a linha de origem."""

    def __init__(self, path: str):
        self.path = path
        self.frames: list[tuple[int, str, dict]] = []   # (linha, texto cru, campos)
        self.journey: list[tuple[int, str, dict]] = []   # idem, em ordem de arquivo (o tique é o mesmo dos quadros)
        self.journey_without_t = 0
        self.pressure: list[tuple[int, str]] = []
        self.other: list[tuple[int, str]] = []
        self.invalid = 0
        with open(path, encoding="utf-8", errors="replace") as handle:
            for number, raw in enumerate(handle, start=1):
                line = raw.rstrip("\n")
                match = FRAMES_RE.search(line)
                if match:
                    self.frames.append((number, line, match.groupdict()))
                    continue
                match = JOURNEY_RE.search(line)
                if match:
                    fields = dict(part.split("=", 1) for part in match.group("body").split() if "=" in part)
                    if as_int(str(fields.get("t", "")).rstrip("s")) is None:
                        self.journey_without_t += 1
                    self.journey.append((number, line, fields))
                    continue
                lowered = line.lower()
                if any(term in lowered for term in PRESSURE_TERMS):
                    self.pressure.append((number, line))
                elif line.strip():
                    self.other.append((number, line))

    def clock_of(self, line: str) -> str | None:
        match = CLOCK_PREFIX_RE.match(line)
        return match.group("clock") if match else None


class Series:
    """O anexo do XCTest: a série que o app publicou, lida do rótulo `feed-frame-proof`."""

    def __init__(self, path: str):
        self.path = path
        self.windows: list[Window] = []
        self.cards: dict[str, str] = {}
        self.budget_ms: float | None = None
        self.seconds: int | None = None
        self.line_of_series: int | None = None
        best: tuple[int, str, dict] | None = None
        with open(path, encoding="utf-8", errors="replace") as handle:
            for number, raw in enumerate(handle, start=1):
                line = raw.rstrip("\n")
                if line.startswith("initial_card="):
                    self.cards["initial"] = line.split("=", 1)[1].strip()
                    continue
                if line.startswith("final_card="):
                    self.cards["final"] = line.split("=", 1)[1].strip()
                    continue
                match = SERIES_RE.search(line)
                if not match:
                    continue
                groups = match.groupdict()
                # `before=` e `after=` são a MESMA série em dois instantes: vale a que mediu mais segundos.
                if best is None or int(groups["seconds"]) > int(best[2]["seconds"]):
                    best = (number, line, groups)
        if best is None:
            return
        number, line, groups = best
        self.line_of_series = number
        self.budget_ms = as_float(groups["budget"])
        self.seconds = as_int(groups["seconds"])
        entries = [entry for entry in groups["entries"].split("|") if entry.strip()]
        first = self.seconds - len(entries) + 1
        for offset, entry in enumerate(entries):
            parts = entry.split("/")
            if len(parts) != 5:
                continue
            window = Window(first + offset)
            window.budget_ms = self.budget_ms
            window.frames = as_int(parts[0])
            window.late = as_int(parts[1])
            window.bad = as_int(parts[2])
            window.severe = as_int(parts[3])
            window.worst_ms = as_float(parts[4])
            window.frames_origin = f"{os.path.basename(self.path)}:{number} ({'after' if line.startswith('after=') else 'before'}=#{window.index})"
            self.windows.append(window)


class Trace:
    """O `trace.jsonl` do app, com a linha de origem de cada evento."""

    def __init__(self, path: str):
        self.path = path
        self.events: list[tuple[int, dict]] = []
        self.invalid = 0
        with open(path, encoding="utf-8", errors="replace") as handle:
            for number, raw in enumerate(handle, start=1):
                line = raw.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    self.invalid += 1
                    continue
                if not isinstance(event, dict) or "event" not in event:
                    self.invalid += 1
                    continue
                self.events.append((number, event))

    def of(self, name: str) -> list[tuple[int, dict]]:
        return [item for item in self.events if item[1].get("event") == name]

    def losses(self) -> dict | None:
        notices = [event for _, event in self.of("trace_truncated")]
        if not notices:
            return None
        last = notices[-1].get("fields") or {}
        return {"anúncios": len(notices), "escrito": as_int(last.get("written")),
                "teto": as_int(last.get("ceiling")), "perdidos_pelo_teto": as_int(last.get("dropped_by_ceiling")),
                "perdidos_pela_escrita": as_int(last.get("dropped_by_write"))}


class Cards:
    """A ordem em que o leitor percorre o feed e o nome das fontes — do banco, lido **numa cópia**."""

    def __init__(self, path: str):
        self.path = path
        self.position: dict[str, int] = {}
        self.segment_ordinal: dict[str, int] = {}
        self.card_ordinal: dict[str, int] = {}
        self.source: dict[str, str] = {}
        self.layout: dict[str, str] = {}
        self.media_key: dict[str, str] = {}
        self.total = 0
        workspace = tempfile.mkdtemp(prefix="hitch-db-")
        copy = os.path.join(workspace, "runtime.sqlite")
        try:
            # Copiar primeiro, ler depois: abrir o SQLite no lugar cria `-shm`/`-wal` ao lado dele (medido: suja a
            # árvore de quem lê), e ler com `immutable=1` ignora o WAL — o que faz a posição parecer mais velha.
            shutil.copy2(path, copy)
            for suffix in ("-wal", "-shm"):
                if os.path.exists(path + suffix):
                    shutil.copy2(path + suffix, copy + suffix)
            connection = sqlite3.connect(f"file:{copy}?mode=ro", uri=True)
            try:
                rows = connection.execute(
                    "SELECT LOWER(c.id) AS id, COALESCE(s.ordinal, 4294967295) AS seg, c.ordinal AS ord, "
                    "       COALESCE(c.source_display_name, '') AS source, COALESCE(c.render_layout, '') AS layout, "
                    "       COALESCE(c.media_key, '') AS media "
                    "FROM published_cards c LEFT JOIN feed_segments s ON s.id = c.segment_id "
                    "ORDER BY seg, ord, c.segment_id").fetchall()
            finally:
                connection.close()
            for index, row in enumerate(rows):
                card = row[0]
                self.position[card] = index
                self.segment_ordinal[card] = row[1]
                self.card_ordinal[card] = row[2]
                self.source[card] = row[3]
                self.layout[card] = row[4]
                self.media_key[card] = row[5]
            self.total = len(rows)
        except sqlite3.Error:
            self.position = {}
        finally:
            shutil.rmtree(workspace, ignore_errors=True)

    def where(self, card_id: str | None) -> str:
        """A carta em termos do leitor: `pos <i> (seg <s>, carta <c>)`, ou o UUID cru quando não resolvida."""
        if not card_id:
            return "?"
        key = card_id.lower()
        if key in self.position:
            return (f"pos {self.position[key]} (seg {self.segment_ordinal[key]}, carta {self.card_ordinal[key]}"
                    + (f", {self.source[key]}" if self.source[key] else "") + ")")
        return f"{card_id} (fora do banco final)"


def find_files(root: str) -> dict:
    """O que um diretório de jornada traz: console, traço, banco e a série publicada."""
    found = {"consoles": [], "traces": [], "databases": [], "series": []}
    for directory, _, names in os.walk(root):
        for name in sorted(names):
            path = os.path.join(directory, name)
            if name.endswith(".log") or name == "console.log":
                found["consoles"].append(path)
            elif name == "trace.jsonl":
                found["traces"].append(path)
            elif name.endswith(".sqlite") and not name.endswith("-wal") and not name.endswith("-shm"):
                found["databases"].append(path)
            elif name.endswith(".txt"):
                with open(path, encoding="utf-8", errors="replace") as handle:
                    head = handle.read(4096)
                if "series=" in head:
                    found["series"].append(path)
    return found


# --------------------------------------------------------------------------------------------------------------
# A junção


class Joined:
    """Um insumo com as três fontes já associadas por ordinal."""

    def __init__(self, title: str):
        self.title = title
        self.windows: list[Window] = []
        self.console: Console | None = None
        self.trace: Trace | None = None
        self.series: Series | None = None
        self.cards: Cards | None = None
        self.missing: list[str] = []
        self.notes: list[str] = []
        self.beyond: list[tuple[int, dict]] = []

    # -- construção ---------------------------------------------------------------------------------------------
    def build(self) -> None:
        axis = "console"
        if self.console and self.console.frames:
            self.windows = []
            for index, (number, line, groups) in enumerate(self.console.frames, start=1):
                window = Window(index)
                window.frames = as_int(groups["frames"])
                window.late = as_int(groups["late"])
                window.bad = as_int(groups["bad"])
                window.severe = as_int(groups["severe"])
                window.worst_ms = as_float(groups["worst"])
                window.budget_ms = as_float(groups["budget"])
                window.frames_origin = f"{os.path.basename(self.console.path)}:{number}"
                window.clock = self.console.clock_of(line)
                window.day = time_of_day(line)
                self.windows.append(window)
        elif self.series and self.series.windows:
            axis = "série publicada"
            self.windows = [Window(window.index) for window in self.series.windows]
            for window, source in zip(self.windows, self.series.windows):
                window.frames = source.frames
                window.late = source.late
                window.bad = source.bad
                window.severe = source.severe
                window.worst_ms = source.worst_ms
                window.budget_ms = source.budget_ms
                window.frames_origin = source.frames_origin
        elif self.trace and self.trace.of("frames"):
            axis = "traço"
            for index, (number, event) in enumerate(self.trace.of("frames"), start=1):
                fields = event.get("fields") or {}
                window = Window(index)
                window.frames = as_int(fields.get("frames"))
                window.late = as_int(fields.get("late"))
                window.bad = as_int(fields.get("bad"))
                window.severe = as_int(fields.get("severe"))
                window.worst_ms = as_float(fields.get("worst_ms"))
                window.budget_ms = as_float(fields.get("budget_ms"))
                window.worst_at = as_float(fields.get("worst_at"))
                window.mono = as_float(event.get("mono"))
                window.at = as_float(event.get("at"))
                window.frames_origin = f"{os.path.basename(self.trace.path)}:{number}"
                self.windows.append(window)
        else:
            self.missing.append("nenhuma série de quadros: nem `feedmine frames=` no console, nem o anexo "
                                "`after=…;series=…`, nem evento `frames` no traço")
            return
        self.notes.append(f"eixo dos segundos: {axis} ({len(self.windows)} janelas)")

        # O ordinal é a chave. O que vem de outra fonte é anexado **por ordinal** e a discordância é medida.
        if axis != "console" and self.console and self.console.frames:
            self.notes.append(f"console com {len(self.console.frames)} linhas `feedmine frames=` não usado como eixo")
        if axis != "traço" and self.trace and self.trace.of("frames"):
            rows = self.trace.of("frames")
            shared = min(len(rows), len(self.windows))
            # O alinhamento não é presumido: ele é CONFERIDO campo a campo nos segundos que os dois insumos têm em
            # comum. Numa corrida real as contagens discordam (medido em 2026-10-16: 299 linhas de console contra
            # 260 eventos `frames`, porque o último lote do traço não chegou ao disco — o app foi encerrado sem
            # `flush`), e um alinhamento por prefixo só vale se os números concordarem no prefixo.
            mismatches = []
            for index in range(shared):
                window, (_, event) = self.windows[index], rows[index]
                fields = event.get("fields") or {}
                for name, mine, theirs in (("frames", window.frames, as_int(fields.get("frames"))),
                                           ("late", window.late, as_int(fields.get("late"))),
                                           ("bad", window.bad, as_int(fields.get("bad"))),
                                           ("severe", window.severe, as_int(fields.get("severe"))),
                                           ("worst_ms", window.worst_ms, as_float(fields.get("worst_ms")))):
                    if mine is not None and theirs is not None and mine != theirs:
                        mismatches.append((index + 1, name, mine, theirs))
            if mismatches:
                first = mismatches[0]
                self.notes.append(f"ALINHAMENTO RECUSADO: console e traço discordam em {len(mismatches)} campos nos "
                                  f"{shared} segundos em comum (primeira discordância na janela {first[0]}: "
                                  f"{first[1]} = {first[2]} no console contra {first[3]} no traço) — nenhum relógio "
                                  "do traço foi anexado, porque duas séries que discordam não são a mesma série")
            else:
                for index in range(shared):
                    window = self.windows[index]
                    fields = rows[index][1].get("fields") or {}
                    window.mono = as_float(rows[index][1].get("mono"))
                    window.at = as_float(rows[index][1].get("at"))
                    window.worst_at = as_float(fields.get("worst_at"))
                    if window.budget_ms is None:
                        window.budget_ms = as_float(fields.get("budget_ms"))
                self.notes.append(f"alinhamento console × traço CONFERIDO campo a campo em {shared} segundos "
                                  f"(frames/late/bad/severe/worst_ms concordam; o relógio do traço entra pela "
                                  f"posição, não por suposição)")
                if len(rows) != len(self.windows):
                    if len(rows) < len(self.windows):
                        self.notes.append(f"o traço cobre os primeiros {len(rows)} de {len(self.windows)} segundos: "
                                          f"as janelas {len(rows) + 1}..{len(self.windows)} existem no console e não "
                                          "no traço (último lote perdido no encerramento, ou traço truncado — ver "
                                          "`trace_truncated` no próprio traço)")
                    else:
                        self.notes.append(f"o traço tem MAIS segundos ({len(rows)}) do que o console "
                                          f"({len(self.windows)}): o eixo é o console e o excedente do traço não "
                                          "foi usado")

        # A linha de jornada sai do MESMO tique que a linha `feedmine frames=`, então ela é anexada por posição; o
        # `t=` que ela carrega é conferido contra a posição e o resultado é dito — uma corrida em que o app pula um
        # segundo aparece aqui em vez de deslocar a série em silêncio (medido em 2026-10-16: `t=193s` ausente).
        if self.console and self.console.journey:
            entries = self.console.journey
            if len(entries) == len(self.windows):
                skips: list[str] = []
                for index, (number, line, fields) in enumerate(entries):
                    window = self.windows[index]
                    window.journey = fields
                    window.journey_line = line
                    window.journey_origin = f"{os.path.basename(self.console.path)}:{number}"
                    moment = as_int(str(fields.get("t", "")).rstrip("s"))
                    if moment is not None and moment != index:
                        skips.append(f"posição {index + 1} diz t={moment}")
                detail = ("as linhas de jornada e as de quadro têm a mesma contagem e saem do mesmo tique"
                          if not skips else
                          "o ordinal é a POSIÇÃO e o `t=` do app discorda em " + ", ".join(skips[:3])
                          + (f" (e mais {len(skips) - 3} posições)" if len(skips) > 3 else
                             " — o app pulou o(s) segundo(s) que faltam; o `t=` de cada janela é impresso abaixo"))
                self.notes.append("linhas de jornada anexadas por posição: " + detail)
            else:
                for number, line, fields in entries:
                    moment = as_int(str(fields.get("t", "")).rstrip("s"))
                    if moment is None or not (1 <= moment + 1 <= len(self.windows)):
                        continue
                    window = self.windows[moment]     # `t=0s` é a janela #1
                    window.journey = fields
                    window.journey_line = line
                    window.journey_origin = f"{os.path.basename(self.console.path)}:{number}"
                self.notes.append(f"linhas de jornada anexadas pelo `t=` do app: {len(entries)} linhas contra "
                                  f"{len(self.windows)} janelas de quadro — as contagens discordam, então a posição "
                                  "não é usada como chave")
            if self.console.journey_without_t:
                self.notes.append(f"{self.console.journey_without_t} linhas de jornada sem `t=` legível")

        # Eventos do traço: cada um cai na janela cujo intervalo monotônico o contém — o evento `frames` da janela
        # k fecha o intervalo (mono_k), então a janela k é (mono_{k-1}, mono_k]. Eventos depois do último segundo
        # com relógio (a cauda que o traço cobre e o console não) são separados, não jogados na última janela.
        if self.trace:
            stamped = [window for window in self.windows if window.mono is not None]
            self.beyond = []
            if stamped:
                cursor = 0
                for number, event in self.trace.events:
                    if event.get("event") == "frames":
                        continue
                    moment = as_float(event.get("mono"))
                    if moment is None:
                        continue
                    while cursor < len(stamped) - 1 and moment > (stamped[cursor].mono or 0):
                        cursor += 1
                    if moment > (stamped[cursor].mono or 0):
                        self.beyond.append((number, event))
                    else:
                        stamped[cursor].events.append((number, event))
                if self.beyond:
                    self.notes.append(f"{len(self.beyond)} eventos do traço estão depois do último segundo que o "
                                      "eixo das janelas cobre: eles saem em uma seção própria, porque atribuí-los à "
                                      "última janela seria inventar o instante")
            else:
                self.notes.append(f"ATRIBUIÇÃO: nenhuma janela tem relógio monotônico, então os "
                                  f"{len([event for _, event in self.trace.events if event.get('event') != 'frames'])} "
                                  "eventos do traço não foram atribuídos a nenhum segundo — sem um evento `frames` "
                                  "por janela não existe eixo de tempo do traço")

        # As linhas do console que **não** são a série de quadros nem a linha de jornada: cada uma cai na janela
        # cujo intervalo de relógio a contém (a janela k termina no carimbo da k-ésima linha `frames=`), e a
        # atribuição por ordem de linha é o recurso quando algum carimbo não é legível. É por aqui que o log
        # unificado do app (`[composition] …`, `viewport forwarded …`) entra na janela — o que `devicectl --console`
        # não traz numa jornada física (medido: 605 linhas de console, nenhuma `[composition]`).
        if self.console and axis == "console" and self.windows:
            days = [window.day for window in self.windows]
            leftovers = sorted(self.console.pressure + self.console.other, key=lambda item: item[0])
            stops = [number for number, _, _ in self.console.frames]
            unattributed = 0
            cursor = 0
            for number, line in leftovers:
                window = None
                day = time_of_day(line)
                if all(value is not None for value in days) and day is not None:
                    while cursor < len(self.windows) - 1 and day > (days[cursor] or 0):
                        cursor += 1
                    window = self.windows[cursor]
                else:
                    for index, stop in enumerate(stops):
                        if number <= stop:
                            window = self.windows[index]
                            break
                if window is None:
                    unattributed += 1
                    continue
                if any(term in line.lower() for term in PRESSURE_TERMS):
                    window.pressure.append((number, line))
                elif is_app_note(line):
                    window.notes_app.append((number, line))
                else:
                    window.notes_other += 1
            lines = [f"linhas do console atribuídas entre a (k−1)-ésima e a k-ésima `feedmine frames=` "
                     f"(`k` = ordinal do app) — quando todos os carimbos são legíveis a atribuição é por carimbo, "
                     f"senão por ordem de linha (medido: {len(leftovers)} linhas, {unattributed} não atribuídas)"]
            if any(day is None for day in days):
                lines.append("AVISO: alguma linha `feedmine frames=` não tem carimbo legível neste console")
            self.notes.extend(lines)

        # A conferência que o cabeçalho promete: a junção é por ordinal, e o relógio entra como teste. O carimbo do
        # console não tem fuso; converter para epoch exige supor que o aparelho e esta máquina estão no mesmo fuso,
        # e é isso que a linha abaixo mede **e declara como suposição**.
        if self.console and self.trace and len(self.windows) == len(self.trace.of("frames")):
            skews = []
            for window in self.windows:
                if window.day is None or window.at is None:
                    continue
                local = datetime.fromtimestamp(window.at, tz=timezone.utc)
                printed = local.hour * 3600 + local.minute * 60 + local.second + local.microsecond / 1e6
                skew = window.day - printed
                skews.append(skew - 86400 if skew > 43200 else (skew + 86400 if skew < -43200 else skew))
            if skews:
                skews.sort()
                self.notes.append("conferência relógio × ordinal (com o eixo UTC do traço lido como se estivesse no "
                                  f"fuso LOCAL desta máquina — SUPOSIÇÃO): desvio mediano {skews[len(skews)//2]:+.3f} s, "
                                  f"mínimo {skews[0]:+.3f} s, máximo {skews[-1]:+.3f} s em {len(skews)} janelas — "
                                  "um desvio constante do tamanho do fuso significa que a suposição está errada e a "
                                  "junção por ordinal está certa do mesmo jeito")

    # -- consultas ----------------------------------------------------------------------------------------------
    def selected(self, which: str) -> list[Window]:
        if which == "severe":
            return [window for window in self.windows if (window.severe or 0) > 0]
        if which == "bad":
            return [window for window in self.windows if (window.bad or 0) > 0]
        if which == "late":
            return [window for window in self.windows if (window.late or 0) > 0]
        return [window for window in self.windows if window.off_budget > 0]

    def totals(self) -> dict:
        def total(key) -> int:
            return sum((getattr(window, key) or 0) for window in self.windows)
        worst = max([window.worst_ms for window in self.windows if window.worst_ms is not None], default=None)
        return {"janelas": len(self.windows), "quadros": total("frames"), "late": total("late"),
                "bad": total("bad"), "severe": total("severe"), "pior_ms": worst,
                "segundos_com_severe": sum(1 for window in self.windows if (window.severe or 0) > 0),
                "segundos_com_bad": sum(1 for window in self.windows if (window.bad or 0) > 0),
                "segundos_com_late": sum(1 for window in self.windows if (window.late or 0) > 0)}

    def admitted_before(self, window: Window) -> tuple[int, dict] | None:
        """O último `admitted` anterior ao fim da janela — inclui os eventos dentro dela."""
        if window.mono is None:
            return None
        found = None
        for number, event in self.trace.events:
            if event.get("event") != "admitted":
                continue
            moment = as_float(event.get("mono"))
            if window.mono is not None and moment is not None and moment > window.mono:
                break
            found = (number, event)
        return found


# --------------------------------------------------------------------------------------------------------------
# Impressão


def event_line(trace: Trace | None, number: int, event: dict) -> str:
    origin = f"{os.path.basename(trace.path)}:{number}" if trace else "?"
    fields = event.get("fields") or {}
    rendered = " ".join(f"{key}={value}" for key, value in fields.items())
    mono = event.get("mono")
    return (f"    [{origin}] mono={mono:.3f} at={iso(event.get('at'))} {event.get('event')}"
            + (f" {rendered}" if rendered else ""))


def journey_line(window: Window) -> str:
    if not window.journey:
        return "    NOT_AVAILABLE: a linha `feedmine journey` não está nesta captura"
    fields = window.journey
    keys = ["t", "cards", "hero", "thumb", "text", "media_resident", "media_prepared", "media_settled",
            "sources_contacted", "sources_responded", "sources_unreachable", "preparation", "install_rejects"]
    rendered = " ".join(f"{key}={fields[key]}" for key in keys if key in fields)
    return f"    [{window.journey_origin}] {rendered}"


def journey_delta(previous: Window | None, window: Window) -> list[str]:
    if not window.journey or previous is None or not previous.journey:
        return []
    rows = []
    for key in ("cards", "media_resident", "media_prepared", "media_settled", "sources_contacted",
                "sources_responded", "sources_unreachable", "install_rejects"):
        before, after = as_int(previous.journey.get(key)), as_int(window.journey.get(key))
        if before is None or after is None:
            continue
        if before != after:
            rows.append(f"      Δ{key}: {before} → {after} ({after - before:+d})")
    return rows


def render_window(joined: Joined, position: int, window: Window, context: int) -> list[str]:
    lines: list[str] = []
    ident = f"--- janela {window.index}"
    if window.severe:
        ident += f"  severe={window.severe}"
    elif window.bad:
        ident += f"  bad={window.bad}"
    else:
        ident += f"  late={window.late}"
    lines.append(ident)

    # Contexto: as janelas vizinhas em uma linha cada, para a janela não ser lida fora da série.
    if context:
        for offset in range(-context, context + 1):
            neighbour = position + offset
            if neighbour < 0 or neighbour >= len(joined.windows) or offset == 0:
                continue
            other = joined.windows[neighbour]
            mark = "  " if other.index == window.index else "· "
            lines.append(f"    {mark}contexto #{other.index}: frames={other.frames} late={other.late} "
                         f"bad={other.bad} severe={other.severe} worst_ms={other.worst_ms}")

    # (a) o intervalo e a duração do quadro, com a linha crua
    lines.append("  (a) intervalo monotônico e duração do quadro")
    lines.append(f"    quadro: frames={window.frames} late={window.late} bad={window.bad} severe={window.severe} "
                 f"worst_ms={window.worst_ms} budget_ms={window.budget_ms}  [{window.frames_origin}]")
    if window.clock:
        lines.append(f"    carimbo do aparelho (verbatim): {window.clock}")
    if window.mono is not None:
        previous = joined.windows[position - 1] if position else None
        start = previous.mono if previous and previous.mono is not None else None
        if start is not None:
            lines.append(f"    intervalo: mono {start:.3f} → {window.mono:.3f} "
                         f"({window.mono - start:.3f} s)   at={iso(window.at)}")
        else:
            lines.append(f"    intervalo: mono … → {window.mono:.3f} (a janela anterior não tem mono) "
                         f"at={iso(window.at)}")
        if window.worst_at is not None:
            lines.append(f"    pior intervalo do medidor: worst_at={window.worst_at:.3f} "
                         f"(mono do fim − worst_at = {window.mono - window.worst_at:.3f} s antes do fim da janela)")
    else:
        lines.append("    NOT_AVAILABLE: intervalo monotônico — esta captura não carrega o traço nem `mono`; "
                     "o ordinal do app é a única chave")

    # (b) posição e movimento do leitor
    lines.append("  (b) posição e movimento do leitor")
    positions = [(number, event) for number, event in window.events if event.get("event") in POSITION_EVENTS]
    if positions:
        for number, event in positions:
            lines.append(event_line(joined.trace, number, event))
            fields = event.get("fields") or {}
            if event.get("event") in ("advance", "position_checkpoint", "position_kept_exact"):
                lines.append(f"      ↳ âncora: {joined.cards.where(fields.get('anchor'))}" if joined.cards
                             else f"      ↳ âncora: {fields.get('anchor')}")
            if event.get("event") == "admitted":
                for key in ("head", "tail", "anchor"):
                    if fields.get(key):
                        lines.append(f"      ↳ {key}: {joined.cards.where(fields.get(key))}")
    else:
        lines.append("    nenhum evento de posição do traço nesta janela (`advance`, `runway_completed`, "
                     "`position_checkpoint`, `window`)")
        if not joined.trace:
            lines.append("    NOT_AVAILABLE: falta o traço (`trace.jsonl`) — sem ele não há movimento do leitor "
                         "atribuível a um segundo; o que existe é só a carta inicial/final da corrida")
    if joined.series and joined.series.cards:
        lines.append("    da série publicada: initial_card=" + joined.cards.where(joined.series.cards.get("initial"))
                     if joined.cards else "    da série publicada: initial_card=" + str(joined.series.cards.get("initial")))
        lines.append("    da série publicada: final_card=" + (joined.cards.where(joined.series.cards.get("final"))
                     if joined.cards else str(joined.series.cards.get("final"))))
    if window.notes_app:
        lines.append(f"    movimento/trabalho dito pelo PRÓPRIO app no log unificado ({len(window.notes_app)} "
                     "linhas nesta janela):")
        for number, line in window.notes_app[:14]:
            lines.append(f"    [{os.path.basename(joined.console.path)}:{number}] {line}")
        if len(window.notes_app) > 14:
            lines.append(f"    … ({len(window.notes_app) - 14} linhas do app omitidas nesta janela)")
    elif joined.console:
        lines.append("    nenhuma linha do log unificado do app nesta janela (a captura de console desta corrida "
                     "não inclui o syslog do sistema: `[composition] installed cards=…`, `viewport forwarded …`, "
                     "`Runway opportunity completed …` são `Logger`, não `NSLog`)")

    # (c) a janela admitida
    lines.append("  (c) estado da janela admitida")
    if not joined.trace:
        lines.append("    NOT_AVAILABLE: falta o traço (`trace.jsonl`) — a janela admitida por segundo não é "
                     "observável nesta captura")
    elif window.mono is None:
        lines.append("    NOT_AVAILABLE: esta janela está fora do alcance do traço (nenhum `mono` foi alinhado a "
                     "ela), então a janela admitida neste segundo não é observável — não se deriva de outra janela")
    else:
        admitted = joined.admitted_before(window)
        if admitted:
            number, event = admitted
            fields = event.get("fields") or {}
            lines.append(f"    última admissão antes do fim da janela [{os.path.basename(joined.trace.path)}:{number}] "
                         f"cards={fields.get('cards')} order={fields.get('order')}")
            for key in ("head", "tail", "anchor"):
                if fields.get(key):
                    lines.append(f"      ↳ {key}: {joined.cards.where(fields.get(key))}" if joined.cards
                                 else f"      ↳ {key}: {fields.get(key)}")
            if "ids" in fields:
                lines.append(f"      ↳ ids admitidos na ordem: {fields['ids']}")
        else:
            lines.append("    nenhuma admissão antes desta janela no traço")

    # (d) trabalho de aquisição / publicação / mídia
    lines.append("  (d) trabalho de aquisição, publicação e mídia no intervalo")
    work = [(number, event) for number, event in window.events if event.get("event") in WORK_EVENTS]
    counts: dict[str, int] = {}
    for _, event in work:
        counts[event.get("event")] = counts.get(event.get("event"), 0) + 1
    if counts:
        lines.append("    contagem por evento: " + ", ".join(f"{key}={value}" for key, value in sorted(counts.items())))
        shown: dict[str, int] = {}
        for number, event in work:
            name = event.get("event")
            shown[name] = shown.get(name, 0) + 1
            if shown[name] <= 6:
                lines.append(event_line(joined.trace, number, event))
            elif shown[name] == 7:
                lines.append(f"    … ({counts[name] - 6} linhas de {name} omitidas; todas em "
                             f"{os.path.basename(joined.trace.path)})")
    else:
        lines.append("    nenhum evento de trabalho do traço nesta janela")
        if not joined.trace:
            lines.append("    NOT_AVAILABLE: falta o traço (`trace.jsonl`) — o trabalho de fundo por segundo não é "
                         "observável nesta captura")
    previous = joined.windows[position - 1] if position else None
    delta = journey_delta(previous, window)
    if delta:
        lines.append("    linha de jornada desta janela, com o Δ contra a anterior:")
        lines.extend(delta)
    lines.append(journey_line(window))

    # (e) pressão do sistema
    lines.append("  (e) pressão do sistema")
    if window.pressure:
        for number, line in window.pressure:
            lines.append(f"    [{os.path.basename(joined.console.path)}:{number}] {line}")
    else:
        lines.append("    NOT_OBSERVED nesta janela (vocabulário procurado: " + ", ".join(PRESSURE_TERMS) + ")")
    if window.notes_other:
        lines.append(f"    e {window.notes_other} linhas de outros processos do aparelho nesta janela (só "
                     "contadas; a captura não as guarda separadas por processo)")
    if delta and [row for row in delta if "install_rejects" in row]:
        lines.append("    recusas de instalação mudaram nesta janela: "
                     + ", ".join(row.strip() for row in delta if "install_rejects" in row))
    lines.append("    o que uma captura de console NÃO vê por si: memória sob pressão (jetsam/memorystatus), "
                 "estado térmico e hang do watchdog só aparecem se o syslog do sistema tiver sido capturado "
                 "durante a jornada — `scripts/hitch-pass.sh` faz isso quando `idevicesyslog` está disponível, e "
                 "o arquivo `console-journey.log` é a captura; `worst_ms` acima do orçamento é a única medida "
                 "direta de atraso desta janela")
    return lines


def render(joined: Joined, select: str, context: int, limit: int | None) -> list[str]:
    lines: list[str] = []
    lines.append("=" * 100)
    lines.append(f"insumo: {joined.title}")
    lines.append("=" * 100)
    lines.append("proveniência:")
    for label, obj in (("console", joined.console), ("traço", joined.trace), ("série publicada", joined.series),
                       ("banco", joined.cards)):
        if obj is None:
            continue
        path = obj.path
        lines.append(f"  {label}: {path}")
        lines.append(f"      sha256={sha256_file(path) if os.path.exists(path) else '?'}")
    if joined.console:
        lines.append(f"      linhas `feedmine frames=`: {len(joined.console.frames)}   "
                     f"`feedmine journey`: {len(joined.console.journey)}   "
                     f"linhas de pressão: {len(joined.console.pressure)}   outras: {len(joined.console.other)}")
    if joined.trace:
        counts: dict[str, int] = {}
        for _, event in joined.trace.events:
            counts[event.get("event")] = counts.get(event.get("event"), 0) + 1
        lines.append(f"      eventos: {len(joined.trace.events)} linhas ilegíveis: {joined.trace.invalid} "
                     + ", ".join(f"{key}={value}" for key, value in sorted(counts.items())))
        loss = joined.trace.losses()
        if loss:
            lines.append(f"      PERDA DECLARADA PELO PRÓPRIO TRAÇO: {loss}")
    if joined.cards:
        lines.append(f"      cartas na ordem do leitor: {joined.cards.total}")
    for note in joined.notes:
        lines.append(f"  nota: {note}")
    for item in joined.missing:
        lines.append(f"  FALTA: {item}")

    totals = joined.totals()
    lines.append("")
    lines.append(f"totais da série: janelas={totals['janelas']} quadros={totals['quadros']} late={totals['late']} "
                 f"bad={totals['bad']} severe={totals['severe']} pior_ms={totals['pior_ms']}")
    lines.append(f"segundos com pelo menos um quadro: late={totals['segundos_com_late']} "
                 f"bad={totals['segundos_com_bad']} severe={totals['segundos_com_severe']}  "
                 f"(seleção: `--select {select}` = o balde do próprio medidor; nenhum limiar foi escolhido aqui)")
    if not joined.windows:
        return lines

    picks = joined.selected(select)
    if limit:
        picks = picks[:limit]
    if not picks:
        lines.append(f"")
        lines.append(f"nenhuma janela com `{select}` nesta série: a série medida não contém o que a seleção pede "
                     "(isto não é aprovação de fluidez — é ausência do balde)")
        return lines

    index_of = {id(window): position for position, window in enumerate(joined.windows)}
    for window in picks:
        lines.append("")
        lines.extend(render_window(joined, index_of[id(window)], window, context))
    if joined.beyond:
        lines.append("")
        lines.append("--- eventos do traço fora do alcance das janelas (depois do último segundo que o eixo cobre)")
        counts: dict[str, int] = {}
        for _, event in joined.beyond:
            counts[event.get("event")] = counts.get(event.get("event"), 0) + 1
        lines.append("    contagem por evento: " + ", ".join(f"{key}={value}" for key, value in sorted(counts.items())))
        for number, event in joined.beyond[:12]:
            lines.append(event_line(joined.trace, number, event))
        if len(joined.beyond) > 12:
            lines.append(f"    … ({len(joined.beyond) - 12} eventos omitidos)")
    lines.append("")
    lines.append(f"{len(picks)} janelas impressas (seleção `{select}`). O número informa; nenhuma cláusula aqui "
                 "aprova fluidez.")
    return lines


# --------------------------------------------------------------------------------------------------------------
# Entrada


def joined_from_directory(path: str) -> Joined:
    found = find_files(path)
    joined = Joined(path)
    console_path = None
    for candidate in found["consoles"]:
        if os.path.basename(candidate) in ("console.log", "console-standalone.log", "console-journey.log",
                                           "console-journey-feedmine.log"):
            console_path = candidate
            break
    if console_path is None and found["consoles"]:
        console_path = found["consoles"][0]
    if console_path:
        joined.console = Console(console_path)
    if found["traces"]:
        joined.trace = Trace(sorted(found["traces"])[0])
    if found["databases"]:
        joined.cards = Cards(sorted(found["databases"])[0])
    if found["series"]:
        joined.series = Series(sorted(found["series"])[0])
    # O que falta, dito pelo nome do arquivo — nunca inferido de outro campo.
    if joined.console is None or not joined.console.frames:
        joined.missing.append("série de quadros no console (`feedmine frames=`): nenhum arquivo de console com "
                              "essa linha em " + path)
    if joined.console is None or not joined.console.journey:
        joined.missing.append("fatos da jornada (`feedmine journey`): nenhuma linha — a captura não ligou "
                              "`FEEDMINE_JOURNEY_CONSOLE=1`, ou o console desta corrida não foi persistido")
    if joined.trace is None:
        joined.missing.append("traço do app (`trace.jsonl`): não está em " + path + " — sem ele não há posição do "
                              "leitor nem trabalho de fundo por segundo")
    if joined.cards is None:
        joined.missing.append("banco (`runtime.sqlite`): não está em " + path + " — as âncoras saem como UUID cru")
    joined.build()
    return joined


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="hitch-join.py",
        description="Junta por segundo a série de quadros, a linha de jornada e o traço do app, e diz o que estava "
                    "acontecendo em cada janela com quadro severo.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Exit 0 quando imprimiu; 1 quando não havia nada mensurável; 2 para uso recusado.")
    parser.add_argument("--journey", action="append", default=[], metavar="DIR",
                        help="diretório de uma jornada (o --out de scripts/device-journey.sh ou de "
                             "scripts/hitch-pass.sh)")
    parser.add_argument("--console", action="append", default=[], metavar="ARQUIVO",
                        help="log de console com as linhas `feedmine frames=`/`feedmine journey`")
    parser.add_argument("--trace", metavar="ARQUIVO", help="trace.jsonl do app")
    parser.add_argument("--db", metavar="ARQUIVO", help="runtime.sqlite do container (lido numa cópia)")
    parser.add_argument("--series", action="append", default=[], metavar="ARQUIVO",
                        help="anexo do XCTest com a série publicada (`after=…;series=…`)")
    parser.add_argument("--select", choices=("severe", "bad", "late", "any"), default="severe",
                        help="qual balde do medidor abre uma janela (default: severe)")
    parser.add_argument("--context", type=int, default=1, metavar="N",
                        help="quantas janelas vizinhas imprimir de contexto (default: 1)")
    parser.add_argument("--limit", type=int, metavar="N", help="imprime no máximo N janelas")
    parser.add_argument("--json", action="store_true", help="saída em JSON em vez do relatório")
    arguments = parser.parse_args()

    if not (arguments.journey or arguments.console or arguments.trace or arguments.series):
        parser.error("informe --journey <dir> e/ou --console/--trace/--db/--series")

    insumos: list[Joined] = []
    for path in arguments.journey:
        if not os.path.isdir(path):
            print(f"REFUSED: --journey {path} não é um diretório", file=sys.stderr)
            return 2
        insumos.append(joined_from_directory(path))
    if arguments.console or arguments.trace or arguments.series:
        joined = Joined("insumo montado a partir dos arquivos informados")
        if arguments.console:
            joined.console = Console(arguments.console[0])
        if arguments.trace:
            joined.trace = Trace(arguments.trace)
        if arguments.db:
            joined.cards = Cards(arguments.db)
        if arguments.series:
            joined.series = Series(arguments.series[0])
        joined.build()
        insumos.append(joined)

    measurable = [joined for joined in insumos if joined.windows]
    if not measurable:
        for joined in insumos:
            print("=" * 100)
            print(f"insumo: {joined.title}")
            for item in joined.missing:
                print(f"  FALTA: {item}")
        print("NOT_RUN: nenhum insumo trouxe uma série de quadros — nada a juntar", file=sys.stderr)
        return 1

    if arguments.json:
        document = []
        for joined in insumos:
            document.append({"insumo": joined.title, "notas": joined.notes, "falta": joined.missing,
                             "totais": joined.totals(),
                             "janelas_selecionadas": [window.as_dict() for window in joined.selected(arguments.select)]})
        print(json.dumps(document, indent=2, ensure_ascii=False))
        return 0

    for number, joined in enumerate(insumos):
        if number:
            print()
        print("\n".join(render(joined, arguments.select, arguments.context, arguments.limit)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
