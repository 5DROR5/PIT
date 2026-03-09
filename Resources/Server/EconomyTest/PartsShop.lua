-- =============================================================================
-- PIT Economy System — Parts Shop
-- License: AGPL-3.0 — https://www.gnu.org/licenses/agpl-3.0.html
-- =============================================================================

local M    = {}
local ROOT = "Resources/Server/EconomyTest"


-- =============================================================================
-- INJECTED DEPENDENCIES
-- =============================================================================

local _log, _MP, _DB
local _encodeJSON, _decodeJSON
local _triggerClient, _sendMessage, _getUID
local _translations


-- =============================================================================
-- STATE
-- =============================================================================

local PARTS_CONFIG    = {}
local FREE_VEHICLES   = {}
local BANNED_VEHICLES = {}


-- =============================================================================
-- UTILITIES
-- =============================================================================

local function fileExists(path)
    local f = io.open(path, "r"); if f then f:close(); return true end; return false
end

local function readFile(path)
    local f = io.open(path, "r"); if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end


-- =============================================================================
-- CONFIG LOADING
-- =============================================================================

local function loadPartsConfig()
    local path = ROOT .. "/parts_config.lua"
    if not fileExists(path) then _log("PartsShop: parts_config.lua not found"); return end
    local ok, cfg = pcall(dofile, path)
    if ok and type(cfg) == "table" then
        PARTS_CONFIG = cfg
        local n = 0; for _ in pairs(PARTS_CONFIG) do n = n + 1 end
        _log(string.format("PartsShop: loaded %d parts", n))
    else
        _log("PartsShop: failed to load parts_config.lua — " .. tostring(cfg))
    end
end

