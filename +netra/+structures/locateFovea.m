function [ctr, conf] = locateFovea(img, fovMask, odCenter, odRadius, vesselMask, cfg)
%LOCATEFOVEA  Locate the fovea from the OD geometry + a darkest-region search.  [Phase 5]
%   [ctr, conf] = netra.structures.locateFovea(img, fovMask, odCenter, odRadius, vesselMask, cfg)
%
%   The fovea sits ~foveaDiscDiameters disc DIAMETERS temporal to the optic disc
%   along the horizontal raphe, is the darkest central region, and is avascular.
%   This:
%     1. GEOMETRIC PRIOR: places a seed foveaDiscDiameters*(2*odRadius) from the
%        OD centre in the TEMPORAL direction. Temporal = away from the nearest
%        horizontal FOV edge (the OD is nasal, so it lies toward the closer
%        edge; the macula lies toward the FOV centre). This needs no eye label.
%     2. BOUNDED SEARCH: inside a foveaSearchWindow-sized box around the seed
%        (clipped to the FOV), find the darkest, vessel-free spot: smooth the
%        inverted-brightness, suppress vessels, and take the min-intensity
%        centroid. Constrained to the window so a dark lesion elsewhere cannot
%        capture it.
%
%   OUTPUT:
%     ctr  [x y] px
%     conf 0..1: how dark and how avascular the found spot is vs its surround.
%          The CALLER applies the fallback (geometric prior) when this is low.
%
%   The offset is in disc diameters and the window is disc/resolution scaled, so
%   the localisation tracks anatomy rather than a fixed pixel geometry.

    arguments
        img
        fovMask logical
        odCenter (1,2) double
        odRadius (1,1) double
        vesselMask logical
        cfg (1,1) struct
    end

    st = cfg.thresholds.structures;
    [h, w, ~] = size(img);
    scaleFac = min(h,w) / cfg.thresholds.preproc.targetSize;

    % --- temporal direction: away from the nearest horizontal FOV edge ---
    [~, cxFov] = fovCentroid(fovMask, h, w);
    % OD nasal side: if OD is left of FOV centre it is the left (nasal) side, so
    % temporal (macula) is to the RIGHT (+x), and vice-versa.
    if odCenter(1) <= cxFov, tempDir = +1; else, tempDir = -1; end

    offset = st.foveaDiscDiameters * (2*odRadius);     % DD -> px
    seed = [odCenter(1) + tempDir*offset, odCenter(2)];
    seed(1) = min(w, max(1, seed(1)));
    seed(2) = min(h, max(1, seed(2)));

    % --- bounded search window ------------------------------------------
    win = round(st.foveaSearchWindow * scaleFac);
    x0 = max(1, round(seed(1)-win)); x1 = min(w, round(seed(1)+win));
    y0 = max(1, round(seed(2)-win)); y1 = min(h, round(seed(2)+win));

    % darkness map: dark AND vessel-free AND well inside the FOV
    if size(img,3) == 3, bright = (double(img(:,:,1))+double(img(:,:,2)))/2;
    else, bright = double(img); end
    bright = imgaussfilt(bright/255, max(1, 4*scaleFac));
    darkness = 1 - bright;                              % dark -> high
    darkness(vesselMask) = 0;                           % avoid vessels
    innerFov = imerode(fovMask, strel('disk', max(2, round(5*scaleFac))));
    darkness(~innerFov) = 0;

    sub = darkness(y0:y1, x0:x1);
    if ~any(sub(:))
        ctr = seed; conf = 0; return;                   % nothing valid: use prior
    end

    % darkest connected region in the window -> its centroid
    thr = prctile(sub(sub>0), 90);
    darkBlob = sub >= thr;
    darkBlob = imopen(darkBlob, strel('disk', max(1, round(2*scaleFac))));
    if ~any(darkBlob(:)), darkBlob = sub >= thr; end
    darkBlob = bwareafilt(darkBlob, 1);
    rp = regionprops(darkBlob, 'Centroid');
    if isempty(rp)
        ctr = seed; conf = 0; return;
    end
    ctr = [x0-1+rp(1).Centroid(1), y0-1+rp(1).Centroid(2)];

    % --- confidence: darkness contrast + avascularity around ctr ---------
    conf = foveaConfidence(bright, vesselMask, fovMask, ctr, odRadius);
end

% ========================================================================
function [cy, cx] = fovCentroid(fovMask, h, w)
    if any(fovMask(:))
        [yy, xx] = find(fovMask); cy = mean(yy); cx = mean(xx);
    else
        cy = h/2; cx = w/2;
    end
end

function conf = foveaConfidence(bright, vesselMask, fovMask, ctr, odRadius)
    [h, w] = size(bright);
    [X, Y] = meshgrid(1:w, 1:h);
    core = (X-ctr(1)).^2 + (Y-ctr(2)).^2 <= odRadius^2 & fovMask;
    ring = (X-ctr(1)).^2 + (Y-ctr(2)).^2 <= (2.5*odRadius)^2 & ...
           (X-ctr(1)).^2 + (Y-ctr(2)).^2 > odRadius^2 & fovMask;
    if ~any(core(:)) || ~any(ring(:)), conf = 0; return; end
    darkContrast = (mean(bright(ring)) - mean(bright(core)));
    darkContrast = max(0, min(1, darkContrast / 0.10));
    avascular = 1 - min(1, nnz(vesselMask & core)/max(1,nnz(core)) / 0.10);
    avascular = max(0, min(1, avascular));
    conf = 0.6*darkContrast + 0.4*avascular;
    conf = max(0, min(1, conf));
end
