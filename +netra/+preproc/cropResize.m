function [imgOut, maskOut, info] = cropResize(img, mask, cfg)
%CROPRESIZE  Crop to the FOV bounding box, pad to square, resize to target.
%   [imgOut, maskOut, info] = netra.preproc.cropResize(img, mask, cfg)
%
%   Steps:
%     1. Crop img (and mask) to the tight bounding box of the FOV mask. This
%        removes the black surround so the retina fills the frame.
%     2. Pad the crop to a square with black, centred, so a non-square FOV box
%        is not stretched by the resize (aspect ratio is preserved).
%     3. Resize the square to cfg.thresholds.preproc.targetSize on a side.
%
%   Output:
%     imgOut  : uint8 targetSize x targetSize x 3
%     maskOut : logical targetSize x targetSize
%     info    : coordinate-mapping record so a point can be taken back to the
%               ORIGINAL image coordinate frame later. Fields:
%       cropRect   [x0 y0 wBox hBox]  crop box in original coords (1-based)
%       padOffset  [px py]  where the crop sits inside the square (top-left)
%       squareSize  side length of the padded square (pre-resize)
%       scale       targetSize / squareSize  (uniform)
%       targetSize  the configured output side
%
%   MAPPING (cropped/resized [xc yc] -> original [xo yo]):
%       xo = cropRect(1) + (xc/scale - padOffset(1)) - 1 + 1
%       yo = cropRect(2) + (yc/scale - padOffset(2)) - 1 + 1
%   i.e. divide by scale, subtract the pad offset, add the crop origin. See
%   netra.preproc.cropResize>mapToOriginal for the exact inverse used by tests.

    arguments
        img
        mask logical
        cfg (1,1) struct
    end

    targetSize = cfg.thresholds.preproc.targetSize;
    [H, W, ~] = size(img);

    % --- 1. crop box from the mask --------------------------------------
    if any(mask(:))
        anyRow = any(mask, 2); anyCol = any(mask, 1);
        y0 = find(anyRow, 1, 'first'); y1 = find(anyRow, 1, 'last');
        x0 = find(anyCol, 1, 'first'); x1 = find(anyCol, 1, 'last');
    else
        % Empty mask: keep the whole frame (defensive; fovMask falls back to
        % a full-frame mask before this, so this branch is belt-and-braces).
        x0 = 1; y0 = 1; x1 = W; y1 = H;
    end
    wBox = x1 - x0 + 1;
    hBox = y1 - y0 + 1;

    crop     = img(y0:y1, x0:x1, :);
    cropMask = mask(y0:y1, x0:x1);

    % --- 2. pad to square (centred, black) ------------------------------
    side = max(wBox, hBox);
    px = floor((side - wBox)/2);        % left pad
    py = floor((side - hBox)/2);        % top pad

    sq     = zeros(side, side, 3, 'like', img);
    sqMask = false(side, side);
    sq(py+1:py+hBox, px+1:px+wBox, :) = crop;
    sqMask(py+1:py+hBox, px+1:px+wBox) = cropMask;

    % --- 3. resize -------------------------------------------------------
    imgOut  = imresize(sq, [targetSize targetSize]);
    maskOut = imresize(sqMask, [targetSize targetSize], 'nearest');
    if ~isa(imgOut, 'uint8'), imgOut = im2uint8(imgOut); end

    scale = targetSize / side;

    info = struct( ...
        'cropRect',   [x0 y0 wBox hBox], ...
        'padOffset',  [px py], ...
        'squareSize', side, ...
        'scale',      scale, ...
        'targetSize', targetSize);
end
