-- =============================================================================
-- PIT Economy System — Client-Side Script
-- Version: 1.1
-- License: AGPL-3.0 — https://www.gnu.org/licenses/agpl-3.0.html
-- =============================================================================

local M = {}

-- =============================================================================
-- CONSTANTS
-- =============================================================================

local PLUGIN                    = "[EconomyUI-Client]"
local RETRY_INTERVAL            = 1.0
local BLOB_COLOR_CHECK_INTERVAL = 10

local blockedInputActions = {
    "toggleCamera",
    "dropCameraAtPlayer",
    "toggleBigMap",
    "switch_next_vehicle",
    "switch_previous_vehicle"
}

-- =============================================================================
-- GAME STATE
-- =============================================================================

local DEFENSE_STATS = {
    layer1_blocks    = 0,
    layer2_blocks    = 0,
    layer3_cleans    = 0,
    total_edits      = 0,
    successful_syncs = 0
}

local registered_events = false
local retry_acc         = 0
local hook_retry_timer  = 0

local pending_wanted  = nil
local current_prefix  = ""
local is_admin        = false

local player_roles    = {}
local is_local_wanted = false
local display_name_map = {}

local blob_color_check_timer = 0

local police_nearby      = false
local bust_progress      = { active = false, percent = 0, duration_ms = 0 }
local repair_icons_count = 0

local current_rank_data = {
    rank          = 1,
    rank_name_key = "rank_1_name",
    prefix        = "[Rookie]",
    percent       = 0,
    completed     = 0,
    total         = 0,
    tasks         = {},
    max_rank      = 5
}

local server_translations = {}
local current_lang        = "en"

local wanted_enabled = true

local is_editing_vehicle       = false
local current_edit_vehicle     = nil
local last_vehicle_config      = nil
local config_check_timer       = 0
local editing_session_start    = 0
local editing_state_sync_timer = 0

local vehicles_in_blob_mode      = {}
local vehicles_with_pending_edit = {}

local pending_sync_ack    = nil
local pending_blob_updates = {}

local original_MPGameNetwork_send = nil
local original_onVehicleSpawned   = nil

local network_hook_installed = false
local spawn_hook_installed   = false

local noRepairState = {
    enabled    = true,
    spawnPoint = { pos = {x=0, y=0, z=15}, rot = {x=0, y=0, z=0, w=1} },
    worldReady = false
}

local teleportQueue      = {}
local processingTeleport = false

local active_markers     = {}
local ap_hidden_marker   = nil
local ap_map_default_fog = nil

-- =============================================================================
-- FORWARD DECLARATIONS
-- =============================================================================

local startEditingMode
local stopEditingMode
local toggleWantedRestrictions

-- =============================================================================
-- LOGGING
-- =============================================================================

local function logI(msg) print(string.format("[%s] %s",         PLUGIN, msg)) end
local function logW(msg) print(string.format("[%s] WARNING: %s", PLUGIN, msg)) end
local function logE(msg) print(string.format("[%s] ERROR: %s",   PLUGIN, msg)) end

local function printDefenseStats()
    print("[Defense Stats] Layer1: " .. DEFENSE_STATS.layer1_blocks ..
          " | Layer2: "              .. DEFENSE_STATS.layer2_blocks  ..
          " | Layer3: "              .. DEFENSE_STATS.layer3_cleans  ..
          " | Edits: "               .. DEFENSE_STATS.total_edits    ..
          " | Syncs: "               .. DEFENSE_STATS.successful_syncs)
end

-- =============================================================================
-- UTILITIES
-- =============================================================================

local function serialize(t)
    if type(t) ~= "table" then return tostring(t) end
    local ok, result = pcall(jsonEncode, t)
    return ok and result or ""
end

local function decodePayload(payload)
    if type(payload) == "string" then
        local ok, decoded = pcall(jsonDecode, payload)
        return ok and decoded or nil
    end
    return payload
end

local function guiTrigger(event, data)
    if type(guihooks) == "table" and type(guihooks.trigger) == "function" then
        guihooks.trigger(event, data)
    end
end

M.delay = function(seconds, callback)
    local timer = 0
    local tempUpdate
    tempUpdate = function(dt)
        timer = timer + dt
        if timer >= seconds then
            callback()
            local handlers = M._delayHandlers or {}
            for i, h in ipairs(handlers) do
                if h == tempUpdate then table.remove(handlers, i); break end
            end
        end
    end
    M._delayHandlers = M._delayHandlers or {}
    table.insert(M._delayHandlers, tempUpdate)
end

-- =============================================================================
-- VEHICLE EDITING — HOOKS
-- =============================================================================

local function hookOnVehicleSpawned()
    if not extensions or not extensions.MPVehicleGE then return false end
    if spawn_hook_installed then return true end
    if not extensions.MPVehicleGE.onVehicleSpawned then return false end

    original_onVehicleSpawned = extensions.MPVehicleGE.onVehicleSpawned

    extensions.MPVehicleGE.onVehicleSpawned = function(gameVehicleID)
        local veh             = be:getObjectByID(gameVehicleID)
        local vehicle         = extensions.MPVehicleGE.getVehicleByGameID(gameVehicleID)
        local isEdit          = vehicle and vehicle.jbeam and vehicle.jbeam ~= ""
        local playerVeh       = be:getPlayerVehicle(0)
        local isPlayerVehicle = playerVeh and (playerVeh:getID() == gameVehicleID)
        local isLocalVehicle  = vehicle and vehicle.isLocal

        if is_editing_vehicle and isEdit and not (isPlayerVehicle or isLocalVehicle) then
            is_editing_vehicle   = false
            current_edit_vehicle = nil
        end

        if isEdit and not is_editing_vehicle and (isPlayerVehicle or isLocalVehicle) then
            startEditingMode(gameVehicleID)
        end

        if is_editing_vehicle and gameVehicleID == current_edit_vehicle then
            DEFENSE_STATS.layer1_blocks = DEFENSE_STATS.layer1_blocks + 1
            if veh then
                veh:queueLuaCommand("extensions.loadModulesInDirectory('lua/vehicle/extensions/BeamMP')")
            end
            return
        end

        return original_onVehicleSpawned(gameVehicleID)
    end

    spawn_hook_installed = true
    return true
end

