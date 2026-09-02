function quarantineMessidor(messidorRoot, mode)
%QUARANTINEMESSIDOR  Move (or link) Messidor-2 into data/quarantine/messidor2.
%   quarantineMessidor(messidorRoot) MOVES the Messidor-2 folder into
%   data/quarantine/messidor2/ and writes data/quarantine/QUARANTINE_NOTICE.md.
%
%   quarantineMessidor(messidorRoot, "symlink") tries to create a directory
%   symlink instead of moving (falls back to move if the OS refuses the link,
%   e.g. no admin/developer mode on Windows).
%
%   quarantineMessidor() with no source just (re)writes the QUARANTINE_NOTICE
%   and ensures the quarantine folder exists - useful to establish the guard
%   before the dataset is on disk.
%
%   Messidor-2 is the HELD-OUT EXTERNAL TEST SET. After quarantine, any read of
%   a path inside data/quarantine/ throws via netra.io.assertNotQuarantined,
%   which loadImage and batchIngest both call. It is unlocked exactly once, in
%   Phase 10.

    arguments
        messidorRoot (1,:) char = ''
        mode         (1,1) string = "move"
    end

    here = fileparts(mfilename('fullpath'));   % tools/
    root = fileparts(here);                    % project root
    qDir = fullfile(root, 'data', 'quarantine');
    dest = fullfile(qDir, 'messidor2');

    if ~isfolder(qDir), mkdir(qDir); end
    writeNotice(qDir);

    if isempty(messidorRoot)
        fprintf('quarantineMessidor: notice written; no source folder given.\n');
        fprintf('  Quarantine dir: %s\n', qDir);
        return;
    end

    if ~isfolder(messidorRoot)
        error('NETRA:quarantine:noSource', ...
            'Messidor-2 source folder not found: %s', messidorRoot);
    end
    if isfolder(dest)
        error('NETRA:quarantine:destExists', ...
            'Quarantine destination already exists: %s (refusing to clobber).', dest);
    end

    if mode == "symlink"
        ok = trySymlink(messidorRoot, dest);
        if ok
            fprintf('quarantineMessidor: symlinked %s -> %s\n', messidorRoot, dest);
            return;
        end
        warning('NETRA:quarantine:symlinkFailed', ...
            'Symlink failed (need admin/developer mode?); moving instead.');
    end

    [okMv, msg] = movefile(messidorRoot, dest, 'f');
    if ~okMv
        error('NETRA:quarantine:moveFailed', ...
            'Failed to move Messidor-2 into quarantine: %s', msg);
    end
    fprintf('quarantineMessidor: moved %s -> %s\n', messidorRoot, dest);
end

% ------------------------------------------------------------------------
function ok = trySymlink(src, dest)
    ok = false;
    try
        if ispc
            % mklink /D needs the arguments quoted; system() returns status 0 on success.
            cmd = sprintf('cmd /c mklink /D "%s" "%s"', dest, src);
        else
            cmd = sprintf('ln -s "%s" "%s"', src, dest);
        end
        status = system(cmd);
        ok = (status == 0) && (isfolder(dest));
    catch
        ok = false;
    end
end

function writeNotice(qDir)
    notice = fullfile(qDir, 'QUARANTINE_NOTICE.md');
    txt = [ ...
"# QUARANTINE - Messidor-2 (Held-Out External Test Set)"                        newline ...
""                                                                              newline ...
"**Do not read anything under `data/quarantine/` from any training, tuning,"    newline ...
"validation, threshold-selection, or model-selection script.**"                 newline ...
""                                                                              newline ...
"Messidor-2 is NETRA's held-out EXTERNAL test set. It exists to give one"        newline ...
"honest, never-peeked estimate of real-world generalisation. Every time a"       newline ...
"human or a script looks at it to make a decision, that estimate is spent."      newline ...
""                                                                              newline ...
"## Enforcement"                                                                 newline ...
""                                                                              newline ...
"`netra.io.assertNotQuarantined(path)` throws `NETRA:io:quarantined` for any"    newline ...
"path resolving inside this folder. `netra.io.loadImage` and"                    newline ...
"`netra.io.batchIngest` both call it, so the pipeline cannot ingest a"           newline ...
"quarantined image by accident."                                                newline ...
""                                                                              newline ...
"## Unlock"                                                                      newline ...
""                                                                              newline ...
"This set is unlocked EXACTLY ONCE, in Phase 10, for the final external"         newline ...
"evaluation - and only after all training and threshold decisions are frozen."  newline ...
""                                                                              newline ...
"If you think you need this data before Phase 10, you do not. Use the APTOS"     newline ...
"validation split instead (`validation/splits.mat`)."                           newline];
    fid = fopen(notice, 'w');
    if fid < 0
        warning('NETRA:quarantine:noticeWrite', 'Could not write %s', notice);
        return;
    end
    fwrite(fid, txt);
    fclose(fid);
end
