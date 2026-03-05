-- =============================================================================
-- PartsShop - Database Module
-- Part of: PIT Economy System
-- License: AGPL-3.0 (https://www.gnu.org/licenses/agpl-3.0.html)
-- =============================================================================

local M = {}

local luasql = require "luasql.mysql"

local ROOT = "Resources/Server/PartsShop"

-- =============================================================================
-- STATE
-- =============================================================================
local env  = nil
local conn = nil
local DB_CONFIG = {}

-- =============================================================================
-- UTILITIES
-- =============================================================================
local function log(msg) print("[Database-PartsShop] " .. tostring(msg)) end

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function decodeJSON(str)
    if type(str) ~= "string" then return nil end
    if type(Util) == "table" and Util.JsonDecode then
        local ok, t = pcall(Util.JsonDecode, str)
        if ok and type(t) == "table" then return t end
    end
    return nil
end

local function escape(str)
    if not str then return "NULL" end
    return "'" .. tostring(str):gsub("'", "''") .. "'"
end

-- =============================================================================
-- CONFIG LOADING
-- =============================================================================
local function loadConfig()
    local path = ROOT .. "/db.json"
    local s = readFile(path)
    if not s then
        log("ERROR: db.json not found at " .. path)
        return false
    end
    local cfg = decodeJSON(s)
    if not cfg then
        log("ERROR: Failed to parse db.json")
        return false
    end
    DB_CONFIG = cfg
    return true
end

-- =============================================================================
-- CONNECTION
-- =============================================================================
function M.close()
    if conn then conn:close() conn = nil end
    if env  then env:close()  env  = nil end
    log("Connection closed")
end

function M.connect()
    if conn then
        local ok, res = pcall(function() return conn:execute("SELECT 1") end)
        if ok and res then
            if type(res) ~= "number" then pcall(res.close, res) end
            return true
        else
            log("Connection lost - reconnecting")
            M.close()
        end
    end

    if not next(DB_CONFIG) then
        if not loadConfig() then return false end
    end

    env = luasql.mysql()
    local err
    conn, err = env:connect(
        DB_CONFIG.database,
        DB_CONFIG.user,
        DB_CONFIG.password,
        DB_CONFIG.host,
        DB_CONFIG.port
    )

    if not conn then
        log("Failed to connect: " .. tostring(err))
        return false
    end

    conn:execute("SET NAMES utf8mb4")
    conn:execute("SET SESSION wait_timeout = 604800")
    conn:execute("SET SESSION interactive_timeout = 604800")

    log("Connected to MySQL")
    return true
end

-- =============================================================================
-- PLAYER FUNCTIONS
-- =============================================================================
function M.ensurePlayer(uid, name, identifiers, starting_money)
    if not M.connect() then return false end
    starting_money = starting_money or 3333
    local safe_name = escape(name or "Unknown")
    local sql = string.format([[
        INSERT INTO players (uid, name, money, role, lang, created_at, last_seen)
        VALUES (%s, %s, %d, 'civilian', 'en', NOW(), NOW())
        ON DUPLICATE KEY UPDATE name=%s, last_seen=NOW()
    ]], escape(uid), safe_name, starting_money, safe_name)
    local result, err = conn:execute(sql)
    if not result then
        log("Error ensuring player: " .. tostring(err))
        return false
    end
    return true
end

function M.getMoney(uid)
    if not M.connect() then return 0 end
    local cursor, err = conn:execute(
        "SELECT money FROM players WHERE uid=" .. escape(uid)
    )
    if not cursor then
        log("Error getting money: " .. tostring(err))
        return 0
    end
    local row = cursor:fetch({}, "a")
    cursor:close()
    return row and tonumber(row.money) or 0
end

function M.setMoney(uid, amount)
    if not M.connect() then return false end
    amount = math.max(0, tonumber(amount) or 0)
    local result, err = conn:execute(
        string.format("UPDATE players SET money=%d WHERE uid=%s", amount, escape(uid))
    )
    if not result then
        log("Error setting money: " .. tostring(err))
        return false
    end
    return true
end

function M.addMoney(uid, amount)
    local current = M.getMoney(uid)
    local new_amount = math.max(0, current + amount)
    M.setMoney(uid, new_amount)
    return new_amount
end

function M.getRole(uid)
    if not M.connect() then return "civilian" end
    local cursor = conn:execute(
        "SELECT role FROM players WHERE uid=" .. escape(uid)
    )
    if not cursor then return "civilian" end
    local row = cursor:fetch({}, "a")
    cursor:close()
    return row and row.role or "civilian"
end

function M.setRole(uid, role)
    if not M.connect() then return false end
    local result = conn:execute(
        string.format("UPDATE players SET role=%s WHERE uid=%s", escape(role), escape(uid))
    )
    return result ~= nil
end

function M.getLang(uid)
    if not M.connect() then return "en" end
    local cursor = conn:execute(
        "SELECT lang FROM players WHERE uid=" .. escape(uid)
    )
    if not cursor then return "en" end
    local row = cursor:fetch({}, "a")
    cursor:close()
    return row and row.lang or "en"
end

function M.setLang(uid, lang)
    if not M.connect() then return false end
    local result = conn:execute(
        string.format("UPDATE players SET lang=%s WHERE uid=%s", escape(lang), escape(uid))
    )
    return result ~= nil
end

function M.getLastPolicePayment(uid)
    if not M.connect() then return 0 end

    local cursor = conn:execute([[
        SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME='players' AND COLUMN_NAME='last_police_payment'
    ]])
    if cursor then
        local has_column = cursor:fetch({}, "a")
        cursor:close()
        if not has_column then
            conn:execute("ALTER TABLE players ADD COLUMN last_police_payment BIGINT DEFAULT 0")
        end
    end

    cursor = conn:execute(
        "SELECT last_police_payment FROM players WHERE uid=" .. escape(uid)
    )
    if not cursor then return 0 end
    local row = cursor:fetch({}, "a")
    cursor:close()
    return row and tonumber(row.last_police_payment) or 0
end

function M.setLastPolicePayment(uid, time)
    if not M.connect() then return false end
    local result = conn:execute(
        string.format("UPDATE players SET last_police_payment=%d WHERE uid=%s", time, escape(uid))
    )
    return result ~= nil
end

-- =============================================================================
-- PARTS SHOP FUNCTIONS
-- =============================================================================
function M.hasPart(uid, part_key)
    if not M.connect() then return false end
    local cursor = conn:execute(
        string.format("SELECT id FROM purchased_parts WHERE uid=%s AND part_key=%s",
            escape(uid), escape(part_key))
    )
    if not cursor then return false end
    local row = cursor:fetch({}, "a")
    cursor:close()
    return row ~= nil
end

function M.buyPart(uid, part_key, part_name, price)
    if not M.connect() then return false end
    local sql = string.format([[
        INSERT INTO purchased_parts (uid, part_key, part_name, price)
        VALUES (%s, %s, %s, %d)
        ON DUPLICATE KEY UPDATE purchased_at=NOW()
    ]], escape(uid), escape(part_key), escape(part_name), price or 0)
    local result, err = conn:execute(sql)
    if not result then
        log("Error buying part: " .. tostring(err))
        return false
    end
    return true
end

function M.getPlayerParts(uid)
    if not M.connect() then return {} end
    local cursor = conn:execute(
        string.format("SELECT part_key, part_name, price FROM purchased_parts WHERE uid=%s",
            escape(uid))
    )
    if not cursor then return {} end
    local parts = {}
    local row = cursor:fetch({}, "a")
    while row do
        table.insert(parts, {
            key   = row.part_key,
            name  = row.part_name,
            price = tonumber(row.price)
        })
        row = cursor:fetch(row, "a")
    end
    cursor:close()
    return parts
end

function M.isFreeVehicleSeries(series_name)
    if not M.connect() then return false end
    if not series_name or series_name == "" then return false end
    local cursor = conn:execute(
        string.format("SELECT id FROM free_vehicle_series WHERE series_name=%s",
            escape(series_name:lower()))
    )
    if not cursor then return false end
    local row = cursor:fetch({}, "a")
    cursor:close()
    return row ~= nil
end

function M.addFreeVehicleSeries(series_name, description)
    if not M.connect() then return false end
    local sql = string.format([[
        INSERT INTO free_vehicle_series (series_name, description)
        VALUES (%s, %s)
        ON DUPLICATE KEY UPDATE description=%s
    ]], escape(series_name:lower()), escape(description or ""), escape(description or ""))
    local result = conn:execute(sql)
    return result ~= nil
end

return M
