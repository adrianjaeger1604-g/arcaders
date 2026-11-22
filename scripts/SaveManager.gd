extends Node

signal save_created(filepath: String)
signal save_deleted(filepath: String)
signal game_loaded(filepath: String)

const SAVES_DIR = "user://saves"
const AUTOSAVE_FILENAME = "autosave.json"

var current_save_path: String = ""

func _ready():
	_ensure_save_dir()

func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		var err = DirAccess.make_dir_recursive_absolute(SAVES_DIR)
		if err != OK:
			print("SaveManager: Fehler beim Erstellen des Saves-Ordners: ", err)

func color_to_array(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]

func array_to_color(arr: Variant) -> Color:
	if arr is Array and arr.size() >= 4:
		return Color(arr[0], arr[1], arr[2], arr[3])
	elif arr is Dictionary and arr.has("r") and arr.has("g") and arr.has("b"):
		return Color(arr["r"], arr["g"], arr["b"], arr.get("a", 1.0))
	return Color.WHITE

func build_save_data(is_autosave: bool = false, custom_name: String = "") -> Dictionary:
	var dt = Time.get_datetime_dict_from_system()
	var formatted_date = "%02d.%02d.%04d %02d:%02d" % [dt.day, dt.month, dt.year, dt.hour, dt.minute]
	var unix_time = Time.get_unix_time_from_system()
	
	var display_name = custom_name
	if display_name.is_empty():
		if is_autosave:
			display_name = "Autosave"
		else:
			display_name = "Spielstand " + formatted_date
			
	# Serialisiere minigame_winners
	var serialized_winners = {}
	for k in NetworkManager.minigame_winners.keys():
		var val = NetworkManager.minigame_winners[k]
		if val is Color:
			serialized_winners[str(k)] = {
				"color": color_to_array(val),
				"points": 2
			}
		elif val is Dictionary:
			var c = val.get("color", Color.WHITE)
			var sel_c = val.get("selecting_color", null)
			serialized_winners[str(k)] = {
				"color": color_to_array(c) if c is Color else c,
				"points": val.get("points", 2),
				"selecting_color": color_to_array(sel_c) if sel_c is Color else null
			}
			
	# Serialisiere computed_teams
	var serialized_teams = []
	for team in NetworkManager.computed_teams:
		var team_copy = team.duplicate(true)
		if team_copy.has("color") and team_copy["color"] is Color:
			team_copy["color"] = color_to_array(team_copy["color"])
		if team_copy.has("players"):
			for p in team_copy["players"]:
				if not p.has("id"):
					for pid in NetworkManager.player_sessions.keys():
						if NetworkManager.player_sessions[pid].get("name") == p.get("name"):
							p["id"] = int(pid)
							break
		serialized_teams.append(team_copy)
		
	# Serialisiere player_sessions (alle als offline markieren fuer sauberen Reconnect nach dem Laden)
	var serialized_players = {}
	for p_id in NetworkManager.player_sessions.keys():
		var p_data = NetworkManager.player_sessions[p_id].duplicate(true)
		p_data["id"] = int(p_id)
		p_data["connected"] = false
		serialized_players[str(p_id)] = p_data
		
	# Berechne absolvierte Minispiele
	var played_count = NetworkManager.minigame_winners.size()
	
	# Sicherheits-Sync: Runden-Zähler darf niemals kleiner als die Anzahl beendeter Minispiele sein
	if NetworkManager.current_turn_number < played_count:
		NetworkManager.current_turn_number = played_count
	
	var save_data = {
		"version": 1,
		"game_session_id": NetworkManager.game_session_id,
		"timestamp": unix_time,
		"formatted_date": formatted_date,
		"display_name": display_name,
		"is_autosave": is_autosave,
		"played_minigames": played_count,
		"total_minigames": NetworkManager.minigames_count,
		"current_turn": NetworkManager.current_turn_number,
		"player_count": NetworkManager.player_sessions.size(),
		"team_count": NetworkManager.computed_teams.size(),
		
		"settings": {
			"quiz_questions_count": NetworkManager.quiz_questions_count,
			"minigames_count": NetworkManager.minigames_count,
			"team_assignment_mode": NetworkManager.team_assignment_mode,
			"quiz_anonymous_answers": NetworkManager.quiz_anonymous_answers
		},
		
		"board_state": {
			"board_layout": NetworkManager.board_layout,
			"minigame_winners": serialized_winners,
			"quiz_bonus_points": NetworkManager.quiz_bonus_points.duplicate(),
			"current_turn_number": NetworkManager.current_turn_number,
			"current_selecting_team_color": color_to_array(NetworkManager.current_selecting_team_color)
		},
		
		"teams": serialized_teams,
		"players": serialized_players
	}
	
	return save_data

