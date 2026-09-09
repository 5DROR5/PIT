-- =============================================================================
-- PIT Economy System - PowerUps Client Extension
-- License: AGPL-3.0
-- =============================================================================

local M = {}

local PLUGIN              = "[PowerUpsClient]"
local SPIKE_DISTANCE_M    = 8
local BANANA_DISTANCE_M   = 7
local WIRE_OPEN_SPEED     = 1.5
local WIRE_TARGET_SIZE    = 1.5
local WIRE_Z_OFFSET       = 0.3
local BANANA_Z_OFFSET     = 0.3
local CANNON_PROJ_SPEED   = 120
local CANNON_LIFETIME_S   = 2.5
local CANNON_HIT_RADIUS   = 3
local CANNON_SEMICIRCLE_R = 150
local CANNON_OFFSET       = 2

M.cannonTuning = { push = 12, lift = 3 }

local _cannon_fire_time = -math.huge

local active_spikes     = {}
local active_bananas    = {}
local active_cannons    = {}
local powerup_inventory = {}
local cannon_counter    = 0

-- =============================================================================
-- MATH UTILS
-- =============================================================================

local function getPosInFront(pos, dir, dist)
    return pos + dir:normalized() * dist
end

local function getVehiclesInsideRadius(pos, radius, exclude_id)
    local result = {}
    for _, veh in ipairs(getAllVehicles()) do
        local id = veh:getId()
        if id ~= exclude_id and (veh:getPosition() - pos):length() < radius then
            table.insert(result, id)
        end
    end
    return result
end

local function getVehiclesInSemicircle(veh_pos, start_pos, forward, radius, exclude_id)
    local found = {}
    for _, veh in ipairs(getAllVehicles()) do
        local id = veh:getId()
        if id ~= exclude_id then
            local to_target  = veh:getPosition() - veh_pos
            local dist_start = (veh:getPosition() - start_pos):length()
            if to_target:dot(forward) > 0 and dist_start <= radius then
                table.insert(found, { id = id, dist = to_target:length() })
            end
        end
    end
    table.sort(found, function(a, b) return a.dist < b.dist end)
    local ids = {}
    for _, r in ipairs(found) do table.insert(ids, r.id) end
    return ids
end

local function getCollisionsAlongLine(from, to, radius, exclude_id)
    local dist = (to - from):length()
    local dir  = (to - from):normalized()
    local pos  = from
    while true do
        local hits = getVehiclesInsideRadius(pos, radius, exclude_id)
        if #hits > 0 then return hits end
        pos = pos + dir * radius
        if (pos - to):length() > dist then break end
    end
    return getVehiclesInsideRadius(to, radius, exclude_id)
end

local function getPredictedPosition(origin_veh, target_veh, proj_speed)
    local org = origin_veh:getPosition()
    local tar = target_veh:getPosition()
    local vel = target_veh:getVelocity()
    local t   = (tar - org):length() / proj_speed
    return tar + vel * t
end

-- =============================================================================
-- INTERNAL
-- =============================================================================

local function logI(msg) print(PLUGIN .. " " .. tostring(msg)) end

local function guiTrigger(event, data)
    if type(guihooks) == "table" and type(guihooks.trigger) == "function" then
        guihooks.trigger(event, data)
    end
end

local function decodePayload(payload)
    if type(payload) == "string" then
        local ok, t = pcall(jsonDecode, payload)
        return ok and t or nil
    end
    return payload
end

local function safeRemove(obj)
    if not obj then return end
    pcall(function() obj:delete() end)
end

local function deleteSpike(spike)
    if not spike then return end
    safeRemove(spike.wire)
    safeRemove(spike.sign1)
    safeRemove(spike.sign2)
end

local function deleteBanana(banana) if not banana then return end safeRemove(banana.peel) end
local function deleteCannon(cannon) if not cannon then return end safeRemove(cannon.ball) end

local function removeSpikeById(spike_id)   deleteSpike(active_spikes[spike_id])    active_spikes[spike_id]   = nil end
local function removeBananaById(banana_id) deleteBanana(active_bananas[banana_id]) active_bananas[banana_id] = nil end
local function removeCannonById(cannon_id) deleteCannon(active_cannons[cannon_id]) active_cannons[cannon_id] = nil end

