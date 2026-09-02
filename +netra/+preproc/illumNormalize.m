function [imgOut, steps] = illumNormalize(img, fovMask, cfg)
%ILLUMNORMALIZE  Correct uneven illumination by background subtraction.  [Phase 4]
%   [imgOut, steps] = netra.preproc.illumNormalize(img, fovMask, cfg)
%
%   Estimates the slowly-varying illumination background of a fundus image and
%   removes it, restoring the global mean so overall brightness is preserved.
%   This is the classic retinal shade-correction: the retina's true reflectance
%   is the image divided (here, subtracted in a mean-restoring form) by a large
%   low-pass estimate of the illumination field.
%
%   METHOD (per channel, inside the FOV):
%     1. background = large-kernel median filter of the channel. The kernel side
%        is cfg.thresholds.preproc.illumKernelFraction of the FOV RADIUS, so it
%        is resolution-aware (a bigger image gets a proportionally bigger kernel
%        and the same physical smoothing). Median (not mean) so vessels and
%        lesions - which are small and dark/bright - do not bleed into the
%        background estimate the way a mean would.
%     2. corrected = channel - background + mean(background inside FOV). The
%        added constant restores the global brightness the subtraction removed,
%        so the output is not a near-zero flat field.
%     3. Clamp to [0,255], keep pixels outside the FOV at 0 (black surround).
%
%   Median of a large window is expensive; medfilt2 with a big kernel is O(n)
%   per pixel via its histogram method but still the slowest step here. On a
%   512x512 frame it is well within budget (see docs/cv_method.md timings).
%
%   Returns steps = "illumNormalize(kernel=NN)" naming the kernel used, for the
%   preproc.appliedSteps log. imgOut is the same class as img (uint8).

    arguments
        img
        fovMask logical
        cfg (1,1) struct
    end

    pp = cfg.thresholds.preproc;
    [h, w, c] = size(img);
    steps = strings(1,0);

    if isempty(fovMask) || ~any(fovMask(:))
        imgOut = img;                          % nothing to correct
        return;
    end

    % Kernel side from the FOV radius so the smoothing scale is physical.
    fovR = sqrt(nnz(fovMask)/pi);              % equivalent-circle radius (px)
    kside = 2*round(pp.illumKernelFraction * fovR) + 1;   % odd
    kside = max(3, min(kside, 2*floor(min(h,w)/2)-1));    % keep < frame

    % A large-kernel median on the full frame is expensive; estimate the
    % background on a bounded-work-size downsample (the illumination field is
    % slowly-varying, so nothing is lost) and upsample. This keeps the step well
    % inside the runtime budget and makes the cost resolution-independent.
    workSide = 256;
    if max(h,w) > workSide
        s = workSide / max(h,w);
        kWork = max(3, 2*round(kside*s/2)+1);
    else
        s = 1; kWork = kside;
    end
    steps(end+1) = "illumNormalize(kernel=" + kside + ")";

    imgOut = img;
    for ch = 1:c
        chan = double(img(:,:,ch));
        % Estimate background only where there is retina; fill the surround with
        % the inside-FOV mean so the median near the FOV edge is not pulled to 0.
        insideVals = chan(fovMask);
        fillVal = mean(insideVals);
        chanFilled = chan;
        chanFilled(~fovMask) = fillVal;

        if s < 1
            small = imresize(chanFilled, s);
            bgS = medfilt2(small, [kWork kWork], 'symmetric');
            bg = imresize(bgS, [h w]);
        else
            bg = medfilt2(chanFilled, [kWork kWork], 'symmetric');
        end
        bgMean = mean(bg(fovMask));

        corr = chan - bg + bgMean;             % mean-restoring subtraction
        corr = max(0, min(255, corr));
        corr(~fovMask) = 0;                    % keep the surround black
        imgOut(:,:,ch) = cast(corr, 'like', img);
    end
end
