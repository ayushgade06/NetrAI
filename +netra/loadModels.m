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
        data = load(f);                    %#ok<NASGU> % must load without error
        models.files(end+1) = string(matFiles(k).name); %#ok<AGROW>
    end
end

% ------------------------------------------------------------------------
function d = localDefaultModelsDir()
%LOCALDEFAULTMODELSDIR  models/ next to the project root.
    here = fileparts(mfilename('fullpath'));   % +netra
    root = fileparts(here);                    % project root
    d = fullfile(root, 'models');
end
