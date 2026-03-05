// =============================================================================
// PIT Economy System — Police Wanted List Controller
// Version: 1.0
// License: AGPL-3.0 — https://www.gnu.org/licenses/agpl-3.0.html
// =============================================================================

angular.module('beamng.apps')
.directive('policeWantedList', function() {
  return {
    restrict: 'E',
    templateUrl: '/ui/modules/apps/PoliceWantedList/app.html',
    replace: true,
    controller: function($scope) {

      // -------------------------------------------------------------------------
      // Initial state
      // -------------------------------------------------------------------------

      $scope.wantedPlayers = [];
      $scope.isPolice      = false;

      var serverTranslations = {};

      var fallbackText = {
        "wanted_list_title":    "Wanted List",
        "violation_speeding":   "Speeding",
        "violation_zigzag":     "Zigzag",
        "violation_both":       "Combo",
        "no_wanted_players":    "No wanted players",
        "time_label":           "Time",
        "type_label":           "Type",
        "repairs_label":        "Repairs",
        "violation_airpolluter": "Air Polluter",
        "violation_unknown":    "?"
      };

      // -------------------------------------------------------------------------
      // Utilities
      // -------------------------------------------------------------------------

      $scope.t = function(key, vars) {
        var text = serverTranslations[key] || fallbackText[key] || key;
        if (vars) {
          for (var k in vars) {
            text = text.replace('${' + k + '}', vars[k]);
          }
        }
        return text;
      };

      $scope.formatTime = function(totalSeconds) {
        if (totalSeconds <= 0) return '00:00';
        var minutes = Math.floor(totalSeconds / 60);
        var seconds = totalSeconds % 60;
        return (minutes < 10 ? '0' : '') + minutes + ':' + (seconds < 10 ? '0' : '') + seconds;
      };

      function updateDirection(lang) {
        var container = document.getElementById('police-wanted-container');
        if (container) {
          container.dir = (lang === 'he' || lang === 'ar') ? 'rtl' : 'ltr';
        }
      }

      function normalizeWantedList(payload) {
        if (!payload) return null;
        var list = payload.wanted_players;
        if (list && typeof list === 'object' && !Array.isArray(list)) {
          var arr = [];
          for (var key in list) {
            if (list.hasOwnProperty(key)) arr.push(list[key]);
          }
          return arr;
        }
        return Array.isArray(list) ? list : null;
      }

      // -------------------------------------------------------------------------
      // AngularJS event listeners
      // -------------------------------------------------------------------------

      $scope.$on('POLICE_WantedListUpdate', function(e, data) {
        if (!data || typeof data !== 'object') return;
        var list = normalizeWantedList(data);
        $scope.$applyAsync(function() {
          $scope.wantedPlayers = list || [];
          if (list) $scope.isPolice = true;
        });
      });

      $scope.$on('POLICE_RoleUpdate', function(e, data) {
        if (data && data.isPolice !== undefined) {
          $scope.$applyAsync(function() {
            $scope.isPolice = data.isPolice;
            if (!$scope.isPolice) $scope.wantedPlayers = [];
          });
        }
      });

      $scope.$on('POLICE_TranslationsUpdate', function(e, data) {
        if (data && data.translations) {
          serverTranslations = data.translations;
          if (data.lang) {
            $scope.$applyAsync(function() { updateDirection(data.lang); });
          }
        }
      });

      // -------------------------------------------------------------------------
      // guihooks listeners (direct BeamNG bridge)
      // -------------------------------------------------------------------------

      try {
        if (typeof guihooks !== "undefined" && guihooks.on) {
          guihooks.on("POLICE_WantedListUpdate", function(payload) {
            if (!payload) return;
            var list = normalizeWantedList(payload);
            $scope.$applyAsync(function() {
              $scope.wantedPlayers = list || [];
              if (list) $scope.isPolice = true;
            });
          });

          guihooks.on("POLICE_RoleUpdate", function(data) {
            if (data && data.isPolice !== undefined) {
              $scope.$applyAsync(function() {
                $scope.isPolice = data.isPolice;
                if (!$scope.isPolice) $scope.wantedPlayers = [];
              });
            }
          });

          guihooks.on("POLICE_TranslationsUpdate", function(data) {
            if (data && data.translations) {
              serverTranslations = data.translations;
              $scope.$applyAsync(function() {
                if (data.lang) updateDirection(data.lang);
              });
            }
          });
        }
      } catch(err) {
        console.error('[PoliceWantedList] guihooks registration error:', err);
      }

    }
  };
});