local function hookNetworkSend()
    if not MPGameNetwork or not MPGameNetwork.send then return false end
    if network_hook_installed then return true end

    original_MPGameNetwork_send = MPGameNetwork.send

    MPGameNetwork.send = function(data)
        if type(data) == "string" then
            local prefix = string.sub(data, 1, 3)
            if prefix == "Oc:" then
                if is_editing_vehicle and current_edit_vehicle then
                    local serverVehicleID = string.match(data, "^Oc:(%d+%-%d+):") or
                                            string.match(data, "^Oc:(%d+):")
                    if serverVehicleID and extensions.MPVehicleGE then
                        local gameVehicleID = extensions.MPVehicleGE.getGameVehicleID(serverVehicleID)
                        if gameVehicleID == current_edit_vehicle then
                            DEFENSE_STATS.layer2_blocks = DEFENSE_STATS.layer2_blocks + 1
                            return
                        end
                    end
                end
            end
        end
        return original_MPGameNetwork_send(data)
    end

    network_hook_installed = true
    return true
end

local function cleanVehiclesToSync(gameVehicleID)
    if not extensions or not extensions.MPVehicleGE then return false end
    return pcall(function()
        local MPVehicleGE_module = extensions.MPVehicleGE
        for k, v in pairs(MPVehicleGE_module) do
            if type(v) == "table" and v[gameVehicleID] then
                v[gameVehicleID] = nil
                DEFENSE_STATS.layer3_cleans = DEFENSE_STATS.layer3_cleans + 1
                return true
            end
        end
    end)
end

local function restoreHooks()
    if original_MPGameNetwork_send and MPGameNetwork then
        MPGameNetwork.send          = original_MPGameNetwork_send
        original_MPGameNetwork_send = nil
    end
    if original_onVehicleSpawned and extensions.MPVehicleGE then
        extensions.MPVehicleGE.onVehicleSpawned = original_onVehicleSpawned
        original_onVehicleSpawned               = nil
    end
end

-- =============================================================================
-- VEHICLE EDITING — LOGIC
-- =============================================================================

startEditingMode = function(gameVehicleID)
    if is_editing_vehicle then logI("Already in editing mode"); return end

    is_editing_vehicle    = true
    current_edit_vehicle  = gameVehicleID
    editing_session_start = os.clock()
    DEFENSE_STATS.total_edits = DEFENSE_STATS.total_edits + 1

    guiTrigger("ECON_EditingModeUpdate", { isEditing = true })

    local serverVehicleID = nil
    pcall(function()
        if extensions and extensions.MPVehicleGE then
            local vehicle = extensions.MPVehicleGE.getVehicleByGameID(gameVehicleID)
            if vehicle and vehicle.serverVehicleString then
                serverVehicleID = vehicle.serverVehicleString
            end
        end
    end)

    if type(TriggerServerEvent) == "function" then
        local eventData = serverVehicleID and jsonEncode({ serverVehicleID = serverVehicleID }) or ""
        TriggerServerEvent('ECON_StartEditing', eventData)
    end
end

stopEditingMode = function(reason)
    if not is_editing_vehicle then return end

    is_editing_vehicle   = false
    current_edit_vehicle = nil
    last_vehicle_config  = nil
    pending_sync_ack     = nil

    guiTrigger("ECON_EditingModeUpdate", { isEditing = false })

    if type(TriggerServerEvent) == "function" then
        TriggerServerEvent('ECON_CancelEditing', '')
    end

    if DEFENSE_STATS.total_edits % 10 == 0 then printDefenseStats() end
end

local function initializeConfigTracking()
    local veh = be:getPlayerVehicle(0)
    if veh and extensions.core_vehicle_manager then
        local vehicleData = extensions.core_vehicle_manager.getVehicleData(veh:getID())
        if vehicleData and vehicleData.config then
            last_vehicle_config = serialize(vehicleData.config)
        end
    end
end

local function detectEditingMode(dt)
    local inMP = MPCoreNetwork and type(MPCoreNetwork.isMPSession) == "function" and MPCoreNetwork.isMPSession()
    if not inMP then return end

    config_check_timer = config_check_timer + dt
    if config_check_timer <= 0.2 then return end
    config_check_timer = 0

    local veh = be:getPlayerVehicle(0)
    if veh and extensions.core_vehicle_manager then
        local gameVehicleID = veh:getID()
        local vehicleData   = extensions.core_vehicle_manager.getVehicleData(gameVehicleID)
        if vehicleData and vehicleData.config then
            local currentConfig = serialize(vehicleData.config)
            if not last_vehicle_config then
                last_vehicle_config = currentConfig
                return
            end
            if last_vehicle_config ~= currentConfig then
                local vehicle = extensions.MPVehicleGE and extensions.MPVehicleGE.getVehicleByGameID(gameVehicleID)
                if vehicle and vehicle.isLocal and not is_editing_vehicle then
                    startEditingMode(gameVehicleID)
                end
                last_vehicle_config = currentConfig
            end
        end
    else
        last_vehicle_config = nil
    end
end

local function finishVehicleEditing()
    local veh = be:getPlayerVehicle(0)
    if not veh then logE("No vehicle found for sync"); return end

    local gameVehicleID = veh:getID()
    cleanVehiclesToSync(gameVehicleID)

    local serverVehicleID = nil
    pcall(function()
        if extensions and extensions.MPVehicleGE then
            local vehicle = extensions.MPVehicleGE.getVehicleByGameID(gameVehicleID)
            if vehicle and vehicle.serverVehicleString then
                serverVehicleID = vehicle.serverVehicleString
            end
        end
    end)

    is_editing_vehicle   = false
    current_edit_vehicle = nil

    if extensions and extensions.MPVehicleGE then
        if extensions.MPVehicleGE.sendVehicleEdit then
            local ok, err = pcall(extensions.MPVehicleGE.sendVehicleEdit, gameVehicleID)
            if ok then
                DEFENSE_STATS.successful_syncs = DEFENSE_STATS.successful_syncs + 1
                if serverVehicleID then
                    pending_sync_ack = {
                        serverVehicleID = serverVehicleID,
                        gameVehicleID   = gameVehicleID,
                        startTime       = os.clock()
                    }
                end
            else
                logE("Sync failed: " .. tostring(err))
            end
        else
            logE("sendVehicleEdit not available")
        end
    else
        logE("MPVehicleGE not available")
    end

    last_vehicle_config = nil
    guiTrigger("ECON_EditingModeUpdate", { isEditing = false })

    if type(TriggerServerEvent) == "function" then
        TriggerServerEvent('ECON_FinishEditing', '')
    end
