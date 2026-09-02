function score = scoreComposite(feat, cfg)
%SCORECOMPOSITE  Deterministic 0-100 quality score from the eight features. [P3]
%   score = netra.quality.scoreComposite(feat, cfg)
%
%   Each feature is mapped to a 0..1 "subscore" measuring how far it is on the
%   GOOD side of its threshold, then combined with the weights in
%   cfg.thresholds.quality.featureWeights (a 1x8, feature order per
%   netra.quality.featureNames). The weighted mean is scaled to 0..100.
%
%   The mapping direction per feature (higher-is-better vs lower-is-better) and
%   the reference threshold are documented in docs/quality_method.md. The score
%   is deterministic and fully guarded: no NaN/Inf can be produced, because
%   extractFeatures already substitutes safe finite values and every division
%   here is bounded.
%
%   This score is INDEPENDENT of the classifier: it is what the gauge shows and
%   what gradeableScoreMin / borderlineScoreMin band. The classifier decides the
%   class; the score explains it to a human.

    arguments
        feat (1,8) double
        cfg  (1,1) struct
    end

    q = cfg.thresholds.quality;
    w = requireKey(q, 'featureWeights');
    w = w(:)';
    if numel(w) ~= 8
        error('NETRA:config:missingKey', ...
            'thresholds.quality.featureWeights must be 1x8 (feature order).');
    end

    % Per-feature subscore in [0,1]: higher = better quality.
    % higherBetter features: value/threshold clamped to 1 (>=threshold -> ~1).
    % lowerBetter fractions: 1 - value/threshold (>=threshold -> 0).
    fl = q.focusLaplacianMin;
    ft = q.focusTenengradMin;
    iu = q.illumUniformityMin;
    sf = q.saturatedFractionMax;
    df = q.darkFractionMax;
    fc = q.fovCompletenessMin;
    cs = q.contrastStdMin;
    lc = q.localContrastMin;

    s = zeros(1,8);
    s(1) = ratioUp(feat(1), fl);      % focusLaplacian  (higher better)
    s(2) = ratioUp(feat(2), ft);      % focusTenengrad  (higher better)
    s(3) = ratioUp(feat(3), iu);      % illumUniformity (higher better)
    s(4) = ratioDown(feat(4), sf);    % saturatedFraction (lower better)
    s(5) = ratioDown(feat(5), df);    % darkFraction    (lower better)
    s(6) = ratioUp(feat(6), fc);      % fovCompleteness (higher better)
    s(7) = ratioUp(feat(7), cs);      % contrastStd     (higher better)
    s(8) = ratioUp(feat(8), lc);      % localContrast   (higher better)

    wsum = sum(w);
    if wsum <= 0, wsum = 1; end
    score = 100 * sum(w .* s) / wsum;
    score = max(0, min(100, score));
    if ~isfinite(score), score = 0; end
end

% ------------------------------------------------------------------------
function r = ratioUp(v, thr)
%RATIOUP  Higher-is-better: 0 at v=0, ~1 at v>=threshold, saturating past it.
    if thr <= 0, r = double(v > 0); return; end
    r = max(0, min(1, v / thr));
end

function r = ratioDown(v, thr)
%RATIODOWN  Lower-is-better: 1 at v=0, 0 at v>=threshold.
    if thr <= 0, r = double(v <= 0); return; end
    r = max(0, min(1, 1 - v / thr));
end

function val = requireKey(s, key)
    if ~isfield(s, key)
        error('NETRA:config:missingKey', ...
            'Required config key missing: thresholds.quality.%s', key);
    end
    val = s.(key);
end
