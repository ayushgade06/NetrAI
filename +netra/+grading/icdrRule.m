function est = icdrRule(lesionStruct, cfg)
%ICDRRULE  Rule-based ICDR grade estimate from per-quadrant lesion counts.
%   est = netra.grading.icdrRule(lesionStruct, cfg) returns an INDEPENDENT
%   0-4 ICDR severity estimate approximating the clinical 4-2-1 rule. It never
%   looks at the CNN; the caller compares it against the network output (or, on
%   Fallback Path C, uses it AS the grade).
%
%   lesionStruct is cr.lesions (Track A contract): fields MA/HE/EX/CWS, each a
%   lesion-set struct with .count and .perQuadrant (1x4). If lesion data is
%   absent (Track A not merged), returns NaN - the caller decides what that
%   means. Missing sub-fields are treated as zero counts.
%
%   Grading logic (ICDR / ETDRS 4-2-1 approximation):
%     0  No DR            - no MA, HE, EX, CWS anywhere.
%     1  Mild NPDR        - microaneurysms only.
%     2  Moderate NPDR    - more than MA-only, but below the severe 4-2-1 bar.
%     3  Severe NPDR      - ANY 4-2-1 criterion met:
%                             (4) haemorrhages/MA in all 4 quadrants,
%                             (2) venous beading in >=2 quadrants  [PROXY: not
%                                 detected by Track A - see note below],
%                             (1) prominent IRMA in >=1 quadrant   [PROXY: HE in
%                                 3+ quadrants used as a severity surrogate].
%     4  Proliferative    - not inferable from these lesion classes alone; the
%                           rule caps at 3. Only the CNN (path A/B) can assign 4.
%
%   NOTE ON THE 4-2-1 PROXY: true venous beading and IRMA are not among Track
%   A's detected lesion classes (MA/HE/EX/CWS). We approximate the "severe"
%   boundary from haemorrhage spread only. This is a documented approximation,
%   not the clinical rule verbatim - the disagreement flag and the CNN exist
%   precisely to catch where this proxy is wrong.

    arguments
        lesionStruct (1,1) struct
        cfg          (1,1) struct %#ok<INUSA>  % kept for signature symmetry
    end

    % --- pull counts defensively (Track A may not be merged) --------------
    ma = lesionCount(lesionStruct, 'MA');
    he = lesionCount(lesionStruct, 'HE');
    ex = lesionCount(lesionStruct, 'EX');
    cws = lesionCount(lesionStruct, 'CWS');

    if any(isnan([ma he ex cws]))
        est = NaN;                 % lesion data unavailable
        return;
    end

    heQuadrants = quadrantsWith(lesionStruct, 'HE');
    maQuadrants = quadrantsWith(lesionStruct, 'MA');

    % --- severe (grade 3) via the 4-2-1 proxy ----------------------------
    % (4) haemorrhages OR microaneurysms present in all four quadrants.
    allFourQuadrants = (heQuadrants >= 4) || (maQuadrants >= 4);
    % (1)->proxy: prominent haemorrhage spread (3+ quadrants) stands in for
    % the IRMA/venous-beading criteria Track A cannot see.
    prominentSpread  = heQuadrants >= 3;

    if allFourQuadrants || prominentSpread
        est = 3;
    elseif (he > 0) || (ex > 0) || (cws > 0) || (ma > 5)
        % moderate: haemorrhages/exudates/CWS present, or many microaneurysms.
        est = 2;
    elseif ma > 0
        est = 1;                   % mild: microaneurysms only
    else
        est = 0;                   % no DR
    end
end

% ------------------------------------------------------------------------
function c = lesionCount(s, type)
%LESIONCOUNT  s.(type).count, or NaN if the whole lesion group is absent, or 0
%   if the sub-field is merely missing.
    if ~isfield(s, type) || ~isstruct(s.(type))
        c = NaN; return;
    end
    if isfield(s.(type), 'count') && ~isempty(s.(type).count)
        c = double(s.(type).count);
    else
        c = 0;
    end
end

function n = quadrantsWith(s, type)
%QUADRANTSWITH  Number of quadrants (0-4) with >=1 lesion of the given type.
    n = 0;
    if isfield(s, type) && isstruct(s.(type)) ...
            && isfield(s.(type), 'perQuadrant') && ~isempty(s.(type).perQuadrant)
        n = nnz(s.(type).perQuadrant > 0);
    end
end
