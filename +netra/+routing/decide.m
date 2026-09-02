function cr = decide(cr, cfg)
%DECIDE  Clinical routing decision (REAL logic).  [Phase 0 - real]
%   cr = netra.routing.decide(cr, cfg) sets cr.routing.decision / urgency /
%   reason / flags by evaluating ordered rules, first match wins.
%
%   CONTRACT:
%     - Exactly one caseRecord in, exactly one caseRecord out.
%     - May ADD fields; must never DELETE or RENAME a field it did not create.
%     - Must never write to disk.
%     - Sets cr.provenance.routing to "REAL".
%     - cr.timing.routing is written by runPipeline, not here.
%
%   This is the ONLY real logic in Phase 0. Rules, decisions and urgencies
%   come from cfg.routingRules (config/routing_rules.json); the numeric
%   thresholds come from cfg.thresholds. The rule ORDER below mirrors the
%   config array; both must stay in sync (see docs/schema.md).

    arguments
        cr  (1,1) struct
        cfg (1,1) struct
    end

    rules = cfg.routingRules;                 % ordered; carries display text
    confMin = cfg.thresholds.grading.confidenceMin;
    alaLow  = cfg.thresholds.xai.alaLowThreshold;

    grade        = cr.grade.icdr;
    confidence   = cr.grade.confidence;
    ala          = cr.xai.agreementScore;
    disagreement = cr.grade.disagreement;
    ungradeable  = strcmp(cr.quality.class, "Ungradeable");
    nearMacula   = anyLesionNearMacula(cr);

    % Ordered evaluation, first match wins. Index i lines up with rules(i)
    % so the human-readable name/condition from config is reported verbatim.
    flags = strings(1,0);
    if ungradeable                                            % 1
        i = 1;
    elseif grade >= 4                                         % 2
        i = 2;
    elseif grade >= 2 && nearMacula                           % 3
        i = 3;
    elseif grade == 3                                         % 4
        i = 4;
    elseif grade == 2                                         % 5
        i = 5;
    elseif confidence < confMin                               % 6
        i = 6; flags(end+1) = "Uncertain";
    elseif ala < alaLow                                       % 7
        i = 7; flags(end+1) = "LowAgreement";
    elseif disagreement                                       % 8
        i = 8; flags(end+1) = "Disagreement";
    else                                                      % 9
        i = 9;
    end

    rule = rules(i);
    cr.routing.decision = string(rule.decision);
    cr.routing.urgency  = string(rule.urgency);
    cr.routing.reason   = string(rule.name);
    cr.routing.flags    = flags;

    cr.provenance.routing = "REAL";
end

% ------------------------------------------------------------------------
function tf = anyLesionNearMacula(cr)
%ANYLESIONNEARMACULA  True if any lesion class reports nearMacula > 0.
    tf = false;
    classes = {'MA','HE','EX','CWS'};
    for k = 1:numel(classes)
        c = classes{k};
        if isfield(cr.lesions, c) && cr.lesions.(c).nearMacula > 0
            tf = true;
            return;
        end
    end
end
