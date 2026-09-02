function lesion_contact_sheet(imgPaths, outPath)
%LESION_CONTACT_SHEET  Contact sheet of lesion overlays for manual inspection.  [Track A]
%   lesion_contact_sheet() processes up to 30 images (the demo set, or IDRiD/
%   APTOS if placed under datasets/) through the REAL structures+lesions stages,
%   draws the per-class lesion overlay on each (MA red, HE dark red, EX yellow,
%   OD ring green), tiles them, and saves docs/figures/lesion_overlays.png for
%   the mandatory manual verification (§11 of the brief).
%
%   lesion_contact_sheet(imgPaths, outPath) uses an explicit image list/output.
%
%   Prints a per-image count of detected MA/HE/EX so the inspector can note
%   obvious false positives and whether the OD was ever caught as an exudate.
%   It fabricates nothing - only what the detector produced is drawn.

    cfg = netra.loadConfig();
    root = repoRoot();
    if nargin < 2 || isempty(outPath)
        outPath = fullfile(root, 'docs', 'figures', 'lesion_overlays.png');
    end
    if nargin < 1 || isempty(imgPaths)
        imgPaths = gatherImages(root, 30);
    end
    if isempty(imgPaths)
        fprintf('lesion_contact_sheet: no images found - nothing produced.\n'); return;
    end
    if ~isfolder(fileparts(outPath)), mkdir(fileparts(outPath)); end

    n = numel(imgPaths);
    cols = ceil(sqrt(n)); rows = ceil(n/cols);
    fig = figure('Visible','off','Color','k','Position',[0 0 300*cols 300*rows]);
    tl = tiledlayout(fig, rows, cols, 'Padding','compact','TileSpacing','compact');

    fprintf('\nlesion_contact_sheet: %d images\n', n);
    for i = 1:n
        [img, ok] = tryRead(imgPaths{i});
        ax = nexttile(tl);
        if ~ok, axis(ax,'off'); continue; end

        cr = netra.newCaseRecord(imgPaths{i});
        cr.img.raw = img;
        cr = netra.preproc.enhance(cr, cfg);
        cr = netra.structures.segment(cr, cfg);
        cr = netra.lesions.detect(cr, cfg);

        rgb = drawOverlay(cr);
        imshow(rgb, 'Parent', ax);
        title(ax, sprintf('MA %d  HE %d  EX %d', cr.lesions.MA.count, ...
            cr.lesions.HE.count, cr.lesions.EX.count), 'Color','w','FontSize',8);
        fprintf('  %-28s  MA %d  HE %d  EX %d  odFallback=%d\n', ...
            shortName(imgPaths{i}), cr.lesions.MA.count, cr.lesions.HE.count, ...
            cr.lesions.EX.count, cr.structures.odFallback);
    end

    exportgraphics(fig, outPath, 'Resolution', 120);
    close(fig);
    fprintf('lesion_contact_sheet: wrote %s\n', outPath);
    fprintf(['INSPECT %s: count images with obvious false positives, their ' ...
        'cause, and whether the OD ring ever coincides with a yellow EX blob.\n'], outPath);
end

% ========================================================================
function rgb = drawOverlay(cr)
    rgb = cr.img.displayRGB; if isempty(rgb), rgb = cr.img.enhanced; end
    rgb = im2uint8(rgb);
    S = cr.structures;
    [H, W, ~] = size(rgb);

    % lesion layers
    lay = netra.ui.lesionOverlay(cr, [H W]);
    for k = 1:numel(lay)
        rgb = tint(rgb, lay(k).mask, lay(k).color, 0.7);
    end
    % OD ring (green) so the inspector can see OD-vs-EX coincidence
    if all(isfinite(S.odCenter)) && isfinite(S.odRadius) && S.odRadius > 0
        [X,Y] = meshgrid(1:W,1:H); d2 = (X-S.odCenter(1)).^2 + (Y-S.odCenter(2)).^2;
        ring = d2 <= (S.odRadius+2)^2 & d2 >= (S.odRadius-2)^2;
        rgb = tint(rgb, ring, [0.2 0.9 0.3], 0.9);
    end
end

function rgb = tint(rgb, mask, color, a)
    if ~any(mask(:)), return; end
    for c = 1:3
        ch = double(rgb(:,:,c));
        ch(mask) = (1-a)*ch(mask) + a*255*color(c);
        rgb(:,:,c) = uint8(ch);
    end
end

function paths = gatherImages(root, maxN)
    paths = {};
    % Prefer IDRiD/APTOS (real grades); else the demo set.
    cand = { fullfile(root,'datasets','idrid'), ...
             fullfile(root,'datasets','aptos2019'), ...
             fullfile(root,'data','demo') };
    for c = 1:numel(cand)
        if ~isfolder(cand{c}), continue; end
        d = dir(fullfile(cand{c}, '**', '*.*')); d = d(~[d.isdir]);
        for i = 1:numel(d)
            [~,~,e] = fileparts(d(i).name);
            if any(strcmpi(e, {'.jpg','.jpeg','.png','.tif','.tiff'}))
                paths{end+1} = fullfile(d(i).folder, d(i).name); %#ok<AGROW>
            end
            if numel(paths) >= maxN, return; end
        end
        if ~isempty(paths), return; end
    end
end

function [img, ok] = tryRead(f)
    img = []; ok = false;
    try
        img = imread(f); if size(img,3)==1, img = repmat(img,1,1,3); end
        if ~isa(img,'uint8'), img = im2uint8(img); end
        ok = true;
    catch
    end
end

function s = shortName(p)
    [~,n,e] = fileparts(p); s = [n e];
end

function r = repoRoot()
    r = fileparts(fileparts(mfilename('fullpath')));
end
