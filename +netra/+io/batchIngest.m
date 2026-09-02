function results = batchIngest(folderPath, meta, cfg, progressFcn)
%BATCHINGEST  Ingest every supported image in a folder into the case store.
%   results = netra.io.batchIngest(folderPath, meta, cfg, progressFcn)
%
%   For each supported image found (non-recursively) in folderPath:
%     1. quarantine guard (assertNotQuarantined) on the folder;
%     2. load -> validate -> plausibility check;
%     3. build a caseRecord with the REAL pixels in cr.img.raw;
%     4. run the pipeline (FOV mask + crop are real; grading etc. still mock);
%     5. persist via netra.store.save.
%   A single bad file NEVER aborts the batch - it is logged as "error" or
%   "rejected" and the loop continues.
%
%   Inputs:
%     folderPath  : char/string directory to scan.
%     meta        : struct of shared metadata for every case in this batch.
%                   Recognised: phcID, eye ("OD"|"OS"|"alternate"), age,
%                   dmYears, patientPrefix. seq is assigned per file (1..N).
%     cfg         : config struct (netra.loadConfig()).
%     progressFcn : optional function handle called as
%                   progressFcn(i, n, filename) before each file, so a UI can
%                   drive a uiprogressdlg. Pass [] for none.
%
%   Returns a table with one row per file:
%     file (string) status ("ingested"|"rejected"|"error") uid (string)
%     reason (string) elapsedSeconds (double)

    arguments
        folderPath  (1,:) char
        meta        (1,1) struct = struct()
        cfg         (1,1) struct = netra.loadConfig()
        progressFcn = []
    end

    netra.io.assertNotQuarantined(folderPath);

    if ~isfolder(folderPath)
        error('NETRA:io:folderNotFound', 'Folder not found: %s', folderPath);
    end

    files = listSupported(folderPath, cfg);
    n = numel(files);

    fileCol    = strings(n,1);
    statusCol  = strings(n,1);
    uidCol     = strings(n,1);
    reasonCol  = strings(n,1);
    elapsedCol = zeros(n,1);

    phcID = string(getfielddef(meta, 'phcID', "PHC000"));
    eyeMode = string(getfielddef(meta, 'eye', "OD"));

    for i = 1:n
        f = files{i};
        [~, base, ext] = fileparts(f);
        fileCol(i) = string([base ext]);
        if ~isempty(progressFcn)
            try, progressFcn(i, n, [base ext]); catch, end
        end

        tStart = tic;
        try
            [img, ~] = netra.io.loadImage(f);

            [okV, reasonV] = netra.io.validateImage(img, cfg);
            if ~okV
                statusCol(i) = "rejected";
                reasonCol(i) = reasonV;
                elapsedCol(i) = toc(tStart);
                continue;
            end

            [isFundus, score, detail] = netra.io.isPlausibleFundus(img, cfg);
            if ~isFundus
                statusCol(i) = "rejected";
                reasonCol(i) = plausibilityReason(score, detail, cfg);
                elapsedCol(i) = toc(tStart);
                continue;
            end

            % Build the case with real pixels and per-file metadata.
            eye = resolveEye(eyeMode, i);
            caseMeta = struct( ...
                'patientID', string(getfielddef(meta,'patientPrefix',"BATCH")) + sprintf("%04d", i), ...
                'phcID',   phcID, ...
                'age',     getfielddef(meta, 'age', NaN), ...
                'dmYears', getfielddef(meta, 'dmYears', NaN), ...
                'eye',     eye, ...
                'seq',     i);

            cr = netra.newCaseRecord(f, caseMeta);
            cr.img.raw = img;                        % real pixels drive real FOV/crop
            cr = netra.runPipeline(cr, cfg, netra.loadModels());

            statusCol(i) = "ingested";
            uidCol(i)    = cr.meta.uid;
            reasonCol(i) = "";
        catch ME
            statusCol(i) = "error";
            reasonCol(i) = string(ME.identifier) + ": " + string(ME.message);
        end
        elapsedCol(i) = toc(tStart);
    end

    results = table(fileCol, statusCol, uidCol, reasonCol, elapsedCol, ...
        'VariableNames', {'file','status','uid','reason','elapsedSeconds'});
end

% ------------------------------------------------------------------------
function files = listSupported(folderPath, cfg)
%LISTSUPPORTED  Absolute paths of files with a supported extension.
    exts = lower(string(cfg.thresholds.io.supportedFormats)); % e.g. ".jpg"
    d = dir(folderPath);
    files = {};
    for k = 1:numel(d)
        if d(k).isdir, continue; end
        [~, ~, e] = fileparts(d(k).name);
        if ismember(lower(string(e)), exts)
            files{end+1} = fullfile(folderPath, d(k).name); %#ok<AGROW>
        end
    end
    files = sort(files);
end

function eye = resolveEye(mode, i)
%RESOLVEEYE  Fixed OD/OS, or alternate OD,OS,OD,... when mode=="alternate".
    if mode == "alternate"
        eyes = ["OD","OS"];
        eye = eyes(mod(i-1,2)+1);
    elseif ismember(mode, ["OD","OS"])
        eye = mode;
    else
        eye = "OD";
    end
end

function s = plausibilityReason(score, detail, cfg)
%PLAUSIBILITYREASON  Name the weakest sub-check so a rejection is specific.
    names  = ["near-black border", "circular bright region", "red-channel dominance"];
    scores = [detail.borderScore, detail.circleScore, detail.redScore];
    [~, worst] = min(scores);
    s = sprintf(...
        "Not a plausible fundus (score %.2f < %.2f). Weakest cue: %s (%.2f).", ...
        score, cfg.thresholds.io.fundusPlausibilityMin, names(worst), scores(worst));
end

function v = getfielddef(s, f, d)
    if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
