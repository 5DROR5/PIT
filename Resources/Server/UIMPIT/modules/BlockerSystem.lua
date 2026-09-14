-- =============================================================================
-- PIT Economy System - Blocker System
-- Version: 5.0
-- License: AGPL-3.0 - https://www.gnu.org/licenses/agpl-3.0.html
-- Credit: bollard logic adapted from Neverless's mod (discord: neverless)
-- =============================================================================

local M = {}

local _log, _MP, _config
local _encodeJSON, _decodeJSON
local _triggerClient, _broadcastClientEvent
local _getUID, _getPlayerName, _getRole, _setRole
local _addMoney, _sendMoneyUpdate
local _sendRepairIcons, _updatePrefix
local _sendMessage, _broadcastMessage, _translateForPlayer
local _forPlayers, _DB
local _player_repair_counters
local _sendPoliceRole, _sendPlayerListCustomData
local _players_editing_vehicle

local REQUIRED_BLOCKADES   = 5
local REWARD_PER_BLOCKADE  = 5000
local INITIAL_REPAIRS      = 2
local STOP_TIME_S          = 14
local STOP_SPEED_KMH       = 5
local STOP_RANGE_M         = 50
local COOLDOWN_S           = 3600
local MIN_DISTANCE_M       = 500
local MAX_STORED_BLOCKADES = 5
local TICK_S               = 0.5
local BLOCKER_SERIES       = { ["wl40"] = true }

local active_pid       = nil
local mission          = nil
local stop_timer       = 0
local cooldown_end     = 0
local stored_blockades = {}

-- =============================================================================
-- HELPERS
-- =============================================================================

local function isCooldown() return os.time() < cooldown_end end

local function distSq(p1, p2)
    local dx = (p1[1] or 0) - (p2[1] or 0)
    local dy = (p1[2] or 0) - (p2[2] or 0)
    local dz = (p1[3] or 0) - (p2[3] or 0)
    return dx*dx + dy*dy + dz*dz
end

local function nearbyPlayers(pid, range_m)
    local list, rsq = {}, range_m * range_m
    local pd, err = _MP.GetPositionRaw(pid, 0)
    if err ~= "" or not pd or not pd.pos then return list end
    _forPlayers(function(other)
        if other ~= pid and _MP.IsPlayerConnected(other) then
            local pd2, err2 = _MP.GetPositionRaw(other, 0)
            if err2 == "" and pd2 and pd2.pos and distSq(pd.pos, pd2.pos) <= rsq then
                table.insert(list, other)
            end
        end
    end)
    return list
end

local function hasWl40Vehicle(pid)
    local vehs = _MP.GetPlayerVehicles(pid)
    if not vehs then return false end
    for _, v in pairs(vehs) do
        if type(v) == "string" then
            local m = v:match("{.*}")
            if m then
                local data = _decodeJSON(m)
                if type(data) == "table" then
                    local skin   = (data.vcf and data.vcf.partConfigFilename) or ""
                    local series = skin:match("vehicles/([^/]+)/") or ""
                    if BLOCKER_SERIES[series:lower()] then return true end
                end
            end
        end
    end
    return false
end

local function anyOtherPlayerHasWl40(pid)
    for other, _ in pairs(_MP.GetPlayers() or {}) do
        if other ~= pid and _MP.IsPlayerConnected(other) and hasWl40Vehicle(other) then
            return true
        end
    end
    return false
end

local function sendMissionUpdate(pid)
    if not mission then return end
    local p = _encodeJSON({ blockade_count = mission.blockade_count, pending_money = mission.pending_money, required = REQUIRED_BLOCKADES })
    if p then _triggerClient(pid, "BLOCKER_MissionUpdate", p) end
end

local function syncBlockadesToPlayer(pid)
    if #stored_blockades == 0 then return end
    local p = _encodeJSON({ blockades = stored_blockades })
    if p then _triggerClient(pid, "BLOCKER_SyncBlockades", p) end
end

