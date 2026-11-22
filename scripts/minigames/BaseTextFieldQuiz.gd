extends Control

const MinigameResultHelper = preload("res://scripts/minigames/MinigameResultHelper.gd")

@onready var title_label = $MarginContainer/VBoxContainer/Title
@onready var question_label = $MarginContainer/VBoxContainer/QuestionLabel
@onready var scroll_container = $MarginContainer/VBoxContainer/ScrollContainer
@onready var answers_list = $MarginContainer/VBoxContainer/ScrollContainer/CenterBox/AnswersList
@onready var close_round_btn = $MarginContainer/VBoxContainer/CloseRoundButton
@onready var next_round_btn = $MarginContainer/VBoxContainer/NextRoundButton
@onready var round_label = $MarginContainer/VBoxContainer/RoundLabel
@onready var answer_label = $MarginContainer/VBoxContainer/AnswerLabel
@onready var score_label = $MarginContainer/VBoxContainer/ScoreLabel
@onready var score_container = $MarginContainer/VBoxContainer/ScoreContainer
@onready var instruction_label = $MarginContainer/VBoxContainer/InstructionContainer/InstructionLabel if has_node("MarginContainer/VBoxContainer/InstructionContainer/InstructionLabel") else $MarginContainer/VBoxContainer/InstructionLabel
@onready var instruction_container = get_node_or_null("MarginContainer/VBoxContainer/InstructionContainer")
@onready var start_game_btn = $MarginContainer/VBoxContainer/StartGameButton
@onready var answers_title = $MarginContainer/VBoxContainer/AnswersTitle
@onready var spacer = $MarginContainer/VBoxContainer/Spacer
@onready var pixel_back_btn = get_node_or_null("PixelBackButton")

# Eigenschaften, die in vererbenden Scripts überschrieben werden
var quiz_title = "Quiz"
var quiz_instruction = "Lest die Frage und tippt die Antwort auf dem Handy ein. Das Team, das als erstes absendet, loggt die Antwort für das gesamte Team ein!"
var question_pool = []
var max_rounds = 7

var music_track = "quiz"
var is_round_open = false
var current_round = 0

# Trackt, welches Team in dieser Runde schon geantwortet hat: { TeamColor: PlayerID }
var answered_teams = {}
# Trackt die Punkte der Teams für dieses Minispiel: { TeamColor: Points }
var team_scores = {}
# Trackt, wem der GM Punkte in dieser Runde geben will: { TeamColor: Punkte }
var pending_points = {}
# Liste der gezogenen Fragen
var selected_questions = []

var sudden_death = false
var deathmatch_teams: Array = []

func _ready():
	AudioManager.play_random_quiz_music()
	NetworkManager.message_received.connect(_on_message_received)
	NetworkManager.client_connected.connect(_on_client_reconnected)
	close_round_btn.pressed.connect(_on_close_round_pressed)
	next_round_btn.pressed.connect(_on_next_round_pressed)
	
	title_label.text = quiz_title
	
	# Initialisiere Team-Scores
	for team in NetworkManager.computed_teams:
		team_scores[team["color"]] = 0
		
	# Initialisiere den Fragepool
	randomize()
	question_pool.shuffle()
	
	# Nimm genug Fragen für die Runden + Puffer für Sudden Death
	var needed_questions = min(max_rounds + 5, question_pool.size()) # 5 Fragen als Puffer
	selected_questions = question_pool.slice(0, needed_questions)
	
	instruction_label.text = quiz_instruction
	start_game_btn.pressed.connect(_on_start_game_pressed)
	
	# Verstecke Quiz-Elemente bis zum Start
	score_label.visible = false
	if score_container:
		score_container.visible = false
	round_label.visible = false
	question_label.visible = false
	answer_label.visible = false
	answer_label.modulate.a = 0.0
	answer_label.text = " "
	answers_title.visible = false
	if scroll_container:
		scroll_container.visible = false
	else:
		answers_list.visible = false
	if spacer:
		spacer.visible = false
	close_round_btn.visible = false
	next_round_btn.visible = false
	
	# Handys im Wartebildschirm lassen
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})
	_connect_buttons_sfx(self)

