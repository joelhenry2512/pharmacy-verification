# Pharmacy Verification Assistant

An AI assistant for **independent pharmacies** that automates prescription data
entry and prepares a drafted record for **pharmacist verification**. It sits on
top of an existing pharmacy management system (PMS) — it is not a PMS and never
replaces one. Pilot PMS: **Liberty (RxQ)**, via its PIN-authenticated API.

Pipeline: intake → extraction → match/validate → verification draft → write-back.

Full strategy: @docs/game-plan.pdf

## Non-negotiables

- **Pharmacist-in-the-loop, always.** Never write code that dispenses, finalizes,
  or writes back a prescription without an explicit pharmacist action. There is
  no auto-approve path, even for all-green records.
- **The model never assigns clinical tiers.** It reports what it read and how
  confident it was. Tiers are computed by our scorer from model signal + RxNorm
  score margin + NDC-in-stock + patient history. Don't shortcut this.
- **Liberty's clinical/DUR engine stays authoritative** at final verification.
  Our pre-checks surface concerns earlier; they don't replace it.
- **Audit tables are append-only.** Never UPDATE or DELETE a CorrectionEvent or
  VerificationEvent.

## PHI

This codebase handles Protected Health Information. See @.claude/rules/phi-safety.md
before touching data, fixtures, or logging. The short version: no real patient
data in this repo, in a log line, or in a prompt — ever, not even temporarily.

## Layout

```
apps/web/            Next.js verification UI          → Vibhas
packages/schema/     canonical Rx contract (Zod)      → Joel, all consume
packages/db/         Prisma schema + client           → Joel
packages/liberty/    Liberty API connector            → Joel
packages/extraction/ intake, VLM, RxNorm grounding    → Ananth
fixtures/synthetic/  safe, committed test data
fixtures/real/       GITIGNORED — never commit
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
- Import types from `@rx/schema`. Never redefine a prescription type locally —
  see @.claude/rules/schema-contract.md
- Branches: `lane/short-description` (`extraction/rxnorm-fallback`).
  Conventional commits. PRs need one review from outside your lane; anything
  touching `packages/schema` needs Joel's review.
- Prefer boring, well-tested choices over clever ones.
