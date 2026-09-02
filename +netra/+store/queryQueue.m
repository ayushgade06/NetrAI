function tbl = queryQueue(cfg, filterSpec)
%QUERYQUEUE  Return the clinician review queue from the mock registry.
%   tbl = netra.store.queryQueue(cfg) returns all unreviewed REVIEW_QUEUE
%   cases as a table, sorted by urgency descending then confidence ascending
%   (most urgent, least confident first).
%
%   tbl = netra.store.queryQueue(cfg, filterSpec) applies optional filters:
%     filterSpec.urgency (string)  keep only this urgency
%     filterSpec.flagged (logical) if true, keep only rows with a flag
%     filterSpec.limit   (double)  keep only the first N after sorting
%
%   Reads data/mock/registry_seed.mat. If it is missing, returns an EMPTY
%   table with the documented columns (the app shows an empty state, never
%   errors). MOCK DATA - fictional, no clinical meaning.
%
%   Columns match the registry seed:
%     uid patientID phcID timestamp age eye qualityClass icdr confidence
%     ala routingDecision urgency flags reviewed reviewSeconds reviewerAgreed

    arguments
        cfg (1,1) struct %#ok<INUSA>
        filterSpec struct = struct()
    end

    T = netra.store.internalLoadRegistry();
    if isempty(T)
        tbl = T;                    % already the documented empty schema
        return;
    end

    % Queue = cases needing review that are not yet reviewed.
    mask = T.routingDecision == "REVIEW_QUEUE" & ~T.reviewed;
    T = T(mask, :);

    if isfield(filterSpec, 'urgency') && strlength(string(filterSpec.urgency)) > 0
        T = T(T.urgency == string(filterSpec.urgency), :);
    end
    if isfield(filterSpec, 'flagged') && ~isempty(filterSpec.flagged) && filterSpec.flagged
        T = T(strlength(T.flags) > 0, :);
    end

    % Sort: urgency descending (Urgent > Priority > Routine > None), then
    % confidence ascending. Map urgency to a rank for ordering.
    rank = arrayfun(@urgencyRank, T.urgency);
    [~, order] = sortrows([-rank, T.confidence], [1 2]);
    T = T(order, :);

    if isfield(filterSpec, 'limit') && ~isempty(filterSpec.limit)
        T = T(1:min(height(T), filterSpec.limit), :);
    end

    tbl = T;
end

% ------------------------------------------------------------------------
function r = urgencyRank(u)
    switch string(u)
        case "Urgent",   r = 4;
        case "Priority", r = 3;
        case "Routine",  r = 2;
        otherwise,       r = 1;   % "None" / unknown
    end
end
