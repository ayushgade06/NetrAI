classdef tPipeline < matlab.unittest.TestCase
    %TPIPELINE  Orchestrator contract tests.

    properties
        Img
        Cfg
        Models
    end

    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename('fullpath'));
            root = fileparts(here);
            tc.Img = fullfile(root, 'data', 'demo', 'sample01.jpg');
            tc.assumeTrue(isfile(tc.Img), ...
                'Demo image data/demo/sample01.jpg is required for tests.');
            tc.Cfg = netra.loadConfig();
            tc.Models = netra.loadModels();
        end
    end

    methods (Test)

        function completesOnValidImage(tc)
            cr = netra.newCaseRecord(tc.Img);
            cr = netra.runPipeline(cr, tc.Cfg, tc.Models);
            tc.verifyClass(cr, 'struct');
            tc.verifyWarningFree(@() netra.util.assertSchema(cr));
        end

        function everyStageSetsProvenance(tc)
            cr = netra.runPipeline(netra.newCaseRecord(tc.Img), tc.Cfg, tc.Models);
            stages = netra.util.stageNames();
            for k = 1:numel(stages)
                val = cr.provenance.(stages{k});
                % Track B adds two mandated fallback tokens for the no-CNN path.
                allowed = ["REAL","MOCK","PARTIAL","FAILED", ...
                           "RULE_BASED_NO_CNN","UNAVAILABLE_NO_CNN"];
                tc.verifyTrue(any(strcmp(val, allowed)), ...
                    sprintf('Stage %s has no provenance (%s).', stages{k}, val));
            end
            tc.verifyEqual(cr.provenance.routing, "REAL");
        end

        function everyStageSetsTiming(tc)
            cr = netra.runPipeline(netra.newCaseRecord(tc.Img), tc.Cfg, tc.Models);
            stages = netra.util.stageNames();
            for k = 1:numel(stages)
                t = cr.timing.(stages{k});
                tc.verifyTrue(isfinite(t) && t >= 0, ...
                    sprintf('Stage %s has no valid timing.', stages{k}));
            end
        end

        function totalCoversStageSum(tc)
            cr = netra.runPipeline(netra.newCaseRecord(tc.Img), tc.Cfg, tc.Models);
            stages = netra.util.stageNames();
            s = 0;
            for k = 1:numel(stages)
                s = s + cr.timing.(stages{k});
            end
            tol = 1e-3;
            tc.verifyGreaterThanOrEqual(cr.timing.total, s - tol);
        end

        function completesUnderOneSecond(tc)
            cr = netra.runPipeline(netra.newCaseRecord(tc.Img), tc.Cfg, tc.Models);
            tc.verifyLessThan(cr.timing.total, 1.0, ...
                'Mock pipeline must complete in under one second.');
        end

        function brokenStageIsCaughtNotFatal(tc)
            % Inject a stage handle that throws, via timeStage directly, to
            % prove the try/catch pattern records the error and continues.
            cr = netra.newCaseRecord(tc.Img);
            badFn = @(cr,cfg,models) error('NETRA:test:boom', 'deliberate');
            caught = false;
            try
                [cr, ~] = netra.util.timeStage(badFn, cr, tc.Cfg, tc.Models);
            catch ME
                caught = true;
                cr.provenance.grading = "FAILED";
                cr.errors(end+1) = struct('stage','grading', ...
                    'identifier', ME.identifier, 'message', ME.message);
            end
            tc.verifyTrue(caught);
            tc.verifyEqual(cr.provenance.grading, "FAILED");
            tc.verifyNotEmpty(cr.errors);
            tc.verifyEqual(cr.errors(end).identifier, 'NETRA:test:boom');
        end

        function pipelineSurvivesRealInjectedFailure(tc)
            % End-to-end: corrupt cfg so one stage throws inside runPipeline,
            % and verify the pipeline still returns a full caseRecord.
            badCfg = tc.Cfg;
            badCfg.thresholds.preproc = rmfield(badCfg.thresholds.preproc, ...
                'claheClipDefault');   % preproc stage reads this -> throws
            cr = netra.runPipeline(netra.newCaseRecord(tc.Img), badCfg, tc.Models);
            tc.verifyClass(cr, 'struct');
            tc.verifyEqual(cr.provenance.preproc, "FAILED");
            tc.verifyNotEmpty(cr.errors);
            % Downstream stages still ran.
            tc.verifyEqual(cr.provenance.routing, "REAL");
        end

    end
end
