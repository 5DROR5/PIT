-- =============================================================================
-- database.lua
-- MySQL connector for the PIT Economy system.
-- Credentials are loaded from db.json (never committed to version control).
-- Copy db.example.json → db.json and fill in your connection details.
-- License: AGPL-3.0 — https://www.gnu.org/licenses/agpl-3.0.html
-- =============================================================================

local M = {}

local luasql = require "luasql.mysql"

local ROOT = "Resources/Server/EconomyTest"

local env  = nil
local conn = nil


-- =============================================================================
-- CONFIGURATION
-- =============================================================================

local function loadDBConfig()
    local path = ROOT .. "/db.json"
    local f    = io.open(path, "r")
    if not f then
        print("[Database] CRITICAL: db.json not found at " .. path)
        print("[Database] Copy db.example.json to db.json and fill in your credentials.")
        return nil
    end
    local s = f:read("*a")
    f:close()
    local ok, cfg = pcall(function()
        if type(Util) == "table" and Util.JsonDecode then return Util.JsonDecode(s) end
        local json = require("json")
        return json.decode(s)
    end)
    if not ok or type(cfg) ~= "table" then
        print("[Database] CRITICAL: Failed to parse db.json")
        return nil
    end
    if not cfg.host or not cfg.user or not cfg.password or not cfg.database then
        print("[Database] CRITICAL: db.json is missing required fields (host, user, password, database)")
        return nil
    end
    return cfg
end


-- =============================================================================
-- INTERNAL HELPERS
-- =============================================================================

local function escape(str)
    if not str then return "NULL" end
    return "'" .. tostring(str):gsub("'", "''") .. "'"
end

local function columnExists(table_name, column_name)
    if not conn then return false end
    local cursor = conn:execute(string.format(
        "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='%s' AND COLUMN_NAME='%s'",
        table_name, column_name
    ))
    if not cursor then return false end
    local row = cursor:fetch({}, "a")
    cursor:close()
    return row ~= nil
end

local function ensureColumn(table_name, column_name, column_def)
    if not columnExists(table_name, column_name) then
        local result = conn:execute(string.format(
            "ALTER TABLE %s ADD COLUMN %s %s", table_name, column_name, column_def
        ))
        if result then
            print(string.format("[Database] Added column: %s.%s", table_name, column_name))
        end
    end
end


-- =============================================================================
-- CONNECTION
-- =============================================================================

function M.close()
    if conn then conn:close(); conn = nil end
    if env  then env:close();  env  = nil end
    print("[Database] Connection closed")
end

-- Checks if the connection is alive and reconnects if needed.
function M.connect()
    if conn then
        local ok, res = pcall(function() return conn:execute("SELECT 1") end)
        if ok and res then
            if type(res) ~= "number" then pcall(res.close, res) end
            return true
        end
        print("[Database] Connection lost — reconnecting...")
        M.close()
    end

    local cfg = loadDBConfig()
    if not cfg then return false end

    env = luasql.mysql()
    local err
    conn, err = env:connect(cfg.database, cfg.user, cfg.password, cfg.host, cfg.port or 3306)

    if not conn then
        print("[Database] Failed to connect: " .. tostring(err))
        return false
    end

    conn:execute("SET NAMES utf8mb4")
    conn:execute("SET SESSION wait_timeout = 604800")
    conn:execute("SET SESSION interactive_timeout = 604800")

    print("[Database] Connected to MySQL")

    ensureColumn("players", "player_rank",    "INT NOT NULL DEFAULT 1")
    ensureColumn("players", "task_progress",  "TEXT DEFAULT NULL")

    return true
end


-- =============================================================================
-- PLAYER FUNCTIONS
-- =============================================================================

function M.ensurePlayer(uid, name, identifiers, starting_money)
    if not M.connect() then return false end
    starting_money = starting_money or 3333
    local safe_name = escape(name or "Unknown")
    local result, err = conn:execute(string.format([[
        INSERT INTO players (uid, name, money, role, lang, created_at, last_seen, player_rank, task_progress)
        VALUES (%s, %s, %d, 'civilian', 'en', NOW(), NOW(), 1, '{}')
        ON DUPLICATE KEY UPDATE name = %s, last_seen = NOW()
    ]], escape(uid), safe_name, starting_money, safe_name))
    if not result then
        print("[Database] Error ensuring player: " .. tostring(err))
        return false
    end
    return true
