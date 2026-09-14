// Copyright (C) 2024 BeamMP Ltd., BeamMP team and contributors.
// Licensed under AGPL-3.0 (or later), see <https://www.gnu.org/licenses/>.
// SPDX-License-Identifier: AGPL-3.0-or-later

var app = angular.module('beamng.apps');

let lastSentMessage = "";

window.pitDisplayNames = window.pitDisplayNames || {};

let lastMsgId = 0;
let localPlayerNames = new Set();

function playMentionPing() {
	try {
		const ctx = new (window.AudioContext || window.webkitAudioContext)();
		[0, 0.15, 0.30].forEach(function(t) {
			const o = ctx.createOscillator(), g = ctx.createGain();
			o.connect(g); g.connect(ctx.destination);
			o.type = 'sine';
			o.frequency.setValueAtTime(960, ctx.currentTime + t);
			g.gain.setValueAtTime(0.2, ctx.currentTime + t);
			g.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + t + 0.1);
			o.start(ctx.currentTime + t);
			o.stop(ctx.currentTime + t + 0.12);
		});
	} catch(e) {}
}

let newChatMenu = false;
import('/ui/lib/ext/purify.min.js').catch(function (e) {
	console.warn('[CHAT] DOMPurify failed to load, falling back to plain escaping:', e);
});
app.directive('multiplayerchat', [function () {
	return {
		templateUrl: '/ui/modules/apps/BeamMP-Chat/app.html',
		replace: true,
		restrict: 'EA',
		scope: true,
		controllerAs: 'ctrl'
	}
}]); 


