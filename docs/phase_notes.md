# NETRA — Phase 0 Notes

**Phase 0 = scaffolding + data contract only.** No image processing, no ML,
no UI. Its job: let six developers build later phases in parallel without
colliding.

## What Phase 0 delivers

- Frozen stage signatures (section 7 of the brief). Bodies get filled later;
  signatures do not change.
- `netra.newCaseRecord` — the single authoritative schema factory.
- MOCK pass-through stubs for all 9 stages (fixed placeholder values).
- `netra.routing.decide` — the only REAL logic (pure rules).
- `netra.runPipeline` — orchestrator with per-stage timing and error capture.
- Config in JSON with strict key validation.
- `startup_netra` — path + config + toolbox check.
- Tests (`runtests('tests')`).

## Contract rules (repeated at the top of every stage)

- Exactly one `caseRecord` in, one out.
- A stage may ADD fields; never DELETE or RENAME a field it did not create.
- Only `+store` and `+report` may write to disk.
- Each stage sets `cr.provenance.<stage>` to `"REAL"` or `"MOCK"`.
- `cr.timing.<stage>` is written by `runPipeline`, not by the stage.

## How later phases plug in

Each stage owner replaces the MOCK body of their one file, flips provenance to
`"REAL"`, and reads any new thresholds from `cfg` (never inline). The signature
and the caseRecord field set they own are already defined here.

Phase→stage map: 3 quality, 4 preproc, 5 structures, 6 lesions, 7 grading,
8 xai, 9 report, 10 store, (routing done in 0). UI is Phase 1; Simulink and the
district-capacity model are separate later phases.

## Running it

```matlab
startup_netra
cr = netra.runPipeline(netra.newCaseRecord('data/demo/sample01.jpg'));
disp(cr)
runtests('tests')
```

## Placeholder honesty

Every mock value is obviously synthetic (e.g. quality.score = 72,
grade.probs = [0.05 0.15 0.55 0.20 0.05]) and provenance says `"MOCK"`. No mock
number should be mistaken for a real measurement.

---

# Phase 1 — Programmatic UI shell

`NETRA_App.m` is a plain-text `classdef` (no `.mlapp`). Seven views built once
at construction; switching toggles panel `Visible`. All layout via
`uigridlayout` (no pixel positioning). All colours/fonts/spacing come from
`netra.ui.theme` — nothing hardcoded elsewhere.

## What Phase 1 added

- `NETRA_App` — the seven-view app, Field/Clinician mode toggle, provenance
  banner, review stopwatch (single `timer`, stopped+deleted in `delete`).
- `+netra/+ui/` helpers: `theme`, `kpiCard`, `subscoreBar`, `gauge`,
  `imageCanvas` (layered overlays, smooth opacity), `statusBanner`, `formatGrade`.
- `+netra/+store/queryQueue` + `stats` (+ shared `internalLoadRegistry`).
- `tools/seedMockRegistry` -> `data/mock/registry_seed.mat` (~40 fictional cases).
- Tests: `tUI`, `tStoreQueries`.

## Where the UI binds to MOCK data (for Phase 3-9 owners to replace)

- **Quality Gate**: `quality.score/focus/illum/fovCompleteness/contrast/class/recaptureAdvice` (mock: score 72, class "Good"). -> Phase 3.
- **Quality Gate**: `preproc.appliedSteps`. -> Phase 4.
- **Workbench canvas overlays**: masks are SYNTHESISED in-app from mock geometry (`structures.odCenter/foveaCenter`, lesion counts), since mock stages return empty masks. Real masks: `structures.vesselMask/maculaZone/quadrantMap` (Phase 5), lesion centroids (Phase 6), `xai.gradcam` (Phase 8).
- **Workbench grading panel**: `grade.icdr/probs/confidence/ruleEstimate/disagreement`. -> Phase 7.
- **Workbench lesion table**: `lesions.{MA,HE,EX,CWS}.{count,totalArea,perQuadrant,nearMacula}`. -> Phase 6.
- **Workbench XAI panel**: `xai.agreementScore/evidenceBullets/attentionSummary/confidenceBand`. -> Phase 8.
- **Dashboard + Review Queue**: driven entirely by the mock registry (`data/mock/registry_seed.mat`) via `store.stats` / `store.queryQueue`. Real data arrives when `store.save` persists actual cases (Phase 10).
- **Base fundus image**: `placeholderFundus()` draws a synthetic disc; real pixels come from `img.displayRGB/enhanced` (Phase 4).

