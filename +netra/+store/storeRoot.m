function root = storeRoot()
%STOREROOT  Project root for the case store (overridable for tests).
%   root = netra.store.storeRoot() returns the directory whose data/ subfolder
%   holds cases/ and registry.mat. By default this is the NETRA project root.
%
%   If the environment variable NETRA_STORE_ROOT is set, that path is used
%   instead. Tests set it (setenv/onCleanup) so save/load/registry operate in a
%   throwaway directory and never touch the real data/registry.mat or the
%   committed mock seed. This is the ONE place the store root is decided.

    ov = getenv('NETRA_STORE_ROOT');
    if ~isempty(ov)
        root = ov;
        return;
    end
    here = fileparts(mfilename('fullpath'));   % +store
    root = fileparts(fileparts(here));         % project root
end
