-- =============================================================================
-- MinimapSystem.lua
-- Manages minimap updates for police/wanted gameplay.
-- Secondary module — loaded by main.lua via dofile()
-- Note: this module has a corresponding client-side component.
-- License: AGPL-3.0 — https://www.gnu.org/licenses/agpl-3.0.html
-- =============================================================================

local M = {}


-- =============================================================================
-- DEPENDENCIES  (injected via M.init)
-- =============================================================================

local MP, config, active_markers, CurrentMap
local getUID, getRole, isWanted, distance, encodeJSON, triggerClient, log


-- =============================================================================
-- CONFIGURATION
-- =============================================================================

local DISTANCES = {
    WANTED_VISIBLE        = 150,
    WANTED_HIDDEN         = 300,
    POLICE_VISIBLE        = 200,
    POLICE_HIDDEN         = 500,
    WANTED_TRACKING_RANGE = 1000,
}

local UPDATE_RATES = {
    FAST = 200,
    SLOW = 500,
}


-- =============================================================================
-- INTERNAL HELPERS
-- =============================================================================

local function calculatePoliceMode(pid)
    local uid       = getUID(pid)
    local role      = getRole(uid)
    local is_wanted = isWanted(pid)

    local ok, pos_data = pcall(MP.GetPositionRaw, pid, 0)
    if not (ok and pos_data and pos_data.pos) then return "disabled" end

    local player_pos = pos_data.pos

    if role == "civilian" and is_wanted then
        local closest_police_dist = math.huge
        for other_pid, _ in pairs(MP.GetPlayers() or {}) do
            if other_pid ~= pid and MP.IsPlayerConnected(other_pid) then
                if getRole(getUID(other_pid)) == "police" then
                    local ok_cop, cop_pos = pcall(MP.GetPositionRaw, other_pid, 0)
                    if ok_cop and cop_pos and cop_pos.pos then
                        closest_police_dist = math.min(closest_police_dist, distance(player_pos, cop_pos.pos))
                    end
                end
            end
        end
        if closest_police_dist < DISTANCES.WANTED_VISIBLE then
            return "visibleToPolice"
        elseif closest_police_dist < DISTANCES.WANTED_HIDDEN then
            return "hiddenFromPolice"
        else
            return "disabled"
        end
    end

    if role == "police" then
        local closest_wanted_dist = math.huge
        local has_wanted          = false
        for other_pid, _ in pairs(MP.GetPlayers() or {}) do
            if other_pid ~= pid and MP.IsPlayerConnected(other_pid) then
                if isWanted(other_pid) then
                    has_wanted = true
                    local ok_civ, civ_pos = pcall(MP.GetPositionRaw, other_pid, 0)
                    if ok_civ and civ_pos and civ_pos.pos then
                        closest_wanted_dist = math.min(closest_wanted_dist, distance(player_pos, civ_pos.pos))
                    end
                end
            end
        end
        if has_wanted then
            if closest_wanted_dist < DISTANCES.POLICE_VISIBLE then
                return "visibleToPolice"
            elseif closest_wanted_dist < DISTANCES.POLICE_HIDDEN then
                return "hiddenFromPolice"
            else
                return "disabled"
            end
        end
    end

    return "disabled"
end

local function getActiveMarkers()
    if not (config and config.features and config.features.markers_enabled) then return {} end
    if not active_markers or not next(active_markers) then return {} end

    local marker_color = (config.markers and config.markers.marker_color) or { r = 0, g = 255, b = 0, a = 200 }
    local marker_scale = (config.markers and config.markers.marker_scale) or 10

    local markers = {}
    for _, marker_data in pairs(active_markers) do
        if marker_data.position then
            table.insert(markers, {
                x     = marker_data.position.x,
                y     = marker_data.position.y,
                z     = marker_data.position.z,
                r     = marker_color.r,
                g     = marker_color.g,
                b     = marker_color.b,
                a     = marker_color.a,
                scale = marker_scale,
            })
        end
    end
    return markers
end

