function h = gauge(parent, value, opts)
%GAUGE  0-100 gauge rendered as a clean horizontal bar (arc substitute).
%   h = netra.ui.gauge(parent, value) draws a 0-100 gauge for VALUE. Per the
%   Phase 1 brief, a clean bar substitute is explicitly permitted over a
%   fragile arc; this uses a bar with a numeric readout, which resizes
%   robustly inside uigridlayout.
%
%   h = netra.ui.gauge(parent, value, opts):
%     opts.thresholds  1x2 [amberMin greenMin] to colour the readout
%                      (default from caller; if absent, neutral text colour)
%     opts.caption     string shown under the number
%
%   Returns a struct with .Axes, .ValueLabel and .set(value).

    arguments
        parent
        value double
        opts struct = struct()
    end

    t = netra.ui.theme();
    thr     = getOpt(opts, 'thresholds', []);
    caption = getOpt(opts, 'caption', "QUALITY SCORE");

    g = uigridlayout(parent, [2 1], ...
        'RowHeight', {'1x', 'fit'}, ...
        'RowSpacing', t.space.gapSm, ...
        'Padding', [0 0 0 0], ...
        'BackgroundColor', t.color.panel);

    ax = uiaxes(g);
    ax.Layout.Row = 1;

    valLbl = uilabel(g, 'Text', caption, ...
        'FontName', t.font.family, 'FontSize', t.font.small, ...
        'FontColor', t.color.textMuted, 'HorizontalAlignment', 'center');
    valLbl.Layout.Row = 2;

    localDraw(ax, value, thr, t);

    h = struct('Axes', ax, 'ValueLabel', valLbl);
    h.set = @(v) localDraw(ax, v, thr, t);
end

% ------------------------------------------------------------------------
function localDraw(ax, value, thr, t)
    cla(ax);
    v = max(0, min(100, value));
    if isempty(thr)
        c = t.color.info;
    elseif v >= thr(2)
        c = t.color.pass;
    elseif v >= thr(1)
        c = t.color.warn;
    else
        c = t.color.reject;
    end

    rectangle(ax, 'Position', [0 0 100 1], 'FaceColor', t.color.panelAlt, ...
        'EdgeColor', 'none');
    rectangle(ax, 'Position', [0 0 v 1], 'FaceColor', c, 'EdgeColor', 'none');
    text(ax, 50, 0.5, sprintf('%d', round(v)), 'Parent', ax, ...
        'Color', t.color.text, 'FontSize', t.font.h1, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');

    ax.XLim = [0 100]; ax.YLim = [0 1];
    ax.XTick = []; ax.YTick = [];
    ax.Color = t.color.panel; ax.XColor = 'none'; ax.YColor = 'none';
    ax.Box = 'off'; ax.Toolbar.Visible = 'off';
    disableDefaultInteractivity(ax);
end

function v = getOpt(opts, name, default)
    if isfield(opts, name) && ~isempty(opts.(name))
        v = opts.(name);
    else
        v = default;
    end
end
