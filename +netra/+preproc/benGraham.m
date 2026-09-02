function tensor = benGraham(img, fovMask, cfg)
%BENGRAHAM  Ben-Graham colour normalisation for the CNN input.  [Phase 4]
%   tensor = netra.preproc.benGraham(img, fovMask, cfg)
%
%   Produces the normalised model input for Track B's grader using the
%   Ben-Graham scheme that won the 2015 Kaggle DR competition and is still the
%   standard fundus CNN preprocessing:
%
%       out = 4*(img - GaussianBlur(img, sigma)) + 128
%
%   Subtracting a heavily blurred copy removes the slowly-varying illumination
%   and colour cast that varies between cameras/operators, leaving local
%   structure (vessels, lesions) on a consistent mid-grey background. The blur
%   sigma is cfg.thresholds.preproc.benGrahamSigmaFraction of the FOV RADIUS, so
%   the normalisation is resolution-aware (same physical smoothing at 512 or
%   1024). The FOV is then circularly masked (surround = the 128 grey) so black
%   borders do not feed the network a hard edge.
%
%   OUTPUT: single HxWx3 on the 0..1 scale (128/255 background), the type Track
%   B's CNN expects for img.modelInput. NaN/Inf-free by construction (guarded).

    arguments
        img
        fovMask logical
        cfg (1,1) struct
    end

    x = single(img);
    if size(x,3) == 1, x = repmat(x, 1, 1, 3); end
    [h, w, ~] = size(x);

    if isempty(fovMask) || ~any(fovMask(:))
        fovMask = true(h, w);
    end

    fovR = sqrt(nnz(fovMask)/pi);
    sigma = max(1, cfg.thresholds.preproc.benGrahamSigmaFraction * fovR);

    blurred = imgaussfilt(x, sigma);
    out = 4*(x - blurred) + 128;               % Ben-Graham, 0..255 grey-centred
    out = out / 255;                            % -> 0..1
    out = max(0, min(1, out));

    % Circular FOV mask: set the surround to the mid-grey background (0.5), the
    % same neutral value the blur-subtraction leaves flat regions at.
    bg = single(128/255);
    for ch = 1:3
        chan = out(:,:,ch);
        chan(~fovMask) = bg;
        out(:,:,ch) = chan;
    end

    out(~isfinite(out)) = bg;                   % NaN/Inf guard
    tensor = single(out);
end
