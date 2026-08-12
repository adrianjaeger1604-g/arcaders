extends Control

@onready var title_label = $CenterContainer/VBoxContainer/Title
@onready var question_label = $CenterContainer/VBoxContainer/QuestionLabel
@onready var answers_list = $CenterContainer/VBoxContainer/AnswersList
@onready var close_round_btn = $CenterContainer/VBoxContainer/CloseRoundButton
@onready var next_round_btn = $CenterContainer/VBoxContainer/NextRoundButton
@onready var round_label = $CenterContainer/VBoxContainer/RoundLabel
@onready var answer_label = $CenterContainer/VBoxContainer/AnswerLabel
@onready var score_label = $CenterContainer/VBoxContainer/ScoreLabel
@onready var instruction_label = $CenterContainer/VBoxContainer/InstructionLabel
@onready var start_game_btn = $CenterContainer/VBoxContainer/StartGameButton
@onready var answers_title = $CenterContainer/VBoxContainer/AnswersTitle

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
		
		# Erstelle einen Button für die Antwort, damit GM ihn später anklicken kann
		var btn = Button.new()
		btn.text = team["name"] + ": (Eingeloggt \u2714)" # \u2714 ist ein Checkmark Sysbol
		btn.add_theme_font_size_override("font_size", 28)
		
		# Explizite Farb-Overrides für das Retro-Design (Weiß zu Beige/Gelb bei Hover)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 1)) # Weiß wenn noch deaktivert
		btn.add_theme_color_override("font_hover_color", Color(1, 0.921569, 0.682353, 1))
		btn.add_theme_color_override("font_pressed_color", Color(1, 0.921569, 0.682353, 1))
		btn.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))
		
		# Deaktiviere ihn auf dem PC vorerst, bis die Runde geschlossen wird
		btn.disabled = true 
		# Speichere Daten im Meta-Data-Feld des Buttons!
		btn.set_meta("team_color", team_color)
		btn.set_meta("player_name", player_name)
		btn.set_meta("team_name", team["name"])
		btn.set_meta("raw_answer", answer)
		btn.pressed.connect(func(): AudioManager.play_sfx("button_press"))
		btn.pressed.connect(self._on_answer_button_pressed.bind(btn))
		
		answers_list.add_child(btn)

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
	
	# Mache alle Antwort-Buttons anklickbar und decke die Antworten auf
	for child in answers_list.get_children():
		if child is Button:
			child.disabled = false
			var p_name = child.get_meta("player_name")
			var raw_answer = child.get_meta("raw_answer")
			var t_name = child.get_meta("team_name") if child.has_meta("team_name") else ""
			if t_name != "":
				child.text = t_name + " (" + p_name + ") sagt:\n" + raw_answer
			else:
				child.text = p_name + " sagt:\n" + raw_answer
			
func _on_answer_button_pressed(btn: Button):
	var t_color = btn.get_meta("team_color")
	var p_name = btn.get_meta("player_name")
	var t_name = btn.get_meta("team_name") if btn.has_meta("team_name") else ""
	
	var prefix = t_name + " (" + p_name + ") sagt:\n" if t_name != "" else p_name + " sagt:\n"
	
	# Toggle-Logik
	if pending_points.has(t_color) and pending_points[t_color] > 0:
		# Punkte wieder abziehen (Toggle aus)
		pending_points[t_color] = 0
		btn.text = prefix + btn.get_meta("raw_answer")
		btn.modulate = Color(1, 1, 1, 1) # Normal
		print("Punkte abgewählt für Team")
	else:
		# Punkte vergeben (Toggle an)
		pending_points[t_color] = 1
		btn.text = "[+1] " + prefix + btn.get_meta("raw_answer")
		btn.modulate = Color(0.2, 0.8, 0.2, 1) # Mach ihn schön grün
		print("Punkte ausgewählt für Team")

func _update_score_label():
	var score_text = "Punkte: "
	for team in NetworkManager.computed_teams:
		var c = team["color"]
		score_text += team["name"] + ": " + str(team_scores[c]) + " | "
	score_label.text = score_text

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
	if winning_team != null and typeof(winning_team) == TYPE_DICTIONARY and not winning_team.is_empty():
		AudioManager.play_sfx("victory_jubel")
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
	
	# Button erstellen um zurückzukehren
	var back_btn = Button.new()
	back_btn.text = "ZURÜCK ZUM MAINBOARD"
	back_btn.add_theme_font_size_override("font_size", 32)
	back_btn.pressed.connect(func(): 
		AudioManager.play_music("intro")
		get_tree().change_scene_to_file("res://scenes/MainBoard.tscn")
	)
	answers_list.add_child(back_btn)

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
