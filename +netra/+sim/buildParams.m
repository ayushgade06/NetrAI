function p = buildParams(uiStruct, latencyStats, cfg)
%BUILDPARAMS  Assemble capacity-model parameters from UI form + measured data.
%   p = netra.sim.buildParams(uiStruct, latencyStats, cfg) merges, in order:
%     1. config defaults           (default_params, all "assumed")
%     2. MEASURED pipeline latency (latencyStats) -> inferenceSecPerImage
%     3. MEASURED audit data       (auditStats)   -> reviewSecPerCase
%     4. explicit UI overrides     (uiStruct)     -> any field the user typed
%   and returns the parameter struct consumed by netra.sim.runCapacity, with a
%   "<field>_src" flag on every parameter recording "measured" or "assumed".
%
%   inferenceSecPerImage is sourced from the MEASURED median grading-stage
%   latency (netra.util.latencyStats over data/timing.log). reviewSecPerCase is
%   sourced from the MEASURED median review time (netra.store.auditStats). When
%   the measurement is unavailable (no runs / no reviews yet) the config
%   assumption is kept and the flag stays "assumed", so the UI can honestly
%   label it - this function never fabricates a measured value.
%
%   A field present in uiStruct ALWAYS wins (the user is explicitly editing it)
%   and is flagged by uiStruct.(field_src) if supplied, else "assumed" (a typed
%   number is a planning assumption unless it came from a measured field).
%
%   Inputs:
%     uiStruct      struct of parameter overrides (may be empty / partial)
%     latencyStats  output of netra.util.latencyStats (may be [] to skip)
%     cfg           loaded config (optional; loaded if omitted)

    arguments
        uiStruct     struct = struct()
        latencyStats struct = struct('available', false)
        cfg          struct = netra.loadConfig()
    end

    here = fileparts(mfilename('fullpath'));           % +sim
    simDir = fullfile(fileparts(fileparts(here)), 'simulink');
    if exist('default_params', 'file') ~= 2
        addpath(simDir);
    end
    p = default_params(cfg);                            % all "assumed"

    % --- (2) measured inference latency ---------------------------------
    if isfield(latencyStats, 'available') && latencyStats.available
        g = NaN;
        if isfield(latencyStats, 'gradingMedian')
            g = latencyStats.gradingMedian;
        elseif isfield(latencyStats, 'perStage') && isfield(latencyStats.perStage, 'grading')
            g = latencyStats.perStage.grading.median;
        end
        if isfinite(g) && g > 0
            p.inferenceSecPerImage = g;
            p.inferenceSecPerImage_src = "measured";
        end
    end

    % --- (3) measured review time ---------------------------------------
    try
        a = netra.store.auditStats(cfg);
        if isfinite(a.medianReviewSeconds) && a.medianReviewSeconds > 0
            p.reviewSecPerCase = a.medianReviewSeconds;
            p.reviewSecPerCase_src = "measured";
        end
    catch
        % no audit data -> keep assumed default
    end

    % --- (4) explicit UI overrides --------------------------------------
    names = netra.sim.paramNames();
    for k = 1:numel(names)
        f = names{k};
        if isfield(uiStruct, f) && ~isempty(uiStruct.(f)) && isfinite(double(uiStruct.(f)))
            p.(f) = double(uiStruct.(f));
            srcField = [f '_src'];
            if isfield(uiStruct, srcField)
                p.(srcField) = string(uiStruct.(srcField));
            else
                p.(srcField) = "assumed";   % user-typed planning value
            end
        end
    end
end
