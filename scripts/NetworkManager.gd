extends Node

# Signal für andere Skripte, wenn eine Nachricht vom Handy kommt
signal client_connected(player_id, player_name)
signal client_disconnected(player_id)
signal message_received(player_id, data)
signal character_selected(player_id, character)

const PORT = 8080

var server := TCPServer.new()
# Speichert WebSocketPeers, Key = Peer-Objekt oder ID
var peers: Array[WebSocketPeer] = []

# Zuweisung von Peer zu Player ID
var peer_to_player_id = {}

# Speichert bekannte Spielerdaten nach ID: { 1: {"name": "Adri", "score": 0, "connected": true}, ... }
var player_sessions = {}
var next_player_id = 1

# Weltweit aktueller Spiel-Zustand, damit reconnectende Handys direkt das richtige UI sehen
var current_game_state = "waiting"
var current_question = ""

# Globale Einstellungen vom Startmenü
var quiz_questions_count = 5
var minigames_count = 24

# Charakter-Texturen vorausschauend laden
var character_textures = {
	"Aaron": preload("res://assets/characters/sprites/spr_aaron_idle_1.png"),
	"Anna": preload("res://assets/characters/sprites/spr_anna_idle_1.png"),
	"Cedi": preload("res://assets/characters/sprites/spr_cedric_idle_1.png"),
	"Finnja": preload("res://assets/characters/sprites/spr_finnja_idle_1.png"),
	"Jan": preload("res://assets/characters/sprites/spr_jan_idle_1.png"),
	"Janek": preload("res://assets/characters/sprites/spr_janek_idle_1.png"),
	"Leon": preload("res://assets/characters/sprites/spr_leon_idle_1.png"),
	"Leonie": preload("res://assets/characters/sprites/spr_leonie_idle_1.png"),
	"Lia": preload("res://assets/characters/sprites/spr_lia_idle_1.png"),
	"Luca": preload("res://assets/characters/sprites/spr_luca_idle_1.png"),
	"Marius": preload("res://assets/characters/sprites/spr_marius_idle_1.png"),
	"Max": preload("res://assets/characters/sprites/spr_max_idle_1.png"),
	"Mikka": preload("res://assets/characters/sprites/spr_mikka_idle_1.png"),
	"Miles": preload("res://assets/characters/sprites/spr_miles_idle_1.png"),
	"Mirja": preload("res://assets/characters/sprites/spr_mirja_idle_1.png"),
	"Paul": preload("res://assets/characters/sprites/spr_paul_idle_1.png")
}

# Phase 2 Status
var current_minigame_index = -1
var minigame_winners = {} # Dictionary mapping minigame_index -> team_color
var computed_teams = [] # Array von Dicts: [{ "name": "Team 1", "color": Color(...), "players": [p1, p2] }]
var current_turn_number = 0 # Strikter Runden-Zaehler fuer Teamauswahl
var current_selecting_team_color = Color(0, 0, 0, 0) # Farbe des auswaehlenden Teams

# Minigame Pool
var minigame_pool = [
	"res://scenes/minigames/Minigame10Sec.tscn",
	"res://scenes/minigames/MinigameTipFast.tscn",
	"res://scenes/minigames/VideoGameQuiz.tscn"
]
var board_layout = [] # Array of scene paths, index corresponds to card number

# PID for the auto-started local Web Server (controller-web)
var web_server_pid: int = -1

func _ready():
	start_server()
	_start_local_web_server()

func _start_local_web_server():
	var web_dir = ProjectSettings.globalize_path("res://controller-web")
	var os_name = OS.get_name()
	var python_cmd = "py" if os_name == "Windows" else "python3"
	
	print("Starte lokalen Web-Server auf Port 8000 in Verzeichnis: ", web_dir)
	web_server_pid = OS.create_process(python_cmd, ["-m", "http.server", "8000", "-d", web_dir])
	
	if web_server_pid != -1:
		print("Web-Server läuft. PID: ", web_server_pid)
	else:
		printerr("Fehler: Konnte den Web-Server nicht starten. Stelle sicher, dass Python installiert ist.")

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_stop_local_web_server()
		
