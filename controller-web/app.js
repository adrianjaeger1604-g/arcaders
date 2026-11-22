const screens = {
    connection: document.getElementById('connection-screen'),
    join: document.getElementById('join-screen'),
    characterSelect: document.getElementById('character-select-screen'),
    quiz: document.getElementById('quiz-screen'),
    buzzer: document.getElementById('buzzer-screen'),
    minigame10sec: document.getElementById('minigame-10sec-screen'),
    minigameCookieClickers: document.getElementById('minigame-cookie-clickers-screen') || document.getElementById('minigame-tip-fast-screen'),
    minigameTipFast: document.getElementById('minigame-cookie-clickers-screen') || document.getElementById('minigame-tip-fast-screen'),
    feEquip: document.getElementById('fe-equip-screen'),
    feTurn: document.getElementById('fe-turn-screen'),
    iceClimbers: document.getElementById('ice-climbers-screen'),
    betBuddy: document.getElementById('bet-buddy-screen'),
    waiting: document.getElementById('waiting-screen'),
};

const statusText = document.getElementById('status-text');
const btnJoin = document.getElementById('btn-join');
const playerNameInput = document.getElementById('player-name');
const btnSubmitAnswer = document.getElementById('btn-submit-answer');
const quizInput = document.getElementById('quiz-answer');
const btnBuzzer = document.getElementById('btn-buzzer');
const btn10secHold = document.getElementById('btn-10sec-hold');
const btnCookieClickersMash = document.getElementById('btn-cookie-clickers-mash') || document.getElementById('btn-tip-fast-mash');
const btnTipFastMash = btnCookieClickersMash;

let socket = null;
let myPlayerId = parseInt(localStorage.getItem('playerId') || "-1");
let myPlayerName = localStorage.getItem('playerName') || "";
let myGameSessionId = parseInt(localStorage.getItem('gameSessionId') || "0");
let reconnectTimeout = null;

if (playerNameInput && myPlayerName) {
    playerNameInput.value = myPlayerName;
}

let cookieClickersClicks = 0;
let cookieClickersInterval = null;
let tipFastClicks = 0;
let tipFastInterval = null;
let isCookieClickerEnabled = false;
let isIceClimbersEnabled = false;

// Fire Emblem Controller State
let feSelectedRps = "scissors";
let feSelectedRole = "tank";
let feTurnState = null; // Vom Server empfangenes State-Objekt
let fePlannedPath = []; // [{x, y}, ...]
let feAttackDir = "up";
let feMeteorPos = { x: 5, y: 5 };
let feSwapRpsChoice = "scissors";

// Standardized Pixel-Art Icon Helper (sizes: 's', 'm', 'l')
function pxIconHtml(name, size = 's') {
    const safeName = (name || 'question').replace(/[^a-z0-9_]/gi, '');
    return `<img class="px-icon px-icon--${size}" src="assets/icons/${safeName}.svg" alt="">`;
}

const FE_RPS_NAMES = {
    scissors: "Schere",
    rock: "Stein",
    paper: "Papier"
};

const FE_RPS_ICON_KEYS = {
    scissors: "scissors",
    rock: "rock",
    paper: "paper"
};

function logDebug(msg) {
    const el = document.getElementById('debug-log');
    if (el) {
        const isNearBottom = (el.scrollHeight - el.scrollTop - el.clientHeight) < 50;
        const div = document.createElement('div');
        div.textContent = `[${new Date().toLocaleTimeString()}] ${msg}`;
        el.appendChild(div);
        if (isNearBottom) {
            el.scrollTop = el.scrollHeight;
        }
    }
}

function updateScore(score) {
    const scoreDisplay = document.getElementById('score-display');
    const playerScoreSpan = document.getElementById('player-score');
    if (scoreDisplay && playerScoreSpan) {
        playerScoreSpan.innerText = score;
        logDebug("Score updated: " + score);
    }
}

function updateUserBadge(currentScreen) {
    const userBadge = document.getElementById('user-badge');
    const userBadgeName = document.getElementById('user-badge-name');
    if (!userBadge || !userBadgeName) return;

    if (myPlayerName) {
        userBadgeName.textContent = myPlayerName;
    }

    let activeScreen = currentScreen;
    if (!activeScreen) {
        for (const key in screens) {
            if (screens[key] && screens[key].classList.contains('active')) {
                activeScreen = key;
                break;
            }
        }
    }

    // Nicht anzeigen, wenn noch kein Name gewählt oder auf dem Join-/Connection-Screen
    if (!myPlayerName || activeScreen === 'join' || activeScreen === 'connection') {
        userBadge.style.display = 'none';
    } else {
        userBadge.style.display = 'flex';
    }
}
updateUserBadge();

function showScreen(screenName) {
    // Wenn 'waiting' aufgerufen wird, aber noch gar kein Spielername existiert,
    // darf der Spieler nicht im 'Warten'-Screen feststecken, sondern muss den Namen wählen!
    if (screenName === 'waiting' && !myPlayerName) {
        screenName = 'join';
    }

    logDebug("Switching to: " + screenName);
    
    // Clear Cookie Clickers click batching if switching away
    if (screenName !== 'minigameCookieClickers' && screenName !== 'minigameTipFast') {
        if (cookieClickersClicks > 0 || cookieTotalClicks > 0) {
            sendMessage({
                type: "cookie_clickers_clicks_batch",
                clicks: cookieClickersClicks,
                total_clicks: cookieTotalClicks,
                is_final: true
            });
        }
        if (cookieClickersInterval) {
            clearInterval(cookieClickersInterval);
            cookieClickersInterval = null;
        }
        if (tipFastInterval) {
            clearInterval(tipFastInterval);
            tipFastInterval = null;
        }
        cookieClickersClicks = 0;
        tipFastClicks = 0;
        setCookieClickerState(false, "READY");
    }

    if (screenName !== 'iceClimbers') {
        resetIceClimbersInput();
        isIceClimbersEnabled = false;
    }

    if (screenName !== 'buzzer') {
        stopBuzzerCountdown(false);
    }
    
    if (screenName !== 'betBuddy') {
        const bbInputSec = document.getElementById('bet-buddy-input-section');
        const bbSubmittedBox = document.getElementById('bet-buddy-submitted-box');
        const bbSpectatorBox = document.getElementById('bet-buddy-spectator-box');
        const bbTopicTitle = document.getElementById('bet-buddy-topic-title');
        const bbSpecPlayer = document.getElementById('bet-buddy-spec-player');
        const bbSpecCount = document.getElementById('bet-buddy-spec-count');
        const bbBtnSubmit = document.getElementById('btn-submit-bet');
        if (bbInputSec) bbInputSec.style.display = 'flex';
        if (bbSubmittedBox) bbSubmittedBox.style.display = 'none';
        if (bbSpectatorBox) bbSpectatorBox.style.display = 'none';
        if (bbTopicTitle) bbTopicTitle.textContent = "Thema lädt...";
        if (bbSpecPlayer) bbSpecPlayer.textContent = "";
        if (bbSpecCount) bbSpecCount.textContent = "";
        if (bbBtnSubmit) {
            bbBtnSubmit.disabled = false;
            bbBtnSubmit.textContent = "WETTE EINLOGGEN";
        }
    }
    
    Object.values(screens).forEach(s => {
        if (s) s.classList.remove('active');
    });
    if (screens[screenName]) {
        screens[screenName].classList.add('active');
    } else {
        logDebug("ERROR: Screen not found: " + screenName);
        console.error("Screen nicht gefunden: " + screenName);
    }

    // Score-Anzeige auf dem Handy nicht anzeigen
    const scoreDisplay = document.getElementById('score-display');
    if (scoreDisplay) {
        scoreDisplay.style.display = 'none';
    }

    // Ice Climbers Eingaben zurücksetzen beim Screen-Wechsel
    resetIceClimbersInput();

    // Benutzeranzeige oben rechts aktualisieren
    updateUserBadge(screenName);

    // Abmelden-Button nur auf dem Join- oder Connection-Screen ausblenden.
    // Auf ALLEN anderen Screens (auch 'waiting') ist er stets sichtbar!
    if (btnLogout) {
        if (screenName === 'join' || screenName === 'connection') {
            btnLogout.style.display = 'none';
        } else {
            btnLogout.style.display = 'block';
        }
    }
}

