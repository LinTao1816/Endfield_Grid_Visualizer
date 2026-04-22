classdef MaterialDatabase < handle
    % MaterialDatabase 物料数据库管理类
    % 用于注册、存储和查询系统中所有的物料
    
    properties
        Materials % 存储字典：Key为ID，Value为Material对象
    end
    
    methods
        function obj = MaterialDatabase()
            % 构造函数：初始化字典
            obj.Materials = dictionary();
        end
        
        function loadFromJSON(obj, filepath)
            % 从JSON文件加载物料定义
            txt = fileread(filepath);
            data = jsondecode(txt);
            for i = 1:length(data)
                % data 可能是结构体数组，或者是cell数组，根据 MATLAB jsondecode 规则
                if iscell(data)
                    item = data{i};
                else
                    item = data(i);
                end
                obj.registerMaterial(item.ID, item.Name, item.State);
            end
        end
        
        function registerMaterial(obj, id, name, state)
            % 注册一个新物料
            if obj.Materials.numEntries > 0 && obj.Materials.isKey(id)
                warning('Material with ID "%s" already exists. Overwriting.', id);
            end
            mat = Material(id, name, state);
            obj.Materials(id) = mat;
        end
        
        function mat = getMaterial(obj, id)
            % 通过ID获取物料对象
            if obj.Materials.numEntries > 0 && obj.Materials.isKey(id)
                mat = obj.Materials(id);
            else
                error('Material with ID "%s" not found in the database.', id);
            end
        end
        
        function disp(obj)
            % 打印所有已注册物料
            keys = obj.Materials.keys();
            fprintf('--- Material Database (%d items) ---\n', length(keys));
            for i = 1:length(keys)
                mat = obj.Materials(keys(i));
                fprintf('ID: %-15s | Name: %-15s | State: %s\n', mat.ID, mat.Name, mat.State);
            end
            fprintf('------------------------------------\n');
        end
    end
end
