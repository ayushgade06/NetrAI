function results = eval_quality(opts)
%EVAL_QUALITY  Validate the trained quality classifier; save REAL metrics.
%   results = eval_quality() evaluates the trained model on a held-out synthetic
%   set (degradations generated from the VAL split, disjoint from training's
%   TRAIN split) and on an investigator-selected naturally-poor set, and saves
%   every number - computed from actual runs - to validation/results_quality.mat.
%
%   ABSOLUTE RULE: every value saved here comes from an executed run. If the
%   trainset/model/splits are missing, this ERRORS and saves nothing rather than
%   writing placeholder numbers.
%
%   Metrics saved (per the Phase 3 brief):
%     confusion         3x3 confusion matrix (rows true, cols predicted)
%     classOrder        ["Good","Borderline","Ungradeable"]
%     precision/recall/f1  per-class
%     accuracy          overall
%     falseRejectRate   fraction of true-Good misclassified as not-Good
%                       (THROUGHPUT-CRITICAL: how often the gate rejects a fine
%                        image)
%     naturalRejectRate one-class rejection rate on the naturally-poor set
%                       (investigator-selected -> selection bias; see docs)
%     featureImportance if the chosen model exposes it (bagged trees do)
%     trainsetInfo      the exact size/composition actually used
%
%   opts (name-value):
%     'ModelFile'   models/quality_clf.mat
%     'SplitsFile'  validation/splits.mat
%     'NaturalList' validation/natural_poor_quality.txt
%     'OutFile'     validation/results_quality.mat
%     'Seed'        base seed for the eval degradations (default 424242)

    arguments
        opts.ModelFile   (1,:) char = defaultPath('models','quality_clf.mat')
        opts.SplitsFile  (1,:) char = defaultPath('validation','splits.mat')
        opts.NaturalList (1,:) char = defaultPath('validation','natural_poor_quality.txt')
        opts.OutFile     (1,:) char = defaultPath('validation','results_quality.mat')
        opts.Seed        (1,1) double = 424242
    end

    cfg = netra.loadConfig();

    if ~isfile(opts.ModelFile)
        error('NETRA:quality:noModel', ...
            'Model not found: %s. Run training/train_quality first.', opts.ModelFile);
    end
    M = load(opts.ModelFile); qmodel = M.qmodel;

    if ~isfile(opts.SplitsFile)
        error('NETRA:quality:noSplits', ...
            'Splits not found: %s. Run tools/freezeSplits first.', opts.SplitsFile);
    end
    S = load(opts.SplitsFile);
    valPaths = resolveSplit(S, 'val');
    if isempty(valPaths)
        error('NETRA:quality:emptyVal', 'VAL split is empty in %s.', opts.SplitsFile);
    end

    classOrder = ["Good","Borderline","Ungradeable"];

    % --- build a held-out synthetic eval set from the VAL split ----------
    [Xv, yv] = degradeSet(valPaths, cfg, opts.Seed);
    yhat = predictClass(qmodel, Xv);

    confusion = confMat(yv, yhat, classOrder);
    [precision, recall, f1] = prf(confusion);
    accuracy = sum(diag(confusion)) / max(1, sum(confusion(:)));

    % false rejection rate on clean (true-Good) images
    isGood = yv == "Good";
    if any(isGood)
        falseRejectRate = mean(yhat(isGood) ~= "Good");
    else
        falseRejectRate = NaN;
    end

    % --- naturally-poor one-class rejection rate -------------------------
    naturalRejectRate = NaN; nNatural = 0;
    if isfile(opts.NaturalList)
        natPaths = readList(opts.NaturalList);
        [Xn, ~, nNatural] = featuresFor(natPaths, cfg);
        if nNatural > 0
            yn = predictClass(qmodel, Xn);
            naturalRejectRate = mean(yn ~= "Good");   % rejected = not Good
        end
    end

    % --- feature importance (if exposed) --------------------------------
    featureImportance = [];
    try
        if ismember(qmodel.modelType, "bagged-trees")
            featureImportance = predictorImportance(qmodel.model);
        end
    catch
        featureImportance = [];
    end

    % --- trainset composition actually used -----------------------------
    trainsetInfo = struct('note','trainset not loaded here');
    tf = defaultPath('training','quality_trainset.mat');
    if isfile(tf)
        T = load(tf);
        trainsetInfo = struct( ...
            'nSamples', numel(T.labels), ...
            'nSources', numel(unique(T.srcId)), ...
            'good',        sum(T.labels=="Good"), ...
            'borderline',  sum(T.labels=="Borderline"), ...
            'ungradeable', sum(T.labels=="Ungradeable"));
    end

    results = struct();
    results.confusion         = confusion;
    results.classOrder        = classOrder;
    results.precision         = precision;
    results.recall            = recall;
    results.f1                = f1;
    results.accuracy          = accuracy;
    results.falseRejectRate   = falseRejectRate;
    results.naturalRejectRate = naturalRejectRate;
    results.nNatural          = nNatural;
    results.featureNames      = netra.quality.featureNames();
    results.featureImportance = featureImportance;
    results.trainsetInfo      = trainsetInfo;
    results.modelType         = qmodel.modelType;
    results.cvAccuracy        = qmodel.cvAccuracy;
    results.evaluatedAt       = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
    results.naturalCaveat     = ['Naturally-poor set is investigator-selected ' ...
        'and subject to selection bias; reported as a one-class rejection rate ' ...
        'only, NOT a false-positive rate against invented labels.'];

    ensureDir(opts.OutFile);
    save(opts.OutFile, '-struct', 'results', '-v7');

    fprintf('eval_quality: accuracy %.4f, falseRejectRate %.4f -> %s\n', ...
        accuracy, falseRejectRate, opts.OutFile);
    disp(array2table(confusion, 'VariableNames', cellstr(classOrder), ...
        'RowNames', cellstr(classOrder)));
