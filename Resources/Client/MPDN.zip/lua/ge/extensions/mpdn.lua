-- =============================================================================
-- PIT Day/Night Sync - Client Core
-- Version: 5.0
-- License: AGPL-3.0 - https://www.gnu.org/licenses/agpl-3.0.html
-- Credit: rewritten from OfficialLambdax's implementation
-- =============================================================================

local M = {}

M.pinDate            = { year = 2026, month = 6, day = 20 }
M.fallbackNightStart = 0.25
M.fallbackNightEnd   = 0.75
M.snapTolerance      = 0.02
M.checkInterval      = 1.0
M.correctError       = 0.002
M.edgeWidth          = 0.02

M.phases = {
    { name = "dawn", seconds = 150 },
    { name = "day",  seconds = 900 },
    { name = "dusk", seconds = 150 },
}

local HANDLER_NAME = "dayNightSync"

local hooked     = false
local worldReady = false
local active     = false

local cycleSecs  = 1200
local progress   = nil
local playing    = true

local window     = nil
local segs       = nil
local currentSeg = nil
local checkAccum = 0

local function circDelta(a, b)
    local d = (a - b) % 1
    if d > 0.5 then d = d - 1 end
    return d
end

local function readWindow()
    local lightState = core_environment.getLightState()

    local nightStart = lightState and lightState.nightStart or M.fallbackNightStart
    local nightEnd   = lightState and lightState.nightEnd   or M.fallbackNightEnd

    local span = (nightStart - nightEnd) % 1

    if span < 1e-6 then
        nightStart = M.fallbackNightStart
        nightEnd   = M.fallbackNightEnd
        span       = (nightStart - nightEnd) % 1
    end

    return { from = nightEnd, span = span }
end

local function buildSegments()
    if not window then return nil end
    if #M.phases ~= 3 then return nil end

    local totalSeconds = 0
    for _, p in ipairs(M.phases) do
        if type(p.seconds) ~= "number" or p.seconds <= 0 then return nil end
        totalSeconds = totalSeconds + p.seconds
    end

    local span   = window.span
    local edge   = math.min(M.edgeWidth, span * 0.4)
    local widths = { edge, span - 2 * edge, edge }

    local built  = {}
    local u0, t0 = 0, 0

    for i, p in ipairs(M.phases) do
        local last = (i == #M.phases)
        local u1   = last and 1    or (u0 + p.seconds / totalSeconds)
        local t1   = last and span or (t0 + widths[i])

        built[i] = {
            name      = p.name,
            u0        = u0,
            u1        = u1,
            t0        = t0,
            t1        = t1,
            dayLength = ((u1 - u0) * cycleSecs) / (t1 - t0),
        }

        u0, t0 = u1, t1
    end

    return built
end

local function segFor(u)
    if not segs then return nil end
    u = u % 1
    for _, s in ipairs(segs) do
        if u >= s.u0 and u < s.u1 then return s end
    end
    return segs[#segs]
end

local function todTime(u)
    u = u % 1
    local s = segFor(u)
    if not s then return window.from end

    local f = (u - s.u0) / (s.u1 - s.u0)
    return (window.from + s.t0 + f * (s.t1 - s.t0)) % 1
end

local function push(seg, u)
    core_environment.setTimeOfDay({
        time      = todTime(u),
        dayLength = seg.dayLength,
        play      = playing,
    })
    checkAccum = 0
end

local function takeOver()
    if not worldReady then return end

    core_environment.setTimeOfDay({
        year  = M.pinDate.year,
        month = M.pinDate.month,
        day   = M.pinDate.day,
        play  = false,
    })

    window     = readWindow()
    segs       = buildSegments()
    currentSeg = nil
    checkAccum = 0

    if segs and progress then
        currentSeg = segFor(progress)
        push(currentSeg, progress)
    end
end

local function release()
    active     = false
    window     = nil
    segs       = nil
    currentSeg = nil
    progress   = nil
    core_environment.setTimeOfDay({ play = true })
end

local function onSync(raw_msg)
    if type(raw_msg) ~= "string" or #raw_msg == 0 then
        if active then release() end
        return
    end

    local msg = jsonDecode(raw_msg)
    if type(msg) ~= "table" then return end

    local rebuild = false

    if type(msg.cycle) == "number" and msg.cycle > 0 and msg.cycle ~= cycleSecs then
        cycleSecs = msg.cycle
        rebuild   = true
    end

    if type(msg.play) == "boolean" and msg.play ~= playing then
        playing    = msg.play
        currentSeg = nil
    end

    if type(msg.u) == "number" then
        local incoming = msg.u % 1
        if progress == nil or math.abs(circDelta(incoming, progress)) > M.snapTolerance then
            progress   = incoming
            currentSeg = nil
        end
    end

    if not active then
        active = true
        takeOver()
        return
    end

    if rebuild then
        segs       = buildSegments()
        currentSeg = nil
    end
end

M.onWorldReadyState = function(state)
    if state ~= 2 then return end
    worldReady = true

    if not hooked and AddEventHandler then
        hooked = true
        AddEventHandler("dnSync", onSync, HANDLER_NAME)
    end

    if active then takeOver() end

    if TriggerServerEvent then
        TriggerServerEvent("dnRequest", "")
    end
end

M.onClientEndMission = function()
    worldReady = false
    window     = nil
    segs       = nil
    currentSeg = nil
end

M.onUpdate = function(dtReal)
    if not active or not segs or not progress then return end

    local dt = tonumber(dtReal) or 0
    if dt < 0   then dt = 0   end
    if dt > 0.5 then dt = 0.5 end

    if playing then
        progress = (progress + dt / cycleSecs) % 1
    end

    local seg = segFor(progress)
    if not seg then return end

    if seg ~= currentSeg then
        currentSeg = seg
        push(seg, progress)
        return
    end

    checkAccum = checkAccum + dt
    if checkAccum < M.checkInterval then return end
    checkAccum = 0

    local s = core_environment.getTimeOfDay()
    if not s or type(s.time) ~= "number" then return end

    if math.abs(circDelta(todTime(progress), s.time)) > M.correctError
        or (s.play == true) ~= playing then
        push(seg, progress)
    end
end

M.onExtensionUnloaded = function()
    if active then release() end

    if hooked and RemoveEventHandler then
        RemoveEventHandler("dnSync", HANDLER_NAME)
        hooked = false
    end
end

M.status = function()
    if not active then return "DayNightSync: inactive" end
    if not segs   then return "DayNightSync: active, no segments" end

    local s   = core_environment.getTimeOfDay()
    local ls  = core_environment.getLightState()
    local seg = segFor(progress or 0)
    local tgt = todTime(progress or 0)

    return string.format(
        "u=%.4f phase=%s target=%.5f engine=%.5f err=%.5f dayLength=%.0f span=%.4f cycle=%ds light=%s",
        progress or -1,
        seg and seg.name or "?",
        tgt,
        s and s.time or -1,
        s and circDelta(tgt, s.time) or -1,
        seg and seg.dayLength or -1,
        window and window.span or -1,
        cycleSecs,
        ls and ls.phase or "?")
end

return M
