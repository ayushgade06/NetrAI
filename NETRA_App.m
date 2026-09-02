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
        Mode         string = "Field"           % "Field" | "Clinician"
        ActiveView   string = "Dashboard"
        DevMode      logical = false            % dev-only verdict override
        ReviewTimer                             % stopwatch timer object
        ReviewStart                             % datetime when review began
        QueueTable   table                      % cached queue
        Root         string                     % project root

        % --- top-level UI handles ---
        Fig
        NavButtons   struct = struct()          % name -> uibutton
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
            bg = uigridlayout(g, [1 6], 'Padding',[0 0 0 0], ...
                'ColumnSpacing', t.space.gap, ...
                'ColumnWidth', {'1x','1x','1x','1x','1x','1x'}, ...
                'BackgroundColor', t.color.bg);
            bg.Layout.Row = 2;
            app.mkButton(bg, 'New Screening', @() app.switchView("New Screening"), t.color.info);
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
            data = [cellstr(T.uid), cellstr(T.patientID), ...
                    cellstr(string(T.age)), cellstr(T.eye), ...
                    cellstr(string(T.icdr)), cellstr(T.urgency), ...
                    cellstr(T.routingDecision)];
            app.DashHandles.tblRecent.Data = data;
        end

        function tbl = mkRecentTable(app, parent)
            t = netra.ui.theme();
            pnl = app.titledPanel(parent, 'Recent Cases');
            tbl = uitable(pnl.Grid, ...
                'ColumnName', {'UID','Patient','Age','Eye','Grade','Urgency','Decision'}, ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'BackgroundColor', [t.color.panelAlt; t.color.panel], ...
                'ForegroundColor', t.color.text, ...
                'RowName', {}, ...
                'CellSelectionCallback', @(src,ev) app.onRecentRowSelected(ev));
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

            % Simulate Field Capture (disabled in Phase 1)
            app.mkFieldLabel(fg, 'Simulate Capture');
            simdd = uidropdown(fg, 'Items', ...
                {'Blur','Underexposed','Overexposed','Partial FOV','Haze','Random'}, ...
                'Enable','off', 'Tooltip','Available in Phase 2', ...
                'FontName', t.font.family, 'FontSize', t.font.body, ...
                'BackgroundColor', t.color.panelAlt, 'FontColor', t.color.textDim);
            app.NewHandles.simCapture = simdd;

            % buttons
            app.mkFieldLabel(fg, '');
            brow = uigridlayout(fg, [1 4], 'Padding',[0 0 0 0], ...
                'ColumnSpacing', t.space.gapSm, 'BackgroundColor', t.color.panel);
            app.mkButton(brow, 'Load Image', @() app.onLoadImage(), t.color.info);
            app.mkButton(brow, 'Analyze', @() app.onAnalyze(), t.color.pass);
            app.mkButton(brow, 'Clear', @() app.onClearForm(), t.color.panelAlt);

            % --- right: drop-zone + thumbnail ---
            dp = app.titledPanel(g, 'Image Preview');
            dg = uigridlayout(dp.Grid, [1 1], 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.panel);
            app.NewHandles.thumb = uiimage(dg, ...
                'ScaleMethod','fit', 'BackgroundColor', t.color.panelAlt);
        end

        function onLoadImage(app)
            app.wrap(@() localLoad());
            function localLoad()
                [f, p] = uigetfile({'*.jpg;*.jpeg;*.png;*.tif;*.tiff', ...
                    'Images'}, 'Select a fundus image');
                if isequal(f, 0), return; end
                full = fullfile(p, f);
                try
                    imfinfo(full);   % validate readable; no pixel decode needed
                catch
                    uialert(app.Fig, sprintf('"%s" is not a readable image.', f), ...
                        'Load failed');
                    return;
                end
                app.NewHandles.imgPathLbl.Text = f;
                app.NewHandles.imgPathLbl.UserData = full;
                app.NewHandles.thumb.ImageSource = full;
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
        end

        function onAnalyze(app)
            app.wrap(@() localAnalyze());
            function localAnalyze()
                pid = strtrim(app.NewHandles.patientID.Value);
                if isempty(pid)
                    uialert(app.Fig, 'Patient ID is required before analysis.', ...
                        'Missing field'); return;
                end
                imgPath = app.NewHandles.imgPathLbl.UserData;
                if isempty(imgPath)
                    imgPath = char(fullfile(app.Root, 'data','demo','sample01.jpg'));
                    if ~isfile(imgPath)
                        uialert(app.Fig, 'No image loaded and no demo image found.', ...
                            'Missing image'); return;
                    end
                end

                meta = struct('patientID', string(pid), ...
                    'age', app.NewHandles.age.Value, ...
                    'dmYears', app.NewHandles.dmYears.Value, ...
                    'eye', string(app.NewHandles.eye.Value), ...
                    'phcID', app.phcIdFromLabel(app.NewHandles.phc.Value));

                d = uiprogressdlg(app.Fig, 'Title','Running NETRA pipeline', ...
                    'Message','Analysing (mock pipeline)...', 'Indeterminate','on');
                cleanup = onCleanup(@() delete(d));

                cr = netra.newCaseRecord(char(imgPath), meta);
                cr = netra.runPipeline(cr, app.Config, app.Models);
                app.CurrentCase = cr;
                app.Banner.update(cr.provenance);

                app.populateQualityGate(cr);
                app.switchView("Quality Gate");
            end
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
            vbg = uigridlayout(vb, [1 2], 'ColumnWidth', {'1x','fit'}, ...
                'Padding', t.space.pad*[1 1 1 1], 'BackgroundColor', t.color.panelAlt);
            app.QGHandles.verdict = uilabel(vbg, 'Text', 'VERDICT', ...
                'FontName', t.font.family, 'FontSize', t.font.h2, ...
                'FontWeight','bold', 'FontColor', t.color.text, ...
                'VerticalAlignment','center');
            % dev-only verdict override
            devbox = uigridlayout(vbg, [1 2], 'ColumnWidth', {'fit','fit'}, ...
                'Padding',[0 0 0 0], 'BackgroundColor', t.color.panelAlt);
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
            rp = uipanel(g, 'BorderType','none','BackgroundColor', t.color.bg);
            rp.Layout.Row = 2; rp.Layout.Column = 2;
            rg = uigridlayout(rp, [4 1], ...
                'RowHeight', {150,'fit','fit','1x'}, ...
                'RowSpacing', t.space.gapLg, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.bg);

            gp = app.titledPanel(rg, 'Quality Score');
            qmin = app.Config.thresholds.quality.gradeableScoreMin;
            bmin = app.Config.thresholds.quality.borderlineScoreMin;
            app.QGHandles.gauge = netra.ui.gauge(gp.Grid, 0, ...
                struct('thresholds', [bmin qmin], 'caption', "0-100 QUALITY"));

            sp = app.titledPanel(rg, 'Subscores');
            sg = uigridlayout(sp.Grid, [4 1], 'RowSpacing', t.space.gap, ...
                'Padding',[0 0 0 0], 'BackgroundColor', t.color.panel);
            thr = app.Config.thresholds.quality;
            app.QGHandles.sbFocus = netra.ui.subscoreBar(sg, "Focus", 0, thr.focusMin);
            app.QGHandles.sbIllum = netra.ui.subscoreBar(sg, "Illumination", 0, thr.illumUniformityMin);
            app.QGHandles.sbFov   = netra.ui.subscoreBar(sg, "Field of View", 0, thr.fovCompletenessMin);
            app.QGHandles.sbCon   = netra.ui.subscoreBar(sg, "Contrast", 0, thr.contrastMin);

            cp = app.titledPanel(rg, 'Preprocessing / Advice');
            cg = uigridlayout(cp.Grid, [2 1], 'RowHeight', {'fit','fit'}, ...
                'Padding',[0 0 0 0], 'BackgroundColor', t.color.panel);
            app.QGHandles.steps = uilabel(cg, 'Text','Applied steps: -', ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'FontColor', t.color.text, 'WordWrap','on');
            app.QGHandles.advice = uilabel(cg, 'Text','', ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'FontColor', t.color.warn, 'WordWrap','on');

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
            t = netra.ui.theme();
            q = cr.quality;

            app.setCanvasBase(app.QGHandles.canvas, cr);

            app.QGHandles.gauge.set(q.score);
            app.QGHandles.sbFocus.set(q.focus, app.Config.thresholds.quality.focusMin);
            app.QGHandles.sbIllum.set(q.illum, app.Config.thresholds.quality.illumUniformityMin);
            app.QGHandles.sbFov.set(q.fovCompleteness, app.Config.thresholds.quality.fovCompletenessMin);
            app.QGHandles.sbCon.set(q.contrast, app.Config.thresholds.quality.contrastMin);

            if isempty(cr.preproc.appliedSteps)
                app.QGHandles.steps.Text = 'Applied steps: (none)';
            else
                app.QGHandles.steps.Text = "Applied steps: " + strjoin(cr.preproc.appliedSteps, ", ");
            end

            app.applyVerdict(string(q.class), q.recaptureAdvice);
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
            b = app.QGHandles.btnToggle;
            if strcmp(b.Text, 'Show Original')
                b.Text = 'Show Enhanced';
            else
                b.Text = 'Show Original';
            end
            % Phase 1: base image is the same placeholder; toggle is wired,
            % pixel swap arrives with real preproc output.
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

            % --- right: three stacked panels ---
            rp = uigridlayout(g, [4 1], 'RowHeight', {'1x','1x','1x','fit'}, ...
                'RowSpacing', t.space.gap, 'Padding',[0 0 0 0], ...
                'BackgroundColor', t.color.bg);

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
            app.mkButton(g, 'Send to Review Queue', @() app.noteToast('Sent to review queue (mock).'), t.color.info);
            app.WBHandles.btnAutoClear = app.mkButton(g, 'Auto-Clear', @() app.onAutoClear(), t.color.pass);
            app.mkButton(g, 'Next Case', @() app.noteToast('Next case (mock).'), t.color.panelAlt);
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
            app.WBHandles.lesionTbl = uitable(p.Grid, ...
                'ColumnName', {'Type','Count','Area %','Quadrants','Near macula'}, ...
                'FontName', t.font.family, 'FontSize', t.font.small, ...
                'BackgroundColor', [t.color.panelAlt; t.color.panel], ...
                'ForegroundColor', t.color.text, 'RowName', {}, ...
                'CellSelectionCallback', @(src,ev) app.onLesionRow(ev));
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

            app.WBHandles.confPill.Text = sprintf('Confidence: %.0f%%   Band: %s', ...
                100*nz(cr.grade.confidence), defaultStr(cr.xai.confidenceBand,'-'));
            app.WBHandles.ruleRow.Text = sprintf('Rule cross-check: rule=%s  CNN=%s  disagreement=%s', ...
                numOrDash(cr.grade.ruleEstimate), numOrDash(cr.grade.icdr), ...
                string(cr.grade.disagreement));

            % lesions table
            app.WBHandles.lesionTbl.Data = app.lesionTableData(cr);

            % xai
            app.WBHandles.alaLabel.Text = sprintf('ALA: %.2f', nz(cr.xai.agreementScore));
            app.WBHandles.alaBar.set(nz(cr.xai.agreementScore), ...
                app.Config.thresholds.xai.alaLowThreshold);
            if isempty(cr.xai.evidenceBullets)
                app.WBHandles.evidence.Text = 'Evidence: (none)';
            else
                bullets = "- " + cr.xai.evidenceBullets;
                app.WBHandles.evidence.Text = "Evidence:" + newline + strjoin(bullets, newline);
            end
            app.WBHandles.attn.Text = string(cr.xai.attentionSummary);
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
                data{k,4} = strjoin(string(quads), ',');
                data{k,5} = ternStr(L.nearMacula > 0, 'yes','no');
            end
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
                    return;
                end
                app.WBHandles.canvas.setLayerVisible(key, val);
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
                % Solo that lesion class: dim other overlays. Phase 1 has a
                % single combined 'Lesions' layer, so solo it against others.
                app.WBHandles.canvas.soloLesion('Lesions');
                app.noteToast(sprintf('Focused lesion class: %s', keys{row}));
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
                app.RQHandles.kEst.set(round(height(Q)*0.5));  % ~30s each -> min
                st = app.safeStats();
                app.RQHandles.kCleared.set(st.autoCleared);

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
            if ~isempty(app.CurrentCase)
                app.CurrentCase.review.action = string(action);
                app.CurrentCase.review.finalGrade = finalGrade;
                app.CurrentCase.review.seconds = secs;
                app.CurrentCase.review.timestamp = datetime('now');
            end
            % advance queue
            remaining = 0;
            if ~isempty(app.QueueTable) && height(app.QueueTable) > 0
                app.QueueTable(1,:) = [];
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
            app.emptyStatePanel(tab2, 'Populated in Phase 9', ...
                {'Intended: Screening throughput by PHC', ...
                 'Intended: Queue depth vs reviewer capacity', ...
                 'Intended: District coverage projection (Simulink)'});
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
            allowed = app.viewsForMode();
            for k = 1:numel(app.NavOrder)
                nm = app.NavOrder(k);
                vis = matlab.lang.OnOffSwitchState(ismember(nm, allowed));
                app.NavButtons.(app.key(nm)).Visible = vis;
            end
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
            % Phase 1 has no real pixels: synthesize a fundus-like base from
            % the demo image if loadable, else a neutral gradient. Honest
            % placeholder, clearly not a measurement.
            base = app.placeholderFundus(cr);
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
            % Build placeholder masks from mock geometry so overlay toggles
            % show visible layers in Phase 1 (real masks arrive in Phases 5-8).
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
