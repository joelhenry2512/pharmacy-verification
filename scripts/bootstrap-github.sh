#!/usr/bin/env bash
# Creates the GitHub repo, labels, milestones, and Phase 0-3 issues.
# Requires: gh CLI, already authenticated (`gh auth status` to check).
# Usage: ./scripts/bootstrap-github.sh
set -euo pipefail

# ── EDIT THESE ─────────────────────────────────────────────────────
REPO_NAME="pharmacy-verification"       # rename once the product name is locked
VISIBILITY="private"                    # keep private — this repo touches PHI design

# Real handles, for reference: ananth-123 (Ananth), vibhas-krishnapuram (Vibhas).
# Left blank below until each is invited as a collaborator — GitHub rejects
# --assignee for a non-collaborator, which would abort this script partway
# through issue creation. Once invited, set these and re-run (mkissue is
# idempotent-ish for labels/milestones; issues would need manual assignment
# or a second pass).
JOEL="joelhenry2512"
ANANTH=""
VIBHAS=""
MATT=""                                 # add as member even though he won't push
ANJALI=""
# ───────────────────────────────────────────────────────────────────

command -v gh >/dev/null || { echo "gh CLI not found: https://cli.github.com"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Run 'gh auth login' first."; exit 1; }

echo "→ creating repo"
if gh repo view "$REPO_NAME" >/dev/null 2>&1; then
  echo "  exists, continuing"
else
  gh repo create "$REPO_NAME" --"$VISIBILITY" --source=. --remote=origin \
    --description "AI prescription data entry + pharmacist verification for independent pharmacies"
fi

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "  → $REPO"

echo "→ labels"
mklabel () { gh label create "$1" --color "$2" --description "$3" --force >/dev/null; }
mklabel "lane:integration" "0d7a6f" "Liberty connector, schema, infra, write-back"
mklabel "lane:extraction"  "1f6feb" "Intake, VLM, RxNorm/NDC grounding"
mklabel "lane:ui"          "8250df" "Verification surface, matching, pre-checks"
mklabel "lane:clinical"    "b06a00" "Clinical correctness, protocol, ground truth"
mklabel "phi"              "d1242f" "Touches Protected Health Information — extra review"
mklabel "blocker"          "d1242f" "Blocks another lane"
mklabel "spike"            "6e7781" "Timeboxed investigation, throwaway code OK"

echo "→ milestones"
mkmilestone () {
  gh api "repos/$REPO/milestones" -f title="$1" -f description="$2" >/dev/null 2>&1 || true
}
mkmilestone "Phase 0 · Foundations (wk 1-2)"  "De-risk + scaffold. API spec confirmed, BAAs signed, baseline measured."
mkmilestone "Phase 1 · Extraction (wk 3-5)"   "eScript parser, VLM extraction, RxNorm/NDC grounding, scored vs gold set."
mkmilestone "Phase 2 · Verify UI (wk 5-8)"    "Matching, pre-checks, verification screen, correction logging."
mkmilestone "Phase 3 · Pilot (wk 8-12)"       "Shadow then assist mode in the pharmacy. Measure, calibrate weekly."

echo "→ issues"
mkissue () { # title, body, labels, milestone, assignee
  gh issue create --title "$1" --body "$2" --label "$3" \
     --milestone "$4" ${5:+--assignee "$5"} >/dev/null
  echo "  · $1"
}

M0="Phase 0 · Foundations (wk 1-2)"
M1="Phase 1 · Extraction (wk 3-5)"
M2="Phase 2 · Verify UI (wk 5-8)"
M3="Phase 3 · Pilot (wk 8-12)"

# ── PHASE 0 ────────────────────────────────────────────────────────
mkissue "Get Liberty API spec + write-back scope in writing" \
"Via the pharmacy owner's account, contact Liberty dev/support for the full API spec.

**Must answer before architecture is locked:**
- Can we WRITE a drafted/entered Rx, or is the API read-only today?
- Rate limits
- Any data agreement required

This is the single biggest unknown in the plan. If write is limited, v1 becomes
'automate everything upstream, pharmacist confirms in RxQ' — still shippable." \
"lane:integration,blocker" "$M0" "$JOEL"

mkissue "Execute HIPAA BAAs (pharmacy ↔ us, us ↔ model provider)" \
"Two agreements:
1. Pharmacy ↔ us — we are their business associate
2. Us ↔ model provider — PHI hits the model at extraction

**No real PHI touches any system until both are signed.**
Also confirm what the IDE/AI tooling retains, since code context leaves the machine." \
"lane:integration,phi,blocker" "$M0" "$JOEL"

mkissue "Generate Liberty API key, confirm live data pull" \
"In RxQ: System > Settings > API Keys (beta builds: Settings > Utilities) > Add.
Generates a random 7-digit key. Label it and save.

Done when we can pull live patient/dispensing data into a test DB, parsed into
the canonical schema." \
"lane:integration" "$M0" "$JOEL"

mkissue "Scaffold monorepo, CI, Postgres, secrets management" \
"pnpm workspaces, Prisma + Postgres, GitHub Actions, secrets handling, append-only
audit tables. Run scripts/scaffold.sh then wire up the DB." \
"lane:integration" "$M0" "$JOEL"

mkissue "Canonical prescription schema v1.0.0 — review and sign-off" \
"packages/schema/src/prescription.ts is drafted. All three devs review and sign off
before building against it — this is the shared contract and changing it later is
expensive.

Points to confirm:
- Field envelope shape (value + provenance + confidence + bbox + tier)
- VlmPrescriptionExtraction vs VerificationRecord split
- Whether any NCPDP field is missing" \
"lane:integration,blocker" "$M0" "$JOEL"

mkissue "Week-1 baseline: time ~20 real scripts through current RxQ flow" \
"Time the existing data-entry + verification workflow end to end for ~20 real
prescriptions. Median seconds-per-script is the number every later claim is
measured against.

Capture the mix: eScript vs fax vs handwritten." \
"lane:clinical,blocker" "$M0" "$ANJALI"

mkissue "Map the RxQ data-entry workflow step-by-step" \
"Screenshot each screen in the current data-entry and verification path so the
devs can see what they're modelling. Note every field that has to be filled and
where it comes from.

Screenshots must not contain real patient data — use a test patient or redact." \
"lane:clinical,phi" "$M0" "$ANJALI"

mkissue "Field-level correctness rubric + initial tier thresholds" \
"Define what 'correct' means per field, and the green/amber/red thresholds.

Inputs to the composite scorer: model confidence, RxNorm score margin,
NDC-in-stock, patient-history consistency. Starting values are placeholders in
packages/schema — replace them with clinically defensible numbers." \
"lane:clinical,blocker" "$M0" "$MATT"

mkissue "Michigan board of pharmacy rules check" \
"Data-entry and verification rules, technician ratios, anything touching
AI-assisted entry or who may perform which step. Flag constraints before they
surprise us mid-pilot.

Also confirm: during assist mode, final sign-off sits with the store's licensed
pharmacist on duty." \
"lane:clinical,blocker" "$M0" "$MATT"

mkissue "Gold-standard labeling protocol" \
"Define how prescriptions get labeled for the eval set: which fields, what counts
as a disagreement, how disputes are adjudicated. Anjali collects, Matt adjudicates.

Target a set that includes messy faxes and handwriting, not just clean eScripts." \
"lane:clinical" "$M0" "$MATT"

mkissue "Build synthetic fixture set (no PHI)" \
"Realistic but entirely fabricated prescriptions covering eScript XML, clean fax,
messy fax, handwritten. These are what we develop and demo against.

**Blocks safe development** — until this exists people will be tempted to use
real scripts." \
"lane:extraction,phi,blocker" "$M0" "$ANANTH"

mkissue "SPIKE: VLM extraction on 10-20 sample scripts" \
"Timeboxed. Structured-output extraction against VlmPrescriptionExtraction on a
mixed sample. Goal is a starting accuracy number per field and a sense of where
confidence is well- vs poorly-calibrated.

Throwaway code is fine — we want the number, not the implementation." \
"lane:extraction,spike" "$M0" "$ANANTH"

mkissue "SPIKE: RxNorm resolution (exact → normalized → approximate)" \
"Hit NLM RxNorm REST: findRxcuiByString for clean strings, getApproximateMatch as
fallback. Measure how often a garbled name still resolves, and what score margin
separates a confident match from a coin flip.

Also sanity-check the ~25% eScript non-resolution figure against our own data." \
"lane:extraction,spike" "$M0" "$ANANTH"

mkissue "Wireframe the verification screen" \
"Two-lane queue (fast/review), side-by-side image + fields, bounding-box overlay,
green/amber/red treatment, focus landing on the riskiest field.

Review with Matt and Anjali before building — they're the users." \
"lane:ui" "$M0" "$VIBHAS"

mkissue "Scaffold Next.js app + queue table schema" \
"App Router, Prisma client, TanStack Query. Polling against a Postgres-backed
queue table — no websockets until staleness is actually noticed." \
"lane:ui" "$M0" "$VIBHAS"

# ── PHASE 1 ────────────────────────────────────────────────────────
mkissue "eScript (NCPDP SCRIPT XML) parser → canonical schema" \
"Parse NEWRX and REFREQ into VerificationRecord with provenance='escript'.
The easy 60-70% of volume — should be near-zero error." \
"lane:extraction" "$M1" "$ANANTH"

mkissue "Image preprocessing for faxes and handwriting" \
"Deskew, denoise, contrast normalization, multi-page splitting. Handwriting routes
to a higher-scrutiny path." \
"lane:extraction" "$M1" "$ANANTH"

mkissue "VLM extraction: strict JSON schema + confidence + bbox in one pass" \
"Generate the JSON Schema from VlmPrescriptionExtraction — do not hand-write it.
Normalized bounding boxes power the click-to-source overlay." \
"lane:extraction" "$M1" "$ANANTH"

mkissue "RxNorm resolver with score margins" \
"Production version of the spike: exact → normalized → approximate, recording
topCandidate, runnerUp, and scoreMargin into DrugResolution." \
"lane:extraction" "$M1" "$ANANTH"

mkissue "RxCUI → NDC via openFDA, intersect with Liberty stock" \
"Resolve concept to package NDCs, then intersect with the pharmacy's actual
inventory. Flags out-of-stock early, which independents care about." \
"lane:extraction" "$M1" "$ANANTH"

mkissue "Composite tier scorer" \
"Combine model signal + score margin + stock + history into green/amber/red using
Matt's thresholds from config, not hardcoded.

**The model never assigns its own tier.**" \
"lane:extraction" "$M1" "$ANANTH"

mkissue "Eval harness against the gold set" \
"Per-field accuracy plus confidence calibration. Wire correction data back in as
it accumulates so we can see calibration drift during pilot." \
"lane:extraction" "$M1" "$ANANTH"

# ── PHASE 2 ────────────────────────────────────────────────────────
mkissue "Two-lane verification queue" \
"All-green → fast lane (one tap to accept, never zero-touch).
Any amber/red → review lane, sorted by severity." \
"lane:ui" "$M2" "$VIBHAS"

mkissue "Side-by-side viewer with bidirectional bbox overlay" \
"Image/PDF (pdf.js) beside the form. Click a field → highlight its source region;
click a region → focus its field. This is what makes correction faster than
retyping." \
"lane:ui" "$M2" "$VIBHAS"

mkissue "Tier-driven UX" \
"Green pre-checked and quiet; amber requires explicit acknowledgment; red blocks
the fast path. Focus auto-lands on the riskiest field, not the top of the form." \
"lane:ui" "$M2" "$VIBHAS"

mkissue "Patient matcher against Liberty profiles" \
"Fuzzy name/DOB match with candidate list. New vs existing patient changes how
much history we can cross-check." \
"lane:ui,phi" "$M2" "$VIBHAS"

mkissue "Pre-checks: allergy, duplicate therapy, dose plausibility" \
"Run against the Liberty profile before the pharmacist looks.

**Additive only** — Liberty's own DUR engine stays authoritative at final verify." \
"lane:ui" "$M2" "$VIBHAS"

mkissue "Correction logging → append-only audit trail" \
"Every field edit emits a CorrectionEvent. Never UPDATE or DELETE.
Doubles as the calibration signal for the eval harness." \
"lane:ui,phi" "$M2" "$VIBHAS"

mkissue "Metrics dashboard" \
"Median seconds-per-script (the headline number), auto-accept rate, corrections by
field, flags caught. Compared against Anjali's Week-1 baseline." \
"lane:ui" "$M2" "$VIBHAS"

mkissue "Write-back to Liberty" \
"Push the verified record via API where supported. If write scope is limited,
build the clean manual-confirm handoff instead.

**Never auto-dispense without the pharmacist checkpoint.**" \
"lane:integration,phi" "$M2" "$JOEL"

# ── PHASE 3 ────────────────────────────────────────────────────────
mkissue "Shadow mode deployment" \
"AI drafts but changes nothing in RxQ. Pharmacists compare against what they'd
have typed. Trust is earned before the tool touches the workflow." \
"lane:clinical" "$M3" "$MATT"

mkissue "Assist mode cutover" \
"Only after shadow-mode accuracy holds. Final sign-off stays with the licensed
pharmacist on duty." \
"lane:clinical" "$M3" "$MATT"

mkissue "Weekly calibration loop" \
"Standing review: what the AI missed, what it flagged correctly, where it saved
time. Every correction becomes a test case." \
"lane:clinical" "$M3" "$ANJALI"

echo
echo "✓ done → https://github.com/$REPO"
echo "  next: protect main (require 1 review + CI green), add Matt and Anjali as members"
