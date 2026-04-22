classdef EquipmentDatabase < handle
    % EquipmentDatabase 设备数据库管理类
    % 结合物料数据库进行配方校验，注册和管理所有设备原型
    
    properties
        Equipments % 存储字典：Key为ID，Value为StandardEquipment对象
        MatDB      % 关联的 MaterialDatabase 实例
    end
    
    methods
        function obj = EquipmentDatabase(matDB)
            % 构造函数
            obj.Equipments = dictionary();
            obj.MatDB = matDB;
        end
        
        function loadFromJSON(obj, filepath)
            % 从JSON文件加载设备定义
            txt = fileread(filepath);
            data = jsondecode(txt);
            for i = 1:length(data)
                if iscell(data)
                    item = data{i};
                else
                    item = data(i);
                end
                
                equip = StandardEquipment(item.ID, item.BaseSize);
                
                % 添加端口
                if isfield(item, 'SolidInputs') && ~isempty(item.SolidInputs)
                    ports = item.SolidInputs;
                    if iscell(ports), ports = cell2mat(ports); end
                    for p = 1:length(ports)
                        equip.addPort('SolidInput', ports(p).PortID, ports(p).Pos);
                    end
                end
                if isfield(item, 'SolidOutputs') && ~isempty(item.SolidOutputs)
                    ports = item.SolidOutputs;
                    if iscell(ports), ports = cell2mat(ports); end
                    for p = 1:length(ports)
                        equip.addPort('SolidOutput', ports(p).PortID, ports(p).Pos);
                    end
                end
                if isfield(item, 'LiquidInputs') && ~isempty(item.LiquidInputs)
                    ports = item.LiquidInputs;
                    if iscell(ports), ports = cell2mat(ports); end
                    for p = 1:length(ports)
                        equip.addPort('LiquidInput', ports(p).PortID, ports(p).Pos);
                    end
                end
                if isfield(item, 'LiquidOutputs') && ~isempty(item.LiquidOutputs)
                    ports = item.LiquidOutputs;
                    if iscell(ports), ports = cell2mat(ports); end
                    for p = 1:length(ports)
                        equip.addPort('LiquidOutput', ports(p).PortID, ports(p).Pos);
                    end
                end
                
                % 添加配方
                if isfield(item, 'Recipes') && ~isempty(item.Recipes)
                    recs = item.Recipes;
                    if iscell(recs), recs = cell2mat(recs); end
                    for r = 1:length(recs)
                        rec = recs(r);
                        inps = []; outs = [];
                        if isfield(rec, 'Inputs') && ~isempty(rec.Inputs)
                            inps = rec.Inputs;
                            if iscell(inps), inps = cell2mat(inps); end
                        end
                        if isfield(rec, 'Outputs') && ~isempty(rec.Outputs)
                            outs = rec.Outputs;
                            if iscell(outs), outs = cell2mat(outs); end
                        end
                        equip.addRecipe(rec.RecipeID, rec.Time, inps, outs);
                    end
                end
                
                % 处理供电属性
                if isfield(item, 'NeedsPower')
                    equip.NeedsPower = item.NeedsPower;
                end
                if isfield(item, 'PowerRange')
                    % 转换为空或数组
                    if isempty(item.PowerRange)
                        equip.PowerRange = [];
                    else
                        equip.PowerRange = item.PowerRange;
                    end
                end
                
                % 注册
                obj.registerEquipment(equip);
            end
        end
        
        function registerEquipment(obj, equip)
            % 注册一个设备对象并进行配方校验
            % 校验配方中的物料是否在MatDB中注册
            for i = 1:length(equip.Recipes)
                recipe = equip.Recipes(i);
                
                % 校验Inputs
                for j = 1:length(recipe.Inputs)
                    matID = recipe.Inputs(j).MaterialID;
                    try
                        obj.MatDB.getMaterial(matID);
                    catch
                        error('Equipment "%s" uses unregistered input material "%s" in recipe "%s".', ...
                            equip.ID, matID, recipe.RecipeID);
                    end
                end
                
                % 校验Outputs
                for j = 1:length(recipe.Outputs)
                    matID = recipe.Outputs(j).MaterialID;
                    try
                        obj.MatDB.getMaterial(matID);
                    catch
                        error('Equipment "%s" produces unregistered output material "%s" in recipe "%s".', ...
                            equip.ID, matID, recipe.RecipeID);
                    end
                end
            end
            
            % 注册
            if obj.Equipments.numEntries > 0 && obj.Equipments.isKey(equip.ID)
                warning('Equipment with ID "%s" already exists. Overwriting.', equip.ID);
            end
            obj.Equipments(equip.ID) = equip;
        end
        
        function equip = getEquipment(obj, id)
            % 通过ID获取设备对象的深拷贝（用于放置多个实例）
            if obj.Equipments.numEntries > 0 && obj.Equipments.isKey(id)
                % 创建一个新的实例
                baseEquip = obj.Equipments(id);
                equip = StandardEquipment(baseEquip.ID, baseEquip.BaseSize);
                equip.BaseSolidInputs = baseEquip.BaseSolidInputs;
                equip.BaseSolidOutputs = baseEquip.BaseSolidOutputs;
                equip.BaseLiquidInputs = baseEquip.BaseLiquidInputs;
                equip.BaseLiquidOutputs = baseEquip.BaseLiquidOutputs;
                equip.Recipes = baseEquip.Recipes;
                equip.NeedsPower = baseEquip.NeedsPower;
                equip.PowerRange = baseEquip.PowerRange;
            else
                error('Equipment with ID "%s" not found in the database.', id);
            end
        end
        
        function disp(obj)
            keys = obj.Equipments.keys();
            fprintf('--- Equipment Database (%d items) ---\n', length(keys));
            for i = 1:length(keys)
                eq = obj.Equipments(keys(i));
                fprintf('ID: %-15s | BaseSize: [%d, %d] | Recipes count: %d\n', ...
                    eq.ID, eq.BaseSize(1), eq.BaseSize(2), length(eq.Recipes));
            end
            fprintf('-------------------------------------\n');
        end
    end
end
