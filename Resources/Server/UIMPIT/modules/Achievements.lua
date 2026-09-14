-- =============================================================================
-- Achievements.lua - PIT Rank & Achievement System
-- License: AGPL-3.0 - https://www.gnu.org/licenses/agpl-3.0.html
-- =============================================================================
local M = {}

local cfg, DB
local _getUID, _trigger, _forPlayers, _getPlayerName
local _sendMsg, _broadcast, _updatePrefix, _encodeJSON
local _sendMoneyUpdate   = nil
local _translateForPlayer = nil

local ms_by_stat = {}
local ms_by_id   = {}
local stats_cache = {}
local ach_cache   = {}
local session     = {}

function M.init(config, db, getUID, trigger, forPlayers,
                getPlayerName, sendMessage, broadcastMessage, updatePrefix, encodeJSON,
                sendMoneyUpdate, translateForPlayer)
    cfg                  = config
    DB                   = db
    _getUID              = getUID
    _trigger             = trigger
    _forPlayers          = forPlayers
    _getPlayerName       = getPlayerName
    _sendMsg             = sendMessage
    _broadcast           = broadcastMessage
    _updatePrefix        = updatePrefix
    _encodeJSON          = encodeJSON
    _sendMoneyUpdate     = sendMoneyUpdate
    _translateForPlayer  = translateForPlayer
    ms_by_stat = {}; ms_by_id = {}
    for _, ms in ipairs(cfg.milestones) do
        ms_by_id[ms.id] = ms
        local k = ms.stat
        if not ms_by_stat[k] then ms_by_stat[k] = {} end
        table.insert(ms_by_stat[k], ms)
    end
    for _, list in pairs(ms_by_stat) do
        table.sort(list, function(a, b) return a.threshold < b.threshold end)
    end
    print(string.format("[ACH] init: %d milestones, %d ranks", #cfg.milestones, #cfg.ranks))
end

local function rankFromPts(pts)
    local idx = 1
    for i, r in ipairs(cfg.ranks) do
        if pts >= r.threshold then idx = i else break end
    end
    return idx, cfg.ranks[idx]
end

local function ld(uid)
    if stats_cache[uid] then return end
    local s = DB.getAllStats(uid) or {}
    stats_cache[uid] = s
    local a = DB.getAchievementData(uid)
    local done = {}
    for _, id in ipairs(a.milestones_done or {}) do done[id] = true end
    ach_cache[uid] = { data = a, done = done }
end

local function initSess(uid)
    if session[uid] then return end
    session[uid] = { join_time=os.time(), seconds=0, busts=0, escapes=0, cop_markers=0, zigzags=0, points=0 }
end

local SESS_MAP = {
    session_seconds="seconds", session_busts="busts", session_escapes="escapes",
    session_cop_markers="cop_markers", session_zigzags="zigzags", session_points="points",
}
local PU = { spike_used=true,banana_used=true,cannon_used=true,spike_hits=true,banana_hits=true,cannon_hits=true }

local function sv(uid, stat)
    local sk = SESS_MAP[stat]; if sk then return session[uid] and session[uid][sk] or 0 end
    if PU[stat] then return ach_cache[uid] and (ach_cache[uid].data[stat] or 0) or 0 end
    return stats_cache[uid] and (stats_cache[uid][stat] or 0) or 0
end

local function addPts(uid, pts)
    if pts <= 0 then return end
    DB.addPoints(uid, pts)
    if stats_cache[uid] then stats_cache[uid].total_points = (stats_cache[uid].total_points or 0) + pts end
    if session[uid]     then session[uid].points = (session[uid].points or 0) + pts end
end

local function chkStat(uid, stat, is_cop)
    local list = ms_by_stat[stat]; if not list then return {} end
    local ac = ach_cache[uid]; if not ac then return {} end
    local val = sv(uid, stat); local done = ac.done; local earned = {}
    for _, ms in ipairs(list) do
        if done[ms.id] then goto skip end
        if ms.requires and not done[ms.requires] then goto skip end
        if val < ms.threshold then break end
        done[ms.id] = true; table.insert(ac.data.milestones_done, ms.id); table.insert(earned, ms)
        ::skip::
    end
    return earned
end

local function mult(ms, is_cop)
    local r = ms.role
    if r=="none" then return 1 end
    if r=="police"   then return is_cop and 2 or 1 end
    if r=="civilian" then return 1 end
    if r=="mixed"    then return is_cop and 2 or 1 end
    return 0
end

local function proc(pid, uid, earned, is_cop)
    if #earned == 0 then return end
    local old_pts  = stats_cache[uid] and stats_cache[uid].total_points or 0
    local old_rank = rankFromPts(old_pts)
    for _, ms in ipairs(earned) do
        local pts = ms.base_points * mult(ms, is_cop)
        addPts(uid, pts)
        local pay = _encodeJSON({ id=ms.id, name_key=ms.name_key, points=pts })
        if pay then _trigger(pid, "ACH_MilestoneEarned", pay) end
    end
    DB.setAchievementData(uid, ach_cache[uid].data)
    local new_pts  = stats_cache[uid] and stats_cache[uid].total_points or 0
    local new_rank = rankFromPts(new_pts)
    if new_rank > old_rank then
        local rc     = cfg.ranks[new_rank]
        local reward = rc.reward or 0
        if reward > 0 then
            DB.addMoney(uid, reward)
            if _sendMoneyUpdate then _sendMoneyUpdate(pid) end
        end
        local pay = _encodeJSON({
            old_rank=old_rank, new_rank=new_rank,
            new_prefix=rc.prefix, reward=reward,
        })
        if pay then _trigger(pid, "ACH_RankUp", pay) end
        _updatePrefix(pid)
        if _translateForPlayer then
            _sendMsg(pid, _translateForPlayer(pid, "ach_rank_up_message", {
                rank=new_rank, prefix=rc.prefix, reward=reward }))
            _broadcast(_translateForPlayer(-1, "ach_rank_up_broadcast", {
                player=_getPlayerName(pid), prefix=rc.prefix }))
        else
            _broadcast(string.format("[PIT] %s reached rank %s!",
                _getPlayerName(pid), rc.prefix))
        end
    end
    M.sendUpdate(pid)
end

local DB_FN = {
    busts               = function(uid,n) for _=1,n do DB.incrementPoliceArrests(uid)  end end,
    cop_chase_time      = function(uid,n) DB.addChaseTime(uid,n)                           end,
    wanted_chase_time   = function(uid,n) DB.addWantedTime(uid,n)                          end,
    cop_marker_chase    = function(uid,n) for _=1,n do DB.incrementMarkersPolice(uid)  end end,
    wanted_marker_chase = function(uid,n) for _=1,n do DB.incrementMarkersWanted(uid)  end end,
    escapes             = function(uid,n) for _=1,n do DB.incrementWantedSuccess(uid)  end end,
    zigzag_count        = function(uid,n) for _=1,n do DB.incrementZigzag(uid)         end end,
    combo_count         = function(uid,n) for _=1,n do DB.incrementCombo(uid)          end end,
    close_markers       = function(uid,n) for _=1,n do DB.incrementCloseMarker(uid)    end end,
    total_playtime      = function(uid,n) DB.addPlaytime(uid,n)                            end,
}

local function incStat(pid, uid, stat, n, is_cop)
    n = math.floor(tonumber(n) or 0); if n <= 0 then return end
    if DB_FN[stat] then DB_FN[stat](uid, n)
    elseif PU[stat] then
        local a = ach_cache[uid]; if a then a.data[stat] = (a.data[stat] or 0) + n end
    end
    local sc = stats_cache[uid]
    if sc then
        sc[stat] = (sc[stat] or 0) + n
        if stat == "cop_marker_chase" or stat == "wanted_marker_chase" then
            sc.total_markers = (sc.total_markers or 0) + n
        end
    end
    local e = chkStat(uid, stat, is_cop)
    if stat == "cop_marker_chase" or stat == "wanted_marker_chase" then
        for _, ms in ipairs(chkStat(uid, "total_markers", is_cop)) do table.insert(e, ms) end
    end
    proc(pid, uid, e, is_cop)
end

local function incSess(pid, uid, stat, n, is_cop)
    n = math.floor(tonumber(n) or 0); if n <= 0 then return end
    local s = session[uid]; if not s then return end
    local k = SESS_MAP[stat]; if not k then return end
    s[k] = (s[k] or 0) + n
    proc(pid, uid, chkStat(uid, stat, is_cop), is_cop)
end

function M.onPlayerJoin(pid)
    local uid = _getUID(pid); ld(uid); initSess(uid)
    local streak = DB.updateStreak(uid)
    if streak and stats_cache[uid] then stats_cache[uid].streak_days = streak end
    if streak and streak >= 2 then proc(pid, uid, chkStat(uid, "streak_days", false), false) end
    M.sendUpdate(pid)
end

function M.onPlayerLeave(pid)
    local uid = _getUID(pid)
    if ach_cache[uid] then DB.setAchievementData(uid, ach_cache[uid].data) end
    stats_cache[uid]=nil; ach_cache[uid]=nil; session[uid]=nil
end

function M.awardAction(pid, action_key, is_cop)
    local act = cfg.actions[action_key]; if not act then return end
    local r = act.role; local mul
    if     r=="mixed"    then mul = is_cop and 2 or 1
    elseif r=="police"   then if not is_cop then return end; mul = 2
    elseif r=="civilian" then if is_cop     then return end; mul = 1
    else return end
    local pts = act.base * mul; if pts <= 0 then return end
    local uid = _getUID(pid); ld(uid); initSess(uid)
    addPts(uid, pts)
    local npay = _encodeJSON({ points=pts, task_name_key="pts_action_"..action_key })
    if npay then _trigger(pid, "ACH_TaskProgress", npay) end
    incSess(pid, uid, "session_points", pts, is_cop)
end

function M.onMarkerCapture(pid, is_close, is_cop)
    local uid = _getUID(pid); ld(uid); initSess(uid)
    M.awardAction(pid, "marker_capture", is_cop)
    if is_close then M.awardAction(pid, "close_marker_capture", is_cop) end
    local mc_stat = is_cop and "cop_marker_chase" or "wanted_marker_chase"
    incStat(pid, uid, mc_stat, 1, is_cop)
    if is_close then incStat(pid, uid, "close_markers", 1, is_cop) end
    if is_cop   then incSess(pid, uid, "session_cop_markers", 1, true) end
end

function M.onBust(pid)
    local uid = _getUID(pid); ld(uid); initSess(uid)
    M.awardAction(pid, "bust", true)
    incStat(pid, uid, "busts", 1, true)
    incSess(pid, uid, "session_busts", 1, true)
end

function M.onEscape(pid)
    local uid = _getUID(pid); ld(uid); initSess(uid)
    M.awardAction(pid, "escape", false)
    incStat(pid, uid, "escapes", 1, false)
    incSess(pid, uid, "session_escapes", 1, false)
end

function M.onZigzag(pid)
    local uid = _getUID(pid); ld(uid); initSess(uid)
    M.awardAction(pid, "zigzag_pressure", false)
    incStat(pid, uid, "zigzag_count", 1, false)
    incSess(pid, uid, "session_zigzags", 1, false)
end

function M.onComboEscape(pid)
    local uid = _getUID(pid); ld(uid); initSess(uid)
    M.awardAction(pid, "combo_escape", false)
    incStat(pid, uid, "combo_count", 1, false)
end


function M.onChaseTime(pid, secs, is_cop)
    local uid = _getUID(pid); ld(uid); initSess(uid)
    secs = math.floor(tonumber(secs) or 0); if secs <= 0 then return end
    local stat = is_cop and "cop_chase_time" or "wanted_chase_time"
    incStat(pid, uid, stat, secs, is_cop)
end

function M.onPlaytime(pid, secs)
    local uid = _getUID(pid); ld(uid); initSess(uid)
    secs = math.floor(tonumber(secs) or 0); if secs <= 0 then return end
    incStat(pid, uid, "total_playtime", secs, false)
    session[uid].seconds = (session[uid].seconds or 0) + secs
    proc(pid, uid, chkStat(uid, "session_seconds", false), false)
end


function M.onPowerupUsed(pid, pu_type)
    local uid  = _getUID(pid); local stat = pu_type .. "_used"
    if not PU[stat] then return end; ld(uid); initSess(uid)
    incStat(pid, uid, stat, 1, true)
end

function M.onPowerupHit(attacker_pid, pu_type, victim_pid)
    if attacker_pid == nil then return end
    if victim_pid ~= nil and attacker_pid == victim_pid then return end
    local uid  = _getUID(attacker_pid); local stat = pu_type .. "_hits"
    if not PU[stat] then return end; ld(uid); initSess(uid)
    incStat(attacker_pid, uid, stat, 1, true)
end

function M.sendUpdate(pid)
    local uid = _getUID(pid); ld(uid)
    local pts     = stats_cache[uid] and stats_cache[uid].total_points or DB.getTotalPoints(uid)
    local ri, rc  = rankFromPts(pts)
    local nrc     = cfg.ranks[ri + 1]
    local pct, tn = 100, 0
    if nrc then
        tn = nrc.threshold - pts
        local span = nrc.threshold - rc.threshold
        pct = span > 0 and math.floor(((pts - rc.threshold) / span) * 100) or 100
    end
    local ac   = ach_cache[uid] and ach_cache[uid].data or {}
    local done = ac.milestones_done and #ac.milestones_done or 0
    local doneset = (ach_cache[uid] and ach_cache[uid].done) or {}
    local ms_list = {}
    for _, ms in ipairs(cfg.milestones) do
        local val       = sv(uid, ms.stat)
        local is_done   = doneset[ms.id] == true
        local is_locked = (ms.requires ~= nil) and (doneset[ms.requires] ~= true)
        if is_done then is_locked = false end
        ms_list[#ms_list + 1] = {
            id        = ms.id,
            name_key  = ms.name_key,
            stat      = ms.stat,
            role      = ms.role or "none",
            threshold = ms.threshold,
            value     = val,
            done      = is_done,
            locked    = is_locked,
            points    = ms.base_points,
        }
    end

    local pay  = _encodeJSON({
        total_points=pts, rank=ri, prefix=rc.prefix, max_rank=#cfg.ranks,
        progress_pct=pct, pts_to_next=tn, next_prefix=nrc and nrc.prefix or nil,
        milestones_done=done, milestones_total=#cfg.milestones,
        milestones=ms_list,
    })
    if pay then _trigger(pid, "ACH_RankUpdate", pay) end
end

function M.updateAll()       _forPlayers(M.sendUpdate) end
function M.getPrefix(pid)
    local uid = _getUID(pid); ld(uid)
    local pts = stats_cache[uid] and stats_cache[uid].total_points or DB.getTotalPoints(uid)
    local _, rc = rankFromPts(pts); return rc and rc.prefix or "[I]"
end
function M.getRankFromPoints(pts) return rankFromPts(pts) end
function M.runMigration()         return DB.runRankMigration(cfg) end

return M
