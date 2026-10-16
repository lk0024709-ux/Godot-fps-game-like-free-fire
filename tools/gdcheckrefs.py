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


def entry(argv):
    rc = main(argv)
    if "--params" in argv:
        rc = max(rc, unused_params(argv))
    return rc


if __name__ == "__main__":
    sys.exit(entry(sys.argv[1:]))