func _connect_buttons_sfx(node: Node):
	if node is BaseButton:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func _on_start_game_pressed():
	var bg_tilemap = get_node_or_null("BackgroundTileMap")
	if bg_tilemap:
		bg_tilemap.visible = false
	if has_node("CenterContainer/VBoxContainer"):
		$CenterContainer/VBoxContainer.add_theme_constant_override("separation", 12)
	if pixel_back_btn:
		pixel_back_btn.visible = true
	start_game_btn.visible = false
	if instruction_container:
		instruction_container.visible = false
	if instruction_label:
		instruction_label.visible = false
	
	score_label.visible = false
	if score_container:
		score_container.visible = true
	round_label.visible = true
	question_label.visible = true
	answer_label.visible = true
	answer_label.modulate.a = 0.0
	answer_label.text = " "
	answers_title.visible = true
	if scroll_container:
		scroll_container.visible = true
	else:
		answers_list.visible = true
	if spacer:
		spacer.visible = true
	
	_update_score_label()
	start_quiz_question()

func start_quiz_question():
	if current_round >= selected_questions.size():
		# Wir haben keine Fragen mehr übrig, auch nicht für Sudden Death. 
		# Wir beenden das Spiel unentschieden (oder wählen zufällig).
		print("Keine Fragen mehr im Pool! Beende Minispiel.")
		_end_minigame({})
		return
		
	var question_dict = selected_questions[current_round]
	var question_text = question_dict["q"]
	question_label.text = question_text
	
	if sudden_death:
		round_label.text = "DEATHMATCH!"
		round_label.add_theme_color_override("font_color", Color(1.0, 0.28, 0.28))
	else:
		round_label.text = "Runde %d / %d" % [current_round + 1, max_rounds]
		round_label.remove_theme_color_override("font_color")
	
	# Lösung unsichtbar halten, aber im Layout belassen gegen Springen
	answer_label.visible = true
	answer_label.modulate.a = 0.0
	answer_label.text = " "
	
	if scroll_container:
		scroll_container.scroll_vertical = 0
	
	# UI Reset für die neue Runde
	is_round_open = true
	answered_teams.clear()
	pending_points.clear()
	answers_title.text = "Warte auf Antworten..."
	
	# Lösche alte Antwort-Buttons
	for child in answers_list.get_children():
		child.queue_free()
		
	# Dynamische Spaltenanzahl für das Grid berechnen
	var t_count = NetworkManager.computed_teams.size()
	if t_count <= 4:
		answers_list.columns = max(1, t_count)
	elif t_count <= 6:
		answers_list.columns = 3
	else:
		answers_list.columns = 4
	_update_scroll_container_height(t_count, answers_list.columns)
		
	# Generiere Karten für alle Teams
	var card_scene = preload("res://scenes/minigames/QuizParticipantCard.tscn")
	for team in NetworkManager.computed_teams:
		var card = card_scene.instantiate()
		var t_name = team["name"]
		var t_color = team["color"]
		
		# Extrahiere die Charakter-Namen der Teammitglieder
		var chars = []
		for p in team["players"]:
			chars.append(p.get("character", "Cedric"))
			
		answers_list.add_child(card)
		card.setup(t_name, chars, t_color)
		card.set_meta("team_color", t_color)
		card.pressed.connect(func(): AudioManager.play_sfx("button_press"))
		card.pressed.connect(self._on_answer_button_pressed.bind(card))
		card.disabled = true # Gamemaster kann noch nicht klicken
		
		# Im Deathmatch: Nicht-teilnehmende Teams optisch dimmen
		if sudden_death and not _is_team_in_deathmatch(team):
			card.modulate = Color(0.4, 0.4, 0.4, 0.35)
		
	close_round_btn.visible = true
	next_round_btn.visible = false
	
	# Sende Handys den Befehl (im Deathmatch nur aktiven Teams die Frage zeigen!)
	for p_id in NetworkManager.player_sessions.keys():
		var team = _get_team_for_player(p_id)
		if sudden_death and not _is_team_in_deathmatch(team):
			NetworkManager.send_to_player(p_id, {
				"type": "state_change",
				"state": "inactive",
				"title": "DEATHMATCH",
				"message": "Deathmatch! Nur die führenden Teams spielen um den Sieg."
			})
		else:
			NetworkManager.send_to_player(p_id, {
				"type": "state_change",
				"state": "quiz",
				"question": question_text
			})
	
	# Sende jedem Spieler seinen aktuellen In-Game Team-Score separat zu
	for p_id in NetworkManager.player_sessions.keys():
		var team = _get_team_for_player(p_id)
		var current_score = 0
		if team != null and team_scores.has(team["color"]):
			current_score = team_scores[team["color"]]
		NetworkManager.send_to_player(p_id, {
			"type": "score_update",
			"score": current_score
		})
		
	is_round_open = true
	print("Quiz Frage gesendet!")

