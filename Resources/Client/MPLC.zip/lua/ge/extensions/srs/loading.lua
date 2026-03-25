-- Originally created by Codex && MYNAMEISJEFF482 for Scenic Route Servers & other communities

local M = {}

local injectInterval = 0.5
local injectMaxTries = 60
local injectTries = 0
local injectTimer = 0
local injecting = false

local function logInfo(msg)
  log('I', 'srs_loading', msg)
end

local function reloadUiDelayed()
  if type(reloadUI) ~= "function" then return end
  if type(core_jobsystem) == "table" and type(core_jobsystem.create) == "function" then
    core_jobsystem.create(function(job)
      job.sleep(0.5)
      reloadUI()
    end)
  else
    reloadUI()
  end
end

local function injectUiAssets()
  if not (be and be.executeJS) then return end
  local js = [[
    (function () {
      if (window.__srsLoadingInjected) return;
      window.__srsLoadingInjected = true;
      var head = document.head || document.getElementsByTagName('head')[0];
      function addCss(href) {
        if (document.querySelector('link[data-srs-loading="1"]')) return;
        var l = document.createElement('link');
        l.rel = 'stylesheet';
        l.href = href;
        l.setAttribute('data-srs-loading', '1');
        head.appendChild(l);
      }
      function addScript(src) {
        if (document.querySelector('script[data-srs-loading="1"]')) return;
        var s = document.createElement('script');
        s.defer = true;
        s.src = src;
        s.setAttribute('data-srs-loading', '1');
        (document.body || head).appendChild(s);
      }
      addCss('/ui/scenic_route_loading/srs_loading.css');
      addScript('/ui/scenic_route_loading/srs_loading.js');
    })();
  ]]
  be:executeJS(js)
end

M.onExtensionLoaded = function()
  logInfo("extension loaded")
  injectTries = 0
  injectTimer = 0
  injecting = true
  injectUiAssets()
end

M.onUpdate = function(dt)
  if not injecting then return end
  injectTimer = injectTimer + dt
  if injectTimer < injectInterval then return end
  injectTimer = 0
  injectTries = injectTries + 1
  injectUiAssets()
  if injectTries >= injectMaxTries then
    injecting = false
    logInfo("inject attempts finished")
  end
end

M.onServerJoined = function()
  logInfo("server joined")
  injectTries = 0
  injectTimer = 0
  injecting = true
  injectUiAssets()
end

M.onServerLeave = function()
  logInfo("server leave")
  reloadUiDelayed()
end

M.onExtensionUnloaded = function()
  logInfo("extension unloaded")
  reloadUiDelayed()
end

return M
