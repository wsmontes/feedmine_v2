#!/usr/bin/env python3
# File: bench/build_corpus.py
# Owns: building the frozen FeedMine discovery acceptance corpus from the repository's real bundled catalog.
# Does not own: production code, the app target, the package sources, the criteria text (which is *quoted*, not
# redefined here) or any run result. Nothing outside `bench/` is read-only-accessed except the real catalog and
# the benchmark document, which are only read.
#
# This script is the evaluator's fixture generator (docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md §2):
#   * bench/corpus/catalog.sqlite — the real catalog rows selected by their own labels, same schema the app reads
#     through LegacyCatalogReader, with `request_url` rewritten to the local transport.
#   * bench/corpus/items.json     — labelled items (topic, language, region, source, canonical article id,
#     material revision, media kind/URL) for those sources.
#   * bench/corpus/sources.json   — the per-source transport plan (protocol, delays, failure class, item count).
#   * bench/corpus/criteria.json  — the frozen criteria: profiles, the B01/B02/B03 thresholds quoted verbatim,
#     and the trace description.
#   * bench/corpus/media.pack     — frozen media bytes (PNG/MP3/MP4) served by bench/serve.py.
#   * bench/corpus/feeds/*        — frozen feed documents (RSS 2.0, Atom, JSON Feed), rendered at build time.
#   * bench/manifest.json + bench/MANIFEST.sha256 — hashes of all of the above plus this generator and the server.
#
# Determinism: a fixed seed, fixed base timestamp (no wall clock enters the data), stable ordering everywhere.
# Regenerating is deliberate: it refuses to overwrite a frozen corpus unless --rebuild is passed.
#
# Usage:
#   python3 bench/build_corpus.py            # first build only; refuses if the corpus is already frozen
#   python3 bench/build_corpus.py --rebuild  # deliberate regeneration (rewrites the manifest too)

from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import shutil
import sqlite3
import struct
import subprocess
import sys
import zlib
from datetime import datetime, timedelta, timezone
from email.utils import format_datetime
from pathlib import Path
from urllib.parse import quote

# --------------------------------------------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------------------------------------------

BENCH_DIR = Path(__file__).resolve().parent
REPO_ROOT = BENCH_DIR.parent
CORPUS_DIR = BENCH_DIR / "corpus"
FEEDS_DIR = CORPUS_DIR / "feeds"
DEFAULT_CATALOG = REPO_ROOT / "FeedMineApp" / "FeedMineApp" / "Resources" / "catalog.sqlite"
BENCHMARK_DOC = REPO_ROOT / "docs" / "product" / "DISCOVERY_ACCEPTANCE_BENCHMARK.md"

SEED = 20261010
BASE_URL = "http://127.0.0.1:8757"
# Fixed clock for every generated date: the corpus carries no wall-clock value.
FIXED_NOW = datetime(2026, 10, 9, 0, 0, 0, tzinfo=timezone.utc)
FIXED_NOW_ISO = "2026-10-09T00:00:00Z"

# Profile sources: items per source. Profile sources carry enough items that *each* profile alone clears the
# benchmark's ≥5,000 eligible items precondition (B03 needs the whole trace from one profile context).
ITEMS_PER_PROFILE_SOURCE = (6, 9)   # inclusive range: 6 + h % 4
ITEMS_PER_NOISE_SOURCE = (3, 5)     # inclusive range: 3 + h % 3
NOISE_SOURCES = 240                 # real rows outside both profiles, so recipe filtering is actually exercised
NOISE_LANGUAGES = ("es", "fr", "de")

PAIRS_PER_PROFILE = {"A": 120, "B": 150}       # deliberate cross-publisher duplicates
REVISIONS_PER_PROFILE = {"A": 35, "B": 40}     # PD-1 material revisions of a duplicated canonical article

# Behaviour classes (deterministic bands over a per-source hash of 1000):
#   normal 0..699, slow 700..819 (2.5-6.0s), intermittent 820..939 (every 3rd request fails 500/503),
#   timeout 940..999 (every 4th request hangs 12s, then 504).
BEHAVIOUR_NORMAL = 700
BEHAVIOUR_SLOW = 120
BEHAVIOUR_INTERMITTENT = 120
BEHAVIOUR_TIMEOUT = 60
EMPTY_SOURCES_PER_MILLE = 30        # a valid document with zero items
SLOW_MEDIA_PER_MILLE = 100          # media responses of that source are delayed 2.5-7.0s

PROTOCOL_TYPES = {
    "rss": ("application/rss+xml; charset=utf-8", ".xml"),
    "atom": ("application/atom+xml; charset=utf-8", ".atom"),
    "jsonfeed": ("application/feed+json; charset=utf-8", ".json"),
}
# 55% RSS 2.0, 25% Atom, 20% JSON Feed (deterministic band).
PROTOCOL_CUTS = (550, 800)

REGION_BY_LANGUAGE_VARIANT = {
    "pt-BR": "BR", "pt": "PT", "en": "INT", "en-US": "US", "en-GB": "GB", "en-AU": "AU", "en-CA": "CA",
    "en-IE": "IE", "en-NZ": "NZ", "en-ZA": "ZA", "en-IN": "IN", "en-PH": "PH", "es": "ES", "fr": "FR",
    "de": "DE", "it": "IT", "nl": "NL", "da": "DK", "sv": "SE", "no": "NO", "ja": "JP", "ru": "RU",
    "tr": "TR", "vi": "VN", "ar": "AR", "in": "ID", "ko": "KR", "pl": "PL", "cs": "CZ", "fi": "FI",
}

# --------------------------------------------------------------------------------------------------------------
# Headline banks: composed deterministically into distinct, realistic headlines per topic and language.
# --------------------------------------------------------------------------------------------------------------

