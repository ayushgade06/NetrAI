function assertNotQuarantined(path)
%ASSERTNOTQUARANTINED  Guard: error if a path resolves inside the quarantine.
%   netra.io.assertNotQuarantined(path) throws NETRA:io:quarantined if the
%   given path lies inside data/quarantine/ (the held-out external test set,
%   principally Messidor-2). Called from loadImage and batchIngest so no
%   training/tuning/ingest code can read the held-out set by accident.
%
%   The quarantine is unlocked exactly once in Phase 10. See
%   data/quarantine/QUARANTINE_NOTICE.md and tools/quarantineMessidor.m.
%
%   Comparison is done on absolute, normalised paths so ".." tricks and
%   forward/back-slash differences cannot slip a quarantined path through.

    arguments
        path (1,:) char
    end

    here = fileparts(mfilename('fullpath'));           % +io
    root = fileparts(fileparts(here));                 % project root
    qRoot = fullfile(root, 'data', 'quarantine');

    absPath = localAbs(path);
    absQ    = localAbs(qRoot);

    % Normalise separators + case (Windows is case-insensitive) for the prefix
    % test. A trailing filesep on the quarantine root prevents a sibling like
    % "quarantine_backup" from matching "quarantine".
    p = [lower(strrep(absPath, '/', filesep)) filesep];
    q = [lower(strrep(absQ,    '/', filesep)) filesep];

    if startsWith(p, q)
        error('NETRA:io:quarantined', ...
            ['Refusing to read a QUARANTINED path (held-out external test ' ...
             'set, unlocked only in Phase 10):\n  %s'], absPath);
    end
end

% ------------------------------------------------------------------------
function a = localAbs(p)
%LOCALABS  Absolute, ..-collapsed path without requiring the file to exist.
    if isempty(p)
        a = pwd; return;
    end
    % java.io.File.getCanonicalPath collapses "." and ".." and makes absolute
    % without needing the target to exist on disk.
    a = char(java.io.File(p).getCanonicalPath());
end
