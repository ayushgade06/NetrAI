function img = readImageFile(path)
%READIMAGEFILE  Robust image read that survives MATLAB Online's .jpg quirk.
%   img = netra.io.readImageFile(path) returns a uint8 image (HxWx3 or HxW),
%   reading reliably even where imread's filename-based format detection fails
%   for the ".jpg" extension on MATLAB Online.
%
%   Strategy, in order (first that works wins):
%     1. imread(path)                       - normal case, other platforms.
%     2. imread(path, <ext-derived format>) - explicit format bypasses the
%                                             broken filename detection.
%     3. Java ImageIO.read on the raw file  - decodes from BYTES, ignoring the
%                                             extension entirely. Last-resort but
%                                             always available (bundled JRE).
%   Errors only if all three fail (a genuinely unreadable file).

    path = char(path);

    % --- 1. plain imread ------------------------------------------------
    try
        img = imread(path);
        return;
    catch
    end

    % --- 2. imread with an explicit format ------------------------------
    [~, ~, ext] = fileparts(path);
    fmt = lower(erase(string(ext), "."));
    if any(fmt == ["jpg","jpeg","jpe","jfif"]), fmt = "jpg"; end
    if any(fmt == ["tif","tiff"]), fmt = "tif"; end
    if fmt ~= ""
        try
            img = imread(path, char(fmt));
            return;
        catch
        end
    end

    % --- 3. Java ImageIO (decode from bytes, extension-agnostic) --------
    img = javaReadImage(path);
end

% ------------------------------------------------------------------------
function img = javaReadImage(path)
%JAVAREADIMAGE  Decode any common image via the bundled Java ImageIO.
    bi = javax.imageio.ImageIO.read(java.io.File(path));
    if isempty(bi)
        error('NETRA:io:unreadable', ...
            'Could not decode image (imread and Java ImageIO both failed): %s', path);
    end
    h = bi.getHeight();
    w = bi.getWidth();
    % getRGB returns a 1-D int array of packed ARGB, row-major.
    pix = bi.getRGB(0, 0, w, h, [], 0, w);     % 1 x (w*h) int32
    pix = typecast(int32(pix), 'uint32');
    R = uint8(bitshift(bitand(pix, uint32(hex2dec('00FF0000'))), -16));
    G = uint8(bitshift(bitand(pix, uint32(hex2dec('0000FF00'))), -8));
    B = uint8(       bitand(pix, uint32(hex2dec('000000FF'))));
    % reshape row-major (w fastest) -> HxW, then transpose to MATLAB's col-major
    R = reshape(R, w, h).';
    G = reshape(G, w, h).';
    B = reshape(B, w, h).';
    img = cat(3, R, G, B);
end
