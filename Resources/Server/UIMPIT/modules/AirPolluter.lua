-- =============================================================================
-- AirPolluter.lua
-- Special Mission: Air Polluter
-- Secondary module — loaded by main.lua via dofile()
-- License: AGPL-3.0 — https://www.gnu.org/licenses/agpl-3.0.html
-- =============================================================================

local AP = {}


-- =============================================================================
-- CONSTANTS  (overridable via config.json → "air_polluter")
-- =============================================================================

local MISSION_DURATION_MS   = 900000  -- 15 minutes
local TOUCH_DURATION_MS     = 5000    -- hold time required to activate (ms)
local TOUCH_RADIUS_M        = 4       -- server-side activation radius
local HOVER_RADIUS_M        = 15      -- show status UI within this range
local VISIBILITY_RADIUS_M   = 50      -- client hides marker beyond this distance
local MIN_PLAYERS           = 4       -- minimum connected players to allow activation
local COOLDOWN_SECS         = 21600   -- 6 hours between missions
local SUCCESS_BONUS         = 10000
local FAIL_PENALTY          = 1000
local MISSION_REPAIRS       = 2
local INCOME_PER_SEC        = 11
local POLICE_RANGE_M        = 150
local POLICE_INCOME_PER_SEC = 20
local MAX_FOG_DENSITY       = 0.03
local FOG_UPDATE_MS         = 5000


-- =============================================================================
-- STATE
-- =============================================================================

local state = {
    active         = false,
    pid            = nil,
    uid            = nil,
    start_ms       = nil,
    end_ms         = nil,
    last_income_ms = nil,
    last_fog_ms    = 0,
    fog_intensity  = 0,
    touch_timers   = {},
    cooldown_time  = nil,
    cooldown_uid   = nil,
}

-- Tracks which pids currently have the status panel visible.
local status_visible_players = {}


-- =============================================================================
-- DEPENDENCIES  (injected via AP.init)
-- =============================================================================

local deps = {}


-- =============================================================================
-- INTERNAL HELPERS
-- =============================================================================

local function log(msg)
    if deps.log then deps.log("[AirPolluter] " .. tostring(msg)) end
end

local function getMarkerPos()
    local map      = deps.getCurrentMap and deps.getCurrentMap() or "west_coast_usa"
    local map_locs = deps.locations and deps.locations[map]
    if map_locs and map_locs.air_polluter_marker then
        return map_locs.air_polluter_marker
    end
    local wc = deps.locations and deps.locations["west_coast_usa"]
    return (wc and wc.air_polluter_marker) or { x = 0, y = 0, z = 100 }
end

local function getPlayerCount()
    local n = 0
    deps.forPlayers(function(_) n = n + 1 end)
    return n
end

local function isCooldown()
    if not state.cooldown_time then return false end
    return (os.time() - state.cooldown_time) < COOLDOWN_SECS
end

local function encode(t) return deps.encodeJSON(t) end


-- =============================================================================
-- NETWORK
-- =============================================================================

local function toPlayer(pid, event, payload)
    deps.triggerClient(pid, event, payload)
end

local function toAll(event, payload)
    deps.broadcastClientEvent(event, payload)
end

local function broadcastFog(intensity, single_pid)
    local p = encode({ intensity = intensity })
    if not p then return end
    if single_pid then toPlayer(single_pid, "AIRPOLLUTER_FogUpdate", p)
    else               toAll("AIRPOLLUTER_FogUpdate", p) end
end

local function sendMarker(pid)
    local pos = getMarkerPos()
    local p   = encode({ x = pos.x, y = pos.y, z = pos.z, visibility_radius = VISIBILITY_RADIUS_M })
    if p then toPlayer(pid, "AIRPOLLUTER_SetMarker", p) end
end


-- =============================================================================
-- STATUS PANEL  (proximity UI — shown when mission is idle only)
-- =============================================================================

local function hideStatusPanel(pid)
    local p = encode({ visible = false })
    if p then toPlayer(pid, "AIRPOLLUTER_StatusUpdate", p) end
    status_visible_players[pid] = nil
end

