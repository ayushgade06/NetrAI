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
