function plotResults(out, axesHandles)
%PLOTRESULTS  Draw the three capacity charts into the supplied axes.
%   netra.sim.plotResults(out, axesHandles) plots, into axesHandles (a 1x3
%   array or cell of uiaxes/axes):
%     (1) Review queue depth over time      -- the hero chart
%     (2) Cumulative arrived vs cleared
%     (3) Reviewer utilisation over time (%)
%
%   out is the struct from netra.sim.runCapacity. When out.source is the MATLAB
%   fallback, the hero chart title is annotated so the chart can never be
%   mistaken for a Simulink result.

    arguments
        out         (1,1) struct
        axesHandles
    end

    if iscell(axesHandles), ax = axesHandles; else, ax = num2cell(axesHandles); end
    s = out.signals;
    d = s.days(:)';

    srcTag = "";
    if out.source == "matlab_numerical"
        srcTag = "  [MATLAB numerical]";
    end

    % (1) queue depth (hero)
    a1 = ax{1}; cla(a1);
    plot(a1, d, s.reviewQueueDepth, '-', 'LineWidth', 2, 'Color', [0.85 0.2 0.2]);
    title(a1, char("Review queue depth (cases)" + srcTag));
    xlabel(a1, 'Day'); ylabel(a1, 'Queue depth'); grid(a1, 'on');

    % (2) cumulative arrived vs cleared
    a2 = ax{2}; cla(a2);
    plot(a2, d, s.cumulativeArrived, '-', 'LineWidth', 1.5, 'Color', [0.2 0.4 0.8]); hold(a2, 'on');
    plot(a2, d, s.cumulativeCleared, '-', 'LineWidth', 1.5, 'Color', [0.2 0.7 0.3]);
    hold(a2, 'off'); grid(a2, 'on');
    title(a2, 'Cumulative arrived vs cleared');
    xlabel(a2, 'Day'); ylabel(a2, 'Images / cases');
    legend(a2, {'Arrived', 'Cleared'}, 'Location', 'northwest');

    % (3) reviewer utilisation
    a3 = ax{3}; cla(a3);
    plot(a3, d, 100 * s.reviewerUtilisation, '-', 'LineWidth', 1.5, 'Color', [0.5 0.3 0.8]);
    ylim(a3, [0 110]); grid(a3, 'on');
    title(a3, 'Reviewer utilisation (%)');
    xlabel(a3, 'Day'); ylabel(a3, 'Utilisation %');
end
