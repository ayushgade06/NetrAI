classdef tLesions < matlab.unittest.TestCase
    %TLESIONS  Tests for red/bright lesion detection (Phase 6).
    %   Synthetic images with planted lesions provide ground truth; no external
    %   dataset is required. IDRiD sensitivity/FP metrics are computed by
    %   validation/eval_lesions.m only when IDRiD is on disk.

    properties
        Cfg
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.Cfg = netra.loadConfig();
        end
    end

    methods (Test)

        function odNotDetectedAsExudate(tc)
            % CRITICAL (written first): a bright optic disc with NO exudates must
            % not be counted as a hard exudate. This catches the single most
            % common bug in the module - the OD dominating brightLesions.
            [img, fov, odC, odR] = fundusWithDisc(512);
            [ex, ~] = netra.lesions.brightLesions(img, fov, odC, odR, tc.Cfg);
            tc.verifyLessThanOrEqual(nnz(bwareaopen(ex, 5)), 3, ...
                'Optic disc was detected as an exudate (EX count high).');
        end

        function nBrightCirclesYieldApproxNExudates(tc)
            [img, fov, odC, odR] = fundusWithDisc(512);
            N = 6;
            [img, gt] = plantBrightSpots(img, fov, odC, odR, N);
            [ex, ~] = netra.lesions.brightLesions(img, fov, odC, odR, tc.Cfg);
            cc = bwconncomp(bwareaopen(ex, 3));
            fprintf('\n[tLesions] planted %d bright spots, detected %d EX blobs.\n', ...
                N, cc.NumObjects);
            tc.verifyGreaterThanOrEqual(cc.NumObjects, round(0.5*N), ...
                'Detected far fewer exudates than planted.');
            tc.verifyLessThanOrEqual(cc.NumObjects, 2*N + 2, ...
                'Detected far more exudates than planted (over-segmentation).');
            tc.verifyGreaterThan(nnz(ex & gt), 0, 'No detected EX overlaps a planted spot.');
        end

        function smallDarkDotsYieldMA(tc)
            [img, fov, ~, odR] = fundusWithDisc(512);
            img = plantDarkDots(img, fov, 8, round(0.006*512));   % tiny, round
            [vm,~] = netra.structures.vesselsFrangi(img, fov, tc.Cfg);
            lcfg = tc.Cfg; lcfg.odRadius = odR;
            [ma, he, ~] = netra.lesions.redLesions(img, fov, vm, lcfg);
            tc.verifyGreaterThan(nnz(ma), 0, 'No MA detected from small dark dots.');
            tc.verifyGreaterThanOrEqual(nnz(ma), nnz(he), ...
                'Small round dots classified as HE rather than MA.');
        end

        function largeIrregularBlobsYieldHE(tc)
            [img, fov, odC, odR] = fundusWithDisc(512); %#ok<ASGLU>
            img = plantDarkBlobs(img, fov, 4, round(0.05*512));   % large, irregular
            [vm,~] = netra.structures.vesselsFrangi(img, fov, tc.Cfg);
            lcfg = tc.Cfg; lcfg.odRadius = odR;
            [ma, he, ~] = netra.lesions.redLesions(img, fov, vm, lcfg);
            tc.verifyGreaterThan(nnz(he), 0, 'No HE detected from large dark blobs.');
            tc.verifyGreaterThanOrEqual(nnz(he), nnz(ma), ...
                'Large blobs classified as MA rather than HE.');
        end

        function zeroLesionImageReturnsZeroCounts(tc)
            [img, ~, ~, ~] = fundusWithDisc(512);   % clean disc, no lesions
            cr = tc.runToLesions(img);
            for ty = ["MA","HE","EX"]
                tc.verifyGreaterThanOrEqual(cr.lesions.(ty).count, 0);
            end
            tc.verifyClass(cr.lesions.allMask, 'logical');
        end

        function allMaskEqualsUnion(tc)
            [img, ~, ~, ~] = fundusWithDisc(512);
            img = plantDarkDots(img, trueFov(img,tc.Cfg), 5, 3);
            cr = tc.runToLesions(img);
            u = cr.lesions.MA.mask | cr.lesions.HE.mask | cr.lesions.EX.mask;
            tc.verifyEqual(cr.lesions.allMask, u, 'allMask != union of MA,HE,EX.');
        end

        function masksLogicalAndSized(tc)
            [img, ~, ~, ~] = fundusWithDisc(512);
            cr = tc.runToLesions(img);
            sz = size(cr.img.enhanced(:,:,1));
            for ty = ["MA","HE","EX"]
                tc.verifyClass(cr.lesions.(ty).mask, 'logical');
                tc.verifyEqual(size(cr.lesions.(ty).mask), sz, ...
                    sprintf('%s.mask wrong size.', ty));
            end
            tc.verifyEqual(size(cr.lesions.allMask), sz);
        end

        function perQuadrantSumsEqualCount(tc)
            [img, ~, ~, ~] = fundusWithDisc(512);
            img = plantDarkDots(img, trueFov(img,tc.Cfg), 6, 3);
            cr = tc.runToLesions(img);
            for ty = ["MA","HE","EX"]
                L = cr.lesions.(ty);
                % Every lesion lands in exactly one quadrant (centroid), UNLESS
                % it fell on a background pixel (quad 0) - allow <= count.
                tc.verifyLessThanOrEqual(sum(L.perQuadrant), L.count, ...
                    sprintf('%s perQuadrant sum exceeds count.', ty));
            end
        end

    end

    methods
        function cr = runToLesions(tc, img)
            tmp = [tempname '.png']; imwrite(img, tmp);
            cr = netra.newCaseRecord(tmp);
            cr.img.raw = img;
            cr = netra.preproc.enhance(cr, tc.Cfg);
            cr = netra.structures.segment(cr, tc.Cfg);
            cr = netra.lesions.detect(cr, tc.Cfg);
            delete(tmp);
        end
    end
