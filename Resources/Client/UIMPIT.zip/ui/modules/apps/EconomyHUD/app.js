// =============================================================================
// PIT Economy System - HUD Controller
// Version: 5.0
// License: AGPL-3.0 - https://www.gnu.org/licenses/agpl-3.0.html
// =============================================================================

angular.module('beamng.apps')
.directive('economyHud', function() {
  return {
    restrict: 'E',
    templateUrl: '/ui/modules/apps/EconomyHUD/app.html',
    replace: true,
    controller: function($scope, $timeout) {

      // Set to true to enable the Discord & Rulebook buttons in the welcome screen.
      // Leave as false until you have filled in your own URLs below.
      var LINKS_ENABLED = false;

      // TODO: Replace with your own Discord invite link (e.g. 'https://discord.gg/XXXXXXX')
      var DISCORD_URL  = 'https://discord.gg/xxxxxxxx';

      // TODO: Replace with your own rulebook/website URL (e.g. 'https://yoursite.com/rules')
      var RULEBOOK_URL = 'https://yoursite.com/rules';

      // Set to true if you have QR images in the EconomyHUD folder (qr_discord.png, qr_rulebook.png).
      var SHOW_QR_CODES = false;

      $scope.linksEnabled = LINKS_ENABLED;
      $scope.showQrCodes  = SHOW_QR_CODES;

      // -------------------------------------------------------------------------
      // Initial state
      // -------------------------------------------------------------------------

      window.PIT_ECON_SESSION = window.PIT_ECON_SESSION || {
        welcomeDone:  false,
        authDone:     false,
        translations: null,
        inServer:     null
      };
      var SESSION = window.PIT_ECON_SESSION;

      function resetPitSession() {
        SESSION.welcomeDone  = false;
        SESSION.authDone     = false;
        SESSION.translations = null;
      }

      if (!window.PIT_ECON_SESSION_WATCHER) {
        window.PIT_ECON_SESSION_WATCHER = setInterval(function() {
          if (!window.bngApi || typeof window.bngApi.engineLua !== 'function') return;
          window.bngApi.engineLua(
            'extensions.MPCoreNetwork and extensions.MPCoreNetwork.isMPSession and extensions.MPCoreNetwork.isMPSession() or false',
            function(res) {
              if (res !== true && res !== false) return;
              var prev = SESSION.inServer;
              SESSION.inServer = res;
              if (prev === true && res === false) { resetPitSession(); }
            }
          );
        }, 4000);
      }

      var savedLang = null;
      try {
        savedLang = localStorage.getItem('economyUI_language');
      } catch(e) {
        console.warn('[EconomyUI] Could not read language from localStorage:', e);
      }

      var savedUsername     = null;
      var savedPasswordHash = null;
      var deviceToken       = null;
      var savedMigrationToken = null;
      try {
        savedUsername       = localStorage.getItem('pit_username');
        savedPasswordHash   = localStorage.getItem('pit_password_hash');
        savedMigrationToken = localStorage.getItem('pit_migration_token');
        deviceToken         = localStorage.getItem('pit_device_token');
        if (!deviceToken) {
          deviceToken = crypto.randomUUID();
          localStorage.setItem('pit_device_token', deviceToken);
        }
      } catch(e) {}

      $scope.showWelcomeScreen = !SESSION.welcomeDone;
      $scope.currentStep       = SESSION.welcomeDone ? 4 : 1;
      $scope.authStep          = 'login';
      $scope.authData          = { username: savedUsername || '', password: '' };
      $scope.authError         = '';
      $scope.authLoading       = false;
      $scope.authRequired      = false;
      $scope.hasSavedPassword  = !!(savedPasswordHash);
      $scope.migrationToken    = savedMigrationToken || null;
      $scope.tokenCopied       = false;
      $scope.isUIOpen          = true;
      $scope.minimalStyle      = false;
      try { $scope.minimalStyle = localStorage.getItem('pit_minimal_style') === 'true'; } catch(e) {}
      $scope.isLangOpen        = false;
      $scope.spawnsMenuOpen    = false;
      $scope.balance           = 0;
      $scope.wantedTime        = 0;

      $scope.selectedLang  = savedLang || 'en';
      $scope.policeNearby  = false;
      $scope.bustProgress  = { active: false, percent: 0 };
      $scope.repairIcons   = 0;
      $scope.maxRepairs    = 2;

      $scope.wantedEnabled    = true;
      $scope.showWantedToggle = false;
      $scope.isPolice         = false;
      $scope.navEnabled      = false;
      var navPreference      = false;
      var prevWantedForNav   = 0;
      var prevPoliceForNav   = false;
      try { navPreference = localStorage.getItem('pit_nav_preference') === 'true'; } catch(e) {}

      $scope.showSyncButton    = false;
      $scope.isEditingVehicle  = false;

      $scope.rankData = {
        rank: 1, rank_name_key: 'rank_1_name', prefix: '[I]',
        percent: 0, completed: 0, total: 0, tasks: [], max_rank: 20,
        total_points: 0, pts_to_next: 0, next_prefix: '[II]',
        milestones_done: 0, milestones_total: 0
      };
      $scope.showRankPanel          = false;
      $scope.rankBarGlow            = false;
      $scope.pointsNotifications    = [];
      $scope.showRankUpCelebration  = false;
      $scope.rankUpData             = { old_rank: 0, new_rank: 0, reward: 0, new_prefix: '' };

      $scope.taskGroups             = { available: [], done: [], locked: [] };
      var COUNTUP_MS                = 2500;

      $scope.showTransferWindow = false;
      $scope.transferData       = { recipient: '', amount: 0 };

      $scope.airPollutorAlert = { show: false, title: '', message: '', success: null };
      $scope.apStatusPanel    = { visible: false };
      $scope.powerupInventory = { spike_strip: 0 };
      $scope.copInventories   = {};

      // -------------------------------------------------------------------------
      // Air Polluter alert helper
      // -------------------------------------------------------------------------

      function showAPAlert(title, message, success) {
        $scope.$applyAsync(function() {
          $scope.airPollutorAlert = { show: true, title: title, message: message, success: success };
        });
        $timeout(function() {
          $scope.$applyAsync(function() { $scope.airPollutorAlert.show = false; });
        }, 6000);
      }

      // -------------------------------------------------------------------------
      // Translations
      // -------------------------------------------------------------------------

      var serverTranslations = SESSION.translations || {};

      var fallbackText = {
        "help_title": "Economy Mod Help:",
        "help_money": "/money - Display your current balance.",
        "help_who": "/who - Display the list of connected players.",
        "help_pay": "/pay <player number> <amount> - Send money to another player.",
        "help_setlang": "/setlang <language code> - Change language (he, en, ar, de, it, fr, es, ru, cs, hu, ja_JP, pl_PL, pt_BR, pt_PT, sv_SE, tr_TR, uk, zh_Hans).",
        "help_repair": "/repair - (Command currently inactive)",
        "help_rank": "/rank - View your rank progress and tasks.",
        "help_stats": "/stats [player_id] - View player statistics.",
        "balance": "Your current balance is: ${money}",
        "your_balance": "Your current balance is: ${money}",
        "invalid_target": "Target player is not connected or invalid.",
        "no_money": "You don't have enough money for this action.",
        "pay_sent": "You sent ${amount} to ${to}. Your new balance: ${money}",
        "pay_received": "You received ${amount} from ${from}. Your new balance: ${money}",
        "lang_not_found": "Language code not found. Supported languages: ${supported_langs}",
        "language_changed": "Language changed successfully.",
        "cool_player_message": "Follow the server rules.",
        "added_money_per_minute": "You earned **$${amount}** for being with us! Your new balance: ${money}",
        "welcome_server": "Welcome to the server! Enjoy!",
        "welcome_police": "Welcome, officer! Maintain order.",
        "welcome_civilian": "Welcome, civilian! Drive safely.",
        "who_title": "Connected players list:",
        "speed_start_wanted": "WANTED: Excessive speeding! You have ${duration} seconds to evade the police and earn your reward!",
        "zigzag_start_wanted": "WANTED: Reckless driving! You have ${duration} seconds to evade the police and earn your reward!",
        "zigzag_end_reward": "Successful evasion! You successfully evaded the police and earned **$${amount}**!",
        "wanted_extended": "WANTED status extended by ${seconds} seconds!",
        "wanted_fail_message": "MISSION FAILED! You were fined **$${penalty}** due to ${reason}.",
        "speeding_end_reward": "Successful evasion! You successfully evaded the police and earned **$${amount}**!",
        "evaded_both_bonus": "Combo escape! You completed both missions and earned a combo bonus of **$${amount}**!",
        "busted_global_message": "BUSTED! ${criminal} was caught by the police!",
        "police_bust_bonus": "You received $${amount} for busting the wanted ${criminal}!",
        "reason_vehicle_reset": "vehicle reset",
        "reason_vehicle_edited": "vehicle repair/modification",
        "reason_change_vehicle": "vehicle change",
        "reason_player_left": "disconnection from server",
        "reason_became_police": "becoming a police officer",
        "reason_exit_vehicle": "exiting vehicle",
        "reason_vehicle_delete": "vehicle deletion",
        "reason_busted": "caught by police",
        "reason_home_button": "pressing home button",
        "repair_too_fast": "Too fast! Slow down below 5 km/h to repair.",
        "civilian_not_wanted": "You're not wanted, no need for repair.",
        "civilian_no_repairs": "You have no repairs available.",
        "civilian_no_repairs_left": "You ran out of repairs.",
        "civilian_repair_success": "Vehicle repaired! Used ${used}/${total} repairs.",
        "police_repair_wanted_nearby": "Wanted person nearby! Move at least ${range} m away.",
        "police_no_repairs_left": "You ran out of repairs. Wait ${cooldown_minutes} minutes.",
        "police_repair_success": "Vehicle repaired successfully!",
        "civilian_repair_police_nearby": "Police officer nearby! Move at least ${range} m away.",
        "teleported_home": "Teleported to spawn point.",
        "teleport_cooldown": "Wait 2 seconds before next teleport.",
        "teleport_on_edit": "Vehicle edit during mission - teleporting to spawn!",
        "teleport_on_reset": "Unauthorized vehicle reset - teleporting to spawn!",
        "teleport_on_change": "Vehicle change during mission - teleporting to spawn!",
        "marker_spawned_at_dockyards": "A repair marker has spawned at the Dockyards!",
        "marker_spawned_at_drain_canal": "A repair marker has spawned in the Drain Canal!",
        "marker_spawned_at_abandoned_cabin": "A repair marker has spawned near the Abandoned Cabin!",
        "marker_spawned_at_mount_wallis": "A repair marker has spawned at Mount Wallis!",
        "marker_spawned_at_mount_wallis_gas_station": "A repair marker has spawned at the Mount Wallis Gas Station!",
        "marker_spawned_at_oil_ref_tank_island": "A repair marker has spawned near the island's oil refinery tank!",
        "marker_spawned_at_train_bridge_stairs_island": "A repair marker has spawned at the train bridge stairs on the island!",
        "marker_spawned_at_little_china": "A repair marker has spawned in Little China!",
        "marker_spawned_at_train_track_start": "A repair marker has spawned at the start of the train tracks!",
        "marker_spawned_at_rent_a_box": "A repair marker has spawned near Rent-A-Box!",
        "marker_spawned_at_sealbrik": "A repair marker has spawned at Sealbrik!",
        "marker_spawned_at_easy_auto_repair": "A repair marker has spawned at Easy Auto Repair!",
        "marker_spawned_at_near_fish_pond": "A repair marker has spawned near the Fish Pond!",
        "marker_spawned_at_new_residential_district": "A repair marker has spawned in the New Residential District!",
        "marker_spawned_at_near_water_tower": "A repair marker has spawned near the Water Tower!",
        "marker_spawned_at_new_container_area": "A repair marker has spawned in the New Container Area!",
        "marker_spawned_at_high_mountain": "A repair marker has spawned on the High Mountain!",
        "marker_spawned_at_bypass_road": "A repair marker has spawned on the Bypass Road!",
        "marker_spawned_at_triangle_before_bridge": "A repair marker has spawned at the Triangle before the Bridge!",
        "marker_spawned_at_new_hill": "A repair marker has spawned on the New Hill!",
        "marker_spawned_at_new_bridge_edge": "A repair marker has spawned at the New Bridge Edge!",
        "marker_captured": "${player} captured the repair marker!",
        "marker_reward_success": "You got +1 repair and earned $200!",
        "marker_reward_limit": "You've reached max repairs, but earned $200!",
        "open_ui": "Open",
        "close_ui": "Close",
        "currency_symbol": "$",
        "wanted_label": "WANTED",
        "language_label": "Language",
        "being_arrested": "Being Arrested",
        "return_home": "Return Home",
        "repair_vehicle": "Repair Vehicle",
        "disable_wanted": "Disable Wanted Mode",
        "enable_wanted": "Enable Wanted Mode",
        "sync_vehicle": "Finish Editing & Sync",
        "btn_next": "Next",
        "btn_finish": "I have read and agree to all the rules",
        "step1_title": "Basic Income",
        "step1_line1": "Starting Money: $50,000",
        "step1_line2": "Passive Salary: $75 every few minutes",
        "step1_line3": "BX-Series vehicles are always free",
        "step2_title": "Cops - Rules & Rewards",
        "step2_subtitle1": "Cops Income",
        "step2_income1": "$8 per second when a Wanted player is within 150 meters",
        "step2_income2": "$3,000 for every successful arrest",
        "step2_subtitle2": "Arrest Rules - How to Arrest?",
        "step2_arrest1": "Enter within 25 meters of the suspect",
        "step2_arrest2": "Suspect must be under 5 km/h",
        "step2_arrest3": "Stay in range for 7 seconds",
        "step2_arrest4": "Successful arrest",
        "step2_subtitle3": "Cops Repairs",
        "step2_repair1": "Starts with 1 repair + markers (max 2)",
        "step2_repair2": "Conditions:",
        "step2_repair2a": "No Wanted players nearby",
        "step2_repair2b": "Under 5 km/h",
        "step2_pit_rule": "You may arrest a Wanted player only by a clean side PIT maneuver",
        "step2_roadblock_rule": "OR by a police roadblock that was placed at least 5 seconds in advance.",
        "step2_ramming_warning": "Don't be a rammer - it will get you kicked from the server.",
        "step3_title": "Wanted Players - Missions & Rewards",
        "step3_speed_title": "Speed Mission",
        "step3_speed_desc": "Driving over 150 km/h → Become Wanted for 4 minutes",
        "step3_speed_repairs": "Available repairs: 0 (collect markers for repairs)",
        "step3_speed_income": "$4/second per cop within 150 meters",
        "step3_speed_bonus": "End bonus: $900",
        "step3_zigzag_title": "Zigzag Mission",
        "step3_zigzag_desc": "Perform 5 sharp left/right turns → Become Wanted for 7 minutes",
        "step3_zigzag_repairs": "Available repairs: 0 (collect markers for repairs)",
        "step3_zigzag_income": "$7/second when a cop is within 150 meters",
        "step3_zigzag_bonus": "End bonus: $1,500",
        "step3_combo_title": "Combo (Speed + Zigzag)",
        "step3_combo_repairs": "Base: 0 | Combo bonus: +1 | Markers: up to 2 total",
        "step3_combo_income": "$11/second",
        "step3_combo_bonus": "End bonus: $2,500",
        "step3_penalty_title": "Penalties (-$750 each)",
        "step3_penalty1": "Caught by a cop",
        "step3_penalty2": "Editing the vehicle / exiting the vehicle",
        "step3_penalty3": "Using Reset",
        "step3_penalty4": "Pressing Home",
        "step3_repair_cond_title": "Repair Conditions",
        "step3_repair_cond1": "Repairs are allowed only under 5 km/h and 50 m away from rivals",
        "step3_repair_cond2": "Repairs can only be obtained by collecting markers (max 2 per player)",
        "step4_title": "Server Rules",
        "step4_rule1": "Respect all players and staff",
        "step4_rule2": "Drive realistically only",
        "step4_rule3": "No intentional ramming",
        "step4_rule4": "Use common sense at all times",
        // Discord & Rulebook button labels (translatable via server)
        "btn_discord":        "Join Discord",
        "btn_rulebook":       "Server Rulebook",
        "welcome_links_hint": "Scan the QR codes or click to open in your browser",
        "qr_label_discord":   "Join Discord",
        "qr_label_rulebook":  "Server Rulebook",
        "rank_panel_title": "Driver Rank",
        "complete": "Complete",
        "cop_tasks": "Police Tasks",
        "wanted_tasks": "Wanted Tasks",
        "rank_up": "Rank Up",
        "awesome": "Awesome",
        "rank_1_name": "Asphalt Rookie",
        "rank_2_name": "Operational Driver",
        "rank_3_name": "Tactical Expert",
        "rank_4_name": "Road Ruler",
        "rank_5_name": "The Ultimate Driver",
        "task_cop_arrests_1": "Arrest 3 criminals",
        "task_cop_arrests_2": "Arrest 8 criminals",
        "task_cop_arrests_3": "Arrest 15 criminals",
        "task_cop_arrests_4": "Arrest 25 criminals",
        "task_cop_arrests_5": "Arrest 40 criminals",
        "task_cop_chase_1": "Chase wanted for 2 minutes",
        "task_cop_chase_2": "Chase wanted for 5 minutes",
        "task_cop_chase_3": "Chase wanted for 10 minutes",
        "task_cop_chase_4": "Chase wanted for 20 minutes",
        "task_cop_chase_5": "Chase wanted for 40 minutes",
        "task_wanted_escape_1": "Escape 2 times",
        "task_wanted_escape_2": "Escape 5 times",
        "task_wanted_escape_3": "Escape 10 times",
        "task_wanted_escape_4": "Escape 20 times",
        "task_wanted_escape_5": "Escape 35 times",
        "task_wanted_zigzag_1": "Zigzag near police 3 times",
        "task_wanted_zigzag_2": "Zigzag near police 10 times",
        "task_wanted_zigzag_3": "Zigzag near police 15 times",
        "task_wanted_zigzag_4": "Zigzag near police 20 times",
        "task_wanted_zigzag_5": "Zigzag near police 35 times",
        "task_wanted_combo_1": "Combo escape 2 times",
        "task_wanted_combo_2": "Combo escape 8 times",
        "task_wanted_combo_3": "Combo escape 15 times",
        "rank_up_message":    "RANK UP! You reached rank ${rank}! Reward: **$${reward}**",
        "rank_up_broadcast":  "${player} reached rank ${rank}!",
        "points_label":       "pts",
        "milestones_label":   "Milestones",
        "tasks_role_police":      "Police",
        "tasks_role_wanted":      "Wanted",
        "tasks_role_global":      "Global",
        "tasks_group_completed":  "Completed",
        "tasks_group_available":  "Available",
        "tasks_group_locked":     "Locked",
        "task_cop_markers_1": "Collect 5 markers",
        "task_cop_markers_2": "Collect 10 markers",
        "task_cop_markers_3": "Collect 18 markers",
        "task_cop_markers_4": "Collect 30 markers",
        "task_cop_markers_5": "Collect 50 markers",
        "task_cop_markers_chase_1": "Collect 2 markers in active chase",
        "task_cop_markers_chase_2": "Collect 4 markers in active chase",
        "task_cop_markers_chase_3": "Collect 7 markers in active chase",
        "task_cop_markers_chase_4": "Collect 12 markers in active chase",
        "task_cop_markers_chase_5": "Collect 20 markers in active chase",
        "task_wanted_markers_1": "Collect 5 markers",
        "task_wanted_markers_2": "Collect 10 markers",
        "task_wanted_markers_3": "Collect 18 markers",
        "task_wanted_markers_4": "Collect 30 markers",
        "task_wanted_markers_5": "Collect 50 markers",
        "task_wanted_markers_chase_1": "Collect 2 markers while chased",
        "task_wanted_markers_chase_2": "Collect 4 markers while chased",
        "task_wanted_markers_chase_3": "Collect 7 markers while chased",
        "task_wanted_markers_chase_4": "Collect 12 markers while chased",
        "task_wanted_markers_chase_5": "Collect 20 markers while chased",
        "pts_action_marker_capture":       "Marker captured",
        "pts_action_close_marker_capture": "Close marker!",
        "pts_action_bust":                 "Criminal arrested",
        "pts_action_escape":               "Escaped!",
        "pts_action_zigzag_pressure":      "Zigzag pressure",
        "pts_action_combo_escape":         "Combo escape!",
        "pts_action_cop_marker_chase":     "Marker during chase",
        "pts_action_wanted_marker_chase":  "Marker while fleeing",
        "wanted_global_speeding":  "${player} committed excessive speeding and became WANTED!",
        "wanted_global_zigzag":    "${player} committed reckless driving and became WANTED!",
        "wanted_fail_global":      "${player} failed the WANTED mission!",
        "wanted_escape_global":    "${player} has successfully escaped!",
        "editing_mode_banner":     "Editing Mode Active | Vehicle Won't Sync Until You Press Sync",
        "tooltip_home":            "Home",
        "tooltip_repair":          "Repair Vehicle",
        "tooltip_wanted_enable":   "Enable Wanted Challenges",
        "tooltip_wanted_disable":  "Disable Wanted Challenges",
        "tooltip_sync":            "Send Vehicle to Sync",
        "tooltip_language":        "Language",
        "tooltip_open":            "Open",
        "tooltip_close":           "Close",
        "tooltip_rank":            "Driver Rank",
        "wanted_cleared_editing":  "Your wanted status was cleared because you entered edit mode",
        "editing_wanted_disabled": "Challenge mode disabled during editing",
        "editing_wanted_enabled":  "Challenge mode re-enabled after editing",
        "editing_wanted_blocked":  "Cannot enter challenge mode while editing vehicle",
        "spawn_not_available":     "This spawn location is not available on the current map",
        "spawn_location":          "Spawn Location",
        "show_spawn_menu":         "Actions",
        "hide_spawn_menu":         "Actions",
        "transfer_window_title":         "Transfer Money",
        "transfer_recipient":            "Player ID:",
        "transfer_amount":               "Amount:",
        "transfer_send_button":          "Send Money",
        "transfer_cancel_button":        "Cancel",
        "transfer_limit_reached":        "Transfer limit reached! You can send max $10,000 to this player per hour.",
        "transfer_moderator_limit":      "Transfer limit reached! Moderators can send max $50,000 per player per hour.",
        "transfer_invalid_amount":       "Please enter a valid amount.",
        "transfer_invalid_recipient":    "Please enter a valid player ID.",
        "transfer_success":              "Successfully sent $${amount} to ${recipient}!",
        "transfer_insufficient_funds":   "Insufficient funds!",
        "transfer_self":                 "You cannot send money to yourself!",
        "airpolluter_alert_title":       "AIR POLLUTION ALERT",
        "airpolluter_alert_body":        "is polluting the air! Stop them before it's too late!",
        "airpolluter_end_title_success": "AIR CLEAR",
        "airpolluter_end_body_success":  "The air polluter escaped. The skies are clearing.",
        "airpolluter_end_title_fail":    "POLLUTION STOPPED",
        "airpolluter_end_body_fail":     "The suspect was caught. Air quality restored.",
        "ap_status_title":        "Air Polluter Mission",
        "ap_status_hold_hint":    "Hold position for 5 seconds to activate",
        "ap_reason_cooldown":     "Mission is on cooldown",
        "ap_reason_players":      "Not enough players on the server",
        "ap_reason_not_civilian": "Must be playing as a civilian",
        "ap_reason_wanted":       "Cannot start while wanted",
        "ap_reason_editing":      "Cannot start while editing a vehicle",
        "ap_players_label":       "players",
        "ap_cooldown_label":      "Available in",
        "marker_spawned_at_fields_area":      "A repair marker has spawned at the Fields!",
        "marker_spawned_at_city_gas_station": "A repair marker has spawned at the City Gas Station!",
        "marker_spawned_at_narrow_city_road": "A repair marker has spawned on the Narrow City Road!",
        "marker_spawned_at_fishing_village":  "A repair marker has spawned at the Fishing Village!",
        "marker_spawned_at_western_trail":    "A repair marker has spawned on the Western Trail!",
        "marker_spawned_at_north_dirt_trail": "A repair marker has spawned on the North Dirt Trail!",
        "marker_spawned_at_near_tower":       "A repair marker has spawned near the Tower!",
        "marker_spawned_at_tree_lined_path":  "A repair marker has spawned on the Tree-Lined Path!",
        "marker_spawned_at_sawmill":          "A repair marker has spawned at the Sawmill!",
        "auth_login_title":          "Sign In",
        "auth_register_title":       "Create Account",
        "auth_login":                "Sign In",
        "auth_register":             "Register",
        "auth_username":             "Username",
        "auth_password":             "Password",
        "auth_username_placeholder": "3-20 chars, letters/numbers/_/-",
        "auth_password_placeholder": "Your password",
        "auth_do_login":             "Sign In",
        "auth_do_register":          "Create Account",
        "auth_loading":              "Please wait...",
        "auth_empty_fields":         "Please fill in all fields.",
        "auth_username_length":      "Username must be 3-20 characters.",
        "auth_username_invalid":     "Username: letters, numbers, _ or - only.",
        "auth_username_taken":       "Username already taken.",
        "auth_not_found":            "Username not found.",
        "auth_wrong_password":       "Incorrect password.",
        "auth_failed":               "Authentication failed.",
        "auth_invalid":              "Invalid data.",
        "tooltip_change_account":    "Change Account",
        "auth_password_saved":       "Leave empty to sign in with saved password",
        "tooltip_spike_strip":       "Spike Strip",
        "tooltip_banana":            "Banana Peel",
        "tooltip_cannon":            "Cannon",
        "tooltip_nav_on":            "Navigate to Nearest Marker",
        "tooltip_nav_off":           "Stop Navigation"
      };

      $scope.t = function(key, vars) {
        var text = serverTranslations[key] || fallbackText[key] || key;
        if (vars) {
          for (var k in vars) {
            text = text.replace('${' + k + '}', vars[k]);
          }
        }
        return text;
      };

      // -------------------------------------------------------------------------
      // Welcome screen
      // -------------------------------------------------------------------------

      function sha256hex(message) {
        var buf = new TextEncoder().encode(message);
        return crypto.subtle.digest('SHA-256', buf).then(function(hash) {
          return Array.from(new Uint8Array(hash))
            .map(function(b) { return b.toString(16).padStart(2, '0'); })
            .join('');
        });
      }

      $scope.submitAuth = function(mode) {
        var username = ($scope.authData.username || '').trim();
        var password = $scope.authData.password  || '';
        if (!username) {
          $scope.$applyAsync(function() { $scope.authError = $scope.t('auth_empty_fields'); });
          return;
        }
        if (username.length < 3 || username.length > 20) {
          $scope.$applyAsync(function() { $scope.authError = $scope.t('auth_username_length'); });
          return;
        }
        if (!password && savedPasswordHash && savedUsername === username && mode === 'login') {
          $scope.$applyAsync(function() { $scope.authLoading = true; $scope.authError = ''; });
          var p = JSON.stringify({ mode: 'login', username: username, hash: savedPasswordHash, device_token: deviceToken });
          if (window.bngApi) window.bngApi.engineLua('TriggerServerEvent("ECON_Auth", [==[' + p + ']==])');
          return;
        }
        if (!password) {
          $scope.$applyAsync(function() { $scope.authError = $scope.t('auth_empty_fields'); });
          return;
        }
        $scope.$applyAsync(function() { $scope.authLoading = true; $scope.authError = ''; });
        sha256hex(password).then(function(hash) {
          if (window.bngApi && typeof window.bngApi.engineLua === 'function') {
            var p = JSON.stringify({ mode: mode, username: username, hash: hash, device_token: deviceToken });
            window.bngApi.engineLua('TriggerServerEvent("ECON_Auth", [==[' + p + ']==])');
          }
          try {
            localStorage.setItem('pit_username',      username);
            localStorage.setItem('pit_password_hash', hash);
          } catch(e) {}
        });
      };

      $scope.switchAuthStep = function(step) {
        $scope.$applyAsync(function() { $scope.authStep = step; $scope.authError = ''; });
      };

      $scope.copyMigrationToken = function() {
        var token = $scope.migrationToken;
        if (!token) return;
        try {
          navigator.clipboard.writeText(token);
        } catch(e) {
          var el = document.createElement('textarea');
          el.value = token;
          document.body.appendChild(el);
          el.select();
          document.execCommand('copy');
          document.body.removeChild(el);
        }
        $scope.$applyAsync(function() { $scope.tokenCopied = true; });
        $timeout(function() {
          $scope.$applyAsync(function() { $scope.tokenCopied = false; });
        }, 2000);
      };

      $scope.nextStep = function() {
        if ($scope.currentStep < 4) {
          $scope.currentStep++;
          $timeout(function() {
            var content = document.querySelector('.welcome-content');
            if (content) content.scrollTop = 0;
          }, 10);
        }
      };

      $scope.acceptRules = function() {
        SESSION.welcomeDone = true;
        $scope.showWelcomeScreen = false;
      };

      // -------------------------------------------------------------------------
      // Discord & Rulebook links
      // -------------------------------------------------------------------------

      var BNG_PROXY = 'https://www.beamng.com/proxy.php?link=';

      function openExternalLink(url) {
        if (window.bngApi && typeof window.bngApi.engineLua === 'function') {
          window.bngApi.engineLua('MPCoreNetwork.openURL("' + url + '")');
        } else {
          console.error('[EconomyUI] bngApi not available for openURL');
        }
      }

      function openExternalLinkLegacy(url) {
        if (window.bngApi && typeof window.bngApi.engineLua === 'function') {
          window.bngApi.engineLua('openWebBrowser("' + BNG_PROXY + url + '")');
        } else {
          console.error('[EconomyUI] bngApi not available for openWebBrowser');
        }
      }

      $scope.openDiscord = function() {
        openExternalLink(DISCORD_URL);
      };

      $scope.openRulebook = function() {
        openExternalLinkLegacy(RULEBOOK_URL);
      };

      // -------------------------------------------------------------------------
      // UI controls
      // -------------------------------------------------------------------------

      $scope.toggleUI         = function() { $scope.$applyAsync(function() { $scope.isUIOpen       = !$scope.isUIOpen;       }); };

      function applyStyleClass() {
        var root = document.getElementById('economy-hud-container');
        if (!root) return;
        if ($scope.minimalStyle) root.classList.add('outlined');
        else root.classList.remove('outlined');
      }
      $scope.toggleUIStyle = function() {
        $scope.$applyAsync(function() {
          $scope.minimalStyle = !$scope.minimalStyle;
          try { localStorage.setItem('pit_minimal_style', String($scope.minimalStyle)); } catch(e) {}
          applyStyleClass();
        });
      };
      $timeout(applyStyleClass, 0);
      $scope.toggleLangMenu   = function() { $scope.$applyAsync(function() { $scope.isLangOpen     = !$scope.isLangOpen;     }); };
      $scope.toggleSpawnsMenu = function() { $scope.$applyAsync(function() { $scope.spawnsMenuOpen = !$scope.spawnsMenuOpen; }); };

      $scope.setLanguage = function(lang) {
        if (window.bngApi && typeof window.bngApi.engineLua === 'function') {
          window.bngApi.engineLua("setPlayerLanguage('" + lang + "')");
        }
        $scope.$applyAsync(function() {
          $scope.selectedLang = lang;
          $scope.isLangOpen   = false;
          updateDirection(lang);
          try {
            localStorage.setItem('economyUI_language', lang);
          } catch(e) {
            console.warn('[EconomyUI] Could not save language to localStorage:', e);
          }
        });
      };

      function updateDirection(lang) {
        var container = document.getElementById('economy-hud-container');
        if (container) {
          container.dir = (lang === 'he' || lang === 'ar') ? 'rtl' : 'ltr';
        }
      }

      if (savedLang) {
        updateDirection(savedLang);
      }

      // -------------------------------------------------------------------------
      // Formatting helpers
      // -------------------------------------------------------------------------

      $scope.formatCooldown = function(seconds) {
        if (!seconds || seconds <= 0) return '';
        var h = Math.floor(seconds / 3600);
        var m = Math.floor((seconds % 3600) / 60);
        if (h > 0) return h + 'h ' + m + 'm';
        return m + 'm';
      };

      $scope.formatTime = function(totalSeconds) {
        if (totalSeconds <= 0) return '00:00';
        var minutes = Math.floor(totalSeconds / 60);
        var seconds = totalSeconds % 60;
        return (minutes < 10 ? '0' : '') + minutes + ':' + (seconds < 10 ? '0' : '') + seconds;
      };

      $scope.getRepairArray = function() { return new Array(Math.min($scope.repairIcons, 10)); };

      // -------------------------------------------------------------------------
      // Spawn / navigation
      // -------------------------------------------------------------------------

      $scope.optionalSpawns = [
        { id: 1, icon: '1' },
        { id: 2, icon: '2' },
        { id: 3, icon: '3' }
      ];

      $scope.teleportToSpawn = function(spawnIndex) {
        if (window.bngApi && typeof window.bngApi.engineLua === 'function') {
          window.bngApi.engineLua('requestOptionalSpawn(' + spawnIndex + ')');
        } else {
          console.error('[EconomyUI] bngApi not available for optional spawn');
        }
      };

      $scope.returnHome = function() {
        if (window.bngApi && typeof window.bngApi.engineLua === 'function') {
          window.bngApi.engineLua('extensions.hook("trackNewPosition"); TriggerServerEvent("requestHomeButton", "home")');
        }
      };

      $scope.repairVehicle = function() {
        if ($scope.repairIcons <= 0) return;
        if (window.bngApi && typeof window.bngApi.engineLua === 'function') {
          window.bngApi.engineLua('TriggerServerEvent("requestVehicleRepair", "repair")');
        }
      };

      $scope.toggleWantedMode = function() {
        if (window.bngApi && typeof window.bngApi.engineLua === 'function') {
          window.bngApi.engineLua('toggleWantedEnabled()');
        } else {
          console.error('[EconomyUI] bngApi not available');
        }
      };

      $scope.toggleNav = function() {
        navPreference = !$scope.navEnabled;
        try { localStorage.setItem('pit_nav_preference', String(navPreference)); } catch(e) {}
        if (window.bngApi && typeof window.bngApi.engineLua === 'function') {
          window.bngApi.engineLua('toggleMarkerNavigation()');
        }
      };

      $scope.syncVehicle = function() {
        if (window.bngApi && typeof window.bngApi.engineLua === 'function') {
          window.bngApi.engineLua('finishVehicleEditing()');
          $scope.$applyAsync(function() {
            $scope.isEditingVehicle = false;
            updateButtonsVisibility();
          });
        }
      };

      $scope.activatePowerup = function(type) {
        if (!window.bngApi || typeof window.bngApi.engineLua !== 'function') return;
        if (type === 'spike_strip') {
          window.bngApi.engineLua('activateSpikeStrip()');
        } else if (type === 'banana') {
          window.bngApi.engineLua('activateBanana()');
        } else if (type === 'cannon') {
          window.bngApi.engineLua('activateCannon()');
        }
      };

      $scope.nearbyHasSpikes = function() {
        for (var pid in $scope.copInventories) {
          if ($scope.copInventories[pid] &&
              ($scope.copInventories[pid].spike_strip || 0) > 0) return true;
        }
        return false;
      };

      $scope.nearbyHasBanana = function() {
        for (var pid in $scope.copInventories) {
          if ($scope.copInventories[pid] &&
              ($scope.copInventories[pid].banana || 0) > 0) return true;
        }
        return false;
      };

      $scope.nearbyHasCannon = function() {
        for (var pid in $scope.copInventories) {
          if ($scope.copInventories[pid] &&
              ($scope.copInventories[pid].cannon || 0) > 0) return true;
        }
        return false;
      };

      // -------------------------------------------------------------------------
      // Rank panel
      // -------------------------------------------------------------------------

      $scope.openRankPanel = function() {
        $scope.$applyAsync(function() { $scope.showRankPanel = true; });
      };

      $scope.closeRankPanel = function($event) {
        if ($event.target === $event.currentTarget) {
          $scope.$applyAsync(function() { $scope.showRankPanel = false; });
        }
      };

      $scope.closeRankPanelBtn = function() {
        $scope.$applyAsync(function() { $scope.showRankPanel = false; });
      };

      $scope.closeRankUpBtn = function() {
        if (_rankUpAuto) $timeout.cancel(_rankUpAuto);
        stopConfetti();
        $scope.$applyAsync(function() { $scope.showRankUpCelebration = false; });
      };

      $scope.closeTransferWindowBtn = function() {
        $scope.$applyAsync(function() { $scope.showTransferWindow = false; });
      };

      // -------------------------------------------------------------------------
      // Task list
      // -------------------------------------------------------------------------

      function roleClassFor(role) {
        if (role === 'police')   return 'role-police';
        if (role === 'civilian') return 'role-wanted';
        return 'role-global';
      }

      function fmtDuration(sec) {
        sec = Math.max(0, Math.floor(sec || 0));
        var h = Math.floor(sec / 3600);
        var m = Math.floor((sec % 3600) / 60);
        return h + ':' + (m < 10 ? '0' : '') + m;
      }
      function fmtCount(n) {
        n = Math.floor(n || 0);
        try { return n.toLocaleString('en-US'); } catch (e) { return '' + n; }
      }
      function isTimeStat(stat) { return /seconds|playtime/i.test(stat || ''); }

      function recomputeTasks() {
        var ms = ($scope.rankData && $scope.rankData.milestones) || [];
        var groups = { available: [], done: [], locked: [] };
        for (var i = 0; i < ms.length; i++) {
          var m         = ms[i];
          var threshold = m.threshold || 0;
          var value     = m.value || 0;
          var capped    = value > threshold ? threshold : value;
          var item = {
            id:        m.id,
            name_key:  m.name_key,
            role:      m.role,
            roleClass: roleClassFor(m.role),
            threshold: threshold,
            value:     value,
            dispValue: capped,
            pct:       threshold > 0 ? Math.floor((capped / threshold) * 100) : 0,
            reward:    m.points || m.base_points || 0,
            progText:  isTimeStat(m.stat) ? fmtDuration(capped)    : fmtCount(capped),
            threshText:isTimeStat(m.stat) ? fmtDuration(threshold) : fmtCount(threshold)
          };
          if (m.done)        groups.done.push(item);
          else if (m.locked) groups.locked.push(item);
          else               groups.available.push(item);
        }
        $scope.taskGroups = groups;
      }

      $scope.getWantedTooltip = function() {
        return $scope.wantedEnabled ? $scope.t('tooltip_wanted_disable') : $scope.t('tooltip_wanted_enable');
      };

      // -------------------------------------------------------------------------
      // Tooltip row activation
      // -------------------------------------------------------------------------

      $scope.tooltipRow1Active = false;
      $scope.tooltipRow2Active = false;
      $scope.tooltipRowActive  = false;

      $scope.activateTooltipRow1   = function() { $scope.$applyAsync(function() { $scope.tooltipRow1Active = true;  }); };
      $scope.deactivateTooltipRow1 = function() { $scope.$applyAsync(function() { $scope.tooltipRow1Active = false; }); };
      $scope.activateTooltipRow2   = function() { $scope.$applyAsync(function() { $scope.tooltipRow2Active = true;  }); };
      $scope.deactivateTooltipRow2 = function() { $scope.$applyAsync(function() { $scope.tooltipRow2Active = false; }); };
      $scope.activateTooltipRow    = function() { $scope.$applyAsync(function() { $scope.tooltipRowActive  = true;  }); };
      $scope.deactivateTooltipRow  = function() { $scope.$applyAsync(function() { $scope.tooltipRowActive  = false; }); };

      // -------------------------------------------------------------------------
      // Rank up 
      // -------------------------------------------------------------------------

      var _notifSeq = 0;

      var _lastNotifKey = null;
      var _lastNotifTs  = 0;
      var NOTIF_DEDUPE_MS = 400;

      function showPointsNotification(data) {
        if (!data || !data.points || data.points <= 0) return;

        var _dedupeKey = Math.round(data.points) + '|' +
                         (data.task_name_key || '') + '|' +
                         (data.complete === true ? '1' : '0');
        var _now = (typeof performance !== 'undefined' && performance.now)
                   ? performance.now() : Date.now();
        if (_dedupeKey === _lastNotifKey && (_now - _lastNotifTs) < NOTIF_DEDUPE_MS) {
          return;
        }
        _lastNotifKey = _dedupeKey;
        _lastNotifTs  = _now;

        var notif = {
          id: ++_notifSeq,
          points: Math.round(data.points),
          display: 0,
          task_name_key: data.task_name_key || '',
          complete: data.complete === true,
          glow: true,
          leaving: false
        };

        $scope.$applyAsync(function() {
          $scope.pointsNotifications.push(notif);
          while ($scope.pointsNotifications.length > 5) {
            $scope.pointsNotifications.shift();
          }
          $scope.rankBarGlow = true;
        });

        var startTs = null;
        function tick(ts) {
          if (startTs === null) startTs = ts;
          var t = Math.min(1, (ts - startTs) / COUNTUP_MS);
          var eased = 1 - Math.pow(1 - t, 3);
          notif.display = Math.round(eased * notif.points);
          $scope.$applyAsync();
          if (t < 1) {
            requestAnimationFrame(tick);
          } else {
            notif.display = notif.points;
            $scope.$applyAsync();
          }
        }
        requestAnimationFrame(tick);

        $timeout(function() {
          $scope.$applyAsync(function() { notif.leaving = true; });
        }, COUNTUP_MS + 1100);
        $timeout(function() {
          $scope.$applyAsync(function() {
            var i = $scope.pointsNotifications.indexOf(notif);
            if (i !== -1) $scope.pointsNotifications.splice(i, 1);
            if ($scope.pointsNotifications.length === 0) $scope.rankBarGlow = false;
          });
        }, COUNTUP_MS + 1500);
      }

      var _confettiRAF = null;
      var _rankUpAuto  = null;

      function startConfetti() {
        var canvas = document.getElementById('rankup-confetti');
        if (!canvas) return;
        var ctx = canvas.getContext('2d');
        var W = canvas.width  = canvas.offsetWidth  || 320;
        var H = canvas.height = canvas.offsetHeight || 380;
        var colors = ['#f39c12', '#e67e22', '#27ae60', '#3498db', '#e74c3c', '#ffffff', '#9b59b6'];
        var parts = [];
        for (var i = 0; i < 110; i++) {
          parts.push({
            x: Math.random() * W,
            y: Math.random() * -H,
            r: 3 + Math.random() * 5,
            c: colors[Math.floor(Math.random() * colors.length)],
            vy: 1.4 + Math.random() * 3,
            vx: -1.2 + Math.random() * 2.4,
            rot: Math.random() * Math.PI,
            vr: -0.25 + Math.random() * 0.5,
            rect: Math.random() < 0.55
          });
        }
        function frame() {
          ctx.clearRect(0, 0, W, H);
          for (var i = 0; i < parts.length; i++) {
            var p = parts[i];
            p.y += p.vy; p.x += p.vx; p.rot += p.vr;
            if (p.y > H + 12) { p.y = -12; p.x = Math.random() * W; }
            ctx.save();
            ctx.translate(p.x, p.y);
            ctx.rotate(p.rot);
            ctx.fillStyle = p.c;
            if (p.rect) ctx.fillRect(-p.r, -p.r / 2, p.r * 2, p.r);
            else { ctx.beginPath(); ctx.arc(0, 0, p.r, 0, Math.PI * 2); ctx.fill(); }
            ctx.restore();
          }
          _confettiRAF = requestAnimationFrame(frame);
        }
        frame();
      }

      function stopConfetti() {
        if (_confettiRAF) { cancelAnimationFrame(_confettiRAF); _confettiRAF = null; }
      }

      function showRankUpCelebration(data) {
        $scope.$applyAsync(function() {
          $scope.rankUpData            = data;
          $scope.showRankUpCelebration = true;
        });
        $timeout(function() { startConfetti(); }, 80);
        if (_rankUpAuto) $timeout.cancel(_rankUpAuto);
        _rankUpAuto = $timeout(function() {
          stopConfetti();
          $scope.$applyAsync(function() { $scope.showRankUpCelebration = false; });
        }, 8000);
      }

      // -------------------------------------------------------------------------
      // HUD button visibility logic
      // -------------------------------------------------------------------------

      function updateButtonsVisibility() {
        $scope.$applyAsync(function() {
          $scope.showSyncButton = $scope.isEditingVehicle;
          $scope.showWantedToggle = !$scope.isPolice &&
                                    $scope.wantedTime === 0 &&
                                    !$scope.isEditingVehicle;
        });
      }

      // -------------------------------------------------------------------------
      // Money transfer
      // -------------------------------------------------------------------------

      $scope.openTransferWindow = function($event) {
        if ($event) $event.stopPropagation();
        $scope.$applyAsync(function() {
          $scope.showTransferWindow = true;
          $scope.transferData       = { recipient: '', amount: 0 };
        });
      };

      $scope.closeTransferWindow = function($event) {
        if ($event.target === $event.currentTarget) {
          $scope.$applyAsync(function() { $scope.showTransferWindow = false; });
        }
      };

      $scope.sendMoney = function() {
        var recipient = $scope.transferData.recipient;
        var amount    = $scope.transferData.amount;

        var recipientId    = (typeof recipient === 'number') ? recipient : parseInt(recipient, 10);
        var transferAmount = (typeof amount === 'number')    ? amount    : parseInt(amount, 10);

        if (recipientId === null || isNaN(recipientId) || recipientId < 0) return;
        if (transferAmount === null || isNaN(transferAmount) || transferAmount <= 0) return;

        if (window.bngApi && typeof window.bngApi.engineLua === 'function') {
          var luaCode = 'if type(TriggerServerEvent) == "function" and type(jsonEncode) == "function" then ' +
                        'local payload = jsonEncode({target = "' + recipientId + '", amount = ' + transferAmount + '}); ' +
                        'TriggerServerEvent("ECON_PayTransfer", payload); ' +
                        'end';
          window.bngApi.engineLua(luaCode);
        } else {
          console.error('[EconomyUI] bngApi not available for money transfer');
        }

        $scope.showTransferWindow = false;
      };

      // -------------------------------------------------------------------------
      // AngularJS event listeners
      // -------------------------------------------------------------------------

      $scope.$on('ECON_AuthRequired', function(e, data) {
        if (!data || !data.required) return;
        if (SESSION.authDone) return;
        $scope.$applyAsync(function() {
          $scope.isGuestAccount    = true;
          $scope.authRequired      = true;
          $scope.showWelcomeScreen = true;
          $scope.currentStep       = 0;
          if (savedUsername) { $scope.authData.username = savedUsername; }
        });
      });

      $scope.$on('AIRPOLLUTER_MissionStart', function(e, data) {
        if (!data) return;
        var msg = (data.playerName || '?') + ' ' + $scope.t('airpolluter_alert_body');
        showAPAlert($scope.t('airpolluter_alert_title'), msg, null);
      });

      $scope.$on('AIRPOLLUTER_MissionEnd', function(e, data) {
        if (!data) return;
        if (data.success) {
          showAPAlert('✅ ' + $scope.t('airpolluter_end_title_success'),
                              $scope.t('airpolluter_end_body_success'), true);
        } else {
          showAPAlert('🚨 ' + $scope.t('airpolluter_end_title_fail'),
                              $scope.t('airpolluter_end_body_fail'), false);
        }
      });

      $scope.$on('AIRPOLLUTER_StatusUpdate', function(e, data) {
        if (data) $scope.$applyAsync(function() { $scope.apStatusPanel = data; });
      });

      $scope.$on('POWERUP_InventoryUpdate', function(e, data) {
        if (data) $scope.$applyAsync(function() { $scope.powerupInventory = data; });
      });

      $scope.$on('POWERUP_CopInventories', function(e, data) {
        if (data) $scope.$applyAsync(function() { $scope.copInventories = data; });
      });

      $scope.$on('EconomyUI_Update', function(e, data) {
        if (data && data.money !== undefined) {
          $scope.$applyAsync(function() { $scope.balance = data.money; });
        }
      });

      function handleWantedPayload(payload) {
        var wantedSeconds = null;
        if (payload && typeof payload === 'object' && payload.wantedTime != null) {
          wantedSeconds = Number(payload.wantedTime);
        }
        if (wantedSeconds != null && !isNaN(wantedSeconds)) {
          wantedSeconds = Math.max(0, Math.floor(wantedSeconds));
          $scope.$applyAsync(function() {
            $scope.wantedTime = wantedSeconds;
            updateButtonsVisibility();
          });
        }
      }
      $scope.$on('EconomyUI_WantedUpdate', function(e, p) {
        handleWantedPayload(p);
        var wt = (p && p.wantedTime != null) ? Math.max(0, Math.floor(Number(p.wantedTime))) : 0;
        if (prevWantedForNav === 0 && wt > 0 && navPreference && !$scope.navEnabled) {
          if (window.bngApi && typeof window.bngApi.engineLua === 'function') {
            window.bngApi.engineLua('toggleMarkerNavigation()');
          }
        }
        prevWantedForNav = wt;
      });

      $scope.$on('EconomyUI_PoliceProximity', function(e, p) {
        if (p && typeof p === 'object' && p.policeNearby !== undefined) {
          $scope.$applyAsync(function() { $scope.policeNearby = p.policeNearby === true; });
        }
      });

      function makeCuffsTo(ac, dest, when) {
        [0, 0.18].forEach(function(offset) {
          var buf = ac.createBuffer(1, Math.floor(ac.sampleRate * 0.08), ac.sampleRate);
          var d   = buf.getChannelData(0);
          for (var i = 0; i < d.length; i++)
            d[i] = (Math.random() * 2 - 1) * Math.exp(-i / (d.length * 0.15));
          var src = ac.createBufferSource();
          src.buffer = buf;
          var hp = ac.createBiquadFilter();
          hp.type = 'highpass'; hp.frequency.value = 3000;
          var g = ac.createGain(); g.gain.value = 1.8;
          src.connect(hp); hp.connect(g); g.connect(dest);
          src.start(when + offset);
        });
      }

      function buildOption3(ac, dest) {
        var buf = ac.createBuffer(1, ac.sampleRate * 0.15, ac.sampleRate);
        var d   = buf.getChannelData(0);
        for (var i = 0; i < d.length; i++)
          d[i] = (Math.random() * 2 - 1) *
                 (i < d.length * 0.7 ? 1 : Math.exp(-(i - d.length * 0.7) / (d.length * 0.1)));
        var src = ac.createBufferSource();
        src.buffer = buf;
        var bp = ac.createBiquadFilter();
        bp.type = 'bandpass'; bp.frequency.value = 1400; bp.Q.value = 0.6;
        var rg = ac.createGain(); rg.gain.value = 2.5;
        src.connect(bp); bp.connect(rg); rg.connect(dest);
        src.start(ac.currentTime + 0.2);
        var osc = ac.createOscillator();
        var og  = ac.createGain();
        osc.frequency.value = 1050;
        og.gain.setValueAtTime(0,    ac.currentTime + 0.45);
        og.gain.linearRampToValueAtTime(0.35, ac.currentTime + 0.48);
        og.gain.linearRampToValueAtTime(0,    ac.currentTime + 0.62);
        osc.connect(og); og.connect(dest);
        osc.start(ac.currentTime + 0.4); osc.stop(ac.currentTime + 0.65);
        makeCuffsTo(ac, dest, ac.currentTime + 6.8);
      }

      var _arrestAc      = null;
      var _arrestCleanup = null;

      function startArrestSound() {
        if (_arrestAc) return;
        try {
          _arrestAc = new (window.AudioContext || window.webkitAudioContext)();
          buildOption3(_arrestAc, _arrestAc.destination);
          _arrestCleanup = $timeout(stopArrestSound, 7500);
        } catch(e) {
          console.warn('[EconomyUI] Arrest sound failed:', e);
        }
      }

      function stopArrestSound() {
        if (_arrestCleanup) { $timeout.cancel(_arrestCleanup); _arrestCleanup = null; }
        if (_arrestAc)      { try { _arrestAc.close(); } catch(e) {} _arrestAc = null; }
      }

      function syncBustPct() {
        var row = document.querySelector('.bust-progress-row');
        if (row) row.style.setProperty('--bust-pct', ($scope.bustProgress.percent || 0) + '%');
      }
      $scope.$on('EconomyUI_BustProgress', function(e, p) {
        if (p && typeof p === 'object') {
          var wasActive = $scope.bustProgress.active;
          $scope.$applyAsync(function() {
            $scope.bustProgress = { active: p.active === true, percent: Number(p.bustProgress) || 0 };
          });
          $timeout(syncBustPct, 0);
          if (p.active === true && !wasActive) startArrestSound();
          else if (!p.active && wasActive)     stopArrestSound();
        }
      });

      $scope.$on('EconomyUI_RepairIcons', function(e, p) {
        if (p && typeof p === 'object' && p.repairIcons !== undefined) {
          $scope.$applyAsync(function() {
            $scope.repairIcons = Math.max(0, Number(p.repairIcons) || 0);
            if (p.maxRepairs !== undefined) $scope.maxRepairs = Number(p.maxRepairs) || 2;
            updateButtonsVisibility();
          });
        }
      });

      $scope.$on('PIT_DisplayNames', function(e, data) {
        if (data) { window.pitDisplayNames = data; }
      });

      $scope.$on('ECON_AuthResult', function(e, data) {
        if (!data) return;
        $scope.$applyAsync(function() {
          $scope.authLoading = false;
          if (data.ok) {
            SESSION.authDone    = true;
            $scope.authRequired = false;
            if (data.migration_token) {
              $scope.migrationToken = data.migration_token;
              try { localStorage.setItem('pit_migration_token', data.migration_token); } catch(e) {}
            }
            if ($scope.currentStep === 0) { $scope.currentStep = 1; }
            if (data.money !== undefined) { $scope.balance = data.money; }
          } else {
            $scope.authError  = $scope.t(data.error_key || 'auth_failed');
            savedPasswordHash = null;
            try { localStorage.removeItem('pit_password_hash'); } catch(e) {}
          }
        });
      });

      $scope.$on('POLICE_RoleUpdate', function(e, data) {
        if (data && data.isPolice !== undefined) {
          $scope.$applyAsync(function() {
            var wasPolice = prevPoliceForNav;
            $scope.isPolice = data.isPolice;
            updateButtonsVisibility();
            if (!wasPolice && data.isPolice && navPreference && !$scope.navEnabled) {
              if (window.bngApi && typeof window.bngApi.engineLua === 'function') {
                window.bngApi.engineLua('toggleMarkerNavigation()');
              }
            }
            prevPoliceForNav = data.isPolice;
          });
        }
      });

      $scope.$on('EconomyUI_WantedEnabledUpdate', function(e, data) {
        if (data && data.wantedEnabled !== undefined) {
          $scope.$applyAsync(function() { $scope.wantedEnabled = data.wantedEnabled; });
        }
      });

      $scope.$on('ECON_EditingModeUpdate', function(e, data) {
        if (data && data.isEditing !== undefined) {
          $scope.$applyAsync(function() {
            $scope.isEditingVehicle = data.isEditing;
            updateButtonsVisibility();
          });
        }
      });

      $scope.$on('ECON_NavUpdate', function(e, data) {
        if (data && data.navEnabled !== undefined) {
          $scope.$applyAsync(function() { $scope.navEnabled = data.navEnabled; });
        }
      });

      $scope.$on('EconomyUI_TranslationsUpdate', function(e, data) {
        if (data && data.translations) {
          serverTranslations   = data.translations;
          SESSION.translations = data.translations;
          if (data.lang) {
            $scope.$applyAsync(function() {
              $scope.selectedLang = data.lang;
              updateDirection(data.lang);
              try {
                localStorage.setItem('economyUI_language', data.lang);
              } catch(e) {
                console.warn('[EconomyUI] Could not save language from server:', e);
              }
            });
          }
          if (data.auth_required && !SESSION.authDone) {
            $scope.$applyAsync(function() {
              $scope.authRequired      = true;
              $scope.showWelcomeScreen = true;
              $scope.currentStep       = 0;
              $scope.hasSavedPassword  = !!(savedPasswordHash);
              if (savedUsername) { $scope.authData.username = savedUsername; }
            });
          }
        }
      });

      function syncRankPct() {
        var track = document.querySelector('.rank-bar-track');
        if (track) track.style.setProperty('--rank-pct', ($scope.rankData.percent || 0) + '%');
      }
      $scope.$on('EconomyUI_RankUpdate', function(e, data) {
        if (data) {
          $scope.$applyAsync(function() {
            $scope.rankData = {
              rank:             data.rank             || 1,
              rank_name_key:    data.rank_name_key    || 'rank_1_name',
              prefix:           data.prefix           || '[I]',
              percent:          data.percent          || 0,
              completed:        data.completed        || 0,
              total:            data.total            || 0,
              tasks:            data.tasks            || [],
              milestones:       data.milestones       || [],
              max_rank:         data.max_rank         || 20,
              total_points:     data.total_points     || 0,
              pts_to_next:      data.pts_to_next      || 0,
              next_prefix:      data.next_prefix      || null,
              milestones_done:  data.milestones_done  || 0,
              milestones_total: data.milestones_total || 0,
            };
            recomputeTasks();
          });
          $timeout(syncRankPct, 0);
        }
      });
      $timeout(syncRankPct, 0);

      $scope.$on('EconomyUI_TaskProgress', function(e, data) { if (data) showPointsNotification(data); });
      $scope.$on('EconomyUI_RankUp',       function(e, data) { if (data) showRankUpCelebration(data); });
      $scope.$on('EconomyUI_ShowRankPanel', function() {
        $scope.$applyAsync(function() { $scope.showRankPanel = true; });
      });

      // -------------------------------------------------------------------------
      // Tooltip DOM binding
      // -------------------------------------------------------------------------

      $timeout(function() {
        var tooltipButtons = document.querySelectorAll('.tooltip-bottom');
        tooltipButtons.forEach(function(button) {
          button.addEventListener('mouseenter', function() {
            var hudRow = this.closest('.hud-row');
            if (hudRow) hudRow.classList.add('tooltip-active');
          });
          button.addEventListener('mouseleave', function() {
            var hudRow = this.closest('.hud-row');
            if (hudRow) hudRow.classList.remove('tooltip-active');
          });
        });
      }, 500);

      // -------------------------------------------------------------------------
      // Initialization
      // -------------------------------------------------------------------------

      $scope.$on('$destroy', function() {
        if (_arrestAc) { try { _arrestAc.close(); } catch(e) {} _arrestAc = null; }
      });

      $timeout(function() {
        updateButtonsVisibility();
      }, 100);

      if (window.bngApi && typeof window.bngApi.engineLua === 'function') {
        if (savedLang && savedLang !== 'en') {
          window.bngApi.engineLua("setPlayerLanguage('" + savedLang + "')");
        }
        window.bngApi.engineLua(
          'TriggerServerEvent("ECON_RequestTranslations", ' +
          'tostring(settings.getValue("userLanguage") or ""))'
        );
      }

    }
  };
});