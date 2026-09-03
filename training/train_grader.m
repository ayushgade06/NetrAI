function meta = train_grader(opts)
%TRAIN_GRADER  Fine-tune a CNN to grade DR severity (ICDR 0-4) on APTOS.  [Track D]
%   meta = train_grader() trains a ResNet-18 (ImageNet-pretrained, fine-tuned)
%   on the APTOS train split and validates on the APTOS val split, then saves
%   models/dr_grader.mat containing:
%       net   - the trained network (predict returns 5 logits, classOrder 0..4)
%       meta  - dataset, split, class counts, val accuracy/kappa, timestamp,
%               config hash, backbone - so every downstream number is traceable.
%
%   netra.loadModels auto-detects dr_grader.mat, sets models.grader and
%   isPlaceholder=false, so netra.grading.classify switches to the real CNN path
%   with NO code change. Run validation/run_ablation and run_external AFTER this.
%
%   train_grader(opts) accepts:
%       opts.backbone   "resnet18" (default) | "squeezenet" (no add-on needed)
%       opts.maxEpochs  default 8
%       opts.miniBatch  default 32
%       opts.subset     0..1 fraction of the train split to use (default 1;
%                       set e.g. 0.3 for a fast dry run)
%
%   REQUIRES: Deep Learning Toolbox, APTOS under datasets/aptos2019/, and
%   validation/splits.mat (run registerDatasets + freezeSplits first). Errors
%   with a clear message if any is missing - it NEVER fabricates a model.

    arguments
        opts.backbone   (1,1) string = "resnet18"
        opts.maxEpochs  (1,1) double = 8
        opts.miniBatch  (1,1) double = 32
        opts.subset     (1,1) double = 1
    end

    root = fileparts(fileparts(mfilename('fullpath')));
    cfg  = netra.loadConfig();
    inSz = cfg.thresholds.grading.modelInputSize(:).';   % [224 224]
    inSz = inSz(1:2);

    % --- preconditions (never fabricate) --------------------------------
    aptos = fullfile(root, 'datasets', 'aptos2019');
    assert(isfolder(aptos), 'NETRA:train:noAptos', ...
        'APTOS not found at %s. Place it there first.', aptos);
    if license('test','Neural_Network_Toolbox') ~= 1
        error('NETRA:train:noDLT', 'Deep Learning Toolbox is required to train the grader.');
    end

    % --- build the labelled image table from the split ------------------
    [imgs, labels] = loadSplitTable(root, aptos, "train");
    [vImgs, vLabels] = loadSplitTable(root, aptos, "val");
    assert(~isempty(imgs), 'NETRA:train:emptyTrain', 'No training images resolved from the split.');

    if opts.subset < 1
        keep = subsampleStratified(labels, opts.subset);
        imgs = imgs(keep); labels = labels(keep);
        fprintf('train_grader: using %.0f%% subset -> %d train images\n', 100*opts.subset, numel(imgs));
    end

    classes = categorical(0:4, 0:4, cellstr(string(0:4)));
    yTrain  = categorical(labels, 0:4, cellstr(string(0:4)));
    yVal    = categorical(vLabels, 0:4, cellstr(string(0:4)));

    % --- datastores with Ben-Graham-style preprocessing -----------------
    trainDS = imgTable(imgs, yTrain, inSz);
    valDS   = imgTable(vImgs, yVal, inSz);

    % --- network: pretrained backbone, new 5-class head -----------------
    [net0, backboneUsed] = makeBackbone(opts.backbone, inSz, classes);

    % --- class weights: APTOS is heavily grade-0 skewed -----------------
    counts = countcats(yTrain);
    w = sum(counts) ./ (numel(counts) * max(counts,1));   % inverse-frequency
    net0 = setWeightedClassificationLayer(net0, classes, w);

    % --- training options ------------------------------------------------
    valFreq = max(1, floor(numel(imgs)/opts.miniBatch/2));
    options = trainingOptions('adam', ...
        'InitialLearnRate', 1e-4, ...
        'MaxEpochs', opts.maxEpochs, ...
        'MiniBatchSize', opts.miniBatch, ...
        'Shuffle', 'every-epoch', ...
        'ValidationData', valDS, ...
        'ValidationFrequency', valFreq, ...
        'ExecutionEnvironment', 'auto', ...      % GPU if present, else CPU
        'Verbose', true, ...
        'Plots', 'none');

    fprintf('train_grader: %s, %d train / %d val, %d epochs...\n', ...
        backboneUsed, numel(imgs), numel(vImgs), opts.maxEpochs);
    net = trainNetwork(trainDS, net0, options);

    % --- validation metrics (measured, saved with the model) ------------
    predV = classify(net, valDS);
    accV  = mean(predV == yVal);
    kappaV = quadraticKappa(double(yVal)-1, double(predV)-1, 0:4);

    meta = struct();
    meta.dataset       = "APTOS2019";
    meta.backbone      = backboneUsed;
    meta.inputSize     = inSz;
    meta.classOrder    = 0:4;
    meta.nTrain        = numel(imgs);
    meta.nVal          = numel(vImgs);
    meta.trainClassCounts = counts(:).';
    meta.valAccuracy   = accV;
    meta.valKappa      = kappaV;
    meta.maxEpochs     = opts.maxEpochs;
    meta.miniBatch     = opts.miniBatch;
    meta.subset        = opts.subset;
    meta.configHash    = configHash(cfg);
    meta.splitSeed     = splitSeed(root);
    meta.timestamp     = string(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));

    outDir = fullfile(root, 'models');
    if ~isfolder(outDir), mkdir(outDir); end
    outPath = fullfile(outDir, 'dr_grader.mat');
    save(outPath, 'net', 'meta', '-v7.3');

    fprintf('\ntrain_grader: saved %s\n', outPath);
    fprintf('  backbone   : %s\n', backboneUsed);
    fprintf('  val accuracy: %.3f   val kappa: %.3f\n', accV, kappaV);
    fprintf('  timestamp  : %s\n', meta.timestamp);
    fprintf('  -> netra.loadModels now returns models.grader (isPlaceholder=false).\n');
