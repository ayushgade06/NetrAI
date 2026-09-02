# NETRA

MATLAB-based diabetic retinopathy (DR) screening prototype — Smart India
Hackathon PS 26038 (MathWorks). This repository is at **Phase 0: scaffolding
and the pipeline data contract.** No image processing, ML, or UI yet.

## Quick start

Requires MATLAB **R2023b or later** (base MATLAB only for Phase 0). Place a
fundus image at `data/demo/sample01.jpg`, then:

```matlab
startup_netra
cr = netra.runPipeline(netra.newCaseRecord('data/demo/sample01.jpg'));
disp(cr)
runtests('tests')
```

`startup_netra` adds paths, loads config, and prints a toolbox-availability
table. The pipeline runs all nine stages as MOCK stubs (fixed placeholder
values) except **routing**, which is the one real rules engine in Phase 0.

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
