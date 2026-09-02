function T = seedMockRegistry(outPath)
%SEEDMOCKREGISTRY  Generate the fictional mock case registry for the UI.
%
%   ALL DATA PRODUCED HERE IS FICTIONAL DEMO DATA WITH NO CLINICAL MEANING.
%   These are invented patients, grades, and review outcomes used only to
%   populate the NETRA dashboard and review queue during Phase 1 development.
%   Nothing here is a measurement, a model output, or a real screening result.
%
%   T = seedMockRegistry() writes data/mock/registry_seed.mat (a table named
%   'registry') and returns the table. (tools/ is added to the path by
%   startup_netra, so call it unqualified.)
%
%   T = seedMockRegistry(outPath) writes to an explicit path.
%
%   The table spans all ICDR grades, all routing decisions and urgencies, and
%   includes unreviewed cases so the queue has depth. Values are generated
%   deterministically (fixed rng seed) so the demo is reproducible.
%
%   Columns:
%     uid patientID phcID timestamp age eye qualityClass icdr confidence
%     ala routingDecision urgency flags reviewed reviewSeconds reviewerAgreed

    if nargin < 1
        here = fileparts(mfilename('fullpath'));       % tools/
        root = fileparts(here);
        outPath = fullfile(root, 'data', 'mock', 'registry_seed.mat');
    end

    rng(26038);                     % fixed seed: reproducible fictional data
    n = 40;

    phcIDs   = ["PHC001" "PHC002" "PHC003" "PHC004"];
    eyes     = ["OD" "OS"];
    qClasses = ["Good" "Borderline" "Ungradeable"];

    uid            = strings(n,1);
    patientID      = strings(n,1);
    phcID          = strings(n,1);
    timestamp      = NaT(n,1);
    age            = zeros(n,1);
    eye            = strings(n,1);
    qualityClass   = strings(n,1);
    icdr           = zeros(n,1);
    confidence     = zeros(n,1);
    ala            = zeros(n,1);
    routingDecision= strings(n,1);
    urgency        = strings(n,1);
    flags          = strings(n,1);
    reviewed       = false(n,1);
    reviewSeconds  = nan(n,1);
    reviewerAgreed = strings(n,1);   % "" | "Agreed" | "Overridden"

    baseTime = datetime(2026,9,2,8,0,0);   % fixed demo day (no Date.now here)

    for i = 1:n
        uid(i)       = sprintf("NETRA_MOCK_%03d", i);
        patientID(i) = sprintf("P%04d", 1000 + i);
        phcID(i)     = phcIDs(mod(i-1,4)+1);
        timestamp(i) = baseTime - minutes(15*(n-i));   % spread across the day
        age(i)       = 35 + mod(i*7, 45);              % 35..79
        eye(i)       = eyes(mod(i,2)+1);

        % Force coverage of edge cases in the first several rows, then spread.
        if i <= 3
            g = i - 1;                 % grades 0,1,2
        elseif i == 4
            g = 3;
        elseif i == 5
            g = 4;
        else
            g = mod(i,5);              % cycle 0..4
        end
        icdr(i) = g;

        % Two deliberately ungradeable cases.
        if any(i == [7 22])
            qualityClass(i) = "Ungradeable";
        elseif mod(i,6) == 0
            qualityClass(i) = "Borderline";
        else
            qualityClass(i) = "Good";
        end

        confidence(i) = round(0.55 + 0.4*rand(), 2);   % 0.55..0.95
        ala(i)        = round(0.30 + 0.6*rand(), 2);    % 0.30..0.90

        [routingDecision(i), urgency(i), flags(i)] = ...
            mockRoute(qualityClass(i), g, confidence(i), ala(i));

        % Some cases already reviewed, some pending (pending = queue depth).
        if routingDecision(i) == "REVIEW_QUEUE"
            reviewed(i) = rand() < 0.5;
        elseif routingDecision(i) == "AUTO_CLEARED"
            reviewed(i) = true;         % auto-cleared counts as resolved
        else
            reviewed(i) = false;        % recapture pending
        end

        if reviewed(i) && routingDecision(i) == "REVIEW_QUEUE"
            reviewSeconds(i)  = round(12 + 40*rand());
            if rand() < 0.8
                reviewerAgreed(i) = "Agreed";
            else
                reviewerAgreed(i) = "Overridden";
            end
        end
    end

    registry = table(uid, patientID, phcID, timestamp, age, eye, ...
        qualityClass, icdr, confidence, ala, routingDecision, urgency, ...
        flags, reviewed, reviewSeconds, reviewerAgreed);

    d = fileparts(outPath);
    if ~isfolder(d), mkdir(d); end
    save(outPath, 'registry');
    fprintf('seedMockRegistry: wrote %d fictional cases to %s\n', n, outPath);

    T = registry;
end

% ------------------------------------------------------------------------
function [decision, urgency, flag] = mockRoute(qClass, grade, conf, ala)
%MOCKROUTE  Mirror of netra.routing.decide, used only to label seed rows.
%   Kept local so the seeder does not depend on a live caseRecord. Order and
%   thresholds match config/routing_rules.json (confMin 0.6, alaLow 0.4).
    confMin = 0.6; alaLow = 0.4;
    flag = "";
    if qClass == "Ungradeable"
        decision = "RECAPTURE"; urgency = "None";
    elseif grade >= 4
        decision = "REVIEW_QUEUE"; urgency = "Urgent";
    elseif grade == 3
        decision = "REVIEW_QUEUE"; urgency = "Priority";
    elseif grade == 2
        decision = "REVIEW_QUEUE"; urgency = "Routine";
    elseif conf < confMin
        decision = "REVIEW_QUEUE"; urgency = "Routine"; flag = "Uncertain";
    elseif ala < alaLow
        decision = "REVIEW_QUEUE"; urgency = "Routine"; flag = "LowAgreement";
    else
        decision = "AUTO_CLEARED"; urgency = "None";
    end
end