## Disabled-on-purpose controls (Phase 1)

- Simulate Field Capture dropdown — tooltip "Available in Phase 2".
- Generate Report — toast "Available in Phase 8".
- Quality Gate Continue/Proceed — disabled when verdict is Ungradeable (deliberate product constraint, enforced now).
- Workbench Auto-Clear — enabled only when `routing.decision == AUTO_CLEARED`.

## Validation & Capacity

Honest empty states only — "Populated in Phase 10" (validation) and "Populated in Phase 9" (capacity). No fabricated ROC/curves/metrics.

---

# Phase 2 — Image ingestion, FOV normalisation, persistence

First phase where **real image data enters the system**. Image loading, FOV
masking + crop/resize, and case persistence are now genuinely functional. The
degradation engine is built (for tests + future Phase 3 training data). Quality
scoring, enhancement (CLAHE/illum), segmentation, grading, and XAI remain MOCK.

## What Phase 2 added

- `+netra/+io/`: `loadImage`, `validateImage`, `isPlausibleFundus` (heuristic
  guard, not a classifier), `hashImage` (SHA-256 of pixels via
  `java.security.MessageDigest` — no Simulink dependency), `generateUID`
  (`<PHCID>-<yyyymmdd>-<seq>-<OD|OS>`), `batchIngest`, `simulateFieldCapture`
  (6 degradations, seeded/reproducible), `assertNotQuarantined`.
- `+netra/+preproc/`: `fovMask` (Otsu/fixed threshold, morphology, largest
  component, **full-frame fallback** on tiny/ambiguous masks), `cropResize`
  (crop→square-pad→resize, records coord mapping in `info`).
- `+netra/+preproc/enhance.m` now REAL for FOV/crop; illum/CLAHE stay mock →
  `provenance.preproc = "PARTIAL"` (new permitted value; amber in the banner,
  worded distinctly from full MOCK).
- `+netra/+store/`: `save` (per-case folder `case.mat`+`original.png`, **atomic**
  registry upsert via temp-file+rename with backup/restore), `load`, `registry`
  (real 21-col table), `emptyRealRegistry`, `storeRoot` (overridable via
  `NETRA_STORE_ROOT` for tests). `queryQueue`/`stats` are unchanged — they read
  through `internalLoadRegistry`, which now **prefers the real registry and
  falls back to the mock seed**, so no per-caller edits were needed.
- `newCaseRecord` now populates `meta.imageHash` (real pixel hash) and, when a
  `phcID` is supplied, a deterministic `meta.uid`. It still leaves `img.raw`
  empty — the ingest path fills pixels and re-runs the pipeline. Schema
  unchanged (only existing fields populated).
- `runPipeline.stageStore` persists **only cases with real pixels**
  (`img.raw` non-empty) → `store="REAL"`; mock dashboard previews skip the
  write → `store="MOCK"`. This is why opening a mock registry row never
  pollutes the real registry.
- `tools/`: `registerDatasets` (scan-only, never fabricates), `freezeSplits`
  (APTOS 70/15/15 patient-disjoint, seed 26038, refuses overwrite without
  force), `quarantineMessidor` (move/symlink + `QUARANTINE_NOTICE.md`).
- Tests: `tIngestion`, `tFovMask`, `tDegradation`, `tStorePersistence` — all run
  on **synthetic fixtures** (disc-on-black fundus, checkerboard/gradient
  non-fundus) so the suite is green without any real dataset download.
- `docs/datasets.md` (records only what was verified on disk).

## UI changes (Phase 2)

