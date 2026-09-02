function R = template(cr, cfg)
%TEMPLATE  Assemble the ordered content of a NETRA clinical report.
%   R = netra.report.template(cr, cfg) flattens a caseRecord into a struct of
%   ready-to-render report sections, so netra.report.generate produces the same
%   content whether it uses the Report Generator or the exportgraphics fallback.
%
%   R fields (all strings unless noted):
%     R.title                     report title
%     R.patientHeader   string[]  patient/capture header lines
%     R.qualityVerdict            quality class + score line
%     R.gradeLine                 ICDR grade + label
%     R.referralLine              routing decision + urgency
%     R.confidenceLine            confidence % + band
%     R.evidence        string[]  evidence bullets (>=1; a fallback line if none)
%     R.alaLine                   attention-lesion agreement summary
%     R.provenance      string[]  per-stage REAL/MOCK/FAILED summary
%     R.timestampLine             generation timestamp
%     R.versionLine               pipeline version + model/config hash
%     R.disclaimer                the mandatory prototype disclaimer footer
%
%   The disclaimer text is fixed by the brief and MUST appear on every report.

    arguments
        cr  (1,1) struct
        cfg (1,1) struct = struct()
    end

    R = struct();
    R.title = "NETRA Diabetic Retinopathy Screening Report";

    % --- patient / capture header ---------------------------------------
    R.patientHeader = [ ...
        "Case UID: "   + str(cr.meta.uid); ...
        "Patient ID: " + strOr(cr.meta.patientID, "(not supplied)") + ...
            "    PHC: " + strOr(cr.meta.phcID, "(n/a)"); ...
        "Age: " + numOrNA(cr.meta.age) + " yr" + ...
            "    Diabetes duration: " + numOrNA(cr.meta.dmYears) + " yr" + ...
            "    Eye: " + str(cr.meta.eye); ...
        "Image: " + str(cr.meta.imagePath)];

    % --- quality verdict -------------------------------------------------
    R.qualityVerdict = "Image quality: " + strOr(cr.quality.class, "(not assessed)") + ...
        " (score " + numOrNA(cr.quality.score) + "/100)";
    if strlength(str(cr.quality.failReason)) > 0
        R.qualityVerdict = R.qualityVerdict + "  -  " + str(cr.quality.failReason);
    end

    % --- grade + referral ------------------------------------------------
    [lbl, ~] = netra.ui.formatGrade(cr.grade.icdr);
    R.gradeLine = "ICDR grade: " + numOrDash(cr.grade.icdr) + "  -  " + lbl;
    R.referralLine = "Referral: " + strOr(cr.routing.decision, "(none)") + ...
        "    Urgency: " + strOr(cr.routing.urgency, "None");
    if ~isempty(cr.routing.flags)
        R.referralLine = R.referralLine + "    Flags: " + strjoin(cr.routing.flags, ", ");
    end

    % --- confidence band -------------------------------------------------
    band = str(cr.xai.confidenceBand);
    if strlength(band) == 0, band = "(unbanded)"; end
    R.confidenceLine = "Confidence: " + pct(cr.grade.confidence) + ...
        "    Band: " + band;

    % --- evidence bullets (always >= 1 line) ----------------------------
    if isempty(cr.xai.evidenceBullets)
        R.evidence = "No structured evidence available (explainability stage not run).";
    else
        R.evidence = cr.xai.evidenceBullets(:);
    end

    % --- ALA -------------------------------------------------------------
    R.alaLine = "Attention-Lesion Agreement (ALA): " + numOrNA(cr.xai.agreementScore);
    if strlength(str(cr.xai.attentionSummary)) > 0
        R.alaLine = R.alaLine + "  -  " + str(cr.xai.attentionSummary);
    end

    % --- provenance summary (which stages were real at generation) ------
    R.provenance = provLines(cr);

    % --- timestamp + version --------------------------------------------
    R.timestampLine = "Generated: " + string(datetime('now', ...
        'Format', 'yyyy-MM-dd HH:mm:ss'));
    R.versionLine = "Pipeline " + str(cr.version.pipelineVersion) + ...
        "    model#" + shortHash(cr.version.modelHash) + ...
        "    config#" + shortHash(cr.version.configHash);

    % --- mandatory disclaimer footer ------------------------------------
    R.disclaimer = "AI-generated screening output. Requires ophthalmologist " + ...
        "confirmation. Research prototype - not validated for clinical use.";
end

% ------------------------------------------------------------------------
function lines = provLines(cr)
    stages = fieldnames(cr.provenance);
    lines = strings(numel(stages), 1);
    for k = 1:numel(stages)
        v = str(cr.provenance.(stages{k}));
        if strlength(v) == 0, v = "(unset)"; end
        lines(k) = pad(stages{k}, 12) + " " + v;
    end
end

function s = str(x),   s = string(x); end
function s = strOr(x, d)
    s = string(x);
    if strlength(s) == 0, s = string(d); end
end
function s = numOrNA(x)
    if isempty(x) || ~isfinite(x), s = "n/a"; else, s = string(round(x,2)); end
end
function s = numOrDash(x)
    if isempty(x) || ~isfinite(x), s = "-"; else, s = string(round(x)); end
end
function s = pct(x)
    if isempty(x) || ~isfinite(x), s = "n/a"; else, s = string(round(100*x)) + "%"; end
end
function s = shortHash(x)
    s = string(x);
    if strlength(s) == 0, s = "0000"; end
    s = extractBefore(s + "        ", 9);
end
function s = pad(txt, n)
    s = string(txt);
    while strlength(s) < n, s = s + " "; end
end
