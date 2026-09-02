classdef tSchema < matlab.unittest.TestCase
    %TSCHEMA  Schema factory and assertSchema contract tests.

    properties
        Img
    end

    methods (TestClassSetup)
        function findImage(tc)
            here = fileparts(mfilename('fullpath'));
            root = fileparts(here);
            tc.Img = fullfile(root, 'data', 'demo', 'sample01.jpg');
            tc.assumeTrue(isfile(tc.Img), ...
                'Demo image data/demo/sample01.jpg is required for tests.');
        end
    end

    methods (Test)

        function returnsAllGroups(tc)
            cr = netra.newCaseRecord(tc.Img);
            expected = {'meta','img','quality','preproc','structures', ...
                'lesions','grade','xai','routing','report','review', ...
                'timing','provenance','version','errors'};
            for k = 1:numel(expected)
                tc.verifyTrue(isfield(cr, expected{k}), ...
                    sprintf('Missing top-level group: %s', expected{k}));
            end
        end

        function assertSchemaPassesOnFresh(tc)
            cr = netra.newCaseRecord(tc.Img);
            tc.verifyWarningFree(@() netra.util.assertSchema(cr));
        end

        function assertSchemaFailsWithUsefulMessage(tc)
            cr = netra.newCaseRecord(tc.Img);
            cr.quality = rmfield(cr.quality, 'score');   % break one field
            try
                netra.util.assertSchema(cr);
                tc.verifyFail('assertSchema should have thrown.');
            catch ME
                tc.verifyEqual(ME.identifier, 'NETRA:schema:missingField');
                tc.verifySubstring(ME.message, 'quality.score', ...
                    'Error message must name the missing field path.');
            end
        end

        function fieldTypesMatchContract(tc)
            cr = netra.newCaseRecord(tc.Img);
            tc.verifyClass(cr.meta.uid, 'string');
            tc.verifyClass(cr.meta.timestamp, 'datetime');
            tc.verifyClass(cr.meta.age, 'double');
            tc.verifyClass(cr.img.raw, 'uint8');
            tc.verifyClass(cr.img.fovMask, 'logical');
            tc.verifyClass(cr.img.modelInput, 'single');
            tc.verifyClass(cr.quality.score, 'double');
            tc.verifyClass(cr.quality.class, 'string');
            tc.verifyClass(cr.quality.quadrantMeans, 'double');
            tc.verifySize(cr.quality.quadrantMeans, [1 4]);
            tc.verifyClass(cr.grade.probs, 'double');
            tc.verifySize(cr.grade.probs, [1 5]);
            tc.verifyClass(cr.routing.flags, 'string');
            tc.verifyClass(cr.structures.quadrantMap, 'uint8');
        end

        function metaDefaultsAndOverrides(tc)
            cr = netra.newCaseRecord(tc.Img);
            tc.verifyEqual(cr.meta.eye, "OD");           % documented default
            meta = struct('patientID', "P42", 'eye', "OS", 'age', 61);
            cr2 = netra.newCaseRecord(tc.Img, meta);
            tc.verifyEqual(cr2.meta.patientID, "P42");
            tc.verifyEqual(cr2.meta.eye, "OS");
            tc.verifyEqual(cr2.meta.age, 61);
        end

        function fileNotFoundErrors(tc)
            tc.verifyError(@() netra.newCaseRecord('no/such/file.jpg'), ...
                'NETRA:io:fileNotFound');
        end

    end
end
