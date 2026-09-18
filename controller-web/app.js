const screens = {
    connection: document.getElementById('connection-screen'),
    join: document.getElementById('join-screen'),
    characterSelect: document.getElementById('character-select-screen'),
    quiz: document.getElementById('quiz-screen'),
    buzzer: document.getElementById('buzzer-screen'),
    minigame10sec: document.getElementById('minigame-10sec-screen'),
    minigameTipFast: document.getElementById('minigame-tip-fast-screen'),
    waiting: document.getElementById('waiting-screen'),
};

const statusText = document.getElementById('status-text');
const btnJoin = document.getElementById('btn-join');
const playerNameInput = document.getElementById('player-name');
const btnSubmitAnswer = document.getElementById('btn-submit-answer');
const quizInput = document.getElementById('quiz-answer');
const btnBuzzer = document.getElementById('btn-buzzer');
const btn10secHold = document.getElementById('btn-10sec-hold');
const btnTipFastMash = document.getElementById('btn-tip-fast-mash');

let socket = null;
let myPlayerId = -1;
let myPlayerName = localStorage.getItem('playerName') || "";
let reconnectTimeout = null;

if (playerNameInput && myPlayerName) {
    playerNameInput.value = myPlayerName;
}

let tipFastClicks = 0;
let tipFastInterval = null;

function logDebug(msg) {
    const el = document.getElementById('debug-log');
    if (el) {
        el.innerHTML += `<div>[${new Date().toLocaleTimeString()}] ${msg}</div>`;
        el.scrollTop = el.scrollHeight;
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

function showScreen(screenName) {
    logDebug("Switching to: " + screenName);
    
    // Clear Tip Fast click batching if switching away
    if (screenName !== 'minigameTipFast') {
        if (tipFastInterval) {
            clearInterval(tipFastInterval);
            tipFastInterval = null;
        }
        tipFastClicks = 0;
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

    // Score-Anzeige nur beim Allgemeinwissen-Quiz anzeigen
    const scoreDisplay = document.getElementById('score-display');
    if (scoreDisplay) {
        if (screenName === 'quiz') {
            scoreDisplay.style.display = 'block';
        } else {
            scoreDisplay.style.display = 'none';
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
            sendMessage({ type: "join", name: myPlayerName });
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
        if (msg.state === "waiting") showScreen('waiting');
        else if (msg.state === "character_select") showScreen('characterSelect');
        else if (msg.state === "quiz") {
            document.getElementById('quiz-question').innerText = msg.question || "Neue Frage!";
            quizInput.value = "";
            showScreen('quiz');
        }
        else if (msg.state === "buzzer") showScreen('buzzer');
        else if (msg.state === "minigame_10sec") {
            // Button zurücksetzen
            if (btn10secHold) {
                btn10secHold.classList.remove('active-hold');
                btn10secHold.innerText = "HALTEN";
                btn10secHold.disabled = false;
            }
            showScreen('minigame10sec');
        }
        else if (msg.state === "minigame_tip_fast") {
            // Start click batching interval
            tipFastClicks = 0;
            if (tipFastInterval) clearInterval(tipFastInterval);
            tipFastInterval = setInterval(() => {
                if (tipFastClicks > 0) {
                    sendMessage({ type: "tip_fast_clicks_batch", clicks: tipFastClicks });
                    tipFastClicks = 0;
                }
            }, 200);
            showScreen('minigameTipFast');
        }
    }
    else if (msg.type === "join_accept") {
        myPlayerId = msg.player_id;

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
        else if (msg.current_state === "buzzer") showScreen('buzzer');
        else if (msg.current_state === "minigame_10sec") showScreen('minigame10sec');
        else if (msg.current_state === "minigame_tip_fast") {
            // Start click batching interval upon reconnecting/join_accept
            tipFastClicks = 0;
            if (tipFastInterval) clearInterval(tipFastInterval);
            tipFastInterval = setInterval(() => {
                if (tipFastClicks > 0) {
                    sendMessage({ type: "tip_fast_clicks_batch", clicks: tipFastClicks });
                    tipFastClicks = 0;
                }
            }, 200);
            showScreen('minigameTipFast');
        }
        else showScreen('waiting');
    }
    else if (msg.type === "score_update") {
        updateScore(msg.score);
    }
    else if (msg.type === "kicked") {
        alert("Du wurdest vom Spielleiter entfernt.");
        localStorage.removeItem('playerName');
        location.reload();
    }
}

// UI Event Listeners
const btnLogout = document.getElementById('btn-logout');
const btnToggleDebug = document.getElementById('btn-toggle-debug');
const debugLog = document.getElementById('debug-log');

if (btnToggleDebug && debugLog) {
    btnToggleDebug.addEventListener('click', () => {
        if (debugLog.style.display === 'none') {
            debugLog.style.display = 'block';
        } else {
            debugLog.style.display = 'none';
        }
    });
}

if (btnLogout) {
    btnLogout.addEventListener('click', () => {
        localStorage.removeItem('playerName');
        location.reload();
    });
    
    if (myPlayerName) {
        btnLogout.style.display = 'block';
    }
}

if (btnJoin && playerNameInput) {
    btnJoin.addEventListener('click', () => {
        const name = playerNameInput.value.trim();
        logDebug("Click Beitreten: " + name);
        if (name) {
            myPlayerName = name;
            localStorage.setItem('playerName', name);
            if (btnLogout) btnLogout.style.display = 'block';
            btnJoin.disabled = true;
            btnJoin.innerText = "Warte...";
            sendMessage({ type: "join", name: name });
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

// Logic for Minigame Tip Fast
if (btnTipFastMash) {
    const handleMash = (e) => {
        if (e) e.preventDefault(); // Prevent double calls or zooming

        // Haptic feedback (vibrate for 50ms)
        if (navigator.vibrate) {
            navigator.vibrate(50);
        }

        logDebug("Tip Fast Clicked!");
        tipFastClicks++; // Increment locally, will be batch-sent by interval
    };

    btnTipFastMash.addEventListener('touchstart', handleMash);
    btnTipFastMash.addEventListener('mousedown', handleMash);
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
    { id: "Leon", file: "sprites/spr_leon_idle_1.png" },
    { id: "Leonie", file: "sprites/spr_leonie_idle_1.png" },
    { id: "Lia", file: "sprites/spr_lia_idle_1.png" },
    { id: "Luca", file: "sprites/spr_luca_idle_1.png" },
    { id: "Marius", file: "sprites/spr_marius_idle_1.png" },
    { id: "Max", file: "sprites/spr_max_idle_1.png" },
    { id: "Mikka", file: "sprites/spr_mikka_idle_1.png" },
    { id: "Miles", file: "sprites/spr_miles_idle_1.png" },
    { id: "Mirja", file: "sprites/spr_mirja_idle_1.png" },
    { id: "Paul", file: "sprites/spr_paul_idle_1.png" }
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

// Start
initWebSocket();