function initWebSocket() {
    // URL parameters to get Godot IP (e.g. ?ip=192.168.1.50)
    const urlParams = new URLSearchParams(window.location.search);
    const ip = urlParams.get('ip') || 'localhost'; // default to localhost for testing

    statusText.innerText = `Verbinde zu ${ip}...`;

    if (socket) {
        try {
            socket.onopen = null;
            socket.onmessage = null;
            socket.onclose = null;
            socket.onerror = null;
            socket.close();
        } catch(e) {}
    }

    socket = new WebSocket(`ws://${ip}:8080`);

    socket.onopen = function (e) {
        statusText.innerText = "Verbunden!";
        logDebug("WS Connected.");
        if (reconnectTimeout) {
            clearTimeout(reconnectTimeout);
            reconnectTimeout = null;
        }

        if (myPlayerName) {
            logDebug("Auto-rejoining as: " + myPlayerName);
            sendMessage({ type: "join", name: myPlayerName, game_session_id: myGameSessionId });
        } else {
            showScreen('join');
        }
    };

    socket.onmessage = async function (event) {
        let rawData = event.data;
        let textData = rawData;

        // Wenn Godot das Paket als Binärdaten (Blob) schickt, wandeln wir es in einen String um
        if (rawData instanceof Blob) {
            textData = await rawData.text();
        }

        let msg;
        try {
            msg = JSON.parse(textData);
            logDebug("RCV: " + msg.type + (msg.state ? " state=" + msg.state : ""));
        } catch (e) {
            logDebug("ERR: Invalid JSON");
            console.error("Invalid JSON from server", textData);
            return;
        }

        handleServerMessage(msg);
    };

    socket.onclose = function (event) {
        logDebug("WS Closed: " + event.code);
        if (myPlayerName) {
            statusText.innerText = "Verbindung verloren. Verbinde erneut...";
            if (!reconnectTimeout) {
                reconnectTimeout = setTimeout(() => {
                    reconnectTimeout = null;
                    initWebSocket();
                }, 1500);
            }
        } else {
            statusText.innerText = "Verbindung getrennt. Bitte neu laden.";
            showScreen('connection');
        }
    };

    socket.onerror = function (error) {
        logDebug("WS Error");
        console.error("WebSocket Error: ", error);
        if (myPlayerName) {
            statusText.innerText = "Verbindungsfehler. Verbinde erneut...";
            if (!reconnectTimeout) {
                reconnectTimeout = setTimeout(() => {
                    reconnectTimeout = null;
                    initWebSocket();
                }, 1500);
            }
        } else {
            statusText.innerText = "Verbindungsfehler!";
        }
    };
}

function sendMessage(msgObj) {
    if (socket && socket.readyState === WebSocket.OPEN) {
        // Always include our ID if we have one
        if (myPlayerId !== -1) {
            msgObj.player_id = myPlayerId;
        }
        socket.send(JSON.stringify(msgObj));
    }
}

function handleServerMessage(msg) {
    // Example: Server tells us to switch state
    if (msg.type === "state_change") {
        if (msg.state === "waiting" || msg.state === "inactive") {
            const waitTitle = document.getElementById('waiting-title');
            const waitMsg = document.getElementById('waiting-message');
            if (waitTitle) waitTitle.innerText = msg.title || (msg.state === "inactive" ? "DEATHMATCH" : "Warten...");
            if (waitMsg) waitMsg.innerText = msg.message || "Bitte schau auf den Hauptbildschirm.";
            showScreen('waiting');
        }
        else if (msg.state === "character_select") showScreen('characterSelect');
        else if (msg.state === "quiz") {
            document.getElementById('quiz-question').innerText = msg.question || "Neue Frage!";
            quizInput.value = "";
            showScreen('quiz');
        }
        else if (msg.state === "buzzer") {
            setupBuzzerScreen(msg);
        }
        else if (msg.state === "minigame_10sec") {
            // Button zurücksetzen
            if (btn10secHold) {
                btn10secHold.classList.remove('active-hold');
                btn10secHold.innerText = "HALTEN";
                btn10secHold.disabled = false;
            }
            showScreen('minigame10sec');
        }
        else if (msg.state === "minigame_cookie_clickers" || msg.state === "cookie_clickers" || msg.state === "coockie_clickers" || msg.state === "minigame_tip_fast") {
            const isEnabled = msg.enabled !== false;
            setCookieClickerState(isEnabled, msg.countdown_text || (isEnabled ? "GO!" : "READY"));
            showScreen('minigameCookieClickers');
        }
        else if (msg.state === "fire_emblem_equip") {
            const btnEquipSubmit = document.getElementById('btn-fe-equip-submit');
            if (btnEquipSubmit) {
                btnEquipSubmit.disabled = false;
                btnEquipSubmit.innerText = "AUSRÜSTUNG EINLOGGEN";
            }
            showScreen('feEquip');
        }
        else if (msg.state === "fire_emblem_turn") {
            setupFireEmblemTurn(msg);
        }
        else if (msg.state === "ice_climbers") {
            const isEnabled = msg.enabled !== false;
            setIceClimbersState(isEnabled, msg.countdown_text || (isEnabled ? "GO!" : "READY"), msg.banner_text);
            showScreen('iceClimbers');
        }
        else if (msg.state === "bet_buddy_bet") {
            setupBetBuddyScreen(msg);
        }
        else if (msg.state === "bet_buddy_spectate") {
            setupBetBuddySpectate(msg);
        }
    }
    else if (msg.type === "join_accept") {
        myPlayerId = msg.player_id;
        localStorage.setItem('playerId', myPlayerId);
        if (msg.name) {
            myPlayerName = msg.name;
        }
        localStorage.setItem('playerName', myPlayerName);
        updateUserBadge();
        if (btnJoin) {
            btnJoin.disabled = false;
            btnJoin.innerText = "BEITRETEN";
        }
        if (btnLogout) btnLogout.style.display = 'block';

        if (msg.game_session_id !== undefined) {
            myGameSessionId = parseInt(msg.game_session_id);
            localStorage.setItem('gameSessionId', myGameSessionId);
        }

        // Aktualisiere sofort den Punktestand (z.B. nach Reload/Reconnect)
        if (msg.score !== undefined) {
            updateScore(msg.score);
        }

        // Wenn der Server uns mitteilt, dass das Spiel schon einen bestimmten Screen hat
        if (msg.current_state === "character_select") showScreen('characterSelect');
        else if (msg.current_state === "quiz") {
            const el = document.getElementById('quiz-question');
            if (el) el.innerText = msg.question || "Neue Frage!";
            if (quizInput) quizInput.value = "";
            showScreen('quiz');
        }
        else if (msg.current_state === "buzzer") {
            setupBuzzerScreen(msg);
        }
        else if (msg.current_state === "minigame_10sec") showScreen('minigame10sec');
        else if (msg.current_state === "minigame_cookie_clickers" || msg.current_state === "cookie_clickers" || msg.current_state === "coockie_clickers" || msg.current_state === "minigame_tip_fast") {
            const isEnabled = msg.enabled !== false;
            setCookieClickerState(isEnabled, isEnabled ? "GO!" : "READY");
            showScreen('minigameCookieClickers');
        }
        else if (msg.current_state === "fire_emblem_equip") {
            showScreen('feEquip');
        }
        else if (msg.current_state === "ice_climbers") {
            const isEnabled = msg.enabled !== false;
            setIceClimbersState(isEnabled, msg.countdown_text || (isEnabled ? "GO!" : "READY"), msg.banner_text);
            showScreen('iceClimbers');
        }
        else if (msg.current_state === "bet_buddy_bet") {
            setupBetBuddyScreen(msg);
        }
        else if (msg.current_state === "bet_buddy_spectate") {
            setupBetBuddySpectate(msg);
        }
        else showScreen('waiting');
    }
    else if (msg.type === "new_game_started" || msg.type === "reset_to_join") {
        logDebug("New game started: resetting session.");
        myPlayerId = -1;
        myPlayerName = "";
        localStorage.removeItem('playerName');
        updateUserBadge();
        if (msg.game_session_id !== undefined) {
            myGameSessionId = parseInt(msg.game_session_id);
            localStorage.setItem('gameSessionId', myGameSessionId);
        }
        if (playerNameInput) playerNameInput.value = "";
        if (btnJoin) {
            btnJoin.disabled = false;
            btnJoin.innerText = "BEITRETEN";
        }
        if (btnLogout) btnLogout.style.display = 'none';
        showScreen('join');
    }
    else if (msg.type === "left_game_confirmed") {
        logDebug("Left game confirmed.");
        myPlayerId = -1;
        myPlayerName = "";
        localStorage.removeItem('playerName');
        updateUserBadge();
        if (playerNameInput) playerNameInput.value = "";
        if (btnJoin) {
            btnJoin.disabled = false;
            btnJoin.innerText = "BEITRETEN";
        }
        if (btnLogout) btnLogout.style.display = 'none';
        showScreen('join');
    }
    else if (msg.type === "score_update") {
        updateScore(msg.score);
    }
    else if (msg.type === "cookie_clickers_countdown" || msg.type === "tip_fast_countdown") {
        const lockText = document.getElementById('cookie-lock-text');
        const lockBadge = document.getElementById('cookie-lock-badge');
        if (lockBadge) lockBadge.classList.remove('hidden', 'go');
        if (lockText) lockText.textContent = msg.countdown_text || "READY";
    }
    else if (msg.type === "ice_climbers_countdown") {
        const lockText = document.getElementById('ic-lock-text');
        const lockBadge = document.getElementById('ic-lock-badge');
        if (lockBadge && !isIceClimbersEnabled) lockBadge.classList.remove('hidden', 'go');
        if (lockText) lockText.textContent = msg.countdown_text || "READY";
    }
    else if (msg.type === "buzzer_locked") {
        const buzzerLockedBadge = document.getElementById('buzzer-locked-badge');
        if (buzzerLockedBadge) {
            buzzerLockedBadge.innerText = (msg.player_name || "Jemand") + " hat gebuzzert!";
            buzzerLockedBadge.style.display = 'block';
        }
        if (btnBuzzer) {
            btnBuzzer.disabled = true;
            btnBuzzer.classList.add('buzzer-disabled');
        }
        stopBuzzerCountdown(true);
    }
    else if (msg.type === "buzzer_unlocked") {
        const buzzerLockedBadge = document.getElementById('buzzer-locked-badge');
        if (buzzerLockedBadge) buzzerLockedBadge.style.display = 'none';
        if (btnBuzzer) {
            btnBuzzer.disabled = false;
            btnBuzzer.classList.remove('buzzer-disabled');
        }
    }
    else if (msg.type === "buzzer_timer_sync") {
        // Handy zeigt laut Regel 9 keinen Timer
    }
    else if (msg.type === "bet_buddy_timer_update") {
        updateBetBuddySpectatorTimer(msg);
    }
    else if (msg.type === "join_rejected") {
        // Name existiert im laufenden Spiel nicht -> zurueck zur Namenseingabe
        myPlayerName = "";
        myPlayerId = -1;
        localStorage.removeItem('playerName');
        updateUserBadge();
        if (btnJoin) {
            btnJoin.disabled = false;
            btnJoin.innerText = "BEITRETEN";
        }
        if (btnLogout) btnLogout.style.display = 'none';
        showScreen('join');
        alert(msg.reason || "Dieser Spieler existiert im aktuell laufenden Spiel nicht.");
    }
    else if (msg.type === "kicked") {
        alert("Du wurdest vom Spielleiter entfernt.");
        localStorage.removeItem('playerName');
        location.reload();
    }
}

