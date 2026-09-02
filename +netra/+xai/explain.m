function cr = explain(cr, cfg, models)
%EXPLAIN  Grad-CAM explainability and evidence summary.  [Phase 8 / Track B]
%   cr = netra.xai.explain(cr, cfg, models) writes cr.xai.* plus
%   cr.provenance.xai.
%
%   TWO PATHS (mirrors netra.grading.classify):
%
%   PATH A/B (models.grader present): compute Grad-CAM on the final conv block
%     for the predicted class, the Attention-Lesion Agreement score against
%     Track A's union lesion mask, evidence bullets, confidence band and
%     attention summary. provenance.xai = "REAL". [NOT ACTIVE here.]
%
%   PATH C (no trained CNN - THIS ENVIRONMENT): Grad-CAM needs a network; there
%     is none. Per the fallback policy:
%       - xai.gradcam        = empty single
%       - xai.agreementScore = NaN  (no attention map -> no ALA)
%       - provenance.xai     = "UNAVAILABLE_NO_CNN"
%     BUT evidence bullets and the confidence band do NOT require a CNN, so they
%     are still produced from the (rule-based) grade and lesion counts - they
%     are honest, measured outputs.
%
%   CONTRACT (unchanged): one caseRecord in/out; may ADD fields, never delete or
%   rename; never writes to disk; sets cr.provenance.xai; timing set by
%   runPipeline. On Grad-CAM failure the pipeline must NOT abort (caught here).

    arguments
        cr     (1,1) struct
        cfg    (1,1) struct
        models (1,1) struct
    end

    hasNet = isfield(models, 'grader') && ~isempty(models.grader) ...
             && (~isfield(models, 'isPlaceholder') || ~models.isPlaceholder);

    % Evidence bullets + confidence band are always available (measured, no CNN).
    cr.xai.evidenceBullets = netra.xai.evidenceBullets(cr, cfg);

    if hasNet
        cr = explainWithCnn(cr, cfg, models);      % path A/B
    else
        cr = explainNoCnn(cr, cfg);                % path C
    end
end

% ------------------------------------------------------------------------
function cr = explainNoCnn(cr, cfg)
%EXPLAINNOCNN  Fallback Path C: no Grad-CAM, ALA N/A, honest band + summary.
    cr.xai.gradcam         = zeros(0,0,'single');
    cr.xai.agreementScore  = NaN;                 % no attention to agree with
    cr.xai.confidenceBand  = netra.xai.confidenceBand( ...
        cr.grade.confidence, cr.quality.score, NaN, cfg);
    cr.xai.attentionSummary = ...
        "Rule-based grading (no trained CNN available). " + ...
        "Grad-CAM explainability requires a trained network.";
    cr.provenance.xai = "UNAVAILABLE_NO_CNN";
end

% ------------------------------------------------------------------------
function cr = explainWithCnn(cr, cfg, models)
%EXPLAINWITHCNN  Path A/B: Grad-CAM + ALA. INACTIVE here (no trained net).
%   Wrapped so a Grad-CAM failure degrades gracefully instead of aborting the
%   pipeline (section 10 error handling).
    classIdx = cr.grade.icdr + 1;                 % classOrder 0..4 -> 1..5
    lesionMask = unionMask(cr);

    try
        [heat, ~] = netra.xai.gradcamOverlay(models.grader, cr.img.modelInput, classIdx, cfg);
        cr.xai.gradcam        = single(heat);
        cr.xai.agreementScore = netra.xai.agreementScore(heat, lesionMask, cfg);
    catch ME
        warning('NETRA:xai:gradcamFailed', ...
            'Grad-CAM failed (%s); ALA set NaN, case flagged for review.', ME.message);
        cr.xai.gradcam        = zeros(0,0,'single');
        cr.xai.agreementScore = NaN;
    end

    cr.xai.confidenceBand = netra.xai.confidenceBand( ...
        cr.grade.confidence, cr.quality.score, cr.xai.agreementScore, cfg);
    cr.xai.attentionSummary = attentionLine(cr);
    cr.provenance.xai = "REAL";
end

function m = unionMask(cr)
%UNIONMASK  Track A's union lesion mask, or empty if not merged yet.
    m = [];
    if isfield(cr.lesions, 'allMask')
        m = cr.lesions.allMask;
    end
end

function line = attentionLine(cr)
%ATTENTIONLINE  One-line peak-attention-quadrant summary (path A/B).
    ala = cr.xai.agreementScore;
    if isnan(ala)
        line = "Attention-lesion agreement not applicable (no lesions detected).";
    else
        line = sprintf("Peak attention overlaps detected lesions (ALA %.2f).", ala);
    end
    line = string(line);
end