func _update_scroll_container_height(count: int, columns: int):
	if not scroll_container:
		return
	var cols = max(1, columns)
	var rows = ceil(float(max(1, count)) / float(cols))
	if rows <= 1:
		# Bei nur einer Zeile reicht der Platz vollkommen aus -> Scrollen komplett deaktivieren
		scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll_container.custom_minimum_size.y = 234
		scroll_container.scroll_vertical = 0
	else:
		scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		# 180px Kartenhöhe + 16px vertikaler Zwischenraum + 44px CenterBox-Margins + 10px Puffer
		var content_height = rows * 180 + max(0, rows - 1) * 16 + 54
		var max_height = 420 # Maximalhöhe ca. 2 Reihen von Boxen
		scroll_container.custom_minimum_size.y = min(content_height, max_height)

func _get_player_id(player_dict: Dictionary) -> int:
	if player_dict.has("id"):
		return int(player_dict["id"])
	for pid in NetworkManager.player_sessions.keys():
		if NetworkManager.player_sessions[pid].get("name") == player_dict.get("name"):
			return int(pid)
	return -1

func _get_team_for_player(p_id: int) -> Variant:
	for team in NetworkManager.computed_teams:
		for player in team.get("players", []):
			if _get_player_id(player) == p_id:
				return team
	return null

func _on_message_received(player_id, data):
	if data.get("type") == "quiz_answer" and is_round_open:
		var team: Variant = _get_team_for_player(player_id)
		if team == null:
			return
			
		if sudden_death and not _is_team_in_deathmatch(team):
			return # Inaktives Team darf im Deathmatch nicht teilnehmen!
			
		var team_color = team["color"]
		
		# Ein Team darf nur 1x antworten (der Schnellste gewinnt für das Team)
		if answered_teams.has(team_color):
			return
			
		answered_teams[team_color] = player_id
		
		# Sende allen Spielern dieses Teams sofort den Befehl, auf den Warten-Bildschirm zu wechseln!
		for p in team.get("players", []):
			var p_id = _get_player_id(p)
			if p_id != -1:
				NetworkManager.send_to_player(p_id, {
					"type": "state_change",
					"state": "waiting"
				})
		
		var answer = data.get("answer", "")
		var player_name = "Unbekannt"
		
		if NetworkManager.player_sessions.has(player_id):
			player_name = NetworkManager.player_sessions[player_id]["name"]
			
		print("Team ", team["name"], " (", player_name, ") antwortet: ", answer)
		
		# Finde die Karte des Teams und aktualisiere sie
		for card in answers_list.get_children():
			if card.has_meta("team_color") and card.get_meta("team_color") == team_color:
				if card.has_method("set_answer"):
					card.set_answer(player_name + ":\n" + answer)
				break

