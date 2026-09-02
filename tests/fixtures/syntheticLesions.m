function lesions = syntheticLesions(spec)
%SYNTHETICLESIONS  Fabricate a Track-A-conforming cr.lesions struct for tests.
%   lesions = syntheticLesions(spec) builds an MA/HE/EX/CWS lesion struct that
%   satisfies the Track B <-> Track A contract WITHOUT Track A being finished,
%   plus the .allMask union used by the ALA computation.
%
%   spec is a struct; every field is optional:
%     .MA/.HE/.EX/.CWS : struct with .count (scalar) and/or .perQuadrant (1x4)
%                        and/or .nearMacula (scalar). Missing -> zero.
%     .imSize          : [H W] for the masks (default [64 64]).
%     .maskType        : struct MA/HE/EX with a mask spec, one of:
%                          'full'   - all-true mask
%                          'none'   - all-false mask (default)
%                          [r c h w]- a rectangular block of true pixels
%
%   The per-type .mask fields are LOGICAL, size imSize, and .allMask is their
%   logical union - matching the mask-format contract in the Track B brief:
%       cr.lesions.<MA|HE|EX>.mask  logical, size(img.enhanced,[1 2])
%       cr.lesions.allMask          logical union.
%
%   Example - a case with 3 MA in the superior quadrant:
%     L = syntheticLesions(struct('MA', struct('count',3,'perQuadrant',[3 0 0 0])));

    arguments
        spec (1,1) struct = struct()
    end

    imSize = getfielddef(spec, 'imSize', [64 64]);
    types = ["MA","HE","EX","CWS"];

    lesions = struct();
    allMask = false(imSize);

    for t = types
        s = struct('count',0, 'totalArea',0, 'centroids',nan(0,2), ...
                   'areas',nan(0,1), 'perQuadrant',zeros(1,4), 'nearMacula',0);
        if isfield(spec, t) && isstruct(spec.(t))
            given = spec.(t);
            if isfield(given,'count'),       s.count = given.count; end
            if isfield(given,'perQuadrant'), s.perQuadrant = given.perQuadrant(:).'; end
            if isfield(given,'nearMacula'),  s.nearMacula = given.nearMacula; end
            if isfield(given,'totalArea'),   s.totalArea = given.totalArea; end
            % Keep count and perQuadrant consistent if only one was given.
            if s.count == 0 && any(s.perQuadrant > 0)
                s.count = sum(s.perQuadrant);
            end
        end
        % Per-type mask (CWS has none in the contract; MA/HE/EX carry masks).
        if t ~= "CWS"
            s.mask = maskFor(spec, t, imSize);
            allMask = allMask | s.mask;
        end
        lesions.(t) = s;
    end

    lesions.allMask = allMask;
end

% ------------------------------------------------------------------------
function m = maskFor(spec, type, imSize)
    m = false(imSize);
    if ~isfield(spec, 'maskType') || ~isfield(spec.maskType, type)
        return;
    end
    v = spec.maskType.(type);
    if ischar(v) || isstring(v)
        switch lower(string(v))
            case "full", m = true(imSize);
            case "none", m = false(imSize);
        end
    elseif isnumeric(v) && numel(v) == 4
        r = v(1); c = v(2); h = v(3); w = v(4);
        m(r:min(r+h-1,imSize(1)), c:min(c+w-1,imSize(2))) = true;
    end
end

function v = getfielddef(s, f, d)
    if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
