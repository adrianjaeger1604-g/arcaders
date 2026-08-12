extends Control

@onready var question_label = $CenterContainer/VBoxContainer/QuestionLabel
@onready var answers_list = $CenterContainer/VBoxContainer/AnswersList
@onready var close_round_btn = $CenterContainer/VBoxContainer/CloseRoundButton
@onready var next_round_btn = $CenterContainer/VBoxContainer/NextRoundButton
@onready var round_label = $CenterContainer/VBoxContainer/RoundLabel
@onready var answer_label = $CenterContainer/VBoxContainer/AnswerLabel
@onready var answers_title = $CenterContainer/VBoxContainer/AnswersTitle

var is_round_open = false
var answered_players = [] # Merken, wer schon geantwortet hat
var pending_points = {} # Merken, wem der GM Punkte in dieser Runde geben will: { player_id: punkte }

var question_pool = [
	{"q": "Was ist die Hauptstadt von Frankreich?", "a": "Paris"},
	{"q": "Wie viele Planeten hat unser Sonnensystem?", "a": "Acht (8)"},
	{"q": "Welches ist das größte Säugetier der Welt?", "a": "Blauwal"},
	{"q": "Wie heißt das flächenmäßig kleinste Land der Erde?", "a": "Vatikanstadt"},
	{"q": "Welcher Kontinent ist der größte?", "a": "Asien"},
	{"q": "In welchem Jahr fiel die Berliner Mauer?", "a": "1989"},
	{"q": "Wie alt ist die Erde ca. (in Milliarden Jahren)?", "a": "4,6 Milliarden"},
	{"q": "Was ist das chemische Symbol für Gold?", "a": "Au"},
	{"q": "Wer malte die Mona Lisa?", "a": "Leonardo da Vinci"},
	{"q": "Welcher Planet ist der Sonne am nächsten?", "a": "Merkur"},
	{"q": "Wie nennt man ein Dreieck mit drei gleich langen Seiten?", "a": "Gleichseitiges Dreieck"},
	{"q": "Welches Tier ist das Wappentier von Berlin?", "a": "Bär"},
	{"q": "Aus wie vielen Quadraten besteht ein Schachbrett?", "a": "64"},
	{"q": "Wie viele Tasten hat ein klassisches Klavier?", "a": "88"},
	{"q": "Welches Element macht den größten Teil der Erdatmosphäre aus?", "a": "Stickstoff"}
]

var selected_questions = []
var current_round = 0
var max_rounds = 5

func _ready():
	AudioManager.play_music("qualifikationsquiz")
	# Nutze die globale Einstellung, aber deckle sie auf die Anzahl der verfügbarer Fragen
	max_rounds = min(NetworkManager.quiz_questions_count, question_pool.size())
	
	# Wir abonnieren uns auf Nachrichten vom Netzwerk
	NetworkManager.message_received.connect(_on_message_received)
	NetworkManager.client_connected.connect(_on_client_reconnected)
	close_round_btn.pressed.connect(_on_close_round_pressed)
	next_round_btn.pressed.connect(_on_next_round_pressed)
	
	# Initialisiere den Fragepool
	randomize()
	question_pool.shuffle()
	# Nimm die ersten 10 (bzw. max_rounds)
	selected_questions = question_pool.slice(0, max_rounds)
	
	start_quiz_question()
	_connect_buttons_sfx(self)

func _connect_buttons_sfx(node: Node):
	if node is Button:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func start_quiz_question():
	var question_dict = selected_questions[current_round]
	var question_text = question_dict["q"]
	question_label.text = question_text
	round_label.text = "Runde %d / %d" % [current_round + 1, max_rounds]
	
	# Lösung verstecken
	answer_label.visible = false
	answer_label.text = ""
	
	# UI Reset für die neue Runde
	is_round_open = true
	answered_players.clear()
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
	is_round_open = true
	print("Quiz Frage gesendet!")