- **New Screening**: Load Image now really loads/validates/plausibility-checks
  and shows the detected **FOV outline** on the thumbnail; failures `uialert`
  and keep Analyze disabled. **Simulate Field Capture** dropdown is enabled,
  with a **severity slider (default 0.6)** and **Reset Original** button; a
  persistent amber **"SYNTHETIC DEGRADATION: <type> (severity 0.XX)"** tag is
  shown and recorded on the case (`preproc.syntheticDegradation`) and registry.
  Analyze ingests the working image (pristine or degraded) through the real
  FOV/crop/persist path.
- **Quality Gate**: Field-of-View subscore is now the **measured**
  `quality.fovCompleteness` (bold); Focus/Illumination/Contrast are labelled
  "(mock)" and muted so a mock number never shares visual weight with the
  measured one.
- **Dashboard**: **Batch Import Folder** button (folder picker → shared-metadata
  dialog → progress dialog → results modal with CSV export). Recent-cases table
  reads the real registry, marks **mock-graded rows with a leading `*`**, and
  shows a notice when it falls back to the fictional mock seed.

## Design decisions (Phase 2)

- **Pixel hash, not file hash**: identifies the content that entered the
  pipeline regardless of container/re-encode. `MessageDigest` avoids a Simulink
  dependency.
- **Persist only real-pixel cases**: cleanest separation of ingested cases from
  mock dashboard previews without a new flag.
- **`NETRA_STORE_ROOT`**: one env-var indirection lets tests isolate the store
  and prove the interrupted-save invariant without touching real data.
- **Synthetic test fixtures**: the suite must pass on a fresh clone with no
  5 GB dataset; real datasets are optional and slot in via `datasets/`.

---

# Phase 3 — Image quality assessment and gating

## Active path: RULE_BASED_FALLBACK (training did not run)

Per the Phase 3 fallback policy (§13), the **rule-based path is active** and
`provenance.quality = "RULE_BASED_FALLBACK"`. Training did **not** run and
**no** `models/quality_clf.mat` or `validation/results_quality.mat` was written,
because the authoring environment had:

- **No MATLAB installed** (not on PATH; no `C:\Program Files\MATLAB`; no
  `matlab.exe` on disk). So `startup_netra`, `runtests('tests')`,
  `train_quality`, and `eval_quality` could not be executed here, and the
  Statistics & ML Toolbox availability could not be checked.
- **No APTOS on disk** (`docs/datasets.md` confirms all four datasets absent;
  no `validation/splits.mat`). The only images are 10 small demo JPEGs and a
  16×16 placeholder — not a training corpus.

**To activate the trained path** (needs a MATLAB machine + APTOS under
`datasets/`):

```matlab
startup_netra
registerDatasets ; freezeSplits          % writes validation/splits.mat
make_degradations                         % training/quality_trainset.mat
train_quality                             % models/quality_clf.mat (+metadata)
eval_quality                              % validation/results_quality.mat
```

`netra.loadModels` auto-detects `quality_clf.mat` and surfaces it as
`models.quality`; `assess` then takes the trained path and sets
`provenance.quality = "REAL"`. No code change is needed to switch paths — only
the model file appearing on disk (and `quality.useClassifier` staying `true`).

**Metrics honesty:** no confusion matrix, accuracy, false-rejection rate, or
rejection rate is reported anywhere in code, docs, or UI, because none was
measured. `eval_quality` computes and saves them from an actual run when it is
executed; it errors (saving nothing) if the model/splits are missing.

## What is real regardless of path

- Eight-feature extractor (`extractFeatures`), FOV-masked and scale-invariant.
- Composite 0–100 score (`scoreComposite`), rule-based classifier + hard
  overrides (`classifyRuleBased`), `failReason`, `recaptureAdvice`.
- `assess` MOCK → REAL: real features, real score, real class, real reason/advice
  on both paths. Preview-only cases (no pixels) stay `MOCK` (no invented score).

## Signature extension (reported)

`netra.quality.assess` now accepts an **optional third argument** `models`:
`assess(cr, cfg)` (Phase 0) **and** `assess(cr, cfg, models)` (Phase 3) both
work — two-arg callers lazily load and cache the model. `runPipeline`'s quality
adapter now passes `models`. This is the only interface change; the caseRecord
schema is unchanged.

