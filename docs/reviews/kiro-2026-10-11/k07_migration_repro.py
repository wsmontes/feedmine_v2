"""K-07 reproduction: run FeedMine V2's real migration SQL on a NON-EMPTY SQLite database.

Extracts every SQL statement of RuntimeMigrations.swift in order and applies it the way GRDB 7
`registerMigration(_:foreignKeyChecks: .deferred)` (the default) does:
  PRAGMA foreign_keys = OFF; BEGIN; <migration>; PRAGMA foreign_key_check must be empty; COMMIT.
Optionally the stricter `.immediate` mode (foreign_keys = ON during the migration) to test A03's claim.

Data is seeded right before the two table rebuilds (reader-context-identity-v1 rebuilds context_checkpoints,
media-playback-candidate-v1 rebuilds media_candidates). Asserts: every pre-existing row survives with exact
values, foreign_key_check and integrity_check are clean, and the rebuilt tables keep their indexes.

Swift-only steps are emulated: backfillEditionContextIdentities (identity text stand-in, non-empty),
backfillCheckpointContextIdentities (its SQL is extracted verbatim), and reader-library-v1 arguments.
Usage: python k07_migration_repro.py <path/to/RuntimeMigrations.swift> [immediate]
"""
import re
import sqlite3
import sys
import uuid

SWIFT = open(sys.argv[1], encoding="utf-8").read()
MODE = sys.argv[2] if len(sys.argv) > 2 else "deferred"

# --- extract migrations -------------------------------------------------------------------------------
body = SWIFT[SWIFT.index("static var current: DatabaseMigrator"):SWIFT.index("return migrator")]
blocks = re.split(r'migrator\.registerMigration\("([^"]+)"\)', body)[1:]
migrations = []  # (id, [steps]); step = ("sql", text) | ("sql_args", text, argnames) | ("backfill_edition",) | ("backfill_checkpoint",)
for i in range(0, len(blocks), 2):
    mid, text = blocks[i], blocks[i + 1]
    steps = []
    pattern = re.compile(r'db\.execute\(sql:\s*"""(.*?)"""(\s*,\s*arguments:\s*\[[^\]]*\])?|db\.execute\(sql:\s*"((?:[^"\\]|\\.)*)"(\s*,\s*arguments:\s*\[[^\]]*\])?\)|Self\.(backfillEditionContextIdentities|backfillCheckpointContextIdentities)', re.S)
    for m in pattern.finditer(text):
        if m.group(5):
            steps.append(("backfill_edition",) if m.group(5) == "backfillEditionContextIdentities" else ("backfill_checkpoint",))
        else:
            sql = m.group(1) if m.group(1) is not None else m.group(3)
            args = m.group(2) or m.group(4)
            steps.append(("sql_args", sql) if args else ("sql", sql))
    migrations.append((mid, steps))

checkpoint_backfill_sql = re.search(r'func backfillCheckpointContextIdentities.*?db\.execute\(sql:\s*"""(.*?)"""', SWIFT, re.S).group(1)

DEFAULT_LIST_ID = "default-box"  # stand-in for ReaderBookmarkList.defaultID


def run_step(db, step):
    kind = step[0]
    if kind == "sql":
        db.executescript_in_txn(step[1])
    elif kind == "sql_args":
        sql = step[1]
        args = [DEFAULT_LIST_ID, "Salvos"][: sql.count("?")]
        db.execute(sql, args)
    elif kind == "backfill_edition":
        # Swift derives the identity from ContextKey; any non-empty identity per surface is equivalent here.
        db.execute("""UPDATE feed_editions SET
                context_identity = CASE context_kind WHEN 'main' THEN 'identity:main'
                    WHEN 'source' THEN 'identity:source:' || context_source_id
                    ELSE 'identity:search:' || context_search_query END,
                context_key_json = '{"kind":"' || context_kind || '"}'
            WHERE context_identity = '' OR context_key_json = ''""")
    elif kind == "backfill_checkpoint":
        db.execute(checkpoint_backfill_sql)


