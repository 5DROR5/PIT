-- =============================================================================
-- PartsShop - Client-Side Extension
-- Part of: PIT Economy System
-- License: AGPL-3.0 (https://www.gnu.org/licenses/agpl-3.0.html)
-- =============================================================================

local M = {}

local PLUGIN = "[PartsShop-Client]"

-- =============================================================================
-- STATE
-- =============================================================================
local registered_events = false
local retry_acc         = 0
local RETRY_INTERVAL    = 1.0

local frozen            = false
local lastFreezeCheck   = 0
local pending_ui_data   = nil

-- =============================================================================
-- UTILITIES
-- =============================================================================
local function log(msg) print(PLUGIN .. " " .. tostring(msg)) end

local function parsePayload(payload)
    if type(payload) == "table" then return payload end
    if type(payload) == "string" then
        local ok, decoded = pcall(jsonDecode, payload)
        if ok and type(decoded) == "table" then return decoded end
    end
    return nil
end

local function sendToUI(event, data)
    if type(guihooks) == "table" and type(guihooks.trigger) == "function" then
        guihooks.trigger(event, data)
        return true
    else
        log("WARNING: guihooks not available")
        return false
    end
end

-- =============================================================================
-- VEHICLE CONTROL
-- =============================================================================
local function freeze()
    if frozen then return end
    frozen = true
    local v = be:getPlayerVehicle(0)
    if v then
        core_vehicleBridge.executeAction(v, 'setFreeze', true)
        v:queueLuaCommand('electrics.setIgnitionLevel(0)')
    end
end

local function unfreeze()
    if not frozen then return end
    frozen = false
    local v = be:getPlayerVehicle(0)
    if v then
        core_vehicleBridge.executeAction(v, 'setFreeze', false)
    end
end

-- =============================================================================
-- EVENT HANDLERS
-- =============================================================================
local function onShowPurchaseUI(payload)
    local data = parsePayload(payload)
    if not data then
        log("ERROR: Failed to parse purchase UI data")
        return
    end
    if not sendToUI("PartsShop_ShowPurchase", data) then
        pending_ui_data = { event = "PartsShop_ShowPurchase", data = data }
    end
end

local function onShowBannedUI(payload)
    local data = parsePayload(payload)
    if not data then
        log("ERROR: Failed to parse banned UI data")
        return
    end
    if not sendToUI("PartsShop_ShowBanned", data) then
        pending_ui_data = { event = "PartsShop_ShowBanned", data = data }
    end
end

local function onLanguageUpdate(payload)
    local data = parsePayload(payload)
    if not data or not data.translations then
        log("ERROR: Failed to parse language data")
        return
    end
    if not sendToUI("PartsShop_LanguageUpdate", data) then
        pending_ui_data = { event = "PartsShop_LanguageUpdate", data = data }
    end
end

local function onFreeze(_)   freeze()   end
local function onUnfreeze(_) unfreeze() end

-- =============================================================================
-- UI CALLBACKS (exposed to global scope for UI calls)
-- =============================================================================
function confirmPurchase(dataJson)
    if type(TriggerServerEvent) == "function" then
        TriggerServerEvent('PartsShop_ConfirmPurchase', dataJson)
    else
        log("ERROR: TriggerServerEvent not available")
    end
end

function cancelPurchase(dataJson)
    if type(TriggerServerEvent) == "function" then
        TriggerServerEvent('PartsShop_CancelPurchase', dataJson or "")
    else
        log("ERROR: TriggerServerEvent not available")
    end
end

function closeBannedUI() end

_G.confirmPurchase = confirmPurchase
_G.cancelPurchase  = cancelPurchase
_G.closeBannedUI   = closeBannedUI

-- =============================================================================
-- REGISTRATION
-- =============================================================================
local function try_register()
    if registered_events then return end
    if type(AddEventHandler) ~= "function" then return end

    AddEventHandler("PartsShop_ShowPurchase",   onShowPurchaseUI)
    AddEventHandler("PartsShop_ShowBanned",     onShowBannedUI)
    AddEventHandler("PartsShop_LanguageUpdate", onLanguageUpdate)
    AddEventHandler("PartsShop_Freeze",         onFreeze)
    AddEventHandler("PartsShop_Unfreeze",       onUnfreeze)

    registered_events = true
    log("Event handlers registered")
end

-- =============================================================================
-- UPDATE LOOP
-- =============================================================================
function M.onUpdate(dt)
    if not registered_events then
        retry_acc = retry_acc + (dt or 0)
        if retry_acc >= RETRY_INTERVAL then
            retry_acc = 0
            try_register()
        end
    end

    if pending_ui_data then
        if sendToUI(pending_ui_data.event, pending_ui_data.data) then
            pending_ui_data = nil
        end
    end

    if frozen then
        lastFreezeCheck = lastFreezeCheck + (dt or 0)
        if lastFreezeCheck >= 0.5 then
            lastFreezeCheck = 0
            local v = be:getPlayerVehicle(0)
            if v then
                core_vehicleBridge.executeAction(v, 'setFreeze', true)
            end
        end
    end
end

try_register()

log("Loaded v1.2.0")
return M
