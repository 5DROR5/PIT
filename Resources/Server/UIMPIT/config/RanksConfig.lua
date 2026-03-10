-- =============================================================================
-- RanksConfig.lua
-- Rank progression system — all ranks, tasks, and reward definitions.
-- Edit this file to add ranks, adjust targets, or change rewards.
-- License: AGPL-3.0 — https://www.gnu.org/licenses/agpl-3.0.html
-- =============================================================================

return {
    -- Minimum vehicle speed (km/h) required for chase-time progress to count.
    min_speed_for_progress = 30,

    -- Base display points awarded per unit of each task action.
    -- chase_time is awarded per 10 seconds of qualifying chase.
    task_points = {
        bust             = 50,
        chase_time       = 5,
        escape           = 50,
        zigzag_pressure  = 30,
        combo_escape     = 100,
        marker_capture   = 10,
        marker_chase     = 75,
    },

    [1] = {
        name_key = "rank_1_name",
        prefix   = "[RK]",
        reward   = 5000,
        tasks = {
            -- Police tasks
            { id = "cop_arrests_1",       type = "police",   action = "bust",           target = 3,  name_key = "task_cop_arrests_1" },
            { id = "cop_chase_time_1",    type = "police",   action = "chase_time",     target = 120, name_key = "task_cop_chase_1" },
            { id = "cop_markers_1",       type = "police",   action = "marker_capture", target = 5,  name_key = "task_cop_markers_1" },
            { id = "cop_markers_chase_1", type = "police",   action = "marker_chase",   target = 2,  name_key = "task_cop_markers_chase_1" },
            -- Civilian tasks
            { id = "wanted_escape_1",        type = "civilian", action = "escape",          target = 2, name_key = "task_wanted_escape_1" },
            { id = "wanted_zigzag_1",        type = "civilian", action = "zigzag_pressure", target = 3, name_key = "task_wanted_zigzag_1" },
            { id = "wanted_markers_1",       type = "civilian", action = "marker_capture",  target = 5, name_key = "task_wanted_markers_1" },
            { id = "wanted_markers_chase_1", type = "civilian", action = "marker_chase",    target = 2, name_key = "task_wanted_markers_chase_1" },
        },
    },

    [2] = {
        name_key = "rank_2_name",
        prefix   = "[OP]",
        reward   = 10000,
        tasks = {
            -- Police tasks
            { id = "cop_arrests_2",       type = "police",   action = "bust",           target = 8,   name_key = "task_cop_arrests_2" },
            { id = "cop_chase_time_2",    type = "police",   action = "chase_time",     target = 300, name_key = "task_cop_chase_2" },
            { id = "cop_markers_2",       type = "police",   action = "marker_capture", target = 10,  name_key = "task_cop_markers_2" },
            { id = "cop_markers_chase_2", type = "police",   action = "marker_chase",   target = 4,   name_key = "task_cop_markers_chase_2" },
            -- Civilian tasks
            { id = "wanted_escape_2",        type = "civilian", action = "escape",         target = 5,  name_key = "task_wanted_escape_2" },
            { id = "wanted_combo_1",         type = "civilian", action = "combo_escape",   target = 2,  name_key = "task_wanted_combo_1" },
            { id = "wanted_markers_2",       type = "civilian", action = "marker_capture", target = 10, name_key = "task_wanted_markers_2" },
            { id = "wanted_markers_chase_2", type = "civilian", action = "marker_chase",   target = 4,  name_key = "task_wanted_markers_chase_2" },
        },
    },

    [3] = {
        name_key = "rank_3_name",
        prefix   = "[TAC]",
        reward   = 20000,
        tasks = {
            -- Police tasks
            { id = "cop_arrests_3",       type = "police",   action = "bust",           target = 15,  name_key = "task_cop_arrests_3" },
            { id = "cop_chase_time_3",    type = "police",   action = "chase_time",     target = 600, name_key = "task_cop_chase_3" },
            { id = "cop_markers_3",       type = "police",   action = "marker_capture", target = 18,  name_key = "task_cop_markers_3" },
            { id = "cop_markers_chase_3", type = "police",   action = "marker_chase",   target = 7,   name_key = "task_cop_markers_chase_3" },
            -- Civilian tasks
            { id = "wanted_escape_3",        type = "civilian", action = "escape",          target = 10, name_key = "task_wanted_escape_3" },
            { id = "wanted_zigzag_2",        type = "civilian", action = "zigzag_pressure", target = 10, name_key = "task_wanted_zigzag_2" },
            { id = "wanted_markers_3",       type = "civilian", action = "marker_capture",  target = 18, name_key = "task_wanted_markers_3" },
            { id = "wanted_markers_chase_3", type = "civilian", action = "marker_chase",    target = 7,  name_key = "task_wanted_markers_chase_3" },
        },
    },

    [4] = {
        name_key = "rank_4_name",
        prefix   = "[RLR]",
        reward   = 35000,
        tasks = {
            -- Police tasks
            { id = "cop_arrests_4",       type = "police",   action = "bust",           target = 25,   name_key = "task_cop_arrests_4" },
            { id = "cop_chase_time_4",    type = "police",   action = "chase_time",     target = 1200, name_key = "task_cop_chase_4" },
            { id = "cop_markers_4",       type = "police",   action = "marker_capture", target = 30,   name_key = "task_cop_markers_4" },
            { id = "cop_markers_chase_4", type = "police",   action = "marker_chase",   target = 12,   name_key = "task_cop_markers_chase_4" },
            -- Civilian tasks
            { id = "wanted_escape_4",        type = "civilian", action = "escape",         target = 20, name_key = "task_wanted_escape_4" },
            { id = "wanted_combo_2",         type = "civilian", action = "combo_escape",   target = 8,  name_key = "task_wanted_combo_2" },
            { id = "wanted_markers_4",       type = "civilian", action = "marker_capture", target = 30, name_key = "task_wanted_markers_4" },
            { id = "wanted_markers_chase_4", type = "civilian", action = "marker_chase",   target = 12, name_key = "task_wanted_markers_chase_4" },
        },
    },

    [5] = {
        name_key = "rank_5_name",
        prefix   = "[ULT]",
        reward   = 50000,
        tasks = {
            -- Police tasks
            { id = "cop_arrests_5",       type = "police",   action = "bust",           target = 40,   name_key = "task_cop_arrests_5" },
            { id = "cop_chase_time_5",    type = "police",   action = "chase_time",     target = 2400, name_key = "task_cop_chase_5" },
            { id = "cop_markers_5",       type = "police",   action = "marker_capture", target = 50,   name_key = "task_cop_markers_5" },
            { id = "cop_markers_chase_5", type = "police",   action = "marker_chase",   target = 20,   name_key = "task_cop_markers_chase_5" },
            -- Civilian tasks
            { id = "wanted_escape_5",        type = "civilian", action = "escape",         target = 35, name_key = "task_wanted_escape_5" },
            { id = "wanted_combo_3",         type = "civilian", action = "combo_escape",   target = 15, name_key = "task_wanted_combo_3" },
            { id = "wanted_markers_5",       type = "civilian", action = "marker_capture", target = 50, name_key = "task_wanted_markers_5" },
            { id = "wanted_markers_chase_5", type = "civilian", action = "marker_chase",   target = 20, name_key = "task_wanted_markers_chase_5" },
        },
    },
}
