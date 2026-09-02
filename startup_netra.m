function startup_netra()
%STARTUP_NETRA  Initialise the NETRA environment for the current session.
%   startup_netra() adds the project root to the MATLAB path, verifies the
%   config loads, and prints a toolbox-availability table. It is the ONLY
%   place in the project that touches the path (stages never call addpath).
%
%   Run this once per session before using netra.* functions:
%     startup_netra
%     cr = netra.runPipeline(netra.newCaseRecord('data/demo/sample01.jpg'));
%
%   Missing toolboxes produce a WARNING, not an error: Phase 0 needs only
%   base MATLAB.

    root = fileparts(mfilename('fullpath'));
    addpath(root);                       % +netra package + NETRA_App live here
    addpath(fullfile(root, 'tools'));    % seedMockRegistry (Phase 1)

    fprintf('NETRA startup\n');
    fprintf('  project root : %s\n', root);
    fprintf('  MATLAB       : %s\n', version('-release'));

    % --- config sanity ---------------------------------------------------
    try
        cfg = netra.loadConfig();
        fprintf('  config       : loaded OK (%d routing rules, %d PHCs)\n', ...
            numel(cfg.routingRules), numel(cfg.phcRegistry) - 1);
    catch ME
        warning('NETRA:startup:config', ...
            'Config failed to load: %s (%s)', ME.message, ME.identifier);
    end

    % --- toolbox availability table --------------------------------------
    toolboxes = { ...
        'Image Processing Toolbox',            'image_toolbox'; ...
        'Computer Vision Toolbox',             'video_and_image_blockset'; ...
        'Deep Learning Toolbox',               'neural_network_toolbox'; ...
        'Statistics and Machine Learning Toolbox', 'statistics_toolbox'; ...
        'Simulink',                            'simulink'};

    fprintf('\n  Toolbox availability:\n');
    fprintf('  %-42s %-10s\n', 'Toolbox', 'Status');
    fprintf('  %-42s %-10s\n', repmat('-',1,42), repmat('-',1,10));
    anyMissing = false;
    for k = 1:size(toolboxes,1)
        present = license('test', toolboxes{k,2}) == 1;
        statusStr = ternary(present, 'present', 'MISSING');
        fprintf('  %-42s %-10s\n', toolboxes{k,1}, statusStr);
        anyMissing = anyMissing || ~present;
    end
    fprintf('\n');

    if anyMissing
        warning('NETRA:startup:toolbox', ...
            ['One or more optional toolboxes are missing. Phase 0 needs ', ...
             'only base MATLAB, but later phases will require them.']);
    end

    % --- registry hint (Phase 1 mock seed + Phase 2 real registry) -------
    seed    = fullfile(root, 'data', 'mock', 'registry_seed.mat');
    realReg = fullfile(root, 'data', 'registry.mat');
    if isfile(realReg)
        fprintf('  case store   : real registry.mat present (ingested cases)\n');
    elseif isfile(seed)
        fprintf('  case store   : no real cases yet; mock seed present (demo dashboard)\n');
    else
        fprintf(['  case store   : empty. Run  seedMockRegistry  for a demo ', ...
                 'dashboard, or ingest images via the app / batchIngest.\n']);
    end

    fprintf('\nNETRA ready.  Launch the UI with:  app = NETRA_App;\n');
    fprintf('(Dev verdict override: app = NETRA_App(''DevMode'', true);)\n');
end

% ------------------------------------------------------------------------
function out = ternary(cond, a, b)
%TERNARY  Inline conditional value (no branch statement clutter).
    if cond
        out = a;
    else
        out = b;
    end
end
