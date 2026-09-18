extends Control

@onready var title_label = $MarginContainer/VBoxContainer/Title
@onready var question_label = $MarginContainer/VBoxContainer/QuestionLabel
@onready var answers_list = $MarginContainer/VBoxContainer/ScrollContainer/AnswersList
@onready var close_round_btn = $MarginContainer/VBoxContainer/CloseRoundButton
@onready var next_round_btn = $MarginContainer/VBoxContainer/NextRoundButton
@onready var round_label = $MarginContainer/VBoxContainer/RoundLabel
@onready var answer_label = $MarginContainer/VBoxContainer/AnswerLabel
@onready var score_label = $MarginContainer/VBoxContainer/ScoreLabel
@onready var instruction_label = $MarginContainer/VBoxContainer/InstructionLabel
@onready var start_game_btn = $MarginContainer/VBoxContainer/StartGameButton
@onready var answers_title = $MarginContainer/VBoxContainer/AnswersTitle

# Eigenschaften, die in vererbenden Scripts überschrieben werden
var quiz_title = "Quiz"
var quiz_instruction = "Lest die Frage und tippt die Antwort auf dem Handy ein. Das Team, das als erstes absendet, loggt die Antwort für das gesamte Team ein!"
var question_pool = []
var max_rounds = 7

var music_track = "video_game_quiz"
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

func _ready():
	AudioManager.play_music(music_track)
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
	round_label.visible = false
	question_label.visible = false
	answer_label.visible = false
	answers_title.visible = false
	answers_list.visible = false
	close_round_btn.visible = false
	next_round_btn.visible = false
	
	# Handys im Wartebildschirm lassen
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})
	_connect_buttons_sfx(self)

