function reason = failReason(feat, detail, cls, cfg)
%FAILREASON  Specific, metric-named reason a fundus image is not Good.  [Phase 3]
%   reason = netra.quality.failReason(feat, detail, cls, cfg)
%
%   Returns "" when cls == "Good". Otherwise names the SINGLE most severe
%   failing metric, its measured value, and its threshold, in one clinician-
%   readable sentence, e.g.:
%     "Focus score 0.31 (minimum 0.55). Image is blurred across the field."
%     "Dark pixel fraction 0.62 (maximum 0.35). Image is underexposed."
%
%   Severity is measured as how far each failing metric is on the WRONG side of
%   its threshold (as a fraction of the threshold), so the reason reported is
%   the one a health worker should fix first.

    arguments
        feat   (1,8) double
        detail (1,1) struct
        cls    (1,1) string
        cfg    (1,1) struct
    end

    if cls == "Good"
        reason = ""; return;
    end

    % Empty FOV / substituted vector: the measurement itself failed.
    if isfield(detail,'emptyFov') && detail.emptyFov
        reason = "No field of view detected. The retina is not visible in the frame.";
        return;
    end
    if isfield(detail,'substituted') && detail.substituted
        reason = "Quality features could not be measured reliably (invalid readings). Treated as ungradeable.";
        return;
    end

    q = cfg.thresholds.quality;

    % Each candidate: {label, value, threshold, direction, sentence}
    % direction "up"  -> fails when value <  threshold
    % direction "down"-> fails when value >  threshold
    cand = {
        'Focus (Laplacian)',   feat(1), q.focusLaplacianMin,    'up',   'Image is blurred across the field.'
        'Focus (Tenengrad)',   feat(2), q.focusTenengradMin,    'up',   'Image lacks sharp edges; likely out of focus.'
        'Illumination uniformity', feat(3), q.illumUniformityMin,'up',  'Lighting is uneven across the retina.'
        'Saturated pixel fraction', feat(4), q.saturatedFractionMax,'down','Image is over-exposed; highlights are blown out.'
        'Dark pixel fraction', feat(5), q.darkFractionMax,       'down', 'Image is under-exposed; the retina is too dark.'
        'FOV completeness',    feat(6), q.fovCompletenessMin,    'up',   'The field of view is clipped; part of the retina is missing.'
        'Contrast (std)',      feat(7), q.contrastStdMin,        'up',   'Image is low in contrast; structures are washed out.'
        'Local contrast',      feat(8), q.localContrastMin,      'up',   'Fine detail is lost, consistent with haze or defocus.'
    };

    worstSev = -inf; worstIdx = 0;
    for i = 1:size(cand,1)
        v   = cand{i,2};
        thr = cand{i,3};
        dir = cand{i,4};
        if strcmp(dir,'up')
            failing = v < thr;
            sev = failing * relSeverity(thr - v, thr);
        else
            failing = v > thr;
            sev = failing * relSeverity(v - thr, thr);
        end
        if failing && sev > worstSev
            worstSev = sev; worstIdx = i;
        end
    end

    if worstIdx == 0
        % Classifier said not-Good but no single threshold is breached (a
        % borderline the model disliked). Report the weakest metric honestly.
        reason = "Overall quality is marginal; no single measurement is clearly out of range.";
        return;
    end

    label = cand{worstIdx,1};
    v     = cand{worstIdx,2};
    thr   = cand{worstIdx,3};
    dir   = cand{worstIdx,4};
    sent  = cand{worstIdx,5};
    if strcmp(dir,'up')
        bound = sprintf('minimum %.2f', thr);
    else
        bound = sprintf('maximum %.2f', thr);
    end
    reason = string(sprintf('%s %.2f (%s). %s', label, v, bound, sent));
end

% ------------------------------------------------------------------------
function s = relSeverity(gap, thr)
%RELSEVERITY  Positive gap on the wrong side, normalised by the threshold.
    if thr <= 0, s = gap; return; end
    s = gap / thr;
end
