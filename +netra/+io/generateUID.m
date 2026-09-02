function uid = generateUID(phcID, timestamp, eye, seq)
%GENERATEUID  Deterministic case UID: <PHCID>-<yyyymmdd>-<4-digit seq>-<OD|OS>.
%   uid = netra.io.generateUID(phcID, timestamp, eye, seq) builds the case
%   identifier used to name the on-disk case folder and the registry row.
%
%   Inputs:
%     phcID     : string/char, e.g. "PHC001". Non-alphanumerics are stripped.
%     timestamp : datetime (the yyyymmdd date part is used).
%     eye       : "OD" | "OS" (right | left); anything else errors.
%     seq       : integer 0..9999, the per-(phc,date) capture sequence number.
%
%   Deterministic: the SAME four inputs always produce the SAME uid. This is
%   what makes a re-save of the same case UPDATE its registry row rather than
%   duplicate it (netra.store.save keys on the uid).
%
%   Example:
%     netra.io.generateUID("PHC001", datetime(2026,9,2), "OD", 7)
%       -> "PHC001-20260902-0007-OD"

    arguments
        phcID     (1,1) string
        timestamp (1,1) datetime
        eye       (1,1) string
        seq       (1,1) double {mustBeInteger, mustBeNonnegative}
    end

    eye = upper(strtrim(eye));
    if ~ismember(eye, ["OD", "OS"])
        error('NETRA:io:badEye', 'eye must be "OD" or "OS", got "%s".', eye);
    end
    if seq > 9999
        error('NETRA:io:seqRange', 'seq must be 0..9999, got %d.', seq);
    end

    % Strip anything not alphanumeric from the PHC id so the uid stays a clean
    % single-token filename (no spaces, no separators that clash with '-').
    phcClean = regexprep(char(phcID), '[^A-Za-z0-9]', '');
    if isempty(phcClean)
        phcClean = 'PHCXXX';
    end

    dateStr = char(timestamp, 'yyyyMMdd');
    uid = string(sprintf('%s-%s-%04d-%s', phcClean, dateStr, seq, eye));
end
