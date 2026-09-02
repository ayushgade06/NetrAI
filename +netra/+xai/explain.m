function cr = explain(cr, cfg, models)
%EXPLAIN  Grad-CAM explainability and evidence summary.  [Phase 8]
%   cr = netra.xai.explain(cr, cfg, models) writes cr.xai.* plus
%   cr.provenance.xai.
%
%   CONTRACT:
%     - Exactly one caseRecord in, exactly one caseRecord out.
%     - May ADD fields; must never DELETE or RENAME a field it did not create.
%     - Must never write to disk (only +store and +report may).
%     - Sets cr.provenance.xai to "REAL" or "MOCK".
%     - cr.timing.xai is written by runPipeline, not here.
%
%   MOCK IMPLEMENTATION - PHASE 0 SCAFFOLD
%   Returns fixed placeholder values. These are NOT measurements and NOT
%   model outputs. Replaced with a real implementation in Phase 8.

    arguments
        cr     (1,1) struct
        cfg    (1,1) struct
        models (1,1) struct %#ok<INUSA>
    end

    cr.xai.agreementScore   = 0.75;             % synthetic ALA placeholder
    cr.xai.evidenceBullets  = [ ...
        "PLACEHOLDER: microaneurysms in superior quadrant"; ...
        "PLACEHOLDER: attention concentrated near macula"];
    cr.xai.confidenceBand   = "Moderate";
    cr.xai.attentionSummary = "PLACEHOLDER attention summary (mock).";
    % gradcam heatmap stays typed-empty in Phase 0 (no pixels processed).

    cr.provenance.xai = "MOCK";
end
