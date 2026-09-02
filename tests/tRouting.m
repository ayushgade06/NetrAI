classdef tRouting < matlab.unittest.TestCase
    %TROUTING  Real routing-logic tests: one per rule, first-match-wins.

    properties
        Cfg
        Img
    end

    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename('fullpath'));
            root = fileparts(here);
            tc.Img = fullfile(root, 'data', 'demo', 'sample01.jpg');
            tc.assumeTrue(isfile(tc.Img), ...
                'Demo image data/demo/sample01.jpg is required for tests.');
            tc.Cfg = netra.loadConfig();
        end
    end

    methods (Test)

        function rule1_ungradeableRecapture(tc)
            cr = tc.base();
            cr.quality.class = "Ungradeable";
            cr.grade.icdr = 4;                 % high grade must NOT win
            cr = netra.routing.decide(cr, tc.Cfg);
            tc.verifyEqual(cr.routing.decision, "RECAPTURE");
            tc.verifyEqual(cr.routing.urgency, "None");
        end

        function rule2_grade4Urgent(tc)
            cr = tc.base();
            cr.grade.icdr = 4;
            cr = netra.routing.decide(cr, tc.Cfg);
            tc.verifyEqual(cr.routing.decision, "REVIEW_QUEUE");
            tc.verifyEqual(cr.routing.urgency, "Urgent");
        end

        function rule3_referableNearMaculaUrgent(tc)
            cr = tc.base();
            cr.grade.icdr = 2;
            cr.lesions.EX.nearMacula = 1;      % triggers macula rule
            cr = netra.routing.decide(cr, tc.Cfg);
            tc.verifyEqual(cr.routing.decision, "REVIEW_QUEUE");
            tc.verifyEqual(cr.routing.urgency, "Urgent");
        end

        function rule4_grade3Priority(tc)
            cr = tc.base();
            cr.grade.icdr = 3;
            cr = netra.routing.decide(cr, tc.Cfg);
            tc.verifyEqual(cr.routing.urgency, "Priority");
        end

        function rule5_grade2Routine(tc)
            cr = tc.base();
            cr.grade.icdr = 2;                 % no near-macula lesion
            cr = netra.routing.decide(cr, tc.Cfg);
            tc.verifyEqual(cr.routing.decision, "REVIEW_QUEUE");
            tc.verifyEqual(cr.routing.urgency, "Routine");
        end

        function rule6_lowConfidenceRoutineUncertain(tc)
            cr = tc.base();
            cr.grade.icdr = 1;                 % below grade rules
            cr.grade.confidence = tc.Cfg.thresholds.grading.confidenceMin - 0.1;
            cr = netra.routing.decide(cr, tc.Cfg);
            tc.verifyEqual(cr.routing.urgency, "Routine");
            tc.verifyTrue(ismember("Uncertain", cr.routing.flags));
        end

        function rule7_lowAgreementRoutine(tc)
            cr = tc.base();
            cr.grade.icdr = 1;
            cr.grade.confidence = 0.9;          % clears rule 6
            cr.xai.agreementScore = tc.Cfg.thresholds.xai.alaLowThreshold - 0.1;
            cr = netra.routing.decide(cr, tc.Cfg);
            tc.verifyEqual(cr.routing.urgency, "Routine");
            tc.verifyTrue(ismember("LowAgreement", cr.routing.flags));
        end

        function rule8_disagreementRoutine(tc)
            cr = tc.base();
            cr.grade.icdr = 0;
            cr.grade.confidence = 0.9;
            cr.xai.agreementScore = 0.9;        % clears rules 6,7
            cr.grade.disagreement = true;
            cr = netra.routing.decide(cr, tc.Cfg);
            tc.verifyEqual(cr.routing.urgency, "Routine");
            tc.verifyTrue(ismember("Disagreement", cr.routing.flags));
        end

        function rule9_confidentGrade0AutoCleared(tc)
            cr = tc.base();
            cr.grade.icdr = 0;
            cr.grade.confidence = 0.9;
            cr.xai.agreementScore = 0.9;
            cr.grade.disagreement = false;
            cr = netra.routing.decide(cr, tc.Cfg);
            tc.verifyEqual(cr.routing.decision, "AUTO_CLEARED");
            tc.verifyEqual(cr.routing.urgency, "None");
        end

        function firstMatchWins_ungradeableBeatsGrade4(tc)
            % Ungradeable (rule 1) must beat grade>=4 (rule 2).
            cr = tc.base();
            cr.quality.class = "Ungradeable";
            cr.grade.icdr = 4;
            cr = netra.routing.decide(cr, tc.Cfg);
            tc.verifyEqual(cr.routing.decision, "RECAPTURE");
        end

        function provenanceIsReal(tc)
            cr = tc.base();
            cr = netra.routing.decide(cr, tc.Cfg);
            tc.verifyEqual(cr.provenance.routing, "REAL");
        end

    end

    methods (Access = private)
        function cr = base(tc)
            % A confident, gradeable, grade-0 baseline (routes AUTO_CLEARED
            % unless a test overrides fields). Uses the real factory.
            cr = netra.newCaseRecord(tc.Img);
            cr.quality.class      = "Good";
            cr.grade.icdr         = 0;
            cr.grade.confidence   = 0.9;
            cr.grade.disagreement = false;
            cr.xai.agreementScore = 0.9;
        end
    end
end
