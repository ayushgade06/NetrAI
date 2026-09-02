classdef tReport < matlab.unittest.TestCase
    %TREPORT  Tests for the clinical PDF report and composite figure (Track C).

    properties
        Cfg
        Models
        TmpRoot
        Demo
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.Cfg = netra.loadConfig();
            try, tc.Models = netra.loadModels(); catch, tc.Models = struct(); end
            root = fileparts(fileparts(mfilename('fullpath')));
            tc.Demo = fullfile(root, 'data', 'demo', 'sample01.jpg');
            % Redirect the store so reports never touch the real data/ tree.
            tc.TmpRoot = tempname; mkdir(tc.TmpRoot);
            setenv('NETRA_STORE_ROOT', tc.TmpRoot);
        end
    end

    methods (TestClassTeardown)
        function teardown(tc)
            setenv('NETRA_STORE_ROOT', '');
            if isfolder(tc.TmpRoot), rmdir(tc.TmpRoot, 's'); end
        end
    end

    methods (Access = private)
        function cr = mockCase(tc, grade)
            cr = netra.newCaseRecord(char(tc.Demo));
            cr = netra.runPipeline(cr, tc.Cfg, tc.Models);
            cr.grade.icdr = grade;
            cr.grade.confidence = 0.8;
        end
    end

    methods (Test)

        function generatesNonTrivialPdf(tc)
            cr = tc.mockCase(2);
            pdf = netra.report.generate(cr, tc.Cfg);
            tc.verifyTrue(isfile(pdf), 'Report PDF must exist.');
            info = dir(pdf);
            tc.verifyGreaterThan(info.bytes, 2000, 'PDF should be non-trivial in size.');
        end

        function compositeHandlesMissingGradCam(tc)
            cr = tc.mockCase(1);
            cr.xai.gradcam = zeros(0,0,'single');   % no attention map
            cr.provenance.xai = "MOCK";
            fig = netra.report.composite(cr, tc.Cfg);
            cleanup = onCleanup(@() delete(fig)); %#ok<NASGU>
            tc.verifyTrue(ishandle(fig), 'Composite must render even without Grad-CAM.');
        end

        function compositeHandlesZeroLesions(tc)
            cr = tc.mockCase(0);   % grade 0: no lesions
            fig = netra.report.composite(cr, tc.Cfg);
            cleanup = onCleanup(@() delete(fig)); %#ok<NASGU>
            tc.verifyTrue(ishandle(fig));
        end

        function footerHasDisclaimer(tc)
            cr = tc.mockCase(3);
            R = netra.report.template(cr, tc.Cfg);
            tc.verifySubstring(char(R.disclaimer), ...
                'Requires ophthalmologist confirmation');
            tc.verifySubstring(char(R.disclaimer), ...
                'not validated for clinical use');
        end

        function reportHasProvenanceSummary(tc)
            cr = tc.mockCase(2);
            R = netra.report.template(cr, tc.Cfg);
            joined = strjoin(R.provenance, ' ');
            % Every pipeline stage should appear in the provenance summary so a
            % reader can see which stages were mock at generation time.
            tc.verifySubstring(char(joined), 'grading');
            tc.verifySubstring(char(joined), 'routing');
        end

        function allGradesNoOverflow(tc)
            for g = 0:4
                cr = tc.mockCase(g);
                pdf = netra.report.generate(cr, tc.Cfg);
                tc.verifyTrue(isfile(pdf), sprintf('Grade %d report must exist.', g));
            end
        end

    end
end
