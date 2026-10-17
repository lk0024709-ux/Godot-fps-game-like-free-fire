#!/usr/bin/env python3
"""Cross-reference check: har `SomeHelper.func_name(` call ka match dhundho.

gdlint/gdparse sirf syntax batate hain — identifiers nahi. Isliye galti se rename
kiya gaya function call (jo bahut aam bug hai: "Identifier X not declared in the
current scope") sirf real Godot pakadta hai. Ye script wahi kaam pehle hi kar deti
hai: scripts/*.gd me jo bhi <Helper>.<func> call hai, usko helper file me dhundhti hai.

Chalao: python3 tools/gdcheckrefs.py
"""
import os
import re
import sys

# helper script ka naam (constant) -> uski file
HELPERS = {
    "Loader": "scripts/asset_loader.gd",
    "ASSETS": "scripts/assets.gd",
    "Assets": "scripts/assets.gd",
    "CHARACTERS": "scripts/character_data.gd",
    "DATA": "scripts/weapon_data.gd",
    "WeaponData": "scripts/weapon_data.gd",
    "CharacterData": "scripts/character_data.gd",
}

CALL = re.compile(r"\b(%s)\.([a-z_][a-z0-9_]*)\b" % "|".join(HELPERS))
DEF = re.compile(r"^\s*(?:static\s+)?(?:func|var|const)\s+([a-zA-Z_][a-zA-Z0-9_]*)",
                 re.M)


def declared(path):
    return set(DEF.findall(open(path).read()))


def main(argv):
    scripts = sorted(
        os.path.join("scripts", f) for f in os.listdir("scripts") if f.endswith(".gd")
    )
    known = {}
    missing_files = []
    for helper, path in HELPERS.items():
        if os.path.exists(path):
            known[helper] = declared(path)
        else:
            missing_files.append(path)

    problems = []
    checked = 0
    for script in scripts:
        src = open(script).read()
        lines = src.split("\n")
        # is script me jo khud define hui cheezein (local vars) unko chhod do
        local = declared(script)
        for match in CALL.finditer(src):
            helper, name = match.group(1), match.group(2)
            if helper == "Loader" and name in ("new",):
                continue
            if name in local and helper != "Loader":
                pass
            checked += 1
            if helper not in known:
                continue
            if name not in known[helper]:
                line_no = src[:match.start()].count("\n") + 1
                problems.append("%s:%d -> %s.%s() nahi mila (%s me nahi hai)"
                                % (script, line_no, helper, name, HELPERS[helper]))

    for f in missing_files:
        problems.append("helper file missing: " + f)

    if problems:
        print("REFERENCE PROBLEMS (%d):" % len(problems))
        for p in problems:
            print("  " + p)
        return 1
    print("Refs OK: %d call(s) check hue, sab helper functions mil gaye" % checked)
    return 0




# --------------------------------------------------------------- unused params --
# Heuristic: agar kisi function ka parameter body me ek baar bhi use nahi hua, to
# aksar wo rename ka adhoora kaam hota hai (jaise `collision_layer_bits` bug).
FUNC = re.compile(r"^\s*(?:static\s+)?func\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(([^)]*)\)", re.M)


def unused_params(argv):
    problems = []
    for script in sorted(os.path.join("scripts", f) for f in os.listdir("scripts")
                         if f.endswith(".gd")):
        src = open(script).read()
        for match in FUNC.finditer(src):
            name, params = match.group(1), match.group(2)
            # function ka body: agle func/end of file tak
            rest = src[match.end():]
            nxt = re.search(r"^\s*(?:static\s+)?func\s", rest, re.M)
            body = rest[:nxt.start()] if nxt else rest
            for raw in params.split(","):
                raw = raw.strip()
                if not raw or raw.startswith("_"):
                    continue
                pname = raw.split(":")[0].strip()
                if not re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]*", pname):
                    continue
                if not re.search(r"\b%s\b" % re.escape(pname), body):
                    line = src[:match.start()].count("\n") + 1
                    problems.append("%s:%d %s() ka param '%s' body me kahin use nahi hua"
                                    % (script, line, name, pname))
    if problems:
        print("UNUSED PARAMS (%d) — rename ka adhoora kaam ho sakta hai:" % len(problems))
        for p in problems:
            print("  " + p)
        return 1
    print("Params OK: koi unused parameter nahi mila")
    return 0


