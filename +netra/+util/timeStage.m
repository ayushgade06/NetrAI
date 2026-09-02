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
    if nargout(fnHandle) == 0
        % Stage yields no output (e.g. it only ever errors). Call it for its
        % side effect / to let its own error propagate, rather than requesting
        % an output MATLAB won't bind (which would throw MATLAB:maxlhs and mask
        % the real failure).
        fnHandle(varargin{:});
        out = [];
    else
        out = fnHandle(varargin{:});
    end
    elapsed = toc(t0);
end
