# NETRA Quality Gate — Method (Phase 3)

The quality gate decides whether a fundus image is good enough to grade. It
extracts eight handcrafted features, classifies the image **Good / Borderline /
Ungradeable**, computes a 0–100 composite score, and produces a specific
failure reason and a plain-language recapture instruction.

**No deep learning.** The classifier is a shallow model (SVM-RBF or bagged
trees) on eight interpretable features. This is deliberate: it trains in
seconds, every feature maps to a displayable subscore, and a health worker or a
judge can read *why* an image was rejected off the screen.

> **Active path in this repository.** No MATLAB/APTOS were available when this
> phase was authored, so no classifier is trained and `models/quality_clf.mat`
> does not exist. The **rule-based path is active**: `netra.quality.assess`
> classifies with `netra.quality.classifyRuleBased` and sets
> `provenance.quality = "RULE_BASED_FALLBACK"`. The eight thresholds in
> `config/thresholds.json` **are** the quality model on this path. The UI labels
> it "Threshold-based assessment (trained classifier unavailable)" and never
> presents it as a trained model. See `docs/phase_notes.md` for the exact
> reason training did not run and how to run it.

---

## Feature order (fixed)

The trained model depends on this order; it is defined once in
`netra.quality.featureNames` and written into the saved model file.

| # | Name | Definition (inside FOV only) | Direction |
|---|------|------------------------------|-----------|
| 1 | `focusLaplacian` | variance of the Laplacian of the green channel, normalised by inside-FOV intensity variance | higher = sharper |
| 2 | `focusTenengrad` | mean squared Sobel gradient magnitude, normalised by intensity variance | higher = sharper |
| 3 | `illumUniformity` | `min(quadrantMean) / max(quadrantMean)` over the four image quadrants | higher = more even |
| 4 | `saturatedFraction` | fraction of inside-FOV green pixels `> 250` | lower = better |
| 5 | `darkFraction` | fraction of inside-FOV green pixels `< 15` | lower = better |
| 6 | `fovCompleteness` | mask area ÷ area of the equivalent-radius circle (from Phase 2 `fovMask`) | higher = more complete |
| 7 | `contrastStd` | std of the green channel inside FOV (0–1 scale) | higher = better |
| 8 | `localContrast` | mean local std (`stdfilt`, ~1%-of-frame neighbourhood) inside FOV | higher = better |

The **green channel** is used for intensity/focus/contrast because it carries
the highest retinal signal-to-noise (vessels and lesions are most visible in
green).

### Inside-FOV only

Every feature is computed over inside-FOV pixels only. Computing over the black
surround is the single most common bug here and silently wrecks the classifier.
Two safeguards, both tested (`tQualityFeatures/featuresIgnoreBorderNoise`):

- **Sampling** uses the boolean FOV mask, so border pixels never enter a mean,
  std, or fraction.
- For the **gradient features** (which need a neighbourhood), the outside-FOV
  region is first filled with the inside-FOV mean (a smooth constant), and the
  sampled response set is taken over an **eroded** mask, so no sampled pixel's
  neighbourhood ever straddled the FOV boundary. The test injects random noise
  into the border and asserts every feature is unchanged to 1e-6.

### Scale invariance

Features are invariant to image resolution (tested at 512 and 1024):

- **1, 2 (focus):** normalised by inside-FOV intensity variance → dimensionless,
  and invariant to global brightness/contrast scaling.
- **3 (uniformity), 4, 5 (fractions), 6 (completeness):** ratios and fractions
  are inherently scale-free.
- **7 (contrastStd):** std on the fixed 0–1 intensity scale.
- **8 (localContrast):** the `stdfilt` neighbourhood is a **fixed fraction of
  the frame** (≈1%, odd side length), so the same *spatial* scale is measured at
  every resolution.

Large frames are downsampled to a bounded working side (`2 × targetSize`, i.e.
1024 by default; `detail.computedAt` records the side used) before extraction,
so runtime is bounded and features are computed at a consistent scale.

---

## Composite score (0–100)