BANKS: dict[str, dict] = {
    "pt-science": {
        "leads": [
            "Cientistas brasileiros descobrem", "Pesquisadores revelam", "Novo estudo aponta",
            "Astrônomos observam", "Uma equipe internacional mapeia", "Biólogos testam", "Físicos medem",
            "Geólogos identificam", "Climatologistas alertam para", "Engenheiros desenvolvem",
            "Pesquisa da USP mostra", "Laboratório europeu confirma", "Dados de satélite revelam",
            "Análise publicada na Nature descreve", "Consórcio de universidades propõe",
            "Oceanógrafos registram", "Genetistas sequenciam", "Arqueólogos encontram",
            "Neurocientistas explicam", "Meteorologistas acompanham",
        ],
        "objects": [
            "exoplaneta rochoso", "genoma completo de coral", "buraco negro supermassivo",
            "nova espécie de fungo", "fóssil de dinossauro", "amostra de gelo antártico",
            "célula solar mais eficiente", "microrganismo resistente", "asteroide próximo da Terra",
            "mapa de desmatamento", "variante genética rara", "recife artificial",
            "algoritmo de previsão climática", "bateria de estado sólido", "sistema de alerta sísmico",
            "padrão de migração de aves", "vento solar", "camada de ozônio", "iceberg gigante",
        ],
        "quals": [
            "na órbita de uma estrela próxima", "em laboratório", "na Amazônia", "no litoral brasileiro",
            "em escala global", "com dados de vinte anos", "em tempo recorde", "com apoio de aprendizado de máquina",
            "no Ártico", "em condições extremas", "por meio de telescópios", "em três continentes",
        ],
        "tails": [
            "", "", "", "e reacendem o debate sobre financiamento", "com impacto para políticas públicas",
            "segundo pesquisadores brasileiros", "em estudo revisado por pares",
        ],
        "summaries": [
            "O achado, {qual}, foi apresentado nesta semana e deve orientar novos estudos no país.",
            "O resultado, {qual}, amplia o que se sabia sobre o tema e será discutido em congresso no próximo mês.",
            "A equipe afirma que o trabalho, {qual}, levou três anos e contou com financiamento público.",
            "Especialistas avaliam que a descoberta, {qual}, pode mudar protocolos adotados hoje.",
            "Os autores dizem que o estudo, {qual}, é o primeiro a medir o fenômeno nessa escala.",
        ],
    },
    "pt-technology": {
        "leads": [
            "Startup brasileira lança", "Pesquisadores desenvolvem", "Indústria testa", "Novo relatório analisa",
            "Universidade cria", "Empresas adotam", "Laboratório nacional projeta", "Time de engenharia publica",
            "Consórcio de empresas apresenta", "Estudo sobre privacidade examina", "Regulador discute",
            "Projeto open source entrega", "Chip brasileiro é testado em",
        ],
        "objects": [
            "modelo de linguagem em português", "rede de sensores urbanos", "plataforma de pagamentos instantâneos",
            "sistema de energia solar residencial", "protocolo de identidade digital", "robô agrícola autônomo",
            "aplicativo de acessibilidade", "infraestrutura de dados abertos", "antena de quinta geração",
            "bateria para veículos elétricos", "serviço de nuvem soberana", "framework de criptografia pós-quântica",
            "processador de baixo consumo", "sistema de rastreio de enchentes", "assistente de voz regional",
            "plataforma de telemedicina", "digital twin de fábrica", "cartão de transporte integrado",
        ],
        "quals": [
            "com custo 30% menor", "em parceria com o setor público", "usando hardware aberto", "em escala industrial",
            "depois de dois anos de testes", "com foco no mercado interno", "em ambiente de produção",
            "sob auditoria independente", "com dados de usuários protegidos", "em regiões sem cobertura",
            "para pequenas empresas", "em conjunto com universidades",
        ],
        "tails": [
            "", "", "", "e atraem investimento estrangeiro", "em anúncio feito durante evento do setor",
            "com expectativa de piloto no próximo trimestre", "segundo o relatório técnico divulgado hoje",
        ],
        "summaries": [
            "O anúncio, {qual}, foi feito em evento do setor e inclui planos de expansão.",
            "A equipe técnica explica que a solução, {qual}, já roda em ambiente controlado.",
            "Segundo o documento, o projeto, {qual}, deve chegar a novos clientes no próximo ciclo.",
            "O consórcio afirma que a iniciativa, {qual}, reduz dependência de fornecedores externos.",
            "Analistas veem a proposta, {qual}, como um passo relevante para o mercado local.",
        ],
    },
    "pt-brazil-news": {
        "leads": [
            "Governo anuncia", "Congresso discute", "Prefeitura de São Paulo divulga", "Ministério confirma",
            "Justiça decide sobre", "Banco Central avalia", "Agência reguladora abre consulta sobre",
            "Comissão aprova", "Estado publica edital para", "Relatório aponta", "Pesquisa eleitoral indica",
            "Sindicato negocia", "Defesa Civil alerta para",
        ],
        "objects": [
            "novo plano de habitação", "reforma tributária", "leilão de saneamento", "regras para plataformas digitais",
            "programa de merenda escolar", "orçamento da saúde", "linha de crédito para pequenos negócios",
            "concessão de rodovias", "política de segurança pública", "calendário de vacinação",
            "metas de desmatamento", "tarifas de energia", "acordo de compensação ambiental",
            "piso salarial da categoria", "plano de mobilidade urbana", "reajuste de servidores",
            "medida provisória", "fundo de infraestrutura",
        ],
        "quals": [
            "na Amazônia", "em capitais do Nordeste", "no interior de Minas Gerais", "no Rio Grande do Sul",
            "em cinco estados", "depois de audiência pública", "com impacto no orçamento federal",
            "em municípios de médio porte", "segundo dados oficiais", "em parceria com estados",
            "a partir do próximo mês", "após decisão do Supremo",
        ],
        "tails": [
            "", "", "", "e provocam reação de entidades", "em meio a debate no parlamento",
            "com previsão de votação até dezembro", "segundo o texto publicado no Diário Oficial",
        ],
        "summaries": [
            "A medida, {qual}, ainda depende de regulamentação e gera expectativa entre entidades.",
            "Autoridades afirmam que a proposta, {qual}, entra em vigor depois de análise técnica.",
            "O texto, {qual}, recebeu manifestações favoráveis e contrárias nas últimas horas.",
            "Segundo o órgão responsável, a decisão, {qual}, será revisada em uma nova rodada.",
            "Entidades acompanham os desdobramentos da medida, {qual}, prevista há meses.",
        ],
    },
    "pt-photography": {
        "leads": [
            "Fotógrafo brasileiro documenta", "Exposição reúne", "Ensaio registra", "Livro fotográfico mostra",
            "Prêmio reconhece", "Museu digitaliza", "Projeto percorre", "Oficina ensina",
            "Coletivo publica", "Galeria apresenta",
        ],
        "objects": [
            "a vida nas periferias", "as águas do Pantanal", "o cotidiano das feiras livres",
            "a arquitetura moderna de Brasília", "as queimadas no cerrado", "os povos ribeirinhos",
            "a migração nas fronteiras", "o trabalho nas salinas", "as manifestações de rua",
            "a cultura do carnaval de rua", "as baleias do litoral sul", "a seca no semiárido",
        ],
        "quals": [
            "em preto e branco", "com câmeras analógicas", "em série de doze anos", "usando luz natural",
            "com apoio de arquivos públicos", "em ensaios de rua", "durante a pandemia", "em formato panorâmico",
        ],
        "tails": ["", "", "e impressionam pela proximidade", "em mostra itinerante", "em edição bilíngue"],
        "summaries": [
            "A série, {qual}, ficará em cartaz por dois meses e tem entrada gratuita.",
            "O autor descreve o trabalho, {qual}, como um exercício de escuta e convivência.",
            "Curadores destacam o conjunto, {qual}, como um retrato revelador do país.",
            "As imagens, {qual}, serão reunidas em livro previsto para o próximo semestre.",
            "O projeto, {qual}, recebeu apoio de um edital cultural e percorrerá quatro capitais.",
        ],
    },
    "en-science": {
        "leads": [
            "Researchers discover", "Scientists observe", "New study finds", "An international team maps",
            "Astronomers measure", "Biologists test", "Physicists model", "Geologists identify",
            "Climate scientists warn about", "Engineers build", "Data from satellites reveal",
            "A paper in Nature describes", "Oceanographers record", "Geneticists sequence",
            "Archaeologists unearth", "Neuroscientists explain", "Chemists synthesize",
        ],
        "objects": [
            "a rocky exoplanet", "a complete coral genome", "a supermassive black hole",
            "a new fungal species", "a dinosaur fossil", "an Antarctic ice core",
            "a more efficient solar cell", "a radiation-resistant microbe", "an asteroid passing near Earth",
            "a global deforestation map", "a rare genetic variant", "an artificial reef",
            "a climate forecasting model", "a solid-state battery", "an earthquake early-warning system",
            "a bird migration pattern", "the solar wind", "the ozone layer", "a giant iceberg",
        ],
        "quals": [
            "in orbit around a nearby star", "in the laboratory", "in the Arctic", "with twenty years of data",
            "at record speed", "with the help of machine learning", "across three continents",
            "under extreme conditions", "using space telescopes", "in a peer-reviewed study",
            "at a depth of four kilometres", "during the last glacial period",
        ],
        "tails": [
            "", "", "", "and the findings reopen a funding debate", "with implications for public policy",
            "according to the research team", "in work reviewed by independent experts",
        ],
        "summaries": [
            "The finding, {qual}, was presented this week and should shape the next round of experiments.",
            "Researchers say the result, {qual}, took three years and involved several institutions.",
            "Independent experts called the work, {qual}, an important step for the field.",
            "The team reports that the measurement, {qual}, is the first of its kind at this scale.",
            "The study, {qual}, appears in a journal and is open to replication.",
        ],
    },
    "en-technology": {
        "leads": [
            "A startup launches", "Engineers unveil", "Regulators examine", "A new report analyses",
            "Researchers develop", "Companies adopt", "A university builds", "The team behind publishes",
            "An open-source project ships", "A chipmaker tests", "Security researchers disclose",
            "Developers release",
        ],
        "objects": [
            "an on-device language model", "an urban sensor network", "an instant payment platform",
            "a residential solar system", "a digital identity protocol", "an autonomous farm robot",
            "an accessibility app", "an open data infrastructure", "a fifth-generation antenna",
            "an electric-vehicle battery", "a sovereign cloud service", "a post-quantum cryptography framework",
            "a low-power processor", "a flood-tracking system", "a regional voice assistant",
            "a telemedicine platform", "a factory digital twin", "an integrated transit card",
        ],
        "quals": [
            "at 30% lower cost", "with public-sector partners", "using open hardware", "at industrial scale",
            "after two years of trials", "with a focus on local markets", "in production",
            "under independent audit", "with user data kept private", "in areas without coverage",
            "for small businesses", "together with universities",
        ],
        "tails": [
            "", "", "", "and attract foreign investment", "at a developer conference",
            "with a pilot expected next quarter", "according to the technical report released today",
        ],
        "summaries": [
            "The announcement, {qual}, was made at an industry event and includes expansion plans.",
            "The engineering team says the system, {qual}, already runs in a controlled environment.",
            "According to the report, the project, {qual}, will reach new customers next cycle.",
            "The consortium says the effort, {qual}, reduces dependence on outside suppliers.",
            "Analysts see the proposal, {qual}, as a meaningful step for the sector.",
        ],
    },
    "en-world-news": {
        "leads": [
            "Leaders agree on", "Parliament debates", "The foreign ministry confirms", "Officials announce",
            "A court rules on", "The central bank reviews", "A regulator opens a consultation on",
            "The commission approves", "Voters decide on", "An investigation finds",
            "Negotiators resume talks over", "The agency warns about", "Delegates sign",
        ],
        "objects": [
            "a new housing plan", "an energy taxation reform", "a water infrastructure tender",
            "rules for digital platforms", "a school meals programme", "the health budget",
            "a credit line for small business", "a motorway concession", "a public safety policy",
            "a vaccination calendar", "deforestation targets", "electricity tariffs",
            "a carbon offset agreement", "a wage floor", "an urban mobility plan",
            "a temporary measure", "an infrastructure fund", "a peacekeeping mandate",
        ],
        "quals": [
            "across five states", "after a public hearing", "with an impact on the federal budget",
            "in mid-sized cities", "according to official figures", "in partnership with regional governments",
            "from next month", "after a supreme court ruling", "at the annual summit",
            "in the largest economies", "following months of negotiation", "amid rising prices",
        ],
        "tails": [
            "", "", "", "and trigger a reaction from industry groups", "amid a heated parliamentary debate",
            "with a vote expected by December", "according to the official gazette",
        ],
        "summaries": [
            "The measure, {qual}, still depends on secondary rules and is being watched by industry groups.",
            "Officials say the proposal, {qual}, takes effect after technical review.",
            "The text, {qual}, drew both support and criticism within hours.",
            "According to the agency, the decision, {qual}, will be revisited in a new round.",
            "Stakeholders are following the measure, {qual}, which has been expected for months.",
        ],
    },
    "es-other": {
        "leads": [
            "El gobierno anuncia", "Los investigadores describen", "Una nueva ley regula",
            "La ciudad aprueba", "El ministerio confirma", "Los vecinos denuncian",
            "La universidad presenta", "El banco central revisa",
        ],
        "objects": [
            "un plan de vivienda", "un programa de transporte", "una reforma fiscal", "un acuerdo comercial",
            "una campaña de vacunación", "un plan de energía solar", "una ruta turística",
            "un proyecto de ley", "una feria del libro", "un plan de riego",
        ],
        "quals": [
            "en las zonas rurales", "tras una consulta pública", "con impacto en el presupuesto",
            "en cinco provincias", "según cifras oficiales", "a partir del próximo mes",
        ],
        "tails": ["", "", "y generan debate público", "según el diario oficial", "con apoyo internacional"],
        "summaries": [
            "La medida, {qual}, aún debe reglamentarse y genera expectativas en el sector.",
            "Las autoridades afirman que la propuesta, {qual}, entrará en vigor tras el análisis técnico.",
            "El texto, {qual}, recibió opiniones a favor y en contra en las últimas horas.",
        ],
    },
    "fr-other": {
        "leads": [
            "Le gouvernement annonce", "Les chercheurs décrivent", "Une nouvelle loi encadre",
            "La ville adopte", "Le ministère confirme", "Les habitants signalent",
            "L'université présente", "La banque centrale révise",
        ],
        "objects": [
            "un plan de logement", "un programme de transport", "une réforme fiscale", "un accord commercial",
            "une campagne de vaccination", "un plan solaire", "une route touristique",
            "un projet de loi", "un salon du livre", "un plan d'irrigation",
        ],
        "quals": [
            "dans les zones rurales", "après une consultation publique", "avec un impact budgétaire",
            "dans cinq régions", "selon les chiffres officiels", "à partir du mois prochain",
        ],
        "tails": ["", "", "et suscitent le débat", "selon le journal officiel", "avec un soutien international"],
        "summaries": [
            "La mesure, {qual}, doit encore être précisée et suscite des attentes dans le secteur.",
            "Les autorités affirment que la proposition, {qual}, entrera en vigueur après analyse.",
            "Le texte, {qual}, a recueilli des avis favorables et défavorables ces dernières heures.",
        ],
    },
    "de-other": {
        "leads": [
            "Die Regierung kündigt an", "Forschende beschreiben", "Ein neues Gesetz regelt",
            "Die Stadt beschließt", "Das Ministerium bestätigt", "Anwohner melden",
            "Die Universität stellt vor", "Die Zentralbank prüft",
        ],
        "objects": [
            "einen Wohnungsplan", "ein Verkehrsprogramm", "eine Steuerreform", "ein Handelsabkommen",
            "eine Impfkampagne", "einen Solarplan", "eine Tourismusroute",
            "einen Gesetzentwurf", "eine Buchmesse", "einen Bewässerungsplan",
        ],
        "quals": [
            "in ländlichen Regionen", "nach einer öffentlichen Anhörung", "mit Auswirkungen auf den Haushalt",
            "in fünf Bundesländern", "laut offiziellen Zahlen", "ab dem nächsten Monat",
        ],
        "tails": ["", "", "und lösen Debatten aus", "laut Amtsblatt", "mit internationaler Unterstützung"],
        "summaries": [
            "Die Maßnahme, {qual}, muss noch konkretisiert werden und wird in der Branche erwartet.",
            "Behörden zufolge tritt der Vorschlag, {qual}, nach technischer Prüfung in Kraft.",
            "Der Text, {qual}, erhielt innerhalb weniger Stunden Zustimmung und Kritik.",
        ],
    },
    "en-other": {
        "leads": [
            "Officials announce", "Researchers describe", "A new rule covers", "The city approves",
            "The ministry confirms", "Neighbours report", "The university presents", "The central bank reviews",
            "A local paper reports", "The council debates",
        ],
        "objects": [
            "a housing plan", "a transport programme", "a tax reform", "a trade agreement",
            "a vaccination campaign", "a solar plan", "a tourist route", "a draft bill",
            "a book fair", "an irrigation plan", "a waste collection scheme", "a library network",
        ],
        "quals": [
            "in rural areas", "after a public consultation", "with a budget impact",
            "in five districts", "according to official figures", "from next month",
        ],
        "tails": ["", "and it stirred public debate", "according to the official gazette"],
        "summaries": [
            "The measure, {qual}, still needs secondary rules and is awaited by the sector.",
            "Authorities say the proposal, {qual}, takes effect after technical review.",
            "The text, {qual}, drew both support and criticism within hours.",
        ],
    },
    "pt-other": {
        "leads": [
            "Autoridades anunciam", "Pesquisadores descrevem", "Nova norma trata de", "A cidade aprova",
            "O ministério confirma", "Moradores relatam", "A universidade apresenta", "O banco central revisa",
            "Jornal local noticia", "O conselho debate",
        ],
        "objects": [
            "um plano de moradia", "um programa de transporte", "uma reforma tributária", "um acordo comercial",
            "uma campanha de vacinação", "um plano de energia solar", "uma rota turística", "um projeto de lei",
            "uma feira do livro", "um plano de irrigação", "um programa de coleta seletiva", "uma rede de bibliotecas",
        ],
        "quals": [
            "na zona rural", "após consulta pública", "com impacto no orçamento",
            "em cinco distritos", "segundo dados oficiais", "a partir do próximo mês",
        ],
        "tails": ["", "e provocou debate público", "conforme o diário oficial"],
        "summaries": [
            "A medida, {qual}, ainda depende de regulamentação e é aguardada pelo setor.",
            "Autoridades dizem que a proposta, {qual}, entra em vigor após análise técnica.",
            "O texto, {qual}, recebeu apoio e críticas em poucas horas.",
        ],
    },
}

