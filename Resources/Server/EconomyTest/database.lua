-- =============================================================================
-- PIT Economy System — Database Layer
-- Backends: MySQL (primary) · JSON file (automatic fallback)
-- License: AGPL-3.0 — https://www.gnu.org/licenses/agpl-3.0.html
-- =============================================================================

local M    = {}
local ROOT = "Resources/Server/EconomyTest"

M.BACKEND_MYSQL = "mysql"
M.BACKEND_JSON  = "json"


-- =============================================================================
-- STATE
-- =============================================================================

local backend = nil
local conn    = nil
local env     = nil

local LOCAL_DB_PATH = ROOT .. "/local_storage.json"
local _store        = { players = {} }
local _dirty        = false
local _last_save    = 0
local AUTOSAVE_SECS = 30


-- =============================================================================
-- UTILITIES
-- =============================================================================

local function log(msg) print("[DB] " .. tostring(msg)) end

local function fileExists(path)
    local f = io.open(path, "r"); if f then f:close(); return true end; return false
end

local function readFile(path)
    local f = io.open(path, "r"); if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end

local function writeFile(path, s)
    local f = io.open(path, "w+"); if not f then return false end
    local ok = pcall(f.write, f, s); f:close(); return ok
end

local function jsonEnc(t)
    if type(Util) == "table" and Util.JsonEncode then
        local ok, s = pcall(Util.JsonEncode, t)
        if ok and type(s) == "string" then return s end
    end
    return nil
end

local function jsonDec(s)
    if type(s) ~= "string" then return nil end
    if type(Util) == "table" and Util.JsonDecode then
        local ok, t = pcall(Util.JsonDecode, s)
        if ok then return t end
    end
    return nil
end


-- =============================================================================
-- JSON BACKEND
-- =============================================================================

local function j_load()
    if fileExists(LOCAL_DB_PATH) then
        local t = jsonDec(readFile(LOCAL_DB_PATH) or "")
        if type(t) == "table" then
            _store         = t
            _store.players = _store.players or {}
            local n = 0; for _ in pairs(_store.players) do n = n + 1 end
            log(string.format("JSON backend: loaded %d player record(s)", n))
            return
        end
    end
    _store = { players = {} }
    log("JSON backend: starting with empty store")
end

local function j_flush()
    local s = jsonEnc(_store)
    if not s then log("ERROR: JSON encode failed"); return false end
    local tmp = LOCAL_DB_PATH .. ".tmp"
    if not writeFile(tmp, s) then log("ERROR: cannot write temp file"); return false end
    if FS and FS.Rename then pcall(FS.Rename, tmp, LOCAL_DB_PATH)
    else writeFile(LOCAL_DB_PATH, s) end
    _dirty = false; _last_save = os.time()
    return true
end

local function j_player(uid, starting_money)
    if not _store.players[uid] then
        _store.players[uid] = {
            name                      = "Unknown",
            money                     = tonumber(starting_money) or 0,
            role                      = "civilian",
            lang                      = "en",
            player_rank               = 1,
            task_progress             = "{}",
            last_police_payment       = 0,
            is_wanted                 = false,
            wanted_count              = 0,
            wanted_success            = 0,
            wanted_failed             = 0,
            police_arrests            = 0,
            total_chase_time_seconds  = 0,
            total_wanted_time_seconds = 0,
            markers_captured_police   = 0,
            markers_captured_wanted   = 0,
            total_money_earned        = 0,
            total_money_spent         = 0,
            total_playtime_seconds    = 0,
            login_count               = 0,
            purchased_parts           = {},
        }
        _dirty = true
    end
    return _store.players[uid]
end


-- =============================================================================
-- MYSQL BACKEND
-- =============================================================================

local function mysql_load_config()
    local s   = readFile(ROOT .. "/db.json")
    local cfg = s and jsonDec(s)
    return (type(cfg) == "table" and cfg.host) and cfg or nil
end

local function mysql_try_connect(cfg)
    local ok_drv, drv = pcall(require, "luasql.mysql")
    if not ok_drv then return nil, "luasql.mysql not found" end
    env = drv.mysql()
    local ok_c, c = pcall(env.connect, env, cfg.database, cfg.user, cfg.password, cfg.host, cfg.port or 3306)
    if not ok_c then return nil, tostring(c) end
    return c, nil
end

local function esc(v)
    local s = type(v) == "string" and v or tostring(v)
    return "'" .. (s:gsub("'", "''")) .. "'"
end

local function q(sql)
    if not conn then return nil end
    local ok, cur = pcall(conn.execute, conn, sql)
    if not ok then log("SQL error: " .. tostring(cur) .. "\n  query: " .. sql); return nil end
    return cur
