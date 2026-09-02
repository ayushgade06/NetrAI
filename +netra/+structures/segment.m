function cr = segment(cr, cfg)
%SEGMENT  Retinal structure segmentation (vessels, OD, fovea).  [Phase 5]
%   cr = netra.structures.segment(cr, cfg) writes cr.structures.* plus
%   cr.provenance.structures.
%
%   CONTRACT:
%     - Exactly one caseRecord in, exactly one caseRecord out.
%     - May ADD fields; must never DELETE or RENAME a field it did not create.
%     - Must never write to disk (only +store and +report may).
%     - Sets cr.provenance.structures to "REAL" or "MOCK".
%     - cr.timing.structures is written by runPipeline, not here.
%
%   MOCK IMPLEMENTATION - PHASE 0 SCAFFOLD
%   Returns fixed placeholder values. These are NOT measurements and NOT
%   model outputs. Replaced with a real implementation in Phase 5.

    arguments
        cr  (1,1) struct
        cfg (1,1) struct %#ok<INUSA>
    end

    cr.structures.odCenter      = [512 480];   % synthetic pixel coordinates
    cr.structures.odRadius      = 55;
    cr.structures.foveaCenter   = [620 500];
    cr.structures.vesselDensity = 0.12;
    cr.structures.tortuosity    = 1.15;
    % Mask fields stay typed-empty in Phase 0 (no pixels processed).

    cr.provenance.structures = "MOCK";
end