# Normalisation: a repeated alternative that renders identically (several empty tails) would collapse two distinct
# cursor positions onto one headline, so each bank keeps exactly one empty tail. Every bank stays its own object.
for _bank_key, _bank in BANKS.items():
    if "tails" in _bank:
        _seen: list[str] = []
        for _tail in _bank["tails"]:
            if _tail not in _seen:
                _seen.append(_tail)
        _bank["tails"] = _seen

# --------------------------------------------------------------------------------------------------------------
# Frozen criteria: the profiles used to select the corpus, plus the benchmark's own thresholds quoted verbatim.
# --------------------------------------------------------------------------------------------------------------


def load_criteria(repo_catalog_sha256: str) -> dict:
    doc_text = BENCHMARK_DOC.read_text(encoding="utf-8")
    doc_sha = hashlib.sha256(doc_text.encode("utf-8")).hexdigest()
    return {
        "schema": "feedmine-bench-criteria/1",
        "frozen": True,
        "source_document": {
            "path": "docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md",
            "sha256": doc_sha,
            "note": "Thresholds below are quoted verbatim from this document; they are the evaluator's régua, not "
                    "this generator's invention. The generator cannot alter them.",
        },
        "profiles": {
            "A": {
                "id": "A",
                "description": "Leitor de ciência, tecnologia, fotografia e notícias do Brasil",
                "language_codes": ["pt", "pt-BR"],
                "language_primary": ["pt"],
                "topic_criteria": [
                    {"kind": "node_subtree", "key": "04-technology-science",
                     "note": "real taxonomy section (kind 0) of the bundled catalog"},
                    {"kind": "node_subtree", "key": "90_countries/brazil",
                     "note": "real country node (kind 1) of the bundled catalog"},
                    {"kind": "source_tag", "tag": "photography",
                     "note": "the bundled taxonomy has NO photography node; the catalog carries this interest in "
                             "the real `tags` column, so the criterion uses that real label"},
                ],
            },
            "B": {
                "id": "B",
                "description": "World news and technology, English",
                "language_codes": ["en", "en-US", "en-GB", "en-AU", "en-CA", "en-IE", "en-NZ", "en-ZA",
                                   "en-IN", "en-PH"],
                "language_primary": ["en"],
                "topic_criteria": [
                    {"kind": "node_subtree", "key": "04-technology-science"},
                    {"kind": "node_subtree", "key": "01-news-current-affairs/world-news"},
                ],
            },
        },
        "eligibility_rule": (
            "A source is eligible for a profile iff its catalog `language` primary subtag is in the profile's "
            "language_primary set AND (some placement node key equals or is prefixed by one of the profile's "
            "node_subtree keys, OR one of the profile's source_tag values appears in the source's comma-separated "
            "`tags` column). An item is eligible for a profile iff its source is eligible. The rule is computable "
            "from bench/corpus/catalog.sqlite alone, so the evaluator can recompute it independently."
        ),
        "thresholds": {
            "B01": [
                "No cenário rico do corpus, pelo menos 50 fontes distintas entram automaticamente no conjunto de "
                "aquisição elegível, e pelo menos 20 fontes distintas contribuem com os primeiros 300 cards.",
            ],
            "B02": [
                "≥80% dos 200 cards correspondem aos interesses/idiomas declarados, de acordo com o rótulo externo "
                "congelado; a distribuição de relevância por assunto/idioma é publicada junto do resultado.",
                "≥20 fontes distintas aparecem; nenhuma fonte representa >15% dos cards quando o corpus oferece "
                "alternativas.",
                "Zero pares de cards consecutivos da mesma fonte em contexto multi-fonte (PD-4), incluindo "
                "fronteiras de segmentos.",
                "Zero duplicatas de artigo canônico apresentadas como descobertas novas na mesma edição; uma edição "
                "material segue a decisão PD-1 e é contada separadamente.",
            ],
            "B03": [
                "instalação limpa em contexto rico com ≥5.000 itens elegíveis; replay externo de 30 minutos de "
                "avanços efetivos, a 1 card por segundo, com rajadas de até 3 cards por segundo durante 20 segundos "
                "a cada 5 minutos, usando gestos/scroll nativos.",
                "Zero fim artificial de feed, tela vazia, retorno ao início, repetição para disfarçar falta de "
                "supply ou loading que substitua a história visível enquanto ainda há conteúdo elegível disponível.",
                "Zero paralisação visível ≥1 segundo causada por falta de runway, no ambiente controlado desta "
                "baseline do benchmark.",
            ],
        },
        "trace": {
            "description": (
                "B03 trace: 30 minutes of effective advances driven by an external replayer using native gestures. "
                "Baseline is 1 card per second, with bursts of up to 3 cards per second for 20 seconds every 5 "
                "minutes (5 or 6 burst windows inside the 30 minutes, depending on whether a window starts at the "
                "30-minute boundary). Expected advances therefore lie between 2,000 and 2,040 distinct cards "
                "(1,800 baseline + 200-240 extra), which is the count the corpus must be able to serve from one "
                "profile's eligible supply."
            ),
            "duration_seconds": 1800,
            "baseline_cards_per_second": 1,
            "burst_cards_per_second": 3,
            "burst_seconds": 20,
            "burst_period_seconds": 300,
            "expected_advances_min": 2000,
            "expected_advances_max": 2040,
        },
        "provenance": {
            "generator": "bench/build_corpus.py",
            "seed": SEED,
            "fixed_base_timestamp": FIXED_NOW_ISO,
            "real_catalog": "FeedMineApp/FeedMineApp/Resources/catalog.sqlite",
            "real_catalog_sha256": repo_catalog_sha256,
            "transport_base_url": BASE_URL,
            "note": "Item identities and dates are generated from the real catalog's labels; no article text is "
                    "copied from the live internet. Headlines are synthesised from frozen word banks.",
        },
    }


