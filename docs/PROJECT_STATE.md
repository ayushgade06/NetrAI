# NETRA — Complete Project State & Session Handoff

> Single source of truth for picking up work in a new session. Covers the whole
> project from Phase 0 to now, not just the current track.

---

## 1. WHAT NETRA IS

MATLAB diabetic-retinopathy (DR) screening prototype for **Smart India Hackathon
PS 26038 (MathWorks-sponsored)**. A rural health worker photographs a patient's
retina; NETRA:
- gates image **quality** (rejects ungradeable captures with a reason),
- **enhances** the image and segments retinal **structures** (vessels, optic
  disc, fovea) and **lesions** (microaneurysms, haemorrhages, exudates),
- **grades** DR severity (ICDR 0–4) with a CNN,
- **explains** the grade (Grad-CAM + evidence bullets + an ALA agreement score),
- **routes** the case (auto-clear / review / urgent referral),
- produces a **clinical PDF report**, and
- models **district screening capacity** in Simulink.

Repo: `github.com/ayushgade06/NetrAI` (branch `main`).

---

## 2. EXECUTION ENVIRONMENT (read first)

- Development is on **Windows at `D:\NetrAI`** — **no MATLAB installed here.**
- Code **runs on the user's MATLAB Online R2026a** at `/MATLAB Drive/NetrAI`.
- **Workflow:** edit + commit + push on Windows → user pulls/runs on MATLAB
  Online → user pastes output → fix → repeat. The user is the hands on MATLAB.
- **Toolboxes on MATLAB Online:** Image Processing ✅, Deep Learning ✅,
  Statistics & ML ✅, Simulink ✅. Computer Vision shows **"MISSING" — false
  alarm**, nothing uses it (`fibermetric` lives in Image Processing).
- **Commit style:** NO `Co-Authored-By: Claude` trailer (user preference).

### Two recurring MATLAB-Online quirks (both handled, but they recur)

1. **`git pull` corrupts `.git` packfiles on MATLAB Drive.** Recovery = re-clone:
   ```matlab
   cd /MATLAB Drive
   movefile('NetrAI/datasets','datasets_backup')
   !rm -rf NetrAI && git clone https://github.com/ayushgade06/NetrAI.git
   movefile('datasets_backup','NetrAI/datasets')
   cd NetrAI && startup_netra
   ```
   After a re-clone, `validation/splits.mat` and `models/dr_grader.mat` are gone
   from the repo folder — **restore from backups**, don't regenerate/retrain.