func _connect_buttons_sfx(node: Node):
	if node is Button:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func _on_start_game_pressed():
	start_game_btn.visible = false
	instruction_label.visible = false
	
	score_label.visible = true
	round_label.visible = true
	question_label.visible = true
	answers_title.visible = true
	answers_list.visible = true
	
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
		round_label.text = "SUDDEN DEATH!"
		round_label.add_theme_color_override("font_color", Color.RED)
	else:
		round_label.text = "Runde %d / %d" % [current_round + 1, max_rounds]
	
	# Lösung verstecken
	answer_label.visible = false
	answer_label.text = ""
	
	# UI Reset für die neue Runde
	is_round_open = true
	answered_teams.clear()
	pending_points.clear()
	answers_title.text = "Warte auf Antworten..."
	
	# Lösche alte Antwort-Buttons
	for child in answers_list.get_children():
		child.queue_free()
		
	# Generiere Karten für alle Teams
	var card_scene = preload("res://scenes/minigames/QuizParticipantCard.tscn")
	for team in NetworkManager.computed_teams:
		var card = card_scene.instantiate()
		var t_name = team["name"]
		var t_color = team["color"]
		
		# Extrahiere die Charakter-Namen der Teammitglieder
		var chars = []
		for p in team["players"]:
			chars.append(p.get("character", "Leon"))
			
		answers_list.add_child(card)
		card.setup(t_name, chars, t_color)
		card.set_meta("team_color", t_color)
		card.pressed.connect(func(): AudioManager.play_sfx("button_press"))
		card.pressed.connect(self._on_answer_button_pressed.bind(card))
		card.disabled = true # Gamemaster kann noch nicht klicken
		
	close_round_btn.visible = true
	next_round_btn.visible = false
	
	# Sende allen Handys den Befehl, in die Quiz-Ansicht zu wechseln
	NetworkManager.broadcast({
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

func _get_team_for_player(p_id: int) -> Variant:
	for team in NetworkManager.computed_teams:
		for player in team["players"]:
			if player["id"] == p_id:
				return team
	return null

func _on_message_received(player_id, data):
	if data.get("type") == "quiz_answer" and is_round_open:
		var team: Variant = _get_team_for_player(player_id)
		if team == null:
			return
			
		var team_color = team["color"]
		
		# Ein Team darf nur 1x antworten (der Schnellste gewinnt für das Team)
		if answered_teams.has(team_color):
			return
			
		answered_teams[team_color] = player_id
		
		# Sende allen Spielern dieses Teams sofort den Befehl, auf den Warten-Bildschirm zu wechseln!
		for p in team["players"]:
			var p_id = p["id"]
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
	
	# Lösung auf dem Monitor anzeigen
	var question_dict = selected_questions[current_round]
	answer_label.text = "Lösung: " + question_dict["a"]
	answer_label.visible = true
	
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
	var parts = []
	for team in NetworkManager.computed_teams:
		var c = team["color"]
		parts.append(team["name"] + ": " + str(team_scores[c]))
	score_label.text = "Punkte: " + " | ".join(parts)

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
		# Unentschieden -> Sudden Death
		print("Unentschieden! Sudden Death gestartet.")
		sudden_death = true
		max_rounds += 1 # Eine weitere Runde hinzufügen
		start_quiz_question()

func _end_minigame(winning_team: Variant):
	question_label.text = "Quiz beendet!"
	answers_title.visible = false
	answer_label.visible = false
	score_label.visible = false
	
	if winning_team != null and typeof(winning_team) == TYPE_DICTIONARY and not winning_team.is_empty():
		AudioManager.play_sfx("victory_jubel")
		if winning_team.has("players"):
			for p in winning_team["players"]:
				if p.has("character"):
					AudioManager.play_character_sfx(p["character"], "win")
					
		round_label.text = "Gewinner: " + winning_team["name"]
		round_label.add_theme_color_override("font_color", winning_team["color"])
		
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
		
	answers_list.columns = 2
	answers_list.add_theme_constant_override("v_separation", 20)
	answers_list.add_theme_constant_override("h_separation", 60)
	
	var sorted_teams = []
	var max_score_possible = 1
	for team in NetworkManager.computed_teams:
		sorted_teams.append(team)
		if team_scores[team["color"]] > max_score_possible:
			max_score_possible = team_scores[team["color"]]
			
	max_score_possible = max(5, max_score_possible)
	sorted_teams.sort_custom(func(a, b): return team_scores[a["color"]] > team_scores[b["color"]])
	
	var i = 0
	for team in sorted_teams:
		var target_score = team_scores[team["color"]]
		var t_color = team["color"]
		
		var row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 20)
		
		var left_box = HBoxContainer.new()
		left_box.alignment = BoxContainer.ALIGNMENT_END
		left_box.custom_minimum_size = Vector2(350, 0)
		left_box.add_theme_constant_override("separation", 15)
		
		var trophy_rect = TextureRect.new()
		if i == 0:
			trophy_rect.texture = preload("res://assets/ui/icons/icon_trophy.png")
		trophy_rect.custom_minimum_size = Vector2(40, 40)
		trophy_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		trophy_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if i == 0:
			trophy_rect.modulate.a = 0.0
		left_box.add_child(trophy_rect)
		
		var char_name_vbox = VBoxContainer.new()
		char_name_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		
		var chars_hbox = HBoxContainer.new()
		chars_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		for p in team["players"]:
			var char_icon = TextureRect.new()
			char_icon.custom_minimum_size = Vector2(48, 48)
			char_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			char_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			char_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var c_name = p.get("character", "")
			if c_name == "" or not NetworkManager.character_textures.has(c_name):
				c_name = "Cedi"
			if NetworkManager.character_textures.has(c_name):
				char_icon.texture = NetworkManager.character_textures[c_name]
			chars_hbox.add_child(char_icon)
		char_name_vbox.add_child(chars_hbox)
		
		var name_label = Label.new()
		name_label.text = team["name"]
		name_label.add_theme_font_size_override("font_size", 20)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		char_name_vbox.add_child(name_label)
		
		left_box.add_child(char_name_vbox)
		row.add_child(left_box)
		
		var bar_container = MarginContainer.new()
		bar_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
		var bar = ProgressBar.new()
		bar.custom_minimum_size = Vector2(450, 40)
		bar.max_value = max_score_possible
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
		style_fg.bg_color = t_color
		style_fg.corner_radius_top_left = 10
		style_fg.corner_radius_top_right = 10
		style_fg.corner_radius_bottom_right = 10
		style_fg.corner_radius_bottom_left = 10
		bar.add_theme_stylebox_override("fill", style_fg)
		
		bar_container.add_child(bar)
		
		var score_lbl = Label.new()
		score_lbl.text = "0 / " + str(max_score_possible)
		score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		score_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		score_lbl.add_theme_font_size_override("font_size", 24)
		bar_container.add_child(score_lbl)
		
		row.add_child(bar_container)
		
		answers_list.add_child(row)
		
		var tween = create_tween()
		tween.tween_interval(0.2 * i)
		tween.tween_property(bar, "value", target_score, 1.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		
		var int_tween = create_tween()
		int_tween.tween_interval(0.2 * i)
		int_tween.tween_method(func(val: float): score_lbl.text = str(int(val)) + " Points", 0.0, float(target_score), 1.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		
		if i == 0:
			var trophy_tween = create_tween()
			trophy_tween.tween_interval((0.2 * i) + 1.6)
			trophy_tween.tween_property(trophy_rect, "modulate:a", 1.0, 0.5)
			
		i += 1
		
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	$MarginContainer/VBoxContainer.add_child(spacer)
	
	var back_btn = Button.new()
	back_btn.text = "ZURÜCK ZUM MAINBOARD"
	back_btn.add_theme_font_size_override("font_size", 32)
	back_btn.custom_minimum_size = Vector2(400, 60)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(func(): 
		AudioManager.play_music("intro")
		get_tree().change_scene_to_file("res://scenes/MainBoard.tscn")
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
	if is_round_open and current_round < selected_questions.size():
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
