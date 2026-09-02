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