# --------------------------------------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------------------------------------


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def stable_int(*parts) -> int:
    payload = "|".join(str(part) for part in parts).encode("utf-8")
    return int.from_bytes(hashlib.sha256(payload).digest()[:8], "big")


def rng_for(*parts) -> random.Random:
    return random.Random("|".join(str(part) for part in (SEED,) + parts))


def primary_subtag(code: str) -> str:
    code = (code or "").strip().lower()
    for separator in ("-", "_"):
        if separator in code:
            return code.split(separator, 1)[0]
    return code


def encode_key(key: str) -> str:
    """Percent-encoded so the key is one URL path segment and a safe file name."""
    return quote(key, safe="")


def png_bytes(width: int, height: int, bands: list[tuple[int, int, int]]) -> bytes:
    """A deterministic, valid PNG (RGB, 8-bit). No external dependency, byte-stable for identical arguments."""
    rows = bytearray()
    for y in range(height):
        band = bands[min(len(bands) - 1, (y * len(bands)) // height)]
        rows.append(0)  # filter type 0
        rows.extend(bytes(band) * width)

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(
            ">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
            + chunk(b"IEND", b""))


def ffmpeg_template(args: list[str]) -> bytes:
    """Renders a media template with ffmpeg into a temporary file (the mp4 muxer needs a seekable sink)."""
    import tempfile

    suffix = ".mp3" if "mp3" in args else ".mp4"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as handle:
        temporary = Path(handle.name)
    try:
        process = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args, str(temporary)],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if process.returncode != 0 or not temporary.exists() or temporary.stat().st_size == 0:
            raise RuntimeError("ffmpeg failed: " + process.stderr.decode("utf-8", "replace")[:400])
        return temporary.read_bytes()
    finally:
        temporary.unlink(missing_ok=True)


def slugify(text: str) -> str:
    out = []
    for char in text.lower():
        if char.isalnum():
            out.append(char)
        elif out and out[-1] != "-":
            out.append("-")
    return "".join(out).strip("-")[:60] or "item"


def xml_escape(text: str) -> str:
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;"))


def bucket_for(node_keys: list[str], tags: list[str]) -> str:
    """The item's independent topic label, from the source's most specific real taxonomy placement:
    a technology/science leaf anywhere in its path wins (country-scoped leaves included), then world news, then
    the Brazil country subtree, then the real `photography` tag. Never invented: every branch is a real node key.
    Global taxonomy nodes carry a numeric prefix (`04-technology-science`); country-scoped ones do not
    (`90_countries/brazil/technology-science/software-computing`), so both spellings are matched by segment."""
    def segments(key: str) -> list[str]:
        return key.split("/")

    def has(segments_of: list[str], name: str) -> bool:
        return name in segments_of or f"04-{name}" in segments_of or f"01-{name}" in segments_of

    if any(has(segments(key), "technology-science")
           and segments(key)[-1] in ("software-computing", "gadgets-engineering") for key in node_keys):
        return "technology"
    if any(has(segments(key), "technology-science") for key in node_keys):
        return "science"
    if any(has(segments(key), "world-news") for key in node_keys):
        return "world-news"
    if any(key == "90_countries/brazil" or key.startswith("90_countries/brazil/") for key in node_keys):
        return "brazil-news"
    if any(tag.strip().lower() == "photography" for tag in tags):
        return "photography"
    return "other"


def headline_for(bank: dict, index: int, stride: int, offset: int) -> str:
    leads, objects, quals, tails = bank["leads"], bank["objects"], bank["quals"], bank["tails"]
    total = len(leads) * len(objects) * len(quals) * len(tails)
    cursor = (offset + index * stride) % total
    tail_index = cursor % len(tails); cursor //= len(tails)
    qual_index = cursor % len(quals); cursor //= len(quals)
    object_index = cursor % len(objects); cursor //= len(objects)
    lead_index = cursor % len(leads)
    parts = [leads[lead_index], objects[object_index], quals[qual_index]]
    if tails[tail_index]:
        parts.append(tails[tail_index])
    return " ".join(parts)


def choose_stride(total: int, salt: str) -> int:
    """A stride coprime with `total`, so `index -> (index * stride) % total` is a bijection on [0, total)."""
    if total <= 1:
        return 1
    stride = (stable_int("stride", salt) % total) or 1
    while _gcd(stride, total) != 1:
        stride = stride % total + 1
    return stride


def _gcd(a: int, b: int) -> int:
    while b:
        a, b = b, a % b
    return a


COUNTRY_ISO = {
    "brazil": "BR", "portugal": "PT", "usa": "US", "united_states": "US", "united_kingdom": "GB",
    "canada": "CA", "australia": "AU", "india": "IN", "ireland": "IE", "new_zealand": "NZ",
    "south_africa": "ZA", "spain": "ES", "france": "FR", "germany": "DE", "italy": "IT",
    "netherlands": "NL", "belgium": "BE", "switzerland": "CH", "austria": "AT", "sweden": "SE",
    "norway": "NO", "denmark": "DK", "finland": "FI", "poland": "PL", "czech_republic": "CZ",
    "japan": "JP", "china": "CN", "south_korea": "KR", "russia": "RU", "mexico": "MX",
    "argentina": "AR", "chile": "CL", "colombia": "CO", "peru": "PE", "uruguay": "UY",
    "paraguay": "PY", "bolivia": "BO", "ecuador": "EC", "venezuela": "VE", "turkey": "TR",
    "greece": "GR", "hungary": "HU", "romania": "RO", "ukraine": "UA", "israel": "IL",
    "egypt": "EG", "nigeria": "NG", "kenya": "KE", "morocco": "MA", "indonesia": "ID",
    "vietnam": "VN", "thailand": "TH", "philippines": "PH", "malaysia": "MY", "singapore": "SG",
    "pakistan": "PK", "bangladesh": "BD", "iran": "IR", "iraq": "IQ", "saudi_arabia": "SA",
    "uae": "AE", "angola": "AO", "mozambique": "MZ", "cape_verde": "CV",
}


def region_for(language: str, node_keys: list[str]) -> str:
    """Region label: the country node when the catalog places the source in one, else the language variant.
    A country key without a known ISO code falls back to its own uppercased key (transparent, never invented)."""
    for key in node_keys:
        if key.startswith("90_countries/"):
            parts = key.split("/")
            if len(parts) >= 2 and primary_subtag(parts[1]) not in ("", "und"):
                country = parts[1].lower()
                return COUNTRY_ISO.get(country, country.upper())
    return REGION_BY_LANGUAGE_VARIANT.get(language, REGION_BY_LANGUAGE_VARIANT.get(primary_subtag(language), "INT"))


# --------------------------------------------------------------------------------------------------------------
# Real catalog access
# --------------------------------------------------------------------------------------------------------------


def read_real_catalog(path: Path) -> dict:
    connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        tables = {row[0] for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table'")}
        required = {"catalog_source", "catalog_node", "catalog_placement", "catalog_metadata"}
        missing = required - tables
        if missing:
            raise SystemExit(f"real catalog is missing tables: {sorted(missing)}")

        def eligible(profile: str) -> list[int]:
            if profile == "A":
                language_sql = "s.language IN ('pt','pt-BR')"
                topic_sql = ("cd.key LIKE '04-technology-science%' OR cd.key LIKE '90_countries/brazil%'"
                             " OR s.tags LIKE '%photograph%'")
            else:
                language_sql = "s.language LIKE 'en%'"
                topic_sql = ("cd.key LIKE '04-technology-science%'"
                             " OR cd.key LIKE '01-news-current-affairs/world-news%'")
            sql = f"""
                SELECT DISTINCT s.id FROM catalog_source s
                JOIN catalog_placement p ON p.source_id = s.id
                JOIN catalog_node cd ON cd.id = p.node_id
                WHERE {language_sql} AND ({topic_sql})
            """
            return sorted(row[0] for row in connection.execute(sql))

        profile_ids = {profile: set(eligible(profile)) for profile in ("A", "B")}
        union = profile_ids["A"] | profile_ids["B"]

        # Noise: real rows from other languages, so the recipe's filter has something to reject.
        noise_candidates = [row[0] for row in connection.execute(
            "SELECT id FROM catalog_source WHERE COALESCE(language,'') LIKE ? OR COALESCE(language,'') LIKE ? "
            "OR COALESCE(language,'') LIKE ? ORDER BY key",
            tuple(prefix + "%" for prefix in NOISE_LANGUAGES))]
        noise_candidates = [source_id for source_id in noise_candidates if source_id not in union]
        noise_rng = rng_for("noise")
        noise_ids = set(noise_rng.sample(noise_candidates, min(NOISE_SOURCES, len(noise_candidates))))

        selected_ids = union | noise_ids
        sources = {}
        for row in connection.execute("SELECT * FROM catalog_source"):
            if row["id"] in selected_ids:
                sources[row["id"]] = dict(row)
        if len(sources) != len(selected_ids):
            raise SystemExit("could not read every selected source row")
        sources = {source_id: sources[source_id] for source_id in sorted(sources)}

        placements = []
        for row in connection.execute("SELECT * FROM catalog_placement ORDER BY source_id, node_id, sort_order, id"):
            if row["source_id"] in selected_ids:
                placements.append(dict(row))
        nodes = {}
        for row in connection.execute("SELECT * FROM catalog_node"):
            nodes[row["id"]] = dict(row)

        metadata = {row["key"]: row["value"] for row in connection.execute("SELECT * FROM catalog_metadata")}
        ddl = {row["name"]: row["sql"] for row in connection.execute(
            "SELECT name, sql FROM sqlite_master WHERE type IN ('table','index') AND sql IS NOT NULL")}
        for source_id in sorted(sources):
            sources[source_id]["_profiles"] = [profile for profile in ("A", "B")
                                              if source_id in profile_ids[profile]]
        return {"sources": sources, "placements": placements, "nodes": nodes, "metadata": metadata, "ddl": ddl,
                "profile_ids": profile_ids, "noise_ids": noise_ids}
    finally:
        connection.close()


def write_catalog(path: Path, real: dict) -> dict:
    if path.exists():
        path.unlink()
    connection = sqlite3.connect(path)
    try:
        connection.execute("PRAGMA page_size=4096")
        connection.execute("PRAGMA journal_mode=OFF")
        connection.execute("PRAGMA synchronous=OFF")
        for name in ("catalog_metadata", "catalog_node", "catalog_source", "catalog_placement",
                     "catalog_source_fts"):
            connection.execute(real["ddl"][name])
        for name in ("idx_catalog_node_parent_name", "idx_catalog_source_title",
                     "idx_catalog_placement_node_order", "idx_catalog_placement_source"):
            connection.execute(real["ddl"][name])

        # Nodes: every placement node plus its ancestor chain (root included), counts recomputed for this catalog.
        # `parent_id` stays exactly as the real catalog has it (root NULL, sections 0), so the reader's own
        # `nodes(parentID: 0)` / `ancestors` walks keep their real semantics.
        kept_nodes: set[int] = {0}
        for placement in real["placements"]:
            node_id = placement["node_id"]
            guard = 0
            while node_id is not None and guard < 64:
                kept_nodes.add(node_id)
                parent = real["nodes"][node_id]["parent_id"]
                node_id = parent if parent is not None else None
                guard += 1
        source_counts = {node_id: 0 for node_id in kept_nodes}
        for placement in real["placements"]:
            node_id = placement["node_id"]
            guard = 0
            while node_id is not None and guard < 64:
                if node_id in source_counts:
                    source_counts[node_id] += 1
                parent = real["nodes"][node_id]["parent_id"]
                node_id = parent if parent is not None else None
                guard += 1
        child_counts = {node_id: 0 for node_id in kept_nodes}
        for node_id in kept_nodes:
            parent = real["nodes"][node_id]["parent_id"]
            if parent is not None and parent in child_counts:
                child_counts[parent] += 1

        node_rows = 0
        for node_id in sorted(kept_nodes):
            node = real["nodes"][node_id]
            connection.execute(
                "INSERT INTO catalog_node(id,key,parent_id,name,kind,source_count,child_count,language) "
                "VALUES(?,?,?,?,?,?,?,?)",
                (node["id"], node["key"], node["parent_id"], node["name"],
                 node["kind"], source_counts[node_id], child_counts[node_id], node["language"]))
            node_rows += 1

        source_rows = 0
        for source_id in sorted(real["sources"]):
            row = real["sources"][source_id]
            key = row["key"]
            request_url = f"{BASE_URL}/s/{encode_key(key)}"
            connection.execute(
                "INSERT INTO catalog_source(id,key,title,declared_url,request_url,display_host,media_kind,"
                "language,site_url,description,tags,nature,activity,latest_item_at,quality_score,default_enabled,type)"
                " VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (row["id"], key, row["title"], row["declared_url"], request_url, row["display_host"],
                 row["media_kind"], row["language"], row["site_url"], row["description"], row["tags"],
                 row["nature"], row["activity"], row["latest_item_at"], row["quality_score"],
                 row["default_enabled"], row["type"]))
            source_rows += 1

        placement_rows = 0
        for placement in real["placements"]:
            connection.execute(
                "INSERT INTO catalog_placement(id,source_id,node_id,node_name,opml_file,sort_order,"
                "title_override,language_override,media_kind_override) VALUES(?,?,?,?,?,?,?,?,?)",
                (placement["id"], placement["source_id"], placement["node_id"], placement["node_name"],
                 placement["opml_file"], placement["sort_order"], placement["title_override"],
                 placement["language_override"], placement["media_kind_override"]))
            placement_rows += 1

        for source_id in sorted(real["sources"]):
            row = real["sources"][source_id]
            path_keys = []
            for placement in real["placements"]:
                if placement["source_id"] == source_id:
                    path_keys.append(real["nodes"][placement["node_id"]]["key"].replace("/", " "))
            deepest = max(path_keys, key=len) if path_keys else ""
            connection.execute(
                "INSERT INTO catalog_source_fts(rowid,title,description,tags,display_host,language,media_kind,path)"
                " VALUES(?,?,?,?,?,?,?,?)",
                (row["id"], row["title"], row["description"] or "", row["tags"] or "",
                 row["display_host"] or "", row["language"] or "", row["media_kind"], deepest))

        metadata = dict(real["metadata"])
        real_source_count = metadata.get("source_count", "?")
        metadata["source_count"] = str(source_rows)
        metadata["node_count"] = str(node_rows)
        metadata["placement_count"] = str(placement_rows)
        metadata["bench_corpus"] = "feedmine-discovery-acceptance-benchmark"
        metadata["bench_corpus_real_catalog_source_count"] = str(real_source_count)
        metadata["bench_corpus_transport_base_url"] = BASE_URL
        for key in sorted(metadata):
            connection.execute("INSERT INTO catalog_metadata(key,value) VALUES(?,?)", (key, metadata[key]))
        connection.commit()
        connection.execute("ANALYZE")
        connection.commit()
        return {"sources": source_rows, "nodes": node_rows, "placements": placement_rows}
    finally:
        connection.close()


# --------------------------------------------------------------------------------------------------------------
# Item generation
# --------------------------------------------------------------------------------------------------------------


def generate_sources(real: dict) -> tuple[list[dict], dict[str, int]]:
    """The per-source transport plan: protocol, delays, failure class, item count."""
    plans = []
    empty_ids = set()
    global_budget: dict[str, int] = {}
    for source_id in sorted(real["sources"]):
        row = real["sources"][source_id]
        key = row["key"]
        node_keys = sorted({real["nodes"][placement["node_id"]]["key"]
                            for placement in real["placements"] if placement["source_id"] == source_id})
        tags = [tag.strip() for tag in (row["tags"] or "").split(",") if tag.strip()]
        language = row["language"] or "und"
        language_primary = primary_subtag(language) or "und"
        profiles = row["_profiles"]
        bucket = bucket_for(node_keys, tags)

        roll = stable_int("class", key) % 1000
        if roll < BEHAVIOUR_NORMAL:
            behaviour: dict = {"class": "normal"}
        elif roll < BEHAVIOUR_NORMAL + BEHAVIOUR_SLOW:
            delay = 2500 + (stable_int("delay", key) % 3501)
            behaviour = {"class": "slow", "delay_ms": delay}
        elif roll < BEHAVIOUR_NORMAL + BEHAVIOUR_SLOW + BEHAVIOUR_INTERMITTENT:
            if stable_int("failshape", key) % 2 == 0:
                behaviour = {"class": "intermittent", "fail_every": 3, "statuses": [500, 503]}
            else:
                behaviour = {"class": "intermittent", "fail_every": 4, "statuses": [503]}
        else:
            behaviour = {"class": "timeout", "hang_every": 4, "hang_seconds": 12, "status": 504}

        empty = (stable_int("empty", key) % 1000) < EMPTY_SOURCES_PER_MILLE
        if empty:
            empty_ids.add(key)
        protocol_roll = stable_int("protocol", key) % 1000
        protocol = "rss" if protocol_roll < PROTOCOL_CUTS[0] else (
            "atom" if protocol_roll < PROTOCOL_CUTS[1] else "jsonfeed")
        media_roll = stable_int("slowmedia", key) % 1000
        media_delay = (2500 + stable_int("mediadelay", key) % 4501) if media_roll < SLOW_MEDIA_PER_MILLE else 0
        if empty:
            item_count = 0
        elif profiles:
            item_count = ITEMS_PER_PROFILE_SOURCE[0] + stable_int("count", key) % (
                ITEMS_PER_PROFILE_SOURCE[1] - ITEMS_PER_PROFILE_SOURCE[0] + 1)
        else:
            item_count = ITEMS_PER_NOISE_SOURCE[0] + stable_int("count", key) % (
                ITEMS_PER_NOISE_SOURCE[1] - ITEMS_PER_NOISE_SOURCE[0] + 1)

        bank_key = f"{language_primary}-{bucket}" if bucket != "other" else f"{language_primary}-other"
        if bank_key not in BANKS:
            bank_key = f"{language_primary}-other"
        if bank_key not in BANKS:
            bank_key = "en-other"
        plans.append({
            "key": key,
            "title": row["title"],
            "language": language,
            "language_primary": language_primary,
            "media_kind": row["media_kind"],
            "nature": row["nature"],
            "activity": row["activity"],
            "quality_score": row["quality_score"],
            "default_enabled": row["default_enabled"],
            "tags": tags,
            "node_keys": node_keys,
            "profiles": profiles,
            "topic_bucket": bucket,
            "topic_node_key": max(node_keys, key=len) if node_keys else "",
            "region": region_for(language, node_keys),
            "bank": bank_key,
            "protocol": protocol,
            "content_type": PROTOCOL_TYPES[protocol][0],
            "extension": PROTOCOL_TYPES[protocol][1],
            "behaviour": behaviour,
            "empty": empty,
            "media_delay_ms": media_delay,
            "item_count": item_count,
            "feed_path": f"feeds/{hashlib.sha1(key.encode('utf-8')).hexdigest()[:40]}{PROTOCOL_TYPES[protocol][1]}",
            "feed_key_sha1": hashlib.sha1(key.encode("utf-8")).hexdigest(),
            "source_url": f"{BASE_URL}/s/{encode_key(key)}",
        })
        global_budget[language_primary] = global_budget.get(language_primary, 0) + item_count
    return plans, global_budget


def generate_items(plans: list[dict]) -> list[dict]:
    items: list[dict] = []
    bank_index: dict[str, int] = {}
    bank_stride: dict[str, int] = {}
    for bank_key, bank in BANKS.items():
        total = len(bank["leads"]) * len(bank["objects"]) * len(bank["quals"]) * len(bank["tails"])
        bank_stride[bank_key] = choose_stride(total, bank_key)
        # The index must start at 0 so the coprime stride actually visits the whole bank; per-bank variety comes
        # from the stride itself, not from an offset that would silently shrink the usable space.
        bank_index[bank_key] = 0
    for plan in plans:
        if plan["empty"]:
            continue
        bank_key = plan["bank"]
        bank = BANKS[bank_key]
        source_hash = hashlib.sha1(plan["key"].encode("utf-8")).hexdigest()
        minute_base = stable_int("minute", plan["key"]) % 2880
        minute_step = 7 + stable_int("step", plan["key"]) % 97
        for slot in range(plan["item_count"]):
            index = bank_index[bank_key]
            capacity = (len(bank["leads"]) * len(bank["objects"]) * len(bank["quals"]) * len(bank["tails"]))
            if index >= capacity:
                raise SystemExit(f"headline bank {bank_key} is exhausted ({index} >= {capacity}); "
                                 f"enlarge the bank so headlines stay distinct")
            bank_index[bank_key] = index + 1
            title = headline_for(bank, index, bank_stride[bank_key], 0)
            template = bank["summaries"][stable_int("summary", plan["key"], slot) % len(bank["summaries"])]
            summary = " ".join(template.format(
                object=bank["objects"][stable_int("ob", plan["key"], slot) % len(bank["objects"])],
                qual=bank["quals"][stable_int("ql", plan["key"], slot) % len(bank["quals"])],
                tail="").split())
            published = FIXED_NOW - timedelta(minutes=minute_base + slot * minute_step)
            uid = f"{source_hash[:12]}-{slot:03d}"
            canonical = "urn:article:" + hashlib.sha1(
                f"{plan['key']}#{title}".encode("utf-8")).hexdigest()[:20]

            if plan["media_kind"] == "video":
                media_kind, media_type = "video", "video/mp4"
            elif plan["media_kind"] == "audio":
                media_kind, media_type = "audio", "audio/mpeg"
            else:
                has_image = (stable_int("media", uid) % 100) < 60
                media_kind, media_type = ("image", "image/png") if has_image else ("none", None)

            kind_class = "text" if media_kind in ("none", "image") else media_kind
            duration = {"audio": 2.0, "video": 1.0}.get(media_kind)
            items.append({
                # --- the evaluator interface (bench/README.md) ---
                "id": uid,
                "source_key": plan["key"],
                "canonical": canonical,
                "revision": 0,
                "headline": title,
                "summary": summary,
                "topic": plan["topic_node_key"],
                "language": plan["language_primary"],
                "region": plan["region"].lower(),
                "published_at": published.strftime("%Y-%m-%dT%H:%M:%SZ"),
                "media": {
                    "kind": media_kind,
                    "url": f"{BASE_URL}/m/{uid}" if media_kind != "none" else None,
                    "content_type": media_type,
                    "duration_seconds": duration,
                    "bytes": None,   # filled from the media pack after it is written
                },
                # --- additive provenance the oracles use ---
                "link": f"{BASE_URL}/a/{uid}",
                "source_title": plan["title"],
                "language_code": plan["language"],
                "topic_bucket": plan["topic_bucket"],
                "topic_node_keys": plan["node_keys"],
                "eligible_profiles": plan["profiles"],
                "origin": "own",
                "material_revision": False,
                "revision_of": None,
                "duplicate_of": None,
                "kind_class": kind_class,
            })
    return items


def inject_duplicates(items: list[dict]) -> dict:
    counts = {"pairs": 0, "revisions": 0}
    for profile in ("A", "B"):
        groups: dict[tuple, list[int]] = {}
        for position, item in enumerate(items):
            if item["origin"] == "own" and profile in item["eligible_profiles"]:
                groups.setdefault((item["topic_bucket"], item["language"], item["kind_class"]),
                                  []).append(position)
        pairs: list[tuple[int, int]] = []
        used: set[int] = set()
        leftovers: list[int] = []
        for group in sorted(groups):
            positions = list(groups[group])
            random.Random(f"{SEED}:dup:{profile}:{group}").shuffle(positions)
            cursor = 0
            while cursor + 1 < len(positions) and len(pairs) < PAIRS_PER_PROFILE[profile]:
                first, second = positions[cursor], positions[cursor + 1]
                cursor += 2
                if first in used or second in used:
                    continue
                if items[first]["source_key"] == items[second]["source_key"]:
                    continue
                pairs.append((first, second))
                used.add(first); used.add(second)
            leftovers.extend(positions[cursor:])
        revisions = 0
        revision_budget = REVISIONS_PER_PROFILE[profile]
        for first, second in pairs:
            base = items[first]
            twin = items[second]
            twin["canonical"] = base["canonical"]
            twin["origin"] = "syndicated"
            twin["duplicate_of"] = base["id"]
            counts["pairs"] += 1
            if revisions < revision_budget:
                third = next((position for position in leftovers
                              if position not in used
                              and items[position]["source_key"] not in (base["source_key"], twin["source_key"])
                              and items[position]["kind_class"] == base["kind_class"]), None)
                if third is None:
                    continue
                used.add(third)
                update = items[third]
                update["canonical"] = base["canonical"]
                update["origin"] = "material-revision"
                update["material_revision"] = True
                update["revision"] = 1
                update["revision_of"] = base["id"]
                update["headline"] = "Atualização: " + base["headline"]
                update["summary"] = "Versão materialmente revisada de uma história já publicada. " + base["summary"]
                original = datetime.strptime(base["published_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
                update["published_at"] = (original + timedelta(hours=6)).strftime("%Y-%m-%dT%H:%M:%SZ")
                revisions += 1
                counts["revisions"] += 1
        if not pairs:
            raise SystemExit(f"profile {profile} produced no cross-publisher duplicate pairs")
    for item in items:
        item.pop("kind_class", None)
    return counts


# --------------------------------------------------------------------------------------------------------------
# Feed rendering
# --------------------------------------------------------------------------------------------------------------


def rfc822(timestamp: str) -> str:
    return format_datetime(datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc),
                           usegmt=True)


def render_rss(plan: dict, items: list[dict]) -> str:
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" '
             'xmlns:media="http://search.yahoo.com/mrss/" '
             'xmlns:content="http://purl.org/rss/1.0/modules/content/">',
             '<channel>',
             f'<title>{xml_escape(plan["title"])}</title>',
             f'<link>{xml_escape(BASE_URL + "/s/" + encode_key(plan["key"]))}</link>',
             f'<description>{xml_escape(plan["title"] + " — benchmark feed document")}</description>',
             f'<language>{xml_escape(plan["language"])}</language>',
             f'<lastBuildDate>{rfc822(FIXED_NOW_ISO)}</lastBuildDate>',
             f'<atom:link href="{xml_escape(plan["source_url"])}" rel="self" '
             f'type="{PROTOCOL_TYPES["rss"][0]}"/>']
    for item in items:
        media = item["media"]
        length = (media.get("bytes") or {}).get("length") or 0
        lines.append("<item>")
        lines.append(f'<title>{xml_escape(item["headline"])}</title>')
        lines.append(f'<link>{xml_escape(item["link"])}</link>')
        lines.append(f'<guid isPermaLink="false">{xml_escape(item["canonical"])}</guid>')
        lines.append(f'<pubDate>{rfc822(item["published_at"])}</pubDate>')
        lines.append(f'<description>{xml_escape(item["summary"])}</description>')
        if media["kind"] == "image":
            lines.append(f'<content:encoded><![CDATA[<p>{xml_escape(item["summary"])}</p>'
                         f'<img src="{xml_escape(media["url"])}" alt=""/>]]></content:encoded>')
            lines.append(f'<enclosure url="{xml_escape(media["url"])}" type="image/png" length="{length}"/>')
            lines.append(f'<media:thumbnail url="{xml_escape(media["url"])}"/>')
            lines.append(f'<media:content url="{xml_escape(media["url"])}" type="image/png" medium="image"/>')
        elif media["kind"] == "video":
            lines.append(f'<enclosure url="{xml_escape(media["url"])}" type="video/mp4" length="{length}"/>')
            lines.append(f'<media:content url="{xml_escape(media["url"])}" type="video/mp4" medium="video"/>')
        elif media["kind"] == "audio":
            lines.append(f'<enclosure url="{xml_escape(media["url"])}" type="audio/mpeg" length="{length}"/>')
            lines.append(f'<media:content url="{xml_escape(media["url"])}" type="audio/mpeg" medium="audio"/>')
        lines.append("</item>")
    lines.append("</channel>")
    lines.append("</rss>")
    return "\n".join(lines) + "\n"


def render_atom(plan: dict, items: list[dict]) -> str:
    feed_id = "urn:feedmine-bench:source:" + hashlib.sha1(plan["key"].encode("utf-8")).hexdigest()[:16]
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/">',
             f'<title>{xml_escape(plan["title"])}</title>',
             f'<id>{feed_id}</id>',
             f'<updated>{FIXED_NOW_ISO}</updated>',
             f'<link rel="alternate" href="{xml_escape(plan["source_url"])}"/>',
             f'<link rel="self" href="{xml_escape(plan["source_url"])}" type="{PROTOCOL_TYPES["atom"][0]}"/>']
    for item in items:
        media = item["media"]
        lines.append("<entry>")
        lines.append(f'<title>{xml_escape(item["headline"])}</title>')
        lines.append(f'<id>{xml_escape(item["canonical"])}</id>')
        lines.append(f'<updated>{item["published_at"]}</updated>')
        lines.append(f'<published>{item["published_at"]}</published>')
        lines.append(f'<link rel="alternate" href="{xml_escape(item["link"])}"/>')
        if media["kind"] != "none":
            lines.append(f'<link rel="enclosure" type="{media["content_type"]}" '
                         f'href="{xml_escape(media["url"])}"/>')
            lines.append(f'<media:content url="{xml_escape(media["url"])}" '
                         f'type="{media["content_type"]}"/>')
        lines.append(f'<summary type="text">{xml_escape(item["summary"])}</summary>')
        lines.append("</entry>")
    lines.append("</feed>")
    return "\n".join(lines) + "\n"