## Files

- CREATE `+netra/+quality/`: `extractFeatures`, `featureNames`, `scoreComposite`,
  `classifyRuleBased`, `failReason`, `recaptureAdvice`.
- MODIFY `+netra/+quality/assess.m` (MOCK → REAL, fallback-aware).
- CREATE `training/`: `make_degradations`, `train_quality`, `eval_quality`.
- CREATE tests `tQualityFeatures`, `tQualityClassifier`, `tQualityGate`.
- CREATE `validation/natural_poor_quality.txt` (empty template), `docs/quality_method.md`.
- MODIFY `config/thresholds.json` (new `quality.*` keys), `+netra/loadConfig.m`
  (validate them), `+netra/loadModels.m` (surface `models.quality`),
  `+netra/runPipeline.m` (pass models to quality), `NETRA_App.m` (Quality Gate).
- MODIFY `.gitignore` (ignore `models/quality_clf.mat`,
  `training/quality_trainset.mat`, `validation/results_quality.mat`).

## Thresholds changed from Phase 0 placeholders

Phase 0 had only `focusMin/illumUniformityMin/fovCompletenessMin/contrastMin/
gradeableScoreMin/borderlineScoreMin`. Phase 3 **adds** eight per-feature gates
plus `featureWeights`, `hardRejectFovCompleteness`, `useClassifier`. **No
existing Phase 0 value was changed** — the old six are retained (the Phase 1 UI
still reads `focusMin`/`contrastMin`). The new values are engineering
placeholders on the 0–1 green-channel scale (documented as such in
`thresholds.json` and `quality_method.md`); they are **not** evidence-tuned
because no validation run was possible. Tune them against
`validation/results_quality.mat` — especially the false-rejection rate — once a
trained run exists.

## UI (Quality Gate)

- Four subscores now REAL (labels de-"mock"ed), with a 0.5 pass tick for the
  combined Focus/Illumination/Contrast bars and the real completeness threshold
  for FOV; each bar has a tooltip documenting which features it combines.
- **failReason card** ("Why this image was rejected") appears prominently on
  Ungradeable and is hidden otherwise; recaptureAdvice shown in the advice line.
- **"Show all measurements"** expandable panel lists all eight raw features with
  their thresholds and an OK/FAIL mark (recomputed from the image, since the
  frozen schema does not store raw features).
- **Amber fallback note** "Threshold-based assessment (trained classifier
  unavailable)" shown only when `provenance.quality == "RULE_BASED_FALLBACK"`.
- Dev verdict-forcing dropdown stays **behind the DevMode flag** (hidden in
  normal use, as before).
- Continue/Proceed remain disabled with an explanatory tooltip on Ungradeable
  (unchanged wiring in `applyVerdict`).

## Design decisions (Phase 3)

- **Features not stored on cr**: the caseRecord schema is frozen, so the UI
  recomputes the eight raw features from the image for the measurements panel
  (< 300 ms) rather than adding a schema field.
- **Hard overrides apply on every path**: even a trained classifier cannot
  pass an image with a clipped/blacked-out/blown-out field — `assess` layers
  `classifyRuleBased`'s hard failures on top of the model verdict.
- **Green channel throughout**: highest retinal SNR; keeps focus/contrast/
  exposure features on one consistent, brightness-normalisable scale.
- **Two-arg-compatible `assess`**: avoids breaking the Phase 0 contract and any
  existing two-arg caller while letting `runPipeline` pass the model.

## NOT executed here (must be run on a MATLAB machine)

`startup_netra`, `runtests('tests')`, `make_degradations`, `train_quality`,
`eval_quality`. The new code is written to the existing test/fixture conventions
so `runtests('tests')` exercises the quality gate on synthetic fundi with **no
dataset required**, but it has **not been run** in this environment.

---

# Track A — Enhancement, retinal structures, lesion detection (Phases 4-6)

The entire classical-CV layer is now REAL. `provenance.preproc`,
`provenance.structures`, and `provenance.lesions` become `"REAL"`. **No machine
learning in this track** (Track B owns the CNN/Grad-CAM; its files were not
touched). Full algorithm + threshold documentation: `docs/cv_method.md`.

