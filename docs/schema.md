# NETRA caseRecord Schema (Phase 0)

The `caseRecord` (`cr`) is a scalar struct flowing through the pipeline. It is
created by `netra.newCaseRecord` and mutated by each stage. **A stage may add
fields; it must never delete or rename a field it did not create.** Every field
below is created up front by the factory so the shape is stable from the start.

Legend — **Owner**: the stage that populates the field with real data in later
phases. In Phase 0 every non-routing owner writes fixed MOCK placeholders.
Units are noted where meaningful; `px` = pixels, `s` = seconds.

---

## meta — patient / capture metadata
Owner: `newCaseRecord` (from caller `metaStruct`)

| Field | Type | Units | Default | Notes |
|-------|------|-------|---------|-------|
| uid | string | — | `NETRA_<ts>_<hex>` | Unique case id |
| patientID | string | — | `""` | From metaStruct |
| phcID | string | — | `""` | PHC id (see phc_registry.json) |
| age | double | years | `NaN` | From metaStruct |
| dmYears | double | years | `NaN` | Diabetes duration |
| eye | string | — | `"OD"` | `"OD"` (right) or `"OS"` (left) |
| timestamp | datetime | — | now | Record creation time |
| imagePath | string | — | input | Path to fundus image |
| imageHash | string | — | `""` | Filled when image is hashed |

## img — image buffers
Owner: `preproc` (enhanced/modelInput/displayRGB), `newCaseRecord` (raw/fovMask)

| Field | Type | Shape | Notes |
|-------|------|-------|-------|
| raw | uint8 | HxWx3 | Original fundus (empty in Phase 0) |
| fovMask | logical | HxW | Field-of-view mask |
| enhanced | uint8 | HxWx3 | After enhancement |
| modelInput | single | HxWx3 | Normalised CNN input |
| displayRGB | uint8 | HxWx3 | For UI display |

## quality — capture quality assessment
Owner: `netra.quality.assess` (Phase 3)

| Field | Type | Units | Notes |
|-------|------|-------|-------|
| score | double | 0–100 | Overall quality |
| class | string | — | `"Good"`/`"Borderline"`/`"Ungradeable"` |
| focus | double | 0–1 | Focus metric |
| illum | double | 0–1 | Illumination uniformity |
| fovCompleteness | double | 0–1 | Fraction of FOV present |
| contrast | double | 0–1 | Contrast metric |
| quadrantMeans | double | — | 1×4 mean intensity per quadrant |
| failReason | string | — | Why ungradeable (if any) |
| recaptureAdvice | string | — | Guidance for re-capture |

## preproc — enhancement record
Owner: `netra.preproc.enhance` (Phase 4)

| Field | Type | Notes |
|-------|------|-------|
| appliedSteps | string array | Ordered list of applied steps |
| claheClip | double | CLAHE clip limit used |
| illumApplied | logical | Illumination correction applied |
| denoiseApplied | logical | Denoising applied |

## structures — retinal anatomy
Owner: `netra.structures.segment` (Phase 5)

| Field | Type | Shape/Units | Notes |
|-------|------|-------------|-------|
| vesselMask | logical | HxW | Vessel segmentation |
| odCenter | double | 1×2 px | Optic disc centre (x,y) |
| odRadius | double | px | Optic disc radius |
| foveaCenter | double | 1×2 px | Fovea centre (x,y) |
| maculaZone | logical | HxW | Macula region mask |
| quadrantMap | uint8 | HxW | Values 0–4 (0=bg, 1–4 quadrants) |
| vesselDensity | double | 0–1 | Vessel area fraction |
| tortuosity | double | ≥1 | Vessel tortuosity index |

## lesions — lesion detections
Owner: `netra.lesions.detect` (Phase 6)

`MA`, `HE`, `EX`, `CWS` (microaneurysms, haemorrhages, hard exudates, cotton
wool spots) each hold a lesion-set struct:

| Field | Type | Shape/Units | Notes |
|-------|------|-------------|-------|
| count | double | — | Number of lesions |
| totalArea | double | px² | Summed area |
| centroids | double | N×2 px | Lesion centroids |
| areas | double | N×1 px² | Per-lesion area |
| perQuadrant | double | 1×4 | Count/area per quadrant |
| nearMacula | double | — | Count near macula (drives routing) |