local function hideStatusPanelAll()
    local MP = deps.MP
    for pid, _ in pairs(status_visible_players) do
        if MP.IsPlayerConnected(pid) then hideStatusPanel(pid) end
    end
    status_visible_players = {}
end

local function sendStatusToNearbyPlayers(now)
    local mPos    = getMarkerPos()
    local hoverSq = HOVER_RADIUS_M * HOVER_RADIUS_M
    local MP      = deps.MP
    local pc      = getPlayerCount()

    local in_cooldown        = isCooldown()
    local cooldown_remaining = 0
    if in_cooldown then
        cooldown_remaining = math.max(0, COOLDOWN_SECS - (os.time() - state.cooldown_time))
    end

    deps.forPlayers(function(pid)
        if not MP.IsPlayerConnected(pid) then return end
        local ok, pd = pcall(MP.GetPositionRaw, pid, 0)
        if not (ok and pd and pd.pos) then return end
        local p  = pd.pos
        local dx = (p[1] or 0) - mPos.x
        local dy = (p[2] or 0) - mPos.y
        local dz = (p[3] or 0) - mPos.z

        if dx*dx + dy*dy + dz*dz <= hoverSq then
            local uid       = deps.getUID(pid)
            local available = true
            local reasons   = {}

            if in_cooldown then
                available = false
                table.insert(reasons, "ap_reason_cooldown")
            end
            if pc < MIN_PLAYERS then
                available = false
                table.insert(reasons, "ap_reason_players")
            end
            if deps.getRole(uid) ~= "civilian" then
                available = false
                table.insert(reasons, "ap_reason_not_civilian")
            elseif deps.isWanted(pid) then
                available = false
                table.insert(reasons, "ap_reason_wanted")
            elseif deps.players_editing_vehicle and deps.players_editing_vehicle[pid] then
                available = false
                table.insert(reasons, "ap_reason_editing")
            end

            local touch_progress = 0
            if state.touch_timers[pid] then
                touch_progress = math.min(100, (now - state.touch_timers[pid]) / TOUCH_DURATION_MS * 100)
            end

            local payload = encode({
                visible            = true,
                available          = available,
                reasons            = reasons,
                player_count       = pc,
                required_players   = MIN_PLAYERS,
                cooldown_remaining = cooldown_remaining,
                touch_progress     = touch_progress,
            })
            if payload then
                toPlayer(pid, "AIRPOLLUTER_StatusUpdate", payload)
                status_visible_players[pid] = true
            end
        elseif status_visible_players[pid] then
            hideStatusPanel(pid)
        end
    end)
end


-- =============================================================================
-- MISSION LIFECYCLE
-- =============================================================================

local function startMission(pid)
    local uid = deps.getUID(pid)
    local now = os.time() * 1000

    state.active         = true
    state.pid            = pid
    state.uid            = uid
    state.start_ms       = now
    state.end_ms         = now + MISSION_DURATION_MS
    state.last_income_ms = now
    state.last_fog_ms    = now
    state.fog_intensity  = 0
    state.touch_timers   = {}

    -- Hide the proximity status panel for all players — mission is now in progress.
    hideStatusPanelAll()

    deps.DB.setWanted(uid, true)
    pcall(function() deps.DB.incrementWantedCount(uid) end)

    deps.wanted_timers[pid]          = state.end_ms
    deps.wanted_violations[pid]      = { airpolluter = true }
    deps.player_repair_counters[pid] = {
        count       = 0,
        max_repairs = MISSION_REPAIRS,
        violations  = { airpolluter = true },
    }

    broadcastFog(0)
    deps.sendRepairIcons(pid)
    deps.sendWantedUI(pid, MISSION_DURATION_MS / 1000)
    deps.updatePrefix(pid)

    local name = deps.getPlayerName(pid)
    deps.broadcastMessage(deps.translateForPlayer(-1, "airpolluter_start_broadcast", { player = name }))
    toAll("AIRPOLLUTER_MissionStart", encode({ playerName = name }))
    log("Mission started by " .. name .. " (pid=" .. pid .. ")")
end

