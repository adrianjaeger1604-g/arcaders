extends Control

@onready var players_list = $CenterContainer/VBox/PlayersList
@onready var status_label = $CenterContainer/VBox/StatusLabel
@onready var start_btn = $CenterContainer/VBox/StartGameButton
@onready var close_btn = $CenterContainer/VBox/CloseRoundButton
@onready var back_btn = $CenterContainer/VBox/BackButton

var phase = "intro" # intro -> countdown -> play -> end
var countdown_time = 3.0
var play_time_left = 15.0

var player_clicks = {} # Speichert: { player_id: int_click_count }
var round_timer: Timer

@onready var max_expected_clicks = 120 # Grobe Schätzung für UI-Balkenskalierung

func _ready():
	AudioManager.play_music("minigame_tip_fast")
	NetworkManager.message_received.connect(_on_message_received)
	NetworkManager.client_connected.connect(_on_client_reconnected)
	start_btn.pressed.connect(_on_start_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	_connect_buttons_sfx(self)
	
	status_label.text = "Erkläre die Regeln... Warten auf Start."
	# Handys in der Warteschlange lassen
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})
	
	round_timer = Timer.new()
	round_timer.timeout.connect(_on_timer_tick)
	round_timer.wait_time = 0.1 # Tick alle 100ms für smoothe Anzeige
	add_child(round_timer)

func _connect_buttons_sfx(node: Node):
	if node is Button:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func _on_start_pressed():
	phase = "countdown"
	countdown_time = 3.0
	start_btn.visible = false
	status_label.text = "Ready"
	status_label.add_theme_font_size_override("font_size", 128)
	
	# Handys in der Warteschlange lassen bis "Go!"
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})
	round_timer.start()

	# Intro Explanation Screen Label & Title ausblenden
	$CenterContainer/VBox/Title.visible = false
	$CenterContainer/VBox/Instruction.visible = false

func _on_timer_tick():
	if phase == "countdown":
		var prev_sec = ceil(countdown_time)
		countdown_time -= 0.1
		var curr_sec = ceil(countdown_time)
		if curr_sec != prev_sec and curr_sec >= 1:
			AudioManager.play_sfx("timer_tick")
		
		# Verwende ceil, um aus 2.9 -> 3 ("Ready"), 1.9 -> 2 ("Set"), 0.9 -> 1 ("Go!") zu machen
		var sec = ceil(countdown_time)
		
		if sec == 3:
			status_label.text = "Ready"
		elif sec == 2:
			status_label.text = "Set"
		elif sec == 1:
			status_label.text = "Go!"
			
		if countdown_time <= 0:
			phase = "play"
			play_time_left = 15.0
			status_label.text = "15.0"
			
			# Jetzt die Handys freischalten
			NetworkManager.broadcast({
				"type": "state_change",
				"state": "minigame_tip_fast"
			})
			
	elif phase == "play":
		var prev_sec = ceil(play_time_left)
		play_time_left -= 0.1
		var curr_sec = ceil(play_time_left)
		if curr_sec != prev_sec and curr_sec >= 0:
			AudioManager.play_sfx("timer_tick")
			
		status_label.text = "%.1f" % play_time_left
		
		if play_time_left <= 0:
			round_timer.stop()
			phase = "end"
			_end_game()

func _on_message_received(player_id, data):
	if data.get("type") == "tip_fast_click" and phase == "play":
		if not player_clicks.has(player_id):
			player_clicks[player_id] = 0
		player_clicks[player_id] += 1
	elif data.get("type") == "tip_fast_clicks_batch" and phase == "play":
		if not player_clicks.has(player_id):
			player_clicks[player_id] = 0
		player_clicks[player_id] += int(data.get("clicks", 0))

func _update_player_ui(p_id, text_to_show):
	var node_name = "Player_" + str(p_id)
	var label = players_list.get_node_or_null(node_name)
	
	if label == null:
		label = Label.new()
		label.name = node_name
		label.add_theme_font_size_override("font_size", 28)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		players_list.add_child(label)
		
	label.text = text_to_show

func _end_game():
	status_label.add_theme_font_size_override("font_size", 64)
	status_label.text = "ZEIT ABGELAUFEN!"
	close_btn.visible = false
	back_btn.visible = true
	
	# Sage den Handys, dass sie warten sollen
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})
	
	if player_clicks.is_empty():
		status_label.text = "Niemand hat teilgenommen!"
		return
		
	# Finde den Gewinner (Meiste Klicks)
	var best_player_id = -1
	var best_clicks = -1
	
	for p_id in player_clicks:
		var clicks = player_clicks[p_id]
		if clicks > best_clicks:
			best_clicks = clicks
			best_player_id = p_id
			
	# Update max_expected für Balkenskalierung
	max_expected_clicks = max(10, best_clicks)
			
	# Lösche alte Platzhalter
	for child in players_list.get_children():
		child.queue_free()
		
	# Zeige animierte Balken (Wie im Leaderboard)
	var sorted_players = []
	for p_id in player_clicks:
		sorted_players.append({"id": p_id, "clicks": player_clicks[p_id]})
		
	# Absteigend sortieren
	sorted_players.sort_custom(func(a, b): return a["clicks"] > b["clicks"])
	
	var i = 0
	for p_data in sorted_players:
		_create_result_bar(p_data["id"], p_data["clicks"], i, best_player_id)
		i += 1
	
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
		var p_name = NetworkManager.player_sessions[best_player_id]["name"]
		status_label.text = "Gewinner: " + p_name + " (" + winning_team["name"] + ") mit " + str(best_clicks) + " Klicks!"
		status_label.add_theme_color_override("font_color", winning_team["color"])
		
		# Verstecke das Label initial, um es am Ende der Animation einzublenden
		status_label.modulate.a = 0.0
		
		var max_delay = (0.3 * max(0, sorted_players.size() - 1)) + 5.2
		var win_tween = create_tween()
		win_tween.tween_interval(max_delay)
		win_tween.tween_property(status_label, "modulate:a", 1.0, 0.5)
		win_tween.tween_callback(func(): AudioManager.play_sfx("victory_jubel"))
		
		# Punkt an das Team vergeben
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

