function [imgOut, clip] = claheAdaptive(img, fovMask, contrastMeasure, cfg)
%CLAHEADAPTIVE  CLAHE with a clip limit computed from the contrast deficit.  [Phase 4]
%   [imgOut, clip] = netra.preproc.claheAdaptive(img, fovMask, contrastMeasure, cfg)
%
%   Applies Contrast-Limited Adaptive Histogram Equalisation to the luminance
%   of a fundus image, with the clip limit CHOSEN FROM the measured contrast so
%   a low-contrast image gets a stronger stretch than an already-contrasty one.
%   This is what makes the enhancement adaptive rather than a fixed filter.
%
%   contrastMeasure is a 0..1 scalar (the quality contrast subscore, or a raw
%   green-channel std): higher = more contrast already present.
%
%   CLIP-LIMIT RULE:
%     deficit = max(0, 1 - contrastMeasure / contrastTarget)      in [0,1]
%     clip    = claheClipMin + deficit * (claheClipMax - claheClipMin)
%   So a contrast at/above target -> clip = claheClipMin (gentle); a very
%   low-contrast image -> clip near claheClipMax (aggressive). Both bounds come
%   from cfg.thresholds.preproc.
%
%   COLOUR: CLAHE is applied to the L channel of Lab (perceptual luminance) so
%   hue is preserved and red/orange lesion colour is not distorted. Only the
%   inside-FOV region is equalised; the black surround is restored afterwards so
%   its dark pixels do not bias the tile histograms into lifting the border.
%
%   adapthisteq's tile grid is fixed at 8x8 (its documented default). Tiles are
%   a grid over the frame, so they are inherently resolution-relative.

    arguments
        img
        fovMask logical
        contrastMeasure (1,1) double
        cfg (1,1) struct
    end

    pp = cfg.thresholds.preproc;
    clipMin = pp.claheClipMin;
    clipMax = pp.claheClipMax;
    target  = pp.contrastTarget;

    deficit = max(0, min(1, 1 - contrastMeasure / max(target, eps)));
    clip = clipMin + deficit * (clipMax - clipMin);
    clip = max(clipMin, min(clipMax, clip));   % guard bounds

    if size(img,3) == 3
        lab = rgb2lab(img);
        L = lab(:,:,1) / 100;                  % 0..1
        Leq = adapthisteq(L, 'ClipLimit', clip, 'Distribution', 'rayleigh');
        lab(:,:,1) = Leq * 100;
        imgOut = lab2rgb(lab, 'OutputType', 'uint8');
    else
        L = im2double(img);
        Leq = adapthisteq(L, 'ClipLimit', clip, 'Distribution', 'rayleigh');
        imgOut = im2uint8(Leq);
    end

    % Restore the surround: adapthisteq operates on the whole frame; blacken
    % anything outside the FOV so the crop/mask contract is preserved.
    if ~isempty(fovMask) && ~all(fovMask(:))
        for ch = 1:size(imgOut,3)
            chan = imgOut(:,:,ch);
            chan(~fovMask) = 0;
            imgOut(:,:,ch) = chan;
        end
    end
end
