-- =============================================================================
-- PIT Day/Night Sync - Server Core
-- Version: 5.0
-- License: AGPL-3.0 - https://www.gnu.org/licenses/agpl-3.0.html
-- Credit: rewritten from OfficialLambdax's implementation
-- =============================================================================

local M = {}

M.enabled           = true
M.cycleSeconds      = 1200
M.tickIntervalMs    = 1000
M.broadcastMs       = 5000
M.progressWhenEmpty = true
M.startProgress     = 0.0
M.resetWhenEmpty    = true

local progress  = M.startProgress
local playing   = true
local tickTimer = nil
local sinceSync = 0

local function sendTo(player_id)
    if not M.enabled then
        MP.TriggerClientEvent(player_id, "dnSync", "")
        return
    end

    MP.TriggerClientEventJson(player_id, "dnSync", {
        u     = progress,
        play  = playing,
        cycle = M.cycleSeconds,
    })
end

function dnTick()
    local dt = tickTimer:GetCurrent()
    tickTimer:Start()

    if not M.enabled then return end

    if MP.GetPlayerCount() == 0 then
        if M.resetWhenEmpty then progress = M.startProgress end
        if not M.progressWhenEmpty then return end
    end

    if playing then
        progress = (progress + dt / M.cycleSeconds) % 1
    end

    sinceSync = sinceSync + dt * 1000
    if sinceSync >= M.broadcastMs then
        sinceSync = 0
        sendTo(-1)
    end
end

function dnPlayerJoin(player_id)
    sendTo(player_id)
end

function dnOnRequest(player_id)
    sendTo(player_id)
end

function dnConsole(cmd)
    local verb, arg = cmd:match("^dn%s+(%S+)%s*(.*)$")
    if not verb then return end

    if verb == "status" then
        return string.format("progress=%.4f play=%s cycle=%ds players=%d",
            progress, tostring(playing), M.cycleSeconds, MP.GetPlayerCount())

    elseif verb == "pause" then
        playing = false
        sendTo(-1)
        return "clock paused"

    elseif verb == "resume" then
        playing = true
        sendTo(-1)
        return "clock resumed"

    elseif verb == "set" then
        local value = tonumber(arg)
        if not value then return "usage: dn set <0..1>" end
        progress = value % 1
        sendTo(-1)
        return string.format("progress = %.4f", progress)

    elseif verb == "cycle" then
        local value = tonumber(arg)
        if not value or value <= 0 then return "usage: dn cycle <seconds>" end
        M.cycleSeconds = value
        sendTo(-1)
        return string.format("cycle = %ds", M.cycleSeconds)
    end

    return "dn: status | pause | resume | set <0..1> | cycle <seconds>"
end

function onInit()
    tickTimer = MP.CreateTimer()

    MP.RegisterEvent("onPlayerJoin", "dnPlayerJoin")
    MP.RegisterEvent("dnRequest",    "dnOnRequest")
    MP.RegisterEvent("dnTickEvent",  "dnTick")

    MP.CancelEventTimer("dnTickEvent")
    MP.CreateEventTimer("dnTickEvent", M.tickIntervalMs)

    for player_id in pairs(MP.GetPlayers()) do
        sendTo(player_id)
    end

    Util.LogInfo(string.format(
        "DayNightSync: cycle %ds | tick %dms | broadcast %dms | enabled=%s",
        M.cycleSeconds, M.tickIntervalMs, M.broadcastMs, tostring(M.enabled)))
end

MP.RegisterEvent("onInit",         "onInit")
MP.RegisterEvent("onConsoleInput", "dnConsole")

return M