end

local function q1(sql)
    local cur = q(sql); if not cur then return nil end
    local row = cur:fetch({}, "a"); cur:close(); return row
end

local function columnExists(tbl, col)
    local r = q1(string.format(
        "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='%s' AND COLUMN_NAME='%s'",
        tbl, col))
    return r ~= nil
end

local function ensureColumn(tbl, col, def)
    if not columnExists(tbl, col) then
        q(string.format("ALTER TABLE %s ADD COLUMN %s %s", tbl, col, def))
        log(string.format("Added column %s.%s", tbl, col))
    end
end


-- =============================================================================
-- CONNECTION
-- =============================================================================

function M.connect()
    if conn then
        local ok, res = pcall(conn.execute, conn, "SELECT 1")
        if ok and res then
            if type(res) ~= "number" then pcall(res.close, res) end
            return true
        end
        log("MySQL connection lost — reconnecting...")
        if conn then pcall(conn.close, conn); conn = nil end
        if env  then pcall(env.close,  env);  env  = nil end
    end

    local cfg = mysql_load_config()
    if cfg then
        local c, err = mysql_try_connect(cfg)
        if c then
            conn = c
            pcall(conn.execute, conn, "SET NAMES utf8mb4")
            pcall(conn.execute, conn, "SET SESSION wait_timeout = 604800")
            pcall(conn.execute, conn, "SET SESSION interactive_timeout = 604800")
            backend = M.BACKEND_MYSQL
            log("Backend: MySQL (" .. cfg.host .. " / " .. cfg.database .. ")")
            ensureColumn("players", "player_rank",               "INT NOT NULL DEFAULT 1")
            ensureColumn("players", "task_progress",             "TEXT DEFAULT NULL")
            ensureColumn("players", "last_police_payment",       "BIGINT DEFAULT 0")
            ensureColumn("players", "is_wanted",                 "TINYINT(1) DEFAULT 0")
            ensureColumn("players", "total_chase_time_seconds",  "INT(11) DEFAULT 0")
            ensureColumn("players", "total_wanted_time_seconds", "INT(11) DEFAULT 0")
            ensureColumn("players", "markers_captured_police",   "INT(11) DEFAULT 0")
            ensureColumn("players", "markers_captured_wanted",   "INT(11) DEFAULT 0")
            ensureColumn("players", "total_money_earned",        "BIGINT DEFAULT 0")
            ensureColumn("players", "total_money_spent",         "BIGINT DEFAULT 0")
            ensureColumn("players", "total_playtime_seconds",    "INT(11) DEFAULT 0")
            ensureColumn("players", "login_count",               "INT(11) DEFAULT 0")
            return true
        end
        log("MySQL unavailable: " .. tostring(err) .. " — falling back to JSON")
    else
        log("db.json not found — using JSON storage")
    end

    j_load()
    backend = M.BACKEND_JSON
    log("Backend: JSON (" .. LOCAL_DB_PATH .. ")")
    return true
end

function M.getBackend() return backend end

function M.tick()
    if backend == M.BACKEND_JSON and _dirty and (os.time() - _last_save) >= AUTOSAVE_SECS then
        j_flush()
    end
end

function M.flush()
    if backend == M.BACKEND_JSON and _dirty then j_flush() end
end

function M.close()
    M.flush()
    if conn then pcall(conn.close, conn); conn = nil end
    if env  then pcall(env.close,  env);  env  = nil end
    log("Connection closed")
end


-- =============================================================================
-- PLAYER FUNCTIONS
-- =============================================================================

function M.ensurePlayer(uid, name, _identifiers, starting_money)
    if backend == M.BACKEND_MYSQL then
        local sn = esc(name or "Unknown")
        q(string.format(
            "INSERT INTO players (uid, name, money, role, lang, created_at, last_seen, player_rank, task_progress) "
            .. "VALUES (%s, %s, %d, 'civilian', 'en', NOW(), NOW(), 1, '{}') "
            .. "ON DUPLICATE KEY UPDATE name=%s, last_seen=NOW()",
            esc(uid), sn, tonumber(starting_money) or 0, sn))
    else
        local p = j_player(uid, starting_money)
        if name then p.name = name; _dirty = true end
    end
end

function M.getMoney(uid)
    if backend == M.BACKEND_MYSQL then
        local r = q1("SELECT money FROM players WHERE uid=" .. esc(uid))
        return r and tonumber(r.money) or 0
    else
        return j_player(uid).money or 0
    end
end

