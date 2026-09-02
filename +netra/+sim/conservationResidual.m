function [residual, relResidual] = conservationResidual(L)
%CONSERVATIONRESIDUAL  Flow-conservation residual of a capacity-model run.
%   [residual, relResidual] = netra.sim.conservationResidual(L) returns the
%   absolute and relative imbalance of the end-of-run mass balance:
%
%     cumArrived == cleared + reviewed + inReviewQueue + uploadBacklog
%                   + aiBacklog + pendingRecapture
%
%   residual is (LHS - sum of sinks); relResidual normalises it by the arrivals.
%   A well-wired model gives residual ~ 0 (floating-point dust). The Simulink
%   conservation test and the runtime guard both use this; a non-zero residual
%   means a signal is created or destroyed somewhere in the flow.
%
%   L may be the struct from netra.sim.numericalModel or the harmonised signal
%   struct netra.sim.runCapacity attaches to its SimulationOutput.

    arguments
        L (1,1) struct
    end

    sinks = L.cumClearedEnd + L.cumReviewedEnd + L.inQueueEnd + ...
        L.uploadBacklogEnd + L.aiBacklogEnd + L.pendingRecapture;
    residual = L.cumArrivedEnd - sinks;
    relResidual = residual / max(1, L.cumArrivedEnd);
end