# --------------------------------------------------------------- call arity ----
# Godot galat argument count wale call ko kai baar runtime pe hi pakadta hai
# ("Invalid call. Nonexistent function ... with N arguments"), aur headless CI
# me wo galti sirf tab dikhti hai jab wo line chale. Ye checker wahi pehle hi
# pakad leta hai: <Helper>.<func>(...) ke arguments gine jate hain aur helper
# file me uski definition ke required/total param se milaye jate hain.

FUNC_SIG = re.compile(
    r"^[ \t]*(?:static[ \t]+)?func[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*\(", re.M)


def _split_args(src, open_idx):
    """'(' index se matching ')' tak ke arguments ko top-level pe todo."""
    args = []
    cur = []
    depth = 0
    i = open_idx + 1
    quote = ""
    while i < len(src):
        ch = src[i]
        if quote:
            cur.append(ch)
            if ch == "\\":
                if i + 1 < len(src):
                    cur.append(src[i + 1])
                    i += 1
            elif ch == quote:
                quote = ""
        elif ch in "\"'":
            quote = ch
            cur.append(ch)
        elif ch in "([{":
            depth += 1
            cur.append(ch)
        elif ch in ")]}":
            if depth == 0 and ch == ")":
                args.append("".join(cur))
                return args, i
            depth -= 1
            cur.append(ch)
        elif ch == "," and depth == 0:
            args.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
        i += 1
    return args, -1


def _signatures(path):
    src = open(path).read()
    out = {}
    for match in FUNC_SIG.finditer(src):
        args, _end = _split_args(src, match.end() - 1)
        params = [a for a in args if a.strip()]
        required = sum(1 for a in params if "=" not in a)
        out[match.group(1)] = (required, len(params))
    return out


def check_arity(argv):
    problems = []
    checked = 0
    sigs = {h: _signatures(p) for h, p in HELPERS.items() if os.path.exists(p)}
    for script in sorted(os.path.join("scripts", f) for f in os.listdir("scripts")
                         if f.endswith(".gd")):
        src = open(script).read()
        for match in CALL.finditer(src):
            helper, name = match.group(1), match.group(2)
            # call hone chahiye: naam ke turant baad '(' (space allowed)
            rest = src[match.end():]
            if not re.match(r"[ \t]*\(", rest):
                continue                      # jaise Loader.CATEGORIES (list)
            open_idx = match.end() + rest.index("(")
            args, end = _split_args(src, open_idx)
            if end < 0:
                continue                      # multi-line ya samajh nahi aaya
            given = len([a for a in args if a.strip()])
            sig = sigs.get(helper, {}).get(name)
            if not sig:
                continue
            required, total = sig
            checked += 1
            if given < required or given > total:
                line = src[:match.start()].count("\n") + 1
                problems.append(
                    "%s:%d -> %s.%s() ko %d argument diye, par definition (%s) me "
                    "%d-%d chahiye" % (script, line, helper, name, given,
                                       HELPERS[helper], required, total))
    if problems:
        print("ARITY PROBLEMS (%d):" % len(problems))
        for p in problems:
            print("  " + p)
        return 1
    print("Arity OK: %d call(s) ke arguments definition se match karte hain" % checked)
    return 0


def entry(argv):
    rc = main(argv)
    rc = max(rc, check_arity(argv))
    if "--params" in argv:
        rc = max(rc, unused_params(argv))
    return rc


if __name__ == "__main__":
    sys.exit(entry(sys.argv[1:]))