local function endMission(success)
    if not state.active then return end

    local pid  = state.pid
    local uid  = state.uid
    local name = (pid and deps.MP.IsPlayerConnected(pid))
                 and deps.getPlayerName(pid) or "?"

    state.fog_intensity = 0
    broadcastFog(0)

    state.cooldown_uid  = uid
    state.cooldown_time = os.time()

    if success then
        if pid and deps.MP.IsPlayerConnected(pid) then
            deps.addMoney(uid, SUCCESS_BONUS)
            deps.sendMoneyUpdate(pid)
            deps.sendMessage(pid, deps.translateForPlayer(pid, "airpolluter_success", { amount = SUCCESS_BONUS }))
            pcall(function() deps.DB.incrementWantedSuccess(uid) end)
        end
        deps.broadcastMessage(deps.translateForPlayer(-1, "airpolluter_success_broadcast", { player = name }))
        toAll("AIRPOLLUTER_MissionEnd", encode({ success = true,  playerName = name }))
    else
        deps.broadcastMessage(deps.translateForPlayer(-1, "airpolluter_fail_broadcast", { player = name }))
        toAll("AIRPOLLUTER_MissionEnd", encode({ success = false, playerName = name }))
    end

    if pid and deps.MP.IsPlayerConnected(pid) then
        deps.clearWanted(pid)
        deps.sendWantedUI(pid, 0)
        deps.updatePrefix(pid)
        deps.sendRepairIcons(pid)
    end

    state.active         = false
    state.pid            = nil;  state.uid           = nil
    state.start_ms       = nil;  state.end_ms        = nil
    state.last_income_ms = nil;  state.fog_intensity = 0

    log("Mission ended — success=" .. tostring(success))
end


-- =============================================================================
-- PUBLIC API
-- =============================================================================

function AP.init(d)
    deps = d
    if deps.config and deps.config.air_polluter then
        local c = deps.config.air_polluter
        if c.min_players    then MIN_PLAYERS    = tonumber(c.min_players)    or MIN_PLAYERS    end
        if c.cooldown_secs  then COOLDOWN_SECS  = tonumber(c.cooldown_secs)  or COOLDOWN_SECS  end
        if c.hover_radius_m then HOVER_RADIUS_M = tonumber(c.hover_radius_m) or HOVER_RADIUS_M end
        if c.touch_radius_m then TOUCH_RADIUS_M = tonumber(c.touch_radius_m) or TOUCH_RADIUS_M end
        log(string.format("Config loaded: min_players=%d  cooldown=%ds  hover_radius=%dm  touch_radius=%dm",
            MIN_PLAYERS, COOLDOWN_SECS, HOVER_RADIUS_M, TOUCH_RADIUS_M))
    end
    log("Module initialized")
end

function AP.onPlayerJoin(pid)
    sendMarker(pid)
    if state.active then broadcastFog(state.fog_intensity, pid) end
end

function AP.onPlayerLeave(pid)
    state.touch_timers[pid]     = nil
    status_visible_players[pid] = nil
    if state.active and state.pid == pid then
        state.fog_intensity = 0
        broadcastFog(0)
        state.cooldown_time = os.time()
        state.active        = false
        state.pid           = nil;  state.uid      = nil
        state.end_ms        = nil;  state.start_ms = nil
        log("Mission aborted — player disconnected")
    end
end

function AP.onMissionFailed(pid)
    if not state.active or state.pid ~= pid then return end
    local uid = state.uid
    deps.addMoney(uid, -FAIL_PENALTY)
    deps.sendMoneyUpdate(pid)
    deps.sendMessage(pid, deps.translateForPlayer(pid, "airpolluter_fail_message", { penalty = FAIL_PENALTY }))
    pcall(function() deps.DB.incrementWantedFailed(uid) end)
    endMission(false)
end

function AP.isActiveMission() return state.active                  end
function AP.getActivePid()    return state.pid                     end
function AP.isAPPlayer(pid)   return state.active and state.pid == pid end


-- =============================================================================
-- MAIN TICK  (called every 300 ms by main.lua)
-- =============================================================================

