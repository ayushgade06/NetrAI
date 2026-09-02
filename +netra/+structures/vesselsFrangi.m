function [mask, info] = vesselsFrangi(img, fovMask, cfg)
%VESSELSFRANGI  Multi-scale vesselness segmentation of the retinal vasculature.  [Phase 5]
%   [mask, info] = netra.structures.vesselsFrangi(img, fovMask, cfg)
%
%   Segments blood vessels with a multi-scale Frangi/Hessian vesselness filter
%   on the INVERTED green channel (vessels are dark on the green channel, so
%   inverting makes them bright ridges the filter responds to). Uses MATLAB's
%   fibermetric (Image Processing Toolbox), which is a documented Frangi-family
%   ridge detector, evaluated at the scales in cfg.thresholds.structures
%   .frangiScales (vessel radii in px). The per-scale responses are combined by
%   a max (strongest ridge at any scale wins).
%
%   POST-PROCESSING:
%     - hysteresis threshold: strong seeds at vesselThreshold, grown into weak
%       (half-threshold) connected pixels, so faint vessel continuations are
%       kept while isolated weak noise is dropped.
%     - restrict to a slightly eroded FOV so the bright FOV rim is not caught.
%     - length-based pruning: remove connected components shorter than
%       minVesselLength (disc-scaled), which are spurs / lesion edges, not vessels.
%
%   info fields:
%     density     vessel area / FOV area (0..1)   [0 if the FOV is empty]
%     tortuosity  mean (skeleton path length / end-to-end distance) over the
%                 longest branches; >=1, higher = more tortuous. 1 if no vessels.
%     scales      the scales actually used
%     threshold   the hysteresis high threshold used
%
%   All parameters are resolution-aware: scales/lengths are given at the 512px
%   target and scaled by the frame size so the same physical vessels are found
%   at any resolution.

    arguments
        img
        fovMask logical
        cfg (1,1) struct
    end

    st = cfg.thresholds.structures;
    [h, w, ~] = size(img);

    if isempty(fovMask) || ~any(fovMask(:))
        mask = false(h, w);
        info = struct('density',0,'tortuosity',1,'scales',[],'threshold',st.vesselThreshold);
        return;
    end

    % --- green channel, inverted, contrast-normalised inside FOV ---------
    if size(img,3) == 3, g = double(img(:,:,2)); else, g = double(img); end
    g = g / 255;
    inv = 1 - g;                                 % vessels -> bright ridges
    inv(~fovMask) = 0;

    % --- resolution-aware scales ----------------------------------------
    scaleFac = min(h,w) / cfg.thresholds.preproc.targetSize;
    scales = max(1, round(st.frangiScales(:)' * scaleFac));

    % --- multi-scale vesselness -----------------------------------------
    % fibermetric returns a 0..1 tubular-structure response; take the max
    % response over scales (strongest ridge at the natural vessel width).
    V = fibermetric(inv, scales, 'ObjectPolarity', 'bright', 'StructureSensitivity', 0.5);
    if size(V,3) > 1, V = max(V, [], 3); end
    V(~fovMask) = 0;
    if max(V(:)) > 0, V = V / max(V(:)); end     % normalise 0..1

    % --- hysteresis threshold -------------------------------------------
    hi = st.vesselThreshold;
    lo = hi/2;
    strong = V >= hi;
    weak   = V >= lo;
    mask = imreconstruct(strong & fovMask, weak & fovMask);

    % Keep off the FOV rim (bright edge can masquerade as a vessel).
    rimErode = max(2, round(0.02*sqrt(nnz(fovMask)/pi)));
    innerFov = imerode(fovMask, strel('disk', rimErode));
    mask = mask & innerFov;

    % --- length-based spur pruning --------------------------------------
    minLen = max(3, round(st.minVesselLength * scaleFac));
    mask = bwareaopen(mask, minLen);

    % --- density + tortuosity -------------------------------------------
    density = nnz(mask) / nnz(fovMask);          % FOV empty already handled
    tortuosity = localTortuosity(mask);

    info = struct('density', density, 'tortuosity', tortuosity, ...
        'scales', scales, 'threshold', hi);
end

% ========================================================================
function tort = localTortuosity(mask)
%LOCALTORTUOSITY  Mean path/chord ratio of the longest skeleton branches.
%   Skeletonise, break into branches, and for the longest few compute
%   (number of skeleton pixels along the branch) / (Euclidean endpoint distance).
%   A straight vessel -> ~1; a wavy one -> larger. Returns 1 when there is no
%   usable vessel, so density-free callers never see NaN.
    if nnz(mask) == 0, tort = 1; return; end
    skel = bwmorph(mask, 'thin', Inf);
    branchpts = bwmorph(skel, 'branchpoints');
    branches = skel & ~imdilate(branchpts, ones(3));   % cut at junctions
    cc = bwconncomp(branches);
    if cc.NumObjects == 0, tort = 1; return; end
    lens = cellfun(@numel, cc.PixelIdxList);
    [~, ord] = sort(lens, 'descend');
    take = ord(1:min(20, numel(ord)));           % longest 20 branches
    ratios = [];
    [H, W] = size(mask);
    for i = take
        idx = cc.PixelIdxList{i};
        if numel(idx) < 5, continue; end
        [yy, xx] = ind2sub([H W], idx);
        % endpoints ~ the two extremal points along the principal axis
        d2 = (xx - xx').^2 + (yy - yy').^2;
        chord = sqrt(max(d2(:)));
        if chord > 0
            ratios(end+1) = numel(idx) / chord; %#ok<AGROW>
        end
    end
    if isempty(ratios), tort = 1; else, tort = max(1, mean(ratios)); end
end
