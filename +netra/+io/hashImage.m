function h = hashImage(img)
%HASHIMAGE  SHA-256 hex digest of the pixel content of an image.
%   h = netra.io.hashImage(img) returns a lowercase 64-character hex string:
%   the SHA-256 of the raw pixel bytes of img, with a small shape header so
%   two arrays with the same bytes but different dimensions do not collide.
%
%   Why SHA-256 over the PIXELS (not the file):
%     - The hash identifies the CONTENT that entered the pipeline, not the
%       on-disk container. The same retina re-encoded JPEG->PNG, or loaded
%       from two copies of one file, hashes the same pixels.
%     - Simulink.getFileChecksum hashes a FILE and needs Simulink on the path;
%       Phase 2 deliberately avoids a Simulink dependency (brief s.6).
%       java.security.MessageDigest ships with every MATLAB, hashes bytes
%       directly, and adds no dependency -> the lazy, correct choice.
%
%   Deterministic: identical pixels -> identical hash; different pixels ->
%   (with overwhelming probability) a different hash.

    arguments
        img {mustBeNumeric, mustBeNonempty}
    end

    % Header folds class tag + dimensions into the digest so a 1x6 row and a
    % 2x3 image of the same six bytes hash differently.
    dims = size(img, 1, 2, 3);
    hdr  = [uint8('NETRA1'), typecast(uint32(dims), 'uint8')];

    % Bytes fed to Java must be a byte[] (signed). typecast uint8->int8
    % reinterprets the bits (no value change), which is exactly what we want.
    hdrJ  = typecast(hdr, 'int8');
    bodyJ = typecast(uint8(img(:)), 'int8');   % column-major pixel bytes

    md = java.security.MessageDigest.getInstance('SHA-256');
    md.update(hdrJ);
    md.update(bodyJ);
    digest = typecast(md.digest(), 'uint8');   % 32 signed java bytes -> uint8
    h = string(sprintf('%02x', digest));
end
