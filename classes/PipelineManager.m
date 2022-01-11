classdef PipelineManager < handle
    % PIPELINEMANAGER manages data processing pipelines.
    % This class allows the creation of analysis pipeline and manages the execution of
    % functions. In addition, it controls for failed / completed  steps in the pipeline.
    
    properties
        b_ignoreLoggedFiles  = false %(bool) If true, PIPELINEMANAGER will ignore identical jobs previously run.
        b_saveDataBeforeFail = false %(bool) If true, the more recent data ("current_data") in the pipeline will be...
        % saved to a file when an error occurs.
    end
    properties (SetAccess = private)
        
        % Structure array containing steps of the pipeline.
        pipe = struct('className', '','argsIn', {},'argsOut',{},'outFileName','',...
            'inputFileName', '','lvl', [], 'b_save2Dat', logical.empty, 'datFileName',...
            '', 'opts',[],'name','');% !!If the fields are changed, please apply
        % the same changes to the property's set method.
        
        fcnDir char % Directory of the analysis functions.
        funcList struct % structure containing the info about each function in the "fcnDir".
        ProtocolObj Protocol % Protocol Object.
        b_taskState = false % Boolean indicating if the task in pipeline was successful (TRUE) or not (FALSE).
        tmp_LogBook % Temporarily stores the table from PROTOCOL.LOGBOOKFILE
        tmp_BranchPipeline % Temporarily stores LogBook from a Hierarchical branch.
        PipelineSummary % Shows the jobs run in the current Pipeline
        tmp_TargetObj % % Temporarily stores an object (TARGEROBJ).
    end
    properties (Access = private)
        current_task % Task structure currently running.
        current_pipe % Pipeline currently running.
        current_data % Data available in the workspace during pipeline.
        current_metaData % MetaData associated with "current_data".
        current_outFile cell % List of file names created as output from some of the analysis functions.
        b_state logical % True if a task of a pipeline was successfully executed.
        pipeFirstInput = '' % Name of the first data to be used by the Pipeline.
        % It can be the name of an existing file, or
        % "outFile" for a function that creates a file
        % such as "run_ImagesClassification".
    end
    methods
        % Constructor
        function obj = PipelineManager(ProtocolObj)
            % PIPELINEMANAGER Construct an instance of this class
            %  Input:
            %   ProtocolObj(Protocol): Protocol object. This input is
            %   needed to have access to the protocol's hierarchy of
            %   objects.
            
            p = inputParser;
            addRequired(p,'ProtocolObj', @(x) isa(x, 'Protocol'));
            parse(p,ProtocolObj);
            obj.ProtocolObj = p.Results.ProtocolObj;
            root = getenv('Umitoolbox');
            obj.fcnDir = fullfile(root, 'Analysis');
            obj.createFcnList;
            obj.b_ignoreLoggedFiles = false;
            obj.b_saveDataBeforeFail = false;
        end
        % SETTERS %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        function set.pipe(obj, pipe)
            % Pipeline structure setter. If pipe is empty, create an empty
            % structure containing tasks fields.
            
            if isempty(fieldnames(pipe))
                pipe = struct('className', '','argsIn', {},'argsOut',{},'outFileName','',...
                    'inputFileName', '','lvl', [], 'b_save2Dat', logical.empty, 'datFileName',...
                    '', 'opts',[],'name','');
            end
            % Check if all fields exist:
            if ~all(ismember(fieldnames(pipe),fieldnames(obj.pipe)))
                error('umIToolbox:PipelineManager:InvalidInput',...
                    'The pipeline structure provided is invalid!');
            end
            obj.pipe = pipe;
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        function setOpts(obj, func)
            % SETOPTS opens an INPUTDLG for entry of optional variables
            % (OPTS) of methods in the Pipeline.
            
            idx = obj.check_funcName(func);
            if isempty(idx)
                return
            end
            
            S = obj.funcList(idx).info.opts;
            if isempty(S)
                disp(['The function ' obj.funcList(idx).name ' does not have any optional parameters.']);
                return
            end
            fields = fieldnames(S);
            b_isNum = structfun(@(x) isnumeric(x), S);
            b_isLogic = structfun(@(x) islogical(x), S);
            for i = 1:length(fields)
                if b_isNum(i)
                    fields{i} = [fields{i} ' (numeric)'];
                elseif b_isLogic(i)
                    fields{i} = [fields{i} ' (logical: 0 or 1)'];
                end
            end
            prompt = fields;
            dlgtitle = ['Set optional parameters for ' obj.funcList(idx).name];
            dims = [1 35];
            definput = structfun(@(x) {num2str(x)}, S);
            opts.Resize = 'on';
            answer = inputdlg(prompt,dlgtitle,dims,definput,opts);
            if isempty(answer)
                disp('Operation cancelled by User');
                return
            end
            fields = fieldnames(S);
            for i = 1:length(answer)
                if b_isNum(i)
                    obj.funcList(idx).info.opts.(fields{i}) = str2double(answer{i});
                elseif b_isLogic(i)
                    obj.funcList(idx).info.opts.(fields{i}) = logical(str2double(answer{i}));
                else
                    obj.funcList(idx).info.opts.(fields{i}) = answer{i};
                end
            end
            disp(['Optional Parameters set for function : ' obj.funcList(idx).name]);
        end
        function addTask(obj,className, func, varargin)
            % This method adds an analysis function, or task, to the
            % pipeline. Here, we can choose to save the output of a given
            % task as a .DAT file. ADDTASK will create a string containing
            % the task that will be evaluated during pipeline execution.
            % Inputs:
            %   className (str): name of the object (Subject, Acquitision,
            %       Modality, etc) that the task will run.
            %   func (str || char):  name or index of the analysis function
            %       contained in obj.funcList property.
            %   b_save2Dat (bool): Optional. True means that the output data
            %       from the function will be saved as a .DAT file.
            %   datFileName(char): Optional. Name of the file to be saved.
            %       If not provided, the analysis function's default
            %       filename will be used.
            
            p = inputParser;
            addRequired(p,'className', @(x) ischar(x) || isstring(x));
            addRequired(p, 'func', @(x) ischar(x) || isnumeric(x));
            addOptional(p, 'b_save2Dat', false, @islogical);
            addOptional(p, 'datFileName', '', @ischar);
            parse(p,className, func, varargin{:});
            
            % Check if the function name is valid:
            idx = obj.check_funcName(p.Results.func);
            if isempty(idx)
                warning('Operation cancelled! The function "%s" does not exist!',...
                    p.Results.func);
                return
            end
            % Create "task" structure. This is the one that will be added
            % to the pipeline:
            task = obj.funcList(idx).info;
            task.inputFileName = '';
            task.className = p.Results.className;
            task.name = obj.funcList(idx).name;
            task.b_save2Dat = p.Results.b_save2Dat;
            task.datFileName = p.Results.datFileName;
            % Determine Level of the task in the Protocol's hierarchy.
            switch p.Results.className
                %                 case 'Protocol' % Disabled for now.
                %                     lvl = 4;
                case 'Subject'
                    task.lvl = 3;
                case 'Acquisition'
                    task.lvl = 2;
                otherwise
                    task.lvl = 1;
            end
            % Control for steps IDENTICAL to the task that are already in the pipeline:
            idx_equal = arrayfun(@(x) isequaln(task,x), obj.pipe);
            if any(idx_equal)
                warning('Operation cancelled! The function "%s" already exists in the Pipeline!',....
                    task.name);
                return
            end
            
            % Look for first input file to the pipeline;
            if isempty(obj.pipeFirstInput)
                task.inputFileName = obj.getFirstInputFile(task);
                if task.inputFileName == 0
                    disp('Operation Cancelled by User')
                    return
                end
            end
            
            %             if any(contains('data', task.argsIn)) &
            % Control for multiple outputs from the previous step:
            % Here, we assume that functions with multiple outputs
            % create only "Files" and not "data".
            % Therefore, we will update the function string to load
            % one of the "Files" before running the task.
            
            % Look from bottom to top of the pipeline for tasks with files
            % as outputs. This is necessary because not all analysis
            % functions have outputs.
            
            for i = length(obj.pipe):-1:1
                if ismember('outData', obj.pipe(i).argsOut)
                    break
                elseif any(strcmp(task.argsIn, 'data')) && any(strcmp('outFile', obj.pipe(i).argsOut))
                    if iscell(obj.pipe(i).outFileName)
                        % Ask user to select a file:
                        disp('Controlling for multiple outputs')
                        w = warndlg({'Previous step has multiple output files!',...
                            'Please, select one to be analysed!'});
                        waitfor(w);
                        [indxFile, tf] = listdlg('ListString', obj.pipe(i).outFileName,...
                            'SelectionMode','single');
                        if ~tf
                            disp('Operation cancelled by User')
                            return
                        end
                        task.inputFileName = obj.pipe(i).outFileName{indxFile};
                    else
                        task.inputFileName = obj.pipe(i).outFileName;
                    end
                end
            end
            % Save to Pipeline:
            obj.pipe = [obj.pipe; task];
            disp(['Added "' task.name '" to pipeline.']);
            
            % Control for data to be saved as .DAT files for task:
            if ~task.b_save2Dat
                return
            end
            if ~any(strcmp('outData', task.argsOut))
                warning(['Cannot save output to .DAT file for the function'...
                    ' "%s" \nbecause it doesn''t have any data as output!'], task.name);
                return
            end
            % Save datFileName as default output name from task's function:
            if isempty(task.datFileName)
                obj.pipe(end).datFileName = obj.pipe(end).outFileName;
                % OR update datFileName to add file extension:
            else
                obj.pipe(end).datFileName = [obj.pipe(end).datFileName, '.dat'];
            end
            
        end
        function varargout = showPipeSummary(obj)
            % This method creates a summary of the current pipeline.
            
            % Output (optional): if an output variable exists, it creates a
            % character array, if not, the information is displayed in the
            % command window.
            
            if isempty(obj.pipe)
                disp('Pipeline is empty!')
                if nargout == 1
                    varargout{1} = '';
                end
                return
            end
            
            str = sprintf('%s\n', 'Pipeline Summary:');
            for i = 1:length(obj.pipe)
                str =  [str sprintf('--->> Step # %d <<---\n', i)];
                if isempty(obj.pipe(i).opts)
                    opts = {'none'; 'none'};
                else
                    opts = [fieldnames(obj.pipe(i).opts)';...
                        cellfun(@(x) num2str(x), struct2cell(obj.pipe(i).opts), 'UniformOutput', false)'];
                end
                txt = sprintf('Function name : %s\nOptional Parameters:\n',...
                    obj.pipe(i).name);
                str = [str, txt, sprintf('\t%s : %s\n', opts{:})];
                if obj.pipe(i).b_save2Dat
                    str = [str, sprintf('Data to be saved as : "%s"\n', obj.pipe(i).datFileName)];
                end
                if ~isempty(obj.pipe(i).inputFileName)
                    str = [str, sprintf('Input File Name : "%s"\n', obj.pipe(i).inputFileName)];
                end
                str = [str, sprintf('--------------------\n')];
            end
            if nargout == 0
                disp(str)
            else
                varargout{1} = str;
            end
        end
        function showFuncList(obj)
            % Displays a list of analysis function from "obj.funcList" in
            % the command window.
            disp('List of available functions (index : Name) :');
            for i = 1:length(obj.funcList)
                fprintf('%d : %s\n', i, obj.funcList(i).name);
            end
        end
        
        
        % TO BE CHANGED... %%
        function run_pipeline(obj)
            % RUN_PIPELINE runs the tasks in OBJ.PIPE
            lbf = matfile(obj.ProtocolObj.LogBookFile);
            obj.tmp_LogBook = lbf.LogBook;
            obj.PipelineSummary = obj.ProtocolObj.createEmptyTable;
            % Identify the maximum level in the hierarchy to run the
            % pipeline.
            top_lvl = max([obj.pipe.lvl]);
            % Get indexes of Filtered Objects from OBJ.PROTOCOLOBJ.QUERYFILTER function.
            idxList = obj.ProtocolObj.Idx_Filtered;
            % Identify branches in the hierarchy that will be processed in
            % a single pipeline run.
            ppIdx = zeros(size(idxList,1),1);
            switch top_lvl
                % The pipeline will run at the modality level.
                case 1
                    ppIdx = (1:size(idxList,1))';
                    % The pipeline will run at the acquisition level.
                case 2
                    a = 1;
                    uniqA = unique(idxList(:,[1 2]),'rows');
                    for i = 1:size(uniqA,1)
                        idx = all(idxList(:,[1 2]) == uniqA(i,:),2);
                        ppIdx(idx) = a;
                        a = a+1;
                    end
                    % The pipeline will run at the subject level.
                case 3
                    a = 1;
                    uniqS = unique(idxList(:,1),'rows');
                    for i = 1:length(uniqS)
                        idx = all(idxList(:,1) == uniqS(i,:),2);
                        ppIdx(idx) = a;
                        a = a+1;
                    end
            end
            f = waitbar(0,'Analysing data...', 'Name', 'Pipeline progress');
            % run pipeline at each branch of the hierarchy
            uniq_branch = unique(ppIdx);
            for i = 1:length(uniq_branch)
                %                 obj.b_state = true;
                waitbar(i/length(uniq_branch),f);
                branch = idxList(ppIdx == uniq_branch(i),:);
                obj.run_tasksOnBranch(branch);
            end
            
            obj.PipelineSummary(1,:) = []; % remove dummy row.
            
            LogBook = obj.PipelineSummary;
            save(obj.ProtocolObj.LogBookFile, 'LogBook');
            disp(obj.PipelineSummary)
            
            % Save Protocol Object:
            protocol = obj.ProtocolObj;
            save([obj.ProtocolObj.SaveDir obj.ProtocolObj.Name '.mat'], 'protocol');
            disp('Protocol object Saved!');
            waitbar(1,f,'Finished!');
            delete(f)
        end
        %%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        
        % Pipeline Management methods:
        function savePipe(obj, filename)
            % SAVEPIPE saves the structure OBJ.PIPE in a .MAT file in the
            % folder PIPELINECONFIGFiles inside MAINDIR of OBJ.PROTOCOLOBJ.
            targetDir = fullfile(obj.ProtocolObj.SaveDir, 'PipeLineConfigFiles');
            [~,~] = mkdir(targetDir);
            pipeStruct = obj.pipe;
            txt = jsonencode(pipeStruct);
            fid = fopen(fullfile(targetDir,[filename '.json']), 'w');
            fprintf(fid, '%s', txt);
            fclose(fid);
            disp(['Pipeline saved as "' filename '" in ' targetDir]);
        end
        function loadPipe(obj, filename)
            % LOADPIPE loads the structure PIPE inside FILENAME and assigns
            % it to OBJ.PIPE property.
            if ~isfile(filename)
                filename = fullfile(obj.ProtocolObj.SaveDir, 'PipeLineConfigFiles',...
                    [filename, '.json']);
            end
            txt = fileread(filename);
            obj.pipe = jsondecode(txt);
            disp('Pipeline Loaded!');
            obj.showPipeSummary;
        end
        function reset_pipe(obj)
            % This function erases the pipe property and resets the funcList
            % property to default parameter values.
            obj.pipe = struct();
            obj.funcList = struct.empty;
            obj.createFcnList;
        end
    end
    
    methods (Access = private)
        
        function subTasks = pipeSplitter(obj)
            % PIPESPLITTER segments the pipeline in sub-pipelines that are run
            % at each level of the Hierarchy.
            
            % Find consecutive levels
            lvls = [obj.pipe.lvl];
            idx = ones(1,length(lvls));
            a = 1;
            for i = 1:length(lvls)-1
                lvl = lvls(i);
                next_lvl = lvls(i+1);
                if lvl ~= next_lvl
                    idx(i) = a;
                    a = a+1;
                    idx(i+1) = a;
                else
                    idx(i) = a;
                    idx(i+1) = a;
                end
            end
            uniq_idx = unique(idx);
            subTasks = cell(1,numel(uniq_idx));
            for i = 1:numel(uniq_idx)
                b_idx = ( idx == uniq_idx(i) );
                subTasks{i} = obj.pipe(b_idx);
            end
        end
        function run_tasksOnBranch(obj, branch)
            % RUN_TASKSONBRANCH finds the object to run the tasks in the
            % pipeline.
            
            % Split pipeline if there is more than one level.
            ppLine = obj.pipeSplitter;
            obj.tmp_BranchPipeline = obj.ProtocolObj.createEmptyTable;
            for i = 1:length(ppLine)
                subtasks = ppLine{i};
                obj.current_pipe = subtasks;
                lvl = subtasks.lvl;
                switch lvl
                    case 1
                        targetIdxArr = unique(branch,'rows');
                    case 2
                        targetIdxArr = unique(branch(:,[1 2]), 'rows');
                    case 3
                        targetIdxArr = unique(branch(:,1), 'rows');
                end
                
                for j = 1:size(targetIdxArr,1)
                    obj.getTargetObj(targetIdxArr(j,:));
                    obj.tmp_TargetObj.LastLog = obj.ProtocolObj.createEmptyTable;
                    
                    for k = 1:length(subtasks)
                        obj.current_task = subtasks(k);
                        obj.run_taskOnTarget;
                        if ~obj.b_state
                            return
                        end
                    end
                    obj.tmp_BranchPipeline = [obj.tmp_BranchPipeline; obj.tmp_TargetObj.LastLog];
                end
            end
            
        end
        function run_taskOnTarget(obj)
            % RUN_TASKONTARGET runs a task in the pipeline structure array in
            % TASK.
            %   It checks if the command TASK.FUNCNAME was already
            %   sucessfully performed by comparing it to the LOGBOOK from
            %   the PROTOCOL object. Also, it appends the information of
            %   the task on the object's LASTLOG.
            
            % Current task:
            task = obj.current_task;
            % Initialize empty Log for current object:
            LastLog = obj.ProtocolObj.createEmptyTable;
            % Fill out Log with Subject/Acquisition/Modality IDs :
            cnt = 2;
            tmpObj = obj.tmp_TargetObj;
            ID_list = {tmpObj.ID};
            while ~isa(tmpObj.MyParent, 'Protocol')
                tmpObj = tmpObj.MyParent;
                ID_list{cnt} = tmpObj.ID;
                cnt = cnt+1;
            end
            LastLog(:,1:3) = fliplr(ID_list);
            clear tmpObj
            % Add class name to table:
            LastLog(:,4) = {task.className};
            %%%
            
            % Create function string and update log table:
            task.funcStr = createFcnString(obj, task);
            LastLog.Job = {task.funcStr};
            
            % Check for data already run and skip step if so:
            b_skipStep = obj.checkDataHistory(task);
            
            if b_skipStep & ~obj.b_ignoreLoggedFiles
                disp(['Skipped function' task.name '!']);
                LastLog.Messages_short = 'Skipped';
                LastLog.Completed = true;
                return
            end
            
            %  Execute the task:
            try
                % Control for missing input files:
                if task.inputFileName
                    errID = 'MATLAB:Umitoolbox:pipelineManager:FileNotFound';
                    errmsg = ['Input File for function ' task.Name ' not found!'];
                    assert(~isfile(fullfile(obj.tmp_TargetObj.SaveFolder, task.inputFileName)),...
                        errID,errmsg);
                end
                disp(['Running  function : ' task.name '...']);
                % Load options structure in the workspace.
                opts = task.opts;%#ok the "opts" structure is used in the EVAL function.
                % Evaluate function string:
                eval(task.funcStr);
                % Update log table and tell other methods that the function
                % was successfully run:
                obj.b_state = true;
                LastLog.Messages = 'No Errors';
                % Optionally, save the current Data to a file:
                if task.b_save2Dat
                    obj.saveDataToFile(task);
                end
                % Update data history of current data with task:
                obj.updateDataHistory(task);
                
            catch ME
                obj.b_state = false;
                LastLog.Messages = {getReport(ME)};
                LastLog.Messages_short = {getReport(ME, 'basic','hyperlinks','off')};
                if obj.b_saveDataBeforeFail
                    obj.saveDataToFile(task);
                end
            end
            % Update log table of target object:
            LastLog.Completed = obj.b_state;
            LastLog.RunDateTime = datetime('now');
            obj.tmp_TargetObj.LastLog = [obj.tmp_TargetObj.LastLog; LastLog];
            
            
            
            
            
            
            %
            %
            %
            %
            %
            %             %%%%%%%%% OLD CODE %%%%%%%%%%%%%
            %             if ~strcmp(task.InputFile_UUID, 'None')
            %                 LastLog.InputFile_UUID = {task.InputFile_UUID};
            %                 LastLog.InputFile_Path = {task.Input};
            %             end
            %             LastLog.ClassName = {class(obj.tmp_TargetObj)};
            %             LastLog.Job = {task.funcStr};
            %             % Check if Job was already performed:
            %             b_isLogged = obj.checkInFilePtr(task);
            %             if ~b_isLogged || (b_isLogged && obj.IgnoreLoggedFiles)
            %                 % Run the step:
            %                 try
            %                     if strcmp(task.Input, 'missing')
            %                         errID = 'MATLAB:Umitoolbox:pipelineManager:FileNotFound';
            %                         errmsg = ['Input File for function ' task.Name ' not found!'];
            %                         error(errID,errmsg);
            %                     end
            %                     disp(['Running ' task.Name '...']);
            %                     % Load options structure in the workspace.
            %                     opts = task.opts;
            %                     % Evaluate function string:
            %                     eval(task.funcStr);
            %                     %
            %                     state = true;
            %                     LastLog.Messages = 'No Errors';
            %                 catch ME
            %                     state = false;
            %                     LastLog.Messages = {getReport(ME)};
            %                     LastLog.Messages_short = {getReport(ME, 'basic','hyperlinks','off')};
            %                 end
            %                 LastLog.Completed = state;
            %                 LastLog.RunDateTime = datetime('now');
            %                 obj.tmp_TargetObj.LastLog = [obj.tmp_TargetObj.LastLog; LastLog];
            %                 obj.pipelineSummary = [obj.pipelineSummary; LastLog];
            %                 obj.b_state = state;
            %                 if LastLog.Completed
            %                     disp('Task Completed!')
            %                     if exist('out', 'var')
            %                         if ischar(out)
            %                             out = {out};
            %                         end
            %                         for i = 1:length(out)
            %                             SaveFolder = task.SaveIn;
            %                             if endsWith(out{i}, '.dat')
            %                                 mDt_file = matfile(strrep(fullfile(SaveFolder, out{i}), '.dat', '_info.mat'),'Writable', true);
            %                             else
            %                                 mDt_file = matfile(out{i},'Writable', true);
            %                             end
            %                             % Inheritance of MetaData from last File created (Different ones ONLY by different function).
            %                             lastFile = task.Input;
            %                             if isfile(lastFile)
            %                                 lastMetaData = matfile(strrep(lastFile, '.dat', '_info.mat'));
            %                                 props = setdiff(properties(lastMetaData), properties(mDt_file));
            %                                 for k = 1:length(props)
            %                                     eval(['mDt_file.' props{k} '= lastMetaData.' props{k} ';'])
            %                                 end
            %                             end
            %                             fileUUID = mDt_file.fileUUID;
            %                             if iscell(fileUUID)
            %                                 fileUUID = [fileUUID{:}];
            %                             end
            %                             task.File_UUID = fileUUID;
            %                             task.FileName = out{i};
            %                             obj.current_task = task;
            %                             obj.write2FilePtr(task);
            %                         end
            %                     end
            %                 else
            %                     disp('Failed!')
            %                 end
            %             else
            %                 disp([task.Name ' Skipped!'])
            %                 obj.b_state = true;
            %                 return
            %             end
        end
        function getTargetObj(obj, targetIdx)
            % GETTARGETOBJ finds the object TARGETOBJ indicated by the
            % index TARGETIDX inside PROTOCOL.
            
            tgtSz = size(targetIdx,2);
            switch tgtSz
                case 1
                    targetObj = obj.ProtocolObj.Array.ObjList(targetIdx);
                case 2
                    targetObj = obj.ProtocolObj.Array.ObjList(targetIdx(1)).Array.ObjList(targetIdx(2));
                case 3
                    targetObj = obj.ProtocolObj.Array.ObjList(targetIdx(1)).Array.ObjList(targetIdx(2)).Array.ObjList(targetIdx(3));
            end
            obj.tmp_TargetObj = targetObj;
        end
        
        function out = getFirstInputFile(obj, funcInfo)
            % This method verifies is the function has any data as input.
            % If yes, then a creates an dialog box containing a list of .DAT files
            % to choose as input. This method is called by ADDTASK only
            % when the first task of a pipeline is created.
            % Input:
            %   funcInfo (struct): structure containing the task's function info.
            % Output:
            %   out (char): name of input file. Empty if file does not exist.
            
            out = '';
            % Control for function that creates the first input:
            if any(strcmp('outFile', funcInfo.argsOut))
                obj.pipeFirstInput = 'outFile';
                return
            end
            
            % Control for tasks that do not have any data as input:
            if ~any(ismember({'data', 'dataStat'}, funcInfo.argsIn))
                return
            end
            
            
            % Get all existing objects from the selected items in Protocol
            % object:
            idx = unique(obj.ProtocolObj.Idx_Filtered,'rows');
            classes = {};
            for i = 1:size(idx,1)
                classes{i} = class(obj.ProtocolObj.Array.ObjList(idx(i,1)).Array.ObjList(idx(i,2)).Array.ObjList(idx(i,3)));
            end
            classes = [{'Subject', 'Acquisition'}  classes]; classes = unique(classes);
            % Select Object containing input file:
            [indx,tf] = listdlg('PromptString', {'Select the Object containing', 'the input for the function :',...
                funcInfo.name},'ListString',classes, 'SelectionMode', 'single');
            if ~tf
                out = 0;
                return
            end
            switch classes{indx}
                case 'Subject'
                    targetObj = obj.ProtocolObj.Array.ObjList(idx(1,1));
                case 'Acquisition'
                    targetObj = obj.ProtocolObj.Array.ObjList(idx(1,1)).Array.ObjList(idx(1,2));
                otherwise
                    for i = 1:size(idx,1)
                        b_isMod = strcmp(class(obj.ProtocolObj.Array.ObjList(idx(i,1)).Array.ObjList(idx(i,2)).Array.ObjList(idx(i,3))), classes{indx});
                        if b_isMod
                            break
                        end
                    end
                    targetObj = obj.ProtocolObj.Array.ObjList(idx(i,1)).Array.ObjList(idx(i,2)).Array.ObjList(idx(i,3));
            end
            
            % Display a list of files from the selected
            % object(targetObj):
            datFileList = dir(fullfile(targetObj.SaveFolder, '*.dat'));
            if any(strcmp('outDataStat', funcInfo.argsOut))
                % Select only .MAT files containing "dataHistory" variable.
                % This was a way to exclude other .MAT files in the folder
                % that are not Stats files.
                matFileList = dir(fullfile(targetObj.SaveFolder, '*.mat'));
                matFilesMap = arrayfun(@(x) matfile(fullfile(x.folder,x.name)), matFileList, 'UniformOutput',false);
                b_validMat = cellfun(@(x) isprop(x, 'dataHistory'), matFilesMap);
                [~,datFileNames,~] = arrayfun(@(x) fileparts(x.name), datFileList, 'UniformOutput', false);
                [~,matFileNames,~] = arrayfun(@(x) fileparts(x.name), matFileList, 'UniformOutput', false);
                b_statMat = ~ismember(matFileNames, datFileNames);
                % Update index of valid .mat files:
                b_validMat = b_validMat & b_statMat;
                FileList = matFileList(b_validMat);
            else
                FileList = datFileList;
            end
            if isempty(FileList)
                warndlg(['No valid Files found in ' targetObj.SaveFolder], 'pipeline warning!', 'modal')
                out = 0;
                return
            else
                [indx,tf] = listdlg('PromptString', {'Select the File from ' classes{indx},...
                    'as input for the function :',  funcInfo.name},'ListString',{FileList.name}, 'SelectionMode',...
                    'single');
                if ~tf
                    out = 0;
                    return
                end
            end
            
            % Save first input
            out = FileList(indx).name;
            obj.pipeFirstInput = out;
        end
        
        %         function readFilePtr(obj)
        %             % READFILEPTR loads the content of FILEPTR.JSON in a structure
        %             % stored in OBJ.TMP_FILEPTR.
        %             txt = fileread(obj.tmp_TargetObj.FilePtr);
        %             a = jsondecode(txt);
        %             for i = 1:numel(a.Files)
        %                 a.Files(i).Folder = tokenizePath(a.Files(i).Folder, obj.tmp_TargetObj, 'detokenize');
        %                 a.Files(i).InputFile_Path = tokenizePath(a.Files(i).InputFile_Path, obj.tmp_TargetObj, 'detokenize');
        %             end
        %                 obj.tmp_FilePtr = a;
        %         end
        %         function write2FilePtr(obj, task)
        %             % WRITE2FILEPTR writes the File information stored in structure FILEINFO
        %             % in OBJ.TMP_TARGETOBJ.FILEPTR.
        %
        %             %Initialize
        %             FileInfo = struct('Name', task.FileName, 'UUID', task.File_UUID, 'Folder', task.SaveIn, 'InputFile_Path', task.Input,...
        %                 'InputFile_UUID', task.InputFile_UUID, 'creationDateTime', datestr(now), 'FunctionInfo', ...
        %                 struct('Name', task.Name, 'DateNum', task.DateNum, 'Job', task.funcStr, 'opts', task.opts));
        %
        %             FileList = obj.tmp_FilePtr.Files;
        %             % Check for Files already logged on FilePtr
        %             idx = false(length(FileList),2);
        %             for i = 1:length(FileList)
        %                 idx(i,1) = strcmp(FileInfo.Name, FileList(i).Name);
        %                 idx(i,2) = strcmp(FileInfo.FunctionInfo.Name, FileList(i).FunctionInfo.Name);
        %             end
        %             idx = all(idx,2);
        %             % If there are no Files
        %             if isempty(FileList)
        %                 obj.tmp_FilePtr.Files = FileInfo;
        %             % If there are files and one identical, replace it.
        %             elseif ~isempty(FileList) && any(idx)
        %                 obj.tmp_FilePtr.Files(idx) = FileInfo;
        %             % If there are files and none identical: Append
        %             else
        %                 obj.tmp_FilePtr.Files = [FileList; FileInfo];
        %             end
        %             for i = 1:numel(obj.tmp_FilePtr.Files)
        %                 obj.tmp_FilePtr.Files(i).Folder = tokenizePath(obj.tmp_FilePtr.Files(i).Folder, obj.tmp_TargetObj);
        %                 obj.tmp_FilePtr.Files(i).InputFile_Path = tokenizePath(obj.tmp_FilePtr.Files(i).InputFile_Path, obj.tmp_TargetObj);
        %             end
        %             txt = jsonencode(obj.tmp_FilePtr);
        %             fid = fopen(obj.tmp_TargetObj.FilePtr, 'w');
        %             fprintf(fid, '%s', txt);
        %             fclose(fid);
        %         end
        function createFcnList(obj)
            % This function creates a structure containing all information
            % about the analysis functions inside the "Analysis" folder.
            % This information is stored in the "funcList" property of
            % pipelineManager.
            
            % !!For now, it will read only folders directly below the
            % "Analysis" folder. Subfolders inside these folders will not
            % be read.
            
            % Set Defaults:
            default_Output = '';
            default_opts = struct();
            
            disp('Creating Fcn list...');
            list = dir(fullfile(obj.fcnDir, '\*\*.m'));
            for i = 1:length(list)
                out = parseFuncFile(list(i));
                % Validate if all input arguments from the function are
                % "valid" inputs keywords:
                kwrds_args = {'data', 'metaData', 'SaveFolder', 'RawFolder', 'opts', 'object', 'dataStat'};
                kwrds_out = {'outFile', 'outData', 'metaData', 'outDataStat'};
                if all(ismember(out.argsIn, kwrds_args)) && all(ismember(out.argsOut, kwrds_out))
                    %                     disp(list(i).name);
                    [~,list(i).name, ~] = fileparts(list(i).name);
                    list(i).info = out;
                    
                    obj.funcList = [obj.funcList ; list(i)];
                end
                
            end
            disp('Function list created!');
            function info = parseFuncFile(fcnStruct)
                info = struct('argsIn', {},'argsOut', {}, 'outFileName', '', 'opts', []);
                txt = fileread(fullfile(fcnStruct.folder, fcnStruct.name));
                funcStr = erase(regexp(txt, '(?<=function\s*).*?(?=\r*\n)', 'match', 'once'),' ');
                outStr = regexp(funcStr,'.*(?=\=)', 'match', 'once');
                out_args = regexp(outStr, '\[*(\w*)\,*(\w*)\]*', 'tokens', 'once');
                idx_empty = cellfun(@isempty, out_args);
                info(1).argsOut = out_args(~idx_empty);
                [~,funcName,~] = fileparts(fcnStruct.name);
                expInput = ['(?<=' funcName '\s*\().*?(?=\))'];
                str = regexp(funcStr, expInput, 'match', 'once');
                str = strip(split(str, ','));
                idx_varargin = strcmp(str, 'varargin');
                info.argsIn = str(~idx_varargin);
                expOutput = 'default_Output\s*=.*?(?=\n)';
                str = regexp(txt, expOutput, 'match', 'once');
                if isempty(str)
                    default_Output = '';
                else
                    eval(str)
                end
                info.outFileName = default_Output;
                expOpts = 'default_opts\s*=.*?(?=\n)';
                str = regexp(txt, expOpts, 'match', 'once');
                if ~isempty(str)
                    eval(str)
                    info.opts = default_opts;
                    info.argsIn{end+1} = 'opts';
                end
            end
        end
        function task = populateFuncStr(obj, task)
            % POPULATEFUNCSTR replaces keywords in TASK.FUNCSTR with the
            % info contained in OBJ.TMP_TARGETOBJ. It is used in
            % OBJ.RUN_TASKONTARGET.
            
            % Replace Input string:
            switch task.Input
                case 'RawFolder'
                    folder = obj.tmp_TargetObj.RawFolder;
                    task.Input = folder;
                case 'SaveFolder'
                    folder = obj.tmp_TargetObj.SaveFolder;
                    task.Input = folder;
                case 'object'
                    task.Input = 'obj.tmp_TargetObj';
                otherwise
                    % ALL THIS SECTION NEEDS TO BE CHANGED!!
                    if isempty(obj.tmp_FilePtr.Files)
                        task.Input = 'missing';
                        task.funcStr = '';
                        return
                    else
                        idx = strcmp(task.Input, {obj.tmp_FilePtr.Files.Name});
                        if sum(idx) == 0
                            try
                                % Try to find file with name different from
                                % default:
                                idx_pipe = strcmp(task.Input, {obj.current_pipe.Output});
                                prev_task = obj.current_pipe(idx_pipe);
                                % Find file in FilePtr from function in prev_task:
                                fcn_info = arrayfun(@(x) x.FunctionInfo, obj.tmp_FilePtr.Files);
                                idxFcnName = strcmp({fcn_info.Name}, prev_task.Name);
                                idxFcnDate = [fcn_info.DateNum] == prev_task.DateNum;
                                idx = idxFcnName & idxFcnDate;
                                if sum(idx) == 1
                                    filePath = fullfile(obj.tmp_TargetObj.SaveFolder, obj.tmp_FilePtr.Files(idx).Name);
                                else
                                    task.Input = 'missing';
                                    task.funcStr = '';
                                    return
                                end
                            catch
                                task.Input = 'missing';
                                task.funcStr = '';
                                return
                            end
                        end
                        if strcmp(obj.tmp_FilePtr.Files(idx).Folder, 'RawFolder')
                            filePath = fullfile(obj.tmp_TargetObj.RawFolder, obj.tmp_FilePtr.Files(idx).Name);
                        else
                            filePath = fullfile(obj.tmp_TargetObj.SaveFolder, obj.tmp_FilePtr.Files(idx).Name);
                        end
                    end
                    task.Input = filePath;
                    inputMetaData = strrep(filePath, '.dat', '_info.mat');
                    mDt_input = matfile(inputMetaData); fileUUID = mDt_input.fileUUID;
                    if iscell(fileUUID)
                        fileUUID = [fileUUID{:}];
                    end
                    task.InputFile_UUID = fileUUID;
            end
            % Replace SaveFolder string:
            switch task.SaveIn
                case 'RawFolder'
                    folder = obj.tmp_TargetObj.RawFolder;
                    task.SaveIn = folder;
                case 'SaveFolder'
                    folder = obj.tmp_TargetObj.SaveFolder;
                    task.SaveIn = folder;
            end
            if ~strcmp(task.Input, 'obj.tmp_TargetObj')
                funcStr = [task.Name '(''' task.Input ''',''' task.SaveIn ''''];
            else
                funcStr = [task.Name '(' task.Input ',''' task.SaveIn ''''];
            end
            % Fix empty input character "~":
            funcStr = strrep(funcStr, '''~''', '~');
            
            % Add optionals:
            if ~isempty(task.opts)
                funcStr = [funcStr ', opts'];
            end
            if ~isempty(task.Output)
                funcStr = ['out = ' funcStr];
            end
            funcStr = [funcStr ');'];
            task.funcStr = funcStr;
        end
        %%%%%%%%%% NEW METHODS %%%%%%%%
        function idx_fcn = check_funcName(obj, func)
            % This function is used by "setOpts" and "addTask" methods to
            % validate if the input "func" is valid.
            % Input
            %   func (numeric OR char) : index OR name of a function from
            %   obj.funcList.
            % Output:
            %   idx_fcn(bool): index of "func" in "obj.funcList". Returns
            %   empty if the function was not found in the list.
            idx_fcn = [];
            if isnumeric(func)
                idx_fcn = func == 1:length(obj.funcList);
                msg = ['Function with index # ' num2str(func)];
            else
                idx_fcn = strcmp(func, {obj.funcList.name});
                msg = ['Function "' func '"'];
            end
            if ~any(idx_fcn)
                disp([msg ' not found in the function list!']);
                idx_fcn = [];
            end
        end
        function fcnStr = createFcnString(obj, task)
            % This method creates a string containing the function to be
            % called during the current task of the pipeline by an EVAL
            % statement. This method is called from "run_taskOnTarget"
            % method.
            % !! If new input or output arguments are created, meaning new
            % argument keywords, this function has to be updated in order the
            % function string to work.
            
            % Input:
            %   task (struct): info of current function to be run on the
            %       current object.
            % Output:
            %   fcnStr (char): string containing call to analysis function
            %   in the current task.
            
            disp('Creating Function String...')
            fcnStr = '';
            
            % Step 1: add string to load input file:
            % Here, we assume that all input files are stored in the Save
            % folder of the target object.
            if ~isempty(task.inputFileName)
                fcnStr = ['load(' fullfile(obj.tmp_TargetObj.SaveFolder, task.inputFileName) ');'];
            end
            
            % Step 2: create analysis function string:
            % Replace input argument names:
            argsIn = replace(task.argsIn, {'RawFolder', 'SaveFolder', 'data','metaData', 'object', 'dataStat'},...
                {['''' obj.tmp_TargetObj.RawFolder ''''],['''' obj.tmp_TargetObj.SaveFolder ''''], 'obj.current_data',...
                'obj.current_metaData', 'obj.tmp_TargetObj', 'obj.current_data'});
            argsOut = replace(task.argsOut, {'outData', 'metaData', 'outDataStat', 'outFile'},...
                {'obj.current_data', 'obj.current_metaData', 'obj.current_data', 'obj.current_outFile'});
            fcnStr = [fcnStr ';' '[' strjoin(argsOut, ',') ']=' task.name '(' strjoin(argsIn,',') ');'];
        end
        
        function updateDataHistory(obj, step)
            % This function creates or  updates the "dataHistory" structure
            % and saves the information to the metaData structure/matfile.
            % The dataHistory contains all information about the functions'
            % parameters used to create the current "data" and when it was run.
            %
            % Input:
            %    step(struct) : current step of the pipeline;
            
            disp('Building Data History...')
            funcInfo = obj.funcList(strcmp(step.name, {obj.funcList.name}));
            % Create a local structure with the function's info:
            curr_dtHist = struct('runDatetime', datetime('now'), 'name', {funcInfo.name},...
                'folder', {funcInfo.folder}, 'creationDatetime', datetime(funcInfo.date),...
                'opts', step.opts, 'funcStr', {step.funcStr}, 'outputFile_list', 'none');
            % First, we need to know if the output is a "data", a .DAT file or a .MAT file:
            if any(strcmp(step.argsOut, 'outFile'))
                % In case the step ouput is .DAT file(s):
                
                % Get only filename instead of full path:
                [~, filenames, ext] = cellfun(@(x) fileparts(x), obj.current_outFile,...
                    'UniformOutput', false);
                curr_dtHist.outputFile_list = join([filenames',ext'],'');
                
                for i = 1:length(obj.current_outFile)
                    % Map existing metaData file to memory:
                    mtD = matfile(strrep(obj.current_outFile{i}, '.dat', '.mat'));
                    mtD.Properties.Writable = true;
                    % Create or update "dataHistory" structure:
                    if isprop(mtD, 'dataHistory')
                        mtD.dataHistory = [mtD.dataHistory; curr_dtHist];
                    else
                        mtD.dataHistory = curr_dtHist;
                    end
                end
            elseif any(strcmp(step.argsOut, 'outDataStat'))
                % In case of step output is .MAT file(s):
                disp('SAVING .MAT FILE>>>')
                
            else
                % In case of step output is a data array:
                if isfield(obj.metaData, 'dataHistory')
                    obj.metaData.dataHistory = [obj.metaData.dataHistory; curr_dtHist];
                else
                    obj.metaData.dataHistory = curr_dtHist;
                end
            end
        end
        
        function b_skip = checkDataHistory(obj,step)
            % This method verifies if the function to be run in "step" was
            % already performed or not on the current data.
            % If so, the pipeline step will be skipped.
            % Input:
            %   step (struct): structure containing the function information that
            %   will run on the data.
            % Output:
            %   b_skip (bool): True if the step was already run on the
            %   data and should be skipped.
            
            disp('Checking step...');
            b_skip = false;
            % Find function info in Function List:
            fcnInfo = obj.funcList(strcmp(step.name, {obj.funcList.name}));
            % Find step info in object's dataHistory:
            
            % For retro-compatibility with data created in previous
            % versions of umIT:
            if ~isfield(obj.current_metaData, 'dataHistory')
                return
            end
            
            dH = obj.metaData.dataHistory(strcmp(step.name, {obj.metaData.dataHistory.name}));
            % If the function's creation date AND the function string AND optional parameters are
            % the same, we consider that the current step was already run.
            if isempty(dH)
                return
            elseif ( isequal(datetime(fcnInfo.date), dH.creationDatetime) &&...
                    strcmp(step.funcStr, dH.funcStr) ) && isequaln(step.opts, dH.opts)
                b_skip = true;
            end
        end
        
        
        function saveDataToFile(obj, step)
            % This methods manages data saving to .DAT and .MAT files.
            % Input:
            %    step(struct) : info of the current task in the pipeline.
            
            
            disp('Saving File...');
            
            
            
            
            
            
        end
        
    end
end

