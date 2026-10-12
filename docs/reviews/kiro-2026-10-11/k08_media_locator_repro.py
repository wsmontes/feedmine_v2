"""K-08 evidence: Python port of SyndicationMediaLocator.firstContentImage / preferredSrcsetCandidate / resolve
(main@ccba5e9), used to reproduce E3-07 and to test E3-08 before changing Swift.

The port keeps the same regexes (`<img\\b[^>]*>`, the attribute pattern), the same two passes (raw HTML,
then &lt;/&gt;/&quot;-unescaped), the same lazy-attribute precedence and the srcset rule. resolve() is
reduced to what matters here: &amp; unescape, absolute/relative/protocol-relative URL, data:/javascript:
refusal and the decorative markers used in the cases. Host routability is assumed public for the cases.
`FIXED=1` applies the proposed fix: drop comments and never-rendered elements before matching.
"""
import os
import re
from urllib.parse import urljoin

IMG = re.compile(r"<img\b[^>]*>", re.I)
ATTR = re.compile(r"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:\"([^\"]*)\"|'([^']*)')")
HIDDEN = ("script", "style", "template", "iframe")  # raw text / inert content in HTML parsing; never rendered
COMMENT = re.compile(r"<!--.*?(?:-->|\Z)", re.S)
HIDDEN_BLOCK = re.compile(r"<(%s)(?=[\s/>])[^>]*>.*?(?:</\1\s*>|\Z)" % "|".join(HIDDEN), re.I | re.S)
FIXED = os.environ.get("FIXED") == "1"


def resolve(raw, base):
    if raw is None:
        return None
    text = raw.strip()
    if not text:
        return None
    for e in ("&amp;", "&#038;", "&#38;"):
        text = text.replace(e, "&")
    low = text.lower()
    if low.startswith(("data:", "javascript:")):
        return None
    if low.startswith("//"):
        url = "https:" + text
    elif low.startswith(("http://", "https://")):
        url = text
    elif base:
        url = urljoin(base, text)
    else:
        return None
    if any(m in url.lower() for m in ("gravatar.com/avatar", "pixel.gif", "1x1.gif")):
        return None
    return url


def preferred_srcset(srcset, preferred=960):
    if srcset is None:
        return None
    entries = []
    for entry in srcset.split(","):
        parts = entry.split()
        if len(parts) < 2:
            continue
        d = parts[-1]
        unit = d[-1]
        try:
            n = float(d[:-1])
        except ValueError:
            continue
        if unit in "wx" and n > 0:
            entries.append((parts[0], n, unit))
    widths = sorted([e for e in entries if e[2] == "w"], key=lambda e: e[1])
    for e in widths:
        if e[1] >= preferred:
            return e[0]
    if widths:
        return widths[-1][0]
    dens = sorted([e for e in entries if e[2] == "x"], key=lambda e: e[1])
    for e in dens:
        if e[1] >= 2:
            return e[0]
    return dens[-1][0] if dens else None


def renderable(html):
    return HIDDEN_BLOCK.sub("", COMMENT.sub("", html))


def first_content_image(html, base):
    if html is None or ("<img" not in html.lower() and "&lt;img" not in html.lower()):
        return None
    unescaped = html.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"')
    for candidate in (html, unescaped):
        if FIXED:
            candidate = renderable(candidate)
        for m in IMG.finditer(candidate):
            tag = m.group(0)
            attrs = {}
            for a in ATTR.finditer(tag):
                v = a.group(2) if a.group(2) is not None else a.group(3)
                attrs.setdefault(a.group(1).lower(), v)
            first = lambda names: next((attrs[n] for n in names if n in attrs), None)
            srcset = first(["data-lazy-srcset", "data-srcset", "srcset"])
            source = preferred_srcset(srcset) or first(["data-lazy-src", "data-original", "data-orig-file", "data-src", "src"])
            url = resolve(source, base)
            if url:
                return url
    return None


BASE = "https://news.example/story/1"
CASES = [
    # (name, html, expected)  -- E3-07
    ("comment only", '<p>Text</p><!-- <img src="https://attacker.example/track.png?u=1"> -->', None),
    ("script only", '<script>var t = \'<img src="https://attacker.example/s.png">\';</script><p>t</p>', None),
    ("style only", '<style>/* <img src="https://attacker.example/c.png"> */</style>', None),
    ("template only", '<template><img src="https://attacker.example/t.png"></template>', None),
    ("escaped comment only", '&lt;!-- &lt;img src="https://attacker.example/e.png"&gt; --&gt;&lt;p&gt;x&lt;/p&gt;', None),
    ("hidden first, visible later", '<!-- <img src="https://attacker.example/x.png"> --><img src="https://cdn.example/real.jpg">', "https://cdn.example/real.jpg"),
    ("unterminated comment", '<img src="https://cdn.example/ok.jpg"><!-- <img src="https://attacker.example/u.png">', "https://cdn.example/ok.jpg"),
    ("noscript is rendered without JS", '<img src="data:image/gif;base64,R0"><noscript><img src="https://cdn.example/ns.jpg"></noscript>', "https://cdn.example/ns.jpg"),
    ("visible stays", '<p><img src="/body.jpg"></p>', "https://news.example/body.jpg"),
    ("escaped visible stays", '&lt;img src="https://example.test/body.jpg"&gt;', "https://example.test/body.jpg"),
    ("embed is void: images after it survive", '<embed src="https://cdn.example/x.swf"><img src="https://cdn.example/after.jpg">', "https://cdn.example/after.jpg"),
    ("object fallback is rendered", '<object data="https://cdn.example/x.swf"><img src="https://cdn.example/fallback.jpg"></object>', "https://cdn.example/fallback.jpg"),
    ("iframe inner markup is not rendered", '<iframe src="https://v.example/e"><img src="https://attacker.example/i.png"></iframe><img src="https://cdn.example/v.jpg">', "https://cdn.example/v.jpg"),
    ("uppercase SCRIPT", '<SCRIPT>x="<img src=https://attacker.example/q.png>"</SCRIPT><img src="https://cdn.example/q.jpg">', "https://cdn.example/q.jpg"),
    ("custom element named template-card is rendered", '<template-card><img src="https://cdn.example/tc.jpg"></template-card>', "https://cdn.example/tc.jpg"),
    # E3-08
    ("srcset with &amp;", '<img srcset="https://cdn.example/a.jpg?w=960&amp;s=x 960w, https://cdn.example/b.jpg?w=480&amp;s=y 480w">', "https://cdn.example/a.jpg?w=960&s=x"),
    ("srcset with &#038;", '<img srcset="https://cdn.example/a.jpg?w=1200&#038;q=80 1200w">', "https://cdn.example/a.jpg?w=1200&q=80"),
    ("src with &amp;", '<img src="https://cdn.example/a.jpg?x=1&amp;y=2">', "https://cdn.example/a.jpg?x=1&y=2"),
    ("escaped html, double-escaped &amp;", '&lt;img src="https://cdn.example/a.jpg?x=1&amp;y=2"&gt;', "https://cdn.example/a.jpg?x=1&y=2"),
]
fails = 0
for name, html, want in CASES:
    got = first_content_image(html, BASE)
    ok = got == want
    fails += 0 if ok else 1
    print(("PASS " if ok else "FAIL ") + f"{name}: got={got} want={want}")
print(f"FIXED={FIXED} SUMMARY failed={fails}")
raise SystemExit(1 if fails else 0)
