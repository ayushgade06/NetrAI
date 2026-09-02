function bullets = evidenceBullets(cr, cfg)
%EVIDENCEBULLETS  Templated clinical-evidence bullets from measured findings.
%   bullets = netra.xai.evidenceBullets(cr, cfg) builds a string array of
%   evidence statements from cr.lesions (Track A contract) and cr.grade. Every
%   bullet is derived from a measured count or the grade - a bullet is NEVER
%   emitted for a lesion type whose count is zero (internal-consistency
%   requirement; see tests/tEvidenceBullets.m).
%
%   Phrasing is clinical but NEVER diagnostic. The closing line reads
%   "Findings consistent with ICDR Level N (<label>)", not "patient has ...".
%
%   A zero-lesion / grade-0 case still produces sensible output ("No referable
%   diabetic retinopathy lesions detected." + the consistency line), never an
%   empty array.

    arguments
        cr  (1,1) struct
        cfg (1,1) struct %#ok<INUSA>  % kept for signature symmetry
    end

    quadNames = ["superior", "inferior", "nasal", "temporal"];
    types = struct( ...
        'MA',  "microaneurysm", ...
        'HE',  "haemorrhage", ...
        'EX',  "hard exudate", ...
        'CWS', "cotton-wool spot");

    bullets = strings(0,1);
    fn = fieldnames(types);

    for k = 1:numel(fn)
        t = fn{k};
        [count, perQ, nearMac] = lesionFacts(cr.lesions, t);
        if count <= 0
            continue;               % never assert a lesion we did not count
        end

        noun = types.(t);
        plural = pluralise(noun, count);
        line = sprintf("%d %s detected", count, plural);

        % Quadrant distribution, only for quadrants that actually have lesions.
        if ~isempty(perQ) && any(perQ > 0)
            active = find(perQ > 0);
            parts = strings(1, numel(active));
            for j = 1:numel(active)
                parts(j) = sprintf("%d %s", perQ(active(j)), quadNames(active(j)));
            end
            line = line + " (" + strjoin(parts, ", ") + ")";
        end

        if nearMac > 0
            line = line + sprintf("; %d within one disc-diameter of the macula", nearMac);
        end

        bullets(end+1,1) = line + "."; %#ok<AGROW>
    end

    if isempty(bullets)
        bullets(end+1,1) = "No referable diabetic retinopathy lesions detected.";
    end

    % Closing consistency line - the ONLY place the grade is stated, and never
    % as a diagnosis.
    icdr = cr.grade.icdr;
    if isfinite(icdr)
        label = netra.ui.formatGrade(icdr);
        bullets(end+1,1) = sprintf("Findings consistent with ICDR Level %d (%s).", ...
            round(icdr), label);
    end
end

% ------------------------------------------------------------------------
function [count, perQ, nearMac] = lesionFacts(lesions, type)
%LESIONFACTS  Defensive read of one lesion group (Track A may not be merged).
    count = 0; perQ = []; nearMac = 0;
    if ~isfield(lesions, type) || ~isstruct(lesions.(type))
        return;
    end
    s = lesions.(type);
    if isfield(s, 'count') && ~isempty(s.count)
        count = double(s.count);
    end
    if isfield(s, 'perQuadrant') && ~isempty(s.perQuadrant)
        perQ = double(s.perQuadrant(:).');
    end
    if isfield(s, 'nearMacula') && ~isempty(s.nearMacula)
        nearMac = double(s.nearMacula);
    end
end

function s = pluralise(noun, n)
%PLURALISE  Naive English plural sufficient for these four lesion nouns.
    if n == 1
        s = noun;
    else
        s = noun + "s";
    end
end