func _on_message_received(player_id, data):
	if data.get("type") == "quiz_answer" and is_round_open:
		# Jeder darf nur 1x antworten
		if player_id in answered_players:
			return
		answered_players.append(player_id)
		
		var answer = data.get("answer", "")
		var player_name = "Unbekannt"
		
		if NetworkManager.player_sessions.has(player_id):
			player_name = NetworkManager.player_sessions[player_id]["name"]
			
		print("Spieler ", player_name, " antwortet: ", answer)
		
		# Erstelle einen Button für die Antwort, damit GM ihn später anklicken kann
		var btn = Button.new()
		btn.text = player_name + ": (Eingeloggt \u2714)" # \u2714 ist ein Checkmark Sysbol
		btn.add_theme_font_size_override("font_size", 28)
		
		# Explizite Farb-Overrides für das Retro-Design (Weiß zu Beige/Gelb bei Hover)
		btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 1)) # Weiß wenn noch deaktivert
		btn.add_theme_color_override("font_hover_color", Color(1, 0.921569, 0.682353, 1))
		btn.add_theme_color_override("font_pressed_color", Color(1, 0.921569, 0.682353, 1))
		btn.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))
		
		# Deaktiviere ihn auf dem PC vorerst, bis die Runde geschlossen wird
		btn.disabled = true 
		# Speichere die player_id im Meta-Data-Feld des Buttons!
		btn.set_meta("player_id", player_id)
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
			# Hole den Namen des Spielers und die eigentliche Antwort aus den Metadaten
			var p_id = child.get_meta("player_id")
			var raw_answer = child.get_meta("raw_answer")
			var p_name = NetworkManager.player_sessions[p_id]["name"] if NetworkManager.player_sessions.has(p_id) else "Unbekannt"
			child.text = p_name + " sagt:\n" + raw_answer
			
func _on_answer_button_pressed(btn: Button):
	var p_id = btn.get_meta("player_id")
	if NetworkManager.player_sessions.has(p_id):
		var p_name = NetworkManager.player_sessions[p_id]["name"]
		
		# Toggle-Logik
		if pending_points.has(p_id) and pending_points[p_id] > 0:
			# Punkte wieder abziehen (Toggle aus)
			pending_points[p_id] = 0
			btn.text = p_name + " sagt:\n" + btn.get_meta("raw_answer")
			btn.modulate = Color(1, 1, 1, 1) # Normal weiß
			print("Punkte abgewählt für ", p_name)
		else:
			# Punkte vergeben (Toggle an)
			pending_points[p_id] = 1
			btn.text = "[+1] " + p_name + " sagt:\n" + btn.get_meta("raw_answer")
			btn.modulate = Color(0.2, 0.8, 0.2, 1) # Mach ihn grün
			print("Punkte ausgewählt für ", p_name)

func _on_next_round_pressed():
	# Erst JETZT die Punkte final verrechnen
	for p_id in pending_points.keys():
		var punkte = pending_points[p_id]
		if punkte > 0 and NetworkManager.player_sessions.has(p_id):
			NetworkManager.player_sessions[p_id]["score"] += punkte
			var new_score = NetworkManager.player_sessions[p_id]["score"]
			print("Finale Punkte an ", NetworkManager.player_sessions[p_id]["name"], " überwiesen! Score: ", new_score)
			
			# Score an das jeweilige Handy senden
			NetworkManager.send_to_player(p_id, {
				"type": "score_update",
				"score": new_score
			})
			
	current_round += 1
	if current_round < max_rounds:
		print("Starte nächste Runde...")
		start_quiz_question()
	else:
		print("Quiz beendet! Alle Runden gespielt.")
		question_label.text = "Quiz beendet!"
		answers_title.text = "Endergebnis:"
		round_label.text = "Bereite Leaderboard vor..."
		next_round_btn.visible = false
		# Scene Transition
		AudioManager.play_sfx("victory_jubel")
		AudioManager.play_music("intro")
		get_tree().change_scene_to_file("res://scenes/Leaderboard.tscn")

func _on_client_reconnected(p_id: int, p_name: String):
	# Wenn ein Spieler während des laufenden Qualifikationsquizes wiederverbindet:
	# 1. Schicke ihm seinen aktuellen globalen Punktestand
	if NetworkManager.player_sessions.has(p_id):
		NetworkManager.send_to_player(p_id, {
			"type": "score_update",
			"score": NetworkManager.player_sessions[p_id]["score"]
		})
	
	# 2. Bringe ihn auf den richtigen Screen (Quiz oder Warten)
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
