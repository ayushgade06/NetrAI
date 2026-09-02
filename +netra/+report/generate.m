function pdfPath = generate(cr, cfg)
%GENERATE  Produce the clinical PDF report for a case.  [Phase 9]
%   pdfPath = netra.report.generate(cr, cfg) returns the path where the
%   report PDF would be written and sets cr is NOT returned (this stage's
%   public contract returns a path). The orchestrator records the path and
%   sets cr.provenance.report.
%
%   CONTRACT:
%     - Reads the caseRecord; returns a path string.
%     - Only +store and +report may write to disk. Phase 0 writes NOTHING.
%     - cr.timing.report is written by runPipeline, not here.
%
%   MOCK IMPLEMENTATION - PHASE 0 SCAFFOLD
%   Returns a fixed placeholder path. No PDF is generated. These are NOT
%   measurements and NOT model outputs. Replaced with a real implementation
%   in Phase 9.

    arguments
        cr  (1,1) struct
        cfg (1,1) struct %#ok<INUSA>
    end

    % Phase 0: compute the path we WOULD write to, but do not create a file.
    pdfPath = string(fullfile('data', 'cases', ...
        char(cr.meta.uid) + "_report.pdf"));
end