class Conn:
    def __init__(self):
        self.c = sqlite3.connect(":memory:", isolation_level=None)

    def execute(self, sql, args=()):
        return self.c.execute(sql, args)

    def executescript_in_txn(self, script):
        # executescript would COMMIT implicitly; split statements and run inside the open transaction instead.
        for stmt in split_sql(script):
            self.c.execute(stmt)


def split_sql(script):
    out, buf = [], ""
    for line in script.splitlines(keepends=True):
        buf += line
        if sqlite3.complete_statement(buf):
            if buf.strip():
                out.append(buf)
            buf = ""
    if buf.strip():
        out.append(buf)
    return out


def migrate(db, upto=None, start=0):
    done = start
    for idx in range(start, len(migrations)):
        mid, steps = migrations[idx]
        db.execute("PRAGMA foreign_keys = " + ("ON" if MODE == "immediate" else "OFF"))
        db.execute("BEGIN")
        try:
            for step in steps:
                run_step(db, step)
            violations = db.execute("PRAGMA foreign_key_check").fetchall()
            if violations:
                raise RuntimeError(f"{mid}: foreign_key_check violations {violations[:5]}")
            db.execute("COMMIT")
        except Exception:
            db.execute("ROLLBACK")
            raise
        finally:
            db.execute("PRAGMA foreign_keys = ON")
        done = idx + 1
        if mid == upto:
            break
    return done


def u():
    return str(uuid.uuid4())


def dump(db, table, exclude=()):
    cols = [r[1] for r in db.execute(f"PRAGMA table_info({table})") if r[1] not in exclude]
    return sorted(db.execute(f"SELECT {', '.join(cols)} FROM {table}").fetchall(), key=repr)


db = Conn()
ids = [m[0] for m in migrations]
print(f"mode={MODE} migrations={len(ids)}")
stop = migrate(db, upto="publication-media-use-v1")
print("migrated up to", ids[stop - 1])

# --- seed realistic rows (FKs satisfied) ----------------------------------------------------------------
o1, o2, r1, r2 = u(), u(), u(), u()
src = u()
for o, r in ((o1, r1), (o2, r2)):
    db.execute("INSERT INTO origin_records (id, object_connector_kind, object_namespace, object_value, object_role, availability, first_observed_at, last_observed_at) VALUES (?, 'syndication', 'ns', ?, 'object', 'available', 1, 2)", (o, o))
    db.execute("INSERT INTO origin_revisions (id, origin_record_id, headline, observed_at) VALUES (?, ?, 'h', 1)", (r, o))
    db.execute("UPDATE origin_records SET current_revision_id = ? WHERE id = ?", (r, o))
    db.execute("INSERT INTO source_memberships VALUES (?, ?, 'direct', 1, 1)", (o, src))
    db.execute("INSERT INTO selection_supply VALUES (?, ?, 1, 'observedFallback')", (o, r))
media = [(u(), r1, 0, 'cardVisual', 'image', 'https://img.example/a.jpg', 'image/jpeg', 1200, 800),
         (u(), r1, 1, 'cardVisual', 'image', 'https://img.example/b.jpg', None, None, None),
         (u(), r2, 0, 'cardVisual', 'image', 'https://img.example/c.png', 'image/png', 640, 640)]
db.c.executemany("INSERT INTO media_candidates VALUES (?,?,?,?,?,?,?,?,?)", media)
ed_main, ed_src = u(), u()
for ed, kind, s in ((ed_main, 'main', None), (ed_src, 'source', src)):
    db.execute("INSERT INTO feed_editions (id, editorial_revision_id, context_kind, context_source_id, catalog_generation, user_selection_version, eligibility_policy_version, scoring_policy_version, sequencing_policy_version, exposure_policy_version, selection_schema_version, publication_schema_version, selection_seed, created_at) VALUES (?, ?, ?, ?, 1,1,1,1,1,1,1,1,1,1)", (ed, u(), kind, s))
cards = {}
for ed in (ed_main, ed_src):
    seg = u()
    db.execute("INSERT INTO feed_segments VALUES (?, ?, 0, 1, 1, 1)", (seg, ed))
    for ordinal, (o, r) in enumerate(((o1, r1), (o2, r2))):
        cid = u()
        cards.setdefault(ed, []).append(cid)
        db.execute("INSERT INTO published_cards (id, segment_id, ordinal, origin_record_id, origin_revision_id, title, media_key, media_pixel_width, media_pixel_height, render_layout, render_media_aspect_ratio) VALUES (?, ?, ?, ?, ?, 't', 'k', 1200, 800, 'hero', 1.5)", (cid, seg, ordinal, o, r))
