extends Control

const MinigameResultHelper = preload("res://scripts/minigames/MinigameResultHelper.gd")

@onready var players_list = $CenterContainer/VBox/PlayersList
@onready var status_label = $CenterContainer/VBox/StatusLabel
@onready var start_btn = $CenterContainer/VBox/StartGameButton
@onready var close_btn = $CenterContainer/VBox/CloseRoundButton
@onready var back_btn = $CenterContainer/VBox/BackButton
@onready var pixel_back_btn = get_node_or_null("PixelBackButton")
@onready var bg_tilemap = get_node_or_null("BackgroundTileMap")

var gameplay_bg: TextureRect = null
var gameplay_dim: ColorRect = null

var phase = "intro" # intro -> countdown -> play -> end
var countdown_time = 3.0
var play_time_left = 15.0

var player_clicks = {} # Speichert: { player_id: int_click_count }
var round_timer: Timer

@onready var max_expected_clicks = 120 # Grobe Schätzung für UI-Balkenskalierung

func _load_texture_safe(res_path: String) -> Texture2D:
	if FileAccess.file_exists(res_path):
		var bytes = FileAccess.get_file_as_bytes(res_path)
		if not bytes.is_empty():
			var img = Image.new()
			if img.load_jpg_from_buffer(bytes) == OK or img.load_png_from_buffer(bytes) == OK:
				return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(res_path):
		var t = load(res_path)
		if t is Texture2D:
			return t
	return null

func _setup_gameplay_background():
	var tex = _load_texture_safe("res://assets/minigames/cookie_clickers/bakery_bg.jpg")
	if tex == null:
		tex = _load_texture_safe("res://assets/minigames/coockie_clickers/bakery_bg.jpg")
	if tex == null:
		tex = _load_texture_safe("res://assets/minigames/tip_fast/bakery_bg.jpg")
		
	gameplay_bg = TextureRect.new()
	gameplay_bg.name = "GameplayBackground"
	gameplay_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	gameplay_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gameplay_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	gameplay_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	gameplay_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gameplay_bg.texture = tex
	gameplay_bg.visible = false
	add_child(gameplay_bg)
	
	var insert_idx = 1
	if bg_tilemap:
		insert_idx = bg_tilemap.get_index() + 1
	move_child(gameplay_bg, insert_idx)
	
	# Tönung für optimalen Kontrast von Countdown, Timer & Spieler-Balken auf dem hellen Bäckerei-Hintergrund
	gameplay_dim = ColorRect.new()
	gameplay_dim.name = "GameplayDim"
	gameplay_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	gameplay_dim.color = Color(0.04, 0.03, 0.02, 0.45)
	gameplay_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gameplay_dim.visible = false
	add_child(gameplay_dim)
	move_child(gameplay_dim, insert_idx + 1)

func _ready():
	AudioManager.play_music("cookie_clickers")
	_setup_gameplay_background()
	NetworkManager.message_received.connect(_on_message_received)
	NetworkManager.client_connected.connect(_on_client_reconnected)
	start_btn.pressed.connect(_on_start_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	if pixel_back_btn:
		if "auto_return_to_main_board" in pixel_back_btn and pixel_back_btn.auto_return_to_main_board:
			# PixelBackButton führt cancel_and_return_to_board bereits selbstständig aus
			pass
		else:
			pixel_back_btn.pressed.connect(_on_back_pressed)
	_connect_buttons_sfx(self)
	
	status_label.text = "Erkläre die Regeln... Warten auf Start."
	status_label.visible = false
	players_list.visible = false
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
	if node is BaseButton:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func _on_start_pressed():
	AudioManager.play_music("cookie_clickers")
	if pixel_back_btn:
		pixel_back_btn.visible = true
	phase = "countdown"
	countdown_time = 3.0
	start_btn.visible = false
	status_label.visible = true
	status_label.text = "3"
	status_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	status_label.add_theme_font_size_override("font_size", 128)
	AudioManager.play_sfx("countdown_321go")
	
	# Knackige Outlines & Schatten für perfekte Lesbarkeit auf dem Bäckerei-Hintergrund
	status_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.84))
	status_label.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.02, 0.95))
	status_label.add_theme_constant_override("outline_size", 16)
	status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	status_label.add_theme_constant_override("shadow_offset_x", 4)
	status_label.add_theme_constant_override("shadow_offset_y", 4)
	
	# Bäckerei-Hintergrund nach der Erklärseite für das laufende Spiel aktivieren
	if bg_tilemap:
		bg_tilemap.visible = false
	if gameplay_bg:
		gameplay_bg.visible = true
	if gameplay_dim:
		gameplay_dim.visible = true
	
	# Initialisiere alle verbundenen Spieler mit 0 Klicks
	player_clicks.clear()
	for p_id in NetworkManager.player_sessions.keys():
		player_clicks[p_id] = 0
	
	# Handys bereits auf den Keks-Bildschirm schalten, aber DEAKTIVIERT!
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "minigame_cookie_clickers",
		"enabled": false,
		"countdown_text": "3"
	})
	round_timer.start()

	# Intro Explanation Screen Label & Title ausblenden
	$CenterContainer/VBox/Title.visible = false
	var inst_box = get_node_or_null("CenterContainer/VBox/InstructionContainer")
	if inst_box:
		inst_box.visible = false
	elif has_node("CenterContainer/VBox/Instruction"):
		$CenterContainer/VBox/Instruction.visible = false

