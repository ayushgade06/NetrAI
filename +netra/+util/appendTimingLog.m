function appendTimingLog(cr)
%APPENDTIMINGLOG  Append one caseRecord's per-stage timings to data/timing.log.
%   netra.util.appendTimingLog(cr) writes a single CSV line to
%   <storeRoot>/data/timing.log with columns:
%       timestamp,uid,<stage1>,<stage2>,...,total
%   one column per stage from netra.util.stageNames plus the total, all in
%   seconds. The header is written once, when the file is first created.
%
%   This is the file netra.util.latencyStats reads to source the Simulink
%   capacity model's inferenceSecPerImage from MEASURED pipeline latency
%   (rather than an invented constant). runPipeline calls this best-effort;
%   a write failure here must never affect a screening run.
%
%   The log lives under netra.store.storeRoot so tests that redirect the store
%   root (NETRA_STORE_ROOT) do not pollute the committed project log.

    arguments
        cr (1,1) struct
    end

    stages = netra.util.stageNames();
    root   = netra.store.storeRoot();
    dataDir = fullfile(root, 'data');
    if ~isfolder(dataDir), mkdir(dataDir); end
    logPath = fullfile(dataDir, 'timing.log');

    writeHeader = ~isfile(logPath);
    fid = fopen(logPath, 'a');
    if fid < 0
        error('NETRA:util:timingLog', 'Cannot open %s for append.', logPath);
    end
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>

    if writeHeader
        fprintf(fid, 'timestamp,uid,%s,total\n', strjoin(stages, ','));
    end

    vals = zeros(1, numel(stages));
    for k = 1:numel(stages)
        v = cr.timing.(stages{k});
        if ~isscalar(v) || ~isfinite(v), v = 0; end
        vals(k) = v;
    end
    total = cr.timing.total;
    if ~isscalar(total) || ~isfinite(total), total = 0; end

    ts = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss.SSS'));
    fprintf(fid, '%s,%s,%s,%.6f\n', ts, char(cr.meta.uid), ...
        strjoin(compose('%.6f', vals), ','), total);
end
