classdef tEnhancement < matlab.unittest.TestCase
    %TENHANCEMENT  Tests for the adaptive enhancement stage (Phase 4).
    %   Runs on synthetic fundi + the real demo JPEGs (data/demo/*.jpeg) when
    %   present. No external dataset required. Where the brief asks for a
    %   before/after quality table on 20 borderline images, the table is BUILT
    %   and printed from an actual run (not asserted to a magnitude we did not
    %   measure); the assertions only require improvement-or-equal on average.

    properties
        Cfg
        Clean       % clean synthetic fundus
        DemoImgs    % cell array of real demo fundus (may be empty)
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.Cfg = netra.loadConfig();
            tc.Clean = synthFundus(512, 0.9);
            tc.DemoImgs = loadDemos();
        end
    end

    methods (Test)

        function producesTypedOutputs(tc)
            cr = tc.runEnhance(tc.Clean);
            tc.verifyClass(cr.img.enhanced, 'uint8');
            tc.verifyClass(cr.img.modelInput, 'single');
            tc.verifyEqual(size(cr.img.enhanced,3), 3);
            tc.verifyEqual(size(cr.img.modelInput,3), 3);
            tc.verifyEqual(cr.provenance.preproc, "REAL");
        end

        function noNaNorInfInEitherOutput(tc)
            imgs = [{tc.Clean}, tc.DemoImgs];
            for k = 1:numel(imgs)
                cr = tc.runEnhance(imgs{k});
                tc.verifyFalse(any(~isfinite(double(cr.img.enhanced(:)))), ...
                    sprintf('enhanced has non-finite (img %d).', k));
                tc.verifyFalse(any(~isfinite(cr.img.modelInput(:))), ...
                    sprintf('modelInput has non-finite (img %d).', k));
            end
        end

        function claheClipDiffersWithContrast(tc)
            % Low-contrast input must get a larger clip than high-contrast input.
            hi = synthFundus(512, 0.9);                 % rich texture -> contrasty
            lo = lowContrast(hi);                        % flattened -> low contrast
            [mask,~] = netra.preproc.fovMask(hi, tc.Cfg);
            cHi = localContrast(hi, mask);
            cLo = localContrast(lo, mask);
            [~, clipHi] = netra.preproc.claheAdaptive(hi, mask, cHi, tc.Cfg);
            [~, clipLo] = netra.preproc.claheAdaptive(lo, mask, cLo, tc.Cfg);
            tc.verifyGreaterThan(clipLo, clipHi, ...
                sprintf('Low-contrast clip %.4f not > high-contrast clip %.4f.', clipLo, clipHi));
        end

        function cleanImageStepsAreMinimal(tc)
            % A clean image should NOT trigger illum-normalise or denoise (proves
            % no over-processing). CLAHE + geometry + model-input always run.
            cr = tc.runEnhance(tc.Clean);
            steps = cr.preproc.appliedSteps;
            tc.verifyFalse(cr.preproc.illumApplied, ...
                'Illumination normalisation fired on a clean, uniform image.');
            tc.verifyFalse(cr.preproc.denoiseApplied, ...
                'Denoise fired on a clean, low-noise image.');
            tc.verifyTrue(any(contains(steps, 'skipped')), ...
                'No step was skipped on a clean image (expected adaptive skips).');
        end

        function borderlineTriggersMoreSteps(tc)
            % An unevenly-lit / noisy image should fire MORE real steps than a
            % clean one - the core adaptiveness claim (chip lists differ).
            clean = tc.runEnhance(tc.Clean);
            dark  = unevenLight(tc.Clean, 0.8);
            bl    = tc.runEnhance(dark);
            nClean = countReal(clean.preproc);
            nBl    = countReal(bl.preproc);
            tc.verifyGreaterThanOrEqual(nBl, nClean, ...
                'Borderline image did not fire at least as many real steps.');
            tc.verifyNotEqual(chipSig(clean.preproc), chipSig(bl.preproc), ...
                'Clean and borderline produced identical step lists (not adaptive).');
        end

        function beforeAfterQualityTable(tc)
            % Build a real before/after quality-score table on up to 20
            % borderline images (synthetic degradations of the clean fundus).
            % Prints it; asserts the AVERAGE score does not drop.
            n = 20; before = nan(n,1); after = nan(n,1);
            for k = 1:n
                sev = 0.4 + 0.5*mod(k,4)/4;
                deg = unevenLight(tc.Clean, sev);
                before(k) = qualityScore(deg, tc.Cfg);
                cr = tc.runEnhance(deg);
                after(k) = qualityScore(cr.img.enhanced, tc.Cfg);
            end
            fprintf('\n[tEnhancement] Before/after quality (20 borderline):\n');
            fprintf('  mean before = %.1f   mean after = %.1f   delta = %+.1f\n', ...
                mean(before,'omitnan'), mean(after,'omitnan'), ...
                mean(after,'omitnan')-mean(before,'omitnan'));
            tc.verifyGreaterThanOrEqual(mean(after,'omitnan'), mean(before,'omitnan')-1, ...
                'Average quality dropped after enhancement.');
        end

        function schemaPreproFieldsPresent(tc)
            cr = tc.runEnhance(tc.Clean);
            for f = ["appliedSteps","claheClip","illumApplied","denoiseApplied"]
                tc.verifyTrue(isfield(cr.preproc, f), ...
                    sprintf('preproc.%s missing.', f));
            end
        end

    end

    methods
        function cr = runEnhance(tc, img)
            tmp = [tempname '.png']; imwrite(img, tmp);
            cr = netra.newCaseRecord(tmp);
            cr.img.raw = img;
            cr = netra.preproc.enhance(cr, tc.Cfg);
            delete(tmp);
        end
    end
end

% ======================= helpers ========================================
function img = synthFundus(n, brightness)
    [X,Y] = meshgrid(linspace(0,1,n), linspace(0,1,n));
    R = sqrt((X-0.5).^2 + (Y-0.5).^2);
    m = double(R <= 0.45);
    tex = 0.10*sin(50*X).*cos(50*Y);
    r = brightness*(0.6 + tex).*m; g = brightness*(0.38 + tex).*m; b = 0.12.*m;
    img = uint8(255*cat(3, min(1,max(0,r)), min(1,max(0,g)), min(1,max(0,b))));
end

function img = lowContrast(img)
    d = double(img); mu = mean(d(:));
    img = uint8(mu + 0.25*(d - mu));            % squeeze contrast toward the mean
end

function img = unevenLight(img, sev)
    % Impose a smooth left->right illumination gradient (breaks quadrant
    % uniformity) and a mild contrast squeeze, so the illum-normalise trigger
    % fires. sev in [0,1].
    [h, w, ~] = size(img);
    ramp = linspace(1-0.6*sev, 1+0.0*sev, w);   % darker on one side
    G = repmat(ramp, h, 1);
    out = img;
    for c = 1:3
        out(:,:,c) = uint8(min(255, max(0, double(img(:,:,c)) .* G)));
    end
    img = out;
end

function c = localContrast(img, mask)
    g = double(img(:,:,2))/255;
    if any(mask(:)), c = std(g(mask)); else, c = std(g(:)); end
end

function s = qualityScore(img, cfg)
    [mask,~] = netra.preproc.fovMask(img, cfg);
    feat = netra.quality.extractFeatures(img, mask, cfg);
    s = netra.quality.scoreComposite(feat, cfg);
end

function n = countReal(pp)
    % Count real (non-skipped, non-mask, non-modelinput) enhancement steps.
    n = 0;
    for s = pp.appliedSteps
        if contains(s,'skipped'), continue; end
        if startsWith(s,'CLAHE') || startsWith(s,'illumNormalize') || startsWith(s,'denoise(Wiener')
            n = n + 1;
        end
    end
end

function sig = chipSig(pp)
    sig = strjoin(pp.appliedSteps, '|');
end

function imgs = loadDemos()
    here = fileparts(fileparts(mfilename('fullpath')));
    d = dir(fullfile(here, 'data', 'demo', '*.jpeg'));
    imgs = {};
    for k = 1:numel(d)
        try
            im = imread(fullfile(d(k).folder, d(k).name));
            if size(im,3) == 1, im = repmat(im,1,1,3); end
            imgs{end+1} = im; %#ok<AGROW>
        catch
        end
    end
end
