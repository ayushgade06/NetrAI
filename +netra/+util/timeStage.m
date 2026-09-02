function [out, elapsed] = timeStage(fnHandle, varargin)
%TIMESTAGE  Run a function handle and return its output plus wall-clock time.
%   [out, elapsed] = netra.util.timeStage(fnHandle, arg1, arg2, ...) calls
%   fnHandle(arg1, arg2, ...), returns its single output in OUT and the
%   elapsed wall-clock time in seconds in ELAPSED.
%
%   Timing uses tic/toc (monotonic wall clock). Any error thrown by
%   fnHandle propagates to the caller; runPipeline is responsible for
%   catching it. ELAPSED is still meaningful only on success.
%
%   Example:
%     [cr, t] = netra.util.timeStage(@netra.quality.assess, cr, cfg);

    arguments
        fnHandle (1,1) function_handle
    end
    arguments (Repeating)
        varargin
    end

    t0 = tic;
    % nargout(fnHandle) is 0 for a zero-output function and -1 for an anonymous
    % handle whose output count is unknown. In BOTH cases requesting an output
    % can throw MATLAB:maxlhs and mask the stage's own error, so call without
    % binding an output first, then bind one only if the handle actually
    % produced it.
    if nargout(fnHandle) <= 0
        try
            out = fnHandle(varargin{:});   % anonymous handle may still return a value
        catch ME
            if ME.identifier == "MATLAB:maxlhs" || ME.identifier == "MATLAB:TooManyOutputs"
                fnHandle(varargin{:});     % no output to bind; run for side effect / error
                out = [];
            else
                rethrow(ME);               % the stage's real error propagates
            end
        end
    else
        out = fnHandle(varargin{:});
    end
    elapsed = toc(t0);
end
