function img = realImage(kind, n)
%REALIMAGE  A real fundus image from the on-disk dataset, or [] if absent.
%   img = realImage("clean")     -> a grade-0 (no-DR) APTOS fundus (uint8 HxWx3)
%   img = realImage("clean", n)  -> the same, centre-cropped/resized to n x n
%   img = realImage("any")       -> any APTOS fundus regardless of grade
%
%   Returns [] when datasets/aptos2019 is not present, so callers can fall back
%   to a synthetic fixture and the suite still runs on a fresh clone.
%
%   This lets quality/lesion/structure tests exercise the algorithms on REAL
%   pixels once APTOS is on disk, instead of only on synthetic disc-on-black
%   patterns whose statistics differ from real fundus photography.

    arguments
        kind (1,1) string = "clean"
        n    (1,1) double = 0
    end

    img = [];
    root = fileparts(fileparts(mfilename('fullpath')));   % project root
    aptos = fullfile(root, 'datasets', 'aptos2019');
    if ~isfolder(aptos), return; end

    % Pick a labelled image: grade 0 for "clean", else the first available.
    stem = pickStem(aptos, kind);
    if stem == "", return; end

    % The image lives under one of the split folders; find it by stem.
    for sub = ["train_images","val_images","test_images"]
        p = fullfile(aptos, sub, char(stem) + ".jpg");
        if isfile(p)
            img = imread(p);
            if size(img,3) == 1, img = repmat(img,1,1,3); end
            img = im2uint8(img);
            if n > 0, img = squareResize(img, n); end
            return;
        end
    end
end

% ------------------------------------------------------------------------
function stem = pickStem(aptos, kind)
%PICKSTEM  First image id whose grade matches the request (0 for "clean").
    stem = "";
    for csv = ["train_1.csv","valid.csv","test.csv"]
        f = fullfile(aptos, char(csv));
        if ~isfile(f), continue; end
        T = readtable(f, 'TextType','string');
        vn = lower(string(T.Properties.VariableNames));
        idCol = find(contains(vn,"id"),1);
        gCol  = find(contains(vn,"diagn")|contains(vn,"grade")|contains(vn,"level"),1);
        if isempty(idCol), continue; end
        ids = string(T{:,idCol});
        if kind == "clean" && ~isempty(gCol)
            g = double(T{:,gCol});
            cand = sort(ids(g == 0));      % SORTED -> deterministic across clones
        else
            cand = sort(ids);
        end
        if ~isempty(cand), stem = cand(1); return; end
    end
end

function out = squareResize(img, n)
%SQUARERESIZE  Centre-crop to square then resize to n x n (keeps aspect).
    [h,w,~] = size(img);
    s = min(h,w);
    r0 = floor((h-s)/2)+1; c0 = floor((w-s)/2)+1;
    out = imresize(img(r0:r0+s-1, c0:c0+s-1, :), [n n]);
end
