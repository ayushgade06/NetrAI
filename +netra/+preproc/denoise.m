function imgOut = denoise(img, cfg)
%DENOISE  Optional edge-preserving denoising, triggered by a noise estimate.  [Phase 4]
%   imgOut = netra.preproc.denoise(img, cfg)
%
%   Estimates image noise and, only if it exceeds the configured trigger,
%   applies a gentle Wiener filter per channel. Wiener2 is locally adaptive: it
%   smooths flat regions more than detailed ones, so vessels and lesion edges
%   survive better than under a uniform Gaussian blur.
%
%   NOISE ESTIMATE: the robust std of the Laplacian, sigma = median(|Lap|)/0.6745
%   (the classic MAD estimator of high-frequency noise). It is compared against
%   cfg.thresholds.preproc.denoiseTrigger, expressed on the 0..255 luminance
%   scale. Below the trigger the image is returned UNCHANGED so a clean image is
%   never softened (this is what keeps appliedSteps minimal on clean images).
%
%   Returns the input class (uint8). The caller decides whether it fired by
%   comparing imgOut to img / by reading the step this function's caller logs.

    arguments
        img
        cfg (1,1) struct
    end

    trigger = cfg.thresholds.preproc.denoiseTrigger;
    % Scale a 0..1 trigger onto the 0..255 luminance MAD scale used below.
    trigger255 = trigger * 3;   % ~clean images sit well under this

    if size(img,3) == 3
        lum = double(0.299*img(:,:,1) + 0.587*img(:,:,2) + 0.114*img(:,:,3));
    else
        lum = double(img);
    end

    lap = imfilter(lum, fspecial('laplacian', 0), 'symmetric');
    sigma = median(abs(lap(:))) / 0.6745;      % robust HF-noise std, 0..255

    if sigma <= trigger255
        imgOut = img;                          % clean enough: do nothing
        return;
    end

    imgOut = img;
    for ch = 1:size(img,3)
        imgOut(:,:,ch) = wiener2(img(:,:,ch), [3 3]);
    end
end