// =========================================================================
// FIRE EMBLEM MINIGAME LOGIC
// =========================================================================

const rpsButtons = document.querySelectorAll('#fe-rps-group .fe-choice-btn');
rpsButtons.forEach(btn => {
    btn.addEventListener('click', () => {
        rpsButtons.forEach(b => b.classList.remove('selected'));
        btn.classList.add('selected');
        feSelectedRps = btn.dataset.rps;
    });
});

const roleButtons = document.querySelectorAll('#fe-role-group .fe-role-btn');
roleButtons.forEach(btn => {
    btn.addEventListener('click', () => {
        roleButtons.forEach(b => b.classList.remove('selected'));
        btn.classList.add('selected');
        feSelectedRole = btn.dataset.role;
    });
});

const btnFeEquipSubmit = document.getElementById('btn-fe-equip-submit');
if (btnFeEquipSubmit) {
    btnFeEquipSubmit.addEventListener('click', () => {
        btnFeEquipSubmit.disabled = true;
        btnFeEquipSubmit.innerText = "GESENDET...";
        sendMessage({
            type: "fe_equip_submit",
            rps: feSelectedRps,
            role: feSelectedRole
        });
        showScreen('waiting');
    });
}

function isFeValidCell(x, y, state) {
    const size = state.grid_size || 11;
    const cx = state.center ? state.center.x : 5;
    const cy = state.center ? state.center.y : 5;
    const maxDist = state.max_arena_dist || 7;
    if (x < 0 || x >= size || y < 0 || y >= size) return false;
    return (Math.abs(x - cx) + Math.abs(y - cy)) <= maxDist;
}

function getFeArenaRingDist(x, y, state) {
    const cx = state.center ? state.center.x : 5;
    const cy = state.center ? state.center.y : 5;
    const dx = Math.abs(x - cx);
    const dy = Math.abs(y - cy);
    const manh = dx + dy;
    const cheb = Math.max(dx, dy);
    const clampCheb = Math.min(2, Math.max(0, cheb - 1));
    return Math.max(manh, cheb + clampCheb);
}

function isFeDangerZone(x, y, state) {
    const zoneDist = state.zone_max_dist !== undefined ? state.zone_max_dist : 7;
    return getFeArenaRingDist(x, y, state) > zoneDist;
}

const FE_CELL_PX = 52;
const FE_CELL_GAP = 3;
const FE_GRID_PAD = 10;
let fePanOffset = { x: 0, y: 0 };
let feDragActive = false;
let feDragMoved = false;
let feDragStartPt = { x: 0, y: 0 };
let feDragStartPan = { x: 0, y: 0 };

function applyFePanTransform(animate = false) {
    const zoomGrid = document.getElementById('fe-zoom-grid');
    const vp = document.getElementById('fe-map-viewport');
    if (!zoomGrid || !vp) return;

    const vpW = vp.clientWidth || 286;
    const vpH = vp.clientHeight || 286;
    const totalPx = 13 * FE_CELL_PX + 12 * FE_CELL_GAP + FE_GRID_PAD * 2;
    const minX = Math.min(0, vpW - totalPx);
    const minY = Math.min(0, vpH - totalPx);

    fePanOffset.x = Math.max(minX, Math.min(0, fePanOffset.x));
    fePanOffset.y = Math.max(minY, Math.min(0, fePanOffset.y));

    zoomGrid.style.transition = animate ? 'transform 0.24s cubic-bezier(0.22, 1, 0.36, 1)' : 'none';
    zoomGrid.style.transform = `translate(${Math.round(fePanOffset.x)}px, ${Math.round(fePanOffset.y)}px)`;
}

function centerFeCameraOnCell(cx, cy, animate = true) {
    const vp = document.getElementById('fe-map-viewport');
    const vpW = (vp && vp.clientWidth) ? vp.clientWidth : 286;
    const vpH = (vp && vp.clientHeight) ? vp.clientHeight : 286;
    const col = cx + 1;
    const row = cy + 1;
    const cellCenterX = FE_GRID_PAD + col * (FE_CELL_PX + FE_CELL_GAP) + FE_CELL_PX * 0.5;
    const cellCenterY = FE_GRID_PAD + row * (FE_CELL_PX + FE_CELL_GAP) + FE_CELL_PX * 0.5;
    fePanOffset.x = vpW * 0.5 - cellCenterX;
    fePanOffset.y = vpH * 0.5 - cellCenterY;
    applyFePanTransform(animate);
}

(function initFeViewportDrag() {
    const vp = document.getElementById('fe-map-viewport');
    if (!vp) return;

    const onStart = (clientX, clientY) => {
        feDragActive = true;
        feDragMoved = false;
        feDragStartPt = { x: clientX, y: clientY };
        feDragStartPan = { x: fePanOffset.x, y: fePanOffset.y };
    };

    const onMove = (clientX, clientY) => {
        if (!feDragActive) return;
        const dx = clientX - feDragStartPt.x;
        const dy = clientY - feDragStartPt.y;
        if (Math.hypot(dx, dy) > 7) {
            feDragMoved = true;
        }
        if (feDragMoved) {
            fePanOffset.x = feDragStartPan.x + dx;
            fePanOffset.y = feDragStartPan.y + dy;
            applyFePanTransform(false);
        }
    };

    const onEnd = () => {
        feDragActive = false;
    };

    vp.addEventListener('touchstart', (e) => {
        if (e.touches.length === 1) {
            onStart(e.touches[0].clientX, e.touches[0].clientY);
        }
    }, { passive: true });

    vp.addEventListener('touchmove', (e) => {
        if (!feDragActive || e.touches.length !== 1) return;
        onMove(e.touches[0].clientX, e.touches[0].clientY);
        if (feDragMoved && e.cancelable) {
            e.preventDefault();
        }
    }, { passive: false });

    vp.addEventListener('touchend', onEnd);
    vp.addEventListener('touchcancel', onEnd);

    vp.addEventListener('mousedown', (e) => {
        if (e.button !== 0) return;
        onStart(e.clientX, e.clientY);
    });
    window.addEventListener('mousemove', (e) => {
        if (feDragActive) onMove(e.clientX, e.clientY);
    });
    window.addEventListener('mouseup', onEnd);

    const btnCenter = document.getElementById('btn-fe-center-cam');
    if (btnCenter) {
        btnCenter.addEventListener('click', (e) => {
            e.stopPropagation();
            const endPos = getFeCurrentEndPos();
            centerFeCameraOnCell(endPos.x, endPos.y, true);
        });
    }
})();

function getFeCurrentEndPos() {
    if (!feTurnState || !feTurnState.me) return { x: 5, y: 5 };
    if (fePlannedPath.length > 0) {
        return fePlannedPath[fePlannedPath.length - 1];
    }
    return { x: feTurnState.me.x, y: feTurnState.me.y };
}

function getFeAttackTargetCell() {
    const endPos = getFeCurrentEndPos();
    if (feAttackDir === "up") return { x: endPos.x, y: endPos.y - 1 };
    if (feAttackDir === "down") return { x: endPos.x, y: endPos.y + 1 };
    if (feAttackDir === "left") return { x: endPos.x - 1, y: endPos.y };
    if (feAttackDir === "right") return { x: endPos.x + 1, y: endPos.y };
    return { x: endPos.x, y: endPos.y - 1 };
}

function getCharSpritePath(charId) {
    const map = {
        Aaron: "sprites/spr_aaron_idle_1.png",
        Anna: "sprites/spr_anna_idle_1.png",
        Cedi: "sprites/spr_cedric_idle_1.png",
        Cedric: "sprites/spr_cedric_idle_1.png",
        Finnja: "sprites/spr_finnja_idle_1.png",
        Jan: "sprites/spr_jan_idle_1.png",
        Janek: "sprites/spr_janek_idle_1.png",
        Leonie: "sprites/spr_leonie_idle_1.png",
        Lia: "sprites/spr_lia_idle_1.png",
        Luca: "sprites/spr_luca_idle_1.png",
        Marius: "sprites/spr_marius_idle_1.png",
        Mikka: "sprites/spr_mikka_idle_1.png",
        Miles: "sprites/spr_miles_idle_1.png",
        Paul: "sprites/spr_paul_idle_1.png",
        Simon: "sprites/spr_simon_idle_1.png"
    };
    return "assets/characters/" + (map[charId] || map["Cedi"]);
}