end

% ========================================================================
function [imgs, labels] = loadSplitTable(root, aptos, which)
%LOADSPLITTABLE  Resolve split image paths + ICDR labels from validation/splits.mat.
    sp = fullfile(root, 'validation', 'splits.mat');
    assert(isfile(sp), 'NETRA:train:noSplits', ...
        'validation/splits.mat missing. Run registerDatasets; freezeSplits first.');
    S = load(sp, 'splits'); splits = S.splits;
    switch which
        case "train", ids = splits.train; g = splits.trainGrades;
        case "val",   ids = splits.val;   g = splits.valGrades;
        case "test",  ids = splits.test;  g = splits.testGrades;
    end
    imgs = strings(0,1); labels = [];
    subs = ["train_images","val_images","test_images"];
    for i = 1:numel(ids)
        [~, stem] = fileparts(char(ids(i)));
        for s = subs
            p = fullfile(aptos, s, stem + ".jpg");
            if isfile(p)
                imgs(end+1,1) = p;           %#ok<AGROW>
                labels(end+1,1) = g(i);      %#ok<AGROW>
                break;
            end
        end
    end
end

function ds = imgTable(paths, y, inSz)
%IMGTABLE  imageDatastore with Ben-Graham preprocessing + resize to inSz.
    imds = imageDatastore(cellstr(paths));
    lds  = arrayDatastore(y);
    ds0  = combine(imds, lds);
    ds   = transform(ds0, @(c) {benGrahamCell(c{1}, inSz), c{2}});
end

function out = benGrahamCell(img, inSz)
%BENGRAHAMCELL  Cheap Ben-Graham normalisation for training (no FOV mask needed):
%   subtract a large-sigma blur, rescale, resize to the model input.
    img = im2single(img);
    if size(img,3)==1, img = repmat(img,1,1,3); end
    s = 0.10 * max(size(img,1), size(img,2));
    bg = imgaussfilt(img, s);
    x = 4*(img - bg) + 0.5;                 % Ben-Graham style
    x = min(1, max(0, x));
    out = imresize(x, inSz);
end

