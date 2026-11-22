extends Node

# Signal für andere Skripte, wenn eine Nachricht vom Handy kommt
signal client_connected(player_id, player_name)
signal client_disconnected(player_id)
signal message_received(player_id, data)
signal character_selected(player_id, character)
signal qr_code_ready(texture: ImageTexture)

# QR-Code Cache (damit alle Szenen sofort 0ms Ladezeit haben)
var cached_qr_texture: ImageTexture = null
var cached_qr_url: String = ""
var qr_is_fetching: bool = false
var cached_local_ip: String = ""

const PORT = 8080

var server := TCPServer.new()
# Speichert WebSocketPeers, Key = Peer-Objekt oder ID
var peers: Array[WebSocketPeer] = []

# Zuweisung von Peer zu Player ID
var peer_to_player_id = {}

# Speichert bekannte Spielerdaten nach ID: { 1: {"name": "Adri", "score": 0, "connected": true}, ... }
var player_sessions = {}
var next_player_id = 1
var game_session_id = randi() % 900000 + 100000

# Weltweit aktueller Spiel-Zustand, damit reconnectende Handys direkt das richtige UI sehen
var current_game_state = "waiting"
var current_question = ""

# Wird true, sobald die Charakterauswahl abgeschlossen ist. Danach koennen keine
# neuen Spieler mehr beitreten - nur bestehende Spieler duerfen sich wieder einloggen.
var game_locked = false

# Globale Einstellungen (Spieloptionen)
var quiz_questions_count = 5
var minigames_count = 24
var team_assignment_mode: String = "quiz_ranking" # "quiz_ranking" oder "manual"
var quiz_anonymous_answers: bool = false

# Charakter-Texturen vorausschauend laden
var character_textures = {
	"Aaron": preload("res://assets/characters/sprites/spr_aaron_idle_1.png"),
	"Anna": preload("res://assets/characters/sprites/spr_anna_idle_1.png"),
	"Cedi": preload("res://assets/characters/sprites/spr_cedric_idle_1.png"),
	"Cedric": preload("res://assets/characters/sprites/spr_cedric_idle_1.png"),
	"Finnja": preload("res://assets/characters/sprites/spr_finnja_idle_1.png"),
	"Jan": preload("res://assets/characters/sprites/spr_jan_idle_1.png"),
	"Janek": preload("res://assets/characters/sprites/spr_janek_idle_1.png"),
	"Leonie": preload("res://assets/characters/sprites/spr_leonie_idle_1.png"),
	"Lia": preload("res://assets/characters/sprites/spr_lia_idle_1.png"),
	"Luca": preload("res://assets/characters/sprites/spr_luca_idle_1.png"),
	"Marius": preload("res://assets/characters/sprites/spr_marius_idle_1.png"),
	"Mikka": preload("res://assets/characters/sprites/spr_mikka_idle_1.png"),
	"Miles": preload("res://assets/characters/sprites/spr_miles_idle_1.png"),
	"Paul": preload("res://assets/characters/sprites/spr_paul_idle_1.png"),
	"Simon": preload("res://assets/characters/sprites/spr_simon_idle_1.png")
}

# Phase 2 Status
var current_minigame_index = -1
var minigame_winners = {} # Dictionary mapping minigame_index -> team_color
var computed_teams = [] # Array von Dicts: [{ "name": "Team 1", "color": Color(...), "players": [p1, p2] }]
var quiz_bonus_points: Dictionary = {} # Mapping player_id (int) -> bonus_points (int: 3, 2, 1)
var current_turn_number = 0 # Strikter Runden-Zaehler fuer Teamauswahl
var current_selecting_team_color = Color(0, 0, 0, 0) # Farbe des auswaehlenden Teams
var is_replaying_minigame = false # Flag ob ein bereits gespieltes Spiel wiederholt wird

