classdef tReviewWorkflow < matlab.unittest.TestCase
    %TREVIEWWORKFLOW  Tests for the review queue, logReview and auditStats.

    properties
        Cfg
        TmpRoot
        SeedPath
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.Cfg = netra.loadConfig();
            root = fileparts(fileparts(mfilename('fullpath')));
            addpath(fullfile(root, 'tools'));

            % Isolated store: a temp root with a small mock seed we can mutate.
            tc.TmpRoot = tempname; mkdir(tc.TmpRoot);
            setenv('NETRA_STORE_ROOT', tc.TmpRoot);
            tc.SeedPath = fullfile(tc.TmpRoot, 'data', 'mock', 'registry_seed.mat');
            seedMockRegistry(tc.SeedPath);
        end
    end

    methods (TestClassTeardown)
        function teardown(tc)
            setenv('NETRA_STORE_ROOT', '');
            if isfolder(tc.TmpRoot), rmdir(tc.TmpRoot, 's'); end
        end
    end

    methods (Access = private)
        function uid = firstQueued(tc)
            Q = netra.store.queryQueue(tc.Cfg);
            tc.assertGreaterThan(height(Q), 0, 'Need a queued case for the test.');
            uid = char(Q.uid(1));
        end
    end

    methods (Test)

        % ---- logReview persists the decision ----------------------------
        function logReviewWritesDecision(tc)
            uid = tc.firstQueued();
            netra.store.logReview(uid, 'Override', 3, 'revA', 22.5, 'looks worse', tc.Cfg);

            T = netra.store.internalLoadRegistry();
            row = T(T.uid == string(uid), :);
            tc.verifyTrue(row.reviewed, 'Row must be marked reviewed.');
            tc.verifyEqual(row.reviewSeconds, 22.5, 'AbsTol', 1e-9);
            tc.verifyEqual(string(row.reviewerAgreed), "Overridden");
        end

        function confirmMarksAgreed(tc)
            uid = tc.firstQueued();
            netra.store.logReview(uid, 'Confirm', 1, 'revA', 15, '', tc.Cfg);
            T = netra.store.internalLoadRegistry();
            row = T(T.uid == string(uid), :);
            tc.verifyEqual(string(row.reviewerAgreed), "Agreed");
        end

        function skipDoesNotMarkReviewed(tc)
            uid = tc.firstQueued();
            netra.store.logReview(uid, 'Skip', NaN, 'revA', 3, '', tc.Cfg);
            T = netra.store.internalLoadRegistry();
            row = T(T.uid == string(uid), :);
            tc.verifyFalse(row.reviewed, 'Skip is a non-decision; row stays unreviewed.');
        end

        % ---- queryQueue sorting -----------------------------------------
        function sortUrgencyDescConfidenceAsc(tc)
            Q = netra.store.queryQueue(tc.Cfg);
            tc.assumeGreaterThan(height(Q), 1);
            rank = @(u) arrayfun(@(x) find(["None","Routine","Priority","Urgent"]==x), u);
            r = rank(Q.urgency);
            tc.verifyTrue(all(diff(r) <= 0), 'Urgency must be descending.');
            for u = unique(r)'
                idx = find(r == u);
                if numel(idx) > 1
                    tc.verifyTrue(all(diff(Q.confidence(idx)) >= -1e-9), ...
                        'Confidence must ascend within an urgency band.');
                end
            end
        end

        % ---- filter chips return the right subset -----------------------
        function urgentFilterSubset(tc)
            Q = netra.store.queryQueue(tc.Cfg, struct('urgency', "Urgent"));
            if ~isempty(Q), tc.verifyTrue(all(Q.urgency == "Urgent")); end
        end

        function flaggedFilterSubset(tc)
            Q = netra.store.queryQueue(tc.Cfg, struct('flagged', true));
            if ~isempty(Q), tc.verifyTrue(all(strlength(Q.flags) > 0)); end
        end

        % ---- auditStats agreement rate ----------------------------------
        function auditAgreementRate(tc)
            % Review three queued cases: 2 confirm (agree), 1 override.
            Q = netra.store.queryQueue(tc.Cfg);
            tc.assertGreaterThanOrEqual(height(Q), 3);
            netra.store.logReview(char(Q.uid(1)), 'Confirm', 0, 'r', 10, '', tc.Cfg);
            netra.store.logReview(char(Q.uid(2)), 'Confirm', 0, 'r', 12, '', tc.Cfg);
            netra.store.logReview(char(Q.uid(3)), 'Override', 2, 'r', 20, '', tc.Cfg);

            a = netra.store.auditStats(tc.Cfg);
            tc.verifyGreaterThanOrEqual(a.reviewedCount, 3);
            % At least the three we just logged: 2 agreed / 3 decided among them.
            tc.verifyTrue(isfinite(a.agreementRate));
            tc.verifyGreaterThanOrEqual(a.overrideCount, 1);
            tc.verifyGreaterThanOrEqual(numel(a.reviewSeconds), 3);
        end

        function auditEmptyRegistryIsHonest(tc)
            % Fresh temp root with an empty registry -> NaN rate, zero counts.
            tmp = tempname; mkdir(tmp);
            old = getenv('NETRA_STORE_ROOT');
            setenv('NETRA_STORE_ROOT', tmp);
            cleanup = onCleanup(@() restore(old, tmp)); %#ok<NASGU>
            a = netra.store.auditStats(tc.Cfg);
            tc.verifyEqual(a.reviewedCount, 0);
            tc.verifyTrue(isnan(a.agreementRate));

            function restore(o, t)
                setenv('NETRA_STORE_ROOT', o);
                if isfolder(t), rmdir(t, 's'); end
            end
        end

        % ---- reviewing the last case does not error ---------------------
        function reviewLastCaseNoError(tc)
            Q = netra.store.queryQueue(tc.Cfg);
            n = height(Q);
            for i = 1:n
                netra.store.logReview(char(Q.uid(i)), 'Confirm', 0, 'r', 8, '', tc.Cfg);
            end
            % Queue should now be empty; querying and auditing must not error.
            Q2 = netra.store.queryQueue(tc.Cfg);
            tc.verifyEqual(height(Q2), 0);
            a = netra.store.auditStats(tc.Cfg);
            tc.verifyGreaterThanOrEqual(a.reviewedCount, 1);
        end

    end
end
