function [label, color] = formatGrade(icdrLevel)
%FORMATGRADE  Map an ICDR grade (0-4) to a human label and semantic colour.
%   [label, color] = netra.ui.formatGrade(icdrLevel) returns the standard
%   ICDR (International Clinical Diabetic Retinopathy) label and a 1x3 RGB
%   colour from the theme's semantic grade ramp.
%
%   icdrLevel may be NaN or empty (ungraded); returns "Not graded" / muted.
%
%   Example:
%     [lbl, c] = netra.ui.formatGrade(2);   % "Moderate NPDR", amber

    t = netra.ui.theme();

    if isempty(icdrLevel) || ~isfinite(icdrLevel)
        label = "Not graded";
        color = t.color.textMuted;
        return;
    end

    switch round(icdrLevel)
        case 0
            label = "No DR";                 color = t.color.grade0;
        case 1
            label = "Mild NPDR";             color = t.color.grade1;
        case 2
            label = "Moderate NPDR";         color = t.color.grade2;
        case 3
            label = "Severe NPDR";           color = t.color.grade3;
        case 4
            label = "Proliferative DR";      color = t.color.grade4;
        otherwise
            label = "Unknown grade";         color = t.color.textMuted;
    end
    label = string(label);
end
