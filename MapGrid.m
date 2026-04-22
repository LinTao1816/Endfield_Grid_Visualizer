classdef MapGrid < handle
    % MapGrid 产线多层网格类
    % 包含设备层、固体物流层和液体物流层，并支持布局结果可视化
    
    properties
        Width       % 网格列数 (X轴最大值)
        Height      % 网格行数 (Y轴最大值)
        
        Equipments  % 已放置的设备列表, struct('Instance', obj, 'X', x, 'Y', y)
        
        FacilityGrid % W x H 矩阵，记录是否被设备占用 (0表示未占用，1表示占用)
        SolidGrid    % W x H cell矩阵，记录固体节点结构体
        LiquidGrid   % W x H cell矩阵，记录液体节点结构体
        PowerGrid    % W x H 矩阵，记录供电覆盖度 (值 > 0 表示有供电覆盖)
    end
    
    methods
        function obj = MapGrid(width, height)
            obj.Width = width;
            obj.Height = height;
            obj.Equipments = [];
            
            obj.FacilityGrid = zeros(width, height);
            obj.SolidGrid = cell(width, height);
            obj.LiquidGrid = cell(width, height);
            obj.PowerGrid = zeros(width, height);
        end
        
        function success = placeEquipment(obj, equip, x, y, rotation)
            % 放置设备 (x, y) 为左上角坐标，1-based
            equip.setRotation(rotation);
            w = equip.Size(1);
            h = equip.Size(2);
            
            % 1. 越界检查
            if x < 1 || y < 1 || (x + w - 1) > obj.Width || (y + h - 1) > obj.Height
                error('Equipment %s placed out of bounds at [%d, %d].', equip.ID, x, y);
            end
            
            % 2. 重叠检查
            if any(any(obj.FacilityGrid(x : x+w-1, y : y+h-1)))
                error('Equipment %s overlaps with existing facilities at [%d, %d].', equip.ID, x, y);
            end
            
            % 3. 执行放置
            obj.FacilityGrid(x : x+w-1, y : y+h-1) = 1;
            item = struct('Instance', equip, 'X', x, 'Y', y);
            obj.Equipments = [obj.Equipments, item];
            
            % 4. 扩展供电范围 (如果是供电设备)
            if ~isempty(equip.PowerRange)
                pw = equip.PowerRange(1);
                ph = equip.PowerRange(2);
                % 计算中心点坐标 (中心点不一定在网格交叉点，我们以左上和右下的中心进行外扩)
                % 供电桩的占用矩形中心：
                cx = x + (w - 1) / 2;
                cy = y + (h - 1) / 2;
                % 辐射范围左上角和右下角：
                px1 = max(1, floor(cx - pw/2 + 0.5));
                py1 = max(1, floor(cy - ph/2 + 0.5));
                px2 = min(obj.Width, floor(cx + pw/2 + 0.5));
                py2 = min(obj.Height, floor(cy + ph/2 + 0.5));
                
                % 覆盖度增加
                obj.PowerGrid(px1:px2, py1:py2) = obj.PowerGrid(px1:px2, py1:py2) + 1;
            end
            
            success = true;
        end
        
        function success = addSolidNode(obj, x, y, type, dirName)
            % 添加固体物流节点
            % type: '传送带', 'S分流器', 'S汇流器', 'S桥'
            % dirName: 方向指示或缩写
            
            if x < 1 || y < 1 || x > obj.Width || y > obj.Height
                error('Solid node out of bounds.');
            end
            if obj.FacilityGrid(x, y) == 1
                error('Cannot place solid node on facility at [%d, %d].', x, y);
            end
            
            % 液体层排斥性校验：如果该点有液体特殊节点，则不能放传送带
            liq = obj.LiquidGrid{x, y};
            if ~isempty(liq) && ~strcmp(liq.Type, '水管')
                error('Cannot place solid node at [%d, %d] due to existing liquid special node.', x, y);
            end
            
            obj.SolidGrid{x, y} = struct('Type', type, 'Dir', dirName, 'MaterialID', '');
            success = true;
        end
        
        function success = addLiquidNode(obj, x, y, type, dirName)
            % 添加液体物流节点
            % type: '水管', 'L分流器', 'L汇流器', 'L桥'
            
            if x < 1 || y < 1 || x > obj.Width || y > obj.Height
                error('Liquid node out of bounds.');
            end
            if obj.FacilityGrid(x, y) == 1
                error('Cannot place liquid node on facility at [%d, %d].', x, y);
            end
            
            % 如果当前要放置的是液体特殊节点，且固体层被占用，则拒绝
            if ~strcmp(type, '水管') && ~isempty(obj.SolidGrid{x, y})
                error('Cannot place liquid special node at [%d, %d] due to existing solid node.', x, y);
            end
            
            obj.LiquidGrid{x, y} = struct('Type', type, 'Dir', dirName, 'MaterialID', '');
            success = true;
        end
        
        function visualize(obj)
            % 可视化整个网格
            figure('Name', 'Line Layout Optimization', 'Color', 'w', 'Position', [100, 100, 800, 800]);
            hold on; axis equal;
            axis([0, obj.Width, 0, obj.Height]);
            set(gca, 'XTick', 0:obj.Width, 'YTick', 0:obj.Height, 'GridColor', [0.8 0.8 0.8]);
            grid on;
            
            % 由于 MATLAB plot 坐标轴默认左下角为(0,0)，我们为了和矩阵 (x,y) 对应，将坐标反转Y轴
            set(gca, 'YDir', 'reverse');
            
            % 1. 绘制网格上的物流节点 (Solid & Liquid) - 全格填色
            for x = 1:obj.Width
                for y = 1:obj.Height
                    sol = obj.SolidGrid{x, y};
                    liq = obj.LiquidGrid{x, y};
                    
                    if isempty(sol) && isempty(liq)
                        continue;
                    end
                    
                    % 决定填充颜色
                    if ~isempty(sol) && isempty(liq)
                        % 仅固体：淡橙色
                        bgColor = [1, 0.9, 0.8];
                    elseif isempty(sol) && ~isempty(liq)
                        % 仅液体：淡蓝色
                        bgColor = [0.8, 0.9, 1];
                    else
                        % 都有：淡绿色
                        bgColor = [0.8, 1, 0.8];
                    end
                    
                    % 绘制填色网格背景
                    rectangle('Position', [x-1, y-1, 1, 1], 'FaceColor', bgColor, 'EdgeColor', [0.8 0.8 0.8]);
                    
                    % 叠加文字标识
                    if ~isempty(sol) && isempty(liq)
                        % 仅固体
                        txt = sol.Type;
                        if strcmp(txt, '传送带')
                            txt = sol.Dir;
                        end
                        text(x-0.5, y-0.5, txt, 'Color', [0.85 0.33 0.1], 'FontSize', 8, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
                    elseif isempty(sol) && ~isempty(liq)
                        % 仅液体
                        txt = liq.Type;
                        if strcmp(txt, '水管')
                            txt = liq.Dir;
                        end
                        text(x-0.5, y-0.5, txt, 'Color', [0 0.45 0.74], 'FontSize', 8, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
                    else
                        % 两者共存，上下分别写
                        txtSol = sol.Type;
                        if strcmp(txtSol, '传送带'), txtSol = sol.Dir; end
                        text(x-0.5, y-0.7, txtSol, 'Color', [0.85 0.33 0.1], 'FontSize', 7, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
                        
                        txtLiq = liq.Type;
                        if strcmp(txtLiq, '水管'), txtLiq = liq.Dir; end
                        text(x-0.5, y-0.3, txtLiq, 'Color', [0 0.45 0.74], 'FontSize', 7, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
                    end
                end
            end
            
            % 2. 绘制设备
            for i = 1:length(obj.Equipments)
                item = obj.Equipments(i);
                eq = item.Instance;
                ex = item.X; ey = item.Y;
                ew = eq.Size(1); eh = eq.Size(2);
                
                % 画矩形 (MATLAB rectangle 坐标为 [x, y, w, h]，由于Y反转，左上角点其实是(x-1, y-1))
                rectangle('Position', [ex-1, ey-1, ew, eh], 'FaceColor', [0.8 0.9 1], 'EdgeColor', [0.2 0.4 0.8], 'LineWidth', 2);
                
                % 写设备名称
                text(ex - 1 + ew/2, ey - 1 + eh/2, eq.ID, 'FontSize', 10, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
                
                % 绘制端口
                obj.drawPorts(eq.SolidInputs, ex, ey, 'SI', [0.85 0.33 0.1]);
                obj.drawPorts(eq.SolidOutputs, ex, ey, 'SO', [0.85 0.33 0.1]);
                obj.drawPorts(eq.LiquidInputs, ex, ey, 'LI', [0 0.45 0.74]);
                obj.drawPorts(eq.LiquidOutputs, ex, ey, 'LO', [0 0.45 0.74]);
            end
            
            title('Production Line Layout');
            hold off;
        end
        
    end
    
    methods (Access = private)
        function drawPorts(obj, ports, baseX, baseY, label, color)
            for j = 1:length(ports)
                px = baseX + ports(j).Pos(1) - 1;
                py = baseY + ports(j).Pos(2) - 1;
                % 在网格中央偏上/下的位置打个标记
                cx = px - 0.5;
                cy = py - 0.5;
                
                % 画一个小方块作为端口并使用同色斜线阴影
                psize = 0.4;
                rectangle('Position', [cx-psize/2, cy-psize/2, psize, psize], 'FaceColor', 'w', 'EdgeColor', color);
                for d = -psize/4 : psize/4 : psize/4
                    xs = max(-psize/2, -psize/2-d);
                    xe = min(psize/2, psize/2-d);
                    ys = xs + d;
                    ye = xe + d;
                    plot([cx+xs, cx+xe], [cy+ys, cy+ye], 'Color', color, 'LineWidth', 1.5);
                end
                text(cx, cy, label, 'FontSize', 6, 'Color', 'k', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
            end
        end
    end
end