end

function M.getMoney(uid)
    if not M.connect() then return 0 end
    local cursor, err = conn:execute("SELECT money FROM players WHERE uid=" .. escape(uid))
    if not cursor then
        print("[Database] Error getting money: " .. tostring(err))
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
        print("[Database] Error setting money: " .. tostring(err))
        return false
    end
    return true
end

function M.addMoney(uid, amount)
    local current    = M.getMoney(uid)
    local new_amount = math.max(0, current + amount)
    M.setMoney(uid, new_amount)
    if amount > 0 then
        M.addMoneyEarned(uid, amount)
    elseif amount < 0 then
        M.addMoneySpent(uid, math.abs(amount))
    end
    return new_amount
end

function M.getRole(uid)
    if not M.connect() then return "civilian" end
    local cursor = conn:execute("SELECT role FROM players WHERE uid=" .. escape(uid))
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
    local cursor = conn:execute("SELECT lang FROM players WHERE uid=" .. escape(uid))
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
    ensureColumn("players", "last_police_payment", "BIGINT DEFAULT 0")
    local cursor = conn:execute(
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
-- RANK SYSTEM
-- =============================================================================

function M.getRank(uid)
    if not M.connect() then return 1 end
    local cursor = conn:execute("SELECT player_rank FROM players WHERE uid=" .. escape(uid))
    if not cursor then return 1 end
    local row = cursor:fetch({}, "a")
    cursor:close()
    return row and tonumber(row.player_rank) or 1
end

function M.setRank(uid, rank)
    if not M.connect() then return false end
    rank = math.max(1, math.min(5, tonumber(rank) or 1))
    local result = conn:execute(
        string.format("UPDATE players SET player_rank=%d WHERE uid=%s", rank, escape(uid))
    )
    return result ~= nil
end

function M.getTaskProgress(uid)
    if not M.connect() then return "{}" end
    local cursor = conn:execute("SELECT task_progress FROM players WHERE uid=" .. escape(uid))
    if not cursor then return "{}" end
    local row = cursor:fetch({}, "a")
    cursor:close()
    if row and row.task_progress and row.task_progress ~= "" then
        return row.task_progress
    end
    return "{}"
end

function M.setTaskProgress(uid, progress_json)
    if not M.connect() then return false end
    if type(progress_json) ~= "string" or progress_json == "" then progress_json = "{}" end
    local result = conn:execute(string.format(
        "UPDATE players SET task_progress=%s WHERE uid=%s",
        escape(progress_json), escape(uid)
    ))
    return result ~= nil
end

function M.savePlayerRankData(uid, rank, progress_json)
    if not M.connect() then return false end
    rank = math.max(1, math.min(5, tonumber(rank) or 1))
    if type(progress_json) ~= "string" or progress_json == "" then progress_json = "{}" end
    local result, err = conn:execute(string.format(
        "UPDATE players SET player_rank=%d, task_progress=%s WHERE uid=%s",
        rank, escape(progress_json), escape(uid)
    ))
    if not result then
        print("[Database] Error saving rank data: " .. tostring(err))
        return false
    end
    return true
end


-- =============================================================================
-- PARTS SHOP
-- =============================================================================

function M.hasPart(uid, part_key)
    if not M.connect() then return false end
    local cursor = conn:execute(string.format(
        "SELECT id FROM purchased_parts WHERE uid=%s AND part_key=%s",
        escape(uid), escape(part_key)
    ))
    if not cursor then return false end
    local row = cursor:fetch({}, "a")
    cursor:close()
    return row ~= nil
end

function M.buyPart(uid, part_key, part_name, price)
    if not M.connect() then return false end
    local result = conn:execute(string.format([[
        INSERT INTO purchased_parts (uid, part_key, part_name, price)
        VALUES (%s, %s, %s, %d)
        ON DUPLICATE KEY UPDATE purchased_at = NOW()
    ]], escape(uid), escape(part_key), escape(part_name), price or 0))
    return result ~= nil
end

function M.getPlayerParts(uid)
    if not M.connect() then return {} end
    local cursor = conn:execute(string.format(
        "SELECT part_key, part_name, price FROM purchased_parts WHERE uid=%s", escape(uid)
    ))
    if not cursor then return {} end
    local parts = {}
    local row   = cursor:fetch({}, "a")
    while row do
        table.insert(parts, { key = row.part_key, name = row.part_name, price = tonumber(row.price) })
        row = cursor:fetch(row, "a")
    end
    cursor:close()
    return parts
end

function M.isFreeVehicleSeries(series_name)
    if not M.connect() then return false end
    if not series_name or series_name == "" then return false end
    local cursor = conn:execute(string.format(
        "SELECT id FROM free_vehicle_series WHERE series_name=%s",
        escape(series_name:lower())
    ))
    if not cursor then return false end
    local row = cursor:fetch({}, "a")
    cursor:close()
    return row ~= nil
end

function M.addFreeVehicleSeries(series_name, description)
    if not M.connect() then return false end
    local result = conn:execute(string.format([[
        INSERT INTO free_vehicle_series (series_name, description)
        VALUES (%s, %s)
        ON DUPLICATE KEY UPDATE description=%s
    ]], escape(series_name:lower()), escape(description or ""), escape(description or "")))
    return result ~= nil
end


-- =============================================================================
-- STATISTICS
-- =============================================================================

function M.incrementWantedCount(uid)
    if not M.connect() then return false end
    return conn:execute(string.format(
        "UPDATE players SET wanted_count = wanted_count + 1 WHERE uid=%s", escape(uid)
    )) ~= nil
end

function M.incrementWantedSuccess(uid)
    if not M.connect() then return false end
    return conn:execute(string.format(
        "UPDATE players SET wanted_success = wanted_success + 1 WHERE uid=%s", escape(uid)
    )) ~= nil
end

function M.incrementWantedFailed(uid)
    if not M.connect() then return false end
    return conn:execute(string.format(
        "UPDATE players SET wanted_failed = wanted_failed + 1 WHERE uid=%s", escape(uid)
    )) ~= nil
end

function M.incrementPoliceArrests(uid)
    if not M.connect() then return false end
    return conn:execute(string.format(
        "UPDATE players SET police_arrests = police_arrests + 1 WHERE uid=%s", escape(uid)
    )) ~= nil
end

function M.getPlayerStats(uid)
    if not M.connect() then return nil end
    ensureColumn("players", "total_chase_time_seconds",  "INT(11) DEFAULT 0")
    ensureColumn("players", "total_wanted_time_seconds", "INT(11) DEFAULT 0")
    ensureColumn("players", "markers_captured_wanted",   "INT(11) DEFAULT 0")
    ensureColumn("players", "markers_captured_police",   "INT(11) DEFAULT 0")
    ensureColumn("players", "total_money_earned",        "BIGINT DEFAULT 0")
    ensureColumn("players", "total_money_spent",         "BIGINT DEFAULT 0")
    ensureColumn("players", "total_playtime_seconds",    "INT(11) DEFAULT 0")
    ensureColumn("players", "login_count",               "INT(11) DEFAULT 0")
    local cursor = conn:execute(string.format([[
        SELECT
            wanted_count, wanted_success, wanted_failed, police_arrests,
            total_chase_time_seconds, total_wanted_time_seconds,
            markers_captured_wanted, markers_captured_police,
            total_money_earned, total_money_spent,
            total_playtime_seconds, login_count
        FROM players WHERE uid=%s
    ]], escape(uid)))
    if not cursor then return nil end
    local row = cursor:fetch({}, "a")
    cursor:close()
    if not row then return nil end
    return {
        wanted_count   = tonumber(row.wanted_count)                or 0,
        wanted_success = tonumber(row.wanted_success)              or 0,
        wanted_failed  = tonumber(row.wanted_failed)               or 0,
        police_arrests = tonumber(row.police_arrests)              or 0,
        chase_time     = tonumber(row.total_chase_time_seconds)    or 0,
        wanted_time    = tonumber(row.total_wanted_time_seconds)   or 0,
        markers_wanted = tonumber(row.markers_captured_wanted)     or 0,
        markers_police = tonumber(row.markers_captured_police)     or 0,
        money_earned   = tonumber(row.total_money_earned)          or 0,
        money_spent    = tonumber(row.total_money_spent)           or 0,
        playtime       = tonumber(row.total_playtime_seconds)      or 0,
        logins         = tonumber(row.login_count)                 or 0,
    }
end

function M.resetPlayerStats(uid)
    if not M.connect() then return false end
    return conn:execute(string.format([[
        UPDATE players
        SET wanted_count = 0, wanted_success = 0, wanted_failed = 0, police_arrests = 0
        WHERE uid=%s
    ]], escape(uid))) ~= nil
end


-- =============================================================================
-- TIME TRACKING
-- =============================================================================

function M.addChaseTime(uid, seconds)
    if not M.connect() then return false end
    ensureColumn("players", "total_chase_time_seconds", "INT(11) DEFAULT 0")
    return conn:execute(string.format(
        "UPDATE players SET total_chase_time_seconds = total_chase_time_seconds + %d WHERE uid=%s",
        math.floor(seconds), escape(uid)
    )) ~= nil
end

function M.addWantedTime(uid, seconds)
    if not M.connect() then return false end
    ensureColumn("players", "total_wanted_time_seconds", "INT(11) DEFAULT 0")
    return conn:execute(string.format(
        "UPDATE players SET total_wanted_time_seconds = total_wanted_time_seconds + %d WHERE uid=%s",
        math.floor(seconds), escape(uid)
    )) ~= nil
end


-- =============================================================================
-- MARKER TRACKING
-- =============================================================================

function M.incrementMarkersWanted(uid)
    if not M.connect() then return false end
    ensureColumn("players", "markers_captured_wanted", "INT(11) DEFAULT 0")
    return conn:execute(string.format(
        "UPDATE players SET markers_captured_wanted = markers_captured_wanted + 1 WHERE uid=%s",
        escape(uid)
    )) ~= nil
end

function M.incrementMarkersPolice(uid)
    if not M.connect() then return false end
    ensureColumn("players", "markers_captured_police", "INT(11) DEFAULT 0")
    return conn:execute(string.format(
        "UPDATE players SET markers_captured_police = markers_captured_police + 1 WHERE uid=%s",
        escape(uid)
    )) ~= nil
end


-- =============================================================================
-- MONEY TRACKING
-- =============================================================================

function M.addMoneyEarned(uid, amount)
    if not M.connect() then return false end
    ensureColumn("players", "total_money_earned", "BIGINT DEFAULT 0")
    return conn:execute(string.format(
        "UPDATE players SET total_money_earned = total_money_earned + %d WHERE uid=%s",
        math.floor(amount), escape(uid)
    )) ~= nil
end

function M.addMoneySpent(uid, amount)
    if not M.connect() then return false end
    ensureColumn("players", "total_money_spent", "BIGINT DEFAULT 0")
    return conn:execute(string.format(
        "UPDATE players SET total_money_spent = total_money_spent + %d WHERE uid=%s",
        math.floor(amount), escape(uid)
    )) ~= nil
end


-- =============================================================================
-- SESSION TRACKING
-- =============================================================================

function M.addPlaytime(uid, seconds)
    if not M.connect() then return false end
    ensureColumn("players", "total_playtime_seconds", "INT(11) DEFAULT 0")
    return conn:execute(string.format(
        "UPDATE players SET total_playtime_seconds = total_playtime_seconds + %d WHERE uid=%s",
        math.floor(seconds), escape(uid)
    )) ~= nil
end

function M.incrementLoginCount(uid)
    if not M.connect() then return false end
    ensureColumn("players", "login_count", "INT(11) DEFAULT 0")
    return conn:execute(string.format(
        "UPDATE players SET login_count = login_count + 1 WHERE uid=%s", escape(uid)
    )) ~= nil
end


-- =============================================================================
-- WANTED STATUS
-- =============================================================================

function M.setWanted(uid, is_wanted)
    if not M.connect() then return false end
    ensureColumn("players", "is_wanted", "TINYINT(1) DEFAULT 0")
    local value  = is_wanted and 1 or 0
    local result = conn:execute(
        string.format("UPDATE players SET is_wanted=%d WHERE uid=%s", value, escape(uid))
    )
    return result ~= nil
end

function M.getWanted(uid)
    if not M.connect() then return false end
    local cursor = conn:execute("SELECT is_wanted FROM players WHERE uid=" .. escape(uid))
    if not cursor then return false end
    local row = cursor:fetch({}, "a")
    cursor:close()
    return row and (tonumber(row.is_wanted) == 1) or false
end

return M
