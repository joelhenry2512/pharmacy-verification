/**
 * CANONICAL PRESCRIPTION CONTRACT
 * ------------------------------------------------------------------
 * The single source of truth every workstream builds against.
 *
 *   Joel    → Liberty connector emits / consumes these types
 *   Ananth  → extraction pipeline produces VlmPrescriptionExtraction,
 *             then enriches into VerificationRecord
 *   Vibhas  → the UI renders VerificationRecord and emits CorrectionEvent
 *
 * RULES OF THE ROAD
 *  1. Nobody defines a parallel prescription type in their own package.
 *     If a field is missing, change it HERE and open a PR — don't fork.
 *  2. Zod gives us three things from one definition: the TypeScript type,
 *     runtime validation at every boundary, and a JSON Schema we hand to
 *     the VLM for structured extraction. Keep it that way.
 *  3. The model NEVER assigns a tier. It reports what it saw and how sure
 *     it was. Tiers are computed by our scorer from model signal +
 *     RxNorm score margin + stock + patient history. See computeTier().
 */

import { z } from "zod";

/* ═══════════════════════════════════════════════════════════════
   PRIMITIVES
   ═══════════════════════════════════════════════════════════════ */

/** Normalized to 0–1 so it survives any rescaling of the source image. */
export const BoundingBox = z.object({
  page: z.number().int().nonnegative(),
  x: z.number().min(0).max(1),
  y: z.number().min(0).max(1),
  width: z.number().min(0).max(1),
  height: z.number().min(0).max(1),
});
export type BoundingBox = z.infer<typeof BoundingBox>;

/** Where a value came from. Drives how much we trust it by default. */
export const Provenance = z.enum([
  "escript", //  parsed from NCPDP SCRIPT XML — structured, high trust
  "vlm_extraction", //  read off an image by the model
  "pms_lookup", //  pulled from Liberty (patient profile, inventory)
  "pharmacist_entry", //  typed or corrected by a human — always wins
  "derived", //  computed by us (e.g. days supply from qty + sig)
]);
export type Provenance = z.infer<typeof Provenance>;

export const Tier = z.enum(["green", "amber", "red"]);
export type Tier = z.infer<typeof Tier>;

/** Why a field landed in its tier. Shown in the UI, stored in the audit log. */
export const TierReason = z.enum([
  // resolution outcomes
  "exact_match",
  "normalized_match",
  "approximate_match_clear_margin",
  "approximate_match_close_runner_up",
  "no_rxnorm_match",
  // inventory / history
  "ndc_in_stock",
  "ndc_not_in_stock",
  "consistent_with_history",
  "new_to_patient",
  // risk signals
  "low_model_confidence",
  "field_missing",
  "implausible_dose",
  "allergy_conflict",
  "duplicate_therapy",
  "controlled_substance",
  // human
  "pharmacist_corrected",
]);
export type TierReason = z.infer<typeof TierReason>;

/* ═══════════════════════════════════════════════════════════════
   STAGE 2 — WHAT THE MODEL RETURNS
   Deliberately narrow. No tiers, no resolution, no clinical judgment.
   Hand the JSON Schema of this object to the VLM as its output contract.
   ═══════════════════════════════════════════════════════════════ */

export function vlmField<T extends z.ZodTypeAny>(inner: T) {
  return z.object({
    value: inner.nullable(),
    /** Model's own certainty. A soft signal — never used alone. */
    confidence: z.number().min(0).max(1),
    /** Powers the click-to-source overlay in the verification UI. */
    bbox: BoundingBox.nullable().default(null),
    /** Free-text note when the model saw something ambiguous. */
    note: z.string().nullable().default(null),
  });
}

