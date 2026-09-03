# NETRA — Complete Judge Demo Workflow

> Ground-truth walkthrough of the actual app (`NETRA_App.m`, 7 views). Every
> claim here is traced to the code. The demo's power is honesty: we say exactly
> what is a real measurement and what is seeded demo data. Judges trust that.

---

## 0. THE ONE HONESTY RULE (memorise this)

There are **two paths** through the app and they are NOT equally "real":

| Path | What runs | Realness |
|---|---|---|
| **New Screening → Analyze** | Loads a real fundus image, runs the FULL real pipeline on real pixels (`onAnalyze` → `runPipeline`). | **REAL** — this is your hero. |
| **Dashboard / Review Queue cases** | Reconstructed from the fictional mock registry (`mockCaseFromRow` loads `sample01.jpg`, runs the pipeline, then paints the *row's* grade as a cosmetic label). | **SEEDED DEMO DATA.** |

The app itself marks this — Dashboard's Recent Cases table prefixes mock grades
with `*` and shows the line *"No real registry yet — showing FICTIONAL mock
seed. * = mock grade."* Point at that line on purpose. It's a credibility win.

**Opening line for the room:** *"The classical-CV pipeline, routing, report, and
Simulink model are fully real. The DR grade comes from a ResNet-18 we fine-tuned
on APTOS. The cases you see pre-loaded are seeded so the dashboard isn't empty —
every case I run live in front of you is real, and the app labels the seeded
ones with an asterisk so we never blur that line."*

---

## 1. PRE-FLIGHT (do before the room, offline)

```matlab
cd /MATLAB Drive/NetrAI
startup_netra          % paths + config + toolbox table.
                       % "Computer Vision MISSING" is a FALSE ALARM — nothing uses it. Say so if asked.
```

Confirm these files exist (restore from backup if a re-clone wiped them — see PROJECT_STATE §2):
- `models/dr_grader.mat` — the trained CNN. **If present, the live grade is REAL** (`provenance.grading == "REAL"`). If absent, grading silently falls back to a rule estimate labelled *"Rule-based grading (no trained CNN available)"* — still honest, but weaker. **Get the full-run model in place and backed up.**
- `data/mock/registry_seed.mat` — makes the Dashboard/queue populated on launch (auto-loaded by `internalLoadRegistry`).

Launch, leave it up on Dashboard:
```matlab
app = NETRA_App;       % opens Field mode, Dashboard view
```

Have `data/demo/1.jpeg` … `10.jpeg` ready to pick from `onLoadImage`'s file dialog.

---

## 2. WHAT "FIELD" vs "CLINICIAN" MEANS

Top bar → **Mode** dropdown. This is a *persona filter on the nav rail* — same
engine, different job:

- **Field mode** (rural health worker at the PHC) sees:
  `Dashboard · New Screening · Quality Gate · Workbench · Validation & Capacity`.
  The capture-and-screen workflow. No review authority.
- **Clinician mode** (reviewing ophthalmologist) sees:
  `Dashboard · Workbench · Review Queue · Case Review · Validation & Capacity`.
  No capture form — they *adjudicate* what field workers sent up.

Both see Dashboard + Validation. Switching hides/collapses nav rows
(`applyMode`), it does not rebuild anything. **Say it in one sentence:** *"One
tool, two hats — the health worker captures, the clinician reviews."*

---

## 3. THE SEVEN VIEWS — what each is, what to click, what to say

### VIEW 1 — Dashboard ("the district at a glance") · ~30s
- **KPI cards** across the top (screenings, queue depth, auto-cleared, etc.).
- **Four charts** (`drawDashboardCharts`): grade distribution (bar, colour-coded
  0–4), last-7-days stacked (auto-cleared / reviewed / recaptured), queue depth
  by hour (line), quality-failure reasons (horizontal bar). Every chart has an
  **honest empty state** ("No cases yet", "No history") when there's no data.
- **Recent Cases table** — columns UID / Patient / Age / Eye / Grade / Urgency /
  Decision. Mock grades carry a leading `*`.
- **Do:** wave at the KPIs, then point at the `*` legend line and deliver the
  honesty rule from §0. Clicking a Recent row jumps to Workbench (seeded case).

### VIEW 2 — New Screening (Field) · **THE HERO, ~90s**
This is the real pipeline. Left = patient/capture form, right = image preview.
- **Do, in order:**
  1. **Patient ID** — required (`onAnalyze` blocks without it). Type `DEMO001`.
  2. Age / Diabetes yrs / Eye / PHC — leave defaults (55 / 5 / OD / PHC001).
  3. **Load Image** → pick `data/demo/1.jpeg`. The preview shows the image with
     a **cyan FOV outline** + a plausibility line — that's the real ingestion
     guard (`loadImage` → `validateImage` → plausibility) already running. If the
     file is junk it's rejected here and Analyze stays disabled.
  4. **(High-impact optional) Simulate Capture** dropdown → **Blur**, Severity
     slider ~0.6. **Say clearly:** *"This applies a SYNTHETIC degradation — it's
     how we prove the quality gate rejects bad captures without needing a broken
     camera."* A persistent amber tag shows it's synthetic. Then **Analyze** →
     it gets rejected at the gate. Then **Reset Original** → **Analyze** the
     clean image. This proves the gate actually gates.
  5. **Analyze** → progress dialog ("Ingesting, masking FOV, persisting…") →
     lands on **Quality Gate**.
- **Buttons:** Load Image · Analyze (enabled only after a valid load) · Reset
  Original · Clear.

### VIEW 3 — Quality Gate ("it refuses what it can't grade") · ~30s
`populateQualityGate`. All measurements are **real** (Phase 3, calibrated on APTOS).
- **Verdict banner:** GRADEABLE (green) / BORDERLINE – ENHANCEMENT APPLIED
  (amber) / UNGRADEABLE – RECAPTURE REQUIRED (red).
- **Quality gauge** 0–100 with pass/borderline threshold ticks.
- **Four subscore bars:** Focus (Laplacian var + Tenengrad), Illumination
  (uniformity + saturated + dark), Field of View (mask area vs full circle),
  Contrast (global + local std). Hover any bar → tooltip explains the features.
- **Preprocessing / Advice** — the **adaptive** enhancement chip list, e.g.
  `[FOV mask] [Circular crop + resize] [CLAHE (clip=…)] [Denoise: Wiener]`. A
  clean image and a borderline one produce **different** chips — that's the proof
  it's adaptive, not a fixed filter. Point this out.
- **"Why this image was rejected"** card — appears only on Ungradeable, with the
  concrete reason.
- **"Show all measurements"** — expands a monospace table of all 8 raw features
  vs thresholds with OK/FAIL per row. Great for a judge who asks "prove it".
- **Buttons:** Retake · Proceed w/ Enhanced · Continue (disabled on Ungradeable,
  with a tooltip saying why) · Show Original (before/after toggle vs enhanced).
- **Do:** on the clean image, hit **Continue** → Workbench.

### VIEW 4 — Workbench ("show your work") · **the analytical centrepiece, ~90s**
Left = analysis canvas + overlay toggles; right = Grading / Lesion Evidence /
Explainability panels + action bar.
- **Overlay checkboxes** (`onOverlayToggle`) — Original · Vessels · Disc & Fovea
  · Quadrants · Lesions · Grad-CAM, plus a **Grad-CAM opacity** slider. On a
  live (real) case these are drawn from the **actual masks** (`addRealOverlays`:
  Frangi vessel skeleton in cyan, green OD circle, magenta fovea crosshair,
  quadrant grid, per-class lesion layers). **Do:** tick Vessels, then Disc &
  Fovea, then Lesions, then Grad-CAM — build the picture layer by layer.
- **Grading panel:** big **grade badge 0–4** (colour-coded) + label; **probability
  bar chart** over grades 0–4; **confidence pill** ("Confidence: 87%  Band: …");
  **rule cross-check** row ("rule=2  CNN=2  disagreement=0"). On the real path
  this reads *Confidence …*; if no CNN it honestly says *"Rule-based grading (no
  trained CNN available)."*
