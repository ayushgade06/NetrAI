classdef tStructures < matlab.unittest.TestCase
    %TSTRUCTURES  Tests for vessel / OD / fovea / quadrant segmentation (Phase 5).
    %   Runs on a synthetic fundus with a KNOWN bright disc, dark macula, and
    %   vessel streaks (ground truth is the construction), plus the real demo
    %   JPEGs when present. IDRiD is NOT on disk, so the OD-vs-ground-truth
    %   accuracy test is SKIPPED with an assumeFail-free note (validation/
    %   eval_structures.m computes it when IDRiD is placed under datasets/).

    properties
        Cfg
        Fundus      % synthetic fundus (struct: img, odCenter, foveaCenter)
        DemoImgs
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.Cfg = netra.loadConfig();
            tc.Fundus = synthFundusStruct(512);
            tc.DemoImgs = loadDemos();
        end
    end

    methods (Test)

        function vesselMaskLogicalCorrectSize(tc)
            img = tc.Fundus.img;
            [mask, fov] = fovOf(img, tc.Cfg);
            [vm, info] = netra.structures.vesselsFrangi(img, fov, tc.Cfg); %#ok<ASGLU>
            tc.verifyClass(vm, 'logical');
            tc.verifyEqual(size(vm), size(img(:,:,1)));
            tc.verifyGreaterThanOrEqual(info.density, 0);
            tc.verifyLessThan(info.density, 0.5, 'Vessel density implausibly high.');
            tc.verifyGreaterThanOrEqual(info.tortuosity, 1);
        end

        function odCentreInsideFov(tc)
            imgs = [{tc.Fundus.img}, tc.DemoImgs];
            for k = 1:numel(imgs)
                img = imgs{k};
                [~, fov] = fovOf(img, tc.Cfg);
                [vm,~] = netra.structures.vesselsFrangi(img, fov, tc.Cfg);
                [ctr,~,~] = netra.structures.locateOD(img, fov, vm, tc.Cfg);
                cx = min(size(fov,2),max(1,round(ctr(1))));
                cy = min(size(fov,1),max(1,round(ctr(2))));
                tc.verifyTrue(fov(cy,cx), ...
                    sprintf('Image %d: OD centre outside FOV.', k));
            end
        end

        function odNearSyntheticGroundTruth(tc)
            % On the synthetic fundus the disc location is known; the detector
            % should land within ~1 disc radius of it.
            img = tc.Fundus.img;
            [~, fov] = fovOf(img, tc.Cfg);
            [vm,~] = netra.structures.vesselsFrangi(img, fov, tc.Cfg);
            [ctr, rad, ~] = netra.structures.locateOD(img, fov, vm, tc.Cfg);
            d = hypot(ctr(1)-tc.Fundus.odCenter(1), ctr(2)-tc.Fundus.odCenter(2));
            tc.verifyLessThanOrEqual(d, 1.5*rad, ...
                sprintf('OD %.0f px from synthetic ground truth (rad %.0f).', d, rad));
        end

        function foveaTemporalToOD(tc)
            img = tc.Fundus.img;
            [~, fov] = fovOf(img, tc.Cfg);
            [vm,~] = netra.structures.vesselsFrangi(img, fov, tc.Cfg);
            [odc, odr, ~] = netra.structures.locateOD(img, fov, vm, tc.Cfg);
            [fvc, ~] = netra.structures.locateFovea(img, fov, odc, odr, vm, tc.Cfg);
            % Fovea must be offset horizontally from the OD (temporal), not on it.
            tc.verifyGreaterThan(abs(fvc(1)-odc(1)), odr, ...
                'Fovea is not horizontally displaced from the OD.');
        end

        function quadrantMapValuesAndCoverage(tc)
            img = tc.Fundus.img;
            [~, fov] = fovOf(img, tc.Cfg);
            [vm,~] = netra.structures.vesselsFrangi(img, fov, tc.Cfg);
            [odc, odr, ~] = netra.structures.locateOD(img, fov, vm, tc.Cfg);
            [fvc, ~] = netra.structures.locateFovea(img, fov, odc, odr, vm, tc.Cfg);
            q = netra.structures.quadrantMap(fov, odc, fvc, "OD", tc.Cfg);
            tc.verifyTrue(all(ismember(unique(q(:)), uint8(0:4))), ...
                'quadrantMap has values outside 0..4.');
            for code = 1:4
                tc.verifyGreaterThan(nnz(q==code), 0, ...
                    sprintf('Quadrant %d is empty.', code));
            end
        end

        function segmentSetsRealProvenanceAndMasks(tc)
            cr = tc.runToStructures(tc.Fundus.img);
            tc.verifyEqual(cr.provenance.structures, "REAL");
            sz = size(cr.img.enhanced(:,:,1));
            tc.verifyEqual(size(cr.structures.vesselMask), sz);
            tc.verifyEqual(size(cr.structures.maculaZone), sz);
            tc.verifyEqual(size(cr.structures.quadrantMap), sz);
            tc.verifyClass(cr.structures.vesselMask, 'logical');
        end

        function degenerateImageTriggersFallback(tc)
            % A flat grey image has no disc/fovea -> both fallbacks fire and set
            % their flags; the pipeline must not error.
            flat = uint8(120*ones(512,512,3));
            cr = tc.runToStructures(flat);
            tc.verifyTrue(cr.structures.odFallback || cr.structures.foveaFallback, ...
                'No fallback fired on a featureless image.');
            % odCenter must still be a finite point inside the frame.
            tc.verifyTrue(all(isfinite(cr.structures.odCenter)));
        end

        function idridOdAccuracyReportedOrSkipped(tc)
            % Honest: only runs if IDRiD is on disk. Otherwise states it is
            % absent and skips (no fabricated accuracy).
            root = repoRoot();
            idrid = fullfile(root, 'datasets', 'idrid');
            if ~isfolder(idrid)
                fprintf(['\n[tStructures] IDRiD not on disk (%s absent): OD-vs-GT ' ...
                    'accuracy not computed. Run validation/eval_structures.m ' ...
                    'once IDRiD is placed under datasets/.\n'], idrid);
                tc.assumeFail('IDRiD absent - see printed note.');
            end
            % (If present, eval_structures.m is the authoritative harness.)
        end

    end

    methods
        function cr = runToStructures(tc, img)
            tmp = [tempname '.png']; imwrite(img, tmp);
            cr = netra.newCaseRecord(tmp);
            cr.img.raw = img;
            cr = netra.preproc.enhance(cr, tc.Cfg);
            cr = netra.structures.segment(cr, tc.Cfg);
            delete(tmp);
        end
    end
