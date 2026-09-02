function cr = runPipeline(cr, cfg, models)
%RUNPIPELINE  Run the full NETRA pipeline over a caseRecord.
%   cr = netra.runPipeline(cr) runs all nine stages in fixed order,
%   loading config and models via netra.loadConfig / netra.loadModels.
%
%   cr = netra.runPipeline(cr, cfg, models) uses the supplied config and
%   models structs (cfg and models are optional and independently defaulted).
%
%   Contract:
%     - Each stage is wrapped in try/catch. On failure, the error is appended
%       to cr.errors, cr.provenance.<stage> is set to "FAILED", and the
%       pipeline CONTINUES to the next stage. A caseRecord is ALWAYS returned.
%     - Per-stage wall-clock time is written to cr.timing.<stage> by this
%       orchestrator (stages do not time themselves).
%     - cr.timing.total is the wall-clock time of the whole run.
%
%   Stage order is defined by netra.util.stageNames().
%
%   Example:
%     cr = netra.runPipeline(netra.newCaseRecord('data/demo/sample01.jpg'));

    arguments
        cr     (1,1) struct
        cfg    struct = netra.loadConfig()
        models struct = netra.loadModels()
    end

    stages = netra.util.stageNames();
    tTotal = tic;

    for k = 1:numel(stages)
        stage = stages{k};
        fn = stageHandle(stage);
        try
            [cr, elapsed] = netra.util.timeStage(fn, cr, cfg, models);
            cr.timing.(stage) = elapsed;
        catch ME
            cr.timing.(stage) = 0;
            cr.provenance.(stage) = "FAILED";
            cr.errors(end+1) = struct( ...
                'stage',      stage, ...
                'identifier', ME.identifier, ...
                'message',    ME.message);
        end
    end

    cr.timing.total = toc(tTotal);
end

% ------------------------------------------------------------------------
function fn = stageHandle(stage)
%STAGEHANDLE  Adapter mapping a stage name to a uniform (cr,cfg,models) call.
%   Stages have heterogeneous public signatures (report returns a path,
%   store.save returns nothing, grading/xai take models). This wraps each so
%   the orchestrator can call them all as cr = fn(cr, cfg, models) and always
%   get a caseRecord back.
    switch stage
        case 'quality'
            fn = @(cr,cfg,models) netra.quality.assess(cr, cfg, models);
        case 'preproc'
            fn = @(cr,cfg,~)      netra.preproc.enhance(cr, cfg);
        case 'structures'
            fn = @(cr,cfg,~)      netra.structures.segment(cr, cfg);
        case 'lesions'
            fn = @(cr,cfg,~)      netra.lesions.detect(cr, cfg);
        case 'grading'
            fn = @(cr,cfg,models) netra.grading.classify(cr, cfg, models);
        case 'xai'
            fn = @(cr,cfg,models) netra.xai.explain(cr, cfg, models);
        case 'routing'
            fn = @(cr,cfg,~)      netra.routing.decide(cr, cfg);
        case 'report'
            fn = @(cr,cfg,~)      stageReport(cr, cfg);
        case 'store'
            fn = @(cr,cfg,~)      stageStore(cr, cfg);
        otherwise
            error('NETRA:pipeline:unknownStage', 'Unknown stage: %s', stage);
    end
end

function cr = stageReport(cr, cfg)
%STAGEREPORT  Adapt report.generate (returns a path) to the cr-in/cr-out form.
%   report/store have frozen signatures that cannot set provenance on the
%   record themselves, so the orchestrator sets it on their behalf.
    pdfPath = netra.report.generate(cr, cfg);
    cr.report.pdfPath = string(pdfPath);
    cr.provenance.report = "MOCK";
end

function cr = stageStore(cr, cfg)
%STAGESTORE  Adapt store.save (returns nothing) to the cr-in/cr-out form.
%   Persistence is REAL in Phase 2, but only for cases that carry real pixels
%   (cr.img.raw non-empty). Mock dashboard previews (built from registry rows
%   with no image loaded) must NOT pollute the real registry, so they skip the
%   write and are tagged MOCK. Ingested cases (UI New Screening / batchIngest)
%   have pixels, get persisted, and are tagged REAL.
    if isempty(cr.img.raw)
        cr.provenance.store = "MOCK";        % nothing to persist (preview only)
        return;
    end
    netra.store.save(cr, cfg);
    cr.provenance.store = "REAL";
end
