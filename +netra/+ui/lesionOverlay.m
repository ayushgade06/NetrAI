function layers = lesionOverlay(cr, sz)
%LESIONOVERLAY  Build per-class lesion overlay masks + colours for the canvas.  [Phase 6 UI]
%   layers = netra.ui.lesionOverlay(cr) returns a struct array with one entry
%   per detected lesion class, each { name, mask, color, count }, sized to the
%   enhanced image. netra.ui.lesionOverlay(cr, [H W]) resizes the masks to sz
%   (nearest-neighbour) so they line up with a resized canvas base.
%
%   Colours follow the brief's legend, keyed off netra.ui.theme:
%       MA -> red dots        (theme reject)
%       HE -> dark red blobs  (a darkened reject)
%       EX -> yellow          (theme warn / lesion amber-yellow)
%   MA/EX detections are small; their masks are dilated a little so single-pixel
%   dots are visible on the canvas without changing the underlying detection.
%
%   Uses cr.lesions.<TYPE>.mask (the §7 contract field). A class with a zero
%   mask still returns an entry with count 0 (so the legend shows "MA: 0"), an
%   all-false mask, so the caller never special-cases the normal-retina case.

    arguments
        cr (1,1) struct
        sz double = []
    end

    t = netra.ui.theme();
    darkRed = t.color.reject * 0.6;                % HE: darker than MA
    yellow  = [0.95 0.85 0.20];                    % EX: distinct yellow

    spec = { ...
        'MA', t.color.reject, 2; ...               % class, colour, dilation px
        'HE', darkRed,        1; ...
        'EX', yellow,         2};

    layers = struct('name', {}, 'mask', {}, 'color', {}, 'count', {});
    for k = 1:size(spec,1)
        type = spec{k,1};
        L = cr.lesions.(type);
        m = logical(L.mask);
        if ~isempty(sz) && ~isequal(size(m), sz)
            m = resizeMask(m, sz(1), sz(2));
        end
        d = spec{k,3};
        if d > 0 && any(m(:))
            m = imdilate(m, strel('disk', d));
        end
        layers(end+1) = struct('name', ['Lesion_' type], 'mask', m, ...
            'color', spec{k,2}, 'count', L.count); %#ok<AGROW>
    end
end

% ---- helper -------------------------------------------------------------
function m2 = resizeMask(m, H, W)
    [h, w] = size(m);
    ri = max(1, round((1:H)/H * h));
    ci = max(1, round((1:W)/W * w));
    m2 = m(ri, ci);
end