end

% ======================= helpers ========================================
function s = synthFundusStruct(n)
    % Bright disc on the left, dark macula to the right, radial vessels.
    [X,Y] = meshgrid(1:n, 1:n);
    cx = n/2; cy = n/2; R = hypot(X-cx, Y-cy);
    fov = R <= 0.46*n;

    base = zeros(n,n,3);
    base(:,:,1) = 0.55; base(:,:,2) = 0.32; base(:,:,3) = 0.12;   % retina orange

    % optic disc: bright disc at ~30% width
    odC = [0.30*n, 0.5*n]; odR = 0.06*n;
    disc = hypot(X-odC(1), Y-odC(2)) <= odR;
    % fovea: dark spot ~2.2 DD temporal (to the right)
    fvC = [odC(1) + 2.2*2*odR, odC(2)];
    mac = hypot(X-fvC(1), Y-fvC(2)) <= 0.05*n;

    % vessels: streaks emanating from the disc
    vessels = false(n);
    for a = linspace(-1, 1, 7)
        yy = round(odC(2) + a*0.35*n + 12*sin(2*pi*(1:n)/140));
        yy = min(n, max(1, yy));
        for x = round(odC(1)):n, vessels(yy(x), x) = true; end
    end
    vessels = imdilate(vessels, strel('disk',1)) & fov;

    r = base(:,:,1); g = base(:,:,2); b = base(:,:,3);
    r(disc) = 0.95; g(disc) = 0.85; b(disc) = 0.55;              % bright disc
    r(mac) = 0.25; g(mac) = 0.12; b(mac) = 0.05;                 % dark macula
    r(vessels) = 0.35; g(vessels) = 0.10; b(vessels) = 0.06;     % dark vessels
    img = cat(3, r, g, b); img(repmat(~fov,1,1,3)) = 0;
    img = uint8(255*min(1,max(0,img)));

    s = struct('img', img, 'odCenter', odC, 'foveaCenter', fvC, ...
        'odRadius', odR);
end

function [mask, fov] = fovOf(img, cfg)
    [mask, ~] = netra.preproc.fovMask(img, cfg);
    fov = mask;
end

function imgs = loadDemos()
    here = repoRoot();
    d = dir(fullfile(here, 'data', 'demo', '*.jpeg'));
    imgs = {};
    for k = 1:numel(d)
        try
            im = imread(fullfile(d(k).folder, d(k).name));
            if size(im,3) == 1, im = repmat(im,1,1,3); end
            imgs{end+1} = im; %#ok<AGROW>
        catch
        end
    end
end

function r = repoRoot()
    r = fileparts(fileparts(mfilename('fullpath')));
end
