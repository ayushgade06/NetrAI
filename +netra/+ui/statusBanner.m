function h = statusBanner(parent, provenanceStruct)
%STATUSBANNER  Provenance banner reflecting which pipeline stages are mock.
%   h = netra.ui.statusBanner(parent) creates the banner in an "unknown"
%   state (no case run yet).
%
%   h = netra.ui.statusBanner(parent, provenanceStruct) creates the banner
%   coloured by the provenance of a caseRecord:
%     - every stage "REAL"  -> thin green strip, "All pipeline stages: ..."
%     - any stage "MOCK"    -> amber strip listing the mock stages by name
%     - any stage "FAILED"  -> red strip naming the failed stage(s)
%
%   Returns a struct handle with:
%     h.Panel   the uipanel
%     h.Label   the uilabel
%     h.update(provenanceStruct)   re-render for a new provenance
%
%   The banner is a uilabel inside a uipanel so the whole strip is coloured.

    t = netra.ui.theme();

    panel = uipanel(parent, ...
        'BorderType', 'none', ...
        'BackgroundColor', t.color.panelAlt);
    g = uigridlayout(panel, [1 1], ...
        'Padding', [t.space.pad 2 t.space.pad 2], ...
        'BackgroundColor', t.color.panelAlt);
    lbl = uilabel(g, ...
        'FontName', t.font.family, ...
        'FontSize', t.font.small, ...
        'FontWeight', 'bold', ...
        'FontColor', t.color.text, ...
        'HorizontalAlignment', 'left', ...
        'VerticalAlignment', 'center', ...
        'Text', 'Provenance: no case analysed yet.');

    h = struct('Panel', panel, 'Label', lbl);
    h.update = @(p) localUpdate(panel, g, lbl, p);

    if nargin >= 2 && ~isempty(provenanceStruct)
        h.update(provenanceStruct);
    end
end

% ------------------------------------------------------------------------
function localUpdate(panel, grid, lbl, prov)
    t = netra.ui.theme();
    stages = fieldnames(prov);
    vals = strings(numel(stages),1);
    for k = 1:numel(stages)
        vals(k) = string(prov.(stages{k}));
    end

    failed = string(stages(vals == "FAILED"));
    mock   = string(stages(vals == "MOCK"));

    if ~isempty(failed)
        bg  = t.color.bannerRejectBg;
        txt = sprintf('PIPELINE FAILURE: %s stage(s) failed - results are invalid.', ...
            strjoin(failed, ', '));
    elseif ~isempty(mock)
        bg  = t.color.bannerWarnBg;
        txt = sprintf('MOCK COMPONENTS ACTIVE: %s - outputs are placeholders, not measurements.', ...
            strjoin(mock, ', '));
    else
        % all REAL (or all blank -> treat blanks as not-yet-run REAL-shaped)
        bg  = t.color.bannerPassBg;
        txt = 'All pipeline stages: validated implementations.';
    end

    panel.BackgroundColor = bg;
    grid.BackgroundColor  = bg;
    lbl.Text = txt;
end