app.controller("Chat", ['$scope', 'Settings', function ($scope, Settings) {
	const CHAT_EVENTS = {
		chatMessage:      ['chatMessage',      'onBeamMPChatMessage'],
		clearChatHistory: ['clearChatHistory', 'onBeamMPClearChatHistory']
	};

	function onAny(eventNames, handler) {
		eventNames.forEach(function (eventName) {
			$scope.$on(eventName, handler);
		});
	}

	function parsePayload(data, fallback) {
		if (typeof data !== 'string') {
			return (data === undefined || data === null) ? fallback : data;
		}
		try {
			return JSON.parse(data);
		} catch (e) {
			return fallback;
		}
	}
	const applyChatStyle = function(useNewDesign) {
		const stylesheet = document.getElementById('chat-style');
		const sendButton = document.getElementById('send-button');
		if (!stylesheet) return;
		let newStylePath;
		if (useNewDesign) {
			newStylePath = '/ui/modules/apps/BeamMP-Chat/redesign.css';
			if (sendButton) sendButton.innerHTML = '💬';
		} else {
			newStylePath = '/ui/modules/apps/BeamMP-Chat/app.css';
			if (sendButton) sendButton.innerHTML = 'Send';
		}		
		if (stylesheet.getAttribute('href') !== newStylePath) {
			stylesheet.setAttribute('href', newStylePath);
		}
		scrollToLastMessage();
	};

	$scope.init = function() {
		applyChatStyle(Settings.values.useUiAppRedesign);

		var chatMessages = retrieveChatMessages()
		newChatMenu = Settings.values.enableNewChatMenu;
		var chatinput = document.getElementById("chat-input");
		if (chatinput) {
			chatinput.addEventListener("mouseover", function(){ chatShown = true; showChat(); });
			chatinput.addEventListener("mouseout", function(){ chatShown = false; });
			chatinput.addEventListener('keydown', onKeyDown);
		}

		var chatlist = document.getElementById("chat-list");
		if (chatlist) {
			chatlist.addEventListener("mouseover", function(){ chatShown = true; showChat(); });
			chatlist.addEventListener("mouseout", function(){ chatShown = false; });
		}
		setChatDirection(localStorage.getItem('chatHorizontal'));
		setChatDirection(localStorage.getItem('chatVertical'));

		const chatbox = document.getElementById("chat-window");
		if (newChatMenu) {
			chatbox.style.display = "none";
		} else {
			chatbox.style.display = "flex";
		}

		if (chatMessages) {
			chatMessages.map((v, i) => {
				addMessage(v.message, v.time)
			})
		}

		if (chatlist) {
			setTimeout(() => {
				scrollToLastMessage();
			}, 0)
		}
	};

	$scope.reset = function() {
		$scope.init();
	};

	$scope.select = function() {
		bngApi.engineLua('setCEFFocus(true)');
	};

	function setChatDirection(direction) {
		const chatbox = document.getElementById("chatbox");
		const chatwindow = document.getElementById("chat-window");
		const chatlist = document.getElementById("chat-list");
		if (direction == "left") {
			chatbox.style.flexDirection = "row";
			chatbox.style.marginLeft = "0px";
			chatwindow.style.alignItems = "flex-start";
			localStorage.setItem('chatHorizontal', "left");
		}
		else if (direction == "right") {
			chatbox.style.flexDirection = "row-reverse";
			chatbox.style.marginLeft = "auto";
			chatwindow.style.alignItems = "flex-start";
			localStorage.setItem('chatHorizontal', "right");
		}
		else if (direction == "middle") {
			chatbox.style.flexDirection = "row";
			chatbox.style.marginLeft = "0px";
			chatwindow.style.alignItems = "center";
			localStorage.setItem('chatHorizontal', "middle");
		}
		else if (direction == "top") {
			chatwindow.style.flexDirection = "column-reverse";
			chatlist.style.flexDirection = "column-reverse";
			chatlist.style.marginTop = "0px";
			chatlist.style.marginBottom = "auto";
			localStorage.setItem('chatVertical', "top");
		}
		else if (direction == "bottom") {
			chatwindow.style.flexDirection = "column";
			chatlist.style.flexDirection = "column";
			chatlist.style.marginTop = "auto";
			chatlist.style.marginBottom = "0px";
			localStorage.setItem('chatVertical', "bottom");
		}
	}

	$scope.chatSwapHorizontal = function() {
		const chatHorizontal = localStorage.getItem('chatHorizontal') || "middle";
		if (chatHorizontal == "left") setChatDirection("middle");
		else if (chatHorizontal == "middle") setChatDirection("right");
		else setChatDirection("left");
	}

	$scope.chatSwapVertical = function() {
		const chatVertical = localStorage.getItem('chatVertical');
		if (chatVertical != "top") setChatDirection("top");
		else setChatDirection("bottom");
	
		scrollToLastMessage();
	}

	onAny(CHAT_EVENTS.chatMessage, function (event, rawData) {
		const data = parsePayload(rawData, null);
		if (!data || data.id === undefined) return;
		if (data.id > lastMsgId) {
			lastMsgId = data.id;

			var now = new Date();
			var hour    = now.getHours();
			var minute  = now.getMinutes();
			var second  = now.getSeconds();
			if(hour < 10) hour = '0'+hour;
			if(minute < 10) minute = '0'+minute;
			if(second < 10) second = '0'+second;
		
			var time = hour + ":" + minute + ":" + second;
			
			storeChatMessage({message: data.message, time: time})
			addMessage(data.message);
		}
	});

	onAny(CHAT_EVENTS.clearChatHistory, function (event, data) {
		localStorage.removeItem('chatMessages');
	})

	$scope.$on('LocalPlayerIdentity', function (event, rawData) {
		const data = parsePayload(rawData, {}) || {};
		localPlayerNames.clear();
		if (data.beammp_name)  localPlayerNames.add(data.beammp_name);
		if (data.display_name) localPlayerNames.add(data.display_name);
	});

	$scope.$on('SettingsChanged', function (event, data) {
		Settings.values = data.values;

		applyChatStyle(Settings.values.useUiAppRedesign);

		newChatMenu = Settings.values.enableNewChatMenu;

		const chatbox = document.getElementById("chat-window");
		if (newChatMenu) {
			chatbox.style.display = "none";
		} else {
			chatbox.style.display = "flex";
		}
	})

	$scope.chatSend = function() {
		let chatinput = document.getElementById("chat-input");
		const text = chatinput.value
		if (text) {
			lastSentMessage = text;
			if (text.length > 500) addMessage("Your message is over the character limit! (500)");
			else {
				bngApi.engineLua('UI.chatSend(' + bngApi.serializeToLua(text) + ')');
				chatinput.value = '';
			}
		}
	};
}]);



function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

var chatShown = false;
var chatShowTime = 3500; // 5000ms
var chatFadeSteps = 1/30; // 60 steps
var chatFadeSpeed = 1000 / (1/chatFadeSteps); // 1000ms
async function fadeNode(node) {
	node.style.opacity = 1.0;
	for (var steps = chatShowTime/35; steps < chatShowTime; steps += chatShowTime/35) {
		if (chatShown) return;
		await sleep(chatShowTime/35);
	}
	var nodeOpacity = 1.0;
	while (nodeOpacity > 0.0) {
		if (chatShown) return;
		nodeOpacity = nodeOpacity - chatFadeSteps;
		node.style.opacity = nodeOpacity;
		await sleep(chatFadeSpeed);
	}
}

