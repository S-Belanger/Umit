function [eventID, state, timestamps] = getEventsFromTTL(TTLsignal, sample_rate, varargin)
% GETEVENTSFROMTTL gets the channel, state and time stamps of a 
% TTL signal(TTLSIGNAL) passing a given threshold(THRESHOLD).
% Inputs:
% TTLsignal: a nChannel x Signal matrix containing the analog TTL signal.
% sample_rate : The sample rate of the TTL signal recording.
% threshold (Optional): threshold value in Volts. If not provided, 2.5V is
% used.
% Outputs:
%   eventID: list of channels (index of rows from TTLsignal matrix).
%   state: state of the channel : 1 = rising; 0 = falling.
%   timestamps: time stamps of events in seconds.

default_threshold = 2.5;

p = inputParser;
validAnalogData = @(x) isnumeric(x) && ~isscalar(x);
validNumScal = @(x) isnumeric(x) && isscalar(x);
addRequired(p, 'TTLsignal', validAnalogData);
addRequired(p, 'sample_rate', validNumScal);
addOptional(p,'threshold', default_threshold, validNumScal);
parse(p,TTLsignal, sample_rate, varargin{:});

data = p.Results.TTLsignal;
sr = p.Results.sample_rate;
thr = p.Results.threshold;

% Flips the matrix to have nChannels x nSamples: assuming that
% there are more samples than channels.
if size(data,1) > size(data,2)
    data = data';
end
% Find samples that cross the threshold (rising and falling):
szdat = size(data);
idx = data > thr;
dif = diff(idx,1,2); dif = [dif zeros(szdat(1),1)];

[chanRise,tmRise] = find(dif == 1);
tmRise = tmRise./sr; % transform sample into seconds;
[chanFall,tmFall] = find(dif == -1);
tmFall = tmFall./sr; % transform sample into seconds;
eventID = uint16([chanRise chanFall]);
timestamps = single([tmRise tmFall]);
state = [ones(1,numel(tmRise), 'uint8') zeros(1,numel(tmFall), 'uint8')];
% Sort arrays by time and flip:
[timestamps,idx] = sort(timestamps);
timestamps = timestamps';
eventID = eventID(idx)';
state = state(idx)';
end