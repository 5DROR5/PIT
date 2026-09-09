-- =============================================================================
-- PIT Economy System - PowerUps System
-- License: AGPL-3.0
-- =============================================================================

local M = {}

local MAX_PER_TYPE       = 2
local SPIKE_DURATION_MS  = 180000
local BANANA_DURATION_MS = 180000
local POOL_SIZE          = 50
local POOL_WINS_SPIKE    = 8
local POOL_WINS_BANANA   = 8
local POOL_WINS_CANNON   = 8

local player_powerups = {}
local player_pools    = {}
local active_spikes   = {}
local active_bananas  = {}
local spike_counter   = 0
local banana_counter  = 0
local active_cannons  = {}

local _log, _encodeJSON, _triggerClient, _broadcastClientEvent
local _getUID, _getRole, _isWanted, _sendMessage, _translateForPlayer

-- =============================================================================
-- INTERNAL
-- =============================================================================

local function sendInventoryUpdate(pid)
    local payload = _encodeJSON({ inventory = player_powerups[pid] or { spike_strip = 0, banana = 0, cannon = 0 } })
    if payload then _triggerClient(pid, "POWERUP_InventoryUpdate", payload) end
end

local function broadcastSpikeRemoved(spike_id)
    local payload = _encodeJSON({ spike_id = spike_id })
    if payload then _broadcastClientEvent("POWERUP_SpikesRemoved", payload) end
    active_spikes[spike_id] = nil
end

local function broadcastBananaRemoved(banana_id)
    local payload = _encodeJSON({ banana_id = banana_id })
    if payload then _broadcastClientEvent("POWERUP_BananaRemoved", payload) end
    active_bananas[banana_id] = nil
end

local function generatePool()
    local slots = {}
    for i = 1, POOL_SIZE do slots[i] = nil end
    local function fill(reward, count)
        local placed = 0
        while placed < count do
            local idx = math.random(POOL_SIZE)
            if not slots[idx] then slots[idx] = reward; placed = placed + 1 end
        end
    end
    fill("spike_strip", POOL_WINS_SPIKE)
    fill("banana",      POOL_WINS_BANANA)
    fill("cannon",      POOL_WINS_CANNON)
    return { slots = slots, index = 0 }
end

local function checkAvailable(pid)
    if not player_powerups[pid] then return false end
    local role = _getRole(_getUID(pid))
    if role ~= "police" and role ~= "blocker" and not _isWanted(pid) then
        _sendMessage(pid, _translateForPlayer(pid, "powerup_not_available"))
        return false
    end
    return true
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

M.init = function(deps)
    _log                  = deps.log
    _encodeJSON           = deps.encodeJSON
    _triggerClient        = deps.triggerClient
    _broadcastClientEvent = deps.broadcastClientEvent
    _getUID               = deps.getUID
    _getRole              = deps.getRole
    _isWanted             = deps.isWanted
    _sendMessage          = deps.sendMessage
    _translateForPlayer   = deps.translateForPlayer
end

M.onPlayerJoin = function(pid)
    player_powerups[pid] = { spike_strip = 0, banana = 0, cannon = 0 }
    player_pools[pid]    = generatePool()
    sendInventoryUpdate(pid)
end

M.onPlayerLeave = function(pid)
    for spike_id,  spike  in pairs(active_spikes)  do if spike.pid  == pid then broadcastSpikeRemoved(spike_id)   end end
    for banana_id, banana in pairs(active_bananas) do if banana.pid == pid then broadcastBananaRemoved(banana_id) end end
    player_powerups[pid] = nil
    player_pools[pid]    = nil
end

M.tryGrantRandom = function(pid)
    if not player_powerups[pid] then player_powerups[pid] = { spike_strip = 0, banana = 0, cannon = 0 } end
    if not player_pools[pid]    then player_pools[pid]    = generatePool()                               end

    local pool = player_pools[pid]
    pool.index = pool.index + 1
    if pool.index > POOL_SIZE then
        player_pools[pid] = generatePool()
        pool              = player_pools[pid]
        pool.index        = 1
    end

    local reward = pool.slots[pool.index]
    if not reward then return false end

    local current = player_powerups[pid][reward] or 0
    if current >= MAX_PER_TYPE then return false end

    player_powerups[pid][reward] = current + 1
    sendInventoryUpdate(pid)

    local key = (reward == "spike_strip") and "powerup_bonus_spike"
             or (reward == "banana")      and "powerup_bonus_banana"
             or                               "powerup_bonus_cannon"
    _sendMessage(pid, _translateForPlayer(pid, key,
        { count = player_powerups[pid][reward], max = MAX_PER_TYPE }))
    return true
end

