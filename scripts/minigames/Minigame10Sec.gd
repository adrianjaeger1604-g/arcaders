extends Control

@onready var players_list = $CenterContainer/VBox/PlayersList
@onready var status_label = $CenterContainer/VBox/StatusLabel
@onready var start_btn = $CenterContainer/VBox/StartGameButton
@onready var close_btn = $CenterContainer/VBox/CloseRoundButton
@onready var back_btn = $CenterContainer/VBox/BackButton

var is_round_open = false
var player_times = {} # Speichert: { player_id: time_in_seconds }

func _ready():
	AudioManager.play_music("minigame_10sec")
	NetworkManager.message_received.connect(_on_message_received)
	NetworkManager.client_connected.connect(_on_client_reconnected)
	start_btn.pressed.connect(_on_start_pressed)
	close_btn.pressed.connect(_on_close_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	
	status_label.text = "Erkläre die Regeln... Warten auf Start."
	_connect_buttons_sfx(self)
	
	# Handys in der Warteschlange lassen
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})

func _connect_buttons_sfx(node: Node):
	if node is Button:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func _on_start_pressed():
	is_round_open = true
	start_btn.visible = false
	close_btn.visible = true
	status_label.text = "Spiel läuft!"
	
	# Jetzt das Minispiel auf den Handys starten
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "minigame_10sec"
	})

func _on_message_received(player_id, data):
	if data.get("type") == "minigame_10sec_result" and is_round_open:
		var time_taken = float(data.get("time", 0.0))
		player_times[player_id] = time_taken
		
		# Zeige an, dass der Spieler fertig ist, ohne die Zeit zu verraten
		var p_name = "Unbekannt"
		if NetworkManager.player_sessions.has(player_id):
			p_name = NetworkManager.player_sessions[player_id]["name"]
			
		_update_player_ui(player_id, p_name + " hat losgelassen!")

func _update_player_ui(p_id, text_to_show):
	var node_name = "Player_" + str(p_id)
	var existing_row = players_list.get_node_or_null(node_name)
	
	if existing_row != null:
		existing_row.queue_free()
		
	var row = HBoxContainer.new()
	row.name = node_name
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	
	var label = Label.new()
	label.text = text_to_show
	label.add_theme_font_size_override("font_size", 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(label)
	
	players_list.add_child(row)

func _create_result_row(p_id: int, time_str: String, best_id: int):
	var node_name = "Player_" + str(p_id)
	var existing_row = players_list.get_node_or_null(node_name)
	if existing_row != null:
		existing_row.queue_free()
		
	var p_name = NetworkManager.player_sessions[p_id]["name"] if NetworkManager.player_sessions.has(p_id) else "Unbekannt"
	
	var row = HBoxContainer.new()
	row.name = node_name
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	
	# Trophy
	var trophy_label = Label.new()
	trophy_label.text = "🏆" if p_id == best_id else ""
	trophy_label.add_theme_font_size_override("font_size", 32)
	trophy_label.custom_minimum_size = Vector2(40, 0)
	trophy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(trophy_label)
	
	# Character + Name Box
	var char_name_vbox = VBoxContainer.new()
	char_name_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var char_icon = TextureRect.new()
	char_icon.custom_minimum_size = Vector2(64, 64)
	char_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	char_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	char_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var character_name = ""
	if NetworkManager.player_sessions.has(p_id):
		character_name = NetworkManager.player_sessions[p_id].get("character", "")
	if NetworkManager.character_textures.has(character_name):
		char_icon.texture = NetworkManager.character_textures[character_name]
	char_name_vbox.add_child(char_icon)
	
	var name_label = Label.new()
	name_label.text = p_name
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_name_vbox.add_child(name_label)
	row.add_child(char_name_vbox)
	
	# Time Label
	var time_label = Label.new()
	time_label.text = time_str
	time_label.add_theme_font_size_override("font_size", 28)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(time_label)
	
	players_list.add_child(row)

func _on_close_pressed():
	is_round_open = false
	close_btn.visible = false
	back_btn.visible = true
	
	# Sage den Handys, dass sie warten sollen
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})
	
	if player_times.is_empty():
		status_label.text = "Niemand hat teilgenommen!"
		return
		
	# Finde den Gewinner (am nächsten an 10.0 dran)
	var best_player_id = -1
	var best_diff = 99999.0
	
	for p_id in player_times:
		var diff = abs(10.0 - player_times[p_id])
		if diff < best_diff:
			best_diff = diff
			best_player_id = p_id
			
	# Decke alle Zeiten auf mit detaillierter Ansicht
	for p_id in player_times:
		var time_str = "%.2f s" % player_times[p_id]
		var diff_str = "(Abweichung: %.2f s)" % abs(10.0 - player_times[p_id])
		
		var full_time_str = time_str + "  " + diff_str
		_create_result_row(p_id, full_time_str, best_player_id)
	
	# Gewinner-Team bestimmen
	var winning_team = null
	for team in NetworkManager.computed_teams:
		for player in team["players"]:
			if player["id"] == best_player_id:
				winning_team = team
				break
		if winning_team != null:
			break
			
	if winning_team != null:
		AudioManager.play_sfx("victory_jubel")
		var p_name = NetworkManager.player_sessions[best_player_id]["name"]
		status_label.text = "Gewinner: " + p_name + " (" + winning_team["name"] + ")!"
		# Färbe den Text in der entsprechenden Teamfarbe
		status_label.add_theme_color_override("font_color", winning_team["color"])
		
		# Punkt an das Team vergeben, indem wir das aktuelle Minispiel markieren
		if NetworkManager.current_minigame_index != -1:
			var points = 2
			if NetworkManager.current_selecting_team_color == winning_team["color"]:
				points = 3
			
			NetworkManager.minigame_winners[NetworkManager.current_minigame_index] = {
				"color": winning_team["color"],
				"points": points
			}
			
			for p in winning_team["players"]:
				var p_id = p["id"]
				if NetworkManager.player_sessions.has(p_id):
					NetworkManager.player_sessions[p_id]["score"] += points
					
			print("Minigame " + str(NetworkManager.current_minigame_index) + " gewonnen von " + winning_team["name"] + " (+" + str(points) + " Punkte)")
	else:
		status_label.text = "Kein Gewinner-Team ermittelt?"

func _on_back_pressed():
	AudioManager.play_music("intro")
	get_tree().change_scene_to_file("res://scenes/MainBoard.tscn")

func _on_client_reconnected(p_id: int, p_name: String):
	if is_round_open:
		NetworkManager.send_to_player(p_id, {
			"type": "state_change",
			"state": "minigame_10sec"
		})
	else:
		NetworkManager.send_to_player(p_id, {
			"type": "state_change",
			"state": "waiting"
		})
