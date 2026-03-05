-- =============================================================================
-- PartsShop - Vehicle Parts Purchase System
-- Part of: PIT Economy System
-- License: AGPL-3.0 (https://www.gnu.org/licenses/agpl-3.0.html)
-- =============================================================================

local PLUGIN = "[PartsShop]"
local ROOT = "Resources/Server/PartsShop"

-- =============================================================================
-- STATE
-- =============================================================================
local DB = nil
local PARTS_CONFIG = {}
local FREE_VEHICLES = {}
local BANNED_VEHICLES = {}
local translations = {}

-- =============================================================================
-- UTILITIES
-- =============================================================================
local function log(msg) print(PLUGIN .. " " .. tostring(msg)) end

local function fileExists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function encodeJSON(tbl)
    if type(tbl) ~= "table" then return nil end
    if type(Util) == "table" and Util.JsonEncode then
        local ok, s = pcall(Util.JsonEncode, tbl)
        if ok and type(s) == "string" then return s end
    end
    return nil
end

local function decodeJSON(str)
    if type(str) ~= "string" then return nil end
    if type(Util) == "table" and Util.JsonDecode then
        local ok, t = pcall(Util.JsonDecode, str)
        if ok and type(t) == "table" then return t end
    end
    return nil
end

local function loadJSON(path)
    local s = readFile(path)
    if not s or s == "" then return {} end
    local ok, tbl = pcall(decodeJSON, s)
    return (ok and type(tbl) == "table") and tbl or {}
end

local function getUID(pid)
    local ids = (MP and MP.GetPlayerIdentifiers) and MP.GetPlayerIdentifiers(pid) or {}
    return ids.beammp or ids.steam or ids.license or ("pid:" .. pid)
end

local function sendMessage(pid, msg)
    if MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid) then
        pcall(MP.SendChatMessage, pid, msg)
    end
end

local function triggerClient(pid, event, data)
    if MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid) then
        pcall(MP.TriggerClientEvent, pid, event, data)
    end
end

-- =============================================================================
-- CONFIG LOADING
-- =============================================================================
local function loadDatabaseModule()
    local ok, module = pcall(require, "database")
    if not ok then
        log("Failed to load database module: " .. tostring(module))
        return nil
    end
    return module
end

local function loadPartsConfig()
    local path = ROOT .. "/parts_config.lua"
    if not fileExists(path) then
        log("parts_config.lua not found")
        return
    end
    local ok, config = pcall(dofile, path)
    if ok and type(config) == "table" then
        PARTS_CONFIG = config
        local count = 0
        for _ in pairs(PARTS_CONFIG) do count = count + 1 end
        log("Loaded " .. count .. " parts from config")
    else
        log("Failed to load parts_config.lua: " .. tostring(config))
    end
end