function setupFireEmblemTurn(msg) {
    feTurnState = msg;
    fePlannedPath = [];
    feAttackDir = "up";

    if (!msg.me || !msg.me.alive || msg.me.turn_ready) {
        showScreen('waiting');
        return;
    }

    const btnTurnSubmit = document.getElementById('btn-fe-turn-submit');
    if (btnTurnSubmit) {
        btnTurnSubmit.disabled = false;
        btnTurnSubmit.innerText = "ZUG BESTÄTIGEN";
    }

    document.querySelectorAll('#fe-atk-group .fe-atk-btn').forEach(b => {
        b.classList.toggle('selected', b.dataset.atk === feAttackDir);
    });

    // Standard-Auswahl für Typ-Wechsel-Feld (nächster Typ im Zyklus)
    const rpsOrder = ["scissors", "rock", "paper"];
    const currIdx = rpsOrder.indexOf(msg.me.rps || "rock");
    feSwapRpsChoice = rpsOrder[(currIdx + 1) % rpsOrder.length];
    document.querySelectorAll('#fe-swap-group .fe-swap-btn').forEach(b => {
        b.classList.toggle('selected', b.dataset.swapRps === feSwapRpsChoice);
    });

    // Standard-Ziel für Meteor (+ Bereich): nächster lebender Gegner oder Kartenmitte
    feMeteorPos = { x: msg.center ? msg.center.x : 5, y: msg.center ? msg.center.y : 5 };
    let bestDist = 999;
    (msg.units || []).forEach(u => {
        if (u.team_index !== msg.me.team_index) {
            const d = Math.abs(u.x - msg.me.x) + Math.abs(u.y - msg.me.y);
            if (d < bestDist) {
                bestDist = d;
                feMeteorPos = { x: u.x, y: u.y };
            }
        }
    });

    renderFireEmblemZoomGrid();
    showScreen('feTurn');
    requestAnimationFrame(() => {
        centerFeCameraOnCell(msg.me.x, msg.me.y, false);
    });
}

function tryAddFeStep(nx, ny) {
    if (!feTurnState || !feTurnState.me) return;
    const maxSteps = feTurnState.me.steps || 2;

    // Wenn man auf das vorletzte Feld tippt -> Schritt rückgängig machen
    if (fePlannedPath.length >= 2) {
        const prev = fePlannedPath[fePlannedPath.length - 2];
        if (prev.x === nx && prev.y === ny) {
            fePlannedPath.pop();
            renderFireEmblemZoomGrid();
            centerFeCameraOnCell(nx, ny, true);
            return;
        }
    } else if (fePlannedPath.length === 1) {
        if (feTurnState.me.x === nx && feTurnState.me.y === ny) {
            fePlannedPath.pop();
            renderFireEmblemZoomGrid();
            centerFeCameraOnCell(nx, ny, true);
            return;
        }
    }

    if (fePlannedPath.length >= maxSteps) return;
    if (!isFeValidCell(nx, ny, feTurnState)) return;

    const curr = getFeCurrentEndPos();
    const dist = Math.abs(nx - curr.x) + Math.abs(ny - curr.y);
    if (dist !== 1) return;

    fePlannedPath.push({ x: nx, y: ny });
    renderFireEmblemZoomGrid();
    centerFeCameraOnCell(nx, ny, true);
}

function renderFireEmblemZoomGrid() {
    if (!feTurnState || !feTurnState.me) return;
    const me = feTurnState.me;
    const maxSteps = me.steps || 2;

    const hpEl = document.getElementById('fe-hud-hp');
    const typeEl = document.getElementById('fe-hud-type');
    const stepsEl = document.getElementById('fe-hud-steps');
    if (hpEl) hpEl.innerHTML = `${pxIconHtml('heart', 's')} ${me.hp}/${me.max_hp} (${pxIconHtml('sword', 's')}${me.dmg})`;
    if (typeEl) {
        const rpsKey = FE_RPS_ICON_KEYS[me.rps] || 'rock';
        const rpsName = FE_RPS_NAMES[me.rps] || 'Stein';
        typeEl.innerHTML = `${pxIconHtml(rpsKey, 's')} ${rpsName}`;
    }
    if (stepsEl) stepsEl.innerHTML = `${pxIconHtml('boots', 's')} ${fePlannedPath.length}/${maxSteps}`;

    const zoomGrid = document.getElementById('fe-zoom-grid');
    if (!zoomGrid) return;
    zoomGrid.innerHTML = '';

    const endPos = getFeCurrentEndPos();
    const atkCell = getFeAttackTargetCell();
    const gridSize = feTurnState.grid_size || 11;
    const roundNum = feTurnState.round || 1;
    const zoneDist = feTurnState.zone_max_dist !== undefined ? feTurnState.zone_max_dist : 7;
    const turnsUntilShrink = 2 - ((roundNum - 1) % 2);

    // Prüfe ob der Endpunkt auf einem Wechsel-Feld liegt
    const landsOnSwap = (feTurnState.specials || []).some(
        s => s.type === "type_swap" && s.x === endPos.x && s.y === endPos.y
    );
    const swapBox = document.getElementById('fe-swap-box');
    if (swapBox) {
        swapBox.style.display = landsOnSwap ? 'flex' : 'none';
    }

    // Prüfe ob der Endpunkt auf einem Meteor-Schrein liegt
    const landsOnMeteor = (feTurnState.specials || []).some(
        s => s.type === "meteor" && s.x === endPos.x && s.y === endPos.y
    );
    const meteorBox = document.getElementById('fe-meteor-box');
    if (meteorBox) {
        const wasHidden = (meteorBox.style.display === 'none' || !meteorBox.style.display);
        meteorBox.style.display = landsOnMeteor ? 'flex' : 'none';
        if (landsOnMeteor) {
            renderFireEmblemMeteorGrid();
            if (wasHidden) {
                setTimeout(() => {
                    meteorBox.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
                }, 60);
            }
        }
    }

    // Rendere das vollständige 13x13 Schlachtfeld inkl. äußerem Feuerring (cx/cy von -1 bis gridSize)
    for (let cy = -1; cy <= gridSize; cy++) {
        for (let cx = -1; cx <= gridSize; cx++) {
            const cellDiv = document.createElement('div');
            cellDiv.className = 'fe-cell';
            const rDist = getFeArenaRingDist(cx, cy, feTurnState);
            const isValid = isFeValidCell(cx, cy, feTurnState);

            if (!isValid) {
                if (rDist === 8) {
                    cellDiv.classList.add('perim-fire-cell');
                    const fireLayer = document.createElement('div');
                    const firePhase = ((cx * 3 + cy * 5) % 4 + 4) % 4;
                    fireLayer.className = `fe-cell-fire fe-fire-p${firePhase}`;
                    cellDiv.appendChild(fireLayer);
                } else {
                    cellDiv.classList.add('void');
                }
                zoomGrid.appendChild(cellDiv);
                continue;
            }

            const inDanger = rDist > zoneDist;
            const isNextRing = (!inDanger && zoneDist > 1 && rDist === zoneDist && turnsUntilShrink === 1);
            const isChecker = ((cx + cy) % 2) === 0;
            const terrainHash = (cx * 17 + cy * 31 + cx * cy * 7) % 10;
            const isBareDirt = terrainHash < 5;

            if (isBareDirt) {
                cellDiv.classList.add(isChecker ? 'terrain-dirt' : 'terrain-dirt-alt');
            } else if (!isChecker) {
                cellDiv.classList.add('terrain-grass-alt');
            }
            if (isNextRing) {
                cellDiv.classList.add('next-ring');
                const emberLayer = document.createElement('div');
                const emberPhase = ((cx * 3 + cy * 5) % 2 + 2) % 2;
                emberLayer.className = `fe-cell-ember fe-ember-p${emberPhase}`;
                cellDiv.appendChild(emberLayer);
            }

            // Sonderfeld exakt wie auf dem Hauptbildschirm einfärben + zentriertes M-Icon
            const spec = (feTurnState.specials || []).find(s => s.x === cx && s.y === cy);
            if (spec && !inDanger) {
                cellDiv.classList.add(`special-${spec.type}`);
                const centerIcon = document.createElement('span');
                centerIcon.className = 'fe-cell-special-center';
                centerIcon.innerHTML = pxIconHtml(spec.icon || 'question', 'm');
                cellDiv.appendChild(centerIcon);
            }

            if (inDanger) {
                cellDiv.classList.add('danger');
                const fireLayer = document.createElement('div');
                const firePhase = ((cx * 3 + cy * 5) % 4 + 4) % 4;
                fireLayer.className = `fe-cell-fire fe-fire-p${firePhase}`;
                cellDiv.appendChild(fireLayer);
            }

            // Ist das Feld direkt vom aktuellen Endpunkt aus erreichbar?
            const distFromEnd = Math.abs(cx - endPos.x) + Math.abs(cy - endPos.y);
            if (distFromEnd === 1 && fePlannedPath.length < maxSteps) {
                cellDiv.classList.add('reachable');
            }

            // Ist das Feld im geplanten Pfad? -> Blau färben!
            let stepIndex = -1;
            for (let i = 0; i < fePlannedPath.length; i++) {
                if (fePlannedPath[i].x === cx && fePlannedPath[i].y === cy) {
                    stepIndex = i + 1;
                }
            }
            if (stepIndex !== -1 || (fePlannedPath.length > 0 && cx === me.x && cy === me.y)) {
                cellDiv.classList.add('in-path');
            }

            // Liegt das Feld im gewählten + Bereich des Meteors?
            if (landsOnMeteor && (Math.abs(cx - feMeteorPos.x) + Math.abs(cy - feMeteorPos.y)) <= 1) {
                cellDiv.classList.add('meteor-impact');
            }

            // Ist das Feld das gewählte Schlag-Zielfeld?
            const isAtkTarget = (cx === atkCell.x && cy === atkCell.y);
            if (isAtkTarget) {
                cellDiv.classList.add('attack-target');
            }

            // Einheit auf diesem Feld? (gleicher Aufbau wie auf dem Hauptbildschirm)
            const unit = (feTurnState.units || []).find(u => u.x === cx && u.y === cy);
            if (unit) {
                const isAlly = (unit.team_index === me.team_index);
                const tColor = unit.team_color || (isAlly ? '#4caf50' : '#ef5350');

                const ring = document.createElement('div');
                ring.className = 'fe-cell-team-ring';
                ring.style.borderColor = tColor;
                ring.style.backgroundColor = `${tColor}44`;
                cellDiv.appendChild(ring);

                const img = document.createElement('img');
                img.className = 'fe-cell-unit-img';
                img.src = getCharSpritePath(unit.character);
                cellDiv.appendChild(img);

                const uBadge = document.createElement('span');
                uBadge.className = 'fe-cell-badge';
                const rpsKey = FE_RPS_ICON_KEYS[unit.rps] || 'rock';
                const boostHtml = unit.dmg_boost ? pxIconHtml('bolt', 's') : '';
                uBadge.innerHTML = `${pxIconHtml(rpsKey, 's')}${boostHtml}`;
                cellDiv.appendChild(uBadge);

                const hpSpan = document.createElement('span');
                hpSpan.className = 'fe-cell-hp';
                const hpRatio = (unit.hp || 0) / Math.max(1, unit.max_hp || 8);
                hpSpan.style.color = hpRatio > 0.5 ? '#59ff73' : (hpRatio > 0.25 ? '#ffd940' : '#ff5959');
                hpSpan.innerHTML = `${unit.hp}${pxIconHtml('heart', 's')}`;
                cellDiv.appendChild(hpSpan);

                const nameSpan = document.createElement('span');
                nameSpan.className = 'fe-cell-name';
                nameSpan.innerText = unit.name || '';
                cellDiv.appendChild(nameSpan);
            }

            // Schlag-Icon auf dem Angriffsziel
            if (isAtkTarget) {
                const numSpan = document.createElement('span');
                numSpan.className = 'fe-cell-step-num';
                numSpan.innerHTML = pxIconHtml('sword', 's');
                cellDiv.appendChild(numSpan);
            }

            cellDiv.addEventListener('click', () => {
                if (feDragMoved) return;
                tryAddFeStep(cx, cy);
            });

            zoomGrid.appendChild(cellDiv);
        }
    }

    // Zeichne durchgehenden weißen Pfeil über die geplanten Schritte auf dem 13x13 Feld
    if (fePlannedPath.length > 0) {
        const pitch = FE_CELL_PX + FE_CELL_GAP;
        const half = FE_CELL_PX * 0.5;
        const innerSpan = 13 * FE_CELL_PX + 12 * FE_CELL_GAP;
        const pathCoords = [{ x: me.x, y: me.y }, ...fePlannedPath];
        const svgPts = pathCoords.map(p => ({
            x: (p.x + 1) * pitch + half,
            y: (p.y + 1) * pitch + half
        }));

        if (svgPts.length >= 2) {
            const last = svgPts[svgPts.length - 1];
            const prev = svgPts[svgPts.length - 2];
            const dx = last.x - prev.x;
            const dy = last.y - prev.y;
            const len = Math.hypot(dx, dy) || 1;
            const ux = dx / len;
            const uy = dy / len;
            const px = -uy;
            const py = ux;

            const linePts = svgPts.map((pt, idx) => {
                if (idx === svgPts.length - 1) {
                    return `${(pt.x - ux * 10).toFixed(1)},${(pt.y - uy * 10).toFixed(1)}`;
                }
                return `${pt.x.toFixed(1)},${pt.y.toFixed(1)}`;
            }).join(' ');

            const tipX = last.x + ux * 4;
            const tipY = last.y + uy * 4;
            const baseLX = last.x - ux * 13 + px * 9.5;
            const baseLY = last.y - uy * 13 + py * 9.5;
            const baseRX = last.x - ux * 13 - px * 9.5;
            const baseRY = last.y - uy * 13 - py * 9.5;
            const headPoints = `${tipX.toFixed(1)},${tipY.toFixed(1)} ${baseLX.toFixed(1)},${baseLY.toFixed(1)} ${baseRX.toFixed(1)},${baseRY.toFixed(1)}`;

            const svgEl = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
            svgEl.setAttribute('class', 'fe-path-svg');
            svgEl.setAttribute('viewBox', `0 0 ${innerSpan} ${innerSpan}`);
            svgEl.setAttribute('preserveAspectRatio', 'none');
            svgEl.innerHTML = `
                <polyline points="${linePts}" fill="none" stroke="rgba(0,0,0,0.78)" stroke-width="11" stroke-linecap="round" stroke-linejoin="round" />
                <polyline points="${linePts}" fill="none" stroke="#ffffff" stroke-width="6" stroke-linecap="round" stroke-linejoin="round" />
                <polygon points="${headPoints}" fill="#ffffff" stroke="rgba(0,0,0,0.78)" stroke-width="2.5" stroke-linejoin="round" />
            `;
            zoomGrid.appendChild(svgEl);
        }
    }

    applyFePanTransform(false);
}

