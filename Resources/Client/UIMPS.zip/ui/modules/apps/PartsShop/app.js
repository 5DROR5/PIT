// =============================================================================
// PartsShop - AngularJS Controller
// Part of: PIT Economy System
// License: AGPL-3.0 (https://www.gnu.org/licenses/agpl-3.0.html)
// =============================================================================

angular.module('beamng.apps')
.directive('appPartsshop', [function() {
  return {
    replace: true,
    templateUrl: '/ui/modules/apps/PartsShop/app.html',
    restrict: 'EA',
    scope: true,
    controller: ['$scope', function($scope) {

      // =======================================================================
      // STATE
      // =======================================================================
      $scope.visible     = false;
      $scope.uiType      = null;
      $scope.partsList   = [];
      $scope.totalCost   = 0;
      $scope.playerMoney = 0;
      $scope.vehicleId   = null;
      $scope.bannedParts = [];

      $scope.translations = {
        parts_required_title:   'Parts Required for Purchase',
        total_cost:             'Total Cost',
        current_balance:        'Current Balance',
        missing_amount:         'Missing',
        confirm_purchase:       'Are you sure you want to buy?',
        btn_confirm:            'Confirm',
        btn_cancel:             'Cancel',
        btn_close:              'Close',
        vehicle_has_banned_parts: 'Vehicle Contains Banned Parts',
        cannot_use_vehicle:     'Cannot use this vehicle',
        banned_parts_list:      'Banned Parts:'
      };

      // =======================================================================
      // EVENT HANDLERS
      // =======================================================================
      $scope.$on('PartsShop_ShowPurchase', function(event, data) {
        if (!data || !data.parts) {
          console.error('[PartsShop-UI] Invalid purchase data');
          return;
        }
        $scope.$applyAsync(function() {
          $scope.uiType      = 'purchase';
          $scope.partsList   = data.parts   || [];
          $scope.totalCost   = data.totalCost   || 0;
          $scope.playerMoney = data.playerMoney || 0;
          $scope.vehicleId   = data.vehicleId;
          $scope.visible     = true;
        });
      });

      $scope.$on('PartsShop_ShowBanned', function(event, data) {
        if (!data || !data.parts) {
          console.error('[PartsShop-UI] Invalid banned data');
          return;
        }
        $scope.$applyAsync(function() {
          $scope.uiType      = 'banned';
          $scope.bannedParts = data.parts || [];
          $scope.visible     = true;
        });
      });

      $scope.$on('PartsShop_LanguageUpdate', function(event, data) {
        if (!data || !data.translations) {
          console.error('[PartsShop-UI] Invalid language data');
          return;
        }
        $scope.$applyAsync(function() {
          $scope.translations = data.translations;
        });
      });

      // =======================================================================
      // UI ACTIONS
      // =======================================================================
      $scope.confirm = function() {
        var purchaseData = {
          parts:     $scope.partsList,
          totalCost: $scope.totalCost,
          vehicleId: $scope.vehicleId
        };
        if (typeof bngApi !== 'undefined' && bngApi.engineLua) {
          var dataJson = JSON.stringify(purchaseData);
          bngApi.engineLua('confirmPurchase(\'' + dataJson.replace(/'/g, "\\'") + '\')');
        } else {
          console.error('[PartsShop-UI] bngApi not available');
        }
        $scope.visible = false;
      };

      $scope.cancel = function() {
        if (typeof bngApi !== 'undefined' && bngApi.engineLua) {
          bngApi.engineLua('cancelPurchase()');
        }
        $scope.visible = false;
      };

      $scope.closeBanned = function() {
        if (typeof bngApi !== 'undefined' && bngApi.engineLua) {
          bngApi.engineLua('closeBannedUI()');
        }
        $scope.visible = false;
      };

      // =======================================================================
      // GUIHOOKS BRIDGE
      // =======================================================================
      if (typeof guihooks !== 'undefined') {
        guihooks.on('PartsShop_ShowPurchase',   function(data) { $scope.$broadcast('PartsShop_ShowPurchase',   data); });
        guihooks.on('PartsShop_ShowBanned',     function(data) { $scope.$broadcast('PartsShop_ShowBanned',     data); });
        guihooks.on('PartsShop_LanguageUpdate', function(data) { $scope.$broadcast('PartsShop_LanguageUpdate', data); });
      }
    }]
  };
}]);
