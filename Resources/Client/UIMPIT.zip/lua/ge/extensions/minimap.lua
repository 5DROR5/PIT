-- =============================================================================
-- PIT Economy System — Minimap Extension
-- Version: 0.06
-- License: AGPL-3.0 — https://www.gnu.org/licenses/agpl-3.0.html
-- =============================================================================

local M = {}

-- =============================================================================
-- GAME STATE
-- =============================================================================

local currentMinimapData = {
    policeMode   = "disabled",
    distToTarget = nil,
    locationName = nil,
    markers      = {},
    wanted_pids  = {}
}

local lastUpdate     = 0
local hasNewData     = false
local lastDistUpdate = 0

-- =============================================================================
-- UTILITIES
-- =============================================================================

local function calculateLocalDistance()
    if not currentMinimapData.markers or #currentMinimapData.markers == 0 then
        return nil
    end

    local playerVehicle = be:getPlayerVehicle(0)
    if not playerVehicle then return nil end

    local playerPos = playerVehicle:getPosition()
    if not playerPos then return nil end

    local closestDist = math.huge

    for _, marker in ipairs(currentMinimapData.markers) do
        local dx   = playerPos.x - marker.x
        local dy   = playerPos.y - marker.y
        local dz   = playerPos.z - marker.z
        local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
        if dist < closestDist then
            closestDist = dist
        end
    end

    if closestDist < math.huge then
        if closestDist < 1000 then
            return string.format("%d m", math.floor(closestDist))
        else
            return string.format("%.1f km", closestDist / 1000)
        end
    end

    return nil
end

local function getWantedPlayerPosition(pid)
    if not extensions.MPVehicleGE then return nil end

    local vehicles = extensions.MPVehicleGE.getVehicles()
    if not vehicles then return nil end

    for serverVehicleID, vehicle in pairs(vehicles) do
        if vehicle.ownerID == pid and vehicle.gameVehicleID then
            local veh = be:getObjectByID(vehicle.gameVehicleID)
            if veh then return veh:getPosition() end
        end
    end

    return nil
end

-- =============================================================================
-- DATA HANDLER
-- =============================================================================

local function onMinimapUpdate(data)
    if not data then return end

    local decoded = data
    if type(data) == "string" then
        local ok, result = pcall(jsonDecode, data)
        if ok then
            decoded = result
        else
            log("W", "economy_minimap", "Failed to decode minimap data")
            return
        end
    end

    currentMinimapData.policeMode   = decoded.policeMode   or "disabled"
    currentMinimapData.markers      = decoded.markers      or {}
    currentMinimapData.locationName = decoded.locationName
    currentMinimapData.wanted_pids  = decoded.wanted_pids  or {}
    hasNewData = true
end

-- =============================================================================
-- MINIMAP RENDERING
-- =============================================================================

M.onDrawOnMinimap = function(td)
    if not ui_apps_minimap_utils then return end

    if currentMinimapData.markers and #currentMinimapData.markers > 0 then
        for _, marker in ipairs(currentMinimapData.markers) do
            local pos         = vec3(marker.x, marker.y, marker.z)
            local fillColor   = color(marker.r or 0, marker.g or 255, marker.b or 0, marker.a or 200)
            local strokeColor = color(255, 255, 255, 255)
            local radius      = (marker.scale or 10) * 0.8

            ui_apps_minimap_utils.simpleCircleWithEdgePointer(pos, fillColor, strokeColor, radius)
        end
    end

    if currentMinimapData.wanted_pids and #currentMinimapData.wanted_pids > 0 then
        for _, pid in ipairs(currentMinimapData.wanted_pids) do
            local wantedPos = getWantedPlayerPosition(pid)
            if wantedPos then
                local pos         = vec3(wantedPos.x, wantedPos.y, wantedPos.z)
                local fillColor   = color(255, 0, 0, 255)
                local strokeColor = color(255, 255, 255, 255)

                ui_apps_minimap_utils.simpleCircleWithEdgePointer(pos, fillColor, strokeColor, 8)
            end
        end
    end
end

-- =============================================================================
-- LIFECYCLE
-- =============================================================================

M.onExtensionLoaded = function()
    log("I", "economy_minimap", "Economy Minimap extension loaded")
end

M.onInit = function()
    if AddEventHandler then
        AddEventHandler("ECON_MinimapUpdate", onMinimapUpdate)
        log("I", "economy_minimap", "Registered ECON_MinimapUpdate handler")
    end

    if extensions and extensions.hook then
        extensions.hook("onDrawOnMinimap", M.onDrawOnMinimap)
        log("I", "economy_minimap", "Registered onDrawOnMinimap hook")
    end
end

-- =============================================================================
-- UPDATE LOOP
-- =============================================================================

M.onUpdate = function(dt)
    local now = os.clock()

    if now - lastDistUpdate > 0.016 then
        lastDistUpdate               = now
        currentMinimapData.distToTarget = calculateLocalDistance()
        hasNewData = true
    end

    if not hasNewData then return end
    if now - lastUpdate < 0.05 then return end

    lastUpdate = now
    hasNewData = false

    if guihooks and guihooks.queueStream then
        guihooks.queueStream("minimap", currentMinimapData)
    end
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

M.onMinimapUpdate = onMinimapUpdate  -- called directly by key.lua via extensions.minimap
M.getCurrentData  = function() return currentMinimapData end
M.forceUpdate     = function() hasNewData = true end

return M
