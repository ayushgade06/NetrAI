classdef tQualityGate < matlab.unittest.TestCase
    %TQUALITYGATE  End-to-end tests for netra.quality.assess.  [Phase 3]
    %   Uses synthetic fundus images and Phase 2's degradation engine. Runs in
    %   the rule-based fallback configuration (no trained model required).

    properties
        Cfg
        Clean   % a clean synthetic fundus
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.Cfg = netra.loadConfig();
            tc.Clean = synthFundus(512);
        end
    end

    methods (Test)

        function assessPopulatesEveryQualityField(tc)
            cr = tc.assessImg(tc.Clean);
            q = cr.quality;
            tc.verifyTrue(isfinite(q.score), 'score is not finite.');
            tc.verifyGreaterThanOrEqual(q.score, 0);
            tc.verifyLessThanOrEqual(q.score, 100);
            tc.verifyTrue(ismember(q.class, ["Good","Borderline","Ungradeable"]));
            tc.verifyTrue(isfinite(q.focus));
            tc.verifyTrue(isfinite(q.illum));
            tc.verifyTrue(isfinite(q.fovCompleteness));
            tc.verifyTrue(isfinite(q.contrast));
            tc.verifyNumElements(q.quadrantMeans, 4);
            tc.verifyClass(q.failReason, 'string');
            tc.verifyClass(q.recaptureAdvice, 'string');
        end

        function provenanceIsFallbackWithoutModel(tc)
            cr = tc.assessImg(tc.Clean);
            tc.verifyTrue(ismember(cr.provenance.quality, ...
                ["REAL","RULE_BASED_FALLBACK"]), ...
                'Unexpected provenance for a real image.');
            % In the shipping (no-model) config this is the fallback string.
            if ~isfile(fullfile(repoRoot(),'models','quality_clf.mat'))
                tc.verifyEqual(cr.provenance.quality, "RULE_BASED_FALLBACK");
            end
        end

        function cleanImageIsGood(tc)
            cr = tc.assessImg(tc.Clean);
            tc.verifyEqual(cr.quality.class, "Good", ...
                sprintf('Clean image classified %s (score %.1f).', ...
                cr.quality.class, cr.quality.score));
            tc.verifyEqual(cr.quality.failReason, "", ...
                'failReason non-empty for a Good image.');
        end

        function heavilyBlurredIsUngradeable(tc)
            blurred = netra.io.simulateFieldCapture(tc.Clean, "blur", 0.9, 7);
            cr = tc.assessImg(blurred);
            tc.verifyEqual(cr.quality.class, "Ungradeable", ...
                sprintf('Blurred image classified %s (score %.1f).', ...
                cr.quality.class, cr.quality.score));
            tc.verifyNotEqual(cr.quality.failReason, "", ...
                'failReason empty for an Ungradeable image.');
            tc.verifyNotEqual(cr.quality.recaptureAdvice, "", ...
                'recaptureAdvice empty for an Ungradeable image.');
        end

        function adviceNonEmptyWheneverNotGood(tc)
            dark = netra.io.simulateFieldCapture(tc.Clean, "underexposed", 0.9, 7);
            cr = tc.assessImg(dark);
            if cr.quality.class ~= "Good"
                tc.verifyNotEqual(cr.quality.recaptureAdvice, "", ...
                    'recaptureAdvice empty for a not-Good image.');
            end
        end

        function noPixelsLeavesProvenanceMock(tc)
            % A preview case (no raw image) must not invent a score.
            cr = netra.newCaseRecord(fullfile(repoRoot(),'data','demo','sample01.jpg'));
            cr.img.raw = zeros(0,0,3,'uint8');
            cr = netra.quality.assess(cr, tc.Cfg, struct('isPlaceholder',true));
            tc.verifyEqual(cr.provenance.quality, "MOCK");
        end

        function schemaUnchanged(tc)
            % assess must not add or remove quality fields.
            ref = netra.newCaseRecord(fullfile(repoRoot(),'data','demo','sample01.jpg'));
            before = sort(fieldnames(ref.quality));
            cr = tc.assessImg(tc.Clean);
            after = sort(fieldnames(cr.quality));
            tc.verifyEqual(after, before, 'quality field set changed.');
        end

        function runtimeUnder300msAt512(tc)
            % Warm up (JIT), then time a single 512x512 assessment.
            [mask,~] = netra.preproc.fovMask(tc.Clean, tc.Cfg);
            netra.quality.extractFeatures(tc.Clean, mask, tc.Cfg);   % warmup
            t = tic;
            netra.quality.extractFeatures(tc.Clean, mask, tc.Cfg);
            elapsed = toc(t);
            tc.verifyLessThan(elapsed, 0.300, ...
                sprintf('Feature extraction took %.0f ms (>300 ms).', elapsed*1000));
        end

    end

    methods
        function cr = assessImg(tc, img)
            cr = makeCr(img);
            warnState = warning('off','NETRA:quality:noModel');
            cleanup = onCleanup(@() warning(warnState)); %#ok<NASGU>
            cr = netra.quality.assess(cr, tc.Cfg, struct('isPlaceholder',true));
        end
    end
end

% ======================= helpers ========================================
function cr = makeCr(img)
    tmp = [tempname '.png']; imwrite(img, tmp);
    cr = netra.newCaseRecord(tmp);
    cr.img.raw = img;
    [mask,~] = netra.preproc.fovMask(img, netra.loadConfig());
    cr.img.fovMask = mask;
    delete(tmp);
end

function img = synthFundus(n)
    [X,Y] = meshgrid(linspace(0,1,n), linspace(0,1,n));
    R = sqrt((X-0.5).^2 + (Y-0.5).^2);
    m = double(R <= 0.45);
    tex = 0.10*sin(50*X).*cos(50*Y);        % rich texture -> sharp, contrasty
    r = (0.6 + tex).*m; g = (0.38 + tex).*m; b = 0.12.*m;
    img = uint8(255*cat(3, min(1,max(0,r)), min(1,max(0,g)), min(1,max(0,b))));
end

function r = repoRoot()
    r = fileparts(fileparts(mfilename('fullpath')));
end
