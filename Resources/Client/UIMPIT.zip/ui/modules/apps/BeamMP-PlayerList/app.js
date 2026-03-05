// Copyright (C) 2024 BeamMP Ltd., BeamMP team and contributors.
// Licensed under AGPL-3.0 (or later), see <https://www.gnu.org/licenses/>.
// SPDX-License-Identifier: AGPL-3.0-or-later
// Modified for PIT Economy System — added role, rank, and wanted player display.

var connected = false;
var players = [];
let pingList = [];
var nickname = "";
var app = angular.module('beamng.apps');

app.directive('multiplayerplayerlist', [function () {
	return {
		templateUrl: '/ui/modules/apps/BeamMP-PlayerList/app.html',
		replace: true,
		restrict: 'EA',
		scope: true,
		controllerAs: 'ctrl'
	}
}]);

app.controller("PlayerList", ['$scope', '$filter', 'Settings', function ($scope, $filter, Settings) {
	$scope.warnVis = false;
	$scope.timer = null;
	$scope.showPlayerIDs = true;
	$scope.playerlistLeftclick = 0;

	// --- PIT Economy System additions ---
	$scope.customPlayerData = {};
	$scope.hasCustomData = false;
	$scope.showPlayerRoles = true;
	$scope.showPlayerRanks = true;
	// ------------------------------------

	const applyPlayerListStyle = function(useNewDesign) {
		const stylesheet = document.getElementById('playerlist-style');
		if (!stylesheet) return;

		let newStylePath;
		if (useNewDesign) {
			newStylePath = '/ui/modules/apps/BeamMP-PlayerList/redesign.css';
		} else {
			newStylePath = '/ui/modules/apps/BeamMP-PlayerList/app.css';
		}
		
		if (stylesheet.getAttribute('href') !== newStylePath) {
			stylesheet.setAttribute('href', newStylePath);
		}
	};

	$scope.init = function() {
		setPLDirection(localStorage.getItem('plHorizontal'));
		setPLDirection(localStorage.getItem('plVertical'));
		if (localStorage.getItem('plShown') == 1) showList();
		bngApi.engineLua("guihooks.trigger('updateCustomButtons', UI.getCustomButtonNames())");
		
		applyPlayerListStyle(Settings.values.useUiAppRedesign);
		bngApi.engineLua('settings.getValue("showPlayerIDs")', (data) => {
			$scope.showPlayerIDs = data;
		});
		bngApi.engineLua('settings.getValue("playerlistLeftclick")', (data) => {
			$scope.playerlistLeftclick = data;
		});

		bngApi.engineLua('settings.getValue("showPlayerRoles")', (data) => {
			$scope.showPlayerRoles = data !== false;
		});
		bngApi.engineLua('settings.getValue("showPlayerRanks")', (data) => {
			$scope.showPlayerRanks = data !== false;
		});
	};

	$scope.$on('SettingsChanged', function (event, data) {
		Settings.values = data.values;
		applyPlayerListStyle(Settings.values.useUiAppRedesign);
		$scope.showPlayerIDs = Settings.values.showPlayerIDs;
		$scope.playerlistLeftclick = Settings.values.playerlistLeftclick;
		
		$scope.showPlayerRoles = Settings.values.showPlayerRoles !== false;
		$scope.showPlayerRanks = Settings.values.showPlayerRanks !== false;
	});

	// --- PIT Economy System addition ---
	$scope.$on('PlayerList_CustomData', function(event, data) {
		try {
			if (data && data.players) {
				$scope.customPlayerData = {};
				$scope.hasCustomData = data.players.length > 0;
				
				data.players.forEach(player => {
					if (player.id !== undefined) {
						$scope.customPlayerData[player.id] = {
							role: player.role,
							rank: player.rank,
							rank_prefix: player.rank_prefix,
							is_wanted: player.is_wanted
						};
					}
				});
				
				if (players && players.length > 0) {
					$scope.$broadcast('playerList', JSON.stringify(players));
				}
			}
		} catch (e) {
			console.error("PlayerList: Failed to process custom data:", e);
		}
	});

	// --- PIT Economy System addition ---
	function getRoleIcon(role) {
		connected = false;
		players = [];
		$scope.customPlayerData = {};
		$scope.hasCustomData = false;
		$scope.init();
	};

	$scope.select = function() {
		bngApi.engineLua('setCEFFocus(true)');
	};

	$scope.disconnect = function() {
		players = [];
		connected = false;
		$scope.customPlayerData = {};
		$scope.hasCustomData = false;
	};

	function setPLDirection(direction) {
		const mainContainer = document.getElementById("main-container");
		const plistContainer = document.getElementById("plist-container");
		const showButton = document.getElementById("show-button");
		if (direction == "left") {
			mainContainer.style.flexDirection = "row-reverse";
			localStorage.setItem('plHorizontal', "left");
		}
		else if (direction == "right") {
			mainContainer.style.flexDirection = "row";
			localStorage.setItem('plHorizontal', "right");
		}
		else if (direction == "top") {
			plistContainer.style.marginTop = "0";
			showButton.style.marginTop = "0";
			localStorage.setItem('plVertical', "top");
		}
		else if (direction == "bottom") {
			plistContainer.style.marginTop = "auto";
			showButton.style.marginTop = "auto";
			localStorage.setItem('plVertical', "bottom");
		}
	}

	$scope.plSwapHorizontal = function() {
		const plHorizontal = localStorage.getItem('plHorizontal');
		if (plHorizontal != "left") setPLDirection("left");
		else setPLDirection("right");
	}

	$scope.plSwapVertical = function() {
		const plVertical = localStorage.getItem('plVertical');
		if (plVertical != "bottom") setPLDirection("bottom");
		else setPLDirection("top");
	}

	$scope.$on('playerPings', function(event, data) {
		pingList = JSON.parse(data);
		for(let i = 0; i < pingList.length; i++) {
			pingList[i] = pingList[i]-16;
			if (pingList[i] > 999) pingList[i] = 999;
		}
	});

	var customButtons = [];

	$scope.$on('updateCustomButtons', function(event, data) {
		if (Array.isArray(data)) {
			customButtons = data;
		}
	});

	function getRoleIcon(role) {
		const icons = {
			"police": "👮",
			"civilian": "🚗"
		};
		return icons[role] || "👤";
	}

	$scope.$on('playerList', function(event, data) {
		let playersList = document.getElementById("players-table");
		let parsedList = JSON.parse(data);
		
		if(players != null && playersList != null){
			clearPlayerList();
	
			parsedList.sort(function(a, b) {
				var keyA = a.id, keyB = b.id;
				if (keyA < keyB) return -1;
				if (keyA > keyB) return 1;
				return 0;
			});

			for (let i = 0; i < parsedList.length; i++) {
				var row = playersList.insertRow(playersList.rows.length);
				row.setAttribute("id", "playerlist-row-" + parsedList[i].id);

				let cellIndex = 0;
				let customData = $scope.customPlayerData[parsedList[i].id];

				if ($scope.showPlayerIDs) {
					var idCell = row.insertCell(cellIndex++);
					idCell.textContent = parsedList[i].id;
					idCell.setAttribute("onclick", "restorePlayerVehicle('"+parsedList[i].name+"')");
					idCell.setAttribute("class", "player-id");
				}

				if ($scope.hasCustomData && $scope.showPlayerRoles) {
					let roleCell = row.insertCell(cellIndex++);
					if (customData && customData.role) {
						if (customData.is_wanted) {
							roleCell.innerHTML = '<span class="player-role-wanted">⭐</span>';
							roleCell.setAttribute("title", "WANTED - " + customData.role);
						} else {
							roleCell.textContent = getRoleIcon(customData.role);
							roleCell.setAttribute("title", customData.role);
						}
						roleCell.setAttribute("class", "playerslist-col-role");
					} else {
						roleCell.textContent = "";
						roleCell.setAttribute("class", "playerslist-col-role");
					}
				}

				if ($scope.hasCustomData && $scope.showPlayerRanks) {
					let rankCell = row.insertCell(cellIndex++);
					if (customData && customData.rank_prefix) {
						rankCell.textContent = customData.rank_prefix;
						rankCell.setAttribute("class", "playerslist-col-rank player-rank rank-" + (customData.rank || 1));
					} else {
						rankCell.textContent = "";
						rankCell.setAttribute("class", "playerslist-col-rank");
					}
				}

				var nameCell = row.insertCell(cellIndex++);
				nameCell.textContent = parsedList[i].formatted_name;
				nameCell.setAttribute("class", "player-button");

				if (customData && customData.role) {
					nameCell.classList.add("player-role-" + customData.role);
				}

				if (customData && customData.is_wanted) {
					nameCell.classList.add("player-role-wanted");
				}

				switch ($scope.playerlistLeftclick) {
					case 0:
						nameCell.setAttribute("onclick", "applyQueuesForPlayer('"+parsedList[i].id+"')");
						break;
					case 1:
						nameCell.setAttribute("onclick", "showPlayerInfo('"+parsedList[i].name+"')");
						break;
					case 2:
						nameCell.setAttribute("onclick", "viewPlayer('"+parsedList[i].name+"')");
						break;
					case 3:
						nameCell.setAttribute("onclick", "bngApi.engineLua(`for id, veh in pairs(MPVehicleGE.getVehicles()) do if veh.ownerName == require('mime').unb64('` + btoa(parsedList[i].name) + `') then be:getObjectByID(veh.gameVehicleID):delete() end end`)");
						break;
					case 4:
						nameCell.setAttribute("onclick", "restorePlayerVehicle('"+parsedList[i].name+"')");
						break;
					case 5:
						nameCell.setAttribute("onclick", "bngApi.engineLua(`setClipboard(require('mime').unb64('` + btoa(parsedList[i].name) + `'))`)");
						break;
				}

				nameCell.addEventListener("contextmenu", function(e) {
					e.preventDefault();
				
					const playerlistContextmenu = document.getElementById("playerlist-contextmenu");
					playerlistContextmenu.style.display = "block";
					playerlistContextmenu.style.top = e.clientY + "px";
					playerlistContextmenu.style.left = e.clientX + "px";
					playerlistContextmenu.style.position = "fixed";

					playerlistContextmenu.onmouseleave = function () {
						playerlistContextmenu.style.display = "none";
					};

					document.getElementById("pl-context-CopyNameButton").onclick = function() {
						bngApi.engineLua(`setClipboard(require("mime").unb64('` + btoa(parsedList[i].name) + `'))`);
						playerlistContextmenu.style.display = "none";
					}

					document.getElementById("pl-context-DeleteAllButton").onclick = function() {
						bngApi.engineLua(`for id, veh in pairs(MPVehicleGE.getVehicles()) do if veh.ownerName == require("mime").unb64('` + btoa(parsedList[i].name) + `') then be:getObjectByID(veh.gameVehicleID):delete() end end`);
						playerlistContextmenu.style.display = "none";
					}

					document.getElementById("pl-context-QueueEventsButton").onclick = function() {
						applyQueuesForPlayer(parsedList[i].id);
						playerlistContextmenu.style.display = "none";
					}

					document.getElementById("pl-context-SwitchCameraButton").onclick = function() {
						showPlayerInfo(parsedList[i].name);
						playerlistContextmenu.style.display = "none";
					}

					document.getElementById("pl-context-OpenProfileButton").onclick = function() {
						viewPlayer(parsedList[i].name);
						playerlistContextmenu.style.display = "none";
					}

					document.getElementById("pl-context-RestoreVehicles").onclick = function() {
						restorePlayerVehicle(parsedList[i].name);
						playerlistContextmenu.style.display = "none";
					}

					for (let child of playerlistContextmenu.children) {
						if (child.id === "pl-context-custom") {
							playerlistContextmenu.removeChild(child);
						}
					}

					customButtons.forEach(element => {
						let customButton = document.createElement("button");
						customButton.id = "pl-context-custom";
						customButton.textContent = element;
						customButton.onclick = function() {
							bngApi.engineLua(`UI.getCustomPlayerlistButtons()["` + element + `"]("` + parsedList[i].name + `", ` + parsedList[i].id + `)`);
						}
						playerlistContextmenu.appendChild(customButton);
					});
				});

				var pingCell = row.insertCell(cellIndex++);
				var btn = document.createElement("BUTTON");
				var pingText = pingList[parsedList[i].name] || "?";
				btn.appendChild(document.createTextNode(pingText+='ms'));
				btn.setAttribute("onclick","teleportToPlayer('"+parsedList[i]+"')");
				btn.setAttribute("class", "tp-button buttons");
				pingCell.appendChild(btn);

				if ($scope.queuedPlayers[parsedList[i].id] == true) {
					row.style.setProperty('background-color', 'var(--bng-orange-shade1)');
				}
			}
			
			if(document.getElementById("plist-container").style.display == "block")
				document.getElementById("show-button").style.height = playersList.offsetHeight + "px"; 
		}
		players = parsedList;
	});

	$scope.$on('setNickname', function(event, data) {
		nickname = data;
	});

	$scope.queuedPlayers = [];

	$scope.$on('setQueue', function(event, data) {
		$scope.queuedPlayers = [];

		if (!data.queuedPlayers) {
			var rows = document.querySelectorAll('[id^="playerlist-row-"]');
			for (let i = 0; i < rows.length; i++) {
				rows[i].style.setProperty('background-color', 'transparent');
			}
			return;
		}

		for (var key in data.queuedPlayers) {
			$scope.queuedPlayers[key] = data.queuedPlayers[key];
			var playerrow = document.getElementById("playerlist-row-" + key);
			if (playerrow) {
				playerrow.style.setProperty('background-color', data.queuedPlayers[key] ? 'var(--bng-orange-shade1)' : 'transparent');
			}
		}
	});

	bngApi.engineLua('UI.updatePlayersList(); UI.sendQueue()');
}]);

