function cr = classify(cr, cfg, models)
%CLASSIFY  DR severity grading (ICDR 0-4).  [Phase 7 / Track B]
%   cr = netra.grading.classify(cr, cfg, models) writes cr.grade.* plus
%   cr.provenance.grading.
%
%   TWO PATHS, selected by whether a trained CNN is present in `models`:
%
%   PATH A/B (models.grader present): run the network's predict, apply the
%     fitted temperature, tune-derived referable threshold, and the rule-based
%     cross-check. provenance.grading = "REAL". [NOT ACTIVE in this environment.]
%
%   PATH C (no trained CNN - THIS ENVIRONMENT): no APTOS on disk, no MATLAB/GPU
%     to train, no splits.mat. Per the Track B fallback policy we do NOT
%     fabricate a CNN or invent probabilities. The grade IS the rule-based
%     icdrRule estimate over Track A's lesion counts.
%       - grade.icdr        = ruleEstimate (or NaN if lesion data absent)
%       - grade.probs       = NaN(1,5)  (no distribution without a model)
%       - grade.referableProb / confidence = NaN
%       - grade.disagreement = false    (nothing to disagree with)
%       - provenance.grading = "RULE_BASED_NO_CNN"
%     No grading metrics are produced or saved on this path.
%
%   CONTRACT (unchanged): one caseRecord in/out; may ADD fields, never delete or
%   rename; never writes to disk; sets cr.provenance.grading; timing set by
%   runPipeline.

    arguments
        cr     (1,1) struct
        cfg    (1,1) struct
        models (1,1) struct
    end

    hasNet = isfield(models, 'grader') && ~isempty(models.grader) ...
             && (~isfield(models, 'isPlaceholder') || ~models.isPlaceholder);

    ruleEst = netra.grading.icdrRule(cr.lesions, cfg);

    if hasNet
        cr = gradeWithCnn(cr, cfg, models, ruleEst);   % path A/B
    else
        cr = gradeRuleBased(cr, cfg, ruleEst);         % path C
    end
end

% ------------------------------------------------------------------------
function cr = gradeRuleBased(cr, cfg, ruleEst)
%GRADERULEBASED  Fallback Path C: rule-based grade, no CNN, no fabricated probs.
    cr.grade.ruleEstimate = ruleEst;

    if isnan(ruleEst)
        % Track A lesion data unavailable - cannot grade at all.
        cr.grade.icdr    = NaN;
        cr.grade.label   = "Not graded (lesion data unavailable)";
    else
        cr.grade.icdr    = ruleEst;
        cr.grade.label   = netra.ui.formatGrade(ruleEst);
    end

    cr.grade.probs         = nan(1,5);   % no model -> no distribution
    cr.grade.referableProb = NaN;
    cr.grade.confidence    = NaN;
    cr.grade.disagreement  = false;      % nothing to cross-check against

    cr.provenance.grading  = "RULE_BASED_NO_CNN";
end

% ------------------------------------------------------------------------
function cr = gradeWithCnn(cr, cfg, models, ruleEst)
%GRADEWITHCNN  Path A/B: real CNN grading. INACTIVE here (no trained net).
%   Left as the documented integration point for when a model is imported
%   (native MATLAB training or ONNX import). Kept minimal deliberately - it is
%   NOT exercised in this environment and carries no fabricated numbers.
    modelInput = cr.img.modelInput;
    if isempty(modelInput)
        % Defensive: Track A did not produce a CNN input - resize from enhanced.
        modelInput = defensiveModelInput(cr, cfg);
    end

    logits = predict(models.grader, modelInput);          %#ok<NASGU> (real net)
    probs  = netra.grading.applyTemperature(logits, cfg.thresholds.grading.temperature);

    [~, argmax] = max(probs);
    cr.grade.icdr          = argmax - 1;                  % classOrder 0..4
    cr.grade.probs         = probs;
    cr.grade.referableProb = referableProbability(cr, cfg, probs, models);
    cr.grade.confidence    = max(probs);
    cr.grade.ruleEstimate  = ruleEst;
    cr.grade.disagreement  = isfinite(ruleEst) && ...
        abs(cr.grade.icdr - ruleEst) >= cfg.thresholds.grading.disagreementLevels;
    cr.grade.label         = netra.ui.formatGrade(cr.grade.icdr);
    cr.provenance.grading  = "REAL";
end

function p = referableProbability(cr, cfg, probs, models)
%REFERABLEPROBABILITY  Fusion probability if enabled and available, else the
%   plain P(grade>=2) from the calibrated CNN distribution.
    if cfg.thresholds.grading.useFusion && isfield(models, 'fusion') ...
            && ~isempty(models.fusion)
        featVec = fusionFeatures(cr, probs);
        p = netra.grading.fuseEvidence(featVec, models.fusion, cfg);
    else
        p = sum(probs(3:5));
    end
end

function mi = defensiveModelInput(cr, cfg)
%DEFENSIVEMODELINPUT  Resize enhanced image to the model input size if Track A
%   did not populate cr.img.modelInput. Logged by the caller path.
    sz = cfg.thresholds.grading.modelInputSize(:).';
    src = cr.img.enhanced;
    if isempty(src)
        error('NETRA:grading:noInput', ...
            'No modelInput and no enhanced image to resize from.');
    end
    mi = single(imresize(src, sz(1:2))) / 255;
end

function f = fusionFeatures(cr, probs) %#ok<INUSD>
%FUSIONFEATURES  Assemble the fusion feature vector (section 4.6). Defined for
%   the path-A/B integration; unused on path C.
    l = cr.lesions;
    f = [probs(:).', ...
         log1p(l.MA.count), log1p(l.HE.count), exFraction(cr), ...
         nnz(anyQuadrant(l)), double(l.MA.nearMacula>0 || l.HE.nearMacula>0), ...
         cr.quality.score];
end

function frac = exFraction(cr)
    frac = 0;
    if isfield(cr.lesions,'EX') && isfield(cr.lesions.EX,'totalArea')
        n = numel(cr.img.enhanced(:,:,1));
        if n > 0, frac = cr.lesions.EX.totalArea / n; end
    end
end

function q = anyQuadrant(l)
    q = false(1,4);
    for t = ["MA","HE","EX","CWS"]
        if isfield(l, t) && isfield(l.(t), 'perQuadrant')
            q = q | (l.(t).perQuadrant(:).' > 0);
        end
    end
end
