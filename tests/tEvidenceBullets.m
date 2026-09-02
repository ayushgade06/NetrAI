classdef tEvidenceBullets < matlab.unittest.TestCase
    %TEVIDENCEBULLETS  Tests for the evidence-bullet template engine (Track B).
    %   The load-bearing test is INTERNAL CONSISTENCY: no bullet may claim a
    %   lesion type whose count is zero, and quadrant counts quoted in bullets
    %   must match perQuadrant exactly. A fabricated finding here is a defect.

    properties
        Cfg
    end

    methods (TestClassSetup)
        function setup(tc)
            here = fileparts(mfilename('fullpath'));
            addpath(fullfile(here, 'fixtures'));
            tc.Cfg = netra.loadConfig();
        end
    end

    methods (Test)

        function bulletsNonEmptyForCaseWithLesions(tc)
            cr = caseFixture(struct('MA', struct('count',4,'perQuadrant',[2 1 1 0])), 2);
            b = netra.xai.evidenceBullets(cr, tc.Cfg);
            tc.verifyNotEmpty(b);
            tc.verifyTrue(any(contains(b, "microaneurysm")));
        end

        function noBulletClaimsLesionWhenCountZero(tc)
            % MA present, HE/EX/CWS all zero. No bullet may mention the zero types.
            cr = caseFixture(struct('MA', struct('count',3,'perQuadrant',[3 0 0 0])), 1);
            b = netra.xai.evidenceBullets(cr, tc.Cfg);
            joined = lower(strjoin(b, " | "));
            tc.verifyFalse(contains(joined, "haemorrhage"), 'Claimed haemorrhage with count 0.');
            tc.verifyFalse(contains(joined, "exudate"),     'Claimed exudate with count 0.');
            tc.verifyFalse(contains(joined, "cotton"),      'Claimed cotton-wool spot with count 0.');
        end

        function quadrantCountsInBulletsMatchPerQuadrant(tc)
            perQ = [2 0 3 1];
            cr = caseFixture(struct('MA', struct('count',6,'perQuadrant',perQ)), 2);
            b = netra.xai.evidenceBullets(cr, tc.Cfg);
            maBullet = b(contains(b, "microaneurysm"));
            tc.verifyNotEmpty(maBullet);
            s = maBullet(1);
            % Each non-zero quadrant count must appear with its quadrant name;
            % the zero quadrant (inferior) must NOT appear.
            tc.verifyTrue(contains(s, "2 superior"));
            tc.verifyTrue(contains(s, "3 nasal"));
            tc.verifyTrue(contains(s, "1 temporal"));
            tc.verifyFalse(contains(s, "inferior"), 'Zero-count quadrant leaked into bullet.');
        end

        function bulletsContainNoDiagnosticAssertion(tc)
            cr = caseFixture(struct('HE', struct('count',5,'perQuadrant',[2 2 1 0])), 3);
            b = netra.xai.evidenceBullets(cr, tc.Cfg);
            joined = lower(strjoin(b, " | "));
            % Must phrase as "findings consistent with", never "patient has".
            tc.verifyTrue(contains(joined, "findings consistent with"));
            tc.verifyFalse(contains(joined, "patient has"));
            tc.verifyFalse(contains(joined, "diagnosis"));
        end

        function zeroLesionGrade0ProducesSensibleOutput(tc)
            cr = caseFixture(struct(), 0);          % no lesions, grade 0
            b = netra.xai.evidenceBullets(cr, tc.Cfg);
            tc.verifyNotEmpty(b, 'Grade-0 case must still produce bullets, not empty.');
            joined = lower(strjoin(b, " | "));
            tc.verifyTrue(contains(joined, "no referable"));
            tc.verifyTrue(contains(joined, "icdr level 0"));
        end

    end
end

% ======================= fixtures =======================================
function cr = caseFixture(lesionSpec, icdr)
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    cr = netra.newCaseRecord(fullfile(root, 'data', 'demo', 'sample01.jpg'));
    cr.lesions = syntheticLesions(lesionSpec);
    cr.grade.icdr = icdr;
end
