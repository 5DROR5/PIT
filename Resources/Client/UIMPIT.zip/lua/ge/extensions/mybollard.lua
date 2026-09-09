-- =============================================================================
-- PIT Economy System - mybollard Extension
-- License: AGPL-3.0 - https://www.gnu.org/licenses/agpl-3.0.html
-- =============================================================================

local M = {}

local bollard_list  = {}
local groups        = {}
local hit_timers    = {}
local spawn_counter = 0
local debug_mode    = false
local MAX_GROUPS    = 5
local MIN_DIST_M    = 500

local mission_active    = false
local pending_start     = false
local cooldown_s        = 0
local in_wl40           = false
local is_first_spawn    = false
local mission_spawn_pos = nil

local undo_timer            = 0
local UNDO_DURATION         = 10.0
local last_confirmed_count  = 0

local wl40_check_timer    = 0
local WL40_CHECK_INTERVAL = 1.0

local events_ok   = false
local retry_timer = 0

-- =============================================================================
-- UTILITIES
-- =============================================================================

M.toggleDebug = function() debug_mode = not debug_mode end

local function decodePayload(p)
    if type(p) == "table" then return p end
    if type(p) ~= "string" then return {} end
    local ok, t = pcall(jsonDecode, p)
    return (ok and type(t) == "table") and t or {}
end

-- =============================================================================
-- WL40 DETECTION
-- =============================================================================

local function checkWl40Visibility()
    local veh = be:getPlayerVehicle(0)
    local new_state = false
    if veh then
        local vd = extensions.core_vehicle_manager and
                   extensions.core_vehicle_manager.getVehicleData(veh:getID())
        if vd and vd.config and vd.config.partConfigFilename then
            local series = vd.config.partConfigFilename:match("vehicles/([^/]+)/") or ""
            new_state = (series:lower() == "wl40")
        end
    end
    if new_state ~= in_wl40 then
        in_wl40 = new_state
        if not in_wl40 then
            mission_active  = false
            pending_start   = false
        end
    end
    guihooks.trigger("BollardVisible", { visible = in_wl40 })
end

-- =============================================================================
-- BOLLARD SPAWN/REMOVE
-- =============================================================================

local function removeGroup(group)
    for _, b in ipairs(group) do
        local obj = scenetree.findObjectById(b.obj_id)
        if obj then obj:delete() end
        for i = #bollard_list, 1, -1 do
            if bollard_list[i] == b then table.remove(bollard_list, i); break end
        end
    end
end