func _stop_local_web_server():
	if web_server_pid != -1:
		print("Beende lokalen Web-Server (PID: ", web_server_pid, ")...")
		OS.kill(web_server_pid)
		web_server_pid = -1

func generate_board_layout():
	randomize()
	board_layout.clear()
	
	var available_pool = minigame_pool.duplicate()
	var total_cards = minigames_count
	
	for i in range(total_cards):
		if available_pool.size() > 0:
			# Pick a random game from the pool
			var random_index = randi() % available_pool.size()
			board_layout.append(available_pool[random_index])
			available_pool.remove_at(random_index)
		else:
			# Pool is empty, use placeholder
			board_layout.append("res://scenes/minigames/PlaceholderMinigame.tscn")
			
	# Shuffle the board layout so the order is random
	board_layout.shuffle()

func compute_teams():
	computed_teams.clear()
	
	var players = []
	for p_id in player_sessions:
		var p_data = player_sessions[p_id].duplicate()
		p_data["id"] = p_id
		players.append(p_data)
		
	players.sort_custom(func(a, b): return a.get("score", 0) > b.get("score", 0))
	
	var team_colors = [
		Color(0.95, 0.35, 0.35, 1), # Rot
		Color(0.35, 0.65, 1.0, 1), # Blau
		Color(0.35, 0.85, 0.45, 1), # Gruen
		Color(1.0, 0.9, 0.3, 1), # Gelb
		Color(0.75, 0.45, 0.95, 1), # Lila
		Color(1.0, 0.6, 0.25, 1)  # Orange
	]
	
	var team_color_names = [
		"Team Rot", "Team Blau", "Team Grün", 
		"Team Gelb", "Team Lila", "Team Orange"
	]
	
	var num_players = players.size()
	var team_index = 0
	
	for i in range(ceil(num_players / 2.0)):
		var team_data = {
			"name": team_color_names[team_index % team_color_names.size()],
			"color": team_colors[team_index % team_colors.size()],
			"players": []
		}
		
		# Player 1 (Bester)
		team_data["players"].append(players[i])
		
		# Player 2 (Schlechtester), falls nicht der Mittlere
		if i != (num_players - 1 - i):
			team_data["players"].append(players[num_players - 1 - i])
			
		computed_teams.append(team_data)
		team_index += 1

func start_server():
	if server.listen(PORT) != OK:
		printerr("Fehler: Konnte WebSocket-Server nicht auf Port %d starten!" % PORT)
		return
	print("WebSocket Server laeuft auf Port %d" % PORT)

func _process(delta):
	# Akzeptiere neue TCP-Verbindungen
	if server.is_connection_available():
		var tcp_peer = server.take_connection()
		var ws_peer = WebSocketPeer.new()
		ws_peer.accept_stream(tcp_peer)
		peers.append(ws_peer)
		print("Neuer potenzieller Client verbunden")

	# Verarbeite existierende Verbindungen
	# Rückwärts durchlaufen, damit wir peers entfernen können
	for i in range(peers.size() - 1, -1, -1):
		var peer = peers[i]
		peer.poll()
		
		var state = peer.get_ready_state()
		
		if state == WebSocketPeer.STATE_OPEN:
			while peer.get_available_packet_count() > 0:
				var packet = peer.get_packet()
				var packet_string = packet.get_string_from_utf8()
				#print("Raw packet: ", packet_string)
				_handle_packet(peer, packet_string)
				
		elif state == WebSocketPeer.STATE_CLOSED:
			print("Client getrennt. Code: ", peer.get_close_code(), ", Grund: ", peer.get_close_reason())
			peers.remove_at(i)
			
			# Finde heraus, welche Player ID das war
			if peer_to_player_id.has(peer):
				var p_id = peer_to_player_id[peer]
				peer_to_player_id.erase(peer)
				
				if player_sessions.has(p_id):
					player_sessions[p_id]["connected"] = false
					
				emit_signal("client_disconnected", p_id)

