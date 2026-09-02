function cr = detect(cr, cfg)
%DETECT  Lesion detection (MA / HE / EX / CWS).  [Phase 6]
%   cr = netra.lesions.detect(cr, cfg) writes cr.lesions.* plus
%   cr.provenance.lesions.
%
%   CONTRACT:
%     - Exactly one caseRecord in, exactly one caseRecord out.
%     - May ADD fields; must never DELETE or RENAME a field it did not create.
%     - Must never write to disk (only +store and +report may).
%     - Sets cr.provenance.lesions to "REAL" or "MOCK".
%     - cr.timing.lesions is written by runPipeline, not here.
%
%   MOCK IMPLEMENTATION - PHASE 0 SCAFFOLD
%   Returns fixed placeholder values. These are NOT measurements and NOT
%   model outputs. Replaced with a real implementation in Phase 6.

    arguments
        cr  (1,1) struct
        cfg (1,1) struct %#ok<INUSA>
    end

    % Fixed, obviously synthetic lesion counts. nearMacula kept 0 so the
    % default mock case does not trip the "lesion near macula" routing rule.
    cr.lesions.MA  = mockLesion(3, [30 20 40 10]);
    cr.lesions.HE  = mockLesion(1, [10 0 0 0]);
    cr.lesions.EX  = mockLesion(0, [0 0 0 0]);
    cr.lesions.CWS = mockLesion(0, [0 0 0 0]);

    cr.provenance.lesions = "MOCK";
end

% ------------------------------------------------------------------------
function les = mockLesion(count, perQuadrant)
%MOCKLESION  Build one deterministic placeholder lesion-set struct.
    les = struct( ...
        'count',       count, ...
        'totalArea',   sum(perQuadrant), ...
        'centroids',   nan(count,2), ...
        'areas',       nan(count,1), ...
        'perQuadrant', perQuadrant, ...
        'nearMacula',  0);
end