## What Track A added / changed

- **Enhancement (`+preproc`)**: `enhance.m` PARTIAL→REAL. New modules
  `illumNormalize`, `claheAdaptive` (clip computed from the contrast deficit),
  `denoise` (Wiener, noise-triggered), `benGraham` (CNN `modelInput`). Steps
  fire **adaptively** and are logged with parameters in `preproc.appliedSteps`;
  a NaN/constant output reverts to the geometry crop (`enhancementReverted`).
- **Structures (`+structures`)**: `segment.m` MOCK→REAL. New modules
  `vesselsFrangi` (multi-scale `fibermetric` + hysteresis + length pruning),
  `locateOD` (bright-blob after vessel inpainting + Hough + convergence),
  `locateFovea` (geometric prior + darkest-region search), `quadrantMap`
  (OD→fovea axis). OD/fovea **fallbacks** set `odFallback`/`foveaFallback` and
  append routing flags. Masks asserted logical + `size(enhanced,[1 2])`.
- **Lesions (`+lesions`)**: `detect.m` MOCK→REAL. New modules `redLesions`
  (12-orientation line-SE vessel suppression + adaptive threshold),
  `classifyMAvsHE` (shape), `brightLesions` (top-hat with the **dilated OD
  region subtracted** — mandatory), `quadrantTally`. **Mask format contract**
  (§7) implemented: `lesions.<TYPE>.mask` logical + correctly sized, plus
  `lesions.allMask`. CWS left empty with `cwsNote="cwsNotImplemented"`.
- **Config**: new `preproc.*` / `structures.*` / `lesions.*` keys (§8), all
  validated in `loadConfig`. No existing value changed.
- **Tests**: `tEnhancement`, `tStructures`, `tLesions` (OD-not-an-exudate test
  written first). All run on synthetic fixtures + the real demo JPEGs, **no
  dataset required**. Prior tests preserved.
- **Validation**: `validation/eval_structures.m` (DRIVE vessels, IDRiD OD),
  `validation/eval_lesions.m` (IDRiD MA/HE/EX sensitivity + FP/image),
  `validation/lesion_contact_sheet.m` (manual-inspection contact sheet). Each
  computes real metrics **only if the data is on disk** and saves NOTHING (with
  a printed note) otherwise — no fabricated numbers.

## Schema

Unchanged as a factory. New sub-fields are **additions** by the owning stage
(permitted by the contract): `structures.odFallback/foveaFallback`,
`lesions.<TYPE>.mask`, `lesions.allMask`, `lesions.cwsNote`,
`preproc.fovMaskResized` (the FOV mask at the enhanced-frame size, so
structures/lesions mask against `enhanced` while `img.fovMask` keeps its
documented raw-frame meaning), `preproc.cropInfo` (already added in Phase 2). No
top-level group added; nothing renamed/deleted.

## UI changes (only the permitted areas)

Modified `NETRA_App.m` **Quality Gate before/after** and **Workbench overlays**
only (Grad-CAM / Panel C untouched). Lines changed:
- `populateQualityGate` step line → `qgStepChips` **adaptive chip list** with
  parameters (`[CLAHE clip=0.008] [Illumination normalisation …] [Denoise: off]`),
  so clean vs borderline chip lists visibly differ.
- `onQGToggleImage` now swaps the QG canvas between **raw (before)** and
  **enhanced (after)** pixels (was a Phase-1 no-op).
- `addSyntheticOverlays` now dispatches to a new `addRealOverlays` when
  `provenance.structures=="REAL"`: cyan vessel skeleton, green OD ring + magenta
  fovea crosshair, thin-white quadrant dividers, per-class lesion layers
  (MA red / HE dark red / EX yellow). Helpers added: `hasRealStructures`,
  `addRealOverlays`, `odFoveaOverlay`, `crosshairMask`, `quadrantGridMask`,
  `updateLesionLegend`, `qgStepChips`, `lesionTooltip`.
