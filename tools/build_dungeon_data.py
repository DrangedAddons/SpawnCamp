"""Builds DungeonData.lua: what Questie doesn't know about each dungeon and raid.

Questie (Forever's own data) stays SpawnCamp's main source for an instance's mobs.
This fills two gaps from the cMaNGOS classic database (1.12, the data Questie is
itself built from):

  * mobs  - NPCs cMaNGOS spawns in the instance, for the ones Questie has no
            spawn or zone for;
  * summons - what the instance's mobs summon (totems, wards, adds, pets) and who
            summons them. Questie has no record of this at all. Found by following
            each mob's spells (its spell list, AI script casts and summons, death
            scripts) to spell effects that create an NPC, through triggered spells.

Usage:
  python tools/build_dungeon_data.py            # download the dump if not cached, build
  python tools/build_dungeon_data.py --refresh  # download the latest dump first
  python tools/build_dungeon_data.py --dump path/to/ClassicDB.sql.gz

The dump is cached in tools/.cache (git-ignored). The file name of the newest full
dump is read from the repo, so --refresh picks up a new one by itself.
"""
import argparse
import gzip
import json
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "tools", ".cache")
OUT = os.path.join(ROOT, "DungeonData.lua")
REPO = "cmangos/classic-db"
LISTING = "https://api.github.com/repos/%s/contents/Full_DB" % REPO
RAW = "https://raw.githubusercontent.com/%s/master/Full_DB/%%s" % REPO

# Spell effects that create an NPC (EffectMiscValue = its entry), 1.12 numbering.
SUMMON_EFFECTS = {28, 41, 42, 56, 73, 74, 87, 88, 89, 90, 93, 97, 112}
TRIGGER_EFFECTS = {64}            # trigger spell
TRIGGER_AURAS = {23, 42}          # periodic trigger spell, proc trigger spell
AI_CAST, AI_SUMMON, AI_SUMMON_ID = 11, 12, 32
DB_SUMMON = 10                    # dbscripts: temp summon creature

TOTEM_TYPE = 11
UNIT_FLAG_NOT_SELECTABLE = 0x02000000
EXTRA_FLAG_INVISIBLE = 0x80
HELPER_NAME = re.compile(r"trigger|bunny|\[dn[dt]\]|\bstalker$|dummy|invisible", re.I)

TABLES = {
    "instance_template", "creature_template", "creature", "creature_spawn_entry",
    "creature_template_spells", "creature_spell_list", "spell_template",
    "creature_ai_scripts", "dbscripts_on_creature_death",
}


def latest_dump_name():
    with urllib.request.urlopen(LISTING) as r:
        files = json.load(r)
    dumps = sorted(f["name"] for f in files if f["name"].endswith(".sql.gz"))
    if not dumps:
        sys.exit("no .sql.gz in %s" % LISTING)
    return dumps[-1]


def fetch(refresh):
    os.makedirs(CACHE, exist_ok=True)
    cached = sorted(f for f in os.listdir(CACHE) if f.endswith(".sql.gz"))
    if cached and not refresh:
        return os.path.join(CACHE, cached[-1])
    name = latest_dump_name()
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        print("downloading", name)
        urllib.request.urlretrieve(RAW % name, path + ".part")
        os.replace(path + ".part", path)
    for old in cached:
        if old != name:
            os.remove(os.path.join(CACHE, old))
    return path


def tuples(s, i):
    """Yields each (...) tuple of an INSERT's VALUES list as a list of values."""
    n = len(s)
    while i < n:
        while i < n and s[i] != "(":
            if s[i] == ";":
                return
            i += 1
        if i >= n:
            return
        i += 1
        row, cur = [], []
        while True:
            c = s[i]
            if c == "'":
                i += 1
                buf = []
                while True:
                    c = s[i]
                    if c == "\\":
                        buf.append({"n": "\n", "r": "\r", "t": "\t", "0": "\0"}.get(s[i + 1], s[i + 1]))
                        i += 2
                    elif c == "'":
                        if i + 1 < n and s[i + 1] == "'":
                            buf.append("'")
                            i += 2
                        else:
                            i += 1
                            break
                    else:
                        buf.append(c)
                        i += 1
                row.append("".join(buf))
                cur = None
            elif c == "," or c == ")":
                if cur is not None:
                    tok = "".join(cur).strip()
                    if tok == "NULL":
                        row.append(None)
                    else:
                        try:
                            row.append(int(tok))
                        except ValueError:
                            try:
                                row.append(float(tok))
                            except ValueError:
                                row.append(tok)
                cur = []
                i += 1
                if c == ")":
                    yield row
                    break
            else:
                cur.append(c)
                i += 1


def load(path):
    cols, rows = {}, {t: [] for t in TABLES}
    create, table = None, None
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("CREATE TABLE `"):
                table = line.split("`")[1]
                create = [] if table in TABLES else None
            elif create is not None:
                m = re.match(r"\s+`([A-Za-z0-9_]+)`", line)
                if m:
                    create.append(m.group(1))
                elif line.startswith(")"):
                    cols[table] = create
                    create = None
            elif line.startswith("INSERT INTO `"):
                t = line.split("`")[1]
                if t in TABLES:
                    head = line.index("VALUES") + 6
                    names = cols[t]
                    m = re.match(r"INSERT INTO `\w+` \(([^)]*)\)", line)
                    if m:
                        names = [c.strip(" `") for c in m.group(1).split(",")]
                    for r in tuples(line, head):
                        rows[t].append(dict(zip(names, r)))
    return rows