function [net0, name] = makeBackbone(backbone, inSz, classes)
%MAKEBACKBONE  Pretrained backbone with a fresh 5-class head. Falls back to
%   squeezenet (ships with DLT) if resnet18's support package is absent.
    name = backbone;
    try
        if backbone == "resnet18"
            lg = layerGraph(resnet18);
            lg = replaceHead(lg, 'fc1000', 'ClassificationLayer_predictions', ...
                'prob', numel(classes), classes);
        else
            lg = layerGraph(squeezenet);
            lg = replaceHead(lg, 'conv10', 'ClassificationLayer_predictions', ...
                'prob', numel(classes), classes); %#ok<*NASGU>
        end
    catch ME
        warning('NETRA:train:backbone', ...
            '%s unavailable (%s); falling back to squeezenet.', backbone, ME.message);
        name = "squeezenet";
        lg = layerGraph(squeezenet);
        lg = replaceHead(lg, 'conv10', 'ClassificationLayer_predictions', ...
            'prob', numel(classes), classes);
    end
    net0 = lg;
end

function lg = replaceHead(lg, learnableName, classLayerName, ~, nClasses, classes)
%REPLACEHEAD  Swap the final learnable + classification layers for a 5-class head.
    newLearnable = fullyConnectedLayer(nClasses, 'Name', 'fc_dr', ...
        'WeightLearnRateFactor', 10, 'BiasLearnRateFactor', 10);
    try
        lg = replaceLayer(lg, learnableName, newLearnable);
    catch
        % squeezenet's learnable is a conv layer
        newConv = convolution2dLayer(1, nClasses, 'Name', 'fc_dr', ...
            'WeightLearnRateFactor', 10, 'BiasLearnRateFactor', 10);
        lg = replaceLayer(lg, learnableName, newConv);
    end
    lg = replaceLayer(lg, classLayerName, ...
        classificationLayer('Name', 'dr_out', 'Classes', classes));
end

function lg = setWeightedClassificationLayer(lg, classes, w)
%SETWEIGHTEDCLASSIFICATIONLAYER  Use class weights to counter APTOS grade-0 skew.
    try
        newOut = classificationLayer('Name', 'dr_out', 'Classes', classes, ...
            'ClassWeights', w(:)');
        lg = replaceLayer(lg, 'dr_out', newOut);
    catch
        % Older releases: ClassWeights unsupported -> leave unweighted (documented).
        warning('NETRA:train:noClassWeights', ...
            'Weighted classification layer unavailable; training unweighted.');
    end
end

function keep = subsampleStratified(labels, frac)
%SUBSAMPLESTRATIFIED  Keep `frac` of each grade (reproducible).
    rs = RandStream('mt19937ar','Seed',26038);
    keep = false(numel(labels),1);
    for g = 0:4
        idx = find(labels==g);
        n = max(1, round(frac*numel(idx)));
        sel = idx(randperm(rs, numel(idx), min(n,numel(idx))));
        keep(sel) = true;
    end
end

function k = quadraticKappa(y, yhat, classes)
%QUADRATICKAPPA  Quadratic-weighted Cohen's kappa (the APTOS metric).
    N = numel(classes);
    O = zeros(N);
    for i = 1:numel(y)
        O(y(i)+1, yhat(i)+1) = O(y(i)+1, yhat(i)+1) + 1;
    end
    W = (repmat((0:N-1)',1,N) - repmat(0:N-1,N,1)).^2 / (N-1)^2;
    r = sum(O,2); c = sum(O,1); E = (r*c)/sum(O(:));
    num = sum(W(:).*O(:)); den = sum(W(:).*E(:));
    if den == 0, k = 0; else, k = 1 - num/den; end
end

function h = configHash(cfg) %#ok<INUSD>
    try
        h = string(sprintf('%d', round(1e6*sum(double(char(jsonencode(cfg.thresholds.grading)))))));
    catch
        h = "UNHASHED";
    end
end

function s = splitSeed(root)
    try
        S = load(fullfile(root,'validation','splits.mat'),'splits');
        s = S.splits.seed;
    catch
        s = NaN;
    end
end
