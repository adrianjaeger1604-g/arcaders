extends Control

const MinigameResultHelper = preload("res://scripts/minigames/MinigameResultHelper.gd")
const ParticipantCardScene = preload("res://scenes/minigames/QuizParticipantCard.tscn")

@onready var scroll_container = $CenterContainer/VBox/ScrollContainer
@onready var players_list = $CenterContainer/VBox/ScrollContainer/CenterBox/PlayersList
@onready var result_list = $CenterContainer/VBox/ResultList
@onready var status_label = $CenterContainer/VBox/StatusLabel
@onready var title_label = $CenterContainer/VBox/Title
@onready var instruction_container = $CenterContainer/VBox/InstructionContainer
@onready var start_btn = $CenterContainer/VBox/StartGameButton
@onready var close_btn = $CenterContainer/VBox/CloseRoundButton
@onready var back_btn = $CenterContainer/VBox/BackButton
@onready var pixel_back_btn = get_node_or_null("PixelBackButton")

var is_round_open: bool = false
var player_times: Dictionary = {} # { player_id: time_in_seconds }
var participant_cards: Dictionary = {} # { player_id: QuizParticipantCard }

var video_background: VideoStreamPlayer = null
var gameplay_dim: ColorRect = null

func _ready():
	AudioManager.stop_music()
	_setup_gameplay_background()
	NetworkManager.message_received.connect(_on_message_received)
	NetworkManager.client_connected.connect(_on_client_reconnected)
	start_btn.pressed.connect(_on_start_pressed)
	close_btn.pressed.connect(_on_close_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	
	status_label.text = "Erkläre die Regeln... Warten auf Start."
	status_label.visible = false
	scroll_container.visible = false
	result_list.visible = false
	_connect_buttons_sfx(self)
	
	# Handys in der Warteschlange lassen
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})

func _setup_gameplay_background():
	var stream = null
	if ResourceLoader.exists("res://assets/minigames/10sec/10sec_background.ogv"):
		stream = load("res://assets/minigames/10sec/10sec_background.ogv")
	
	if stream != null:
		video_background = VideoStreamPlayer.new()
		video_background.name = "VideoBackground"
		video_background.set_anchors_preset(Control.PRESET_FULL_RECT)
		video_background.anchor_right = 1.0
		video_background.anchor_bottom = 1.0
		video_background.expand = true
		video_background.loop = true
		video_background.volume_db = -80.0
		video_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		video_background.stream = stream
		video_background.visible = false
		video_background.finished.connect(func():
			if is_instance_valid(video_background) and video_background.visible:
				video_background.play()
		)
		add_child(video_background)
		
		var insert_idx = 1
		var bg_tilemap = get_node_or_null("BackgroundTileMap")
		if bg_tilemap:
			insert_idx = bg_tilemap.get_index() + 1
		move_child(video_background, insert_idx)
		
		# Universelle Kontrast-Tönung für Video-Hintergrund gemäß Regel 5 & 6
		gameplay_dim = ColorRect.new()
		gameplay_dim.name = "GameplayDim"
		gameplay_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		gameplay_dim.anchor_right = 1.0
		gameplay_dim.anchor_bottom = 1.0
		gameplay_dim.color = Color(0.04, 0.03, 0.02, 0.40)
		gameplay_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gameplay_dim.visible = false
		add_child(gameplay_dim)
		move_child(gameplay_dim, insert_idx + 1)

