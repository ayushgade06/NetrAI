function cr = classify(cr, cfg, models)
%CLASSIFY  CNN-based DR severity grading (ICDR 0-4).  [Phase 7]
%   cr = netra.grading.classify(cr, cfg, models) writes cr.grade.* plus
%   cr.provenance.grading.
%
%   CONTRACT:
%     - Exactly one caseRecord in, exactly one caseRecord out.
%     - May ADD fields; must never DELETE or RENAME a field it did not create.
%     - Must never write to disk (only +store and +report may).
%     - Sets cr.provenance.grading to "REAL" or "MOCK".
%     - cr.timing.grading is written by runPipeline, not here.
%
%   MOCK IMPLEMENTATION - PHASE 0 SCAFFOLD
%   Returns fixed placeholder values. These are NOT measurements and NOT
%   model outputs. Replaced with a real implementation in Phase 7.

    arguments
        cr     (1,1) struct
        cfg    (1,1) struct
        models (1,1) struct %#ok<INUSA>
    end

    probs = [0.05 0.15 0.55 0.20 0.05];        % synthetic, sums to 1
    cr.grade.icdr          = 2;                 % argmax of probs (ICDR grade)
    cr.grade.probs         = probs;
    cr.grade.referableProb = sum(probs(3:5));   % grades >=2 are referable
    cr.grade.confidence    = 0.8;
    cr.grade.ruleEstimate  = 2;
    cr.grade.disagreement  = false;
    cr.grade.label         = "Moderate NPDR";

    cr.provenance.grading = "MOCK";
end
