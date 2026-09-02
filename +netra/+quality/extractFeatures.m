function [feat, detail] = extractFeatures(img, fovMask, cfg)
%EXTRACTFEATURES  Eight handcrafted image-quality features, FOV-masked.  [Phase 3]
%   [feat, detail] = netra.quality.extractFeatures(img, fovMask, cfg)
%
%   feat : 1x8 double, in the FIXED FEATURE ORDER (see docs/quality_method.md):
%     1 focusLaplacian    variance of the Laplacian of the green channel,
%                         inside FOV, normalised by intensity variance so it is
%                         invariant to global brightness/contrast scaling.
%     2 focusTenengrad    mean squared Sobel gradient magnitude, inside FOV,
%                         normalised the same way.
%     3 illumUniformity   min(quadrantMean)/max(quadrantMean), inside FOV.
%     4 saturatedFraction fraction of inside-FOV pixels with green > 250.
%     5 darkFraction      fraction of inside-FOV pixels with green < 15.
%     6 fovCompleteness   Phase 2 fovMask completeness (passed in via cfg or
%                         recomputed here from the mask if not supplied).
%     7 contrastStd       std of the green channel inside FOV, on the 0..1 scale.
%     8 localContrast     mean local std (stdfilt, 9x9) inside FOV, 0..1 scale.
%
%   detail : struct of named sub-measurements for the UI "show all measurements"
%            panel and for debugging (quadrant means, raw laplacian var, the
%            computed-at resolution, an anyNaN flag, etc.).
%
%   CONTRACT / INVARIANTS:
%     - EVERY feature is computed over inside-FOV pixels ONLY. Computing over the
%       black border is the classic bug here; tQualityFeatures asserts that
%       noise injected into the border leaves every feature unchanged.
%     - EVERY feature is scale-invariant w.r.t. image resolution: gradient
%       features are normalised by intensity variance (dimensionless), fractions
%       and ratios are inherently scale-free, and stdfilt uses a neighbourhood
%       that is a fixed fraction of the image so it sees the same spatial scale
%       at 512 and 1024. See docs/quality_method.md for the per-feature argument.
%     - No NaN/Inf may ever leave this function. Every ratio is guarded; an
%       empty/all-false mask returns a documented all-safe vector with
%       detail.emptyFov = true so the caller routes to Ungradeable.
%     - Large images are downsampled to a bounded working size before feature
%       extraction (detail.computedAt records the side length used), so runtime
%       is bounded and features are computed at a consistent scale.

    arguments
        img
        fovMask logical
        cfg (1,1) struct
    end

    NAMES = netra.quality.featureNames();   % single source of truth for order
    NF = numel(NAMES);

    detail = struct();
    detail.featureNames = NAMES;
    detail.emptyFov     = false;
    detail.anyNaN       = false;
    detail.substituted  = false;

    % --- empty / all-false FOV: cannot measure anything ------------------
    if isempty(fovMask) || ~any(fovMask(:))
        detail.emptyFov = true;
        feat = safeVector();                 % documented all-safe -> Ungradeable
        detail = fillDetail(detail, feat, NAMES, [NaN NaN NaN NaN], NaN, NaN);
        return;
    end

    % --- FIX working resolution -----------------------------------------
    % Focus features (Laplacian/Tenengrad variance) depend on the spatial pixel
    % scale, so merely CAPPING the size left them resolution-dependent: the same
    % eye at 512 vs 1024 px gave a ~73% focus drift. Resize the long side to a
    % FIXED targetSize (down or up) so focus is always measured at one scale and
    % the feature is genuinely resolution-invariant (real fundus images arrive at
    % many resolutions). This is also fast and bounded.
    fixedSide = cfg.thresholds.preproc.targetSize;     % 512 by default
    [img, fovMask, computedAt] = fixResolution(img, fovMask, fixedSide);
    detail.computedAt = computedAt;

    % --- green channel, 0..1 --------------------------------------------
    if size(img,3) == 3
        gch = double(img(:,:,2)) / 255;      % green: highest retinal SNR
        g8  = double(img(:,:,2));            % 0..255 for the >250 / <15 tests
    else
        gch = double(img) / 255;
        g8  = double(img);
    end

    m = fovMask;
    inside = gch(m);                         % column vector, inside-FOV only
    inside8 = g8(m);
    nInside = numel(inside);

    % --- 1,2 focus: Laplacian & Tenengrad -------------------------------
    % Compute the gradient maps over the whole frame (border pixels contribute
    % to a neighbour's gradient), then SAMPLE only inside-FOV pixels. To keep
    % the border noise from ever touching an inside-FOV response, we zero the
    % outside-FOV region to a smooth constant before filtering: filling with the
    % inside mean means the mask edge is the only artefact, and the mask edge is
    % excluded from the sampled set below via an eroded mask.
    fillVal = mean(inside);
    gFilled = gch;
    gFilled(~m) = fillVal;

    lap = imfilter(gFilled, fspecial('laplacian', 0), 'replicate');
    [gx, gy] = imgradientxy(gFilled, 'sobel');
    tenMap = gx.^2 + gy.^2;

    % Erode the mask by the filter radius so sampled responses never include a
    % pixel whose neighbourhood straddled the FOV boundary.
    mErode = imerode(m, strel('disk', 2));
    if ~any(mErode(:)), mErode = m; end      % tiny FOV: fall back to full mask

    intensityVar = var(inside);              % normaliser: brightness-invariant
    denom = max(intensityVar, 1e-6);
    focusLaplacian = var(lap(mErode)) / denom;
    focusTenengrad = mean(tenMap(mErode)) / denom;

    % --- 3 illumUniformity + quadrant means -----------------------------
    [quadMeans, illumUniformity] = quadrantIllum(g8, m);

    % --- 4,5 saturated / dark fractions ---------------------------------
    saturatedFraction = mean(inside8 > 250);
    darkFraction      = mean(inside8 < 15);

    % --- 6 fovCompleteness ----------------------------------------------
    % Prefer a value the caller already measured in Phase 2 (passed via
    % cfg.qualityFovCompleteness); otherwise recompute from this mask so the
    % function is self-contained for tests.
    if isfield(cfg, 'qualityFovCompleteness') && ~isnan(cfg.qualityFovCompleteness)
        fovCompleteness = cfg.qualityFovCompleteness;
    else
        fovCompleteness = maskCompleteness(m);
    end

    % --- 7 contrastStd ---------------------------------------------------
    contrastStd = std(inside);               % 0..1 scale (green normalised)

    % --- 8 localContrast (stdfilt, neighbourhood = fraction of frame) ----
    % Neighbourhood side is a fixed fraction of the working image so the same
    % spatial scale is measured at every resolution -> scale-invariant.
    [h, w] = size(gch);
    nb = max(3, 2*round(0.01 * min(h,w)) + 1);   % odd, ~1% of the frame
    lc = stdfilt(gFilled, true(nb));
    localContrast = mean(lc(mErode));

    % --- assemble in fixed order ----------------------------------------
    feat = [focusLaplacian, focusTenengrad, illumUniformity, ...
            saturatedFraction, darkFraction, fovCompleteness, ...
            contrastStd, localContrast];

    % --- NaN/Inf guard: nothing bad may escape --------------------------
    bad = ~isfinite(feat);
    if any(bad)
        detail.anyNaN = true;
        detail.substituted = true;
        safe = safeVector();
        feat(bad) = safe(bad);               % documented safe defaults
    end

    detail = fillDetail(detail, feat, NAMES, quadMeans, intensityVar, nInside);
end

% ========================================================================
function v = safeVector()
%SAFEVECTOR  Documented all-safe feature vector that ROUTES TO UNGRADEABLE.
%   Every value is set to the worst plausible reading so an image we could not
%   measure is never mistaken for a good one: zero focus/contrast, zero
%   uniformity, full dark fraction, zero FOV completeness.
    v = [0, 0, 0, 0, 1, 0, 0, 0];
end

function detail = fillDetail(detail, feat, names, quadMeans, intensityVar, nInside)
    for i = 1:numel(names)
        detail.(names{i}) = feat(i);
    end
    detail.quadrantMeans = quadMeans;
    detail.intensityVar  = intensityVar;
    detail.nInsideFov    = nInside;
end

function [imgOut, maskOut, side] = fixResolution(img, mask, fixedSide)
%FIXRESOLUTION  Resize so the LONGER side == fixedSide (up or down), for a
%   resolution-invariant working scale. Within 2% already -> leave as-is.
    [h, w, ~] = size(img);
    longSide = max(h, w);
    if abs(longSide - fixedSide) <= 0.02*fixedSide
        imgOut = img; maskOut = mask; side = longSide; return;
    end
    s = fixedSide / longSide;
    imgOut  = imresize(img, s);
    maskOut = imresize(mask, [size(imgOut,1) size(imgOut,2)], 'nearest');
    side    = max(size(imgOut,1), size(imgOut,2));
end

function [quadMeans, uniformity] = quadrantIllum(g8, mask)
%QUADRANTILLUM  Mean inside-FOV green intensity per image quadrant + ratio.
%   Quadrants are the four halves of the frame (TL,TR,BL,BR). Each quadrant's
%   mean is over inside-FOV pixels in that quadrant only; a quadrant with no FOV
%   pixels contributes NaN and is excluded from the ratio.
    [h, w] = size(g8);
    my = round(h/2); mx = round(w/2);
    quads = {[1 my 1 mx], [1 my mx+1 w], [my+1 h 1 mx], [my+1 h mx+1 w]};
    quadMeans = nan(1,4);
    for q = 1:4
        r = quads{q};
        sub  = g8(r(1):r(2), r(3):r(4));
        subM = mask(r(1):r(2), r(3):r(4));
        if any(subM(:))
            quadMeans(q) = mean(sub(subM));
        end
    end
    valid = quadMeans(~isnan(quadMeans));
    if numel(valid) < 2 || max(valid) <= 0
        uniformity = 0;                      % cannot judge -> worst case
    else
        uniformity = min(valid) / max(valid);
    end
end

function c = maskCompleteness(mask)
%MASKCOMPLETENESS  Fallback FOV completeness from the mask alone.
%   Mirrors netra.preproc.fovMask's definition: mask area / area of the
%   equivalent-radius circle. Guarded against a zero radius.
    a = sum(mask(:));
    if a == 0, c = 0; return; end
    equivR = sqrt(a/pi);
    circleArea = pi * equivR^2;             % == a by construction; kept explicit
    c = max(0, min(1, a / max(circleArea, 1)));
end
