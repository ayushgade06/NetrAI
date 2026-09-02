classdef tIngestion < matlab.unittest.TestCase
    %TINGESTION  Tests for the +netra/+io ingestion layer.
    %   Uses synthetic images (no real dataset required): a disc-on-black
    %   "fundus" and non-fundus patterns (gradient, checkerboard).

    properties
        Cfg
        TmpDir
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.Cfg = netra.loadConfig();
            tc.TmpDir = tempname; mkdir(tc.TmpDir);
        end
    end
    methods (TestClassTeardown)
        function teardown(tc)
            if isfolder(tc.TmpDir), rmdir(tc.TmpDir, 's'); end
        end
    end

    methods (Test)

        function loadImageReturnsUint8HxWx3(tc)
            img = synthFundus(400);
            p = fullfile(tc.TmpDir, 'f1.png');
            imwrite(img, p);
            [out, info] = netra.io.loadImage(p);
            tc.verifyClass(out, 'uint8');
            tc.verifyEqual(ndims(out), 3);
            tc.verifyEqual(size(out,3), 3);
            tc.verifyEqual(info.format, "png");
        end

        function validateRejectsBelowMinDimension(tc)
            small = synthFundus(100);           % < io.minDimension (256)
            [ok, reason] = netra.io.validateImage(small, tc.Cfg);
            tc.verifyFalse(ok);
            tc.verifySubstring(char(reason), 'minimum dimension');
        end

        function validateRejectsExtremeAspectRatio(tc)
            wide = uint8(zeros(300, 900, 3));
            wide(:, :, 1) = 128;                 % non-uniform so only AR fails
            wide(1,1,1) = 255;
            [ok, reason] = netra.io.validateImage(wide, tc.Cfg);
            tc.verifyFalse(ok);
            tc.verifySubstring(char(reason), 'Aspect ratio');
        end

        function plausibleFundusScoresHigh(tc)
            img = synthFundus(400);
            [isFundus, score] = netra.io.isPlausibleFundus(img, tc.Cfg);
            tc.verifyGreaterThanOrEqual(score, tc.Cfg.thresholds.io.fundusPlausibilityMin);
            tc.verifyTrue(isFundus);
        end

        function nonFundusScoresLow(tc)
            % A full-frame checkerboard: no black border, no red dominance.
            n = 400;
            [X,Y] = meshgrid(1:n, 1:n);
            cb = uint8(mod(floor(X/25) + floor(Y/25), 2) * 255);
            checker = repmat(cb, 1, 1, 3);
            [isFundusC, scoreC] = netra.io.isPlausibleFundus(checker, tc.Cfg);
            tc.verifyLessThan(scoreC, tc.Cfg.thresholds.io.fundusPlausibilityMin);
            tc.verifyFalse(isFundusC);

            % A smooth grayscale gradient filling the frame: also not a fundus.
            grad = uint8(repmat(uint8(linspace(0,255,n)), n, 1));
            grad = repmat(grad, 1, 1, 3);
            [~, scoreG] = netra.io.isPlausibleFundus(grad, tc.Cfg);
            tc.verifyLessThan(scoreG, tc.Cfg.thresholds.io.fundusPlausibilityMin);
        end

        function hashIsDeterministicAndDistinct(tc)
            a = synthFundus(300);
            b = a; b(1,1,1) = uint8(mod(double(b(1,1,1))+40, 256));
            tc.verifyEqual(netra.io.hashImage(a), netra.io.hashImage(a));  % deterministic
            tc.verifyNotEqual(netra.io.hashImage(a), netra.io.hashImage(b)); % distinct
            tc.verifyEqual(strlength(netra.io.hashImage(a)), 64);           % SHA-256 hex
        end

        function uidFormatAndUniqueness(tc)
            u1 = netra.io.generateUID("PHC001", datetime(2026,9,2), "OD", 7);
            tc.verifyEqual(u1, "PHC001-20260902-0007-OD");
            u2 = netra.io.generateUID("PHC001", datetime(2026,9,2), "OD", 8);
            tc.verifyNotEqual(u1, u2);           % different seq -> different uid
            % Bad eye is rejected.
            tc.verifyError(@() netra.io.generateUID("PHC001", datetime(2026,9,2), "XX", 1), ...
                'NETRA:io:badEye');
        end

        function grayscaleIsReplicatedAndFlagged(tc)
            gray = uint8(40 + 150*mat2grayLocal(discMask(400)));  % 1-channel disc
            p = fullfile(tc.TmpDir, 'gray.png');
            imwrite(gray, p);
            [out, info] = netra.io.loadImage(p);
            tc.verifyEqual(size(out,3), 3);
            tc.verifyTrue(info.wasGrayscale);
            % all three channels identical after replication
            tc.verifyEqual(out(:,:,1), out(:,:,2));
            tc.verifyEqual(out(:,:,2), out(:,:,3));
        end

        function unsupportedFormatErrors(tc)
            p = fullfile(tc.TmpDir, 'note.bmp');
            imwrite(synthFundus(300), p);
            tc.verifyError(@() netra.io.loadImage(p), 'NETRA:io:unsupportedFormat');
        end

    end
end

% ======================= fixtures =======================================
function img = synthFundus(n)
%SYNTHFUNDUS  Red-dominant disc on a black surround (a fundus-like fixture).
    m = discMask(n);
    [X,Y] = meshgrid(linspace(-1,1,n), linspace(-1,1,n));
    R = sqrt(X.^2 + Y.^2);
    r = (0.55 + 0.30*(1-R)) .* m;      % red channel, bright, radial falloff
    g = (0.22 + 0.10*(1-R)) .* m;
    b = (0.12 + 0.05*(1-R)) .* m;
    img = uint8(255*cat(3, min(1,r), min(1,g), min(1,b)));
end

function m = discMask(n)
    [X,Y] = meshgrid(linspace(-1,1,n), linspace(-1,1,n));
    m = double(sqrt(X.^2 + Y.^2) <= 0.92);
end

function g = mat2grayLocal(x)
    lo = min(x(:)); hi = max(x(:));
    if hi > lo, g = (x - lo)/(hi - lo); else, g = zeros(size(x)); end
end
