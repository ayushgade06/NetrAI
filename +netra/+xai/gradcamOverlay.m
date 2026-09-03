function [heat, info] = gradcamOverlay(net, modelInput, classIdx, cfg)
%GRADCAMOVERLAY  Grad-CAM class-activation heatmap for the DR grader.  [Track D]
%   [heat, info] = netra.xai.gradcamOverlay(net, modelInput, classIdx, cfg)
%
%   Returns HEAT, a single-precision map the SAME height/width as modelInput,
%   normalised to [0,1], where high values are the regions the network relied on
%   for the predicted class. Feeds netra.xai.agreementScore (ALA) and the
%   Workbench Grad-CAM panel.
%
%   INPUTS
%     net        - the trained grader (SeriesNetwork/DAGNetwork from
%                  trainNetwork, or a dlnetwork).
%     modelInput - HxWx3 image the grade was computed on (single, 0..1 or uint8).
%     classIdx   - target class index 1..5 (ICDR 0..4 + 1). Defaults to the
%                  predicted class if out of range.
%     cfg        - config (reserved; colormap etc. live in cfg.thresholds.xai).
%
%   info.layer     the feature layer used
%   info.method    "gradcam" (dlnetwork gradients) or "cam-fallback" (weights)
%
%   Uses MATLAB's built-in gradCAM when available (Deep Learning Toolbox); falls
%   back to a manual dlnetwork Grad-CAM so it works across releases. Never
%   fabricates - errors only if no activation map can be produced, which the
%   caller (explain.m) catches and degrades to ALA=NaN.

    arguments
        net
        modelInput
        classIdx (1,1) double = 1
        cfg struct = struct()  %#ok<INUSA>
    end

    % --- normalise the input to single HxWx3 in [0,1] -------------------
    x = modelInput;
    if ~isa(x,'single'), x = im2single(x); end
    if size(x,3) == 1, x = repmat(x,1,1,3); end
    inSz = [size(x,1) size(x,2)];

    % --- clamp class index ----------------------------------------------
    nClasses = numClassesOf(net);
    if classIdx < 1 || classIdx > nClasses || ~isfinite(classIdx)
        classIdx = 1;
    end

    % --- 1) built-in gradCAM (simplest, most robust) --------------------
    try
        map = gradCAM(net, x, classIdx);
        heat = normmap(imresize(single(map), inSz));
        info = struct('layer', "auto", 'method', "gradcam-builtin");
        return;
    catch
        % fall through to the manual implementation
    end

    % --- 2) manual Grad-CAM via dlnetwork -------------------------------
    lname = lastConvLayer(net);
    lg = layerGraphOf(net);
    dln = dlnetwork(removeClassificationLayers(lg));

    dlx = dlarray(x, 'SSCB');
    [~, actMap] = dlfeval(@camGradients, dln, dlx, classIdx, lname);
    heat = normmap(imresize(single(extractdata(actMap)), inSz));
    info = struct('layer', string(lname), 'method', "gradcam-dlnetwork");
end

% ========================================================================
function [score, cam] = camGradients(dln, dlx, classIdx, featLayer)
%CAMGRADIENTS  Forward to the score + feature maps, backprop to features.
    [scores, feats] = forward(dln, dlx, 'Outputs', {dln.OutputNames{1}, featLayer});
    score = scores(classIdx);
    grad  = dlgradient(score, feats);                 % dScore/dFeature
    w = mean(grad, [1 2]);                             % GAP over spatial dims
    cam = sum(w .* feats, 3);                          % weighted feature sum
    cam = max(cam, 0);                                 % ReLU (positive influence)
    cam = squeeze(cam);
end

function m = normmap(m)
%NORMMAP  Scale to [0,1]; flat map -> zeros (no fabricated structure).
    m = double(m);
    lo = min(m(:)); hi = max(m(:));
    if hi > lo
        m = (m - lo) / (hi - lo);
    else
        m = zeros(size(m));
    end
    m = single(m);
end

function n = numClassesOf(net)
    try
        if isa(net,'dlnetwork')
            n = 5;                                     % grader head is 5-class
        else
            L = net.Layers(end);
            if isprop(L,'Classes') && ~isempty(L.Classes)
                n = numel(L.Classes);
            else
                n = 5;
            end
        end
    catch
        n = 5;
    end
end

function name = lastConvLayer(net)
%LASTCONVLAYER  Name of the deepest 2-D convolution layer (Grad-CAM feature src).
    layers = net.Layers;
    name = '';
    for i = 1:numel(layers)
        if isa(layers(i), 'nnet.cnn.layer.Convolution2DLayer')
            name = layers(i).Name;
        end
    end
    if name == ""
        error('NETRA:xai:noConvLayer', 'No convolution layer found for Grad-CAM.');
    end
end

function lg = layerGraphOf(net)
    if isa(net,'dlnetwork')
        lg = net;
    else
        lg = layerGraph(net);
    end
end

function lg = removeClassificationLayers(lg)
%REMOVECLASSIFICATIONLAYERS  Strip the output classificationLayer so the graph is
%   a valid dlnetwork (softmax kept as the score source).
    try
        names = {lg.Layers.Name};
        for i = 1:numel(lg.Layers)
            if isa(lg.Layers(i), 'nnet.cnn.layer.ClassificationOutputLayer')
                lg = removeLayers(lg, names{i});
            end
        end
    catch
    end
end
