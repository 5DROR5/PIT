-- =============================================================================
-- Day/Night Sync - Server Side
-- Copyright (c) 2026 5DROR5
-- License: MIT (https://opensource.org/licenses/MIT)
-- =============================================================================

local M = {}

-- =============================================================================
-- STATE
-- =============================================================================

M.enabled = true
M.progressTimeIfNoPlayer = true
M.resetToPresetWhenServerEmpty = true
M.globalSyncTime = 5000

-- Full cycle: 20 minutes (15 min day + 5 min night)
M.preset = {
    play       = true,   -- time advances automatically
    dayScale   = 1.11,   -- day speed  (15 min)
    nightScale = 2.73,   -- night speed (5 min)
    time       = 0       -- start at noon
}

M.TimeMovePerSecond = 0.00055
M.NightStart        = 0.27433
M.NightEnd          = 0.72507

-- =============================================================================
-- UTILITIES
-- =============================================================================
local function lenTbl(tbl)
    if type(tbl) ~= "table" then return 0 end
    local len = 0
    for _ in pairs(tbl) do len = len + 1 end
    return len
end

local function isBetween(value, min, max)
    return value >= min and value <= max
end

-- =============================================================================
-- PLAYER SYNC TRACKER
-- =============================================================================
local PlayerSync = {}
PlayerSync.players = {}

function PlayerSync:isSynced(player_id)
    return self.players[player_id] or false
end

function PlayerSync:setSynced(player_id)
    self.players[player_id] = true
end

function PlayerSync:remove(player_id)
    self.players[player_id] = nil
end

function PlayerSync:send(player_id, event_name, event_data)
    local targets = {}
    player_id = tonumber(player_id)
    if player_id ~= -1 then
        table.insert(targets, player_id)
    else
        for pid in pairs(MP.GetPlayers()) do
            table.insert(targets, pid)
        end
    end
    for _, pid in pairs(targets) do
        if self:isSynced(pid) then
            if type(event_data) == "table" then
                event_data = Util.JsonEncode(event_data)
            end
            MP.TriggerClientEvent(pid, event_name, tostring(event_data) or "")
        end
    end
end

-- =============================================================================
-- ACCURATE TIMER
-- =============================================================================
local function AccuTimer()
    local timer = { int = { timer = MP.CreateTimer() } }
    function timer:stop()
        return self.int.timer:GetCurrent() * 1000
    end
    function timer:stopAndReset()
        local time = self.int.timer:GetCurrent() * 1000
        self.int.timer:Start()
        return time
    end
    return timer
end

-- =============================================================================
-- PLAYER TRACKING
-- =============================================================================
M.Players = { int = {} }

function M.Players:new(player_id)
    local player = {
        int = {
            name       = MP.GetPlayerName(player_id),
            play       = false,
            dayScale   = 1,
            nightScale = 1,
            time       = 0
        }
    }

    function player:updateFromTable(tbl)
        if type(tbl.play) == "boolean" then self.int.play = tbl.play end
        if tbl.dayScale   ~= nil and type(tbl.dayScale)   == "number" then self.int.dayScale   = tbl.dayScale   end
        if tbl.nightScale ~= nil and type(tbl.nightScale) == "number" then self.int.nightScale = tbl.nightScale end
        if tbl.time ~= nil and type(tbl.time) == "number" and isBetween(tbl.time, 0, 1) then
            self.int.time = tbl.time
        end
    end

    function player:diff(tbl)
        local diff = {}
        for k, v in pairs(tbl) do
            if self.int[k] ~= nil then
                if k == "time" then
                    local d = self.int[k] - v
                    if not (isBetween(d, -0.01, 0.01) or isBetween(d, -1, -0.99)) then
                        diff[k] = v
                    end
                elseif type(self.int[k]) == "number" then
                    local d = tonumber(string.format("%.3f", self.int[k])) - tonumber(string.format("%.3f", v))
                    if d < -0.1 or d > 0.1 then diff[k] = v end
                else
                    if self.int[k] ~= v then diff[k] = v end
                end
            end
        end
        if lenTbl(diff) == 0 then return nil end
        return diff
    end

    self.int[player_id] = player
end

function M.Players:remove(player_id)
    self.int[player_id] = nil
end

function M.Players:diff(tbl)
    local diff = {}
    for player_id, player in pairs(self.int) do
        diff[player_id] = player:diff(tbl)
    end
    return diff
end

function M.Players:updateFromTable(player_id, tbl)
    if self.int[player_id] ~= nil then
        self.int[player_id]:updateFromTable(tbl)
    end
end

function M.Players:getCount()
    return lenTbl(self.int)
end

-- =============================================================================
-- SERVER TIME
-- =============================================================================
M.ServerTickTimer = AccuTimer()
M.ServerTime = {
    play       = M.preset.play,
    dayScale   = M.preset.dayScale,
    nightScale = M.preset.nightScale,
    time       = M.preset.time
}

local function fitPreset()
    for k, v in pairs(M.preset) do
        if type(M.ServerTime[k]) == type(v) then
            M.ServerTime[k] = v
        end
    end
end

local function syncAll()
    PlayerSync:send(-1, "syncDaytime", M.ServerTime)
end

-- =============================================================================
-- MAIN TICK
-- =============================================================================
function timeTick()
    if not M.enabled then return end
    if not M.progressTimeIfNoPlayer and M.Players:getCount() == 0 then return end

    local dt = M.ServerTickTimer:stopAndReset()
    if M.ServerTime.play then
        local increase
        if isBetween(M.ServerTime.time, M.NightStart, M.NightEnd) then
            increase = (dt / 1000) * (M.TimeMovePerSecond * M.ServerTime.nightScale)
        else
            increase = (dt / 1000) * (M.TimeMovePerSecond * M.ServerTime.dayScale)
        end
        M.ServerTime.time = M.ServerTime.time + increase
        while M.ServerTime.time > 1 do
            M.ServerTime.time = M.ServerTime.time - 1
        end
    end

    local diff = M.Players:diff(M.ServerTime)
    for player_id, d in pairs(diff) do
        PlayerSync:send(player_id, "syncDaytime", d)
    end
end

-- =============================================================================
-- EVENT HANDLERS
-- =============================================================================
function refreshPlayer(player_id, raw_msg)
    local decode = Util.JsonDecode(raw_msg)
    if decode == nil or type(decode) == "string" then return end
    M.Players:updateFromTable(player_id, decode)
end

function onPlayerJoin(player_id)
    if M.resetToPresetWhenServerEmpty and M.Players:getCount() == 0 then
        fitPreset()
    end
    PlayerSync:setSynced(player_id)
    M.Players:new(player_id)
    PlayerSync:send(player_id, "syncTime", M.globalSyncTime)
    PlayerSync:send(player_id, "syncDaytime", M.ServerTime)
end

function onPlayerDisconnect(player_id)
    PlayerSync:remove(player_id)
    M.Players:remove(player_id)
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================
function onInit()
    MP.RegisterEvent("onPlayerJoin",       "onPlayerJoin")
    MP.RegisterEvent("onPlayerDisconnect", "onPlayerDisconnect")
    MP.RegisterEvent("syncDaytime",        "refreshPlayer")

    MP.CancelEventTimer("tickTime")
    MP.RegisterEvent("tickTime", "timeTick")
    MP.CreateEventTimer("tickTime", M.globalSyncTime)

    -- Re-sync existing players on hot reload
    local players = MP.GetPlayers()
    if lenTbl(players) > 0 then
        for player_id in pairs(players) do
            onPlayerJoin(player_id)
        end
    end

    if M.enabled then
        syncAll()
    else
        PlayerSync:send(-1, "syncDaytime", "")
    end

    print("[DayNightSync] Loaded - sync interval: " .. M.globalSyncTime .. "ms")
end

MP.RegisterEvent("onInit", "onInit")

return M