function clearPlayerList() {
	let playersList = document.getElementById("players-table");
	var rowCount = playersList.rows.length - 1;
	for(rowCount; rowCount > 0; rowCount--) playersList.deleteRow(1);
}

function teleportToPlayer(targetPlayerName) {
}

function viewPlayer(targetPlayerName) {
	openExternalLink(`https://forum.beammp.com/u/${targetPlayerName}/summary`);
}

function restorePlayerVehicle(targetPlayerName){
	bngApi.engineLua('MPVehicleGE.restorePlayerVehicle("'+targetPlayerName+'")');
}

function applyQueuesForPlayer(targetPlayerID) {
	bngApi.engineLua('MPVehicleGE.applyPlayerQueues('+targetPlayerID+')');
}

function showPlayerInfo(targetPlayerName) {
	bngApi.engineLua('MPVehicleGE.focusCameraOnPlayer("'+targetPlayerName+'")');
}

function setOfflineInPlayerList() {
	let playersList = document.getElementById("players");
	if(playersList != null) playersList.textContent = "OFFLINE";
}

function showList() {
	var shownText = "&gt;";
	var hiddenText = "&lt;";
	if (localStorage.getItem('plHorizontal') == "right") { shownText = "&lt;"; hiddenText = "&gt;"; }
	var plContainer = document.getElementById("plist-container");
	var btn = document.getElementById("show-button");
	plContainer.style.display = "block";
	btn.innerHTML = shownText;
}

function hideList() {
	var hiddenText = "&lt;";
	if (localStorage.getItem('plHorizontal') == "right") { hiddenText = "&gt;"; }
	var plContainer = document.getElementById("plist-container");
	var btn = document.getElementById("show-button");
	plContainer.style.display = "none";
	btn.innerHTML = hiddenText;
	btn.style.height = "75px";
}

function toggleList() {
	if(localStorage.getItem('plShown') != 1) {
		showList();
		localStorage.setItem('plShown', 1);
	}
	else {
		hideList();
		localStorage.setItem('plShown', 0);
	}
}
