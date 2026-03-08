-- =============================================================================
-- Day/Night Sync - Client Side
-- Part of: PIT Economy System
-- License: AGPL-3.0 (https://www.gnu.org/licenses/agpl-3.0.html)
-- =============================================================================

local M = {}

-- =============================================================================
-- STATE
-- =============================================================================
M.routineTimer    = hptimer()
M.globalSyncTime  = 5000
M.enabled         = false
M.setToState      = {
    play       = false,
    dayScale   = 1,
    nightScale = 1,
    time       = 0
}

M.setStatePointer     = core_environment.setState
M.requestStatePointer = core_environment.requestState

-- =============================================================================
-- UTILITIES
-- =============================================================================
M.len = function(tbl)
    if type(tbl) ~= "table" then return 0 end
    local len = 0
    for _ in pairs(tbl) do len = len + 1 end
    return len
end

M.between = function(value, min, max)
    return value >= min and value <= max
end

-- =============================================================================
-- ENVIRONMENT CONTROL
-- =============================================================================
M.delta = function()
    local diff  = {}
    local state = core_environment.getState()
    state.play  = state.play or false

    for k, v in pairs(state) do
        if type(v) == "number" and type(M.setToState[k]) == "number" then
            local tolerance = (k == "time") and 0.001 or 0.01
            if not M.between(v, M.setToState[k] - tolerance, M.setToState[k] + tolerance) then
                diff[k] = v
            end
        else
            if v ~= M.setToState[k] then diff[k] = v end
        end
    end

    return diff
end

M.apply = function()
    core_environment.setState = function() end
    core_environment.requestState = function()
        local state = core_environment.getState()
        guihooks.trigger("EnvironmentStateUpdate", { time = state.time, play = state.play })
    end
end

M.revert = function()
    core_environment.setState    = M.setStatePointer
    core_environment.requestState = M.requestStatePointer
end

-- =============================================================================
-- SYNC LOOP
-- =============================================================================
M.mainLoop = function(dt)
    if M.routineTimer:stop() > M.globalSyncTime then
        M.routineTimer:stopAndReset()
        local diff = M.delta()
        if M.len(diff) > 0 then
            TriggerServerEvent("syncDaytime", jsonEncode(diff))
        end
    end
end

-- =============================================================================
-- EVENT HANDLERS
-- =============================================================================
M.updateEnv = function(raw_msg)
    if raw_msg:len() > 0 then
        if not M.enabled then
            M.enabled = true
            M.apply()
        end
        local state = jsonDecode(raw_msg)
        for k, v in pairs(state) do
            M.setToState[k] = v
        end
        M.setStatePointer(M.setToState)
        TriggerServerEvent("syncDaytime", raw_msg)
    else
        if M.enabled then
            M.enabled = false
            M.revert()
        end
    end
end

M.updateSyncTime = function(raw_msg)
    M.globalSyncTime = tonumber(raw_msg)
end

M.onWorldReadyState = function(state)
    if state == 2 then
        if AddEventHandler then
            M.onExtensionUnloaded = M.revert
            M.onUpdate            = M.mainLoop
            AddEventHandler("syncDaytime", M.updateEnv)
            AddEventHandler("syncTime",    M.updateSyncTime)
        end
    end
end

return M
