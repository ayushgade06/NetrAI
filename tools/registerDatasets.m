function manifest = registerDatasets(roots)
%REGISTERDATASETS  Scan dataset roots and write data/dataset_manifest.mat.
%   manifest = registerDatasets() scans the default roots (see below) for the
%   four NETRA datasets, reports how many images and label files were found for
%   each, and writes data/dataset_manifest.mat. It DOWNLOADS NOTHING. A dataset
%   that is absent on disk is recorded as absent - a manifest is never fabricated.
%
%   manifest = registerDatasets(roots) uses an explicit struct of roots:
%     roots.aptos, roots.idrid, roots.drive, roots.messidor2  (char/string dirs)
%   Missing fields fall back to the defaults under <project>/datasets/<name>.
%
%   manifest is a struct with one field per dataset, each:
%     .present      logical
%     .root         string  (the path scanned)
%     .imageCount   double
%     .images       string array of relative image paths (empty if absent)
%     .labelFiles   string array of candidate label files (.csv/.xls*/.txt)
%     .note         string  human summary
%
%   Run from a MATLAB session after startup_netra (tools/ is on the path).

    here = fileparts(mfilename('fullpath'));   % tools/
    root = fileparts(here);                    % project root
    dsRoot = fullfile(root, 'datasets');

    defaults = struct( ...
        'aptos',     fullfile(dsRoot, 'aptos2019'), ...
        'idrid',     fullfile(dsRoot, 'idrid'), ...
        'drive',     fullfile(dsRoot, 'drive'), ...
        'messidor2', fullfile(dsRoot, 'messidor2'));

    if nargin < 1, roots = struct(); end
    names = fieldnames(defaults);

    imgExts = [".jpg",".jpeg",".png",".tif",".tiff",".ppm",".gif"];
    lblExts = [".csv",".xls",".xlsx",".txt"];

    manifest = struct();
    fprintf('registerDatasets: scanning (no downloads)\n');
    for k = 1:numel(names)
        nm = names{k};
        if isfield(roots, nm) && ~isempty(roots.(nm))
            dir_ = char(roots.(nm));
        else
            dir_ = defaults.(nm);
        end

        entry = struct('present', false, 'root', string(dir_), ...
            'imageCount', 0, 'images', strings(0,1), ...
            'labelFiles', strings(0,1), 'note', "");

        if isfolder(dir_)
            imgs = listByExt(dir_, imgExts);
            lbls = listByExt(dir_, lblExts);
            entry.present    = true;
            entry.images     = imgs;
            entry.imageCount = numel(imgs);
            entry.labelFiles = lbls;
            entry.note = sprintf("%d image(s), %d label file(s)", ...
                numel(imgs), numel(lbls));
        else
            entry.note = "ABSENT on disk - not downloaded, recorded as absent.";
        end

        manifest.(nm) = entry;
        fprintf('  %-10s : %s  [%s]\n', nm, entry.note, dir_);
    end

    outDir = fullfile(root, 'data');
    if ~isfolder(outDir), mkdir(outDir); end
    outPath = fullfile(outDir, 'dataset_manifest.mat');
    save(outPath, 'manifest');
    fprintf('registerDatasets: wrote %s\n', outPath);
end

% ------------------------------------------------------------------------
function rel = listByExt(root, exts)
%LISTBYEXT  Recursive relative-path list of files with the given extensions.
    all = dir(fullfile(root, '**', '*'));
    rel = strings(0,1);
    for k = 1:numel(all)
        if all(k).isdir, continue; end
        [~,~,e] = fileparts(all(k).name);
        if ismember(lower(string(e)), exts)
            full = fullfile(all(k).folder, all(k).name);
            rel(end+1,1) = string(erase(full, [root filesep])); %#ok<AGROW>
        end
    end
    rel = sort(rel);
end
