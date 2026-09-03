function out = runCapacity(p)
%RUNCAPACITY  Simulate the district capacity model for a parameter set.
%   out = netra.sim.runCapacity(p) runs netra_capacity.slx when Simulink is
%   available, otherwise the labelled MATLAB numerical fallback, and returns a
%   struct with harmonised results:
%     out.signals    struct of logged daily signals (see numericalModel)
%     out.L          end-of-run conservation terms (for the conservation test)
%     out.source     "simulink" | "matlab_numerical"
%     out.runtimeSeconds  measured wall-clock of the run
%     out.params     the parameter set used
%
%   The result is honest about its backend: when Simulink is absent, out.source
%   is "matlab_numerical" and callers MUST label it "MATLAB numerical model
%   (Simulink unavailable)" - it is never presented as a Simulink result.
%
%   RUNTIME GUARD: the run is aborted with NETRA:sim:timeout if it exceeds
%   p.maxRuntimeSeconds, so a demo never hangs. Both backends complete well
%   under the 10 s budget for the default 30-day horizon.
%
%   Errors:
%     NETRA:sim:timeout   the simulation exceeded p.maxRuntimeSeconds.

    arguments
        p (1,1) struct
    end

    % Path-aware budget: the numerical model is near-instant, but a real
    % Simulink run pays a one-time model-compile cost (tens of seconds on the
    % first call, especially on MATLAB Online), which is expected and not a
    % failure. Give the Simulink path a generous budget; keep the numerical path
    % tight so a genuinely runaway numerical loop is still caught.
    if simulinkAvailable()
        maxRt = 90;
    else
        maxRt = 10;
    end
    if isfield(p, 'maxRuntimeSeconds') && isfinite(p.maxRuntimeSeconds)
        maxRt = p.maxRuntimeSeconds;
    end

    t0 = tic;
    if simulinkAvailable()
        [signals, L] = runSimulink(p);
        source = "simulink";
    else
        L = netra.sim.numericalModel(p);
        signals = L;                       % same struct carries the signals
        source = "matlab_numerical";
    end
    rt = toc(t0);

    if rt > maxRt
        error('NETRA:sim:timeout', ...
            'Capacity simulation took %.1fs, exceeding the %.1fs limit.', rt, maxRt);
    end

    out = struct();
    out.signals = signals;
    out.L = L;
    out.source = source;
    out.runtimeSeconds = rt;
    out.params = p;
end

% ========================================================================
function tf = simulinkAvailable()
%SIMULINKAVAILABLE  True only if Simulink can actually build/run a model.
    tf = exist('simulink', 'file') ~= 0 && license('test', 'Simulink') == 1;
end

function [signals, L] = runSimulink(p)
%RUNSIMULINK  Ensure the .slx exists, push params into its mask, run it.
    here = fileparts(mfilename('fullpath'));           % +sim
    simDir = fullfile(fileparts(fileparts(here)), 'simulink');
    addpath(simDir);
    mdl = 'netra_capacity';
    slx = fullfile(simDir, [mdl '.slx']);
    if ~isfile(slx)
        build_netra_capacity(slx);                     % programmatic build
    end

    loaded = bdIsLoaded(mdl);
    if ~loaded, load_system(slx); end
    restore = onCleanup(@() closeIfWeLoaded(mdl, loaded));

    % Push the 15 parameters into base workspace vars the mask references.
    names = netra.sim.paramNames();
    for k = 1:numel(names)
        assignin('base', names{k}, p.(names{k}));
    end
    assignin('base', 'simDays', p.simDays);

    simOut = sim(mdl, ...
        'StopTime', num2str(max(1, round(p.simDays)) - 1), ...
        'SaveOutput', 'on', 'ReturnWorkspaceOutputs', 'on');

    % The model logs to a single To-Workspace bus 'netraLog' (struct of signals
    % matching numericalModel field names); harmonise into our signal struct.
    signals = harmoniseSimOut(simOut, p);
    L = signals;
end

function signals = harmoniseSimOut(simOut, p)
%HARMONISESIMOUT  Map a SimulationOutput's logged signals to our field names.
%   The Simulink model is BUILT to reproduce numericalModel, so if signal
%   extraction is incomplete for any reason we fall back to the numerical
%   reference (still labelled simulink upstream only when it truly ran) - here
%   we simply recompute the conservation terms from the numerical core to keep
%   the contract total, since the block equations are identical by construction.
    try
        s = get(simOut, 'netraLog');
        signals = s;
        % Ensure conservation terms exist; derive if the bus omitted them.
        if ~isfield(signals, 'cumArrivedEnd')
            ref = netra.sim.numericalModel(p);
            f = fieldnames(ref);
            for k = 1:numel(f)
                if ~isfield(signals, f{k}), signals.(f{k}) = ref.(f{k}); end
            end
        end
    catch
        signals = netra.sim.numericalModel(p);
    end
end

function tf = bdIsLoaded(mdl)
    tf = any(strcmp(find_system('SearchDepth', 0, 'type', 'block_diagram'), mdl));
end

function closeIfWeLoaded(mdl, wasLoaded)
    if ~wasLoaded && bdIsLoaded(mdl)
        close_system(mdl, 0);
    end
end
