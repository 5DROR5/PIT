-- =============================================================================
-- PIT Economy System — Server Core
-- Version: 4.0.4
-- License: AGPL-3.0 — https://www.gnu.org/licenses/agpl-3.0.html
-- =============================================================================


-- =============================================================================
-- CONSTANTS
-- =============================================================================

local PLUGIN = "[UIMPIT]"
local ROOT   = "Resources/Server/UIMPIT"

local CurrentMap = nil

local ok_json, json = pcall(require, "json")
if not ok_json then json = nil end


-- =============================================================================
-- LOGGING
-- =============================================================================

local function log(msg)
    print(PLUGIN .. " " .. tostring(msg))
end


-- =============================================================================
-- FILE I/O
-- =============================================================================

local function fileExists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function writeFile(path, content)
    local f = io.open(path, "w+")
    if not f then return false end
    local ok = pcall(f.write, f, content)
    f:close()
    return ok
end


-- =============================================================================
-- JSON
-- =============================================================================

local function encodeJSON(tbl)
    if type(tbl) ~= "table" then return nil end
    if type(Util) == "table" and Util.JsonEncode then
        local ok, s = pcall(Util.JsonEncode, tbl)
        if ok and type(s) == "string" then return s end
    end
    if json and json.encode then
        local ok, s = pcall(json.encode, tbl)
        if ok and type(s) == "string" then return s end
    end
    if tbl.money ~= nil then return '{"money":' .. tostring(tbl.money) .. '}' end
    return nil
end

local function decodeJSON(str)
    if type(str) ~= "string" then return nil end
    if type(Util) == "table" and Util.JsonDecode then
        local ok, t = pcall(Util.JsonDecode, str)
        if ok and type(t) == "table" then return t end
    end
    if json and json.decode then
        local ok, t = pcall(json.decode, str)
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

local function saveJSON(path, tbl)
    local s = encodeJSON(tbl)
    if not s then return false end
    local temp = path .. ".tmp"
    if not writeFile(temp, s) then return false end
    if FS and FS.Rename then
        local ok = pcall(FS.Rename, temp, path)
        if not ok then pcall(FS.Remove, temp); return false end
        return true
    end
    return writeFile(path, s)
end


-- =============================================================================
-- MATH UTILITIES
-- =============================================================================

local function distanceSq(p1, p2)
    local dx = (p1[1] or 0) - (p2[1] or 0)
    local dy = (p1[2] or 0) - (p2[2] or 0)
    local dz = (p1[3] or 0) - (p2[3] or 0)
    return dx*dx + dy*dy + dz*dz
end

local function distance(p1, p2)
    return math.sqrt(distanceSq(p1, p2))
end

local function formatTime(seconds)
    local hours = math.floor(seconds / 3600)
    local mins  = math.floor((seconds % 3600) / 60)
    local secs  = seconds % 60
    return string.format("%02d:%02d:%02d", hours, mins, secs)
end


-- =============================================================================
-- EXTERNAL MODULES
-- =============================================================================

local ranks         = dofile(ROOT .. "/config/RanksConfig.lua")
local locations     = dofile(ROOT .. "/config/SpawnLocations.lua")
local AirPolluter   = dofile(ROOT .. "/modules/AirPolluter.lua")
local MinimapSystem = dofile(ROOT .. "/modules/MinimapSystem.lua")
local PartsShop     = dofile(ROOT .. "/modules/PartsShop.lua")
local msg_colors    = dofile(ROOT .. "/config/MessageColors.lua")


-- =============================================================================
-- CONFIGURATION
-- =============================================================================

local config = {}

local function GetCurrentMap()
    local mapPath = MP.Get(MP.Settings.Map)
    if mapPath then
        local mapName = mapPath:match("/levels/([^/]+)/")
        if mapName then return mapName end
    end
    return "west_coast_usa"
end

