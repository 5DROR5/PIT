-- =============================================================================
-- PIT Economy System - Parts Price Display
-- License: AGPL-3.0 - https://www.gnu.org/licenses/agpl-3.0.html
-- =============================================================================

local M = {}

local jbeamIO               = require('jbeam/io')
local origGetAvailableParts = jbeamIO.getAvailableParts
local priceCache            = {}
local freeVehicles          = {}
local bannedVehicles        = {}
local bannedParts           = {}

-- =============================================================================
-- PRICE BUILDING
-- =============================================================================

local function buildAndCache(vehId)
    local vd  = core_vehicle_manager.getVehicleData(vehId)
    local veh = getObjectByID(vehId)
    if not vd or not vd.ioCtx or not veh then return end

    local parts  = origGetAvailableParts(vd.ioCtx)
    local prices = {}
    local series = veh:getJBeamFilename():lower()

    if bannedVehicles[series] then
        for partName in pairs(parts) do prices[partName] = -1 end
    elseif freeVehicles[series] then
        for partName in pairs(parts) do prices[partName] = 0 end
    else
        for partName in pairs(parts) do
            if bannedParts[partName] then
                prices[partName] = -1
            else
                local part = jbeamIO.getPart(vd.ioCtx, partName)
                if part and part.information and (part.information.value or 0) > 0 then
                    prices[partName] = part.information.value
                end
            end
        end
    end

    priceCache[vehId] = prices
    extensions.core_vehicle_partmgmt.onVehicleSpawned(vehId)
end

-- =============================================================================
-- MONKEY-PATCH
-- =============================================================================

jbeamIO.getAvailableParts = function(ioCtx)
    local parts  = origGetAvailableParts(ioCtx)
    local veh    = getPlayerVehicle(0)
    if not veh then return parts end
    local prices = priceCache[veh:getID()]
    if not prices then return parts end

    local enriched = {}
    for partName, partDesc in pairs(parts) do
        local price = prices[partName]
        if price then
            local e = {}
            for k, v in pairs(partDesc) do e[k] = v end
            if price == -1 then
                e.description = partDesc.description .. '  [Banned]'
            elseif price == 0 then
                e.description = partDesc.description .. '  [Free]'
            else
                e.description = string.format('%s  [$%d]', partDesc.description, price)
            end
            enriched[partName] = e
        else
            enriched[partName] = partDesc
        end
    end
    return enriched
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

function M.setConfig(data)
    freeVehicles   = {}
    bannedVehicles = {}
    bannedParts    = {}
    if data.freeVehicles   then for _, s in ipairs(data.freeVehicles)   do freeVehicles[s]   = true end end
    if data.bannedVehicles then for _, s in ipairs(data.bannedVehicles) do bannedVehicles[s] = true end end
    if data.bannedParts    then for _, s in ipairs(data.bannedParts)    do bannedParts[s]    = true end end
    local veh = getPlayerVehicle(0)
    if veh then buildAndCache(veh:getID()) end
end

-- =============================================================================
-- HOOKS
-- =============================================================================

function M.onExtensionLoaded()
    local veh = getPlayerVehicle(0)
    if veh then buildAndCache(veh:getID()) end
end

function M.onVehicleSpawned(vehId)
    buildAndCache(vehId)
end

function M.onExtensionUnloaded()
    jbeamIO.getAvailableParts = origGetAvailableParts
    priceCache     = {}
    freeVehicles   = {}
    bannedVehicles = {}
    bannedParts    = {}
end

return M