func auto_save() -> String:
	_ensure_save_dir()
	var save_data = build_save_data(true, "Autosave")
	var filepath = SAVES_DIR + "/" + AUTOSAVE_FILENAME
	
	var file = FileAccess.open(filepath, FileAccess.WRITE)
	if not file:
		print("SaveManager: Konnte Autosave-Datei nicht schreiben: ", FileAccess.get_open_error())
		return ""
		
	var json_str = JSON.stringify(save_data, "\t")
	file.store_string(json_str)
	file.close()
	
	print("SaveManager: Autosave erfolgreich gespeichert (Runde ", save_data.current_turn, ") -> ", filepath)
	emit_signal("save_created", filepath)
	return filepath

func save_game(custom_name: String = "") -> String:
	_ensure_save_dir()
	var save_data = build_save_data(false, custom_name)
	var filename = "save_%d.json" % int(save_data.timestamp)
	var filepath = SAVES_DIR + "/" + filename
	
	var file = FileAccess.open(filepath, FileAccess.WRITE)
	if not file:
		print("SaveManager: Konnte Spielstand nicht schreiben: ", FileAccess.get_open_error())
		return ""
		
	var json_str = JSON.stringify(save_data, "\t")
	file.store_string(json_str)
	file.close()
	
	print("SaveManager: Spielstand erfolgreich gespeichert -> ", filepath)
	emit_signal("save_created", filepath)
	return filepath

func duplicate_save(filepath: String) -> String:
	_ensure_save_dir()
	if not FileAccess.file_exists(filepath):
		print("SaveManager: Zu duplizierende Datei existiert nicht: ", filepath)
		return ""
		
	var src_file = FileAccess.open(filepath, FileAccess.READ)
	if not src_file:
		print("SaveManager: Konnte Datei zum Duplizieren nicht öffnen: ", filepath)
		return ""
		
	var text = src_file.get_as_text()
	src_file.close()
	
	var json = JSON.new()
	if json.parse(text) != OK:
		print("SaveManager: JSON-Fehler beim Duplizieren: ", json.get_error_message())
		return ""
		
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return ""
		
	var copy_data: Dictionary = data.duplicate(true)
	copy_data["is_autosave"] = false
	
	var orig_date = str(copy_data.get("formatted_date", "Unbekannt"))
	if not orig_date.ends_with(" (Kopie)"):
		copy_data["formatted_date"] = orig_date + " (Kopie)"
		
	var orig_name = str(copy_data.get("display_name", "Spielstand"))
	if orig_name == "Autosave":
		copy_data["display_name"] = "Spielstand " + orig_date + " (Kopie)"
	elif not orig_name.ends_with(" (Kopie)"):
		copy_data["display_name"] = orig_name + " (Kopie)"
		
	var base_ts = int(Time.get_unix_time_from_system())
	var suffix = 1
	var new_filename = "save_%d.json" % base_ts
	var new_filepath = SAVES_DIR + "/" + new_filename
	while FileAccess.file_exists(new_filepath):
		new_filename = "save_%d_%d.json" % [base_ts, suffix]
		new_filepath = SAVES_DIR + "/" + new_filename
		suffix += 1
		
	copy_data["timestamp"] = base_ts + (suffix - 1) * 0.001
	
	var out_file = FileAccess.open(new_filepath, FileAccess.WRITE)
	if not out_file:
		print("SaveManager: Konnte Kopie nicht schreiben: ", FileAccess.get_open_error())
		return ""
		
	out_file.store_string(JSON.stringify(copy_data, "\t"))
	out_file.close()
	
	print("SaveManager: Spielstand dupliziert -> ", new_filepath)
	emit_signal("save_created", new_filepath)
	return new_filepath