`netra.quality.scoreComposite` maps each feature to a 0–1 subscore measuring how
far it is on the *good* side of its threshold (higher-is-better features use
`value/threshold`; lower-is-better fractions use `1 − value/threshold`), then
takes the weighted mean using `quality.featureWeights` and scales to 0–100. It
is deterministic and fully guarded — no NaN/Inf can be produced. The gauge shows
this score; `gradeableScoreMin` / `borderlineScoreMin` colour-band it.

The **class** is decided by the classifier (or the rule-based path); the
**score** explains it to a human. They can disagree at the margins by design.

---

## Rule-based classifier and hard overrides

`netra.quality.classifyRuleBased` is both the fallback classifier and the source
of the **hard overrides** that fire on *every* path (including the trained one).
Order matters — first hard failure wins:

1. `fovCompleteness < hardRejectFovCompleteness` → **Ungradeable**
2. `darkFraction > darkFractionMax` → **Ungradeable**
3. `saturatedFraction > saturatedFractionMax` → **Ungradeable**
4. both focus metrics below their mins → **Ungradeable**
5. otherwise band the composite score: `≥ gradeableScoreMin` → Good;
   `≥ borderlineScoreMin` → Borderline; else Ungradeable.

`assess` additionally forces Ungradeable when the FOV was empty or the feature
vector had to be NaN-substituted.

---

## Severity-to-label mapping (a modelling assumption, not ground truth)

Training data is synthesised from clean images with Phase 2's
`simulateFieldCapture`. Labels are assigned from the applied degradation
severity — this is a **modelling assumption**, not clinical ground truth. It is
stated here explicitly because a judge may ask.

`training/make_degradations.m` (`labelFor`) uses:

| Severity band | Label |
|---------------|-------|
| 0.2 – ~0.45 | **Borderline** (all types) |
| ~0.45 – ~0.75 | **Ungradeable** for `overexposed`, `underexposed`, `partialFOV`; **Borderline** for `blur`, `haze`, `random` |
| ~0.75 – 1.0 | **Ungradeable** (all types) |
| 0 (undegraded) | **Good** |

Rationale for the mid-band split: a blown-out, blacked-out, or clipped field is
less recoverable than mild softness or haze at the same severity, so exposure
and FOV failures are treated as harder. This is an engineering judgement; it is
not validated against expert labels and should be revisited if real
quality-labelled data becomes available.

---

## Validation and its limits

`training/eval_quality.m` evaluates on a **held-out synthetic set built from the
VAL split** (source-disjoint from training's TRAIN split) and saves *only
measured* numbers to `validation/results_quality.mat`: 3-class confusion matrix,
per-class precision/recall/F1, overall accuracy, **false rejection rate on clean
images** (the throughput-critical metric — how often a fine image is rejected),
feature importance (if the model exposes it), and the exact trainset
composition.

### Naturally-poor set — selection bias

`validation/natural_poor_quality.txt` lists ~100 naturally poor-quality APTOS
images. They have **no official quality labels**, so they are used as a
**one-class check**: what fraction does the classifier reject? This set is
**investigator-selected and therefore subject to selection bias** — the honest
figure is a rejection rate, *not* a false-positive rate against invented labels.
The caveat is restated in `results_quality.mat` (`naturalCaveat`).

---

## Thresholds (config/thresholds.json → `quality`)

| Key | Meaning |
|-----|---------|
| `featureWeights` | 1×8, composite-score weights (feature order above) |
| `focusLaplacianMin`, `focusTenengradMin` | focus gates |
| `illumUniformityMin` | min quadrant-mean ratio |
| `saturatedFractionMax`, `darkFractionMax` | exposure gates |
| `fovCompletenessMin` | FOV completeness gate |
| `contrastStdMin`, `localContrastMin` | contrast gates |
| `hardRejectFovCompleteness` | hard-override FOV floor |
| `gradeableScoreMin`, `borderlineScoreMin` | score bands |
| `useClassifier` | `false` forces the rule-based path |

**These `*Min`/`*Max` values are engineering placeholders** on the 0–1
green-channel scale, not trained thresholds. Once APTOS is on disk, train the
classifier and tune them against `validation/results_quality.mat` (specifically
the false rejection rate). Any placeholder changed from its Phase 0 value, and
the evidence for the change, is recorded in `docs/phase_notes.md`.