async function showChat() {
	if (newChatMenu) return;

	var chatMessages = []
	while (chatShown) {
		var tempMessages = document.getElementById("chat-list").getElementsByTagName("li");
		for (i = 0; i < tempMessages.length; i++) {
			chatMessages[i] = tempMessages[i];
		}
		for (var i = 0; i < chatMessages.length; ++i) chatMessages[i].style.opacity = 1.0;
		await sleep(100);
	}

	for (var steps = chatShowTime/35; steps < chatShowTime; steps += chatShowTime/35) {
		if (chatShown) return;
		await sleep(chatShowTime/35);
	}
	var chatOpacity = 1.0;
	while (chatOpacity > 0.0) {
		if (chatShown) break;
		chatOpacity = chatOpacity - chatFadeSteps;
		for (var i = 0; i < chatMessages.length; ++i) chatMessages[i].style.opacity = chatOpacity;
		await sleep(chatFadeSpeed);
	}
}


function escapeChatHtml(value) {
    return String(value === undefined || value === null ? '' : value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function sanitizeChatInput(string) {
    if (typeof DOMPurify !== 'undefined' && DOMPurify && typeof DOMPurify.sanitize === 'function') {
        return DOMPurify.sanitize(string);
    }
    return escapeChatHtml(string);
}

function formatChatMessage(string) {
    const blockedTags = new Set(['script', 'iframe', 'form', 'input', 'button', 'a']);
    
    const dangerousAttributePattern = /^(?:on.*|(?:form).*|action)$/i;

    function isSafeHtml(html) {
        const div = document.createElement('div');
        div.innerHTML = html;
        
        const elements = div.getElementsByTagName('*');
        for (let element of elements) {
            if (blockedTags.has(element.tagName.toLowerCase())) {
                return false;
            }
            
            for (let attr of element.attributes) {
                if (dangerousAttributePattern.test(attr.name) || 
                    /javascript:|data:/i.test(attr.value)) {
                    return false;
                }
            }
        }
        return true;
    }

    if (string.startsWith("Server: ")) {
        const messageContent = string.substring(8);
        if (messageContent.includes('<') && messageContent.includes('>')) {
            if (isSafeHtml(messageContent)) {
                return "Server: " + messageContent;
            }
        }
    }

    let result = '';
    let currentText = '';
    let classes = new Set();
    let currentHexColor = null;
    let currentHexBg = null;

    string = sanitizeChatInput(string);
    const tokens = string.split(/(\^@#[0-9a-fA-F]{6}|\^#[0-9a-fA-F]{6}|\^.)/g);

    const flush = () => {
        if (!currentText) return;
        const classList = Array.from(classes);
        let attrs = classList.length ? ` class="${classList.join(' ')}"` : '';
        let style = '';
        if (currentHexColor) style += `color:${currentHexColor};`;
        if (currentHexBg) style += `background-color:${currentHexBg};`;
        if (style) attrs += ` style="${style}"`;
        result += attrs
            ? `<span${attrs}>${currentText}</span>`
            : currentText;
        currentText = '';
    };

    for (let index = 0; index < tokens.length; index += 1) {
        const token = tokens[index];
        const nextToken = (tokens[index + 1] || '').trim();

        if (/^\^@#[0-9a-fA-F]{6}$/.test(token)) {
            flush();
            currentHexBg = token.slice(2);
        } else if (/^\^#[0-9a-fA-F]{6}$/.test(token)) {
            flush();
            [...classes].forEach(c => c.startsWith('color-') && classes.delete(c));
            currentHexColor = token.slice(1);
        } else if (/^\^.$/.test(token)) {
            flush();
            if (token === '^r') {
                classes.clear();
                currentHexColor = null;
                currentHexBg = null;
            } else if (token === '^p') {
                result += '<br>';
            } else if (token === '^*') {
                const cls = globalThis.serverStyleMap?.[token];
                if (cls) classes.add(cls);
                if (globalThis.iconsOrig?.[nextToken]) {
                    currentText = globalThis.iconsOrig[nextToken].glyph;
                }
            } else {
                const cls = globalThis.serverStyleMap?.[token];
                if (cls?.startsWith('color-')) {
                    [...classes].forEach(c => c.startsWith('color-') && classes.delete(c));
                    classes.add(cls);
                    currentHexColor = null;
                } else if (cls) {
                    classes.add(cls);
                }
            }
        } else if (tokens[index - 1] !== '^*') {
            currentText += token;
        }
    }

    flush();
    return result;
}

function storeChatMessage(message) {
  if (typeof(Storage) !== "undefined") {
    let chatMessages = JSON.parse(localStorage.getItem("chatMessages")) || [];

    chatMessages.push(message);

		if (chatMessages.length > 70) {
			chatMessages.shift()
		}

    localStorage.setItem("chatMessages", JSON.stringify(chatMessages));

    return chatMessages;
  } else {
    console.error("localStorage is not available in this browser.");
    return null;
  }
}

function retrieveChatMessages() {
	if (typeof localStorage !== 'undefined') {
		const storedMessages = localStorage.getItem('chatMessages');
		if (storedMessages) {
			return JSON.parse(storedMessages);
		}
	}
}

function addMessage(msg, time = null) {
    if (window.pitDisplayNames) {
        for (var _bn in window.pitDisplayNames) {
            var _idx = msg.indexOf(_bn + ': ');
            if (_idx !== -1) {
                msg = msg.substring(0, _idx)
                    + window.pitDisplayNames[_bn]
                    + msg.substring(_idx + _bn.length);
                break;
            }
        }
    }
	if (time == null) {
		var now = new Date();
		var hour    = now.getHours();
		var minute  = now.getMinutes();
		var second  = now.getSeconds();
		if(hour < 10) hour = '0'+hour;
		if(minute < 10) minute = '0'+minute;
		if(second < 10) second = '0'+second;

		time = hour + ":" + minute + ":" + second;
	}

  const msgText = "" + msg
	msg = time + " " + msg;

	const chatMessageNode = document.createElement("li");
	chatMessageNode.className = "chat-message";
	fadeNode(chatMessageNode);

	const messageTimestampNode = document.createElement("span");
	messageTimestampNode.className = "chat-message-timestamp";

	const timestampTextNode = document.createTextNode(time);
	messageTimestampNode.appendChild(timestampTextNode);

	chatMessageNode.appendChild(messageTimestampNode)

	const chatList = document.getElementById("chat-list");

	if (msgText.startsWith("Server: ")) {
		const formattedInnerHtml = formatChatMessage(msgText);
		chatMessageNode.innerHTML = chatMessageNode.innerHTML + formattedInnerHtml;
	} else {
		const textNode = document.createTextNode(msgText);
		chatMessageNode.appendChild(textNode);
	}

	for (let name of localPlayerNames) {
		if (msgText.includes('@' + name)) {
			const mentionArea = document.getElementById('mention-area');
			mentionArea.style.display = 'flex';
			playMentionPing();
			const bell = '<span style="font-size:14px;flex-shrink:0;filter:drop-shadow(0 0 3px #000);">🔔</span>';
			const timeSpan = '<span style="font-size:0.7em;color:rgba(255,215,0,0.6);margin-right:3px;">' + time + '</span>';
			const cleanMsg = formatChatMessage(msgText.replace(new RegExp('@' + name, 'g'), '').trim());
			mentionArea.innerHTML = bell + '<span class="mention-inner">' + timeSpan + cleanMsg + '</span>';
			mentionArea.onclick = () => {
				mentionArea.style.display = 'none';
				mentionArea.innerHTML = '';
			};
			break;
		}
	}

	chatList.appendChild(chatMessageNode);

	if (chatList.children.length > 70) {
		chatList.removeChild(chatList.children[0]);
	}
	
	scrollToLastMessage();

}

function scrollToLastMessage() {
	const chatwindow = document.getElementById("chat-window");
	const chatlist = document.getElementById("chat-list");
	const isReversed = getComputedStyle(chatwindow).flexDirection === "column-reverse";
	if (isReversed) {
		chatlist.scrollTop = -chatlist.scrollHeight;
	} else {
		chatlist.scrollTop = chatlist.scrollHeight;
	}
}

function onKeyDown(e) {
	if (e.key == "ArrowUp") {
		console.log(e);
		document.getElementById("chat-input").value = lastSentMessage;
		e.target.setSelectionRange(lastSentMessage.length, lastSentMessage.length);
	} else if (e.key === "Enter") {
		e.preventDefault();
		e.stopPropagation();
		document.getElementById("send-button").click();
	}
}
