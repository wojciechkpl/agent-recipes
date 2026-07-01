# Kiro Agent Recipes

Kiro-compatible agent configurations converted from the Claude Code agents in this repository. Same domain expertise, adapted to Kiro's JSON format.

## Setup

```bash
# Install all agents globally
./setup-kiro.sh

# Or copy specific agents
cp kiro/agents/code-reviewer.json ~/.kiro/agents/
cp kiro/agents/languages/python-expert.json ~/.kiro/agents/
```

## Agent Model Tiers

| Tier | Model | Agents | Use Case |
|------|-------|--------|----------|
| **opus** | `claude-opus-4-8` | ai-researcher | Deep research, architecture |
| **sonnet** | `claude-sonnet-5` | code-reviewer, debugger, python-expert, etc. | Code writing, reviews, implementation |
| **haiku** | `claude-haiku-4-5` | documentation-agent, bash-expert, dependency-auditor | Docs, scripts, simple tasks |

## Directory Structure

```
kiro/
├── agents/
│   ├── *.json                # 8 core agents
│   ├── languages/*.json      # 5 language experts
│   ├── specialized/*.json    # 2 specialized agents
│   └── subrecipes/*.json     # 6 shared subrecipes
├── skills/                   # Kiro skills (SKILL.md format)
├── setup-kiro.sh             # Installation script
└── README.md
```

## Key Differences from Claude Code Format

| Feature | Claude Code | Kiro |
|---------|------------|------|
| Format | Markdown with YAML frontmatter | JSON |
| Tools | `Read, Write, Edit, Bash, Grep, Glob` | `read, write, shell` |
| Models | `opus, sonnet, haiku` | `claude-opus-4-8, claude-sonnet-5, claude-haiku-4-5` |
| Location | `~/.claude/agents/` | `~/.kiro/agents/` |
| Skills | `.claude/skills/SKILL.md` | `.kiro/skills/SKILL.md` (same format) |

## Usage

```bash
# Start Kiro with a specific agent
kiro-cli --agent code-reviewer

# Swap agents mid-session
> /agent swap python-expert

# List available agents
> /agent list
```