func _create_result_bar(p_id: int, clicks: int, index: int, best_id: int):
	var p_name = NetworkManager.player_sessions[p_id]["name"] if NetworkManager.player_sessions.has(p_id) else "Unbekannt"
	
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	
	var spacer_left = Control.new()
	spacer_left.custom_minimum_size = Vector2(0, 0)
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer_left)
	
	var left_box = HBoxContainer.new()
	left_box.alignment = BoxContainer.ALIGNMENT_END
	left_box.custom_minimum_size = Vector2(350, 0)
	left_box.add_theme_constant_override("separation", 15)
	
	var trophy_label = Label.new()
	trophy_label.text = "🏆" if p_id == best_id else ""
	trophy_label.add_theme_font_size_override("font_size", 32)
	trophy_label.custom_minimum_size = Vector2(40, 0)
	trophy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Pokal erst unsichtbar machen, wenn einer da ist
	if p_id == best_id:
		trophy_label.modulate.a = 0.0
	left_box.add_child(trophy_label)
	
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
	
	left_box.add_child(char_name_vbox)
	row.add_child(left_box)
	
	var bar_container = MarginContainer.new()
	bar_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(450, 40)
	bar.max_value = max_expected_clicks
	bar.value = 0
	bar.step = 1.0
	bar.show_percentage = false
	
	var style_bg = StyleBoxFlat.new()
	style_bg.bg_color = Color(0.2, 0.2, 0.2, 1)
	style_bg.corner_radius_top_left = 10
	style_bg.corner_radius_top_right = 10
	style_bg.corner_radius_bottom_right = 10
	style_bg.corner_radius_bottom_left = 10
	bar.add_theme_stylebox_override("background", style_bg)
	
	var style_fg = StyleBoxFlat.new()
	style_fg.bg_color = Color(0.2, 0.8, 0.2, 1) if p_id == best_id else Color(0.4, 0.4, 0.8, 1)
	style_fg.corner_radius_top_left = 10
	style_fg.corner_radius_top_right = 10
	style_fg.corner_radius_bottom_right = 10
	style_fg.corner_radius_bottom_left = 10
	bar.add_theme_stylebox_override("fill", style_fg)
	
	bar_container.add_child(bar)
	
	var score_label = Label.new()
	score_label.text = "0 Klicks"
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	score_label.add_theme_font_size_override("font_size", 24)
	bar_container.add_child(score_label)
	
	row.add_child(bar_container)
	
	var spacer_right = Control.new()
	spacer_right.custom_minimum_size = Vector2(350, 0)
	row.add_child(spacer_right)
	
	players_list.add_child(row)
	
	var tween = create_tween()
	tween.tween_interval(0.3 * index) # Stagger animation
	# Mach die Animation langsamer, z.B. 4.0 oder 5.0 Sekunden
	tween.tween_property(bar, "value", float(clicks), 5.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	var int_tween = create_tween()
	int_tween.tween_interval(0.3 * index)
	int_tween.tween_method(func(val: float): score_label.text = str(int(val)) + " Klicks", 0.0, float(clicks), 5.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Pokal am Ende der Animation einblenden
	if p_id == best_id:
		var trophy_tween = create_tween()
		# Warte, bis (0.3 * index) + 5.0 s Animation vorbei ist + minimaler "Suspense"-Delay
		trophy_tween.tween_interval((0.3 * index) + 5.2)
		trophy_tween.tween_property(trophy_label, "modulate:a", 1.0, 0.5)

func _on_back_pressed():
	AudioManager.play_music("intro")
	get_tree().change_scene_to_file("res://scenes/MainBoard.tscn")

func _on_client_reconnected(p_id: int, p_name: String):
	# Wenn ein Spieler während des Klickens wiederverbindet, schicken wir ihn direkt wieder auf den Klick-Bildschirm!
	if phase == "play":
		NetworkManager.send_to_player(p_id, {
			"type": "state_change",
			"state": "minigame_tip_fast"
		})
	else:
		NetworkManager.send_to_player(p_id, {
			"type": "state_change",
			"state": "waiting"
		})
