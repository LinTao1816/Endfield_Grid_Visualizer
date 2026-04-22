classdef StandardEquipment < handle
    % StandardEquipment 标准生产设备模型
    % 包含设备的尺寸、端口配置及支持的配方
    
    properties
        ID              % 设备类型ID或名称
        BaseSize        % 初始占地面积 [a, b]，表示宽(列数)和长(行数)
        Rotation        % 旋转角度: 0, 90, 180, 270
        
        % 端口定义，结构体数组，格式: struct('PortID', id, 'Pos', [x,y])
        % Pos 为基于 BaseSize 的相对坐标(1-based)，例如 [1, 1] 为左上角
        BaseSolidInputs
        BaseSolidOutputs
        BaseLiquidInputs
        BaseLiquidOutputs
        
        Recipes         % 配方列表，结构体数组
        % 配方格式: struct('RecipeID', id, 'Time', t, 
        %                 'Inputs', struct('MaterialID', id, 'Quantity', qty),
        %                 'Outputs', struct('MaterialID', id, 'Quantity', qty))
        
        NeedsPower      % 布尔值，是否需要供电才能运作
        PowerRange      % 供电范围 [width, height]，为空表示不是供电设备
        
        ActiveRecipe      % 当前正在运行的配方ID（字符串），为空表示未加工
        PortFlows         % 字典，记录各端口当前的物流状态：Key为PortID，Value为 struct('MaterialID', id, 'Rate', rate)
        OutputPortMapping % 字典，记录自定义的产物输出规则：Key为MaterialID，Value为指定的输出PortID
    end
    
    properties (Dependent)
        % 考虑旋转后的实际尺寸和端口位置
        Size            
        SolidInputs
        SolidOutputs
        LiquidInputs
        LiquidOutputs
    end
    
    methods
        function obj = StandardEquipment(id, baseSize)
            % 构造函数
            obj.ID = id;
            obj.BaseSize = baseSize;
            obj.Rotation = 0;
            
            obj.BaseSolidInputs = [];
            obj.BaseSolidOutputs = [];
            obj.BaseLiquidInputs = [];
            obj.BaseLiquidOutputs = [];
            obj.Recipes = [];
            
            obj.NeedsPower = false; % 默认不消耗电
            obj.PowerRange = [];    % 默认不供电
            
            obj.ActiveRecipe = '';
            obj.PortFlows = dictionary();
            obj.OutputPortMapping = dictionary();
        end
        
        function setRotation(obj, angle)
            % 设置旋转角度 (0, 90, 180, 270)
            if ~ismember(angle, [0, 90, 180, 270])
                error('Rotation angle must be 0, 90, 180, or 270 degrees.');
            end
            obj.Rotation = angle;
        end
        
        function s = get.Size(obj)
            if obj.Rotation == 90 || obj.Rotation == 270
                s = [obj.BaseSize(2), obj.BaseSize(1)];
            else
                s = obj.BaseSize;
            end
        end
        
        function ports = get.SolidInputs(obj)
            ports = rotatePorts(obj, obj.BaseSolidInputs);
        end
        function ports = get.SolidOutputs(obj)
            ports = rotatePorts(obj, obj.BaseSolidOutputs);
        end
        function ports = get.LiquidInputs(obj)
            ports = rotatePorts(obj, obj.BaseLiquidInputs);
        end
        function ports = get.LiquidOutputs(obj)
            ports = rotatePorts(obj, obj.BaseLiquidOutputs);
        end
        
        function addPort(obj, type, portID, pos)
            % 添加端口
            % type: 'SolidInput', 'SolidOutput', 'LiquidInput', 'LiquidOutput'
            p = struct('PortID', portID, 'Pos', pos);
            switch type
                case 'SolidInput'
                    obj.BaseSolidInputs = [obj.BaseSolidInputs, p];
                case 'SolidOutput'
                    obj.BaseSolidOutputs = [obj.BaseSolidOutputs, p];
                case 'LiquidInput'
                    obj.BaseLiquidInputs = [obj.BaseLiquidInputs, p];
                case 'LiquidOutput'
                    obj.BaseLiquidOutputs = [obj.BaseLiquidOutputs, p];
                otherwise
                    error('Unknown port type.');
            end
        end
        
        function addRecipe(obj, recipeID, time, inputs, outputs)
            % 添加配方
            % inputs / outputs: struct array, format: struct('MaterialID', ..., 'Quantity', ...)
            r = struct('RecipeID', recipeID, 'Time', time, 'Inputs', inputs, 'Outputs', outputs);
            obj.Recipes = [obj.Recipes, r];
        end
        
        function updateRecipe(obj, matDB)
            % 根据当前的输入流，推导运行的配方及产生的输出流
            
            % 1. 汇总所有输入物料的速率
            inMaterials = dictionary(); % Key: MaterialID, Value: Total Rate
            allInPorts = [obj.SolidInputs, obj.LiquidInputs];
            if isempty(allInPorts), return; end
            
            for i = 1:length(allInPorts)
                pID = allInPorts(i).PortID;
                if obj.PortFlows.numEntries > 0 && obj.PortFlows.isKey(pID)
                    flow = obj.PortFlows(pID);
                    if ~isempty(flow.MaterialID) && flow.Rate > 0
                        % 使用 string 以避免 char 数组作为 dictionary 键带来的问题
                        mID = string(flow.MaterialID);
                        if inMaterials.numEntries > 0 && inMaterials.isKey(mID)
                            inMaterials(mID) = inMaterials(mID) + flow.Rate;
                        else
                            inMaterials(mID) = flow.Rate;
                        end
                    end
                end
            end
            
            % 2. 匹配配方
            bestRecipe = [];
            maxScale = 0;
            
            if inMaterials.numEntries > 0
                for i = 1:length(obj.Recipes)
                    rec = obj.Recipes(i);
                    match = true;
                    scale = inf;
                    
                    if isempty(rec.Inputs)
                        match = false;
                        continue;
                    end
                    
                    % 检查配方的所有输入是否都满足
                    for j = 1:length(rec.Inputs)
                        reqMat = string(rec.Inputs(j).MaterialID);
                        reqRate = rec.Inputs(j).Quantity / rec.Time;
                        
                        if inMaterials.numEntries == 0 || ~inMaterials.isKey(reqMat)
                            match = false;
                            break;
                        else
                            actRate = inMaterials(reqMat);
                            scale = min(scale, actRate / reqRate);
                        end
                    end
                    
                    if match && scale > 0
                        % 找到可用配方，选规模最大的（或第一个匹配的）
                        if isempty(bestRecipe) || scale > maxScale
                            bestRecipe = rec;
                            maxScale = scale;
                        end
                    end
                end
            end
            
            % 清理旧的输出流
            allOutPorts = [obj.SolidOutputs, obj.LiquidOutputs];
            for i = 1:length(allOutPorts)
                pID = allOutPorts(i).PortID;
                if obj.PortFlows.numEntries > 0 && obj.PortFlows.isKey(pID)
                    obj.PortFlows(pID) = struct('MaterialID', '', 'Rate', 0);
                end
            end
            
            % 3. 应用配方生成输出
            if ~isempty(bestRecipe)
                obj.ActiveRecipe = bestRecipe.RecipeID;
                
                % 记录哪些端口已被使用，避免冲突
                usedPorts = dictionary();
                
                for j = 1:length(bestRecipe.Outputs)
                    outMat = bestRecipe.Outputs(j).MaterialID;
                    outRate = maxScale * (bestRecipe.Outputs(j).Quantity / bestRecipe.Time);
                    
                    targetPort = '';
                    outMatStr = string(outMat);
                    % a. 检查自定义路由 OutputPortMapping
                    if obj.OutputPortMapping.numEntries > 0 && obj.OutputPortMapping.isKey(outMatStr)
                        targetPort = string(obj.OutputPortMapping(outMatStr));
                    else
                        % b. 自动分配
                        matDef = matDB.getMaterial(outMat);
                        if strcmp(matDef.State, 'Solid')
                            cands = obj.SolidOutputs;
                        else
                            cands = obj.LiquidOutputs;
                        end
                        
                        for k = 1:length(cands)
                            pID = cands(k).PortID;
                            if usedPorts.numEntries == 0 || ~usedPorts.isKey(pID)
                                targetPort = pID;
                                break;
                            end
                        end
                    end
                    
                    if ~isempty(targetPort)
                        obj.PortFlows(targetPort) = struct('MaterialID', outMat, 'Rate', outRate);
                        usedPorts(targetPort) = true;
                    else
                        warning('Equipment %s has no available output port for material %s', obj.ID, outMat);
                    end
                end
            else
                obj.ActiveRecipe = '';
            end
        end
    end
    
    methods (Access = private)
        function newPorts = rotatePorts(obj, basePorts)
            % 内部辅助方法：根据当前旋转角度和BaseSize计算新的相对坐标
            % 假设坐标是(x,y)，1-based
            % BaseSize = [width, height]
            newPorts = basePorts;
            if isempty(basePorts)
                return;
            end
            
            w = obj.BaseSize(1);
            h = obj.BaseSize(2);
            
            for i = 1:length(basePorts)
                x = basePorts(i).Pos(1);
                y = basePorts(i).Pos(2);
                
                switch obj.Rotation
                    case 0
                        nx = x; ny = y;
                    case 90
                        % 顺时针旋转90度
                        nx = h - y + 1;
                        ny = x;
                    case 180
                        nx = w - x + 1;
                        ny = h - y + 1;
                    case 270
                        nx = y;
                        ny = w - x + 1;
                end
                newPorts(i).Pos = [nx, ny];
            end
        end
    end
end
