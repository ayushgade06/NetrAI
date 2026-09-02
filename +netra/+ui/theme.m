function t = theme()
%THEME  Centralised UI constants for the NETRA application.
%   t = netra.ui.theme() returns a struct of every colour, font size, and
%   spacing value used in the UI. NOTHING in the UI may hardcode a colour,
%   font size, or spacing literal; all of them come from here.
%
%   Semantic accent colours are reserved strictly for meaning (see the
%   Phase 1 brief 9.1): green = pass/no-referral, amber = borderline/
%   uncertain, red = reject/refer, cyan = vessels, magenta = fovea. They are
%   NEVER used decoratively.
%
%   Fields:
%     .color.<name>   1x3 RGB in [0,1]
%     .font.<name>    point size (double) or family (char)
%     .size.<name>    pixel size / width (double)
%     .space.<name>   spacing / padding (double)

    % --- colours (RGB, 0..1) --------------------------------------------
    color = struct();
    % neutral dark palette
    color.bg          = [0.11 0.12 0.14];   % app background
    color.panel       = [0.16 0.17 0.20];   % panel surface
    color.panelAlt    = [0.20 0.21 0.25];   % raised surface / cards
    color.navBg       = [0.09 0.10 0.12];   % nav rail
    color.navSel      = [0.20 0.28 0.34];   % selected nav item
    color.border      = [0.28 0.30 0.35];   % hairline borders
    color.text        = [0.90 0.92 0.95];   % primary text
    color.textMuted   = [0.62 0.65 0.70];   % secondary text
    color.textDim     = [0.45 0.48 0.53];   % tertiary / disabled

    % semantic accents (meaning only, never decorative)
    color.pass        = [0.30 0.72 0.42];   % green  - pass / no referral
    color.warn        = [0.92 0.68 0.22];   % amber  - borderline / uncertain
    color.reject      = [0.86 0.30 0.30];   % red    - reject / refer
    color.vessel      = [0.20 0.78 0.86];   % cyan   - vessels overlay
    color.fovea       = [0.86 0.30 0.78];   % magenta- optic disc / fovea
    color.lesion      = [0.95 0.55 0.20];   % orange - lesions overlay
    color.gradcam     = [0.90 0.20 0.20];   % gradcam hot (base tint)
    color.info        = [0.35 0.55 0.85];   % neutral informational accent

    % banner backgrounds (semantic, slightly darkened for text contrast)
    color.bannerPassBg    = [0.16 0.30 0.20];
    color.bannerWarnBg    = [0.34 0.27 0.10];   % MOCK: full placeholder
    color.bannerPartialBg = [0.30 0.24 0.08];   % PARTIAL: real+mock mix (deeper amber)
    color.bannerRejectBg  = [0.34 0.14 0.14];

    % grade scale (ICDR 0..4) - green->red ramp, semantic
    color.grade0 = [0.30 0.72 0.42];
    color.grade1 = [0.62 0.75 0.30];
    color.grade2 = [0.92 0.68 0.22];
    color.grade3 = [0.90 0.45 0.20];
    color.grade4 = [0.86 0.30 0.30];

    % --- fonts -----------------------------------------------------------
    font = struct();
    font.family    = 'Segoe UI';
    font.mono      = 'Consolas';
    font.tiny      = 10;
    font.small     = 12;
    font.body      = 14;
    font.h3        = 16;
    font.h2        = 20;
    font.h1        = 26;
    font.display   = 40;   % stopwatch / big grade badge

    % --- sizes -----------------------------------------------------------
    sz = struct();
    sz.navWidth      = 200;
    sz.topBarHeight  = 56;
    sz.bannerHeight  = 34;
    sz.rowHeight     = 28;
    sz.cardHeight    = 104;   % fits caption + h1 value + sub without clipping
    sz.buttonHeight  = 34;
    sz.iconBtn       = 40;
    sz.minWidth      = 1366;   % minimum usable width
    sz.minHeight     = 768;
    sz.defWidth      = 1600;
    sz.defHeight     = 950;

    % --- spacing ---------------------------------------------------------
    space = struct();
    space.pad        = 12;
    space.gap        = 10;
    space.gapSm      = 6;
    space.gapLg      = 18;

    t = struct('color', color, 'font', font, 'size', sz, 'space', space);
end