func _on_close_round_pressed():
	is_round_open = false
	close_round_btn.visible = false
	next_round_btn.visible = true
	answers_title.text = "Eingegangene Antworten (GM wählt Punkte):"
	
	# Lösung auf dem Monitor anzeigen (ohne Layout-Shift)
	var question_dict = selected_questions[current_round]
	answer_label.text = "Lösung: " + question_dict["a"]
	answer_label.visible = true
	answer_label.modulate.a = 1.0
	
	print("Runde geschlossen! Verteile nun Punkte.")
	# Sende allen Handys den "Warten" Befehl (falls sie noch tippen, ist es zu spät)
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})
	
	# Mache alle Antwort-Karten anklickbar und decke die Antworten auf
	for card in answers_list.get_children():
		if card.has_method("set_state"):
			card.disabled = false
			card.set_state(2) # 2 = REVEALED
			
func _on_answer_button_pressed(card: Button):
	if card.has_method("set_state") and not card.is_active:
		return # Keine Antwort abgegeben, kann nicht gepunktet werden
		
	var t_color = card.get_meta("team_color")
	
	# Toggle-Logik
	if pending_points.has(t_color) and pending_points[t_color] > 0:
		# Punkte wieder abziehen (Toggle aus)
		pending_points[t_color] = 0
		card.set_state(2) # 2 = REVEALED
		print("Punkte abgewählt für Team")
	else:
		# Punkte vergeben (Toggle an)
		pending_points[t_color] = 1
		card.set_state(3) # 3 = SELECTED
		print("Punkte ausgewählt für Team")

func _update_score_label():
	if score_container == null:
		return
		
	for child in score_container.get_children():
		child.queue_free()
		
	for team in NetworkManager.computed_teams:
		var t_color: Color = team.get("color", Color(1, 1, 1, 1))
		var t_name: String = team.get("name", "Team")
		var score: int = team_scores.get(t_color, 0)
		
		# Badge Container mit Team-Rahmen
		var badge = PanelContainer.new()
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.09, 0.14, 0.9)
		style.border_color = t_color
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		style.content_margin_left = 18
		style.content_margin_right = 18
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		badge.add_theme_stylebox_override("panel", style)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		
		# Farbiger Indikator-Punkt in Teamfarbe
		var dot = ColorRect.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.color = t_color
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(dot)
		
		# Team-Name in Teamfarbe
		var name_lbl = Label.new()
		name_lbl.text = t_name
		name_lbl.add_theme_color_override("font_color", t_color)
		name_lbl.add_theme_font_size_override("font_size", 22)
		name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		name_lbl.add_theme_constant_override("outline_size", 4)
		hbox.add_child(name_lbl)
		
		# Eleganter vertikaler Trenner
		var sep = ColorRect.new()
		sep.custom_minimum_size = Vector2(2, 18)
		sep.color = Color(1, 1, 1, 0.25)
		sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(sep)
		
		# Punktestand in hellem Weiß
		var score_lbl = Label.new()
		score_lbl.text = str(score) + " Pkt"
		score_lbl.add_theme_color_override("font_color", Color.WHITE)
		score_lbl.add_theme_font_size_override("font_size", 24)
		score_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		score_lbl.add_theme_constant_override("outline_size", 4)
		hbox.add_child(score_lbl)
		
		badge.add_child(hbox)
		
		# Im Deathmatch: Nicht-teilnehmende Teams werden oben im Punktestand ausgegraut!
		if sudden_death and not _is_team_in_deathmatch(team):
			badge.modulate = Color(0.4, 0.4, 0.4, 0.45)
		else:
			badge.modulate = Color(1.0, 1.0, 1.0, 1.0)
			
		score_container.add_child(badge)

func _is_team_in_deathmatch(team: Variant) -> bool:
	if not sudden_death:
		return true
	if team == null:
		return false
	var t_col = team.get("color", Color.BLACK)
	for dt in deathmatch_teams:
		if dt.get("color", Color.WHITE) == t_col:
			return true
	return false