db.execute("INSERT INTO context_checkpoints VALUES ('main', ?, ?, 'top', 10)", (ed_main, cards[ed_main][1]))
db.execute("INSERT INTO context_checkpoints VALUES (?, ?, ?, 'center', 11)", ("source:" + src, ed_src, cards[ed_src][0]))
db.execute("INSERT INTO edition_reading_state VALUES (?, ?, 1, 1)", (ed_main, cards[ed_main][1]))
db.execute("INSERT INTO publication_card_usage VALUES (?, 10)", (cards[ed_main][1],))
db.execute("INSERT INTO publication_bookmarks VALUES (?, 12)", (cards[ed_main][0],))
db.execute("INSERT INTO reader_preferences (singleton_id, source_keys, selection_version, active_context) VALUES (1, x'00', 2, x'00')")

before_media = dump(db, "media_candidates")
before_ckpt = dump(db, "context_checkpoints")
before_cards = dump(db, "published_cards")
before_bookmark = db.execute("SELECT card_id, bookmarked_at FROM publication_bookmarks").fetchall()

# --- run the remaining migrations, including both rebuilds -----------------------------------------------
migrate(db, start=stop)
print("migrated to", ids[-1])

fails = []
def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (f"  {detail}" if detail else ""))
    if not ok:
        fails.append(name)

check("media_candidates rows identical after rebuild", dump(db, "media_candidates") == before_media)
after_ckpt = db.execute("SELECT context_key, edition_id, card_id, anchor_placement, updated_at, context_identity, context_key_json FROM context_checkpoints ORDER BY context_key").fetchall()
check("context_checkpoints keep every row (edition, card, anchor, time)",
      sorted(r[:5] for r in after_ckpt) == sorted(before_ckpt), f"after={len(after_ckpt)} before={len(before_ckpt)}")
check("context_checkpoints carry a non-empty identity", all(r[5] and r[6] for r in after_ckpt))
check("published_cards untouched", dump(db, "published_cards") == before_cards)
moved = db.execute("SELECT card_id, added_at FROM reader_bookmark_memberships WHERE list_id = ?", (DEFAULT_LIST_ID,)).fetchall()
check("bookmark folded into default box", moved == before_bookmark, f"{moved}")
check("foreign_key_check clean", db.execute("PRAGMA foreign_key_check").fetchall() == [])
check("integrity_check ok", db.execute("PRAGMA integrity_check").fetchone()[0] == "ok")
idx = {r[0] for r in db.execute("SELECT name FROM sqlite_schema WHERE type='index' AND tbl_name='media_candidates'")}
check("media_candidates indexes present", {"media_candidates_one_playback"}.issubset(idx) and any(i.startswith("sqlite_autoindex") for i in idx), f"{sorted(idx)}")
fk = db.execute("PRAGMA foreign_key_list(media_candidates)").fetchall()
check("media_candidates FK still targets origin_revisions", any(r[2] == "origin_revisions" for r in fk))
fk = {r[2] for r in db.execute("PRAGMA foreign_key_list(context_checkpoints)")}
check("context_checkpoints FKs target feed_editions and published_cards", fk == {"feed_editions", "published_cards"}, f"{fk}")
# A playback row is now admissible, and a second playback for the same revision is refused by the new index.
db.execute("INSERT INTO media_candidates VALUES (?, ?, 5, 'playback', 'audio', 'https://a.example/ep.mp3', 'audio/mpeg', NULL, NULL)", (u(), r2))
try:
    db.execute("INSERT INTO media_candidates VALUES (?, ?, 6, 'playback', 'video', 'https://a.example/ep.mp4', NULL, NULL, NULL)", (u(), r2))
    check("second playback per revision refused", False)
except sqlite3.IntegrityError:
    check("second playback per revision refused", True)
print(f"sqlite {sqlite3.sqlite_version}; SUMMARY failed={len(fails)}")
sys.exit(1 if fails else 0)