local function spawnGroupAt(bx, by, dir_x, dir_y, pz_mid, skip_dist_check)
    if not skip_dist_check then
        if not is_first_spawn and #groups > 0 then
            local last = groups[#groups]
            for _, b in ipairs(last) do
                if not b.is_light and (vec3(bx, by, b.pos.z) - b.pos):length() < MIN_DIST_M then
                    return false, "too_close"
                end
            end
        end
        is_first_spawn = false
    end
    loadJsonMaterialsFile("art/shapes/pwu/signs/materials.json")
    local sx, group = -dir_y, {}
    for i = 0, 4 do
        local dist = math.abs(i - 2)
        local px   = bx + sx * (i - 2)
        local py   = by + dir_x * (i - 2)
        local pz   = be:getSurfaceHeightBelow(vec3(px, py, pz_mid + 50))
        local obj  = createObject("TSStatic")
        obj.shapeName = "art/shapes/pwu/signs/bollard.cdae"
        obj.dynamic = true; obj.useInstanceRenderData = 1
        obj.instanceColor = Point4F(0, 0, 0, 1); obj.scale = vec3(3, 3, 3)
        obj:setPosRot(px, py, pz - 2, 0, 0, 0, 1)
        obj:registerObject("boll_" .. spawn_counter .. "_" .. i)
        local entry = {
            obj = obj, obj_id = obj:getId(), pos = vec3(px, py, pz),
            check_points = { vec3(px,py,pz+0.3), vec3(px,py,pz+1.5), vec3(px,py,pz+2.7) },
            target_z = pz, done = false,
            delay = (2-dist)*0.3, delay_timer = 0,
            rise_speed = 1+dist*0.3, is_light = false,
        }
        table.insert(bollard_list, entry); table.insert(group, entry)
    end
    for _, side in ipairs({ 2.5, -2.5 }) do
        local light = createObject("PointLight")
        light:setPosition(vec3(bx + dir_x*side, by + dir_y*side, pz_mid))
        light.radius = 5
        light:registerObject("boll_light_" .. spawn_counter .. "_" .. (side > 0 and "f" or "b"))
        table.insert(group, { obj=light, obj_id=light:getId(), pos=vec3(0,0,0),
            check_points={}, target_z=0, done=true, delay=0, delay_timer=0, rise_speed=1, is_light=true })
    end
    table.insert(groups, group)
    if #groups > MAX_GROUPS then removeGroup(table.remove(groups, 1)) end
    spawn_counter = spawn_counter + 1
    return true
end

local function doSpawn()
    local v = be:getPlayerVehicle(0)
    if not v then return end
    local vel = v:getVelocity()
    if math.sqrt(vel.x*vel.x + vel.y*vel.y) * 3.6 >= 5 then
        guihooks.trigger("BollardStatus", { error = "too_fast" }); return
    end
    local dir    = v:getDirectionVector()
    local c      = v:getSpawnWorldOOBB():getCenter()
    local half   = v:getSpawnWorldOOBB():getHalfExtents()
    local roff   = math.max(half.x, half.y) + 2
    local bx     = c.x - dir.x * roff
    local by     = c.y - dir.y * roff
    local pz_mid = be:getSurfaceHeightBelow(vec3(bx, by, c.z))
    local ok, reason = spawnGroupAt(bx, by, dir.x, dir.y, pz_mid, false)
    if not ok then guihooks.trigger("BollardStatus", { error = reason }); return end
    if type(TriggerServerEvent) == "function" then
        TriggerServerEvent("BLOCKER_BlockadePlaced", jsonEncode({
            x=bx, y=by, z=pz_mid, dir_x=dir.x, dir_y=dir.y,
        }))
    end
end

M.spawn = function()
    if not in_wl40 then return end
    if cooldown_s > 0 then
        guihooks.trigger("BollardStatus", { error="cooldown", remaining=math.ceil(cooldown_s) }); return
    end
    if not mission_active then
        if pending_start then return end
        pending_start = true
        guihooks.trigger("BollardStatus", { status="requesting" })
        if type(TriggerServerEvent) == "function" then TriggerServerEvent("BLOCKER_RequestStart", "") end
        return
    end
    doSpawn()
end

M.undoLastBlockade = function()
    if undo_timer <= 0 or #groups == 0 then return end
    undo_timer = 0
    guihooks.trigger("BollardUndoUpdate", { active=false, remaining=0, total=UNDO_DURATION })
    removeGroup(table.remove(groups, #groups))
    if #groups == 0 then is_first_spawn = true end
    if type(TriggerServerEvent) == "function" then TriggerServerEvent("BLOCKER_UndoBlockade", "") end
end

M.clear = function()
    for _, g in ipairs(groups) do removeGroup(g) end
    bollard_list = {}; hit_timers = {}; groups = {}
end

-- =============================================================================
-- SERVER EVENT HANDLERS
-- =============================================================================

local function onMissionStart(payload)
    local data            = decodePayload(payload)
    mission_active        = true
    pending_start         = false
    is_first_spawn        = true
    last_confirmed_count  = 0
    mission_spawn_pos     = data.spawn_x and vec3(data.spawn_x, data.spawn_y, data.spawn_z) or nil
    guihooks.trigger("BollardMissionUpdate", {
        active=true, blockade_count=data.blockade_count or 0,
        pending_money=data.pending_money or 0, required=data.required or 5,
        initial_repairs=data.initial_repairs or 2,
    })
end

local function onMissionEnd(payload)
    local data              = decodePayload(payload)
    mission_active          = false
    pending_start           = false
    mission_spawn_pos       = nil
    undo_timer              = 0
    last_confirmed_count    = 0
    guihooks.trigger("BollardMissionUpdate", { active=false, success=data.success })
    guihooks.trigger("BollardStopTimer",     { active=false, elapsed=0, limit=14 })
    guihooks.trigger("BollardUndoUpdate",    { active=false, remaining=0, total=UNDO_DURATION })
end

local function onMissionUpdate(payload)
    local data      = decodePayload(payload)
    local new_count = data.blockade_count or 0
    if new_count > last_confirmed_count then
        undo_timer = UNDO_DURATION
        guihooks.trigger("BollardUndoUpdate", { active=true, remaining=UNDO_DURATION, total=UNDO_DURATION })
    end
    last_confirmed_count = new_count
    guihooks.trigger("BollardMissionUpdate", {
        active=true, blockade_count=new_count,
        pending_money=data.pending_money or 0, required=data.required or 5,
    })
end

local function onStartDenied(payload)
    pending_start = false
    guihooks.trigger("BollardStatus", { error = decodePayload(payload).reason or "denied" })
end

local function onNewBlockade(payload)
    local data = decodePayload(payload)
    if not data.x then return end
    local pz = be:getSurfaceHeightBelow(vec3(data.x, data.y, 1000))
    spawnGroupAt(data.x, data.y, tonumber(data.dir_x) or 0, tonumber(data.dir_y) or 0, pz, true)
end

local function onSyncBlockades(payload)
    local data = decodePayload(payload)
    if type(data.blockades) ~= "table" then return end
    for _, b in ipairs(data.blockades) do
        if b.x then
            local pz = be:getSurfaceHeightBelow(vec3(b.x, b.y, 1000))
            spawnGroupAt(b.x, b.y, tonumber(b.dir_x) or 0, tonumber(b.dir_y) or 0, pz, true)
        end
    end
end

local function onUndoFromServer()
    if #groups == 0 then return end
    removeGroup(table.remove(groups, #groups))
end

local function onBlockadeDenied(payload)
    guihooks.trigger("BollardStatus", { error = decodePayload(payload).reason or "denied" })
    if #groups > 0 then removeGroup(table.remove(groups, #groups)) end
    undo_timer = 0
    guihooks.trigger("BollardUndoUpdate", { active=false, remaining=0, total=UNDO_DURATION })
    if #groups == 0 and mission_active then is_first_spawn = true end
end

local function onStopTimer(payload)
    local data = decodePayload(payload)
    guihooks.trigger("BollardStopTimer", { active=data.active or false, elapsed=data.elapsed or 0, limit=data.limit or 14 })
end

local function onServerCooldown(payload)
    cooldown_s = tonumber(decodePayload(payload).cooldown_seconds) or 0
    guihooks.trigger("BollardServerCooldown", { cooldown_seconds = cooldown_s })
end

-- =============================================================================
-- EVENT REGISTRATION
-- =============================================================================

local function tryRegisterEvents()
    if events_ok or type(AddEventHandler) ~= "function" then return end
    AddEventHandler("BLOCKER_MissionStart",    onMissionStart)
    AddEventHandler("BLOCKER_MissionEnd",      onMissionEnd)
    AddEventHandler("BLOCKER_MissionUpdate",   onMissionUpdate)
    AddEventHandler("BLOCKER_StartDenied",     onStartDenied)
    AddEventHandler("BLOCKER_BlockadeDenied",  onBlockadeDenied)
    AddEventHandler("BLOCKER_NewBlockade",     onNewBlockade)
    AddEventHandler("BLOCKER_SyncBlockades",   onSyncBlockades)
    AddEventHandler("BLOCKER_UndoLastBlockade",onUndoFromServer)
    AddEventHandler("BLOCKER_StopTimer",       onStopTimer)
    AddEventHandler("BLOCKER_ServerCooldown",  onServerCooldown)
    events_ok = true
end

-- =============================================================================
-- LIFECYCLE
-- =============================================================================

M.onExtensionLoaded = function()
    tryRegisterEvents()
    checkWl40Visibility()
end

M.onPreRender = function(dt)
    if not events_ok then
        retry_timer = retry_timer + dt
        if retry_timer >= 1.0 then retry_timer = 0; tryRegisterEvents() end
    end

    wl40_check_timer = wl40_check_timer + dt
    if wl40_check_timer >= WL40_CHECK_INTERVAL then
        wl40_check_timer = 0; checkWl40Visibility()
    end

    if cooldown_s > 0 then
        cooldown_s = math.max(0, cooldown_s - dt)
        if cooldown_s == 0 then guihooks.trigger("BollardServerCooldown", { cooldown_seconds=0 }) end
    end

    if undo_timer > 0 then
        undo_timer = math.max(0, undo_timer - dt)
        if undo_timer == 0 then
            guihooks.trigger("BollardUndoUpdate", { active=false, remaining=0, total=UNDO_DURATION })
        else
            guihooks.trigger("BollardUndoUpdate", { active=true, remaining=undo_timer, total=UNDO_DURATION })
        end
    end

    if in_wl40 then
        local v   = be:getPlayerVehicle(0)
        local spd = 0
        if v then
            local vel = v:getVelocity()
            spd = math.floor(math.sqrt(vel.x*vel.x + vel.y*vel.y) * 3.6)
        end

        if v and mission_active and is_first_spawn and mission_spawn_pos then
            local d = math.floor((v:getPosition() - mission_spawn_pos):length())
            guihooks.trigger("BollardUpdate", {
                distance  = d,
                can_spawn = cooldown_s <= 0 and d >= MIN_DIST_M,
                speed     = spd,
            })
        elseif v and #groups > 0 then
            local vpos, last_g, min_d = v:getPosition(), groups[#groups], math.huge
            for _, b in ipairs(last_g) do
                if not b.is_light then
                    local d = (vpos - b.pos):length()
                    if d < min_d then min_d = d end
                end
            end
            guihooks.trigger("BollardUpdate", {
                distance  = math.floor(min_d),
                can_spawn = mission_active and cooldown_s <= 0 and min_d >= MIN_DIST_M,
                speed     = spd,
            })
        else
            guihooks.trigger("BollardUpdate", {
                distance  = -1,
                can_spawn = not mission_active and cooldown_s <= 0,
                speed     = spd,
            })
        end
    end

    for _, b in ipairs(bollard_list) do
        if not b.done and not b.is_light then
            if b.delay_timer < b.delay then
                b.delay_timer = b.delay_timer + dt
            else
                local pos = b.obj:getPosition()
                pos.z = math.min(pos.z + b.rise_speed * dt, b.target_z)
                b.obj:setPosition(pos)
                if pos.z >= b.target_z then b.done = true end
            end
        end
    end

    for _, vehicle in ipairs(getAllVehicles()) do
        if vehicle then
            local oobb = vehicle:getSpawnWorldOOBB()
            if debug_mode then debugDrawer:drawBox(oobb:getCenter(), oobb:getHalfExtents(), ColorF(0,1,0,1)) end
            for _, b in ipairs(bollard_list) do
                if b.done and not b.is_light then
                    local hit = false
                    for _, p in ipairs(b.check_points) do
                        if debug_mode then debugDrawer:drawSphere(p, 0.3, ColorF(1,0,0,1)) end
                        if oobb:isContained(p) then hit = true; break end
                    end
                    if hit then
                        local vid = vehicle:getId()
                        local now = Engine.Platform.getRuntime()
                        local vel = vehicle:getVelocity()
                        local spd = math.sqrt(vel.x*vel.x + vel.y*vel.y + vel.z*vel.z)
                        local cooldown = spd < 0.1 and 0.0 or 0.2
                        if not hit_timers[vid] or (now - hit_timers[vid]) > cooldown then
                            hit_timers[vid] = now
                            local push = (vehicle:getPosition() - b.pos):normalized()
                            if spd < 0.1 then
                                vehicle:applyClusterVelocityScaleAdd(vehicle:getRefNodeId(), 1, push.x*2, push.y*2, push.z*2)
                            elseif spd < 1.0 then
                                vehicle:applyClusterVelocityScaleAdd(vehicle:getRefNodeId(), 0.0, -vel.x, -vel.y, -vel.z)
                            else
                                vehicle:applyClusterVelocityScaleAdd(vehicle:getRefNodeId(), 0.3, -vel.x*0.7, -vel.y*0.7, -vel.z*0.7)
                            end
                        end
                    end
                end
            end
        end
    end
end

M.onExtensionUnloaded = function()
    M.clear(); events_ok = false; in_wl40 = false
end

return M