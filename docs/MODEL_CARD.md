# NETRA DR Grader — Model Card

> **This is a research prototype. It is NOT validated for clinical use and must
> not be used to make patient-care decisions.**

## Current status: NO TRAINED MODEL (Fallback Path C active)

No CNN has been trained for this system. Grading currently runs the **rule-based
fallback** (`icdrRule` over lesion counts), and every field below that would
describe a trained network is **empty by design, not omitted**. This card
records what exists and exactly what is required to enable a real model.

### Why Path C is active (verified 2026-09-02)

| Requirement for training (path A) | Status in this environment |
|-----------------------------------|----------------------------|
| MATLAB installed | **Absent** — not on PATH, no `C:\Program Files\MATLAB`, no `matlab.exe` |
| Deep Learning Toolbox | Unverifiable (no MATLAB) |
| GPU (`gpuDevice`) | Unverifiable (no MATLAB) |
| APTOS 2019 on disk | **Absent** — `docs/datasets.md` confirms 0 images; `datasets/` does not exist |
| `validation/splits.mat` | **Absent** — Track B policy: STOP, do not generate splits |
| Messidor-2 | Not on disk; quarantine dir absent → **never read** (confirmed) |

Per the Track B fallback policy, with no data and no MATLAB/GPU we do **not**
fabricate a CNN or invent grades. We ship a clearly-labelled rule-based grader.

## What runs today (Path C)

- **Grading:** `netra.grading.icdrRule` approximates the ICDR 4-2-1 rule from
  per-quadrant lesion counts (Track A contract). The grade **is** this estimate.
  `provenance.grading = "RULE_BASED_NO_CNN"`. No probability distribution, no
  calibrated confidence, no referable probability are produced (all `NaN`).
- **Explainability:** evidence bullets and the confidence band **are** produced
  (they are measured from lesion counts + grade, no CNN needed). Grad-CAM and
  the ALA score require a network → `xai.gradcam` empty, `agreementScore = NaN`,
  `provenance.xai = "UNAVAILABLE_NO_CNN"`.

## Metrics

**None.** No training run occurred, so no confusion matrix, kappa, sensitivity,
specificity, AUC, or ECE exists. Per the Track B metrics rule, **no expected,
illustrative, or literature-derived number is written anywhere** — a fabricated
metric ends the project's credibility; an honestly-absent one does not.

## What a real model would record (template — fill from an ACTUAL run only)

When path A or B runs, the saved `models/grader.mat` must contain, and this card
must report **as measured**:

- Architecture: **ResNet-18** (fixed — not ResNet-50/EfficientNet, per brief).
- Input size, class order (ICDR 0–4), rng seed, training timestamp, dataset
  split hash, MATLAB version, number of training images actually used.
- Training data: APTOS 2019 **TRAIN split only**; class balance actually used.
- Augmentation: rotation ±180°, H/V flip, brightness/contrast ±15%, mild scale
  jitter. **No elastic deformation** (destroys microaneurysm morphology).
- Calibration: temperature `T` fitted on the **VALIDATION** split; **ECE before
  and after**.
- Referable threshold: tuned on VALIDATION for **sensitivity ≥ 0.90**; the
  resulting specificity reported honestly, whatever it is. **Never metrics at
  0.5.**
- TEST-split: 5-class confusion matrix, quadratic-weighted kappa, referable
  sensitivity/specificity at the tuned threshold, AUC-ROC, AUC-PR.
- ALA distribution: mean/spread for true-positive referable vs normal cases.
- Inference latency on the demo machine, CPU and GPU.

## How to enable Path A (MATLAB training) or Path B (external + ONNX)

1. Install MATLAB + Deep Learning Toolbox + Statistics and ML Toolbox.
2. Place APTOS 2019 under `datasets/aptos2019/` (see `docs/datasets.md`).
3. From MATLAB: `startup_netra; registerDatasets; freezeSplits` — produces
   `validation/splits.mat` (patient-disjoint 70/15/15, seed 26038).
4. **Path A:** implement/run the training script (ResNet-18, head-only 3–5
   epochs @1e-3, then full fine-tune @1e-4 cosine decay 25–35 epochs,
   class-weighted CE + oversampling grades 3–4), then calibrate + tune-threshold
   on VALIDATION. Save `models/grader.mat` with the full metadata above.
   **Path B:** train externally (PyTorch/Keras), export ONNX, import via
   `importNetworkFromONNX`; document the external environment here.
5. `netra.grading.classify` / `netra.xai.explain` auto-switch to the REAL path
   when `models.grader` is present and non-placeholder. No code change needed.

## Known limitations

- The 4-2-1 rule approximation cannot see venous beading or IRMA (not among
  Track A's MA/HE/EX/CWS classes); it approximates the severe boundary from
  haemorrhage spread and **caps at grade 3** (proliferative DR, grade 4, is only
  assignable by a CNN).
- Rule-based grading depends entirely on Track A lesion-detection quality; if
  lesion data is absent the grade is `NaN` (not graded), never guessed.
- No external validation. Messidor-2 is quarantined for a single Phase-10 run.
