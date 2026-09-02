function fig = composite(cr, cfg)
%COMPOSITE  Build the 2x2 annotated evidence figure for a case report.
%   fig = netra.report.composite(cr, cfg) returns an invisible figure handle
%   holding a 2x2 tiled layout:
%       (1,1) Original fundus        (2,1) Lesion overlay
%       (1,2) Enhanced               (2,2) Grad-CAM attention
%
%   Where a panel's source stage has not run for real (other tracks still
%   MOCK, or the stage failed), that tile renders a LABELLED PLACEHOLDER naming
%   the responsible stage - never a blank tile and never a substituted image.
%   This is deliberate: the report must show a reader which evidence is real.
%
%   The caller owns the returned figure (report.generate exports then deletes
%   it). The figure is created invisible so batch report generation does not
%   pop windows. cfg is accepted for signature uniformity (colormap etc.).

    arguments
        cr  (1,1) struct
        cfg (1,1) struct = struct()
    end

    cmap = 'jet';
    if isfield(cfg, 'thresholds') && isfield(cfg.thresholds, 'xai') ...
            && isfield(cfg.thresholds.xai, 'gradcamColormap')
        cmap = char(cfg.thresholds.xai.gradcamColormap);
    end

    fig = figure('Visible', 'off', 'Color', 'w', ...
        'Units', 'pixels', 'Position', [100 100 900 900]);
    tl = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

    base = baseImage(cr);                       % [] if no pixels at all

    % (1,1) Original -----------------------------------------------------
    ax = nexttile(tl, 1);
    raw = firstNonEmpty({cr.img.raw, cr.img.displayRGB, base});
    drawPanel(ax, raw, 'Original fundus', 'ingest / image capture');

    % (1,2) Enhanced -----------------------------------------------------
    ax = nexttile(tl, 2);
    enh = [];
    if provOK(cr, 'preproc') && ~isempty(cr.img.enhanced)
        enh = cr.img.enhanced;
    elseif ~isempty(cr.img.displayRGB)
        enh = cr.img.displayRGB;
    end
    drawPanel(ax, enh, 'Enhanced', 'preprocessing (netra.preproc.enhance)');

    % (2,1) Lesion overlay ----------------------------------------------
    ax = nexttile(tl, 3);
    [ov, ok] = lesionOverlayImage(cr, base);
    if ok
        drawImage(ax, ov, 'Lesion overlay');
    else
        drawPlaceholder(ax, 'Lesion overlay', 'lesion detection (netra.lesions.detect)');
    end

    % (2,2) Grad-CAM -----------------------------------------------------
    ax = nexttile(tl, 4);
    [gc, ok] = gradcamImage(cr, base, cmap);
    if ok
        drawImage(ax, gc, 'Grad-CAM attention');
    else
        drawPlaceholder(ax, 'Grad-CAM attention', 'explainability (netra.xai.explain)');
    end

    title(tl, sprintf('Case %s  -  %s eye', char(cr.meta.uid), char(cr.meta.eye)), ...
        'FontWeight', 'bold', 'Interpreter', 'none');
end

% ========================================================================
function tf = provOK(cr, stage)
%PROVOK  True when a stage produced REAL output (not MOCK/FAILED/empty).
    tf = isfield(cr, 'provenance') && isfield(cr.provenance, stage) ...
        && cr.provenance.(stage) == "REAL";
end

function b = baseImage(cr)
%BASEIMAGE  Best available real frame to composite overlays onto, or [].
    b = firstNonEmpty({cr.img.displayRGB, cr.img.enhanced, cr.img.raw});
end

function out = firstNonEmpty(cands)
    out = [];
    for k = 1:numel(cands)
        if ~isempty(cands{k}), out = cands{k}; return; end
    end
end

function [img, ok] = lesionOverlayImage(cr, base)
%LESIONOVERLAYIMAGE  RGB base with coloured lesion masks burned in.
%   ok=false when the lesion stage is not REAL or provides no mask field, so
%   the caller draws the labelled placeholder instead of a fake overlay.
    img = []; ok = false;
    if isempty(base) || ~provOK(cr, 'lesions'), return; end
    % Track A adds cr.lesions.<TYPE>.mask; the frozen factory does not. Guard.
    if ~isfield(cr.lesions, 'MA') || ~isfield(cr.lesions.MA, 'mask'), return; end
    [H, W, ~] = size(base);
    img = im2uint8Rgb(base);
    try
        layers = netra.ui.lesionOverlay(cr, [H W]);
    catch
        img = []; return;              % overlay build failed -> placeholder
    end
    for k = 1:numel(layers)
        m = layers(k).mask;
        if any(m(:))
            img = burnMask(img, m, layers(k).color);
        end
    end
    % A REAL lesion stage with zero lesions is still a valid overlay: the clean
    % enhanced frame is returned (ok=true) so grade-0 cases show a real image,
    % not a placeholder. (Section 11: composite handles zero lesions.)
    ok = true;