export const VlmPrescriptionExtraction = z.object({
  patientName: vlmField(z.string()),
  patientDob: vlmField(z.string()), // ISO 8601 where legible
  patientAddress: vlmField(z.string()),

  drugName: vlmField(z.string()), // as literally written
  strength: vlmField(z.string()), // "10 mg", "5 mg/mL"
  dosageForm: vlmField(z.string()), // tablet, capsule, suspension
  quantity: vlmField(z.number()),
  sig: vlmField(z.string()), // directions, verbatim
  daysSupply: vlmField(z.number()),
  refills: vlmField(z.number()),
  daw: vlmField(z.boolean()), // dispense as written

  prescriberName: vlmField(z.string()),
  prescriberNpi: vlmField(z.string()),
  prescriberDea: vlmField(z.string()), // controlled substances only
  dateWritten: vlmField(z.string()),

  /** Model flags anything it could not read at all. */
  illegibleRegions: z.array(BoundingBox).default([]),
});
export type VlmPrescriptionExtraction = z.infer<typeof VlmPrescriptionExtraction>;

/* ═══════════════════════════════════════════════════════════════
   STAGE 2b — DRUG RESOLUTION (the moat)
   RxNorm exact → normalized → approximate, then RxCUI → NDC,
   intersected with what the pharmacy actually stocks.
   ═══════════════════════════════════════════════════════════════ */

export const RxNormCandidate = z.object({
  rxcui: z.string(),
  name: z.string(),
  score: z.number(), // as returned by getApproximateMatch
  tty: z.string().nullable().default(null), // SCD, SBD, IN, ...
});
export type RxNormCandidate = z.infer<typeof RxNormCandidate>;

export const DrugResolution = z.object({
  method: z.enum(["exact", "normalized", "approximate", "unresolved"]),
  topCandidate: RxNormCandidate.nullable(),
  runnerUp: RxNormCandidate.nullable().default(null),
  /** topCandidate.score - runnerUp.score. Big gap = confident resolution. */
  scoreMargin: z.number().nullable().default(null),
  /** All package NDCs mapping to the resolved concept. */
  candidateNdcs: z.array(z.string()).default([]),
  /** The one we'd actually dispense — present only if in Liberty inventory. */
  stockedNdc: z.string().nullable().default(null),
  resolvedAt: z.string(), // ISO timestamp
});
export type DrugResolution = z.infer<typeof DrugResolution>;

/* ═══════════════════════════════════════════════════════════════
   STAGE 3 — PRE-CHECKS
   Additive only. Liberty's own clinical/DUR engine stays authoritative
   at final verification — we surface concerns EARLIER, we don't replace it.
   ═══════════════════════════════════════════════════════════════ */

export const PreCheck = z.object({
  kind: z.enum([
    "allergy_conflict",
    "duplicate_therapy",
    "dose_plausibility",
    "refill_too_soon",
    "not_in_stock",
    "controlled_substance",
    "new_to_patient",
  ]),
  severity: z.enum(["info", "warn", "block"]),
  message: z.string(),
  /** Whatever the check looked at, for the audit trail. */
  evidence: z.record(z.string(), z.unknown()).default({}),
});
export type PreCheck = z.infer<typeof PreCheck>;

/* ═══════════════════════════════════════════════════════════════
   STAGE 4 — THE VERIFICATION RECORD
   What the pharmacist actually sees. What the audit log stores.
   ═══════════════════════════════════════════════════════════════ */

/** Enriched field: model output + our provenance and tiering. */
export function field<T extends z.ZodTypeAny>(inner: T) {
  return z.object({
    value: inner.nullable(),
    provenance: Provenance,
    modelConfidence: z.number().min(0).max(1).nullable().default(null),
    bbox: BoundingBox.nullable().default(null),
    tier: Tier,
    tierReasons: z.array(TierReason).default([]),
  });
}

export const IntakeSource = z.object({
  kind: z.enum(["escript", "fax", "scan", "manual"]),
  receivedAt: z.string(),
  /** Object-store key. NEVER a public URL — this is PHI. */
  imageKey: z.string().nullable().default(null),
  pageCount: z.number().int().positive().default(1),
  /** Raw NCPDP SCRIPT payload when kind === "escript". */
  rawScriptXml: z.string().nullable().default(null),
});
export type IntakeSource = z.infer<typeof IntakeSource>;

export const Lane = z.enum(["fast", "review"]);
export type Lane = z.infer<typeof Lane>;