2. **`imread` fails on the `.jpg` extension** ("Unable to determine file format
   from filename") though `.jpeg` works and the files are valid JPEGs. FIXED via
   `netra.io.readImageFile` (imread → imread with explicit `'jpg'` → Java
   `ImageIO` byte-decode). Wired into `loadImage`, `realImage`, `train_grader`.

### Persistence across sessions
Trained model + split live **inside the repo folder**, which re-cloning wipes.
Back them up to stable paths after producing them, restore after re-clone:
```matlab
% after training / splitting:
copyfile('models/dr_grader.mat','/MATLAB Drive/dr_grader_backup.mat')
copyfile('validation/splits.mat','/MATLAB Drive/splits_backup.mat')
% after a re-clone:
copyfile('/MATLAB Drive/dr_grader_backup.mat','NetrAI/models/dr_grader.mat')
copyfile('/MATLAB Drive/splits_backup.mat','NetrAI/validation/splits.mat')
```

---

## 3. HOW IT'S BUILT (architecture)

**Frozen `caseRecord` contract.** One struct defined in `netra.newCaseRecord`,
documented in `docs/schema.md`. Nine stages run in fixed order, each takes one
`caseRecord` and returns one; a stage may ADD fields, never delete/rename. Only
`+store`/`+report` touch disk. Each stage sets `cr.provenance.<stage>`;
`runPipeline` sets `cr.timing.<stage>`. Every threshold lives in `config/*.json`
— never inline.

**Package layout (`+netra/`):**
| Package | Role |
|---|---|
| `+io` | load/validate/hash images, plausibility guard, degradation engine, `readImageFile` |
| `+quality` | 8 handcrafted features → rule-based classifier + hard overrides |
| `+preproc` | FOV mask, crop/resize, illumination, adaptive CLAHE, denoise, Ben-Graham |
| `+structures` | Frangi vessels, optic disc (Hough), fovea (geometric), quadrant map |
| `+lesions` | red lesions (MA/HE), bright lesions (EX, OD-subtracted), quadrant tally |
| `+grading` | ICDR rule estimate + CNN classify + temperature scaling |
| `+xai` | agreement/ALA score, evidence bullets, confidence band, Grad-CAM (path A) |
| `+routing` | decision rules (auto-clear / review / urgent) — the one always-REAL stage |
| `+report` | 2×2 composite figure, template, PDF via `exportgraphics` |
| `+store` | per-case `.mat`+`.png`, atomic registry upsert, review logging, audit stats |
| `+sim` | district capacity model (numerical + Simulink), params, recommendation |
| `+ui` | theme, KPI card, gauge, image canvas, status banner, overlays |
| `+util` | timeStage, assertSchema, stageNames, timing log, latency stats |

**UI:** programmatic App Designer classdef `NETRA_App.m` (no `.mlapp`). 7 views
(Dashboard, New Screening, Quality Gate, Workbench, Review Queue, Case Review,
Validation & Capacity), Field/Clinician mode toggle, all layout via
`uigridlayout`, centralized theme. **Storage:** file-based (per-case `.mat` +
atomic `registry.mat`). No web/DB stack — deliberate (single-operator clinical
tool; MathWorks-sponsored so MATLAB is required and fits the CV/ML/Simulink work).

---

## 4. PROJECT HISTORY (phase → track, per git history)

- **Phase 0** — scaffolding, frozen schema, MOCK stubs, routing rules, config,
  `runPipeline`, tests. (`58ccc79` and earlier)
- **Phase 1** — programmatic UI shell, 7 views, mock registry seed, UI helpers.
- **Phase 2** — real image ingestion, FOV masking, crop/resize, persistence,
  degradation engine, dataset tooling. (folded into Track A commit history)
- **Phase 3** — quality assessment + gating (rule-based fallback active; no
  trained classifier — no data at authoring time).
- **Track A** (`19d389a`) — classical CV: enhancement, structures, lesions. All
  REAL. No ML.
- **Track B** (`b9ebd76`) — DR grading + ALA explainability. Authored on the
  RULE_BASED_NO_CNN fallback path (no MATLAB/data at the time); ALA, evidence
  bullets, ICDR rule, temperature scaling all real + unit-tested.
- **Track C** (`67293ea`) — clinical PDF report, timed review workflow, Simulink
  district-capacity model.
- **Track D** (`ecf4d14` → present) — integration, external validation, demo
  hardening. THIS is the current track. See §6.

> **Key fact:** Tracks A/B/C were all written on a machine with **no MATLAB and
> never executed**. Track D's first job was running them on real MATLAB Online
> and fixing everything that broke — ~30 real bugs surfaced and were fixed.

---

## 5. WHAT IS REAL / SIMULATED / MOCK (current, honest)

- **REAL now:** the full classical-CV pipeline (quality, preproc, structures,
  lesions), routing rules, report, store, Simulink capacity model, AND the
  **trained CNN grader** (ResNet-18 on APTOS — see §6). Quality thresholds
  (blur/denoise/scale/FOV) were CALIBRATED from measured real-APTOS values.
- **SIMULATED:** the degradation engine (synthetic capture failures for
  tests/demo), the district-capacity model (modelled, not a live telemedicine
  system), demo registry seed.
- **NOT YET:** fusion classifier, one-shot Messidor validation, ablation table,
  populated Validation view — all pending in Track D (§6), all now UNBLOCKED
  because the CNN trains.
- **OUT OF SCOPE (documented):** cotton-wool spots, neovascularisation, real
  camera integration, multi-PHC aggregation.

---

## 6. TRACK D — CURRENT STATUS

### Done
- **Test suite: 168 passing, 0 failing** on MATLAB Online. Remaining "incomplete"
  are HONEST capability-gated skips (no IDRiD dataset, no fake passes).
- **~30 bugs fixed** (commits `ecf4d14`→`9dda049`): quadrantMap arguments, imadd
  scalar, kpiCard.set, timeStage nargout, Simulink build (empty ports, MinMax
  Inputs=2, runtime budget), fovMask completeness (EquivDiameter), OD-inside-FOV,
  quality threshold calibration, sidebar nav gaps, KPI clipping, `.jpg` reader,
  CNN-path double-softmax + modelInput guard.
- **CNN GRADER TRAINED & WORKING.** `training/train_grader.m` fine-tunes ResNet-18
  on the APTOS train split. Dry run (30% data, 2 epochs, CPU, ~1.5min):
  **val accuracy 0.738, quadratic kappa 0.804.** Saves `models/dr_grader.mat`;
  `loadModels` auto-detects → `models.grader`, `isPlaceholder=false` →
  `grading.classify` uses the real CNN path with no code change.
    - `train_grader('maxEpochs',8)` = full run; `('subset',0.3,'maxEpochs',2)` = quick.

### Remaining (in order)
1. **Full training run** (all 2048 imgs, ~8 epochs) → the model to demo/report;
   back it up immediately.
2. **§4.2 Fusion classifier** — `train_fusion.m` (CNN probs + Track A lesion
   features → referable-DR head, fit on APTOS val).
3. **§4.3 Latency** — 50 imgs through pipeline, per-stage median/p95 →
   `validation/latency.mat` → feed real inference latency into Simulink params.
4. **§4.4 ONE-SHOT Messidor-2 external validation** — `run_external.m`. Run the
   pipeline over Messidor **exactly once**, save verbatim with timestamp + model
   hash, **no tuning after**. Report the gap vs internal honestly.
5. **§4.5 Ablation** (4 configs on APTOS test split): A=classical+SVM only,
   B=CNN no quality gate, C=CNN+quality gate, D=full+fusion. Report sensitivity/
   specificity/AUC/kappa each. If D doesn't win, report that honestly.
6. **§4.6 Benchmark table** — only sourceable published figures.
7. **§4.7 Validation view** (5 tabs) populated from saved `.mat` only; honest
   empty states where data is missing; never computes live.
8. **§4.8** `tests/tRegression.m` — 50 imgs, zero crashes, latency + memory.
9. **§4.9–4.14** — 5 demo images, `tools/seedDemoState.m`, splash/model preload,
   error hardening (no stack trace reaches screen), fallback assets (recording,
   chart PDF, Simulink screenshot), docs: `demo_script.md`, `qa_prep.md`,
   `limitations.md`.

### Non-negotiable rules (Track D brief)
- **NO fabricated numbers anywhere.** Every number in UI/docs must come from a
  saved `.mat` produced by an executed run. Missing data → honest empty state
  naming what's absent.
- **Messidor-2 is ONE-SHOT** — run once, save verbatim, never tune after.
- **Ablation reported as measured** — a clean negative finding is defensible.
- Don't change the schema. Fix bugs, don't refactor working modules.
- Every result `.mat` records inputs (dataset, split, model hash, timestamp,
  config hash) for traceability.

---

## 7. DATASETS

- `datasets/aptos2019/` — `train_images/`(2930) `val_images/`(366)
  `test_images/`(366) + `train_1.csv`/`valid.csv`/`test.csv`
  (cols `id_code`, `diagnosis` 0–4). Flat `*.jpg`, all grade-labeled.
- `datasets/messidor2/` — `images/`(1748) + `messidor_data.csv`
  (`image_id`, `adjudicated_dr_grade` 0–4, `adjudicated_gradable`). ONE-SHOT.
- Local source zips: `D:\aptos.zip`, `D:\messidor.zip`. Resize script:
  `tools/resize_for_upload.py` (600px, ~172MB total for MATLAB Drive quota).
- `validation/splits.mat` (gitignored): train 2048 / val 439 / test 443, seed
  26038, stratified. Recreate: `registerDatasets; freezeSplits` (or
  `freezeSplits(true)` to overwrite).
- IDRiD / DRIVE: absent (some lesion/structure validation + tests skip honestly).

---

## 8. HOW TO RUN (MATLAB Online)

```matlab
cd /MATLAB Drive/NetrAI
startup_netra                       % paths + config + toolbox table
runtests('tests')                   % suite (168 pass / 0 fail expected)
% datasets present? then:
registerDatasets; freezeSplits      % -> validation/splits.mat
train_grader('maxEpochs',8)         % train the CNN grader
app = NETRA_App;                    % launch the UI
```

Headless pipeline: `cr = netra.runPipeline(netra.newCaseRecord('data/demo/1.jpeg'));`