func get_save_files() -> Array[Dictionary]:
	_ensure_save_dir()
	var saves: Array[Dictionary] = []
	
	var dir = DirAccess.open(SAVES_DIR)
	if not dir:
		return saves
		
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var filepath = SAVES_DIR + "/" + file_name
			var info = _read_save_header(filepath)
			if not info.is_empty():
				info["filepath"] = filepath
				info["filename"] = file_name
				saves.append(info)
		file_name = dir.get_next()
		
	# Sortiere absteigend nach Timestamp (neueste zuerst; Autosave an oberster Stelle wenn aktuell)
	saves.sort_custom(func(a, b):
		if a.get("is_autosave", false) and not b.get("is_autosave", false):
			# Falls Autosave ähnlich neu ist wie manueller Speicherstand, halte es oben
			if abs(a.get("timestamp", 0) - b.get("timestamp", 0)) < 2:
				return true
		return a.get("timestamp", 0) > b.get("timestamp", 0)
	)
	
	return saves

func _read_save_header(filepath: String) -> Dictionary:
	var file = FileAccess.open(filepath, FileAccess.READ)
	if not file:
		return {}
		
	var text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		return {}
		
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return {}
		
	# Liefere Zusammenfassung für die UI
	return {
		"display_name": data.get("display_name", "Spielstand"),
		"formatted_date": data.get("formatted_date", "Unbekannt"),
		"timestamp": data.get("timestamp", 0),
		"is_autosave": data.get("is_autosave", false),
		"played_minigames": data.get("played_minigames", 0),
		"total_minigames": data.get("total_minigames", 24),
		"current_turn": data.get("current_turn", 0),
		"player_count": data.get("player_count", 0),
		"team_count": data.get("team_count", 0)
	}

func delete_save(filepath: String) -> bool:
	if not FileAccess.file_exists(filepath):
		return false
		
	var dir = DirAccess.open(SAVES_DIR)
	if not dir:
		return false
		
	var filename = filepath.get_file()
	var err = dir.remove(filename)
	if err == OK:
		print("SaveManager: Spielstand gelöscht: ", filepath)
		emit_signal("save_deleted", filepath)
		return true
	else:
		print("SaveManager: Fehler beim Löschen von: ", filepath, " Code: ", err)
		return false

