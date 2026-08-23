#!/usr/bin/env python3
"""Generate the Kiro (JSON) and Goose (YAML) renderings from the Claude canonicals.

Single source of truth:
  claude/agents/*.md, claude/agents/languages/*.md, claude/agents/specialized/*.md
  claude/skills/<name>/SKILL.md          (rendered as "subrecipe" agents — Kiro and
                                          Goose have no skill primitive)

Outputs:
  kiro/agents/**.json   — fully regenerated. Content (name, description, tools,
                          prompt) always comes from canonical; `model` comes from
                          the canonical frontmatter when present (alias → full ID),
                          otherwise it is preserved from the existing file.
  goose/general/**.yaml — content-synced, structure-preserved: `description` and
                          `instructions` are regenerated (a parameter-echo header
                          rebuilt from the file's own `parameters:` + the canonical
                          body); `title`, `parameters`, `prompt`, `activities`,
                          `sub_recipes`, `extensions`, `settings`, `retry` are
                          preserved. Files with no canonical source (goose-only
                          subrecipes, workflows, missions) are never touched.

Usage:
  python3 tools/generate_renderings.py --write   # regenerate in place
  python3 tools/generate_renderings.py --check   # exit 1 if anything would change

Requires PyYAML (`pip install pyyaml`).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent

MODEL_MAP = {
    "haiku": "claude-haiku-4-5",
    "sonnet": "claude-sonnet-5",
    "opus": "claude-opus-5",
}

# Claude tool name → kiro tool bucket
KIRO_TOOL_MAP = {
    "read": "read", "grep": "read", "glob": "read",
    "bash": "shell",
    "write": "write", "edit": "write", "notebookedit": "write",
}

# (canonical glob, kiro subdir, goose subdir)
CATEGORIES = [
    ("claude/agents/*.md", "kiro/agents", "goose/general"),
    ("claude/agents/languages/*.md", "kiro/agents/languages", "goose/general/languages"),
    ("claude/agents/specialized/*.md", "kiro/agents/specialized", "goose/general"),
    ("claude/skills/*/SKILL.md", "kiro/agents/subrecipes", "goose/general/subrecipes"),
]


def parse_canonical(path: Path) -> dict:
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", path.read_text(), re.S)
    if not m:
        sys.exit(f"error: no frontmatter in {path}")
    fm = yaml.safe_load(m.group(1)) or {}
    name = fm.get("name") or (path.parent.name if path.name == "SKILL.md" else path.stem)
    tools = fm.get("tools") or fm.get("allowed-tools") or ""
    if isinstance(tools, str):
        tools = [t.strip() for t in tools.split(",") if t.strip()]
    return {
        "name": name,
        "description": str(fm.get("description", "")).strip(),
        "model": fm.get("model"),
        "tools": tools,
        "body": m.group(2).strip() + "\n",
    }


def render_kiro(agent: dict, existing: dict | None) -> str:
    kiro_tools = sorted({KIRO_TOOL_MAP[t.lower()] for t in agent["tools"]
                         if t.lower() in KIRO_TOOL_MAP},
                        key=["read", "shell", "write"].index)
    model = MODEL_MAP.get(agent["model"])
    if model is None:
        model = (existing or {}).get("model", MODEL_MAP["sonnet"])
    doc = {
        "name": agent["name"],
        "description": agent["description"],
        "model": model,
        "tools": kiro_tools or ["read"],
        "allowedTools": ["read"],
        "prompt": agent["body"],
    }
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"


def _titleize(name: str) -> str:
    return name.replace("-", " ").replace("_", " ").title()


def _param_header(parameters: list) -> str:
    lines = []
    for p in parameters or []:
        key = p.get("key")
        if key:
            lines.append(f"## {_titleize(key)}: {{{{ {key} }}}}")
    return ("\n".join(lines) + "\n\n") if lines else ""


def render_goose(agent: dict, existing: dict | None) -> str:
    body = agent["body"]
    if agent["name"] != "bash-expert":  # bash-expert's body is ABOUT Bash — leave it
        body = re.sub(r"\bBash\b", "Shell", body)
    existing = existing or {}
    doc = {
        "version": existing.get("version", "1.0.0"),
        "title": existing.get("title", _titleize(agent["name"])),
        "description": agent["description"],
    }
    if existing.get("parameters"):
        doc["parameters"] = existing["parameters"]
    doc["instructions"] = _param_header(existing.get("parameters", [])) + body
    for key in ("prompt", "activities", "sub_recipes", "retry"):
        if key in existing:
            doc[key] = existing[key]
    doc["extensions"] = existing.get("extensions") or [{
        "type": "builtin", "name": "developer",
        "description": "File system and shell access", "timeout": 300, "bundled": True,
    }]
    doc["settings"] = existing.get("settings") or {"temperature": 0.1}
    for key, value in existing.items():  # anything else the file had, keep at the end
        if key not in doc:
            doc[key] = value
    return yaml.dump(doc, Dumper=_Dumper, sort_keys=False, allow_unicode=True, width=100)


class _Dumper(yaml.SafeDumper):
    pass


def _str_representer(dumper, data):
    if "\n" in data:
        data = "\n".join(line.rstrip() for line in data.splitlines()) + "\n"
        return dumper.represent_scalar("tag:yaml.org,2002:str", data, style="|")
    return dumper.represent_scalar("tag:yaml.org,2002:str", data)


_Dumper.add_representer(str, _str_representer)


def main() -> int:
    ap = argparse.ArgumentParser()
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = ap.parse_args()

    drift: list[str] = []
    written = 0
    for glob, kiro_dir, goose_dir in CATEGORIES:
        for src in sorted(REPO.glob(glob)):
            agent = parse_canonical(src)
            targets = []

            kiro_path = REPO / kiro_dir / f"{agent['name']}.json"
            kiro_existing = json.loads(kiro_path.read_text()) if kiro_path.exists() else None
            targets.append((kiro_path, render_kiro(agent, kiro_existing)))

            goose_path = REPO / goose_dir / f"{agent['name']}.yaml"
            goose_existing = (yaml.safe_load(goose_path.read_text())
                              if goose_path.exists() else None)
            targets.append((goose_path, render_goose(agent, goose_existing)))

            for path, content in targets:
                current = path.read_text() if path.exists() else None
                if current == content:
                    continue
                if args.check:
                    drift.append(str(path.relative_to(REPO)))
                else:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(content)
                    written += 1

    if args.check:
        if drift:
            print("renderings out of date (run: python3 tools/generate_renderings.py --write):")
            for f in drift:
                print(f"  {f}")
            return 1
        print("renderings in sync")
        return 0
    print(f"wrote {written} rendering(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