local function resetStopTimer()
    if stop_timer <= 0 then return end
    stop_timer = 0
    if active_pid and _MP.IsPlayerConnected(active_pid) then
        local p = _encodeJSON({ active = false, elapsed = 0, limit = STOP_TIME_S })
        if p then _triggerClient(active_pid, "BLOCKER_StopTimer", p) end
    end
end

local function distributeMoney(amount, pid)
    if amount <= 0 then return end
    local nearby = nearbyPlayers(pid, STOP_RANGE_M)
    if #nearby == 0 then return end
    local share = math.floor(amount / #nearby)
    if share <= 0 then return end
    for _, npid in ipairs(nearby) do
        if _MP.IsPlayerConnected(npid) then
            _addMoney(_getUID(npid), share)
            _sendMoneyUpdate(npid)
            _sendMessage(npid, _translateForPlayer(npid, "blocker_money_share", { amount = share }))
        end
    end
end

local function assignBlockerRole(pid)
    local uid = _getUID(pid)
    _setRole(uid, "blocker")
    _updatePrefix(pid)
    _player_repair_counters[pid] = { count = 0, max_repairs = INITIAL_REPAIRS, violations = { ["blocker"] = true } }
    _sendRepairIcons(pid)
    if _sendPoliceRole           then _sendPoliceRole(pid) end
    if _sendPlayerListCustomData then _sendPlayerListCustomData() end
end

local function clearBlockerRole(pid)
    local uid = _getUID(pid)
    _setRole(uid, "civilian")
    _updatePrefix(pid)
    _player_repair_counters[pid] = nil
    _sendRepairIcons(pid)
    if _sendPoliceRole           then _sendPoliceRole(pid) end
    if _sendPlayerListCustomData then _sendPlayerListCustomData() end
end

-- =============================================================================
-- MISSION CORE
-- =============================================================================

local function endMission(pid, success)
    if not mission then return end
    local pending = mission.pending_money
    local uid     = _getUID(pid)
    if success then
        _addMoney(uid, pending)
        _sendMoneyUpdate(pid)
        _sendMessage(pid, _translateForPlayer(pid, "blocker_mission_success", { amount = pending }))
        _forPlayers(function(p) _sendMessage(p, _translateForPlayer(p, "blocker_success_broadcast", { player = _getPlayerName(pid) })) end)
        cooldown_end = os.time() + COOLDOWN_S
        local cp = _encodeJSON({ cooldown_seconds = COOLDOWN_S })
        if cp then _broadcastClientEvent("BLOCKER_ServerCooldown", cp) end
    else
        distributeMoney(pending, pid)
        _sendMessage(pid, _translateForPlayer(pid, "blocker_mission_failed"))
        _forPlayers(function(p) _sendMessage(p, _translateForPlayer(p, "blocker_fail_broadcast", { player = _getPlayerName(pid) })) end)
    end
    clearBlockerRole(pid)
    local ep = _encodeJSON({ success = success })
    if ep then _triggerClient(pid, "BLOCKER_MissionEnd", ep) end
    active_pid = nil
    mission    = nil
    stop_timer = 0
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

function M.onRequestStart(pid, spawn_pos)
    if not _MP.IsPlayerConnected(pid) then return end
    if active_pid == pid then return end
    if _players_editing_vehicle and _players_editing_vehicle[pid] then
        local p = _encodeJSON({ reason = "not_synced" })
        if p then _triggerClient(pid, "BLOCKER_StartDenied", p) end
        return
    end
    if active_pid ~= nil then
        _sendMessage(pid, _translateForPlayer(pid, "blocker_already_active"))
        local p = _encodeJSON({ reason = "already_active" })
        if p then _triggerClient(pid, "BLOCKER_StartDenied", p) end
        return
    end
    if isCooldown() then
        local rem = cooldown_end - os.time()
        _sendMessage(pid, _translateForPlayer(pid, "blocker_cooldown", { minutes = math.ceil(rem / 60) }))
        local p = _encodeJSON({ reason = "cooldown", remaining = rem })
        if p then _triggerClient(pid, "BLOCKER_StartDenied", p) end
        return
    end
    if not hasWl40Vehicle(pid) then
        _sendMessage(pid, _translateForPlayer(pid, "blocker_wrong_vehicle"))
        local p = _encodeJSON({ reason = "wrong_vehicle" })
        if p then _triggerClient(pid, "BLOCKER_StartDenied", p) end
        return
    end
    if anyOtherPlayerHasWl40(pid) then
        _sendMessage(pid, _translateForPlayer(pid, "blocker_wl40_taken"))
        local p = _encodeJSON({ reason = "wl40_taken" })
        if p then _triggerClient(pid, "BLOCKER_StartDenied", p) end
        return
    end
    active_pid = pid
    mission    = { blockade_count = 0, pending_money = 0, last_pos = nil, spawn_pos = spawn_pos }
    stop_timer = 0
    local p = _encodeJSON({
        blockade_count  = 0,
        pending_money   = 0,
        required        = REQUIRED_BLOCKADES,
        initial_repairs = INITIAL_REPAIRS,
        spawn_x         = spawn_pos and spawn_pos.x or 0,
        spawn_y         = spawn_pos and spawn_pos.y or 0,
        spawn_z         = spawn_pos and spawn_pos.z or 0,
    })
    if p then _triggerClient(pid, "BLOCKER_MissionStart", p) end
    _sendMessage(pid, _translateForPlayer(pid, "blocker_mission_started"))
    _forPlayers(function(p) _sendMessage(p, _translateForPlayer(p, "blocker_started_broadcast", { player = _getPlayerName(pid) })) end)
end

function M.onBlockadePlaced(pid, data)
    if active_pid ~= pid or not mission then return end
    local d = type(data) == "string" and _decodeJSON(data) or data
    if not d or not d.x then return end

    if mission.blockade_count == 0 and mission.spawn_pos then
        local sp = mission.spawn_pos
        local dx, dy, dz = d.x - sp.x, d.y - sp.y, (d.z or 0) - sp.z
        if math.sqrt(dx*dx + dy*dy + dz*dz) < MIN_DISTANCE_M then
            _sendMessage(pid, _translateForPlayer(pid, "blocker_too_close_spawn"))
            local p = _encodeJSON({ reason = "too_close_spawn" })
            if p then _triggerClient(pid, "BLOCKER_BlockadeDenied", p) end
            return
        end
    end

    if mission.last_pos then
        local lp = mission.last_pos
        local dx, dy, dz = d.x - lp.x, d.y - lp.y, (d.z or 0) - lp.z
        if math.sqrt(dx*dx + dy*dy + dz*dz) < MIN_DISTANCE_M then
            _sendMessage(pid, _translateForPlayer(pid, "blocker_too_close"))
            local p = _encodeJSON({ reason = "too_close" })
            if p then _triggerClient(pid, "BLOCKER_BlockadeDenied", p) end
            return
        end
    end

    if mission.blockade_count == 0 then assignBlockerRole(pid) end

    mission.blockade_count = mission.blockade_count + 1
    mission.pending_money  = mission.pending_money + REWARD_PER_BLOCKADE
    mission.last_pos       = { x = d.x, y = d.y, z = d.z or 0 }

    table.insert(stored_blockades, { x = d.x, y = d.y, z = d.z or 0, dir_x = d.dir_x or 0, dir_y = d.dir_y or 0 })
    if #stored_blockades > MAX_STORED_BLOCKADES then table.remove(stored_blockades, 1) end

    local bp = _encodeJSON({ x = d.x, y = d.y, z = d.z or 0, dir_x = d.dir_x or 0, dir_y = d.dir_y or 0 })
    if bp then _forPlayers(function(other) if other ~= pid then _triggerClient(other, "BLOCKER_NewBlockade", bp) end end) end

    sendMissionUpdate(pid)
    if mission.blockade_count >= REQUIRED_BLOCKADES then endMission(pid, true) end
end

function M.onBlockadeUndone(pid)
    if active_pid ~= pid or not mission then return end
    if mission.blockade_count <= 0 then return end
    mission.blockade_count = mission.blockade_count - 1
    mission.pending_money  = mission.pending_money - REWARD_PER_BLOCKADE
    if #stored_blockades > 0 then table.remove(stored_blockades, #stored_blockades) end
    mission.last_pos = (#stored_blockades > 0) and stored_blockades[#stored_blockades] or nil
    local bp = _encodeJSON({ undo = true })
    if bp then _forPlayers(function(other) if other ~= pid then _triggerClient(other, "BLOCKER_UndoLastBlockade", bp) end end) end
    sendMissionUpdate(pid)
    if mission.blockade_count == 0 then clearBlockerRole(pid) end
end

function M.onMissionFailed(pid, reason)
    if active_pid ~= pid then return end
    endMission(pid, false)
end

function M.onPlayerJoin(pid)
    if isCooldown() then
        local rem = cooldown_end - os.time()
        local p   = _encodeJSON({ cooldown_seconds = rem })
        if p then _triggerClient(pid, "BLOCKER_ServerCooldown", p) end
    end
    syncBlockadesToPlayer(pid)
end

function M.onPlayerLeave(pid)
    if active_pid == pid then endMission(pid, false) end
end

function M.isBlocker(pid)      return active_pid == pid end
function M.getPendingMoney()   return mission and mission.pending_money or 0 end
function M.isActiveMission()   return active_pid ~= nil end
function M.hasWl40Vehicle(pid) return hasWl40Vehicle(pid) end

-- =============================================================================
-- TICK
-- =============================================================================

function M.tick()
    if not active_pid then return end
    if not _MP.IsPlayerConnected(active_pid) then
        active_pid = nil; mission = nil; stop_timer = 0; return
    end
    local pd, err = _MP.GetPositionRaw(active_pid, 0)
    if err ~= "" or not pd or not pd.vel then return end
    if mission.blockade_count == 0 then return end
    local spd = math.sqrt((pd.vel[1] or 0)^2 + (pd.vel[2] or 0)^2) * 3.6
    if spd < STOP_SPEED_KMH and pd.pos then
        local nearby = nearbyPlayers(active_pid, STOP_RANGE_M)
        if #nearby > 0 then
            stop_timer = stop_timer + TICK_S
            local p = _encodeJSON({ active = true, elapsed = stop_timer, limit = STOP_TIME_S })
            if p then _triggerClient(active_pid, "BLOCKER_StopTimer", p) end
            if stop_timer >= STOP_TIME_S then endMission(active_pid, false) end
        else
            resetStopTimer()
        end
    else
        resetStopTimer()
    end
end

-- =============================================================================
-- INIT
-- =============================================================================

function M.init(deps)
    _log                      = deps.log
    _MP                       = deps.MP
    _config                   = deps.config
    _encodeJSON               = deps.encodeJSON
    _decodeJSON               = deps.decodeJSON
    _triggerClient            = deps.triggerClient
    _broadcastClientEvent     = deps.broadcastClientEvent
    _getUID                   = deps.getUID
    _getPlayerName            = deps.getPlayerName
    _getRole                  = deps.getRole
    _setRole                  = deps.setRole
    _addMoney                 = deps.addMoney
    _sendMoneyUpdate          = deps.sendMoneyUpdate
    _sendRepairIcons          = deps.sendRepairIcons
    _updatePrefix             = deps.updatePrefix
    _sendMessage              = deps.sendMessage
    _broadcastMessage         = deps.broadcastMessage
    _translateForPlayer       = deps.translateForPlayer
    _forPlayers               = deps.forPlayers
    _DB                       = deps.DB
    _player_repair_counters   = deps.player_repair_counters
    _sendPoliceRole           = deps.sendPoliceRole
    _sendPlayerListCustomData = deps.sendPlayerListCustomData
    _players_editing_vehicle  = deps.players_editing_vehicle
    _log("BlockerSystem initialized")
end

return M