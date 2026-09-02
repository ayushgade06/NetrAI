function cr = assess(cr, cfg)
%ASSESS  Fundus image quality assessment.  [Phase 3]
%   cr = netra.quality.assess(cr, cfg) evaluates capture quality and writes
%   cr.quality.* plus cr.provenance.quality.
%
%   CONTRACT:
%     - Exactly one caseRecord in, exactly one caseRecord out.
%     - May ADD fields; must never DELETE or RENAME a field it did not create.
%     - Must never write to disk (only +store and +report may).
%     - Sets cr.provenance.quality to "REAL" or "MOCK".
%     - cr.timing.quality is written by runPipeline, not here.
%
%   MOCK IMPLEMENTATION - PHASE 0 SCAFFOLD
%   Returns fixed placeholder values. These are NOT measurements and NOT
%   model outputs. Replaced with a real implementation in Phase 3.

    arguments
        cr  (1,1) struct
        cfg (1,1) struct %#ok<INUSA>
    end

    cr.quality.score           = 72;               % synthetic placeholder
    cr.quality.class           = "Good";
    cr.quality.focus           = 0.6;
    cr.quality.illum           = 0.6;
    cr.quality.fovCompleteness = 0.9;
    cr.quality.contrast        = 0.5;
    cr.quality.quadrantMeans   = [110 115 108 112];
    cr.quality.failReason      = "";
    cr.quality.recaptureAdvice = "";

    cr.provenance.quality = "MOCK";
end
