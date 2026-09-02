function band = confidenceBand(confidence, qualityScore, ala, cfg)
%CONFIDENCEBAND  Map calibrated confidence, image quality and ALA to a band.
%   band = netra.xai.confidenceBand(confidence, qualityScore, ala, cfg) returns
%   "High", "Moderate" or "Low". The band starts from the calibrated confidence
%   against cfg.thresholds.grading.confidenceHigh / confidenceLow, then is
%   demoted (never promoted) by poor image quality or poor attention-lesion
%   agreement:
%     - qualityScore below quality.borderlineScoreMin caps the band at Moderate.
%     - a FINITE ala below xai.alaLowThreshold caps the band at Low (the model
%       is confident but looking in the wrong place).
%
%   NaN ala means "no lesions to agree with" - it is NOT evidence against the
%   case, so it never demotes the band. It is handled without erroring.
%
%   confidence NaN (grading unavailable / rule-based path) yields "Low".

    arguments
        confidence   (1,1) double
        qualityScore (1,1) double
        ala          (1,1) double
        cfg          (1,1) struct
    end

    hi = cfg.thresholds.grading.confidenceHigh;
    lo = cfg.thresholds.grading.confidenceLow;
    qMin = cfg.thresholds.quality.borderlineScoreMin;
    alaLow = cfg.thresholds.xai.alaLowThreshold;

    if ~isfinite(confidence)
        band = "Low";
        return;
    end

    % Base band from confidence alone.
    if confidence >= hi
        band = "High";
    elseif confidence >= lo
        band = "Moderate";
    else
        band = "Low";
    end

    % Poor image quality caps at Moderate.
    if isfinite(qualityScore) && qualityScore < qMin && band == "High"
        band = "Moderate";
    end

    % Poor attention-lesion agreement (finite ALA only) caps at Low.
    if isfinite(ala) && ala < alaLow
        band = "Low";
    end
end
