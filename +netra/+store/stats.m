function s = stats(cfg, dateRange)
%STATS  Aggregate dashboard statistics from the mock registry.
%   s = netra.store.stats(cfg) returns a struct of dashboard metrics computed
%   from data/mock/registry_seed.mat.
%
%   s = netra.store.stats(cfg, dateRange) restricts to a [startDate endDate]
%   datetime range (optional; default = all rows).
%
%   Returns a struct with fields:
%     screenedToday      double   count of cases in range
%     referred           double   count routed to REVIEW_QUEUE
%     autoCleared        double   count routed to AUTO_CLEARED
%     recaptureRate      double   fraction routed to RECAPTURE (0..1)
%     avgReviewSeconds   double   mean reviewSeconds over reviewed cases
%     queueDepth         double   unreviewed REVIEW_QUEUE cases
%     gradeDistribution  1x5      counts of ICDR grades 0..4
%     last7Days          7x3      [autoCleared reviewed recaptured] per day
%     qualityFailReasons table    reason/count of non-Good quality classes
%     queueDepthByHour   1xN      queue arrivals bucketed by hour
%
%   MOCK DATA - fictional, no clinical meaning. On a missing/empty registry,
%   returns zeros/empties so the dashboard renders an honest empty state.

    arguments
        cfg (1,1) struct %#ok<INUSA>
        dateRange (1,:) datetime = datetime.empty
    end

    T = netra.store.internalLoadRegistry();

    if ~isempty(dateRange) && numel(dateRange) == 2 && ~isempty(T)
        T = T(T.timestamp >= dateRange(1) & T.timestamp <= dateRange(2), :);
    end

    s = struct();
    s.screenedToday   = height(T);
    s.referred        = sum(T.routingDecision == "REVIEW_QUEUE");
    s.autoCleared     = sum(T.routingDecision == "AUTO_CLEARED");
    nRecapture        = sum(T.routingDecision == "RECAPTURE");
    if height(T) > 0
        s.recaptureRate = nRecapture / height(T);
    else
        s.recaptureRate = 0;
    end

    reviewedSecs = T.reviewSeconds(T.reviewed & ~isnan(T.reviewSeconds));
    if isempty(reviewedSecs)
        s.avgReviewSeconds = 0;
    else
        s.avgReviewSeconds = mean(reviewedSecs);
    end

    s.queueDepth = sum(T.routingDecision == "REVIEW_QUEUE" & ~T.reviewed);

    % Grade distribution 0..4
    gd = zeros(1,5);
    for g = 0:4
        gd(g+1) = sum(T.icdr == g);
    end
    s.gradeDistribution = gd;

    % last7Days: 7 rows (oldest..newest) x [autoCleared reviewed recaptured]
    s.last7Days = last7(T);

    % qualityFailReasons: counts of non-Good quality classes
    s.qualityFailReasons = failReasons(T);

    % queueDepthByHour: arrivals per hour-of-day (0..23), trimmed to used span
    s.queueDepthByHour = byHour(T);
end

% ------------------------------------------------------------------------
function M = last7(T)
    M = zeros(7,3);
    if isempty(T), return; end
    lastDay = dateshift(max(T.timestamp), 'start', 'day');
    for d = 1:7
        dayStart = lastDay - days(7-d);
        dayEnd   = dayStart + days(1);
        inDay = T.timestamp >= dayStart & T.timestamp < dayEnd;
        Td = T(inDay, :);
        M(d,1) = sum(Td.routingDecision == "AUTO_CLEARED");
        M(d,2) = sum(Td.routingDecision == "REVIEW_QUEUE");
        M(d,3) = sum(Td.routingDecision == "RECAPTURE");
    end
end

function tbl = failReasons(T)
    reasons = ["Borderline"; "Ungradeable"];
    counts  = zeros(numel(reasons),1);
    if ~isempty(T)
        for k = 1:numel(reasons)
            counts(k) = sum(T.qualityClass == reasons(k));
        end
    end
    tbl = table(reasons, counts, 'VariableNames', {'reason','count'});
end

function v = byHour(T)
    if isempty(T), v = zeros(1,1); return; end
    h = hour(T.timestamp);
    lo = min(h); hi = max(h);
    edges = lo:hi;
    v = zeros(1, numel(edges));
    for i = 1:numel(edges)
        v(i) = sum(h == edges(i));
    end
end
