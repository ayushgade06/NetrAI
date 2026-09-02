function logReview(uid, action, finalGrade, reviewerID, seconds, note, cfg)
%LOGREVIEW  Persist an ophthalmologist review decision to the case registry.
%   netra.store.logReview(uid, action, finalGrade, reviewerID, seconds, note, cfg)
%   records a reviewer's decision for case UID:
%     - marks the registry row reviewed = true
%     - stores reviewSeconds = seconds
%     - stores reviewerAgreed = "Agreed" (action "Confirm") or "Overridden"
%       (action "Override"/"Ungradeable"); "Skip" leaves the row UNreviewed
%     - if a per-case case.mat exists, writes action/finalGrade/reviewerID/
%       seconds/note/timestamp into cr.review and re-saves that case
%
%   The row is updated IN PLACE in whichever registry is currently active
%   (the real data/registry.mat when it has rows, otherwise the committed mock
%   seed data/mock/registry_seed.mat), preserving that file's schema so both
%   the fresh-clone demo (mock seed) and a live ingested session (real
%   registry) log reviews correctly. Only +store/+report touch disk.
%
%   "Skip" is a non-decision: it advances the queue without recording an
%   outcome, so it does not mark the row reviewed and does not touch audit
%   agreement. Elapsed time for a skip is still not persisted as a review.
%
%   Errors:
%     NETRA:store:reviewNoUid   uid is empty.
%   A uid absent from the active registry is a no-op on the registry (the
%   case.mat, if present, is still updated) - the queue simply had a stale row.

    arguments
        uid        (1,:) char
        action     (1,:) char
        finalGrade (1,1) double
        reviewerID (1,:) char
        seconds    (1,1) double
        note       (1,:) char = ''
        cfg        (1,1) struct = struct() %#ok<INUSA>
    end

    if isempty(uid)
        error('NETRA:store:reviewNoUid', 'logReview requires a non-empty uid.');
    end

    agreed = agreedLabel(action);          % "", "Agreed" or "Overridden"
    isDecision = strlength(agreed) > 0;    % Skip -> not a decision

    % --- 1. update the active registry row (in its own schema) -----------
    [regPath, T] = activeRegistry();
    if ~isempty(T) && ismember('uid', T.Properties.VariableNames)
        idx = find(T.uid == string(uid), 1);
        if ~isempty(idx) && isDecision
            T.reviewed(idx)      = true;
            T.reviewSeconds(idx) = seconds;
            if ismember('reviewerAgreed', T.Properties.VariableNames)
                T.reviewerAgreed(idx) = agreed;
            end
            registry = T; %#ok<NASGU>
            d = fileparts(regPath);
            if ~isfolder(d), mkdir(d); end
            % builtin: sibling +store/save.m and +store/load.m would otherwise
            % shadow the bare save/load inside this package.
            builtin('save', regPath, 'registry');
        end
    end

    % --- 2. update the per-case caseRecord if it was persisted -----------
    caseFile = fullfile(netra.store.storeRoot(), 'data', 'cases', uid, 'case.mat');
    if isfile(caseFile)
        S = builtin('load', caseFile, 'cr');
        if isfield(S, 'cr') && isstruct(S.cr)
            cr = S.cr;
            cr.review.action     = string(action);
            cr.review.finalGrade = finalGrade;
            cr.review.reviewerID = string(reviewerID);
            cr.review.seconds    = seconds;
            cr.review.note       = string(note);
            cr.review.timestamp  = datetime('now');
            builtin('save', caseFile, 'cr');
        end
    end
end

% ------------------------------------------------------------------------
function lbl = agreedLabel(action)
%AGREEDLABEL  Map a review action to the registry's reviewerAgreed label.
    switch string(action)
        case "Confirm"
            lbl = "Agreed";
        case {"Override", "Ungradeable"}
            lbl = "Overridden";
        otherwise                      % "Skip" or unknown -> non-decision
            lbl = "";
    end
end

function [regPath, T] = activeRegistry()
%ACTIVEREGISTRY  Path + table of the registry the queue is currently showing.
%   Prefers the real registry when it has rows; else the mock seed. Mirrors
%   netra.store.internalLoadRegistry's precedence so logReview updates exactly
%   the file the review queue was populated from.
    root = netra.store.storeRoot();
    realPath = fullfile(root, 'data', 'registry.mat');
    R = netra.store.registry();
    if ~isempty(R)
        regPath = realPath; T = R; return;
    end
    regPath = fullfile(root, 'data', 'mock', 'registry_seed.mat');
    T = netra.store.internalLoadRegistry(regPath);
end