func load_game(filepath: String) -> bool:
	if not FileAccess.file_exists(filepath):
		print("SaveManager: Datei existiert nicht: ", filepath)
		return false
		
	var file = FileAccess.open(filepath, FileAccess.READ)
	if not file:
		print("SaveManager: Konnte Datei nicht oeffnen: ", filepath)
		return false
		
	var text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		print("SaveManager: JSON Parsing fehlgeschlagen: ", json.get_error_message())
		return false
		
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		print("SaveManager: Ungueltiges Format!")
		return false
		
	# 1. Settings wiederherstellen
	var settings = data.get("settings", {})
	NetworkManager.quiz_questions_count = int(settings.get("quiz_questions_count", 5))
	NetworkManager.minigames_count = int(settings.get("minigames_count", 24))
	NetworkManager.team_assignment_mode = str(settings.get("team_assignment_mode", "quiz_ranking"))
	NetworkManager.quiz_anonymous_answers = bool(settings.get("quiz_anonymous_answers", false))
	
	# 2. Board State wiederherstellen
	var board_state = data.get("board_state", {})
	NetworkManager.board_layout = board_state.get("board_layout", [])
	for b_idx in range(NetworkManager.board_layout.size()):
		if NetworkManager.board_layout[b_idx] == "res://scenes/minigames/MinigameTipFast.tscn":
			NetworkManager.board_layout[b_idx] = "res://scenes/minigames/MinigameCookieClickers.tscn"
	var turn_val = board_state.get("current_turn_number", data.get("current_turn", 0))
	NetworkManager.current_turn_number = int(turn_val)
	NetworkManager.current_selecting_team_color = array_to_color(board_state.get("current_selecting_team_color", [1,1,1,1]))
	NetworkManager.current_minigame_index = -1
	
	# Deserialisiere minigame_winners
	NetworkManager.minigame_winners.clear()
	var raw_winners = board_state.get("minigame_winners", {})
	for k in raw_winners.keys():
		var idx = int(k)
		var entry = raw_winners[k]
		if typeof(entry) == TYPE_DICTIONARY:
			var sel_c = entry.get("selecting_color", null)
			NetworkManager.minigame_winners[idx] = {
				"color": array_to_color(entry.get("color", [1,1,1,1])),
				"points": int(entry.get("points", 2)),
				"selecting_color": array_to_color(sel_c) if sel_c != null else Color(0, 0, 0, 0)
			}
		elif typeof(entry) == TYPE_ARRAY:
			NetworkManager.minigame_winners[idx] = array_to_color(entry)
			
	# Sicherheits-Sync: Runden-Zähler muss mindestens der Anzahl absolvierter Minispiele entsprechen
	if NetworkManager.current_turn_number < NetworkManager.minigame_winners.size():
		NetworkManager.current_turn_number = NetworkManager.minigame_winners.size()
		print("SaveManager: Runden-Zähler korrigiert auf: ", NetworkManager.current_turn_number)
		
	# quiz_bonus_points wiederherstellen
	NetworkManager.quiz_bonus_points.clear()
	var raw_bonus = board_state.get("quiz_bonus_points", {})
	if raw_bonus is Dictionary:
		for k in raw_bonus.keys():
			NetworkManager.quiz_bonus_points[int(k)] = int(raw_bonus[k])
			
	# 3. Players wiederherstellen (ZUERST, damit Teams die IDs und Namen matchen können!)
	NetworkManager.player_sessions.clear()
	var raw_players = data.get("players", {})
	var max_id = 0
	for p_id_str in raw_players.keys():
		var p_id = int(p_id_str)
		if p_id > max_id:
			max_id = p_id
		var p_entry = raw_players[p_id_str].duplicate(true)
		p_entry["id"] = p_id
		p_entry["score"] = int(p_entry.get("score", 0))
		p_entry["connected"] = false # Warten auf Smartphone Reconnect
		NetworkManager.player_sessions[p_id] = p_entry
		
	NetworkManager.next_player_id = int(max_id + 1)
	NetworkManager.game_locked = true # Keine neuen Spieler erlauben, nur Reconnects
	NetworkManager.game_session_id = int(data.get("game_session_id", randi() % 900000 + 100000))
	NetworkManager.current_game_state = "waiting"

	# 4. Teams wiederherstellen
	NetworkManager.computed_teams.clear()
	var raw_teams = data.get("teams", [])
	for team_data in raw_teams:
		var restored_team = team_data.duplicate(true)
		if restored_team.has("color"):
			restored_team["color"] = array_to_color(restored_team["color"])
		if restored_team.has("players"):
			for p in restored_team["players"]:
				var found_id = -1
				var p_name = str(p.get("name", "")).strip_edges().to_lower()
				# Zuerst nach Name in den aktiven player_sessions suchen
				for pid in NetworkManager.player_sessions.keys():
					if str(NetworkManager.player_sessions[pid].get("name", "")).strip_edges().to_lower() == p_name:
						found_id = int(pid)
						break
				# Fallback auf gespeicherte ID falls vorhanden
				if found_id == -1 and p.has("id"):
					found_id = int(p["id"])
				p["id"] = found_id
		NetworkManager.computed_teams.append(restored_team)
	current_save_path = filepath
	
	print("SaveManager: Spielstand erfolgreich geladen!")
	print(" - Datei: ", filepath)
	print(" - Game Session ID: ", NetworkManager.game_session_id)
	print(" - Spieler: ", NetworkManager.player_sessions.size(), " (alle auf 'connected=false' gesetzt für Reconnect)")
	print(" - Runden-Zähler: ", NetworkManager.current_turn_number)
	print(" - Bereits gewonnene Minispiele: ", NetworkManager.minigame_winners.size())
	
	# Handys informieren, dass der Spielstand geladen wurde
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting",
		"game_session_id": NetworkManager.game_session_id
	})
	
	emit_signal("game_loaded", filepath)
	
	# Direkt zum MainBoard wechseln (deferred, um SceneTree-Kollisionen zu vermeiden)
	get_tree().change_scene_to_file.call_deferred("res://scenes/MainBoard.tscn")
	return true