end

local function checkSyncCompletion()
    if not pending_sync_ack then return end

    local serverVehicleID = pending_sync_ack.serverVehicleID

    if (os.clock() - pending_sync_ack.startTime) > 10 then
        if type(TriggerServerEvent) == "function" then
            TriggerServerEvent('ECON_VehicleSyncComplete', jsonEncode({ serverVehicleID = serverVehicleID }))
        end
        pending_sync_ack = nil
        return
    end

    pcall(function()
        if not (extensions and extensions.MPVehicleGE and extensions.MPVehicleGE.getVehicles) then return end
        local vehicles = extensions.MPVehicleGE.getVehicles()
        if not vehicles then return end
        local vehicle = vehicles[serverVehicleID]
        if not vehicle then return end
        if vehicle.isSpawned and vehicle.gameVehicleID and vehicle.gameVehicleID > 0 then
            if be:getObjectByID(vehicle.gameVehicleID) then
                if type(TriggerServerEvent) == "function" then
                    TriggerServerEvent('ECON_VehicleSyncComplete', jsonEncode({ serverVehicleID = serverVehicleID }))
                end
                pending_sync_ack = nil
            end
        end
    end)
end

-- =============================================================================
-- WANTED RESTRICTIONS
-- =============================================================================

toggleWantedRestrictions = function(enable)
    pcall(function()
        settings.setValue("skipOtherPlayersVehicles", enable)
        extensions.core_input_actionFilter.setGroup('ECON_WantedBlock', blockedInputActions)
        extensions.core_input_actionFilter.addAction(0, 'ECON_WantedBlock', enable)
    end)

    if extensions and extensions.MPVehicleGE then
        local players = extensions.MPVehicleGE.getPlayers()
        if players then
            for playerID, player in pairs(players) do
                if player_roles[playerID] == "police" then
                    player.hideNametag = enable
                end
            end
        end
    end

    logI(enable and "Wanted restrictions activated" or "Wanted restrictions deactivated")
end

-- =============================================================================
-- BLOB SYSTEM
-- =============================================================================

local function on_set_vehicle_spawned(payload)
    local data = decodePayload(payload)
    if not data or not data.serverVehicleID then logE("[BLOB] Invalid data"); return end

    local serverVehicleID = tostring(data.serverVehicleID)
    local isSpawned       = data.isSpawned
    local playerRole      = data.playerRole or "civilian"

    if not (extensions and extensions.MPVehicleGE and extensions.MPVehicleGE.getVehicles) then
        table.insert(pending_blob_updates, {
            serverVehicleID = serverVehicleID,
            isSpawned       = isSpawned,
            playerRole      = playerRole,
            timestamp       = os.clock()
        })
        return
    end

    pcall(function()
        local vehicles = extensions.MPVehicleGE.getVehicles()
        if not vehicles then return end
        local vehicle = vehicles[serverVehicleID]

        if not isSpawned then
            if vehicle then
                if playerRole == "police" then
                    vehicle.isIllegal = true
                    vehicle.isDeleted = false
                else
                    vehicle.isDeleted = true
                    vehicle.isIllegal = false
                end
                vehicle.isSpawned = false
                vehicles_in_blob_mode[serverVehicleID] = true
                if vehicle.gameVehicleID and vehicle.gameVehicleID > 0 then
                    local veh = be:getObjectByID(vehicle.gameVehicleID)
                    if veh then
                        if not vehicle.position then
                            local x, y, z = be:getObjectOOBBCenterXYZ(vehicle.gameVehicleID)
                            vehicle.position = vec3(x, y, z)
                        end
                        veh:setActive(0)
                    end
                end
            else
                vehicles_in_blob_mode[serverVehicleID] = true
            end
        else
            if vehicle then
                vehicle.isDeleted = false
                vehicle.isIllegal = false
                vehicle.isSpawned = true
                vehicles_in_blob_mode[serverVehicleID] = nil
                if vehicle.gameVehicleID and vehicle.gameVehicleID > 0 then
                    local veh = be:getObjectByID(vehicle.gameVehicleID)
                    if veh then veh:setActive(1) end
                end
            end
        end
    end)
end

local function process_pending_blob_updates()
    if not (extensions and extensions.MPVehicleGE and extensions.MPVehicleGE.getVehicles) then return end
    local vehicles = extensions.MPVehicleGE.getVehicles()
    if not vehicles or type(vehicles) ~= "table" then return end

    if #pending_blob_updates > 0 then
        for _, update in ipairs(pending_blob_updates) do
            on_set_vehicle_spawned(update)
        end
        pending_blob_updates = {}
    end
end

-- =============================================================================
-- MARKERS
-- =============================================================================

local function createMarker(data)
    local decoded = decodePayload(data)
    if not decoded or not decoded.markerId then return end
    if not decoded.x or not decoded.y or not decoded.z then return end

    local markerId = tostring(decoded.markerId)
    active_markers[markerId] = {
        id          = markerId,
        pos         = vec3(decoded.x, decoded.y, decoded.z),
        radius      = tonumber(decoded.scale) or 10,
        color       = ColorF((decoded.r or 0)/255, (decoded.g or 255)/255, (decoded.b or 0)/255, (decoded.a or 200)/255),
        alpha       = (decoded.a or 200) / 255,
        createdTime = os.clock()
    }
end

local function removeMarker(data)
    local decoded = decodePayload(data)
    if decoded and decoded.markerId then
        active_markers[tostring(decoded.markerId)] = nil
    end
end