def render_jsonfeed(plan: dict, items: list[dict]) -> str:
    document = {
        "version": "https://jsonfeed.org/version/1.1",
        "title": plan["title"],
        "home_page_url": plan["source_url"],
        "feed_url": plan["source_url"],
        "language": plan["language"],
        "items": [],
    }
    for item in items:
        media = item["media"]
        entry = {
            "id": item["canonical"],
            "url": item["link"],
            "title": item["headline"],
            "summary": item["summary"],
            "date_published": item["published_at"],
        }
        if media["kind"] != "none":
            entry["attachments"] = [{"url": media["url"], "mime_type": media["content_type"]}]
        if media["kind"] == "image":
            entry["image"] = media["url"]
        document["items"].append(entry)
    return json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def article_html(item: dict) -> bytes:
    """Deterministic rendering of a frozen item record by the frozen server (see bench/README.md)."""
    paragraphs = [item["summary"],
                  f"Reportagem da fonte {item['source_title']} para o perfil "
                  f"{' e '.join(item['eligible_profiles']) or 'fora dos perfis principais'}. "
                  f"Identificador canônico: {item['canonical']} (revisão {item['revision']}).",
                  "Conteúdo de referência do corpus de aceitação do FeedMine; não é uma publicação real."]
    body = "\n".join(f"<p>{xml_escape(paragraph)}</p>" for paragraph in paragraphs)
    image = ""
    if item["media"]["kind"] == "image":
        image = f'<p><img src="{xml_escape(item["media"]["url"])}" alt=""/></p>'
    html = f"""<!DOCTYPE html>
<html lang="{xml_escape(item['language'] or 'und')}">
<head><meta charset="utf-8"/><title>{xml_escape(item['headline'])}</title></head>
<body>
<article data-canonical-article-id="{xml_escape(item['canonical'])}" data-revision="{item['revision']}">
<h1>{xml_escape(item['headline'])}</h1>
<p><time datetime="{item['published_at']}">{item['published_at']}</time> — {xml_escape(item['source_title'])}</p>
{image}
{body}
</article>
</body>
</html>
"""
    return html.encode("utf-8")


