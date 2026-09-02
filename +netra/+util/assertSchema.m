function assertSchema(cr)
%ASSERTSCHEMA  Verify a caseRecord contains every required field.
%   netra.util.assertSchema(cr) throws NETRA:schema:missingField if any
%   required field path is absent. ALL missing paths are collected and
%   reported in a single error message, not just the first.
%
%   The required-field list is derived from a fresh newCaseRecord: this
%   guarantees assertSchema and the factory can never drift apart. The
%   demo image path is used only to build that reference record.
%
%   Example:
%     netra.util.assertSchema(cr);   % silent if valid, errors otherwise

    arguments
        cr (1,1) struct
    end

    required = localRequiredPaths();
    missing = strings(1,0);
    for k = 1:numel(required)
        if ~hasPath(cr, required(k))
            missing(end+1) = required(k); %#ok<AGROW>
        end
    end

    if ~isempty(missing)
        error('NETRA:schema:missingField', ...
            'caseRecord is missing %d required field(s):\n  %s', ...
            numel(missing), strjoin(missing, sprintf('\n  ')));
    end
end

% ------------------------------------------------------------------------
function tf = hasPath(s, dottedPath)
%HASPATH  True if the dotted field path exists in struct s.
    parts = split(dottedPath, ".");
    tf = true;
    for i = 1:numel(parts)
        if ~isstruct(s) || ~isfield(s, parts(i))
            tf = false;
            return;
        end
        s = s.(parts(i));
    end
end

function paths = localRequiredPaths()
%LOCALREQUIREDPATHS  Full dotted field list, generated from the factory.
%   Built once from a reference record so the schema stays authoritative
%   in newCaseRecord alone. errors/img/timing/provenance leaf sets are
%   dynamic per run, so we require the groups exist, not every leaf.
    ref = netra.newCaseRecord(localDemoImage());
    paths = strings(1,0);
    groups = fieldnames(ref);
    for g = 1:numel(groups)
        grp = groups{g};
        paths(end+1) = string(grp); %#ok<AGROW>
        % errors is a struct array (may be 0x0); provenance/timing leaves
        % are stage-driven. Require the group only for these three.
        if any(strcmp(grp, {'errors','timing','provenance'}))
            continue;
        end
        val = ref.(grp);
        if isstruct(val) && isscalar(val)
            leaves = fieldnames(val);
            for L = 1:numel(leaves)
                paths(end+1) = string([grp '.' leaves{L}]); %#ok<AGROW>
            end
        end
    end
end

function p = localDemoImage()
%LOCALDEMOIMAGE  Path to the bundled demo image, relative to this file.
    here = fileparts(mfilename('fullpath'));           % +util
    root = fileparts(fileparts(here));                 % project root
    p = fullfile(root, 'data', 'demo', 'sample01.jpg');
end
