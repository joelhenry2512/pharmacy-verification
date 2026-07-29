# Pharmacy Verification Assistant

Automates prescription data entry and prepares a drafted record for pharmacist
verification, sitting on top of an existing pharmacy management system.
Pilot PMS: **Liberty (RxQ)**. Full strategy in `docs/game-plan.pdf`.

> **Rename me.** Package scope is `@rx/*` as a placeholder — swap it once the
> product name is locked.

## Repo layout

```
apps/
  web/                 Next.js verification UI                → Vibhas
packages/
  schema/              canonical Rx contract (Zod)            → Joel, all consume
  db/                  Prisma schema + client                 → Joel
  liberty/             Liberty API connector                  → Joel
  extraction/          intake, VLM, RxNorm/NDC grounding      → Ananth
fixtures/
  synthetic/           safe, committed test data
  real/                GITIGNORED — never commit
docs/
```

## Lane ownership

| Lane | Owner | Pipeline stages |
|---|---|---|
| Integration & infra | Joel | connector, schema, DB, CI, write-back |
| Extraction & AI | Ananth | 1–2: intake, VLM extraction, drug resolution |
| Product & UI | Vibhas | 3–4: matching, pre-checks, verification screen |

Clinical direction (what "correct" and "safe" mean) sits with **Matt**;
ground truth and pilot feedback come from **Anjali**.

> The Ananth/Vibhas split is swappable based on who's stronger on ML-pipeline
> vs product/frontend work. Lock it at the Week-1 kickoff and stick with it.

## Setup

```bash
pnpm install
cp .env.example .env      # fill in — never commit .env
pnpm db:migrate
pnpm dev
```

## Cursor

The team develops in Cursor, so `.cursor/rules/` is the canonical rule set —
it's committed, and everyone gets identical project context.

| Rule | Scope |
|---|---|
| `00-project.mdc` | always — non-negotiables, v1 scope decisions |
| `10-phi-safety.mdc` | always — **read this first** |
| `20-schema-contract.mdc` | `packages/**`, `apps/**` TypeScript |
| `30-extraction.mdc` | `packages/extraction/` |
| `40-verification-ui.mdc` | `apps/web/` |
| `50-liberty-connector.mdc` | `packages/liberty/`, `packages/db/` |

Path-scoped rules attach when you open a matching file, so you get your lane's
decisions without loading everyone else's. `CLAUDE.md` imports the same files
for anyone on Claude Code — edit the `.mdc`, never a copy.

If you add an MCP server in Cursor, note `.cursor/mcp.json` is gitignored — it
tends to hold API keys.

## Working agreements

- Branch as `lane/short-description` (`extraction/rxnorm-fallback`,
  `ui/bbox-overlay`). Never commit straight to `main`.
- PRs need one review from outside your lane. Anything touching
  `packages/schema` needs Joel's review.
- Conventional commits (`feat:`, `fix:`, `chore:`).
- **Read `.cursor/rules/10-phi-safety.mdc` before your first commit.**

## The three rules that matter most

1. No prescription is ever finalized without an explicit pharmacist action.
2. No real patient data in this repo, in a log line, or in an AI chat.
3. The schema is the contract — extend it, don't fork it.
