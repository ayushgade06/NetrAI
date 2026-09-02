function cr = assess(cr, cfg, models)
%ASSESS  Fundus image quality assessment and gating.  [Phase 3 - REAL]
%   cr = netra.quality.assess(cr, cfg)          (Phase 0 signature)
%   cr = netra.quality.assess(cr, cfg, models)  (Phase 3 extension)
%
%   Extracts eight FOV-masked features (netra.quality.extractFeatures),
%   classifies the image Good / Borderline / Ungradeable, computes a 0-100
%   composite score, and writes a specific failReason and recaptureAdvice.
%
%   CONTRACT:
%     - Exactly one caseRecord in, exactly one caseRecord out.
%     - May ADD fields; must never DELETE or RENAME a field it did not create.
%     - Never writes to disk.
%     - Sets cr.provenance.quality to "REAL", "RULE_BASED_FALLBACK", or "MOCK".
%     - cr.timing.quality is written by runPipeline, not here.
%
%   SIGNATURE EXTENSION (reported to the team): the Phase 0 contract was
%   assess(cr,cfg). This adds an optional third argument `models`. If omitted,
%   the quality model is loaded lazily and cached in a persistent, so runPipeline
%   and legacy two-arg callers both work. runPipeline is updated to pass models.
%
%   PATH SELECTION:
%     - A trained classifier (models.quality.model) present AND
%       cfg.thresholds.quality.useClassifier true -> trained path, provenance
%       "REAL". Hard overrides (classifyRuleBased) still apply on top.
%     - Otherwise -> rule-based path, provenance "RULE_BASED_FALLBACK", with a
%       one-time warning. The rule-based thresholds ARE a quality model; the UI
%       must label it as threshold-based, never as a trained model.
%
%   NO PIXELS: dashboard previews carry no raw image (cr.img.raw empty). There is
%   nothing to assess, so this leaves quality NaN/"" and tags provenance "MOCK"
%   (mirrors runPipeline's store stage), rather than inventing a score.

    arguments
        cr  (1,1) struct
        cfg (1,1) struct
        models struct = lazyModels()
    end

    % --- no pixels to assess (preview-only case) ------------------------
    img = cr.img.raw;
    if isempty(img)
        cr.provenance.quality = "MOCK";      % nothing measured; not a real read
        return;
    end

    % --- FOV mask: reuse Phase 2 if present, else compute ----------------
    fovComplete = NaN;
    if isfield(cr.img,'fovMask') && ~isempty(cr.img.fovMask) ...
            && isequal(size(cr.img.fovMask), size(img(:,:,1)))
        mask = cr.img.fovMask;
        % completeness isn't stored on cr; recompute cheaply for feature 6.
        [~, fm] = safeFovMask(img, cfg);
        if ~isempty(fm), fovComplete = fm.completeness; end
    else
        [mask, fm] = safeFovMask(img, cfg);
        if ~isempty(fm), fovComplete = fm.completeness; end
    end

    % --- features --------------------------------------------------------
    featCfg = cfg;
    featCfg.qualityFovCompleteness = fovComplete;   % prefer Phase 2 completeness
    [feat, detail] = netra.quality.extractFeatures(img, mask, featCfg);

    % --- classify: trained if available, else rule-based -----------------
    [useTrained, mdl] = trainedAvailable(models, cfg);

    if useTrained
        try
            [cls, conf] = predictTrained(mdl, feat);
            provenance = "REAL";
        catch
            [cls, conf] = netra.quality.classifyRuleBased(feat, cfg);
            provenance = "RULE_BASED_FALLBACK";
            warnOnce('NETRA:quality:predictFailed', ...
                'Quality model prediction failed; using rule-based fallback.');
        end
    else
        [cls, conf] = netra.quality.classifyRuleBased(feat, cfg);
        provenance = "RULE_BASED_FALLBACK";
        warnOnce('NETRA:quality:noModel', ...
            'Trained quality model unavailable; using rule-based fallback.');
    end

    % --- HARD OVERRIDES apply on every path -----------------------------
    % A FOV too incomplete, blown-out, blacked-out, or unmeasurable image is
    % Ungradeable regardless of what the trained model said.
    [hardCls, hardConf] = netra.quality.classifyRuleBased(feat, cfg);
    if hardCls == "Ungradeable" && cls ~= "Ungradeable"
        cls = "Ungradeable";
        conf = hardConf;
    end
    if detail.emptyFov || detail.substituted
        cls = "Ungradeable";
    end

    % --- composite score + human-facing text ----------------------------
    score = netra.quality.scoreComposite(feat, cfg);
    reason = netra.quality.failReason(feat, detail, cls, cfg);
    if cls == "Good"
        advice = "";
    else
        advice = netra.quality.recaptureAdvice(feat, detail, cfg);
    end

    % Empty FOV: score is meaningless -> force 0 per the error-handling spec.
    if detail.emptyFov
        score = 0;
    end

    % --- write cr.quality.* (schema-preserving; no new top-level fields) --
    cr.quality.score           = score;
    cr.quality.class           = cls;
    cr.quality.focus           = combineFocus(feat, cfg);       % 0..1 display
    cr.quality.illum           = feat(3);                        % illumUniformity
    cr.quality.fovCompleteness = feat(6);
    cr.quality.contrast        = combineContrast(feat, cfg);     % 0..1 display
    cr.quality.quadrantMeans   = detail.quadrantMeans;
    cr.quality.failReason      = reason;
    cr.quality.recaptureAdvice = advice;

    % Stash the raw feature vector + confidence for the UI "show all
    % measurements" panel WITHOUT adding a schema field: recaptureAdvice/fail
    % are strings, so we attach an extra struct on a documented, additive field
    % only if the schema allows. The schema is frozen, so we DO NOT add fields;
    % the UI recomputes features from the image via extractFeatures instead.
    %#ok<*NASGU>

    cr.provenance.quality = provenance;
end

% ========================================================================
function m = lazyModels()
%LAZYMODELS  Load models once and cache, for two-arg callers.
    persistent cached
    if isempty(cached)
        try
            cached = netra.loadModels();
        catch
            cached = struct('isPlaceholder', true);
        end
    end
    m = cached;
end

function [useTrained, mdl] = trainedAvailable(models, cfg)
%TRAINEDAVAILABLE  Decide whether a usable trained quality model is present.
    useTrained = false; mdl = [];
    q = cfg.thresholds.quality;
    if isfield(q,'useClassifier') && ~q.useClassifier
        return;                              % config forces the rule-based path
    end
    if isfield(models,'quality') && isstruct(models.quality) ...
            && isfield(models.quality,'model') && ~isempty(models.quality.model)
        mdl = models.quality;
        useTrained = true;
    end
end

function [cls, conf] = predictTrained(mdl, feat)
%PREDICTTRAINED  Normalise features with the model's params and predict.
    x = feat;
    if isfield(mdl,'mu') && isfield(mdl,'sigma')
        sig = mdl.sigma; sig(sig == 0) = 1;
        x = (feat - mdl.mu) ./ sig;
    end
    [label, scoreVec] = predict(mdl.model, x);
    cls = string(label);
    if isnumeric(scoreVec) && ~isempty(scoreVec)
        conf = max(0, min(1, max(scoreVec(:))));
    else
        conf = 0.75;
    end
end

function [mask, metrics] = safeFovMask(img, cfg)
%SAFEFOVMASK  fovMask that never throws; returns a full-frame mask on failure.
    try
        [mask, metrics] = netra.preproc.fovMask(img, cfg);
    catch
        mask = true(size(img,1), size(img,2));
        metrics = struct('completeness', 1);
    end
end

function f = combineFocus(feat, cfg)
%COMBINEFOCUS  0..1 display focus = mean of the two focus subscores.
    q = cfg.thresholds.quality;
    s1 = ratioUp(feat(1), q.focusLaplacianMin);
    s2 = ratioUp(feat(2), q.focusTenengradMin);
    f = mean([s1 s2]);
end

function c = combineContrast(feat, cfg)
%COMBINECONTRAST  0..1 display contrast = mean of the two contrast subscores.
    q = cfg.thresholds.quality;
    s1 = ratioUp(feat(7), q.contrastStdMin);
    s2 = ratioUp(feat(8), q.localContrastMin);
    c = mean([s1 s2]);
end

function r = ratioUp(v, thr)
    if thr <= 0, r = double(v > 0); return; end
    r = max(0, min(1, v / thr));
end

function warnOnce(id, msg)
%WARNONCE  Emit a given warning id at most once per MATLAB session.
    persistent seen
    if isempty(seen), seen = containers.Map('KeyType','char','ValueType','logical'); end
    if ~isKey(seen, id)
        warning(id, '%s', msg);
        seen(id) = true;
    end
end
