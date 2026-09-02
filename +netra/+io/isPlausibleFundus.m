function [isFundus, score, detail] = isPlausibleFundus(img, cfg)
%ISPLAUSIBLEFUNDUS  Heuristic guard: does this image look like a retina?
%   [isFundus, score, detail] = netra.io.isPlausibleFundus(img, cfg)
%
%   THIS IS A HEURISTIC GUARD, NOT A CLASSIFIER. Its only job is to stop an
%   obvious non-fundus (a laptop photo, a screenshot, a gradient) from being
%   ingested as a retina. It is intentionally cheap and conservative; it will
%   never be used to make a clinical statement, and the Phase 3 quality model
%   is what actually judges capture quality.
%
%   score in [0,1] is a weighted blend of three sub-checks, each also in [0,1]
%   and returned individually in `detail` so a rejection can name the culprit:
%     detail.borderScore   fraction of near-black border pixels (fundus images
%                          sit on a black surround; a laptop photo fills the
%                          frame). Higher = more fundus-like.
%     detail.circleScore   how disc-like the bright region is: area fraction of
%                          the bright mask near a target band AND how well its
%                          bounding box fills a circle. Higher = more fundus-like.
%     detail.redScore      red-channel dominance typical of retina (R > G > B
%                          on average across the lit region). Higher = more so.
%
%   isFundus = score >= cfg.thresholds.io.fundusPlausibilityMin.

    arguments
        img
        cfg (1,1) struct
    end

    io = cfg.thresholds.io;

    g = double(img);
    if size(g,3) == 1
        g = repmat(g, 1, 1, 3);
    end
    R = g(:,:,1); G = g(:,:,2); B = g(:,:,3);
    lum = 0.299*R + 0.587*G + 0.114*B;         % perceived luminance 0..255
    [h, w] = size(lum);

    % --- sub-check 1: near-black border fraction ------------------------
    % Sample a 1-px frame border ring is too thin; use an outer 8% margin ring.
    m = max(1, round(0.08 * min(h,w)));
    borderMask = false(h, w);
    borderMask(1:m, :) = true; borderMask(end-m+1:end, :) = true;
    borderMask(:, 1:m) = true; borderMask(:, end-m+1:end) = true;
    borderPix = lum(borderMask);
    blackFrac = mean(borderPix < 25);          % near-black threshold on 0..255
    detail.borderScore = blackFrac;

    % --- sub-check 2: large roughly-circular bright region --------------
    % Bright = above a mid luminance. A fundus fills a large central disc; a
    % screenshot's bright region is rectangular and edge-to-edge.
    bright = lum > 40;
    areaFrac = mean(bright(:));                 % lit fraction of the frame
    % Ideal fundus lit fraction sits around pi/4 (~0.785) of the frame if the
    % disc is inscribed. Score peaks there and falls off toward 0 and 1.
    circleArea = 1 - min(1, abs(areaFrac - 0.75) / 0.55);

    % Circularity of the lit region's bounding box: for an inscribed disc the
    % lit fraction of its own bounding box ~ pi/4. Compute cheaply from the
    % rows/cols that contain any bright pixel.
    anyRow = any(bright, 2); anyCol = any(bright, 1);
    if any(anyRow) && any(anyCol)
        bh = find(anyRow, 1, 'last') - find(anyRow, 1, 'first') + 1;
        bw = find(anyCol, 1, 'last') - find(anyCol, 1, 'first') + 1;
        fillRatio = sum(bright(:)) / (bh * bw);     % ~0.785 for a disc, ~1 for a rectangle
        circleFill = 1 - min(1, abs(fillRatio - 0.785) / 0.5);
    else
        circleFill = 0;
    end
    detail.circleScore = 0.5*circleArea + 0.5*circleFill;

    % --- sub-check 3: red-channel dominance -----------------------------
    % Over the lit region, retinas run red-dominant (R > G > B on average).
    lit = bright;
    if any(lit(:))
        mR = mean(R(lit)); mG = mean(G(lit)); mB = mean(B(lit));
    else
        mR = mean(R(:)); mG = mean(G(:)); mB = mean(B(:));
    end
    denom = max(1, mR + mG + mB);
    % Reward R being the largest and B the smallest; map the R-share above an
    % equal-thirds baseline (0.333) into 0..1.
    rShare = mR / denom;
    redOrder = double(mR >= mG) * 0.5 + double(mG >= mB) * 0.5;   % 0,0.5,1
    detail.redScore = max(0, min(1, (rShare - 0.30) / 0.25)) * 0.5 + redOrder * 0.5;

    % --- blend -----------------------------------------------------------
    % Border and colour are the strongest discriminators against everyday
    % photos; shape is supporting evidence. Weights sum to 1.
    w1 = 0.4; w2 = 0.25; w3 = 0.35;
    score = w1*detail.borderScore + w2*detail.circleScore + w3*detail.redScore;
    score = max(0, min(1, score));

    detail.areaFrac = areaFrac;
    detail.weights  = [w1 w2 w3];
    isFundus = score >= io.fundusPlausibilityMin;
end