function renderFireEmblemMeteorGrid() {
    const mGrid = document.getElementById('fe-meteor-grid');
    if (!mGrid || !feTurnState || !feTurnState.me) return;
    mGrid.innerHTML = '';
    const gridSize = feTurnState.grid_size || 11;
    const me = feTurnState.me;

    for (let y = 0; y < gridSize; y++) {
        for (let x = 0; x < gridSize; x++) {
            const cell = document.createElement('div');
            cell.className = 'fe-meteor-cell';
            if (!isFeValidCell(x, y, feTurnState)) {
                cell.classList.add('void');
                mGrid.appendChild(cell);
                continue;
            }
            if (isFeDangerZone(x, y, feTurnState)) {
                cell.classList.add('danger');
            }
            const dist = Math.abs(x - feMeteorPos.x) + Math.abs(y - feMeteorPos.y);
            if (dist === 0) {
                cell.classList.add('plus-center');
            } else if (dist === 1) {
                cell.classList.add('plus-area');
            }

            const unit = (feTurnState.units || []).find(u => u.x === x && u.y === y);
            if (unit) {
                const dot = document.createElement('span');
                dot.className = 'fe-meteor-dot ' + (unit.team_index === me.team_index ? 'ally' : 'enemy');
                cell.appendChild(dot);
            }

            cell.addEventListener('click', () => {
                feMeteorPos = { x, y };
                renderFireEmblemZoomGrid();
            });
            mGrid.appendChild(cell);
        }
    }
}

document.querySelectorAll('.fe-step-btn[data-dir]').forEach(btn => {
    btn.addEventListener('click', () => {
        const dir = btn.dataset.dir;
        const curr = getFeCurrentEndPos();
        if (dir === "up") tryAddFeStep(curr.x, curr.y - 1);
        else if (dir === "down") tryAddFeStep(curr.x, curr.y + 1);
        else if (dir === "left") tryAddFeStep(curr.x - 1, curr.y);
        else if (dir === "right") tryAddFeStep(curr.x + 1, curr.y);
    });
});

const btnFeUndo = document.getElementById('btn-fe-undo-step');
if (btnFeUndo) {
    btnFeUndo.addEventListener('click', () => {
        if (fePlannedPath.length > 0) {
            fePlannedPath.pop();
            renderFireEmblemZoomGrid();
        }
    });
}

document.querySelectorAll('#fe-atk-group .fe-atk-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('#fe-atk-group .fe-atk-btn').forEach(b => b.classList.remove('selected'));
        btn.classList.add('selected');
        feAttackDir = btn.dataset.atk;
        renderFireEmblemZoomGrid();
    });
});

document.querySelectorAll('#fe-swap-group .fe-swap-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('#fe-swap-group .fe-swap-btn').forEach(b => b.classList.remove('selected'));
        btn.classList.add('selected');
        feSwapRpsChoice = btn.dataset.swapRps;
    });
});

const btnFeTurnSubmit = document.getElementById('btn-fe-turn-submit');
if (btnFeTurnSubmit) {
    btnFeTurnSubmit.addEventListener('click', () => {
        btnFeTurnSubmit.disabled = true;
        btnFeTurnSubmit.innerText = "ZUG GESENDET";

        sendMessage({
            type: "fe_turn_submit",
            path: fePlannedPath,
            attack_dir: feAttackDir,
            meteor_pos: feMeteorPos,
            swap_rps: feSwapRpsChoice
        });
        showScreen('waiting');
    });
}

// UI Event Listeners
const btnLogout = document.getElementById('btn-logout');
const btnToggleDebug = document.getElementById('btn-toggle-debug');
const btnReload = document.getElementById('btn-reload');
const debugLog = document.getElementById('debug-log');

if (btnToggleDebug && debugLog) {
    btnToggleDebug.addEventListener('click', () => {
        const isHidden = debugLog.style.display === 'none' || getComputedStyle(debugLog).display === 'none';
        debugLog.style.display = isHidden ? 'block' : 'none';
        if (isHidden) {
            debugLog.scrollTop = debugLog.scrollHeight;
        }
    });
}