func _on_next_round_pressed():
	# Punkte verrechnen
	for t_color in pending_points.keys():
		var punkte = pending_points[t_color]
		if punkte > 0:
			team_scores[t_color] += punkte
	
	_update_score_label()
			
	current_round += 1
	
	# Prüfen, ob Spiel zu Ende ist
	if current_round >= max_rounds:
		_check_winner()
	else:
		print("Starte nächste Runde...")
		start_quiz_question()

func _check_winner():
	var max_score = -1
	var winning_teams = []
	
	for team in NetworkManager.computed_teams:
		var s = team_scores[team["color"]]
		if s > max_score:
			max_score = s
			winning_teams = [team]
		elif s == max_score:
			winning_teams.append(team)
			
	if winning_teams.size() == 1:
		# Eindeutiger Gewinner
		var winner = winning_teams[0]
		print("Quiz beendet! Gewinner ist ", winner["name"])
		_end_minigame(winner)
	else:
		# Unentschieden -> Deathmatch
		print("Unentschieden! Deathmatch gestartet.")
		sudden_death = true
		deathmatch_teams = winning_teams.duplicate()
		max_rounds += 1 # Eine weitere Runde hinzufügen
		_update_score_label()
		start_quiz_question()

func _end_minigame(winning_team: Variant):
	question_label.text = "Quiz beendet!"
	answers_title.visible = false
	answer_label.visible = false
	score_label.visible = false
	if score_container:
		score_container.visible = false
		
	var max_score_possible = 1
	var best_score = 0
	for team in NetworkManager.computed_teams:
		var s = team_scores.get(team["color"], 0)
		if s > max_score_possible:
			max_score_possible = s
		if s > best_score:
			best_score = s
	max_score_possible = max(1, max_score_possible)
	
	var actual_rise_duration: float = 0.0
	if best_score > 0 and max_score_possible > 0:
		actual_rise_duration = clampf(MinigameResultHelper.RISE_DURATION * (float(best_score) / float(max_score_possible)), 0.6, MinigameResultHelper.RISE_DURATION)
	
	if winning_team != null and typeof(winning_team) == TYPE_DICTIONARY and not winning_team.is_empty():
		round_label.text = "Gewinner: " + winning_team["name"] + "!"
		round_label.add_theme_color_override("font_color", winning_team["color"])
		round_label.modulate.a = 0.0
		
		var title_tween = create_tween()
		title_tween.tween_interval(actual_rise_duration + 0.1)
		title_tween.tween_callback(func():
			AudioManager.play_sfx("confetti-pop-sound-effect")
			if winning_team.has("players"):
				for p in winning_team["players"]:
					if p.has("character"):
						AudioManager.play_character_sfx(p["character"], "win")
		)
		title_tween.tween_property(round_label, "modulate:a", 1.0, 0.4)
		
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
		round_label.text = "Unentschieden (Keine Fragen mehr)"
		
	next_round_btn.visible = false
	close_round_btn.visible = false
	
	# Alle auf Warten setzen
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})
	
	# --- LEADERBOARD AUFBAUEN ---
	for child in answers_list.get_children():
		child.queue_free()
		
	var sorted_teams = []
	for team in NetworkManager.computed_teams:
		sorted_teams.append(team)
	
	var cols = 2 if sorted_teams.size() > 1 else 1
	answers_list.columns = cols
	answers_list.add_theme_constant_override("v_separation", 16)
	answers_list.add_theme_constant_override("h_separation", 40 if cols == 2 else 60)
	
	# Dynamische Höhe der Scrollbox für das Endergebnis
	if scroll_container:
		scroll_container.clip_contents = false
		var num_rows = ceil(float(sorted_teams.size()) / float(cols))
		var needed_h = num_rows * 64 + max(0, num_rows - 1) * 16 + 24 + 44
		if num_rows <= 1:
			# Bei nur einer Zeile an Teams ist kein Scrollen nötig
			scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			scroll_container.custom_minimum_size.y = max(needed_h, 160)
		else:
			scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			scroll_container.custom_minimum_size.y = clamp(needed_h, 220, 560)
		scroll_container.scroll_vertical = 0
	
	# Aufsteigender Spannungs-Sound synchron zu den Balken (nur so lange, wie der Sieger-Balken steigt)
	if actual_rise_duration > 0.0:
		AudioManager.play_rising_sfx(actual_rise_duration)
	
	var i = 0
	for team in sorted_teams:
		var target_score = team_scores.get(team["color"], 0)
		var t_color = team["color"]
		
		var row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 16)
		
		var left_box_w = 200 if cols == 2 else 300
		var bar_w = 300 if cols == 2 else 450
		
		var left_box = HBoxContainer.new()
		left_box.alignment = BoxContainer.ALIGNMENT_CENTER
		left_box.custom_minimum_size = Vector2(left_box_w, 0)
		
		var team_char_data = []
		var players = team.get("players", [])
		
		if players.size() <= 1:
			var player_p = players[0] if players.size() > 0 else null
			var p_name = player_p.get("name", team.get("name", "Team")) if player_p != null else team.get("name", "Team")
			var c_name = player_p.get("character", "") if player_p != null else ""
			if c_name == "" or not NetworkManager.character_textures.has(c_name):
				c_name = "Cedi"
				
			var char_name_vbox = VBoxContainer.new()
			char_name_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			char_name_vbox.custom_minimum_size = Vector2(left_box_w, 0)
			char_name_vbox.add_theme_constant_override("separation", 4)
			
			var char_holder = Control.new()
			char_holder.custom_minimum_size = Vector2(48, 48)
			char_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			
			var char_icon = TextureRect.new()
			char_icon.size = Vector2(48, 48)
			char_icon.position = Vector2.ZERO
			char_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			char_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			char_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			if NetworkManager.character_textures.has(c_name):
				char_icon.texture = NetworkManager.character_textures[c_name]
			char_holder.add_child(char_icon)
			char_name_vbox.add_child(char_holder)
			team_char_data.append({"icon": char_icon, "name": c_name})
			
			var name_label = Label.new()
			name_label.text = p_name
			name_label.add_theme_font_size_override("font_size", 20)
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_label.custom_minimum_size = Vector2(left_box_w, 0)
			name_label.clip_text = true
			name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			char_name_vbox.add_child(name_label)
			
			left_box.add_child(char_name_vbox)
		else:
			var members_hbox = HBoxContainer.new()
			members_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
			members_hbox.add_theme_constant_override("separation", 8)
			members_hbox.custom_minimum_size = Vector2(left_box_w, 0)
			
			var unit_w = int((left_box_w - (players.size() - 1) * 8) / float(players.size()))
			for p in players:
				var player_unit = VBoxContainer.new()
				player_unit.alignment = BoxContainer.ALIGNMENT_CENTER
				player_unit.custom_minimum_size = Vector2(unit_w, 0)
				player_unit.add_theme_constant_override("separation", 4)
				
				var c_name = p.get("character", "")
				if c_name == "" or not NetworkManager.character_textures.has(c_name):
					c_name = "Cedi"
					
				var char_holder = Control.new()
				char_holder.custom_minimum_size = Vector2(48, 48)
				char_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				
				var char_icon = TextureRect.new()
				char_icon.size = Vector2(48, 48)
				char_icon.position = Vector2.ZERO
				char_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				char_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				char_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				if NetworkManager.character_textures.has(c_name):
					char_icon.texture = NetworkManager.character_textures[c_name]
				char_holder.add_child(char_icon)
				player_unit.add_child(char_holder)
				team_char_data.append({"icon": char_icon, "name": c_name})
				
				var p_label = Label.new()
				p_label.text = p.get("name", "Spieler")
				p_label.add_theme_font_size_override("font_size", 16 if cols == 2 else 18)
				p_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				p_label.custom_minimum_size = Vector2(unit_w, 0)
				p_label.clip_text = true
				p_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				player_unit.add_child(p_label)
				
				members_hbox.add_child(player_unit)
				
			left_box.add_child(members_hbox)
			
		row.add_child(left_box)
		
		# Styled Progress Bar in Teamfarbe
		var bar_data = MinigameResultHelper.create_styled_bar(max_score_possible, t_color, Vector2(bar_w, 40))
		var bar = bar_data["bar"]
		var score_lbl = bar_data["label"]
		score_lbl.text = "0 Punkte"
		row.add_child(bar_data["container"])
		
		# Symmetrischer Ausgleichs-Spacer rechts nur bei 1 Spalte
		if cols == 1:
			var right_spacer = MinigameResultHelper.create_balancing_spacer(left_box.custom_minimum_size.x)
			row.add_child(right_spacer)
		
		answers_list.add_child(row)
		
		# Balken-Animation (synchron, kein Stagger)
		var duration = MinigameResultHelper.RISE_DURATION * (float(target_score) / float(max_score_possible))
		if target_score > 0:
			var tween = create_tween().set_parallel(true)
			tween.tween_property(bar, "value", float(target_score), duration).set_trans(Tween.TRANS_LINEAR)
			tween.tween_method(func(val: float): score_lbl.text = str(int(round(val))) + " Punkte", 0.0, float(target_score), duration).set_trans(Tween.TRANS_LINEAR)
			
			# Pop-Effekt am Ende
			bar.pivot_offset = bar.custom_minimum_size / 2.0
			var pop = create_tween()
			pop.tween_interval(duration)
			pop.tween_property(bar, "scale", Vector2(1.06, 1.15), 0.08)
			pop.tween_property(bar, "scale", Vector2.ONE, 0.15)
			
		# Gewinner-Sprunganimation für alle Charaktere des Siegerteams (ohne Pokal!)
		if target_score == best_score and best_score > 0:
			for c_data in team_char_data:
				var t = create_tween()
				t.tween_interval(duration + 0.1)
				t.tween_callback(func(): MinigameResultHelper.celebrate_winner(c_data["icon"], c_data["name"]))
			
		i += 1
		
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	$MarginContainer/VBoxContainer.add_child(spacer)
	
	var back_btn = Button.new()
	back_btn.text = "WEITER"
	back_btn.add_theme_font_size_override("font_size", 32)
	back_btn.custom_minimum_size = Vector2(280, 56)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(func(): 
		AudioManager.stop_music()
		var tree = get_tree()
		if tree:
			tree.change_scene_to_file("res://scenes/MainBoard.tscn")
	)
	$MarginContainer/VBoxContainer.add_child(back_btn)

