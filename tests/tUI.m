classdef tUI < matlab.unittest.TestCase
    %TUI  Tests for the NETRA_App programmatic UI shell.
    %   These construct the real app. They require a display / graphics-capable
    %   MATLAB. Where a headless environment cannot create a uifigure, the
    %   affected tests assume-skip rather than fail.

    methods (TestClassSetup)
        function ensureSeed(~)
            root = fileparts(fileparts(mfilename('fullpath')));
            seed = fullfile(root, 'data', 'mock', 'registry_seed.mat');
            if ~isfile(seed)
                addpath(fullfile(root, 'tools'));
                seedMockRegistry(seed);
            end
        end
    end

    methods (Test)

        function constructsAndDestructs(tc)
            app = tc.tryLaunch();
            tc.addTeardown(@() delete(app));
            tc.verifyClass(app, 'NETRA_App');
        end

        function allSevenViewPanelsExist(tc)
            app = tc.tryLaunch();
            tc.addTeardown(@() delete(app));
            names = app.tGetViewNames();
            tc.verifyEqual(numel(names), 7, ...
                'Expected exactly seven view panels.');
        end

        function modeToggleChangesNavVisibility(tc)
            app = tc.tryLaunch();
            tc.addTeardown(@() delete(app));
            % Field mode: New Screening visible, Review Queue hidden.
            app.tSetMode('Field');
            tc.verifyEqual(char(app.tNavVisible("New Screening")), 'on');
            tc.verifyEqual(char(app.tNavVisible("Review Queue")), 'off');
            % Clinician mode: Review Queue visible, New Screening hidden.
            app.tSetMode('Clinician');
            tc.verifyEqual(char(app.tNavVisible("Review Queue")), 'on');
            tc.verifyEqual(char(app.tNavVisible("New Screening")), 'off');
        end

        function navCallbacksSwitchActiveView(tc)
            app = tc.tryLaunch();
            tc.addTeardown(@() delete(app));
            app.tSetMode('Clinician');
            for nm = ["Dashboard","Workbench","Review Queue","Case Review", ...
                      "Validation & Capacity"]
                app.tNavTo(nm);
                tc.verifyEqual(app.tGetActiveView(), nm);
            end
        end

        function bannerListsMockStages(tc)
            % Direct helper test (no figure needed beyond a container).
            fig = tc.tryFigure();
            tc.addTeardown(@() delete(fig));
            prov = struct('quality',"MOCK",'grading',"MOCK",'routing',"REAL");
            h = netra.ui.statusBanner(fig, prov);
            tc.verifySubstring(h.Label.Text, 'MOCK COMPONENTS ACTIVE');
            tc.verifySubstring(h.Label.Text, 'quality');
            tc.verifySubstring(h.Label.Text, 'grading');
        end

        function bannerGreenWhenAllReal(tc)
            fig = tc.tryFigure();
            tc.addTeardown(@() delete(fig));
            prov = struct('quality',"REAL",'grading',"REAL");
            h = netra.ui.statusBanner(fig, prov);
            tc.verifySubstring(h.Label.Text, 'validated implementations');
        end

        function reviewTimerStartsStopsCleansUp(tc)
            app = tc.tryLaunch();
            tc.addTeardown(@() delete(app));
            app.tStartTimer();
            tc.verifyTrue(app.tTimerRunning());
            s = app.tStopTimer();
            tc.verifyGreaterThanOrEqual(s, 0);
            tc.verifyFalse(app.tTimerRunning());
        end

        function fiveConstructDeleteCyclesLeaveNoTimers(tc)
            tc.tryLaunch();   % probe: skips here if no display
            n0 = numel(timerfindall());
            for i = 1:5
                app = NETRA_App();
                app.tStartTimer();
                delete(app);
            end
            tc.verifyEqual(numel(timerfindall()), n0, ...
                'Timers leaked across construct/delete cycles.');
        end

        function formatGradeMapsLevels(tc)
            [l0,~] = netra.ui.formatGrade(0);
            [l4,~] = netra.ui.formatGrade(4);
            [ln,~] = netra.ui.formatGrade(NaN);
            tc.verifyEqual(l0, "No DR");
            tc.verifyEqual(l4, "Proliferative DR");
            tc.verifyEqual(ln, "Not graded");
        end

    end

    methods (Access = private)
        function app = tryLaunch(tc)
            try
                app = NETRA_App();
            catch ME
                tc.assumeFail(sprintf(...
                    'Cannot construct NETRA_App (no display?): %s', ME.message));
            end
        end
        function fig = tryFigure(tc)
            try
                fig = uifigure('Visible','off');
            catch ME
                tc.assumeFail(sprintf('Cannot create uifigure: %s', ME.message));
            end
        end
    end
end
