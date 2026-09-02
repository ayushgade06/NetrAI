# NETRA — Clinical Report Specification

`netra.report.generate(cr, cfg)` produces a printable PDF at
`<storeRoot>/data/cases/<uid>/<uid>_report.pdf` and returns the path. Only
`+store` and `+report` write to disk.

## Contents (in order)

1. **Patient header** — UID, patient ID, PHC, age, diabetes duration, eye, image path.
2. **Quality verdict** — class + score (+ fail reason if any).
3. **ICDR grade** — grade number + human label.
4. **Referral decision + urgency** — routing decision, urgency, any flags.
5. **Confidence band** — confidence % + High/Moderate/Low band.
6. **ALA** — Attention-Lesion Agreement score + attention summary.
7. **Evidence bullets** — from `cr.xai.evidenceBullets` (≥1 line; a fallback
   line states when explainability did not run).
8. **2×2 annotated panel** — original / enhanced / lesion overlay / Grad-CAM.
9. **Provenance summary** — per-stage `REAL`/`MOCK`/`FAILED`, so a reader can
   see which stages were mock at generation time.
10. **Timestamp + version** — generation time, pipeline version, model/config hash.
11. **Disclaimer footer** (mandatory, verbatim):
    > AI-generated screening output. Requires ophthalmologist confirmation.
    > Research prototype — not validated for clinical use.

## The 2×2 composite (`netra.report.composite`)

| Tile | Source stage |
|------|--------------|
| Original fundus | ingest / image capture |
| Enhanced | `netra.preproc.enhance` |
| Lesion overlay | `netra.lesions.detect` |
| Grad-CAM attention | `netra.xai.explain` |

Where a tile's source stage has **not run for real** (another track still MOCK,
or the stage failed / produced no output), that tile renders a **labelled grey
placeholder naming the responsible stage** — never a blank tile and never a
substituted image. A REAL lesion stage with zero lesions is a valid overlay
(the clean enhanced frame), not a placeholder.

## Rendering method (and fallback)

The report is rendered with **base-MATLAB graphics + `exportgraphics`**
(multi-page vector PDF: page 1 text, page 2 the 2×2 panel). This is the shipped
path — it needs **no Report Generator toolbox**, so it works on any MATLAB. The
footer records the method used (`[rendered via exportgraphics]`).

Per the fallback policy (brief §13): if Report Generator *were* preferred it is
still not required here; and if `exportgraphics` itself is unavailable, the code
falls back further to `print(...,'-dpdf')` (single-page layout, panel written to
a sibling `_panel.pdf`) and the footer records `[rendered via print]`.

## Provenance note

`runPipeline`'s `stageReport` still tags `cr.provenance.report = "MOCK"` because
the brief forbids changing `runPipeline.m` beyond the timing-log append. The
report content is nonetheless real; the MOCK flag reflects only that the
orchestrator's provenance line was left untouched by policy. The report's own
provenance summary reports the true per-stage state of the pipeline stages it
draws from (preproc/lesions/xai/grading/routing).