end

% ========================================================================
function [X, y] = degradeSet(paths, cfg, seed)
%DEGRADESET  Same degradation recipe as make_degradations, applied to VAL imgs.
    types = ["blur","underexposed","overexposed","partialFOV","haze","random"];
    sev = [0.3 0.6 0.9];
    rows = {}; labs = strings(0,1);
    for i = 1:numel(paths)
        try
            cr = netra.io.loadImage(paths{i}, cfg); img = cr.img.raw;
        catch, continue; end
        rows{end+1} = featOf(img, cfg); labs(end+1,1) = "Good"; %#ok<AGROW>
        for t = 1:numel(types)
            for s = 1:numel(sev)
                d = netra.io.simulateFieldCapture(img, types(t), sev(s), seed+i*100+t*10+s);
                rows{end+1} = featOf(d, cfg); %#ok<AGROW>
                labs(end+1,1) = evalLabel(types(t), sev(s)); %#ok<AGROW>
            end
        end
    end
    X = cell2mat(rows(:)); y = labs;
end

function lab = evalLabel(type, sev)
%EVALLABEL  Mirror make_degradations>labelFor exactly (same assumption).
    if sev <= 0.45
        lab = "Borderline";
    elseif sev >= 0.75
        lab = "Ungradeable";
    else
        switch lower(type)
            case {"overexposed","underexposed","partialfov"}, lab = "Ungradeable";
            otherwise, lab = "Borderline";
        end
    end
end

function [X, paths, n] = featuresFor(paths, cfg)
    rows = {}; n = 0;
    for i = 1:numel(paths)
        try
            cr = netra.io.loadImage(paths{i}, cfg); img = cr.img.raw;
        catch, continue; end
        rows{end+1} = featOf(img, cfg); n = n + 1; %#ok<AGROW>
    end
    if n > 0, X = cell2mat(rows(:)); else, X = zeros(0,8); end
end

function f = featOf(img, cfg)
    try
        [mask, m] = netra.preproc.fovMask(img, cfg);
        c = cfg; c.qualityFovCompleteness = m.completeness;
        f = netra.quality.extractFeatures(img, mask, c);
    catch
        f = [0 0 0 0 1 0 0 0];
    end
end

function yhat = predictClass(qmodel, X)
    sig = qmodel.sigma; sig(sig==0) = 1;
    Xn = (X - qmodel.mu) ./ sig;
    yhat = string(predict(qmodel.model, Xn));
end

function C = confMat(ytrue, ypred, order)
    k = numel(order); C = zeros(k);
    for a = 1:k
        for b = 1:k
            C(a,b) = sum(ytrue==order(a) & ypred==order(b));
        end
    end
end

function [p, r, f1] = prf(C)
    k = size(C,1); p = nan(1,k); r = nan(1,k); f1 = nan(1,k);
    for i = 1:k
        tp = C(i,i); fp = sum(C(:,i)) - tp; fn = sum(C(i,:)) - tp;
        if tp+fp > 0, p(i) = tp/(tp+fp); else, p(i) = 0; end
        if tp+fn > 0, r(i) = tp/(tp+fn); else, r(i) = 0; end
        if p(i)+r(i) > 0, f1(i) = 2*p(i)*r(i)/(p(i)+r(i)); else, f1(i) = 0; end
    end
end

function paths = resolveSplit(S, which)
    paths = {}; cand = {};
    if isfield(S,'splits') && isfield(S.splits, which), cand = S.splits.(which);
    elseif isfield(S, which), cand = S.(which); end
    if isstruct(cand) && isfield(cand,'paths'), cand = cand.paths; end
    if isstring(cand) || ischar(cand), cand = cellstr(cand); end
    if iscell(cand), paths = cand(:)'; end
end

function lines = readList(f)
    txt = string(splitlines(fileread(f)));
    txt = strtrim(txt); txt = txt(strlength(txt) > 0);
    txt = txt(~startsWith(txt, "#"));
    lines = cellstr(txt);
end

function ensureDir(f)
    d = fileparts(f); if ~isempty(d) && ~isfolder(d), mkdir(d); end
end

function p = defaultPath(varargin)
    here = fileparts(mfilename('fullpath')); root = fileparts(here);
    p = fullfile(root, varargin{:});
end
