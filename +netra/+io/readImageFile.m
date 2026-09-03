function img = readImageFile(path)
%READIMAGEFILE  Robust image read that survives MATLAB Online's .jpg quirk.
%   img = netra.io.readImageFile(path) reads an image like imread, but passes
%   an EXPLICIT format to imread derived from the extension.
%
%   WHY: on MATLAB Online, imread's filename-based format detection fails for
%   the ".jpg" extension specifically ("Unable to determine file format from
%   filename"), while ".jpeg" works and the files are valid JPEGs (verified by
%   magic bytes FF D8 FF). Passing the format explicitly (imread(path,'jpg'))
%   bypasses the broken detection. This helper centralises that workaround so
%   loadImage, realImage, and training all read reliably.

    [~, ~, ext] = fileparts(char(path));
    fmt = lower(erase(string(ext), "."));

    % Map common aliases to the imformats name.
    switch fmt
        case {"jpg","jpeg","jpe","jfif"}
            fmt = "jpg";
        case {"tif","tiff"}
            fmt = "tif";
        case ""
            fmt = "";                 % no extension: let imread guess
    end

    if fmt == ""
        img = imread(path);
    else
        try
            img = imread(path, char(fmt));   % explicit format: robust on MATLAB Online
        catch
            img = imread(path);              % fall back to auto-detection
        end
    end
end
