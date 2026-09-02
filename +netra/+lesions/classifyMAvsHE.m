function label = classifyMAvsHE(stats, odRadius, cfg)
%CLASSIFYMAVSHE  Split one red-lesion region into microaneurysm vs haemorrhage.  [Phase 6]
%   label = netra.lesions.classifyMAvsHE(stats, odRadius, cfg)
%
%   Microaneurysms are SMALL, ROUND, COMPACT dark dots; haemorrhages are LARGER
%   and/or more IRREGULAR. The split is purely by shape, per the thresholds in
%   cfg.thresholds.lesions:
%     MA  iff   area      <= maAreaMax        (disc-scaled, see below)
%          AND  eccentricity <= maEccentricityMax   (round, not elongated)
%          AND  circularity  >= maCircularityMin     (compact: 4*pi*A/P^2)
%     otherwise -> HE.
%
%   stats is one element of regionprops(...,'Area','Eccentricity','Perimeter').
%
%   RESOLUTION-AWARENESS: maAreaMax/heAreaMin are px^2 at the 512px target. They
%   are rescaled by (odRadius / referenceOdRadius512)^2 so the physical size cut
%   between an MA and an HE tracks the true disc scale of THIS image, not the
%   raw pixel count. odRadius comes from the structures stage.
%
%   Returns "MA" or "HE".

    arguments
        stats (1,1) struct
        odRadius (1,1) double
        cfg (1,1) struct
    end

    L = cfg.thresholds.lesions;
    areaScale = (odRadius / L.referenceOdRadius512)^2;   % px^2 disc scaling
    if ~isfinite(areaScale) || areaScale <= 0, areaScale = 1; end
    maAreaMax = L.maAreaMax * areaScale;

    area = stats.Area;
    ecc  = stats.Eccentricity;
    peri = max(stats.Perimeter, eps);
    circ = 4*pi*area / peri^2;                    % 1 = perfect circle

    isMA = area <= maAreaMax && ecc <= L.maEccentricityMax && circ >= L.maCircularityMin;
    if isMA, label = "MA"; else, label = "HE"; end
end