func _on_timer_tick():
	if phase == "countdown":
		countdown_time -= 0.1
		var new_text = ""
		if countdown_time > 2.0:
			new_text = "3"
		elif countdown_time > 1.0:
			new_text = "2"
		elif countdown_time > 0.0:
			new_text = "1"
		else:
			new_text = "GO!"
			
		if new_text != "GO!" and new_text != status_label.text:
			status_label.text = new_text
			NetworkManager.broadcast({
				"type": "cookie_clickers_countdown",
				"countdown_text": new_text
			})
		elif new_text == "GO!" and phase == "countdown":
			phase = "play"
			play_time_left = 15.0
			status_label.text = "GO!"
			status_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
			status_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
			
			# Jetzt die Handys freischalten
			NetworkManager.broadcast({
				"type": "state_change",
				"state": "minigame_cookie_clickers",
				"enabled": true,
				"countdown_text": "GO!"
			})
			
	elif phase == "play":
		var prev_sec = ceil(play_time_left)
		play_time_left -= 0.1
		var curr_sec = ceil(play_time_left)
		if curr_sec != prev_sec and curr_sec >= 0:
			AudioManager.play_sfx("timer_tick")
			
		if play_time_left > 14.2:
			status_label.text = "GO!"
		else:
			status_label.text = "%.1f" % play_time_left
		
		if play_time_left <= 0:
			round_timer.stop()
			phase = "await_final"
			status_label.text = "STOP!"
			
			# Sofort Handys sperren und zur finalen Klick-Übermittlung auffordern
			NetworkManager.broadcast({
				"type": "state_change",
				"state": "minigame_cookie_clickers",
				"enabled": false,
				"countdown_text": "STOP!"
			})
			
			# Kurze Gnadenfrist (0.35s), damit die letzten WebSocket-Pakete der Handys garantiert eintreffen
			var timer = get_tree().create_timer(0.35)
			timer.timeout.connect(func():
				if phase == "await_final":
					phase = "end"
					_end_game()
			)

func _on_message_received(player_id, data):
	var msg_type = data.get("type", "")
	var is_click_msg = msg_type in [
		"cookie_clickers_click", "tip_fast_click", "cookie_clicker_click", "coockie_clickers_click",
		"cookie_clickers_clicks_batch", "tip_fast_clicks_batch", "cookie_clicker_clicks_batch", "coockie_clickers_clicks_batch"
	]
	if is_click_msg and (phase == "play" or phase == "await_final" or phase == "end"):
		if not player_clicks.has(player_id):
			player_clicks[player_id] = 0
			
		if data.has("total_clicks"):
			var tot = int(data.get("total_clicks", 0))
			if tot > player_clicks[player_id]:
				player_clicks[player_id] = tot
		else:
			var clicks_delta = int(data.get("clicks", 1))
			player_clicks[player_id] += clicks_delta

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

func _get_player_id(player_dict: Dictionary) -> int:
	if player_dict.has("id"):
		return int(player_dict["id"])
	for pid in NetworkManager.player_sessions.keys():
		if NetworkManager.player_sessions[pid].get("name") == player_dict.get("name"):
			return int(pid)
	return -1

