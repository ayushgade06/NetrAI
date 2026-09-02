classdef tSimulink < matlab.unittest.TestCase
    %TSIMULINK  Tests for the district capacity model (Track C).
    %   Exercises netra.sim.* against either the real Simulink model or the
    %   labelled MATLAB numerical fallback - the block equations are identical
    %   by construction, so every invariant below holds for either backend.

    properties
        Cfg
        P
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.Cfg = netra.loadConfig();
            here = fileparts(mfilename('fullpath'));
            addpath(fullfile(fileparts(here), 'simulink'));
            tc.P = default_params(tc.Cfg);
        end
    end

    methods (Test)

        % ---- CONSERVATION (written first: catches wiring errors) --------
        function conservationHolds(tc)
            L = netra.sim.numericalModel(tc.P);
            [resid, rel] = netra.sim.conservationResidual(L);
            tc.verifyLessThan(abs(rel), 1e-6, ...
                sprintf('Mass balance violated: residual %.3g (rel %.3g).', resid, rel));
        end

        function conservationHoldsEveryScenario(tc)
            here = fileparts(mfilename('fullpath'));
            addpath(fullfile(fileparts(here), 'simulink'));
            sc = scenarios(tc.Cfg);
            for k = 1:numel(sc)
                L = netra.sim.numericalModel(sc(k).params);
                [~, rel] = netra.sim.conservationResidual(L);
                tc.verifyLessThan(abs(rel), 1e-6, ...
                    sprintf('Scenario %d violates conservation.', k));
            end
        end

        % ---- runs and completes under the runtime budget ----------------
        function runsWithoutErrorUnderBudget(tc)
            out = netra.sim.runCapacity(tc.P);
            tc.verifyTrue(ismember(out.source, ["simulink","matlab_numerical"]));
            tc.verifyLessThan(out.runtimeSeconds, tc.P.maxRuntimeSeconds);
            tc.verifyEqual(numel(out.signals.reviewQueueDepth), round(tc.P.simDays));
        end

        % ---- SANITY: zero reviewers -> queue diverges monotonically ------
        function zeroReviewersDiverge(tc)
            p = tc.P; p.reviewers = 0; p.autoClearRate = 0;
            L = netra.sim.numericalModel(p);
            q = L.reviewQueueDepth;
            % Non-decreasing and strictly larger at the end than the start.
            tc.verifyGreaterThanOrEqual(min(diff(q)), -1e-9, 'Queue must not shrink.');
            tc.verifyGreaterThan(q(end), q(1), 'Queue must grow without reviewers.');
        end

        % ---- SANITY: huge reviewer count -> queue ~ 0 -------------------
        function hugeReviewersKeepQueueNearZero(tc)
            p = tc.P; p.reviewers = 1e6;
            L = netra.sim.numericalModel(p);
            tc.verifyLessThan(max(L.reviewQueueDepth), ...
                0.01 * max(L.dailyArrivals), 'Queue should stay near zero.');
        end

        % ---- queue never negative --------------------------------------
        function queueNeverNegative(tc)
            L = netra.sim.numericalModel(tc.P);
            tc.verifyGreaterThanOrEqual(min(L.reviewQueueDepth), 0);
        end

        % ---- scenarios produce measurably different curves --------------
        function scenariosDiffer(tc)
            here = fileparts(mfilename('fullpath'));
            addpath(fullfile(fileparts(here), 'simulink'));
            sc = scenarios(tc.Cfg);
            q1 = netra.sim.numericalModel(sc(1).params).reviewQueueDepth;
            q2 = netra.sim.numericalModel(sc(2).params).reviewQueueDepth;
            q3 = netra.sim.numericalModel(sc(3).params).reviewQueueDepth;
            tc.verifyGreaterThan(max(abs(q1 - q2)), 1, 'S1 vs S2 should differ.');
            tc.verifyGreaterThan(max(abs(q2 - q3)), 1, 'S2 vs S3 should differ.');
        end

        function reviewersOneVsTwoChangesQueue(tc)
            p1 = tc.P; p1.reviewers = 1; p1.autoClearRate = 0;
            p2 = p1;   p2.reviewers = 2;
            q1 = netra.sim.numericalModel(p1).reviewQueueDepth;
            q2 = netra.sim.numericalModel(p2).reviewQueueDepth;
            tc.verifyGreaterThan(max(abs(q1 - q2)), 1, ...
                'Changing reviewers 1->2 must visibly change the queue.');
        end

        % ---- buildParams ingests measured latency -----------------------
        function buildParamsIngestsMeasuredLatency(tc)
            lat = struct('available', true, 'gradingMedian', 4.2, ...
                'perStage', struct('grading', struct('median', 4.2, 'p95', 5)));
            p = netra.sim.buildParams(struct(), lat, tc.Cfg);
            tc.verifyEqual(p.inferenceSecPerImage, 4.2, 'AbsTol', 1e-9);
            tc.verifyEqual(string(p.inferenceSecPerImage_src), "measured");
        end

        function buildParamsFallsBackToAssumed(tc)
            lat = struct('available', false);
            p = netra.sim.buildParams(struct(), lat, tc.Cfg);
            tc.verifyEqual(string(p.inferenceSecPerImage_src), "assumed");
        end

        function uiOverrideWins(tc)
            lat = struct('available', false);
            p = netra.sim.buildParams(struct('reviewers', 5), lat, tc.Cfg);
            tc.verifyEqual(p.reviewers, 5);
        end

        % ---- recommendation is generated from the run -------------------
        function recommendationHasNumbersFromRun(tc)
            out = netra.sim.runCapacity(tc.P);
            txt = netra.sim.recommendation(out, tc.P);
            tc.verifyGreaterThan(strlength(txt), 0);
            tc.verifyTrue(~isempty(regexp(char(txt), '\d', 'once')), ...
                'Recommendation must contain at least one number from the run.');
        end

    end
end
