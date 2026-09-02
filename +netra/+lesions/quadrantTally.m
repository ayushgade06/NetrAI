function lesionStruct = quadrantTally(mask, qmap, maculaZone, cfg)
%QUADRANTTALLY  Tally one lesion-class mask into a schema lesion-set struct.  [Phase 6]
%   lesionStruct = netra.lesions.quadrantTally(mask, qmap, maculaZone, cfg)
%
%   Turns a per-class logical lesion mask into the caseRecord lesion-set struct
%   (count, totalArea, centroids, areas, perQuadrant, nearMacula) PLUS the
%   Track-B mask contract field. Each connected component is one lesion; it is
%   assigned to the quadrant (1..4 from qmap) at its centroid and flagged near
%   the macula if its centroid falls inside maculaZone.
%
%   Returned fields (superset of the schema lesion-set; adds .mask per §7):
%     count       number of lesions
%     totalArea   summed area (px^2)
%     centroids   Nx2 [x y]
%     areas       Nx1 px^2
%     perQuadrant 1x4 COUNT per quadrant (index = qmap code 1..4)
%     nearMacula  number of lesions whose centroid is inside maculaZone
%     mask        the input logical mask (size preserved) - Track B depends on this
%
%   A zero-lesion mask returns count 0, empty centroids/areas, zeros(1,4),
%   nearMacula 0, and an all-false mask - a VALID normal-retina result, not an
%   error, that propagates cleanly to the UI and to Track B's ALA (all-false).

    arguments
        mask logical
        qmap
        maculaZone logical
        cfg (1,1) struct %#ok<INUSA>
    end

    [h, w] = size(mask);
    lesionStruct = struct( ...
        'count', 0, 'totalArea', 0, 'centroids', nan(0,2), ...
        'areas', nan(0,1), 'perQuadrant', zeros(1,4), 'nearMacula', 0, ...
        'mask', false(h, w));

    lesionStruct.mask = logical(mask);
    if ~any(mask(:)), return; end

    cc = bwconncomp(mask);
    rp = regionprops(cc, 'Area','Centroid');
    n = numel(rp);
    cents = reshape([rp.Centroid], 2, [])';        % Nx2 [x y]
    areas = [rp.Area]';

    perQuad = zeros(1,4);
    nearMac = 0;
    for i = 1:n
        cx = round(cents(i,1)); cy = round(cents(i,2));
        cx = min(w, max(1, cx)); cy = min(h, max(1, cy));
        q = double(qmap(cy, cx));
        if q >= 1 && q <= 4, perQuad(q) = perQuad(q) + 1; end
        if ~isempty(maculaZone) && isequal(size(maculaZone),[h w]) && maculaZone(cy, cx)
            nearMac = nearMac + 1;
        end
    end

    lesionStruct.count       = n;
    lesionStruct.totalArea   = sum(areas);
    lesionStruct.centroids   = cents;
    lesionStruct.areas       = areas;
    lesionStruct.perQuadrant = perQuad;
    lesionStruct.nearMacula  = nearMac;
end
