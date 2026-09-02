function h = imageCanvas(parent)
%IMAGECANVAS  Image display with toggleable, blended overlay layers.
%   h = netra.ui.imageCanvas(parent) creates an image canvas (a uiaxes with
%   an image object) inside the given parent and returns a control struct:
%
%     h.Axes                     the uiaxes
%     h.setBase(rgb)             set the base image (HxWx3 uint8/double)
%     h.addLayer(name,mask,col)  add a coloured overlay for a logical mask
%     h.setLayerVisible(name,tf) show/hide a layer
%     h.setOpacity(name,alpha)   set a layer's opacity (0..1)
%     h.soloLesion(name)         dim all layers except NAME (empty = undim)
%     h.reset()                  reset zoom/pan to fit
%     h.redraw()                 force a recomposite
%
%   Smooth opacity: the base image and each layer's colour/mask are cached
%   once. setOpacity only re-runs a cheap per-pixel alpha blend over the
%   cached arrays - no mask recomputation, no file I/O - so dragging the
%   Grad-CAM opacity slider stays smooth.
%
%   Implemented with nested functions sharing this workspace, so the returned
%   handles all mutate the same layer state without globals or side files.

    t = netra.ui.theme();

    ax = uiaxes(parent);
    ax.Color = t.color.panel;
    ax.XColor = 'none'; ax.YColor = 'none';
    ax.XTick = []; ax.YTick = [];
    ax.Box = 'off';
    ax.DataAspectRatio = [1 1 1];
    ax.YDir = 'reverse';
    disableDefaultInteractivity(ax);

    % --- shared state (captured by the nested functions) -----------------
    base   = repmat(reshape(t.color.panel, 1, 1, 3), 8, 8);   % double 0..1
    layers = struct('name', {}, 'rgb', {}, 'mask', {}, ...
                    'visible', {}, 'alpha', {}, 'dim', {});
    imgObj = image(ax, base);

    composite();
    reset();

    h = struct('Axes', ax);
    h.setBase         = @setBase;
    h.addLayer        = @addLayer;
    h.setLayerVisible = @setLayerVisible;
    h.setOpacity      = @setOpacity;
    h.soloLesion      = @soloLesion;
    h.reset           = @reset;
    h.redraw          = @composite;

    % ==================== nested functions ===============================
    function setBase(rgb)
        base = toDouble(rgb);
        composite();
        reset();
    end

    function addLayer(name, mask, colorRGB)
        L = struct('name', char(name), 'rgb', colorRGB(:)', ...
            'mask', logical(mask), 'visible', false, 'alpha', 0.6, 'dim', false);
        idx = layerIndex(name);
        if isempty(idx), layers(end+1) = L; else, layers(idx) = L; end
    end

    function setLayerVisible(name, tf)
        idx = layerIndex(name);
        if ~isempty(idx)
            layers(idx).visible = logical(tf);
            composite();
        end
    end

    function setOpacity(name, alpha)
        idx = layerIndex(name);
        if ~isempty(idx)
            layers(idx).alpha = max(0, min(1, alpha));
            composite();   % cheap re-blend of cached arrays only
        end
    end

    function soloLesion(name)
        for k = 1:numel(layers)
            layers(k).dim = ~isempty(name) && ~strcmp(layers(k).name, char(name));
        end
        composite();
    end

    function reset()
        [H, W, ~] = size(base);
        ax.XLim = [0.5 W+0.5];
        ax.YLim = [0.5 H+0.5];
    end

    function idx = layerIndex(name)
        if isempty(layers), idx = []; return; end
        idx = find(strcmp({layers.name}, char(name)), 1);
    end

    function composite()
        out = base;
        [H, W, ~] = size(out);
        for k = 1:numel(layers)
            L = layers(k);
            if ~L.visible || isempty(L.mask), continue; end
            m = L.mask;
            if ~isequal(size(m), [H W]), m = resizeMask(m, H, W); end
            a = L.alpha;
            if L.dim, a = a * 0.15; end
            for c = 1:3
                ch = out(:,:,c);
                ch(m) = (1-a)*ch(m) + a*L.rgb(c);
                out(:,:,c) = ch;
            end
        end
        if isempty(imgObj) || ~isvalid(imgObj)
            imgObj = image(ax, out);
        else
            imgObj.CData = out;
        end
    end
end

% ---- helpers (no shared state) -----------------------------------------
function d = toDouble(rgb)
%TODOUBLE  Image to double 0..1 without Image Processing Toolbox.
    if isa(rgb, 'uint8')
        d = double(rgb) / 255;
    elseif isa(rgb, 'uint16')
        d = double(rgb) / 65535;
    else
        d = double(rgb);
        if ~isempty(d) && max(d(:)) > 1, d = d / max(d(:)); end
    end
    if size(d,3) == 1, d = repmat(d, 1, 1, 3); end
end

function m2 = resizeMask(m, H, W)
%RESIZEMASK  Nearest-neighbour mask resize (no toolbox dependency).
    [h, w] = size(m);
    ri = max(1, round((1:H)/H * h));
    ci = max(1, round((1:W)/W * w));
    m2 = m(ri, ci);
end