func _end_game():
	$CenterContainer/VBox/Title.text = "Ergebnis"
	$CenterContainer/VBox/Title.visible = true
	$CenterContainer/VBox/Title.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.02, 0.95))
	$CenterContainer/VBox/Title.add_theme_constant_override("outline_size", 12)
	players_list.visible = true
	
	var inst_box = get_node_or_null("CenterContainer/VBox/InstructionContainer")
	if inst_box:
		inst_box.visible = false
	
	status_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	status_label.add_theme_font_size_override("font_size", 40)
	status_label.text = "ZEIT ABGELAUFEN!"
	status_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.84))
	status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	status_label.add_theme_constant_override("outline_size", 8)
	status_label.remove_theme_color_override("font_shadow_color")
	status_label.remove_theme_constant_override("shadow_offset_x")
	status_label.remove_theme_constant_override("shadow_offset_y")
	status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	status_label.add_theme_constant_override("shadow_offset_x", 0)
	status_label.add_theme_constant_override("shadow_offset_y", 0)
	close_btn.visible = false
	back_btn.visible = true
	
	# Sage den Handys, dass sie warten sollen
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})
	
	if player_clicks.is_empty():
		status_label.text = "Niemand hat teilgenommen!"
		status_label.modulate.a = 1.0
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
		
	# Spieler in Join-Reihenfolge anzeigen (nicht nach Klicks sortieren,
	# damit man nicht vorab sieht, wer gewonnen hat!)
	sorted_players.sort_custom(func(a, b): return a["id"] < b["id"])
	
	# 1 Spalte zentriert für bis zu 4 Spieler, ab 5 Spieler 2 Spalten (wie im Leaderboard)
	players_list.columns = 2 if sorted_players.size() > 4 else 1
	players_list.add_theme_constant_override("v_separation", 16)
	players_list.add_theme_constant_override("h_separation", 36 if players_list.columns == 2 else 20)
	
	var max_expected_clicks = max(1, best_clicks)
		
	# Aufsteigender Spannungs-Sound synchron zu den Balken
	if best_clicks > 0:
		AudioManager.play_rising_sfx(MinigameResultHelper.RISE_DURATION)
	
	var i = 0
	for p_data in sorted_players:
		_create_result_bar(p_data["id"], p_data["clicks"], i, best_player_id, max_expected_clicks)
		i += 1
	
	# Gewinner-Team bestimmen
	var winning_team = null
	for team in NetworkManager.computed_teams:
		for player in team.get("players", []):
			if _get_player_id(player) == best_player_id:
				winning_team = team
				break
		if winning_team != null:
			break
			
	if winning_team != null:
		var p_name = NetworkManager.player_sessions[best_player_id]["name"]
		status_label.text = "Gewinner: " + p_name + " (" + winning_team["name"] + ") mit " + str(best_clicks) + " Klicks!"
		status_label.add_theme_font_size_override("font_size", 38)
		status_label.add_theme_color_override("font_color", winning_team["color"])
		status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		status_label.add_theme_constant_override("outline_size", 10)
		status_label.remove_theme_color_override("font_shadow_color")
		status_label.remove_theme_constant_override("shadow_offset_x")
		status_label.remove_theme_constant_override("shadow_offset_y")
		status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		status_label.add_theme_constant_override("shadow_offset_x", 0)
		status_label.add_theme_constant_override("shadow_offset_y", 0)
		
		# Verstecke das Label initial, um es am Ende der Animation einzublenden (in reiner Teamfarbe ohne Farbstich)
		status_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
		
		var win_tween = create_tween()
		win_tween.tween_interval(MinigameResultHelper.RISE_DURATION + 0.1)
		win_tween.tween_callback(func(): 
			AudioManager.play_sfx("confetti-pop-sound-effect")
			if winning_team.has("players"):
				for p in winning_team["players"]:
					if p.has("character"):
						AudioManager.play_character_sfx(p["character"], "win")
		)
		win_tween.tween_property(status_label, "modulate:a", 1.0, 0.4)
		
		# Punkt an das Team vergeben
		if NetworkManager.current_minigame_index != -1:
			var points = 2
			if NetworkManager.current_selecting_team_color == winning_team["color"]:
				points = 3
			
			NetworkManager.minigame_winners[NetworkManager.current_minigame_index] = {
				"color": winning_team["color"],
				"points": points,
				"selecting_color": NetworkManager.current_selecting_team_color
			}
			
			for p in winning_team.get("players", []):
				var p_id = _get_player_id(p)
				if p_id != -1 and NetworkManager.player_sessions.has(p_id):
					NetworkManager.player_sessions[p_id]["score"] += points
					
			print("Minigame " + str(NetworkManager.current_minigame_index) + " gewonnen von " + winning_team["name"] + " (+" + str(points) + " Punkte)")
	else:
		status_label.text = "Kein Gewinner-Team ermittelt?"
		status_label.modulate.a = 1.0