func _connect_buttons_sfx(node: Node):
	if node is BaseButton:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func _on_start_pressed():
	var bg_tilemap = get_node_or_null("BackgroundTileMap")
	if bg_tilemap:
		bg_tilemap.visible = false
	if video_background:
		video_background.visible = true
		video_background.play()
	if gameplay_dim:
		gameplay_dim.visible = true
	if pixel_back_btn:
		pixel_back_btn.visible = true
		
	# UI-Wechsel auf In-Game Board
	title_label.text = "10 Sekunden Minispiel"
	title_label.add_theme_font_size_override("font_size", 48)
	instruction_container.visible = false
	
	status_label.text = "Haltet den Knopf auf dem Handy genau 10 Sekunden gedrückt!"
	status_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	status_label.visible = true
	status_label.modulate.a = 1.0
	
	start_btn.visible = false
	close_btn.visible = true
	back_btn.visible = false
	
	# Bereinige alte Karten und baue das klassische Teilnehmer-Grid auf
	for child in players_list.get_children():
		child.queue_free()
	for child in result_list.get_children():
		child.queue_free()
	participant_cards.clear()
	player_times.clear()
	result_list.visible = false
	
	var all_players = _get_all_players()
	var p_count = all_players.size()
	
	if p_count <= 4:
		players_list.columns = max(1, p_count)
	elif p_count <= 6:
		players_list.columns = 3
	else:
		players_list.columns = 4
		
	_update_scroll_container_height(p_count, players_list.columns)
	scroll_container.visible = true
	
	for p in all_players:
		var pid = p["id"]
		var card = ParticipantCardScene.instantiate()
		players_list.add_child(card)
		card.setup(p["name"], [p["character"]], p["team_color"])
		card.set_meta("player_id", pid)
		card.disabled = true
		participant_cards[pid] = card
		
	is_round_open = true
	
	# Jetzt das Minispiel auf den Handys starten
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "minigame_10sec"
	})

func _on_message_received(player_id: int, data: Dictionary):
	if data.get("type") == "minigame_10sec_result" and is_round_open:
		var time_taken = float(data.get("time", 0.0))
		player_times[player_id] = time_taken
		
		AudioManager.play_sfx("button_press")
		
		# Teilnehmer-Karte auf "Eingereicht!" setzen (weiß mit Team-Farbrahmen)
		var card = participant_cards.get(player_id)
		if card and is_instance_valid(card):
			card.set_state(1) # 1 = State.SUBMITTED -> Zeigt "Eingereicht!"
			
		var total_players = participant_cards.size()
		var submitted_count = player_times.size()
		status_label.text = "%d von %d Spielern haben losgelassen..." % [submitted_count, total_players]
		
		# Wenn alle Spieler abgegeben haben: Automatische kurze Verzögerung und Auswertung
		if submitted_count >= total_players and total_players > 0:
			var t = create_tween()
			t.tween_interval(0.8)
			t.tween_callback(func():
				if is_round_open:
					_on_close_pressed()
			)

