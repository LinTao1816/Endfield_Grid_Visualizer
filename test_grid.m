% test_grid.m
% 测试MapGrid类的纯JSON驱动及可视化

clear; clc;

% 1. 建立 20x15 网格
gridMap = MapGrid(20, 15);

% 2. 从 JSON 加载数据库
disp('=== 加载 JSON 数据库 ===');
matDB = MaterialDatabase();
matDB.loadFromJSON('data/materials.json');

equipDB = EquipmentDatabase(matDB);
equipDB.loadFromJSON('data/equipments.json');

% 3. 在网格上放置设备
disp('放置 协议核心 和 粉碎机...');
core = equipDB.getEquipment('协议核心');
crusher = equipDB.getEquipment('粉碎机');

% 放置协议核心于 (2,2)，占据 [2~10, 2~10]
gridMap.placeEquipment(core, 2, 2, 0);
% 放置粉碎机于 (15,5)，占据 [15~17, 5~7]
gridMap.placeEquipment(crusher, 15, 5, 0);

% 4. 放置物流管线构建闭环
disp('构建 协议核心 -> 粉碎机 -> 协议核心 闭环...');

% --- 去程：协议核心 到 粉碎机 ---
% 协议核心的 SO_R1 在相对 [9, 2]，全局 [10, 3]
% 传出方向向右
for x = 11:15
    gridMap.addSolidNode(x, 3, '传送带', '→');
end
% 在 (16, 3) 拐弯向下
gridMap.addSolidNode(16, 3, '传送带', '↓');
% 粉碎机的 SI 在相对 [2, 1]，全局 [16, 5]
% 所以带子到 (16, 4) 即可进入设备
gridMap.addSolidNode(16, 4, '传送带', '↓');

% --- 回程：粉碎机 到 协议核心 ---
% 粉碎机的 SO 在相对 [2, 3]，全局 [16, 7]
% 传出方向向下
gridMap.addSolidNode(16, 8, '传送带', '↓');
gridMap.addSolidNode(16, 9, '传送带', '↓');
gridMap.addSolidNode(16, 10, '传送带', '↓');
gridMap.addSolidNode(16, 11, '传送带', '↓');
% 在 (16, 12) 拐弯向左
gridMap.addSolidNode(16, 12, '传送带', '←');
for x = 15:-1:9
    gridMap.addSolidNode(x, 12, '传送带', '←');
end
% 协议核心的 SI_B7 在相对 [8, 9]，全局 [9, 10]
% 在 (8, 12) 拐弯向上
gridMap.addSolidNode(8, 12, '传送带', '↑');
% 带子到 (8, 11) 进入协议核心底部输入口
gridMap.addSolidNode(8, 11, '传送带', '↑');

% 5. 物流流转动态推导测试
disp(' ');
disp('=== 启动物流流转推导测试 ===');

% 模拟求解器给出初始决策变量：协议核心的 SO_R1 输出 赤铜块，速率 0.5
core.PortFlows('SO_R1') = struct('MaterialID', 'item-copper-nugget', 'Rate', 0.5);
fprintf('【设定】协议核心端口 SO_R1 输出: %s, 速率: %.1f\n', ...
    core.PortFlows('SO_R1').MaterialID, core.PortFlows('SO_R1').Rate);

% 模拟传送带运输到达粉碎机 (输入口 PortID: in1)
crusher.PortFlows('in1') = core.PortFlows('SO_R1');
fprintf('【传输】传送带将物料送达粉碎机端口 in1: %s, 速率: %.1f\n', ...
    crusher.PortFlows('in1').MaterialID, crusher.PortFlows('in1').Rate);

% 激发粉碎机内部处理引擎
disp('【处理】粉碎机开始解析配方并自推导输出...');
crusher.updateRecipe(matDB);

% 打印粉碎机状态
fprintf('粉碎机当前激活配方: %s\n', crusher.ActiveRecipe);
if crusher.PortFlows.numEntries > 0 && crusher.PortFlows.isKey('out1')
    outFlow = crusher.PortFlows('out1');
    fprintf('粉碎机自推导产物从 out1 输出: %s, 速率: %.1f\n', outFlow.MaterialID, outFlow.Rate);
    
    % 模拟回流至协议核心 (底部输入口 PortID: SI_B7)
    core.PortFlows('SI_B7') = outFlow;
    fprintf('【回流】传送带将产物送达协议核心端口 SI_B7: %s, 速率: %.1f\n', ...
        core.PortFlows('SI_B7').MaterialID, core.PortFlows('SI_B7').Rate);
else
    disp('错误：粉碎机未能生成预期输出！');
end
disp(' ');

% 6. 渲染可视化图并保存
disp('生成可视化图并保存为 layout_visual.png ...');
gridMap.visualize();
saveas(gcf, 'layout_visual.png');
disp('测试完成！');
