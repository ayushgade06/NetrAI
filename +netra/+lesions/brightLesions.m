function [exMask, stats] = brightLesions(img, fovMask, odCenter, odRadius, cfg)
%BRIGHTLESIONS  Detect hard exudates (bright lesions).  [Phase 6]
%   [exMask, stats] = netra.lesions.brightLesions(img, fovMask, odCenter, odRadius, cfg)
%
%   Hard exudates are bright yellow lipid deposits. They are found on the green
%   channel (where they are bright, and the OD is also bright) by morphological
%   top-hat, which isolates small bright objects on a varying background.
%
%   CRITICAL - OD SUBTRACTION: the optic disc is the brightest object in a
%   fundus image and WILL be detected as a giant exudate if not removed. So the
%   DILATED OPTIC DISC REGION is zeroed from the candidate map before thresholding
%   (dilation = odDilationPx, disc/resolution scaled). This is mandatory; the
%   single most common bug in this module is the OD firing as EX. tLesions tests
%   this first.
%
%   PIPELINE:
%     1. green channel inside FOV.
%     2. top-hat with a disc SE (~ largest exudate radius) -> bright residual.
%     3. ZERO the dilated OD region (mandatory).
%     4. threshold at mean+k*std of the residual inside FOV.
%     5. filter by area (>= exMinArea, disc-scaled) and BOUNDARY SHARPNESS:
%        exudates have sharp edges; drusen/reflections are soft. Sharpness =
%        mean gradient magnitude on the region boundary; reject below
%        exSharpnessMin.
%
%   OUTPUT:
%     exMask  logical HxW, true where a hard exudate is present
%     stats   .centroids/.areas + the threshold and OD-region used, for tuning.

    arguments
        img
        fovMask logical
        odCenter (1,2) double
        odRadius (1,1) double
        cfg (1,1) struct
    end

    L = cfg.thresholds.lesions;
    [h, w, ~] = size(img);
    scaleFac = min(h,w) / cfg.thresholds.preproc.targetSize;

    exMask = false(h, w);
    stats = struct('centroids', nan(0,2), 'areas', nan(0,1), 'threshold', NaN);
    if isempty(fovMask) || ~any(fovMask(:)), return; end

    if size(img,3) == 3, g = double(img(:,:,2)); else, g = double(img); end
    g = g/255;
    innerFov = imerode(fovMask, strel('disk', max(2, round(4*scaleFac))));
    g(~innerFov) = 0;

    % --- top-hat: isolate small bright objects --------------------------
    seR = max(3, round(0.03 * sqrt(nnz(fovMask)/pi)));   % ~exudate scale
    th = imtophat(g, strel('disk', seR));

    % --- MANDATORY: zero the dilated optic disc region ------------------
    [X, Y] = meshgrid(1:w, 1:h);
    odDil = odRadius + max(L.odDilationPx*scaleFac, 0.3*odRadius);
    odRegion = (X-odCenter(1)).^2 + (Y-odCenter(2)).^2 <= odDil^2;
    th(odRegion) = 0;                              % OD can never be an exudate

    % --- threshold ------------------------------------------------------
    valid = th(innerFov & ~odRegion);
    if isempty(valid), return; end
    thr = mean(valid) + 3*std(valid);
    stats.threshold = thr;
    cand = th > thr & innerFov & ~odRegion;
    cand = imopen(cand, strel('disk', 1));
    if ~any(cand(:)), return; end

    % --- area + boundary-sharpness filtering ----------------------------
    minArea = max(round(L.exMinArea * scaleFac^2), 2);
    [gx, gy] = imgradientxy(g);
    gradMag = hypot(gx, gy);
    cc = bwconncomp(cand);
    rp = regionprops(cc, 'Area','Centroid','PixelIdxList');
    cents = nan(0,2); ars = nan(0,1);
    for i = 1:numel(rp)
        if rp(i).Area < minArea, continue; end
        regMask = false(h,w); regMask(rp(i).PixelIdxList) = true;
        edge = regMask & ~imerode(regMask, strel('disk',1));
        sharpness = mean(gradMag(edge));
        if ~isfinite(sharpness) || sharpness < L.exSharpnessMin, continue; end
        exMask(rp(i).PixelIdxList) = true;
        cents(end+1,:) = rp(i).Centroid; %#ok<AGROW>
        ars(end+1,1)   = rp(i).Area;     %#ok<AGROW>
    end
    stats.centroids = cents; stats.areas = ars;
end