## grade — DR severity
Owner: `netra.grading.classify` (Phase 7)

| Field | Type | Units | Notes |
|-------|------|-------|-------|
| icdr | double | 0–4 | ICDR grade |
| probs | double | 1×5 | Class probabilities (sum 1) |
| referableProb | double | 0–1 | P(referable, grade≥2) |
| confidence | double | 0–1 | Model confidence |
| ruleEstimate | double | 0–4 | Rule-based grade estimate |
| disagreement | logical | — | Rule vs CNN disagree |
| label | string | — | Human-readable grade |

## xai — explainability
Owner: `netra.xai.explain` (Phase 8)

| Field | Type | Shape/Units | Notes |
|-------|------|-------------|-------|
| gradcam | single | HxW, 0–1 | Grad-CAM heatmap |
| agreementScore | double | 0–1 | Attention–Lesion Agreement (ALA) |
| evidenceBullets | string array | — | Evidence statements |
| confidenceBand | string | — | `"High"`/`"Moderate"`/`"Low"` |
| attentionSummary | string | — | Prose summary |

## routing — clinical routing (REAL in Phase 0)
Owner: `netra.routing.decide` (Phase 0, real)

| Field | Type | Notes |
|-------|------|-------|
| decision | string | `"RECAPTURE"`/`"AUTO_CLEARED"`/`"REVIEW_QUEUE"` |
| urgency | string | `"None"`/`"Routine"`/`"Priority"`/`"Urgent"` |
| reason | string | Name of the matched rule |
| flags | string array | e.g. `"Uncertain"`, `"LowAgreement"`, `"Disagreement"` |

**Routing rules** (config/routing_rules.json), evaluated in order, first match wins:

1. `quality.class == Ungradeable` → RECAPTURE / None
2. `grade ≥ 4` → REVIEW_QUEUE / Urgent
3. `grade ≥ 2 AND lesionNearMacula` → REVIEW_QUEUE / Urgent
4. `grade == 3` → REVIEW_QUEUE / Priority
5. `grade == 2` → REVIEW_QUEUE / Routine
6. `confidence < grading.confidenceMin` → REVIEW_QUEUE / Routine (flag `Uncertain`)
7. `agreementScore < xai.alaLowThreshold` → REVIEW_QUEUE / Routine (flag `LowAgreement`)
8. `grade.disagreement` → REVIEW_QUEUE / Routine (flag `Disagreement`)
9. default (grade 0–1, confident) → AUTO_CLEARED / None

## report — generated report
Owner: `netra.report.generate` (Phase 9)

| Field | Type | Notes |
|-------|------|-------|
| pdfPath | string | Path to the generated PDF (Phase 0: computed, not written) |

## review — clinician review outcome
Owner: clinician workflow (later phase)

| Field | Type | Units | Notes |
|-------|------|-------|-------|
| action | string | — | Reviewer action |
| finalGrade | double | 0–4 | Confirmed grade |
| reviewerID | string | — | Reviewer id |
| seconds | double | s | Review duration |
| note | string | — | Free text |
| timestamp | datetime | — | Review time (`NaT` until reviewed) |

## timing — per-stage wall-clock
Owner: `netra.runPipeline` (writes every field)

One `double` (seconds) field per stage name from `netra.util.stageNames`
(`quality preproc structures lesions grading xai routing report store`), plus
`total`. A failed stage records `0`.

## provenance — per-stage source flag
Owner: each stage sets its own; `runPipeline` sets `"FAILED"` on error

One `string` field per stage name. Value is `"REAL"`, `"MOCK"`, or `"FAILED"`.
In Phase 0 every stage is `"MOCK"` except `routing`, which is `"REAL"`.

## version — provenance metadata
Owner: `newCaseRecord` (+ later stages set hashes)

| Field | Type | Notes |
|-------|------|-------|
| pipelineVersion | string | e.g. `"0.1.0-phase0"` |
| modelHash | string | Model artefact hash |
| configHash | string | Config hash |
| createdBy | string | Creator function |

## errors — stage failure log
Owner: `netra.runPipeline`

Struct array; one element per failed stage with fields `stage`, `identifier`,
`message`. Empty (`0×0`) on a clean run.
