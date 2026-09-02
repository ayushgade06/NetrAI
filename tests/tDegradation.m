classdef tDegradation < matlab.unittest.TestCase
    %TDEGRADATION  Tests for netra.io.simulateFieldCapture.
    %   Each degradation must move a metric in the documented direction, be
    %   reproducible given a seed, and be ~a no-op at severity 0.

    properties
        Cfg
        Img
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.Cfg = netra.loadConfig();
            tc.Img = synthFundus(400);
        end
    end

    methods (Test)

        function blurLowersLaplacianVariance(tc)
            out = netra.io.simulateFieldCapture(tc.Img, "blur", 0.7, 1);
            tc.verifyLessThan(lapVar(out), lapVar(tc.Img));
        end

        function underexposedLowersMeanIntensity(tc)
            out = netra.io.simulateFieldCapture(tc.Img, "underexposed", 0.7, 1);
            tc.verifyLessThan(meanInt(out), meanInt(tc.Img));
        end

        function overexposedRaisesSaturatedFraction(tc)
            out = netra.io.simulateFieldCapture(tc.Img, "overexposed", 0.8, 1);
            tc.verifyGreaterThan(satFrac(out), satFrac(tc.Img));
        end

        function partialFovLowersFovCompleteness(tc)
            base = netra.io.simulateFieldCapture(tc.Img, "partialFOV", 0.0, 1); % ~no-op
            out  = netra.io.simulateFieldCapture(tc.Img, "partialFOV", 0.6, 1);
            [~, mBase] = netra.preproc.fovMask(base, tc.Cfg);
            [~, mOut]  = netra.preproc.fovMask(out,  tc.Cfg);
            tc.verifyLessThan(mOut.completeness, mBase.completeness);
        end

        function hazeLowersLocalContrast(tc)
            out = netra.io.simulateFieldCapture(tc.Img, "haze", 0.7, 1);
            tc.verifyLessThan(localContrast(out), localContrast(tc.Img));
        end

        function sameSeedIsDeterministic(tc)
            a = netra.io.simulateFieldCapture(tc.Img, "random", 0.6, 42);
            b = netra.io.simulateFieldCapture(tc.Img, "random", 0.6, 42);
            tc.verifyEqual(a, b);
        end

        function differentSeedsDiffer(tc)
            a = netra.io.simulateFieldCapture(tc.Img, "random", 0.6, 1);
            b = netra.io.simulateFieldCapture(tc.Img, "random", 0.6, 2);
            tc.verifyNotEqual(a, b);
        end

        function severityZeroIsApproxNoOp(tc)
            for ty = ["blur","underexposed","overexposed","haze"]
                out = netra.io.simulateFieldCapture(tc.Img, ty, 0.0, 1);
                d = mean(abs(double(out(:)) - double(tc.Img(:))));
                tc.verifyLessThan(d, 2.0, ...
                    sprintf('%s at severity 0 changed the image (mean |d|=%.2f).', ty, d));
            end
        end

    end
end

% ======================= metrics ========================================
function v = lapVar(img)
    g = double(rgb2grayLocal(img));
    lap = conv2(g, [0 1 0; 1 -4 1; 0 1 0], 'valid');
    v = var(lap(:));
end
function m = meanInt(img)
    m = mean(double(img(:)));
end
function f = satFrac(img)
    f = mean(double(img(:)) >= 250);
end
function c = localContrast(img)
    g = double(rgb2grayLocal(img));
    mu = conv2(g, ones(9)/81, 'valid');
    sq = conv2(g.^2, ones(9)/81, 'valid');
    c = mean(sqrt(max(0, sq - mu.^2)), 'all');   % mean local std
end
function g = rgb2grayLocal(img)
    g = 0.299*double(img(:,:,1)) + 0.587*double(img(:,:,2)) + 0.114*double(img(:,:,3));
end

% ======================= fixtures =======================================
function img = synthFundus(n)
    [X,Y] = meshgrid(linspace(-1,1,n), linspace(-1,1,n));
    R = sqrt(X.^2 + Y.^2);
    m = double(R <= 0.9);
    % Add texture so blur/contrast metrics have something to act on.
    tex = 0.15*sin(20*X).*cos(18*Y);
    r = (0.6 + 0.25*(1-R) + tex).*m;
    g = (0.25 + 0.1*(1-R) + tex).*m;
    b = (0.12 + 0.05*(1-R)).*m;
    img = uint8(255*cat(3, clamp(r), clamp(g), clamp(b)));
end
function y = clamp(x)
    y = min(1, max(0, x));
end