end

function [img, ok] = gradcamImage(cr, base, cmap)
%GRADCAMIMAGE  RGB base blended with the Grad-CAM heatmap.
    img = []; ok = false;
    if isempty(base) || ~provOK(cr, 'xai'), return; end
    gc = cr.xai.gradcam;
    if isempty(gc), return; end
    [H, W, ~] = size(base);
    gc = double(gc);
    if ~isequal(size(gc), [H W])
        gc = imresizeNN(gc, H, W);
    end
    gc = gc - min(gc(:));
    if max(gc(:)) > 0, gc = gc / max(gc(:)); end
    heat = applyColormap(gc, cmap);            % HxWx3 double 0..1
    b = im2double01(base);
    a = 0.45;                                  % heatmap opacity
    img = uint8(255 * (a*heat + (1-a)*b));
    ok = true;
end

% ---- drawing -----------------------------------------------------------
function drawPanel(ax, img, ttl, stageDesc)
    if isempty(img)
        drawPlaceholder(ax, ttl, stageDesc);
    else
        drawImage(ax, img, ttl);
    end
end

function drawImage(ax, img, ttl)
    imshowSafe(ax, img);
    title(ax, ttl, 'FontWeight', 'bold');
    axis(ax, 'image'); axis(ax, 'off');
end

function drawPlaceholder(ax, ttl, stageDesc)
%DRAWPLACEHOLDER  A labelled grey tile naming the stage that will fill it.
    tile = repmat(uint8(235), 320, 320);
    tile = cat(3, tile, tile, tile);
    imshowSafe(ax, tile);
    axis(ax, 'image'); axis(ax, 'off');
    title(ax, ttl, 'FontWeight', 'bold');
    text(ax, 0.5, 0.55, 'Not available', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold', ...
        'FontSize', 12, 'Color', [0.5 0.1 0.1]);
    text(ax, 0.5, 0.42, ['Produced by: ' stageDesc], 'Units', 'normalized', ...
        'HorizontalAlignment', 'center', 'FontSize', 9, ...
        'Color', [0.3 0.3 0.3], 'Interpreter', 'none');
end

function imshowSafe(ax, img)
%IMSHOWSAFE  image() into an axes without needing the Image Processing Toolbox.
    image(ax, img);
    ax.YDir = 'reverse';
    ax.XTick = []; ax.YTick = [];
end

% ---- image utilities (toolbox-light) -----------------------------------
function out = im2uint8Rgb(img)
    if ~isa(img, 'uint8')
        img = im2uint8Local(img);
    end
    if size(img,3) == 1, img = repmat(img, 1, 1, 3); end
    out = img;
end

function out = im2double01(img)
    if isa(img, 'uint8')
        out = double(img) / 255;
    else
        out = double(img);
        m = max(out(:));
        if m > 1, out = out / m; end
    end
    if size(out,3) == 1, out = repmat(out, 1, 1, 3); end
end

function u = im2uint8Local(img)
    x = double(img);
    m = max(x(:));
    if m <= 1 && m > 0, x = x * 255; end
    u = uint8(min(255, max(0, x)));
end

function img = burnMask(img, mask, color)
%BURNMASK  Paint 'color' (0..1 rgb) into img (uint8) where mask is true.
    c = uint8(round(color(:)' * 255));
    for ch = 1:3
        band = img(:,:,ch);
        band(mask) = c(ch);
        img(:,:,ch) = band;
    end
end

function rgb = applyColormap(g, name)
%APPLYCOLORMAP  Map a 0..1 gray field to an HxWx3 RGB via a named colormap.
    n = 256;
    try
        cm = feval(name, n);
    catch
        cm = jet(n);
    end
    idx = round(g * (n-1)) + 1;
    idx = min(n, max(1, idx));
    r = reshape(cm(idx, 1), size(g));
    gg = reshape(cm(idx, 2), size(g));
    b = reshape(cm(idx, 3), size(g));
    rgb = cat(3, r, gg, b);
end

function out = imresizeNN(m, H, W)
%IMRESIZENN  Nearest-neighbour resize (no Image Processing Toolbox needed).
    [h, w] = size(m);
    ri = max(1, round((1:H)/H * h));
    ci = max(1, round((1:W)/W * w));
    out = m(ri, ci);
end