local function drawMarkers(dt)
    local worldReady = worldReadyState and (worldReadyState == 2) or noRepairState.worldReady
    if not worldReady or not next(active_markers) then return end

    local clock = os.clock() * 1.5
    for id, marker in pairs(active_markers) do
        if marker.pos then
            debugDrawer:drawSphere(marker.pos, marker.radius, marker.color)

            local ringRadius = marker.radius * 0.85
            local ringHeight = marker.pos.z + marker.radius * 1.3

            for i = 0, 31 do
                local a1 = (i / 32) * math.pi * 2 + clock
                local a2 = ((i+1) / 32) * math.pi * 2 + clock
                local p1 = vec3(marker.pos.x + math.cos(a1)*ringRadius, marker.pos.y + math.sin(a1)*ringRadius, ringHeight)
                local p2 = vec3(marker.pos.x + math.cos(a2)*ringRadius, marker.pos.y + math.sin(a2)*ringRadius, ringHeight)
                debugDrawer:drawLine(p1, p2, marker.color)
            end

            local beamTop = vec3(marker.pos.x, marker.pos.y, marker.pos.z + marker.radius * 3)
            debugDrawer:drawLine(marker.pos, beamTop, ColorF(marker.color.r, marker.color.g, marker.color.b, 0.3))
        end
    end
end

-- =============================================================================
-- AIR POLLUTER
-- =============================================================================

local function drawHiddenMarker()
    if not ap_hidden_marker then return end
    local worldReady = (worldReadyState and worldReadyState == 2) or noRepairState.worldReady
    if not worldReady then return end
    local veh = be:getPlayerVehicle(0)
    if not veh then return end
    local vehPos = veh:getPosition()
    local mPos   = ap_hidden_marker.pos
    local dist   = (vehPos - mPos):length()
    if dist > ap_hidden_marker.visibility_radius then return end
    local t     = os.clock()
    local pulse = math.sin(t * 3) * 0.3 + 0.7
    local col   = ColorF(0.6 * pulse, 0, 0.9 * pulse, 0.85)
    debugDrawer:drawSphere(mPos, 2, col)
end

-- =============================================================================
-- TELEPORT SYSTEM
-- =============================================================================

local function performTeleport(vehicleId, targetPos, targetRot, reason)
    local worldReady = worldReadyState and (worldReadyState == 2) or noRepairState.worldReady
    if not worldReady then return false end

    local veh = be:getPlayerVehicle(0)
    if not veh then return false end

    if MPVehicleGE and MPVehicleGE.isOwn and not MPVehicleGE.isOwn(veh:getID()) then
        return false
    end

    local pos = vec3(targetPos.x, targetPos.y, targetPos.z)
    local rot = quat(targetRot.x, targetRot.y, targetRot.z, targetRot.w)

    if veh.setPositionRotation then
        local correctedRot = quat(0,0,1,0) * rot
        local ok = pcall(function()
            veh:setPositionRotation(pos.x, pos.y, pos.z,
                correctedRot.x, correctedRot.y, correctedRot.z, correctedRot.w)
        end)
        if ok then
            if veh.setVelocity        then pcall(function() veh:setVelocity(vec3(0,0,0)) end) end
            if veh.setAngularVelocity then pcall(function() veh:setAngularVelocity(vec3(0,0,0)) end) end
            return true
        end
    end
    return false
end

local function teleportVehicleToSpawn(data)
    local decoded = decodePayload(data)
    if not decoded or not decoded.vehicle_id then return end
    table.insert(teleportQueue, {
        vehicleId = decoded.vehicle_id,
        pos       = decoded.pos or noRepairState.spawnPoint.pos,
        rot       = decoded.rot or noRepairState.spawnPoint.rot,
        reason    = decoded.reason or "unknown",
        timestamp = os.time(),
        attempts  = 0
    })
end

local function processTeleportQueue(dt)
    local worldReady = worldReadyState and (worldReadyState == 2) or noRepairState.worldReady
    if processingTeleport or #teleportQueue == 0 or not worldReady then return end

    processingTeleport = true
    local teleport = table.remove(teleportQueue, 1)
    local ok = performTeleport(teleport.vehicleId, teleport.pos, teleport.rot, teleport.reason)
    if not ok and teleport.attempts < 3 then
        teleport.attempts = teleport.attempts + 1
        table.insert(teleportQueue, teleport)
    end
    processingTeleport = false
end

-- =============================================================================
-- EVENT HANDLERS
-- =============================================================================

local function send_to_ui(money)
    if type(money) ~= "number" then money = tonumber(money) end
    if not money then return end
    guiTrigger("EconomyUI_Update", { money = money })
end

local function on_receive_money(payload)
    local money = nil
    if type(payload) == "number" then
        money = payload
    elseif type(payload) == "string" then
        local data = decodePayload(payload)
        money = (type(data) == "table" and data.money ~= nil) and tonumber(data.money) or tonumber(payload)
    elseif type(payload) == "table" and payload.money ~= nil then
        money = tonumber(payload.money)
    end
    if money then send_to_ui(money) end
end

local function on_receive_translations(payload)
    local data = decodePayload(payload)
    if type(data) ~= "table" then return end
    if data.lang then current_lang = data.lang end
    if data.translations then
        server_translations = data.translations
        local tdata = { lang = current_lang, translations = server_translations, auth_required = data.auth_required }
        guiTrigger("EconomyUI_TranslationsUpdate", tdata)
        guiTrigger("POLICE_TranslationsUpdate",    tdata)
    end
end

local function on_receive_rank_update(payload)
    local data = decodePayload(payload)
    if type(data) ~= "table" then return end
    current_rank_data = {
        rank          = data.rank          or 1,
        rank_name_key = data.rank_name_key or "rank_1_name",
        prefix        = data.prefix        or "",
        percent       = data.percent       or 0,
        completed     = data.completed     or 0,
        total         = data.total         or 0,
        tasks         = data.tasks         or {},
        max_rank      = data.max_rank      or 5
    }
    guiTrigger("EconomyUI_RankUpdate", current_rank_data)
end

local function on_receive_task_progress(payload)
    local data = decodePayload(payload)
    if type(data) == "table" then guiTrigger("EconomyUI_TaskProgress", data) end
end

local function on_receive_rank_up(payload)
    local data = decodePayload(payload)
    if type(data) == "table" then guiTrigger("EconomyUI_RankUp", data) end
end

local function on_show_rank_panel(payload)
    guiTrigger("EconomyUI_ShowRankPanel", {})
end

local function on_police_wanted_list_update(payload)
    local data = decodePayload(payload)
    if type(data) == "table" and data.wanted_players then
        guiTrigger("POLICE_WantedListUpdate", data)
    end
end

local function on_police_role_update(payload)
    local data = decodePayload(payload)
    if type(data) == "table" and data.isPolice ~= nil then
        guiTrigger("POLICE_RoleUpdate", data)
    end
