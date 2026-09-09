// =============================================================================
// PIT Economy System - Bollard UI Controller
// Version: 5.0
// License: AGPL-3.0 - https://www.gnu.org/licenses/agpl-3.0.html
// =============================================================================

angular.module('beamng.apps')
.directive('bollardUi', [function () {
  return {
    template: `
      <div id="bollard-root" style="display:none;flex-direction:column;align-items:stretch;gap:5px;height:100%;box-sizing:border-box;justify-content:flex-end;font-family:'Segoe UI',Roboto,sans-serif;font-weight:bold;">

        <div style="border:1px solid rgba(255,255,255,0.2);border-radius:8px;overflow:hidden;background:transparent;backdrop-filter:blur(10px);">

          <div style="background:rgba(30,30,30,0.25);backdrop-filter:blur(10px);border-bottom:1px solid rgba(255,255,255,0.2);padding:5px 10px;font-size:10px;color:rgba(255,255,255,0.5);text-shadow:0 0 4px #000,0 0 6px #000;display:flex;justify-content:space-between;align-items:center;letter-spacing:0.5px;">
            <span id="blk-header-title">BOLLARD</span>
            <span id="blk-count" style="color:#fbbf24;display:none;"></span>
            <span id="blk-cooldown-head" style="color:#f97316;font-size:9px;display:none;"></span>
          </div>

          <div id="blk-status" style="display:none;padding:4px 10px;font-size:10px;text-align:center;border-bottom:1px solid rgba(255,255,255,0.1);text-shadow:0 0 4px #000,0 0 6px #000;"></div>

          <div id="blk-money-row" style="display:none;padding:5px 10px;border-bottom:1px solid rgba(255,255,255,0.1);justify-content:space-between;align-items:center;font-size:11px;text-shadow:0 0 4px #000,0 0 6px #000,0 0 8px #000;">
            <span id="blk-pending-label" style="color:rgba(255,255,255,0.55);font-size:10px;">Pending</span>
            <span id="blk-money" style="color:#4ade80;">$0</span>
          </div>

          <div id="blk-timer-wrap" style="display:none;padding:5px 10px;border-bottom:1px solid rgba(255,255,255,0.1);">
            <div id="blk-stopped-label" style="font-size:9px;color:#f87171;text-shadow:0 0 4px #000;margin-bottom:3px;">&#9888; STOPPED</div>
            <div style="background:rgba(255,255,255,0.15);border-radius:3px;height:3px;overflow:hidden;">
              <div id="blk-timer-bar" style="height:100%;border-radius:3px;background:#ef4444;width:0%;transition:width 0.4s linear;"></div>
            </div>
          </div>

          <div style="padding:5px 10px;display:flex;justify-content:space-between;align-items:center;font-size:11px;text-shadow:0 0 4px #000,0 0 6px #000,0 0 8px #000;">
            <span id="blk-distance-label" style="color:rgba(255,255,255,0.55);font-size:10px;">Distance</span>
            <span id="bollard-dist" style="font-size:18px;font-weight:bold;color:white;">-- m</span>
          </div>

        </div>

        <div id="blk-undo-wrap" style="display:none;width:100%;">
          <button id="bollard-undo-btn" style="width:100%;padding:4px 0;border-radius:6px;border:1px solid rgba(239,68,68,0.4);font-family:'Segoe UI',Roboto,sans-serif;font-weight:bold;font-size:11px;cursor:pointer;background:rgba(239,68,68,0.2);color:#fca5a5;letter-spacing:0.3px;">Undo</button>
          <div style="background:rgba(255,255,255,0.1);border-radius:2px;height:2px;margin-top:3px;overflow:hidden;">
            <div id="blk-undo-bar" style="height:100%;background:#ef4444;width:100%;transition:width 0.1s linear;"></div>
          </div>
        </div>

        <button id="bollard-btn" style="width:100%;padding:6px 0;border-radius:6px;border:none;font-family:'Segoe UI',Roboto,sans-serif;font-weight:bold;font-size:12px;cursor:pointer;text-align:center;letter-spacing:0.3px;background:#374151;color:rgba(255,255,255,0.3);transition:background 0.15s,color 0.15s;">Start Mission</button>

      </div>
    `,
    replace: true,
    link: function (scope, element) {

      // -----------------------------------------------------------------------
      // Translation system
      // -----------------------------------------------------------------------

      var serverTranslations = {}
      var currentLang        = 'en'

      var fallbackText = {
        'blk_header':              'BOLLARD',
        'blk_distance':            'Distance',
        'blk_pending':             'Pending',
        'blk_stopped':             '\u26a0 STOPPED',
        'blk_start_mission':       'Start Mission',
        'blk_place_blockade':      'Place Blockade',
        'blk_requesting':          'Requesting...',
        'blk_complete':            '\u2713 Complete!',
        'blk_failed':              '\u2717 Failed',
        'blk_undo':                'Undo',
        'blk_err_too_close':       'Too close! Min 500 m',
        'blk_err_too_close_spawn': 'Too close to spawn! Min 500 m',
        'blk_err_too_fast':        'Stop first! (<5 km/h)',
        'blk_err_cooldown':        'Cooldown',
        'blk_err_already_active':  'Another Blocker is active',
        'blk_err_wl40_taken':      'Another player has a wl40',
        'blk_err_wrong_vehicle':   'Need a wl40 vehicle',
        'blk_err_denied':          'Request denied',
        'blk_err_not_synced':      'Vehicle not synced yet'
      }

      var errMap = {
        too_close:       'blk_err_too_close',
        too_close_spawn: 'blk_err_too_close_spawn',
        too_fast:        'blk_err_too_fast',
        cooldown:        'blk_err_cooldown',
        already_active:  'blk_err_already_active',
        wl40_taken:      'blk_err_wl40_taken',
        wrong_vehicle:   'blk_err_wrong_vehicle',
        denied:          'blk_err_denied',
        not_synced:      'blk_err_not_synced'
      }

      function t(key) { return serverTranslations[key] || fallbackText[key] || key }

      function updateDirection(lang) { element[0].dir = (lang === 'he' || lang === 'ar') ? 'rtl' : 'ltr' }

      function applyTranslations() {
        headerTitle.textContent    = t('blk_header')
        distLabelEl.textContent    = t('blk_distance')
        pendingLabelEl.textContent = t('blk_pending')
        stoppedLabelEl.textContent = t('blk_stopped')
        undoBtn.textContent        = t('blk_undo')
        btn.textContent            = t(currentBtnKey)
      }

      // -----------------------------------------------------------------------
      // DOM refs
      // -----------------------------------------------------------------------

      var root           = element[0]
      var btn            = element[0].querySelector('#bollard-btn')
      var distEl         = element[0].querySelector('#bollard-dist')
      var statusEl       = element[0].querySelector('#blk-status')
      var headCount      = element[0].querySelector('#blk-count')
      var headCooldown   = element[0].querySelector('#blk-cooldown-head')
      var moneyRow       = element[0].querySelector('#blk-money-row')
      var moneyEl        = element[0].querySelector('#blk-money')
      var timerWrap      = element[0].querySelector('#blk-timer-wrap')
      var timerBar       = element[0].querySelector('#blk-timer-bar')
      var undoWrap       = element[0].querySelector('#blk-undo-wrap')
      var undoBtn        = element[0].querySelector('#bollard-undo-btn')
      var undoBar        = element[0].querySelector('#blk-undo-bar')
      var headerTitle    = element[0].querySelector('#blk-header-title')
      var distLabelEl    = element[0].querySelector('#blk-distance-label')
      var pendingLabelEl = element[0].querySelector('#blk-pending-label')
      var stoppedLabelEl = element[0].querySelector('#blk-stopped-label')

      var currentBtnKey = 'blk_start_mission'

      // -----------------------------------------------------------------------
      // State
      // -----------------------------------------------------------------------

      var state = {
        isSynced:         false,
        cooldownSeconds:  0,
        missionActive:    false,
        canSpawnDistance: false,
        stopTimerActive:  false,
        speed:            0,
        pendingStart:     false,
        showingResult:    false
      }

      var statusTimer    = null
      var cooldownTicker = null

      // -----------------------------------------------------------------------
      // Button helpers
      // -----------------------------------------------------------------------

      function setBtn(key, bg, color) {
        currentBtnKey        = key
        btn.textContent      = t(key)
        btn.style.background = bg
        btn.style.color      = color
        btn.style.cursor     = 'pointer'
      }

      function getBlockingReasons() {
        var reasons = []
        if (!state.isSynced) {
          reasons.push(t('blk_err_not_synced'))
        }
        if (state.cooldownSeconds > 0) {
          reasons.push(t('blk_err_cooldown') + ' (~' + Math.ceil(state.cooldownSeconds / 60) + ' min)')
        }
        if (state.missionActive) {
          if (state.stopTimerActive)   reasons.push(t('blk_stopped'))
          if (!state.canSpawnDistance) reasons.push(t('blk_err_too_close'))
          if (state.speed >= 5)        reasons.push(t('blk_err_too_fast'))
        }
        return reasons
      }

      function refreshButton() {
        if (state.showingResult) return

        var key = state.missionActive ? 'blk_place_blockade' : 'blk_start_mission'

        if (state.pendingStart) {
          setBtn('blk_requesting', '#374151', 'rgba(255,255,255,0.5)')
          return
        }

        var reasons = getBlockingReasons()
        if (reasons.length > 0) {
          setBtn(key, '#c2410c', 'white')
        } else {
          setBtn(key, '#16a34a', 'white')
        }
      }

      function showStatus(text, color, autohide) {
        if (statusTimer) { clearTimeout(statusTimer); statusTimer = null }
        statusEl.textContent   = text
        statusEl.style.color   = color || '#f97316'
        statusEl.style.display = 'block'
        if (autohide !== false) {
          statusTimer = setTimeout(function () {
            statusEl.style.display = 'none'
            statusTimer = null
          }, 3500)
        }
      }

      function startCooldownTicker() {
        if (cooldownTicker) { clearInterval(cooldownTicker); cooldownTicker = null }
        cooldownTicker = setInterval(function () {
          if (state.cooldownSeconds > 0) {
            state.cooldownSeconds = Math.max(0, state.cooldownSeconds - 1)
            headCooldown.textContent = '~' + Math.ceil(state.cooldownSeconds / 60) + ' min'
            if (state.cooldownSeconds === 0) {
              headCooldown.style.display = 'none'
              clearInterval(cooldownTicker)
              cooldownTicker = null
              refreshButton()
            }
          }
        }, 1000)
      }

      // -----------------------------------------------------------------------
      // Event handlers
      // -----------------------------------------------------------------------

      btn.addEventListener('mousedown', function () {
        if (state.showingResult) return
        if (state.pendingStart)  return

        var reasons = getBlockingReasons()
        if (reasons.length > 0) {
          showStatus(reasons.join('  ·  '), '#f97316')
          return
        }

        bngApi.engineLua('extensions.mybollard.spawn()')
      })

      undoBtn.addEventListener('mousedown', function () {
        bngApi.engineLua('extensions.mybollard.undoLastBlockade()')
      })

      function onTranslations(data) {
        if (!data || !data.translations) return
        serverTranslations = data.translations
        currentLang        = data.lang || 'en'
        applyTranslations()
        updateDirection(currentLang)
      }

      scope.$on('EconomyUI_TranslationsUpdate', function (e, data) { onTranslations(data) })

      scope.$on('BollardVisible', function (event, data) {
        root.style.display = data.visible ? 'flex' : 'none'
      })

      scope.$on('ECON_EditingModeUpdate', function (event, data) {
        state.isSynced = !data.isEditing
        refreshButton()
      })

      scope.$on('BollardUpdate', function (event, data) {
        if (data.distance < 0) {
          distEl.textContent = '-- m'
          distEl.style.color = 'white'
        } else {
          distEl.textContent = data.distance + ' m'
          distEl.style.color = data.can_spawn ? '#4ade80' : '#f97316'
        }
        state.canSpawnDistance = !!data.can_spawn
        state.speed            = data.speed || 0
        refreshButton()
      })

      scope.$on('BollardMissionUpdate', function (event, data) {
        if (data.active) {
          headCount.textContent   = (data.blockade_count || 0) + ' / ' + (data.required || 5)
          headCount.style.display = 'inline'
          moneyEl.textContent     = '$' + (data.pending_money || 0).toLocaleString()
          moneyRow.style.display  = 'flex'
          if (statusTimer) { clearTimeout(statusTimer); statusTimer = null }
          statusEl.style.display  = 'none'

          state.missionActive  = true
          state.pendingStart   = false
          state.showingResult  = false
          refreshButton()
        } else {
          headCount.style.display = 'none'
          moneyRow.style.display  = 'none'
          timerWrap.style.display = 'none'
          undoWrap.style.display  = 'none'

          state.missionActive    = false
          state.canSpawnDistance = false
          state.stopTimerActive  = false
          state.pendingStart     = false
          state.showingResult    = true

          if (data.success) {
            setBtn('blk_complete', '#15803d', 'white')
          } else {
            setBtn('blk_failed', '#7f1d1d', 'rgba(255,255,255,0.4)')
          }

          setTimeout(function () {
            state.showingResult = false
            refreshButton()
          }, 4000)
        }
      })

      scope.$on('BollardStopTimer', function (event, data) {
        if (data.active) {
          timerWrap.style.display = 'block'
          timerBar.style.width    = Math.min(100, ((data.elapsed || 0) / (data.limit || 14)) * 100) + '%'
          state.stopTimerActive   = true
        } else {
          timerWrap.style.display = 'none'
          timerBar.style.width    = '0%'
          state.stopTimerActive   = false
        }
        refreshButton()
      })

      scope.$on('BollardUndoUpdate', function (event, data) {
        if (data.active) {
          undoWrap.style.display = 'block'
          undoBar.style.width    = Math.max(0, (data.remaining / data.total) * 100) + '%'
        } else {
          undoWrap.style.display = 'none'
          undoBar.style.width    = '100%'
        }
      })

      scope.$on('BollardStatus', function (event, data) {
        if (data.status === 'requesting') {
          state.pendingStart = true
          showStatus(t('blk_requesting'), '#facc15', false)
          refreshButton()
        } else if (data.error) {
          state.pendingStart = false
          showStatus(t(errMap[data.error] || data.error), '#f97316')
          refreshButton()
        }
      })

      scope.$on('BollardServerCooldown', function (event, data) {
        state.cooldownSeconds = data.cooldown_seconds || 0
        if (state.cooldownSeconds > 0) {
          headCooldown.textContent   = '~' + Math.ceil(state.cooldownSeconds / 60) + ' min'
          headCooldown.style.display = 'inline'
          startCooldownTicker()
        } else {
          headCooldown.style.display = 'none'
          if (cooldownTicker) { clearInterval(cooldownTicker); cooldownTicker = null }
        }
        refreshButton()
      })

      scope.$on('$destroy', function () {
        if (statusTimer)    clearTimeout(statusTimer)
        if (cooldownTicker) clearInterval(cooldownTicker)
      })
    }
  }
}])