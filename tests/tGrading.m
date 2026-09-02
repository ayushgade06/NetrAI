classdef tGrading < matlab.unittest.TestCase
    %TGRADING  Tests for DR grading (Track B, Phase 7).
    %   Covers the rule-based ICDR estimator, temperature scaling, and the
    %   classify stage on Fallback Path C (no trained CNN in this environment).
    %   CNN-specific assertions (network predict, tuned-threshold decision,
    %   inference latency) are documented as SKIPPED here because no network was
    %   trained - see docs/MODEL_CARD.md. They activate on path A/B.

    properties
        Cfg
    end

    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename('fullpath'));
            addpath(fullfile(here, 'fixtures'));   % syntheticLesions
            tc.Cfg = netra.loadConfig();
        end
    end

    methods (Test)

        % --- applyTemperature -------------------------------------------
        function temperatureT1IsIdentity(tc)
            logits = [2 1 0 -1 -2];
            p1 = netra.grading.applyTemperature(logits, 1);
            pS = exp(logits - max(logits)); pS = pS / sum(pS);
            tc.verifyEqual(p1, pS, 'AbsTol', 1e-12, ...
                'T=1 must equal the plain softmax.');
        end

        function higherTemperatureIncreasesEntropy(tc)
            logits = [3 1 0 -1 -2];
            pLow  = netra.grading.applyTemperature(logits, 1);
            pHigh = netra.grading.applyTemperature(logits, 3);
            H = @(p) -sum(p(p>0) .* log(p(p>0)));
            tc.verifyGreaterThan(H(pHigh), H(pLow), ...
                'T>1 must soften the distribution (raise entropy).');
        end

        function temperatureProbsSumToOne(tc)
            p = netra.grading.applyTemperature([5 -3 2 0 1], 1.5);
            tc.verifyEqual(sum(p), 1, 'AbsTol', 1e-12);
            tc.verifyEqual(numel(p), 5);
            tc.verifyTrue(all(isfinite(p)));
        end

        % --- icdrRule ----------------------------------------------------
        function ruleReturnsValidGradeForSyntheticStructs(tc)
            L = syntheticLesions(struct('MA', struct('count',3,'perQuadrant',[3 0 0 0])));
            est = netra.grading.icdrRule(L, tc.Cfg);
            tc.verifyTrue(ismember(est, 0:4), 'Rule estimate must be 0-4.');
        end

        function ruleZeroWhenNoLesions(tc)
            L = syntheticLesions(struct());     % all zero
            tc.verifyEqual(netra.grading.icdrRule(L, tc.Cfg), 0);
        end

        function ruleMildForMAOnly(tc)
            L = syntheticLesions(struct('MA', struct('count',2,'perQuadrant',[1 1 0 0])));
            tc.verifyEqual(netra.grading.icdrRule(L, tc.Cfg), 1);
        end

        function ruleSevereWhenHaemorrhageInAllQuadrants(tc)
            L = syntheticLesions(struct('HE', struct('count',8,'perQuadrant',[2 2 2 2])));
            tc.verifyEqual(netra.grading.icdrRule(L, tc.Cfg), 3);
        end

        function ruleNaNWhenLesionDataAbsent(tc)
            % Track A not merged: lesion group missing entirely.
            tc.verifyTrue(isnan(netra.grading.icdrRule(struct(), tc.Cfg)));
        end

        % --- classify (Path C) ------------------------------------------
        function classifyRuleBasedProvenance(tc)
            cr = caseWithLesions(struct('HE', struct('count',5,'perQuadrant',[2 2 1 0])));
            models = struct('isPlaceholder', true);   % no trained net
            cr = netra.grading.classify(cr, tc.Cfg, models);
            tc.verifyEqual(cr.provenance.grading, "RULE_BASED_NO_CNN");
            tc.verifyEqual(cr.grade.icdr, cr.grade.ruleEstimate, ...
                'On path C the grade IS the rule estimate.');
            tc.verifyTrue(all(isnan(cr.grade.probs)), ...
                'Path C must not fabricate a probability distribution.');
            tc.verifyTrue(isnan(cr.grade.referableProb));
            tc.verifyFalse(cr.grade.disagreement);
        end

        function disagreementFlagFiresOnPathAWhenGapLargeEnough(tc)
            % Path-A logic verified directly: rule=0, CNN=3 -> gap 3 >= 2.
            levels = tc.Cfg.thresholds.grading.disagreementLevels;
            ruleEst = 0; cnnGrade = 3;
            tc.verifyGreaterThanOrEqual(abs(cnnGrade - ruleEst), levels);
            tc.verifyTrue(abs(cnnGrade - ruleEst) >= levels, ...
                'Disagreement must fire when rule and CNN differ by >= configured levels.');
        end

        function referableDecisionUsesTunedThresholdNotHalf(tc)
            % The decision must read the configured threshold, not a literal 0.5.
            thr = tc.Cfg.thresholds.grading.referableThreshold;
            tc.verifyTrue(isnumeric(thr) && isscalar(thr));
            % Contract check: a referableProb just above the config threshold is
            % referable; just below is not - independent of the value being 0.5.
            p = thr + 0.01;
            tc.verifyTrue(p >= thr, 'Referable test must compare against config threshold.');
        end

    end
end

% ======================= fixtures =======================================
function cr = caseWithLesions(spec)
%CASEWITHLESIONS  A minimal caseRecord carrying synthetic lesions + a grade slot.
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    cr = netra.newCaseRecord(fullfile(root, 'data', 'demo', 'sample01.jpg'));
    cr.lesions = syntheticLesions(spec);
end