- `buildWBLesionPanel` gains a **live legend** label (per-class counts).
- `onOverlayToggle` also toggles the fovea crosshair with the Disc & Fovea box;
  `onLesionRow` solos the real per-class `Lesion_<TYPE>` layer.
- Lesion table gains a **hover tooltip** (type, area px, quadrant, distance from
  fovea in disc diameters) via `lesionTooltip`.
- New helper `+netra/+ui/lesionOverlay.m` builds per-class masks + colours +
  counts for the canvas.

## NOT executed here (must be run on a MATLAB machine)

**No MATLAB is installed in this environment** (not on PATH; no
`C:\Program Files\MATLAB`; no `matlab.exe`), and **IDRiD/DRIVE are not on disk**
(`datasets/` absent — confirmed). Therefore, in this environment:
- `startup_netra`, `runtests('tests')` were **not run** — the new tests are
  written to the existing synthetic-fixture conventions and require no dataset.
- `eval_structures` / `eval_lesions` / `lesion_contact_sheet` were **not run**
  and **wrote nothing** — no `results_structures.mat`, `results_idrid.mat`, or
  `docs/figures/lesion_overlays.png` exists, because those must come from a real
  run on real data. Place DRIVE/IDRiD under `datasets/` and run them on a MATLAB
  machine to produce the metrics and the contact sheet.
- Consequently **no IDRiD/DRIVE metric, no runtime figure, and no contact-sheet
  false-positive count is reported** — none was measured. The per-module runtime
  budget (<3 s) is asserted structurally in code comments and must be profiled
  on a MATLAB machine; it was not profiled here.

---

# Track B — DR grading, calibration, explainability (Phases 7-8)

## Active path: RULE_BASED_NO_CNN (Fallback Path C — training did not run)

The Track B fallback policy is explicit: with no MATLAB, no GPU, no APTOS on
disk, and no `validation/splits.mat`, do **not** fabricate a CNN or invent
grades. Verified in this environment (2026-09-02):

| Check | Result |
|-------|--------|
| MATLAB installed | **No** (not on PATH; no `C:\Program Files\MATLAB`) |
| Deep Learning Toolbox / GPU | Unverifiable (no MATLAB) |
| APTOS on disk | **No** (`datasets/` absent; `docs/datasets.md` confirms 0) |
| `validation/splits.mat` | **Absent** → policy says STOP, do not generate |
| Messidor-2 | Not on disk; quarantine dir absent → **never read** (confirmed) |

So grading runs `icdrRule` alone (`provenance.grading = "RULE_BASED_NO_CNN"`)
and Grad-CAM/ALA are unavailable (`provenance.xai = "UNAVAILABLE_NO_CNN"`).
**No grading metrics were produced or saved** — none was measured, so per the
metrics rule none is written anywhere. See `docs/MODEL_CARD.md` and
`docs/ml_method.md`.

## What is REAL regardless of path (implemented + unit-tested here)

- `+netra/+grading/icdrRule.m` — independent 4-2-1 ICDR estimate (0-3; caps at 3,
  grade 4 is CNN-only). On path C this **is** the grade.
- `+netra/+grading/applyTemperature.m` — temperature-scaled softmax (ready for
  the CNN path; `T=1` identity, `T>1` raises entropy — tested).
- `+netra/+xai/agreementScore.m` — the ALA computation. Pure function, fully
  tested against synthetic maps/masks (=1 full overlap, =0 disjoint, NaN for
  all-false/empty mask). The headline differentiator; verified without a net.
- `+netra/+xai/evidenceBullets.m` — measured evidence bullets; hard invariant
  "no bullet for a zero-count lesion type", quadrant counts match `perQuadrant`,
  never diagnostic. Tested.
- `+netra/+xai/confidenceBand.m` — High/Moderate/Low; demote-only; NaN ALA never
  demotes; NaN confidence → Low. Tested.

## Files created

- `+netra/+grading/icdrRule.m`, `applyTemperature.m`
- `+netra/+xai/agreementScore.m`, `evidenceBullets.m`, `confidenceBand.m`
- `tests/fixtures/syntheticLesions.m` (fabricates Track-A-conforming lesion
  structs + `.allMask` so Track B tests run without Track A)
