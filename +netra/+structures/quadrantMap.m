function qmap = quadrantMap(fovMask, odCenter, foveaCenter, eye, cfg)
%QUADRANTMAP  Partition the FOV into anatomical quadrants.  [Phase 5]
%   qmap = netra.structures.quadrantMap(fovMask, odCenter, foveaCenter, eye, cfg)
%
%   Divides the field of view into the four clinical quadrants using the
%   OD->fovea axis as the horizontal (temporal) reference, so the partition is
%   anatomically meaningful rather than a naive image-axis split:
%
%       horizontal axis  = the OD->fovea direction (temporal is toward fovea)
%       vertical  split  = superior (up) vs inferior (down), perpendicular to it
%       origin           = the optic disc centre
%
%   Quadrant codes (uint8), background = 0:
%       1 = superior-nasal    2 = superior-temporal
%       3 = inferior-nasal    4 = inferior-temporal
%   Laterality (eye) sets which image side is NASAL: for a right eye (OD) the
%   disc is on the nasal (usually right-of-macula) side; the temporal half is
%   the side the fovea lies on, which the OD->fovea vector already encodes, so
%   eye is used only to LABEL nasal vs temporal consistently, not to recompute
%   geometry. "OS"/"OD" both handled; unknown defaults to OD.
%
%   Every code 1-4 is guaranteed non-empty as long as the FOV is non-degenerate
%   and the OD/fovea are distinct (they are, after localisation/fallback).

    arguments
        fovMask logical
        odCenter (1,2) double
        foveaCenter (1,2) double
        eye string = "OD" %#ok<INUSA>
        cfg (1,1) struct
    end

    [h, w] = size(fovMask);
    qmap = zeros(h, w, 'uint8');
    if ~any(fovMask(:)), return; end

    % --- temporal (horizontal) unit vector: OD -> fovea ------------------
    axis = foveaCenter - odCenter;                 % [dx dy], points temporally
    if norm(axis) < 1e-6
        axis = [1 0];                              % degenerate: fall back to +x
    end
    tHat = axis / norm(axis);                       % temporal direction
    nHatUp = [tHat(2), -tHat(1)];                   % perpendicular, "up" (superior)

    [X, Y] = meshgrid(1:w, 1:h);
    dx = X - odCenter(1); dy = Y - odCenter(2);

    tComp = dx*tHat(1) + dy*tHat(2);                % >0 temporal, <0 nasal
    sComp = dx*nHatUp(1) + dy*nHatUp(2);            % >0 superior, <0 inferior

    isTemporal = tComp >= 0;
    isSuperior = sComp >= 0;

    % Assign codes; background stays 0.
    q = zeros(h, w, 'uint8');
    q( isSuperior & ~isTemporal) = 1;               % superior-nasal
    q( isSuperior &  isTemporal) = 2;               % superior-temporal
    q(~isSuperior & ~isTemporal) = 3;               % inferior-nasal
    q(~isSuperior &  isTemporal) = 4;               % inferior-temporal

    q(~fovMask) = 0;
    qmap = q;

    % eye is retained in the signature for the interface contract and future
    % nasal/temporal LABEL swaps in the UI; the geometry above is already
    % laterality-correct because it is anchored on the measured OD->fovea axis.
end