- **Lesion Evidence table:** Type / Count / Area% / Quadrants / Near-macula for
  MA / HE / EX / CWS, a live per-class legend, and a hover tooltip listing the
  largest lesions with distance-from-fovea in disc diameters. Clicking a row
  **solos** that lesion class on the canvas.
- **Explainability panel** — the money shot: **ALA score** (Attention–Lesion
  Agreement: does the CNN's Grad-CAM attention land where the real lesions are?)
  as a big number + bar; **evidence bullets**; an attention summary line. ALA
  shows `n/a` (not 0.00) when there are no lesions — a deliberate clinical
  distinction. **Say:** *"The grade justifies itself — the heatmap has to agree
  with the lesions we actually detected, and that agreement is scored."*
- **Action bar:** Generate Report · Send to Review Queue · Auto-Clear (only
  enabled when routing = AUTO_CLEARED) · Next Case.
- **Note (honesty):** in the current build the action-bar buttons on Workbench
  are demo stubs (toasts) except Auto-Clear's guard. The **real** report/persist
  path runs inside the pipeline + `+store`; if a judge wants the PDF, generate it
  headlessly (see §5) or show the pre-made one.

### VIEW 5 — Review Queue (Clinician) · ~30s
`refreshQueue` / `queryQueue`. The clinician's worklist of cases needing a human.
- **Four KPI cards:** In Queue · Urgent · Est. Review Time (uses **measured**
  median review seconds when audit data exists, else a 30s planning assumption)
  · Auto-Cleared Today (with % of routed).
- **Filter chips:** All · Urgent · Priority · Routine · Uncertain-flagged.
- **Queue table:** UID / Age / AI Grade / Confidence / Urgency / Flags / Waiting.
- **"AI vs Reviewer" mini chart:** Agreed vs Overridden bar (empty state until
  reviews exist).
- **Buttons:** Review Next (opens the top case, starts the timer) · Open Selected
  · Refresh.
- **Say:** *"Grades 2/3/4 and low-confidence or low-agreement cases route here;
  clean grade-0/1 auto-clear. Rules live in config, not code."*

### VIEW 6 — Case Review (Clinician) · ~30s
`openCaseReview` / `finishReview`. Where a clinician adjudicates one case, timed.
- **Header:** case UID + a live **stopwatch** (green, monospace) — real timer,
  measures review seconds.
- **2×2 image grid:** Enhanced · Lesion overlay · Grad-CAM · Zoomed macula.
- **Evidence panel:** grade badge, confidence, ALA, evidence bullets, prior
  history ("N earlier cases on record" from the registry), optional note field.
- **Action buttons:** **Confirm AI Grade** · **Override (0–4)** (prompts for the
  corrected grade) · **Mark Ungradeable** · **Skip**. Each **stops the timer,
  logs the decision** via `logReview` (action, final grade, reviewer, seconds,
  note) to the registry, then **auto-advances to the next queued case**.
- **Say:** *"Every review is timed and logged — that agreement/override data is
  what feeds the audit stats and the capacity model's review-time parameter.
  Nothing is fabricated; it's measured as the clinician works."*
- **Do:** Review Next → Confirm (or Override to 3) → watch it log + advance.

### VIEW 7 — Validation & Capacity · ~45s
Two tabs.
- **Tab 1 — Validation Report:** currently an **honest empty state** listing what
  it *will* hold (ROC per grade, confusion matrix, sensitivity/specificity,
  kappa vs clinicians). **Say plainly:** *"This is intentionally empty — those
  numbers only appear once the full validation runs are executed and saved. We
  refuse to show a metric we haven't measured. External (Messidor-2) validation
  is one-shot and scheduled, not yet run."* An empty-but-honest panel beats a
  suspiciously complete table.
- **Tab 2 — Capacity Planner (Simulink):** the district-throughput model, real.
  - **Left:** parameter form; each param is tagged **[MEASURED]** (green) or
    **[ASSUMED]** (amber) — e.g. inference latency is measured, arrival rate is
    assumed. Scenario presets **S1 Baseline / S2 Auto-clear / S3 +Staffing**.
  - **Buttons:** **Run Simulation** (runs `netra.sim.runCapacity`, feeds real
    per-stage latency via `latencyStats`) and **Open Model in Simulink** (opens
    the actual `.slx`).
  - **Right:** recommendation banner + 3 charts (queue depth, arrived-vs-cleared,
    reviewer utilisation) + 5 KPI cards (Throughput/day, p95 Wait days, Peak
    Backlog, Utilisation %, Auto-Cleared %).
  - **Do:** click **S2 Auto-clear** (auto-runs) → point at the queue-depth drop.
    Then **Run Simulation** on baseline for contrast. **Say:** *"It's a model of
    screening capacity, fed by our real measured latency — not a live telemedicine
    link. It answers: with N reviewers, does auto-clearing grade 0/1 keep the
    backlog survivable?"*

---

## 4. THE 5-MINUTE DRY RUN (rehearse this exact order)

1. **Dashboard** (30s) — KPIs + charts + the `*`/mock honesty line. → §0 opener.
2. **Mode dropdown** (10s) — flip Field↔Clinician, one sentence on personas.
3. **New Screening** (90s) — Patient ID, Load `1.jpeg`, *(optional Blur→reject→
   Reset)*, Analyze. → real pipeline.
4. **Quality Gate** (30s) — verdict, gauge, adaptive chips, expand "Show all
   measurements", Continue.
5. **Workbench** (90s) — layer on Vessels→Disc&Fovea→Lesions→Grad-CAM; grade
   badge + probs + confidence; lesion table; **ALA explainability** (dwell here).
6. **Review Queue → Case Review** (45s) — Review Next, watch the timer, Confirm/
   Override, it logs + advances.
7. **Validation & Capacity** (45s) — honest empty Validation tab; Capacity S2
   preset, point at the backlog drop; measured-vs-assumed tags.

**Total ≈ 5 min.** If cut to **2 min:** do New Screening → Workbench only (real
pipeline + grade + Grad-CAM + ALA). That single flow is the entire thesis.

---

## 5. HEADLESS FALLBACK (if the UI misbehaves live)

Run the whole pipeline from the command window and talk over it:
```matlab
cr = netra.runPipeline(netra.newCaseRecord('data/demo/1.jpeg'), ...
                       netra.loadConfig(), netra.loadModels());
cr.quality.class, cr.grade.icdr, cr.grade.confidence, cr.xai.agreementScore
```
This proves the engine independent of the GUI. Keep a pre-generated PDF and a
screen recording on the desktop. Never let a stack trace hit the screen —
`app.wrap` catches errors, but if one leaks, switch to the recording and keep
talking.

---

## 6. LIKELY JUDGE QUESTIONS — one-line answers

- **"Is the grade real?"** Yes — ResNet-18 fine-tuned on APTOS; `provenance.
  grading == REAL`. Dry-run model scored val-acc 0.738 / quadratic-kappa 0.804;
  the full-run model is what's loaded here.
- **"Are the dashboard cases real patients?"** No — seeded demo data, marked with
  `*`. Every case I ran live just now is real.
- **"Why no external validation numbers?"** Messidor-2 is one-shot by design —
  we run it exactly once and report verbatim, no tuning after. Not run yet, so
  the panel is honestly empty rather than fabricated.
- **"Computer Vision Toolbox is missing?"** False alarm — nothing uses it;
  `fibermetric`/Frangi live in Image Processing.
- **"What's simulated?"** The capture-degradation engine (for testing the gate)
  and the district-capacity model (a model, not a live network). Both labelled.
