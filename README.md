# NETRA

MATLAB-based diabetic retinopathy (DR) screening prototype — Smart India
Hackathon PS 26038 (MathWorks). This repository is at **Phase 0: scaffolding
and the pipeline data contract.** No image processing, ML, or UI yet.

## Quick start

Requires MATLAB **R2023b or later** (base MATLAB only). A demo image ships at
`data/demo/sample01.jpg`.

```matlab
startup_netra
seedMockRegistry          % one-time: ~40 fictional cases for the dashboard/queue
app = NETRA_App;          % launch the seven-view UI
```

Headless pipeline use (no UI):
```matlab
cr = netra.runPipeline(netra.newCaseRecord('data/demo/sample01.jpg'));
disp(cr)
runtests('tests')
```

`startup_netra` adds paths, loads config, and prints a toolbox-availability
table. The pipeline runs all nine stages as MOCK stubs (fixed placeholder
values) except **routing**, which is the one real rules engine.

### The app (Phase 1)

`NETRA_App` is a programmatic classdef (no `.mlapp`). Seven views: District
Dashboard, New Screening, Quality Gate, Analysis Workbench, Review Queue, Case
Review, Validation & Capacity. A **Field / Clinician** mode toggle (top-right)
filters the nav rail. A persistent **provenance banner** shows amber and names
every MOCK stage — expected in Phase 1, since almost everything is still mock.

Dev layout aid: `NETRA_App('DevMode', true)` adds a verdict-override dropdown on
the Quality Gate to force Good / Borderline / Ungradeable states.

## Layout

```
+netra/          package: factory, orchestrator, config/model loaders, stages
  +quality +preproc +structures +lesions +grading +xai   MOCK stubs
  +routing         REAL rules engine
  +report +store   MOCK stubs (only stages allowed to touch disk)
  +util            timeStage, assertSchema, stageNames
config/          thresholds.json, routing_rules.json, phc_registry.json
models/          placeholders only (see PLACEHOLDER_README.md)
data/demo/       sample images (you provide)
data/cases/      runtime output (gitignored)
docs/            schema.md (field contract), phase_notes.md
tests/           matlab.unittest suite
```

## The contract

The `caseRecord` struct is defined once in `netra.newCaseRecord` and documented
in [`docs/schema.md`](docs/schema.md). Frozen stage signatures (section 7 of the
Phase 0 brief) let six developers fill later phases in parallel. Rules:

- One `caseRecord` in, one out. Stages ADD fields, never delete/rename.
- Only `+store` / `+report` write to disk.
- Every threshold lives in `config/`, never inline in code.
- Each stage sets `provenance.<stage>`; `runPipeline` sets `timing.<stage>`.

## Status

Phase 0 of 11. See `docs/phase_notes.md` for the phase→stage map.
