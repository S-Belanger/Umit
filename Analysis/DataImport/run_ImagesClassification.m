function outFile = run_ImagesClassification(RawFolder, SaveFolder, varargin)
% RUN_IMAGESCLASSIFICATION calls the function
% IMAGESCLASSIFICATION from the IOI library (LabeoTech).

default_Output = {'fChan_475.dat','fChan.dat', 'rChan.dat', 'gChan.dat', 'yChan.dat'}; % This is here only as a reference for PIPELINEMANAGER.m . The real outputs will be stored in OUTFILE.
%%% Arguments parsing and validation %%%
p = inputParser;
% Raw folder:
addRequired(p, 'RawFolder', @isfolder);
% Save folder:
addRequired(p, 'SaveFolder', @isfolder);
% Optional Parameters:
% opts structure:
default_opts = struct('BinningSpatial', 1, 'BinningTemp', 1, 'b_SubROI', false, 'b_IgnoreStim', true);
addOptional(p, 'opts', default_opts,@(x) isstruct(x) && ~isempty(x));

parse(p, RawFolder, SaveFolder, varargin{:});
%Initialize Variables:
RawFolder = p.Results.RawFolder;
SaveFolder = p.Results.SaveFolder;
opts = p.Results.opts;
outFile = {};
%%%%
% Get existing Labeo Imaging files in directory:
existing_ChanList  = dir('*Chan*.dat');
% Calls function from IOI library. Temporary for now.
ImagesClassification(RawFolder, SaveFolder, opts.BinningSpatial, opts.BinningTemp, opts.b_SubROI, opts.b_IgnoreStim)
% Get only new files created during ImagesClassification:
chanList = dir('*Chan*.dat');
idxName = ismember({chanList.name}, {existing_ChanList.name});
idxDate = ismember([chanList.datenum], [existing_ChanList.datenum]);
idxNew = ~all([idxName; idxDate],1);
chanList = {chanList(idxNew).name};
for i = 1:length(chanList)
    chanName = chanList{i};
    switch chanName
        case 'rChan.dat'
            MetaDataFileName = 'Data_red.mat';
        case 'yChan.dat'
            MetaDataFileName = 'Data_yellow.mat';
        case 'gChan.dat'
            MetaDataFileName = 'Data_green.mat';
        case 'dChan.dat'
            MetaDataFileName = 'Data_speckle.mat';
        otherwise
            MetaDataFileName = strrep(chanName, 'fChan', 'Data_Fluo');
            MetaDataFileName = strrep(MetaDataFileName, '.dat', '.mat');
    end
    a =  matfile(fullfile(SaveFolder,MetaDataFileName), 'Writable', true);
    a.fileUUID = char(java.util.UUID.randomUUID);
    a.Datatype = 'single';
    a.datName = 'data';
    a.dim_names = {'Y', 'X', 'T'};
    % TEMPORARY FIX.
    filePath = fullfile(SaveFolder,chanName);
    newmDfile = strrep(filePath, '.dat', '_info.mat');
    statusMat = movefile(MetaDataFileName, newmDfile);
    if ~statusMat
        disp(['Failed to rename ' MetaDataFileName]);
    else
        % Flip X,Y axis:
        [mData, metaData] = mapDatFile(filePath);
        if strcmpi(metaData.FirstDim, 'Y')
            mData.Writable = true;
            mData.Data.data = permute(mData.Data.data, [2 1 3]);
            metaData.Properties.Writable = true;
            metaData.dim_names = metaData.dim_names([2 1 3]);
            metaData.FirstDim = lower(metaData.dim_names{1});
        end
    end
    outFile = [outFile, chanName];
end
end