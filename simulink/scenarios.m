function sc = scenarios(cfg)
%SCENARIOS  The three preconfigured capacity-planning scenarios.
%   sc = scenarios() returns a 1x3 struct array (name, desc, params) where each
%   params is a full parameter struct (netra.sim.buildParams over an override).
%   sc = scenarios(cfg) reuses an already-loaded config.
%
%     S1 Baseline           : 1 reviewer, autoClearRate 0 (every case reviewed)
%     S2 Auto-clear enabled : 1 reviewer, autoClearRate from the registry split
%     S3 Auto-clear+staffing: 2 reviewers, autoClearRate from the registry split
%
%   autoClearRate for S2/S3 is DERIVED from the routing behaviour, not invented:
%   it is the observed fraction of cases the router auto-cleared in the active
%   registry (AUTO_CLEARED / all-routed). If the registry is empty it falls back
%   to a documented default (0.5) and that assumption is recorded in the params.
%
%   These are SIMULATION scenarios, not clinical projections.

    if nargin < 1 || isempty(cfg)
        cfg = netra.loadConfig();
    end

    latency = netra.util.latencyStats(cfg);        % measured where available
    autoClear = derivedAutoClearRate();

    sc = struct('name', {}, 'desc', {}, 'params', {});

    sc(1).name = "S1 Baseline";
    sc(1).desc = "1 reviewer, no auto-clear (every case reviewed)";
    sc(1).params = netra.sim.buildParams( ...
        struct('reviewers', 1, 'autoClearRate', 0), latency, cfg);

    sc(2).name = "S2 Auto-clear enabled";
    sc(2).desc = sprintf("1 reviewer, auto-clear %.0f%% (from routing split)", 100*autoClear);
    sc(2).params = netra.sim.buildParams( ...
        struct('reviewers', 1, 'autoClearRate', autoClear), latency, cfg);

    sc(3).name = "S3 Auto-clear + staffing";
    sc(3).desc = sprintf("2 reviewers, auto-clear %.0f%% (from routing split)", 100*autoClear);
    sc(3).params = netra.sim.buildParams( ...
        struct('reviewers', 2, 'autoClearRate', autoClear), latency, cfg);
end

% ------------------------------------------------------------------------
function r = derivedAutoClearRate()
%DERIVEDAUTOCLEARRATE  Observed AUTO_CLEARED fraction from the active registry.
    r = 0.5;                                        % documented fallback
    try
        T = netra.store.internalLoadRegistry();
        if ~isempty(T) && ismember('routingDecision', T.Properties.VariableNames)
            routed = sum(T.routingDecision == "AUTO_CLEARED" | ...
                         T.routingDecision == "REVIEW_QUEUE");
            if routed > 0
                r = sum(T.routingDecision == "AUTO_CLEARED") / routed;
            end
        end
    catch
        % keep fallback
    end
end
