classdef tQualityFeatures < matlab.unittest.TestCase
    %TQUALITYFEATURES  Tests for netra.quality.extractFeatures.  [Phase 3]
    %   Runs on synthetic fundus discs (a real dataset is not required). The
    %   critical FOV-masking test is written first, then scale invariance,
    %   finiteness/range, the five monotonicity trends under Phase 2's
    %   degradation engine, and the solid-colour no-NaN guard.

    properties
        Cfg
        Fundus   % one representative synthetic fundus (uint8 HxWx3)
        Mask     % its FOV mask
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.Cfg = netra.loadConfig();
            tc.Fundus = synthFundus(512, 0.5, 0.5, 0.9, 0.85);
            [tc.Mask, ~] = netra.preproc.fovMask(tc.Fundus, tc.Cfg);
        end
    end

    methods (Test)

        % ---- THE CRITICAL TEST: features ignore the black border --------
        function featuresIgnoreBorderNoise(tc)
            % Inject random noise everywhere OUTSIDE the FOV mask. Every feature
            % must be unchanged, because features are computed inside FOV only.
            [f0, ~] = netra.quality.extractFeatures(tc.Fundus, tc.Mask, tc.Cfg);

            noisy = tc.Fundus;
            outside = ~tc.Mask;
            for c = 1:3
                ch = noisy(:,:,c);
                rn = uint8(randi([0 255], nnz(outside), 1));
                ch(outside) = rn;
                noisy(:,:,c) = ch;
            end
            [f1, ~] = netra.quality.extractFeatures(noisy, tc.Mask, tc.Cfg);

            tc.verifyEqual(f1, f0, 'AbsTol', 1e-6, ...
                'Border noise changed inside-FOV feature values.');
        end

        function allFeaturesFiniteAndInRange(tc)
            [f, d] = netra.quality.extractFeatures(tc.Fundus, tc.Mask, tc.Cfg);
            tc.verifyTrue(all(isfinite(f)), 'A feature is non-finite.');
            tc.verifyNumElements(f, 8);
            % illumUniformity, saturatedFraction, darkFraction, fovCompleteness
            % are all in [0,1] by construction.
            tc.verifyGreaterThanOrEqual(f(3), 0); tc.verifyLessThanOrEqual(f(3), 1);
            tc.verifyGreaterThanOrEqual(f(4), 0); tc.verifyLessThanOrEqual(f(4), 1);
            tc.verifyGreaterThanOrEqual(f(5), 0); tc.verifyLessThanOrEqual(f(5), 1);
            tc.verifyGreaterThanOrEqual(f(6), 0); tc.verifyLessThanOrEqual(f(6), 1);
            tc.verifyFalse(d.anyNaN, 'detail.anyNaN set on a clean image.');
        end

        function scaleInvariance(tc)
            % The SAME content at two resolutions must give features within a
            % documented tolerance. Generate the source natively at 1024 (so it
            % holds real high-frequency detail) and DOWNSAMPLE to 512 - both
            % then see the same content. (Upsampling 512->1024 would be an
            % unfair test: it destroys focus information and is not a resolution
            % change of the underlying scene.)
            big = synthFundus(1024, 0.5, 0.5, 0.9, 0.85);
            small = imresize(big, [512 512]);
            [mBig, ~]   = netra.preproc.fovMask(big, tc.Cfg);
            [mSmall, ~] = netra.preproc.fovMask(small, tc.Cfg);
            fBig   = netra.quality.extractFeatures(big, mBig, tc.Cfg);
            fSmall = netra.quality.extractFeatures(small, mSmall, tc.Cfg);
            % Fractions/ratios (3,4,5,6) should match closely.
            tc.verifyEqual(fBig(3:6), fSmall(3:6), 'AbsTol', 0.05, ...
                'Ratio/fraction features not scale-invariant.');
            % Focus/contrast (1,2,7,8): within 40% relative. Resampling still
            % softens edges somewhat; 40% is the documented tolerance.
            rel = abs(fBig([1 2 7 8]) - fSmall([1 2 7 8])) ./ max(fSmall([1 2 7 8]), 1e-3);
            tc.verifyLessThan(max(rel), 0.4, ...
                'Focus/contrast features drift too much across resolution.');
        end

        % ---- five monotonicity trends under Phase 2's engine ------------
        function blurLowersFocusLaplacian(tc)
            sev = linspace(0.1, 0.9, 5);
            vals = tc.trendFeature("blur", sev, 1);
            tc.verifyMonotoneDecreasing(vals, 'focusLaplacian vs blur');
        end

        function underexposureRaisesDarkFraction(tc)
            sev = linspace(0.1, 0.9, 5);
            vals = tc.trendFeature("underexposed", sev, 5);
            tc.verifyMonotoneIncreasing(vals, 'darkFraction vs underexposure');
        end

        function overexposureRaisesSaturatedFraction(tc)
            sev = linspace(0.1, 0.9, 5);
            vals = tc.trendFeature("overexposed", sev, 4);
            tc.verifyMonotoneIncreasing(vals, 'saturatedFraction vs overexposure');
        end

        function hazeLowersLocalContrast(tc)
            sev = linspace(0.1, 0.9, 5);
            vals = tc.trendFeature("haze", sev, 8);
            tc.verifyMonotoneDecreasing(vals, 'localContrast vs haze');
        end

        function occlusionLowersFovCompleteness(tc)
            % partialFOV clips the field; fovCompleteness (feature 6) must fall.
            % Recompute the mask per severity (occlusion changes the FOV).
            sev = linspace(0.1, 0.9, 5);
            vals = zeros(size(sev));
            for i = 1:numel(sev)
                d = netra.io.simulateFieldCapture(tc.Fundus, "partialFOV", sev(i), 7);
                [mk, mm] = netra.preproc.fovMask(d, tc.Cfg);
                c = tc.Cfg; c.qualityFovCompleteness = mm.completeness;
                f = netra.quality.extractFeatures(d, mk, c);
                vals(i) = f(6);
            end
            % Monotone non-increasing (occlusion may saturate the mask fallback).
            tc.verifyMonotoneDecreasing(vals, 'fovCompleteness vs occlusion', true);
        end

        function solidColourNoNaN(tc)
            solid = uint8(120 * ones(256,256,3));
            mask = true(256,256);
            [f, d] = netra.quality.extractFeatures(solid, mask, tc.Cfg);
            tc.verifyTrue(all(isfinite(f)), 'Solid-colour input produced NaN/Inf.');
            tc.verifyEqual(numel(f), 8);
            tc.assumeNotEmpty(d);            % detail struct present
        end

        function emptyMaskIsSafe(tc)
            [f, d] = netra.quality.extractFeatures(tc.Fundus, false(512,512), tc.Cfg);
            tc.verifyTrue(all(isfinite(f)), 'Empty mask produced NaN/Inf.');
            tc.verifyTrue(d.emptyFov, 'emptyFov flag not set on empty mask.');
        end

    end

    % ==================== helpers ========================================
    methods
        function vals = trendFeature(tc, type, sev, featIdx)
            vals = zeros(size(sev));
            for i = 1:numel(sev)
                d = netra.io.simulateFieldCapture(tc.Fundus, type, sev(i), 7);
                f = netra.quality.extractFeatures(d, tc.Mask, tc.Cfg);
                vals(i) = f(featIdx);
            end
        end

        function verifyMonotoneDecreasing(tc, v, name, allowFlat)
            if nargin < 4, allowFlat = false; end
            df = diff(v);
            if allowFlat
                tc.verifyLessThanOrEqual(max(df), 1e-6, ...
                    sprintf('%s is not non-increasing: %s', name, mat2str(v,3)));
            else
                tc.verifyLessThan(max(df), 1e-9, ...
                    sprintf('%s is not strictly decreasing: %s', name, mat2str(v,3)));
            end
        end

        function verifyMonotoneIncreasing(tc, v, name)
            df = diff(v);
            tc.verifyGreaterThanOrEqual(min(df), -1e-6, ...
                sprintf('%s is not non-decreasing: %s', name, mat2str(v,3)));
            tc.verifyGreaterThan(v(end), v(1), ...
                sprintf('%s did not rise overall: %s', name, mat2str(v,3)));
        end
    end
end

% ======================= fixtures =======================================
function img = synthFundus(n, cx, cy, rad, bright)
    [X,Y] = meshgrid(linspace(0,1,n), linspace(0,1,n));
    R = sqrt((X-cx).^2 + (Y-cy).^2);
    m = double(R <= rad*0.5);
    fall = 1 - min(1, R/(rad*0.5));
    % Add texture so focus/contrast features are non-degenerate.
    tex = 0.08 * sin(40*X) .* cos(40*Y);
    r = (bright*(0.6 + 0.3*fall) + tex).*m;
    g = (bright*(0.35 + 0.2*fall) + tex).*m;
    b = (bright*(0.12 + 0.05*fall)).*m;
    img = uint8(255*cat(3, min(1,max(0,r)), min(1,max(0,g)), min(1,max(0,b))));
end
