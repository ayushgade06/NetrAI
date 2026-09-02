function cr = enhance(cr, cfg)
%ENHANCE  Adaptive fundus enhancement (illumination, CLAHE, denoise).  [Phase 4]
%   cr = netra.preproc.enhance(cr, cfg) produces cr.img.enhanced /
%   cr.img.modelInput and records cr.preproc.* plus cr.provenance.preproc.
%
%   CONTRACT:
%     - Exactly one caseRecord in, exactly one caseRecord out.
%     - May ADD fields; must never DELETE or RENAME a field it did not create.
%     - Must never write to disk (only +store and +report may).
%     - Sets cr.provenance.preproc to "REAL" or "MOCK".
%     - cr.timing.preproc is written by runPipeline, not here.
%
%   MOCK IMPLEMENTATION - PHASE 0 SCAFFOLD
%   Returns fixed placeholder values. These are NOT measurements and NOT
%   model outputs. Replaced with a real implementation in Phase 4.

    arguments
        cr  (1,1) struct
        cfg (1,1) struct
    end

    cr.preproc.appliedSteps   = ["illumCorrect", "clahe"]; % synthetic
    cr.preproc.claheClip      = cfg.thresholds.preproc.claheClipDefault;
    cr.preproc.illumApplied   = true;
    cr.preproc.denoiseApplied = false;

    cr.provenance.preproc = "MOCK";
end
