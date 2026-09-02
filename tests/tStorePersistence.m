classdef tStorePersistence < matlab.unittest.TestCase
    %TSTOREPERSISTENCE  Tests for the REAL store: save/load/registry.
    %   Isolated via NETRA_STORE_ROOT so nothing here touches the real
    %   data/registry.mat or the committed mock seed.

    properties
        Cfg
        Root        % throwaway store root
        PrevEnv
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.Cfg = netra.loadConfig();
            tc.PrevEnv = getenv('NETRA_STORE_ROOT');
            tc.Root = tempname; mkdir(fullfile(tc.Root, 'data'));
            setenv('NETRA_STORE_ROOT', tc.Root);
        end
    end
    methods (TestClassTeardown)
        function teardown(tc)
            setenv('NETRA_STORE_ROOT', tc.PrevEnv);
            if isfolder(tc.Root), rmdir(tc.Root, 's'); end
        end
    end

    methods (TestMethodSetup)
        function freshRegistry(tc)
            % Start each test from an empty store.
            reg = fullfile(tc.Root, 'data', 'registry.mat');
            if isfile(reg), delete(reg); end
            cdir = fullfile(tc.Root, 'data', 'cases');
            if isfolder(cdir), rmdir(cdir, 's'); end
        end
    end

    methods (Test)

        function saveThenLoadRoundTrips(tc)
            cr = tc.makeCase("PHC001", "OD", 1);
            netra.store.save(cr, tc.Cfg);
            back = netra.store.load(char(cr.meta.uid), tc.Cfg);
            tc.verifyEqual(back.meta.uid, cr.meta.uid);
            tc.verifyEqual(back.meta.imageHash, cr.meta.imageHash);
            tc.verifyEqual(back.meta.patientID, cr.meta.patientID);
            tc.verifyEqual(size(back.img.raw), size(cr.img.raw));
            tc.verifyEqual(back.quality.fovCompleteness, cr.quality.fovCompleteness);
        end

        function eachSaveAddsExactlyOneRow(tc)
            n0 = height(netra.store.registry());
            netra.store.save(tc.makeCase("PHC001","OD",1), tc.Cfg);
            netra.store.save(tc.makeCase("PHC001","OD",2), tc.Cfg);
            netra.store.save(tc.makeCase("PHC001","OD",3), tc.Cfg);
            tc.verifyEqual(height(netra.store.registry()), n0 + 3);
        end

        function sameUidUpdatesNotDuplicates(tc)
            cr = tc.makeCase("PHC001","OD",7);
            netra.store.save(cr, tc.Cfg);
            h1 = height(netra.store.registry());
            % Re-save the SAME uid with a changed field.
            cr.meta.patientID = "CHANGED";
            netra.store.save(cr, tc.Cfg);
            T = netra.store.registry();
            tc.verifyEqual(height(T), h1);                       % no new row
            row = T(T.uid == cr.meta.uid, :);
            tc.verifyEqual(row.patientID, "CHANGED");            % updated in place
        end

        function interruptedSaveLeavesPreviousRegistryIntact(tc)
            % Save a good case, then force the NEXT save's registry swap to
            % fail and verify the previous registry survives unchanged and the
            % error surfaces as NETRA:store:registryWrite.
            %
            % Injection: make data/ read-only so the temp-write / rename step
            % cannot land. This is portable (fopen 'r+' does NOT lock on Linux /
            % MATLAB Online, so the old handle-holding trick silently no-ops
            % there). If the OS ignores the read-only bit (e.g. running as root),
            % the write still succeeds -> we can't exercise the failure path, so
            % assume-skip rather than report a false failure.
            good = tc.makeCase("PHC001","OD",1);
            netra.store.save(good, tc.Cfg);
            before = netra.store.registry();
            tc.verifyEqual(height(before), 1);

            dataDir = fullfile(tc.Root, 'data');
            fileattrib(dataDir, '-w');                          % read-only
            restore = onCleanup(@() fileattrib(dataDir, '+w')); %#ok<NASGU>

            % Confirm the injection actually blocks writes here; if not, skip.
            probe = fullfile(dataDir, 'writeprobe.tmp');
            [okW, ~] = localTryWrite(probe);
            tc.assumeFalse(okW, ...
                'Filesystem ignores read-only bit (root?); cannot test write-failure path.');

            bad = tc.makeCaseNoPersist("PHC002","OS",2);
            tc.verifyError(@() netra.store.save(bad, tc.Cfg), ...
                'NETRA:store:registryWrite');

            fileattrib(dataDir, '+w');                          % re-enable for readback
            bak = fullfile(dataDir,'registry.mat.bak'); if isfile(bak), delete(bak); end

            after = netra.store.registry();
            tc.verifyEqual(height(after), 1);                   % still just the good case
            tc.verifyEqual(after.uid, before.uid);
        end

        function queryAndStatsWorkOnRealRegistry(tc)
            % Ingest a spread so the queue/stats have content.
            for k = 1:5
                netra.store.save(tc.makeCase("PHC001","OD",k), tc.Cfg);
            end
            Q = netra.store.queryQueue(tc.Cfg);
            tc.verifyClass(Q, 'table');
            s = netra.store.stats(tc.Cfg);
            tc.verifyGreaterThanOrEqual(s.screenedToday, 5);
        end

        function queryAndStatsWorkOnEmptyRegistry(tc)
            % No saves this test -> empty real registry.
            Q = netra.store.queryQueue(tc.Cfg);
            tc.verifyEqual(height(Q), 0);
            s = netra.store.stats(tc.Cfg);
            tc.verifyEqual(s.screenedToday, 0);
            tc.verifySize(s.gradeDistribution, [1 5]);
        end

    end

    methods
        function cr = makeCase(tc, phc, eye, seq)
            % A caseRecord with REAL pixels so the store persists it (full
            % pipeline, which also persists internally via the store stage).
            cr = tc.makeCaseNoPersist(phc, eye, seq);
            cr = netra.runPipeline(cr, tc.Cfg, netra.loadModels());
        end

        function cr = makeCaseNoPersist(tc, phc, eye, seq)
            % Valid caseRecord with REAL pixels, WITHOUT running the pipeline
            % (so nothing is persisted as a side effect). save() only needs a
            % valid record with a uid and img.raw.
            img = synthFundus(400);
            p = fullfile(tc.Root, sprintf('in_%s_%d.png', eye, seq));
            imwrite(img, p);
            meta = struct('patientID', "P"+string(seq), 'phcID', phc, ...
                'eye', eye, 'age', 60, 'dmYears', 5, 'seq', seq);
            cr = netra.newCaseRecord(p, meta);
            cr.img.raw = img;
        end
    end
end

% ------------------------------------------------------------------------
function closeAndClean(fid, regPath)
    try, if any(fid == fopen('all')), fclose(fid); end; catch, end
    bak = [regPath '.bak'];
    if isfile(bak), delete(bak); end
end

function [ok, err] = localTryWrite(path)
%LOCALTRYWRITE  True if a file can be created at PATH (probe for writability).
    ok = false; err = '';
    fid = fopen(path, 'w');
    if fid >= 3
        fclose(fid);
        if isfile(path), delete(path); end
        ok = true;
    else
        err = 'fopen failed';
    end
end

% ======================= fixtures =======================================
function img = synthFundus(n)
    [X,Y] = meshgrid(linspace(-1,1,n), linspace(-1,1,n));
    R = sqrt(X.^2 + Y.^2);
    m = double(R <= 0.9);
    r = (0.6 + 0.25*(1-R)).*m; g = (0.25 + 0.1*(1-R)).*m; b = (0.12).*m;
    img = uint8(255*cat(3, min(1,r), min(1,g), min(1,b)));
end
