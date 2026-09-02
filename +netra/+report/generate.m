function pdfPath = generate(cr, cfg)
%GENERATE  Produce the clinical PDF report for a case.  [Track C - REAL]
%   pdfPath = netra.report.generate(cr, cfg) renders the annotated 2x2
%   evidence figure (netra.report.composite) and the report text
%   (netra.report.template) into a real PDF at
%       <storeRoot>/data/cases/<uid>/<uid>_report.pdf
%   and returns that path. The orchestrator records the path on cr and sets
%   cr.provenance.report; this stage returns a path (frozen public contract).
%
%   Only +store and +report may write to disk. The report is composed of:
%     - a title page with the patient header, quality verdict, grade, referral,
%       confidence band, ALA, evidence bullets, provenance summary, timestamp,
%       model/config hash, and the mandatory prototype-disclaimer footer;
%     - the 2x2 annotated panel (original / enhanced / lesion overlay / Grad-CAM),
%       with a labelled placeholder for any panel whose stage has not run real.
%
%   RENDERING METHOD: the report is built with base-MATLAB graphics and written
%   with exportgraphics (multi-page append). This needs no Report Generator
%   toolbox, so it works on any MATLAB. If mlreportgen (Report Generator) is
%   present it is still not required - the fallback layout is the shipped path
%   (documented in docs/report_spec.md). When exportgraphics is unavailable the
%   report falls back further to print(); the footer records the method used.
%
%   Errors:
%     NETRA:report:writeFailed  the output PDF could not be written.

    arguments
        cr  (1,1) struct
        cfg (1,1) struct = struct()
    end

    % Output path under the (overridable) store root.
    root = netra.store.storeRoot();
    caseDir = fullfile(root, 'data', 'cases', char(cr.meta.uid));
    if ~isfolder(caseDir)
        [ok, msg] = mkdir(caseDir);
        if ~ok
            error('NETRA:report:writeFailed', ...
                'Cannot create report folder %s: %s', caseDir, msg);
        end
    end
    pdfFile = fullfile(caseDir, [char(cr.meta.uid) '_report.pdf']);
    if isfile(pdfFile), delete(pdfFile); end   % overwrite cleanly (append mode)

    R = netra.report.template(cr, cfg);
    method = renderMethod();
    R.disclaimer = R.disclaimer + "  [rendered via " + method + "]";

    % --- page 1: text summary -------------------------------------------
    figText = textPage(R);
    cleanup1 = onCleanup(@() safeDelete(figText)); %#ok<NASGU>

    % --- page 2: 2x2 annotated evidence panel ---------------------------
    figPanel = netra.report.composite(cr, cfg);
    cleanup2 = onCleanup(@() safeDelete(figPanel)); %#ok<NASGU>

    try
        writePages(pdfFile, {figText, figPanel}, method);
    catch ME
        error('NETRA:report:writeFailed', ...
            'Failed to write report PDF %s: %s', pdfFile, ME.message);
    end

    if ~isfile(pdfFile)
        error('NETRA:report:writeFailed', ...
            'Report PDF was not created at %s.', pdfFile);
    end
    pdfPath = string(pdfFile);
end

% ========================================================================
function m = renderMethod()
%RENDERMETHOD  Name the rendering path taken, for the report footer + spec.
    if exist('exportgraphics', 'file') == 2 || exist('exportgraphics', 'builtin') == 5
        m = "exportgraphics";
    else
        m = "print";
    end
end

function writePages(pdfFile, figs, method)
%WRITEPAGES  Write each figure as a PDF page (append), using the chosen method.
    for k = 1:numel(figs)
        f = figs{k};
        if method == "exportgraphics"
            if k == 1
                exportgraphics(f, pdfFile, 'ContentType', 'vector');
            else
                exportgraphics(f, pdfFile, 'ContentType', 'vector', 'Append', true);
            end
        else
            % Fallback: print each figure to its own PDF then rely on the first
            % page only (base print() cannot append). Simpler layout, acceptable
            % per the fallback policy; the panel goes to a sibling file.
            if k == 1
                print(f, pdfFile, '-dpdf', '-bestfit');
            else
                [p, n] = fileparts(pdfFile);
                print(f, fullfile(p, [n '_panel.pdf']), '-dpdf', '-bestfit');
            end
        end
    end
