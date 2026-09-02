classdef tConfig < matlab.unittest.TestCase
    %TCONFIG  Config loading and validation tests.

    properties
        Root
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.Root = fileparts(fileparts(mfilename('fullpath')));
        end
    end

    methods (Test)

        function allThreeFilesParse(tc)
            cfg = netra.loadConfig();
            tc.verifyClass(cfg.thresholds, 'struct');
            tc.verifyNotEmpty(cfg.routingRules);
            tc.verifyNotEmpty(cfg.phcRegistry);
        end

        function everyReferencedThresholdKeyExists(tc)
            % Scan +netra source for cfg.thresholds.<a>.<b> references and
            % verify each resolves. Guards against a stage reading a key the
            % JSON does not define.
            cfg = netra.loadConfig();
            src = tc.gatherSource(fullfile(tc.Root, '+netra'));
            keys = regexp(src, ...
                'cfg\.thresholds\.([A-Za-z_]\w*)\.([A-Za-z_]\w*)', 'tokens');
            tc_keys = unique(cellfun(@(t) [t{1} '.' t{2}], keys, ...
                'UniformOutput', false));
            tc.verifyNotEmpty(tc_keys, ...
                'Expected at least one cfg.thresholds reference in +netra.');
            for k = 1:numel(tc_keys)
                parts = strsplit(tc_keys{k}, '.');
                tc.verifyTrue( ...
                    isfield(cfg.thresholds, parts{1}) && ...
                    isfield(cfg.thresholds.(parts{1}), parts{2}), ...
                    sprintf('Referenced threshold missing from JSON: %s', ...
                    tc_keys{k}));
            end
        end

        function missingKeyProducesTypedError(tc)
            % Write a corrupted thresholds.json to a temp config dir and
            % confirm loadConfig raises NETRA:config:missingKey.
            tmp = tempname;
            mkdir(tmp);
            cleanup = onCleanup(@() rmdir(tmp, 's')); %#ok<NASGU>

            good = jsondecode(fileread( ...
                fullfile(tc.Root, 'config', 'thresholds.json')));
            good.grading = rmfield(good.grading, 'confidenceMin'); % remove key
            fid = fopen(fullfile(tmp, 'thresholds.json'), 'w');
            fwrite(fid, jsonencode(good));
            fclose(fid);

            % copy the other two valid files so only the key is the problem
            copyfile(fullfile(tc.Root,'config','routing_rules.json'), tmp);
            copyfile(fullfile(tc.Root,'config','phc_registry.json'), tmp);

            tc.verifyError(@() netra.loadConfig(tmp), 'NETRA:config:missingKey');
        end

        function phcRegistryMarkedFictional(tc)
            cfg = netra.loadConfig();
            % First element carries the _comment marker.
            raw = fileread(fullfile(tc.Root,'config','phc_registry.json'));
            tc.verifySubstring(lower(raw), 'fictional');
        end

    end

    methods (Access = private)
        function src = gatherSource(~, folder)
            % Concatenate all .m source under folder (recursively).
            files = dir(fullfile(folder, '**', '*.m'));
            parts = cell(1, numel(files));
            for k = 1:numel(files)
                parts{k} = fileread(fullfile(files(k).folder, files(k).name));
            end
            src = strjoin(parts, sprintf('\n'));
        end
    end
end
