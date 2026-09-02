function [cls, conf] = classifyRuleBased(feat, cfg)
%CLASSIFYRULEBASED  Pure-threshold quality class + crude confidence.  [Phase 3]
%   [cls, conf] = netra.quality.classifyRuleBased(feat, cfg)
%     cls  : "Good" | "Borderline" | "Ungradeable"
%     conf : crude 0..1 confidence (margin of the score to the nearest band edge)
%
%   TWO ROLES:
%     1. FALLBACK path when the trained classifier is unavailable (see
%        docs/quality_method.md, section 13 of the Phase 3 brief). The eight
%        thresholds in thresholds.json ARE a quality model; this is that model.
%     2. HARD OVERRIDES that fire regardless of any trained model: a FOV that is
%        too incomplete, or a feature vector that had to be NaN-substituted, is
%        Ungradeable no matter what else reads well. netra.quality.assess calls
%        these overrides even on the trained path.
%
%   Logic (documented, order matters - first hard failure wins):
%     H1 fovCompleteness < hardRejectFovCompleteness      -> Ungradeable
%     H2 darkFraction    > darkFractionMax                 -> Ungradeable
%     H3 saturatedFraction > saturatedFractionMax          -> Ungradeable
%     H4 focus (both metrics) below their mins             -> Ungradeable
%     otherwise: band the composite score:
%        score >= gradeableScoreMin   -> Good
%        score >= borderlineScoreMin  -> Borderline
%        else                         -> Ungradeable

    arguments
        feat (1,8) double
        cfg  (1,1) struct
    end

    q = cfg.thresholds.quality;
    reqKeys = {'hardRejectFovCompleteness','focusLaplacianMin', ...
        'focusTenengradMin','saturatedFractionMax','darkFractionMax', ...
        'gradeableScoreMin','borderlineScoreMin'};
    for i = 1:numel(reqKeys)
        if ~isfield(q, reqKeys{i})
            error('NETRA:config:missingKey', ...
                'Required config key missing: thresholds.quality.%s', reqKeys{i});
        end
    end

    focusLaplacian    = feat(1);
    focusTenengrad    = feat(2);
    saturatedFraction = feat(4);
    darkFraction      = feat(5);
    fovCompleteness   = feat(6);

    % --- hard overrides (return maximum confidence: these are categorical) ---
    if fovCompleteness < q.hardRejectFovCompleteness
        cls = "Ungradeable"; conf = 1; return;
    end
    if darkFraction > q.darkFractionMax
        cls = "Ungradeable"; conf = 1; return;
    end
    if saturatedFraction > q.saturatedFractionMax
        cls = "Ungradeable"; conf = 1; return;
    end
    if focusLaplacian < q.focusLaplacianMin && focusTenengrad < q.focusTenengradMin
        cls = "Ungradeable"; conf = 1; return;
    end

    % --- band the composite score ---------------------------------------
    score = netra.quality.scoreComposite(feat, cfg);
    if score >= q.gradeableScoreMin
        cls = "Good";
        conf = bandConf(score, q.gradeableScoreMin, 100);
    elseif score >= q.borderlineScoreMin
        cls = "Borderline";
        conf = bandConf(score, q.borderlineScoreMin, q.gradeableScoreMin);
    else
        cls = "Ungradeable";
        conf = bandConf(score, 0, q.borderlineScoreMin);
    end
end

% ------------------------------------------------------------------------
function c = bandConf(score, lo, hi)
%BANDCONF  Crude confidence: how centred the score sits within its band.
%   0.5 at a band edge (ambiguous), up to 1 at the band centre. Always finite.
    if hi <= lo, c = 0.75; return; end
    frac = (score - lo) / (hi - lo);        % 0..1 within the band
    c = 0.5 + 0.5 * (1 - 2*abs(frac - 0.5));
    c = max(0, min(1, c));
end
