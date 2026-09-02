function s = auditStats(cfg)
%AUDITSTATS  Reviewer-audit statistics from the active case registry.
%   s = netra.store.auditStats(cfg) reads the active registry (real
%   data/registry.mat when it has rows, else the mock seed) and returns:
%
%     s.reviewedCount        double  number of reviewed REVIEW_QUEUE cases
%     s.agreementRate        double  fraction of reviews where the clinician
%                                    AGREED with the AI (0..1; NaN if none)
%     s.overrideCount        double  number of overrides
%     s.overridesByGrade     1x5     override count by AI ICDR grade 0..4
%     s.reviewSeconds        vector  per-review durations (seconds)
%     s.medianReviewSeconds  double  median of reviewSeconds (NaN if none)
%     s.p95ReviewSeconds     double  95th percentile of reviewSeconds
%
%   Agreement is measured from the reviewerAgreed column: "Agreed" vs
%   "Overridden". Cases the reviewer marked Ungradeable/Skip are Overridden /
%   not counted respectively (see netra.store.logReview). On an empty registry
%   every count is 0, rates are NaN and reviewSeconds is empty, so the UI shows
%   an honest empty state rather than a fabricated agreement rate.
%
%   MOCK seed rows are fictional; real rows come from netra.store.save +
%   netra.store.logReview. This function reports counts, never invents them.

    arguments
        cfg (1,1) struct = struct() %#ok<INUSA>
    end

    T = netra.store.internalLoadRegistry();

    s = struct();
    s.reviewedCount       = 0;
    s.agreementRate       = NaN;
    s.overrideCount       = 0;
    s.overridesByGrade    = zeros(1,5);
    s.reviewSeconds       = zeros(0,1);
    s.medianReviewSeconds = NaN;
    s.p95ReviewSeconds    = NaN;

    if isempty(T) || ~ismember('reviewed', T.Properties.VariableNames)
        return;
    end

    reviewedMask = T.reviewed == true;
    if ismember('routingDecision', T.Properties.VariableNames)
        reviewedMask = reviewedMask & (T.routingDecision == "REVIEW_QUEUE");
    end
    R = T(reviewedMask, :);
    s.reviewedCount = height(R);
    if s.reviewedCount == 0
        return;
    end

    % Agreement / override from reviewerAgreed labels.
    if ismember('reviewerAgreed', R.Properties.VariableNames)
        agreed = sum(R.reviewerAgreed == "Agreed");
        overr  = sum(R.reviewerAgreed == "Overridden");
        decided = agreed + overr;
        if decided > 0
            s.agreementRate = agreed / decided;
        end
        s.overrideCount = overr;

        % Overrides by AI grade 0..4.
        if ismember('icdr', R.Properties.VariableNames)
            ov = R(R.reviewerAgreed == "Overridden", :);
            for g = 0:4
                s.overridesByGrade(g+1) = sum(ov.icdr == g);
            end
        end
    end

    % Review-time distribution.
    if ismember('reviewSeconds', R.Properties.VariableNames)
        secs = R.reviewSeconds(~isnan(R.reviewSeconds));
        s.reviewSeconds = secs(:);
        if ~isempty(secs)
            s.medianReviewSeconds = median(secs);
            s.p95ReviewSeconds    = prctile95(secs);
        end
    end
end

% ------------------------------------------------------------------------
function p = prctile95(v)
%PRCTILE95  95th percentile without the Statistics Toolbox (linear interp).
    v = sort(v(:));
    n = numel(v);
    if n == 1, p = v(1); return; end
    rank = 0.95 * (n - 1) + 1;
    lo = floor(rank); hi = ceil(rank);
    if lo == hi
        p = v(lo);
    else
        p = v(lo) + (rank - lo) * (v(hi) - v(lo));
    end
end
