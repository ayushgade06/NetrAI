function results = eval_lesions()
%EVAL_LESIONS  Per-class lesion sensitivity + FP/image on IDRiD.  [Track A]
%   results = eval_lesions() evaluates the REAL lesion detector against IDRiD's
%   pixel-level ground-truth masks and saves validation/results_idrid.mat with,
%   for each class MA / HE / EX:
%     - sensitivity      : fraction of ground-truth lesions overlapped by a
%                          detection (lesion-level, connected-component match).
%     - fpPerImage       : mean number of detected components not matching any
%                          ground-truth lesion, per image.
%
%   IDRiD "Segmentation" layout (datasets/idrid): original images under
%   .../OriginalImages, and per-class mask PNGs under .../Groundtruths with a
%   subfolder per lesion type (Microaneurysms/Haemorrhages/HardExudates).
%   The exact folder names vary by release; this searches case-insensitively.
%
%   METRICS RULE: every number saved comes from an ACTUAL run on IDRiD. If IDRiD
%   is absent, NOTHING is saved and the absence is printed. No expected or
%   illustrative number is ever written.
%
%   Run from a MATLAB session after startup_netra.

    cfg = netra.loadConfig();
    root = repoRoot();
    idrid = fullfile(root, 'datasets', 'idrid');
    if ~isfolder(idrid)
        fprintf(['eval_lesions: IDRiD absent (%s) - saving NOTHING. Place IDRiD ' ...
            'under datasets/ and re-run.\n'], idrid);
        results = []; return;
    end

    imgDir = findDir(idrid, {'originalimages','images','original images'});
    gtRoot = findDir(idrid, {'groundtruths','ground truths','masks'});
    if isempty(imgDir) || isempty(gtRoot)
        fprintf('eval_lesions: IDRiD present but image/groundtruth folders not found - nothing saved.\n');
        results = []; return;
    end

    classDirs = struct( ...
        'MA', findDir(gtRoot, {'microaneurysms','microaneurysm','ma'}), ...
        'HE', findDir(gtRoot, {'haemorrhages','hemorrhages','he'}), ...
        'EX', findDir(gtRoot, {'hardexudates','hard exudates','exudates','ex'}));

    imgs = dir(fullfile(imgDir, '**', '*.*'));
    imgs = imgs(~[imgs.isdir]);
    imgs = imgs(cellfun(@(n) hasImgExt(n), {imgs.name}));

    classes = {'MA','HE','EX'};
    agg = struct();
    for c = 1:3, agg.(classes{c}) = struct('tp',0,'gt',0,'fp',0,'nImg',0); end

    for i = 1:numel(imgs)
        f = fullfile(imgs(i).folder, imgs(i).name);
        [img, ok] = tryRead(f); if ~ok, continue; end

        % run the real pipeline stages needed for lesions
        cr = netra.newCaseRecord(f);
        cr.img.raw = img;
        cr = netra.preproc.enhance(cr, cfg);
        cr = netra.structures.segment(cr, cfg);
        cr = netra.lesions.detect(cr, cfg);
        sz = size(cr.img.enhanced(:,:,1));

        for c = 1:3
            cd = classDirs.(classes{c});
            gt = matchMask(cd, imgs(i).name);
            if isempty(gt), continue; end
            gt = imresize(gt, sz, 'nearest') > 0;
            pred = cr.lesions.(classes{c}).mask;
            [tp, gtN, fp] = lesionLevelMatch(pred, gt);
            a = agg.(classes{c});
            a.tp = a.tp + tp; a.gt = a.gt + gtN; a.fp = a.fp + fp; a.nImg = a.nImg + 1;
            agg.(classes{c}) = a;
        end
    end

    results = struct('ranAt', string(datetime('now')));
    for c = 1:3
        a = agg.(classes{c});
        sens = a.tp / max(a.gt, 1);
        fppi = a.fp / max(a.nImg, 1);
        results.(classes{c}) = struct('sensitivity',sens,'fpPerImage',fppi, ...
            'nImages',a.nImg,'gtLesions',a.gt,'truePos',a.tp,'falsePos',a.fp);
        fprintf('  %s: sens %.3f  FP/img %.2f  (%d imgs, %d GT lesions)\n', ...
            classes{c}, sens, fppi, a.nImg, a.gt);
    end

    if all(structfun(@(s) s.nImg==0, agg))
        fprintf('eval_lesions: no per-class ground-truth matched any image - nothing saved.\n');
        results = []; return;
    end

    outFile = fullfile(root, 'validation', 'results_idrid.mat');
    save(outFile, 'results');
    fprintf('eval_lesions: wrote %s\n', outFile);
end

% ========================================================================
function [tp, gtN, fp] = lesionLevelMatch(pred, gt)
%LESIONLEVELMATCH  Connected-component match: a GT lesion counts as detected if
%   any prediction overlaps it; a prediction is a FP if it overlaps no GT lesion.
    ccGt = bwconncomp(gt); gtN = ccGt.NumObjects;
    ccPr = bwconncomp(bwareaopen(pred, 3));
    tp = 0;
    for k = 1:gtN
        m = false(size(gt)); m(ccGt.PixelIdxList{k}) = true;
        if any(pred(m)), tp = tp + 1; end
    end
    fp = 0;
    for k = 1:ccPr.NumObjects
        idx = ccPr.PixelIdxList{k};
        if ~any(gt(idx)), fp = fp + 1; end
    end
end

function d = findDir(base, cands)
    d = '';
    listing = dir(fullfile(base, '**'));
    listing = listing([listing.isdir]);
    for i = 1:numel(listing)
        nm = lower(listing(i).name);
        for j = 1:numel(cands)
            if strcmp(nm, cands{j})
                d = fullfile(listing(i).folder, listing(i).name); return;
            end
        end
    end
end

function tf = hasImgExt(name)
    [~,~,e] = fileparts(name);
    tf = any(strcmpi(e, {'.jpg','.jpeg','.png','.tif','.tiff'}));
end

function [img, ok] = tryRead(f)
    img = []; ok = false;
    try
        img = imread(f);
        if size(img,3)==1, img = repmat(img,1,1,3); end
        if ~isa(img,'uint8'), img = im2uint8(img); end
        ok = true;
    catch
    end
end

function m = matchMask(dir_, imgName)
    m = [];
    if isempty(dir_) || ~isfolder(dir_), return; end
    stem = regexprep(imgName, '\..*$', '');
    d = dir(fullfile(dir_, '**', '*.*')); d = d(~[d.isdir]);
    for i = 1:numel(d)
        if contains(d(i).name, stem)
            try, m = imread(fullfile(d(i).folder, d(i).name)); catch, m = []; end
            if ~isempty(m) && size(m,3)>1, m = m(:,:,1); end
            return;
        end
    end
end

function r = repoRoot()
    r = fileparts(fileparts(mfilename('fullpath')));
end