func _create_result_bar(p_id: int, clicks: int, index: int, best_id: int, max_expected_clicks: int):
	var p_name = NetworkManager.player_sessions[p_id]["name"] if NetworkManager.player_sessions.has(p_id) else "Unbekannt"
	var team_color = MinigameResultHelper.get_player_team_color(p_id)
	var is_two_cols = players_list.columns == 2
	
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10 if is_two_cols else 12)
	
	var left_box_w = 110 if is_two_cols else 130
	var bar_w = 320 if is_two_cols else 460
	
	var left_box = HBoxContainer.new()
	left_box.alignment = BoxContainer.ALIGNMENT_CENTER
	left_box.custom_minimum_size = Vector2(left_box_w, 0)
	
	var char_name_vbox = VBoxContainer.new()
	char_name_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	char_name_vbox.custom_minimum_size = Vector2(left_box_w, 0)
	char_name_vbox.add_theme_constant_override("separation", 4)
	
	# Char Holder für freies Springen (ohne Layout-Verschiebung)
	var char_holder = Control.new()
	char_holder.custom_minimum_size = Vector2(64, 64)
	char_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var char_icon = TextureRect.new()
	char_icon.size = Vector2(64, 64)
	char_icon.position = Vector2.ZERO
	char_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	char_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	char_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	var character_name = ""
	if NetworkManager.player_sessions.has(p_id):
		character_name = NetworkManager.player_sessions[p_id].get("character", "")
	if character_name == "" or not NetworkManager.character_textures.has(character_name):
		character_name = "Cedi"
	if NetworkManager.character_textures.has(character_name):
		char_icon.texture = NetworkManager.character_textures[character_name]
	char_holder.add_child(char_icon)
	char_name_vbox.add_child(char_holder)
	
	var name_label = Label.new()
	name_label.text = p_name
	name_label.add_theme_font_size_override("font_size", 18 if is_two_cols else 22)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(left_box_w, 0)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	name_label.add_theme_constant_override("outline_size", 6)
	char_name_vbox.add_child(name_label)
	
	left_box.add_child(char_name_vbox)
	row.add_child(left_box)
	
	# Styled Progress Bar in Teamfarbe
	var bar_data = MinigameResultHelper.create_styled_bar(max_expected_clicks, team_color, Vector2(bar_w, 40))
	var bar = bar_data["bar"]
	var score_label = bar_data["label"]
	score_label.text = "0 Klicks"
	score_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	score_label.add_theme_constant_override("outline_size", 6)
	row.add_child(bar_data["container"])
	
	# Symmetrischer Ausgleichs-Spacer rechts NUR bei 1 Spalte
	if not is_two_cols:
		var right_spacer = MinigameResultHelper.create_balancing_spacer(left_box.custom_minimum_size.x)
		row.add_child(right_spacer)
	
	players_list.add_child(row)
	
	# Balken-Animation (alle starten synchron und steigen gleich schnell)
	var duration = MinigameResultHelper.RISE_DURATION * (float(clicks) / float(max_expected_clicks))
	if clicks > 0:
		var tween = create_tween().set_parallel(true)
		tween.tween_property(bar, "value", float(clicks), duration).set_trans(Tween.TRANS_LINEAR)
		tween.tween_method(func(val: float): score_label.text = str(int(round(val))) + " Klicks", 0.0, float(clicks), duration).set_trans(Tween.TRANS_LINEAR)
		
		# Pop-Effekt am Ende
		bar.pivot_offset = bar.custom_minimum_size / 2.0
		var pop = create_tween()
		pop.tween_interval(duration)
		pop.tween_property(bar, "scale", Vector2(1.06, 1.15), 0.08)
		pop.tween_property(bar, "scale", Vector2.ONE, 0.15)
	
	# Gewinner-Sprung (ohne Pokal!)
	if p_id == best_id:
		var t = create_tween()
		t.tween_interval(duration + 0.1)
		t.tween_callback(func(): MinigameResultHelper.celebrate_winner(char_icon, character_name))

func _on_back_pressed():
	AudioManager.stop_music()
	if NetworkManager.current_turn_number > 0:
		if NetworkManager.current_minigame_index == -1 or not NetworkManager.minigame_winners.has(NetworkManager.current_minigame_index):
			if not NetworkManager.is_replaying_minigame:
				NetworkManager.current_turn_number -= 1
	NetworkManager.is_replaying_minigame = false
	if not NetworkManager.minigame_winners.has(NetworkManager.current_minigame_index):
		NetworkManager.current_minigame_index = -1
	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/MainBoard.tscn")

func _on_client_reconnected(p_id: int, p_name: String):
	# Wenn ein Spieler während des Klickens wiederverbindet, schicken wir ihn direkt wieder auf den Klick-Bildschirm!
	if phase == "play":
		NetworkManager.send_to_player(p_id, {
			"type": "state_change",
			"state": "minigame_cookie_clickers",
			"enabled": true,
			"countdown_text": "GO!"
		})
	elif phase == "countdown":
		var current_text = status_label.text
		NetworkManager.send_to_player(p_id, {
			"type": "state_change",
			"state": "minigame_cookie_clickers",
			"enabled": false,
			"countdown_text": current_text
		})
	else:
		NetworkManager.send_to_player(p_id, {
			"type": "state_change",
			"state": "waiting"
		})