local function loadFreeVehicles()
    local path = ROOT .. "/free_vehicles.lua"
    if not fileExists(path) then return end
    local ok, list = pcall(dofile, path)
    if ok and type(list) == "table" then
        for _, s in ipairs(list) do FREE_VEHICLES[s:lower()] = true end
        _log(string.format("PartsShop: loaded %d free vehicle series", #list))
    end
end

local function loadBannedVehicles()
    local path = ROOT .. "/banned_vehicle_series.lua"
    if not fileExists(path) then return end
    local ok, list = pcall(dofile, path)
    if ok and type(list) == "table" then
        for _, s in ipairs(list) do BANNED_VEHICLES[s:lower()] = true end
        _log(string.format("PartsShop: loaded %d banned vehicle series", #list))
    end
end

-- =============================================================================
-- LOCALIZATION
-- =============================================================================

local function translate(lang, key, vars)
    local text = (_translations[lang] or _translations["en"] or {})[key] or key
    if vars then
        for k, v in pairs(vars) do text = text:gsub("${" .. k .. "}", tostring(v)) end
    end
    return text
end

local function translateForPlayer(pid, key, vars)
    local lang = _DB and _DB.getLang(_getUID(pid)) or "en"
    return translate(lang, key, vars)
end

local function sendLanguageToClient(pid)
    local lang    = _DB and _DB.getLang(_getUID(pid)) or "en"
    local payload = _encodeJSON({ lang = lang, translations = _translations[lang] or _translations["en"] or {} })
    if payload then _triggerClient(pid, "PartsShop_LanguageUpdate", payload) end
end


-- =============================================================================
-- VEHICLE DATA
-- =============================================================================

local function extractVehicleParts(data)
    if not data or type(data) ~= "table" then return {} end
    local parts = {}
    if data.vcf and data.vcf.parts and type(data.vcf.parts) == "table" then
        for _, name in pairs(data.vcf.parts) do
            if type(name) == "string" and name ~= "" then table.insert(parts, name) end
        end
    end
    return parts
end

local function getVehicleSeries(data)
    if not data or type(data) ~= "table" then return nil end
    if data.jbm and type(data.jbm) == "string" then
        local m = data.jbm:lower()
        return m:match("^([^_]+)") or m
    end
    if data.vcf and data.vcf.model then return tostring(data.vcf.model):lower() end
    return nil
end

local function parseVehicleData(raw)
    if type(raw) == "table" then return raw end
    if type(raw) == "string" then
        local m = raw:match("{.*}")
        if m then return _decodeJSON(m) end
    end
    return nil
end


-- =============================================================================
-- PARTS VALIDATION
-- =============================================================================

local function checkPartStatus(part_key)
    local cfg = PARTS_CONFIG[part_key]
    if not cfg then return "banned", -1, part_key end
    local v = cfg.value; local name = cfg.name or part_key
    if     v == nil or v == 0 then return "free",        0, name
    elseif v == -1             then return "banned",     -1, name
    elseif v > 0               then return "purchasable", v, name end
    return "banned", -1, name
end

local function checkVehicleParts(pid, vid, vdata)
    local uid    = _getUID(pid)
    local series = getVehicleSeries(vdata)

    sendLanguageToClient(pid)

    if series and BANNED_VEHICLES[series] then
        _log(string.format("PartsShop: PID=%s series '%s' banned", pid, series))
        local payload = _encodeJSON({
            type   = "series_banned",
            series = series,
            parts  = {{ name = translateForPlayer(pid, "series_banned_text", { series = series }) }},
        })
        if payload then
            _triggerClient(pid, "PartsShop_ShowBanned", payload)
            _triggerClient(pid, "PartsShop_Freeze", "")
        end
        _sendMessage(pid, translateForPlayer(pid, "series_banned_message", { series = series }))
        return
    end

    if series and FREE_VEHICLES[series] then
        local vparts = extractVehicleParts(vdata)
        if #vparts == 0 then _triggerClient(pid, "PartsShop_Unfreeze", ""); return end
        local bad = {}
        for _, key in ipairs(vparts) do
            local cfg = PARTS_CONFIG[key]
            if not cfg then
                table.insert(bad, { key = key, name = key .. " (External Mod)" })
            elseif cfg.value == -1 then
                table.insert(bad, { key = key, name = cfg.name or key })
            end
        end
        if #bad > 0 then
            local payload = _encodeJSON({ type = "banned", parts = bad })
            if payload then
                _triggerClient(pid, "PartsShop_ShowBanned", payload)
                _triggerClient(pid, "PartsShop_Freeze", "")
            end
            _sendMessage(pid, translateForPlayer(pid, "banned_parts_detected"))
        else
            _triggerClient(pid, "PartsShop_Unfreeze", "")
        end
        return
    end

    local vparts = extractVehicleParts(vdata)
    if #vparts == 0 then _triggerClient(pid, "PartsShop_Unfreeze", ""); return end

    local missing, banned2, total_cost = {}, {}, 0
    for _, key in ipairs(vparts) do
        local status, price, name = checkPartStatus(key)
        if status == "banned" then
            table.insert(banned2, { key = key, name = name })
        elseif status == "purchasable" and not _DB.hasPart(uid, key) then
            table.insert(missing, { key = key, name = name, price = price })
            total_cost = total_cost + price
        end
    end

    if #banned2 > 0 then
        local payload = _encodeJSON({ type = "banned", parts = banned2 })
        if payload then
            _triggerClient(pid, "PartsShop_ShowBanned", payload)
            _triggerClient(pid, "PartsShop_Freeze", "")
        end
        _sendMessage(pid, translateForPlayer(pid, "banned_parts_detected"))
        return
    end

    if #missing > 0 then
        local payload = _encodeJSON({
            type        = "purchase",
            parts       = missing,
            totalCost   = total_cost,
            playerMoney = _DB.getMoney(uid),
            vehicleId   = vid,
        })
        if payload then
            _triggerClient(pid, "PartsShop_ShowPurchase", payload)
            _triggerClient(pid, "PartsShop_Freeze", "")
        end
        return
    end

    _triggerClient(pid, "PartsShop_Unfreeze", "")
end


-- =============================================================================
-- EVENT HANDLERS
-- =============================================================================

function M.onVehicleSpawn(pid, vid, data)
    if not (_MP.IsPlayerConnected and _MP.IsPlayerConnected(pid)) then return end
    local vd = parseVehicleData(data)
    if not vd then return end
    checkVehicleParts(pid, vid, vd)
end

function M.onVehicleEdited(pid, vid, data)
    if not (_MP.IsPlayerConnected and _MP.IsPlayerConnected(pid)) then return end
    local vd = parseVehicleData(data)
    if not vd then return end
    checkVehicleParts(pid, vid, vd)
end

function M.onConfirmPurchase(pid, data_str)
    if not (_MP.IsPlayerConnected and _MP.IsPlayerConnected(pid)) then return end
    local data = _decodeJSON(data_str)
    if not data or not data.parts or not data.totalCost then
        _log(string.format("PartsShop: PID=%s invalid purchase payload", pid)); return
    end
    local uid  = _getUID(pid)
    local cost = data.totalCost
    if _DB.getMoney(uid) < cost then
        _sendMessage(pid, translateForPlayer(pid, "insufficient_funds", { missing = cost - _DB.getMoney(uid) }))
        return
    end
    _DB.addMoney(uid, -cost)
    for _, part in ipairs(data.parts) do
        _DB.buyPart(uid, part.key, part.name, part.price)
    end
    _log(string.format("PartsShop: PID=%s purchased %d parts for $%d", pid, #data.parts, cost))
    _sendMessage(pid, translateForPlayer(pid, "purchase_success", { count = #data.parts, cost = cost }))
    _triggerClient(pid, "PartsShop_Unfreeze", "")
    _triggerClient(pid, "receiveMoney", _encodeJSON({ money = _DB.getMoney(uid) }))
end

function M.onPlayerJoin(pid)
    if not (_MP.IsPlayerConnected and _MP.IsPlayerConnected(pid)) then return end
    sendLanguageToClient(pid)
end


-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function M.init(deps)
    _log          = deps.log
    _MP           = deps.MP
    _DB           = deps.DB
    _encodeJSON   = deps.encodeJSON
    _decodeJSON   = deps.decodeJSON
    _triggerClient = deps.triggerClient
    _sendMessage  = deps.sendMessage
    _getUID       = deps.getUID

    _translations = deps.translations
    loadPartsConfig()
    loadFreeVehicles()
    loadBannedVehicles()

    _log("PartsShop: ready")
end

return M
