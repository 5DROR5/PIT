-- =============================================================================
-- PIT Economy System - Vehicle Lua Guard
-- Version: 5.0
-- License: AGPL-3.0 - https://www.gnu.org/licenses/agpl-3.0.html
-- =============================================================================

local M = {}

local PLUGIN = "[VehicleLuaGuard]"

local function cleanStaleExtensions(currentModel, resolvedModules, luaExtensionFuncs)
    local pattern = "^vehicles/" .. currentModel:gsub("%-", "%%-") .. "/"
    local toUnload = {}
    local queued   = {}

    for _, m in ipairs(resolvedModules) do
        local path = m.__extensionPath__ or ""
        if path:match("^vehicles/") and not path:match(pattern) then
            local name = m.__extensionName__
            if not queued[name] then
                table.insert(toUnload, name)
                queued[name] = true
            end
        end
    end

    for name, ext in pairs(extensions) do
        if type(ext) == "table"
           and type(ext.__extensionPath__) == "string"
           and ext.__extensionPath__:match("^vehicles/")
           and not ext.__extensionPath__:match(pattern)
           and not queued[name] then
            table.insert(toUnload, name)
            queued[name] = true
        end
    end

    if #toUnload == 0 then return end

    print(PLUGIN .. " cleaning " .. #toUnload .. " stale extension(s) from previous model")

    for _, name in ipairs(toUnload) do
        if extensions[name] then
            extensions[name].onReset       = nil
            extensions[name].updateGFX     = nil
            extensions[name].onPhysicsStep = nil
            extensions[name].onUpdate      = nil
        end
    end

    if luaExtensionFuncs then
        for k in pairs(luaExtensionFuncs) do
            luaExtensionFuncs[k] = nil
        end
    end

    for _, name in ipairs(toUnload) do
        pcall(extensions.unload, name)
        print(PLUGIN .. (extensions[name] == nil and " [OK]   " or " [FAIL] ") .. name)
    end
end

local function onVehicleLoaded()
    local currentModel = v and v.data and v.data.model
    if not currentModel then
        print(PLUGIN .. " WARNING: v.data.model unavailable")
        return
    end

    local resolvedModules   = nil
    local luaExtensionFuncs = nil

    for _, fn in ipairs({ extensions.printExtensions, extensions.hook }) do
        if type(fn) == "function" then
            local idx = 1
            repeat
                local name, val = debug.getupvalue(fn, idx)
                if name == "resolvedModules"   and type(val) == "table" then resolvedModules   = val end
                if name == "luaExtensionFuncs" and type(val) == "table" then luaExtensionFuncs = val end
                idx = idx + 1
            until not name
        end
        if resolvedModules and luaExtensionFuncs then break end
    end

    if not resolvedModules then
        print(PLUGIN .. " WARNING: resolvedModules not found")
        return
    end

    cleanStaleExtensions(currentModel, resolvedModules, luaExtensionFuncs)

    local origHook = extensions.hook
    extensions.hook = function(funcName, ...)
        if funcName == "updateGFX" then
            extensions.hook = origHook
            pcall(cleanStaleExtensions, currentModel, resolvedModules, luaExtensionFuncs)
        end
        return origHook(funcName, ...)
    end
end

M.onVehicleLoaded = onVehicleLoaded
M.onReset         = onVehicleLoaded

return M