end

local function on_receive_wanted_status(payload)
    local wantedTime = nil
    if type(payload) == "string" then
        local data = decodePayload(payload)
        if type(data) == "table" and data.wantedTime ~= nil then
            wantedTime = tonumber(data.wantedTime)
        else
            wantedTime = tonumber(payload)
        end
    elseif type(payload) == "number" then
        wantedTime = payload
    elseif type(payload) == "table" and payload.wantedTime ~= nil then
        wantedTime = tonumber(payload.wantedTime)
    end

    if wantedTime ~= nil then
        local ui_payload = { wantedTime = math.max(0, math.floor(wantedTime)) }
        if type(guihooks) == "table" and type(guihooks.trigger) == "function" then
            guiTrigger("EconomyUI_WantedUpdate", ui_payload)
        else
            pending_wanted = ui_payload
        end
    end
end

local function on_update_police_proximity(payload)
    local data = decodePayload(payload)
    if type(data) == "table" and data.policeNearby ~= nil then
        police_nearby = (data.policeNearby == true)
        guiTrigger("EconomyUI_PoliceProximity", { policeNearby = police_nearby })
    end
end

local function on_update_bust_progress(payload)
    local data = decodePayload(payload)
    if type(data) == "table" then
        bust_progress.percent     = tonumber(data.bustProgress) or 0
        bust_progress.duration_ms = tonumber(data.bustDuration) or 0
        bust_progress.active      = (bust_progress.percent > 0 and bust_progress.duration_ms > 0)
        guiTrigger("EconomyUI_BustProgress", {
            bustProgress = bust_progress.percent,
            bustDuration = bust_progress.duration_ms,
            active       = bust_progress.active
        })
    end
end

local function on_update_repair_icons(payload)
    local data = decodePayload(payload)
    if type(data) == "table" and data.repairIcons ~= nil then
        repair_icons_count = tonumber(data.repairIcons) or 0
        guiTrigger("EconomyUI_RepairIcons", {
            repairIcons = repair_icons_count,
            maxRepairs  = tonumber(data.maxRepairs) or 2
        })
    end
end

local function on_wanted_enabled_update(payload)
    local data = decodePayload(payload)
    if type(data) == "table" and data.wantedEnabled ~= nil then
        wanted_enabled = data.wantedEnabled
        guiTrigger("EconomyUI_WantedEnabledUpdate", { wantedEnabled = wanted_enabled })
    end
end

local function on_editing_mode_update(payload)
    local data = decodePayload(payload)
    if type(data) == "table" and data.isEditing ~= nil then
        is_editing_vehicle = data.isEditing
        guiTrigger("ECON_EditingModeUpdate", data)
    end
end

local function on_receive_playerlist_data(payload)
    local data = decodePayload(payload)
    if not data or type(data) ~= "table" or not data.players then
        logE("[PlayerList] Invalid data"); return
    end

    local localPID = -1
    if MPConfig and MPConfig.getPlayerServerID then
        localPID = MPConfig.getPlayerServerID()
    end

    local was_wanted = is_local_wanted

    for _, player in ipairs(data.players) do
        player_roles[player.id] = player.role
        if player.id == localPID then
            is_local_wanted = player.is_wanted
        end
    end

    if is_local_wanted ~= was_wanted or is_local_wanted then
        M.delay(0.1, function() toggleWantedRestrictions(is_local_wanted) end)
    end

    if extensions and extensions.MPVehicleGE then
        local mp_players = extensions.MPVehicleGE.getPlayers()
        for _, player in ipairs(data.players) do
            local pid       = player.id
            local role      = player.role
            local is_wanted = player.is_wanted
            if is_wanted then
                extensions.MPVehicleGE.setPlayerRole(pid, nil, nil, 255, 0, 0)
            elseif role == "police" then
                extensions.MPVehicleGE.setPlayerRole(pid, nil, nil, 0, 102, 255)
            else
                extensions.MPVehicleGE.clearPlayerRole(pid)
                if is_local_wanted and mp_players and mp_players[pid] then
                    mp_players[pid].hideNametag = false
                end
            end
        end
    end

    for _, player in ipairs(data.players) do
        if player.beammp_name and player.display_name then
            display_name_map[player.beammp_name] = player.display_name
        end
    end
    pcall(function()
        if not (extensions and extensions.MPVehicleGE
                and extensions.MPVehicleGE.getVehicles) then return end
        local vehs = extensions.MPVehicleGE.getVehicles()
        if not vehs then return end
        for _, v in pairs(vehs) do
            local ok, owner = pcall(function() return v:getOwner() end)
            if ok and owner and owner.name and display_name_map[owner.name] then
                v.customName = display_name_map[owner.name]
            end
        end
    end)

    guiTrigger("PlayerList_CustomData", data)
    guiTrigger("PIT_DisplayNames", display_name_map)
end

local function on_minimap_update(payload)
    if extensions and extensions.minimap then
        local decoded = decodePayload(payload)
        if decoded then
            pcall(function() extensions.minimap.onMinimapUpdate(decoded) end)
        end
    end
end

local function on_receive_player_prefix(payload)
    local playerName, prefix, pid = "", "", nil

    local data = decodePayload(payload)
    if type(data) == "table" then
        playerName = tostring(data.playerName or "")
        prefix     = tostring(data.prefix or "")
        pid        = tonumber(data.pid)
    end

    if playerName == "" then return end

    local localPlayerName = (type(MPConfig) == "table" and type(MPConfig.getNickname) == "function")
                            and MPConfig.getNickname() or ""

    if playerName == localPlayerName then current_prefix = prefix end

    if type(MPVehicleGE) == "table" then
        if type(MPVehicleGE.setPlayerNickPrefix) == "function" then
            MPVehicleGE.setPlayerNickPrefix(playerName, "economy_role_prefix", prefix)
        end
        if type(MPVehicleGE.setPlayerNickSuffix) == "function" then
            MPVehicleGE.setPlayerNickSuffix(playerName, "economy_role_suffix", "")
        end
    end
end

local function on_receive_admin_status(payload)
    local data = decodePayload(payload)
    if type(data) == "table" and data.isAdmin ~= nil then
        is_admin = (data.isAdmin == true)
        if M.updateConsolePermissions then M.updateConsolePermissions() end
        guiTrigger("EconomyUI_AdminStatus", { isAdmin = is_admin })
    end