func _on_close_pressed():
	if not is_round_open:
		return
	is_round_open = false
	close_btn.visible = false
	back_btn.visible = false
	title_label.text = "Ergebnis"
	
	# Handys in den Warten-Zustand versetzen
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})
	
	# Wechsle von Teilnehmer-Karten zur animierten Balken-Ansicht (wie im Qualifikationsquiz / Leaderboard)
	scroll_container.visible = false
	result_list.visible = true
	
	for child in result_list.get_children():
		child.queue_free()
	
	if player_times.is_empty():
		status_label.text = "Niemand hat losgelassen!"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		status_label.visible = true
		status_label.modulate.a = 1.0
		back_btn.visible = true
		return
		
	# Besten Spieler ermitteln (am nächsten an 10.0s)
	var best_player_id = -1
	var best_diff = 99999.0
	var best_time = 0.0
	
	for pid in player_times:
		var diff = abs(10.0 - player_times[pid])
		if diff < best_diff:
			best_diff = diff
			best_player_id = pid
			best_time = player_times[pid]
			
	# Höchste Zeit für Balken-Skalierung ermitteln (mindestens 10.0s)
	var max_scale_time = 10.0
	for pid in player_times:
		if player_times[pid] > max_scale_time:
			max_scale_time = player_times[pid]
			
	var all_players = _get_all_players()
	# Spieler in Join-Reihenfolge anzeigen (nach ID sortiert), wie im Leaderboard / TipFast
	all_players.sort_custom(func(a, b): return a["id"] < b["id"])
	
	# 1 Spalte zentriert für bis zu 4 Spieler, ab 5 Spieler 2 Spalten (Standard aus Leaderboard.gd)
	var is_two_cols = all_players.size() > 4
	result_list.columns = 2 if is_two_cols else 1
	result_list.add_theme_constant_override("v_separation", 16)
	result_list.add_theme_constant_override("h_separation", 36 if is_two_cols else 20)
	
	# Tatsächliche Dauer für den Anstieg der Balken ermitteln (synchron zum besten/weitesten Balken)
	var max_active_time = max(best_time, 0.0)
	for pid in player_times:
		if player_times[pid] > max_active_time:
			max_active_time = player_times[pid]
			
	var actual_rise_duration: float = 0.0
	if max_active_time > 0.0 and max_scale_time > 0.0:
		actual_rise_duration = clampf(MinigameResultHelper.RISE_DURATION * (max_active_time / max_scale_time), 0.6, MinigameResultHelper.RISE_DURATION)
	
	# Aufsteigender Spannungs-Sound synchron zu den Balken (nur so lange, wie der weiteste Balken steigt)
	if actual_rise_duration > 0.0:
		AudioManager.play_rising_sfx(actual_rise_duration)
	
	for p_data in all_players:
		_create_result_bar(p_data, is_two_cols, max_scale_time, best_player_id)
			
	# Gewinner-Team ermitteln & Punkte vergeben
	var winning_team = null
	for team in NetworkManager.computed_teams:
		for player in team.get("players", []):
			if _get_player_id(player) == best_player_id:
				winning_team = team
				break
		if winning_team != null:
			break
			
	if winning_team != null:
		var best_name = NetworkManager.player_sessions[best_player_id]["name"] if NetworkManager.player_sessions.has(best_player_id) else "Spieler"
		status_label.text = "Gewinner: %s (%s) mit %0.2f s!" % [best_name, winning_team["name"], best_time]
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
		status_label.modulate.a = 0.0
		status_label.visible = true
		
		var win_tween = create_tween()
		win_tween.tween_interval(actual_rise_duration + 0.1)
		win_tween.tween_callback(func():
			AudioManager.play_sfx("confetti-pop-sound-effect")
			if winning_team.has("players"):
				for p in winning_team["players"]:
					if p.has("character"):
						AudioManager.play_character_sfx(p["character"], "win")
		)
		win_tween.tween_property(status_label, "modulate:a", 1.0, 0.4)
		win_tween.tween_callback(func():
			back_btn.visible = true
		)
		
		# Punkte vergeben (+2 bzw. +3 wenn Wähler-Team)
		var points = 2
		if NetworkManager.current_selecting_team_color == winning_team["color"]:
			points = 3
			
		if NetworkManager.current_minigame_index != -1:
			NetworkManager.minigame_winners[NetworkManager.current_minigame_index] = {
				"color": winning_team["color"],
				"points": points,
				"selecting_color": NetworkManager.current_selecting_team_color
			}
			
			for p in winning_team.get("players", []):
				var pid = _get_player_id(p)
				if pid != -1 and NetworkManager.player_sessions.has(pid):
					NetworkManager.player_sessions[pid]["score"] += points
					
			print("Minigame 10Sec gewonnen von %s (+%d Punkte)" % [winning_team["name"], points])
	else:
		status_label.text = "Runde beendet!"
		status_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		status_label.modulate.a = 1.0
		status_label.visible = true
		back_btn.visible = true