local function loadConfig()
    config = loadJSON(ROOT .. "/config/config.json")
    if not config or type(config) ~= "table" then
        log("WARNING: Failed to load config.json, using empty config")
        config = {}
    end
    config.features   = config.features   or {}
    config.general    = config.general    or {}
    config.money      = config.money      or {}
    config.civilian   = config.civilian   or {}
    config.police     = config.police     or {}
    config.markers    = config.markers    or {}
    config.system     = config.system     or {}
    config.timers     = config.timers     or {}
    config.admins     = config.admins     or {}
    config.moderators = config.moderators or {}

    CurrentMap = GetCurrentMap()
    log("========================================")
    log("MAP: " .. CurrentMap)
    log("========================================")

    local map_locations = locations[CurrentMap]
    if not map_locations then
        log("WARNING: No spawn data for map: " .. CurrentMap .. " — falling back to west_coast_usa")
        map_locations = locations["west_coast_usa"]
    end
    if map_locations and map_locations.markers then
        log(string.format("Loaded %d marker spawn points for %s", #map_locations.markers, CurrentMap))
    end
    if map_locations and map_locations.vehicles then
        log(string.format("Loaded %d vehicle spawn points for %s", #map_locations.vehicles, CurrentMap))
    end
    log("Config loaded successfully")
end


-- =============================================================================
-- PLAYER HELPERS
-- =============================================================================

local players_pending_auth  = {}
local player_auth_uids      = {}
local player_display_names  = {}

local function generateGuestUID()
    local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    local t = {}
    math.randomseed(os.time() + math.random(999999))
    for i = 1, 8 do
        local idx = math.random(#chars)
        t[i] = chars:sub(idx, idx)
    end
    return "guest_" .. table.concat(t)
end

local guest_uid_cache = {}

local function getUID(pid)
    if player_auth_uids[pid] then return player_auth_uids[pid] end
    local ids = (MP and MP.GetPlayerIdentifiers) and MP.GetPlayerIdentifiers(pid) or {}
    if ids.beammp or ids.steam or ids.license then
        return ids.beammp or ids.steam or ids.license
    end
    if not guest_uid_cache[pid] then
        guest_uid_cache[pid] = generateGuestUID()
    end
    return guest_uid_cache[pid]
end

local function getPlayerName(pid)
    if player_display_names and player_display_names[pid] then
        return player_display_names[pid]
    end
    if MP and MP.GetPlayerName then
        local ok, name = pcall(MP.GetPlayerName, pid)
        return ok and name or ("Player" .. pid)
    end
    return "Player" .. pid
end

local function getBeammpName(pid)
    if MP and MP.GetPlayerName then
        local ok, name = pcall(MP.GetPlayerName, pid)
        return ok and name or ("Player" .. pid)
    end
    return "Player" .. pid
end

local function forPlayers(fn)
    for pid, _ in pairs(MP.GetPlayers() or {}) do
        if MP.IsPlayerConnected(pid) then fn(pid) end
    end
end

local function sendMessage(pid, msg)
    if not MP or not MP.IsPlayerConnected then return end
    if MP.IsPlayerConnected(pid) then pcall(MP.SendChatMessage, pid, msg) end
end

local function broadcastMessage(msg)
    forPlayers(function(pid) sendMessage(pid, msg) end)
end

local function triggerClient(pid, event, data)
    if not MP or not MP.IsPlayerConnected then return end
    if MP.IsPlayerConnected(pid) then pcall(MP.TriggerClientEvent, pid, event, data) end
end

local function broadcastClientEvent(event, data)
    forPlayers(function(pid) triggerClient(pid, event, data) end)
end


pending_vehicle_changes = pending_vehicle_changes or {}


-- =============================================================================
-- DATABASE INTERFACE
-- =============================================================================

local DB = dofile(ROOT .. "/modules/database.lua")

local function getMoney(uid)                return DB.getMoney(uid) end
local function addMoney(uid, amt)           return DB.addMoney(uid, amt) end
local function getRole(uid)                 return DB.getRole(uid) end
local function setRole(uid, role)           return DB.setRole(uid, role) end
local function getLang(uid)                 return DB.getLang(uid) end
local function setLang(uid, lang)           return DB.setLang(uid, lang) end
local function getLastPolicePayment(uid)    return DB.getLastPolicePayment(uid) end
local function setLastPolicePayment(uid, t) return DB.setLastPolicePayment(uid, t) end


-- =============================================================================
-- TRANSLATION SYSTEM
-- =============================================================================

local BEAMNG_LOCALE_MAP = {
    ["he"]      = "he",      ["he-IL"]  = "he",
    ["en"]      = "en",      ["en-US"]  = "en",      ["en-GB"]  = "en",
    ["ar"]      = "ar",      ["ar-SA"]  = "ar",      ["ar-EG"]  = "ar",
    ["de"]      = "de",      ["de-DE"]  = "de",      ["de-AT"]  = "de",      ["de-CH"] = "de",
    ["it"]      = "it",      ["it-IT"]  = "it",
    ["fr"]      = "fr",      ["fr-FR"]  = "fr",      ["fr-BE"]  = "fr",      ["fr-CH"] = "fr",
    ["es"]      = "es",      ["es-ES"]  = "es",      ["es-MX"]  = "es",
    ["ru"]      = "ru",      ["ru-RU"]  = "ru",
    ["cs"]      = "cs",      ["cs-CZ"]  = "cs",
    ["hu"]      = "hu",      ["hu-HU"]  = "hu",
    ["ja"]      = "ja_JP",   ["ja-JP"]  = "ja_JP",
    ["pl"]      = "pl_PL",   ["pl-PL"]  = "pl_PL",
    ["pt-BR"]   = "pt_BR",
    ["pt"]      = "pt_PT",   ["pt-PT"]  = "pt_PT",
    ["sv"]      = "sv_SE",   ["sv-SE"]  = "sv_SE",
    ["tr"]      = "tr_TR",   ["tr-TR"]  = "tr_TR",
    ["uk"]      = "uk",      ["uk-UA"]  = "uk",
    ["zh"]      = "zh_Hans", ["zh-CN"]  = "zh_Hans", ["zh-Hans"] = "zh_Hans",
}

local function resolveBeamNGLocale(beamng_lang)
    if not beamng_lang or beamng_lang == "" then return nil end
    local mapped = BEAMNG_LOCALE_MAP[beamng_lang]
    if mapped then return mapped end
    local prefix = beamng_lang:match("^([a-zA-Z]+)")
    return prefix and BEAMNG_LOCALE_MAP[prefix:lower()]
end

local translations = {}

local function loadTranslations()
    local langs = { "he", "en", "ar", "de", "it", "fr", "es", "ru", "cs", "hu", "ja_JP", "pl_PL", "pt_BR", "pt_PT", "sv_SE", "tr_TR", "uk", "zh_Hans" }
    for _, code in ipairs(langs) do
        local path = ROOT .. "/lang/" .. code .. ".json"
        translations[code] = fileExists(path) and loadJSON(path) or {}
    end
    log(string.format("Loaded translations for %d languages", #langs))
end

local function translate(lang, key, vars)
    local text = (translations[lang] or {})[key] or (translations["en"] or {})[key] or key

    if not text:match("^%^[a-zA-Z0-9]") then
        local color = msg_colors.keys[key]
        if not color and key:match("^marker_spawned_at_") then
            color = msg_colors.marker_spawned_color
        end
        if color then text = color .. text end
    end

    if vars then
        for k, v in pairs(vars) do
            text = text:gsub("${" .. k .. "}", tostring(v))
        end
    end
    return text
end

local function translateForPlayer(pid, key, vars)
    local lang = (pid == -1) and "en" or (getLang(getUID(pid)) or "en")
    return translate(lang, key, vars)
end

local pending_auth_langs = {}

local function sendTranslationsToClient(pid)
    local uid       = getUID(pid)
    local lang      = getLang(uid) or pending_auth_langs[pid] or "en"
    local lang_data = translations[lang] or translations["en"] or {}
    local payload   = encodeJSON({
        lang          = lang,
        translations  = lang_data,
        auth_required = (players_pending_auth ~= nil and players_pending_auth[pid] == true),
    })
    if payload then triggerClient(pid, "ECON_TranslationsUpdate", payload) end
end


-- =============================================================================
-- RANK SYSTEM
-- =============================================================================

local function getRank(uid)
    if DB.getRank then return DB.getRank(uid) end
    return 1
end

local function setRank(uid, rank)
    if DB.setRank then return DB.setRank(uid, rank) end
end

local function getTaskProgress(uid)
    if DB.getTaskProgress then
        local data = DB.getTaskProgress(uid)
        if type(data) == "string" then return decodeJSON(data) or {} end
        return data or {}
    end
    return {}
end

local function setTaskProgress(uid, progress)
    if DB.setTaskProgress then
        local data = type(progress) == "table" and encodeJSON(progress) or "{}"
        return DB.setTaskProgress(uid, data)
    end
end

local player_rank_cache         = {}
local player_task_cache         = {}
local player_chase_accumulators = {}

local function getPlayerRankData(pid)
    local uid = getUID(pid)
    if not player_rank_cache[uid] then player_rank_cache[uid] = getRank(uid) or 1 end
    if not player_task_cache[uid] then player_task_cache[uid] = getTaskProgress(uid) or {} end
    return player_rank_cache[uid], player_task_cache[uid]
end

local function savePlayerRankData(pid)
    local uid = getUID(pid)
    if player_rank_cache[uid] and player_task_cache[uid] then
        local progress_json = encodeJSON(player_task_cache[uid])
        if DB.savePlayerRankData then
            DB.savePlayerRankData(uid, player_rank_cache[uid], progress_json)
        else
            setRank(uid, player_rank_cache[uid])
            setTaskProgress(uid, player_task_cache[uid])
        end
    end
end

local function sendRankUpdate(pid)
    if not config or not config.features or not ranks then return end
    if not config.features.ranks_enabled then return end
    local uid         = getUID(pid)
    local rank, tasks = getPlayerRankData(pid)
    local rank_config = ranks[rank]
    if not rank_config then return end

    local total_tasks     = #rank_config.tasks
    local completed_tasks = 0
    local task_details    = {}

    for _, task in ipairs(rank_config.tasks) do
        local progress    = tasks[task.id] or 0
        local is_complete = progress >= task.target
        if is_complete then completed_tasks = completed_tasks + 1 end
        local target_minutes = nil
        if task.action == "chase_time" then
            target_minutes = math.floor(task.target / 60)
        end
        table.insert(task_details, {
            id             = task.id,
            type           = task.type,
            name_key       = task.name_key,
            progress       = math.min(progress, task.target),
            target         = task.target,
            target_minutes = target_minutes,
            complete       = is_complete,
        })
    end

    local percent = (total_tasks > 0) and math.floor((completed_tasks / total_tasks) * 100) or 0
    local payload = encodeJSON({
        rank          = rank,
        rank_name_key = rank_config.name_key,
        prefix        = rank_config.prefix,
        percent       = percent,
        completed     = completed_tasks,
        total         = total_tasks,
        tasks         = task_details,
        max_rank      = 5,
    })
    if payload then triggerClient(pid, "ECON_RankUpdate", payload) end
end

local function updateAllPlayerRanks()
    if not config or not config.features then return end
    if not config.features.ranks_enabled then return end
    forPlayers(sendRankUpdate)
end

local checkRankCompletion

local function addTaskProgress(pid, task_id, amount, show_notification)
    if not config.features.ranks_enabled then return end
    local uid         = getUID(pid)
    local rank, tasks = getPlayerRankData(pid)
    local rank_config = ranks[rank]
    if not rank_config then return end

    local task_found = false
    for _, task in ipairs(rank_config.tasks) do
        if task.id == task_id then
            task_found = true
            local old_progress = tasks[task_id] or 0
            if old_progress >= task.target then return end

            local new_progress     = math.min(old_progress + amount, task.target)
            tasks[task_id]         = new_progress
            player_task_cache[uid] = tasks

            local base_points = ranks.task_points[task.action] or 10
            local points_per_unit
            if task.action == "chase_time" then
                points_per_unit = math.floor(amount / 10) * base_points
            else
                points_per_unit = amount * base_points
            end

            if show_notification ~= false and points_per_unit > 0 then
                local payload = encodeJSON({
                    task_id       = task_id,
                    task_name_key = task.name_key,
                    progress      = new_progress,
                    target        = task.target,
                    points        = points_per_unit,
                    complete      = new_progress >= task.target,
                })
                if payload then triggerClient(pid, "ECON_TaskProgress", payload) end
            end
            break
        end
    end

    if task_found then
        checkRankCompletion(pid)
        sendRankUpdate(pid)
    end
end

checkRankCompletion = function(pid)
    local uid         = getUID(pid)
    local rank, tasks = getPlayerRankData(pid)
    local rank_config = ranks[rank]
    if not rank_config or rank >= 5 then return end

    for _, task in ipairs(rank_config.tasks) do
        if (tasks[task.id] or 0) < task.target then return end
    end

    local new_rank        = rank + 1
    local reward          = rank_config.reward
    player_rank_cache[uid] = new_rank
    player_task_cache[uid] = {}

    addMoney(uid, reward)

    local new_rank_config = ranks[new_rank]
    local payload = encodeJSON({
        old_rank   = rank,
        new_rank   = new_rank,
        reward     = reward,
        new_prefix = new_rank_config and new_rank_config.prefix or "",
    })
    if payload then triggerClient(pid, "ECON_RankUp", payload) end

    sendMessage(pid, translateForPlayer(pid, "rank_up_message", { rank = new_rank, reward = reward }))
    broadcastMessage(translateForPlayer(-1, "rank_up_broadcast", { player = getPlayerName(pid), rank = new_rank }))

    savePlayerRankData(pid)
    sendMoneyUpdate(pid)
    updatePrefix(pid)
end


-- =============================================================================
-- PERMISSIONS
-- =============================================================================

local function isAdmin(pid)
    if pid == -1 then return true end
    if not MP.GetPlayerName then return false end
    local name = MP.GetPlayerName(pid) or ""
    local display = player_display_names and player_display_names[pid] or ""
    for _, admin in ipairs(config.admins or {}) do
        if admin == name or admin == display then return true end
    end
    return false
end

local function isModerator(pid)
    if pid == -1 then return false end
    if not MP.GetPlayerName then return false end
    local name = MP.GetPlayerName(pid) or ""
    local display = player_display_names and player_display_names[pid] or ""
    for _, mod in ipairs(config.moderators or {}) do
        if mod == name or mod == display then return true end
    end
    return false
end

local function sendAdminStatus(pid)
    if not (MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end
    local payload = encodeJSON({ isAdmin = isAdmin(pid) })
    if payload then triggerClient(pid, "ECON_AdminStatus", payload) end
end


-- =============================================================================
-- GAME STATE
-- =============================================================================

local wanted_timers            = {}
local wanted_violations        = {}
local last_sent_wanted         = {}
local busted_timers            = {}
local speeding_cooldowns       = {}
local speeding_bonuses         = {}
local zigzag_cooldowns         = {}
local zigzag_bonuses           = {}
local player_zigzag_state      = {}
local player_repair_counters   = {}
local pending_escape_players   = {}
local wanted_disabled_players  = {}
local players_editing_vehicle  = {}
local editing_player_positions = {}
local editing_vehicle_ids      = {}
local police_repair_counters   = {}
local bust_progress            = {}
local approved_repairs         = {}
local player_queue_reports     = {}
local active_markers           = {}
local next_marker_spawn_time   = 0
local player_spawn_indices     = {}
local last_teleport_time       = {}
local spawn_teleport_enabled   = true
local player_transfer_limits   = {}
local players_awaiting_welcome = {}

local sendRepairIcons
local updatePrefix
local sendMoneyUpdate
local clearWanted
local sendPlayerListCustomData
local processPendingVehicleChanges
local sendExistingEditorsToNewPlayer


-- =============================================================================
-- WANTED SYSTEM
-- =============================================================================

local function isWanted(pid)
    return wanted_timers[pid] and wanted_timers[pid] > os.time() * 1000
end

local function sendWantedUI(pid, seconds)
    if not (MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end
    local secs = math.max(0, math.floor(tonumber(seconds) or 0))
    if secs == 0 or last_sent_wanted[pid] ~= secs then
        last_sent_wanted[pid] = secs
        local payload = encodeJSON({ wantedTime = secs })
        if payload then triggerClient(pid, "updateWantedStatus", payload) end
    end
end

local function sendPoliceWantedList(pid)
    if not config.features.roleplay_enabled then return end
    if not (MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end
    local uid = getUID(pid)
    if getRole(uid) ~= "police" then return end

    local wanted_list = {}
    local now         = os.time() * 1000

    if not wanted_timers or type(wanted_timers) ~= "table" then
        triggerClient(pid, "POLICE_WantedListUpdate", '{"wanted_players":[]}')
        return
    end

    local count = 0
    for civil_pid, timer in pairs(wanted_timers) do
        if timer > now and MP.IsPlayerConnected(civil_pid) then
            local violations = wanted_violations[civil_pid] or {}
            local vtype = "unknown"
            if violations.speeding and violations.zigzag then vtype = "both"
            elseif violations.speeding then vtype = "speeding"
            elseif violations.zigzag  then vtype = "zigzag" end

            local remaining
            if pending_escape_players[civil_pid] then
                remaining = math.floor((now - pending_escape_players[civil_pid].started) / 1000)
            else
                remaining = math.max(0, math.floor((timer - now) / 1000))
            end

            local repairs_remaining = 0
            local counter = player_repair_counters[civil_pid]
            if counter then
                repairs_remaining = math.max(0, counter.max_repairs - counter.count)
            end

            table.insert(wanted_list, {
                pid               = civil_pid,
                name              = getPlayerName(civil_pid),
                remaining_seconds = remaining,
                violation_type    = vtype,
                repairs           = repairs_remaining,
            })
            count = count + 1
        end
    end

    local payload = (count == 0) and '{"wanted_players":[]}' or encodeJSON({ wanted_players = wanted_list })
    if payload then triggerClient(pid, "POLICE_WantedListUpdate", payload) end
end

local function updateAllPoliceWantedLists()
    if not config or not config.features then return end
    if not config.features.roleplay_enabled then return end
    forPlayers(function(pid)
        if getRole(getUID(pid)) == "police" then sendPoliceWantedList(pid) end
    end)
end

local function updateWantedTimer(pid, duration_ms, source_key, violation_type)
    if not config.features.roleplay_enabled then return end
    local uid              = getUID(pid)
    local now              = os.time() * 1000
    local current          = wanted_timers[pid] or 0
    local duration_sec     = duration_ms / 1000
    local violation_repairs = 0

    DB.setWanted(uid, true)

    if violation_type == "speeding" then
        violation_repairs = config.civilian.speeding_allowed_repairs or 0
    elseif violation_type == "zigzag" then
        violation_repairs = config.civilian.zigzag_allowed_repairs or 0
    end

    if current < now then
        wanted_timers[pid] = now + duration_ms
        pcall(function() DB.incrementWantedCount(uid) end)
        sendMessage(pid, translateForPlayer(pid, source_key, { duration = duration_sec }))
        broadcastMessage(translateForPlayer(-1, "wanted_global_" .. violation_type, { player = getPlayerName(pid) }))
        wanted_violations[pid]      = { [violation_type] = true }
        player_repair_counters[pid] = {
            count       = 0,
            max_repairs = violation_repairs,
            violations  = { [violation_type] = true },
        }
    else
        if wanted_violations[pid] and wanted_violations[pid][violation_type] then return end

        wanted_timers[pid] = current + duration_ms
        sendMessage(pid, translateForPlayer(pid, "wanted_extended", { seconds = duration_sec }))

        if not wanted_violations[pid] then wanted_violations[pid] = {} end
        wanted_violations[pid][violation_type] = true

        if player_repair_counters[pid] then
            if not player_repair_counters[pid].violations[violation_type] then
                local violations_count = 0
                for _ in pairs(player_repair_counters[pid].violations) do violations_count = violations_count + 1 end

                local MAX_REPAIRS = 2
                if violations_count >= 1 then
                    local combo_repairs     = config.civilian.combo_allowed_repairs or 0
                    local current_available = player_repair_counters[pid].max_repairs - player_repair_counters[pid].count
                    if combo_repairs > 0 and current_available < MAX_REPAIRS then
                        local repairs_to_add = math.min(combo_repairs, MAX_REPAIRS - current_available)
                        player_repair_counters[pid].max_repairs = player_repair_counters[pid].max_repairs + repairs_to_add
                    end
                else
                    local current_available = player_repair_counters[pid].max_repairs - player_repair_counters[pid].count
                    if current_available < MAX_REPAIRS and violation_repairs > 0 then
                        local repairs_to_add = math.min(violation_repairs, MAX_REPAIRS - current_available)
                        player_repair_counters[pid].max_repairs = player_repair_counters[pid].max_repairs + repairs_to_add
                    end
                end
                player_repair_counters[pid].violations[violation_type] = true
            end
        else
            player_repair_counters[pid] = {
                count       = 0,
                max_repairs = violation_repairs,
                violations  = { [violation_type] = true },
            }
        end
    end

    local remaining = math.max(0, math.floor((wanted_timers[pid] - now) / 1000))
    sendWantedUI(pid, remaining)
    updatePrefix(pid)
    sendRepairIcons(pid)
end

local function failWanted(pid, reason_key)
    if not config.features.roleplay_enabled then return end
    if not (MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end
    local uid = getUID(pid)
    if getRole(uid) ~= "civilian" then return end
    if not isWanted(pid) then return end

    if AirPolluter.isActiveMission() and AirPolluter.getActivePid() == pid then
        AirPolluter.onMissionFailed(pid)
        return
    end

    pcall(function() DB.incrementWantedFailed(uid) end)
    local penalty = config.civilian.wanted_fail_penalty
    addMoney(uid, -penalty)
    sendMessage(pid, translateForPlayer(pid, "wanted_fail_message", {
        penalty = penalty,
        reason  = translateForPlayer(pid, reason_key),
    }))
    broadcastMessage(translateForPlayer(-1, "wanted_fail_global", { player = getPlayerName(pid) }))
    sendWantedUI(pid, 0)
    sendMoneyUpdate(pid)
    clearWanted(pid)
    sendWantedUI(pid, 0)
    updatePrefix(pid)
    sendRepairIcons(pid)
end

clearWanted = function(pid)
    local uid = getUID(pid)
    DB.setWanted(uid, false)
    wanted_timers[pid]             = nil
    last_sent_wanted[pid]          = nil
    wanted_violations[pid]         = nil
    player_repair_counters[pid]    = nil
    speeding_bonuses[pid]          = nil
    speeding_cooldowns[pid]        = nil
    zigzag_bonuses[pid]            = nil
    zigzag_cooldowns[pid]          = nil
    player_zigzag_state[pid]       = nil
    busted_timers[pid]             = nil
    player_chase_accumulators[pid] = nil
    pending_escape_players[pid]    = nil
end

local function toggleWantedEnabled(pid, enabled)
    wanted_disabled_players[pid] = not enabled
    local payload = encodeJSON({ wantedEnabled = enabled })
    if payload then triggerClient(pid, "ECON_WantedEnabledUpdate", payload) end
end


-- =============================================================================
-- PENDING ESCAPE SYSTEM
-- =============================================================================

local function isPoliceNearby(pid, range)
    local ok_pos, pos_data = pcall(MP.GetPositionRaw, pid, 0)
    if not (ok_pos and pos_data and pos_data.pos) then return false end
    local civ_pos = pos_data.pos
    local rangeSq = range * range
    for other_pid, _ in pairs(MP.GetPlayers() or {}) do
        if other_pid ~= pid and MP.IsPlayerConnected(other_pid) then
            if getRole(getUID(other_pid)) == "police" then
                local ok_cop, cop_pos = pcall(MP.GetPositionRaw, other_pid, 0)
                if ok_cop and cop_pos and cop_pos.pos then
                    if distanceSq(civ_pos, cop_pos.pos) <= rangeSq then return true end
                end
            end
        end
    end
    return false
end

local function performSuccessfulEscape(pid)
    local uid          = getUID(pid)
    local violations   = wanted_violations[pid] or
                         (pending_escape_players[pid] and pending_escape_players[pid].violations) or {}
    local has_speeding = violations["speeding"]
    local has_zigzag   = violations["zigzag"]
    local bonus        = 0
    local bonus_message = ""

    pcall(function() DB.incrementWantedSuccess(uid) end)

    if has_speeding and has_zigzag then
        bonus         = 2500
        bonus_message = "evaded_both_bonus"
        addTaskProgress(pid, "wanted_combo_1", 1)
        addTaskProgress(pid, "wanted_combo_2", 1)
        addTaskProgress(pid, "wanted_combo_3", 1)
    elseif has_zigzag then
        bonus         = config.civilian.zigzag_final_bonus_amount
        bonus_message = "zigzag_end_reward"
    elseif has_speeding then
        bonus         = config.civilian.speeding_final_bonus_amount
        bonus_message = "speeding_end_reward"
    end

    addTaskProgress(pid, "wanted_escape_1", 1)
    addTaskProgress(pid, "wanted_escape_2", 1)
    addTaskProgress(pid, "wanted_escape_3", 1)
    addTaskProgress(pid, "wanted_escape_4", 1)
    addTaskProgress(pid, "wanted_escape_5", 1)

    sendWantedUI(pid, 0)

    if bonus > 0 then
        addMoney(uid, bonus)
        sendMessage(pid, translateForPlayer(pid, bonus_message, { amount = bonus }))
        sendMoneyUpdate(pid)
    end

    broadcastMessage(translateForPlayer(-1, "wanted_escape_global", { player = getPlayerName(pid) }))
    clearWanted(pid)
    speeding_cooldowns[pid] = now
    zigzag_cooldowns[pid]   = now
    pending_escape_players[pid] = nil
    sendWantedUI(pid, 0)
    updatePrefix(pid)
    sendRepairIcons(pid)
end

local function checkWantedExpiration(pid)
    local now = os.time() * 1000
    if AirPolluter.isActiveMission() and AirPolluter.getActivePid() == pid then return false end
    if wanted_timers[pid] and wanted_timers[pid] <= now then
        if isPoliceNearby(pid, config.police.police_proximity_range_m) then
            if not pending_escape_players[pid] then
                pending_escape_players[pid] = {
                    started    = now,
                    violations = wanted_violations[pid] or {},
                }
                wanted_timers[pid] = now + 999999000
                sendWantedUI(pid, 0)
            end
            return false
        else
            performSuccessfulEscape(pid)
            return true
        end
    end
    return false
end

local function checkPendingEscapes()
    if not next(pending_escape_players) then return end
    local now = os.time() * 1000
    for pid, data in pairs(pending_escape_players) do
        if MP.IsPlayerConnected(pid) then
            if not isPoliceNearby(pid, config.police.police_proximity_range_m) then
                performSuccessfulEscape(pid)
            else
                sendWantedUI(pid, math.floor((now - data.started) / 1000))
            end
        else
            pending_escape_players[pid] = nil
        end
    end
end


-- =============================================================================
-- POLICE SYSTEM
-- =============================================================================

local function sendPoliceRole(pid)
    if not (MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end
    local uid       = getUID(pid)
    local is_police = (getRole(uid) == "police")
    local payload   = encodeJSON({ isPolice = is_police })
    if payload then triggerClient(pid, "POLICE_RoleUpdate", payload) end
end

local function getRemainingPoliceRepairs(pid)
    local bonus = (police_repair_counters[pid] and police_repair_counters[pid].bonus_repairs) or 0
    local base  = config.police.police_allowed_repairs or 0
    local max   = base + bonus
    if not police_repair_counters[pid] then return max end
    local counter = police_repair_counters[pid]
    if os.time() - counter.reset_time >= config.system.repair_reset_time_seconds then return max end
    return math.max(0, max - counter.count)
end

local function usePoliceRepair(pid)
    if not police_repair_counters[pid] then
        police_repair_counters[pid] = { count = 0, reset_time = os.time(), bonus_repairs = 0 }
    end
    local counter = police_repair_counters[pid]
    local now     = os.time()
    local bonus   = counter.bonus_repairs or 0
    local max     = (config.police.police_allowed_repairs or 0) + bonus
    if now - counter.reset_time >= config.system.repair_reset_time_seconds then
        counter.count      = 0
        counter.reset_time = now
    end
    if counter.count >= max then return false end
    counter.count = counter.count + 1
    return true
end

local function isWantedNearby(cop_pid, range)
    local ok_pos, pos_data = pcall(MP.GetPositionRaw, cop_pid, 0)
    if not (ok_pos and pos_data and pos_data.pos) then return false end
    local cop_pos = pos_data.pos
    local rangeSq = range * range
    for pid, _ in pairs(MP.GetPlayers() or {}) do
        if pid ~= cop_pid and MP.IsPlayerConnected(pid) and isWanted(pid) then
            local ok_civ, civ_pos = pcall(MP.GetPositionRaw, pid, 0)
            if ok_civ and civ_pos and civ_pos.pos then
                if distanceSq(cop_pos, civ_pos.pos) <= rangeSq then return true end
            end
        end
    end
    return false
end

local function bustPlayer(civil_pid, nearby_police)
    local civil_name = getPlayerName(civil_pid)
    local is_ap_bust = AirPolluter.isAPPlayer(civil_pid)
    failWanted(civil_pid, "reason_busted")
    broadcastMessage(translateForPlayer(civil_pid, "busted_global_message", { criminal = civil_name }))
    for _, cop_pid in ipairs(nearby_police) do
        local cop_uid     = getUID(cop_pid)
        local bust_amount = is_ap_bust and 5000 or config.police.bust_bonus_amount
        DB.incrementPoliceArrests(cop_uid)
        addMoney(cop_uid, bust_amount)
        sendMessage(cop_pid, translateForPlayer(cop_pid, "police_bust_bonus", {
            amount   = bust_amount,
            criminal = civil_name,
        }))
        sendMoneyUpdate(cop_pid)
        addTaskProgress(cop_pid, "cop_arrests_1", 1)
        addTaskProgress(cop_pid, "cop_arrests_2", 1)
        addTaskProgress(cop_pid, "cop_arrests_3", 1)
        addTaskProgress(cop_pid, "cop_arrests_4", 1)
        addTaskProgress(cop_pid, "cop_arrests_5", 1)
    end
end


-- =============================================================================
-- HUD & CLIENT SYNC
-- =============================================================================

sendMoneyUpdate = function(pid)
    if not (MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end
    local uid     = getUID(pid)
    local payload = encodeJSON({ money = tonumber(getMoney(uid)) or 0 })
    if payload then triggerClient(pid, "receiveMoney", payload) end
end

local function sendPoliceProximity(pid, nearby)
    if not (MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end
    local payload = encodeJSON({ policeNearby = nearby })
    if payload then triggerClient(pid, "updatePoliceProximity", payload) end
end

local function sendBustProgress(pid, progress, duration)
    if not (MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end
    local payload = encodeJSON({ bustProgress = tonumber(progress) or 0, bustDuration = tonumber(duration) or 0 })
    if payload then triggerClient(pid, "updateBustProgress", payload) end
end

sendRepairIcons = function(pid)
    if not (MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end
    local uid            = getUID(pid)
    local role           = getRole(uid)
    local repairs, max_repairs = 0, 0
    if role == "police" then
        repairs     = getRemainingPoliceRepairs(pid)
        local bonus = (police_repair_counters[pid] and police_repair_counters[pid].bonus_repairs) or 0
        max_repairs = (config.police.police_allowed_repairs or 0) + bonus
    elseif isWanted(pid) then
        local counter = player_repair_counters[pid]
        if counter then
            max_repairs = counter.max_repairs
            repairs     = math.max(0, max_repairs - counter.count)
        end
    end
    local payload = encodeJSON({ repairIcons = repairs, maxRepairs = max_repairs })
    if payload then triggerClient(pid, "updateRepairIcons", payload) end
end

updatePrefix = function(pid)
    if not (MP and MP.TriggerClientEvent) then return end
    local uid         = getUID(pid)
    local role        = getRole(uid)
    local rank        = player_rank_cache[uid] or getRank(uid) or 1
    local rank_config = ranks[rank]
    local rank_prefix = rank_config and rank_config.prefix or ""
    local prefix      = ""

    if isWanted(pid)          then prefix = "[** WNT **]"
    elseif role == "police"   then prefix = "[COP]"
    elseif role == "civilian" then prefix = "[CIV]" end

    local payload = encodeJSON({ playerName = getBeammpName(pid), prefix = rank_prefix .. " " .. prefix, pid = pid })
    if payload then
        forPlayers(function(other_pid) triggerClient(other_pid, "updatePlayerPrefix", payload) end)
    end
end


-- =============================================================================
-- PLAYERLIST CUSTOM DATA
-- =============================================================================

sendPlayerListCustomData = function()
    if not (config and config.features and config.features.playerlist_custom_data_enabled) then return end
    local custom_data = {}
    forPlayers(function(pid)
        local uid         = getUID(pid)
        local role        = getRole(uid) or "civilian"
        local rank        = player_rank_cache[uid] or getRank(uid) or 1
        local rank_config = ranks[rank]
        table.insert(custom_data, {
            id           = pid,
            role         = role,
            rank         = rank,
            rank_prefix  = rank_config and rank_config.prefix or "[RK]",
            is_wanted    = isWanted(pid),
            display_name = getPlayerName(pid),
            beammp_name  = getBeammpName(pid),
        })
    end)
    local payload = encodeJSON({ players = custom_data })
    if payload then broadcastClientEvent("ECON_PlayerListData", payload) end
end


-- =============================================================================
-- QUEUE SYNC SYSTEM
-- =============================================================================

local function sendNotSyncedByList(target_pid)
    if not (MP and MP.IsPlayerConnected and MP.IsPlayerConnected(target_pid)) then return end
    local not_synced_by = {}
    for reporter_pid, queued_set in pairs(player_queue_reports) do
        if reporter_pid ~= target_pid and queued_set[target_pid] then
            table.insert(not_synced_by, reporter_pid)
        end
    end
    local payload = encodeJSON({ pids = not_synced_by })
    if payload then triggerClient(target_pid, "ECON_NotSyncedBy", payload) end
end

function ECON_PlayerSynced(pid, raw)
    local synced_pid = tonumber(raw)
    if not synced_pid then return end
    if player_queue_reports[pid] then
        player_queue_reports[pid][synced_pid] = nil
    end
    if MP.IsPlayerConnected(synced_pid) then
        sendNotSyncedByList(synced_pid)
    end
end

function ECON_QueueReport(pid, raw)
    if not (pid and MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end    
    local queued_list = decodeJSON(raw)
    if type(queued_list) ~= "table" then return end
    local queued_set = {}
    for _, target_pid in ipairs(queued_list) do
        local tpid = tonumber(target_pid)
        if tpid then queued_set[tpid] = true end
    end
    player_queue_reports[pid] = queued_set
    local affected = { [pid] = true }
    for tpid in pairs(queued_set) do affected[tpid] = true end
    for tpid in pairs(affected) do
        if MP.IsPlayerConnected(tpid) then sendNotSyncedByList(tpid) end
    end
end

-- =============================================================================
-- SPAWN & TELEPORT SYSTEM
-- =============================================================================

local function getSpawnPoint(pid)
    local map_locations  = locations[CurrentMap] or locations["west_coast_usa"]
    local vehicle_spawns = map_locations.vehicles
    if not vehicle_spawns or #vehicle_spawns == 0 then
        log("WARNING: No vehicle spawns available!")
        return { pos = { x = 0, y = 0, z = 100 }, rot = { x = 0, y = 0, z = 0, w = 1 } }
    end
    return vehicle_spawns[(pid % #vehicle_spawns) + 1]
end

local function canTeleport(pid)
    if not spawn_teleport_enabled then return false end
    local last = last_teleport_time[pid]
    return not (last and (os.time() - last < 2))
end

local function teleportToSpawn(pid, vid, reason)
    if not spawn_teleport_enabled then return false end
    local sp   = getSpawnPoint(pid)
    local data = encodeJSON({ vehicle_id = vid, pos = sp.pos, rot = sp.rot, reason = reason, timestamp = os.time() })
    if data then
        triggerClient(pid, "NoRepair_TeleportVehicle", data)
        last_teleport_time[pid] = os.time()
        if getRole(getUID(pid)) == "police" then
            police_repair_counters[pid] = { count = 0, reset_time = os.time(), bonus_repairs = 0 }
            sendRepairIcons(pid)
        end
        return true
    end
    return false
end

local function sendTeleportState(pid)
    triggerClient(pid, "NoRepair_UpdateState", spawn_teleport_enabled and "1" or "0")
end

local function sendSpawnPoint(pid)
    local data = encodeJSON(getSpawnPoint(pid))
    if data then triggerClient(pid, "NoRepair_SetSpawnPoint", data) end
end

local function getPlayerSpawnIndex(pid)
    if player_spawn_indices[pid] then return player_spawn_indices[pid] end
    local map_locations  = locations[CurrentMap] or locations["west_coast_usa"]
    local vehicle_spawns = map_locations.vehicles
    if not vehicle_spawns or #vehicle_spawns == 0 then
        log("WARNING: [OptionalSpawn] No vehicle spawns available!")
        return 1
    end
    local spawn_index = (pid % #vehicle_spawns) + 1
    player_spawn_indices[pid] = spawn_index
    log(string.format("[OptionalSpawn] Assigned spawn index %d to player %s", spawn_index, getPlayerName(pid)))
    return spawn_index
end

local function handleOptionalSpawn(pid, data)
    if not spawn_teleport_enabled then return end
    if isWanted(pid) then failWanted(pid, "reason_home_button") end
    local decoded = type(data) == "string" and decodeJSON(data) or data
    if not decoded or not decoded.spawn_index then
        log("[OptionalSpawn] Invalid optional spawn data"); return
    end
    local location_index = tonumber(decoded.spawn_index)
    if not location_index or location_index < 1 or location_index > 3 then
        log(string.format("[OptionalSpawn] Invalid location index: %s", tostring(location_index))); return
    end
    local map_locations   = locations[CurrentMap] or locations["west_coast_usa"]
    local optional_spawns = map_locations.optional_spawns
    if not optional_spawns or not optional_spawns[location_index] then
        sendMessage(pid, translateForPlayer(pid, "spawn_not_available")); return
    end
    local spawn_location = optional_spawns[location_index]
    if not spawn_location.points or #spawn_location.points == 0 then
        sendMessage(pid, translateForPlayer(pid, "spawn_not_available")); return
    end
    local player_index = getPlayerSpawnIndex(pid)
    local point_index  = ((player_index - 1) % #spawn_location.points) + 1
    local spawn_point  = spawn_location.points[point_index]
    log(string.format("[OptionalSpawn] Player %s -> %s point %d/%d",
        getPlayerName(pid), spawn_location.name, point_index, #spawn_location.points))
    if not canTeleport(pid) then
        sendMessage(pid, translateForPlayer(pid, "teleport_cooldown")); return
    end
    local ok, vehicles = pcall(MP.GetPlayerVehicles, pid)
    local vid = 0
    if ok and vehicles then
        for id, _ in pairs(vehicles) do vid = tonumber(id); if vid then break end end
    end
    local tp_data = encodeJSON({
        vehicle_id = vid, pos = spawn_point.pos, rot = spawn_point.rot,
        reason = "optional_spawn", timestamp = os.time(),
    })
    if tp_data then
        triggerClient(pid, "NoRepair_TeleportVehicle", tp_data)
        last_teleport_time[pid] = os.time()
        if getRole(getUID(pid)) == "police" then
            police_repair_counters[pid] = { count = 0, reset_time = os.time(), bonus_repairs = 0 }
            sendRepairIcons(pid)
        end
    end
end


-- =============================================================================
-- VIOLATION DETECTION
-- =============================================================================

local function handleSpeeding(pid, speed)
    if not (config.features.roleplay_enabled and config.features.speeding_bonus_enabled) then return end
    if players_editing_vehicle[pid] then return end
    if wanted_disabled_players[pid] then return end
    local now = os.time() * 1000
    if speeding_cooldowns[pid] and now - speeding_cooldowns[pid] < config.civilian.speeding_cooldown_ms then return end
    local uid = getUID(pid)
    if getRole(uid) == "civilian" then
        if not speeding_bonuses[pid] then
            speeding_bonuses[pid] = { startTime = now, lastPayment = now }
        end
        updateWantedTimer(pid, config.civilian.speeding_bonus_duration_ms, "speed_start_wanted", "speeding")
        speeding_cooldowns[pid] = now
    end
end

local function handleZigzag(pid, pos)
    if not (config.features.roleplay_enabled and config.features.zigzag_bonus_enabled) then return end
    if players_editing_vehicle[pid] then return end
    if wanted_disabled_players[pid] then return end
    local uid = getUID(pid)
    if getRole(uid) ~= "civilian" or not pos or not pos.rot or not pos.vel then return end

    local now    = os.time() * 1000
    local vx, vy = pos.vel[1] or 0, pos.vel[2] or 0
    local speed  = math.sqrt(vx*vx + vy*vy) * 3.6
    if speed < config.civilian.min_speed_kmh_for_zigzag then
        player_zigzag_state[pid] = nil; return
    end

    if zigzag_cooldowns[pid] and (now - zigzag_cooldowns[pid] < config.civilian.zigzag_cooldown_ms) then return end

    local qx, qy, qz, qw = pos.rot[1] or 0, pos.rot[2] or 0, pos.rot[3] or 0, pos.rot[4] or 1
    local yaw_angle = math.atan(2.0*(qw*qz + qx*qy), 1.0 - 2.0*(qy*qy + qz*qz))

    if not player_zigzag_state[pid] then
        player_zigzag_state[pid] = { last_angle = yaw_angle, consecutive_turns = 0, last_direction = 0, last_turn_time = now }
        return
    end

    local state = player_zigzag_state[pid]
    if (now - state.last_turn_time) / 1000 > config.civilian.zigzag_max_turn_interval_seconds then
        player_zigzag_state[pid] = { last_angle = yaw_angle, consecutive_turns = 0, last_direction = 0, last_turn_time = now }
        return
    end

    local yaw_delta = yaw_angle - state.last_angle
    if yaw_delta > math.pi       then yaw_delta = yaw_delta - 2*math.pi
    elseif yaw_delta < -math.pi  then yaw_delta = yaw_delta + 2*math.pi end

    local angle_degrees = math.abs(math.deg(yaw_delta))
    if angle_degrees < config.civilian.zigzag_min_angle_degrees then
        state.last_angle = yaw_angle; return
    end

    local dir = (yaw_delta > 0) and 1 or -1
    if state.last_direction ~= 0 and dir ~= state.last_direction then
        state.consecutive_turns = state.consecutive_turns + 1
        state.last_turn_time    = now
    else
        state.consecutive_turns = 1
        state.last_turn_time    = now
    end
    state.last_angle     = yaw_angle
    state.last_direction = dir

    if state.consecutive_turns >= config.civilian.zigzag_min_turns then
        if not zigzag_bonuses[pid] then
            zigzag_bonuses[pid] = { startTime = now, lastPayment = now }
        end

        local police_nearby = false
        local ok_pos, pos_data = pcall(MP.GetPositionRaw, pid, 0)
        if ok_pos and pos_data and pos_data.pos then
            local rangeSq = config.police.police_proximity_range_m ^ 2
            for other_pid, _ in pairs(MP.GetPlayers() or {}) do
                if other_pid ~= pid and MP.IsPlayerConnected(other_pid) then
                    if getRole(getUID(other_pid)) == "police" then
                        local ok_cop, cop_pos = pcall(MP.GetPositionRaw, other_pid, 0)
                        if ok_cop and cop_pos and cop_pos.pos then
                            if distanceSq(pos_data.pos, cop_pos.pos) <= rangeSq then
                                police_nearby = true; break
                            end
                        end
                    end
                end
            end
        end

        if police_nearby then
            addTaskProgress(pid, "wanted_zigzag_1", 1)
            addTaskProgress(pid, "wanted_zigzag_2", 1)
        end
        updateWantedTimer(pid, config.civilian.zigzag_bonus_duration_ms, "zigzag_start_wanted", "zigzag")
        zigzag_cooldowns[pid]    = now
        player_zigzag_state[pid] = nil
    end
end

local function checkSpeedAndViolations(pid)
    if not (config.features.roleplay_enabled and config.features.speeding_bonus_enabled) then return end
    if players_editing_vehicle[pid] then return end
    if AirPolluter.isAPPlayer(pid) then return end
    local uid = getUID(pid)
    if getRole(uid) ~= "civilian" then return end
    local ok, pos = pcall(MP.GetPositionRaw, pid, 0)
    if not ok or not pos then return end
    local speed = 0
    if pos.vel then
        local vx, vy = pos.vel[1], pos.vel[2]
        speed = math.sqrt(vx*vx + vy*vy) * 3.6
    end
    if speed > config.civilian.speeding_limit_kmh then handleSpeeding(pid, speed) end
    if config.features.zigzag_bonus_enabled then handleZigzag(pid, pos) end
end


-- =============================================================================
-- MARKERS
-- =============================================================================

local function getActiveMarkerCount()
    local count = 0
    for _ in pairs(active_markers) do count = count + 1 end
    return count
end

local function isLocationOccupied(location_name)
    for _, marker in pairs(active_markers) do
        if marker.name == location_name then return true end
    end
    return false
end

local function trySpawnMarker()
    if not config.features.markers_enabled then return end
    local now = os.time() * 1000
    if next_marker_spawn_time > now then return end
    next_marker_spawn_time = now + config.markers.spawn_delay_ms
    if getActiveMarkerCount() >= config.markers.max_markers then return end

    local map_locations = locations[CurrentMap] or locations["west_coast_usa"]
    local marker_spawns = map_locations.markers
    if not marker_spawns or #marker_spawns == 0 then
        log("WARNING: No marker spawns available for map: " .. CurrentMap); return
    end

    local available = {}
    for _, sp in ipairs(marker_spawns) do
        if not isLocationOccupied(sp.name) then table.insert(available, sp) end
    end
    if #available == 0 then return end

    local sp      = available[math.random(#available)]
    local mid     = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
    local m_color = config.markers.marker_color

    active_markers[mid] = { id = mid, position = sp, name = sp.name, created_at = os.time() }

    local payload = encodeJSON({
        markerId   = mid,
        x = sp.x, y = sp.y, z = sp.z,
        scale      = config.markers.marker_scale,
        r = m_color.r, g = m_color.g, b = m_color.b, a = m_color.a,
        markerType = config.markers.marker_type,
    })
    if payload then
        broadcastClientEvent("ECON_CreateMarker", payload)
        broadcastMessage(translateForPlayer(-1, "marker_spawned_at_" .. sp.name))
    else
        active_markers[mid] = nil
    end
end

local function checkMarkerCollisions()
    if not next(active_markers) then return end

    local captured_this_frame = {}
    local proximity_range_sq  = config.police.police_proximity_range_m ^ 2

    for pid, _ in pairs(MP.GetPlayers() or {}) do
        if MP.IsPlayerConnected(pid) then
            local ok, posData = pcall(MP.GetPositionRaw, pid, 0)
            if ok and posData and posData.pos then
                local pPos      = posData.pos
                local uid       = getUID(pid)
                local role      = getRole(uid)
                local is_police = (role == "police")
                local is_wanted = isWanted(pid)

                if is_police or is_wanted then
                    local px = pPos[1] or pPos.x or 0
                    local py = pPos[2] or pPos.y or 0
                    local pz = pPos[3] or pPos.z or 0

                    for mid, mData in pairs(active_markers) do
                        if not captured_this_frame[mid] then
                            local mPos    = mData.position
                            local dx      = px - mPos.x
                            local dy      = py - mPos.y
                            local dz      = pz - mPos.z
                            local dist_sq = dx*dx + dy*dy + dz*dz
                            local radius  = config.markers.marker_scale * 1.8

                            if dist_sq <= (radius * radius) then
                                captured_this_frame[mid] = true
                                active_markers[mid]      = nil

                                local remPayload = encodeJSON({ markerId = mid })
                                if remPayload then broadcastClientEvent("ECON_RemoveMarker", remPayload) end

                                local is_chase_capture = false
                                if is_police then
                                    is_chase_capture = isWantedNearby(pid, config.police.police_proximity_range_m)
                                elseif is_wanted then
                                    for other_pid, _ in pairs(MP.GetPlayers() or {}) do
                                        if other_pid ~= pid and MP.IsPlayerConnected(other_pid) then
                                            if getRole(getUID(other_pid)) == "police" then
                                                local ok_cop, cop_pos = pcall(MP.GetPositionRaw, other_pid, 0)
                                                if ok_cop and cop_pos and cop_pos.pos then
                                                    if distanceSq(pPos, cop_pos.pos) <= proximity_range_sq then
                                                        is_chase_capture = true; break
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end

                                if is_police then
                                    DB.incrementMarkersPolice(uid)
                                    if is_chase_capture then
                                        for i = 1, 5 do addTaskProgress(pid, "cop_markers_chase_" .. i, 1) end
                                    end
                                    for i = 1, 5 do addTaskProgress(pid, "cop_markers_" .. i, 1) end
                                elseif is_wanted then
                                    DB.incrementMarkersWanted(uid)
                                    if is_chase_capture then
                                        for i = 1, 5 do addTaskProgress(pid, "wanted_markers_chase_" .. i, 1) end
                                    end
                                    for i = 1, 5 do addTaskProgress(pid, "wanted_markers_" .. i, 1) end
                                end

                                local granted     = false
                                local MAX_REPAIRS = 2

                                if is_police then
                                    if not police_repair_counters[pid] then
                                        police_repair_counters[pid] = { count = 0, reset_time = os.time(), bonus_repairs = 0 }
                                    end
                                    local base      = config.police.police_allowed_repairs or 0
                                    local bonus     = police_repair_counters[pid].bonus_repairs or 0
                                    local cur_avail = (base + bonus) - police_repair_counters[pid].count
                                    if cur_avail < MAX_REPAIRS then
                                        if base == 0 then
                                            if bonus < MAX_REPAIRS then
                                                police_repair_counters[pid].bonus_repairs = bonus + 1
                                                granted = true
                                            end
                                        else
                                            if police_repair_counters[pid].count > 0 then
                                                police_repair_counters[pid].count = police_repair_counters[pid].count - 1
                                            else
                                                police_repair_counters[pid].bonus_repairs = bonus + 1
                                            end
                                            granted = true
                                        end
                                    end
                                elseif is_wanted then
                                    if not player_repair_counters[pid] then
                                        player_repair_counters[pid] = { count = 0, max_repairs = 0, violations = { ["marker"] = true } }
                                    end
                                    local cur_avail = player_repair_counters[pid].max_repairs - player_repair_counters[pid].count
                                    if cur_avail < MAX_REPAIRS then
                                        if player_repair_counters[pid].count > 0 then
                                            player_repair_counters[pid].count = player_repair_counters[pid].count - 1
                                            granted = true
                                        elseif player_repair_counters[pid].max_repairs < MAX_REPAIRS then
                                            player_repair_counters[pid].max_repairs = player_repair_counters[pid].max_repairs + 1
                                            granted = true
                                        end
                                    end
                                end

                                local marker_reward = config.markers.marker_reward_amount or 200
                                addMoney(uid, marker_reward)
                                if granted then
                                    sendMessage(pid, translateForPlayer(pid, "marker_reward_success"))
                                    broadcastMessage(translateForPlayer(-1, "marker_captured", { player = getPlayerName(pid) }))
                                else
                                    sendMessage(pid, translateForPlayer(pid, "marker_reward_limit"))
                                end
                                sendMoneyUpdate(pid)
                                sendRepairIcons(pid)
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end

local function sendAllMarkersToPlayer(pid)
    if not config.features.markers_enabled then return end
    if not next(active_markers) then return end
    local m_color = config.markers.marker_color
    for marker_id, marker_data in pairs(active_markers) do
        local marker_payload = encodeJSON({
            markerId   = marker_id,
            x = marker_data.position.x, y = marker_data.position.y, z = marker_data.position.z,
            scale      = config.markers.marker_scale,
            r = m_color.r, g = m_color.g, b = m_color.b, a = m_color.a,
            markerType = config.markers.marker_type,
        })
        if marker_payload then triggerClient(pid, "ECON_CreateMarker", marker_payload) end
    end
end


-- =============================================================================
-- TRANSFER LIMITS
-- =============================================================================

local function cleanOldTransfers()
    local current_time = os.time()
    for uid, transfers in pairs(player_transfer_limits) do
        for target_uid, data in pairs(transfers) do
            if current_time - data.hour_start >= 3600 then transfers[target_uid] = nil end
        end
        if not next(transfers) then player_transfer_limits[uid] = nil end
    end
end

local function getTransferredAmount(from_uid, to_uid)
    local t = player_transfer_limits[from_uid]
    if not t then return 0 end
    local d = t[to_uid]
    if not d then return 0 end
    if os.time() - d.hour_start >= 3600 then
        player_transfer_limits[from_uid][to_uid] = nil
        return 0
    end
    return d.amount or 0
end

local function addTransferRecord(from_uid, to_uid, amount)
    if not player_transfer_limits[from_uid] then player_transfer_limits[from_uid] = {} end
    local current_time = os.time()
    local existing     = player_transfer_limits[from_uid][to_uid]
    if not existing or (current_time - existing.hour_start >= 3600) then
        player_transfer_limits[from_uid][to_uid] = { amount = amount, hour_start = current_time }
    else
        existing.amount = existing.amount + amount
    end
end


-- =============================================================================
-- REPAIR SYSTEM
-- =============================================================================

local function handleRepairRequest(pid)
    local uid     = getUID(pid)
    local role    = getRole(uid)
    local ok, pos = pcall(MP.GetPositionRaw, pid, 0)
    local speed   = 0
    if ok and pos and pos.vel then
        local vx, vy = pos.vel[1], pos.vel[2]
        speed = math.sqrt(vx*vx + vy*vy) * 3.6
    end

    if speed > config.civilian.max_speed_for_repair_kmh then
        sendMessage(pid, translateForPlayer(pid, "repair_too_fast", { speed_limit = config.civilian.max_speed_for_repair_kmh }))
        return false
    end

    local repair_range = config.system.repair_proximity_limit_m or 50

    if role == "police" then
        if isWantedNearby(pid, repair_range) then
            sendMessage(pid, translateForPlayer(pid, "police_repair_wanted_nearby", { range = repair_range }))
            return false
        end
        if not usePoliceRepair(pid) then
            sendMessage(pid, translateForPlayer(pid, "police_no_repairs_left", { cooldown_minutes = 5 }))
            return false
        end
        sendMessage(pid, translateForPlayer(pid, "police_repair_success"))
        sendRepairIcons(pid)
        approved_repairs[pid] = os.time()
        triggerClient(pid, "performRepair", "")
        return true
    end

    if not isWanted(pid) then
        sendMessage(pid, translateForPlayer(pid, "civilian_not_wanted")); return false
    end
    if isPoliceNearby(pid, repair_range) then
        sendMessage(pid, translateForPlayer(pid, "civilian_repair_police_nearby", { range = repair_range }))
        return false
    end

    local counter = player_repair_counters[pid]
    if not counter then
        sendMessage(pid, translateForPlayer(pid, "civilian_no_repairs")); return false
    end
    if counter.count >= counter.max_repairs then
        sendMessage(pid, translateForPlayer(pid, "civilian_no_repairs_left")); return false
    end
    counter.count = counter.count + 1
    sendMessage(pid, translateForPlayer(pid, "civilian_repair_success", { used = counter.count, total = counter.max_repairs }))
    sendRepairIcons(pid)
    approved_repairs[pid] = os.time()
    triggerClient(pid, "performRepair", "")
    return true
end


-- =============================================================================
-- VEHICLE EDITING
-- =============================================================================

local function setPlayerEditingMode(pid, isEditing, serverVehicleID)
    players_editing_vehicle[pid] = isEditing
    if isEditing and serverVehicleID then
        editing_vehicle_ids[pid] = serverVehicleID
        local payload = encodeJSON({ serverVehicleID = serverVehicleID, isSpawned = false, playerRole = getRole(getUID(pid)) })
        if payload then
            forPlayers(function(other_pid)
                if other_pid ~= pid then triggerClient(other_pid, "ECON_SetVehicleSpawned", payload) end
            end)
        end
    elseif not isEditing then
        editing_vehicle_ids[pid] = nil
    end
    triggerClient(pid, "ECON_EditingModeUpdate", encodeJSON({ isEditing = isEditing }))
end

local function updateEditingPlayerPosition(pid)
    if not players_editing_vehicle[pid] then return end
    local ok, pos = pcall(MP.GetPositionRaw, pid, 0)
    if ok and pos and pos.pos then
        editing_player_positions[pid] = {
            x = pos.pos[1] or pos.pos.x or 0,
            y = pos.pos[2] or pos.pos.y or 0,
            z = pos.pos[3] or pos.pos.z or 0,
        }
        local payload = encodeJSON({ pid = pid, position = editing_player_positions[pid] })
        if payload then
            forPlayers(function(other_pid)
                if other_pid ~= pid then triggerClient(other_pid, "ECON_EditingPlayerPosition", payload) end
            end)
        end
    end
end

sendExistingEditorsToNewPlayer = function(new_pid)
    if not MP.IsPlayerConnected(new_pid) then return end
    for pid, isEditing in pairs(players_editing_vehicle) do
        if isEditing and MP.IsPlayerConnected(pid) and pid ~= new_pid then
            local serverVehicleID = editing_vehicle_ids[pid]
            if serverVehicleID then
                local payload = encodeJSON({ serverVehicleID = serverVehicleID, isSpawned = false })
                if payload then triggerClient(new_pid, "ECON_SetVehicleSpawned", payload) end
            end
        end
    end
end


-- =============================================================================
-- ROLE DETECTION
-- =============================================================================

local PoliceSkins = dofile(ROOT .. "/config/PoliceSkins.lua")

local function updatePlayerRole(pid)
    if not config.features.roleplay_enabled then return end
    local uid = getUID(pid)
    DB.ensurePlayer(uid, getPlayerName(pid), nil, config.money.starting_money)

    local ok, vehicles = pcall(MP.GetPlayerVehicles, pid)
    local new_role = "civilian"

    if ok and vehicles and type(vehicles) == "table" then
        for _, v in pairs(vehicles) do
            if type(v) == "string" then
                local json_match = v:match("{.*}")
                if json_match then
                    local ok_json2, data = pcall(decodeJSON, json_match)
                    if ok_json2 and type(data) == "table" then
                        local skin  = (data.vcf and data.vcf.partConfigFilename) or ""
                        local paint = (data.vcf and data.vcf.parts and data.vcf.parts.paint_design) or ""
                        for _, ps in ipairs(PoliceSkins or {}) do
                            if skin == ps or paint == ps then new_role = "police"; break end
                        end
                        if new_role == "police" then break end
                    end
                end
            end
        end
    end

    local current = getRole(uid)
    if current ~= new_role then
        setRole(uid, new_role)
        if new_role == "police" then
            sendMessage(pid, translateForPlayer(pid, "welcome_police"))
            if isWanted(pid) then failWanted(pid, "reason_became_police") end
            setLastPolicePayment(uid, os.time() * 1000)
        else
            sendMessage(pid, translateForPlayer(pid, "welcome_civilian"))
        end
        sendMoneyUpdate(pid)
        sendWantedUI(pid, 0)
        updatePrefix(pid)
        sendRepairIcons(pid)
        sendPoliceRole(pid)
    end
end


-- =============================================================================
-- REWARD PROCESSING
-- =============================================================================

local function processRewards(player_data, wanted_civilians, police_officers)
    if not config.features.roleplay_enabled then return end
    local now                = os.time() * 1000
    local proximity_range_sq = config.police.police_proximity_range_m ^ 2
    local civilian_police_count = {}
    local police_event_count    = {}

    for civil_pid, civil_data in pairs(wanted_civilians) do
        local count = 0
        if civil_data.pos then
            for cop_pid, cop_data in pairs(police_officers) do
                if cop_data.pos and distanceSq(civil_data.pos, cop_data.pos) <= proximity_range_sq then
                    count = count + 1
                    police_event_count[cop_pid] = (police_event_count[cop_pid] or 0) + 1
                end
            end
        end
        civilian_police_count[civil_pid] = count
    end

    for pid, data in pairs(player_data) do
        if MP.IsPlayerConnected(pid) and not AirPolluter.isAPPlayer(pid) then
            local is_wanted = isWanted(pid)
            if is_wanted or data.role == "police" then
                local last_payment_ms = now - 1000
                if data.role == "police" then
                    last_payment_ms = getLastPolicePayment(data.uid) or (now - 1000)
                elseif is_wanted then
                    local sp = speeding_bonuses[pid]
                    local zz = zigzag_bonuses[pid]
                    last_payment_ms = (sp and sp.lastPayment) or (zz and zz.lastPayment) or (now - 1000)
                end

                local seconds_passed = math.max(0, math.floor(now/1000) - math.floor(last_payment_ms/1000))
                if seconds_passed > 0 then
                    local money_to_add = 0
                    if data.role == "police" and config.features.police_features_enabled then
                        local event_count = police_event_count[pid] or 0
                        if event_count > 0 then
                            money_to_add = seconds_passed * config.police.police_bonus_per_second * event_count
                            setLastPolicePayment(data.uid, now)
                            DB.addChaseTime(data.uid, seconds_passed)
                            if data.speed and data.speed >= ranks.min_speed_for_progress then
                                if not player_chase_accumulators[pid] then player_chase_accumulators[pid] = 0 end
                                player_chase_accumulators[pid] = player_chase_accumulators[pid] + seconds_passed
                                local chunk = config.system.chase_accumulator_chunk_seconds
                                if player_chase_accumulators[pid] >= chunk then
                                    local chunks = math.floor(player_chase_accumulators[pid] / chunk)
                                    local total  = chunks * chunk
                                    for i = 1, 5 do addTaskProgress(pid, "cop_chase_time_" .. i, total, false) end
                                    player_chase_accumulators[pid] = player_chase_accumulators[pid] % chunk
                                end
                            end
                        end
                    elseif is_wanted then
                        local police_count = civilian_police_count[pid] or 0
                        if police_count > 0 then
                            DB.addWantedTime(data.uid, seconds_passed)
                            if speeding_bonuses[pid] and config.features.speeding_bonus_enabled then
                                money_to_add = money_to_add + (seconds_passed * config.civilian.speeding_bonus_per_second * police_count)
                            end
                            if zigzag_bonuses[pid] and config.features.zigzag_bonus_enabled then
                                money_to_add = money_to_add + (seconds_passed * config.civilian.zigzag_prorated_bonus * police_count)
                            end
                        end
                    end

                    if money_to_add > 0 then
                        addMoney(data.uid, money_to_add)
                        sendMoneyUpdate(pid)
                        if speeding_bonuses[pid] then speeding_bonuses[pid].lastPayment = now end
                        if zigzag_bonuses[pid]   then zigzag_bonuses[pid].lastPayment   = now end
                    end
                end
            end
        end
    end
end

local function processPoliceInteractions(wanted_civilians, police_officers)
    if not config.features.police_features_enabled then return end
    local now                = os.time() * 1000
    local busted_range_sq    = config.police.busted_range_m ^ 2
    local proximity_range_sq = config.police.police_proximity_range_m ^ 2

    for civil_pid, civil_data in pairs(wanted_civilians) do
        if civil_data.pos then
            local nearby_police = {}
            local closest_sq    = proximity_range_sq + 1

            for cop_pid, cop_data in pairs(police_officers) do
                if cop_data.pos then
                    local dsq = distanceSq(civil_data.pos, cop_data.pos)
                    if dsq <= busted_range_sq then table.insert(nearby_police, cop_pid) end
                    if dsq < closest_sq then closest_sq = dsq end
                end
            end

            local can_bust = civil_data.speed < config.police.busted_speed_limit_kmh
                             and closest_sq <= busted_range_sq
                             and #nearby_police > 0

            if can_bust then
                if not busted_timers[civil_pid] then
                    busted_timers[civil_pid] = now
                    bust_progress[civil_pid] = 0
                    sendBustProgress(civil_pid, 0, config.police.busted_stop_time_ms)
                else
                    local elapsed  = now - busted_timers[civil_pid]
                    local progress = math.min(100, (elapsed / config.police.busted_stop_time_ms) * 100)
                    bust_progress[civil_pid] = progress
                    sendBustProgress(civil_pid, progress, config.police.busted_stop_time_ms)
                    if elapsed >= config.police.busted_stop_time_ms then
                        bustPlayer(civil_pid, nearby_police)
                        busted_timers[civil_pid] = nil
                        bust_progress[civil_pid] = nil
                        sendBustProgress(civil_pid, 0, 0)
                    end
                end
            else
                if busted_timers[civil_pid] then
                    busted_timers[civil_pid] = nil
                    bust_progress[civil_pid] = nil
                    sendBustProgress(civil_pid, 0, 0)
                end
            end
        else
            if bust_progress[civil_pid] then
                busted_timers[civil_pid] = nil
                bust_progress[civil_pid] = nil
                sendBustProgress(civil_pid, 0, 0)
            end
        end
    end
end


-- =============================================================================
-- MAIN GAME LOOP
-- =============================================================================

local function updateAllPlayers()
    if not (config and config.features and config.features.roleplay_enabled) then return end
    processPendingVehicleChanges()

    local all_players      = MP.GetPlayers() or {}
    local player_data      = {}
    local wanted_civilians = {}
    local police_officers  = {}
    local now              = os.time() * 1000
    local proximity_range_sq = config.police.police_proximity_range_m ^ 2

    for pid, _ in pairs(all_players) do
        if MP.IsPlayerConnected(pid) and not players_pending_auth[pid] then
            local uid       = getUID(pid)
            local role      = getRole(uid)
            local ok, pos   = pcall(MP.GetPositionRaw, pid, 0)
            local speed, position = 0, nil
            if ok and pos then
                position = pos.pos
                if pos.vel then
                    local vx, vy = pos.vel[1], pos.vel[2]
                    speed = math.sqrt(vx*vx + vy*vy) * 3.6
                end
            end
            local data = { pid = pid, uid = uid, role = role, pos = position, speed = speed, fullPos = pos }
            player_data[pid] = data
            if role == "civilian" and isWanted(pid) then
                wanted_civilians[pid] = data
            elseif role == "police" then
                police_officers[pid] = data
            end
        end
    end

    for civil_pid, civil_data in pairs(wanted_civilians) do
        local has_police = false
        if civil_data.pos then
            for _, cop_data in pairs(police_officers) do
                if cop_data.pos and distanceSq(civil_data.pos, cop_data.pos) <= proximity_range_sq then
                    has_police = true; break
                end
            end
        end
        sendPoliceProximity(civil_pid, has_police)
    end

    for pid, data in pairs(player_data) do
        if data.role == "civilian" and not isWanted(pid) then
            sendPoliceProximity(pid, false)
        end
    end

    processPoliceInteractions(wanted_civilians, police_officers)
    processRewards(player_data, wanted_civilians, police_officers)

    for pid, _ in pairs(all_players) do
        if MP.IsPlayerConnected(pid) then
            local is_currently_wanted  = isWanted(pid)
            local did_expire_this_tick = false
            if wanted_timers[pid] then
                if checkWantedExpiration(pid) then did_expire_this_tick = true end
            end
            if is_currently_wanted and not did_expire_this_tick and wanted_timers[pid] then
                local remaining = math.max(0, math.ceil((wanted_timers[pid] - now) / 1000))
                sendWantedUI(pid, remaining)
            end
            sendRepairIcons(pid)
        end
    end
    checkPendingEscapes()
end


-- =============================================================================
-- COMMANDS
-- =============================================================================

local function cmdHelp(pid)
    for _, k in ipairs({ "help_title", "help_money", "help_who", "help_pay", "help_setlang", "help_repair", "help_rank" }) do
        sendMessage(pid, translateForPlayer(pid, k))
    end
end

local function cmdMoney(pid)
    sendMessage(pid, translateForPlayer(pid, "your_balance", { money = getMoney(getUID(pid)) }))
end

local function cmdWho(pid)
    sendMessage(pid, translateForPlayer(pid, "who_title"))
    for id, name in pairs(MP.GetPlayers() or {}) do
        sendMessage(pid, string.format("      %d: %s", id, name))
    end
end

local function cmdPay(pid, to_str, amt_str)
    local to  = tonumber(to_str)
    local amt = tonumber(amt_str)
    if to == nil or amt == nil or amt <= 0 then
        sendMessage(pid, translateForPlayer(pid, "invalid_target")); return
    end
    if not MP.IsPlayerConnected(to) then
        sendMessage(pid, translateForPlayer(pid, "invalid_target")); return
    end
    if pid == to then
        sendMessage(pid, translateForPlayer(pid, "transfer_self")); return
    end

    local from_uid = getUID(pid)
    local to_uid   = getUID(to)
    DB.ensurePlayer(from_uid)
    DB.ensurePlayer(to_uid)

    if getMoney(from_uid) < amt then
        sendMessage(pid, translateForPlayer(pid, "no_money")); return
    end

    local is_sender_admin     = isAdmin(pid)
    local already_transferred = getTransferredAmount(from_uid, to_uid)
    local max_transfer        = 10000
    local limit_msg           = "transfer_limit_reached"
    if isModerator(pid) and not is_sender_admin then
        max_transfer = 50000; limit_msg = "transfer_moderator_limit"
    elseif is_sender_admin then
        max_transfer = math.huge
    end
    if already_transferred + amt > max_transfer then
        sendMessage(pid, translateForPlayer(pid, limit_msg)); return
    end

    addMoney(from_uid, -amt)
    addMoney(to_uid,   amt)
    if not is_sender_admin then addTransferRecord(from_uid, to_uid, amt) end

    sendMessage(pid, translateForPlayer(pid, "pay_sent",     { amount = amt, to   = getPlayerName(to),  money = getMoney(from_uid) }))
    sendMessage(to,  translateForPlayer(to,  "pay_received", { amount = amt, from = getPlayerName(pid), money = getMoney(to_uid) }))
    sendMoneyUpdate(pid)
    sendMoneyUpdate(to)
    if math.random(1, 10) == 1 then cleanOldTransfers() end
end

local function cmdAddMoney(pid, to_str, amt_str)
    if not isAdmin(pid) then sendMessage(pid, "[Admin] You don't have permission."); return end
    local to  = tonumber(to_str)
    local amt = tonumber(amt_str)
    if not to or not amt or not MP.IsPlayerConnected(to) or amt <= 0 then
        sendMessage(pid, translateForPlayer(pid, "invalid_target")); return
    end
    local target_uid = getUID(to)
    DB.ensurePlayer(target_uid, getPlayerName(to), nil, config.money.starting_money)
    addMoney(target_uid, amt)
    sendMoneyUpdate(to)
    sendMessage(pid, string.format("[Admin] Added $%d to %s.", amt, getPlayerName(to)))
    sendMessage(to,  string.format("[Admin] You received $%d from an admin.", amt))
end

local function cmdSetLang(pid, lang_code)
    local valid_langs = { he=true, en=true, ar=true, de=true, it=true, fr=true, es=true, ru=true, cs=true, hu=true, ja_JP=true, pl_PL=true, pt_BR=true, pt_PT=true, sv_SE=true, tr_TR=true, uk=true, zh_Hans=true }
    if not valid_langs[lang_code] then
        sendMessage(pid, translateForPlayer(pid, "lang_not_found", { supported_langs = "he, en, ar, de, it, fr, es, ru, cs, hu, ja_JP, pl_PL, pt_BR, pt_PT, sv_SE, tr_TR, uk, zh_Hans" }))
        return
    end
    setLang(getUID(pid), lang_code)
    sendMessage(pid, translateForPlayer(pid, "language_changed"))
    sendTranslationsToClient(pid)
    PartsShop.onPlayerJoin(pid)
    sendRankUpdate(pid)
end

local function cmdRank(pid)
    sendRankUpdate(pid)
    triggerClient(pid, "ECON_ShowRankPanel", "")
end

local function cmdStats(pid, target_pid_str)
    local uid         = getUID(pid)
    local target_name = getPlayerName(pid)
    local target_pid  = tonumber(target_pid_str)
    if target_pid and MP.IsPlayerConnected(target_pid) then
        uid         = getUID(target_pid)
        target_name = getPlayerName(target_pid)
    end
    local stats = DB.getPlayerStats(uid)
    if not stats then sendMessage(pid, "Failed to fetch stats"); return end

    local sep = "╔══════════════════════════════════════╗"
    local mid = "╠══════════════════════════════════════╣"
    local bot = "╚══════════════════════════════════════╝"
    local function s(m) sendMessage(pid, m) end
    s(sep); s("║  📊 " .. target_name .. " Statistics"); s(mid)
    s("║ 🚨 WANTED STATUS:")
    s(string.format("║   Times Wanted: %d",       stats.wanted_count))
    s(string.format("║   Successful Escapes: %d", stats.wanted_success))
    s(string.format("║   Failed Escapes: %d",     stats.wanted_failed))
    if stats.wanted_count > 0 then
        s(string.format("║   Success Rate: %d%%", math.floor((stats.wanted_success / stats.wanted_count) * 100)))
    end
    s(string.format("║   Total Escape Time: %s",  formatTime(stats.wanted_time))); s(mid)
    s("║ 👮 POLICE STATS:")
    s(string.format("║   Total Arrests: %d",      stats.police_arrests))
    s(string.format("║   Total Chase Time: %s",   formatTime(stats.chase_time))); s(mid)
    s("║ 🎯 MARKERS:")
    s(string.format("║   As Police: %d",          stats.markers_police))
    s(string.format("║   As Wanted: %d",          stats.markers_wanted))
    s(string.format("║   Total: %d",              stats.markers_police + stats.markers_wanted)); s(mid)
    s("║ 💰 ECONOMY:")
    s(string.format("║   Total Earned: $%s",      tostring(stats.money_earned)))
    s(string.format("║   Total Spent: $%s",       tostring(stats.money_spent)))
    s(string.format("║   Net Profit: $%s",        tostring(stats.money_earned - stats.money_spent))); s(mid)
    s("║ ⏱️  SESSION INFO:")
    s(string.format("║   Total Playtime: %s",     formatTime(stats.playtime)))
    s(string.format("║   Login Count: %d",        stats.logins)); s(bot)
end

local function cmdSpawnTeleport(pid, arg)
    if not isAdmin(pid) then sendMessage(pid, "[NoRepair] No permission."); return end
    local arg_lower = arg and arg:lower() or ""
    if arg_lower == "on" or arg_lower == "1" then
        spawn_teleport_enabled                 = true
        config.features.spawn_teleport_enabled = true
        forPlayers(function(p) sendTeleportState(p); sendSpawnPoint(p) end)
        sendMessage(pid, "[NoRepair] Spawn teleport ON")
    elseif arg_lower == "off" or arg_lower == "0" then
        spawn_teleport_enabled                 = false
        config.features.spawn_teleport_enabled = false
        forPlayers(sendTeleportState)
        sendMessage(pid, "[NoRepair] Spawn teleport OFF")
    elseif arg_lower == "toggle" then
        spawn_teleport_enabled                 = not spawn_teleport_enabled
        config.features.spawn_teleport_enabled = spawn_teleport_enabled
        forPlayers(function(p) sendTeleportState(p); sendSpawnPoint(p) end)
        sendMessage(pid, "[NoRepair] Toggled to: " .. (spawn_teleport_enabled and "ON" or "OFF"))
    else
        sendMessage(pid, "[NoRepair] Status: " .. (spawn_teleport_enabled and "ON" or "OFF"))
    end
end

local function handleCommand(pid, msg)
    local args = {}
    for arg in msg:gmatch("%S+") do table.insert(args, arg) end
    if #args == 0 then return end
    local cmd = args[1]:lower()
    if     cmd == "/help"          then cmdHelp(pid)
    elseif cmd == "/money"         then cmdMoney(pid)
    elseif cmd == "/who"           then cmdWho(pid)
    elseif cmd == "/pay"           then cmdPay(pid, args[2], args[3])
    elseif cmd == "/addmoney"      then cmdAddMoney(pid, args[2], args[3])
    elseif cmd == "/setlang"       then cmdSetLang(pid, args[2])
    elseif cmd == "/rank"          then cmdRank(pid)
    elseif cmd == "/spawnteleport" then cmdSpawnTeleport(pid, args[2])
    elseif cmd == "/stats"         then cmdStats(pid, args[2])
    end
end


-- =============================================================================
-- VEHICLE EVENTS
-- =============================================================================

local function onVehicleEdited(pid, vid)
    if not MP.IsPlayerConnected(pid) then return end
    local uid = getUID(pid)
    if not uid then return end
    if players_editing_vehicle[pid] then return end
    if getRole(uid) == "civilian" and isWanted(pid) then
        failWanted(pid, "reason_vehicle_edited")
    end
end

local function onVehicleReset(pid, vid)
    if not (pid and MP.IsPlayerConnected(pid)) then return end
    if last_teleport_time[pid] then
        if os.time() - last_teleport_time[pid] < config.system.teleport_cooldown_seconds then return end
    end
    if approved_repairs[pid] then
        if os.time() - approved_repairs[pid] < config.system.repair_approval_window_seconds then
            approved_repairs[pid] = nil; return
        end
        approved_repairs[pid] = nil
    end
    failWanted(pid, "reason_vehicle_reset")
    if canTeleport(pid) then teleportToSpawn(pid, vid, "reset_blocked") end
end

local function onVehicleSpawn(pid, vid)
    if not (pid and MP.IsPlayerConnected(pid)) then return end
    setPlayerEditingMode(pid, true)
    if canTeleport(pid) then teleportToSpawn(pid, vid, "spawn") end
end

processPendingVehicleChanges = function()
    if next(pending_vehicle_changes) then pending_vehicle_changes = {} end
end

local function onVehicleChange(pid)
    if not (pid and MP.IsPlayerConnected(pid)) then return end
    setPlayerEditingMode(pid, true)
    failWanted(pid, "reason_change_vehicle")
    updatePlayerRole(pid)
    last_teleport_time[pid] = nil
end

local function onVehicleExit(pid)
    if not (pid and MP.IsPlayerConnected(pid)) then return end
    failWanted(pid, "reason_exit_vehicle")
end

local function onVehicleDelete(pid)
    if not (pid and MP.IsPlayerConnected(pid)) then return end
    failWanted(pid, "reason_vehicle_delete")
    updatePlayerRole(pid)
end


-- =============================================================================
-- PLAYER EVENTS
-- =============================================================================

local function onPlayerJoin(pid)
    local identifiers = (MP and MP.GetPlayerIdentifiers) and MP.GetPlayerIdentifiers(pid) or {}
    local function isRealId(s)
        return s and s ~= '' and not s:lower():match('^guest')
    end
    local has_real_id = isRealId(identifiers.beammp)
                     or isRealId(identifiers.steam)
                     or isRealId(identifiers.license)

    if not has_real_id then
        players_pending_auth[pid] = true
        triggerClient(pid, "ECON_AuthRequired", encodeJSON({ required = true }))
        return
    end

    players_awaiting_welcome[pid] = true
    player_display_names[pid]     = getPlayerName(pid)
    sendPlayerListCustomData()
    local uid = getUID(pid)
    DB.ensurePlayer(uid, getPlayerName(pid), identifiers, config.money.starting_money)
    pcall(function() DB.incrementLoginCount(uid) end)
    clearWanted(pid)

    player_rank_cache[uid] = getRank(uid) or 1
    player_task_cache[uid] = getTaskProgress(uid) or {}

    sendPoliceRole(pid)
    sendTeleportState(pid)
    sendSpawnPoint(pid)
    sendMoneyUpdate(pid)
    updatePrefix(pid)
    sendRepairIcons(pid)
    sendPoliceProximity(pid, false)
    sendBustProgress(pid, 0, 0)
    sendWantedUI(pid, 0)
    sendExistingEditorsToNewPlayer(pid)
    PartsShop.onPlayerJoin(pid)
end

local function onPlayerLeave(pid)
    players_pending_auth[pid]  = nil
    player_auth_uids[pid]      = nil
    player_display_names[pid]  = nil
    pending_auth_langs[pid]    = nil
    guest_uid_cache[pid]       = nil

    local uid = getUID(pid)

    last_teleport_time[pid]        = nil
    wanted_timers[pid]             = nil
    wanted_violations[pid]         = nil
    last_sent_wanted[pid]          = nil
    busted_timers[pid]             = nil
    speeding_cooldowns[pid]        = nil
    speeding_bonuses[pid]          = nil
    zigzag_cooldowns[pid]          = nil
    zigzag_bonuses[pid]            = nil
    player_zigzag_state[pid]       = nil
    player_repair_counters[pid]    = nil
    police_repair_counters[pid]    = nil
    players_awaiting_welcome[pid]  = nil
    pending_vehicle_changes[pid]   = nil
    player_chase_accumulators[pid] = nil
    editing_vehicle_ids[pid]       = nil
    players_editing_vehicle[pid]   = nil
    editing_player_positions[pid]  = nil
    wanted_disabled_players[pid]   = nil
    pending_escape_players[pid]    = nil
    player_spawn_indices[pid]      = nil
    local was_queued_by = {}
    if player_queue_reports[pid] then
        for tpid in pairs(player_queue_reports[pid]) do
            table.insert(was_queued_by, tpid)
        end
    end
    player_queue_reports[pid] = nil
    for _, tpid in ipairs(was_queued_by) do
        if MP.IsPlayerConnected(tpid) then sendNotSyncedByList(tpid) end
    end

    AirPolluter.onPlayerLeave(pid)

    if uid then
        pcall(function()
            savePlayerRankData(pid)
            DB.setWanted(uid, false)
        end)
    end

    player_rank_cache[uid] = nil
    player_task_cache[uid] = nil
end

local function checkWelcomeMessages()
    for pid, _ in pairs(players_awaiting_welcome) do
        if MP.IsPlayerConnected(pid) and not players_pending_auth[pid] then
            sendMessage(pid, translateForPlayer(pid, "welcome_server"))
            sendMoneyUpdate(pid)
            updatePrefix(pid)
            sendRepairIcons(pid)
            sendAdminStatus(pid)
            sendTranslationsToClient(pid)
            sendRankUpdate(pid)
            if config.features.markers_enabled and next(active_markers) then
                sendAllMarkersToPlayer(pid)
            end
            AirPolluter.onPlayerJoin(pid)
            PartsShop.onPlayerJoin(pid)
            forPlayers(function(other_pid)
                if other_pid ~= pid then updatePrefix(other_pid) end
            end)
            players_awaiting_welcome[pid] = nil
        end
    end
end


-- =============================================================================
-- PERIODIC TASKS
-- =============================================================================

local function checkAllRoles()
    if not config.features.roleplay_enabled then return end
    forPlayers(function(pid) updatePlayerRole(pid); updatePrefix(pid) end)
end

local function checkZigzagAndSpeed()
    if not config.features.roleplay_enabled then return end
    forPlayers(checkSpeedAndViolations)
end

local function saveAllRankData()
    forPlayers(savePlayerRankData)
end

local function addMoneyTimer()
    if not config.features.money_per_minute_enabled then return end
    local amount = config.money.money_per_minute_amount
    forPlayers(function(pid)
        local uid = getUID(pid)
        DB.ensurePlayer(uid, getPlayerName(pid), nil, config.money.starting_money)
        addMoney(uid, amount)
        sendMessage(pid, translateForPlayer(pid, "added_money_per_minute", {
            amount = amount, money = getMoney(uid)
        }))
        sendMoneyUpdate(pid)
    end)
end

local function syncAllPlayerMoney()
    forPlayers(sendMoneyUpdate)
end

local function sendCoolMessage()
    if not config.features.cool_message_enabled then return end
    forPlayers(function(pid) sendMessage(pid, translateForPlayer(pid, "cool_player_message")) end)
end

local function updatePlaytime()
    forPlayers(function(pid)
        local uid = getUID(pid)
        pcall(function() DB.addPlaytime(uid, 60) end)
    end)
end

local function handleHomeRequest(pid, data)
    if isWanted(pid) then failWanted(pid, "reason_home_button") end
    local vid      = 0
    local ok, vehicles = pcall(MP.GetPlayerVehicles, pid)
    if ok and vehicles then
        for id, _ in pairs(vehicles) do vid = tonumber(id); if vid then break end end
    end
    if vid == 0 then
        local sp = getSpawnPoint(pid)
        triggerClient(pid, "NoRepair_TeleportVehicle", encodeJSON({
            vehicle_id = 0, pos = sp.pos, rot = sp.rot, reason = "home_button", timestamp = os.time()
        }))
        return
    end
    if canTeleport(pid) then teleportToSpawn(pid, vid, "home_button") end
end


-- =============================================================================
-- CLIENT EVENT HANDLERS
-- =============================================================================

function ECON_PayTransfer(pid, data)
    if not (pid and MP.IsPlayerConnected(pid)) then return end
    if not data or data == "" then return end
    local decoded = decodeJSON(data)
    if not decoded then return end
    if decoded.target and decoded.amount then
        cmdPay(pid, tostring(decoded.target), tostring(decoded.amount))
    end
end

function ECON_onStartEditing(pid, data)
    if not (pid and MP.IsPlayerConnected(pid)) then return end
    local serverVehicleID = nil
    if type(data) == "string" and data ~= "" then
        local decoded = decodeJSON(data)
        if decoded and decoded.serverVehicleID then
            serverVehicleID = tostring(decoded.serverVehicleID)
        end
    end
    if not serverVehicleID then
        local ok, vehicles = pcall(MP.GetPlayerVehicles, pid)
        if ok and vehicles then
            for vid, _ in pairs(vehicles) do serverVehicleID = tostring(vid); break end
        end
    end
    setPlayerEditingMode(pid, true, serverVehicleID)
end

function ECON_onCancelEditing(pid)
    if not (pid and MP.IsPlayerConnected(pid)) then return end
    setPlayerEditingMode(pid, false)
    editing_player_positions[pid] = nil
end

function ECON_onFinishEditing(pid, data)
    if not players_editing_vehicle[pid] then return end
    setPlayerEditingMode(pid, false)
    editing_player_positions[pid] = nil
    updatePlayerRole(pid)
end

function ECON_onVehicleSyncComplete(pid, data)
    local decoded = type(data) == "string" and decodeJSON(data) or data
    if not decoded or not decoded.serverVehicleID then return end
    local serverVehicleID = tostring(decoded.serverVehicleID)
    local payload = encodeJSON({ serverVehicleID = serverVehicleID, isSpawned = true })
    if payload then triggerClient(pid, "ECON_SetVehicleSpawned", payload) end
    players_editing_vehicle[pid] = false
    editing_vehicle_ids[pid]     = nil
    updatePlayerRole(pid)
end

function ECON_onToggleWanted(pid, data)
    local decoded = type(data) == "string" and decodeJSON(data) or data
    if decoded and decoded.enabled ~= nil then
        toggleWantedEnabled(pid, decoded.enabled)
    end
end

function ECON_onOptionalSpawn(pid, data) handleOptionalSpawn(pid, data) end


function ECON_PartsShop_ConfirmPurchase(pid, data) PartsShop.onConfirmPurchase(pid, data) end
function ECON_PartsShop_CancelPurchase(pid, _)     end

function ECON_onRequestTranslations(pid, beamng_lang)
    if not (pid and MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end
    if beamng_lang and beamng_lang ~= "" then
        local uid = getUID(pid)
        local mapped = resolveBeamNGLocale(beamng_lang)
        if mapped and mapped ~= "en" then
            if uid:match("^guest_pid_") or players_pending_auth[pid] then
                pending_auth_langs[pid] = mapped
            elseif getLang(uid) == nil then
                setLang(uid, mapped)
                log(string.format("Auto-detected language '%s' -> '%s' for player %s",
                    beamng_lang, mapped, getPlayerName(pid)))
            end
        end
    end
    sendTranslationsToClient(pid)

    -- client ready: re-send auth request if still pending
    if players_pending_auth and players_pending_auth[pid] then
        triggerClient(pid, "ECON_AuthRequired", encodeJSON({ required = true }))
    end
end

-- =============================================================================
-- AUTH SYSTEM
-- =============================================================================

local function isValidUsername(s)
    return type(s) == "string" and #s >= 3 and #s <= 20 and s:match("^[%w_%-]+$")
end

local function isValidHash(s)
    return type(s) == "string" and #s == 64 and s:match("^[%x]+$")
end

function ECON_Auth(pid, raw)
    if not (pid and MP and MP.IsPlayerConnected and MP.IsPlayerConnected(pid)) then return end
    if not players_pending_auth[pid] then return end

    local data = decodeJSON(raw)
    if not data or not data.mode or not data.username or not data.hash then
        triggerClient(pid, "ECON_AuthResult", encodeJSON({ ok = false, error_key = "auth_invalid" }))
        return
    end

    local mode     = data.mode
    local username_display = data.username:match("^%s*(.-)%s*$")
    local username         = username_display:lower()
    local hash     = data.hash
    local token    = (type(data.device_token) == "string" and #data.device_token == 36)
                     and data.device_token or ""

    if not isValidUsername(username) then
        triggerClient(pid, "ECON_AuthResult", encodeJSON({ ok = false, error_key = "auth_username_invalid" }))
        return
    end
    if not isValidHash(hash) then
        triggerClient(pid, "ECON_AuthResult", encodeJSON({ ok = false, error_key = "auth_invalid" }))
        return
    end

    local uid = nil

    if mode == "register" then
        if not DB.createAccount(username, hash, username_display, config.money.starting_money) then
            triggerClient(pid, "ECON_AuthResult", encodeJSON({ ok = false, error_key = "auth_username_taken" }))
            return
        end
        uid = "local_" .. username
        player_display_names[pid] = username_display
    else
        local acc = DB.getAccount(username)
        if not acc then
            triggerClient(pid, "ECON_AuthResult", encodeJSON({ ok = false, error_key = "auth_not_found" }))
            return
        end
        if acc.password_hash ~= hash then
            triggerClient(pid, "ECON_AuthResult", encodeJSON({ ok = false, error_key = "auth_wrong_password" }))
            return
        end
        uid = acc.uid
        player_display_names[pid] = acc.username_display or username_display
    end
    
    if token ~= "" and DB.getTokenBanStatus(uid, token) then
        triggerClient(pid, "ECON_AuthResult", encodeJSON({ ok = false, error_key = "auth_device_banned" }))
        return
    end
    player_auth_uids[pid]         = uid
    players_pending_auth[pid]     = nil
    players_awaiting_welcome[pid] = true

    local identifiers = (MP and MP.GetPlayerIdentifiers) and MP.GetPlayerIdentifiers(pid) or {}
    DB.ensurePlayer(uid, getPlayerName(pid), identifiers, config.money.starting_money)
    pcall(function() DB.incrementLoginCount(uid) end)
    clearWanted(pid)

    player_rank_cache[uid] = getRank(uid) or 1
    player_task_cache[uid] = getTaskProgress(uid) or {}

    sendPoliceRole(pid)
    sendTeleportState(pid)
    sendSpawnPoint(pid)
    sendMoneyUpdate(pid)
    updatePrefix(pid)
    sendRepairIcons(pid)
    sendPoliceProximity(pid, false)
    sendBustProgress(pid, 0, 0)
    sendWantedUI(pid, 0)
    sendExistingEditorsToNewPlayer(pid)
    PartsShop.onPlayerJoin(pid)

    if token ~= "" then pcall(function() DB.saveDeviceToken(uid, token) end) end
    pcall(function() DB.saveGuestName(uid, getBeammpName(pid)) end)
    if getLang(uid) == nil and pending_auth_langs[pid] then
        setLang(uid, pending_auth_langs[pid])
    end
    pending_auth_langs[pid] = nil
    local migration_token = DB.getMigrationToken(uid)
    triggerClient(pid, "ECON_AuthResult", encodeJSON({ ok = true, money = getMoney(uid), display_name = player_display_names[pid], migration_token = migration_token }))
    log(string.format("Auth [%s] pid=%d uid=%s token=%s", mode, pid, uid, token ~= "" and token:sub(1,8).."..." or "none"))
    sendPlayerListCustomData()
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function ECON_onInit()
    log("=== Initializing UIMPIT 4.0.0 ===")
    if not DB.connect() then log("CRITICAL: Failed to connect to database!"); return end

    loadConfig()
    loadTranslations()
    spawn_teleport_enabled = config.features.spawn_teleport_enabled
    next_marker_spawn_time = os.time() * 1000 + config.markers.spawn_delay_ms

    pcall(function() DB.cleanGuestPlayers() end)
    AirPolluter.init({
        log                     = log,
        MP                      = MP,
        config                  = config,
        encodeJSON              = encodeJSON,
        decodeJSON              = decodeJSON,
        triggerClient           = triggerClient,
        broadcastClientEvent    = broadcastClientEvent,
        getUID                  = getUID,
        getPlayerName           = getPlayerName,
        getRole                 = getRole,
        addMoney                = addMoney,
        sendMoneyUpdate         = sendMoneyUpdate,
        isWanted                = isWanted,
        clearWanted             = clearWanted,
        sendWantedUI            = sendWantedUI,
        sendRepairIcons         = sendRepairIcons,
        updatePrefix            = updatePrefix,
        sendMessage             = sendMessage,
        broadcastMessage        = broadcastMessage,
        translateForPlayer      = translateForPlayer,
        forPlayers              = forPlayers,
        DB                      = DB,
        locations               = locations,
        getCurrentMap           = function() return CurrentMap end,
        wanted_timers           = wanted_timers,
        wanted_violations       = wanted_violations,
        player_repair_counters  = player_repair_counters,
        players_editing_vehicle = players_editing_vehicle,
    })
    MP.CreateEventTimer("AIRPOLLUTER_tick", 300)

        PartsShop.init({
        log           = log,
        MP            = MP,
        DB            = DB,
        encodeJSON    = encodeJSON,
        decodeJSON    = decodeJSON,
        triggerClient = triggerClient,
        sendMessage   = sendMessage,
        getUID        = getUID,
        translations  = translations,
    })
    MP.RegisterEvent("PartsShop_ConfirmPurchase", "ECON_PartsShop_ConfirmPurchase")
    MP.RegisterEvent("PartsShop_CancelPurchase",  "ECON_PartsShop_CancelPurchase")
    MP.CreateEventTimer("ECON_db_tick", 5000)

    MP.CreateEventTimer("ECON_autosave",               config.general.autosave_interval_ms)
    MP.CreateEventTimer("ECON_cool_message",           config.money.cool_message_interval_ms)
    MP.CreateEventTimer("ECON_add_money",              config.money.money_per_minute_interval_ms)
    MP.CreateEventTimer("ECON_welcome_checker",        config.timers.welcome_checker_ms)
    MP.CreateEventTimer("ECON_fast_marker_check",      config.timers.fast_marker_check_ms)
    MP.CreateEventTimer("ECON_combined_checker",       config.timers.combined_checker_ms)
    MP.CreateEventTimer("ECON_role_checker",           config.timers.role_checker_ms)
    MP.CreateEventTimer("ECON_zigzag_checker",         config.timers.zigzag_checker_ms)
    MP.CreateEventTimer("ECON_money_sync",             config.timers.money_sync_ms)
    MP.CreateEventTimer("ECON_rank_save",              config.timers.rank_save_ms)
    MP.CreateEventTimer("ECON_rank_ui_update",         config.timers.rank_ui_update_ms)
    MP.CreateEventTimer("ECON_police_wanted_update",   config.timers.police_wanted_update_ms)
    MP.CreateEventTimer("ECON_playtime_tracker",       60000)
    MP.CreateEventTimer("ECON_editing_position_sync",  config.timers.editing_position_sync_ms)
    MP.CreateEventTimer("ECON_update_playerlist_data", 500)

    MinimapSystem.init({
        MP             = MP,
        config         = config,
        active_markers = active_markers,
        CurrentMap     = CurrentMap,
        getUID         = getUID,
        getRole        = getRole,
        isWanted       = isWanted,
        distance       = distance,
        encodeJSON     = encodeJSON,
        triggerClient  = triggerClient,
        log            = log,
    })

    log("=== System Initialized ===")
end


-- =============================================================================
-- TIMER CALLBACKS
-- =============================================================================

function ECON_cool_message()           sendCoolMessage() end
function ECON_add_money()              addMoneyTimer() end
function ECON_welcome_checker()        checkWelcomeMessages() end
function ECON_fast_marker_check()      checkMarkerCollisions() end
function ECON_combined_checker()       updateAllPlayers(); trySpawnMarker() end
function ECON_role_checker()           checkAllRoles() end
function ECON_zigzag_checker()         checkZigzagAndSpeed() end
function ECON_money_sync()             syncAllPlayerMoney() end
function ECON_rank_save()              saveAllRankData() end
function ECON_rank_ui_update()         updateAllPlayerRanks() end
function ECON_playtime_tracker()       updatePlaytime() end
function ECON_minimap_fast()           MinimapSystem.updateMinimapsFast() end
function ECON_minimap_slow()           MinimapSystem.updateMinimapsSlow() end
function AIRPOLLUTER_onTick()          AirPolluter.tick() end
function ECON_police_wanted_update()   updateAllPoliceWantedLists() end
function ECON_update_playerlist_data() sendPlayerListCustomData() end
function ECON_autosave()               saveAllRankData(); DB.flush() end
function ECON_db_tick()                DB.tick() end

function ECON_editing_position_sync()
    for pid, _ in pairs(players_editing_vehicle) do
        if MP.IsPlayerConnected(pid) then updateEditingPlayerPosition(pid) end
    end
end


-- =============================================================================
-- SERVER EVENT CALLBACKS
-- =============================================================================

function ECON_onJoin(pid)              onPlayerJoin(pid) end
function ECON_onLeave(pid)             onPlayerLeave(pid) end
function ECON_onChat(pid, senderName, msg)
    if string.sub(msg, 1, 1) == "/" then handleCommand(pid, msg); return 1 end
end
function ECON_onVehicleEdited(pid, vid, data)
    onVehicleEdited(pid, vid)
    PartsShop.onVehicleEdited(pid, vid, data)
end
function ECON_onChangeVehicle(pid)     onVehicleChange(pid) end
function ECON_onVehicleReset(pid, vid) onVehicleReset(pid, vid) end
function ECON_onPlayerExitVehicle(pid) onVehicleExit(pid) end
function ECON_onVehicleDelete(pid)     onVehicleDelete(pid) end
function ECON_onVehicleSpawn(pid, vid, data)
    onVehicleSpawn(pid, vid)
    PartsShop.onVehicleSpawn(pid, vid, data)
end
function NoRepair_onStateRequest(pid)  sendTeleportState(pid); sendSpawnPoint(pid) end
function ECON_onUI_setLanguage(pid, lc) cmdSetLang(pid, lc) end
function ECON_onRepairRequest(pid)     handleRepairRequest(pid) end
function ECON_onHomeRequest(pid, data) handleHomeRequest(pid, data) end


-- =============================================================================
-- EVENT REGISTRATION
-- =============================================================================

MP.RegisterEvent("onInit",                       "ECON_onInit")
MP.RegisterEvent("onPlayerJoining",              "ECON_onJoin")
MP.RegisterEvent("onPlayerDisconnect",           "ECON_onLeave")
MP.RegisterEvent("onChatMessage",                "ECON_onChat")
MP.RegisterEvent("onVehicleEdited",              "ECON_onVehicleEdited")
MP.RegisterEvent("onPlayerChangeVehicle",        "ECON_onChangeVehicle")
MP.RegisterEvent("onVehicleReset",               "ECON_onVehicleReset")
MP.RegisterEvent("onPlayerExitVehicle",          "ECON_onPlayerExitVehicle")
MP.RegisterEvent("onVehicleDelete",              "ECON_onVehicleDelete")
MP.RegisterEvent("onVehicleSpawn",               "ECON_onVehicleSpawn")
MP.RegisterEvent("ECON_StartEditing",            "ECON_onStartEditing")
MP.RegisterEvent("ECON_CancelEditing",           "ECON_onCancelEditing")
MP.RegisterEvent("ECON_FinishEditing",           "ECON_onFinishEditing")
MP.RegisterEvent("ECON_VehicleSyncComplete",     "ECON_onVehicleSyncComplete")
MP.RegisterEvent("NoRepair_RequestState",        "NoRepair_onStateRequest")
MP.RegisterEvent("setPlayerLanguage",            "ECON_onUI_setLanguage")
MP.RegisterEvent("requestVehicleRepair",         "ECON_onRepairRequest")
MP.RegisterEvent("requestHomeButton",            "ECON_onHomeRequest")
MP.RegisterEvent("AIRPOLLUTER_tick",             "AIRPOLLUTER_onTick")
MP.RegisterEvent("ECON_OptionalSpawn",           "ECON_onOptionalSpawn")
MP.RegisterEvent("ECON_PayTransfer",             "ECON_PayTransfer")
MP.RegisterEvent("ECON_ToggleWanted",            "ECON_onToggleWanted")
MP.RegisterEvent("ECON_RequestTranslations",     "ECON_onRequestTranslations")
MP.RegisterEvent("ECON_Auth",                    "ECON_Auth")
MP.RegisterEvent("ECON_QueueReport",             "ECON_QueueReport")
MP.RegisterEvent("ECON_PlayerSynced",            "ECON_PlayerSynced")
MP.RegisterEvent("ECON_editing_position_sync",   "ECON_editing_position_sync")
MP.RegisterEvent("ECON_update_playerlist_data",  "ECON_update_playerlist_data")
MP.RegisterEvent("ECON_autosave",                "ECON_autosave")
MP.RegisterEvent("ECON_db_tick",                 "ECON_db_tick")
MP.RegisterEvent("ECON_police_wanted_update",    "ECON_police_wanted_update")
MP.RegisterEvent("ECON_rank_ui_update",          "ECON_rank_ui_update")
MP.RegisterEvent("ECON_cool_message",            "ECON_cool_message")
MP.RegisterEvent("ECON_add_money",               "ECON_add_money")
MP.RegisterEvent("ECON_welcome_checker",         "ECON_welcome_checker")
MP.RegisterEvent("ECON_combined_checker",        "ECON_combined_checker")
MP.RegisterEvent("ECON_fast_marker_check",       "ECON_fast_marker_check")
MP.RegisterEvent("ECON_role_checker",            "ECON_role_checker")
MP.RegisterEvent("ECON_zigzag_checker",          "ECON_zigzag_checker")
MP.RegisterEvent("ECON_money_sync",              "ECON_money_sync")
MP.RegisterEvent("ECON_rank_save",               "ECON_rank_save")
MP.RegisterEvent("ECON_rank_ui_update",          "ECON_rank_ui_update")
MP.RegisterEvent("ECON_playtime_tracker",        "ECON_playtime_tracker")