if (btnReload) {
    btnReload.addEventListener('click', () => {
        btnReload.classList.add('is-spinning');
        setTimeout(() => {
            window.location.reload();
        }, 120);
    });
}

function performLogout() {
    if (confirm("Möchtest du dich abmelden und den Spieler wechseln?")) {
        sendMessage({ type: "leave_game" });
        localStorage.removeItem('playerName');
        localStorage.removeItem('playerId');
        myPlayerName = "";
        myPlayerId = -1;
        updateUserBadge();
        if (playerNameInput) playerNameInput.value = "";
        if (btnLogout) btnLogout.style.display = 'none';
        if (btnJoin) {
            btnJoin.disabled = false;
            btnJoin.innerText = "BEITRETEN";
        }
        showScreen('join');
    }
}

if (btnLogout) {
    btnLogout.addEventListener('click', performLogout);
    
    if (myPlayerName) {
        btnLogout.style.display = 'block';
    }
}

const userBadgeElement = document.getElementById('user-badge');
if (userBadgeElement) {
    userBadgeElement.style.cursor = 'pointer';
    userBadgeElement.title = "Klicken zum Abmelden / Name ändern";
    userBadgeElement.addEventListener('click', performLogout);
}

if (btnJoin && playerNameInput) {
    btnJoin.addEventListener('click', () => {
        const name = playerNameInput.value.trim();
        logDebug("Click Beitreten: " + name);
        if (name) {
            myPlayerName = name;
            localStorage.setItem('playerName', name);
            updateUserBadge();
            if (btnLogout) btnLogout.style.display = 'block';
            btnJoin.disabled = true;
            btnJoin.innerText = "Warte...";
            sendMessage({ type: "join", name: name, game_session_id: myGameSessionId });
        }
    });

    playerNameInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            btnJoin.click();
        }
    });
}

if (btnSubmitAnswer && quizInput) {
    btnSubmitAnswer.addEventListener('click', () => {
        const answer = quizInput.value.trim();
        if (answer) {
            sendMessage({ type: "quiz_answer", answer: answer });
            showScreen('waiting'); // wait for others
        }
    });
}

let buzzerCountdownTimer = null;
let buzzerSecondsLeft = 30;

function updateBuzzerTimerDisplay(sec, isPaused) {
    const badge = document.getElementById('buzzer-timer-badge');
    const secEl = document.getElementById('buzzer-timer-sec');
    if (!badge) return;
    
    badge.classList.remove('warning', 'paused');
    if (isPaused) {
        badge.classList.add('paused');
        badge.innerHTML = "⏱ PAUSIERT";
    } else {
        badge.innerHTML = `⏱ <span id="buzzer-timer-sec">${sec}</span>s`;
        if (sec <= 5) {
            badge.classList.add('warning');
        }
    }
}

function startBuzzerCountdown(sec = 30) {
    if (buzzerCountdownTimer) clearInterval(buzzerCountdownTimer);
    buzzerSecondsLeft = sec;
    updateBuzzerTimerDisplay(buzzerSecondsLeft, false);
    
    buzzerCountdownTimer = setInterval(() => {
        buzzerSecondsLeft--;
        if (buzzerSecondsLeft <= 0) {
            buzzerSecondsLeft = 0;
            clearInterval(buzzerCountdownTimer);
            buzzerCountdownTimer = null;
        }
        updateBuzzerTimerDisplay(buzzerSecondsLeft, false);
    }, 1000);
}

function stopBuzzerCountdown(isPaused = false) {
    if (buzzerCountdownTimer) {
        clearInterval(buzzerCountdownTimer);
        buzzerCountdownTimer = null;
    }
    if (isPaused) {
        updateBuzzerTimerDisplay(buzzerSecondsLeft, true);
    }
}

function setupBuzzerScreen(info) {
    const buzzerHeader = document.getElementById('buzzer-header');
    const buzzerGameTitle = document.getElementById('buzzer-game-title');
    const buzzerTargetVal = document.getElementById('buzzer-target-value');
    const buzzerTargetContainer = document.getElementById('buzzer-target-container');
    const buzzerLockedBadge = document.getElementById('buzzer-locked-badge');
    
    if (info && info.game === "schmierig") {
        if (buzzerHeader) buzzerHeader.style.display = 'flex';
        if (buzzerGameTitle) buzzerGameTitle.innerText = "SCHMIERIG";
        if (buzzerTargetContainer) buzzerTargetContainer.style.display = 'none';
    } else if (info && info.target_sum) {
        if (buzzerHeader) buzzerHeader.style.display = 'flex';
        if (buzzerGameTitle) buzzerGameTitle.innerText = "HEXAGON";
        if (buzzerTargetContainer) buzzerTargetContainer.style.display = 'flex';
        if (buzzerTargetVal) buzzerTargetVal.innerText = info.target_sum;
    } else {
        if (buzzerHeader) buzzerHeader.style.display = 'none';
    }
    stopBuzzerCountdown(false);
    
    if (buzzerLockedBadge) buzzerLockedBadge.style.display = 'none';
    if (btnBuzzer) {
        btnBuzzer.disabled = false;
        btnBuzzer.classList.remove('buzzer-disabled');
    }
    showScreen('buzzer');
}

if (btnBuzzer) {
    btnBuzzer.addEventListener('touchstart', (e) => {
        e.preventDefault(); // prevent mouse emulation
        sendMessage({ type: "buzz" });
    });
    btnBuzzer.addEventListener('mousedown', () => {
        sendMessage({ type: "buzz" });
    });
}

// Logic for Minigame 10 Seconds
if (btn10secHold) {
    let holdStartTime = 0;
    let holdActive = false;

    const startHold = (e) => {
        // Ignoriere Events, falls Knopf deaktiviert
        if (btn10secHold.disabled) return;
        if (e) e.preventDefault();

        holdActive = true;
        holdStartTime = performance.now();
        btn10secHold.classList.add('active-hold');
        btn10secHold.innerText = "LÄUFT...";
        logDebug("Hold started");
    };

    const endHold = (e) => {
        if (!holdActive) return;
        if (e) e.preventDefault();

        holdActive = false;
        const holdEndTime = performance.now();
        const timeInSeconds = (holdEndTime - holdStartTime) / 1000.0;

        btn10secHold.classList.remove('active-hold');
        btn10secHold.innerText = "GESENDET";
        btn10secHold.disabled = true; // Sperren, damit man nur einmal drücken kann

        logDebug("Hold ended: " + timeInSeconds.toFixed(2) + "s");
        sendMessage({ type: "minigame_10sec_result", time: timeInSeconds });

        // Zurück zum Wait Screen wechseln
        showScreen('waiting');
    };

    // Touch
    btn10secHold.addEventListener('touchstart', startHold);
    btn10secHold.addEventListener('touchend', endHold);
    btn10secHold.addEventListener('touchcancel', endHold);

    // Mouse (Fallback für Desktop/Browser Tests)
    btn10secHold.addEventListener('mousedown', startHold);
    btn10secHold.addEventListener('mouseup', endHold);
    btn10secHold.addEventListener('mouseleave', endHold);
}

// Logic for Minigame Cookie Clickers
let cookieTotalClicks = 0;

function setCookieClickerState(enabled, statusText) {
    isCookieClickerEnabled = enabled;
    const mashArea = document.getElementById('btn-cookie-clickers-mash') || document.getElementById('btn-tip-fast-mash');
    const lockBadge = document.getElementById('cookie-lock-badge');
    const lockText = document.getElementById('cookie-lock-text');
    const lockIcon = document.getElementById('cookie-lock-icon');
    const subtitle = document.getElementById('cookie-subtitle');

    if (enabled) {
        if (mashArea) mashArea.classList.remove('disabled');
        if (lockBadge) {
            lockBadge.classList.remove('hidden');
            lockBadge.classList.add('go');
            if (lockIcon) lockIcon.textContent = '⚡';
            if (lockText) lockText.textContent = statusText || 'GO!';
            setTimeout(() => {
                if (isCookieClickerEnabled && lockBadge) {
                    lockBadge.classList.add('hidden');
                }
            }, 650);
        }
        if (subtitle) subtitle.textContent = "LOS GEHT'S! KLICKEN!";

        cookieClickersClicks = 0;
        tipFastClicks = 0;
        cookieTotalClicks = 0;
        const cookieCounter = document.getElementById('cookie-click-count');
        if (cookieCounter) cookieCounter.textContent = "0";

        if (cookieClickersInterval) clearInterval(cookieClickersInterval);
        if (tipFastInterval) clearInterval(tipFastInterval);
        cookieClickersInterval = setInterval(() => {
            if (cookieClickersClicks > 0 || cookieTotalClicks > 0) {
                sendMessage({
                    type: "cookie_clickers_clicks_batch",
                    clicks: cookieClickersClicks,
                    total_clicks: cookieTotalClicks
                });
                cookieClickersClicks = 0;
                tipFastClicks = 0;
            }
        }, 120);
        tipFastInterval = cookieClickersInterval;
    } else {
        if (mashArea) mashArea.classList.add('disabled');
        if (lockBadge) {
            lockBadge.classList.remove('hidden', 'go');
            if (lockIcon) lockIcon.textContent = '🔒';
            if (lockText) lockText.textContent = statusText || 'STOP!';
        }
        if (subtitle) {
            subtitle.textContent = (statusText === 'STOP!' || statusText === 'ZEIT UM!') ? "Zeit abgelaufen!" : "Bereit machen... Warten auf GO!";
        }

        // Vor dem Stoppen: Letzte gepufferte Klicks mit dem verbindlichen Gesamtzähler senden!
        if (cookieTotalClicks > 0 || cookieClickersClicks > 0) {
            sendMessage({
                type: "cookie_clickers_clicks_batch",
                clicks: cookieClickersClicks,
                total_clicks: cookieTotalClicks,
                is_final: true
            });
            cookieClickersClicks = 0;
            tipFastClicks = 0;
        }

        if (cookieClickersInterval) {
            clearInterval(cookieClickersInterval);
            cookieClickersInterval = null;
        }
        if (tipFastInterval) {
            clearInterval(tipFastInterval);
            tipFastInterval = null;
        }
    }
}

