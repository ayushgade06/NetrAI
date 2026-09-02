function T = internalLoadRegistry(regPath)
%INTERNALLOADREGISTRY  Load the mock case registry, or an empty schema table.
%   T = netra.store.internalLoadRegistry() loads data/mock/registry_seed.mat
%   and returns the 'registry' table. If the file is missing or malformed,
%   returns an EMPTY table carrying the documented columns so callers can
%   render an empty state without special-casing.
%
%   T = netra.store.internalLoadRegistry(regPath) loads an explicit path
%   (used by tests). MOCK DATA - fictional, no clinical meaning.
%
%   Shared helper for netra.store.queryQueue and netra.store.stats. Not part
%   of the frozen Phase 0 contract; added in Phase 1 alongside those two.

    if nargin < 1
        here = fileparts(mfilename('fullpath'));   % +store
        root = fileparts(fileparts(here));         % project root
        regPath = fullfile(root, 'data', 'mock', 'registry_seed.mat');
    end

    if ~isfile(regPath)
        T = emptyRegistry();
        return;
    end

    try
        S = load(regPath, 'registry');
        if isfield(S, 'registry') && istable(S.registry)
            T = S.registry;
        else
            T = emptyRegistry();
        end
    catch
        T = emptyRegistry();
    end
end

% ------------------------------------------------------------------------
function T = emptyRegistry()
%EMPTYREGISTRY  Zero-row table with the documented registry columns/types.
    T = table( ...
        strings(0,1), strings(0,1), strings(0,1), NaT(0,1), zeros(0,1), ...
        strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        strings(0,1), strings(0,1), strings(0,1), false(0,1), nan(0,1), ...
        strings(0,1), ...
        'VariableNames', {'uid','patientID','phcID','timestamp','age', ...
        'eye','qualityClass','icdr','confidence','ala','routingDecision', ...
        'urgency','flags','reviewed','reviewSeconds','reviewerAgreed'});
end