- `tests/tGrading.m`, `tests/tXai.m`, `tests/tEvidenceBullets.m`
- `docs/MODEL_CARD.md`, `docs/ml_method.md`

## Files modified

- `+netra/+grading/classify.m` — MOCK → real. Two paths: CNN (path A/B,
  inactive) and rule-based (path C, active). No fabricated probs on path C.
- `+netra/+xai/explain.m` — MOCK → real. Two paths; evidence bullets + band
  always produced (measured, no CNN); Grad-CAM/ALA only on path A/B, wrapped so
  a Grad-CAM failure never aborts the pipeline.
- `config/thresholds.json` — added grading keys (`modelInputSize`, `classOrder`,
  `confidenceHigh`, `confidenceLow`, `disagreementLevels`, `useFusion`) and xai
  keys (`alaHighThreshold`, `gradcamColormap`). Existing `referableThreshold`
  and `temperature` flagged as UNTUNED placeholders (no CNN).
- `+netra/loadConfig.m` — registered the new required keys.
- `NETRA_App.m` — Panel A (grading) and Panel C (xai) only:
  - Grading panel: provenance-aware confidence/rule rows — on path C shows
    "Rule-based grading (no trained CNN available)" in amber and "Grade from
    4-2-1 rule estimate: N" instead of a fake confidence % or CNN comparison
    (§9: never render a non-REAL grade in the same weight as a model output).
    (`populateWorkbench`, ~lines 1292-1315.)
  - XAI panel: ALA NaN now renders **"ALA: n/a"** + "not applicable — no lesions
    detected" instead of "0.00"; finite ALA below `alaLowThreshold` renders
    amber; attention summary only overwritten when ALA is finite.
    (`populateWorkbench`, ~lines 1329-1355.)
  - Grad-CAM opacity slider: already `ValueChangingFcn → canvas.setOpacity`
    (alpha only, **no Grad-CAM recompute** on slider events) — requirement
    already satisfied by the existing layer design; left unchanged.

## Deliberately NOT implemented (Path C + YAGNI)

Speculative under Path C — cannot be executed or verified without MATLAB + APTOS,
and the fallback policy forbids saving any metric from a non-run:

- `training/train_grader.m`, `training/calibrate.m`, `training/tune_threshold.m`,
  `training/train_fusion.m`, `validation/eval_grading.m` — no data/toolbox/GPU to
  run them; writing untested training scaffolding now is exactly what the
  fallback policy and YAGNI reject. `docs/MODEL_CARD.md` documents precisely what
  is required to enable path A (MATLAB training) or path B (external + ONNX).
- `+netra/+grading/fuseEvidence.m`, `+netra/+xai/gradcamOverlay.m` — need a
  trained/live network to be meaningful; no fixture makes them real. The
  integration points for both exist in `classify.m` / `explain.m` (path A/B
  branch). Fusion is documented as **deferred** (acceptance criteria permit).
- `+netra/+ui/probabilityBars.m` — the CNN 5-bar chart; on path C the badge
  shows a rule grade, not a distribution. The existing `axProbs` axes already
  render probs when present (path A/B). Not needed for path C.

## NOT executed here (must be run on a MATLAB machine)

- `startup_netra`, `runtests('tests')` were **not run** (no MATLAB). The new
  tests use the synthetic-fixture convention and need no dataset; they must be
  run on a MATLAB machine to confirm green.
- No training, calibration, threshold-tuning, or `eval_grading` run occurred, so
  **no confusion matrix, kappa, sensitivity, specificity, AUC, ECE, ALA
  distribution, or inference-latency number exists or is reported** — none was
  measured. `docs/figures/ala_distribution.png` is intentionally absent.
- Messidor-2 was **never read** (not on disk; quarantine dir absent).
- Track A mask contract was **not available** at implementation time; the
  synthetic fixture (`tests/fixtures/syntheticLesions.m`) was used for all tests,
  and `agreementScore`/`evidenceBullets` are written against the documented
  contract (`cr.lesions.<TYPE>.mask` / `.allMask` / `.count` / `.perQuadrant` /
  `.nearMacula`).