function M.addMoney(uid, amt)
    amt = tonumber(amt) or 0
    if backend == M.BACKEND_MYSQL then
        q(string.format(
            "UPDATE players SET money = GREATEST(0, money + %d) WHERE uid=%s", amt, esc(uid)))
        if amt > 0 then
            q(string.format(
                "UPDATE players SET total_money_earned = total_money_earned + %d WHERE uid=%s",
                amt, esc(uid)))
        elseif amt < 0 then
            q(string.format(
                "UPDATE players SET total_money_spent = total_money_spent + %d WHERE uid=%s",
                -amt, esc(uid)))
        end
    else
        local p = j_player(uid)
        p.money = math.max(0, (p.money or 0) + amt)
        if     amt > 0 then p.total_money_earned = (p.total_money_earned or 0) + amt
        elseif amt < 0 then p.total_money_spent  = (p.total_money_spent  or 0) + (-amt) end
        _dirty = true
    end
end

function M.getRole(uid)
    if backend == M.BACKEND_MYSQL then
        local r = q1("SELECT role FROM players WHERE uid=" .. esc(uid))
        return r and r.role or "civilian"
    else
        return j_player(uid).role or "civilian"
    end
end

function M.setRole(uid, role)
    if backend == M.BACKEND_MYSQL then
        q(string.format("UPDATE players SET role=%s WHERE uid=%s", esc(role), esc(uid)))
    else
        j_player(uid).role = role; _dirty = true
    end
end

function M.getLang(uid)
    if backend == M.BACKEND_MYSQL then
        local r = q1("SELECT lang FROM players WHERE uid=" .. esc(uid))
        return r and r.lang or "en"
    else
        return j_player(uid).lang or "en"
    end
end

function M.setLang(uid, lang)
    if backend == M.BACKEND_MYSQL then
        q(string.format("UPDATE players SET lang=%s WHERE uid=%s", esc(lang), esc(uid)))
    else
        j_player(uid).lang = lang; _dirty = true
    end
end

function M.getLastPolicePayment(uid)
    if backend == M.BACKEND_MYSQL then
        local r = q1("SELECT last_police_payment FROM players WHERE uid=" .. esc(uid))
        return r and tonumber(r.last_police_payment) or 0
    else
        return j_player(uid).last_police_payment or 0
    end
end

function M.setLastPolicePayment(uid, t)
    if backend == M.BACKEND_MYSQL then
        q(string.format(
            "UPDATE players SET last_police_payment=%d WHERE uid=%s", tonumber(t) or 0, esc(uid)))
    else
        j_player(uid).last_police_payment = t; _dirty = true
    end
end

function M.setWanted(uid, wanted)
    if backend == M.BACKEND_MYSQL then
        q(string.format(
            "UPDATE players SET is_wanted=%d WHERE uid=%s", wanted and 1 or 0, esc(uid)))
    else
        j_player(uid).is_wanted = wanted; _dirty = true
    end
end


-- =============================================================================
-- RANK SYSTEM
-- =============================================================================

function M.getRank(uid)
    if backend == M.BACKEND_MYSQL then
        local r = q1("SELECT player_rank FROM players WHERE uid=" .. esc(uid))
        return r and tonumber(r.player_rank) or 1
    else
        return j_player(uid).player_rank or 1
    end
end

function M.setRank(uid, rank)
    rank = math.max(1, math.min(5, tonumber(rank) or 1))
    if backend == M.BACKEND_MYSQL then
        q(string.format("UPDATE players SET player_rank=%d WHERE uid=%s", rank, esc(uid)))
    else
        j_player(uid).player_rank = rank; _dirty = true
    end
end

function M.getTaskProgress(uid)
    if backend == M.BACKEND_MYSQL then
        local r = q1("SELECT task_progress FROM players WHERE uid=" .. esc(uid))
        return (r and r.task_progress ~= "") and r.task_progress or "{}"
    else
        return j_player(uid).task_progress or "{}"
    end
end

function M.setTaskProgress(uid, data)
    local s = type(data) == "table" and (jsonEnc(data) or "{}") or tostring(data)
    if s == "" then s = "{}" end
    if backend == M.BACKEND_MYSQL then
        q(string.format("UPDATE players SET task_progress=%s WHERE uid=%s", esc(s), esc(uid)))
    else
        j_player(uid).task_progress = s; _dirty = true
    end
end

function M.savePlayerRankData(uid, rank, progress_json)
    rank = math.max(1, math.min(5, tonumber(rank) or 1))
    local s = tostring(progress_json or "{}"); if s == "" then s = "{}" end
    if backend == M.BACKEND_MYSQL then
        q(string.format(
            "UPDATE players SET player_rank=%d, task_progress=%s WHERE uid=%s",
            rank, esc(s), esc(uid)))
    else
        local p = j_player(uid)
        p.player_rank   = rank
        p.task_progress = s
        _dirty = true
    end
