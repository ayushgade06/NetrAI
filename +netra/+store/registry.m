function tbl = registry(cfg)
%REGISTRY  Return the full REAL case registry as a table.  [Phase 2]
%   tbl = netra.store.registry() loads data/registry.mat (a table named
%   'registry') written by netra.store.save. If it does not exist or is
%   malformed, returns an EMPTY table with the documented real-registry
%   columns so callers can render an empty state without special-casing.
%
%   tbl = netra.store.registry(cfg) is the same; cfg is accepted for a uniform
%   call signature and currently unused (the store root is fixed relative to
%   this file).
%
%   SINGLE source of truth for the real-registry column set and types.
%   netra.store.save builds its rows against registry().Properties.VariableNames,
%   and netra.store.emptyRealRegistry() (below) is reused by the shared loader.
%
%   Columns (superset of the Phase 1 mock registry; Phase 1 names retained so
%   the Dashboard/queue keep working):
%     uid patientID phcID timestamp age dmYears eye imagePath imageHash
%     qualityClass qualityScore icdr confidence ala routingDecision urgency
%     flags reviewed reviewSeconds reviewerAgreed provenanceSummary

    arguments
        cfg (1,1) struct = struct() %#ok<INUSA>
    end

    root = netra.store.storeRoot();            % overridable via NETRA_STORE_ROOT
    regPath = fullfile(root, 'data', 'registry.mat');

    tbl = netra.store.emptyRealRegistry();     % correct schema on any failure
    if isfile(regPath)
        try
            S = load(regPath, 'registry');
            if isfield(S, 'registry') && istable(S.registry)
                tbl = S.registry;
            end
        catch
            % keep the empty real schema
        end
    end
end
