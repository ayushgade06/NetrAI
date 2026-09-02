# NETRA Track B — DR Grading, Calibration, Explainability (method)

This document describes the *intended* deep-learning method and the *actual*
state of the system. In this environment the actual state is **Fallback Path C
(rule-based, no CNN)** — see `docs/MODEL_CARD.md` for why. Nothing here reports
a measured number; there are none.

## Architectural principle

Exactly **one** deep model on the critical path (a fine-tuned ResNet-18 grader).
Everything else — quality, structures, lesions, the ICDR rule, calibration,
fusion, ALA, evidence — is classical or shallow. No second network, no ensemble,
no test-time augmentation, no ordinal head.

## Grading

### Rule-based estimate (`+netra/+grading/icdrRule.m`) — ACTIVE

An independent 0–4 ICDR estimate approximating the clinical **4-2-1 rule** from
Track A's per-quadrant lesion counts:

- **0** no MA/HE/EX/CWS anywhere.
- **1** microaneurysms only.
- **2** haemorrhages/exudates/CWS present, or many microaneurysms, below severe.
- **3** any 4-2-1 proxy met: HE or MA in all 4 quadrants, or prominent HE spread
  (≥3 quadrants) standing in for the IRMA/venous-beading criteria Track A cannot
  detect.
- **4** proliferative DR — **not inferable** from these lesion classes; the rule
  caps at 3. Only the CNN can assign 4.

On Path C this estimate **is** the grade. On Path A/B it is the independent
cross-check; a rule-vs-CNN gap ≥ `grading.disagreementLevels` raises
`grade.disagreement`.

### CNN grader (`classify.m`, path A/B) — INACTIVE (no trained net)

ResNet-18, transfer learning: head-only 3–5 epochs @1e-3, then full fine-tune
@1e-4 with cosine decay for 25–35 epochs; class-weighted cross-entropy with
oversampling of grades 3–4. Augmentation: rotation ±180°, H/V flip,
brightness/contrast ±15%, mild scale jitter — **no elastic deformation** (it
destroys microaneurysm morphology). Trained on APTOS **TRAIN only**.

### Calibration (`applyTemperature.m` + `training/calibrate.m`)

Single scalar temperature `T` fitted on the **VALIDATION** split by minimising
NLL; report ECE before and after. `applyTemperature` is implemented and unit
tested (`T=1` identity; `T>1` raises entropy) so it is ready for the CNN path.

### Referable threshold (`training/tune_threshold.m`)

Tuned on VALIDATION for **sensitivity ≥ 0.90**; the resulting specificity is
reported honestly. **Never** report metrics at 0.5. `classify` and routing read
`grading.referableThreshold` from config, never a literal 0.5.

### Fusion (`fuseEvidence.m`, `training/train_fusion.m`) — DEFERRED

Logistic regression over `[P0..P4, log(1+MA), log(1+HE), EX area fraction,
quadrantsWithLesions, nearMaculaFlag, qualityScore] → referable probability`.
Deferred: it needs both a trained CNN (for `P0..P4`) and Track A lesion features
at training time; neither is available. `grading.useFusion=false`. When enabled,
`classify` uses it for `referableProb`; otherwise `sum(P2..P4)`.

## Explainability

### Grad-CAM (`gradcamOverlay.m`, path A/B) — INACTIVE (no net)

Native `gradCAM` on the final conv block for the predicted class, upsampled and
colour-mapped. Not hand-rolled. On Path C there is no network → no heatmap.

### Attention-Lesion Agreement (`agreementScore.m`) — IMPLEMENTED + TESTED

The project's headline differentiator. Binarise Grad-CAM at
`xai.gradcamPercentile`, dilate the union lesion mask by `xai.lesionDilationPx`,
and compute `sum(gradcamTop & lesionMask) / sum(gradcamTop)` — the fraction of
peak attention landing on detected lesions.

- All-false / absent lesion mask → **NaN** ("not applicable", *not* 0). This is
  clinically distinct from a low score and is surfaced as such in the UI and
  `confidenceBand`.
- Empty / degenerate Grad-CAM → NaN.

Fully unit-tested against synthetic attention maps + masks (`tests/tXai.m`,
`tests/fixtures/syntheticLesions.m`), so the ALA maths is verified even without
a trained network.

### Evidence bullets (`evidenceBullets.m`) — IMPLEMENTED + TESTED

Templated clinical evidence from **measured counts + grade only**. Hard
invariant: **no bullet may claim a lesion type whose count is zero**, and
quadrant counts quoted must match `perQuadrant` exactly (tested). Phrasing is
never diagnostic; the closing line reads "Findings consistent with ICDR Level N",
not "patient has …".

### Confidence band (`confidenceBand.m`) — IMPLEMENTED + TESTED

Maps calibrated confidence → High/Moderate/Low against
`grading.confidenceHigh/Low`, then **demotes only**: poor quality caps at
Moderate, finite low ALA caps at Low. NaN ALA never demotes. NaN confidence
(rule-based path) → Low.

## Data governance

- Train on APTOS TRAIN; calibrate/tune on VALIDATION; report on TEST.
- Messidor-2 stays quarantined (Phase-10 one-shot). Every dataset path passes
  `netra.io.assertNotQuarantined`. If `splits.mat` is missing, STOP.
- **Every saved number must come from an executed run on real data.** No
  expected/illustrative/literature number goes into any results file, doc,
  comment, or the UI.
