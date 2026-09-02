# models/ — PLACEHOLDER (Phase 0)

There are **no real models** in NETRA Phase 0. No networks, no weights, no
training artefacts. `netra.loadModels` returns a struct with
`isPlaceholder = true` and works whether or not any `.mat` file is present
here.

## Creating the optional placeholder .mat

The pipeline does **not** require a `.mat` file to run. If you want one on disk
(so later phases have a drop-in slot), create it once from MATLAB — the
placeholder must load without error and be obviously not a real model:

```matlab
placeholder = struct( ...
    'isPlaceholder', true, ...
    'note', 'PHASE 0 PLACEHOLDER - not a real network. Replaced in Phase 7.', ...
    'createdBy', 'NETRA Phase 0 scaffold');
save(fullfile('models','dr_grader_placeholder.mat'), '-struct', 'placeholder');
```

`netra.loadModels` will pick it up automatically (it globs `models/*.mat`),
record its filename, and still report `isPlaceholder = true`.

## Later phases

- Phase 7 replaces this with the real DR-grading network.
- Phase 8 adds any Grad-CAM helper artefacts.

The `netra.loadModels` **signature is frozen**; only the `.mat` contents change.
