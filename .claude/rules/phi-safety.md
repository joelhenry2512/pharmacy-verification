# PHI handling

This codebase handles Protected Health Information: patient names, DOBs,
addresses, prescriptions, prescriber identifiers. We are the pharmacy's
**business associate** under HIPAA. These are hard constraints, not preferences.

## Never

- **Never commit real patient data.** No real prescription images, no Liberty
  exports, no production database dumps. Not in fixtures, not in tests, not in
  a scratch file, not "temporarily."
- **Never put real PHI in a prompt** — yours, mine, or any model's. If you need
  a sample to reason about, use one from `fixtures/synthetic/`.
- **Never log PHI.** No patient name, DOB, address, or full Rx contents in
  console output, error messages, Sentry breadcrumbs, or analytics events. Log
  the record UUID and let an authorized user look it up.
- **Never put PHI in a URL** — no query strings, no path params. Record IDs only.

## Always

- Synthetic fixtures live in `fixtures/synthetic/` and are safe to commit.
- Anything real goes in `fixtures/real/` or `data/local/` — both gitignored.
- Redact before logging: use the `redactPhi()` helper.
- PHI-bearing tables are reached through the data layer, never raw SQL in a
  route handler.

## If you are about to violate one of these

Stop and say so instead. A blocked task is recoverable; a PHI disclosure is not.