local function buildSpikeCheckPoints(x, y, z, dx, dy)
    local px  = -dy
    local py  =  dx
    local pts = {}
    for _, t in ipairs({ -5, -2.5, 0, 2.5, 5 }) do
        table.insert(pts, vec3(x + px * t, y + py * t, z + 0.4))
        table.insert(pts, vec3(x + px * t, y + py * t, z + 1.1))
    end
    return pts
end

local function buildBananaCheckPoints(x, y, z)
    return {
        vec3(x, y, z + 0.3),
        vec3(x, y, z + 0.8),
        vec3(x, y, z + 1.4),
    }
end

local function placeSpike(spike_id, x, y, z_hint, dx, dy, expires_at)
    if active_spikes[spike_id] then return end
    loadJsonMaterialsFile("art/shapes/pwu/signs/materials.json")

    local surface_z = be:getSurfaceHeightBelow(vec3(x, y, z_hint + 50))
    local z         = surface_z + WIRE_Z_OFFSET
    local wire_rot  = quatFromDir(vec3(0, 0, 1), vec3(dx, dy, 0))
    local rx        = -dy; local ry = dx
    local sign_rot1 = quatFromDir(vec3( rx,  ry, 0), vec3(0, 0, 1))
    local sign_rot2 = quatFromDir(vec3(-rx, -ry, 0), vec3(0, 0, 1))
    local sign_z    = z + 3

    local wire = createObject("TSStatic")
    wire.shapeName = "art/shapes/pwu/signs/barbedwire_2.cdae"
    wire:setPosRot(x, y, z, wire_rot.x, wire_rot.y, wire_rot.z, wire_rot.w)
    wire.scale = vec3(0, 1, 1)
    wire:registerObject("spk_wire_" .. spike_id)

    local sign1 = createObject("TSStatic")
    sign1.shapeName = "art/shapes/pwu/signs/road_spikes.cdae"
    sign1:setPosRot(x, y, sign_z, sign_rot1.x, sign_rot1.y, sign_rot1.z, sign_rot1.w)
    sign1.scale = vec3(2, 2, 2); sign1:setHidden(true)
    sign1:registerObject("spk_sign1_" .. spike_id)

    local sign2 = createObject("TSStatic")
    sign2.shapeName = "art/shapes/pwu/signs/road_spikes.cdae"
    sign2:setPosRot(x, y, sign_z, sign_rot2.x, sign_rot2.y, sign_rot2.z, sign_rot2.w)
    sign2.scale = vec3(2, 2, 2); sign2:setHidden(true)
    sign2:registerObject("spk_sign2_" .. spike_id)

    active_spikes[spike_id] = {
        wire         = wire, sign1 = sign1, sign2 = sign2,
        pos          = vec3(x, y, z),
        check_points = buildSpikeCheckPoints(x, y, z, dx, dy),
        expires_at   = expires_at,
        triggered    = false,
        fully_open   = false,
    }
end

local function placeBanana(banana_id, x, y, z_hint, expires_at)
    if active_bananas[banana_id] then return end
    loadJsonMaterialsFile("art/shapes/pwu/signs/materials.json")

    local surface_z = be:getSurfaceHeightBelow(vec3(x, y, z_hint + 50))
    local z         = surface_z + BANANA_Z_OFFSET

    local peel = createObject("TSStatic")
    peel.shapeName = "art/shapes/pwu/signs/banana_peel.cdae"
    peel:setPosRot(x, y, z, 0, 0, 0, 1)
    peel.scale = vec3(8, 8, 8)
    peel:registerObject("ban_peel_" .. banana_id)

    active_bananas[banana_id] = {
        peel         = peel,
        pos          = vec3(x, y, z),
        check_points = buildBananaCheckPoints(x, y, z),
        expires_at   = expires_at,
        triggered    = false,
    }
end

-- =============================================================================
-- PUBLIC
-- =============================================================================

M.onSpikesDeploy = function(payload)
    local data = decodePayload(payload)
    if not data or not data.spike_id then return end
    local veh = be:getPlayerVehicle(0)
    if not veh then return end
    local oobb        = veh:getSpawnWorldOOBB()
    local center      = oobb:getCenter()
    local dir         = veh:getDirectionVector()
    local half        = oobb:getHalfExtents()
    local rear_offset = math.max(half.x, half.y) + SPIKE_DISTANCE_M
    local x = center.x - dir.x * rear_offset
    local y = center.y - dir.y * rear_offset
    placeSpike(data.spike_id, x, y, center.z, dir.x, dir.y, data.expires_at)
    if type(TriggerServerEvent) == "function" then
        TriggerServerEvent("POWERUP_SpikesPosition", jsonEncode({
            spike_id = data.spike_id, x = x, y = y, z = center.z, dx = dir.x, dy = dir.y,
        }))
    end
