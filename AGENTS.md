# AGENTS.md

Project overview, rules, and standard commands live in `README.md`, `CLAUDE.md`,
and `.cursor/rules/`. Read `.cursor/rules/10-phi-safety.mdc` before touching data,
fixtures, or logs. Standard scripts are in the root `package.json`
(`pnpm dev|build|typecheck|test|lint`, `pnpm db:migrate`, `pnpm db:studio`).

## Cursor Cloud specific instructions

State of the repo: this is an early-stage pnpm-workspaces monorepo. Only
`packages/schema` (`@rx/schema`, the canonical Zod contract) has real code.
`packages/db` (`@rx/db`) ships a Prisma schema. `packages/liberty` and
`packages/extraction` are stubs, and `apps/web` does not exist yet.

Node 22 and `pnpm` (9.12.0) are preinstalled; `pnpm install` is the only
dependency step (handled by the startup update script).

### PostgreSQL (required for any `@rx/db` work)

- PostgreSQL 16 is installed but is **not started automatically** on VM boot.
  Start it each session with: `sudo pg_ctlcluster 16 main start`.
- A `pharmacy` role (password `pharmacy`, has `CREATEDB`) and a `pharmacy_dev`
  database already exist in the snapshot. `CREATEDB` is required — Prisma
  Migrate needs it to create its shadow database.
- The DB connection string is in `.env` (gitignored, not the placeholder from
  `.env.example`): `postgresql://pharmacy:pharmacy@localhost:5432/pharmacy_dev`.
- Prisma commands do not auto-load the root `.env`. Load it first, e.g. from
  `packages/db`: `set -a && . /workspace/.env && set +a` before
  `pnpm exec prisma generate` / `pnpm exec prisma migrate dev` / `pnpm db:studio`.
- The initial migration (`packages/db/prisma/migrations/`) is generated locally,
  not committed. If tables are missing, recreate with
  `pnpm exec prisma migrate dev --name init` (env loaded, Postgres running).

### Running / testing caveats

- `pnpm dev` currently starts nothing runnable: there is no `apps/web` and no
  package defines a `dev` script. There is no HTTP server or UI to exercise yet.
- `pnpm lint` is a no-op — no package defines a `lint` script (exits 0).
- `pnpm test` runs `node --test`; there are no test files yet, so it passes with
  zero tests. `@rx/schema` is executable TypeScript — run ad-hoc scripts with
  `pnpm dlx tsx <file>` (native `node --experimental-strip-types` will not
  resolve the package's `.js`→`.ts` internal imports).
- Known pre-existing failure (not an environment issue): `pnpm typecheck` fails
  in `packages/db` with `TS18003: No inputs were found` because its `tsconfig`
  includes `src/**/*.ts` but the package has no `src/` files (only `prisma/`).
  This also makes CI red on `main`. Other packages typecheck cleanly.
