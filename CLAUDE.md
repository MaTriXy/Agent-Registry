# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Agent Registry is a **lazy-loading system for Claude Code agents** that reduces context window token usage by 70-90%. Instead of loading all agents upfront (~117 tokens/agent), it maintains a lightweight JSON index (~20-25 tokens/agent) and loads agents on-demand via search.

The project ships as a **Claude Code Skill** (defined in `SKILL.md`) and is installed to `~/.claude/skills/agent-registry/`.

## Architecture

### Core Data Flow

```
registry.json (index) → search_agents.py (BM25 ranking) → get_agent.py (lazy load) → agent .md file
```

### Key Components

- **`references/registry.json`** — Lightweight index storing agent metadata (name, summary, keywords, token_estimate, content_hash). This is the only file loaded into context at conversation start.
- **`agents/`** — Migrated agent markdown files, organized by subdirectory categories. Entirely git-ignored (user-specific data).
- **`scripts/`** — Python CLI tools that operate on the registry:
  - `init_registry.py` — Interactive migration wizard with questionary checkbox UI (paginated, category-grouped). Scans `~/.claude/agents/` and `.claude/agents/`, builds the index.
  - `search_agents.py` — BM25 + keyword matching search. Custom BM25 implementation (no external dependencies beyond stdlib).
  - `search_agents_paged.py` — Paginated variant for large registries (300+ agents).
  - `get_agent.py` — Loads full agent content by name (exact match, then partial match).
  - `list_agents.py` — Lists all indexed agents with metadata table.
  - `rebuild_registry.py` — Rebuilds `registry.json` from agents in the `agents/` directory.
  - `telemetry.py` — Fire-and-forget anonymous telemetry (imported by all scripts). Opt-out via `AGENT_REGISTRY_NO_TELEMETRY=1` or `DO_NOT_TRACK=1`.
- **`SKILL.md`** — Skill definition with YAML frontmatter consumed by Claude Code's skill system.
- **`install.sh`** — Bash installer that copies files to `~/.claude/skills/agent-registry/`, creates directory structure, and installs the `questionary` Python dependency.

### Search Algorithm

`search_agents.py` implements BM25 (Best Matching 25) from scratch using only Python stdlib (`math`, `re`, `collections.Counter`). No external search libraries are required. Keywords from the registry index are matched against query terms with relevance scoring (0.0-1.0).

### Telemetry

All scripts import `telemetry.track()` which sends anonymous metrics (event type, result count, timing, OS, Python version) to a remote endpoint via background daemon threads. Never sends search queries, agent names, or file paths.

## Commands

### Run scripts (from repo root)

```bash
python3 scripts/search_agents.py "query terms"
python3 scripts/get_agent.py <agent-name>
python3 scripts/list_agents.py
python3 scripts/rebuild_registry.py
python3 scripts/init_registry.py           # Interactive migration
```

### Run tests

```bash
cd scripts && python3 test_questionary.py   # Tests questionary UI integration
cd scripts && python3 test_selection.py      # Tests agent scan and category detection
```

### Install

```bash
./install.sh              # User-level install to ~/.claude/skills/agent-registry/
./install.sh --project    # Project-level install to .claude/skills/agent-registry/
```

### Disable telemetry during development

```bash
AGENT_REGISTRY_NO_TELEMETRY=1 python3 scripts/search_agents.py "query"
```

## Development Notes

- **Python 3.7+ required.** No Node.js runtime needed for the core scripts (package.json is for NPX-based skill installation only).
- **Only external dependency:** `questionary` (for interactive checkbox UI). All search/indexing uses stdlib only. Migration falls back to text input if questionary is missing.
- Scripts use relative imports from `telemetry.py`, so they must be run from `scripts/` or with `scripts/` in the Python path.
- `registry.json` and `agents/*` are git-ignored (user-specific data populated during migration).
- The `remotion-video/` directory is git-ignored and unrelated to the core skill (used for promotional video).
