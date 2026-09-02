function save(cr, cfg)
%SAVE  Persist a caseRecord to the case store.  [Phase 10]
%   netra.store.save(cr, cfg) writes the caseRecord to data/cases/. Returns
%   nothing. The orchestrator sets cr.provenance.store.
%
%   CONTRACT:
%     - Reads the caseRecord; returns nothing.
%     - Only +store and +report may write to disk. Phase 0 writes NOTHING.
%     - cr.timing.store is written by runPipeline, not here.
%
%   MOCK IMPLEMENTATION - PHASE 0 SCAFFOLD
%   No-op. Persists nothing. These are NOT measurements and NOT model
%   outputs. Replaced with a real implementation in Phase 10.

    arguments
        cr  (1,1) struct %#ok<INUSA>
        cfg (1,1) struct %#ok<INUSA>
    end

    % Phase 0: intentionally does not touch disk.
end