func _handle_packet(peer: WebSocketPeer, data_string: String):
	var json = JSON.new()
	var err = json.parse(data_string)
	if err != OK:
		print("JSON Parse Error: ", json.get_error_message())
		return
		
	var data = json.get_data()
	# Debugausgabe was wir überhaupt bekommen
	print("SERVER RCV: ", data)
	
	if typeof(data) == TYPE_DICTIONARY:
		if data.has("type") and data["type"] == "join":
			var player_name = data.get("name", "Unknown").strip_edges()
			
			# Prüfe, ob es schon eine Session mit diesem Namen gibt (Reconnect Logic)
			var existing_id = -1
			for id in player_sessions.keys():
				if player_sessions[id]["name"] == player_name:
					existing_id = id
					break
			
			var p_id = -1
			if existing_id != -1:
				# Session gefunden
				p_id = existing_id
				player_sessions[p_id]["connected"] = true
				print("Spieler RECONNECT: ", player_name, " ID: ", p_id)
			else:
				# Neuer Spieler
				p_id = next_player_id
				next_player_id += 1
				player_sessions[p_id] = {
					"name": player_name,
					"score": 0,
					"connected": true,
					"character": ""
				}
				print("Spieler NEU beigetreten: ", player_name, " ID: ", p_id)

			peer_to_player_id[peer] = p_id
			
			# Sende Bestätigung zurück. Dazu auch direkt den aktuellen State, 
			# damit die JS App gleich weiß, ob sie "waiting" oder etwas anderes ist.
			var response = {
				"type": "join_accept",
				"player_id": p_id,
				"current_state": current_game_state,
				"question": current_question,
				"score": player_sessions[p_id]["score"]
			}
			send_to_peer(peer, response)
			emit_signal("client_connected", p_id, player_name)
			
		elif data.has("type") and data["type"] == "select_character":
			var p_id = int(data.get("player_id", -1))
			if p_id != -1 and player_sessions.has(p_id):
				player_sessions[p_id]["character"] = data.get("character", "Cedric")
				print("Spieler ", player_sessions[p_id]["name"], " hat Charakter gewhlt: ", player_sessions[p_id]["character"])
				emit_signal("character_selected", p_id, player_sessions[p_id]["character"])
			else:
				print("ERR: Konnte select_character nicht zuordnen. p_id:", p_id, " player_sessions:", player_sessions)
				
		else:
			# Eine andere Nachricht (z.B. buzz, quiz_answer)
			var p_id = int(data.get("player_id", -1))
			emit_signal("message_received", p_id, data)

func send_to_peer(peer: WebSocketPeer, message_dict: Dictionary):
	var json_string = JSON.stringify(message_dict)
	peer.put_packet(json_string.to_utf8_buffer())
	peer.poll() # Erzwinge sofortiges Senden

func send_to_player(p_id: int, message_dict: Dictionary):
	for peer in peer_to_player_id.keys():
		if peer_to_player_id[peer] == p_id:
			if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
				send_to_peer(peer, message_dict)
			break

func kick_player(p_id: int):
	if player_sessions.has(p_id):
		# Client benachrichtigen
		send_to_player(p_id, {"type": "kicked"})
		
		# Verbindung schließen
		for peer in peer_to_player_id.keys():
			if peer_to_player_id[peer] == p_id:
				peer.close(1000, "Kicked")
				break
				
		# Session entfernen
		player_sessions.erase(p_id)
		emit_signal("client_disconnected", p_id)
		print("Spieler ", p_id, " wurde gekickt.")

func broadcast(message_dict: Dictionary):
	# Wenn wir den state broadcasten, sichern wir ihn intern für spätere Reconnects!
	if message_dict.has("type") and message_dict["type"] == "state_change":
		if message_dict.has("state"):
			current_game_state = message_dict["state"]
		if message_dict.has("question"):
			current_question = message_dict["question"]

	var json_string = JSON.stringify(message_dict)
	var pkt = json_string.to_utf8_buffer()
	var sent_count = 0
	for peer in peers:
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			peer.put_packet(pkt)
			peer.poll() # Erzwinge sofortiges Senden
			sent_count += 1
			
	if message_dict.has("type") and message_dict["type"] == "state_change":
		print("DEBUG: state_change '", current_game_state, "' broadcasted to ", sent_count, " peers.")

# Hilfsfunktion, um lokale IP zu bekommen
func get_local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			if not ip.ends_with(".1"): # oft Gateway
				return ip
	return "localhost"
