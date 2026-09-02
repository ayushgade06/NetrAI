function save(cr, cfg)
%SAVE  Persist a caseRecord to the on-disk case store.  [Phase 2 - REAL]
%   netra.store.save(cr, cfg) writes:
%     data/cases/<uid>/case.mat      the full caseRecord
%     data/cases/<uid>/original.png  the raw image (if cr.img.raw is present)
%   and appends-or-updates the row for <uid> in data/registry.mat.
%
%   CONTRACT:
%     - Reads the caseRecord; returns nothing. Only +store/+report touch disk.
%     - cr.timing.store / cr.provenance.store are set by runPipeline, not here.
%
%   ATOMICITY: the registry is written to a temp file in the same folder and
%   then RENAMED over the real file (movefile 'f'). A crash mid-write leaves
%   the previous registry.mat intact - never a half-written table. If the
%   rename fails, the previous registry is restored from a backup and the
%   error is surfaced (NETRA:store:registryWrite). Tested in tStorePersistence.
%
%   Saving the same uid twice UPDATES its row (keyed on uid), never appends a
%   duplicate.

    arguments
        cr  (1,1) struct
        cfg (1,1) struct %#ok<INUSA>
    end

    root = localRoot();
    uid  = char(cr.meta.uid);
    if isempty(uid)
        error('NETRA:store:noUid', 'Cannot save a case with an empty meta.uid.');
    end
    caseDir = fullfile(root, 'data', 'cases', uid);

    % --- per-case folder -------------------------------------------------
    if ~isfolder(caseDir)
        [okMk, msg] = mkdir(caseDir);
        if ~okMk
            error('NETRA:store:mkdirFailed', ...
                'Cannot create case folder "%s": %s', caseDir, msg);
        end
    end

    % case.mat: temp then rename (same atomic pattern as the registry).
    caseTmp   = [tempname(caseDir) '.mat'];
    caseFinal = fullfile(caseDir, 'case.mat');
    try
        localSaveCase(caseTmp, cr);
        localRename(caseTmp, caseFinal);
    catch ME
        if isfile(caseTmp), delete(caseTmp); end
        error('NETRA:store:caseWrite', ...
            'Failed to write case.mat for %s: %s', uid, ME.message);
    end

    % original.png (only if we actually have pixels).
    if ~isempty(cr.img.raw)
        try
            imwrite(cr.img.raw, fullfile(caseDir, 'original.png'));
        catch ME
            warning('NETRA:store:pngWrite', ...
                'Could not write original.png for %s: %s', uid, ME.message);
        end
    end

    % --- registry (atomic upsert) ---------------------------------------
    localUpsertRegistry(root, cr);
end

% ------------------------------------------------------------------------
function localUpsertRegistry(root, cr)
%LOCALUPSERTREGISTRY  Append/update the row for cr in data/registry.mat, atomically.
    regPath = fullfile(root, 'data', 'registry.mat');
    regDir  = fileparts(regPath);
    if ~isfolder(regDir), mkdir(regDir); end

    T   = netra.store.registry();           % current real registry (real schema)
    row = localRowFromCase(cr);             % single-row table from this case

    if ~isempty(T) && any(T.uid == cr.meta.uid)
        idx = find(T.uid == cr.meta.uid, 1);
        T(idx, :) = row;
    else
        T = [T; row];
    end

    tmp = [tempname(regDir) '.mat'];
    bak = [regPath '.bak'];
    registry = T; %#ok<NASGU>
    try
        builtin('save', tmp, 'registry');
    catch ME
        if isfile(tmp), delete(tmp); end
        error('NETRA:store:registryWrite', ...
            'Failed to write temp registry: %s', ME.message);
    end

    hadPrev = isfile(regPath);
    try
        if hadPrev, copyfile(regPath, bak, 'f'); end
        localRename(tmp, regPath);
        if isfile(bak), delete(bak); end
    catch ME
        if hadPrev && ~isfile(regPath) && isfile(bak)
            localRename(bak, regPath);       % restore previous registry
        end
        if isfile(tmp), delete(tmp); end
        error('NETRA:store:registryWrite', ...
            'Failed to update registry.mat (previous registry preserved): %s', ...
            ME.message);
    end
end

function localSaveCase(path, cr) %#ok<INUSD>
    builtin('save', path, 'cr');             % variable name in the file is 'cr'
end

function localRename(src, dst)
    [ok, msg] = movefile(src, dst, 'f');
    if ~ok
        error('NETRA:store:rename', 'Rename "%s" -> "%s" failed: %s', src, dst, msg);
    end
end

function r = localRoot()
    r = netra.store.storeRoot();               % overridable via NETRA_STORE_ROOT
end

function row = localRowFromCase(cr)
%LOCALROWFROMCASE  Flatten a caseRecord into one real-schema registry row.
%   Columns (superset of the Phase 1 mock registry - the Phase 1 names are
%   kept so the Dashboard/queue keep working):
%     uid patientID phcID timestamp age dmYears eye imagePath imageHash
%     qualityClass qualityScore icdr confidence ala routingDecision urgency
%     flags reviewed reviewSeconds reviewerAgreed provenanceSummary
%
%   Grading-related columns come from whatever stages produced them; in Phase
%   2 grading/xai are still MOCK, and provenanceSummary records that so the
%   Dashboard can flag the row. A row whose provenanceSummary contains "MOCK"
%   for grading is a demo grade, not a measurement.

    flags = "";
    if ~isempty(cr.routing.flags)
        flags = strjoin(cr.routing.flags, ",");
    end

    row = table( ...
        string(cr.meta.uid), ...
        string(cr.meta.patientID), ...
        string(cr.meta.phcID), ...
        cr.meta.timestamp, ...
        double(cr.meta.age), ...
        double(cr.meta.dmYears), ...
        string(cr.meta.eye), ...
        string(cr.meta.imagePath), ...
        string(cr.meta.imageHash), ...
        string(cr.quality.class), ...
        double(cr.quality.score), ...
        double(cr.grade.icdr), ...
        double(cr.grade.confidence), ...
        double(cr.xai.agreementScore), ...
        string(cr.routing.decision), ...
        string(cr.routing.urgency), ...
        string(flags), ...
        false, ...
        NaN, ...
        "", ...
        localProvSummary(cr), ...
        'VariableNames', netra.store.registry().Properties.VariableNames);
end

function s = localProvSummary(cr)
%LOCALPROVSUMMARY  Compact "stage=PROV;..." string over the pipeline stages.
    stages = fieldnames(cr.provenance);
    parts = strings(1, numel(stages));
    for k = 1:numel(stages)
        parts(k) = stages{k} + "=" + string(cr.provenance.(stages{k}));
    end
    s = strjoin(parts, ";");
end
