function models = loadModels(modelsDir)
%LOADMODELS  Load NETRA model placeholders from models/.
%   models = netra.loadModels() loads the placeholder .mat files in the
%   project's models/ directory and returns a struct. In Phase 0 there are
%   no real networks; this returns clearly-marked placeholders so the
%   grading and xai stages have something to accept.
%
%   models = netra.loadModels(modelsDir) loads from an explicit directory.
%
%   The returned struct always carries models.isPlaceholder = true in
%   Phase 0. Later phases replace the .mat contents; the signature is frozen.

    arguments
        modelsDir (1,:) char = localDefaultModelsDir()
    end

    matFiles = dir(fullfile(modelsDir, '*.mat'));

    models = struct();
    models.isPlaceholder = true;
    models.loadedFrom    = string(modelsDir);
    models.files         = strings(1,0);
    models.hash          = "PLACEHOLDER";

    for k = 1:numel(matFiles)
        f = fullfile(matFiles(k).folder, matFiles(k).name);
        data = load(f);                    % must load without error
        models.files(end+1) = string(matFiles(k).name); %#ok<AGROW>

        % Phase 3: surface the trained quality classifier so
        % netra.quality.assess can take the trained path. quality_clf.mat stores
        % the model under variable `qmodel` (see training/train_quality.m).
        if strcmpi(matFiles(k).name, 'quality_clf.mat') && isfield(data, 'qmodel')
            models.quality = data.qmodel;
        end

        % Track D: surface the trained DR-grading CNN so netra.grading.classify
        % takes path A (real CNN). dr_grader.mat stores the network under `net`
        % and its metadata under `meta` (see training/train_grader.m). Its
        % presence flips isPlaceholder off and records the file hash for
        % traceability (every UI number traces to the model that produced it).
        if strcmpi(matFiles(k).name, 'dr_grader.mat') && isfield(data, 'net')
            models.grader      = data.net;
            models.isPlaceholder = false;
            models.hash        = localFileHash(f);
            if isfield(data, 'meta'), models.graderMeta = data.meta; end
        end

        % Track D: trained fusion model (referable-DR head over CNN probs +
        % lesion features). Optional; classify uses it only when useFusion is on.
        if strcmpi(matFiles(k).name, 'fusion.mat') && isfield(data, 'fusion')
            models.fusion = data.fusion;
        end
    end
end

% ------------------------------------------------------------------------
function h = localFileHash(f)
%LOCALFILEHASH  SHA-256 of a file's bytes (traceability), or "UNHASHED".
    try
        bytes = fileread(f);                       %#ok<NASGU>
        md = java.security.MessageDigest.getInstance('SHA-256');
        fid = fopen(f,'r'); raw = fread(fid, Inf, '*uint8'); fclose(fid);
        dig = typecast(md.digest(raw), 'uint8');
        h = string(sprintf('%02x', dig));
    catch
        h = "UNHASHED";
    end
end

% ------------------------------------------------------------------------
function d = localDefaultModelsDir()
%LOCALDEFAULTMODELSDIR  models/ next to the project root.
    here = fileparts(mfilename('fullpath'));   % +netra
    root = fileparts(here);                    % project root
    d = fullfile(root, 'models');
end
