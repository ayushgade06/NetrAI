function cr = detect(cr, cfg)
%DETECT  Lesion detection (MA / HE / EX; CWS not implemented).  [Phase 6 REAL]
%   cr = netra.lesions.detect(cr, cfg)
%
%   Runs the REAL classical-CV lesion pipeline on the enhanced image, using the
%   structures the previous stage located (OD, quadrant map, macula zone):
%     - netra.lesions.redLesions   -> MA + HE masks (vessel-suppressed residual)
%     - netra.lesions.brightLesions-> EX mask (top-hat, OD region subtracted)
%     - netra.lesions.quadrantTally-> per-class count/area/perQuadrant/nearMacula
%
%   CONTRACT: one caseRecord in/out; may ADD fields, never delete/rename; never
%   writes to disk. Sets cr.provenance.lesions = "REAL" (or "MOCK" if no pixels).
%
%   MASK FORMAT CONTRACT (§7 - Track B depends on this EXACTLY):
%     cr.lesions.<TYPE>.mask  logical size(cr.img.enhanced,[1 2]), true where
%                             that class is present. TYPE in {MA, HE, EX}.
%     cr.lesions.allMask      logical union of MA|HE|EX.
%   Both are asserted logical + correctly sized at the end; a size mismatch
%   errors LOUDLY here rather than silently breaking the ALA score.
%
%   CWS (cotton wool spots) is NOT implemented (out of scope for time). Its
%   schema field is left as the empty lesion-set the factory created - not
%   deleted, not fabricated. A "cwsNotImplemented" note documents this.
%
%   ZERO LESIONS is a VALID result for a normal retina: counts of 0 and
%   all-false masks propagate cleanly (quadrantTally handles the empty case).

    arguments
        cr  (1,1) struct
        cfg (1,1) struct
    end

    % --- working image + FOV --------------------------------------------
    [img, fovMask] = workingImage(cr);
    if isempty(img)
        cr.provenance.lesions = "MOCK";           % preview-only: nothing to do
        return;
    end
    [H, W, ~] = size(img);

    % Structures (from the previous stage); tolerate missing/fallback values.
    vesselMask = getMask(cr.structures.vesselMask, H, W);
    qmap       = getQuad(cr.structures.quadrantMap, H, W);
    maculaZone = getMask(cr.structures.maculaZone, H, W);
    odCenter   = valOr(cr.structures.odCenter, [W/2 H/2]);
    odRadius   = valOr(cr.structures.odRadius, cfg.thresholds.lesions.referenceOdRadius512);

    % Pass the measured disc radius to redLesions/classifyMAvsHE via a transient
    % cfg field (keeps the public signature; does not mutate the shared config).
    lcfg = cfg;
    lcfg.odRadius = odRadius;

    % --- red lesions (MA + HE) ------------------------------------------
    [maMask, heMask, ~] = netra.lesions.redLesions(img, fovMask, vesselMask, lcfg);

    % --- bright lesions (EX) - OD region subtracted inside -------------
    [exMask, ~] = netra.lesions.brightLesions(img, fovMask, odCenter, odRadius, cfg);

    % --- tally each class into a schema lesion-set (+ .mask) ------------
    cr.lesions.MA = netra.lesions.quadrantTally(maMask, qmap, maculaZone, cfg);
    cr.lesions.HE = netra.lesions.quadrantTally(heMask, qmap, maculaZone, cfg);
    cr.lesions.EX = netra.lesions.quadrantTally(exMask, qmap, maculaZone, cfg);

    % CWS: not implemented. Keep the empty set; give it a same-sized mask so the
    % struct shape matches the others, and document the choice.
    cr.lesions.CWS.mask = false(H, W);
    cr.lesions.cwsNote  = "cwsNotImplemented";

    % --- combined convenience mask (§7) --------------------------------
    cr.lesions.allMask = cr.lesions.MA.mask | cr.lesions.HE.mask | cr.lesions.EX.mask;

    % --- LOUD mask-contract assertions (protect Track B) ---------------
    assertMask(cr.lesions.MA.mask, [H W], 'MA.mask');
    assertMask(cr.lesions.HE.mask, [H W], 'HE.mask');
    assertMask(cr.lesions.EX.mask, [H W], 'EX.mask');
    assertMask(cr.lesions.allMask, [H W], 'allMask');

    cr.provenance.lesions = "REAL";
end

% ========================================================================
function [img, fovMask] = workingImage(cr)
    img = []; fovMask = logical([]);
    if ~isempty(cr.img.enhanced)
        img = cr.img.enhanced;
    elseif ~isempty(cr.img.raw)
        img = cr.img.raw;
    else
        return;
    end
    [H, W, ~] = size(img);
    if isfield(cr.preproc,'fovMaskResized') && ...
            isequal(size(cr.preproc.fovMaskResized), [H W])
        fovMask = cr.preproc.fovMaskResized;
    elseif ~isempty(cr.img.fovMask) && isequal(size(cr.img.fovMask), [H W])
        fovMask = cr.img.fovMask;
    else
        fovMask = true(H, W);
    end
end

function m = getMask(m, H, W)
    if ~islogical(m) || ~isequal(size(m), [H W]), m = false(H, W); end
end

function q = getQuad(q, H, W)
    if ~isequal(size(q), [H W]), q = zeros(H, W, 'uint8'); end
end

function v = valOr(v, def)
    if isempty(v) || any(~isfinite(v(:))), v = def; end
end

function assertMask(m, sz, name)
    if ~islogical(m) || ~isequal(size(m), sz)
        error('NETRA:lesions:maskContract', ...
            '%s must be logical %dx%d, got %s %s.', name, sz(1), sz(2), ...
            class(m), mat2str(size(m)));
    end
end
