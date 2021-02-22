function outFile = GSR(File, SaveFolder, varargin)
% GSR performs global signal regression to data with path specified as
% ARGS.INPUT in order to remove global fluctuations from signal.
%%% Arguments parsing and validation %%%
p = inputParser;
% The input of the function must be a File , RawFolder or SaveFolder
addRequired(p,'File',@isfile)% For a file as input.
% Save folder:
addRequired(p, 'SaveFolder', @isfolder);
% Output File: 
default_Output = 'GSR.dat';
addOptional(p, 'Output', default_Output, @(x) ischar(x) || isstring(x) || iscell(x));
% Parse inputs:
parse(p,File, SaveFolder, varargin{:});
%Initialize Variables:
File = p.Results.File;
SaveFolder = p.Results.SaveFolder;
Output = p.Results.Output;
%%%%

mmData = mapDatFile(File);
% Load Data:
data = mmData.Data.data;
szData = size(data);
data = reshape(data, [], szData(3), 1);
% Calculate GSR:
mData = mean(data,3);
Sig = mean(data);
Sig = Sig / mean(Sig);
X = [ones(szData(3),1), Sig'];
B = X\data';
A = X*B;
clear X B Sig
data = data - A';%Center at Zero
data = data + mData; %Center over constant mean value.
data = reshape(data,szData);

% SAVING DATA :
% Generate .DAT and .MAT file Paths:
datFile = fullfile(SaveFolder, Output);
% Save to .DAT file and create .MAT file with metaData:
save2Dat(datFile, data);
outFile = Output;
end