end

M.onSpikesPlaced = function(payload)
    local data = decodePayload(payload)
    if data and data.spike_id then
        placeSpike(data.spike_id, data.x, data.y, data.z, data.dx, data.dy, data.expires_at)
    end
end

M.onSpikesRemoved = function(payload)
    local data = decodePayload(payload)
    if data and data.spike_id then removeSpikeById(data.spike_id) end
end

M.onBananaDeploy = function(payload)
    local data = decodePayload(payload)
    if not data or not data.banana_id then return end
    local veh = be:getPlayerVehicle(0)
    if not veh then return end
    local oobb        = veh:getSpawnWorldOOBB()
    local center      = oobb:getCenter()
    local dir         = veh:getDirectionVector()
    local half        = oobb:getHalfExtents()
    local rear_offset = math.max(half.x, half.y) + BANANA_DISTANCE_M
    local x = center.x - dir.x * rear_offset
    local y = center.y - dir.y * rear_offset
    placeBanana(data.banana_id, x, y, center.z, data.expires_at)
    if type(TriggerServerEvent) == "function" then
        TriggerServerEvent("POWERUP_BananaPosition", jsonEncode({
            banana_id = data.banana_id, x = x, y = y, z = center.z,
        }))
    end
end

M.onBananaPlaced = function(payload)
    local data = decodePayload(payload)
    if data and data.banana_id then
        placeBanana(data.banana_id, data.x, data.y, data.z, data.expires_at)
    end
end

M.onBananaRemoved = function(payload)
    local data = decodePayload(payload)
    if data and data.banana_id then removeBananaById(data.banana_id) end
end

M.onCannonFire = function(payload)
    local now = os.clock()
    if now - _cannon_fire_time < 0.5 then return end
    _cannon_fire_time = now

    local data = decodePayload(payload)
    if not data then return end

    loadJsonMaterialsFile("art/shapes/pwu/signs/materials.json")

    local veh = be:getPlayerVehicle(0)
    if not veh then return end

    local veh_dir   = veh:getDirectionVector()
    local veh_pos   = veh:getPosition()
    veh_pos.z       = veh_pos.z + 0.5
    local start_pos = getPosInFront(veh_pos, veh_dir, CANNON_OFFSET)

    local targets   = getVehiclesInSemicircle(veh_pos, start_pos, veh_dir, CANNON_SEMICIRCLE_R, veh:getId())
    local shoot_dir = veh_dir
    if #targets > 0 then
        local target_veh = getObjectByID(targets[1])
        if target_veh then
            local pred = getPredictedPosition(veh, target_veh, CANNON_PROJ_SPEED)
            shoot_dir  = (pred - veh_pos):normalized()
        end
    end

    veh:applyClusterVelocityScaleAdd(veh:getRefNodeId(), 1,
        -shoot_dir.x * 5, -shoot_dir.y * 5, 0)

    pcall(function()
        Engine.Audio.playOnce('AudioMaster',
            'art/shapes/pwu/signs/cannon_light.ogg', { volume = 3, channel = 'Other' })
    end)

    local ball = createObject("TSStatic")
    ball.shapeName = "art/shapes/pwu/signs/cannonball.cdae"
    ball:setPosRot(start_pos.x, start_pos.y, start_pos.z, 0, 0, 0, 1)
    ball.scale = vec3(2.5, 2.5, 2.5)

    cannon_counter = cannon_counter + 1
    local cannon_id = "can_" .. tostring(os.clock()) .. "_" .. tostring(cannon_counter)
    ball:registerObject("can_ball_" .. cannon_id)

    active_cannons[cannon_id] = {
        ball      = ball,
        pos       = start_pos,
        dir       = shoot_dir,
        owner_id  = veh:getId(),
        lifetime  = 0,
        traveled  = 0,
        triggered = false,
    }

    if type(TriggerServerEvent) == "function" then
        TriggerServerEvent("POWERUP_CannonBallLaunched", jsonEncode({
            cannon_id = cannon_id,
            owner_id  = veh:getId(),
            x = start_pos.x, y = start_pos.y, z = start_pos.z,
            dir_x = shoot_dir.x, dir_y = shoot_dir.y, dir_z = shoot_dir.z,
        }))
    end
end

