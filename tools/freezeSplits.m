function splits = freezeSplits(force)
%FREEZESPLITS  Create frozen patient-disjoint APTOS train/val/test splits.
%   splits = freezeSplits() reads the APTOS manifest (from
%   data/dataset_manifest.mat, written by registerDatasets) and creates
%   stratified 70/15/15 train/val/test splits using a FIXED seed, then writes
%   validation/splits.mat. It REFUSES to overwrite an existing splits.mat.
%
%   splits = freezeSplits(true) forces regeneration, printing a warning that
%   this INVALIDATES every previously reported metric (any number computed
%   against the old test set is no longer comparable).
%
%   APTOS ships one image per patient (its labels are per-image with unique
%   ids), so "patient-disjoint" reduces to image-disjoint here; the code still
%   groups by a patient key so a future multi-image-per-patient dataset stays
%   correct. Stratification is by ICDR grade when a label file is found; if no
%   labels are found, an unstratified random split is used and the output
%   records stratified=false.
%
%   The output struct records the seed, the split fractions, and the id lists,
%   so the split is fully reproducible and auditable.

    arguments
        force (1,1) logical = false
    end

    here = fileparts(mfilename('fullpath'));   % tools/
    root = fileparts(here);                    % project root
    outDir  = fullfile(root, 'validation');
    outPath = fullfile(outDir, 'splits.mat');

    if isfile(outPath) && ~force
        error('NETRA:splits:exists', ...
            ['validation/splits.mat already exists. Refusing to overwrite.\n' ...
             'Regenerating splits INVALIDATES all previously reported metrics.\n' ...
             'Call freezeSplits(true) to force.']);
    end
    if isfile(outPath) && force
        warning('NETRA:splits:overwrite', ...
            ['OVERWRITING validation/splits.mat. Every metric previously ' ...
             'reported against the old test set is now INVALID and must be ' ...
             'recomputed against these new splits.']);
    end

    manPath = fullfile(root, 'data', 'dataset_manifest.mat');
    if ~isfile(manPath)
        error('NETRA:splits:noManifest', ...
            'No data/dataset_manifest.mat. Run registerDatasets first.');
    end
    S = load(manPath, 'manifest');
    if ~isfield(S,'manifest') || ~isfield(S.manifest,'aptos') || ~S.manifest.aptos.present
        error('NETRA:splits:noAptos', ...
            'APTOS is absent from the manifest; cannot create splits.');
    end
    aptos = S.manifest.aptos;

    SEED = 26038;   % recorded in the output so the split is reproducible

    % Build (id, grade, patientKey) rows. id = image relative path stem.
    ids = aptos.images;
    n = numel(ids);
    grades = nan(n,1);
    [grades, stratified] = tryReadGrades(aptos, ids);
    patientKey = ids;   % one image per patient in APTOS -> key == id stem

    % Deterministic stratified split.
    rs = RandStream('mt19937ar', 'Seed', SEED);
    [trainIdx, valIdx, testIdx] = stratSplit(grades, patientKey, [0.70 0.15 0.15], rs, stratified);

    splits = struct();
    splits.dataset      = "APTOS2019";
    splits.seed         = SEED;
    splits.fractions    = [0.70 0.15 0.15];
    splits.stratified   = stratified;
    splits.total        = n;
    splits.train        = ids(trainIdx);
    splits.val          = ids(valIdx);
    splits.test         = ids(testIdx);
    splits.trainGrades  = grades(trainIdx);
    splits.valGrades    = grades(valIdx);
    splits.testGrades   = grades(testIdx);
    splits.createdNote  = "Frozen split. Do not regenerate without freezeSplits(true).";

    if ~isfolder(outDir), mkdir(outDir); end
    save(outPath, 'splits');
    fprintf('freezeSplits: %d images -> train %d / val %d / test %d (seed %d, stratified=%d)\n', ...
        n, numel(trainIdx), numel(valIdx), numel(testIdx), SEED, stratified);
    fprintf('freezeSplits: wrote %s\n', outPath);
end

% ------------------------------------------------------------------------
function [grades, stratified] = tryReadGrades(aptos, ids)
%TRYREADGRADES  Best-effort read of per-image ICDR grades from a label csv.
    grades = nan(numel(ids),1);
    stratified = false;
    if isempty(aptos.labelFiles), return; end
    % Find a csv with columns that look like id_code + diagnosis (APTOS format).
    for k = 1:numel(aptos.labelFiles)
        lf = fullfile(char(aptos.root), char(aptos.labelFiles(k)));
        [~,~,e] = fileparts(lf);
        if ~strcmpi(e, '.csv'), continue; end
        try
            T = readtable(lf, 'TextType','string');
        catch
            continue;
        end
        vn = lower(string(T.Properties.VariableNames));
        idCol = find(contains(vn,"id"), 1);
        gCol  = find(contains(vn,"diagn") | contains(vn,"grade") | contains(vn,"level"), 1);
        if isempty(idCol) || isempty(gCol), continue; end
        labIds = string(T{:, idCol});
        labG   = double(T{:, gCol});
        % Match by stem (ignore folder + extension).
        for j = 1:numel(ids)
            [~, stem] = fileparts(char(ids(j)));
            hit = find(labIds == string(stem), 1);
            if ~isempty(hit), grades(j) = labG(hit); end
        end
        if any(~isnan(grades))
            stratified = true;
            return;
        end
    end
end

function [trIdx, vaIdx, teIdx] = stratSplit(grades, patientKey, frac, rs, stratified)
%STRATSPLIT  Patient-disjoint split, stratified by grade when available.
    uKeys = unique(patientKey, 'stable');
    % One grade per patient key (first occurrence).
    keyGrade = nan(numel(uKeys),1);
    for i = 1:numel(uKeys)
        j = find(patientKey == uKeys(i), 1);
        keyGrade(i) = grades(j);
    end

    trKeys = strings(0,1); vaKeys = strings(0,1); teKeys = strings(0,1);
    if stratified
        classes = unique(keyGrade(~isnan(keyGrade)));
    else
        classes = NaN;   % single pseudo-class -> plain random split
    end
    for c = reshape(classes,1,[])
        if isnan(c)
            sel = true(numel(uKeys),1);
        else
            sel = keyGrade == c;
        end
        ck = uKeys(sel);
        p = randperm(rs, numel(ck));
        ck = ck(p);
        nC = numel(ck);
        nTr = floor(frac(1)*nC);
        nVa = floor(frac(2)*nC);
        trKeys = [trKeys; ck(1:nTr)];               %#ok<AGROW>
        vaKeys = [vaKeys; ck(nTr+1:nTr+nVa)];       %#ok<AGROW>
        teKeys = [teKeys; ck(nTr+nVa+1:end)];       %#ok<AGROW>
    end

    trIdx = find(ismember(patientKey, trKeys));
    vaIdx = find(ismember(patientKey, vaKeys));
    teIdx = find(ismember(patientKey, teKeys));
end
