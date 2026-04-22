classdef Material
    % Material 物料类定义
    % 包含物料的基本信息，用于配方和端口校验
    
    properties
        ID      % 物料的唯一标识 (String/Char)
        Name    % 物料显示名称 (String/Char)
        State   % 物料状态: 'Solid' (固体) 或 'Liquid' (液体)
    end
    
    methods
        function obj = Material(id, name, state)
            % Material 构造函数
            if nargin > 0
                obj.ID = id;
                obj.Name = name;
                if ~ismember(state, {'Solid', 'Liquid'})
                    error('Material state must be ''Solid'' or ''Liquid''.');
                end
                obj.State = state;
            end
        end
    end
end