function AP.tick()
    local now = os.time() * 1000
    local MP  = deps.MP

    -- ── IDLE ─────────────────────────────────────────────────────────────────
    if not state.active then
        if not isCooldown() and getPlayerCount() >= MIN_PLAYERS then
            local mPos          = getMarkerPos()
            local touchSq       = TOUCH_RADIUS_M * TOUCH_RADIUS_M
            local mission_started = false

            deps.forPlayers(function(pid)
                if mission_started then return end
                if not MP.IsPlayerConnected(pid) then return end
                local uid = deps.getUID(pid)

                if deps.getRole(uid) ~= "civilian"
                   or deps.isWanted(pid)
                   or (deps.players_editing_vehicle and deps.players_editing_vehicle[pid])
                then
                    state.touch_timers[pid] = nil
                    return
                end

                local ok, pd = pcall(MP.GetPositionRaw, pid, 0)
                if not (ok and pd and pd.pos) then return end
                local p  = pd.pos
                local dx = (p[1] or 0) - mPos.x
                local dy = (p[2] or 0) - mPos.y
                local dz = (p[3] or 0) - mPos.z

                if dx*dx + dy*dy + dz*dz <= touchSq then
                    if not state.touch_timers[pid] then
                        state.touch_timers[pid] = now
                    elseif (now - state.touch_timers[pid]) >= TOUCH_DURATION_MS then
                        state.touch_timers = {}
                        startMission(pid)
                        mission_started = true
                    end
                else
                    state.touch_timers[pid] = nil
                end
            end)

            if mission_started then return end
        else
            state.touch_timers = {}
        end

        sendStatusToNearbyPlayers(now)
        return
    end

    -- ── ACTIVE ───────────────────────────────────────────────────────────────
    local pid = state.pid
    if not pid then endMission(false); return end

    if not MP.IsPlayerConnected(pid) then
        AP.onPlayerLeave(pid)
        return
    end

    if now >= state.end_ms then
        endMission(true)
        return
    end

    if not deps.isWanted(pid) then
        state.fog_intensity = 0
        broadcastFog(0)
        state.active    = false
        state.pid       = nil;  state.uid      = nil
        state.end_ms    = nil;  state.start_ms = nil
        return
    end

    local remaining = math.max(0, math.ceil((state.end_ms - now) / 1000))
    deps.sendWantedUI(pid, remaining)

    if (now - state.last_fog_ms) >= FOG_UPDATE_MS then
        local ratio         = math.min(1.0, (now - state.start_ms) / MISSION_DURATION_MS)
        state.fog_intensity = ratio * MAX_FOG_DENSITY
        state.last_fog_ms   = now
        broadcastFog(state.fog_intensity)
    end

    local income_sec = math.max(0,
        math.floor(now / 1000) - math.floor((state.last_income_ms or now) / 1000))

    if income_sec > 0 then
        local police_n    = 0
        local nearby_cops = {}
        local rangeSq     = POLICE_RANGE_M * POLICE_RANGE_M
        local ok_c, cpd   = pcall(MP.GetPositionRaw, pid, 0)

        if ok_c and cpd and cpd.pos then
            local cp = cpd.pos
            deps.forPlayers(function(opid)
                if opid == pid or not MP.IsPlayerConnected(opid) then return end
                if deps.getRole(deps.getUID(opid)) ~= "police" then return end
                local ok2, cop = pcall(MP.GetPositionRaw, opid, 0)
                if ok2 and cop and cop.pos then
                    local co  = cop.pos
                    local ddx = (cp[1] or 0) - (co[1] or 0)
                    local ddy = (cp[2] or 0) - (co[2] or 0)
                    local ddz = (cp[3] or 0) - (co[3] or 0)
                    if ddx*ddx + ddy*ddy + ddz*ddz <= rangeSq then
                        police_n = police_n + 1
                        table.insert(nearby_cops, opid)
                    end
                end
            end)
        end

        if police_n > 0 then
            local income = income_sec * INCOME_PER_SEC * police_n
            deps.addMoney(state.uid, income)
            deps.sendMoneyUpdate(pid)
            pcall(function() deps.DB.addWantedTime(state.uid, income_sec) end)
            local cop_income = income_sec * POLICE_INCOME_PER_SEC
            for _, cop_pid in ipairs(nearby_cops) do
                deps.addMoney(deps.getUID(cop_pid), cop_income)
                deps.sendMoneyUpdate(cop_pid)
            end
        end

        state.last_income_ms = now
    end
end

return AP
