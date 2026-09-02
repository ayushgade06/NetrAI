function [mask, metrics] = fovMask(img, cfg)
%FOVMASK  Extract the circular field-of-view mask of a fundus image.
%   [mask, metrics] = netra.preproc.fovMask(img, cfg) returns a logical HxW
%   mask of the illuminated retinal disc (true inside the FOV, false on the
%   black surround), plus geometry metrics.
%
%   Method (Image Processing Toolbox, no third-party libs):
%     1. luminance -> threshold (Otsu via graythresh, or a fixed level from
%        cfg.thresholds.preproc.fovFixedThreshold) to separate lit disc from
%        the near-black border.
%     2. morphological close+open to remove specular dots and fill vessels.
%     3. imfill holes, then bwareafilt to the single largest component.
%
%   metrics fields:
%     completeness   (0..1) area of the mask / area of a circle fitted to it;
%                    ~1 for a complete round FOV, lower when the disc is clipped
%                    (partial FOV). Clamped to [0,1].
%     centerOffset   (1x2 px) [dx dy] of the mask centroid from the frame centre
%     estimatedRadius(px) equivalent-circle radius of the mask
%     boundingBox    [x y w h] tight box around the mask (regionprops convention)
%     areaFraction   mask area / frame area
%     method         "otsu" | "fixed" threshold actually used
%     thresholdLevel the 0..255 level applied
%
%   FALLBACK: if the mask is smaller than cfg.thresholds.preproc.fovMinAreaFraction
%   of the frame, or more than one large component survives, this returns a
%   FULL-FRAME mask (all true) with metrics.fallback=true and completeness set
%   from the raw lit fraction, so the caller can append "fovMaskFallback" and
%   let the quality stage handle the consequences. It never errors.

    arguments
        img
        cfg (1,1) struct
    end

    pp = cfg.thresholds.preproc;
    g = double(img);
    if size(g,3) == 3
        lum = 0.299*g(:,:,1) + 0.587*g(:,:,2) + 0.114*g(:,:,3);
    else
        lum = g;
    end
    [h, w] = size(lum);
    frameArea = h * w;

    % --- threshold -------------------------------------------------------
    lum8 = uint8(min(255, max(0, lum)));
    if strcmpi(pp.fovThresholdMethod, 'fixed')
        level = pp.fovFixedThreshold;                 % 0..255
        bw = lum8 > level;
        methodUsed = "fixed";
    else
        level = 255 * graythresh(lum8);               % Otsu, scaled to 0..255
        bw = imbinarize(lum8, level/255);
        methodUsed = "otsu";
    end

    % --- clean up --------------------------------------------------------
    % Radius scales with frame so it works at any resolution.
    rClose = max(2, round(0.01 * min(h,w)));
    rOpen  = max(2, round(0.01 * min(h,w)));
    bw = imclose(bw, strel('disk', rClose));   % bridge vessels / dark spots
    bw = imopen(bw,  strel('disk', rOpen));    % drop specular speckle
    bw = imfill(bw, 'holes');

    % --- component analysis ----------------------------------------------
    cc = bwconncomp(bw);
    metrics = struct();
    metrics.method = methodUsed;
    metrics.thresholdLevel = level;

    fallback = false;
    if cc.NumObjects == 0
        fallback = true;
    else
        % Keep the largest component; check whether a SECOND comparably-large
        % one exists (ambiguous FOV -> fall back).
        numPix = cellfun(@numel, cc.PixelIdxList);
        [sorted, ord] = sort(numPix, 'descend');
        largest = sorted(1);
        maskLargest = false(h, w);
        maskLargest(cc.PixelIdxList{ord(1)}) = true;

        if largest / frameArea < pp.fovMinAreaFraction
            fallback = true;                         % disc too small -> unreliable
        elseif numel(sorted) >= 2 && sorted(2) > 0.5*largest
            fallback = true;                         % two big blobs -> ambiguous
        end
    end

    if fallback
        mask = true(h, w);
        metrics.fallback       = true;
        metrics.areaFraction   = 1;
        litFrac = mean(bw(:));                       % how much was actually lit
        metrics.completeness   = max(0, min(1, litFrac));
        metrics.centerOffset   = [0 0];
        metrics.estimatedRadius = sqrt(frameArea/pi);
        metrics.boundingBox    = [1 1 w h];
        return;
    end

    mask = maskLargest;
    metrics.fallback = false;

    % --- geometry --------------------------------------------------------
    st = regionprops(mask, 'Centroid', 'BoundingBox', 'Area', ...
        'EquivDiameter', 'MajorAxisLength', 'MinorAxisLength');
    area = st.Area;
    metrics.areaFraction    = area / frameArea;
    metrics.estimatedRadius = st.EquivDiameter / 2;
    metrics.boundingBox     = st.BoundingBox;
    metrics.centerOffset    = st.Centroid - [w/2, h/2];

    % Completeness: how close the mask is to a FULL circle whose diameter is the
    % disc's widest extent. Using EquivDiameter here was a bug: EquivDiameter is
    % the diameter of a circle with the SAME AREA as the mask, so pi*r^2 == area
    % by definition and the ratio was always ~1, even for a clipped disc. Compare
    % instead to a circle of the MAJOR-AXIS radius: a complete round FOV -> ratio
    % ~1, a clipped (partial) FOV keeps a near-full major axis but less area ->
    % ratio < 1.
    rFull = st.MajorAxisLength / 2;
    circleArea = pi * rFull^2;
    if circleArea > 0
        metrics.completeness = max(0, min(1, area / circleArea));
    else
        metrics.completeness = 0;
    end
end
