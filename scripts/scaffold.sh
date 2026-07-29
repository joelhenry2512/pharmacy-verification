#!/usr/bin/env bash
# Scaffolds the monorepo. Idempotent — safe to re-run.
# Usage: ./scripts/scaffold.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "→ directories"
mkdir -p apps/web \
         packages/{schema,db,liberty,extraction}/src \
         packages/db/prisma \
         fixtures/{synthetic,real} \
         docs \
         .github/workflows

# ── workspace ──────────────────────────────────────────────────────
cat > pnpm-workspace.yaml <<'EOF'
packages:
  - "apps/*"
  - "packages/*"
EOF

cat > package.json <<'EOF'
{
  "name": "pharmacy-verification",
  "private": true,
  "packageManager": "pnpm@9.12.0",
  "engines": { "node": ">=20" },
  "scripts": {
    "dev": "pnpm -r --parallel dev",
    "build": "pnpm -r build",
    "typecheck": "pnpm -r typecheck",
    "test": "pnpm -r test",
    "lint": "pnpm -r lint",
    "db:migrate": "pnpm --filter @rx/db migrate",
    "db:studio": "pnpm --filter @rx/db studio"
  },
  "devDependencies": {
    "typescript": "^5.6.0",
    "@types/node": "^22.0.0"
  }
}
EOF

cat > tsconfig.base.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "declaration": true,
    "composite": true
  }
}
EOF

# ── packages ───────────────────────────────────────────────────────
make_pkg () {
  local name="$1" desc="$2" deps="$3"
  cat > "packages/${name}/package.json" <<EOF
{
  "name": "@rx/${name}",
  "version": "0.0.0",
  "private": true,
  "description": "${desc}",
  "type": "module",
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "scripts": {
    "typecheck": "tsc --noEmit",
    "test": "node --test"
  },
  "dependencies": ${deps}
}
EOF
  cat > "packages/${name}/tsconfig.json" <<'EOF'
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": { "outDir": "dist", "rootDir": "src" },
  "include": ["src/**/*.ts"]
}
EOF
}

make_pkg schema     "Canonical prescription contract"        '{ "zod": "^4.0.0" }'
make_pkg liberty    "Liberty (RxQ) API connector"            '{ "@rx/schema": "workspace:*", "zod": "^4.0.0" }'
make_pkg extraction "Intake, VLM extraction, RxNorm/NDC"     '{ "@rx/schema": "workspace:*", "zod": "^4.0.0" }'
make_pkg db         "Prisma schema and client"               '{ "@prisma/client": "^5.20.0" }'

# barrel files (won't clobber real work)
[ -f packages/schema/src/index.ts ]     || echo 'export * from "./prescription.js";' > packages/schema/src/index.ts
[ -f packages/liberty/src/index.ts ]    || echo '// Liberty connector — Joel. PIN auth, patient/dispensing/inventory pulls.' > packages/liberty/src/index.ts
[ -f packages/extraction/src/index.ts ] || echo '// Extraction pipeline — Ananth. Stages 1-2 + drug grounding.' > packages/extraction/src/index.ts

# ── prisma ─────────────────────────────────────────────────────────
if [ ! -f packages/db/prisma/schema.prisma ]; then
cat > packages/db/prisma/schema.prisma <<'EOF'
// Mirrors packages/schema. Rich nested field envelopes are stored as Json;
// anything we filter, sort, or report on is promoted to a real column.
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

enum RecordStatus {
  intake
  extracting
  resolving
  ready_for_verification
  verified
  rejected
  written_back
  error
}

enum Lane {
  fast
  review
}

enum Tier {
  green
  amber
  red
}

model VerificationRecord {
  id            String       @id @default(uuid())
  schemaVersion String
  status        RecordStatus
  lane          Lane
  overallTier   Tier

  /// IntakeSource — imageKey is an object-store key, never a public URL.
  source        Json
  /// Field envelopes: value + provenance + confidence + bbox + tier.
  patient       Json
  drug          Json
  prescriber    Json
  dateWritten   Json
  preChecks     Json         @default("[]")

  /// Set once matched to a Liberty profile. Indexed for patient lookup.
  libertyPatientId String?

  createdAt     DateTime     @default(now())
  updatedAt     DateTime     @updatedAt

  corrections   CorrectionEvent[]
  events        VerificationEvent[]

  @@index([status, lane])
  @@index([libertyPatientId])
}

/// APPEND-ONLY. Never UPDATE or DELETE. Compliance trail + calibration signal.
model CorrectionEvent {
  id            String   @id @default(uuid())
  recordId      String
  record        VerificationRecord @relation(fields: [recordId], references: [id])
  fieldPath     String
  previousValue Json?
  newValue      Json?
  previousTier  Tier
  correctedBy   String
  correctedAt   DateTime @default(now())
  reason        String?

  @@index([recordId])
  @@index([fieldPath])
}

/// APPEND-ONLY. secondsOnScreen is our headline pilot metric.
model VerificationEvent {
  id                   String   @id @default(uuid())
  recordId             String
  record               VerificationRecord @relation(fields: [recordId], references: [id])
  action               String
  pharmacistId         String
  laneAtDecision       Lane
  overallTierAtDecision Tier
  secondsOnScreen      Float
  occurredAt           DateTime @default(now())

  @@index([recordId])
  @@index([occurredAt])
}
EOF
fi

cat > packages/db/package.json <<'EOF'
{
  "name": "@rx/db",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "migrate": "prisma migrate dev",
    "studio": "prisma studio",
    "generate": "prisma generate",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": { "@prisma/client": "^5.20.0" },
  "devDependencies": { "prisma": "^5.20.0" }
}
EOF

# ── env + CI ───────────────────────────────────────────────────────
cat > .env.example <<'EOF'
# Copy to .env — never commit .env
DATABASE_URL="postgresql://localhost:5432/pharmacy_dev"

# Liberty (RxQ) — 7-digit key from System > Settings > API Keys
LIBERTY_API_KEY=""
LIBERTY_BASE_URL=""

# Model provider — must be covered by a signed BAA before any real PHI
MODEL_API_KEY=""

# Object store for prescription images (PHI — private bucket, no public ACL)
STORAGE_BUCKET=""
EOF

cat > .github/workflows/ci.yml <<'EOF'
name: CI
on:
  push: { branches: [main] }
  pull_request:

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with: { version: 9 }
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: pnpm }
      - run: pnpm install --frozen-lockfile
      - run: pnpm typecheck
      - run: pnpm test

  phi-guard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Block committed real fixtures
        run: |
          if git ls-files | grep -qE '^(fixtures/real/|data/local/)'; then
            echo "::error::Real PHI fixtures are committed. Remove them and scrub history."
            exit 1
          fi
EOF

cat > .github/CODEOWNERS <<'EOF'
# The schema is a shared contract — changes need the integration lead.
/packages/schema/   @JOEL_GH_HANDLE
/packages/db/       @JOEL_GH_HANDLE
/.github/           @JOEL_GH_HANDLE
EOF

touch fixtures/synthetic/.gitkeep

echo "✓ scaffold complete"
echo "  next: pnpm install && cp .env.example .env"
