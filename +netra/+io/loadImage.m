function [img, info] = loadImage(path)
%LOADIMAGE  Decode a fundus image to uint8 HxWx3 with capture metadata.
%   [img, info] = netra.io.loadImage(path) reads the image at `path`, returns
%   it as a uint8 HxWx3 array, and returns an info struct.
%
%   Behaviour:
%     - Refuses any path inside the quarantine (Messidor-2 held-out set) via
%       netra.io.assertNotQuarantined -> NETRA:io:quarantined.
%     - Rejects unsupported extensions -> NETRA:io:unsupportedFormat.
%     - Rejects unreadable/corrupt files -> NETRA:io:unreadable.
%     - Grayscale input: replicated to 3 channels, and info.wasGrayscale=true
%       so the caller can log a "grayscaleReplicated" step (never silent).
%     - RGBA / >3 channels: keeps the first three channels (drops alpha).
%     - uint16 / double input: rescaled to uint8 (fundus JPEGs are 8-bit; a
%       16-bit TIFF is downcast so the rest of the pipeline sees one type).
%
%   info fields:
%     originalSize   [H W C]   dimensions as decoded (before channel fixups)
%     fileBytes      double     size of the file on disk
%     format         string     lower-case extension without the dot, e.g. "jpg"
%     colorType      string     "truecolor" | "grayscale" | "indexed" | "unknown"
%     wasGrayscale   logical    true if a 1-channel image was replicated
%
%   NOTE: format validation here is by EXTENSION plus a real decode attempt;
%   structural validity (size, aspect, channels) is netra.io.validateImage.

    arguments
        path (1,:) char
    end

    netra.io.assertNotQuarantined(path);

    if ~isfile(path)
        error('NETRA:io:fileNotFound', 'Image not found: %s', path);
    end

    [~, ~, ext] = fileparts(path);
    fmt = lower(erase(ext, '.'));
    supported = ["jpg","jpeg","png","tif","tiff"];
    if ~ismember(string(fmt), supported)
        error('NETRA:io:unsupportedFormat', ...
            'Unsupported format ".%s" for "%s". Supported: %s', ...
            fmt, path, strjoin("." + supported, ", "));
    end

    d = dir(path);
    fileBytes = d.bytes;

    % Probe metadata, then decode. imfinfo/imread throw on corrupt files; wrap
    % both so the error identifier is NETRA-prefixed and the batch loop can
    % skip the file cleanly.
    try
        meta = imfinfo(path);
        raw  = imread(path);
    catch ME
        error('NETRA:io:unreadable', ...
            'Cannot read image "%s": %s', path, ME.message);
    end
    meta = meta(1);   % multi-frame TIFFs: first frame only

    colorType = "unknown";
    if isfield(meta, 'ColorType') && ~isempty(meta.ColorType)
        colorType = string(meta.ColorType);
    end

    originalSize = size(raw, 1, 2, 3);

    % --- channel normalisation ------------------------------------------
    wasGrayscale = false;
    if ismatrix(raw)                          % HxW grayscale
        raw = repmat(raw, 1, 1, 3);
        wasGrayscale = true;
        colorType = "grayscale";
    elseif size(raw, 3) == 1                  % HxWx1
        raw = repmat(raw, 1, 1, 3);
        wasGrayscale = true;
        colorType = "grayscale";
    elseif size(raw, 3) > 3                   % RGBA / multi-channel
        raw = raw(:, :, 1:3);                 % drop alpha / extra channels
    end

    % --- type normalisation to uint8 ------------------------------------
    if ~isa(raw, 'uint8')
        raw = im2uint8(raw);                  % handles uint16/double/logical
    end

    img = raw;
    info = struct( ...
        'originalSize', originalSize, ...
        'fileBytes',    fileBytes, ...
        'format',       string(fmt), ...
        'colorType',    colorType, ...
        'wasGrayscale', wasGrayscale);
end