M.onCannonBallLaunched = function(payload)
    local data = decodePayload(payload)
    if not data or not data.cannon_id then return end
    local local_veh = be:getPlayerVehicle(0)
    if local_veh and local_veh:getId() == data.owner_id then return end
    if active_cannons[data.cannon_id] then return end

    loadJsonMaterialsFile("art/shapes/pwu/signs/materials.json")
    local start_pos = vec3(data.x, data.y, data.z)
    local dir       = vec3(data.dir_x, data.dir_y, data.dir_z)

    local ball = createObject("TSStatic")
    ball.shapeName = "art/shapes/pwu/signs/cannonball.cdae"
    ball:setPosRot(start_pos.x, start_pos.y, start_pos.z, 0, 0, 0, 1)
    ball.scale = vec3(2.5, 2.5, 2.5)
    ball:registerObject("can_ball_" .. data.cannon_id)

    active_cannons[data.cannon_id] = {
        ball      = ball,
        pos       = start_pos,
        dir       = dir,
        owner_id  = data.owner_id,
        lifetime  = 0,
        traveled  = 0,
        triggered = false,
    }
end

M.onCannonHit = function(payload)
    local data = decodePayload(payload)
    if not data or not data.cannon_id then return end
    removeCannonById(data.cannon_id)
end

M.onInventoryUpdate = function(payload)
    local data = decodePayload(payload)
    if type(data) == "table" and data.inventory then
        powerup_inventory = data.inventory
        guiTrigger("POWERUP_InventoryUpdate", powerup_inventory)
    end
end

M.onCopInventories = function(cop_powerups)
    guiTrigger("POWERUP_CopInventories", cop_powerups)
end

M.getActiveSpikes   = function() return active_spikes   end
M.getActiveBananas  = function() return active_bananas  end
M.getActiveCannons  = function() return active_cannons  end

M.triggerAction = function(action)
    if     action == 'home'        then if type(TriggerServerEvent) == "function" then TriggerServerEvent("requestHomeButton",   "home")   end
    elseif action == 'spawn2'      then _G.requestOptionalSpawn(1)
    elseif action == 'spawn3'      then _G.requestOptionalSpawn(2)
    elseif action == 'spawn4'      then _G.requestOptionalSpawn(3)
    elseif action == 'repair'      then if type(TriggerServerEvent) == "function" then TriggerServerEvent("requestVehicleRepair","repair") end
    elseif action == 'spike_strip' then _G.activateSpikeStrip()
    elseif action == 'banana'      then _G.activateBanana()
    elseif action == 'cannon'      then _G.activateCannon()
    elseif action == 'nav_toggle'  then _G.toggleMarkerNavigation()
    end
end

M.cleanup = function()
    for id in pairs(active_spikes)  do removeSpikeById(id)  end
    for id in pairs(active_bananas) do removeBananaById(id) end
    for id in pairs(active_cannons) do removeCannonById(id) end
    powerup_inventory = {}
end

-- =============================================================================
-- EXTENSION LIFECYCLE
-- =============================================================================