function spawnCookiePopFx() {
    const container = document.getElementById('cookie-click-particles');
    if (!container) return;
    const plusOne = document.createElement('div');
    plusOne.className = 'cookie-pop-plusone';
    plusOne.textContent = '+1';
    
    // Zufälliger leichter horizontaler / vertikaler Versatz vom Keks-Zentrum
    const offsetX = (Math.random() - 0.5) * 80;
    const offsetY = (Math.random() - 0.5) * 40;
    plusOne.style.left = `calc(50% + ${offsetX}px)`;
    plusOne.style.top = `calc(50% + ${offsetY}px)`;
    
    container.appendChild(plusOne);
    setTimeout(() => {
        if (plusOne.parentNode) plusOne.parentNode.removeChild(plusOne);
    }, 550);
}

const mashTargetBtn = btnCookieClickersMash || btnTipFastMash;
if (mashTargetBtn) {
    const handleMash = (e) => {
        if (e && e.cancelable) e.preventDefault(); // Prevent double calls or zooming
        if (!isCookieClickerEnabled) {
            // Noch im Countdown gesperrt -> Klicks ignorieren
            return;
        }

        // Haptic feedback (vibrate for 40ms)
        if (navigator.vibrate) {
            try { navigator.vibrate(40); } catch(err) {}
        }

        // Bouncy cookie pop animation
        const cookieGraphic = document.getElementById('cookie-graphic');
        if (cookieGraphic) {
            cookieGraphic.classList.add('pop');
            setTimeout(() => cookieGraphic.classList.remove('pop'), 50);
        }

        // Arcade floating "+1" FX
        spawnCookiePopFx();

        cookieTotalClicks++;
        const cookieCounter = document.getElementById('cookie-click-count');
        if (cookieCounter) {
            cookieCounter.textContent = cookieTotalClicks;
        }

        logDebug("Cookie Clicked! Total: " + cookieTotalClicks);
        cookieClickersClicks++; // Increment locally, will be batch-sent by interval
        tipFastClicks = cookieClickersClicks;
    };

    mashTargetBtn.addEventListener('touchstart', handleMash, { passive: false });
    mashTargetBtn.addEventListener('mousedown', handleMash);
}

// Character Selection Logic
const charStatus = document.getElementById('char-status');
const charGrid = document.getElementById('char-grid');

const availableCharacters = [
    { id: "Aaron", file: "sprites/spr_aaron_idle_1.png" },
    { id: "Anna", file: "sprites/spr_anna_idle_1.png" },
    { id: "Cedi", file: "sprites/spr_cedric_idle_1.png" },
    { id: "Finnja", file: "sprites/spr_finnja_idle_1.png" },
    { id: "Jan", file: "sprites/spr_jan_idle_1.png" },
    { id: "Janek", file: "sprites/spr_janek_idle_1.png" },
    { id: "Leonie", file: "sprites/spr_leonie_idle_1.png" },
    { id: "Lia", file: "sprites/spr_lia_idle_1.png" },
    { id: "Luca", file: "sprites/spr_luca_idle_1.png" },
    { id: "Marius", file: "sprites/spr_marius_idle_1.png" },
    { id: "Mikka", file: "sprites/spr_mikka_idle_1.png" },
    { id: "Miles", file: "sprites/spr_miles_idle_1.png" },
    { id: "Paul", file: "sprites/spr_paul_idle_1.png" },
    { id: "Simon", file: "sprites/spr_simon_idle_1.png" }
];

if (charGrid) {
    charGrid.innerHTML = '';
    availableCharacters.forEach(char => {
        const btn = document.createElement('button');
        btn.className = 'char-btn';
        btn.dataset.char = char.id;

        const img = document.createElement('img');
        img.src = `assets/characters/${char.file}`;
        img.alt = char.id;
        img.className = 'char-img';

        const span = document.createElement('span');
        span.innerText = char.id;

        btn.appendChild(img);
        btn.appendChild(span);

        btn.addEventListener('click', () => {
            logDebug("Character selected: " + char.id);
            if (charStatus) charStatus.innerText = "Ausgewählt: " + char.id + ". Warte auf andere Spieler...";

            document.querySelectorAll('.char-btn').forEach(b => b.classList.remove('selected'));
            btn.classList.add('selected');

            const charNameLower = char.id.toLowerCase() === "cedi" ? "cedric" : char.id.toLowerCase();
            const playJumpFallback = () => {
                const jumpAudio = document.getElementById('audio-jump');
                if (jumpAudio) {
                    jumpAudio.currentTime = 0;
                    jumpAudio.play().catch(e => console.log("Fallback audio failed:", e));
                }
            };

            const tryPlay = (url, fallback) => {
                const audio = new Audio(url);
                audio.play().catch(e => fallback());
            };

            // Try _select.wav -> _select.mp3 -> generic jump
            tryPlay(`assets/audio/sfx/characters/${charNameLower}_select.wav`, () => {
                tryPlay(`assets/audio/sfx/characters/${charNameLower}_select.mp3`, () => {
                    playJumpFallback();
                });
            });

            sendMessage({
                type: "select_character",
                character: char.id,
                player_id: myPlayerId
            });
        });

        charGrid.appendChild(btn);
    });
}

// =========================================================================
// ICE CLIMBERS REAL-TIME CONTROLLER (ARCADE RETRO D-PAD & JUMP BUTTON)
// =========================================================================
let icState = { left: false, right: false, jump: false, dir: 0 };

function setIceClimbersState(enabled, statusText, customBannerText) {
    isIceClimbersEnabled = enabled;
    const gamepad = document.getElementById('ic-gamepad-bottom');
    const lockBadge = document.getElementById('ic-lock-badge');
    const lockText = document.getElementById('ic-lock-text');
    const lockIcon = document.getElementById('ic-lock-icon');
    const bannerText = document.getElementById('ic-banner-text');

    if (enabled) {
        if (gamepad) gamepad.classList.remove('disabled');
        if (lockBadge) {
            lockBadge.classList.remove('hidden');
            lockBadge.classList.add('go');
            if (lockIcon) lockIcon.src = 'assets/icons/star.svg';
            if (lockText) lockText.textContent = statusText || 'GO!';
            setTimeout(() => {
                if (isIceClimbersEnabled && lockBadge) {
                    lockBadge.classList.add('hidden');
                }
            }, 650);
        }
        if (bannerText) bannerText.textContent = customBannerText || "Klettere nach oben! Nicht abstürzen!";
    } else {
        resetIceClimbersInput();
        if (gamepad) gamepad.classList.add('disabled');
        if (lockBadge) {
            lockBadge.classList.remove('hidden', 'go');
            if (lockIcon) lockIcon.src = 'assets/icons/lock.svg';
            if (lockText) lockText.textContent = statusText || 'READY';
        }
        if (bannerText) bannerText.textContent = customBannerText || "Bereithalten... Countdown läuft!";
    }
}

function resetIceClimbersInput() {
    icState.left = false;
    icState.right = false;
    icState.jump = false;
    icState.dir = 0;
    const knob = document.getElementById('ic-joystick-knob');
    if (knob) {
        knob.style.transition = 'transform 0.15s cubic-bezier(0.175, 0.885, 0.32, 1.275)';
        knob.style.transform = 'translateX(0px)';
        knob.classList.remove('active-touch');
    }
    const arrowLeft = document.querySelector('.ic-guide-left');
    const arrowRight = document.querySelector('.ic-guide-right');
    if (arrowLeft) arrowLeft.classList.remove('active');
    if (arrowRight) arrowRight.classList.remove('active');
    const btnJump = document.getElementById('ic-btn-jump');
    if (btnJump) btnJump.classList.remove('active-touch');
}

function sendIceClimbersInput() {
    if (!isIceClimbersEnabled) return;
    sendMessage({
        type: "ice_climbers_input",
        dir: icState.dir,
        jump: icState.jump,
        player_id: myPlayerId
    });
}

