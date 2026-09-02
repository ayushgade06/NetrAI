function T = emptyRealRegistry()
%EMPTYREALREGISTRY  Zero-row real-registry table (Phase 2 schema, 21 columns).
%   T = netra.store.emptyRealRegistry() returns the empty table that defines
%   the real case registry's columns and types. It is the ONE place the
%   real-registry schema is written down; netra.store.registry, save, and the
%   shared loader all build on it so the schema can never drift.
%
%   Superset of the Phase 1 mock registry - the Phase 1 column NAMES are kept
%   (uid, timestamp, icdr, confidence, urgency, reviewed, ...) so the existing
%   Dashboard and review-queue code keeps working unchanged.
%
%   (Added as a small shared schema constructor, mirroring the Phase 1
%   internalLoadRegistry helper; not a public pipeline stage.)

    T = table( ...
        strings(0,1), ...   uid
        strings(0,1), ...   patientID
        strings(0,1), ...   phcID
        NaT(0,1), ...       timestamp
        zeros(0,1), ...     age
        zeros(0,1), ...     dmYears
        strings(0,1), ...   eye
        strings(0,1), ...   imagePath
        strings(0,1), ...   imageHash
        strings(0,1), ...   qualityClass
        zeros(0,1), ...     qualityScore
        zeros(0,1), ...     icdr
        zeros(0,1), ...     confidence
        zeros(0,1), ...     ala
        strings(0,1), ...   routingDecision
        strings(0,1), ...   urgency
        strings(0,1), ...   flags
        false(0,1), ...     reviewed
        nan(0,1), ...       reviewSeconds
        strings(0,1), ...   reviewerAgreed
        strings(0,1), ...   provenanceSummary
        'VariableNames', {'uid','patientID','phcID','timestamp','age', ...
        'dmYears','eye','imagePath','imageHash','qualityClass','qualityScore', ...
        'icdr','confidence','ala','routingDecision','urgency','flags', ...
        'reviewed','reviewSeconds','reviewerAgreed','provenanceSummary'});
end
