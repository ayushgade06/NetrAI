function cr = load(uid, cfg)
%LOAD  Load a caseRecord from the on-disk case store by uid.  [Phase 2 - REAL]
%   cr = netra.store.load(uid, cfg) reads data/cases/<uid>/case.mat and returns
%   the stored caseRecord.
%
%   CONTRACT:
%     - Returns exactly one caseRecord. Only +store/+report touch disk.
%
%   Errors:
%     NETRA:store:notFound  no case folder / case.mat for that uid.
%     NETRA:store:corrupt   case.mat exists but has no 'cr' variable.

    arguments
        uid (1,:) char
        cfg (1,1) struct = struct() %#ok<INUSA>
    end

    root = netra.store.storeRoot();            % overridable via NETRA_STORE_ROOT
    caseFile = fullfile(root, 'data', 'cases', uid, 'case.mat');

    if ~isfile(caseFile)
        error('NETRA:store:notFound', ...
            'No stored case for uid "%s" (looked for %s).', uid, caseFile);
    end

    S = builtin('load', caseFile, 'cr');
    if ~isfield(S, 'cr') || ~isstruct(S.cr)
        error('NETRA:store:corrupt', ...
            'case.mat for uid "%s" does not contain a caseRecord.', uid);
    end
    cr = S.cr;
end