function setupIceClimbersControls() {
    const track = document.getElementById('ic-joystick-track');
    const knob = document.getElementById('ic-joystick-knob');
    const arrowLeft = document.querySelector('.ic-guide-left');
    const arrowRight = document.querySelector('.ic-guide-right');
    const btnJump = document.getElementById('ic-btn-jump');

    if (!track || !knob || !btnJump) return;

    let joystickTouchId = null;
    let isMouseDragging = false;
    let lastVibratedDir = 0;

    function updateJoystickPosition(clientX) {
        if (!isIceClimbersEnabled) return;
        const rect = track.getBoundingClientRect();
        const centerX = rect.left + rect.width * 0.5;
        const knobWidth = knob.offsetWidth || 66;
        const maxDist = Math.max(30, (rect.width - knobWidth) * 0.5 - 4);

        const deltaX = Math.max(-maxDist, Math.min(maxDist, clientX - centerX));
        knob.style.transition = 'none';
        knob.style.transform = `translateX(${deltaX}px)`;
        knob.classList.add('active-touch');

        const normX = deltaX / maxDist; // -1.0 bis +1.0
        let dir = 0.0;
        if (Math.abs(normX) >= 0.15) {
            // Nach Überwindung der Deadzone (15%) sanfte Skalierung bis zum Vollausschlag ab 60%
            if (Math.abs(normX) >= 0.60) {
                dir = Math.sign(normX) * 1.0;
            } else {
                dir = Math.sign(normX) * ((Math.abs(normX) - 0.15) / (0.60 - 0.15));
                dir = Math.round(dir * 100) / 100;
            }
        }

        const activeDirSign = (dir < -0.1) ? -1 : (dir > 0.1 ? 1 : 0);
        if (arrowLeft) arrowLeft.classList.toggle('active', activeDirSign === -1);
        if (arrowRight) arrowRight.classList.toggle('active', activeDirSign === 1);

        if (activeDirSign !== 0 && activeDirSign !== lastVibratedDir) {
            lastVibratedDir = activeDirSign;
            if (navigator.vibrate) try { navigator.vibrate(10); } catch(e) {}
        } else if (activeDirSign === 0) {
            lastVibratedDir = 0;
        }

        const changed = (icState.dir !== dir);
        icState.dir = dir;
        icState.left = dir < -0.1;
        icState.right = dir > 0.1;
        track.setAttribute('aria-valuenow', String(dir));

        if (changed) {
            sendIceClimbersInput();
        }
    }

    function releaseJoystick() {
        joystickTouchId = null;
        isMouseDragging = false;
        lastVibratedDir = 0;
        knob.style.transition = 'transform 0.15s cubic-bezier(0.175, 0.885, 0.32, 1.275)';
        knob.style.transform = 'translateX(0px)';
        knob.classList.remove('active-touch');
        if (arrowLeft) arrowLeft.classList.remove('active');
        if (arrowRight) arrowRight.classList.remove('active');
        track.setAttribute('aria-valuenow', '0');

        const changed = (icState.dir !== 0.0);
        icState.dir = 0.0;
        icState.left = false;
        icState.right = false;

        if (changed) {
            sendIceClimbersInput();
        }
    }

    // Touch Handling (Multi-touch fähig: Links Joystick, Rechts Jump)
    track.addEventListener('touchstart', (e) => {
        if (e.cancelable) e.preventDefault();
        if (joystickTouchId !== null) return;
        const touch = e.changedTouches[0];
        joystickTouchId = touch.identifier;
        updateJoystickPosition(touch.clientX);
    }, { passive: false });

    track.addEventListener('touchmove', (e) => {
        if (e.cancelable) e.preventDefault();
        for (let i = 0; i < e.changedTouches.length; i++) {
            if (e.changedTouches[i].identifier === joystickTouchId) {
                updateJoystickPosition(e.changedTouches[i].clientX);
                break;
            }
        }
    }, { passive: false });

    const onTouchEnd = (e) => {
        if (e.cancelable) e.preventDefault();
        for (let i = 0; i < e.changedTouches.length; i++) {
            if (e.changedTouches[i].identifier === joystickTouchId) {
                releaseJoystick();
                break;
            }
        }
    };
    track.addEventListener('touchend', onTouchEnd, { passive: false });
    track.addEventListener('touchcancel', onTouchEnd, { passive: false });

    // Maus-Handling (für PC / Browser-Tests)
    track.addEventListener('mousedown', (e) => {
        e.preventDefault();
        isMouseDragging = true;
        updateJoystickPosition(e.clientX);
    });

    window.addEventListener('mousemove', (e) => {
        if (isMouseDragging) {
            updateJoystickPosition(e.clientX);
        }
    });

    window.addEventListener('mouseup', () => {
        if (isMouseDragging) {
            releaseJoystick();
        }
    });

    // Jump Button Handling
    function setJump(active) {
        if (!isIceClimbersEnabled && active) return;
        const changed = (icState.jump !== active);
        icState.jump = active;
        btnJump.classList.toggle('active-touch', active);
        if (changed) {
            sendIceClimbersInput();
            if (active && navigator.vibrate) {
                try { navigator.vibrate(25); } catch(e) {}
            }
        }
    }

    btnJump.addEventListener('touchstart', (e) => {
        if (e.cancelable) e.preventDefault();
        setJump(true);
    }, { passive: false });
    btnJump.addEventListener('touchend', (e) => {
        if (e.cancelable) e.preventDefault();
        setJump(false);
    }, { passive: false });
    btnJump.addEventListener('touchcancel', (e) => {
        if (e.cancelable) e.preventDefault();
        setJump(false);
    }, { passive: false });

    btnJump.addEventListener('mousedown', (e) => {
        e.preventDefault();
        setJump(true);
    });
    btnJump.addEventListener('mouseup', (e) => {
        e.preventDefault();
        setJump(false);
    });
    btnJump.addEventListener('mouseleave', () => {
        if (icState.jump) {
            setJump(false);
        }
    });
}

// =========================================================================
// BET BUDDY EXTREME LOGIC
// =========================================================================
const betBuddyTopicTitle = document.getElementById('bet-buddy-topic-title');
const betBuddyPartnerName = document.getElementById('bet-buddy-partner-name');
const betBuddyInput = document.getElementById('bet-buddy-input');
const btnBetMinus = document.getElementById('btn-bet-minus');
const btnBetPlus = document.getElementById('btn-bet-plus');
const btnSubmitBet = document.getElementById('btn-submit-bet');
const betBuddyInputSec = document.getElementById('bet-buddy-input-section');
const betBuddySubmittedBox = document.getElementById('bet-buddy-submitted-box');
const betBuddyLockedVal = document.getElementById('bet-buddy-locked-value');
const betBuddySpectatorBox = document.getElementById('bet-buddy-spectator-box');
const betBuddySpecPlayer = document.getElementById('bet-buddy-spec-player');
const betBuddySpecCount = document.getElementById('bet-buddy-spec-count');

function setupBetBuddyScreen(msg) {
    if (betBuddyTopicTitle) betBuddyTopicTitle.textContent = msg.topic || "Thema";
    if (betBuddyPartnerName) betBuddyPartnerName.textContent = msg.partner_name || "Partner";
    
    if (msg.already_submitted) {
        if (betBuddyInputSec) betBuddyInputSec.style.display = 'none';
        if (betBuddySubmittedBox) {
            betBuddySubmittedBox.style.display = 'flex';
            if (betBuddyLockedVal) betBuddyLockedVal.textContent = msg.bet_val || 1;
        }
        if (betBuddySpectatorBox) betBuddySpectatorBox.style.display = 'none';
    } else {
        if (betBuddyInput) betBuddyInput.value = (msg.bet_val !== undefined && msg.bet_val > 0) ? msg.bet_val : "1";
        if (betBuddyInputSec) betBuddyInputSec.style.display = 'flex';
        if (betBuddySubmittedBox) betBuddySubmittedBox.style.display = 'none';
        if (betBuddySpectatorBox) betBuddySpectatorBox.style.display = 'none';
        if (btnSubmitBet) {
            btnSubmitBet.disabled = false;
            btnSubmitBet.textContent = "WETTE EINLOGGEN";
        }
    }
    showScreen('betBuddy');
}

function setupBetBuddySpectate(msg) {
    if (betBuddyTopicTitle) betBuddyTopicTitle.textContent = msg.topic || "Thema";
    if (betBuddyInputSec) betBuddyInputSec.style.display = 'none';
    if (betBuddySubmittedBox) betBuddySubmittedBox.style.display = 'none';
    if (betBuddySpectatorBox) betBuddySpectatorBox.style.display = 'flex';
    
    if (betBuddySpecPlayer) betBuddySpecPlayer.textContent = (msg.player_name || "Jemand") + " zählt auf!";
    if (betBuddySpecCount) betBuddySpecCount.textContent = "Noch " + (msg.remaining !== undefined ? msg.remaining : "") + " Begriffe";
    showScreen('betBuddy');
}

function updateBetBuddySpectatorTimer(msg) {
    if (betBuddySpecCount && msg.remaining !== undefined) {
        betBuddySpecCount.textContent = "Noch " + msg.remaining + " Begriffe";
    }
}

if (btnBetMinus && betBuddyInput) {
    btnBetMinus.addEventListener('click', () => {
        let val = parseInt(betBuddyInput.value) || 1;
        if (val > 1) betBuddyInput.value = val - 1;
    });
}
if (btnBetPlus && betBuddyInput) {
    btnBetPlus.addEventListener('click', () => {
        let val = parseInt(betBuddyInput.value) || 1;
        if (val < 99) betBuddyInput.value = val + 1;
    });
}
if (btnSubmitBet && betBuddyInput) {
    btnSubmitBet.addEventListener('click', () => {
        const val = Math.max(1, parseInt(betBuddyInput.value) || 1);
        sendMessage({
            type: "bet_buddy_submit",
            bet: val
        });
        if (btnSubmitBet) {
            btnSubmitBet.disabled = true;
            btnSubmitBet.textContent = "EINGELOGGT";
        }
        if (betBuddyInputSec) betBuddyInputSec.style.display = 'none';
        if (betBuddySubmittedBox) {
            betBuddySubmittedBox.style.display = 'flex';
            if (betBuddyLockedVal) betBuddyLockedVal.textContent = val;
        }
    });
}

setupIceClimbersControls();

// Start
initWebSocket();