def build(rows):
    npc = {r["Entry"]: r for r in rows["creature_template"]}
    spell = {r["Id"]: r for r in rows["spell_template"]}
    instances = {r["map"] for r in rows["instance_template"]}

    # Who's spawned where.
    multi = {}
    for r in rows["creature_spawn_entry"]:
        multi.setdefault(r["guid"], []).append(r["entry"])
    spawned = {}
    for r in rows["creature"]:
        if r["map"] in instances:
            for e in ([r["id"]] if r["id"] else multi.get(r["guid"], [])):
                spawned.setdefault(r["map"], set()).add(e)

    # Spells each NPC can cast, and NPCs it summons directly.
    casts, direct = {}, {}
    by_list = {}
    for r in rows["creature_spell_list"]:
        by_list.setdefault(r["Id"], []).append(r["SpellId"])
    for e, t in npc.items():
        if t.get("SpellList"):
            casts.setdefault(e, set()).update(by_list.get(t["SpellList"], []))
    for r in rows["creature_template_spells"]:
        casts.setdefault(r["entry"], set()).update(r["spell%d" % i] for i in range(1, 11) if r["spell%d" % i])
    for r in rows["creature_ai_scripts"]:
        for a in (1, 2, 3):
            kind, p1 = r["action%d_type" % a], r["action%d_param1" % a]
            if kind == AI_CAST and p1:
                casts.setdefault(r["creature_id"], set()).add(p1)
            elif kind == AI_SUMMON and p1:
                direct.setdefault(r["creature_id"], set()).add(p1)
    for r in rows["dbscripts_on_creature_death"]:
        if r["command"] == DB_SUMMON and r["datalong"]:
            direct.setdefault(r["id"], set()).add(r["datalong"])

    def spell_summons(sid, depth=0, seen=None):
        seen = seen if seen is not None else set()
        if depth > 4 or sid in seen or sid not in spell:
            return set()
        seen.add(sid)
        s, out = spell[sid], set()
        for k in (1, 2, 3):
            eff = s.get("Effect%d" % k) or 0
            misc = s.get("EffectMiscValue%d" % k) or 0
            trig = s.get("EffectTriggerSpell%d" % k) or 0
            aura = s.get("EffectApplyAuraName%d" % k) or 0
            if eff in SUMMON_EFFECTS and misc > 0:
                out.add(misc)
            if trig and (eff in TRIGGER_EFFECTS or aura in TRIGGER_AURAS):
                out |= spell_summons(trig, depth + 1, seen)
        return out

    def summons_of(e):
        out = set(direct.get(e, ()))
        for sid in casts.get(e, ()):
            out |= spell_summons(sid)
        return out

    def usable(e):
        t = npc.get(e)
        if not t or not t["Name"]:
            return False
        if (t.get("UnitFlags") or 0) & UNIT_FLAG_NOT_SELECTABLE:
            return False
        if (t.get("ExtraFlags") or 0) & EXTRA_FLAG_INVISIBLE:
            return False
        if HELPER_NAME.search(t["Name"]):
            return False
        return True

    def service(e):
        return ((npc[e].get("NpcFlags") or 0) & ~1) != 0

    out = {}
    for m in sorted(spawned):
        mobs = sorted({npc[e]["Name"] for e in spawned[m] if usable(e) and not service(e)})
        # Summons, and what those summon (a ward that raises skeletons), 3 deep.
        summons, frontier, level, visited = {}, list(spawned[m]), 0, set(spawned[m])
        while frontier and level < 3:
            nxt = []
            for caster in frontier:
                if not usable(caster):
                    continue
                for s in summons_of(caster):
                    if not usable(s):
                        continue
                    name = npc[s]["Name"]
                    entry = summons.setdefault(name, {"by": set(), "totem": npc[s].get("CreatureType") == TOTEM_TYPE})
                    if npc[caster]["Name"] != name:
                        entry["by"].add(npc[caster]["Name"])
                    if s not in visited:
                        visited.add(s)
                        nxt.append(s)
            frontier, level = nxt, level + 1
        if mobs or summons:
            out[m] = {"script": next((r["ScriptName"] for r in rows["instance_template"] if r["map"] == m), ""),
                      "mobs": mobs, "summons": summons}
    return out


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write(data, source):
    lines = [
        "-- Generated by tools/build_dungeon_data.py from cMaNGOS classic-db (%s)." % source,
        "-- Do not edit by hand: rerun the script. Questie stays the main source for an",
        "-- instance's mobs; this only fills its gaps (see Dungeon.lua).",
        "--",
        "-- [instance map id] = { mobs = { names cMaNGOS spawns there },",
        "--                       summons = { { name, summoned by, totem (creature type Totem) } } }",
        "",
        "local _, SC = ...",
        "",
        "SC.DUNGEON_DATA = {",
    ]
    for m in sorted(data):
        d = data[m]
        lines.append("    [%d] = { -- %s" % (m, d["script"] or "map %d" % m))
        lines.append("        mobs = { " + ", ".join(lua_str(n) for n in d["mobs"]) + " },")
        lines.append("        summons = {")
        for name in sorted(d["summons"]):
            s = d["summons"][name]
            lines.append("            { %s, %s, %s }," % (lua_str(name), lua_str(", ".join(sorted(s["by"]))),
                                                        "true" if s["totem"] else "false"))
        lines.append("        },")
        lines.append("    },")
    lines.append("}")
    lines.append("")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--refresh", action="store_true", help="download the newest dump first")
    ap.add_argument("--dump", help="use this .sql or .sql.gz instead of downloading")
    a = ap.parse_args()
    path = a.dump or fetch(a.refresh)
    print("reading", os.path.basename(path))
    data = build(load(path))
    write(data, os.path.basename(path))
    n_s = sum(len(d["summons"]) for d in data.values())
    print("wrote %s: %d instances, %d summons" % (os.path.relpath(OUT, ROOT), len(data), n_s))


if __name__ == "__main__":
    main()