# Minigame Pool
var minigame_pool = [
	"res://scenes/minigames/Minigame10Sec.tscn",
	"res://scenes/minigames/MinigameCookieClickers.tscn",
	"res://scenes/minigames/MinigameFireEmblem.tscn",
	"res://scenes/minigames/MinigameIceClimbers.tscn",
	"res://scenes/minigames/MinigameHexagon.tscn",
	"res://scenes/minigames/MinigameBetBuddyExtreme.tscn",
	"res://scenes/minigames/MinigameSchmierig.tscn"
]
var board_layout = [] # Array of scene paths, index corresponds to card number

# Eingebauter HTTP-Server fuer controller-web (kein Python noetig)
const HTTP_PORT = 8000
const WEB_ROOT = "res://controller-web"
var http_server := TCPServer.new()
var http_clients: Array = [] # [{ "peer": StreamPeerTCP, "buf": String, "t": float }]

const MIME_TYPES = {
	"html": "text/html; charset=utf-8", "htm": "text/html; charset=utf-8",
	"js": "application/javascript; charset=utf-8", "css": "text/css; charset=utf-8",
	"json": "application/json", "png": "image/png", "jpg": "image/jpeg",
	"jpeg": "image/jpeg", "gif": "image/gif", "svg": "image/svg+xml",
	"ico": "image/x-icon", "webp": "image/webp", "mp3": "audio/mpeg",
	"wav": "audio/wav", "ogg": "audio/ogg", "woff": "font/woff", "woff2": "font/woff2",
	"ttf": "font/ttf", "otf": "font/otf"
}

func _ready():
	start_server()
	_start_local_web_server()

func _start_local_web_server():
	if http_server.listen(HTTP_PORT) != OK:
		printerr("Fehler: Konnte Web-Server nicht auf Port %d starten (Port belegt?)" % HTTP_PORT)
		return
	print("Web-Server laeuft auf http://%s:%d" % [get_local_ip(), HTTP_PORT])