# --------------------------------------------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------------------------------------------


def write_feeds(plans: list[dict], items_by_source: dict[str, list[dict]]) -> None:
    if FEEDS_DIR.exists():
        shutil.rmtree(FEEDS_DIR)
    FEEDS_DIR.mkdir(parents=True)
    for plan in plans:
        source_items = items_by_source.get(plan["key"], [])
        if plan["protocol"] == "rss":
            text = render_rss(plan, source_items)
        elif plan["protocol"] == "atom":
            text = render_atom(plan, source_items)
        else:
            text = render_jsonfeed(plan, source_items)
        path = CORPUS_DIR / plan["feed_path"]
        path.write_text(text, encoding="utf-8")
        plan["feed_bytes"] = path.stat().st_size
        plan["feed_sha256"] = sha256_file(path)


def build_media_pack(items: list[dict], templates: dict[str, bytes]) -> dict:
    pack_path = CORPUS_DIR / "media.pack"
    offsets: dict[str, dict] = {}
    with pack_path.open("wb") as handle:
        cursor = 0
        for item in items:
            kind = item["media"]["kind"]
            if kind == "none":
                continue
            if kind == "image":
                seed = stable_int("image", item["id"])
                base = ((seed >> 8) & 0xFF, (seed >> 16) & 0xFF, (seed >> 24) & 0xFF)
                accent = ((base[0] + 96) % 256, (base[1] + 160) % 256, (base[2] + 32) % 256)
                payload = png_bytes(160, 96, [base, base, accent, base])
            elif kind == "video":
                payload = templates["video"]
            else:
                payload = templates["audio"]
            handle.write(payload)
            offsets[item["id"]] = {"offset": cursor, "length": len(payload), "sha256": sha256_bytes(payload)}
            cursor += len(payload)
    return {"path": "media.pack", "bytes": pack_path.stat().st_size, "entries": offsets}


