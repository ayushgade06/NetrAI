function ala = agreementScore(gradcam, lesionAllMask, cfg)
%AGREEMENTSCORE  Attention-Lesion Agreement (ALA): does the model look where
%   the lesions are?
%   ala = netra.xai.agreementScore(gradcam, lesionAllMask, cfg) binarises the
%   Grad-CAM heatmap at cfg.thresholds.xai.gradcamPercentile, dilates the union
%   lesion mask by cfg.thresholds.xai.lesionDilationPx, and returns
%       ALA = sum(gradcamTop & lesionMask) / sum(gradcamTop)
%   i.e. the fraction of the model's peak-attention region that overlaps
%   detected lesions. 1.0 = attention lands entirely on lesions; 0.0 = attention
%   is entirely off the lesions.
%
%   ALA is NaN (not 0) when there are no lesions to agree with:
%     - lesionAllMask is empty (Track A not merged), or
%     - lesionAllMask is all-false (a normal retina).
%   NaN means "not applicable - no lesions detected", clinically distinct from
%   a low score ("attention disagrees with lesions"). The UI and confidenceBand
%   must honour that distinction.
%
%   gradcam is a single/double H x W map in [0,1]. lesionAllMask is logical,
%   same H x W. A size mismatch is resized (nearest) so a defensive-resize
%   upstream cannot desynchronise the two.

    arguments
        gradcam       {mustBeNumeric}
        lesionAllMask
        cfg           (1,1) struct
    end

    pct        = cfg.thresholds.xai.gradcamPercentile;
    dilationPx = cfg.thresholds.xai.lesionDilationPx;

    % --- no lesions -> NaN ------------------------------------------------
    if isempty(lesionAllMask) || ~any(lesionAllMask(:))
        ala = NaN;
        return;
    end
    % --- no attention map -> NaN (Grad-CAM failed / unavailable) ---------
    if isempty(gradcam) || ~any(gradcam(:) > 0)
        ala = NaN;
        return;
    end

    lesionMask = logical(lesionAllMask);
    gradcam    = double(gradcam);

    % Align sizes if a defensive resize upstream left them mismatched.
    if ~isequal(size(gradcam), size(lesionMask))
        gradcam = imresize(gradcam, size(lesionMask), 'nearest');
    end

    % Binarise Grad-CAM at the configured percentile of its POSITIVE values.
    thr = prctile(gradcam(gradcam > 0), pct);
    gradcamTop = gradcam >= thr;
    if ~any(gradcamTop(:))
        ala = NaN;                  % degenerate map (all equal) -> N/A
        return;
    end

    % Dilate lesions so near-misses (attention adjacent to a lesion) count.
    if dilationPx > 0
        lesionMask = imdilate(lesionMask, strel('disk', round(dilationPx)));
    end

    ala = sum(gradcamTop(:) & lesionMask(:)) / sum(gradcamTop(:));
end