local function loadFreeVehicles()
    local path = ROOT .. "/free_vehicles.lua"
    if not fileExists(path) then
        log("free_vehicles.lua not found, no free vehicles defined")
        return
    end
    local ok, list = pcall(dofile, path)
    if ok and type(list) == "table" then
        for _, series in ipairs(list) do
            FREE_VEHICLES[series:lower()] = true
        end
        log("Loaded " .. #list .. " free vehicle series")
    else
        log("Failed to load free_vehicles.lua: " .. tostring(list))
    end
end

local function loadBannedVehicles()
    local path = ROOT .. "/banned_vehicle_series.lua"
    if not fileExists(path) then
        log("banned_vehicle_series.lua not found, no banned series defined")
        return
    end
    local ok, list = pcall(dofile, path)
    if ok and type(list) == "table" then
        for _, series in ipairs(list) do
            BANNED_VEHICLES[series:lower()] = true
        end
        log("Loaded " .. #list .. " banned vehicle series")
    else
        log("Failed to load banned_vehicle_series.lua: " .. tostring(list))
    end
end

local function loadTranslations()
    local langs = { "he", "en", "ar", "de", "it", "fr", "es", "ru" }
    for _, code in ipairs(langs) do
        local path = ROOT .. "/lang/" .. code .. ".json"
        translations[code] = fileExists(path) and loadJSON(path) or {}
    end
    log("Loaded translations")
end

-- =============================================================================
-- LOCALIZATION
-- =============================================================================
local function translate(lang, key, vars)
    local text = (translations[lang] or translations["en"] or {})[key] or key
    if vars then
        for k, v in pairs(vars) do
            text = text:gsub("${" .. k .. "}", tostring(v))
        end
    end
    return text
end

local function translateForPlayer(pid, key, vars)
    local uid = getUID(pid)
    local lang = DB and DB.getLang(uid) or "en"
    return translate(lang, key, vars)
end

local function sendLanguageToClient(pid)
    local uid = getUID(pid)
    local lang = DB and DB.getLang(uid) or "en"
    local trans = translations[lang] or translations["en"] or {}
    local payload = encodeJSON({ lang = lang, translations = trans })
    if payload then
        triggerClient(pid, "PartsShop_LanguageUpdate", payload)
        log(string.format("PID=%s sent language: %s", pid, lang))
    end
end

-- =============================================================================
-- VEHICLE DATA
-- =============================================================================
local function extractVehicleParts(data)
    if not data or type(data) ~= "table" then return {} end
    local parts = {}
    if data.vcf and data.vcf.parts and type(data.vcf.parts) == "table" then
        for _, part_name in pairs(data.vcf.parts) do
            if type(part_name) == "string" and part_name ~= "" then
                table.insert(parts, part_name)
            end
        end
    end
    return parts
end

local function getVehicleSeries(data)
    if not data or type(data) ~= "table" then return nil end
    if data.jbm and type(data.jbm) == "string" then
        local model = data.jbm:lower()
        return model:match("^([^_]+)") or model
    end
    if data.vcf and data.vcf.model then
        return tostring(data.vcf.model):lower()
    end
    return nil
end

local function parseVehicleData(data)
    if type(data) == "table" then return data end
    if type(data) == "string" then
        local json_match = data:match("{.*}")
        if json_match then return decodeJSON(json_match) end
    end
    return nil
end

-- =============================================================================
-- PARTS VALIDATION
-- =============================================================================
local function checkPartStatus(part_key)
    local config = PARTS_CONFIG[part_key]
    if not config then
        return "banned", -1, part_key
    end
    local value = config.value
    local name = config.name or part_key
    if value == nil or value == 0 then
        return "free", 0, name
    elseif value == -1 then
        return "banned", -1, name
    elseif value > 0 then
        return "purchasable", value, name
    end
    return "banned", -1, name
end

local function checkVehicleParts(pid, vid, vehicle_data)
    local uid = getUID(pid)
    local series = getVehicleSeries(vehicle_data)

    sendLanguageToClient(pid)

    if series and BANNED_VEHICLES[series] then
        log(string.format("PID=%s vehicle series '%s' is banned", pid, series))
        local payload = encodeJSON({
            type = "series_banned",
            series = series,
            parts = {{ name = translateForPlayer(pid, "series_banned_text", { series = series }) }}
        })
        if payload then
            triggerClient(pid, "PartsShop_ShowBanned", payload)
            triggerClient(pid, "PartsShop_Freeze", "")
        end
        sendMessage(pid, translateForPlayer(pid, "series_banned_message", { series = series }))
        return
    end

    if series and FREE_VEHICLES[series] then
        log(string.format("PID=%s vehicle series '%s' is free - validating parts", pid, series))
        local vehicle_parts = extractVehicleParts(vehicle_data)
        if #vehicle_parts == 0 then
            log(string.format("PID=%s free vehicle has no parts data - allowing", pid))
            triggerClient(pid, "PartsShop_Unfreeze", "")
            return
        end

        local problematic_parts = {}
        local valid_count = 0
        for _, part_key in ipairs(vehicle_parts) do
            local config = PARTS_CONFIG[part_key]
            if not config then
                table.insert(problematic_parts, { key = part_key, name = part_key .. " (External Mod)" })
            elseif config.value == -1 then
                table.insert(problematic_parts, { key = part_key, name = config.name or part_key })
            else
                valid_count = valid_count + 1
            end
        end

        if #problematic_parts > 0 then
            log(string.format("PID=%s free vehicle blocked: %d/%d parts invalid", pid, #problematic_parts, #vehicle_parts))
            for _, part in ipairs(problematic_parts) do
                log(string.format("  BLOCKED: %s", part.name))
            end
            local payload = encodeJSON({ type = "banned", parts = problematic_parts })
            if payload then
                triggerClient(pid, "PartsShop_ShowBanned", payload)
                triggerClient(pid, "PartsShop_Freeze", "")
            end
            sendMessage(pid, translateForPlayer(pid, "banned_parts_detected"))
            return
        end

        log(string.format("PID=%s free vehicle approved: %d/%d parts valid", pid, valid_count, #vehicle_parts))
        triggerClient(pid, "PartsShop_Unfreeze", "")
        return
    end

    local vehicle_parts = extractVehicleParts(vehicle_data)
    if #vehicle_parts == 0 then
        log(string.format("PID=%s vehicle has no parts data", pid))
        triggerClient(pid, "PartsShop_Unfreeze", "")
        return
    end

    log(string.format("PID=%s vehicle has %d parts", pid, #vehicle_parts))

    local missing_parts = {}
    local banned_parts = {}
    local total_cost = 0

    for _, part_key in ipairs(vehicle_parts) do
        local status, price, name = checkPartStatus(part_key)
        if status == "banned" then
            table.insert(banned_parts, { key = part_key, name = name })
        elseif status == "purchasable" then
            if not DB.hasPart(uid, part_key) then
                table.insert(missing_parts, { key = part_key, name = name, price = price })
                total_cost = total_cost + price
            end
        end
    end

    if #banned_parts > 0 then
        log(string.format("PID=%s vehicle has %d banned parts", pid, #banned_parts))
        local payload = encodeJSON({ type = "banned", parts = banned_parts })
        if payload then
            triggerClient(pid, "PartsShop_ShowBanned", payload)
            triggerClient(pid, "PartsShop_Freeze", "")
        end
        sendMessage(pid, translateForPlayer(pid, "banned_parts_detected"))
        return
    end

    if #missing_parts > 0 then
        log(string.format("PID=%s vehicle missing %d parts, total cost: $%d", pid, #missing_parts, total_cost))
        local player_money = DB.getMoney(uid)
        local payload = encodeJSON({
            type = "purchase",
            parts = missing_parts,
            totalCost = total_cost,
            playerMoney = player_money,
            vehicleId = vid
        })
        if payload then
            triggerClient(pid, "PartsShop_ShowPurchase", payload)
            triggerClient(pid, "PartsShop_Freeze", "")
        end
        return
    end

    log(string.format("PID=%s vehicle has all required parts", pid))
    triggerClient(pid, "PartsShop_Unfreeze", "")
end

-- =============================================================================
-- EVENT HANDLERS
-- =============================================================================
local function onVehicleSpawn(pid, vid, data)
    if not (pid and vid and data) then return end
    if not (MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end
    log(string.format("Vehicle spawn: PID=%s VID=%s", pid, vid))
    local vehicle_data = parseVehicleData(data)
    if not vehicle_data then
        log(string.format("PID=%s failed to parse vehicle data", pid))
        return
    end
    checkVehicleParts(pid, vid, vehicle_data)
end

local function onVehicleEdited(pid, vid, data)
    if not (pid and vid and data) then return end
    if not (MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end
    log(string.format("Vehicle edited: PID=%s VID=%s", pid, vid))
    local vehicle_data = parseVehicleData(data)
    if not vehicle_data then
        log(string.format("PID=%s failed to parse vehicle data on edit", pid))
        return
    end
    checkVehicleParts(pid, vid, vehicle_data)
end

local function onConfirmPurchase(pid, data_str)
    if not (pid and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end
    local data = decodeJSON(data_str)
    if not data or not data.parts or not data.totalCost then
        log(string.format("PID=%s invalid purchase data", pid))
        return
    end
    local uid = getUID(pid)
    local parts = data.parts
    local cost = data.totalCost
    log(string.format("PID=%s confirm purchase: %d parts, cost=$%d", pid, #parts, cost))
    local player_money = DB.getMoney(uid)
    if player_money < cost then
        local missing = cost - player_money
        sendMessage(pid, translateForPlayer(pid, "insufficient_funds", { missing = missing }))
        log(string.format("PID=%s insufficient funds: has $%d, needs $%d", pid, player_money, cost))
        return
    end
    DB.addMoney(uid, -cost)
    for _, part in ipairs(parts) do
        DB.buyPart(uid, part.key, part.name, part.price)
    end
    sendMessage(pid, translateForPlayer(pid, "purchase_success", { count = #parts, cost = cost }))
    log(string.format("PID=%s purchased %d parts for $%d", pid, #parts, cost))
    triggerClient(pid, "PartsShop_Unfreeze", "")
    triggerClient(pid, "receiveMoney", encodeJSON({ money = DB.getMoney(uid) }))
end

local function onCancelPurchase(pid, _)
    log(string.format("PID=%s cancelled purchase", pid))
end

local function onPlayerJoin(pid)
    if not (MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end
    log(string.format("Player joined: PID=%s", pid))
    sendLanguageToClient(pid)
end

local function onLanguageChange(pid, new_lang)
    if not (MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end
    log(string.format("PID=%s language changed to: %s", pid, new_lang))
    local uid = getUID(pid)
    if DB then DB.setLang(uid, new_lang) end
    sendLanguageToClient(pid)
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================
function PS_onInit()
    log("=== Initializing PartsShop v1.2.0 ===")
    DB = loadDatabaseModule()
    if not DB then
        log("CRITICAL: Failed to load database module")
        return
    end
    if not DB.connect() then
        log("CRITICAL: Failed to connect to database")
        return
    end
    loadPartsConfig()
    loadFreeVehicles()
    loadBannedVehicles()
    loadTranslations()
    MP.RegisterEvent("onVehicleSpawn",   "PS_onVehicleSpawn")
    MP.RegisterEvent("onVehicleEdited",  "PS_onVehicleEdited")
    MP.RegisterEvent("onPlayerJoin",     "PS_onPlayerJoin")
    MP.RegisterEvent("PartsShop_ConfirmPurchase", "PS_onConfirmPurchase")
    MP.RegisterEvent("PartsShop_CancelPurchase",  "PS_onCancelPurchase")
    MP.RegisterEvent("PartsShop_LanguageChange",  "PS_onLanguageChange")
    log("=== PartsShop Ready ===")
end

function PS_onVehicleSpawn(pid, vid, data)   onVehicleSpawn(pid, vid, data) end
function PS_onVehicleEdited(pid, vid, data)  onVehicleEdited(pid, vid, data) end
function PS_onConfirmPurchase(pid, data)     onConfirmPurchase(pid, data) end
function PS_onCancelPurchase(pid, data)      onCancelPurchase(pid, data) end
function PS_onPlayerJoin(pid)                onPlayerJoin(pid) end
function PS_onLanguageChange(pid, lang)      onLanguageChange(pid, lang) end

MP.RegisterEvent("onInit", "PS_onInit")

log("PartsShop loaded")