func _create_result_bar(p_data: Dictionary, is_two_cols: bool, max_scale_time: float, best_player_id: int):
	var pid = p_data["id"]
	var p_name = p_data["name"]
	var team_color = p_data["team_color"]
	var character_name = p_data.get("character", "Cedi")
	var time_taken = player_times.get(pid, 0.0)
	var has_submitted = player_times.has(pid)
	
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10 if is_two_cols else 12)
	
	var left_box_w = 110 if is_two_cols else 130
	var bar_w = 320 if is_two_cols else 460
	
	# Left Content (Name + Character) - orientiert an Leaderboard.gd
	var left_box = HBoxContainer.new()
	left_box.alignment = BoxContainer.ALIGNMENT_CENTER
	left_box.custom_minimum_size = Vector2(left_box_w, 0)
	
	var char_name_vbox = VBoxContainer.new()
	char_name_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	char_name_vbox.custom_minimum_size = Vector2(left_box_w, 0)
	char_name_vbox.add_theme_constant_override("separation", 4)
	
	# Character Icon (im festen Control für zentrierte Ausrichtung und Sieger-Sprung)
	var char_holder = Control.new()
	char_holder.custom_minimum_size = Vector2(64, 64)
	char_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	var char_icon = TextureRect.new()
	char_icon.size = Vector2(64, 64)
	char_icon.position = Vector2.ZERO
	char_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	char_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	char_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if character_name == "" or not NetworkManager.character_textures.has(character_name):
		character_name = "Cedi"
	if NetworkManager.character_textures.has(character_name):
		char_icon.texture = NetworkManager.character_textures[character_name]
	char_holder.add_child(char_icon)
	char_name_vbox.add_child(char_holder)
	
	# Name Label direkt unter dem Charakter
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
	
	# Progress Bar Container in Teamfarbe
	var bar_data = MinigameResultHelper.create_styled_bar(max_scale_time, team_color, Vector2(bar_w, 40))
	var bar = bar_data["bar"]
	var score_label = bar_data["label"]
	score_label.text = "0.00 s"
	score_label.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.06, 0.96))
	score_label.add_theme_constant_override("outline_size", 6)
	row.add_child(bar_data["container"])
	
	# Symmetrischer Ausgleichs-Spacer rechts NUR bei 1 Spalte (wie im Leaderboard)
	if not is_two_cols:
		var right_spacer = MinigameResultHelper.create_balancing_spacer(left_box.custom_minimum_size.x)
		row.add_child(right_spacer)
		
	result_list.add_child(row)
	
	if not has_submitted or time_taken <= 0.0:
		score_label.text = "Nicht losgelassen"
		return
		
	# Synchrones Füllen des Balkens mit proportionaler Dauer
	var duration = MinigameResultHelper.RISE_DURATION * (time_taken / max_scale_time)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(bar, "value", time_taken, duration).set_trans(Tween.TRANS_LINEAR)
	tween.tween_method(func(val: float): score_label.text = "%0.2f s" % val, 0.0, time_taken, duration).set_trans(Tween.TRANS_LINEAR)
	
	# Kleiner Pop-Effekt wenn Ziel erreicht
	bar.pivot_offset = bar.custom_minimum_size / 2.0
	var pop = create_tween()
	pop.tween_interval(duration)
	pop.tween_property(bar, "scale", Vector2(1.06, 1.15), 0.08)
	pop.tween_property(bar, "scale", Vector2.ONE, 0.15)
	
	# Nach Erreichen des Ziels: Exakte Zeit + Abweichung anzeigen
	var diff = abs(10.0 - time_taken)
	var sign_str = "+" if time_taken >= 10.0 else "-"
	var end_text = "%0.2fs (%s%0.2fs)" % [time_taken, sign_str, diff]
	pop.tween_callback(func(): score_label.text = end_text)
	
	# Gewinner-Sprung & Feieranimation
	if pid == best_player_id:
		var t = create_tween()
		t.tween_interval(duration + 0.1)
		t.tween_callback(func(): MinigameResultHelper.celebrate_winner(char_icon, character_name))

func _get_all_players() -> Array:
	var list = []
	for pid in NetworkManager.player_sessions.keys():
		var p = NetworkManager.player_sessions[pid]
		var t_color = MinigameResultHelper.get_player_team_color(int(pid))
		list.append({
			"id": int(pid),
			"name": p.get("name", "Spieler %s" % str(pid)),
			"character": p.get("character", "Cedric"),
			"team_color": t_color
		})
	return list

func _update_scroll_container_height(count: int, columns: int):
	if not scroll_container:
		return
	var cols = max(1, columns)
	var rows = ceil(float(max(1, count)) / float(cols))
	if rows <= 1:
		scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll_container.custom_minimum_size.y = 220
		scroll_container.scroll_vertical = 0
	else:
		scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		var content_height = rows * 180 + max(0, rows - 1) * 16 + 32
		var max_height = 420
		scroll_container.custom_minimum_size.y = min(content_height, max_height)

func _get_player_id(player_dict: Dictionary) -> int:
	if player_dict.has("id"):
		return int(player_dict["id"])
	for pid in NetworkManager.player_sessions.keys():
		if NetworkManager.player_sessions[pid].get("name") == player_dict.get("name"):
			return int(pid)
	return -1

func _exit_tree():
	if video_background:
		video_background.stop()

func _on_back_pressed():
	if video_background:
		video_background.stop()
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