end

local function on_perform_repair(payload)
    local veh = be:getPlayerVehicle(0)
    if not veh then return end
    pcall(function()
        veh:queueLuaCommand([[
            local x, y, z = obj:getPositionXYZ()
            local front = obj:getDirectionVector()
            local rot = quatFromDir(front, vec3(0,0,1))
            obj:queueGameEngineLua("spawn.safeTeleport(getObjectByID("..obj:getId().."), vec3("..x..","..y..","..z.."), quat("..rot.x..","..rot.y..","..rot.z..","..rot.w.."))")
        ]])
    end)
end

local function applyStateFromServer(data)
    local flag    = data
    local enabled = false
    if type(flag) == "string" then
        flag    = flag:lower()
        enabled = (flag == "1" or flag == "true" or flag == "on")
    elseif type(flag) == "boolean" then
        enabled = flag
    end
    noRepairState.enabled = enabled
end

local function setSpawnPointFromServer(data)
    local decoded = decodePayload(data)
    if not decoded then return end
    if decoded.pos and decoded.rot then
        noRepairState.spawnPoint = { pos = decoded.pos, rot = decoded.rot }
    end
end

-- =============================================================================
-- EVENT REGISTRATION
-- =============================================================================

local function try_register()
    if registered_events then return end
    if type(AddEventHandler) ~= "function" then return end

    AddEventHandler("receiveMoney",             on_receive_money)
    AddEventHandler("updateWantedStatus",       on_receive_wanted_status)
    AddEventHandler("updatePlayerPrefix",       on_receive_player_prefix)
    AddEventHandler("updatePoliceProximity",    on_update_police_proximity)
    AddEventHandler("updateBustProgress",       on_update_bust_progress)
    AddEventHandler("updateRepairIcons",        on_update_repair_icons)
    AddEventHandler("performRepair",            on_perform_repair)
    AddEventHandler("NoRepair_UpdateState",     applyStateFromServer)
    AddEventHandler("NoRepair_SetSpawnPoint",   setSpawnPointFromServer)
    AddEventHandler("NoRepair_TeleportVehicle", teleportVehicleToSpawn)
    AddEventHandler("ECON_CreateMarker",        createMarker)
    AddEventHandler("ECON_RemoveMarker",        removeMarker)
    AddEventHandler("ECON_AdminStatus",         on_receive_admin_status)
    AddEventHandler("ECON_TranslationsUpdate",  on_receive_translations)
    AddEventHandler("ECON_RankUpdate",          on_receive_rank_update)
    AddEventHandler("ECON_TaskProgress",        on_receive_task_progress)
    AddEventHandler("ECON_RankUp",              on_receive_rank_up)
    AddEventHandler("ECON_ShowRankPanel",       on_show_rank_panel)
    AddEventHandler("POLICE_WantedListUpdate",  on_police_wanted_list_update)
    AddEventHandler("POLICE_RoleUpdate",        on_police_role_update)
    AddEventHandler("ECON_WantedEnabledUpdate", on_wanted_enabled_update)
    AddEventHandler("ECON_EditingModeUpdate",   on_editing_mode_update)
    AddEventHandler("ECON_SetVehicleSpawned",   on_set_vehicle_spawned)
    AddEventHandler("ECON_PlayerListData",      on_receive_playerlist_data)
    AddEventHandler("ECON_MinimapUpdate",       on_minimap_update)    
    AddEventHandler("ECON_NotSyncedBy", function(payload)
        local data = decodePayload(payload)
        if type(data) == "table" then guiTrigger("PlayerList_NotSyncedBy", data) end
    end)

    AddEventHandler("ECON_AuthRequired", function(payload)
        local data = decodePayload(payload)
        if type(data) == "table" then guiTrigger("ECON_AuthRequired", data) end
    end)

    AddEventHandler("ECON_AuthResult", function(payload)
        local data = decodePayload(payload)
        if type(data) == "table" then guiTrigger("ECON_AuthResult", data) end
    end)

    AddEventHandler("AIRPOLLUTER_SetMarker", function(payload)
        local data = decodePayload(payload)
        if type(data) == "table" and data.x then
            ap_hidden_marker = {
                pos               = vec3(data.x, data.y, data.z),
                visibility_radius = tonumber(data.visibility_radius) or 50
            }
        end
    end)

    AddEventHandler("AIRPOLLUTER_FogUpdate", function(payload)
        local data = decodePayload(payload)
        if type(data) ~= "table" or data.intensity == nil then return end
        local intensity = tonumber(data.intensity) or 0
        pcall(function()
            if not core_environment then return end
            if intensity > 0 then
                core_environment.setFogDensity(intensity)
            else
                core_environment.setFogDensity(ap_map_default_fog or 0)
            end
        end)
    end)

    AddEventHandler("AIRPOLLUTER_MissionStart", function(payload)
        local data = decodePayload(payload)
        if type(data) == "table" then guiTrigger("AIRPOLLUTER_MissionStart", data) end
    end)

    AddEventHandler("AIRPOLLUTER_MissionEnd", function(payload)
        local data = decodePayload(payload)
        if type(data) == "table" then guiTrigger("AIRPOLLUTER_MissionEnd", data) end
    end)

    AddEventHandler("AIRPOLLUTER_StatusUpdate", function(payload)
        local data = decodePayload(payload)
        if type(data) == "table" then guiTrigger("AIRPOLLUTER_StatusUpdate", data) end
    end)

    registered_events = true
end

-- =============================================================================
-- LIFECYCLE
-- =============================================================================