end

% ======================= synthetic fixtures =============================
function [img, fov, odC, odR] = fundusWithDisc(n)
    [X,Y] = meshgrid(1:n, 1:n);
    cx = n/2; cy = n/2; fov = hypot(X-cx,Y-cy) <= 0.46*n;
    r = 0.55*ones(n); g = 0.32*ones(n); b = 0.12*ones(n);
    odC = [0.30*n, 0.5*n]; odR = 0.06*n;
    disc = hypot(X-odC(1),Y-odC(2)) <= odR;
    r(disc) = 0.98; g(disc) = 0.90; b(disc) = 0.60;
    img = cat(3,r,g,b); img(repmat(~fov,1,1,3)) = 0;
    img = uint8(255*min(1,max(0,img)));
end

function [img, gt] = plantBrightSpots(img, fov, odC, odR, N)
    [n,~,~] = size(img); [X,Y] = meshgrid(1:n,1:n);
    gt = false(n); rng(11);
    placed = 0; tries = 0;
    while placed < N && tries < 500
        tries = tries + 1;
        cx = randi(n); cy = randi(n);
        if ~fov(cy,cx), continue; end
        if hypot(cx-odC(1),cy-odC(2)) < 2.5*odR, continue; end   % away from OD
        spot = hypot(X-cx,Y-cy) <= max(2, round(0.008*n));
        gt = gt | spot;
        for c=1:3, ch=img(:,:,c); ch(spot)=uint8(240); img(:,:,c)=ch; end
        placed = placed + 1;
    end
end

function img = plantDarkDots(img, fov, N, rad)
    [n,~,~] = size(img); [X,Y] = meshgrid(1:n,1:n); rng(21);
    placed=0; tries=0;
    while placed<N && tries<500
        tries=tries+1; cx=randi(n); cy=randi(n);
        if ~fov(cy,cx), continue; end
        spot = hypot(X-cx,Y-cy) <= rad;                 % small round
        for c=1:3, ch=img(:,:,c); ch(spot)=uint8(20); img(:,:,c)=ch; end
        placed=placed+1;
    end
end

function img = plantDarkBlobs(img, fov, N, rad)
    [n,~,~] = size(img); [X,Y]=meshgrid(1:n,1:n); rng(31);
    placed=0; tries=0;
    while placed<N && tries<500
        tries=tries+1; cx=randi(n); cy=randi(n);
        if ~fov(cy,cx), continue; end
        % irregular: union of two offset ellipses -> high eccentricity/low circ
        e1 = ((X-cx)/rad).^2 + ((Y-cy)/(0.5*rad)).^2 <= 1;
        e2 = ((X-cx-rad)/rad).^2 + ((Y-cy)/(0.6*rad)).^2 <= 1;
        spot = e1 | e2;
        for c=1:3, ch=img(:,:,c); ch(spot)=uint8(18); img(:,:,c)=ch; end
        placed=placed+1;
    end
end

function fov = trueFov(img, cfg)
    [fov,~] = netra.preproc.fovMask(img, cfg);
end
