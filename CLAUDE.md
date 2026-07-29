# Pharmacy Verification Assistant

An AI assistant for **independent pharmacies** that automates prescription data
entry and prepares a drafted record for **pharmacist verification**. It sits on
top of an existing pharmacy management system (PMS) — it is not a PMS and never
replaces one. Pilot PMS: **Liberty (RxQ)**, via its PIN-authenticated API.

Pipeline: intake → extraction → match/validate → verification draft → write-back.

Full strategy, market position, and phase plan: `docs/game-plan.pdf`.

## Where the rules live

The whole team develops in **Cursor**, so `.cursor/rules/` is the canonical
rule set and this file imports from it. Edit the `.mdc` files — not a copy here —
or Cursor and Claude Code will drift apart.

- @.cursor/rules/00-project.mdc — non-negotiables, v1 scope decisions
- @.cursor/rules/10-phi-safety.mdc — **read before touching data, fixtures, or logs**
- @.cursor/rules/20-schema-contract.mdc — using and changing `@rx/schema`

Lane-scoped rules load by path in Cursor; read the relevant one before working
in that package:

- `.cursor/rules/30-extraction.mdc` → `packages/extraction/`
- `.cursor/rules/40-verification-ui.mdc` → `apps/web/`
- `.cursor/rules/50-liberty-connector.mdc` → `packages/liberty/`, `packages/db/`

## The four that never bend

- **Pharmacist-in-the-loop, always.** Never write code that dispenses,
  finalizes, or writes back a prescription without an explicit pharmacist
  action. All-green earns a one-tap fast lane, never zero-touch.
- **The model never assigns clinical tiers.** It reports what it read and how
  confident it was. Tiers are computed by our scorer from model signal + RxNorm
  score margin + NDC-in-stock + patient history.
- **Liberty's clinical/DUR engine stays authoritative** at final verification.
  Our pre-checks surface concerns earlier; they don't replace it.
- **Audit tables are append-only.** Never UPDATE or DELETE a CorrectionEvent or
  VerificationEvent.

## PHI

This codebase handles Protected Health Information. No real patient data in this
repo, in a log line, or in a prompt — ever, not even temporarily. Synthetic
fixtures only. Details in the PHI rule above.

## Layout

```
apps/web/            Next.js verification UI          → Vibhas
packages/schema/     canonical Rx contract (Zod)      → Joel, all consume
packages/db/         Prisma schema + client           → Joel
packages/liberty/    Liberty API connector            → Joel
packages/extraction/ intake, VLM, RxNorm grounding    → Ananth
fixtures/synthetic/  safe, committed test data
fixtures/real/       GITIGNORED — never commit
docs/game-plan.pdf   full strategy (confidential)
```

## Commands

```bash
pnpm install
pnpm dev              # all workspaces
pnpm typecheck        # tsc across the monorepo
pnpm test
pnpm db:migrate
```

Run `pnpm typecheck` and the closest test before reporting a task complete.

## Conventions

- TypeScript strict everywhere. Zod for validation at every process boundary.
- Import types from `@rx/schema`. Never redefine a prescription type locally.
- Branches: `lane/short-description` (`extraction/rxnorm-fallback`).
  Conventional commits. PRs need one review from outside your lane; anything
  touching `packages/schema` needs Joel's review.
- Prefer boring, well-tested choices over clever ones.
