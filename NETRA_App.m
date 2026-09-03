classdef NETRA_App < handle
%NETRA_APP  Programmatic UI shell for the NETRA DR-screening prototype.
%   app = NETRA_App() launches the seven-view desktop application against the
%   Phase 0 mock pipeline. Built entirely in code (no .mlapp), all layout via
%   uigridlayout, all colours/fonts/spacing from netra.ui.theme.
%
%   Views: Dashboard, New Screening, Quality Gate, Workbench, Review Queue,
%   Case Review, Validation & Capacity. View switching toggles panel
%   Visible; panels are built once at construction.
%
%   The app calls the pipeline only as:
%       cr = netra.runPipeline(cr, app.Config, app.Models);
%   never individual stages.
%
%   Close with the window's X or delete(app); the review timer is stopped and
%   deleted in delete().

    properties (Access = private)
        % --- state ---
        Config       struct                     % loaded once at construction
        Models       struct                     % loaded once at construction
        CurrentCase                             % active caseRecord or []
        OrigImage                               % last loaded uint8 HxWx3 (pristine)
        WorkImage                               % working image (maybe degraded)
        LoadedPath   string = ""                % path of the loaded image
        Degradation  struct = struct('type',"none",'severity',0,'seed',0)
        Mode         string = "Field"           % "Field" | "Clinician"
        ActiveView   string = "Dashboard"
        DevMode      logical = false            % dev-only verdict override
        ReviewTimer                             % stopwatch timer object
        ReviewStart                             % datetime when review began
        ReviewingUid string = ""                % uid of the case open in Case Review
        ReviewerID   string = "reviewer01"      % logged as the review author
        QueueTable   table                      % cached queue
        CPHandles    struct = struct()          % Capacity Planner handles
        LastSimOut                              % last netra.sim.runCapacity out
        Root         string                     % project root

        % --- top-level UI handles ---
        Fig
        NavButtons   struct = struct()          % name -> uibutton
        NavGrid                                  % the nav rail uigridlayout (row heights)
        NavPanel
        ModeSwitch
        Banner                                   % statusBanner handle struct
        ContentGrid
        Views        struct = struct()          % name -> uipanel

        % --- per-view handles needed by callbacks ---
        DashHandles  struct = struct()
        NewHandles   struct = struct()
        QGHandles    struct = struct()
        WBHandles    struct = struct()
        RQHandles    struct = struct()
        CRHandles    struct = struct()
    end

    properties (Constant, Access = private)
        NavOrder = ["Dashboard","New Screening","Quality Gate","Workbench", ...
                    "Review Queue","Case Review","Validation & Capacity"];
        % Which nav items each persona sees (both see Dashboard + Validation).
        FieldViews     = ["Dashboard","New Screening","Quality Gate", ...
                          "Workbench","Validation & Capacity"];
        ClinicianViews = ["Dashboard","Workbench","Review Queue", ...
                          "Case Review","Validation & Capacity"];
    end

    methods (Access = public)
        function app = NETRA_App(varargin)
            % Optional name/value: 'DevMode', true
            p = inputParser;
            addParameter(p, 'DevMode', false, @islogical);
            parse(p, varargin{:});
            app.DevMode = p.Results.DevMode;

            app.Root = string(fileparts(mfilename('fullpath')));

            % Fail loudly if config cannot load - do not launch half-configured.
            try
                app.Config = netra.loadConfig();
            catch ME
                error('NETRA:ui:configFailed', ...
                    ['NETRA cannot start: configuration failed to load.\n%s\n' ...
                     '(%s)'], ME.message, ME.identifier);
            end
            try
                app.Models = netra.loadModels();
            catch
                app.Models = struct('isPlaceholder', true);
            end

            app.buildShell();
            app.buildAllViews();
            app.applyMode();
            app.switchView("Dashboard");
        end

        function delete(app)
            % Stop and delete the review timer; never leak timers.
            app.stopReviewTimer();
            if ~isempty(app.ReviewTimer) && isa(app.ReviewTimer,'timer') ...
                    && isvalid(app.ReviewTimer)
                delete(app.ReviewTimer);
            end
            app.ReviewTimer = [];
            if ~isempty(app.Fig) && isvalid(app.Fig)
                delete(app.Fig);
            end
        end
    end

    % ====================================================================
    %  TEST HOOKS (read-only accessors + programmatic drivers for tUI.m)
    % ====================================================================
    methods (Access = ?matlab.unittest.TestCase)
        function names = tGetViewNames(app)
            names = string(fieldnames(app.Views))';
        end
        function v = tGetActiveView(app)
            v = app.ActiveView;
        end
        function tSetMode(app, m)
            app.onModeChanged(m);
        end
        function vis = tNavVisible(app, name)
            vis = app.NavButtons.(app.key(name)).Visible;
        end
        function tNavTo(app, name)
            app.onNav(name);
        end
        function h = tBanner(app)
            h = app.Banner;
        end
        function tStartTimer(app)
            app.startReviewTimer();
        end
        function s = tStopTimer(app)
            s = app.stopReviewTimer();
        end
        function tf = tTimerRunning(app)
            tf = ~isempty(app.ReviewTimer) && isa(app.ReviewTimer,'timer') ...
                && isvalid(app.ReviewTimer) && strcmp(app.ReviewTimer.Running,'on');
        end
    end

    % ====================================================================
    %  SHELL
    % ====================================================================
    methods (Access = private)
        function buildShell(app)
            t = netra.ui.theme();

            app.Fig = uifigure( ...
                'Name', 'NETRA - Explainable DR Screening (PROTOTYPE)', ...
                'Color', t.color.bg, ...
                'Position', [80 60 t.size.defWidth t.size.defHeight], ...
                'AutoResizeChildren', 'on');
            app.Fig.DeleteFcn = @(~,~) app.delete();

            outer = uigridlayout(app.Fig, [1 2], ...
                'ColumnWidth', {t.size.navWidth, '1x'}, ...
                'RowHeight', {'1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 0, ...
                'BackgroundColor', t.color.bg);

            app.buildNavRail(outer);

            right = uigridlayout(outer, [3 1], ...
                'RowHeight', {t.size.topBarHeight, t.size.bannerHeight, '1x'}, ...
                'RowSpacing', 0, 'Padding', [0 0 0 0], ...
                'BackgroundColor', t.color.bg);
            right.Layout.Column = 2;

            app.buildTopBar(right);

            app.Banner = netra.ui.statusBanner(right);
            app.Banner.Panel.Layout.Row = 2;

            app.ContentGrid = uigridlayout(right, [1 1], ...
                'Padding', t.space.pad*[1 1 1 1], ...
                'BackgroundColor', t.color.bg);
            app.ContentGrid.Layout.Row = 3;
        end

        function buildNavRail(app, parent)
            t = netra.ui.theme();
            names = app.NavOrder;

            app.NavPanel = uipanel(parent, 'BorderType', 'none', ...
                'BackgroundColor', t.color.navBg);
            app.NavPanel.Layout.Column = 1;

            g = uigridlayout(app.NavPanel, [numel(names)+2 1], ...
                'RowHeight', [{t.size.topBarHeight}, ...
                    repmat({t.size.buttonHeight+8}, 1, numel(names)), {'1x'}], ...
                'RowSpacing', t.space.gapSm, ...
                'Padding', [t.space.gapSm t.space.pad t.space.gapSm t.space.pad], ...
                'BackgroundColor', t.color.navBg);
            app.NavGrid = g;   % kept so applyMode can collapse hidden nav rows

            title = uilabel(g, 'Text', 'NETRA', ...
                'FontName', t.font.family, 'FontSize', t.font.h1, ...
                'FontWeight', 'bold', 'FontColor', t.color.text, ...
                'HorizontalAlignment', 'center');
            title.Layout.Row = 1;

            icons = ["[#]","[+]","[Q]","[W]","[=]","[>]","[V]"];
            for k = 1:numel(names)
                nm = names(k);
                b = uibutton(g, 'Text', "  " + icons(k) + "  " + nm, ...
                    'FontName', t.font.family, 'FontSize', t.font.body, ...
                    'FontColor', t.color.text, ...
                    'BackgroundColor', t.color.navBg, ...
                    'HorizontalAlignment', 'left', ...
                    'ButtonPushedFcn', @(~,~) app.onNav(nm));
                b.Layout.Row = k+1;
                app.NavButtons.(app.key(nm)) = b;
            end
        end

        function buildTopBar(app, parent)
            t = netra.ui.theme();
            bar = uipanel(parent, 'BorderType','none', ...
                'BackgroundColor', t.color.panel);
            bar.Layout.Row = 1;

            g = uigridlayout(bar, [1 3], ...
                'ColumnWidth', {'1x', 'fit', 'fit'}, ...
                'ColumnSpacing', t.space.gap, ...
                'Padding', [t.space.pad t.space.gapSm t.space.pad t.space.gapSm], ...
                'BackgroundColor', t.color.panel);

            uilabel(g, 'Text', 'NETRA  -  Explainable DR Screening', ...
                'FontName', t.font.family, 'FontSize', t.font.h2, ...
                'FontWeight', 'bold', 'FontColor', t.color.text, ...
                'VerticalAlignment', 'center');

            uilabel(g, 'Text', 'Mode:', ...
                'FontName', t.font.family, 'FontSize', t.font.body, ...
                'FontColor', t.color.textMuted, ...
                'HorizontalAlignment', 'right', 'VerticalAlignment','center');

            app.ModeSwitch = uidropdown(g, ...
                'Items', {'Field','Clinician'}, ...
                'Value', 'Field', ...
                'FontName', t.font.family, 'FontSize', t.font.body, ...
                'FontColor', t.color.text, ...
                'BackgroundColor', t.color.panelAlt, ...
                'ValueChangedFcn', @(src,~) app.onModeChanged(src.Value));
        end

        function buildAllViews(app)
            t = netra.ui.theme();
            for k = 1:numel(app.NavOrder)
                nm = app.NavOrder(k);
                pnl = uipanel(app.ContentGrid, 'BorderType','none', ...
                    'BackgroundColor', t.color.bg, 'Visible', 'off');
                pnl.Layout.Row = 1; pnl.Layout.Column = 1;
                app.Views.(app.key(nm)) = pnl;
            end
            app.buildDashboard();
            app.buildNewScreening();
            app.buildQualityGate();
            app.buildWorkbench();
            app.buildReviewQueue();
            app.buildCaseReview();
            app.buildValidationAndCapacity();
        end
    end

    % ====================================================================
    %  VIEW 1 - DASHBOARD
    % ====================================================================
    methods (Access = private)
        function buildDashboard(app)
            t = netra.ui.theme();
            root = app.Views.(app.key("Dashboard"));
            s = app.safeStats();

            g = uigridlayout(root, [4 1], ...
                'RowHeight', {t.size.cardHeight, 'fit', '1x', '1.2x'}, ...
                'RowSpacing', t.space.gapLg, 'Padding', [0 0 0 0], ...
                'BackgroundColor', t.color.bg);

            % --- KPI strip (6 cards) ---
            kg = uigridlayout(g, [1 6], 'Padding',[0 0 0 0], ...
                'ColumnSpacing', t.space.gap, 'BackgroundColor', t.color.bg);
            kg.Layout.Row = 1;
            app.DashHandles.kScreened = netra.ui.kpiCard(kg, "Screened Today", s.screenedToday, "");
            app.DashHandles.kReferred = netra.ui.kpiCard(kg, "Referred", s.referred, "", struct('accent', t.color.reject));
            app.DashHandles.kCleared  = netra.ui.kpiCard(kg, "Auto-Cleared", s.autoCleared, "", struct('accent', t.color.pass));
            app.DashHandles.kRecap    = netra.ui.kpiCard(kg, "Recapture Rate", round(100*s.recaptureRate), "%", struct('accent', t.color.warn));
            app.DashHandles.kAvg      = netra.ui.kpiCard(kg, "Avg Review", round(s.avgReviewSeconds), "s");
            app.DashHandles.kQueue    = netra.ui.kpiCard(kg, "Queue Depth", s.queueDepth, "");

            % --- action buttons row ---
            bg = uigridlayout(g, [1 7], 'Padding',[0 0 0 0], ...
                'ColumnSpacing', t.space.gap, ...
                'ColumnWidth', {'1x','1x','1x','1x','1x','1x','1x'}, ...
                'BackgroundColor', t.color.bg);
            bg.Layout.Row = 2;
            app.mkButton(bg, 'New Screening', @() app.switchView("New Screening"), t.color.info);
            app.mkButton(bg, 'Batch Import Folder', @() app.onBatchImport(), t.color.info);
            qcount = s.queueDepth;
            app.DashHandles.btnQueue = app.mkButton(bg, sprintf('Open Review Queue (%d)', qcount), ...
                @() app.switchView("Review Queue"), t.color.panelAlt);
            app.mkButton(bg, 'Capacity Planner', @() app.switchView("Validation & Capacity"), t.color.panelAlt);
            app.mkButton(bg, 'Validation Report', @() app.switchView("Validation & Capacity"), t.color.panelAlt);
            app.mkButton(bg, 'Export Camp Summary', @() app.onExportSummary(), t.color.panelAlt);
            app.mkButton(bg, 'Refresh', @() app.refreshDashboard(), t.color.panelAlt);

            % --- charts row (3 charts) ---
            cg = uigridlayout(g, [1 3], 'Padding',[0 0 0 0], ...
                'ColumnSpacing', t.space.gap, 'BackgroundColor', t.color.bg);
            cg.Layout.Row = 3;
            app.DashHandles.axGrade = app.mkAxesPanel(cg, 'Grade Distribution');
            app.DashHandles.ax7day  = app.mkAxesPanel(cg, 'Last 7 Days');
            app.DashHandles.axHour  = app.mkAxesPanel(cg, 'Queue Depth by Hour');

            % --- bottom row: fail reasons + recent cases table ---
            bg2 = uigridlayout(g, [1 2], 'Padding',[0 0 0 0], ...
                'ColumnWidth', {'1x','1.6x'}, 'ColumnSpacing', t.space.gap, ...
                'BackgroundColor', t.color.bg);
            bg2.Layout.Row = 4;
            app.DashHandles.axFail = app.mkAxesPanel(bg2, 'Quality Failure Reasons');
            app.DashHandles.tblRecent = app.mkRecentTable(bg2);

            app.drawDashboardCharts(s);
        end

        function refreshDashboard(app)
            app.wrap(@() localRefresh());
            function localRefresh()
                s = app.safeStats();
                app.DashHandles.kScreened.set(s.screenedToday);
                app.DashHandles.kReferred.set(s.referred);
                app.DashHandles.kCleared.set(s.autoCleared);
                app.DashHandles.kRecap.set(round(100*s.recaptureRate));
                app.DashHandles.kAvg.set(round(s.avgReviewSeconds));
                app.DashHandles.kQueue.set(s.queueDepth);
                app.DashHandles.btnQueue.Text = sprintf('Open Review Queue (%d)', s.queueDepth);
                app.drawDashboardCharts(s);
                app.populateRecentTable();
            end
        end

        function drawDashboardCharts(app, s)
            t = netra.ui.theme();
            gradeColors = [t.color.grade0; t.color.grade1; t.color.grade2; ...
                           t.color.grade3; t.color.grade4];

            % Grade distribution (bar; honest empty state if all zero)
            ax = app.DashHandles.axGrade; cla(ax);
            if any(s.gradeDistribution > 0)
                b = bar(ax, 0:4, s.gradeDistribution, 'FaceColor','flat');
                b.CData = gradeColors;
                ax.XTick = 0:4;
                ax.XTickLabel = {'0','1','2','3','4'};
            else
                app.emptyAxes(ax, 'No cases yet');
            end
            app.styleAxes(ax);

            % Last 7 days stacked bar
            ax = app.DashHandles.ax7day; cla(ax);
            if ~isempty(s.last7Days) && any(s.last7Days(:) > 0)
                b = bar(ax, 1:7, s.last7Days, 'stacked');
                b(1).FaceColor = t.color.pass;
                b(2).FaceColor = t.color.info;
                b(3).FaceColor = t.color.warn;
                legend(ax, {'Auto-cleared','Reviewed','Recaptured'}, ...
                    'TextColor', t.color.text, 'Color', t.color.panelAlt, ...
                    'EdgeColor', t.color.border, 'FontSize', t.font.tiny, ...
                    'Location','northwest');
            else
                app.emptyAxes(ax, 'No history');
            end
            app.styleAxes(ax);

            % Queue depth by hour (line)
            ax = app.DashHandles.axHour; cla(ax);
            if ~isempty(s.queueDepthByHour) && any(s.queueDepthByHour > 0)
                plot(ax, 1:numel(s.queueDepthByHour), s.queueDepthByHour, ...
                    '-o', 'Color', t.color.info, 'MarkerFaceColor', t.color.info);
            else
                app.emptyAxes(ax, 'No arrivals');
            end
            app.styleAxes(ax);

            % Quality failure reasons (horizontal bar)
            ax = app.DashHandles.axFail; cla(ax);
            fr = s.qualityFailReasons;
            if ~isempty(fr) && any(fr.count > 0)
                barh(ax, categorical(fr.reason), fr.count, ...
                    'FaceColor', t.color.warn);
            else
                app.emptyAxes(ax, 'No failures');
            end
            app.styleAxes(ax);

            app.populateRecentTable();
        end

        function populateRecentTable(app)
            T = app.safeRegistry();
            if isempty(T)
                app.DashHandles.tblRecent.Data = {};
                return;
            end
            T = sortrows(T, 'timestamp', 'descend');
            T = T(1:min(12, height(T)), :);

            % Mock-graded rows get a leading asterisk on the UID so no one
            % mistakes a demo grade for a measurement. A row is mock-graded if
            % its provenanceSummary says grading=MOCK, or if the table has no
            % provenanceSummary column at all (that's the Phase 1 mock seed).
            uidCol = string(T.uid);
            if ismember('provenanceSummary', T.Properties.VariableNames)
                isMockGraded = contains(T.provenanceSummary, "grading=MOCK") | ...
                               contains(T.provenanceSummary, "grading=FAILED");
            else
                isMockGraded = true(height(T),1);   % mock seed -> all demo grades
            end
            uidCol(isMockGraded) = "* " + uidCol(isMockGraded);

            data = [cellstr(uidCol), cellstr(string(T.patientID)), ...
                    cellstr(string(T.age)), cellstr(string(T.eye)), ...
                    cellstr(string(T.icdr)), cellstr(string(T.urgency)), ...
                    cellstr(string(T.routingDecision))];
            app.DashHandles.tblRecent.Data = data;

            % Notice: are we on the real registry, or falling back to the seed?
            if isfield(app.DashHandles, 'recentNotice') && isvalid(app.DashHandles.recentNotice)
                real = netra.store.registry();
                if isempty(real)
                    app.DashHandles.recentNotice.Text = ...
                        'No real registry yet - showing FICTIONAL mock seed. * = mock grade.';
                    app.DashHandles.recentNotice.FontColor = netra.ui.theme().color.warn;
                else
                    app.DashHandles.recentNotice.Text = ...
                        '* grade is MOCK (demo), not a measurement.';
                    app.DashHandles.recentNotice.FontColor = netra.ui.theme().color.textMuted;
                end
            end
        end

        function tbl = mkRecentTable(app, parent)
            t = netra.ui.theme();
            pnl = app.titledPanel(parent, 'Recent Cases');
            % Two rows: table + a legend/notice line.
            gg = uigridlayout(pnl.Grid, [2 1], 'RowHeight', {'1x','fit'}, ...
                'RowSpacing', t.space.gapSm, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.panel);
            tbl = uitable(gg, ...
                'ColumnName', {'UID','Patient','Age','Eye','Grade','Urgency','Decision'}, ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'BackgroundColor', [t.color.panelAlt; t.color.panel], ...
                'ForegroundColor', t.color.text, ...
                'RowName', {}, ...
                'CellSelectionCallback', @(src,ev) app.onRecentRowSelected(ev));
            app.DashHandles.recentNotice = uilabel(gg, ...
                'Text', '* grade is MOCK (demo), not a measurement.', ...
                'FontName', t.font.family, 'FontSize', t.font.tiny, ...
                'FontColor', t.color.textMuted);
        end

        function onRecentRowSelected(app, ev)
            app.wrap(@() localOpen());
            function localOpen()
                if isempty(ev.Indices), return; end
                row = ev.Indices(1);
                T = app.safeRegistry();
                if isempty(T) || row > height(T), return; end
                T = sortrows(T, 'timestamp', 'descend');
                app.loadMockCaseIntoWorkbench(T(row,:), true);
                app.switchView("Workbench");
            end
        end
    end

    % ====================================================================
    %  VIEW 2 - NEW SCREENING (Field)
    % ====================================================================
    methods (Access = private)
        function buildNewScreening(app)
            t = netra.ui.theme();
            root = app.Views.(app.key("New Screening"));

            g = uigridlayout(root, [1 2], 'ColumnWidth', {'1x','1x'}, ...
                'ColumnSpacing', t.space.gapLg, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.bg);

            % --- left: form ---
            fp = app.titledPanel(g, 'Patient & Capture');
            fg = uigridlayout(fp.Grid, [9 2], ...
                'RowHeight', repmat({'fit'},1,9), ...
                'ColumnWidth', {130,'1x'}, ...
                'RowSpacing', t.space.gap, 'ColumnSpacing', t.space.gap, ...
                'BackgroundColor', t.color.panel);

            app.mkFieldLabel(fg, 'Patient ID');
            app.NewHandles.patientID = uieditfield(fg, 'text', ...
                'FontName', t.font.family, 'FontSize', t.font.body, ...
                'BackgroundColor', t.color.panelAlt, 'FontColor', t.color.text);

            app.mkFieldLabel(fg, 'Age');
            app.NewHandles.age = uieditfield(fg, 'numeric', ...
                'Limits',[0 120], 'Value', 55, ...
                'FontName', t.font.family, 'FontSize', t.font.body, ...
                'BackgroundColor', t.color.panelAlt, 'FontColor', t.color.text);

            app.mkFieldLabel(fg, 'Diabetes (yrs)');
            app.NewHandles.dmYears = uieditfield(fg, 'numeric', ...
                'Limits',[0 80], 'Value', 5, ...
                'FontName', t.font.family, 'FontSize', t.font.body, ...
                'BackgroundColor', t.color.panelAlt, 'FontColor', t.color.text);

            app.mkFieldLabel(fg, 'Eye');
            app.NewHandles.eye = uidropdown(fg, 'Items', {'OD','OS'}, ...
                'FontName', t.font.family, 'FontSize', t.font.body, ...
                'BackgroundColor', t.color.panelAlt, 'FontColor', t.color.text);

            app.mkFieldLabel(fg, 'PHC');
            app.NewHandles.phc = uidropdown(fg, 'Items', app.phcItems(), ...
                'FontName', t.font.family, 'FontSize', t.font.body, ...
                'BackgroundColor', t.color.panelAlt, 'FontColor', t.color.text);

            app.mkFieldLabel(fg, 'Image');
            app.NewHandles.imgPathLbl = uilabel(fg, 'Text', '(none loaded)', ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'FontColor', t.color.textMuted);

            % Simulate Field Capture (ENABLED in Phase 2)
            app.mkFieldLabel(fg, 'Simulate Capture');
            simdd = uidropdown(fg, 'Items', ...
                {'(none)','Blur','Underexposed','Overexposed','Partial FOV','Haze','Random'}, ...
                'Enable','on', ...
                'Tooltip','Applies a SYNTHETIC degradation to the loaded image (not a real capture).', ...
                'FontName', t.font.family, 'FontSize', t.font.body, ...
                'BackgroundColor', t.color.panelAlt, 'FontColor', t.color.text, ...
                'ValueChangedFcn', @(src,~) app.onSimulateCapture(src.Value));
            app.NewHandles.simCapture = simdd;

            % Severity slider (0-1, default 0.6)
            app.mkFieldLabel(fg, 'Severity');
            app.NewHandles.severity = uislider(fg, 'Limits',[0 1], 'Value',0.6, ...
                'MajorTicks', [0 0.5 1], ...
                'FontName', t.font.family, 'FontSize', t.font.tiny, ...
                'FontColor', t.color.textMuted);

            % buttons
            app.mkFieldLabel(fg, '');
            brow = uigridlayout(fg, [1 4], 'Padding',[0 0 0 0], ...
                'ColumnSpacing', t.space.gapSm, 'BackgroundColor', t.color.panel);
            app.mkButton(brow, 'Load Image', @() app.onLoadImage(), t.color.info);
            app.NewHandles.btnAnalyze = app.mkButton(brow, 'Analyze', @() app.onAnalyze(), t.color.pass);
            app.NewHandles.btnAnalyze.Enable = 'off';   % enabled once a valid image loads
            app.mkButton(brow, 'Reset Original', @() app.onResetOriginal(), t.color.panelAlt);
            app.mkButton(brow, 'Clear', @() app.onClearForm(), t.color.panelAlt);

            % --- right: preview (tag + thumbnail + FOV/plausibility line) ---
            dp = app.titledPanel(g, 'Image Preview');
            dg = uigridlayout(dp.Grid, [3 1], 'RowHeight', {'fit','1x','fit'}, ...
                'RowSpacing', t.space.gapSm, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.panel);
            % Persistent synthetic-degradation tag (hidden until one is applied).
            app.NewHandles.simTag = uilabel(dg, 'Text','', ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'FontWeight','bold', 'FontColor', t.color.warn, ...
                'BackgroundColor', t.color.bannerWarnBg, ...
                'HorizontalAlignment','center', 'Visible','off');
            app.NewHandles.thumb = uiimage(dg, ...
                'ScaleMethod','fit', 'BackgroundColor', t.color.panelAlt);
            app.NewHandles.previewInfo = uilabel(dg, 'Text','', ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'FontColor', t.color.textMuted, 'WordWrap','on');
        end

        function onLoadImage(app)
            app.wrap(@() localLoad());
            function localLoad()
                exts = app.Config.thresholds.io.supportedFormats;   % {'.jpg',...}
                filt = strjoin("*" + string(exts), ';');
                [f, p] = uigetfile({char(filt), 'Fundus images'}, ...
                    'Select a fundus image');
                if isequal(f, 0), return; end
                full = fullfile(p, f);

                % Real load (also enforces the quarantine guard + format check).
                try
                    [img, ~] = netra.io.loadImage(full);
                catch ME
                    uialert(app.Fig, ME.message, 'Load failed');
                    return;
                end

                % Structural validation.
                [okV, reasonV] = netra.io.validateImage(img, app.Config);
                if ~okV
                    uialert(app.Fig, char(reasonV), 'Invalid image');
                    return;   % form stays populated; Analyze disabled below
                end

                % Plausibility guard (heuristic, not a classifier).
                [isFundus, score, detail] = netra.io.isPlausibleFundus(img, app.Config);
                if ~isFundus
                    names  = ["near-black border","circular bright region","red-channel dominance"];
                    scores = [detail.borderScore, detail.circleScore, detail.redScore];
                    [~, worst] = min(scores);
                    uialert(app.Fig, sprintf(...
                        ['This does not look like a fundus image (plausibility %.2f < %.2f).\n' ...
                         'Weakest cue: %s (%.2f).'], score, ...
                         app.Config.thresholds.io.fundusPlausibilityMin, names(worst), scores(worst)), ...
                        'Not a fundus image');
                    app.setAnalyzeEnabled(false);
                    return;
                end

                % Accept: stash pristine + working image, clear any degradation.
                app.OrigImage = img;
                app.WorkImage = img;
                app.LoadedPath = string(full);
                app.Degradation = struct('type',"none",'severity',0,'seed',0);
                app.NewHandles.simCapture.Value = '(none)';
                app.NewHandles.simTag.Visible = 'off';

                app.NewHandles.imgPathLbl.Text = f;
                app.NewHandles.imgPathLbl.UserData = full;
                app.refreshPreview(score);
                app.setAnalyzeEnabled(true);
            end
        end

        function onSimulateCapture(app, val)
            app.wrap(@() localSim());
            function localSim()
                if isempty(app.OrigImage)
                    uialert(app.Fig, 'Load an image first.', 'No image');
                    app.NewHandles.simCapture.Value = '(none)';
                    return;
                end
                if strcmp(val, '(none)')
                    app.onResetOriginal(); return;
                end
                map = containers.Map( ...
                    {'Blur','Underexposed','Overexposed','Partial FOV','Haze','Random'}, ...
                    {'blur','underexposed','overexposed','partialFOV','haze','random'});
                ty = map(val);
                sev = app.NewHandles.severity.Value;
                seed = 26038;   % fixed -> reproducible demo degradation
                out = netra.io.simulateFieldCapture(app.OrigImage, ty, sev, seed);
                app.WorkImage = out;
                app.Degradation = struct('type',string(ty),'severity',sev,'seed',seed);

                app.NewHandles.simTag.Text = sprintf('SYNTHETIC DEGRADATION: %s (severity %.2f)', ty, sev);
                app.NewHandles.simTag.Visible = 'on';
                app.refreshPreview([]);
            end
        end

        function onResetOriginal(app)
            if isempty(app.OrigImage), return; end
            app.WorkImage = app.OrigImage;
            app.Degradation = struct('type',"none",'severity',0,'seed',0);
            app.NewHandles.simCapture.Value = '(none)';
            app.NewHandles.simTag.Visible = 'off';
            app.refreshPreview([]);
        end

        function refreshPreview(app, plausScore)
            % Render the working image with the detected FOV outline overlaid,
            % and a one-line FOV/plausibility summary.
            img = app.WorkImage;
            [mask, m] = netra.preproc.fovMask(img, app.Config);
            thumb = app.overlayFovOutline(img, mask);
            app.NewHandles.thumb.ImageSource = thumb;

            parts = sprintf('FOV completeness: %.2f', m.completeness);
            if isfield(m,'fallback') && m.fallback
                parts = [parts '  (mask fell back to full frame)'];
            end
            if nargin >= 2 && ~isempty(plausScore)
                parts = [parts sprintf('   |   plausibility: %.2f', plausScore)];
            end
            app.NewHandles.previewInfo.Text = parts;
        end

        function setAnalyzeEnabled(app, tf)
            if isfield(app.NewHandles,'btnAnalyze') && isvalid(app.NewHandles.btnAnalyze)
                app.NewHandles.btnAnalyze.Enable = matlab.lang.OnOffSwitchState(tf);
            end
        end

        function onClearForm(app)
            app.NewHandles.patientID.Value = '';
            app.NewHandles.age.Value = 55;
            app.NewHandles.dmYears.Value = 5;
            app.NewHandles.eye.Value = 'OD';
            app.NewHandles.imgPathLbl.Text = '(none loaded)';
            app.NewHandles.imgPathLbl.UserData = [];
            app.NewHandles.thumb.ImageSource = '';
            app.NewHandles.simCapture.Value = '(none)';
            app.NewHandles.simTag.Visible = 'off';
            app.NewHandles.previewInfo.Text = '';
            app.OrigImage = [];
            app.WorkImage = [];
            app.LoadedPath = "";
            app.Degradation = struct('type',"none",'severity',0,'seed',0);
        end

        function onAnalyze(app)
            app.wrap(@() localAnalyze());
            function localAnalyze()
                pid = strtrim(app.NewHandles.patientID.Value);
                if isempty(pid)
                    uialert(app.Fig, 'Patient ID is required before analysis.', ...
                        'Missing field'); return;
                end
                if isempty(app.WorkImage)
                    uialert(app.Fig, 'Load a valid fundus image first.', ...
                        'Missing image'); return;
                end

                meta = struct('patientID', string(pid), ...
                    'age', app.NewHandles.age.Value, ...
                    'dmYears', app.NewHandles.dmYears.Value, ...
                    'eye', string(app.NewHandles.eye.Value), ...
                    'phcID', app.phcIdFromLabel(app.NewHandles.phc.Value), ...
                    'seq', app.nextSeq(app.phcIdFromLabel(app.NewHandles.phc.Value)));

                d = uiprogressdlg(app.Fig, 'Title','Running NETRA pipeline', ...
                    'Message','Ingesting image, masking FOV, persisting...', ...
                    'Indeterminate','on');
                cleanup = onCleanup(@() delete(d)); %#ok<NASGU>

                % Ingest path: real pixels drive real FOV/crop and persistence.
                cr = netra.newCaseRecord(char(app.LoadedPath), meta);
                cr.img.raw = app.WorkImage;         % pristine OR degraded working image
                if app.Degradation.type ~= "none"
                    cr.preproc.syntheticDegradation = app.Degradation;   % additive, recorded
                end
                cr = netra.runPipeline(cr, app.Config, app.Models);
                app.CurrentCase = cr;
                app.Banner.update(cr.provenance);

                app.populateQualityGate(cr);
                app.switchView("Quality Gate");
            end
        end

        function s = nextSeq(app, phcID)
            % Next per-(phc,today) capture sequence, from the real registry.
            T = netra.store.registry();
            s = 1;
            if isempty(T), return; end
            today = string(datetime('now','Format','yyyyMMdd'));
            same = T(T.phcID == string(phcID), :);
            if isempty(same), return; end
            % uids look like PHC-<yyyymmdd>-<seq>-<eye>; count today's.
            todays = same(contains(same.uid, "-" + today + "-"), :);
            s = height(todays) + 1;
        end

        function out = overlayFovOutline(~, img, mask)
            % Draw the FOV mask boundary on a copy of img (cyan), for preview.
            out = img;
            if isempty(mask) || ~any(mask(:)), return; end
            edge = mask & ~imerode(mask, strel('disk', 2));
            R = out(:,:,1); G = out(:,:,2); B = out(:,:,3);
            R(edge) = 51; G(edge) = 199; B(edge) = 219;   % theme cyan-ish
            out = cat(3, R, G, B);
        end
    end

    % ====================================================================
    %  VIEW 3 - QUALITY GATE
    % ====================================================================
    methods (Access = private)
        function buildQualityGate(app)
            t = netra.ui.theme();
            root = app.Views.(app.key("Quality Gate"));

            g = uigridlayout(root, [2 2], ...
                'RowHeight', {'fit','1x'}, 'ColumnWidth', {'1.5x','1x'}, ...
                'RowSpacing', t.space.gap, 'ColumnSpacing', t.space.gapLg, ...
                'Padding',[0 0 0 0], 'BackgroundColor', t.color.bg);

            % verdict banner (full width, row 1)
            vb = uipanel(g, 'BorderType','none', 'BackgroundColor', t.color.panelAlt);
            vb.Layout.Row = 1; vb.Layout.Column = [1 2];
            vbg = uigridlayout(vb, [1 3], 'ColumnWidth', {'1x','fit','fit'}, ...
                'ColumnSpacing', t.space.gap, ...
                'Padding', t.space.pad*[1 1 1 1], 'BackgroundColor', t.color.panelAlt);
            app.QGHandles.verdict = uilabel(vbg, 'Text', 'VERDICT', ...
                'FontName', t.font.family, 'FontSize', t.font.h2, ...
                'FontWeight','bold', 'FontColor', t.color.text, ...
                'VerticalAlignment','center');
            app.QGHandles.verdict.Layout.Column = 1;
            % Phase 3: amber note shown only when the rule-based fallback is
            % active (trained classifier unavailable). Never present the
            % fallback as a trained model.
            app.QGHandles.provNote = uilabel(vbg, 'Text', '', ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'FontColor', t.color.warn, 'HorizontalAlignment','right', ...
                'VerticalAlignment','center', 'WordWrap','on');
            app.QGHandles.provNote.Layout.Column = 2;
            % dev-only verdict override
            devbox = uigridlayout(vbg, [1 2], 'ColumnWidth', {'fit','fit'}, ...
                'Padding',[0 0 0 0], 'BackgroundColor', t.color.panelAlt);
            devbox.Layout.Column = 3;
            app.QGHandles.devLabel = uilabel(devbox, 'Text','DEV verdict:', ...
                'FontColor', t.color.warn, 'FontSize', t.font.small);
            app.QGHandles.devDrop = uidropdown(devbox, ...
                'Items', {'(mock)','Force Good','Force Borderline','Force Ungradeable'}, ...
                'FontSize', t.font.small, 'BackgroundColor', t.color.panelAlt, ...
                'FontColor', t.color.text, ...
                'ValueChangedFcn', @(src,~) app.onForceVerdict(src.Value));
            app.QGHandles.devLabel.Visible = app.DevMode;
            app.QGHandles.devDrop.Visible = app.DevMode;

            % left: image (row 2, col 1)
            ip = app.titledPanel(g, 'Fundus Image');
            ip.Panel.Layout.Row = 2; ip.Panel.Layout.Column = 1;
            app.QGHandles.canvas = netra.ui.imageCanvas(ip.Grid);

            % right: gauge + subscores + advice (row 2, col 2)
            % Scrollable so the action bar (Continue/Retake) is always reachable
            % on short windows; all rows are fixed/'fit' so the panel overflows
            % and shows a scrollbar instead of clipping the bottom row.
            rp = uipanel(g, 'BorderType','none','BackgroundColor', t.color.bg, ...
                'Scrollable','on');
            rp.Layout.Row = 2; rp.Layout.Column = 2;
            rg = uigridlayout(rp, [6 1], ...
                'RowHeight', {150,'fit','fit','fit','fit','fit'}, ...
                'RowSpacing', t.space.gapLg, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.bg, 'Scrollable','on');

            gp = app.titledPanel(rg, 'Quality Score');
            qmin = app.Config.thresholds.quality.gradeableScoreMin;
            bmin = app.Config.thresholds.quality.borderlineScoreMin;
            app.QGHandles.gauge = netra.ui.gauge(gp.Grid, 0, ...
                struct('thresholds', [bmin qmin], 'caption', "0-100 QUALITY"));

            sp = app.titledPanel(rg, 'Subscores');
            sg = uigridlayout(sp.Grid, [4 1], 'RowSpacing', t.space.gap, ...
                'Padding',[0 0 0 0], 'BackgroundColor', t.color.panel);
            thr = app.Config.thresholds.quality;
            % Phase 3: all four subscores are REAL measurements. Each is a 0..1
            % combined subscore with a threshold tick at 0.5 (the pass line for
            % a combined subscore; individual feature thresholds are in the
            % "Show all measurements" panel below). Tooltips document the
            % combination: Focus = features 1+2, Illumination = 3+4+5,
            % FOV = feature 6, Contrast = features 7+8.
            PASS = 0.5;
            app.QGHandles.sbFocus = netra.ui.subscoreBar(sg, "Focus", 0, PASS);
            app.QGHandles.sbIllum = netra.ui.subscoreBar(sg, "Illumination", 0, PASS);
            app.QGHandles.sbFov   = netra.ui.subscoreBar(sg, "Field of View", 0, thr.fovCompletenessMin);
            app.QGHandles.sbCon   = netra.ui.subscoreBar(sg, "Contrast", 0, PASS);
            app.QGHandles.sbFocus.Label.Tooltip = 'Focus subscore: sharpness from Laplacian variance + Tenengrad gradient (features 1-2), inside FOV.';
            app.QGHandles.sbIllum.Label.Tooltip = 'Illumination subscore: quadrant uniformity + saturated + dark pixel fractions (features 3-5), inside FOV.';
            app.QGHandles.sbFov.Label.Tooltip   = 'Field-of-view completeness: mask area vs a full circle (feature 6). Measured in Phase 2.';
            app.QGHandles.sbCon.Label.Tooltip   = 'Contrast subscore: global std + mean local std of the green channel (features 7-8), inside FOV.';
            for lb = [app.QGHandles.sbFocus.Label, app.QGHandles.sbIllum.Label, ...
                      app.QGHandles.sbFov.Label, app.QGHandles.sbCon.Label]
                lb.FontColor = t.color.text;
            end

            cp = app.titledPanel(rg, 'Preprocessing / Advice');
            cg = uigridlayout(cp.Grid, [2 1], 'RowHeight', {'fit','fit'}, ...
                'Padding',[0 0 0 0], 'BackgroundColor', t.color.panel);
            app.QGHandles.steps = uilabel(cg, 'Text','Applied steps: -', ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'FontColor', t.color.text, 'WordWrap','on');
            app.QGHandles.advice = uilabel(cg, 'Text','', ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'FontColor', t.color.warn, 'WordWrap','on');

            % Phase 3: failReason card - prominent on Ungradeable, a distinct
            % call-to-action card. Hidden entirely when the image is Good.
            fp = app.titledPanel(rg, 'Why this image was rejected');
            app.QGHandles.failCard = fp.Panel;
            app.QGHandles.failReason = uilabel(fp.Grid, 'Text','', ...
                'FontName', t.font.family, 'FontSize', t.font.body, ...
                'FontWeight','bold', 'FontColor', t.color.reject, 'WordWrap','on');
            app.QGHandles.failCard.Visible = 'off';

            % Phase 3: "Show all measurements" - expandable panel listing all
            % eight raw feature values and their thresholds. Collapsed by default.
            mp = app.titledPanel(rg, 'Measurements');
            mg = uigridlayout(mp.Grid, [2 1], 'RowHeight', {'fit','fit'}, ...
                'RowSpacing', t.space.gapSm, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.panel);
            app.QGHandles.measToggle = uibutton(mg, 'Text','Show all measurements  ▸', ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'BackgroundColor', t.color.panelAlt, 'FontColor', t.color.text, ...
                'HorizontalAlignment','left', ...
                'ButtonPushedFcn', @(~,~) app.onQGToggleMeasurements());
            app.QGHandles.measArea = uitextarea(mg, 'Value', {''}, 'Editable','off', ...
                'FontName', 'monospaced', 'FontSize', t.font.small, ...
                'BackgroundColor', t.color.panel, 'FontColor', t.color.text);
            app.QGHandles.measArea.Visible = 'off';
            app.QGHandles.measExpanded = false;

            % action bar (row spanning bottom of right col)
            ap = uipanel(rg, 'BorderType','none','BackgroundColor', t.color.bg);
            abg = uigridlayout(ap, [1 4], 'Padding',[0 0 0 0], ...
                'ColumnSpacing', t.space.gapSm, 'BackgroundColor', t.color.bg);
            app.QGHandles.btnRetake  = app.mkButton(abg, 'Retake', @() app.switchView("New Screening"), t.color.panelAlt);
            app.QGHandles.btnProceed = app.mkButton(abg, 'Proceed w/ Enhanced', @() app.onQGContinue(), t.color.info);
            app.QGHandles.btnContinue= app.mkButton(abg, 'Continue', @() app.onQGContinue(), t.color.pass);
            app.QGHandles.btnToggle  = app.mkButton(abg, 'Show Original', @() app.onQGToggleImage(), t.color.panelAlt);
        end

        function populateQualityGate(app, cr)
            q = cr.quality;
            thr = app.Config.thresholds.quality;

            app.setCanvasBase(app.QGHandles.canvas, cr);

            app.QGHandles.gauge.set(q.score);

            % Combined subscores (0..1) with a 0.5 pass tick; FOV uses its own
            % measured completeness against its real threshold. Focus/Contrast
            % are the combined display values assess already computed; the
            % Illumination combined subscore is derived from the raw features.
            [illumSub, feat, thrVec] = app.qgFeatures(cr);
            app.QGHandles.sbFocus.set(q.focus, 0.5);
            app.QGHandles.sbIllum.set(illumSub, 0.5);
            app.QGHandles.sbFov.set(q.fovCompleteness, thr.fovCompletenessMin);
            app.QGHandles.sbCon.set(q.contrast, 0.5);

            % "Show all measurements": all eight raw features vs their thresholds.
            app.QGHandles.measArea.Value = app.qgMeasurementLines(feat, thrVec);

            % Adaptive enhancement chip list (Phase 4). Each applied step is a
            % [bracketed] chip WITH its parameters, so a clean image and a
            % borderline one produce visibly DIFFERENT chip lists - the proof
            % the enhancement is adaptive, not a fixed filter chain.
            app.QGHandles.steps.Text = app.qgStepChips(cr.preproc.appliedSteps);

            % Provenance note: only when the rule-based fallback is active.
            if cr.provenance.quality == "RULE_BASED_FALLBACK"
                app.QGHandles.provNote.Text = 'Threshold-based assessment (trained classifier unavailable)';
            else
                app.QGHandles.provNote.Text = '';
            end

            % failReason card: prominent on Ungradeable, hidden otherwise.
            if q.class == "Ungradeable" && strlength(q.failReason) > 0
                app.QGHandles.failReason.Text = char(q.failReason);
                app.QGHandles.failCard.Visible = 'on';
            else
                app.QGHandles.failCard.Visible = 'off';
            end

            app.applyVerdict(string(q.class), q.recaptureAdvice);
        end

        function txt = qgStepChips(~, steps)
            % Render preproc.appliedSteps as a readable [chip] list with
            % parameters. Maps the terse internal step ids to human labels while
            % PRESERVING their parameters (clip value, kernel, skipped-reason),
            % so the adaptive difference between images stays visible.
            if isempty(steps)
                txt = 'Applied: (none)'; return;
            end
            chips = strings(1, numel(steps));
            for i = 1:numel(steps)
                s = char(steps(i));
                switch true
                    case strcmp(s,'fovMask'),          chips(i) = "[FOV mask]";
                    case strcmp(s,'fovMaskFallback'),  chips(i) = "[FOV fallback]";
                    case strcmp(s,'cropResize'),       chips(i) = "[Circular crop + resize]";
                    case startsWith(s,'illumNormalize(skipped'), chips(i) = "[Illumination: uniform, skipped]";
                    case startsWith(s,'illumNormalize'), chips(i) = "[Illumination normalisation " + extractParen(s) + "]";
                    case startsWith(s,'CLAHE'),        chips(i) = "[CLAHE " + extractParen(s) + "]";
                    case startsWith(s,'denoise(skipped'), chips(i) = "[Denoise: off]";
                    case startsWith(s,'denoise'),      chips(i) = "[Denoise: Wiener]";
                    case startsWith(s,'benGraham'),    chips(i) = "[Model-input normalise]";
                    case strcmp(s,'enhancementReverted'), chips(i) = "[Enhancement reverted]";
                    otherwise,                         chips(i) = "[" + string(s) + "]";
                end
            end
            txt = "Applied:  " + strjoin(chips, "  ");
            function p = extractParen(str)
                a = strfind(str,'('); b = strfind(str,')');
                if ~isempty(a) && ~isempty(b) && b(end)>a(1)
                    p = str(a(1)+1:b(end)-1);
                else
                    p = '';
                end
            end
        end

        function [illumSub, feat, thrVec] = qgFeatures(app, cr)
            % Recompute the eight raw features for the measurements panel and
            % the combined illumination subscore. The schema is frozen so raw
            % features are not stored on cr; recomputing is < 300 ms and keeps
            % the UI a pure function of the image. Safe if pixels are absent.
            cfg = app.Config;
            thr = cfg.thresholds.quality;
            thrVec = [thr.focusLaplacianMin, thr.focusTenengradMin, ...
                thr.illumUniformityMin, thr.saturatedFractionMax, ...
                thr.darkFractionMax, thr.fovCompletenessMin, ...
                thr.contrastStdMin, thr.localContrastMin];
            if isempty(cr.img.raw)
                feat = nan(1,8); illumSub = 0; return;
            end
            try
                if ~isempty(cr.img.fovMask) && isequal(size(cr.img.fovMask), size(cr.img.raw(:,:,1)))
                    mask = cr.img.fovMask;
                else
                    [mask,~] = netra.preproc.fovMask(cr.img.raw, cfg);
                end
                feat = netra.quality.extractFeatures(cr.img.raw, mask, cfg);
            catch
                feat = nan(1,8); illumSub = 0; return;
            end
            % Illumination combined subscore = mean of uniformity(up),
            % (1-saturated)(down), (1-dark)(down) mapped against thresholds.
            u  = clampUnit(feat(3) / max(thr.illumUniformityMin, eps));
            sa = clampUnit(1 - feat(4) / max(thr.saturatedFractionMax, eps));
            da = clampUnit(1 - feat(5) / max(thr.darkFractionMax, eps));
            illumSub = mean([u sa da]);
        end

        function lines = qgMeasurementLines(~, feat, thrVec)
            names = netra.quality.featureNames();
            dir = {'>=','>=','>=','<=','<=','>=','>=','>='};   % pass direction
            lines = cell(numel(names)+1, 1);
            lines{1} = sprintf('%-18s %8s  %s %-6s  %s', ...
                'FEATURE','VALUE','','THRESH','PASS');
            for i = 1:numel(names)
                v = feat(i); th = thrVec(i);
                if strcmp(dir{i},'>='), pass = v >= th; else, pass = v <= th; end
                if isnan(v), mark = '  -'; elseif pass, mark = ' OK'; else, mark = 'FAIL'; end
                lines{i+1} = sprintf('%-18s %8.3f  %s %-6.3f  %s', ...
                    names{i}, v, dir{i}, th, mark);
            end
        end

        function onQGToggleMeasurements(app)
            app.QGHandles.measExpanded = ~app.QGHandles.measExpanded;
            if app.QGHandles.measExpanded
                app.QGHandles.measArea.Visible = 'on';
                app.QGHandles.measToggle.Text = 'Hide measurements  ▾';
            else
                app.QGHandles.measArea.Visible = 'off';
                app.QGHandles.measToggle.Text = 'Show all measurements  ▸';
            end
        end

        function applyVerdict(app, cls, advice)
            t = netra.ui.theme();
            switch cls
                case "Good"
                    txt = 'GRADEABLE'; c = t.color.pass; gate = true;
                case "Borderline"
                    txt = 'BORDERLINE - ENHANCEMENT APPLIED'; c = t.color.warn; gate = true;
                case "Ungradeable"
                    txt = 'UNGRADEABLE - RECAPTURE REQUIRED'; c = t.color.reject; gate = false;
                otherwise
                    txt = 'VERDICT PENDING'; c = t.color.textMuted; gate = false;
            end
            app.QGHandles.verdict.Text = txt;
            app.QGHandles.verdict.FontColor = c;

            en = matlab.lang.OnOffSwitchState(gate);
            app.QGHandles.btnContinue.Enable = en;
            app.QGHandles.btnProceed.Enable = en;
            if ~gate
                tip = 'Disabled: image is Ungradeable. Retake required.';
                app.QGHandles.btnContinue.Tooltip = tip;
                app.QGHandles.btnProceed.Tooltip = tip;
                if strlength(string(advice)) == 0
                    advice = "Recapture advice: reposition camera, improve focus and illumination.";
                end
            else
                app.QGHandles.btnContinue.Tooltip = '';
                app.QGHandles.btnProceed.Tooltip = '';
            end
            app.QGHandles.advice.Text = string(advice);
        end

        function onForceVerdict(app, val)
            % Dev-only: force layout states without a real quality score.
            switch val
                case 'Force Good',        app.applyVerdict("Good", "");
                case 'Force Borderline',  app.applyVerdict("Borderline", "");
                case 'Force Ungradeable', app.applyVerdict("Ungradeable", "");
                otherwise
                    if ~isempty(app.CurrentCase)
                        app.applyVerdict(string(app.CurrentCase.quality.class), ...
                            app.CurrentCase.quality.recaptureAdvice);
                    end
            end
        end

        function onQGContinue(app)
            app.wrap(@() localCont());
            function localCont()
                if isempty(app.CurrentCase), return; end
                app.populateWorkbench(app.CurrentCase, false);
                app.switchView("Workbench");
            end
        end

        function onQGToggleImage(app)
            % Before/after: swap the QG canvas between the ORIGINAL raw frame
            % and the ENHANCED output (Phase 4 real pixels). Falls back to the
            % enhanced/placeholder base when raw is unavailable.
            b = app.QGHandles.btnToggle;
            cr = app.CurrentCase;
            if isempty(cr), return; end
            if strcmp(b.Text, 'Show Original')
                b.Text = 'Show Enhanced';
                if ~isempty(cr.img.raw)
                    app.QGHandles.canvas.setBase(cr.img.raw);
                end
            else
                b.Text = 'Show Original';
                app.setCanvasBase(app.QGHandles.canvas, cr);   % enhanced
            end
        end
    end

    % ====================================================================
    %  VIEW 4 - WORKBENCH
    % ====================================================================
    methods (Access = private)
        function buildWorkbench(app)
            t = netra.ui.theme();
            root = app.Views.(app.key("Workbench"));

            g = uigridlayout(root, [1 2], 'ColumnWidth', {'1.2x','1x'}, ...
                'ColumnSpacing', t.space.gapLg, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.bg);

            % --- left: canvas + overlay controls ---
            lp = uigridlayout(g, [3 1], 'RowHeight', {'fit','1x','fit'}, ...
                'RowSpacing', t.space.gap, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.bg);

            % overlay checkbox row
            op = app.titledPanel(lp, 'Overlays');
            og = uigridlayout(op.Grid, [1 8], 'Padding',[0 0 0 0], ...
                'ColumnSpacing', t.space.gapSm, 'BackgroundColor', t.color.panel);
            layers = {'Original','Vessels','Disc & Fovea','Quadrants','Lesions','Grad-CAM'};
            keys   = {'Original','Vessels','ODFovea','Quadrants','Lesions','GradCAM'};
            app.WBHandles.chk = struct();
            for k = 1:numel(layers)
                cb = uicheckbox(og, 'Text', layers{k}, 'Value', false, ...
                    'FontName', t.font.family, 'FontSize', t.font.small, ...
                    'FontColor', t.color.text, ...
                    'ValueChangedFcn', @(src,~) app.onOverlayToggle(keys{k}, src.Value));
                app.WBHandles.chk.(keys{k}) = cb;
            end
            % gradcam opacity slider
            uilabel(og, 'Text','GradCAM opacity', 'FontColor', t.color.textMuted, ...
                'FontSize', t.font.tiny);
            app.WBHandles.opacity = uislider(og, 'Limits',[0 1], 'Value',0.6, ...
                'MajorTicks', [], ...
                'ValueChangingFcn', @(~,ev) app.onGradcamOpacity(ev.Value));

            % canvas
            cp = app.titledPanel(lp, 'Analysis Canvas');
            app.WBHandles.canvas = netra.ui.imageCanvas(cp.Grid);

            % view mode + zoom row
            vp = uipanel(lp, 'BorderType','none','BackgroundColor', t.color.bg);
            vg = uigridlayout(vp, [1 4], 'Padding',[0 0 0 0], ...
                'ColumnSpacing', t.space.gapSm, 'BackgroundColor', t.color.bg);
            app.mkButton(vg, 'Single', @() app.noteToast('Single view'), t.color.panelAlt);
            app.mkButton(vg, '2x2 Compare', @() app.noteToast('2x2 compare: Phase 2 layout'), t.color.panelAlt);
            app.mkButton(vg, 'Reset View', @() app.WBHandles.canvas.reset(), t.color.panelAlt);
            app.mkButton(vg, 'Fit', @() app.WBHandles.canvas.reset(), t.color.panelAlt);

            % --- right: three stacked panels (scrollable so grade/lesion/xai
            % panels + action bar stay reachable on short windows) ---
            rpOuter = uipanel(g, 'BorderType','none', ...
                'BackgroundColor', t.color.bg, 'Scrollable','on');
            rp = uigridlayout(rpOuter, [4 1], ...
                'RowHeight', {260,260,260,'fit'}, ...
                'RowSpacing', t.space.gap, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.bg, 'Scrollable','on');

            app.buildWBGradingPanel(rp);
            app.buildWBLesionPanel(rp);
            app.buildWBXaiPanel(rp);
            app.buildWBActionBar(rp);   % row 4: Generate Report / Send / Auto-Clear / Next
        end

        function buildWBActionBar(app, parent)
            t = netra.ui.theme();
            p = uipanel(parent, 'BorderType','none','BackgroundColor', t.color.bg);
            g = uigridlayout(p, [1 4], 'Padding',[0 0 0 0], ...
                'ColumnSpacing', t.space.gapSm, 'BackgroundColor', t.color.bg);
            app.mkButton(g, 'Generate Report', @() app.noteToast('Report generation: Available in Phase 8'), t.color.panelAlt);
            app.mkButton(g, 'Send to Review Queue', @() app.onSendToQueue(), t.color.info);
            app.WBHandles.btnAutoClear = app.mkButton(g, 'Auto-Clear', @() app.onAutoClear(), t.color.pass);
            app.mkButton(g, 'Next Case', @() app.noteToast('Next case (mock).'), t.color.panelAlt);
        end

        function onSendToQueue(app)
            % The case is already persisted by the pipeline (runPipeline calls
            % store.save). This just confirms and jumps to the queue so the
            % clinician sees it - no separate "send" step is needed.
            if isempty(app.CurrentCase)
                uialert(app.Fig, 'No case loaded.', 'Nothing to send'); return;
            end
            dec = app.CurrentCase.routing.decision;
            if dec ~= "REVIEW_QUEUE"
                uialert(app.Fig, sprintf(['This case routed to %s, not the ' ...
                    'review queue. Only grade >=2 / low-confidence cases queue.'], dec), ...
                    'Not queued');
                return;
            end
            app.noteToast('Case is in the review queue (saved by the pipeline).');
            app.switchView("Review Queue");   % refreshes on entry
        end

        function onAutoClear(app)
            if isempty(app.CurrentCase) || app.CurrentCase.routing.decision ~= "AUTO_CLEARED"
                uialert(app.Fig, 'Auto-Clear is only enabled when routing decision is AUTO_CLEARED.', 'Not allowed');
                return;
            end
            app.noteToast('Case auto-cleared (mock).');
        end

        function buildWBGradingPanel(app, parent)
            t = netra.ui.theme();
            p = app.titledPanel(parent, 'Grading');
            g = uigridlayout(p.Grid, [1 2], 'ColumnWidth', {'fit','1x'}, ...
                'ColumnSpacing', t.space.gap, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.panel);
            % grade badge
            bp = uipanel(g, 'BorderType','none', 'BackgroundColor', t.color.panelAlt);
            bpg = uigridlayout(bp, [2 1], 'RowHeight', {'1x','fit'}, ...
                'Padding', t.space.gapSm*[1 1 1 1], 'BackgroundColor', t.color.panelAlt);
            app.WBHandles.gradeBadge = uilabel(bpg, 'Text','-', ...
                'FontName', t.font.family, 'FontSize', t.font.display, ...
                'FontWeight','bold', 'FontColor', t.color.textMuted, ...
                'HorizontalAlignment','center','VerticalAlignment','center');
            app.WBHandles.gradeLabel = uilabel(bpg, 'Text','Not graded', ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'FontColor', t.color.textMuted, 'HorizontalAlignment','center');
            % probability bars + confidence + rule row
            rg = uigridlayout(g, [3 1], 'RowHeight', {'1x','fit','fit'}, ...
                'Padding',[0 0 0 0], 'BackgroundColor', t.color.panel);
            app.WBHandles.axProbs = uiaxes(rg);
            app.styleAxes(app.WBHandles.axProbs);
            app.WBHandles.confPill = uilabel(rg, 'Text','Confidence: -', ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'FontColor', t.color.text);
            app.WBHandles.ruleRow = uilabel(rg, 'Text','Rule cross-check: -', ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'FontColor', t.color.textMuted);
        end

        function buildWBLesionPanel(app, parent)
            t = netra.ui.theme();
            p = app.titledPanel(parent, 'Lesion Evidence');
            g = uigridlayout(p.Grid, [2 1], 'RowHeight', {'1x','fit'}, ...
                'RowSpacing', t.space.gapSm, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.panel);
            app.WBHandles.lesionTbl = uitable(g, ...
                'ColumnName', {'Type','Count','Area %','Quadrants','Near macula'}, ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'BackgroundColor', [t.color.panelAlt; t.color.panel], ...
                'ForegroundColor', t.color.text, 'RowName', {}, ...
                'CellSelectionCallback', @(src,ev) app.onLesionRow(ev));
            % Live legend of per-class counts (Phase 6).
            app.WBHandles.lesionLegend = uilabel(g, 'Text', 'Legend: -', ...
                'FontName', t.font.family, 'FontSize', t.font.tiny, ...
                'FontColor', t.color.textMuted, 'WordWrap','on');
        end

        function buildWBXaiPanel(app, parent)
            t = netra.ui.theme();
            p = app.titledPanel(parent, 'Explainability');
            g = uigridlayout(p.Grid, [4 1], 'RowHeight', {'fit','fit','1x','fit'}, ...
                'RowSpacing', t.space.gapSm, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.panel);
            app.WBHandles.alaLabel = uilabel(g, 'Text','ALA: -', ...
                'FontName', t.font.family, 'FontSize', t.font.h2, ...
                'FontWeight','bold', 'FontColor', t.color.text);
            app.WBHandles.alaBar = netra.ui.subscoreBar(g, "Agreement", 0, ...
                app.Config.thresholds.xai.alaLowThreshold);
            app.WBHandles.evidence = uilabel(g, 'Text','Evidence: -', ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'FontColor', t.color.text, 'WordWrap','on', ...
                'VerticalAlignment','top');
            app.WBHandles.attn = uilabel(g, 'Text','', ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'FontColor', t.color.textMuted, 'WordWrap','on');
        end

        function populateWorkbench(app, cr, readOnly)
            t = netra.ui.theme();
            app.setCanvasBase(app.WBHandles.canvas, cr);
            app.addSyntheticOverlays(app.WBHandles.canvas, cr);

            % grading
            [lbl, c] = netra.ui.formatGrade(cr.grade.icdr);
            if isfinite(cr.grade.icdr)
                app.WBHandles.gradeBadge.Text = string(cr.grade.icdr);
            else
                app.WBHandles.gradeBadge.Text = '-';
            end
            app.WBHandles.gradeBadge.FontColor = c;
            app.WBHandles.gradeLabel.Text = lbl;
            app.WBHandles.gradeLabel.FontColor = c;

            ax = app.WBHandles.axProbs; cla(ax);
            if ~any(isnan(cr.grade.probs))
                b = bar(ax, 0:4, cr.grade.probs, 'FaceColor','flat');
                b.CData = [t.color.grade0;t.color.grade1;t.color.grade2;t.color.grade3;t.color.grade4];
                ax.XTick = 0:4;
            else
                app.emptyAxes(ax, 'No probabilities');
            end
            app.styleAxes(ax);

            % Provenance banner (Track B). Never render a non-REAL grade in the
            % same visual weight as a model output: state plainly what it is.
            gProv = string(cr.provenance.grading);
            if gProv == "RULE_BASED_NO_CNN"
                app.WBHandles.confPill.Text = ...
                    'Rule-based grading (no trained CNN available). Confidence n/a.';
                app.WBHandles.confPill.FontColor = t.color.warn;
            elseif gProv == "REAL"
                app.WBHandles.confPill.Text = sprintf('Confidence: %.0f%%   Band: %s', ...
                    100*nz(cr.grade.confidence), defaultStr(cr.xai.confidenceBand,'-'));
                app.WBHandles.confPill.FontColor = t.color.text;
            else
                app.WBHandles.confPill.Text = sprintf('Grading: %s', defaultStr(gProv,'-'));
                app.WBHandles.confPill.FontColor = t.color.textMuted;
            end
            % Rule cross-check: on path C there is no CNN to disagree with, so
            % show the rule estimate as the grade source, not a comparison.
            if gProv == "RULE_BASED_NO_CNN"
                app.WBHandles.ruleRow.Text = sprintf('Grade from 4-2-1 rule estimate: %s', ...
                    numOrDash(cr.grade.ruleEstimate));
            else
                app.WBHandles.ruleRow.Text = sprintf('Rule cross-check: rule=%s  CNN=%s  disagreement=%s', ...
                    numOrDash(cr.grade.ruleEstimate), numOrDash(cr.grade.icdr), ...
                    string(cr.grade.disagreement));
            end

            % lesions table + hover tooltip + live legend (Phase 6)
            app.WBHandles.lesionTbl.Data = app.lesionTableData(cr);
            app.WBHandles.lesionTbl.Tooltip = app.lesionTooltip(cr);
            if app.hasRealStructures(cr)
                app.updateLesionLegend(cr);
            elseif isfield(app.WBHandles,'lesionLegend') && ...
                    ~isempty(app.WBHandles.lesionLegend) && ...
                    isvalid(app.WBHandles.lesionLegend)
                app.WBHandles.lesionLegend.Text = 'Legend: (mock case)';
            end

            % xai - ALA. NaN means "no lesions to agree with", clinically
            % distinct from a low score; never render NaN as 0.00 (Track B).
            ala = cr.xai.agreementScore;
            alaLow = app.Config.thresholds.xai.alaLowThreshold;
            if isnan(ala)
                app.WBHandles.alaLabel.Text = 'ALA: n/a';
                app.WBHandles.alaLabel.FontColor = t.color.textMuted;
                app.WBHandles.attn.Text = "Attention-lesion agreement not applicable " + ...
                    "- no lesions detected (or no trained CNN).";
            else
                app.WBHandles.alaLabel.Text = sprintf('ALA: %.2f', ala);
                if ala < alaLow
                    app.WBHandles.alaLabel.FontColor = t.color.warn;   % poorly aligned
                else
                    app.WBHandles.alaLabel.FontColor = t.color.text;
                end
                app.WBHandles.alaBar.set(ala, alaLow);
            end
            if isempty(cr.xai.evidenceBullets)
                app.WBHandles.evidence.Text = 'Evidence: (none)';
            else
                bullets = "- " + cr.xai.evidenceBullets;
                app.WBHandles.evidence.Text = "Evidence:" + newline + strjoin(bullets, newline);
            end
            % attn is already set to the "not applicable" message when ALA is
            % NaN; otherwise show the stage's attention summary.
            if ~isnan(cr.xai.agreementScore)
                app.WBHandles.attn.Text = string(cr.xai.attentionSummary);
            end
        end

        function data = lesionTableData(app, cr)
            types = {'MA','HE','EX','CWS'};
            names = {'Microaneurysms','Haemorrhages','Hard exudates','Cotton wool spots'};
            data = cell(numel(types), 5);
            totalArea = 0;
            for k = 1:numel(types)
                totalArea = totalArea + cr.lesions.(types{k}).totalArea;
            end
            for k = 1:numel(types)
                L = cr.lesions.(types{k});
                areaPct = 0;
                if totalArea > 0, areaPct = 100*L.totalArea/totalArea; end
                quads = find(L.perQuadrant > 0);
                data{k,1} = names{k};
                data{k,2} = L.count;
                data{k,3} = sprintf('%.1f', areaPct);
                data{k,4} = char(strjoin(string(quads), ','));
                data{k,5} = ternStr(L.nearMacula > 0, 'yes','no');
            end
        end

        function tip = lesionTooltip(app, cr)
            % Per-lesion hover detail: type, area (px), quadrant, distance from
            % fovea in disc diameters. Lists up to the 8 largest lesions across
            % MA/HE/EX (real detections only). Empty -> a "no lesions" note.
            if ~app.hasRealStructures(cr)
                tip = 'Lesion detail available for analysed (real) cases.';
                return;
            end
            S = cr.structures;
            fov = S.foveaCenter; dd = 2*max(S.odRadius, 1);   % disc diameter px
            qnames = {'S-N','S-T','I-N','I-T'};
            rows = {};   % {area, text}
            types = {'MA','HE','EX'};
            for ti = 1:numel(types)
                L = cr.lesions.(types{ti});
                for j = 1:size(L.centroids,1)
                    c = L.centroids(j,:);
                    a = L.areas(j);
                    q = 0;
                    if ~isempty(S.quadrantMap)
                        cy = min(size(S.quadrantMap,1), max(1, round(c(2))));
                        cx = min(size(S.quadrantMap,2), max(1, round(c(1))));
                        q = double(S.quadrantMap(cy, cx));
                    end
                    qn = '-'; if q>=1 && q<=4, qn = qnames{q}; end
                    distDD = hypot(c(1)-fov(1), c(2)-fov(2)) / dd;
                    txt = sprintf('%s  area %d px  quad %s  %.1f DD from fovea', ...
                        types{ti}, round(a), qn, distDD);
                    rows(end+1,:) = {a, txt}; %#ok<AGROW>
                end
            end
            if isempty(rows)
                tip = 'No lesions detected (normal retina).';
                return;
            end
            [~, ord] = sort(cell2mat(rows(:,1)), 'descend');
            take = ord(1:min(8, numel(ord)));
            lines = rows(take, 2);
            tip = strjoin(["Largest lesions (hover):"; string(lines)], newline);
        end

        function onOverlayToggle(app, key, val)
            app.wrap(@() localToggle());
            function localToggle()
                if strcmp(key,'Original')
                    % Original = hide all overlays
                    fn = fieldnames(app.WBHandles.chk);
                    for i = 1:numel(fn)
                        if ~strcmp(fn{i},'Original')
                            app.WBHandles.chk.(fn{i}).Value = false;
                            app.WBHandles.canvas.setLayerVisible(fn{i}, false);
                        end
                    end
                    app.WBHandles.canvas.setLayerVisible('Fovea', false);
                    return;
                end
                app.WBHandles.canvas.setLayerVisible(key, val);
                % The OD ring and fovea crosshair are separate layers driven by
                % one 'Disc & Fovea' checkbox (Phase 5 real overlays).
                if strcmp(key,'ODFovea')
                    app.WBHandles.canvas.setLayerVisible('Fovea', val);
                end
            end
        end

        function onGradcamOpacity(app, val)
            app.WBHandles.canvas.setOpacity('GradCAM', val);
        end

        function onLesionRow(app, ev)
            app.wrap(@() localRow());
            function localRow()
                if isempty(ev.Indices), return; end
                keys = {'MA','HE','EX','CWS'};
                row = ev.Indices(1);
                if row < 1 || row > 4, return; end
                % Solo that lesion class: dim every overlay except this class's
                % real per-class layer (Phase 6). Falls back to the combined
                % 'Lesions' layer for mock cases that have no per-class layers.
                cls = keys{row};
                if app.hasRealStructures(app.CurrentCase)
                    app.WBHandles.canvas.setLayerVisible(['Lesion_' cls], true);
                    app.WBHandles.canvas.soloLesion(['Lesion_' cls]);
                else
                    app.WBHandles.canvas.soloLesion('Lesions');
                end
                app.noteToast(sprintf('Focused lesion class: %s', cls));
            end
        end
    end

    % ====================================================================
    %  VIEW 5 - REVIEW QUEUE
    % ====================================================================
    methods (Access = private)
        function buildReviewQueue(app)
            t = netra.ui.theme();
            root = app.Views.(app.key("Review Queue"));

            g = uigridlayout(root, [3 1], 'RowHeight', {'fit','fit','1x'}, ...
                'RowSpacing', t.space.gap, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.bg);

            % stat strip
            sp = uigridlayout(g, [1 4], 'Padding',[0 0 0 0], ...
                'ColumnSpacing', t.space.gap, 'BackgroundColor', t.color.bg);
            sp.Layout.Row = 1;
            app.RQHandles.kInQueue = netra.ui.kpiCard(sp, "In Queue", 0, "");
            app.RQHandles.kUrgent  = netra.ui.kpiCard(sp, "Urgent", 0, "", struct('accent', t.color.reject));
            app.RQHandles.kEst      = netra.ui.kpiCard(sp, "Est. Review Time", 0, "min");
            app.RQHandles.kCleared = netra.ui.kpiCard(sp, "Auto-Cleared Today", 0, "");

            % filter chips + buttons
            fp = uigridlayout(g, [1 8], 'Padding',[0 0 0 0], ...
                'ColumnSpacing', t.space.gapSm, 'BackgroundColor', t.color.bg);
            fp.Layout.Row = 2;
            chips = {'All','Urgent','Priority','Routine','Uncertain-flagged'};
            for k = 1:numel(chips)
                app.mkButton(fp, chips{k}, @() app.onQueueFilter(chips{k}), t.color.panelAlt);
            end
            app.mkButton(fp, 'Review Next', @() app.onReviewNext(), t.color.info);
            app.mkButton(fp, 'Open Selected', @() app.onOpenSelected(), t.color.panelAlt);
            app.mkButton(fp, 'Refresh', @() app.refreshQueue("All"), t.color.panelAlt);

            % table + agreement mini chart
            bp = uigridlayout(g, [1 2], 'ColumnWidth', {'3x','1x'}, ...
                'ColumnSpacing', t.space.gap, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.bg);
            bp.Layout.Row = 3;
            tp = app.titledPanel(bp, 'Queue');
            app.RQHandles.tbl = uitable(tp.Grid, ...
                'ColumnName', {'UID','Age','AI Grade','Confidence','Urgency','Flags','Waiting'}, ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'BackgroundColor', [t.color.panelAlt; t.color.panel], ...
                'ForegroundColor', t.color.text, 'RowName', {}, ...
                'CellSelectionCallback', @(src,ev) app.onQueueSelect(ev));
            ap = app.titledPanel(bp, 'AI vs Reviewer');
            app.RQHandles.axAgree = uiaxes(ap.Grid);
            app.styleAxes(app.RQHandles.axAgree);

            app.refreshQueue("All");
        end

        function refreshQueue(app, filterName)
            app.wrap(@() localRefresh());
            function localRefresh()
                spec = struct();
                switch filterName
                    case {'Urgent','Priority','Routine'}
                        spec.urgency = string(filterName);
                    case 'Uncertain-flagged'
                        spec.flagged = true;
                    otherwise
                        % All
                end
                Q = netra.store.queryQueue(app.Config, spec);
                app.QueueTable = Q;

                % stats
                stURgent = sum(Q.urgency == "Urgent");
                app.RQHandles.kInQueue.set(height(Q));
                app.RQHandles.kUrgent.set(stURgent);
                % Estimated total review time: measured median per case when we
                % have audit data, else the 30s planning assumption.
                a = app.safeAudit();
                perCase = 30;
                if isfinite(a.medianReviewSeconds) && a.medianReviewSeconds > 0
                    perCase = a.medianReviewSeconds;
                end
                app.RQHandles.kEst.set(round(height(Q)*perCase/60));   % minutes
                st = app.safeStats();
                clearedPct = 0;
                denom = st.autoCleared + st.referred;
                if denom > 0, clearedPct = round(100*st.autoCleared/denom); end
                app.RQHandles.kCleared.set(st.autoCleared, ...
                    sprintf('%d%% of routed', clearedPct));

                app.RQHandles.tbl.Data = app.queueTableData(Q);
                app.drawAgreementChart();
            end
        end

        function data = queueTableData(~, Q)
            if isempty(Q), data = {}; return; end
            % Per-row confidence formatting: compose gives an N x1 string,
            % so every column below is N x1 and the concat is well-formed.
            conf = cellstr(compose('%.2f', Q.confidence));
            data = [cellstr(Q.uid), cellstr(string(Q.age)), ...
                    cellstr(string(Q.icdr)), conf, ...
                    cellstr(Q.urgency), cellstr(Q.flags), ...
                    cellstr(string(Q.timestamp,'HH:mm'))];
        end

        function drawAgreementChart(app)
            t = netra.ui.theme();
            ax = app.RQHandles.axAgree; cla(ax);
            T = app.safeRegistry();
            if isempty(T)
                app.emptyAxes(ax, 'No data'); app.styleAxes(ax); return;
            end
            agreed = sum(T.reviewerAgreed == "Agreed");
            overr  = sum(T.reviewerAgreed == "Overridden");
            if agreed + overr == 0
                app.emptyAxes(ax, 'No reviews yet');
            else
                b = bar(ax, categorical({'Agreed','Overridden'}), [agreed overr], 'FaceColor','flat');
                b.CData = [t.color.pass; t.color.warn];
            end
            app.styleAxes(ax);
        end

        function onQueueFilter(app, name)
            app.refreshQueue(string(name));
        end

        function onQueueSelect(app, ev)
            if ~isempty(ev.Indices)
                app.RQHandles.tbl.UserData = ev.Indices(1);
            end
        end

        function onOpenSelected(app)
            app.wrap(@() localOpen());
            function localOpen()
                row = app.RQHandles.tbl.UserData;
                if isempty(row) || isempty(app.QueueTable) || row > height(app.QueueTable)
                    uialert(app.Fig, 'Select a queue row first.', 'No selection'); return;
                end
                app.openCaseReview(app.QueueTable(row,:), false);
            end
        end

        function onReviewNext(app)
            app.wrap(@() localNext());
            function localNext()
                if isempty(app.QueueTable) || height(app.QueueTable) == 0
                    uialert(app.Fig, 'Queue is empty.', 'Nothing to review'); return;
                end
                app.openCaseReview(app.QueueTable(1,:), true);
            end
        end
    end

    % ====================================================================
    %  VIEW 6 - CASE REVIEW
    % ====================================================================
    methods (Access = private)
        function buildCaseReview(app)
            t = netra.ui.theme();
            root = app.Views.(app.key("Case Review"));

            g = uigridlayout(root, [2 2], 'RowHeight', {'fit','1x'}, ...
                'ColumnWidth', {'1.3x','1x'}, 'RowSpacing', t.space.gap, ...
                'ColumnSpacing', t.space.gapLg, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.bg);

            % header: uid + stopwatch
            hp = uipanel(g, 'BorderType','none','BackgroundColor', t.color.panel);
            hp.Layout.Row = 1; hp.Layout.Column = [1 2];
            hg = uigridlayout(hp, [1 2], 'ColumnWidth', {'1x','fit'}, ...
                'Padding', t.space.pad*[1 1 1 1], 'BackgroundColor', t.color.panel);
            app.CRHandles.uidLabel = uilabel(hg, 'Text','Case: -', ...
                'FontName', t.font.family, 'FontSize', t.font.h2, ...
                'FontWeight','bold','FontColor', t.color.text, ...
                'VerticalAlignment','center');
            app.CRHandles.stopwatch = uilabel(hg, 'Text','0.0 s', ...
                'FontName', t.font.mono, 'FontSize', t.font.display, ...
                'FontWeight','bold','FontColor', t.color.pass, ...
                'HorizontalAlignment','right','VerticalAlignment','center');

            % 2x2 image grid (placeholders)
            ip = app.titledPanel(g, 'Images');
            ip.Panel.Layout.Row = 2; ip.Panel.Layout.Column = 1;
            ig = uigridlayout(ip.Grid, [2 2], 'RowSpacing', t.space.gapSm, ...
                'ColumnSpacing', t.space.gapSm, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.panel);
            titles = {'Enhanced','Lesion overlay','Grad-CAM','Zoomed macula'};
            app.CRHandles.canvas = cell(1,4);
            for k = 1:4
                sp = uipanel(ig, 'Title', titles{k}, ...
                    'ForegroundColor', t.color.textMuted, ...
                    'BackgroundColor', t.color.panel, ...
                    'FontName', t.font.family, 'FontSize', t.font.tiny, ...
                    'HighlightColor', t.color.border);
                spg = uigridlayout(sp, [1 1], 'Padding',[2 2 2 2], ...
                    'BackgroundColor', t.color.panel);
                app.CRHandles.canvas{k} = netra.ui.imageCanvas(spg);
            end

            % right: evidence + actions
            rp = uigridlayout(g, [2 1], 'RowHeight', {'1x','fit'}, ...
                'RowSpacing', t.space.gap, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.bg);
            rp.Layout.Row = 2; rp.Layout.Column = 2;

            ep = app.titledPanel(rp, 'Evidence');
            eg = uigridlayout(ep.Grid, [6 1], 'RowHeight', repmat({'fit'},1,6), ...
                'RowSpacing', t.space.gapSm, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.panel);
            app.CRHandles.gradeBadge = uilabel(eg, 'Text','Grade: -', ...
                'FontName', t.font.family, 'FontSize', t.font.h2, ...
                'FontWeight','bold', 'FontColor', t.color.textMuted);
            app.CRHandles.conf = uilabel(eg, 'Text','Confidence: -', ...
                'FontName', t.font.family, 'FontSize', t.font.body, 'FontColor', t.color.text);
            app.CRHandles.ala = uilabel(eg, 'Text','ALA: -', ...
                'FontName', t.font.family, 'FontSize', t.font.body, 'FontColor', t.color.text);
            app.CRHandles.evidence = uilabel(eg, 'Text','Evidence: -', ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'FontColor', t.color.text, 'WordWrap','on');
            app.CRHandles.history = uilabel(eg, 'Text','Prior history: none', ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'FontColor', t.color.textMuted, 'WordWrap','on');
            app.CRHandles.note = uieditfield(eg, 'text', ...
                'Placeholder','Optional note...', ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'BackgroundColor', t.color.panelAlt, 'FontColor', t.color.text);

            % action buttons
            ap = uipanel(rp, 'BorderType','none','BackgroundColor', t.color.bg);
            abg = uigridlayout(ap, [2 2], 'RowSpacing', t.space.gapSm, ...
                'ColumnSpacing', t.space.gapSm, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.bg);
            app.mkButton(abg, 'Confirm AI Grade', @() app.onReviewAction("Confirm"), t.color.pass);
            app.mkButton(abg, 'Override (0-4)', @() app.onReviewOverride(), t.color.warn);
            app.mkButton(abg, 'Mark Ungradeable', @() app.onReviewAction("Ungradeable"), t.color.reject);
            app.mkButton(abg, 'Skip', @() app.onReviewAction("Skip"), t.color.panelAlt);
        end

        function openCaseReview(app, row, startTimer)
            app.wrap(@() localOpen());
            function localOpen()
                cr = app.mockCaseFromRow(row);
                app.CurrentCase = cr;
                app.ReviewingUid = string(cr.meta.uid);   % which queue row is on screen
                app.CRHandles.uidLabel.Text = "Case: " + cr.meta.uid;

                for k = 1:4
                    app.setCanvasBase(app.CRHandles.canvas{k}, cr);
                end
                app.addSyntheticOverlays(app.CRHandles.canvas{2}, cr);
                app.CRHandles.canvas{2}.setLayerVisible('Lesions', true);
                app.addSyntheticOverlays(app.CRHandles.canvas{3}, cr);
                app.CRHandles.canvas{3}.setLayerVisible('GradCAM', true);

                [lbl, c] = netra.ui.formatGrade(cr.grade.icdr);
                app.CRHandles.gradeBadge.Text = sprintf('Grade %s - %s', ...
                    numOrDash(cr.grade.icdr), lbl);
                app.CRHandles.gradeBadge.FontColor = c;
                app.CRHandles.conf.Text = sprintf('Confidence: %.0f%%', 100*nz(cr.grade.confidence));
                app.CRHandles.ala.Text = sprintf('ALA: %.2f', nz(cr.xai.agreementScore));
                if isempty(cr.xai.evidenceBullets)
                    app.CRHandles.evidence.Text = 'Evidence: (none)';
                else
                    app.CRHandles.evidence.Text = "Evidence: " + strjoin(cr.xai.evidenceBullets, "; ");
                end
                app.CRHandles.history.Text = app.priorHistoryText(cr.meta.patientID);
                app.CRHandles.note.Value = '';

                app.switchView("Case Review");
                if startTimer, app.startReviewTimer(); end
            end
        end

        function txt = priorHistoryText(app, patientID)
            T = app.safeRegistry();
            txt = 'Prior history: none';
            if isempty(T), return; end
            prior = T(T.patientID == string(patientID), :);
            if height(prior) > 1
                txt = sprintf('Prior history: %d earlier case(s) on record.', height(prior)-1);
            end
        end

        function onReviewOverride(app)
            app.wrap(@() localOv());
            function localOv()
                answer = uiconfirm(app.Fig, 'Select corrected ICDR grade:', ...
                    'Override grade', 'Options', {'0','1','2','3','4'}, ...
                    'DefaultOption', 1);
                app.finishReview("Override", str2double(answer));
            end
        end

        function onReviewAction(app, action)
            app.wrap(@() localAct());
            function localAct()
                switch action
                    case "Confirm"
                        fg = NaN;
                        if ~isempty(app.CurrentCase), fg = app.CurrentCase.grade.icdr; end
                        app.finishReview(action, fg);
                    case "Ungradeable"
                        app.finishReview(action, NaN);
                    case "Skip"
                        app.finishReview(action, NaN);
                end
            end
        end

        function finishReview(app, action, finalGrade)
            secs = app.stopReviewTimer();
            note = '';
            uid = '';
            if ~isempty(app.CurrentCase)
                app.CurrentCase.review.action = string(action);
                app.CurrentCase.review.finalGrade = finalGrade;
                app.CurrentCase.review.reviewerID = app.ReviewerID;
                app.CurrentCase.review.seconds = secs;
                app.CurrentCase.review.timestamp = datetime('now');
                uid = char(app.CurrentCase.meta.uid);
                if isfield(app.CRHandles,'note') && isvalid(app.CRHandles.note)
                    note = char(app.CRHandles.note.Value);
                end
            end
            % Persist the decision to the registry (and the case.mat if stored).
            % A logging failure must not block the reviewer's flow, so wrap it.
            if ~isempty(uid)
                try
                    netra.store.logReview(uid, char(action), finalGrade, ...
                        char(app.ReviewerID), secs, note, app.Config);
                catch ME
                    fprintf(2, 'logReview failed for %s: %s\n', uid, ME.message);
                end
            end
            % advance queue: remove the case we actually reviewed (by uid, not a
            % fixed row 1 - the reviewer may have opened any selected row).
            remaining = 0;
            if ~isempty(app.QueueTable) && height(app.QueueTable) > 0
                if strlength(app.ReviewingUid) > 0
                    app.QueueTable(string(app.QueueTable.uid) == app.ReviewingUid, :) = [];
                else
                    app.QueueTable(1,:) = [];           % fallback: front of queue
                end
                remaining = height(app.QueueTable);
            end
            app.noteToast(sprintf('Reviewed in %.0fs. %d remaining', secs, remaining));
            if remaining > 0
                app.openCaseReview(app.QueueTable(1,:), true);
            else
                app.stopReviewTimer();
                app.switchView("Review Queue");
                app.refreshQueue("All");
            end
        end
    end

    % ====================================================================
    %  VIEW 7 - VALIDATION & CAPACITY (empty states)
    % ====================================================================
    methods (Access = private)
        function buildValidationAndCapacity(app)
            t = netra.ui.theme();
            root = app.Views.(app.key("Validation & Capacity"));

            tg = uitabgroup(root);
            tg.Units = 'normalized'; tg.Position = [0 0 1 1];

            tab1 = uitab(tg, 'Title','Validation Report', ...
                'BackgroundColor', t.color.bg, 'ForegroundColor', t.color.text);
            app.emptyStatePanel(tab1, 'Populated in Phase 10', ...
                {'Intended: ROC curve (per grade)', ...
                 'Intended: Confusion matrix', ...
                 'Intended: Sensitivity / Specificity table', ...
                 'Intended: Agreement (kappa) vs clinicians'});

            tab2 = uitab(tg, 'Title','Capacity Planner', ...
                'BackgroundColor', t.color.bg, 'ForegroundColor', t.color.text);
            app.buildCapacityPlanner(tab2);
        end

        function emptyStatePanel(app, parent, phaseMsg, axisTitles)
            t = netra.ui.theme();
            g = uigridlayout(parent, [3 1], 'RowHeight', {'1x','fit','1x'}, ...
                'Padding', t.space.pad*[1 1 1 1], 'BackgroundColor', t.color.bg);
            box = uipanel(g, 'BorderType','line', 'BackgroundColor', t.color.panel, ...
                'HighlightColor', t.color.border);
            box.Layout.Row = 2;
            bg = uigridlayout(box, [numel(axisTitles)+1 1], ...
                'Padding', t.space.pad*[1 1 1 1], 'RowSpacing', t.space.gapSm, ...
                'BackgroundColor', t.color.panel);
            uilabel(bg, 'Text', phaseMsg, ...
                'FontName', t.font.family, 'FontSize', t.font.h2, ...
                'FontWeight','bold', 'FontColor', t.color.warn, ...
                'HorizontalAlignment','center');
            for k = 1:numel(axisTitles)
                uilabel(bg, 'Text', ['   - ' axisTitles{k}], ...
                    'FontName', t.font.family, 'FontSize', t.font.body, ...
                    'FontColor', t.color.textMuted);
            end
        end

        % ---------------- CAPACITY PLANNER ------------------------------
        function buildCapacityPlanner(app, parent)
            t = netra.ui.theme();
            g = uigridlayout(parent, [1 2], 'ColumnWidth', {320, '1x'}, ...
                'ColumnSpacing', t.space.gap, 'Padding', t.space.pad*[1 1 1 1], ...
                'BackgroundColor', t.color.bg);

            % ---- left: parameter form ----
            lp = app.titledPanel(g, 'Parameters (measured / assumed)');
            names = netra.sim.paramNames();
            fg = uigridlayout(lp.Grid, [numel(names)+5 2], ...
                'ColumnWidth', {'1.4x','1x'}, 'RowHeight', ...
                [repmat({'fit'},1,numel(names)), {'fit','fit','fit','fit','fit'}], ...
                'RowSpacing', 2, 'Padding',[0 0 0 0], 'BackgroundColor', t.color.panel);

            p0 = app.defaultSimParams();     % seeds fields + measured/assumed flags
            app.CPHandles.fields = struct();
            app.CPHandles.srcLabels = struct();
            for k = 1:numel(names)
                nm = names{k};
                src = p0.([nm '_src']);
                lbl = uilabel(fg, 'Text', app.simLabel(nm, src), ...
                    'FontName', t.font.family, 'FontSize', t.font.tiny, ...
                    'FontColor', app.srcColor(src), 'WordWrap','on');
                lbl.Layout.Row = k; lbl.Layout.Column = 1;
                ef = uieditfield(fg, 'numeric', 'Value', p0.(nm), ...
                    'FontName', t.font.family, 'FontSize', t.font.small, ...
                    'BackgroundColor', t.color.panelAlt, 'FontColor', t.color.text);
                ef.Layout.Row = k; ef.Layout.Column = 2;
                app.CPHandles.fields.(nm) = ef;
                app.CPHandles.srcLabels.(nm) = lbl;
            end

            % scenario preset buttons
            rowRun = numel(names)+1;
            sb = uigridlayout(fg, [1 3], 'Padding',[0 4 0 4], ...
                'ColumnSpacing', 4, 'BackgroundColor', t.color.panel);
            sb.Layout.Row = rowRun; sb.Layout.Column = [1 2];
            app.mkButton(sb, 'S1 Baseline', @() app.onScenario(1), t.color.panelAlt);
            app.mkButton(sb, 'S2 Auto-clear', @() app.onScenario(2), t.color.panelAlt);
            app.mkButton(sb, 'S3 +Staffing', @() app.onScenario(3), t.color.panelAlt);

            rb = uibutton(fg, 'Text', 'Run Simulation', ...
                'FontName', t.font.family, 'FontSize', t.font.body, ...
                'FontWeight','bold', 'FontColor', t.color.text, ...
                'BackgroundColor', t.color.info, ...
                'ButtonPushedFcn', @(~,~) app.wrap(@() app.onRunCapacity()));
            rb.Layout.Row = rowRun+1; rb.Layout.Column = [1 2];

            ob = uibutton(fg, 'Text', 'Open Model in Simulink', ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'FontColor', t.color.text, 'BackgroundColor', t.color.panelAlt, ...
                'ButtonPushedFcn', @(~,~) app.wrap(@() app.onOpenModel()));
            ob.Layout.Row = rowRun+2; ob.Layout.Column = [1 2];

            app.CPHandles.backend = uilabel(fg, 'Text', 'Backend: (not run)', ...
                'FontName', t.font.family, 'FontSize', t.font.tiny, ...
                'FontColor', t.color.textMuted, 'WordWrap','on');
            app.CPHandles.backend.Layout.Row = rowRun+3;
            app.CPHandles.backend.Layout.Column = [1 2];

            % ---- right: charts + KPIs + recommendation ----
            rp = uigridlayout(g, [3 1], 'RowHeight', {'fit','1x','fit'}, ...
                'RowSpacing', t.space.gap, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.bg);
            rp.Layout.Column = 2;

            % recommendation banner
            recPanel = uipanel(rp, 'BorderType','line', ...
                'BackgroundColor', t.color.panelAlt, 'HighlightColor', t.color.border);
            recPanel.Layout.Row = 1;
            rg = uigridlayout(recPanel, [1 1], 'Padding', t.space.pad*[1 1 1 1], ...
                'BackgroundColor', t.color.panelAlt);
            app.CPHandles.rec = uilabel(rg, ...
                'Text','Run a simulation to generate a staffing recommendation.', ...
                'FontName', t.font.family, 'FontSize', t.font.body, ...
                'FontColor', t.color.text, 'WordWrap','on');

            % charts (3 stacked)
            cp = uigridlayout(rp, [1 3], 'ColumnSpacing', t.space.gap, ...
                'Padding',[0 0 0 0], 'BackgroundColor', t.color.bg);
            cp.Layout.Row = 2;
            app.CPHandles.axQueue = app.mkAxesPanel(cp, 'Queue depth (hero)');
            app.CPHandles.axCum   = app.mkAxesPanel(cp, 'Arrived vs cleared');
            app.CPHandles.axUtil  = app.mkAxesPanel(cp, 'Reviewer utilisation');

            % KPI cards
            kp = uigridlayout(rp, [1 5], 'ColumnSpacing', t.space.gapSm, ...
                'Padding',[0 0 0 0], 'BackgroundColor', t.color.bg);
            kp.Layout.Row = 3;
            app.CPHandles.kThru = netra.ui.kpiCard(kp, "Throughput", 0, "/day");
            app.CPHandles.kWait = netra.ui.kpiCard(kp, "p95 Wait", 0, "d");
            app.CPHandles.kPeak = netra.ui.kpiCard(kp, "Peak Backlog", 0, "");
            app.CPHandles.kUtil = netra.ui.kpiCard(kp, "Utilisation", 0, "%");
            app.CPHandles.kClear = netra.ui.kpiCard(kp, "Auto-Cleared", 0, "%");
        end

        function p = defaultSimParams(app)
            simDir = fullfile(char(app.Root), 'simulink');
            if exist('default_params','file') ~= 2, addpath(simDir); end
            p = default_params(app.Config);
        end

        function s = simLabel(~, nm, src)
            s = sprintf('%s [%s]', nm, upper(char(src)));
        end

        function c = srcColor(app, src)
            t = netra.ui.theme();
            if string(src) == "measured", c = t.color.pass; else, c = t.color.warn; end
        end

        function ui = readSimForm(app)
            names = netra.sim.paramNames();
            ui = struct();
            for k = 1:numel(names)
                ui.(names{k}) = app.CPHandles.fields.(names{k}).Value;
            end
        end

        function writeSimForm(app, p)
            names = netra.sim.paramNames();
            for k = 1:numel(names)
                nm = names{k};
                app.CPHandles.fields.(nm).Value = p.(nm);
                if isfield(p, [nm '_src'])
                    src = p.([nm '_src']);
                    app.CPHandles.srcLabels.(nm).Text = app.simLabel(nm, src);
                    app.CPHandles.srcLabels.(nm).FontColor = app.srcColor(src);
                end
            end
        end

        function onScenario(app, idx)
            app.wrap(@() localScen());
            function localScen()
                simDir = fullfile(char(app.Root), 'simulink');
                if exist('scenarios','file') ~= 2, addpath(simDir); end
                sc = scenarios(app.Config);
                app.writeSimForm(sc(idx).params);
                app.onRunCapacity();
            end
        end

        function onRunCapacity(app)
            ui = app.readSimForm();
            latency = netra.util.latencyStats(app.Config);
            p = netra.sim.buildParams(ui, latency, app.Config);
            app.writeSimForm(p);                 % reflect measured/assumed flags

            out = netra.sim.runCapacity(p);
            app.LastSimOut = out;

            netra.sim.plotResults(out, {app.CPHandles.axQueue, ...
                app.CPHandles.axCum, app.CPHandles.axUtil});
            for ax = [app.CPHandles.axQueue, app.CPHandles.axCum, app.CPHandles.axUtil]
                app.styleAxes(ax);
            end

            s = out.signals;
            thru = mean(s.reviewedCount + s.autoClearedCount);
            app.CPHandles.kThru.set(round(thru));
            app.CPHandles.kWait.set(round(s.p95WaitDays,1));
            app.CPHandles.kPeak.set(round(max(s.reviewQueueDepth)));
            app.CPHandles.kUtil.set(round(100*mean(s.reviewerUtilisation)));
            clr = 0; tot = sum(s.autoClearedCount)+sum(s.reviewedCount);
            if tot>0, clr = round(100*sum(s.autoClearedCount)/tot); end
            app.CPHandles.kClear.set(clr);

            app.CPHandles.rec.Text = netra.sim.recommendation(out, p);
            if out.source == "matlab_numerical"
                app.CPHandles.backend.Text = sprintf( ...
                    'Backend: MATLAB numerical model (Simulink unavailable). Runtime %.2fs.', ...
                    out.runtimeSeconds);
                app.CPHandles.backend.FontColor = netra.ui.theme().color.warn;
            else
                app.CPHandles.backend.Text = sprintf( ...
                    'Backend: Simulink (netra_capacity.slx). Runtime %.2fs.', ...
                    out.runtimeSeconds);
                app.CPHandles.backend.FontColor = netra.ui.theme().color.pass;
            end
        end

        function onOpenModel(app)
            simDir = fullfile(char(app.Root), 'simulink');
            slx = fullfile(simDir, 'netra_capacity.slx');
            if exist('open_system','file') == 0 || license('test','Simulink') ~= 1
                uialert(app.Fig, sprintf(['Simulink is required to open the ' ...
                    'model.\nModel file: %s'], slx), 'Simulink unavailable');
                return;
            end
            addpath(simDir);
            if ~isfile(slx), build_netra_capacity(slx); end
            open_system(slx);
        end
    end

    % ====================================================================
    %  NAV / MODE / VIEW SWITCHING
    % ====================================================================
    methods (Access = private)
        function onNav(app, name)
            app.wrap(@() app.switchView(name));
        end

        function switchView(app, name)
            % Enforce mode visibility: block hidden views.
            allowed = app.viewsForMode();
            if ~ismember(name, allowed)
                return;
            end
            fn = fieldnames(app.Views);
            for k = 1:numel(fn)
                app.Views.(fn{k}).Visible = 'off';
            end
            app.Views.(app.key(name)).Visible = 'on';
            app.ActiveView = name;

            % highlight nav
            t = netra.ui.theme();
            nb = fieldnames(app.NavButtons);
            for k = 1:numel(nb)
                app.NavButtons.(nb{k}).BackgroundColor = t.color.navBg;
            end
            app.NavButtons.(app.key(name)).BackgroundColor = t.color.navSel;

            % Leaving Case Review stops the stopwatch.
            if name ~= "Case Review"
                app.stopReviewTimer();
            end

            % Refresh data-driven views on entry so they reflect the current
            % registry (nav alone never re-queried them -> "queue not updating").
            switch name
                case "Review Queue"
                    app.refreshQueue("All");
                case "Dashboard"
                    app.refreshDashboard();
            end
        end

        function onModeChanged(app, val)
            app.Mode = string(val);
            app.applyMode();
            % If current view not allowed in new mode, go to Dashboard.
            if ~ismember(app.ActiveView, app.viewsForMode())
                app.switchView("Dashboard");
            end
        end

        function applyMode(app)
            % Show/hide nav buttons per persona AND collapse the grid rows of
            % hidden buttons to 0 height. A uigridlayout row keeps its height
            % when its child is Visible='off', so hidden views otherwise leave a
            % blank gap in the rail (e.g. between Workbench and Validation in
            % Field mode). Collapsing the row removes the gap.
            t = netra.ui.theme();
            allowed = app.viewsForMode();
            rowH = app.NavGrid.RowHeight;                 % row 1 = title, last = '1x'
            for k = 1:numel(app.NavOrder)
                nm = app.NavOrder(k);
                shown = ismember(nm, allowed);
                app.NavButtons.(app.key(nm)).Visible = ...
                    matlab.lang.OnOffSwitchState(shown);
                if shown
                    rowH{k+1} = t.size.buttonHeight + 8;   % normal height
                else
                    rowH{k+1} = 0;                         % collapse the gap
                end
            end
            app.NavGrid.RowHeight = rowH;
        end

        function v = viewsForMode(app)
            if app.Mode == "Clinician"
                v = app.ClinicianViews;
            else
                v = app.FieldViews;
            end
        end
    end

    % ====================================================================
    %  REVIEW TIMER
    % ====================================================================
    methods (Access = private)
        function startReviewTimer(app)
            app.stopReviewTimer();
            app.ReviewStart = datetime('now');
            app.ReviewTimer = timer( ...
                'ExecutionMode','fixedRate', 'Period', 0.1, ...
                'BusyMode','drop', ...
                'TimerFcn', @(~,~) app.tickReviewTimer());
            start(app.ReviewTimer);
        end

        function tickReviewTimer(app)
            if isempty(app.ReviewStart) || isempty(app.CRHandles) ...
                    || ~isfield(app.CRHandles,'stopwatch') ...
                    || ~isvalid(app.CRHandles.stopwatch)
                return;
            end
            t = netra.ui.theme();
            secs = seconds(datetime('now') - app.ReviewStart);
            app.CRHandles.stopwatch.Text = sprintf('%.1f s', secs);
            if secs >= 30
                app.CRHandles.stopwatch.FontColor = t.color.warn;
            else
                app.CRHandles.stopwatch.FontColor = t.color.pass;
            end
        end

        function secs = stopReviewTimer(app)
            secs = 0;
            if ~isempty(app.ReviewStart)
                secs = seconds(datetime('now') - app.ReviewStart);
            end
            if ~isempty(app.ReviewTimer) && isa(app.ReviewTimer,'timer') ...
                    && isvalid(app.ReviewTimer)
                stop(app.ReviewTimer);
                delete(app.ReviewTimer);
            end
            app.ReviewTimer = [];
            app.ReviewStart = [];
        end
    end

    % ====================================================================
    %  SHARED HELPERS
    % ====================================================================
    methods (Access = private)
        function onExportSummary(app)
            app.wrap(@() localExport());
            function localExport()
                T = app.safeRegistry();
                if isempty(T)
                    uialert(app.Fig, 'No cases to export.', 'Export'); return;
                end
                outDir = fullfile(app.Root, 'data', 'exports');
                if ~isfolder(outDir), mkdir(outDir); end
                fname = fullfile(outDir, 'camp_summary.csv');
                writetable(T, fname);
                uialert(app.Fig, sprintf('Exported %d cases to:\n%s', ...
                    height(T), fname), 'Export complete', 'Icon','success');
            end
        end

        function onBatchImport(app)
            app.wrap(@() localBatch());
            function localBatch()
                folder = uigetdir('', 'Select a folder of fundus images');
                if isequal(folder, 0), return; end

                % Shared metadata dialog: phcID + eye handling.
                phcOpts = app.phcItems();
                defPhc = phcOpts{1};
                eyeMode = uiconfirm(app.Fig, ...
                    sprintf(['Batch import from:\n%s\n\nEye handling for this ' ...
                    'batch? (PHC: %s)'], folder, app.phcIdFromLabel(defPhc)), ...
                    'Batch metadata', ...
                    'Options', {'All OD','All OS','Alternate OD/OS','Cancel'}, ...
                    'DefaultOption', 1, 'CancelOption', 4);
                if strcmp(eyeMode, 'Cancel'), return; end
                switch eyeMode
                    case 'All OD', eyeVal = "OD";
                    case 'All OS', eyeVal = "OS";
                    otherwise,     eyeVal = "alternate";
                end

                meta = struct('phcID', app.phcIdFromLabel(defPhc), 'eye', eyeVal);

                dlg = uiprogressdlg(app.Fig, 'Title','Batch ingest', ...
                    'Message','Starting...', 'Cancelable','off', 'Value', 0);
                cleanup = onCleanup(@() delete(dlg)); %#ok<NASGU>
                prog = @(i,n,f) app.batchProgress(dlg, i, n, f);

                results = netra.io.batchIngest(char(folder), meta, app.Config, prog);

                app.refreshDashboard();
                app.showBatchResults(results);
            end
        end

        function batchProgress(~, dlg, i, n, fname)
            if isvalid(dlg)
                dlg.Value = max(0, min(1, (i-1)/max(1,n)));
                dlg.Message = sprintf('(%d/%d)  %s', i, n, fname);
            end
        end

        function showBatchResults(app, results)
            t = netra.ui.theme();
            nIng = sum(results.status == "ingested");
            nRej = sum(results.status == "rejected");
            nErr = sum(results.status == "error");

            d = uifigure('Name','Batch Import Results', 'Color', t.color.bg, ...
                'Position', [200 200 720 460]);
            gg = uigridlayout(d, [3 1], 'RowHeight', {'fit','1x','fit'}, ...
                'Padding', t.space.pad*[1 1 1 1], 'BackgroundColor', t.color.bg);
            uilabel(gg, 'Text', sprintf(...
                'Ingested: %d    Rejected: %d    Errors: %d    (total %d)', ...
                nIng, nRej, nErr, height(results)), ...
                'FontName', t.font.family, 'FontSize', t.font.h3, ...
                'FontWeight','bold', 'FontColor', t.color.text);
            tbl = uitable(gg, ...
                'ColumnName', {'File','Status','UID','Reason','Secs'}, ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'BackgroundColor', [t.color.panelAlt; t.color.panel], ...
                'ForegroundColor', t.color.text, 'RowName', {});
            tbl.Data = [cellstr(results.file), cellstr(results.status), ...
                cellstr(results.uid), cellstr(results.reason), ...
                cellstr(compose('%.2f', results.elapsedSeconds))];
            brow = uigridlayout(gg, [1 2], 'Padding',[0 0 0 0], ...
                'ColumnSpacing', t.space.gapSm, 'BackgroundColor', t.color.bg);
            app.mkButton(brow, 'Export CSV', @() localExportCsv(), t.color.info);
            app.mkButton(brow, 'Close', @() delete(d), t.color.panelAlt);

            function localExportCsv()
                [f, p] = uiputfile('*.csv', 'Save batch results', 'batch_results.csv');
                if isequal(f,0), return; end
                writetable(results, fullfile(p,f));
                uialert(d, sprintf('Saved to %s', fullfile(p,f)), 'Exported', 'Icon','success');
            end
        end

        function loadMockCaseIntoWorkbench(app, row, readOnly)
            cr = app.mockCaseFromRow(row);
            app.CurrentCase = cr;
            app.Banner.update(cr.provenance);
            app.populateWorkbench(cr, readOnly);
        end

        function cr = mockCaseFromRow(app, row)
            % Build a caseRecord from a registry row and run the mock pipeline
            % so the Workbench/Case Review bind to real schema fields. The
            % row's grade/quality are cosmetic labels; the pipeline fills the
            % rest with mock values (that is intended in Phase 1).
            demo = char(fullfile(app.Root, 'data','demo','sample01.jpg'));
            meta = struct('patientID', row.patientID, 'phcID', row.phcID, ...
                'age', row.age, 'eye', row.eye);
            cr = netra.newCaseRecord(demo, meta);
            cr.meta.uid = row.uid;
            cr = netra.runPipeline(cr, app.Config, app.Models);
        end

        function setCanvasBase(app, canvas, cr)
            % Prefer REAL pixels (Phase 2 ingest): displayRGB/enhanced are the
            % cropped, FOV-masked frame. Fall back to the synthetic placeholder
            % only for mock-registry cases that never loaded an image.
            if ~isempty(cr.img.displayRGB)
                base = cr.img.displayRGB;
            elseif ~isempty(cr.img.enhanced)
                base = cr.img.enhanced;
            elseif ~isempty(cr.img.raw)
                base = cr.img.raw;
            else
                base = app.placeholderFundus(cr);   % honest synthetic placeholder
            end
            canvas.setBase(base);
        end

        function img = placeholderFundus(app, cr)
            % Deterministic synthetic fundus disc so overlays have somewhere
            % to sit. NOT a real image.
            n = 256;
            [X,Y] = meshgrid(linspace(-1,1,n), linspace(-1,1,n));
            R = sqrt(X.^2 + Y.^2);
            disc = double(R < 0.95);
            r = 0.35 + 0.15*(1-R); g = 0.12 + 0.05*(1-R); b = 0.10*ones(n);
            img = cat(3, r.*disc, g.*disc, b.*disc);
            img = uint8(255*min(1,max(0,img)));
        end

        function addSyntheticOverlays(app, canvas, cr)
            % Phase 5/6: if the structures/lesions stages ran for real, build
            % overlays from the ACTUAL masks. Otherwise (mock registry preview)
            % fall back to the synthetic placeholders below so the demo cases
            % still show something. Real masks: vessels, OD+fovea, quadrant grid,
            % per-class lesions; Grad-CAM stays Track B's (synthetic here).
            if app.hasRealStructures(cr)
                app.addRealOverlays(canvas, cr);
                return;
            end
            t = netra.ui.theme();
            n = 256;
            [X,Y] = meshgrid(1:n, 1:n);

            % vessels: a few sinusoidal streaks
            vessel = false(n);
            for a = -2:2
                yy = round(n/2 + 30*a + 20*sin(2*pi*(1:n)/120));
                yy = min(n, max(1, yy));
                for x = 1:n, vessel(yy(x), x) = true; end
            end
            vessel = imdilateLite(vessel, 1);

            % OD + fovea discs from mock centres (scaled into n)
            od = false(n); fov = false(n);
            odc = scalePt(cr.structures.odCenter, n);
            fvc = scalePt(cr.structures.foveaCenter, n);
            od  = od  | ((X-odc(1)).^2 + (Y-odc(2)).^2) < (0.06*n)^2;
            fov = fov | ((X-fvc(1)).^2 + (Y-fvc(2)).^2) < (0.03*n)^2;
            odFov = od | fov;

            % quadrant grid lines
            quad = false(n);
            quad(round(n/2),:) = true; quad(:,round(n/2)) = true;
            quad = imdilateLite(quad, 1);

            % lesions: dots from total counts
            les = false(n);
            cnt = cr.lesions.MA.count + cr.lesions.HE.count;
            rng(7);  % deterministic dot placement
            for i = 1:max(0,cnt)
                cx = randi([30 n-30]); cy = randi([30 n-30]);
                les = les | ((X-cx).^2 + (Y-cy).^2) < 5^2;
            end

            % gradcam: soft blob near fovea
            gc = exp(-(((X-fvc(1)).^2 + (Y-fvc(2)).^2)/(2*(0.25*n)^2)));
            gcMask = gc > 0.35;

            canvas.addLayer('Vessels',  vessel, t.color.vessel);
            canvas.addLayer('ODFovea',  odFov,  t.color.fovea);
            canvas.addLayer('Quadrants',quad,   t.color.info);
            canvas.addLayer('Lesions',  les,    t.color.lesion);
            canvas.addLayer('GradCAM',  gcMask, t.color.gradcam);
            canvas.setOpacity('GradCAM', 0.6);
        end

        function tf = hasRealStructures(~, cr)
            % True when the structures stage produced a real vessel mask.
            tf = isfield(cr,'provenance') && isfield(cr.provenance,'structures') ...
                && cr.provenance.structures == "REAL" ...
                && ~isempty(cr.structures.vesselMask);
        end

        function addRealOverlays(app, canvas, cr)
            % Build canvas overlays from the REAL structure/lesion masks. All
            % masks are the enhanced-frame size; the canvas resizes to its base.
            t = netra.ui.theme();
            S = cr.structures;
            [H, W, ~] = size(cr.img.displayRGB);
            if H == 0, [H, W, ~] = size(cr.img.enhanced); end

            % Vessels: cyan skeleton (thin the mask so it reads as a skeleton).
            vessel = S.vesselMask;
            if ~isequal(size(vessel),[H W]), vessel = false(H,W); end
            skel = bwmorph(vessel, 'thin', Inf);
            skel = imdilate(skel, strel('disk',1));       % 1px visibility bump
            canvas.addLayer('Vessels', skel, t.color.vessel);

            % OD (green circle) + fovea (magenta crosshair).
            odFov = app.odFoveaOverlay(S.odCenter, S.odRadius, S.foveaCenter, H, W);
            canvas.addLayer('ODFovea', odFov, t.color.pass);   % green circle
            fovX = app.crosshairMask(S.foveaCenter, H, W);
            canvas.addLayer('Fovea', fovX, t.color.fovea);     % magenta crosshair

            % Quadrant grid: boundaries between quadrant codes = thin dividers.
            quad = app.quadrantGridMask(S.quadrantMap, H, W);
            canvas.addLayer('Quadrants', quad, [1 1 1]);       % thin white dividers

            % Lesions: per-class masks (MA red, HE dark red, EX yellow) + a
            % combined 'Lesions' layer the existing checkbox drives.
            lay = netra.ui.lesionOverlay(cr, [H W]);
            union = false(H, W);
            app.WBHandles.lesionCounts = struct();
            for k = 1:numel(lay)
                canvas.addLayer(lay(k).name, lay(k).mask, lay(k).color);
                union = union | lay(k).mask;
                cls = erase(lay(k).name, 'Lesion_');
                app.WBHandles.lesionCounts.(cls) = lay(k).count;
            end
            canvas.addLayer('Lesions', union, t.color.lesion);

            % Grad-CAM is Track B's; if absent, add an empty layer so the toggle
            % exists but shows nothing (never fabricate an attention map).
            gc = false(H, W);
            if isfield(cr,'xai') && ~isempty(cr.xai.gradcam) ...
                    && isequal(size(cr.xai.gradcam),[H W])
                gc = cr.xai.gradcam > 0.35;
            end
            canvas.addLayer('GradCAM', gc, t.color.gradcam);
            canvas.setOpacity('GradCAM', 0.6);

            % Live legend counts under the lesion table.
            app.updateLesionLegend(cr);
        end

        function m = odFoveaOverlay(~, odC, odR, ~, H, W)
            % Green ring at the optic disc (annulus, ~3px thick).
            m = false(H, W);
            if any(~isfinite(odC)) || ~isfinite(odR) || odR <= 0, return; end
            [X, Y] = meshgrid(1:W, 1:H);
            d2 = (X-odC(1)).^2 + (Y-odC(2)).^2;
            m = d2 <= (odR+1.5)^2 & d2 >= (odR-1.5)^2;
        end

        function m = crosshairMask(~, ctr, H, W)
            % Small magenta plus at the fovea centre.
            m = false(H, W);
            if any(~isfinite(ctr)), return; end
            cx = min(W,max(1,round(ctr(1)))); cy = min(H,max(1,round(ctr(2))));
            r = max(4, round(0.02*min(H,W)));
            xs = max(1,cx-r):min(W,cx+r); ys = max(1,cy-r):min(H,cy+r);
            m(cy, xs) = true; m(ys, cx) = true;
            m = imdilate(m, strel('disk',1));
        end

        function m = quadrantGridMask(~, qmap, H, W)
            % Divider = pixels where the quadrant code changes (thin boundaries).
            m = false(H, W);
            if ~isequal(size(qmap),[H W]) || ~any(qmap(:)), return; end
            gmag = imgradient(double(qmap));
            m = (gmag > 0) & (qmap > 0);
            m = imdilate(m, strel('disk',0));
        end

        function updateLesionLegend(app, cr)
            % Live per-class counts shown on the lesion panel title/legend.
            if ~isfield(app.WBHandles,'lesionLegend') || ...
                    isempty(app.WBHandles.lesionLegend) || ...
                    ~isvalid(app.WBHandles.lesionLegend)
                return;
            end
            app.WBHandles.lesionLegend.Text = sprintf( ...
                'Legend:  MA %d (red)   HE %d (dark red)   EX %d (yellow)', ...
                cr.lesions.MA.count, cr.lesions.HE.count, cr.lesions.EX.count);
        end

        % ---- small UI factory helpers ----
        function b = mkButton(app, parent, label, cb, bgColor)
            t = netra.ui.theme();
            b = uibutton(parent, 'Text', label, ...
                'FontName', t.font.family, 'FontSize', t.font.body, ...
                'FontColor', t.color.text, 'BackgroundColor', bgColor, ...
                'ButtonPushedFcn', @(~,~) app.wrap(cb));
        end

        function mkFieldLabel(~, parent, txt)
            t = netra.ui.theme();
            uilabel(parent, 'Text', txt, ...
                'FontName', t.font.family, 'FontSize', t.font.body, ...
                'FontColor', t.color.textMuted, 'VerticalAlignment','center');
        end

        function out = titledPanel(~, parent, title)
            t = netra.ui.theme();
            p = uipanel(parent, 'Title', title, ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'ForegroundColor', t.color.textMuted, ...
                'BackgroundColor', t.color.panel, ...
                'HighlightColor', t.color.border, ...
                'BorderType','line');
            gr = uigridlayout(p, [1 1], 'Padding', t.space.gapSm*[1 1 1 1], ...
                'BackgroundColor', t.color.panel);
            out = struct('Panel', p, 'Grid', gr);
        end

        function ax = mkAxesPanel(app, parent, title)
            out = app.titledPanel(parent, title);
            ax = uiaxes(out.Grid);
            app.styleAxes(ax);
        end

        function styleAxes(~, ax)
            t = netra.ui.theme();
            ax.Color = t.color.panel;
            ax.XColor = t.color.textMuted; ax.YColor = t.color.textMuted;
            ax.GridColor = t.color.border;
            ax.FontName = t.font.family; ax.FontSize = t.font.tiny;
            ax.Box = 'off';
            try, ax.Toolbar.Visible = 'off'; catch, end
        end

        function emptyAxes(~, ax, msg)
            t = netra.ui.theme();
            cla(ax);
            text(ax, 0.5, 0.5, msg, 'Units','normalized', ...
                'HorizontalAlignment','center', 'Color', t.color.textDim, ...
                'FontSize', t.font.small);
            ax.XTick = []; ax.YTick = [];
        end

        function noteToast(app, msg)
            % Lightweight non-modal confirmation (uialert is modal but fine
            % for Phase 1; a real toast lands later).
            uialert(app.Fig, msg, 'NETRA', 'Icon','info');
        end

        function items = phcItems(app)
            reg = app.Config.phcRegistry;
            items = {};
            for k = 1:numel(reg)
                if isfield(reg(k), 'id') && ~isempty(reg(k).id)
                    items{end+1} = sprintf('%s - %s', reg(k).id, reg(k).name); %#ok<AGROW>
                end
            end
            if isempty(items), items = {'PHC001'}; end
        end

        function id = phcIdFromLabel(~, label)
            parts = split(string(label), " - ");
            id = parts(1);
        end

        function s = safeStats(app)
            try
                s = netra.store.stats(app.Config);
            catch
                s = struct('screenedToday',0,'referred',0,'autoCleared',0, ...
                    'recaptureRate',0,'avgReviewSeconds',0,'queueDepth',0, ...
                    'gradeDistribution',zeros(1,5),'last7Days',zeros(7,3), ...
                    'qualityFailReasons',table(strings(0,1),zeros(0,1), ...
                        'VariableNames',{'reason','count'}), ...
                    'queueDepthByHour',0);
            end
        end

        function T = safeRegistry(~)
            T = netra.store.internalLoadRegistry();
        end

        function a = safeAudit(app)
            try
                a = netra.store.auditStats(app.Config);
            catch
                a = struct('reviewedCount',0,'agreementRate',NaN, ...
                    'overrideCount',0,'overridesByGrade',zeros(1,5), ...
                    'reviewSeconds',zeros(0,1),'medianReviewSeconds',NaN, ...
                    'p95ReviewSeconds',NaN);
            end
        end

        function k = key(~, name)
            k = char(matlab.lang.makeValidName(string(name)));
        end

        function wrap(app, fn)
            % Wrap any callback: show a friendly uialert on error, log stack.
            try
                fn();
            catch ME
                fprintf(2, 'NETRA callback error: %s\n', getReport(ME));
                if ~isempty(app.Fig) && isvalid(app.Fig)
                    uialert(app.Fig, ...
                        sprintf('Something went wrong:\n%s', ME.message), ...
                        'Error', 'Icon','error');
                end
            end
        end
    end
end

% ======================= file-local helpers =============================
function v = nz(x)
    if isempty(x) || ~isfinite(x), v = 0; else, v = x; end
end
function y = clampUnit(x)
    if ~isfinite(x), y = 0; else, y = min(1, max(0, x)); end
end
function s = numOrDash(x)
    if isempty(x) || ~isfinite(x), s = "-"; else, s = string(x); end
end
function s = defaultStr(x, d)
    if strlength(string(x)) == 0, s = string(d); else, s = string(x); end
end
function s = ternStr(cond, a, b)
    if cond, s = a; else, s = b; end
end
function p = scalePt(pt, n)
    % Map a mock pixel centre (~1024 space) into n-space; default to centre.
    if isempty(pt) || any(isnan(pt))
        p = [round(n/2) round(n/2)];
    else
        p = round(pt / 1024 * n);
        p = min(n, max(1, p));
    end
end
function m2 = imdilateLite(m, r)
    % Tiny binary dilation without Image Processing Toolbox.
    m2 = m;
    for dx = -r:r
        for dy = -r:r
            m2 = m2 | circshift(m, [dy dx]);
        end
    end
end