local function getWantedPidsForPolice(cop_pid)
    if getRole(getUID(cop_pid)) ~= "police" then return {} end

    local ok_cop, cop_pos_data = pcall(MP.GetPositionRaw, cop_pid, 0)
    if not (ok_cop and cop_pos_data and cop_pos_data.pos) then return {} end

    local cop_pos    = cop_pos_data.pos
    local wanted_pids = {}

    for other_pid, _ in pairs(MP.GetPlayers() or {}) do
        if other_pid ~= cop_pid and MP.IsPlayerConnected(other_pid) and isWanted(other_pid) then
            local ok_w, w_pos = pcall(MP.GetPositionRaw, other_pid, 0)
            if ok_w and w_pos and w_pos.pos then
                if distance(cop_pos, w_pos.pos) <= DISTANCES.WANTED_TRACKING_RANGE then
                    table.insert(wanted_pids, other_pid)
                end
            end
        end
    end
    return wanted_pids
end


-- =============================================================================
-- PUBLIC API
-- =============================================================================

function M.sendMinimapUpdate(pid)
    if not (MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end

    local payload = encodeJSON({
        policeMode   = calculatePoliceMode(pid),
        markers      = getActiveMarkers(),
        locationName = CurrentMap or "unknown",
        wanted_pids  = getWantedPidsForPolice(pid),
    })
    if payload then triggerClient(pid, "ECON_MinimapUpdate", payload) end
end

function M.updateMinimapsFast()
    for pid, _ in pairs(MP.GetPlayers() or {}) do
        if MP.IsPlayerConnected(pid) and isWanted(pid) then
            M.sendMinimapUpdate(pid)
        end
    end
end

function M.updateMinimapsSlow()
    for pid, _ in pairs(MP.GetPlayers() or {}) do
        if MP.IsPlayerConnected(pid) and not isWanted(pid) then
            M.sendMinimapUpdate(pid)
        end
    end
end

function M.init(dependencies)
    MP             = dependencies.MP
    config         = dependencies.config
    active_markers = dependencies.active_markers
    CurrentMap     = dependencies.CurrentMap
    getUID         = dependencies.getUID
    getRole        = dependencies.getRole
    isWanted       = dependencies.isWanted
    distance       = dependencies.distance
    encodeJSON     = dependencies.encodeJSON
    triggerClient  = dependencies.triggerClient
    log            = dependencies.log or print

    MP.CreateEventTimer("ECON_minimap_fast", UPDATE_RATES.FAST)
    MP.CreateEventTimer("ECON_minimap_slow", UPDATE_RATES.SLOW)
    MP.RegisterEvent("ECON_minimap_fast",    "ECON_minimap_fast")
    MP.RegisterEvent("ECON_minimap_slow",    "ECON_minimap_slow")

    log("Minimap system initialized")
    log(string.format("Fast update: %dms (wanted) | Slow update: %dms (police/civilian)", UPDATE_RATES.FAST, UPDATE_RATES.SLOW))
    log(string.format("Wanted tracking range: %dm", DISTANCES.WANTED_TRACKING_RANGE))
end

-- Allows runtime adjustment of detection distances without restarting the server.
function M.setDistances(wanted_visible, wanted_hidden, police_visible, police_hidden, tracking_range)
    DISTANCES.WANTED_VISIBLE        = wanted_visible   or DISTANCES.WANTED_VISIBLE
    DISTANCES.WANTED_HIDDEN         = wanted_hidden    or DISTANCES.WANTED_HIDDEN
    DISTANCES.POLICE_VISIBLE        = police_visible   or DISTANCES.POLICE_VISIBLE
    DISTANCES.POLICE_HIDDEN         = police_hidden    or DISTANCES.POLICE_HIDDEN
    DISTANCES.WANTED_TRACKING_RANGE = tracking_range   or DISTANCES.WANTED_TRACKING_RANGE
end

-- Allows runtime adjustment of update rates without restarting the server.
function M.setUpdateRates(fast_ms, slow_ms)
    UPDATE_RATES.FAST = fast_ms or UPDATE_RATES.FAST
    UPDATE_RATES.SLOW = slow_ms or UPDATE_RATES.SLOW
end

function M.getConfig()
    return {
        distances   = DISTANCES,
        updateRates = UPDATE_RATES,
    }
end

return M
