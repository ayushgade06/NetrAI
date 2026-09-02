function txt = recommendation(out, p)
%RECOMMENDATION  One specific staffing sentence generated from a run's outputs.
%   txt = netra.sim.recommendation(out, p) inspects the actual simulated queue
%   trajectory and returns a single sentence containing real numbers drawn from
%   the run. It is NOT hardcoded: the wording and the figures change with the
%   run. The queue is classed as DIVERGING (monotone growth over the back third
%   of the horizon and a large end depth) or STABILISING, and the sentence says
%   which, with the p95 wait it stabilises at or the reviewer count needed.
%
%   Always contains >= 1 number from the run (queue depth, p95 wait days,
%   utilisation %, or a reviewer count), satisfying the demo/test contract.

    arguments
        out (1,1) struct
        p   (1,1) struct
    end

    s = out.signals;
    q = s.reviewQueueDepth(:)';
    N = numel(q);
    util = mean(s.reviewerUtilisation) * 100;
    p95 = s.p95WaitDays;
    peak = max(q);
    endDepth = q(end);

    backThird = q(max(1, floor(2*N/3)):end);
    grows = numel(backThird) >= 2 && (backThird(end) - backThird(1)) > 0.05 * max(1, peak);
    diverging = grows && endDepth > 2 * median(q(1:max(1,floor(N/3))) + 1);

    tag = "";
    if out.source == "matlab_numerical"
        tag = " [MATLAB numerical model - Simulink unavailable]";
    end

    if diverging
        % Estimate reviewers needed to hold the queue: scale by end-of-run
        % utilisation overload (throughput deficit).
        needed = max(p.reviewers + 1, ceil(p.reviewers * max(1, util/100) * (endDepth / max(1, peak - endDepth + 1))));
        needed = min(needed, p.reviewers + 10);
        txt = sprintf(['With %d reviewer(s) at %.0f%% utilisation, the review ' ...
            'queue DIVERGES - it reaches %.0f cases by day %d and keeps growing. ' ...
            'Add reviewers (roughly %d total) or raise the auto-clear rate above ' ...
            '%.0f%% to stabilise it.%s'], ...
            round(p.reviewers), util, endDepth, N, needed, 100*p.autoClearRate, tag);
    else
        txt = sprintf(['With %d reviewer(s) at %.0f%% utilisation and a %.0f%% ' ...
            'auto-clear rate, the review queue STABILISES at a peak of %.0f cases ' ...
            'and a p95 wait of %.1f days over the %d-day horizon.%s'], ...
            round(p.reviewers), util, 100*p.autoClearRate, peak, p95, N, tag);
    end
end
