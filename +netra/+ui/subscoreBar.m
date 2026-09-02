function h = subscoreBar(parent, label, value, threshold, opts)
%SUBSCOREBAR  Labelled horizontal bar with a threshold tick.
%   h = netra.ui.subscoreBar(parent, label, value, threshold) draws a bar
%   representing VALUE (0..1) with a vertical tick at THRESHOLD, and colours
%   the bar green if value >= threshold, else red. Used on the Quality Gate
%   for Focus / Illumination / FOV / Contrast subscores.
%
%   h = netra.ui.subscoreBar(parent, label, value, threshold, opts):
%     opts.range   1x2 [min max] value range (default [0 1])
%
%   Implemented with a uiaxes so the bar and tick render crisply and resize
%   cleanly inside a uigridlayout. Returns a struct with .Axes and .set().

    arguments
        parent
        label (1,1) string
        value (1,1) double
        threshold (1,1) double
        opts struct = struct()
    end

    t = netra.ui.theme();
    rng = getOpt(opts, 'range', [0 1]);

    g = uigridlayout(parent, [1 2], ...
        'ColumnWidth', {110, '1x'}, ...
        'ColumnSpacing', t.space.gap, ...
        'Padding', [0 0 0 0], ...
        'BackgroundColor', t.color.panel);

    txt = sprintf('%s', label);
    lbl = uilabel(g, 'Text', txt, ...
        'FontName', t.font.family, 'FontSize', t.font.small, ...
        'FontColor', t.color.text, 'VerticalAlignment', 'center');
    lbl.Layout.Column = 1;

    ax = uiaxes(g);
    ax.Layout.Column = 2;
    localDraw(ax, value, threshold, rng, t);

    h = struct('Axes', ax, 'Label', lbl);
    h.set = @(v, th) localDraw(ax, v, th, rng, t);
end

% ------------------------------------------------------------------------
function localDraw(ax, value, threshold, rng, t)
    cla(ax);
    lo = rng(1); hi = rng(2);
    frac   = clamp((value - lo) / (hi - lo));
    thFrac = clamp((threshold - lo) / (hi - lo));

    pass = value >= threshold;
    if pass, barColor = t.color.pass; else, barColor = t.color.reject; end

    % track
    rectangle(ax, 'Position', [0 0 1 1], 'FaceColor', t.color.panelAlt, ...
        'EdgeColor', 'none');
    % fill
    if frac > 0
        rectangle(ax, 'Position', [0 0 frac 1], 'FaceColor', barColor, ...
            'EdgeColor', 'none');
    end
    % threshold tick
    line(ax, [thFrac thFrac], [-0.15 1.15], 'Color', t.color.text, ...
        'LineWidth', 1.5);
    % value text on the right
    text(ax, 1.0, 0.5, sprintf('  %.2f', value), 'Parent', ax, ...
        'Color', t.color.text, 'FontSize', t.font.small, ...
        'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left', ...
        'Clipping', 'off');

    ax.XLim = [0 1]; ax.YLim = [0 1];
    ax.XTick = []; ax.YTick = [];
    ax.Color = t.color.panel;
    ax.XColor = 'none'; ax.YColor = 'none';
    ax.Box = 'off';
    ax.Toolbar.Visible = 'off';
    disableDefaultInteractivity(ax);
end

function y = clamp(x)
    y = min(1, max(0, x));
end

function v = getOpt(opts, name, default)
    if isfield(opts, name) && ~isempty(opts.(name))
        v = opts.(name);
    else
        v = default;
    end
end