M.onPreRender = function(dt)
    for _, spike in pairs(active_spikes) do
        if not spike.fully_open then
            local scale = spike.wire:getScale()
            scale.x = scale.x + WIRE_OPEN_SPEED * dt
            if scale.x >= WIRE_TARGET_SIZE then
                scale.x          = WIRE_TARGET_SIZE
                spike.fully_open = true
                pcall(function() spike.sign1:setHidden(false) end)
                pcall(function() spike.sign2:setHidden(false) end)
            end
            pcall(function() spike.wire:setScale(scale) end)
        end
    end

    if next(active_cannons) then
        local to_remove = {}
        for cannon_id, cannon in pairs(active_cannons) do
            cannon.lifetime = cannon.lifetime + dt
            if cannon.lifetime >= CANNON_LIFETIME_S then
                table.insert(to_remove, cannon_id)
            else
                local step    = CANNON_PROJ_SPEED * dt
                local new_pos = getPosInFront(cannon.pos, cannon.dir, step)
                cannon.traveled = cannon.traveled + step
                pcall(function() cannon.ball:setPosition(new_pos) end)

                if not cannon.triggered and cannon.traveled > CANNON_HIT_RADIUS then
                    local local_veh = be:getPlayerVehicle(0)
                    if local_veh and local_veh:getId() ~= cannon.owner_id then
                        local veh_pos   = local_veh:getPosition()
                        local from_dist = (cannon.pos - veh_pos):length()
                        local to_dist   = (new_pos    - veh_pos):length()
                        if from_dist <= CANNON_HIT_RADIUS or to_dist <= CANNON_HIT_RADIUS then
                            cannon.triggered = true
                            local push  = cannon.dir:normalized() * M.cannonTuning.push
                            local total = vec3(push.x, push.y, push.z + M.cannonTuning.lift)
                            local_veh:applyClusterVelocityScaleAdd(local_veh:getRefNodeId(), 1, total.x, total.y, total.z)
                            pcall(function()
                                Engine.Audio.playOnce('AudioMaster',
                                    'art/shapes/pwu/signs/hit.ogg', { volume = 6, channel = 'Other' })
                            end)
                            pcall(function() cannon.ball:setScale(vec3(0, 0, 0)) end)
                            if type(TriggerServerEvent) == "function" then
                                TriggerServerEvent("POWERUP_CannonHit", jsonEncode({ cannon_id = cannon_id }))
                            end
                            table.insert(to_remove, cannon_id)
                        end
                    end
                end
                cannon.pos = new_pos
            end
        end
        for _, id in ipairs(to_remove) do removeCannonById(id) end
    end

    local has_spikes  = next(active_spikes)  ~= nil
    local has_bananas = next(active_bananas) ~= nil
    if not has_spikes and not has_bananas then return end

    local local_veh = be:getPlayerVehicle(0)
    if not local_veh then return end
    local oobb = local_veh:getSpawnWorldOOBB()

    local spikes_hit  = {}
    local bananas_hit = {}

    if has_spikes then
        for spike_id, spike in pairs(active_spikes) do
            if spike.fully_open and not spike.triggered and not spikes_hit[spike_id] then
                for _, p in ipairs(spike.check_points) do
                    if oobb:isContained(p) then
                        spike.triggered      = true
                        spikes_hit[spike_id] = local_veh
                        break
                    end
                end
            end
        end
    end

    if has_bananas then
        for banana_id, banana in pairs(active_bananas) do
            if not banana.triggered and not bananas_hit[banana_id] then
                for _, p in ipairs(banana.check_points) do
                    if oobb:isContained(p) then
                        banana.triggered       = true
                        bananas_hit[banana_id] = local_veh
                        break
                    end
                end
            end
        end
    end

    for spike_id, vehicle in pairs(spikes_hit) do
        vehicle:queueLuaCommand('beamstate.deflateRandomTire()')
        removeSpikeById(spike_id)
        if type(TriggerServerEvent) == "function" then
            TriggerServerEvent("POWERUP_SpikesTriggered", jsonEncode({ spike_id = spike_id }))
        end
    end

    for banana_id, vehicle in pairs(bananas_hit) do
        local vel = vehicle:getVelocity()
        vehicle:applyClusterVelocityScaleAdd(vehicle:getRefNodeId(), 1,
            -vel.x * 0.5, -vel.y * 0.5, -vel.z * 0.5)
        local up = vehicle:getDirectionVectorUp():normalized() * 9
        vehicle:queueLuaCommand(string.format(
            "local r=v.data.refNodes[0].ref; local fps=obj:getPhysicsFPS(); obj:applyClusterLinearAngularAccel(r,vec3(0,0,0),-vec3(%f,%f,%f)*fps)",
            up.x, up.y, up.z
        ))
        pcall(function()
            Engine.Audio.playOnce('AudioMaster',
                'art/shapes/pwu/signs/minion_laugh.ogg', { volume = 1, channel = 'Other' })
        end)
        removeBananaById(banana_id)
        if type(TriggerServerEvent) == "function" then
            TriggerServerEvent("POWERUP_BananaTriggered", jsonEncode({ banana_id = banana_id }))
        end
    end
end

M.onExtensionLoaded = function()
    setExtensionUnloadMode(M, "manual")
    _G.activateSpikeStrip = function() if type(TriggerServerEvent) == "function" then TriggerServerEvent("POWERUP_UseSpikes",  "") end end
    _G.activateBanana     = function() if type(TriggerServerEvent) == "function" then TriggerServerEvent("POWERUP_UseBanana",  "") end end
    _G.activateCannon     = function() if type(TriggerServerEvent) == "function" then TriggerServerEvent("POWERUP_UseCannon",  "") end end
end

M.onExtensionUnloaded = function()
    M.cleanup()
    _G.activateSpikeStrip = nil
    _G.activateBanana     = nil
    _G.activateCannon     = nil
end

return M