func _process_http():
	while http_server.is_connection_available():
		var tcp = http_server.take_connection()
		tcp.set_no_delay(true)
		http_clients.append({"peer": tcp, "buf": "", "t": 0.0, "send_buf": PackedByteArray(), "send_pos": 0})

	for i in range(http_clients.size() - 1, -1, -1):
		var c = http_clients[i]
		var peer: StreamPeerTCP = c["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			http_clients.remove_at(i)
			continue
		c["t"] += get_process_delta_time()
		
		var s_buf: PackedByteArray = c["send_buf"]
		if not s_buf.is_empty():
			var s_pos: int = c["send_pos"]
			while s_pos < s_buf.size():
				var chunk_end = min(s_pos + 32768, s_buf.size())
				var res = peer.put_partial_data(s_buf.slice(s_pos, chunk_end))
				if res[0] != OK or int(res[1]) <= 0:
					break
				s_pos += int(res[1])
			c["send_pos"] = s_pos
			if s_pos >= s_buf.size() or c["t"] > 8.0:
				peer.disconnect_from_host()
				http_clients.remove_at(i)
			continue
			
		var avail = peer.get_available_bytes()
		if avail > 0:
			var res = peer.get_data(avail)
			if res[0] == OK:
				c["buf"] += (res[1] as PackedByteArray).get_string_from_utf8()
		if c["buf"].find("\r\n\r\n") != -1:
			_serve_http(c, c["buf"])
		elif c["t"] > 5.0:
			peer.disconnect_from_host()
			http_clients.remove_at(i)

func _serve_http(client_entry: Dictionary, request: String):
	var parts = request.get_slice("\r\n", 0).split(" ")
	var path = "/" if parts.size() < 2 else parts[1]
	path = path.get_slice("?", 0).get_slice("#", 0).uri_decode()
	if path.ends_with("/"):
		path += "index.html"
	if ".." in path:
		_queue_http(client_entry, 403, "text/plain", "Forbidden".to_utf8_buffer())
		return
	var file_path = WEB_ROOT + path
	if not FileAccess.file_exists(file_path):
		_queue_http(client_entry, 404, "text/plain", ("Not found: " + path).to_utf8_buffer())
		return
	var body = FileAccess.get_file_as_bytes(file_path)
	var mime = MIME_TYPES.get(file_path.get_extension().to_lower(), "application/octet-stream")
	_queue_http(client_entry, 200, mime, body)

func _queue_http(client_entry: Dictionary, code: int, mime: String, body: PackedByteArray):
	var status = {200: "OK", 403: "Forbidden", 404: "Not Found"}.get(code, "OK")
	var header = "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n" % [code, status, mime, body.size()]
	var full_pkt = header.to_utf8_buffer()
	full_pkt.append_array(body)
	client_entry["send_buf"] = full_pkt
	client_entry["send_pos"] = 0

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		http_server.stop()

func reset_for_new_game():
	print("NetworkManager: Vollstaendiger Reset fuer NEUES Spiel!")
	player_sessions.clear()
	peer_to_player_id.clear()
	next_player_id = 1
	game_session_id = randi() % 900000 + 100000
	current_game_state = "join"
	current_question = ""
	game_locked = false
	current_minigame_index = -1
	minigame_winners.clear()
	computed_teams.clear()
	quiz_bonus_points.clear()
	current_turn_number = 0
	current_selecting_team_color = Color(0, 0, 0, 0)
	is_replaying_minigame = false
	board_layout.clear()
	
	if SaveManager:
		SaveManager.current_save_path = ""
		
	# Alle verbundenen Handys informieren, dass ein komplett neues Spiel gestartet wurde
	broadcast({
		"type": "new_game_started",
		"game_session_id": game_session_id,
		"state": "join"
	})

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
	# Wenn die Teams im manuellen Modus bereits durch den Gamemaster festgelegt wurden,
	# behalten wir diese Zuweisung bei.
	if team_assignment_mode == "manual" and not computed_teams.is_empty():
		return

	computed_teams.clear()
	
	var players = []
	for p_id in player_sessions:
		var p_data = player_sessions[p_id].duplicate()
		p_data["id"] = p_id
		if p_data.get("character", "") == "" or p_data.get("character", "") == "unknown":
			p_data["character"] = "Cedi"
			player_sessions[p_id]["character"] = "Cedi"
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

func finalize_quiz_ranking_and_bonus():
	if team_assignment_mode == "manual":
		quiz_bonus_points.clear()
		
		var players = []
		for p_id in player_sessions.keys():
			var p = player_sessions[p_id].duplicate()
			p["id"] = int(p_id)
			players.append(p)
			
		# Sortiere Spieler absteigend nach Quiz-Punkten
		players.sort_custom(func(a, b): return a.get("score", 0) > b.get("score", 0))
		
		# Standard-Sport-Ranking mit Gleichstand-Behandlung (nur für Punkte > 0)
		for p in players:
			var s = p.get("score", 0)
			if s <= 0:
				continue
			var better_count = 0
			for other in players:
				if other.get("score", 0) > s:
					better_count += 1
			var rank = better_count + 1
			var bonus = 0
			if rank == 1:
				bonus = 3
			elif rank == 2:
				bonus = 2
			elif rank == 3:
				bonus = 1
				
			if bonus > 0:
				quiz_bonus_points[int(p["id"])] = bonus
				
		print("[NetworkManager] Quiz-Bonuspunkte für manuelle Teams berechnet: ", quiz_bonus_points)
		
		# Jedem Team die Bonuspunkte seiner Spieler als Start-Gesamtpunkte gutschreiben
		for team in computed_teams:
			var team_total = 0
			for tp in team.get("players", []):
				var pid = int(tp.get("id", -1))
				if pid != -1 and quiz_bonus_points.has(pid):
					team_total += quiz_bonus_points[pid]
					
			for tp in team.get("players", []):
				var pid = int(tp.get("id", -1))
				if pid != -1 and player_sessions.has(pid):
					player_sessions[pid]["score"] = team_total
					send_to_player(pid, {
						"type": "score_update",
						"score": team_total
					})
			print("[NetworkManager] Team '", team.get("name", ""), "' startet mit ", team_total, " Gesamtpunkten.")
	else:
		# Im Quiz-Ranking-Modus gibt es keine Start-Bonuspunkte, das Quiz diente nur der Teambildung
		quiz_bonus_points.clear()
		for pid in player_sessions.keys():
			player_sessions[pid]["score"] = 0
			send_to_player(pid, {
				"type": "score_update",
				"score": 0
			})
		print("[NetworkManager] Quiz-Ranking abgeschlossen: Alle Spieler starten Phase 2 mit 0 Punkten.")

func start_server():
	if server.listen(PORT) != OK:
		printerr("Fehler: Konnte WebSocket-Server nicht auf Port %d starten!" % PORT)
		return
	print("WebSocket Server laeuft auf Port %d" % PORT)

func _process(_delta):
	_process_http()
	# Akzeptiere neue TCP-Verbindungen
	if server.is_connection_available():
		var tcp_peer = server.take_connection()
		tcp_peer.set_no_delay(true) # Schaltet Nagles Algorithmus ab -> 0ms TCP-Buffering
		var ws_peer = WebSocketPeer.new()
		ws_peer.accept_stream(tcp_peer)
		peers.append(ws_peer)
		print("Neuer potenzieller Client verbunden")

	poll_network()

func _physics_process(_delta):
	# Poll auch im Physics-Loop, damit Echtzeit-Eingaben sofort im aktuellen Frame verarbeitet werden
	poll_network()

func poll_network():
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
			var client_session_id = int(data.get("game_session_id", 0))
			
			# Wenn das Handy eine alte Session-ID schickt und wir uns in einer neuen Spiel-Lobby befinden:
			if client_session_id != 0 and client_session_id != game_session_id and not game_locked:
				print("Client hat veraltete Game-Session-ID (%d vs %d) -> Sende new_game_started Reset" % [client_session_id, game_session_id])
				send_to_peer(peer, {
					"type": "new_game_started",
					"game_session_id": game_session_id,
					"state": "join"
				})
				return
				
			var player_name = data.get("name", "Unknown").strip_edges()
			
			# Falls dieser Peer vorher an eine andere Spieler-ID gebunden war:
			if peer_to_player_id.has(peer):
				var old_p_id = peer_to_player_id[peer]
				if old_p_id != -1 and player_sessions.has(old_p_id):
					player_sessions[old_p_id]["connected"] = false
				peer_to_player_id.erase(peer)
			
			# Prüfe, ob es schon eine Session mit diesem Namen gibt (Reconnect / Account-Wechsel, case-insensitive)
			var existing_id = -1
			for id in player_sessions.keys():
				if player_sessions[id]["name"].strip_edges().to_lower() == player_name.to_lower():
					existing_id = id
					break
			
			var p_id = -1
			if existing_id == -1 and game_locked:
				print("Join abgelehnt (Spiel laeuft bereits): ", player_name)
				send_to_peer(peer, {
					"type": "join_rejected",
					"reason": "Dieser Spieler existiert im aktuell laufenden Spiel nicht."
				})
				return
			if existing_id != -1:
				# Session gefunden -> Wiederanmeldung / Wechsel
				p_id = existing_id
				player_sessions[p_id]["connected"] = true
				player_sessions[p_id]["id"] = p_id
				print("Spieler RECONNECT / WECHSEL: ", player_name, " ID: ", p_id)
			else:
				# Neuer Spieler
				p_id = next_player_id
				next_player_id += 1
				player_sessions[p_id] = {
					"id": p_id,
					"name": player_name,
					"score": 0,
					"connected": true,
					"character": ""
				}
				print("Spieler NEU beigetreten: ", player_name, " ID: ", p_id)

			# Säubere alte/tote Peers, die noch dieser p_id zugeordnet waren
			for old_peer in peer_to_player_id.keys():
				if old_peer != peer and peer_to_player_id[old_peer] == p_id:
					peer_to_player_id.erase(old_peer)
			peer_to_player_id[peer] = p_id
			
			# Sende Bestätigung zurück. Dazu auch direkt den aktuellen State und die game_session_id
			var response = {
				"type": "join_accept",
				"player_id": p_id,
				"name": player_sessions[p_id]["name"],
				"game_session_id": game_session_id,
				"current_state": current_game_state,
				"question": current_question,
				"score": player_sessions[p_id]["score"]
			}
			send_to_peer(peer, response)
			emit_signal("client_connected", p_id, player_sessions[p_id]["name"])
			
		elif data.has("type") and data["type"] == "leave_game":
			var p_id = int(data.get("player_id", -1))
			if p_id == -1 and peer_to_player_id.has(peer):
				p_id = peer_to_player_id[peer]
			if p_id != -1 and player_sessions.has(p_id):
				var p_name = player_sessions[p_id].get("name", "Unbekannt")
				print("Spieler meldet sich ab (Session bleibt gespeichert): ", p_name, " ID: ", p_id)
				player_sessions[p_id]["connected"] = false
				peer_to_player_id.erase(peer)
				emit_signal("client_disconnected", p_id)
			send_to_peer(peer, { "type": "left_game_confirmed" })
			
		elif data.has("type") and data["type"] == "select_character":
			var p_id = int(data.get("player_id", -1))
			if p_id == -1 and peer_to_player_id.has(peer):
				p_id = peer_to_player_id[peer]
			if p_id != -1 and player_sessions.has(p_id):
				var chosen_char = data.get("character", "Cedi")
				if chosen_char == "" or chosen_char == "unknown":
					chosen_char = "Cedi"
				player_sessions[p_id]["character"] = chosen_char
				print("Spieler ", player_sessions[p_id]["name"], " hat Charakter gewaehlt: ", player_sessions[p_id]["character"])
				emit_signal("character_selected", p_id, player_sessions[p_id]["character"])
			else:
				print("ERR: Konnte select_character nicht zuordnen. p_id:", p_id, " player_sessions:", player_sessions)
				
		else:
			# Eine andere Nachricht (z.B. buzz, quiz_answer, ice_climbers_input)
			# Priorisiere immer den tatsächlich authentifizierten Peer:
			var p_id = peer_to_player_id.get(peer, -1)
			if p_id == -1 and data.has("player_id"):
				p_id = int(data["player_id"])
			emit_signal("message_received", p_id, data)

func send_to_peer(peer: WebSocketPeer, message_dict: Dictionary):
	if peer == null or peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var json_string = JSON.stringify(message_dict)
	peer.put_packet(json_string.to_utf8_buffer())
	peer.poll() # Erzwinge sofortiges Senden

func send_to_player(p_id: int, message_dict: Dictionary):
	for peer in peer_to_player_id.keys():
		if peer != null and peer_to_player_id[peer] == p_id:
			if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
				send_to_peer(peer, message_dict)
				break
			else:
				# Veralteten Peer aufräumen
				peer_to_player_id.erase(peer)

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
		if peer != null and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			peer.put_packet(pkt)
			peer.poll() # Erzwinge sofortiges Senden
			sent_count += 1
			
	if message_dict.has("type") and message_dict["type"] == "state_change":
		print("DEBUG: state_change '", current_game_state, "' broadcasted to ", sent_count, " peers.")

# ==============================================================================
#                      NETZWERK-IP & QR-CODE HELPER
# ==============================================================================

# Ermittelt die lokale IP stabil und dauerhaft konsistent
func get_local_ip() -> String:
	if cached_local_ip != "":
		return cached_local_ip
		
	var all_ips = IP.get_local_addresses()
	var candidates_192: Array[String] = []
	var candidates_10: Array[String] = []
	var candidates_172: Array[String] = []
	
	for ip in all_ips:
		# Nur IPv4
		if not ip.contains(".") or ip.contains(":"):
			continue
		if ip.ends_with(".1") or ip.ends_with(".255") or ip.begins_with("127."):
			continue
		# Virtuelle Interfaces ausschließen (VirtualBox 192.168.56.x, Windows Hotspot etc.)
		if ip.begins_with("192.168.56.") or ip.begins_with("192.168.137."):
			continue
			
		if ip.begins_with("192.168."):
			candidates_192.append(ip)
		elif ip.begins_with("10."):
			candidates_10.append(ip)
		elif ip.begins_with("172."):
			candidates_172.append(ip)
			
	# Priorität 1: Echtes Heimnetzwerk WLAN/LAN (192.168.x.x)
	if not candidates_192.is_empty():
		cached_local_ip = candidates_192[0]
		return cached_local_ip
	# Priorität 2: 10.x.x.x Firmen/Uni-Netzwerk
	if not candidates_10.is_empty():
		cached_local_ip = candidates_10[0]
		return cached_local_ip
	# Priorität 3: 172.x.x.x
	if not candidates_172.is_empty():
		cached_local_ip = candidates_172[0]
		return cached_local_ip
		
	cached_local_ip = "localhost"
	return cached_local_ip

# Gibt die einheitliche Web-Controller URL zurück (ohne dynamische Millisekunden)
func get_join_url() -> String:
	var ip = get_local_ip()
	return "http://" + ip + ":" + str(HTTP_PORT) + "/?ip=" + ip

# Liefert den QR Code sofort zurück (RAM-Cache oder Festplatten-Cache), oder fordert ihn einmalig an
func get_or_request_qr_code(http_req: HTTPRequest = null) -> ImageTexture:
	var current_url = get_join_url()
	
	# 1. Texture bereits im RAM?
	if cached_qr_texture != null and cached_qr_url == current_url:
		return cached_qr_texture
		
	# 2. Auf Festplatte als PNG zwischengespeichert?
	var cache_file_path = "user://cached_qr.png"
	var url_file_path = "user://cached_qr_url.txt"
	if FileAccess.file_exists(cache_file_path) and FileAccess.file_exists(url_file_path):
		var saved_url = FileAccess.get_file_as_string(url_file_path).strip_edges()
		if saved_url == current_url:
			var img = Image.new()
			if img.load(cache_file_path) == OK:
				cached_qr_texture = ImageTexture.create_from_image(img)
				cached_qr_url = current_url
				print("NetworkManager: QR Code blitzschnell (0ms) aus lokalem Festplatten-Cache geladen!")
				return cached_qr_texture
				
	# 3. Falls noch nicht gecacht: Im Hintergrund anfordern (nur einmal!)
	if http_req and not qr_is_fetching:
		qr_is_fetching = true
		cached_qr_url = current_url
		var api_url = "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=" + current_url.uri_encode()
		http_req.timeout = 5.0
		if not http_req.request_completed.is_connected(_on_internal_qr_completed):
			http_req.request_completed.connect(_on_internal_qr_completed)
		http_req.request(api_url)
		
	return null

func _on_internal_qr_completed(result, response_code, headers, body):
	qr_is_fetching = false
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var image = Image.new()
		if image.load_png_from_buffer(body) == OK:
			cached_qr_texture = ImageTexture.create_from_image(image)
			image.save_png("user://cached_qr.png")
			var f = FileAccess.open("user://cached_qr_url.txt", FileAccess.WRITE)
			if f:
				f.store_string(cached_qr_url)
				f.close()
			print("NetworkManager: QR Code erfolgreich geladen und fuer zukuenftige Starts gecacht!")
			emit_signal("qr_code_ready", cached_qr_texture)
			return
			
	print("NetworkManager: Warnung: Konnte QR Code von qrserver nicht laden (HTTP %s)." % str(response_code))