export const RecordStatus = z.enum([
  "intake",
  "extracting",
  "resolving",
  "ready_for_verification",
  "verified",
  "rejected",
  "written_back",
  "error",
]);
export type RecordStatus = z.infer<typeof RecordStatus>;

export const VerificationRecord = z.object({
  id: z.string().uuid(),
  schemaVersion: z.literal("1.0.0"),
  status: RecordStatus,
  lane: Lane,
  source: IntakeSource,

  patient: z.object({
    name: field(z.string()),
    dob: field(z.string()),
    /** Set by the matcher once we've tied this to a Liberty profile. */
    libertyPatientId: field(z.string()),
  }),

  drug: z.object({
    nameAsWritten: field(z.string()),
    strength: field(z.string()),
    dosageForm: field(z.string()),
    quantity: field(z.number()),
    sig: field(z.string()),
    daysSupply: field(z.number()),
    refills: field(z.number()),
    daw: field(z.boolean()),
    resolution: DrugResolution.nullable().default(null),
  }),

  prescriber: z.object({
    name: field(z.string()),
    npi: field(z.string()),
    dea: field(z.string()),
  }),

  dateWritten: field(z.string()),
  preChecks: z.array(PreCheck).default([]),

  /** Worst tier across all fields. Drives lane assignment. */
  overallTier: Tier,

  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VerificationRecord = z.infer<typeof VerificationRecord>;

/* ═══════════════════════════════════════════════════════════════
   AUDIT — every pharmacist touch is logged, append-only
   Compliance trail AND the calibration signal for Ananth's evals.
   ═══════════════════════════════════════════════════════════════ */

export const CorrectionEvent = z.object({
  id: z.string().uuid(),
  recordId: z.string().uuid(),
  /** Dot path into VerificationRecord, e.g. "drug.strength". */
  fieldPath: z.string(),
  previousValue: z.unknown(),
  newValue: z.unknown(),
  previousTier: Tier,
  /** Who — a user id, never a free-text name. */
  correctedBy: z.string(),
  correctedAt: z.string(),
  reason: z.string().nullable().default(null),
});
export type CorrectionEvent = z.infer<typeof CorrectionEvent>;

export const VerificationEvent = z.object({
  id: z.string().uuid(),
  recordId: z.string().uuid(),
  action: z.enum(["accepted", "rejected", "escalated", "written_back"]),
  /** The licensed pharmacist who signed off. Required for accept. */
  pharmacistId: z.string(),
  laneAtDecision: Lane,
  overallTierAtDecision: Tier,
  /** Wall-clock seconds on the verification screen — our headline metric. */
  secondsOnScreen: z.number().nonnegative(),
  occurredAt: z.string(),
});
export type VerificationEvent = z.infer<typeof VerificationEvent>;

/* ═══════════════════════════════════════════════════════════════
   TIERING
   Placeholder thresholds — Matt owns the real numbers. Ananth wires
   them in from config, not hardcoded, so they can be tuned during pilot.
   ═══════════════════════════════════════════════════════════════ */

export const TierThresholds = z.object({
  minModelConfidenceGreen: z.number().min(0).max(1).default(0.9),
  minModelConfidenceAmber: z.number().min(0).max(1).default(0.6),
  /** Minimum RxNorm score gap between #1 and #2 to auto-resolve. */
  minScoreMarginGreen: z.number().default(4),
});
export type TierThresholds = z.infer<typeof TierThresholds>;

/**
 * Aggregate a record's field tiers into an overall tier and a lane.
 * Any red → review lane. Any amber → review lane. All green → fast lane.
 * A blocking pre-check forces red regardless of field tiers.
 */
export function rollUpTier(
  fieldTiers: Tier[],
  preChecks: PreCheck[]
): { overallTier: Tier; lane: Lane } {
  const blocked = preChecks.some((c) => c.severity === "block");
  if (blocked || fieldTiers.includes("red")) {
    return { overallTier: "red", lane: "review" };
  }
  const warned = preChecks.some((c) => c.severity === "warn");
  if (warned || fieldTiers.includes("amber")) {
    return { overallTier: "amber", lane: "review" };
  }
  return { overallTier: "green", lane: "fast" };
}