def build(catalog_path: Path, rebuild: bool) -> None:
    manifest_path = BENCH_DIR / "manifest.json"
    if CORPUS_DIR.exists() and manifest_path.exists() and not rebuild:
        raise SystemExit("bench/corpus is already frozen. Regenerating is deliberate: pass --rebuild.")
    if not catalog_path.exists():
        raise SystemExit(f"real catalog not found: {catalog_path}")
    if not BENCHMARK_DOC.exists():
        raise SystemExit(f"benchmark document not found: {BENCHMARK_DOC}")

    real_catalog_sha = sha256_file(catalog_path)
    print(f"real catalog      : {catalog_path} ({catalog_path.stat().st_size} bytes, sha256 {real_catalog_sha[:16]}…)")
    real = read_real_catalog(catalog_path)
    print(f"profile A rows    : {len(real['profile_ids']['A'])}")
    print(f"profile B rows    : {len(real['profile_ids']['B'])}")
    print(f"noise rows        : {len(real['noise_ids'])}")
    print(f"selected rows     : {len(real['sources'])}")

    if rebuild and CORPUS_DIR.exists():
        shutil.rmtree(CORPUS_DIR)
    CORPUS_DIR.mkdir(parents=True, exist_ok=True)

    catalog_counts = write_catalog(CORPUS_DIR / "catalog.sqlite", real)
    print(f"catalog written   : sources={catalog_counts['sources']} nodes={catalog_counts['nodes']} "
          f"placements={catalog_counts['placements']}")

    plans, _ = generate_sources(real)
    items = generate_items(plans)
    duplicates = inject_duplicates(items)
    print(f"items generated   : {len(items)} (duplicate pairs={duplicates['pairs']}, "
          f"material revisions={duplicates['revisions']})")

    items_by_source: dict[str, list[dict]] = {}
    for item in items:
        items_by_source.setdefault(item["source_key"], []).append(item)
    for source_items in items_by_source.values():
        source_items.sort(key=lambda entry: (entry["published_at"], entry["id"]), reverse=True)

    templates = {
        "audio": ffmpeg_template(["-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono", "-t", "2", "-b:a", "32k",
                                  "-acodec", "libmp3lame", "-f", "mp3"]),
        "video": ffmpeg_template(["-f", "lavfi", "-i", "testsrc=size=160x120:rate=10", "-t", "1",
                                  "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-f", "mp4"]),
    }
    media = build_media_pack(items, templates)
    print(f"media pack        : {media['bytes']} bytes, {len(media['entries'])} entries")
    for item in items:
        item["media"]["bytes"] = media["entries"].get(item["id"])

    write_feeds(plans, items_by_source)
    print(f"feeds written     : {len(plans)}")

    # ---- Verification before anything is declared frozen -------------------------------------------------
    eligible_sources = {profile: 0 for profile in ("A", "B")}
    eligible_items = {profile: 0 for profile in ("A", "B")}
    for plan in plans:
        for profile in plan["profiles"]:
            eligible_sources[profile] += 1
    for item in items:
        for profile in item["eligible_profiles"]:
            eligible_items[profile] += 1
    titles = [item["headline"] for item in items]
    duplicates_titles = len(titles) - len(set(titles))
    canonicals: dict[str, list[str]] = {}
    for item in items:
        canonicals.setdefault(item["canonical"], []).append(item["id"])
    shared = {cid: uids for cid, uids in canonicals.items() if len(uids) > 1}
    protocols = {}
    behaviours = {}
    for plan in plans:
        protocols[plan["protocol"]] = protocols.get(plan["protocol"], 0) + 1
        behaviours[plan["behaviour"]["class"]] = behaviours.get(plan["behaviour"]["class"], 0) + 1
    empty_feeds = sum(1 for plan in plans if plan["empty"])
    slow_media = sum(1 for plan in plans if plan["media_delay_ms"])
    problems = []
    for profile in ("A", "B"):
        if eligible_sources[profile] < 300:
            problems.append(f"profile {profile} has {eligible_sources[profile]} eligible sources (<300)")
        if eligible_items[profile] < 5000:
            problems.append(f"profile {profile} has {eligible_items[profile]} eligible items (<5000)")
    if len(items) < 5000:
        problems.append(f"only {len(items)} items were generated (<5000)")
    if duplicates_titles:
        problems.append(f"{duplicates_titles} duplicate headlines")
    if set(protocols) != {"rss", "atom", "jsonfeed"}:
        problems.append(f"protocol set is incomplete: {sorted(protocols)}")
    for required in ("normal", "slow", "intermittent", "timeout"):
        if behaviours.get(required, 0) == 0:
            problems.append(f"behaviour class {required} is absent")
    for profile in ("A", "B"):
        member_classes = {plan["behaviour"]["class"] for plan in plans if profile in plan["profiles"]}
        missing = {"normal", "slow", "intermittent", "timeout"} - member_classes
        if missing:
            problems.append(f"profile {profile} misses behaviour classes {sorted(missing)}")
        member_protocols = {plan["protocol"] for plan in plans if profile in plan["profiles"]}
        if member_protocols != {"rss", "atom", "jsonfeed"}:
            problems.append(f"profile {profile} misses protocols {sorted({'rss', 'atom', 'jsonfeed'} - member_protocols)}")
    if not shared:
        problems.append("no cross-publisher duplicates were produced")
    print()
    print("verification")
    print(f"  eligible sources     : A={eligible_sources['A']} B={eligible_sources['B']}")
    print(f"  eligible items       : A={eligible_items['A']} B={eligible_items['B']}")
    print(f"  items total          : {len(items)}")
    print(f"  distinct headlines   : {len(set(titles))}")
    print(f"  canonical shared ids : {len(shared)}")
    print(f"  protocols            : {protocols}")
    print(f"  behaviour classes    : {behaviours}")
    print(f"  empty documents      : {empty_feeds}")
    print(f"  slow-media sources   : {slow_media}")
    if problems:
        for problem in problems:
            print(f"  PROBLEM: {problem}")
        raise SystemExit("corpus verification failed; nothing was frozen")

    # ---- Freeze -------------------------------------------------------------------------------------------
    criteria = load_criteria(real_catalog_sha)
    criteria["profiles_file"] = "profiles.json"
    ready_profiles = {
        "A": {
            "interests": ["04-technology-science", "90_countries/brazil"],
            "languages": ["pt"],
            "region": "90_countries/brazil",
            "source_tags": ["photography"],
            "interest_notes": (
                "photography has no taxonomy node in the real catalog; the interest is expressed by the real "
                "`tags` column, so the third interest is a tag match, not a node key"),
            "eligible_sources": eligible_sources["A"],
            "eligible_items": eligible_items["A"],
            "profile_id": "A",
        },
        "B": {
            "interests": ["04-technology-science", "01-news-current-affairs/world-news"],
            "languages": ["en"],
            "region": None,
            "source_tags": [],
            "interest_notes": (
                "profile B is section-scoped (world news + technology), not country-scoped, so it has no single "
                "country node key to offer as a region answer; region is null rather than invented"),
            "eligible_sources": eligible_sources["B"],
            "eligible_items": eligible_items["B"],
            "profile_id": "B",
        },
    }
    (CORPUS_DIR / "profiles.json").write_text(
        json.dumps(ready_profiles, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (CORPUS_DIR / "criteria.json").write_text(
        json.dumps(criteria, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    ordered_items = sorted(items, key=lambda entry: (entry["source_key"], entry["published_at"], entry["id"]),
                           reverse=False)
    totals_document = {
        "sources": len(plans),
        "items": len(items),
        "eligible_sources": eligible_sources,
        "eligible_items": eligible_items,
        "protocols": protocols,
        "behaviour_classes": behaviours,
        "empty_documents": empty_feeds,
        "slow_media_sources": slow_media,
        "canonical_articles_shared": len(shared),
        "cross_publisher_duplicate_pairs": duplicates["pairs"],
        "material_revision_items": duplicates["revisions"],
        "item_topics": {topic: sum(1 for item in items if item["topic_bucket"] == topic)
                        for topic in sorted({item["topic_bucket"] for item in items})},
        "source_topics": {topic: sum(1 for plan in plans if plan["topic_bucket"] == topic)
                          for topic in sorted({plan["topic_bucket"] for plan in plans})},
        "media_kinds": {kind: sum(1 for item in items if item["media"]["kind"] == kind)
                        for kind in sorted({item["media"]["kind"] for item in items})},
        "distinct_headlines": len(set(titles)),
    }
    items_document = {
        "schema": "feedmine-bench-items/1",
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "seed": SEED,
        "profiles": ready_profiles,
        "transport_base_url": BASE_URL,
        "totals": totals_document,
        "field_notes": {
            "canonical": "shared by deliberate cross-publisher duplicates (same article, retitled by the "
                         "second publisher)",
            "revision": "0 = original edition of that canonical article; the material revision item carries a "
                        "later ordinal and material_revision=true",
            "topic": "the source's most specific real catalog node key",
            "media.url": "served by bench/serve.py at /m/<asset>; media.bytes is its frozen slice of media.pack",
        },
        "items": ordered_items,
    }
    (CORPUS_DIR / "items.json").write_text(
        json.dumps(items_document, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8")
    sources_document = {
        "schema": "feedmine-bench-sources/1",
        "transport_base_url": BASE_URL,
        "seed": SEED,
        "generated_from": {"catalog": "FeedMineApp/FeedMineApp/Resources/catalog.sqlite",
                           "catalog_sha256": real_catalog_sha},
        "totals": totals_document,
        "profiles": ready_profiles,
        "sources": {plan["key"]: plan for plan in plans},
    }
    (CORPUS_DIR / "sources.json").write_text(
        json.dumps(sources_document, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    artifact_paths = [
        BENCH_DIR / "build_corpus.py",
        BENCH_DIR / "serve.py",
        BENCH_DIR / "README.md",
        CORPUS_DIR / "catalog.sqlite",
        CORPUS_DIR / "items.json",
        CORPUS_DIR / "profiles.json",
        CORPUS_DIR / "sources.json",
        CORPUS_DIR / "criteria.json",
        CORPUS_DIR / "media.pack",
    ]
    artifact_paths += sorted(FEEDS_DIR.glob("*"))
    artifacts = []
    for path in artifact_paths:
        if not path.exists():
            raise SystemExit(f"required artifact missing: {path}")
        artifacts.append({"path": str(path.relative_to(BENCH_DIR)).replace(os.sep, "/"),
                          "sha256": sha256_file(path), "bytes": path.stat().st_size})
    feed_digest = hashlib.sha256("".join(
        sorted(entry["sha256"] for entry in artifacts
               if entry["path"].startswith("corpus/feeds/"))).encode()).hexdigest()

    manifest = {
        "schema": "feedmine-bench-manifest/1",
        "frozen": True,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "generated_by": "bench/build_corpus.py",
        "seed": SEED,
        "note": ("Corpus and oracle inputs for the FeedMine discovery acceptance benchmark "
                 "(docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md §2). Produced outside production code, frozen "
                 "before any candidate build runs. A run's results belong in a separate report; this manifest "
                 "claims no gate result."),
        "regeneration": "deliberate: `python3 bench/build_corpus.py --rebuild`",
        "totals": sources_document["totals"],
        "transport_base_url": BASE_URL,
        "feed_document_digest": feed_digest,
        "criteria": criteria,
        "artifacts": artifacts,
    }
    (BENCH_DIR / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    lines = [f"{entry['sha256']}  {entry['path']}" for entry in artifacts]
    (BENCH_DIR / "MANIFEST.sha256").write_text("\n".join(lines) + "\n", encoding="utf-8")

    print()
    print("frozen")
    print(f"  bench/manifest.json       : {len(artifacts)} hashed artifacts, feed digest {feed_digest[:16]}…")
    print(f"  bench/MANIFEST.sha256     : {len(lines)} lines")
    print(f"  bench/corpus/items.json   : {(CORPUS_DIR / 'items.json').stat().st_size} bytes")
    print(f"  bench/corpus/catalog.sqlite: {(CORPUS_DIR / 'catalog.sqlite').stat().st_size} bytes")
    print(f"  bench/corpus/media.pack   : {(CORPUS_DIR / 'media.pack').stat().st_size} bytes")


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the frozen FeedMine acceptance benchmark corpus.")
    parser.add_argument("--rebuild", action="store_true",
                        help="deliberately regenerate an already frozen corpus (rewrites the manifest)")
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG,
                        help="path to the repository's real bundled catalog.sqlite (read-only)")
    arguments = parser.parse_args()
    build(arguments.catalog, arguments.rebuild)


if __name__ == "__main__":
    main()
