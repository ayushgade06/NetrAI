function cr = load(uid, cfg)
%LOAD  Load a caseRecord from the case store by uid.  [Phase 10]
%   cr = netra.store.load(uid, cfg) reads back a previously saved case.
%
%   CONTRACT:
%     - Returns exactly one caseRecord.
%     - Only +store and +report may touch disk. Phase 0 reads NOTHING.
%
%   MOCK IMPLEMENTATION - PHASE 0 SCAFFOLD
%   Returns a fresh placeholder caseRecord tagged with the requested uid.
%   Persists/reads nothing. These are NOT measurements and NOT model outputs.
%   Replaced with a real implementation in Phase 10.

    arguments
        uid (1,:) char
        cfg (1,1) struct %#ok<INUSA>
    end

    % Phase 0: no store on disk yet, so return a fresh record carrying the
    % requested uid. Uses the demo image so the schema is valid.
    here = fileparts(mfilename('fullpath'));           % +store
    root = fileparts(fileparts(here));                 % project root
    demo = fullfile(root, 'data', 'demo', 'sample01.jpg');
    cr = netra.newCaseRecord(demo);
    cr.meta.uid = string(uid);
    cr.provenance.store = "MOCK";
end
