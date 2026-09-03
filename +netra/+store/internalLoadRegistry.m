function T = internalLoadRegistry(regPath)
%INTERNALLOADREGISTRY  Load the case registry the UI should display.
%   T = netra.store.internalLoadRegistry() returns, in priority order:
%     1. the REAL registry (data/registry.mat) if it exists and is non-empty;
%     2. otherwise the mock seed (data/mock/registry_seed.mat) if present;
%     3. otherwise an EMPTY mock-schema table.
%   This is what makes the Dashboard/queue show real ingested cases as soon as
%   any exist, and fall back to the fictional seed on a fresh clone.
%
%   T = netra.store.internalLoadRegistry(regPath) loads that explicit path,
%   else returns the EMPTY MOCK-schema table (16 columns) - unchanged Phase 1
%   behaviour that tStoreQueries.bothHandleEmptyRegistry depends on.
%
%   Shared helper for netra.store.queryQueue / stats. MOCK seed rows are
%   fictional; real rows come from netra.store.save.

    if nargin >= 1
        T = loadTableOr(regPath, @emptyMockRegistry);   % explicit path -> mock schema
        return;
    end

    % Merge the fictional mock seed with any real ingested cases so the demo
    % queue/dashboard stay populated after live screenings (real rows win on a
    % uid collision). Real registry alone would starve the 40-case demo queue.
    R = netra.store.registry();
    root = netra.store.storeRoot();            % overridable via NETRA_STORE_ROOT
    seedPath = fullfile(root, 'data', 'mock', 'registry_seed.mat');
    S = loadTableOr(seedPath, @emptyMockRegistry);
    T = mergeRegistries(R, S);
end

% ------------------------------------------------------------------------
function T = mergeRegistries(R, S)
%MERGEREGISTRIES  Union real (R) + mock seed (S) on shared columns; R wins.
    if isempty(R), T = S; return; end
    if isempty(S), T = R; return; end
    % Drop mock rows whose uid already exists in the real registry.
    S = S(~ismember(string(S.uid), string(R.uid)), :);
    % Reconcile to shared columns so vertcat never fails on schema drift.
    common = intersect(R.Properties.VariableNames, S.Properties.VariableNames, 'stable');
    T = [R(:, common); S(:, common)];
end

% ------------------------------------------------------------------------
function T = loadTableOr(regPath, emptyFcn)
%LOADTABLEOR  Load the 'registry' table from a .mat, or emptyFcn() on failure.
    if ~isfile(regPath)
        T = emptyFcn(); return;
    end
    try
        S = load(regPath, 'registry');
        if isfield(S, 'registry') && istable(S.registry)
            T = S.registry;
        else
            T = emptyFcn();
        end
    catch
        T = emptyFcn();
    end
end

function T = emptyMockRegistry()
%EMPTYMOCKREGISTRY  Zero-row 16-column Phase 1 mock schema (unchanged).
    T = table( ...
        strings(0,1), strings(0,1), strings(0,1), NaT(0,1), zeros(0,1), ...
        strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        strings(0,1), strings(0,1), strings(0,1), false(0,1), nan(0,1), ...
        strings(0,1), ...
        'VariableNames', {'uid','patientID','phcID','timestamp','age', ...
        'eye','qualityClass','icdr','confidence','ala','routingDecision', ...
        'urgency','flags','reviewed','reviewSeconds','reviewerAgreed'});
end
