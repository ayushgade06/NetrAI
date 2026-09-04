function outPath = reportToDesktop(uid, cfg)
%REPORTTODESKTOP  Render ONE combined PDF (patient data + 2x2 panel) to Desktop.
%   outPath = reportToDesktop(uid) loads the stored case UID, builds a single
%   2-page PDF (page 1 = patient data + key findings, page 2 = the 2x2 evidence
%   panel) and saves it to the user's Desktop as <uid>_report.pdf.
%
%   Unlike netra.report.generate's print() fallback (which splits text and panel
%   into two files), this always produces ONE file: it writes both pages with
%   exportgraphics when available, else stacks them into a single tall figure so
%   there is never a separate _panel.pdf.
%
%   uid : case UID string, e.g. "PHC001-20260904-0009-OD"
%   cfg : optional config (defaults to netra.loadConfig()).

    arguments
        uid (1,:) char
        cfg (1,1) struct = netra.loadConfig()
    end

    cr = netra.store.load(uid);          % pull the real stored case
    R  = netra.report.template(cr, cfg);

    desktop = fullfile(char(java.lang.System.getProperty('user.home')), 'Desktop');
    if ~isfolder(desktop), desktop = char(java.lang.System.getProperty('user.home')); end
    outPath = fullfile(desktop, [char(uid) '_report.pdf']);
    if isfile(outPath), delete(outPath); end

    figText  = textPage(R);
    figPanel = netra.report.composite(cr, cfg);
    c1 = onCleanup(@() safeDelete(figText));  %#ok<NASGU>
    c2 = onCleanup(@() safeDelete(figPanel)); %#ok<NASGU>

    if exist('exportgraphics','file') || exist('exportgraphics','builtin')
        exportgraphics(figText,  outPath, 'ContentType','vector');
        exportgraphics(figPanel, outPath, 'ContentType','vector', 'Append', true);
    else
        % No exportgraphics: one tall figure so it stays a single PDF.
        combo = stackPages(figText, figPanel);
        c3 = onCleanup(@() safeDelete(combo)); %#ok<NASGU>
        print(combo, outPath, '-dpdf', '-bestfit');
    end

    fprintf('reportToDesktop: wrote %s\n', outPath);
end

% ------------------------------------------------------------------------
function fig = textPage(R)
%TEXTPAGE  Patient data + key findings, only the relevant lines.
    fig = figure('Visible','off','Color','w','Units','pixels', ...
        'Position',[100 100 720 960]);
    ax = axes(fig,'Position',[0 0 1 1]); axis(ax,'off'); xlim(ax,[0 1]); ylim(ax,[0 1]);

    y = 0.965; x = 0.06;
    y = line1(ax,x,y,R.title,15,'bold',[0 0 0]); y = y-0.012;
    line(ax,[0.06 0.94],[y y],'Color',[0.7 0.7 0.7]); y = y-0.024;

    y = block(ax,x,y,R.patientHeader,10); y = y-0.010;
    y = line1(ax,x,y,R.qualityVerdict,10,'normal',[0 0 0]);
    y = line1(ax,x,y,R.gradeLine,12,'bold',[0 0 0]);
    y = line1(ax,x,y,R.referralLine,11,'bold',[0.55 0.2 0]);
    y = line1(ax,x,y,R.confidenceLine,10,'normal',[0 0 0]);
    y = line1(ax,x,y,R.alaLine,10,'normal',[0 0 0]); y = y-0.008;

    y = line1(ax,x,y,"Evidence:",11,'bold',[0 0 0]);
    y = block(ax,x,y,"  - "+R.evidence,10); y = y-0.008;

    y = line1(ax,x,y,R.timestampLine,9,'normal',[0.15 0.15 0.15]);
    line1(ax,x,y,R.versionLine,9,'normal',[0.15 0.15 0.15]);

    text(ax,0.5,0.045,char(R.disclaimer),'Units','normalized', ...
        'HorizontalAlignment','center','FontSize',9,'FontWeight','bold', ...
        'FontAngle','italic','Color',[0.5 0 0],'Interpreter','none');
end

function combo = stackPages(fText, fPanel)
%STACKPAGES  Copy both pages' axes into one tall portrait figure (print path).
    combo = figure('Visible','off','Color','w','Units','pixels', ...
        'Position',[100 100 720 1500]);
    tl = tiledlayout(combo,2,1,'TileSpacing','compact','Padding','compact');
    copyToTile(fText, nexttile(tl,1));
    copyToTile(fPanel, nexttile(tl,2));
end

function copyToTile(srcFig, ax)
    axis(ax,'off');
    axSrc = findobj(srcFig,'Type','axes');
    for k = numel(axSrc):-1:1
        copyobj(allchild(axSrc(k)), ax);
    end
end

function y = line1(ax,x,y,txt,fs,w,c)
    text(ax,x,y,char(txt),'Units','normalized','FontSize',fs,'FontWeight',w, ...
        'Color',c,'VerticalAlignment','top','Interpreter','none');
    y = y - (0.006 + fs*0.0016);
end

function y = block(ax,x,y,lines,fs)
    for k = 1:numel(lines)
        y = line1(ax,x,y,lines(k),fs,'normal',[0 0 0]);
    end
end

function safeDelete(f)
    if ~isempty(f) && ishandle(f), delete(f); end
end