M.onExtensionLoaded = function()
    registered_events = false
    hookNetworkSend()
    hookOnVehicleSpawned()

    local function applyBlobColors()
        if settings and type(settings.setValue) == "function" then
            pcall(function()
                settings.setValue("blobColorDeleted", "#FF6400")
                settings.setValue("blobColorIllegal", "#0066FF")
                settings.setValue("showBlobDeleted",  true)
                settings.setValue("showBlobIllegal",  true)
            end)
        end
        if extensions and extensions.MPConfig and type(extensions.MPConfig.setConfig) == "function" then
            pcall(function()
                extensions.MPConfig.setConfig("blobColorDeleted", "#FF6400")
                extensions.MPConfig.setConfig("blobColorIllegal", "#0066FF")
                extensions.MPConfig.setConfig("showBlobDeleted",  true)
                extensions.MPConfig.setConfig("showBlobIllegal",  true)
            end)
        end
    end

    applyBlobColors()
    M.delay(0.5, applyBlobColors)

    if TriggerServerEvent then
        TriggerServerEvent("NoRepair_RequestState",    "")
        local beamng_lang = (settings and settings.getValue and settings.getValue("userLanguage")) or ""
        TriggerServerEvent("ECON_RequestTranslations", beamng_lang)
    end

    M.delay(0.5, function()
        guiTrigger("ECON_EditingModeUpdate", { isEditing = is_editing_vehicle })
    end)

    M.delay(1.0, function()
        if is_local_wanted then toggleWantedRestrictions(true) end
    end)
end

M.onWorldReadyState = function(newState)
    if newState == 2 then
        noRepairState.worldReady = true
        if core_environment then
            ap_map_default_fog = core_environment.getFogDensity()
        end

        if not network_hook_installed then hookNetworkSend() end
        if not spawn_hook_installed   then hookOnVehicleSpawned() end

        M.delay(1,   initializeConfigTracking)
        M.delay(0.5, function()
            pcall(function()
                if extensions and extensions.load then
                    if extensions.ui_apps_minimap_additionalInfo then
                        extensions.ui_apps_minimap_additionalInfo.onUpdate = nil
                        logI("Disabled original minimap additionalInfo")
                    end
                    extensions.load("minimap")
                    logI("Loaded economy minimap extension")
                end
            end)
        end)

        local inMP = MPCoreNetwork and type(MPCoreNetwork.isMPSession) == "function" and MPCoreNetwork.isMPSession()
        if inMP then
            if core_gamestate and core_gamestate.setGameState then
                pcall(function() core_gamestate.setGameState('multiplayer', 'Pit', 'multiplayer') end)
            end

            local always_blocked_actions = {
                "vehicleReset", "vehicleRecover", "loadHome", "recover_vehicle",
                "recover_to_last_road", "recover_vehicle_alt",
                "nodegrabberAction", "nodegrabberGrab", "nodegrabberRender", "nodegrabberStrength",
                "pause",
                "toggleWalkingMode", "toggleBigMap",
                "funBoost", "funBoostBackwards", "funFling", "funFlingDownward", "forceField", "funBoom",
                "slower_motion", "faster_motion", "toggle_slow_motion",
                "dropPlayerAtCamera", "dropPlayerAtCameraNoReset",
                "reset_physics"
            }
            extensions.core_input_actionFilter.setGroup("uimpit_economy_permanent", always_blocked_actions)
            core_input_actionFilter.addAction(0, "uimpit_economy_permanent", true)

            extensions.core_input_actionFilter.setGroup("uimpit_console_block", { "toggleConsoleNG", "toggleConsole" })
            extensions.core_input_actionFilter.setGroup("uimpit_editor_block",  { "editorToggle", "objectEditorToggle", "editorSafeModeToggle" })

            M.updateConsolePermissions = function()
                core_input_actionFilter.addAction(0, "uimpit_console_block", not is_admin)
                core_input_actionFilter.addAction(0, "uimpit_editor_block",  not is_admin)
            end
            M.updateConsolePermissions()
        end
    else
        noRepairState.worldReady = false
    end
end

M.onVehicleSwitched = function(oldID, newID)
    if is_editing_vehicle and oldID ~= newID and current_edit_vehicle == oldID then
        if oldID and oldID > 0 then
            is_editing_vehicle   = false
            current_edit_vehicle = nil
            if extensions.MPVehicleGE and extensions.MPVehicleGE.sendVehicleEdit then
                pcall(extensions.MPVehicleGE.sendVehicleEdit, oldID)
            end
        end
        stopEditingMode("vehicle_switched")
    end

    if newID and newID > 0 then
        local vehicleData = extensions.core_vehicle_manager and
                            extensions.core_vehicle_manager.getVehicleData(newID)
        last_vehicle_config = (vehicleData and vehicleData.config) and serialize(vehicleData.config) or nil
    else
        last_vehicle_config = nil
    end
end

M.onVehicleDestroyed = function(gameVehicleID)
    if is_editing_vehicle and current_edit_vehicle == gameVehicleID then
        stopEditingMode("vehicle_deleted")
    end
end

M.onDisconnect = function()
    if is_editing_vehicle then stopEditingMode("disconnect") end
    active_markers        = {}
    vehicles_in_blob_mode = {}
    ap_hidden_marker      = nil
    restoreHooks()
    toggleWantedRestrictions(false)
    player_roles    = {}
    is_local_wanted = false
    printDefenseStats()
end

M.onExtensionUnloaded = function()
    active_markers        = {}
    vehicles_in_blob_mode = {}
    if is_editing_vehicle then stopEditingMode("unload") end
    restoreHooks()
    toggleWantedRestrictions(false)
    player_roles    = {}
    is_local_wanted = false
    printDefenseStats()
end

