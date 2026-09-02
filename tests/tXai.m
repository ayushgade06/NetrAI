classdef tXai < matlab.unittest.TestCase
    %TXAI  Tests for explainability (Track B, Phase 8): ALA + confidence band +
    %   the no-CNN explain path. Grad-CAM pixel tests need a trained network and
    %   are documented as SKIPPED on Path C (see docs/MODEL_CARD.md); the ALA
    %   maths is fully tested here against synthetic attention maps and masks.

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

        % --- agreementScore (ALA) ---------------------------------------
        function alaOneWhenLesionCoversWholeImage(tc)
            g = rand(32) + 0.01;                 % all-positive attention
            mask = true(32);                     % lesions everywhere
            ala = netra.xai.agreementScore(g, mask, tc.Cfg);
            tc.verifyEqual(ala, 1.0, 'AbsTol', 1e-12, ...
                'ALA must be 1 when the lesion mask covers the entire image.');
        end

        function alaZeroWhenTopRegionDisjointFromLesions(tc)
            % Attention concentrated top-left; lesions bottom-right; no overlap
            % even after dilation.
            g = zeros(64); g(1:8, 1:8) = 1;      % top region = top-left 8x8
            mask = false(64); mask(60:64, 60:64) = true;
            ala = netra.xai.agreementScore(g, mask, tc.Cfg);
            tc.verifyEqual(ala, 0.0, 'AbsTol', 1e-12, ...
                'ALA must be 0 when attention top-region and lesions are disjoint.');
        end

        function alaNaNForAllFalseMask(tc)
            g = rand(32) + 0.01;
            ala = netra.xai.agreementScore(g, false(32), tc.Cfg);
            tc.verifyTrue(isnan(ala), ...
                'All-false lesion mask -> ALA NaN (no lesions to agree with).');
        end

        function alaNaNForEmptyMask(tc)
            g = rand(16) + 0.01;
            tc.verifyTrue(isnan(netra.xai.agreementScore(g, [], tc.Cfg)), ...
                'Absent lesion mask -> ALA NaN (Track A not merged).');
        end

        function alaNaNForEmptyGradcam(tc)
            tc.verifyTrue(isnan(netra.xai.agreementScore([], true(16), tc.Cfg)), ...
                'Empty Grad-CAM -> ALA NaN.');
        end

        % --- confidenceBand ---------------------------------------------
        function bandHandlesNaNAlaWithoutError(tc)
            b = netra.xai.confidenceBand(0.9, 80, NaN, tc.Cfg);
            tc.verifyEqual(b, "High", 'NaN ALA must not demote a high-confidence band.');
        end

        function bandLowWhenConfidenceNaN(tc)
            % Rule-based path: no confidence -> Low band, no error.
            tc.verifyEqual(netra.xai.confidenceBand(NaN, 80, NaN, tc.Cfg), "Low");
        end

        function bandCappedLowByPoorAla(tc)
            alaLow = tc.Cfg.thresholds.xai.alaLowThreshold;
            b = netra.xai.confidenceBand(0.95, 90, alaLow - 0.1, tc.Cfg);
            tc.verifyEqual(b, "Low", ...
                'Finite ALA below threshold must cap the band at Low.');
        end

        % --- explain stage, Path C (no CNN) -----------------------------
        function explainNoCnnLeavesPipelineRunning(tc)
            cr = caseRecordFixture();
            cr.lesions = syntheticLesions(struct('MA', struct('count',2,'perQuadrant',[2 0 0 0])));
            cr.grade.icdr = 1; cr.grade.confidence = NaN;
            models = struct('isPlaceholder', true);
            cr = netra.xai.explain(cr, tc.Cfg, models);   % must not throw
            tc.verifyEqual(cr.provenance.xai, "UNAVAILABLE_NO_CNN");
            tc.verifyEmpty(cr.xai.gradcam, 'No CNN -> empty Grad-CAM.');
            tc.verifyTrue(isnan(cr.xai.agreementScore), 'No CNN -> ALA NaN.');
            tc.verifyNotEmpty(cr.xai.evidenceBullets, ...
                'Evidence bullets are measured, not CNN-derived; still present.');
        end

    end
end

% ======================= fixtures =======================================
function cr = caseRecordFixture()
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    cr = netra.newCaseRecord(fullfile(root, 'data', 'demo', 'sample01.jpg'));
end