func _on_client_reconnected(p_id: int, p_name: String):
	# Wenn ein Spieler während des laufenden Quizes wiederverbindet,
	# schicken wir ihm sofort seinen aktuellen In-Game Team-Score und Zustand!
	var team = _get_team_for_player(p_id)
	var current_score = 0
	if team != null and team_scores.has(team["color"]):
		current_score = team_scores[team["color"]]
		
	# Sende den In-Game Team-Score
	NetworkManager.send_to_player(p_id, {
		"type": "score_update",
		"score": current_score
	})
	
	# Wenn die Runde gerade offen ist, schicke ihm die Frage.
	# Andernfalls schicke ihn in den Warten-Zustand.
	if sudden_death and not _is_team_in_deathmatch(team):
		NetworkManager.send_to_player(p_id, {
			"type": "state_change",
			"state": "inactive",
			"title": "DEATHMATCH",
			"message": "Deathmatch! Nur die führenden Teams spielen um den Sieg."
		})
	elif is_round_open and current_round < selected_questions.size():
		var question_dict = selected_questions[current_round]
		NetworkManager.send_to_player(p_id, {
			"type": "state_change",
			"state": "quiz",
			"question": question_dict["q"]
		})
	else:
		NetworkManager.send_to_player(p_id, {
			"type": "state_change",
			"state": "waiting"
		})
