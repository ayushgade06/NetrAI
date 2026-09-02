function out = train_quality(opts)
%TRAIN_QUALITY  Train the shallow quality classifier on eight handcrafted feats.
%   out = train_quality() loads training/quality_trainset.mat, trains an
%   SVM-RBF (fitcecoc) and a bagged-tree ensemble (fitcensemble), picks the
%   better by 5-fold cross-validated accuracy, and saves the winner with full
%   metadata to models/quality_clf.mat.
%
%   NO DEEP LEARNING (deliberate): both models train in seconds, are
%   interpretable, and every input feature maps to a displayable subscore.
%
%   REPRODUCIBILITY: rng(Seed) is set before any split/train and the seed is
%   saved in the model file. Same trainset + seed -> same model.
%
%   The saved struct `qmodel` contains exactly (per the Phase 3 brief):
%     .model         the trained classifier
%     .modelType     "svm-rbf" | "bagged-trees"
%     .featureNames  1x8 cellstr, the FEATURE ORDER
%     .mu, .sigma    z-score normalisation params (fit on TRAIN features)
%     .classNames    ordered class labels
%     .config        the training config used (folds, seed, chosen-by)
%     .cvAccuracy    the winner's cross-validated accuracy
%     .rngSeed       the rng seed
%     .trainedAt     timestamp string
%     .matlabVersion version string
%   models/quality_clf.mat stores it under the variable name `qmodel`.
%
%   opts (name-value):
%     'TrainFile' path to quality_trainset.mat  (default repo path)
%     'OutFile'   path to quality_clf.mat        (default repo path)
%     'Folds'     CV folds                        (default 5)
%     'Seed'      rng seed                         (default 26038)

    arguments
        opts.TrainFile (1,:) char = defaultPath('training','quality_trainset.mat')
        opts.OutFile   (1,:) char = defaultPath('models','quality_clf.mat')
        opts.Folds     (1,1) double = 5
        opts.Seed      (1,1) double = 26038
    end

    if ~license('test','Statistics_Toolbox') || exist('fitcecoc','file') ~= 2
        error('NETRA:quality:noStatsToolbox', ...
            ['Statistics and Machine Learning Toolbox is required for training. ' ...
             'Without it, use the rule-based fallback (netra.quality.classifyRuleBased).']);
    end
    if ~isfile(opts.TrainFile)
        error('NETRA:quality:noTrainset', ...
            'Trainset not found: %s. Run training/make_degradations first.', opts.TrainFile);
    end

    T = load(opts.TrainFile);
    X = T.X; y = categorical(T.labels);
    assert(size(X,2) == 8, 'Expected 8 features, got %d.', size(X,2));

    rng(opts.Seed);                          % reproducible split + training

    % z-score normalise (params saved for inference-time normalisation).
    mu = mean(X,1); sigma = std(X,0,1); sigma(sigma == 0) = 1;
    Xn = (X - mu) ./ sigma;

    % --- candidate 1: SVM-RBF (multiclass via ECOC) ---------------------
    tSVM = templateSVM('KernelFunction','rbf','KernelScale','auto','Standardize',false);
    svm = fitcecoc(Xn, y, 'Learners', tSVM);
    cvSVM = crossval(svm, 'KFold', opts.Folds);
    accSVM = 1 - kfoldLoss(cvSVM);

    % --- candidate 2: bagged trees --------------------------------------
    bag = fitcensemble(Xn, y, 'Method','Bag', 'NumLearningCycles', 100, ...
        'Learners', templateTree('MaxNumSplits', 20));
    cvBag = crossval(bag, 'KFold', opts.Folds);
    accBag = 1 - kfoldLoss(cvBag);

    % --- pick the better by CV accuracy (tie -> bagged, for importance) ---
    if accSVM > accBag
        model = svm; modelType = "svm-rbf"; cvAcc = accSVM;
        chosenBy = sprintf('SVM-RBF CV acc %.4f > bagged %.4f', accSVM, accBag);
    else
        model = bag; modelType = "bagged-trees"; cvAcc = accBag;
        chosenBy = sprintf('bagged CV acc %.4f >= SVM-RBF %.4f', accBag, accSVM);
    end

    qmodel = struct();
    qmodel.model         = model;
    qmodel.modelType     = modelType;
    qmodel.featureNames  = netra.quality.featureNames();
    qmodel.mu            = mu;
    qmodel.sigma         = sigma;
    qmodel.classNames    = categories(y);
    qmodel.config        = struct('folds', opts.Folds, 'seed', opts.Seed, ...
                                  'chosenBy', chosenBy, ...
                                  'accSVM', accSVM, 'accBag', accBag);
    qmodel.cvAccuracy    = cvAcc;
    qmodel.rngSeed       = opts.Seed;
    qmodel.trainedAt     = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
    qmodel.matlabVersion = version;

    ensureDir(opts.OutFile);
    save(opts.OutFile, 'qmodel', '-v7');

    fprintf('train_quality: chose %s (CV acc %.4f). %s\n', modelType, cvAcc, chosenBy);
    fprintf('Saved -> %s\n', opts.OutFile);

    out = qmodel;
end

% ------------------------------------------------------------------------
function ensureDir(f)
    d = fileparts(f);
    if ~isempty(d) && ~isfolder(d), mkdir(d); end
end

function p = defaultPath(varargin)
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    p = fullfile(root, varargin{:});
end
