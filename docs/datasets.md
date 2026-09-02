# NETRA Datasets

This file records **only what was actually verified on disk** for this
repository at the time of Phase 2. Nothing here is assumed or fabricated.

## What is present on disk (verified 2026-09-02)

| Dataset | Present? | Location scanned | Images found | Labels found |
|---------|----------|------------------|--------------|--------------|
| APTOS 2019 | **No** | `datasets/aptos2019/` | 0 | 0 |
| IDRiD | **No** | `datasets/idrid/` | 0 | 0 |
| DRIVE | **No** | `datasets/drive/` | 0 | 0 |
| Messidor-2 | **No** | `datasets/messidor2/` | 0 | 0 |

The only image in the repository is `data/demo/sample01.jpg` — a **16×16
single-channel placeholder JPEG**, not a real fundus. It exists so the schema
factory and the Phase 0/1 tests have a readable file; it is too small and not
coloured, so it is **not** used for FOV masking or plausibility verification.

Because no real datasets are on disk, the manifest written by
`tools/registerDatasets` will record all four as **absent**. This is correct
and intentional — `registerDatasets` never invents a manifest.

## How to populate the datasets

Place each dataset under `datasets/<name>/` (create the `datasets/` folder at
the project root — it is git-ignored). Then, from a MATLAB session:

```matlab
startup_netra
registerDatasets        % scans datasets/, writes data/dataset_manifest.mat
freezeSplits            % APTOS 70/15/15 patient-disjoint, seed 26038
quarantineMessidor('datasets/messidor2')   % move Messidor-2 into quarantine
```

`registerDatasets(rootsStruct)` accepts explicit paths if you keep the data
elsewhere:

```matlab
roots = struct('aptos','D:\data\aptos', 'messidor2','D:\data\messidor2');
registerDatasets(roots);
```

## Source URLs (for the team to download — NOT auto-downloaded)

The tools download nothing. Obtain the datasets from their official sources:

- **APTOS 2019 Blindness Detection** — Kaggle competition
  `aptos2019-blindness-detection`. Per-image ICDR grade 0–4 in `train.csv`
  (columns `id_code`, `diagnosis`). One image per patient.
- **IDRiD (Indian Diabetic Retinopathy Image Dataset)** — IEEE DataPort /
  the IDRiD grand-challenge site. Pixel-level lesion masks + image-level grades.
- **DRIVE (Digital Retinal Images for Vessel Extraction)** — the DRIVE
  challenge site. Vessel-segmentation ground-truth masks.
- **Messidor-2** — ADCIS / the Messidor program site.

> Record the exact download URL and version you used in this table when you
> place the data, so the provenance is auditable. Left as a placeholder here
> because no data was downloaded in this environment.

## Label formats

- **APTOS**: `train.csv` — `id_code` (image stem), `diagnosis` (ICDR 0–4).
- **IDRiD**: per-task CSVs for grading; per-image mask PNGs for segmentation.
- **DRIVE**: `.gif`/`.tif` vessel masks paired to each image.
- **Messidor-2**: per-image grade table (spreadsheet).

`freezeSplits` reads APTOS grades by matching each image stem against the
`id_code` column of a label CSV in the APTOS root; if no labels are found it
falls back to an unstratified split and records `stratified = false`.

## Split policy

- **APTOS only** is split into train/val/test at **70 / 15 / 15**.
- Splits are **patient-disjoint** (APTOS is one image per patient, so this is
  image-disjoint in practice; the code groups by a patient key regardless).
- **Seed: `26038`** (the SIH problem-statement number), recorded inside
  `validation/splits.mat`.
- `freezeSplits` **refuses to overwrite** an existing `validation/splits.mat`
  unless called as `freezeSplits(true)`, and warns that regenerating splits
  invalidates every previously reported metric.

## Quarantine policy

- **Messidor-2 is the held-out external test set.** It is moved (or symlinked)
  into `data/quarantine/messidor2/` by `tools/quarantineMessidor`.
- `netra.io.assertNotQuarantined(path)` throws `NETRA:io:quarantined` for any
  path inside `data/quarantine/`. `loadImage` and `batchIngest` both call it,
  so no training/tuning/ingest code can read the held-out set by accident.
- Messidor-2 is unlocked **exactly once, in Phase 10**, for the final external
  evaluation. See `data/quarantine/QUARANTINE_NOTICE.md`.