M.onUpdate = function(dt)
    blob_color_check_timer = blob_color_check_timer + dt
    if blob_color_check_timer >= BLOB_COLOR_CHECK_INTERVAL then
        blob_color_check_timer = 0
        if settings and type(settings.getValue) == "function" and type(settings.setValue) == "function" then
            if settings.getValue("blobColorDeleted") ~= "#FF6400" then
                pcall(function() settings.setValue("blobColorDeleted", "#FF6400") end)
            end
        end
    end

    if pending_sync_ack then checkSyncCompletion() end

    if next(vehicles_in_blob_mode) and extensions and extensions.MPVehicleGE and extensions.MPVehicleGE.getVehicles then
        local vehicles = extensions.MPVehicleGE.getVehicles()
        if vehicles then
            for serverVehicleID, _ in pairs(vehicles_in_blob_mode) do
                local vehicle = vehicles[serverVehicleID]
                if vehicle then
                    if vehicle.editQueue then
                        vehicles_with_pending_edit[serverVehicleID] = true
                    end
                    if vehicles_with_pending_edit[serverVehicleID] and not vehicle.editQueue then
                        if vehicle.isDeleted or vehicle.isIllegal then
                            vehicle.isSpawned = true
                            vehicle.isDeleted = false
                            vehicle.isIllegal = false
                            vehicles_in_blob_mode[serverVehicleID]      = nil
                            vehicles_with_pending_edit[serverVehicleID] = nil
                        end
                    end
                end
            end
        end
    end

    if not registered_events then
        retry_acc = retry_acc + (dt or 0)
        if retry_acc >= RETRY_INTERVAL then
            retry_acc = 0
            try_register()
        end
    end

    if not network_hook_installed or not spawn_hook_installed then
        hook_retry_timer = hook_retry_timer + dt
        if hook_retry_timer > 1.0 then
            hook_retry_timer = 0
            if not network_hook_installed then hookNetworkSend() end
            if not spawn_hook_installed   then hookOnVehicleSpawned() end
        end
    end

    if pending_wanted then
        guiTrigger("EconomyUI_WantedUpdate", pending_wanted)
        pending_wanted = nil
    end

    if M._delayHandlers then
        for i = #M._delayHandlers, 1, -1 do
            M._delayHandlers[i](dt)
        end
    end

    detectEditingMode(dt)

    editing_state_sync_timer = editing_state_sync_timer + dt
    if editing_state_sync_timer > 2.0 then
        editing_state_sync_timer = 0
        if is_editing_vehicle then
            guiTrigger("ECON_EditingModeUpdate", { isEditing = true })
        end
    end

    local worldReady = worldReadyState and (worldReadyState == 2) or noRepairState.worldReady
    if worldReady then
        processTeleportQueue(dt)
        drawMarkers(dt)
        drawHiddenMarker()
    end

    local inMP = MPCoreNetwork and type(MPCoreNetwork.isMPSession) == "function" and MPCoreNetwork.isMPSession()
    if inMP and not is_admin and editor and editor.isEditorActive and editor.isEditorActive() then
        if editor.setEditorActive then editor.setEditorActive(false) end
    end
end

M.onInit = function() setExtensionUnloadMode(M, "manual") end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

M.getCurrentPrefix      = function() return current_prefix end
M.isNoRepairEnabled     = function() return noRepairState.enabled end
M.getSpawnPoint         = function() return noRepairState.spawnPoint end
M.isWorldReady          = function()
    if worldReadyState then return worldReadyState == 2 end
    return noRepairState.worldReady
end
M.isPoliceNearby        = function() return police_nearby end
M.getBustProgress       = function() return bust_progress end
M.getRepairIconsCount   = function() return repair_icons_count end
M.getActiveMarkers      = function() return active_markers end
M.getCurrentRankData    = function() return current_rank_data end
M.getServerTranslations = function() return server_translations end
M.getCurrentLang        = function() return current_lang end
M.getWantedEnabled      = function() return wanted_enabled end
M.isEditingVehicle      = function() return is_editing_vehicle end
M.getDefenseStats       = function() return DEFENSE_STATS end
M.getVehiclesInBlobMode = function() return vehicles_in_blob_mode end
M.printDefenseStats     = printDefenseStats

M.debugAP = function()
    if not ap_hidden_marker then
        print("[AP] ap_hidden_marker is NIL - server never sent SetMarker")
        return
    end
    print("[AP] marker pos: " .. tostring(ap_hidden_marker.pos))
    print("[AP] available: "  .. tostring(ap_hidden_marker.available))
    print("[AP] radius: "     .. tostring(ap_hidden_marker.visibility_radius))
    print("[AP] worldReady: " .. tostring(worldReadyState))
    print("[AP] registered: " .. tostring(registered_events))
    local veh = be:getPlayerVehicle(0)
    if veh then
        local dist = (veh:getPosition() - ap_hidden_marker.pos):length()
        print("[AP] dist to marker: " .. string.format("%.1f", dist) .. "m")
    else
        print("[AP] no vehicle")
    end
end

-- =============================================================================
-- GLOBAL EXPORTS
-- =============================================================================

_G.finishVehicleEditing = finishVehicleEditing

_G.toggleWantedEnabled = function()
    wanted_enabled = not wanted_enabled
    if type(TriggerServerEvent) == "function" then
        TriggerServerEvent('ECON_ToggleWanted', jsonEncode({ enabled = wanted_enabled }))
    end
end

_G.setPlayerLanguage = function(langCode)
    if type(TriggerServerEvent) == "function" then
        TriggerServerEvent('setPlayerLanguage', langCode)
    end
end

_G.requestOptionalSpawn = function(spawn_index)
    if type(TriggerServerEvent) == "function" then
        TriggerServerEvent('ECON_OptionalSpawn', jsonEncode({ spawn_index = spawn_index }))
    end
end

_G.reportQueueToServer = function(pidsJson)
    if type(TriggerServerEvent) == "function" then
        TriggerServerEvent('ECON_QueueReport', pidsJson)
    end
end

_G.reportPlayerSynced = function(syncedPidStr)
    if type(TriggerServerEvent) == "function" then
        TriggerServerEvent('ECON_PlayerSynced', syncedPidStr)
    end
end

_G.debugMinimap = function()
    if extensions and extensions.minimap then
        local data = extensions.minimap.getCurrentData()
        print("=== Minimap Debug ===")
        print("policeMode: "    .. tostring(data.policeMode))
        print("distToTarget: "  .. tostring(data.distToTarget))
        print("locationName: "  .. tostring(data.locationName))
        print("====================")
    else
        print("Minimap extension not loaded")
    end
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

pcall(function()
    if type(guihooks) ~= "undefined" and guihooks.on then
        guihooks.on("EconomyUI_WantedUpdate",       function(payload) end)
        guihooks.on("EconomyUI_PoliceProximity",    function(p) end)
        guihooks.on("EconomyUI_BustProgress",       function(p) end)
        guihooks.on("EconomyUI_RepairIcons",        function(p) end)
        guihooks.on("EconomyUI_TranslationsUpdate", function(data) end)
        guihooks.on("EconomyUI_RankUpdate",         function(data) end)
        guihooks.on("EconomyUI_TaskProgress",       function(data) end)
        guihooks.on("EconomyUI_RankUp",             function(data) end)
        guihooks.on("EconomyUI_ShowRankPanel",      function() end)
        guihooks.on("POLICE_WantedListUpdate",      function(payload) end)
        guihooks.on("POLICE_RoleUpdate",            function(data) end)
    end
end)

try_register()

return M
