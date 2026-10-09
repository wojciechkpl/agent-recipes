#!/usr/bin/env python3
"""Manifest drift check (stdlib only).

Fails when something that states a fact about the tree no longer matches it:

  * README.md and claude/README.md state the agent / skill / workflow counts in
    ANCHORED sentences that must match exactly (a reworded sentence fails instead
    of escaping the check); other numbers in those files are left alone
  * the plugin descriptions in .claude-plugin/marketplace.json and
    claude/.claude-plugin/plugin.json carry no counts at all
  * marketplace.json has a non-empty metadata.description
  * every ${CLAUDE_PLUGIN_ROOT}/<path> in claude/commands/*.md and
    claude/hooks/hooks.json names an existing file under claude/
  * every claude/skills/*/SKILL.md has `name` equal to its directory and a
    non-empty `description`
  * with --base <ref>: when anything under claude/ changed since <ref>, `version`
    in plugin.json is greater than it was at <ref> (Claude Code pins installs to
    that version, so an unbumped change reaches nobody)

Usage: python3 tools/check_manifests.py [--root <dir>] [--base <git-ref>]
  exit 0 and silent when everything matches; exit 1 with one line per problem.
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys

# Anchored sentences. Each must match exactly once; the groups are the counts.
README_HEADLINE = re.compile(r"(\d+) specialist agents \+ (\d+) skills \+ (\d+) evidence-gated")
README_WORKFLOWS = re.compile(r"^### The (\d+) workflows$", re.M)
PLUGIN_README_ROSTER = re.compile(
    r"\*\*(\d+) agents\*\*, \*\*(\d+) skills\*\*, \*\*(\d+) workflow commands\*\*")
PLUGIN_ROOT_REF = re.compile(r"\$\{CLAUDE_PLUGIN_ROOT\}/([^\s\"'`)]+)")
COUNT = re.compile(r"\b\d+\b")


def read(root, rel):
    with open(os.path.join(root, rel), encoding="utf-8") as handle:
        return handle.read()


def load_json(root, rel):
    return json.loads(read(root, rel))


def tree_counts(root):
    agents = glob.glob(os.path.join(root, "claude", "agents", "**", "*.md"), recursive=True)
    skills = glob.glob(os.path.join(root, "claude", "skills", "*", "SKILL.md"))
    workflows = glob.glob(os.path.join(root, "claude", "commands", "wf-*.md"))
    return len(agents), len(skills), len(workflows)


def check_anchor(problems, rel, text, pattern, expected, what):
    """One problem per anchored sentence: missing, or any of its counts wrong."""
    found = pattern.findall(text)
    if len(found) != 1:
        problems.append("%s: expected exactly one '%s' sentence, found %d" % (rel, what, len(found)))
        return
    got = found[0] if isinstance(found[0], tuple) else (found[0],)
    got = tuple(int(n) for n in got)
    if got != expected:
        problems.append("%s: '%s' says %s, tree has %s" % (rel, what, got, expected))


def check_readmes(root, problems):
    agents, skills, workflows = tree_counts(root)
    readme = read(root, "README.md")
    check_anchor(problems, "README.md", readme, README_HEADLINE,
                 (agents, skills, workflows), "N specialist agents + N skills + N evidence-gated")
    check_anchor(problems, "README.md", readme, README_WORKFLOWS,
                 (workflows,), "### The N workflows")
    roster = read(root, os.path.join("claude", "README.md"))
    check_anchor(problems, "claude/README.md", roster, PLUGIN_README_ROSTER,
                 (agents, skills, workflows), "**N agents**, **N skills**, **N workflow commands**")


def check_descriptions(root, problems):
    marketplace = load_json(root, os.path.join(".claude-plugin", "marketplace.json"))
    for i, plugin in enumerate(marketplace.get("plugins", [])):
        if COUNT.search(plugin.get("description", "")):
            problems.append(".claude-plugin/marketplace.json: plugins[%d].description contains a count" % i)
    if not (marketplace.get("metadata") or {}).get("description", "").strip():
        problems.append(".claude-plugin/marketplace.json: metadata.description is missing or empty")
    plugin = load_json(root, os.path.join("claude", ".claude-plugin", "plugin.json"))
    if COUNT.search(plugin.get("description", "")):
        problems.append("claude/.claude-plugin/plugin.json: description contains a count")


def check_plugin_root_refs(root, problems):
    files = sorted(glob.glob(os.path.join(root, "claude", "commands", "*.md")))
    hooks = os.path.join(root, "claude", "hooks", "hooks.json")
    if os.path.isfile(hooks):
        files.append(hooks)
    for path in files:
        rel = os.path.relpath(path, root)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        for target in sorted(set(PLUGIN_ROOT_REF.findall(text))):
            if not os.path.isfile(os.path.join(root, "claude", target)):
                problems.append("%s: ${CLAUDE_PLUGIN_ROOT}/%s does not exist under claude/" % (rel, target))


def frontmatter(text):
    """The YAML frontmatter as a flat dict of top-level scalar keys (no YAML lib)."""
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 4)
    if end < 0:
        return None
    fields = {}
    for line in text[4:end].splitlines():
        match = re.match(r"^([A-Za-z][\w-]*):\s*(.*)$", line)
        if match:
            fields[match.group(1)] = match.group(2).strip().strip("\"'").strip()
    return fields


def check_skills(root, problems):
    for path in sorted(glob.glob(os.path.join(root, "claude", "skills", "*", "SKILL.md"))):
        name = os.path.basename(os.path.dirname(path))
        rel = "claude/skills/%s/SKILL.md" % name
        with open(path, encoding="utf-8") as handle:
            fields = frontmatter(handle.read())
        if fields is None:
            problems.append("%s: no YAML frontmatter" % rel)
            continue
        if fields.get("name") != name:
            problems.append("%s: frontmatter name %r must equal the directory name %r"
                            % (rel, fields.get("name"), name))
        if not fields.get("description"):
            problems.append("%s: frontmatter description is missing or empty" % rel)


def git(root, *args):
    return subprocess.run(["git", "-C", root] + list(args), capture_output=True,
                          text=True, check=True).stdout


VERSION = re.compile(r"^\s*(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?\s*$")


def version_tuple(text):
    """Comparable form of a semver string; a pre-release sorts below its release
    (0.5.0-rc1 < 0.5.0) and above the previous one (0.5.0-rc1 > 0.4.0)."""
    match = VERSION.match(text)
    if not match:
        raise ValueError("not a semver version: %r" % text)
    major, minor, patch, pre = match.groups()
    return (int(major), int(minor), int(patch), pre is None, pre or "")


def check_version_bump(root, base, problems):
    changed = git(root, "diff", "--name-only", base + "...HEAD", "--", "claude/").strip()
    if not changed:
        return
    current = version_tuple(load_json(root, os.path.join("claude", ".claude-plugin", "plugin.json"))["version"])
    previous = version_tuple(json.loads(git(root, "show", base + ":claude/.claude-plugin/plugin.json"))["version"])
    if current <= previous:
        problems.append("claude/.claude-plugin/plugin.json: claude/ changed since %s but version %s is not greater than %s"
                        % (base, ".".join(map(str, current)), ".".join(map(str, previous))))


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        help="repo root to check (default: the repo this script lives in)")
    parser.add_argument("--base", help="git ref; a change under claude/ since it requires a version bump")
    args = parser.parse_args(argv)
    root = os.path.abspath(args.root)
    problems = []
    check_readmes(root, problems)
    check_descriptions(root, problems)
    check_plugin_root_refs(root, problems)
    check_skills(root, problems)
    if args.base:
        check_version_bump(root, args.base, problems)
    for line in problems:
        print(line)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
