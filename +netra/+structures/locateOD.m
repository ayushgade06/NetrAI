function [ctr, rad, conf] = locateOD(img, fovMask, vesselMask, cfg)
%LOCATEOD  Locate the optic disc.  [Phase 5]
%   [ctr, rad, conf] = netra.structures.locateOD(img, fovMask, vesselMask, cfg)
%
%   The optic disc is the brightest, roughly circular region of the retina and
%   the point where the major vessels converge. This finds it by:
%     1. VESSEL INPAINTING: remove the dark vessels from the (green+red) bright
%        channel so they do not fragment the bright disc blob, via grayscale
%        morphological closing guided by the dilated vessel mask.
%     2. BRIGHT-REGION CANDIDATE: smooth, then take the centroid of the
%        brightest odSearchTopPercent of inside-FOV pixels as the coarse centre.
%     3. HOUGH REFINEMENT: search for a circle in odRadiusRange (disc-scaled)
%        near the candidate with imfindcircles; if found, use its centre/radius.
%     4. VALIDATION: confidence from (a) how bright the disc region is vs the
%        retina and (b) local vessel-convergence density around the centre. Low
%        confidence -> the caller applies the FOV-centroid fallback.
%
%   OUTPUT:
%     ctr  [x y] px in the img frame
%     rad  disc radius px
%     conf 0..1 confidence. The CALLER (segment) decides the fallback when this
%          is below its threshold; this function always returns its best guess.
%
%   Radii are given at 512px in cfg and scaled by the frame size, so the search
%   band tracks the true disc size at any resolution.

    arguments
        img
        fovMask logical
        vesselMask logical
        cfg (1,1) struct
    end

    st = cfg.thresholds.structures;
    [h, w, ~] = size(img);
    scaleFac = min(h,w) / cfg.thresholds.preproc.targetSize;

    % Default (degenerate) return: FOV centroid, config fallback radius.
    fovR = sqrt(nnz(fovMask)/pi);
    [cy, cx] = fovCentroid(fovMask, h, w);
    ctr = [cx cy];
    rad = max(5, st.odFallbackRadiusFraction * fovR);
    conf = 0;
    if ~any(fovMask(:)), return; end

    % --- bright channel: mean of green+red (disc is bright in both) ------
    if size(img,3) == 3
        bright = (double(img(:,:,1)) + double(img(:,:,2))) / 2;
    else
        bright = double(img);
    end
    bright = bright / 255;
    bright(~fovMask) = 0;

    % --- inpaint vessels: close over the dilated vessel mask -------------
    vdil = imdilate(vesselMask, strel('disk', max(1, round(3*scaleFac))));
    filled = bright;
    if any(vdil(:))
        closed = imclose(bright, strel('disk', max(2, round(5*scaleFac))));
        filled(vdil) = closed(vdil);
    end
    filled = imgaussfilt(filled, max(1, 4*scaleFac));
    filled(~fovMask) = 0;

    % --- bright-region candidate ----------------------------------------
    inVals = filled(fovMask);
    thr = prctile(inVals, 100 - st.odSearchTopPercent);
    brightBlob = filled >= thr & fovMask;
    brightBlob = imopen(brightBlob, strel('disk', max(1, round(3*scaleFac))));
    if ~any(brightBlob(:)), brightBlob = filled >= thr & fovMask; end
    brightBlob = bwareafilt(brightBlob, 1);      % largest bright region
    rp = regionprops(brightBlob, 'Centroid', 'EquivDiameter');
    if ~isempty(rp)
        cand = rp(1).Centroid;                   % [x y]
        candR = rp(1).EquivDiameter/2;
    else
        cand = [cx cy]; candR = rad;
    end

    % --- Hough refinement in the disc-scaled radius band -----------------
    rMin = round(st.odRadiusRange(1) * scaleFac);
    rMax = round(st.odRadiusRange(2) * scaleFac);
    rMin = max(5, rMin); rMax = max(rMin+2, rMax);
    ctr = cand; rad = max(candR, rMin);
    try
        [centers, radii, metric] = imfindcircles(im2uint8(filled), [rMin rMax], ...
            'ObjectPolarity','bright', 'Sensitivity', 0.95);
        if ~isempty(centers)
            % nearest strong circle to the bright candidate
            d = hypot(centers(:,1)-cand(1), centers(:,2)-cand(2));
            [~, best] = min(d - 0.5*metric*rMax);   % prefer near + strong
            % Only accept the Hough circle if its centre lands INSIDE the FOV;
            % imfindcircles can return a centre in the black border, which would
            % put the OD ring off-retina. The bright-blob candidate is always
            % inside, so fall back to it otherwise.
            cxH = round(centers(best,1)); cyH = round(centers(best,2));
            inBounds = cxH>=1 && cxH<=w && cyH>=1 && cyH<=h && fovMask(cyH,cxH);
            if d(best) < 3*rMax && inBounds
                ctr = centers(best,:);
                rad = radii(best);
            end
        end
    catch
        % imfindcircles unavailable/failed: keep the bright-blob estimate.
    end

    % Final safety: guarantee the returned centre is inside the FOV (the demo
    % overlay draws the OD ring here). If a degenerate path left it outside,
    % snap to the FOV centroid.
    cxr = round(ctr(1)); cyr = round(ctr(2));
    if cxr<1 || cxr>w || cyr<1 || cyr>h || ~fovMask(cyr,cxr)
        ctr = [cx cy];
    end

    % --- validation confidence ------------------------------------------
    conf = odConfidence(filled, vesselMask, fovMask, ctr, rad);
end

% ========================================================================
function [cy, cx] = fovCentroid(fovMask, h, w)
    if any(fovMask(:))
        [yy, xx] = find(fovMask);
        cy = mean(yy); cx = mean(xx);
    else
        cy = h/2; cx = w/2;
    end
end

function conf = odConfidence(bright, vesselMask, fovMask, ctr, rad)
%ODCONFIDENCE  Combine disc brightness contrast and vessel convergence.
    [h, w] = size(bright);
    [X, Y] = meshgrid(1:w, 1:h);
    inDisc = (X-ctr(1)).^2 + (Y-ctr(2)).^2 <= rad^2 & fovMask;
    ring   = (X-ctr(1)).^2 + (Y-ctr(2)).^2 <= (2.5*rad)^2 & ...
             (X-ctr(1)).^2 + (Y-ctr(2)).^2 > rad^2 & fovMask;
    if ~any(inDisc(:)) || ~any(ring(:)), conf = 0; return; end

    % (a) brightness contrast: disc brighter than its surround -> [0,1]
    contrast = (mean(bright(inDisc)) - mean(bright(ring)));
    contrast = max(0, min(1, contrast / 0.15));  % 0.15 green-scale = strong disc

    % (b) vessel convergence: vessel density in a neighbourhood around the disc
    conv = (X-ctr(1)).^2 + (Y-ctr(2)).^2 <= (2*rad)^2 & fovMask;
    if any(conv(:))
        vessDens = nnz(vesselMask & conv) / nnz(conv);
    else
        vessDens = 0;
    end
    vessDens = max(0, min(1, vessDens / 0.15));

    conf = 0.6*contrast + 0.4*vessDens;
    conf = max(0, min(1, conf));
end
