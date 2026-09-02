function advice = recaptureAdvice(feat, detail, cfg)
%RECAPTUREADVICE  One imperative recapture instruction for a health worker. [P3]
%   advice = netra.quality.recaptureAdvice(feat, detail, cfg)
%
%   Returns one plain-language imperative sentence (no jargon) telling the
%   operator what to change and retake, chosen from the SAME most-severe failing
%   metric that failReason names, so the reason and the fix agree. Returns a
%   generic steadying instruction if no single metric dominates.
%
%   This is guidance to be shown whenever the class is not Good; the caller
%   decides when to display it (assess populates it whenever cls ~= "Good").

    arguments
        feat   (1,8) double
        detail (1,1) struct
        cfg    (1,1) struct
    end

    if isfield(detail,'emptyFov') && detail.emptyFov
        advice = "Point the camera directly at the pupil so the whole retina fills the view, then retake.";
        return;
    end

    q = cfg.thresholds.quality;

    % Same candidate ordering/severity as failReason so advice matches reason.
    cand = {
        feat(1), q.focusLaplacianMin,    'up',   "Steady the camera, ask the patient to look at the fixation light, and retake.";
        feat(2), q.focusTenengradMin,    'up',   "Adjust focus until the vessels look sharp, then retake.";
        feat(3), q.illumUniformityMin,   'up',   "Centre the flash on the pupil so the light is even, then retake.";
        feat(4), q.saturatedFractionMax, 'down', "Reduce the flash brightness and retake so the image is not washed out.";
        feat(5), q.darkFractionMax,      'down', "Increase the flash or move closer to the eye, then retake.";
        feat(6), q.fovCompletenessMin,   'up',   "Align the camera so the whole retina is in view, hold steady, and retake.";
        feat(7), q.contrastStdMin,       'up',   "Clean the lens, dim the room lights, and retake for better contrast.";
        feat(8), q.localContrastMin,     'up',   "Clean the lens and shield the eye from stray light, then retake.";
    };

    worstSev = -inf; worstIdx = 0;
    for i = 1:size(cand,1)
        v = cand{i,1}; thr = cand{i,2}; dir = cand{i,3};
        if strcmp(dir,'up')
            failing = v < thr; sev = failing * relSeverity(thr - v, thr);
        else
            failing = v > thr; sev = failing * relSeverity(v - thr, thr);
        end
        if failing && sev > worstSev
            worstSev = sev; worstIdx = i;
        end
    end

    if worstIdx == 0
        advice = "Hold the camera steady, ensure the retina is well lit and centred, and retake.";
    else
        advice = string(cand{worstIdx,4});
    end
end

% ------------------------------------------------------------------------
function s = relSeverity(gap, thr)
    if thr <= 0, s = gap; return; end
    s = gap / thr;
end
