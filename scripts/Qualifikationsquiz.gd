extends Control

@onready var question_label = $MarginContainer/VBoxContainer/QuestionLabel
@onready var answers_list = $MarginContainer/VBoxContainer/ScrollContainer/AnswersList
@onready var close_round_btn = $MarginContainer/VBoxContainer/CloseRoundButton
@onready var next_round_btn = $MarginContainer/VBoxContainer/NextRoundButton
@onready var round_label = $MarginContainer/VBoxContainer/RoundLabel
@onready var answer_label = $MarginContainer/VBoxContainer/AnswerLabel
@onready var answers_title = $MarginContainer/VBoxContainer/AnswersTitle

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
		
	# Dynamische Spaltenanzahl für das Grid berechnen
	var p_count = NetworkManager.player_sessions.size()
	if p_count <= 4:
		answers_list.columns = 4
	elif p_count <= 6:
		answers_list.columns = 3
	elif p_count <= 10:
		answers_list.columns = 5
	else:
		answers_list.columns = 6
		
	# Generiere Karten für alle Spieler
	var card_scene = preload("res://scenes/minigames/QuizParticipantCard.tscn")
	for p_id in NetworkManager.player_sessions.keys():
		var p_data = NetworkManager.player_sessions[p_id]
		var card = card_scene.instantiate()
		var p_name = p_data.get("name", "Unbekannt")
		var p_char = p_data.get("character", "Leon")
		answers_list.add_child(card)
		card.setup(p_name, [p_char], Color(0.2, 0.8, 0.2, 1))
		card.set_meta("player_id", p_id)
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
		
		# Finde die Karte des Spielers und aktualisiere sie
		for card in answers_list.get_children():
			if card.has_meta("player_id") and card.get_meta("player_id") == player_id:
				if card.has_method("set_answer"):
					card.set_answer(answer)
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
	# Sende allen Handys den "Warten" Befehl
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
		return # Wenn inaktiv (keine Antwort), dann nichts tun
		
	var p_id = card.get_meta("player_id")
	if NetworkManager.player_sessions.has(p_id):
		var p_name = NetworkManager.player_sessions[p_id]["name"]
		
		# Toggle-Logik
		if pending_points.has(p_id) and pending_points[p_id] > 0:
			# Punkte wieder abziehen (Toggle aus)
			pending_points[p_id] = 0
			card.set_state(2) # 2 = REVEALED
			print("Punkte abgewählt für ", p_name)
		else:
			# Punkte vergeben (Toggle an)
			pending_points[p_id] = 1
			card.set_state(3) # 3 = SELECTED
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
