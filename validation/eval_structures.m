function results = eval_structures()
%EVAL_STRUCTURES  Vessel + OD-localisation accuracy on DRIVE / IDRiD.  [Track A]
%   results = eval_structures() evaluates the REAL structure segmentation against
%   ground truth and saves validation/results_structures.mat. It computes:
%     - DRIVE: vessel sensitivity / specificity / accuracy vs the 1st-observer
%       manual masks (datasets/drive/test/{images,1st_manual,mask}).
%     - IDRiD: OD-localisation accuracy = fraction of images whose detected OD
%       centre is within 1 disc radius of the ground-truth OD centre
%       (datasets/idrid Optic Disc Center CSV).
%
%   METRICS RULE (§ brief): every number saved comes from an ACTUAL run on real
%   data. If a dataset is absent, NOTHING is saved for it and the absence is
%   printed. No illustrative or expected number is ever written.
%
%   Run from a MATLAB session after startup_netra. Requires the datasets under
%   datasets/ (they are git-ignored and NOT downloaded by this project).

    cfg = netra.loadConfig();
    root = repoRoot();
    results = struct('drive', [], 'idrid', [], 'ranAt', string(datetime('now')));
    anyData = false;

    % ---------------- DRIVE vessels -------------------------------------
    drive = fullfile(root, 'datasets', 'drive');
    if isfolder(drive)
        anyData = true;
        results.drive = evalDrive(drive, cfg);
    else
        fprintf('eval_structures: DRIVE absent (%s). Vessel metrics not computed.\n', drive);
    end

    % ---------------- IDRiD optic disc ----------------------------------
    idrid = fullfile(root, 'datasets', 'idrid');
    if isfolder(idrid)
        anyData = true;
        results.idrid = evalIdridOD(idrid, cfg);
    else
        fprintf('eval_structures: IDRiD absent (%s). OD-localisation not computed.\n', idrid);
    end

    if ~anyData
        fprintf(['eval_structures: no datasets on disk - saving NOTHING. ' ...
            'Place DRIVE/IDRiD under datasets/ and re-run.\n']);
        return;
    end

    outFile = fullfile(root, 'validation', 'results_structures.mat');
    save(outFile, 'results');
    fprintf('eval_structures: wrote %s\n', outFile);
end

% ========================================================================
function r = evalDrive(drive, cfg)
    imgDir = firstExisting(drive, {'test/images','training/images','images'});
    gtDir  = firstExisting(drive, {'test/1st_manual','training/1st_manual','1st_manual'});
    mkDir  = firstExisting(drive, {'test/mask','training/mask','mask'});
    d = dir(fullfile(imgDir, '*.*'));
    d = d(~[d.isdir]);
    TP=0; TN=0; FP=0; FN=0; nImg=0;
    for i = 1:numel(d)
        [img, ok] = tryRead(fullfile(d(i).folder, d(i).name)); if ~ok, continue; end
        gt = matchMask(gtDir, d(i).name); if isempty(gt), continue; end
        fovM = matchMask(mkDir, d(i).name);
        if isempty(fovM)
            [fovM,~] = netra.preproc.fovMask(img, cfg);
        else
            fovM = imresize(fovM, size(img(:,:,1)), 'nearest') > 0;
        end
        gt = imresize(gt, size(img(:,:,1)), 'nearest') > 0;
        [pred,~] = netra.structures.vesselsFrangi(img, fovM, cfg);
        inF = fovM;
        TP = TP + nnz(pred & gt & inF);
        TN = TN + nnz(~pred & ~gt & inF);
        FP = FP + nnz(pred & ~gt & inF);
        FN = FN + nnz(~pred & gt & inF);
        nImg = nImg + 1;
    end
    sens = TP/max(TP+FN,1); spec = TN/max(TN+FP,1);
    acc = (TP+TN)/max(TP+TN+FP+FN,1);
    r = struct('nImages',nImg,'sensitivity',sens,'specificity',spec,'accuracy',acc);
    fprintf('  DRIVE (%d imgs): sens %.3f  spec %.3f  acc %.3f\n', nImg, sens, spec, acc);
end

function r = evalIdridOD(idrid, cfg)
    % IDRiD OD-center ground truth: a CSV with image name + (x,y). Layout varies
    % across releases; we search for a CSV whose columns look like (name,x,y).
    [imgs, gtXY] = idridOdGroundTruth(idrid);
    if isempty(imgs)
        fprintf('  IDRiD: no OD-center ground truth CSV found - OD accuracy not computed.\n');
        r = []; return;
    end
    within = 0; nImg = 0;
    for i = 1:numel(imgs)
        [img, ok] = tryRead(imgs{i}); if ~ok, continue; end
        [fovM,~] = netra.preproc.fovMask(img, cfg);
        [vm,~]  = netra.structures.vesselsFrangi(img, fovM, cfg);
        [ctr, rad, ~] = netra.structures.locateOD(img, fovM, vm, cfg);
        d = hypot(ctr(1)-gtXY(i,1), ctr(2)-gtXY(i,2));
        within = within + (d <= rad);
        nImg = nImg + 1;
    end
    r = struct('nImages',nImg,'withinOneRadius', within/max(nImg,1));
    fprintf('  IDRiD OD (%d imgs): within-1-radius %.3f\n', nImg, within/max(nImg,1));
end

% ---- small IO helpers ---------------------------------------------------
function p = firstExisting(base, cands)
    p = '';
    for i = 1:numel(cands)
        c = fullfile(base, cands{i});
        if isfolder(c), p = c; return; end
    end
    p = base;
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
    stem = regexprep(stem, '_(training|test)$', '');
    d = dir(fullfile(dir_, '*.*')); d = d(~[d.isdir]);
    for i = 1:numel(d)
        if contains(d(i).name, stem)
            try, m = imread(fullfile(d(i).folder, d(i).name)); catch, m = []; end
            if ~isempty(m) && size(m,3)>1, m = m(:,:,1); end
            return;
        end
    end
end

function [imgs, xy] = idridOdGroundTruth(idrid)
    imgs = {}; xy = zeros(0,2);
    csvs = dir(fullfile(idrid, '**', '*.csv'));
    for i = 1:numel(csvs)
        try, T = readtable(fullfile(csvs(i).folder, csvs(i).name)); catch, continue; end
        vn = lower(string(T.Properties.VariableNames));
        hasX = any(contains(vn,'x')); hasY = any(contains(vn,'y'));
        nameCol = find(contains(vn,'image') | contains(vn,'name'), 1);
        if ~(hasX && hasY && ~isempty(nameCol)), continue; end
        xcol = find(contains(vn,'x'),1); ycol = find(contains(vn,'y'),1);
        imgFolder = fullfile(idrid);
        for r = 1:height(T)
            nm = string(T{r, nameCol});
            f = findImage(imgFolder, nm);
            if isempty(f), continue; end
            imgs{end+1} = f; %#ok<AGROW>
            xy(end+1,:) = [T{r,xcol}, T{r,ycol}]; %#ok<AGROW>
        end
        if ~isempty(imgs), return; end
    end
end

function f = findImage(base, stem)
    f = '';
    stem = regexprep(char(stem), '\..*$', '');
    d = dir(fullfile(base, '**', [stem '.*']));
    for i = 1:numel(d)
        [~,~,e] = fileparts(d(i).name);
        if any(strcmpi(e, {'.jpg','.jpeg','.png','.tif','.tiff'}))
            f = fullfile(d(i).folder, d(i).name); return;
        end
    end
end

function r = repoRoot()
    r = fileparts(fileparts(mfilename('fullpath')));
end
