#!/usr/bin/env python3
"""Cross-platform packaging validation for agent-memory-engineering.

Checks (standard library only, no build system):
  1. canonical SKILL.md exists and has valid YAML frontmatter (name, description)
  2. referenced files (references/*.md mentioned by SKILL.md) exist
  3. all relative markdown links inside the skill resolve
  4. manifests present and names valid
  5. VERSION / manifest version synchronization
  6. optional: --check-install <dir> verifies an installed copy matches canonical

Usage:
  python scripts/validate.py
  python scripts/validate.py --check-install ~/.claude/skills/agent-memory-engineering
"""

import argparse
import difflib
import filecmp
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SKILL = REPO / "skills" / "agent-memory-engineering"
SKILL_MD = SKILL / "SKILL.md"

MANIFESTS = {
    "portable (Agent Plugins)": REPO / "plugin.json",
    "claude (.claude-plugin)": REPO / ".claude-plugin" / "plugin.json",
}

failures = []


def ok(msg):
    print(f"  OK    {msg}")


def fail(msg):
    failures.append(msg)
    print(f"  FAIL  {msg}")


def check_frontmatter():
    print("[1] canonical SKILL.md frontmatter")
    if not SKILL_MD.is_file():
        fail(f"missing {SKILL_MD}")
        return None
    text = SKILL_MD.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        fail("SKILL.md has no YAML frontmatter block")
        return None
    fm = m.group(1)
    for key in ("name", "description"):
        if not re.search(rf"^{key}:", fm, re.M):
            fail(f"frontmatter missing '{key}'")
        else:
            ok(f"frontmatter has '{key}'")
    name = re.search(r"^name:\s*(.+)$", fm, re.M)
    return name.group(1).strip() if name else None


def check_references():
    print("[2] skill-internal references")
    ref_dir = SKILL / "references"
    expected = ["architecture.md", "testing.md"]
    for f in expected:
        if (ref_dir / f).is_file():
            ok(f"references/{f} exists")
        else:
            fail(f"missing references/{f}")


def check_links():
    print("[3] relative links inside the skill")
    for md in SKILL.rglob("*.md"):
        text = md.read_text(encoding="utf-8")
        for target in re.findall(r"\]\(([^)#]+?\.md)\)", text):
            if re.match(r"^[a-z]+://", target) or target.startswith("/"):
                continue
            resolved = (md.parent / target).resolve()
            if resolved.is_file():
                ok(f"{md.relative_to(SKILL)} -> {target}")
            else:
                fail(f"{md.relative_to(SKILL)} links to missing '{target}'")
        # backtick-quoted references like `references/architecture.md`
        for target in re.findall(r"`(references/[\w./-]+\.md)`", text):
            if (SKILL / target).is_file():
                ok(f"{md.relative_to(SKILL)} -> {target}")
            else:
                fail(f"{md.relative_to(SKILL)} references missing '{target}'")


def check_manifests(skill_name):
    print("[4] manifests")
    versions = {}
    version_file = REPO / "VERSION"
    if version_file.is_file():
        versions["VERSION"] = version_file.read_text(encoding="utf-8").strip()
    else:
        fail("missing VERSION file")
    for label, path in MANIFESTS.items():
        if not path.is_file():
            fail(f"missing manifest: {path}")
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            fail(f"{label}: invalid JSON ({e})")
            continue
        if "name" not in data:
            fail(f"{label}: missing 'name'")
        elif skill_name and data["name"] != skill_name:
            fail(f"{label}: name '{data['name']}' != skill name '{skill_name}'")
        else:
            ok(f"{label}: name '{data['name']}'")
        if "version" not in data:
            fail(f"{label}: missing 'version'")
        else:
            versions[label] = data["version"]
    print("[5] version synchronization")
    unique = set(versions.values())
    if len(unique) == 1:
        ok(f"all sources at version {unique.pop()}")
    else:
        fail(f"version drift: {versions}")
    # Agent Plugins schema requires $schema on the portable manifest
    portable = MANIFESTS["portable (Agent Plugins)"]
    if portable.is_file():
        data = json.loads(portable.read_text(encoding="utf-8"))
        if data.get("$schema") == "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json":
            ok("portable manifest targets Agent Plugins 1.0.0 schema")
        else:
            fail("portable manifest missing/incorrect $schema")


def check_install(install_dir):
    print(f"[6] installed copy matches canonical: {install_dir}")
    install_dir = Path(install_dir).expanduser().resolve()
    inst_skill = install_dir / "agent-memory-engineering"
    src_files = sorted(p.relative_to(SKILL) for p in SKILL.rglob("*") if p.is_file())
    if not inst_skill.is_dir():
        fail(f"no installed skill at {inst_skill}")
        return
    inst_files = sorted(p.relative_to(inst_skill) for p in inst_skill.rglob("*") if p.is_file())
    if src_files != inst_files:
        only_src = set(src_files) - set(inst_files)
        only_inst = set(inst_files) - set(src_files)
        fail(f"file set differs; missing={sorted(only_src)} extra={sorted(only_inst)}")
        return
    mismatch = [
        str(rel)
        for rel in src_files
        if not filecmp.cmp(SKILL / rel, inst_skill / rel, shallow=False)
    ]
    if mismatch:
        fail(f"content differs in: {mismatch}")
    else:
        ok(f"{len(src_files)} files identical to canonical source")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check-install", metavar="SKILLS_DIR",
                    help="host skills directory (e.g. ~/.claude/skills) to verify against canonical")
    args = ap.parse_args()

    print(f"Validating agent-memory-engineering packaging at {REPO}\n")
    skill_name = check_frontmatter()
    check_references()
    check_links()
    check_manifests(skill_name)
    if args.check_install:
        check_install(args.check_install)

    print()
    if failures:
        print(f"FAILED: {len(failures)} problem(s)")
        sys.exit(1)
    print("All checks passed.")


if __name__ == "__main__":
    main()
