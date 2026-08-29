// fe_registry.vh — 模块注册表（fe_atom 与 fe_ability_base 共用，单一事实来源）
// 能力子集：5 Ability + 2 Data，与 MCU 版同名同命令。

// Ability 名称（右对齐 256 位，可直接与字符串字面量比较）
localparam [255:0] T_BASE_ABILITY = "ability_BaseAbility";
localparam [255:0] T_ROLE         = "ability_RoleAbility";
localparam [255:0] T_TIME         = "ability_TimeAbility";
localparam [255:0] T_ONEKEY       = "ability_OneKeyAbility";
localparam [255:0] T_MODBUS       = "ability_ModbusAbility";
// Data 名称
localparam [255:0] T_BASE_DATA    = "data_BaseData";
localparam [255:0] T_CONFIG       = "data_ConfigData";

// 名称列表（供 list_ability_names / list_data_names / help 使用）
// 注意：修改上方注册表时同步修改这两行
localparam integer LIST_AB_LEN = 63;
localparam [8*61-1:0] LIST_ABILITIES =
    "BaseAbility,RoleAbility,TimeAbility,OneKeyAbility,ModbusAbility";
localparam integer LIST_DATA_LEN = 19;
localparam [8*19-1:0] LIST_DATAS = "BaseData,ConfigData";

// 从右对齐字符串常量取第 idx 个字符（0 起）
function [7:0] cbyte(input [1023:0] s, input integer len, input integer idx);
    cbyte = s[(len-1-idx)*8 +: 8];
endfunction
