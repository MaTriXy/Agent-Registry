# Plan: ctx-Inspired Improvements for Agent Registry

**Status:** Proposed
**Date:** 2026-06-07
**Inspiration:** [stevesolun/ctx](https://github.com/stevesolun/ctx) (MIT) — a graph-backed skill/agent recommendation engine for Claude Code. This plan ports its *feedback-loop principles* (not its Python code or graph artifacts) while keeping Agent Registry's zero-dependency Bun character.

## Motivation

Agent Registry's README lists known limitations that ctx has working solutions for:

| Current limitation | ctx mechanism to adapt |
|---|---|
| No relevance feedback — scoring fixed, doesn't learn from selections | Routing telemetry: log `considered` vs `picked`, fold hit-rate back into ranking |
| Hook re-suggests the same agents on every prompt | Per-session "already shown" dedup flag |
| No way to see which registered agents are dead weight | Telemetry-driven quality grades (A–F) with hard floors |
| Keyword matching is exact-term only | Slug-token scoring (exact token ≫ substring), IDF-weighted |

Important distinction: `lib/telemetry.js` today is **anonymous network analytics** (opt-in, fire-and-forget to an endpoint). Everything below is **local-only JSONL** that never leaves the machine and powers ranking/quality. The two stay separate.

## Phase 1 — Routing telemetry (foundation)

**New file:** `lib/routing-log.js`

- Append-only JSONL at `<skill-dir>/references/routing-log.jsonl` (sits next to `registry.json`, git-ignored like other user data).
- Event shapes:
  - `{"event":"considered","agent":"react-expert","score":0.71,"session_id":"...","ts":"..."}` — emitted by `hooks/user_prompt_search.js` for each agent it injects.
  - `{"event":"picked","agent":"react-expert","session_id":"...","ts":"..."}` — emitted by `bin/get.js` on successful load.
- `hitRate(agent) = picked / max(considered, picked)`; return **neutral 0.5 when considered < 3** (ctx's minimum-observations rule — prevents one unlucky suggestion from tanking an agent).
- Truncate log to last 30 days on write (ctx truncates its intent log the same way; keeps the file small and reads fast).
- Writes are fire-and-forget and wrapped in try/catch — a telemetry failure must never break the hook or `get`.

**Touches:** `hooks/user_prompt_search.js`, `bin/get.js`
**Tests:** `tests/routing-log.test.js` — event append, hit-rate math, neutral prior, 30-day truncation, corrupt-line tolerance.

## Phase 2 — Session dedup in the hook

**Touches:** `hooks/user_prompt_search.js`

- The hook already receives `session_id` on stdin. Keep `<skill-dir>/references/.suggest-shown.json` mapping `session_id → [agent names already injected]`.
- Skip agents already shown this session; if all top-K were shown, exit silently (saves the injected-context tokens entirely).
- Prune entries older than 24h on write.

**Tests:** same agents not re-injected for same `session_id`; different session re-injects; stale sessions pruned.

## Phase 3 — Slug-token scoring upgrade

**Touches:** `lib/search.js`

ctx scores exact slug-token matches far above substring matches (50 vs 10 in its scale). Adapted to our 0–1 normalized space:

- Tokenize agent `name` on `-`/`_` (e.g. `react-expert` → `react`, `expert`).
- Exact query-term ↔ name-token match gets a strong boost; substring containment a small one; weight rare tokens higher (simple IDF over the registry: `log(N / df(token))`).
- Fold into the existing keyword component — formula becomes `0.6 * bm25 + 0.4 * keywordScore` where `keywordScore` now includes the token tier. No new dependencies.

**Tests:** extend `tests/search.test.js` — "react expert" ranks `react-expert` above agents that merely mention react in the summary; IDF de-weights ubiquitous tokens like `expert`.

## Phase 4 — Hit-rate feedback in ranking

**Touches:** `lib/search.js`, `hooks/user_prompt_search.js`

- Final hook-side score: `final = combined * (0.85 + 0.3 * hitRate)` — i.e. a never-picked agent (hitRate→0 after ≥3 observations) is dampened ~15%, a always-picked one boosted ~15%. Bounded multiplier so BM25 relevance still dominates (ctx keeps usage as a minority signal too).
- Applied only in the hook (where the feedback loop lives); `bin/search.js` stays pure relevance with an optional `--feedback` flag.

**Tests:** dampening/boost math; neutral prior leaves score unchanged; pure CLI search unaffected by log contents.

## Phase 5 — Quality grading command

**New files:** `bin/quality.js`, `lib/quality.js`

ctx grades every entity A–F from four weighted signals with hard floors. Adapted to what we can measure locally (no graph, no intake pipeline):

| Signal | Weight | Source |
|---|---|---|
| Usage (ever picked, recent picks saturating at 3 in 14d, recency linear-decay over 30d) | 0.45 | routing-log `picked` events |
| Routing hit-rate (neutral 0.5 under 3 observations) | 0.30 | routing-log considered/picked |
| Structure (summary present & non-trivial, ≥3 keywords, sane token_estimate, file still exists & hash matches) | 0.25 | `registry.json` + agent file |

- Grade bands: A ≥0.80, B ≥0.60, C ≥0.40, D otherwise.
- **Hard floors** (ctx pattern): missing/unparseable agent file ⇒ F; never-considered-and-never-picked ⇒ capped at D ("dead weight" flag).
- Output: table via `bun bin/quality.js`, `--json` for machine use, `--explain <agent>` for per-signal breakdown.

**Tests:** `tests/quality.test.js` — weighted sum, both hard floors, grade bands, `--explain` output.

## Phase 6 (stretch, separate decision) — Optional semantic ranker

ctx's `CosineRanker` is ~50 lines (L2-normalized matrix · query, top-k via partial sort) and would fix the "no fuzzy matching" limitation — but it requires an embedding source, which breaks the zero-dependency promise. Park it behind an explicit opt-in design doc; **not** part of this plan's deliverables. Revisit after Phases 1–5 ship and we can measure whether hit-rate feedback already closes most relevance gaps.

## Sequencing & dependencies

```
Phase 1 (routing log)  ──► Phase 4 (feedback ranking) ──► Phase 5 (quality grades)
Phase 2 (session dedup)     [independent, ship anytime]
Phase 3 (slug tokens)       [independent, ship anytime]
```

Each phase is a self-contained PR with tests; no phase changes `registry.json`'s schema.

## Build & test

```bash
bun install            # only dep: @clack/prompts (init UI)
bun test               # full suite (101 tests today; each phase adds its file)
bun bin/search.js "query"        # manual smoke
bun bin/quality.js               # after Phase 5
./install.sh           # user-level install to ~/.claude/skills/agent-registry/
```

Constraints to preserve: Bun-only built-ins for all search/scoring paths, CommonJS in `lib/`, silent-fail hooks, `registry.json`/`agents/` stay git-ignored, all new state lives under `references/` and is git-ignored too.