end

function fig = textPage(R)
%TEXTPAGE  A single portrait figure holding the report's text sections.
    fig = figure('Visible', 'off', 'Color', 'w', ...
        'Units', 'pixels', 'Position', [100 100 720 960]);
    ax = axes(fig, 'Position', [0 0 1 1]); axis(ax, 'off');
    xlim(ax, [0 1]); ylim(ax, [0 1]);

    y = 0.965; x = 0.06;
    y = putLine(ax, x, y, R.title, 15, 'bold', [0 0 0]);
    y = y - 0.012;
    y = putRule(ax, y);

    y = putBlock(ax, x, y, R.patientHeader, 10, 'normal');
    y = y - 0.010;
    y = putLine(ax, x, y, R.qualityVerdict, 10, 'normal', [0 0 0]);
    y = putLine(ax, x, y, R.gradeLine, 12, 'bold', [0 0 0]);
    y = putLine(ax, x, y, R.referralLine, 11, 'bold', [0.55 0.2 0]);
    y = putLine(ax, x, y, R.confidenceLine, 10, 'normal', [0 0 0]);
    y = putLine(ax, x, y, R.alaLine, 10, 'normal', [0 0 0]);
    y = y - 0.006;

    y = putLine(ax, x, y, "Evidence:", 11, 'bold', [0 0 0]);
    bullets = "  - " + R.evidence;
    y = putBlock(ax, x, y, bullets, 10, 'normal');
    y = y - 0.006;

    y = putLine(ax, x, y, "Provenance (stage source at generation):", 11, 'bold', [0 0 0]);
    y = putBlock(ax, x, y, R.provenance, 9, 'normal', 'Monospaced');
    y = y - 0.008;

    y = putLine(ax, x, y, R.timestampLine, 9, 'normal', [0.3 0.3 0.3]);
    y = putLine(ax, x, y, R.versionLine, 9, 'normal', [0.3 0.3 0.3]);

    % Disclaimer footer, pinned near the bottom regardless of content height.
    text(ax, 0.5, 0.045, char(R.disclaimer), 'Units', 'normalized', ...
        'HorizontalAlignment', 'center', 'FontSize', 9, ...
        'FontWeight', 'bold', 'FontAngle', 'italic', 'Color', [0.5 0 0], ...
        'Interpreter', 'none');
    annotation(fig, 'line', [0.06 0.94], [0.075 0.075], 'Color', [0.6 0 0]);
end

% ---- text layout helpers -----------------------------------------------
function y = putLine(ax, x, y, txt, fs, weight, color)
    if nargin < 7, color = [0 0 0]; end
    text(ax, x, y, char(txt), 'Units', 'normalized', 'FontSize', fs, ...
        'FontWeight', weight, 'Color', color, 'VerticalAlignment', 'top', ...
        'Interpreter', 'none');
    y = y - lineHeight(fs);
end

function y = putBlock(ax, x, y, lines, fs, weight, fontName)
    if nargin < 7, fontName = 'Helvetica'; end
    for k = 1:numel(lines)
        text(ax, x, y, char(lines(k)), 'Units', 'normalized', 'FontSize', fs, ...
            'FontWeight', weight, 'FontName', fontName, ...
            'VerticalAlignment', 'top', 'Interpreter', 'none');
        y = y - lineHeight(fs);
    end
end

function y = putRule(ax, y)
    line(ax, [0.06 0.94], [y y], 'Color', [0.7 0.7 0.7]);
    y = y - 0.012;
end

function h = lineHeight(fs)
    h = 0.006 + fs * 0.0016;   % rough px->normalized spacing for a 960px page
end

function safeDelete(f)
    if ~isempty(f) && ishandle(f), delete(f); end
end
