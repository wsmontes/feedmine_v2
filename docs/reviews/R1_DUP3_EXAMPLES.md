# R1/DUP-3 — real examples, positive and negative

Requested by the architect on 2026-10-10 before any `contentClusterID` or semantic deduplication is
considered: *"OMP deverá apresentar um conjunto real de exemplos positivos e negativos, incluindo
notícias em idiomas diferentes. Não quero um mecanismo que elimine três perspectivas legítimas porque
compartilham personagens e palavras-chave."*

Source: the soak run's own database (22,186 supply candidates, 1,347 sources, 1,415 enabled targets),
read-only. Titles and locators below are verbatim.

## Class 1 — safe to consolidate: one canonical locator under two SourceIDs

Signal: the same normalized content locator (article URL / video id / Atom id) carried by two sources
that share no `SourceID`.

- **45 locators, 90 candidates** (0.4 % of supply).
- Largest cluster, 25 posts: one Blogger blog, `tag:blogger.com,1999:blog-970993311301307639`, reached
  through **two distinct SourceIDs** — `ANDRES CALAMARO DISCOGRAFIA`,
  `FULGOL EN VIVO WWW.FULGOL.TK EL PARTIDO DE FUTBOL`, and 23 more, identical ids.
- Same video carried twice: `yt:video:w7Z8-3cWLpE` — *TINI - Una Noche Más (Making Of)*.
- Same publication, two paths: `rodtrent.substack.com` — 7 posts under two feed identities.

No reader wants the same blog post twice, and this signal cannot misfire: the canonical locator (not
the title, not the language, not keywords) is the identity. This is the mechanism I recommend for
DUP-3.

## Class 2 — must NOT be merged: identical titles over different content

The cheap signal is a trap. Grouping the supply by **identical normalized title** yields 142 groups
across disjoint sources, and the biggest are unrelated content:

| group size | title (verbatim) | what it actually is |
|---|---|---|
| 52 | `😱😱🥴` | 52 different YouTube Shorts with an emoji title; two of them share one channel |
| 30 | `FINAL EPICO 😱 🤣` | the same, all from `yt:video:0uFik_v4Q2g` and neighbours |
| 14 | `Hello world!` | unrelated blogs' first post: `paulkrugman.wordpress.com` (2010), `tiktok.wordpress.com` (2006), `columnista.wordpress.com` (es) |
| 4 | `MISTERIOS DOLOROSOS` | the same daily prayer series published independently by **four different Spotify podcasters** |
| 4 | `Misterios Gozosos.` | the same, three different shows |

A title-equality rule would delete 52 unrelated videos and 14 unrelated blogs. Note the languages in
that table as well: three `Hello world!` posts are in different languages and countries.

## Class 3 — must never be merged: one event, many independent reports

The Christa Pike story in the supply, verbatim, seven items, five publishers, two languages:

| language | headline | source |
|---|---|---|
| en-gb | `US murderer Christa Pike discharged from hospital 10 days after…` | BBC News |
| es | `Christa Pike, la mujer que sobrevivió a dos inyecciones letales…` | Clarin.com |
| es | `Christa Pike recibió el alta médica y volvió a la prisión…` | Diario Río Negro |
| es | `Qué se sabe de la salud de Christa Pike tras sobrevivir a la…` | La Gaceta |
| es | `Christa Pike: el caso que reabre el debate por la pena de mu…` | YouTube |
| ro-RO | `Christa Pike a supraviețuit execuției. Consider că trebuie i…` | a WordPress blog |

**Token overlap between the BBC and the Spanish headlines is 0.00** — the two share no four-character
token. Nothing based on title or text similarity can even see that these are the same event; only an
event-entity signal could, and `content_entity_id` / `content_cluster_id` are `nil` for every published
card today (`AppComposition.swift:1144`). Building that signal to *merge* these items is exactly the
mechanism the architect warned against; the correct treatment of class 3 is to preserve all of them.

## Consequence

| class | measured size | recommendation |
|---|---|---|
| 1 — same canonical locator | 45 locators / 90 candidates | consolidate (catalog/locator identity, mechanical) |
| 2 — same title, different content | 142 title groups, dominated by Shorts and first posts | never use title equality; needs body text, same language, high overlap before it is even a candidate |
| 3 — one event, independent reports | the Christa Pike cluster and similar | preserve; no mechanism may merge them |

The cheap win is therefore **not** semantic clustering: it is recognising that two SourceIDs carry one
publication or one canonical locator. That also covers the 12 catalog rows titled `BBC News` — the same
problem seen from the reader's side.
