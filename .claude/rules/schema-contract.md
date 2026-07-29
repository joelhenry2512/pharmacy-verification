---
paths:
  - "packages/**/*.ts"
  - "apps/**/*.ts"
  - "apps/**/*.tsx"
---

# The schema is the contract

`packages/schema` defines the canonical prescription types. Three workstreams
depend on it simultaneously, so treat it like a public API.

- **Import, don't redefine.** Never declare a local `Prescription`, `RxField`,
  or similar type. If something is missing, add it to `packages/schema` and open
  a PR — a duplicate type is how the three lanes silently diverge.
- **Validate at every boundary.** Parse with Zod when data crosses a process
  edge: Liberty API responses, VLM output, HTTP bodies, queue payloads. Inside a
  module, trust the parsed type.
- **`VlmPrescriptionExtraction` is what the model returns** — narrow, no tiers.
  `VerificationRecord` is the enriched object the UI and audit log use. Don't
  blur them.
- **Bump `schemaVersion` on any breaking change** and note it in the PR. Records
  already in Postgres carry their original version.

## The model's output contract

Generate the VLM's JSON Schema from `VlmPrescriptionExtraction` rather than
hand-writing it — one definition drives the TypeScript type, runtime validation,
and the structured-output contract. If they drift, extraction breaks quietly.
