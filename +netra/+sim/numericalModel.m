function L = numericalModel(p)
%NUMERICALMODEL  Discrete-time district screening flow/queue recurrence.
%   L = netra.sim.numericalModel(p) integrates the same day-step difference
%   equations the Simulink model netra_capacity.slx implements, and returns a
%   struct of logged daily signals. It is BOTH the MATLAB-only fallback (when
%   Simulink is unavailable) and the reference the Simulink block wiring is
%   built to reproduce, so the conservation and sanity tests hold identically
%   for either backend.
%
%   Model (one step = one day, per docs/simulink_model.md):
%     arrivals   ~ mean daily images * (1 + variability * zero-mean noise)
%     recapture  : rejected images retry next day; a fraction succeed and rejoin
%     upload cap = bandwidth*3600*hours / (imageMB*8)         [images/day]
%     AI cap     = nodes*3600*hours / inferenceSec            [images/day]
%       - an AI backlog integrator (floored at 0) carries unprocessed load over
%     routing    : autoClearRate of processed images auto-clear; the rest queue
%     review cap = reviewers*hours*3600 / reviewSec           [cases/day]
%       - a review queue integrator (floored at 0, MinMax) drains at the cap
%
%   Logged fields (all 1 x simDays unless noted):
%     dailyArrivals dailyProcessed reviewQueueDepth cumulativeArrived
%     cumulativeCleared reviewerUtilisation meanWaitDays p95WaitDays
%     autoClearedCount reviewedCount recaptureCount
%     days (1 x simDays time vector)
%   plus scalar conservation terms used by the tests:
%     inQueueEnd uploadBacklogEnd aiBacklogEnd
%
%   Determinism: arrival noise uses a fixed seed derived from the parameters so
%   a given parameter set always yields the same curve (reproducible demo).
%   These are SIMULATION outputs, not measurements.

    arguments
        p (1,1) struct
    end

    N = max(1, round(p.simDays));
    hours = p.reviewerHoursPerDay;

    % Mean daily image inflow over the camp calendar.
    imagesPerYear = p.annualPatients * p.imagesPerPatient;
    meanDaily = imagesPerYear / max(1, p.campDaysPerYear);

    % Per-day service capacities (images or cases per day).
    uploadCap = (p.bandwidthMbps * 3600 * hours) / (p.imageSizeMB * 8);
    aiCap     = (p.processingNodes * 3600 * hours) / max(1e-9, p.inferenceSecPerImage);
    reviewCap = (p.reviewers * hours * 3600) / max(1e-9, p.reviewSecPerCase);

    % Deterministic zero-mean arrival noise (reproducible per parameter set).
    seed = mod(round(1e3*meanDaily + 7*p.simDays + 13*p.arrivalVariability*100), 2^31);
    rs = RandStream('mt19937ar', 'Seed', seed);
    noise = (rs.rand(1, N) - 0.5) * 2;             % in [-1, 1]

    % State carried across days.
    pendingRecapture = 0;    % rejected images awaiting a retry
    uploadBacklog    = 0;    % images captured+recaptured but not yet uploaded
    aiBacklog        = 0;    % images uploaded but not yet AI-processed
    reviewQueue      = 0;    % cases routed to review, not yet reviewed

    % Cumulative sinks (for conservation).
    cumArrived   = 0;   % all NEW arrivals (first-time captures) entered
    cumRecapture = 0;   % successful recaptures rejoined (re-entries)
    cumRejected  = 0;   % images that failed quality (left as reject, may retry)
    cumCleared   = 0;   % auto-cleared cases
    cumReviewed  = 0;   % reviewed cases

    L.dailyArrivals       = zeros(1, N);
    L.dailyProcessed      = zeros(1, N);
    L.reviewQueueDepth    = zeros(1, N);
    L.cumulativeArrived   = zeros(1, N);
    L.cumulativeCleared   = zeros(1, N);
    L.reviewerUtilisation = zeros(1, N);
    L.autoClearedCount    = zeros(1, N);
    L.reviewedCount       = zeros(1, N);
    L.recaptureCount      = zeros(1, N);

    reviewedCumForWait = 0;      % for a simple Little's-law wait estimate
    waitAccum = zeros(1, N);

    for d = 1:N
        % --- arrivals (first-time captures) -----------------------------
        arr = meanDaily * (1 + p.arrivalVariability * noise(d));
        arr = max(0, arr);
        cumArrived = cumArrived + arr;

        % --- quality gate: reject a fraction; rejects retry next day ----
        rejected = arr * p.qualityRejectRate;
        passed   = arr - rejected;
        cumRejected = cumRejected + rejected;

        % Recaptures that succeeded today rejoin the passed stream.
        recapSucc = pendingRecapture * p.recaptureSuccessRate;
        cumRecapture = cumRecapture + recapSucc;
        % Remaining rejects (today's + carried failures) wait for next day.
        pendingRecapture = rejected + pendingRecapture * (1 - p.recaptureSuccessRate);
        L.recaptureCount(d) = recapSucc;

        inflowToUpload = passed + recapSucc;

        % --- bandwidth-limited upload (integrator + saturation) ---------
        uploadBacklog = uploadBacklog + inflowToUpload;
        uploaded = min(uploadBacklog, uploadCap);
        uploadBacklog = max(0, uploadBacklog - uploaded);

        % --- AI processing (saturation + backlog integrator, floor 0) ---
        aiBacklog = aiBacklog + uploaded;
        processed = min(aiBacklog, aiCap);
        aiBacklog = max(0, aiBacklog - processed);
        L.dailyProcessed(d) = processed;

        % --- routing split ---------------------------------------------
        autoCleared = processed * p.autoClearRate;
        toReview    = processed - autoCleared;
        cumCleared  = cumCleared + autoCleared;
        L.autoClearedCount(d) = autoCleared;

        % --- review queue (integrator, drain at reviewCap, MinMax floor)-
        reviewQueue = reviewQueue + toReview;
        reviewed = min(reviewQueue, reviewCap);
        reviewQueue = max(0, reviewQueue - reviewed);      % never negative
        cumReviewed = cumReviewed + reviewed;
        L.reviewedCount(d) = reviewed;

        % --- logged states ---------------------------------------------
        % cumulativeArrived counts each image ONCE (first-time captures only).
        % A recapture is a re-entry of an already-arrived image, not a new
        % arrival, so it is NOT added here - that keeps the conservation
        % identity below exact (see cumRecapture used only for the KPI).
        L.dailyArrivals(d)    = arr;
        L.reviewQueueDepth(d) = reviewQueue;
        L.cumulativeArrived(d)   = cumArrived;                  % unique arrivals
        L.cumulativeCleared(d)   = cumCleared;
        L.reviewerUtilisation(d) = min(1, reviewed / max(1e-9, reviewCap));

        % Wait estimate (Little's law): queue depth / throughput, in days.
        reviewedCumForWait = reviewedCumForWait + reviewed;
        thru = reviewedCumForWait / d;
        waitAccum(d) = reviewQueue / max(1e-9, thru);
    end

    % Wait summaries (over the run).
    L.meanWaitDays = mean(waitAccum);
    L.p95WaitDays  = prctile95(waitAccum);
    L.days = (1:N);

    % Conservation bookkeeping (end-of-run terms). Every image that ever
    % arrived (counted once) is, at end of run, in exactly one place:
    %   cumArrived == cleared + reviewed + inReviewQueue + uploadBacklog
    %                 + aiBacklog + pendingRecapture
    % netra.sim.conservationResidual asserts this to within tolerance; a
    % non-zero residual means a flow is created or destroyed -> wiring bug.
    L.inQueueEnd        = reviewQueue;
    L.uploadBacklogEnd  = uploadBacklog;
    L.aiBacklogEnd      = aiBacklog;
    L.pendingRecapture  = pendingRecapture;
    L.cumClearedEnd     = cumCleared;
    L.cumReviewedEnd    = cumReviewed;
    L.cumArrivedEnd     = cumArrived;
    L.cumRecaptureEnd   = cumRecapture;        % re-entries (KPI only, not a sink)
end

% ------------------------------------------------------------------------
function q = prctile95(v)
    v = sort(v(:)); n = numel(v);
    if n == 1, q = v(1); return; end
    rank = 0.95*(n-1) + 1; lo = floor(rank); hi = ceil(rank);
    if lo == hi, q = v(lo); else, q = v(lo) + (rank-lo)*(v(hi)-v(lo)); end
end
