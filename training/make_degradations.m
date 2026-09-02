function info = make_degradations(opts)
%MAKE_DEGRADATIONS  Build the quality training set from clean APTOS TRAIN images.
%   info = make_degradations() reads the TRAIN split from validation/splits.mat,
%   and for each source image emits:
%     * 1 undegraded copy                        -> label "Good"
%     * 6 degradation types x 3 severity levels  -> label by severity/type
%   using Phase 2's netra.io.simulateFieldCapture as the degradation engine.
%   It extracts the eight quality features (netra.quality.extractFeatures) for
%   every sample and saves FEATURES ONLY (never images) to
%   training/quality_trainset.mat, with the source image id, degradation type,
%   severity, and label, so the split is reproducible and source-disjoint.
%
%   opts (name-value, all optional):
%     'SplitsFile'  path to validation/splits.mat        (default: repo path)
%     'OutFile'     path to write the trainset            (default: repo path)
%     'MaxImages'   cap on source images (0 = all)        (default: 0)
%     'Seed'        base RNG seed for degradation           (default: 26038)
%
%   SEVERITY-TO-LABEL MAPPING (a modelling assumption, NOT ground truth - see
%   docs/quality_method.md). Per-type, per the Phase 3 brief:
%     severity 0.2-0.4 -> Borderline
%     severity 0.5-0.7 -> Borderline or Ungradeable, per type (see labelFor)
%     severity 0.8-1.0 -> Ungradeable
%
%   REPRODUCIBILITY: the same splits.mat + Seed produce identical features.
%   SOURCE-DISJOINT: only TRAIN images are read; val/test/quarantine are never
%   touched (guarded by netra.io.assertNotQuarantined inside loadImage).

    arguments
        opts.SplitsFile (1,:) char = defaultPath('validation','splits.mat')
        opts.OutFile    (1,:) char = defaultPath('training','quality_trainset.mat')
        opts.MaxImages  (1,1) double = 0
        opts.Seed       (1,1) double = 26038
    end

    cfg = netra.loadConfig();

    if ~isfile(opts.SplitsFile)
        error('NETRA:quality:noSplits', ...
            ['Splits not found: %s. Run tools/freezeSplits after placing APTOS ' ...
             'under datasets/. Training cannot proceed without a TRAIN split.'], ...
            opts.SplitsFile);
    end
    S = load(opts.SplitsFile);
    trainPaths = resolveTrainPaths(S);
    if isempty(trainPaths)
        error('NETRA:quality:emptyTrain', ...
            'The TRAIN split in %s is empty; nothing to degrade.', opts.SplitsFile);
    end
    if opts.MaxImages > 0 && numel(trainPaths) > opts.MaxImages
        trainPaths = trainPaths(1:opts.MaxImages);
    end

    types = ["blur","underexposed","overexposed","partialFOV","haze","random"];
    sevLevels = [0.3, 0.6, 0.9];             % one representative per band

    % Pre-count for preallocation: (1 clean + 6 types * 3 severities) per image.
    perImage = 1 + numel(types)*numel(sevLevels);
    nTotal = numel(trainPaths) * perImage;

    X        = nan(nTotal, 8);
    labels   = strings(nTotal,1);
    srcId    = strings(nTotal,1);
    degType  = strings(nTotal,1);
    severity = nan(nTotal,1);

    row = 0;
    for i = 1:numel(trainPaths)
        p = trainPaths{i};
        [~, stem] = fileparts(p);
        try
            cr = netra.io.loadImage(p, cfg);      % honours quarantine guard
            imgClean = cr.img.raw;
        catch ME
            warning('NETRA:quality:skipImage', ...
                'Skipping %s: %s', stem, ME.message);
            continue;
        end

        % clean copy -> Good
        row = row + 1;
        [X(row,:)] = featOf(imgClean, cfg);
        labels(row) = "Good"; srcId(row) = string(stem);
        degType(row) = "none"; severity(row) = 0;

        for t = 1:numel(types)
            for s = 1:numel(sevLevels)
                sev = sevLevels(s);
                seed = opts.Seed + i*1000 + t*10 + s;
                degImg = netra.io.simulateFieldCapture(imgClean, types(t), sev, seed);
                row = row + 1;
                X(row,:) = featOf(degImg, cfg);
                labels(row)  = labelFor(types(t), sev);
                srcId(row)   = string(stem);
                degType(row) = types(t);
                severity(row)= sev;
            end
        end
    end

    % Trim unused preallocated rows (skipped images).
    keep = 1:row;
    X = X(keep,:); labels = labels(keep); srcId = srcId(keep);
    degType = degType(keep); severity = severity(keep);

    featureNames = netra.quality.featureNames();
    savedAt = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));  %#ok<NASGU>

    info = struct();
    info.nSamples   = row;
    info.nSources   = numel(unique(srcId));
    info.classCounts = countClasses(labels);
    info.featureNames = featureNames;

    ensureDir(opts.OutFile);
    save(opts.OutFile, 'X', 'labels', 'srcId', 'degType', 'severity', ...
        'featureNames', 'savedAt', '-v7');

    fprintf('make_degradations: %d samples from %d source images -> %s\n', ...
        row, info.nSources, opts.OutFile);
    disp(info.classCounts);
end

% ========================================================================
function f = featOf(img, cfg)
%FEATOF  FOV-mask an image and extract the eight features (all-safe on error).
    try
        [mask, m] = netra.preproc.fovMask(img, cfg);
        c = cfg; c.qualityFovCompleteness = m.completeness;
        f = netra.quality.extractFeatures(img, mask, c);
    catch
        f = [0 0 0 0 1 0 0 0];               % safe vector -> Ungradeable side
    end
end

function lab = labelFor(type, sev)
%LABELFOR  Severity-to-label mapping. DOCUMENTED ASSUMPTION (quality_method.md).
%   0.2-0.4 Borderline; 0.8-1.0 Ungradeable. In the 0.5-0.7 band, exposure and
%   FOV failures are treated as harder (Ungradeable) than blur/haze at the same
%   severity, because a blown-out or clipped field is less recoverable than mild
%   softness. This is a modelling choice, not clinical ground truth.
    if sev <= 0.45
        lab = "Borderline";
    elseif sev >= 0.75
        lab = "Ungradeable";
    else
        switch lower(type)
            case {"overexposed","underexposed","partialfov"}
                lab = "Ungradeable";
            otherwise                         % blur, haze, random
                lab = "Borderline";
        end
    end
end

function c = countClasses(labels)
    u = ["Good","Borderline","Ungradeable"];
    n = arrayfun(@(x) sum(labels == x), u);
    c = table(u(:), n(:), 'VariableNames', {'Class','Count'});
end

function paths = resolveTrainPaths(S)
%RESOLVETRAINPATHS  Pull the TRAIN image path list out of a splits struct.
%   freezeSplits' exact field layout may vary; accept the common shapes.
    paths = {};
    cand = {};
    if isfield(S,'splits') && isstruct(S.splits) && isfield(S.splits,'train')
        cand = S.splits.train;
    elseif isfield(S,'train')
        cand = S.train;
    end
    if isstruct(cand) && isfield(cand,'paths'), cand = cand.paths; end
    if isstring(cand) || ischar(cand), cand = cellstr(cand); end
    if iscell(cand), paths = cand(:)'; end
end

function ensureDir(f)
    d = fileparts(f);
    if ~isempty(d) && ~isfolder(d), mkdir(d); end
end

function p = defaultPath(varargin)
    here = fileparts(mfilename('fullpath'));   % training/
    root = fileparts(here);
    p = fullfile(root, varargin{:});
end
