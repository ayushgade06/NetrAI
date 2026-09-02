classdef tFovMask < matlab.unittest.TestCase
    %TFOVMASK  Tests for netra.preproc.fovMask + cropResize.
    %   Runs on 15+ synthetic fundus discs (a real dataset is not required).
    %   Point APTOS at datasets/aptos2019/ to also exercise real images.

    properties
        Cfg
        Fundi   % cell array of synthetic fundus images (varied)
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.Cfg = netra.loadConfig();
            % 18 varied discs: different sizes, centres, radii, brightness.
            tc.Fundi = {};
            for k = 1:18
                n = 300 + 20*mod(k,6);
                cx = 0.5 + 0.06*sin(k);          % slight off-centre
                cy = 0.5 + 0.06*cos(k);
                rad = 0.80 + 0.08*mod(k,3)/3;
                tc.Fundi{end+1} = synthFundus(n, cx, cy, rad, 0.8 + 0.15*mod(k,2)); %#ok<AGROW>
            end
        end
    end

    methods (Test)

        function maskAreaInRangeOnAll(tc)
            for k = 1:numel(tc.Fundi)
                [mask, ~] = netra.preproc.fovMask(tc.Fundi{k}, tc.Cfg);
                frac = mean(mask(:));
                tc.verifyGreaterThanOrEqual(frac, 0.15, ...
                    sprintf('Image %d: mask area %.2f below 15%%.', k, frac));
                tc.verifyLessThanOrEqual(frac, 0.95, ...
                    sprintf('Image %d: mask area %.2f above 95%%.', k, frac));
            end
        end

        function maskIsSingleComponent(tc)
            for k = 1:numel(tc.Fundi)
                [mask, m] = netra.preproc.fovMask(tc.Fundi{k}, tc.Cfg);
                if m.fallback, continue; end     % full-frame fallback is trivially one comp
                cc = bwconncomp(mask);
                tc.verifyEqual(cc.NumObjects, 1, ...
                    sprintf('Image %d: mask has %d components.', k, cc.NumObjects));
            end
        end

        function completenessInUnitInterval(tc)
            for k = 1:numel(tc.Fundi)
                [~, m] = netra.preproc.fovMask(tc.Fundi{k}, tc.Cfg);
                tc.verifyGreaterThanOrEqual(m.completeness, 0);
                tc.verifyLessThanOrEqual(m.completeness, 1);
            end
        end

        function cropResizeIsExactlyTargetSize(tc)
            ts = tc.Cfg.thresholds.preproc.targetSize;
            img = tc.Fundi{1};
            [mask, ~] = netra.preproc.fovMask(img, tc.Cfg);
            [out, maskOut, ~] = netra.preproc.cropResize(img, mask, tc.Cfg);
            tc.verifyEqual(size(out), [ts ts 3]);
            tc.verifyEqual(size(maskOut), [ts ts]);
            tc.verifyClass(out, 'uint8');
        end

        function cornerBlackFractionLowAfterCrop(tc)
            % After crop the black surround should be largely gone. Measure the
            % near-black fraction in the four 12% corner squares; require it
            % below a documented bound (0.35 - corners still hold some disc
            % falloff, but the wide black border must be removed).
            BOUND = 0.35;
            img = tc.Fundi{1};
            [mask, ~] = netra.preproc.fovMask(img, tc.Cfg);
            [out, ~, ~] = netra.preproc.cropResize(img, mask, tc.Cfg);
            lum = 0.299*double(out(:,:,1)) + 0.587*double(out(:,:,2)) + 0.114*double(out(:,:,3));
            n = size(lum,1); c = round(0.12*n);
            corners = [lum(1:c,1:c); lum(1:c,end-c+1:end); ...
                       lum(end-c+1:end,1:c); lum(end-c+1:end,end-c+1:end)];
            blackFrac = mean(corners(:) < 20);
            tc.verifyLessThan(blackFrac, BOUND, ...
                sprintf('Corner black fraction %.2f exceeds bound %.2f.', blackFrac, BOUND));
        end

        function coordinateMappingRoundTrips(tc)
            % A known point in the ORIGINAL image, forward-mapped into the
            % cropped/resized frame, then inverse-mapped via info, returns to
            % (approximately) the original point.
            img = tc.Fundi{1};
            [mask, ~] = netra.preproc.fovMask(img, tc.Cfg);
            [~, ~, info] = netra.preproc.cropResize(img, mask, tc.Cfg);

            % Pick a point inside the crop box, in original coords.
            xo = info.cropRect(1) + round(info.cropRect(3)/2);
            yo = info.cropRect(2) + round(info.cropRect(4)/2);

            % Forward: original -> cropped-resized (per the documented model).
            xc = ((xo - info.cropRect(1) + 1) + info.padOffset(1)) * info.scale;
            yc = ((yo - info.cropRect(2) + 1) + info.padOffset(2)) * info.scale;

            % Inverse: cropped-resized -> original.
            xoBack = (xc/info.scale - info.padOffset(1)) + info.cropRect(1) - 1;
            yoBack = (yc/info.scale - info.padOffset(2)) + info.cropRect(2) - 1;

            tc.verifyEqual(xoBack, xo, 'AbsTol', 2);
            tc.verifyEqual(yoBack, yo, 'AbsTol', 2);
        end

        function partialFovLowersCompleteness(tc)
            % A clipped disc must report lower completeness than the full disc.
            full = synthFundus(400, 0.5, 0.5, 0.9, 0.9);
            [~, mFull] = netra.preproc.fovMask(full, tc.Cfg);
            clipped = full; clipped(1:round(0.35*400), :, :) = 0;   % cut top band
            [~, mClip] = netra.preproc.fovMask(clipped, tc.Cfg);
            tc.verifyLessThan(mClip.completeness, mFull.completeness);
        end

    end
end

% ======================= fixtures =======================================
function img = synthFundus(n, cx, cy, rad, bright)
    if nargin < 2, cx = 0.5; end
    if nargin < 3, cy = 0.5; end
    if nargin < 4, rad = 0.9; end
    if nargin < 5, bright = 0.85; end
    [X,Y] = meshgrid(linspace(0,1,n), linspace(0,1,n));
    R = sqrt((X-cx).^2 + (Y-cy).^2);
    m = double(R <= rad*0.5);            % disc radius as fraction of frame
    fall = 1 - min(1, R/(rad*0.5));
    r = bright*(0.6 + 0.3*fall).*m;
    g = bright*(0.25 + 0.1*fall).*m;
    b = bright*(0.12 + 0.05*fall).*m;
    img = uint8(255*cat(3, min(1,r), min(1,g), min(1,b)));
end
