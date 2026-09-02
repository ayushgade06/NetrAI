function cfg = loadConfig(configDir)
%LOADCONFIG  Load and validate NETRA JSON configuration.
%   cfg = netra.loadConfig() loads thresholds.json, routing_rules.json and
%   phc_registry.json from the project's config/ directory and returns a
%   single validated struct with fields:
%       cfg.thresholds   (struct)
%       cfg.routingRules (struct array)
%       cfg.phcRegistry  (struct array)
%
%   cfg = netra.loadConfig(configDir) loads from an explicit directory
%   (used by tests to point at a corrupted temp copy).
%
%   Every required threshold key is checked. A missing key raises
%   NETRA:config:missingKey naming the exact dotted path; nothing is ever
%   silently defaulted.
%
%   Errors:
%     NETRA:config:fileNotFound  a config file is absent.
%     NETRA:config:parseError    a config file is not valid JSON.
%     NETRA:config:missingKey    a required threshold key is absent.

    arguments
        configDir (1,:) char = localDefaultConfigDir()
    end

    cfg = struct();
    cfg.thresholds   = readJson(fullfile(configDir, 'thresholds.json'));
    cfg.routingRules = readJson(fullfile(configDir, 'routing_rules.json'));
    cfg.phcRegistry  = readJson(fullfile(configDir, 'phc_registry.json'));

    % Validate every threshold key the project depends on. This list is the
    % contract: if code needs a new threshold, add it here AND in the JSON.
    requiredKeys = { ...
        'quality.focusMin', ...
        'quality.illumUniformityMin', ...
        'quality.fovCompletenessMin', ...
        'quality.contrastMin', ...
        'quality.gradeableScoreMin', ...
        'quality.borderlineScoreMin', ...
        'preproc.claheClipDefault', ...
        'preproc.claheClipMax', ...
        'preproc.targetSize', ...
        'lesions.maAreaMax', ...
        'lesions.maEccentricityMax', ...
        'lesions.maCircularityMin', ...
        'lesions.exMinArea', ...
        'lesions.odDilationPx', ...
        'grading.referableThreshold', ...
        'grading.confidenceMin', ...
        'grading.temperature', ...
        'xai.gradcamPercentile', ...
        'xai.lesionDilationPx', ...
        'xai.alaLowThreshold', ...
        'structures.discDiameterRatioFovea'};

    for k = 1:numel(requiredKeys)
        assertKey(cfg.thresholds, requiredKeys{k});
    end

    % Also expose a config hash so downstream provenance can record it.
    cfg.configHash = string(localHashStruct(cfg.thresholds));
end

% ------------------------------------------------------------------------
function s = readJson(path)
%READJSON  Read and decode a JSON file with NETRA-prefixed errors.
    if ~isfile(path)
        error('NETRA:config:fileNotFound', 'Config file not found: %s', path);
    end
    txt = fileread(path);
    try
        s = jsondecode(txt);
    catch ME
        error('NETRA:config:parseError', ...
            'Failed to parse JSON "%s": %s', path, ME.message);
    end
end

function assertKey(s, dottedKey)
%ASSERTKEY  Throw NETRA:config:missingKey unless the dotted key resolves.
    parts = strsplit(dottedKey, '.');
    node = s;
    for i = 1:numel(parts)
        if ~isstruct(node) || ~isfield(node, parts{i})
            error('NETRA:config:missingKey', ...
                'Required config key missing: thresholds.%s', dottedKey);
        end
        node = node.(parts{i});
    end
end

function d = localDefaultConfigDir()
%LOCALDEFAULTCONFIGDIR  config/ next to the project root.
    here = fileparts(mfilename('fullpath'));   % +netra
    root = fileparts(here);                    % project root
    d = fullfile(root, 'config');
end

function h = localHashStruct(s)
%LOCALHASHSTRUCT  Cheap stable-ish hash of a struct via its JSON encoding.
    txt = jsonencode(s);
    bytes = uint8(txt);
    h = sprintf('%08X', mod(sum(double(bytes) .* (1:numel(bytes))), 2^32));
end
