function cr = enhance(cr, cfg)
%ENHANCE  Adaptive fundus enhancement: FOV/crop + illum/CLAHE/denoise.  [Phase 4 REAL]
%   cr = netra.preproc.enhance(cr, cfg)
%
%   Runs the full REAL preprocessing stage on cr.img.raw:
%     1. FOV mask (netra.preproc.fovMask)            -> cr.img.fovMask
%     2. crop to FOV + square-pad + resize           -> cr.img.enhanced (geom)
%     3. ADAPTIVE illumination normalisation, CLAHE, and denoising, each fired
%        ONLY when the measured quality indicates it is needed. This is what
%        makes the chip list differ between a clean and a borderline image.
%     4. Ben-Graham normalisation                    -> cr.img.modelInput (CNN)
%
%   ADAPTIVE TRIGGERS (all thresholds from cfg.thresholds.preproc):
%     - illumNormalize fires when the FOV illumination uniformity is below
%       uniformityTrigger (uneven lighting to flatten).
%     - claheAdaptive ALWAYS fires (it is the core contrast step) but its CLIP
%       LIMIT is computed from the measured contrast deficit, so a contrasty
%       image gets a gentle clip and a flat image a strong one - adaptive in
%       strength even when always present.
%     - denoise fires only when a noise estimate exceeds denoiseTrigger.
%   The uniformity/contrast measures reuse quality subscores when the quality
%   stage has already run (cr.quality.illum / .contrast are 0..1); otherwise
%   they are measured here so enhance is self-contained.
%
%   OUTPUTS written:
%     cr.img.enhanced   uint8  HxWx3  (human display, enhanced)
%     cr.img.modelInput single HxWx3  (Ben-Graham, for Track B's CNN)
%     cr.img.displayRGB uint8  HxWx3  (= enhanced)
%     cr.preproc.appliedSteps / claheClip / illumApplied / denoiseApplied
%     cr.provenance.preproc = "REAL"
%
%   ERROR HANDLING: if any enhancement step yields NaN, Inf, or a saturated
%   constant image, the enhanced buffer REVERTS to the geometry-only crop, a
%   step "enhancementReverted" is logged, and the pipeline continues.
%
%   NO PIXELS: a preview-only case (empty cr.img.raw) records the intended step
%   flags, leaves buffers empty, and tags provenance "MOCK" (nothing measured).

    arguments
        cr  (1,1) struct
        cfg (1,1) struct
    end

    pp = cfg.thresholds.preproc;

    % --- preview-only case: nothing to enhance --------------------------
    if isempty(cr.img.raw)
        cr.preproc.appliedSteps   = strings(1,0);
        cr.preproc.claheClip      = NaN;
        cr.preproc.illumApplied   = false;
        cr.preproc.denoiseApplied = false;
        cr.provenance.preproc     = "MOCK";
        return;
    end

    steps = strings(1,0);
    img = cr.img.raw;

    % --- 1. FOV mask -----------------------------------------------------
    [mask, m] = netra.preproc.fovMask(img, cfg);
    cr.img.fovMask = mask;
    cr.quality.fovCompleteness = m.completeness;
    steps(end+1) = "fovMask";
    if isfield(m,'fallback') && m.fallback
        steps(end+1) = "fovMaskFallback";
    end

    % --- 2. crop to FOV, pad square, resize ------------------------------
    [geom, maskR, info] = netra.preproc.cropResize(img, mask, cfg);
    cr.preproc.cropInfo = info;
    steps(end+1) = "cropResize";

    % maskR is the resized FOV mask (matches cr.img.enhanced). Stash it so the
    % structures/lesions stages mask against the ENHANCED frame, not the
    % original-resolution cr.img.fovMask (which matches cr.img.raw). This is an
    % additive field; cr.img.fovMask keeps its documented raw-frame meaning.
    fovMask = maskR;
    cr.preproc.fovMaskResized = maskR;

    % --- measure what drives the adaptive decisions ----------------------
    [uniformity, contrastMeasure] = localMeasures(geom, fovMask, cr, cfg);

    working = geom;                              % pixels we progressively enhance

    % --- 3a. adaptive illumination normalisation -------------------------
    illumApplied = false;
    if uniformity < pp.uniformityTrigger
        [working, illStep] = netra.preproc.illumNormalize(working, fovMask, cfg);
        steps = [steps, illStep];
        illumApplied = true;
        % Contrast may change after flattening; re-measure for the CLAHE clip.
        contrastMeasure = localContrast(working, fovMask);
    else
        steps(end+1) = "illumNormalize(skipped: uniform)";
    end

    % --- 3b. adaptive CLAHE (always on; clip from contrast deficit) ------
    [working, clip] = netra.preproc.claheAdaptive(working, fovMask, contrastMeasure, cfg);
    steps(end+1) = "CLAHE(clip=" + sprintf('%.3f', clip) + ")";

    % --- 3c. optional denoise --------------------------------------------
    before = working;
    working = netra.preproc.denoise(working, cfg);
    denoiseApplied = ~isequal(working, before);
    if denoiseApplied
        steps(end+1) = "denoise(Wiener)";
    else
        steps(end+1) = "denoise(skipped: low noise)";
    end

    % --- revert guard: NaN / Inf / saturated-constant --------------------
    if isBadImage(working)
        working = geom;                          % fall back to geometry-only
        clip = pp.claheClipMin;
        illumApplied = false;
        denoiseApplied = false;
        steps(end+1) = "enhancementReverted";
    end

    enhanced = working;
    if ~isa(enhanced,'uint8'), enhanced = im2uint8(enhanced); end

    % --- 4. Ben-Graham model input ---------------------------------------
    modelInput = netra.preproc.benGraham(enhanced, fovMask, cfg);
    steps(end+1) = "benGraham(modelInput)";

    % --- write buffers + record ------------------------------------------
    cr.img.enhanced   = enhanced;
    cr.img.displayRGB = enhanced;
    cr.img.modelInput = modelInput;

    cr.preproc.appliedSteps   = steps;
    cr.preproc.claheClip      = clip;
    cr.preproc.illumApplied   = illumApplied;
    cr.preproc.denoiseApplied = denoiseApplied;
    cr.provenance.preproc     = "REAL";
end

% ========================================================================
function [uniformity, contrastMeasure] = localMeasures(img, fovMask, cr, cfg) %#ok<INUSD>
%LOCALMEASURES  Illumination uniformity + contrast, reusing quality if present.
    % Contrast: prefer the quality subscore (0..1) if the quality stage ran.
    if isfield(cr,'quality') && isfinite(cr.quality.contrast)
        contrastMeasure = cr.quality.contrast;
    else
        contrastMeasure = localContrast(img, fovMask);
    end
    if isfield(cr,'quality') && isfinite(cr.quality.illum)
        uniformity = cr.quality.illum;
    else
        uniformity = localUniformity(img, fovMask);
    end
end

function c = localContrast(img, fovMask)
%LOCALCONTRAST  Std of the green channel inside the FOV, 0..1 scale.
    if size(img,3) == 3, g = double(img(:,:,2))/255; else, g = double(img)/255; end
    if any(fovMask(:)), c = std(g(fovMask)); else, c = std(g(:)); end
end

function u = localUniformity(img, fovMask)
%LOCALUNIFORMITY  min/max quadrant mean green intensity inside the FOV.
    if size(img,3) == 3, g = double(img(:,:,2)); else, g = double(img); end
    [h,w] = size(g); my = round(h/2); mx = round(w/2);
    quads = {[1 my 1 mx],[1 my mx+1 w],[my+1 h 1 mx],[my+1 h mx+1 w]};
    mu = nan(1,4);
    for q = 1:4
        r = quads{q}; sub = g(r(1):r(2),r(3):r(4)); sm = fovMask(r(1):r(2),r(3):r(4));
        if any(sm(:)), mu(q) = mean(sub(sm)); end
    end
    v = mu(~isnan(mu));
    if numel(v) < 2 || max(v) <= 0, u = 0; else, u = min(v)/max(v); end
end

function bad = isBadImage(img)
%ISBADIMAGE  True if the image is non-finite or a near-constant (saturated).
    d = double(img);
    if any(~isfinite(d(:))), bad = true; return; end
    bad = std(d(:)) < 1e-3;                       % collapsed to a flat field
end
