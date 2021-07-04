function outFile = apply_aggregate_function(File, SaveFolder, varargin)
% APPLY_AGGREGATE_FUNCTION applies an aggregate function to one or more
% dimensions of a .DAT file. 
% Inputs:
%   File : fullpath of functional imaging .DAT file.
%   SaveFolder : path to save the output file.
%   Output (optional) : Name of outFile.
%   opts (optional) : structure containing the function's parameters:
%       aggregateFcn (default = "mean") : name of the aggregate function.
%       dimensionName (default = "T") : name of the dimension(s) to perform
%       the calculation.
% Output:
%   outFile : name of Output file.

% Defaults:
default_opts = struct('aggregateFcn', 'mean', 'dimensionName', 'T');
default_Output = 'aggFcn_applied.dat'; 
%%% Arguments parsing and validation %%%
% Parse inputs:
p = inputParser;
addRequired(p,'File',@isfile & endsWith('.dat'))
addRequired(p, 'SaveFolder', @isfolder);
addOptional(p, 'opts', default_opts,@(x) isstruct(x) && ~isempty(x) && ...
    ismember(x.aggregateFcn, {'mean', 'max', 'min', 'median', 'mode', 'sum', 'std'}) && ...
    ~isempty(x.dimensionName) && (iscell(x.dimensionName) && ischar(x.dimenqsionName{:}) || ...
    ischar(x.dimensionName)));
addOptional(p, 'Output', default_Output)
% Parse inputs:
parse(p,File, SaveFolder, varargin{:});
%Initialize Variables:
File = p.Results.File; 
SaveFolder = p.Results.SaveFolder;
opts = p.Results.opts;
Output = p.Results.Output;

% Map .DAT file to memory:
[mData, metaData] = mapDatFile(File);

% Parse dimension names from opts struct:
str = opts.dimensionName;
str = split(str, ',');
dim_names= cellfun(@(x) upper(strip(x)), str, 'UniformOutput', false); 
% Validate if dimension name(s) is(are) in File meta data:
errID = 'Umitoolbox:apply_aggregate_function:InvalidName';
errMsg = 'Input dimension name(s) was not found in file meta data';
[idx_dims, dimVec] = ismember(dim_names, metaData.dim_names);
assert(all(idx_dims), errID, errMsg);

% Load Data:
data = mData.Data.(metaData.datName);
orig_data_sz = size(data);

% Permute data:
data = permute(data,[dimVec, setdiff(1:ndims(data), dimVec)]);
% Apply aggregate function:
data = applyAggFcn(data, opts.aggregateFcn);
% Remove singleton dimensions:
data = squeeze(data);
%Update dimension names:
dim_names = dim_names(setdiff(1:length(orig_data_sz), dimVec));

% Save DATA, METADATA and DIMENSION_NAMES to DATFILE:
[~,filename, ~] = fileparts(mData.Filename);
filename = [filename, '_', opts.aggregateFcn '.dat'];
datFile = fullfile(SaveFolder, filename);
save2Dat(datFile, data, dim_names);
% Output filename:
outFile = filename;
end

% Local function:
function out = applyAggFcn(vals, aggfcn, idxDim)
% APPLYAGGFCN performs the aggregate function of name "fcn_name" on the 1st
% dimension of the data "vals". All aggregate functions EXCLUDE NaNs!

switch aggfcn
    case 'mean'
        out = nanmean(vals, idxDim);
    case 'median'
        out = median(vals, idxDim, 'omitnan');
    case 'mode'
        out = mode(vals, idxDim);
    case 'std'
        out = std(vals, 0, idxDim, 'omitnan');
    case 'max'
        out = max(vals, [], idxDim, 'omitnan');
    case 'min'
        out = min(vals, [], idxDim, 'omitnan');
    case 'sum'
        out = sum(vals, idxDim, 'omitnan');
    otherwise
        out = vals;
end
end
