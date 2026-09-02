function h = kpiCard(parent, label, value, unit, opts)
%KPICARD  Reusable KPI tile: big value, unit, and a caption label.
%   h = netra.ui.kpiCard(parent, label, value, unit) builds a card in the
%   given grid cell (parent should be a uigridlayout or panel).
%
%   h = netra.ui.kpiCard(parent, label, value, unit, opts) accepts opts:
%     opts.accent  1x3 RGB   value colour (default theme text)
%     opts.sub     string    small caption under the value (e.g. delta)
%
%   Returns a struct with .Panel, .ValueLabel, and a .set(value,sub) updater
%   so a dashboard can refresh a card without rebuilding it.

    arguments
        parent
        label (1,1) string
        value
        unit (1,1) string = ""
        opts struct = struct()
    end

    t = netra.ui.theme();
    accent = getOpt(opts, 'accent', t.color.text);
    sub    = getOpt(opts, 'sub', "");

    panel = uipanel(parent, ...
        'BorderType', 'line', ...
        'BackgroundColor', t.color.panelAlt, ...
        'ForegroundColor', t.color.textMuted, ...
        'HighlightColor', t.color.border);

    % The value uses a large font (h1); in a short fixed-height card row the
    % '1x' middle row could not give it enough vertical space and the number
    % clipped ("half visible"). Pin the value row to the font's line box and
    % trim padding/spacing so all three rows fit within the card height.
    valRowH = t.font.h1 + 10;                      % guaranteed line box for the value
    g = uigridlayout(panel, [3 1], ...
        'RowHeight', {'fit', valRowH, 'fit'}, ...
        'Padding', [t.space.gapSm t.space.gapSm t.space.gapSm t.space.gapSm], ...
        'RowSpacing', 2, ...
        'BackgroundColor', t.color.panelAlt);

    capLbl = uilabel(g, 'Text', upper(label), ...
        'FontName', t.font.family, 'FontSize', t.font.tiny, ...
        'FontColor', t.color.textMuted, 'FontWeight', 'bold');
    capLbl.Layout.Row = 1;

    valLbl = uilabel(g, ...
        'Text', localFmt(value, unit), ...
        'FontName', t.font.family, 'FontSize', t.font.h1, ...
        'FontWeight', 'bold', 'FontColor', accent, ...
        'VerticalAlignment', 'center');
    valLbl.Layout.Row = 2;

    subLbl = uilabel(g, 'Text', sub, ...
        'FontName', t.font.family, 'FontSize', t.font.small, ...
        'FontColor', t.color.textMuted);
    subLbl.Layout.Row = 3;

    h = struct('Panel', panel, 'ValueLabel', valLbl, 'SubLabel', subLbl);
    % varargin so .set(value) and .set(value, sub) both work (the anon wrapper
    % must not force the optional sub arg — localSet already guards on nargin).
    h.set = @(varargin) localSet(valLbl, subLbl, unit, varargin{:});
end

% ------------------------------------------------------------------------
function localSet(valLbl, subLbl, unit, value, sub)
    valLbl.Text = localFmt(value, unit);
    if nargin >= 5, subLbl.Text = sub; end
end

function s = localFmt(value, unit)
    if isstring(value) || ischar(value)
        s = string(value);
    elseif isnumeric(value)
        if value == round(value)
            s = string(sprintf('%d', value));
        else
            s = string(sprintf('%.1f', value));
        end
    else
        s = string(value);
    end
    if strlength(unit) > 0
        s = s + " " + unit;
    end
end

function v = getOpt(opts, name, default)
    if isfield(opts, name) && ~isempty(opts.(name))
        v = opts.(name);
    else
        v = default;
    end
end