M.useSpikes = function(pid)
    if not checkAvailable(pid) then return false end
    local count = player_powerups[pid].spike_strip or 0
    if count <= 0 then _sendMessage(pid, _translateForPlayer(pid, "powerup_no_spikes")); return false end
    local pos_data, err = MP.GetPositionRaw(pid, 0)
    if err == "" and pos_data and pos_data.vel then
        local vx, vy = pos_data.vel[1] or 0, pos_data.vel[2] or 0
        if math.sqrt(vx*vx + vy*vy) * 3.6 > 5 then
            _sendMessage(pid, _translateForPlayer(pid, "powerup_speed_limit")); return false
        end
    end
    player_powerups[pid].spike_strip = count - 1
    sendInventoryUpdate(pid)
    spike_counter           = spike_counter + 1
    local spike_id          = "spk_" .. tostring(os.time()) .. "_" .. tostring(spike_counter)
    local placed_ms         = os.time() * 1000
    active_spikes[spike_id] = { pid = pid, placed_at = placed_ms }
    local payload = _encodeJSON({ spike_id = spike_id, expires_at = placed_ms + SPIKE_DURATION_MS })
    if payload then _triggerClient(pid, "POWERUP_SpikesDeploy", payload) end
    return true
end

M.useBanana = function(pid)
    if not checkAvailable(pid) then return false end
    local count = player_powerups[pid].banana or 0
    if count <= 0 then _sendMessage(pid, _translateForPlayer(pid, "powerup_no_bananas")); return false end
    player_powerups[pid].banana = count - 1
    sendInventoryUpdate(pid)
    banana_counter             = banana_counter + 1
    local banana_id            = "ban_" .. tostring(os.time()) .. "_" .. tostring(banana_counter)
    local placed_ms            = os.time() * 1000
    active_bananas[banana_id]  = { pid = pid, placed_at = placed_ms }
    local payload = _encodeJSON({ banana_id = banana_id, expires_at = placed_ms + BANANA_DURATION_MS })
    if payload then _triggerClient(pid, "POWERUP_BananaDeploy", payload) end
    return true
end

M.useCannon = function(pid)
    if not checkAvailable(pid) then return false end
    local count = player_powerups[pid].cannon or 0
    if count <= 0 then _sendMessage(pid, _translateForPlayer(pid, "powerup_no_cannon")); return false end
    player_powerups[pid].cannon = count - 1
    sendInventoryUpdate(pid)
    local payload = _encodeJSON({ owner_pid = pid })
    if payload then _triggerClient(pid, "POWERUP_CannonFire", payload) end
    return true
end

M.onCannonBallLaunched = function(shooter_pid, data)
    if data.cannon_id then
        active_cannons[data.cannon_id] = { pid = shooter_pid }
    end
    local payload = _encodeJSON({
        cannon_id = data.cannon_id,
        owner_id  = data.owner_id,
        x         = data.x,     y     = data.y,     z     = data.z,
        dir_x     = data.dir_x, dir_y = data.dir_y, dir_z = data.dir_z,
    })
    if payload then _broadcastClientEvent("POWERUP_CannonBallLaunched", payload) end
end

M.onCannonHit = function(shooter_pid, data)
    local payload = _encodeJSON({ cannon_id = data.cannon_id })
    if payload then _broadcastClientEvent("POWERUP_CannonHit", payload) end
end

M.onSpikesPosition = function(pid, data)
    local spike_id = data.spike_id
    if not active_spikes[spike_id] or active_spikes[spike_id].pid ~= pid then return end
    local payload = _encodeJSON({
        spike_id = spike_id, owner_pid = pid,
        x = data.x, y = data.y, z = data.z, dx = data.dx, dy = data.dy,
        expires_at = active_spikes[spike_id].placed_at + SPIKE_DURATION_MS,
    })
    if payload then _broadcastClientEvent("POWERUP_SpikesPlaced", payload) end
end

M.onBananaPosition = function(pid, data)
    local banana_id = data.banana_id
    if not active_bananas[banana_id] or active_bananas[banana_id].pid ~= pid then return end
    local payload = _encodeJSON({
        banana_id = banana_id, owner_pid = pid,
        x = data.x, y = data.y, z = data.z,
        expires_at = active_bananas[banana_id].placed_at + BANANA_DURATION_MS,
    })
    if payload then _broadcastClientEvent("POWERUP_BananaPlaced", payload) end
end

M.onSpikesTriggered  = function(pid, spike_id)  if active_spikes[spike_id]   then broadcastSpikeRemoved(spike_id)   end end
M.onBananaTriggered  = function(pid, banana_id) if active_bananas[banana_id] then broadcastBananaRemoved(banana_id) end end

M.tick = function()
    local now = os.time() * 1000
    for spike_id, spike in pairs(active_spikes) do
        if now - spike.placed_at >= SPIKE_DURATION_MS then broadcastSpikeRemoved(spike_id) end
    end
    for banana_id, banana in pairs(active_bananas) do
        if now - banana.placed_at >= BANANA_DURATION_MS then broadcastBananaRemoved(banana_id) end
    end
end

M.getInventory = function(pid)
    return player_powerups[pid] or { spike_strip = 0, banana = 0, cannon = 0 }
end


M.getSpikeOwner  = function(spike_id)
    return active_spikes[spike_id] and active_spikes[spike_id].pid or nil
end

M.getBananaOwner = function(banana_id)
    return active_bananas[banana_id] and active_bananas[banana_id].pid or nil
end

M.getCannonOwner = function(cannon_id)
    return active_cannons[cannon_id] and active_cannons[cannon_id].pid or nil
end

return M