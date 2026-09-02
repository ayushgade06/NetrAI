function st = latencyStats(cfg)
%LATENCYSTATS  Aggregate measured per-stage latency from data/timing.log.
%   st = netra.util.latencyStats(cfg) reads <storeRoot>/data/timing.log
%   (written by netra.util.appendTimingLog on every pipeline run) and returns a
%   struct summarising MEASURED wall-clock latency:
%
%     st.perStage        struct: st.perStage.<stage>.median / .p95 (seconds)
%     st.totalMedian     double median of the per-run total (seconds)
%     st.totalP95        double 95th percentile of the per-run total
%     st.gradingMedian   double convenience alias for perStage.grading.median
%     st.n               double number of runs aggregated
%     st.available       logical true if any real timing rows were found
%     st.source          string  "measured" | "none"
%
%   When the log is missing or empty, st.available is false, numeric fields are
%   NaN, and st.source is "none" - the caller (buildParams) then falls back to
%   the documented ASSUMPTION in cfg.thresholds.sim and labels it as such. This
%   function never invents a latency; it only reports what was measured.

    arguments
        cfg (1,1) struct = struct() %#ok<INUSA>
    end

    stages = netra.util.stageNames();
    st = struct();
    st.perStage = struct();
    for k = 1:numel(stages)
        st.perStage.(stages{k}) = struct('median', NaN, 'p95', NaN);
    end
    st.totalMedian  = NaN;
    st.totalP95     = NaN;
    st.gradingMedian = NaN;
    st.n            = 0;
    st.available    = false;
    st.source       = "none";

    logPath = fullfile(netra.store.storeRoot(), 'data', 'timing.log');
    if ~isfile(logPath)
        return;
    end

    try
        T = readtable(logPath, 'TextType', 'string');
    catch
        return;   % unreadable/partial log -> honest "none", never guess
    end
    if height(T) == 0
        return;
    end

    st.n = height(T);
    st.available = true;
    st.source = "measured";

    for k = 1:numel(stages)
        s = stages{k};
        if ismember(s, T.Properties.VariableNames)
            v = T.(s);
            v = v(isfinite(v));
            if ~isempty(v)
                st.perStage.(s).median = median(v);
                st.perStage.(s).p95    = prctile95(v);
            end
        end
    end
    if ismember('total', T.Properties.VariableNames)
        v = T.total; v = v(isfinite(v));
        if ~isempty(v)
            st.totalMedian = median(v);
            st.totalP95    = prctile95(v);
        end
    end
    st.gradingMedian = st.perStage.grading.median;
end

% ------------------------------------------------------------------------
function p = prctile95(v)
%PRCTILE95  95th percentile without the Statistics Toolbox (linear interp).
    v = sort(v(:));
    n = numel(v);
    if n == 1, p = v(1); return; end
    rank = 0.95 * (n - 1) + 1;      % 1-based fractional rank
    lo = floor(rank); hi = ceil(rank);
    if lo == hi
        p = v(lo);
    else
        p = v(lo) + (rank - lo) * (v(hi) - v(lo));
    end
end
