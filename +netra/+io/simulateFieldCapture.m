function imgOut = simulateFieldCapture(imgIn, type, severity, seed)
%SIMULATEFIELDCAPTURE  Synthesise a realistic capture degradation on an image.
%
%   *** THIS SYNTHESISES DEGRADATIONS FOR TESTING AND TRAINING-DATA        ***
%   *** GENERATION. THE OUTPUT IS NOT A REAL CAMERA CAPTURE. It is a clean  ***
%   *** image with an artificial failure mode applied on purpose, so the    ***
%   *** UI, the tests, and (later) the Phase 3 quality classifier have      ***
%   *** known-bad inputs to work against.                                   ***
%
%   imgOut = netra.io.simulateFieldCapture(imgIn, type, severity, seed)
%     imgIn    : uint8 HxWx3
%     type     : "blur" | "underexposed" | "overexposed" | "partialFOV" |
%                "haze" | "random"
%     severity : 0..1  (0 is ~no-op; 1 is the strongest documented degradation)
%     seed     : integer; same seed -> identical output (reproducible demos/tests)
%
%   The severity maps LINEARLY into the per-type range from
%   config/thresholds.json (degradation.*), so the knobs live in config, not
%   inline here. "random" picks one of the five concrete types from the seed
%   and applies it, so a folder of "random" degradations is varied yet
%   reproducible.

    arguments
        imgIn    uint8
        type     (1,1) string
        severity (1,1) double {mustBeGreaterThanOrEqual(severity,0), mustBeLessThanOrEqual(severity,1)}
        seed     (1,1) double = 0
    end

    if size(imgIn,3) ~= 3
        error('NETRA:io:degradeInput', 'simulateFieldCapture expects HxWx3 uint8.');
    end

    cfg = netra.loadConfig();
    dg  = cfg.thresholds.degradation;

    % Deterministic local RNG that does NOT disturb the global stream.
    rs = RandStream('mt19937ar', 'Seed', mod(round(seed),2^31));

    type = lower(strtrim(type));
    if type == "random"
        types = ["blur","underexposed","overexposed","partialfov","haze"];
        pick  = types(randi(rs, numel(types)));
        imgOut = netra.io.simulateFieldCapture(imgIn, pick, severity, seed + 101);
        return;
    end

    switch type
        case "blur"
            % Gaussian blur; sigma scales with severity across the config range.
            sigma = lerp(dg.blurSigmaRange, severity);
            if sigma <= 0.05
                imgOut = imgIn;
            else
                imgOut = imgaussfilt(imgIn, sigma);
            end

        case "underexposed"
            % Gamma > 1 darkens. severity 0 -> gamma 1 (no-op); severity 1 ->
            % gammaRange(2).
            gamma = 1 + severity*(dg.gammaRange(2) - 1);
            imgOut = gammaAdjust(imgIn, gamma);

        case "overexposed"
            % Gamma < 1 brightens toward saturation. severity 0 -> 1; 1 -> gammaRange(1).
            gamma = 1 - severity*(1 - dg.gammaRange(1));
            imgOut = gammaAdjust(imgIn, gamma);
            % Add a mild additive lift so highlights actually clip (saturated
            % pixel fraction is the quantity the test checks).
            % scalar DOUBLE lift: imadd requires the addend be same-size/class
            % or a scalar double (a scalar uint8 is rejected in R2026a).
            imgOut = imadd(imgOut, severity * 60);

        case "partialfov"
            % Occlude a chord of the frame (as if the pupil/eyelid clipped the
            % field). Fraction of the frame removed scales with severity.
            frac = lerp(dg.occlusionFractionRange, severity);
            imgOut = occludeFOV(imgIn, frac, rs);

        case "haze"
            % Alpha-blend toward a bright grey veil -> lowered local contrast.
            alpha = lerp(dg.hazeAlphaRange, severity);
            veil  = uint8(200);   % bright grey haze colour
            imgOut = imgIn;
            for c = 1:3
                ch = double(imgIn(:,:,c));
                imgOut(:,:,c) = uint8((1-alpha)*ch + alpha*double(veil));
            end

        otherwise
            error('NETRA:io:degradeType', ...
                ['Unknown degradation type "%s". Use blur|underexposed|' ...
                 'overexposed|partialFOV|haze|random.'], type);
    end
end

% ------------------------------------------------------------------------
function v = lerp(range, s)
%LERP  Linear map severity s in [0,1] onto [range(1), range(2)].
    v = range(1) + s*(range(2) - range(1));
end

function out = gammaAdjust(img, gamma)
%GAMMAADJUST  Per-channel gamma on a uint8 image (gamma=1 is an exact no-op).
    if abs(gamma - 1) < 1e-6
        out = img; return;
    end
    out = im2uint8((im2double(img)) .^ gamma);
end

function out = occludeFOV(img, frac, rs)
%OCCLUDEFOV  Black out a straight-edged region covering `frac` of the frame.
%   The cut is a horizontal or vertical band from a random edge, so repeated
%   calls with different seeds clip different sides.
    [h, w, ~] = size(img);
    out = img;
    frac = max(0, min(0.9, frac));
    side = randi(rs, 4);          % 1=top 2=bottom 3=left 4=right
    switch side
        case 1, out(1:round(frac*h), :, :) = 0;
        case 2, out(end-round(frac*h)+1:end, :, :) = 0;
        case 3, out(:, 1:round(frac*w), :) = 0;
        case 4, out(:, end-round(frac*w)+1:end, :) = 0;
    end
end
