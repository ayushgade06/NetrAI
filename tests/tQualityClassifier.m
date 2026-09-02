classdef tQualityClassifier < matlab.unittest.TestCase
    %TQUALITYCLASSIFIER  Tests for the rule-based classifier + fallback path.
    %   The trained-model prediction test runs only if models/quality_clf.mat
    %   exists; otherwise it is skipped (assumeFail-free) so the suite passes in
    %   the rule-based fallback configuration that ships without a trained model.

    properties
        Cfg
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.Cfg = netra.loadConfig();
        end
    end

    methods (Test)

        function ruleBasedReturnsValidClassOnRandomSweep(tc)
            % Randomised eight-feature vectors must always yield a valid class
            % and a finite confidence in [0,1]. No NaN/Inf may leak.
            rng(26038);
            valid = ["Good","Borderline","Ungradeable"];
            for i = 1:500
                feat = randFeat();
                [cls, conf] = netra.quality.classifyRuleBased(feat, tc.Cfg);
                tc.verifyTrue(ismember(cls, valid), ...
                    sprintf('Invalid class "%s" for %s', cls, mat2str(feat,3)));
                tc.verifyTrue(isfinite(conf) && conf >= 0 && conf <= 1, ...
                    'Confidence out of [0,1] or non-finite.');
            end
        end

        function hardOverrideFiresOnLowFov(tc)
            % fovCompleteness below hardRejectFovCompleteness -> Ungradeable
            % regardless of every other feature being ideal.
            good = idealFeat();
            good(6) = tc.Cfg.thresholds.quality.hardRejectFovCompleteness - 0.01;
            [cls, ~] = netra.quality.classifyRuleBased(good, tc.Cfg);
            tc.verifyEqual(cls, "Ungradeable", ...
                'Low-FOV hard override did not fire.');
        end

        function hardOverrideFiresOnDarkAndSaturated(tc)
            q = tc.Cfg.thresholds.quality;
            dark = idealFeat(); dark(5) = q.darkFractionMax + 0.05;
            tc.verifyEqual(netra.quality.classifyRuleBased(dark, tc.Cfg), "Ungradeable");
            sat = idealFeat(); sat(4) = q.saturatedFractionMax + 0.05;
            tc.verifyEqual(netra.quality.classifyRuleBased(sat, tc.Cfg), "Ungradeable");
        end

        function idealFeaturesAreGood(tc)
            tc.verifyEqual(netra.quality.classifyRuleBased(idealFeat(), tc.Cfg), "Good");
        end

        function fallbackActivatesWhenModelAbsent(tc)
            % With no models.quality present, assess must use the rule-based
            % path and set provenance accordingly.
            cr = makeCr(tc, synthFundus(256));
            models = struct('isPlaceholder', true);   % no .quality field
            warnState = warning('off','NETRA:quality:noModel');
            cleanup = onCleanup(@() warning(warnState));
            cr = netra.quality.assess(cr, tc.Cfg, models);
            tc.verifyEqual(cr.provenance.quality, "RULE_BASED_FALLBACK", ...
                'Fallback provenance not set when model absent.');
        end

        function trainedModelLoadsAndPredictsIfPresent(tc)
            % Only runs when a real trained model exists on disk.
            mf = fullfile(repoRoot(), 'models', 'quality_clf.mat');
            tc.assumeTrue(isfile(mf), 'No trained model on disk; skipping.');
            M = load(mf);
            tc.assertTrue(isfield(M,'qmodel'), 'quality_clf.mat missing qmodel var.');
            q = M.qmodel;
            x = idealFeat();
            sig = q.sigma; sig(sig==0) = 1;
            xn = (x - q.mu) ./ sig;
            label = predict(q.model, xn);
            tc.verifyTrue(ismember(string(label), ...
                ["Good","Borderline","Ungradeable"]), ...
                'Trained model returned an unexpected label.');
        end

    end
end

% ======================= helpers ========================================
function f = idealFeat()
    % Comfortably above every "up" threshold, below every "down" threshold.
    f = [0.20, 0.10, 0.90, 0.00, 0.00, 0.98, 0.20, 0.15];
end

function f = randFeat()
    f = [rand*0.3, rand*0.2, rand, rand*0.5, rand*0.6, rand, rand*0.3, rand*0.2];
    if rand < 0.05, f(randi(8)) = 0; end        % occasional degenerate zero
end

function cr = makeCr(tc, img) %#ok<INUSD>
    tmp = [tempname '.png']; imwrite(img, tmp);
    cr = netra.newCaseRecord(tmp);
    cr.img.raw = img;
    delete(tmp);
end

function img = synthFundus(n)
    [X,Y] = meshgrid(linspace(0,1,n), linspace(0,1,n));
    R = sqrt((X-0.5).^2 + (Y-0.5).^2);
    m = double(R <= 0.45);
    tex = 0.08*sin(40*X).*cos(40*Y);
    r = (0.6 + tex).*m; g = (0.35 + tex).*m; b = 0.12.*m;
    img = uint8(255*cat(3, min(1,max(0,r)), min(1,max(0,g)), min(1,max(0,b))));
end

function r = repoRoot()
    r = fileparts(fileparts(mfilename('fullpath')));   % tests/ -> root
end
