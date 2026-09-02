# NETRA — Classical CV Method (Track A: enhancement, structures, lesions)

This documents every algorithm and threshold in the Track A layer: adaptive
enhancement (Phase 4), retinal-structure segmentation (Phase 5), and lesion
detection (Phase 6). **No machine learning is used in this track.** Every
numeric parameter lives in `config/thresholds.json`; nothing is inlined.

Resolution policy (applies throughout): parameters are specified **at the
512 px target size** and scaled at runtime by `min(H,W)/preproc.targetSize`
(a linear scale factor) or by the measured disc radius, so the same physical
structures are found at any resolution.

---

## 1. Adaptive enhancement (`+netra/+preproc`)

The stage produces two outputs: `img.enhanced` (uint8, for human display) and
`img.modelInput` (single, Ben-Graham normalised, for Track B's CNN). Steps fire
**adaptively**, driven by the measured quality subscores, and every applied
operation is logged with its parameters in `preproc.appliedSteps`. A clean and a
borderline image therefore produce **different** chip lists — the proof the
enhancement is adaptive, not a fixed filter chain.

### 1.1 Illumination normalisation — `illumNormalize.m`
- **Trigger:** FOV illumination uniformity `< preproc.uniformityTrigger` (0.7).
  Uniformity = min/max of the four quadrant mean green intensities inside FOV
  (reused from `quality.illum` if the quality stage ran).
- **Method:** per channel, `corrected = channel − background + mean(background)`,
  where `background = medfilt2` with a large kernel. Median (not mean) so small
  dark/bright structures (vessels, lesions) do not bleed into the estimate.
- **Kernel:** side = `2·round(illumKernelFraction · fovRadius)+1`
  (`illumKernelFraction = 0.5` of the FOV radius) → resolution-aware.
- **Why subtract-and-restore-mean:** removes the low-frequency shade while
  preserving global brightness, so the output is not a flat near-zero field.
- **Runtime:** the large-kernel median is computed on a 256 px-bounded
  downsample (the illumination field is slowly varying) and upsampled, making
  the step fast and its cost resolution-independent.

### 1.2 Adaptive CLAHE — `claheAdaptive.m`
- **Always fires** (core contrast step) but the **clip limit is computed from
  the measured contrast deficit**, so strength is adaptive:
  `deficit = max(0, 1 − contrast/contrastTarget)`,
  `clip = claheClipMin + deficit·(claheClipMax − claheClipMin)`.
  `contrastTarget = 0.18`, `claheClipMin = 0.004`, `claheClipMax = 0.05`.
- **Channel:** applied to the **L channel of Lab** (perceptual luminance) so hue
  is preserved and red/orange lesion colour is not distorted. 8×8 tiles
  (adapthisteq default; a grid, hence resolution-relative), Rayleigh
  distribution. Surround re-blackened afterwards.

### 1.3 Optional denoise — `denoise.m`
- **Trigger:** robust HF-noise estimate `sigma = median(|Laplacian|)/0.6745`
  exceeds `preproc.denoiseTrigger` (0.9, on the 0..255 MAD scale). Below it the
  image is returned **unchanged** (keeps clean images un-softened).
- **Method:** per-channel `wiener2([3 3])` — locally adaptive, so vessel/lesion
  edges survive better than under a uniform Gaussian blur.

### 1.4 Ben-Graham model input — `benGraham.m`
- `out = 4·(img − GaussianBlur(img, σ)) + 128`, σ =
  `benGrahamSigmaFraction · fovRadius` (`0.05`) → resolution-aware.
- Removes camera/operator colour cast, centres on mid-grey. Circular FOV mask
  set to the 0.5 grey background. Output single, 0..1, NaN/Inf-guarded.

### 1.5 Revert guard
If any step yields NaN/Inf or collapses to a near-constant image
(`std < 1e-3`), the enhanced buffer reverts to the geometry-only crop, a step
`enhancementReverted` is logged, and the pipeline continues.

---

## 2. Retinal structures (`+netra/+structures`)

Runs on the enhanced frame; writes `vesselMask`, `odCenter/odRadius`,
`foveaCenter`, `maculaZone`, `quadrantMap`, `vesselDensity`, `tortuosity`, plus
`odFallback`/`foveaFallback` flags.

### 2.1 Vessels — `vesselsFrangi.m`
- **Multi-scale Frangi vesselness** via `fibermetric` (IPT, a documented
  Frangi-family ridge detector) on the **inverted green channel** (vessels are
  dark → bright ridges). Scales = `frangiScales` = `[2 3 4 6 8]` px at 512,
  disc/frame-scaled; per-scale responses combined by max.
- **Hysteresis threshold:** strong seeds at `vesselThreshold` (0.12) grown into
  weak (½·threshold) connected pixels via `imreconstruct`.
- Restricted to an eroded FOV (drops the bright rim); **length pruning**
  removes components shorter than `minVesselLength` (12 px @512).
- `vesselDensity` = vessel area / FOV area (0 if FOV empty, guarded).
  `tortuosity` = mean skeleton-path / endpoint-chord over the longest 20
  branches (≥1; 1 if no vessels).

### 2.2 Optic disc — `locateOD.m`
1. **Vessel inpainting:** close the bright (green+red)/2 channel over the
   dilated vessel mask so vessels don't fragment the disc blob.
2. **Bright-region candidate:** brightest `odSearchTopPercent` (5%) of
   inside-FOV pixels → largest bright blob centroid.
3. **Hough refinement:** `imfindcircles` in `odRadiusRange` (`[30 70]` px @512,
   scaled), nearest strong circle to the candidate.
4. **Validation confidence** = 0.6·(disc-vs-surround brightness contrast) +
   0.4·(vessel-convergence density near the centre).

### 2.3 Fovea — `locateFovea.m`
1. **Geometric prior:** `foveaDiscDiameters` (2.2) disc **diameters** temporal
   to the OD. Temporal direction = away from the nearest horizontal FOV edge
   (the OD is nasal), so no eye label is needed for the geometry.
2. **Bounded darkest-region search** inside a `foveaSearchWindow` (90 px @512)
   box: darkest, vessel-free, well-inside-FOV spot. Constrained to the window so
   a dark lesion elsewhere cannot capture it.
3. **Confidence** = 0.6·(dark-vs-surround contrast) + 0.4·avascularity.
- **Macula zone** = disc within `lesions.maculaRadiusDiscDiameters` (1.0) disc
  **diameter** of the fovea, ∩ FOV.

### 2.4 Quadrants — `quadrantMap.m`
- Horizontal axis = the measured **OD→fovea** direction (temporal); vertical =
  perpendicular (superior/inferior); origin = OD centre. Codes: 1 SN, 2 ST,
  3 IN, 4 IT; background 0. Anchored on the OD→fovea axis, so it is
  laterality-correct; `eye` is retained for future nasal/temporal UI labelling.

### 2.5 Fallbacks (`segment.m`)
- **OD conf < 0.35** → `odCenter` = FOV centroid, `odRadius` =
  `odFallbackRadiusFraction·fovRadius` (0.18), `odFallback = true`, routing flag
  `ODLocalisationLowConfidence`.
- **Fovea conf < 0.30** → keep the geometric prior, `foveaFallback = true`,
  flag `FoveaLocalisationLowConfidence`.
- **Empty vessel mask** → density 0 (no divide-by-zero), flag `EmptyVesselMask`.
- All three masks are asserted logical/uint8 and exactly `size(enhanced,[1 2])`
  at the end — a mismatch errors loudly (protects Track B's ALA).

---

## 3. Lesions (`+netra/+lesions`)

Runs on the enhanced frame using the located OD / quadrant map / macula zone.

### 3.1 Red lesions (MA + HE) — `redLesions.m`
- On the **inverted green** channel: `vesselMap = max over K line-SE openings`
  (K = `seOrientations` = 12, length = `seLength` = 15 px @512, disc-scaled). A
  line SE keeps elongated vessels (aligned at some orientation) and erases
  compact lesions; the max reconstructs the whole vessel tree.
- `residual = inv − vesselMap`; **adaptive threshold** at
  `redThresholdFactor·std(residual in FOV)` (`redThresholdFactor = 3.0`).
- Dilated vessel pixels removed; specks below sensor scale dropped.
- Each region classified MA vs HE by `classifyMAvsHE.m`.
- **Runtime knob:** if over the 3 s budget, reduce `seOrientations` before
  sacrificing correctness (per the brief).

### 3.2 MA vs HE — `classifyMAvsHE.m`
MA iff `area ≤ maAreaMax` **and** `eccentricity ≤ maEccentricityMax` (0.85)
**and** `circularity (4πA/P²) ≥ maCircularityMin` (0.6); else HE. `maAreaMax`
(120) and `heAreaMin` (120) are px² **at 512** and rescaled by
`(odRadius/referenceOdRadius512)²` (`referenceOdRadius512 = 50`) so the MA/HE
size cut tracks the true disc scale.

### 3.3 Bright lesions (EX) — `brightLesions.m`
- **Top-hat** (`imtophat`, disc SE ~ exudate scale) on the green channel isolates
  small bright objects.
- **MANDATORY OD subtraction:** the dilated optic-disc region
  (`odRadius + max(odDilationPx·scale, 0.3·odRadius)`) is **zeroed** before
  thresholding. The OD is the brightest object in the image and will otherwise
  dominate — this is the single most common bug in the module (tested first in
  `tLesions`).
- Threshold at `mean+3·std` of the residual inside FOV, then filter by
  `exMinArea` (15 px² @512, scaled) **and boundary sharpness**
  (`exSharpnessMin = 0.02`, mean edge gradient — exudates have sharp edges;
  soft drusen/reflections are rejected).

### 3.4 Tally — `quadrantTally.m`
Each connected component = one lesion, assigned to its centroid's quadrant and
flagged `nearMacula` if the centroid is inside `maculaZone`. Produces the schema
lesion-set (count/totalArea/centroids/areas/perQuadrant/nearMacula) **plus** the
Track-B `mask` field.

### 3.5 Mask format contract (§7 — Track B depends on this exactly)
`cr.lesions.<TYPE>.mask` is **logical**, size `size(cr.img.enhanced,[1 2])`,
true where that class is present (TYPE ∈ {MA, HE, EX}). `cr.lesions.allMask` =
logical union of the three. Both asserted at the end of `detect.m`.
**CWS is not implemented** (out of scope for time); its field stays the empty
lesion-set (a same-sized all-false `mask` is added for shape consistency) with a
documented `cwsNote = "cwsNotImplemented"`. Zero lesions is a **valid** normal
result: counts of 0 and all-false masks propagate cleanly.

---

## 4. Threshold provenance

All Track A thresholds in `config/thresholds.json` are **engineering estimates**,
not tuned on IDRiD/DRIVE, because **neither dataset was on disk** in the
authoring environment (`docs/datasets.md`). Tune them against the real metrics
from `validation/eval_structures.m` (DRIVE vessels, IDRiD OD) and
`validation/eval_lesions.m` (IDRiD MA/HE/EX sensitivity + FP/image) once the data
is placed under `datasets/`. Per the metrics rule, **no expected or illustrative
number is written into any results file, doc, or the UI** — every saved number
comes from an executed run on real data.
