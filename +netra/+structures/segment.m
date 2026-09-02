function cr = segment(cr, cfg)
%SEGMENT  Retinal structure segmentation (vessels, OD, fovea, quadrants).  [Phase 5 REAL]
%   cr = netra.structures.segment(cr, cfg)
%
%   Runs the REAL classical-CV structure pipeline on the enhanced image:
%     - netra.structures.vesselsFrangi -> vesselMask, vesselDensity, tortuosity
%     - netra.structures.locateOD      -> odCenter, odRadius (+ fallback)
%     - netra.structures.locateFovea   -> foveaCenter, maculaZone (+ fallback)
%     - netra.structures.quadrantMap   -> quadrantMap (0..4)
%
%   CONTRACT: one caseRecord in/out; may ADD fields, never delete/rename; never
%   writes to disk. Sets cr.provenance.structures = "REAL" (or "MOCK" if no
%   pixels). cr.timing.structures is written by runPipeline.
%
%   FALLBACKS (per the error-handling spec):
%     - OD confidence below threshold  -> odCenter = FOV centroid, odRadius =
%       odFallbackRadiusFraction*FOVradius, cr.structures.odFallback = true, and
%       a "ODLocalisationLowConfidence" flag appended to cr.routing.flags so the
%       case is reviewed rather than silently mis-analysed.
%     - Fovea confidence below threshold -> geometric-prior centre kept,
%       cr.structures.foveaFallback = true, "FoveaLocalisationLowConfidence" flag.
%     - Empty vessel mask -> density 0 (no divide-by-zero), "EmptyVesselMask" flag.
%
%   The masks (vesselMask, maculaZone, quadrantMap) are asserted to be exactly
%   size(enhanced,[1 2]) at the end - a size mismatch errors LOUDLY here rather
%   than silently corrupting Track B's ALA computation downstream.

    arguments
        cr  (1,1) struct
        cfg (1,1) struct
    end

    % Confidence gate for accepting a localisation over the fallback.
    OD_CONF_MIN    = 0.35;
    FOVEA_CONF_MIN = 0.30;

    % --- pick the working image: enhanced (preferred), else raw ----------
    [img, fovMask] = workingImage(cr);
    if isempty(img)
        cr.provenance.structures = "MOCK";       % preview-only: nothing to do
        return;
    end
    [H, W, ~] = size(img);
    cr.structures.odFallback    = false;
    cr.structures.foveaFallback = false;

    % --- vessels ---------------------------------------------------------
    [vesselMask, vinfo] = netra.structures.vesselsFrangi(img, fovMask, cfg);
    cr.structures.vesselMask    = vesselMask;
    cr.structures.vesselDensity = vinfo.density;     % 0 when FOV empty (guarded)
    cr.structures.tortuosity    = vinfo.tortuosity;
    if ~any(vesselMask(:))
        cr = addFlag(cr, "EmptyVesselMask");
    end

    % --- optic disc ------------------------------------------------------
    [odC, odR, odConf] = netra.structures.locateOD(img, fovMask, vesselMask, cfg);
    if odConf < OD_CONF_MIN
        fovR = sqrt(nnz(fovMask)/pi);
        [cy, cx] = localFovCentroid(fovMask, H, W);
        odC = [cx cy];
        odR = max(5, cfg.thresholds.structures.odFallbackRadiusFraction * fovR);
        cr.structures.odFallback = true;
        cr = addFlag(cr, "ODLocalisationLowConfidence");
    end
    cr.structures.odCenter = odC;
    cr.structures.odRadius = odR;

    % --- fovea -----------------------------------------------------------
    [fovC, fovConf] = netra.structures.locateFovea(img, fovMask, odC, odR, vesselMask, cfg);
    if fovConf < FOVEA_CONF_MIN
        cr.structures.foveaFallback = true;
        cr = addFlag(cr, "FoveaLocalisationLowConfidence");
        % keep fovC (the geometric-prior centre locateFovea returned)
    end
    cr.structures.foveaCenter = fovC;

    % --- macula zone: maculaRadiusDiscDiameters * disc DIAMETER ----------
    maculaR = cfg.thresholds.lesions.maculaRadiusDiscDiameters * (2*odR);
    [X, Y] = meshgrid(1:W, 1:H);
    maculaZone = (X-fovC(1)).^2 + (Y-fovC(2)).^2 <= maculaR^2 & fovMask;
    cr.structures.maculaZone = maculaZone;

    % --- quadrant map ----------------------------------------------------
    eye = "OD";
    if isfield(cr,'meta') && isfield(cr.meta,'eye'), eye = string(cr.meta.eye); end
    cr.structures.quadrantMap = netra.structures.quadrantMap( ...
        fovMask, odC, fovC, eye, cfg);

    % --- LOUD size assertions (protect Track B) --------------------------
    assertMask(cr.structures.vesselMask,  [H W], 'vesselMask');
    assertMask(cr.structures.maculaZone,  [H W], 'maculaZone');
    assertSize(cr.structures.quadrantMap, [H W], 'quadrantMap');

    cr.provenance.structures = "REAL";
end

% ========================================================================
function [img, fovMask] = workingImage(cr)
%WORKINGIMAGE  Prefer the enhanced frame + its FOV mask; else raw.
    img = []; fovMask = logical([]);
    if ~isempty(cr.img.enhanced)
        img = cr.img.enhanced;
    elseif ~isempty(cr.img.raw)
        img = cr.img.raw;
    else
        return;
    end
    [H, W, ~] = size(img);
    % Prefer the RESIZED FOV mask (matches enhanced); fall back to the raw-frame
    % mask only if it happens to match, else the whole frame (defensive).
    if isfield(cr.preproc,'fovMaskResized') && ...
            isequal(size(cr.preproc.fovMaskResized), [H W])
        fovMask = cr.preproc.fovMaskResized;
    elseif ~isempty(cr.img.fovMask) && isequal(size(cr.img.fovMask), [H W])
        fovMask = cr.img.fovMask;
    else
        fovMask = true(H, W);
    end
end

function [cy, cx] = localFovCentroid(fovMask, h, w)
    if any(fovMask(:))
        [yy, xx] = find(fovMask); cy = mean(yy); cx = mean(xx);
    else
        cy = h/2; cx = w/2;
    end
end

function cr = addFlag(cr, flag)
%ADDFLAG  Append a routing flag once (idempotent).
    if ~isfield(cr,'routing') || ~isfield(cr.routing,'flags')
        return;
    end
    if ~any(cr.routing.flags == flag)
        cr.routing.flags(end+1) = flag;
    end
end

function assertMask(m, sz, name)
    if ~islogical(m) || ~isequal(size(m), sz)
        error('NETRA:structures:maskContract', ...
            '%s must be logical %dx%d, got %s %s.', name, sz(1), sz(2), ...
            class(m), mat2str(size(m)));
    end
end

function assertSize(m, sz, name)
    if ~isequal(size(m), sz)
        error('NETRA:structures:maskContract', ...
            '%s must be %dx%d, got %s.', name, sz(1), sz(2), mat2str(size(m)));
    end
end
