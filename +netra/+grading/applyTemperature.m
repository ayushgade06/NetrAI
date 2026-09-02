function probs = applyTemperature(logits, T)
%APPLYTEMPERATURE  Temperature-scaled softmax over class logits.
%   probs = netra.grading.applyTemperature(logits, T) divides the logits by the
%   scalar temperature T (fitted on the validation split by training/calibrate)
%   and returns a softmax distribution. T=1 is the plain softmax (identity in
%   the temperature sense); T>1 softens the distribution (higher entropy),
%   T<1 sharpens it.
%
%   logits is a 1xK (or Kx1) real vector; probs is the same shape, non-negative,
%   summing to 1. Renormalisation guards against floating-point drift so no
%   malformed distribution reaches downstream code (schema requires sum==1).
%
%   NOTE: no CNN is trained in this environment (Fallback Path C), so this is
%   not yet exercised on real logits. It is a pure, tested function ready for
%   the path-A/B CNN. See training/calibrate.m for how T is obtained.

    arguments
        logits (1,:) double {mustBeReal}
        T      (1,1) double {mustBePositive} = 1
    end

    z = logits(:).' / T;
    z = z - max(z);                 % numerically stable softmax
    e = exp(z);
    probs = e / sum(e);
    probs = probs / sum(probs);     % belt-and-braces renormalise

    if ~isrow(logits)
        probs = probs.';            % preserve caller's orientation
    end
end
