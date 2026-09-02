function [ok, reason] = validateImage(img, cfg)
%VALIDATEIMAGE  Cheap sanity checks on a decoded image before ingestion.
%   [ok, reason] = netra.io.validateImage(img, cfg) returns ok=true and
%   reason="" when img passes every structural check, else ok=false and a
%   human-readable reason naming the first failed check.
%
%   Checks (all thresholds from cfg.thresholds.io):
%     - 3-channel                  (a fundus is colour; grayscale is handled
%                                    upstream in loadImage, so here 3 channels
%                                    are required)
%     - both dimensions >= minDimension
%     - aspect ratio within [1/maxAspectRatio, maxAspectRatio]
%     - not entirely uniform       (a blank / solid frame carries no retina)
%
%   These are STRUCTURAL checks only; whether the content looks like a retina
%   is the separate job of netra.io.isPlausibleFundus.

    arguments
        img
        cfg (1,1) struct
    end

    io = cfg.thresholds.io;
    ok = false;

    if ~isnumeric(img) || ndims(img) ~= 3 || size(img,3) ~= 3
        reason = "Image is not 3-channel colour (expected HxWx3).";
        return;
    end

    [h, w, ~] = size(img);
    if min(h, w) < io.minDimension
        reason = sprintf("Image too small: %dx%d, minimum dimension is %d px.", ...
            w, h, io.minDimension);
        return;
    end

    ar = max(h, w) / min(h, w);
    if ar > io.maxAspectRatio
        reason = sprintf("Aspect ratio %.2f exceeds max %.2f (image %dx%d).", ...
            ar, io.maxAspectRatio, w, h);
        return;
    end

    % "Entirely uniform" = every channel has ~zero spread. Use a tiny epsilon
    % so an 8-bit image with a single stray value still counts as content.
    g = double(img);
    spread = max(g(:)) - min(g(:));
    if spread < 1
        reason = "Image is a single flat colour (no content).";
        return;
    end

    ok = true;
    reason = "";
end
