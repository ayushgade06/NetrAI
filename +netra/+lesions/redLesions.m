function [maMask, heMask, stats] = redLesions(img, fovMask, vesselMask, cfg)
%REDLESIONS  Detect red lesions (microaneurysms + haemorrhages).  [Phase 6]
%   [maMask, heMask, stats] = netra.lesions.redLesions(img, fovMask, vesselMask, cfg)
%
%   Red (dark) lesions - microaneurysms and haemorrhages - are dark blobs on the
%   green channel that are NOT vessels. The classic separation from vessels is a
%   morphological opening with LINE structuring elements at many orientations:
%   a line SE longer than a lesion but thinner than / aligned to a vessel keeps
%   vessels (elongated) while erasing compact lesions. Taking, at each pixel, the
%   MAX opening over orientations reconstructs the whole vessel tree (a vessel
%   survives the opening at the orientation it is aligned to); subtracting that
%   from the original leaves the compact lesions as a residual.
%
%   PIPELINE (on the inverted green channel so lesions are bright):
%     1. inv = 1 - green, restricted to FOV.
%     2. vesselMap = max over K line-SE openings (K = seOrientations, length =
%        seLength, disc-scaled). This is the "everything elongated" image.
%     3. residual = inv - vesselMap  (compact dark spots that no line kept).
%     4. adaptive threshold: residual > redThresholdFactor * std(residual in FOV).
%     5. remove anything overlapping the (dilated) vessel mask and the OD? -
%        the OD is bright, not a red lesion, so it is naturally absent from the
%        inverted-dark residual; vessels are removed explicitly.
%     6. regionprops -> classify each region MA vs HE (classifyMAvsHE).
%
%   OUTPUT:
%     maMask, heMask  logical HxW, true where each red-lesion class is present
%     stats           struct with per-region .centroids/.areas/.labels and the
%                     residual/threshold used (for tests + tuning).
%
%   The number of orientations and SE length come from config; per the runtime
%   budget, reduce seOrientations before sacrificing correctness. odRadius for
%   the shape scaling is read from stats-free config default if absent (the
%   caller - detect - passes the measured odRadius via cfg.thresholds.lesions
%   at runtime through a transient field; here we accept it on cfg).

    arguments
        img
        fovMask logical
        vesselMask logical
        cfg (1,1) struct
    end

    L = cfg.thresholds.lesions;
    [h, w, ~] = size(img);
    scaleFac = min(h,w) / cfg.thresholds.preproc.targetSize;

    maMask = false(h, w); heMask = false(h, w);
    stats = struct('centroids', nan(0,2), 'areas', nan(0,1), ...
                   'labels', strings(0,1), 'threshold', NaN);
    if isempty(fovMask) || ~any(fovMask(:)), return; end

    % odRadius for shape scaling: passed transiently by detect on cfg, else
    % fall back to the 512-reference so thresholds still apply.
    if isfield(cfg,'odRadius') && isfinite(cfg.odRadius)
        odRadius = cfg.odRadius;
    else
        odRadius = L.referenceOdRadius512 * scaleFac;
    end

    % --- inverted green inside FOV --------------------------------------
    if size(img,3) == 3, g = double(img(:,:,2)); else, g = double(img); end
    g = g/255;
    inv = 1 - g;
    innerFov = imerode(fovMask, strel('disk', max(2, round(4*scaleFac))));
    inv(~innerFov) = 0;

    % --- vessel map: max over line-SE openings --------------------------
    seLen = max(3, round(L.seLength * scaleFac));
    K = max(2, L.seOrientations);
    vesselMap = zeros(h, w);
    for k = 0:K-1
        ang = 180 * k / K;
        se = strel('line', seLen, ang);
        vesselMap = max(vesselMap, imopen(inv, se));
    end

    residual = inv - vesselMap;                   % compact dark spots
    residual(residual < 0) = 0;
    residual(~innerFov) = 0;

    % --- adaptive threshold ---------------------------------------------
    rIn = residual(innerFov);
    sigma = std(rIn);
    thr = L.redThresholdFactor * sigma;
    stats.threshold = thr;
    cand = residual > thr & innerFov;

    % remove vessel pixels (dilated) - line openings leave thin vessel remnants
    vdil = imdilate(vesselMask, strel('disk', max(1, round(2*scaleFac))));
    cand = cand & ~vdil;
    cand = imopen(cand, strel('disk', 1));         % drop single-pixel noise
    if ~any(cand(:)), return; end

    % --- regionprops + per-region MA/HE classification ------------------
    cc = bwconncomp(cand);
    rp = regionprops(cc, 'Area','Centroid','Eccentricity','Perimeter','PixelIdxList');
    minArea = max(3, round(4*scaleFac^2));         % drop specks below sensor scale
    cents = nan(0,2); ars = nan(0,1); labs = strings(0,1);
    for i = 1:numel(rp)
        if rp(i).Area < minArea, continue; end
        lab = netra.lesions.classifyMAvsHE(rp(i), odRadius, cfg);
        idx = cc.PixelIdxList{i};
        if lab == "MA", maMask(idx) = true; else, heMask(idx) = true; end
        cents(end+1,:) = rp(i).Centroid;  %#ok<AGROW>
        ars(end+1,1)   = rp(i).Area;      %#ok<AGROW>
        labs(end+1,1)  = lab;             %#ok<AGROW>
    end
    stats.centroids = cents; stats.areas = ars; stats.labels = labs;
end