end


-- =============================================================================
-- STATISTICS
-- =============================================================================

local function _inc(uid, col)
    if backend == M.BACKEND_MYSQL then
        q(string.format("UPDATE players SET %s=%s+1 WHERE uid=%s", col, col, esc(uid)))
    else
        local p = j_player(uid); p[col] = (p[col] or 0) + 1; _dirty = true
    end
end

local function _add(uid, col, n)
    n = math.floor(tonumber(n) or 0); if n == 0 then return end
    if backend == M.BACKEND_MYSQL then
        q(string.format("UPDATE players SET %s=%s+%d WHERE uid=%s", col, col, n, esc(uid)))
    else
        local p = j_player(uid); p[col] = (p[col] or 0) + n; _dirty = true
    end
end

function M.incrementWantedCount(uid)   _inc(uid, "wanted_count")              end
function M.incrementWantedSuccess(uid) _inc(uid, "wanted_success")            end
function M.incrementWantedFailed(uid)  _inc(uid, "wanted_failed")             end
function M.incrementPoliceArrests(uid) _inc(uid, "police_arrests")            end
function M.incrementLoginCount(uid)    _inc(uid, "login_count")               end
function M.incrementMarkersPolice(uid) _inc(uid, "markers_captured_police")   end
function M.incrementMarkersWanted(uid) _inc(uid, "markers_captured_wanted")   end
function M.addChaseTime(uid, secs)     _add(uid, "total_chase_time_seconds",  secs) end
function M.addWantedTime(uid, secs)    _add(uid, "total_wanted_time_seconds", secs) end
function M.addPlaytime(uid, secs)      _add(uid, "total_playtime_seconds",    secs) end

function M.getPlayerStats(uid)
    if backend == M.BACKEND_MYSQL then
        local r = q1(string.format([[
            SELECT
                wanted_count, wanted_success, wanted_failed, police_arrests,
                total_chase_time_seconds   AS chase_time,
                total_wanted_time_seconds  AS wanted_time,
                markers_captured_police    AS markers_police,
                markers_captured_wanted    AS markers_wanted,
                total_money_earned         AS money_earned,
                total_money_spent          AS money_spent,
                total_playtime_seconds     AS playtime,
                login_count                AS logins
            FROM players WHERE uid=%s
        ]], esc(uid)))
        if not r then return nil end
        for k, v in pairs(r) do r[k] = tonumber(v) or 0 end
        return r
    else
        local p = _store.players[uid]; if not p then return nil end
        return {
            wanted_count   = p.wanted_count                or 0,
            wanted_success = p.wanted_success              or 0,
            wanted_failed  = p.wanted_failed               or 0,
            police_arrests = p.police_arrests              or 0,
            chase_time     = p.total_chase_time_seconds    or 0,
            wanted_time    = p.total_wanted_time_seconds   or 0,
            markers_police = p.markers_captured_police     or 0,
            markers_wanted = p.markers_captured_wanted     or 0,
            money_earned   = p.total_money_earned          or 0,
            money_spent    = p.total_money_spent           or 0,
            playtime       = p.total_playtime_seconds      or 0,
            logins         = p.login_count                 or 0,
        }
    end
end


-- =============================================================================
-- PARTS SHOP
-- =============================================================================

function M.hasPart(uid, part_key)
    if backend == M.BACKEND_MYSQL then
        local r = q1(string.format(
            "SELECT id FROM purchased_parts WHERE uid=%s AND part_key=%s",
            esc(uid), esc(part_key)))
        return r ~= nil
    else
        local p = j_player(uid)
        return p.purchased_parts ~= nil and p.purchased_parts[part_key] ~= nil
    end
end

function M.buyPart(uid, part_key, part_name, price)
    if backend == M.BACKEND_MYSQL then
        q(string.format(
            "INSERT INTO purchased_parts (uid, part_key, part_name, price) "
            .. "VALUES (%s, %s, %s, %d) "
            .. "ON DUPLICATE KEY UPDATE purchased_at=NOW()",
            esc(uid), esc(part_key), esc(part_name or part_key), tonumber(price) or 0))
    else
        local p = j_player(uid)
        if not p.purchased_parts then p.purchased_parts = {} end
        p.purchased_parts[part_key] = {
            name      = part_name or part_key,
            price     = tonumber(price) or 0,
            bought_at = os.time(),
        }
        _dirty = true
    end
end

return M-- =============================================================================
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
