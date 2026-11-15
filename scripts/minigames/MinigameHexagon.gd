extends Control

const MinigameResultHelper = preload("res://scripts/minigames/MinigameResultHelper.gd")

# 19 Hexagon Buchstaben (A bis S)
const HEX_LETTERS = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S"]

# Hex-Definitionen mit Zeile und relativer Spaltenkoordinate
# 5 Zeilen: 3, 4, 5, 4, 3 Felder
const HEX_COORDS = [
	# Zeile 0 (Index 0..2)
	{"r": -2.0, "c": -1.0}, {"r": -2.0, "c": 0.0}, {"r": -2.0, "c": 1.0},
	# Zeile 1 (Index 3..6)
	{"r": -1.0, "c": -1.5}, {"r": -1.0, "c": -0.5}, {"r": -1.0, "c": 0.5}, {"r": -1.0, "c": 1.5},
	# Zeile 2 (Index 7..11)
	{"r": 0.0, "c": -2.0}, {"r": 0.0, "c": -1.0}, {"r": 0.0, "c": 0.0}, {"r": 0.0, "c": 1.0}, {"r": 0.0, "c": 2.0},
	# Zeile 3 (Index 12..15)
	{"r": 1.0, "c": -1.5}, {"r": 1.0, "c": -0.5}, {"r": 1.0, "c": 0.5}, {"r": 1.0, "c": 1.5},
	# Zeile 4 (Index 16..18)
	{"r": 2.0, "c": -1.0}, {"r": 2.0, "c": 0.0}, {"r": 2.0, "c": 1.0}
]

# Alle 27 geraden, zusammenhängenden 3er-Reihen auf dem 19er-Board
const TRIPLETS = [
	# Horizontal (9)
	[0, 1, 2], [3, 4, 5], [4, 5, 6], [7, 8, 9], [8, 9, 10], [9, 10, 11],
	[12, 13, 14], [13, 14, 15], [16, 17, 18],
	# Diagonal Unten-Rechts \ (9)
	[7, 12, 16], [3, 8, 13], [8, 13, 17], [0, 4, 9], [4, 9, 14], [9, 14, 18],
	[1, 5, 10], [5, 10, 15], [2, 6, 11],
	# Diagonal Unten-Links / (9)
	[0, 3, 7], [1, 4, 8], [4, 8, 12], [2, 5, 9], [5, 9, 13], [9, 13, 16],
	[6, 10, 14], [10, 14, 17], [11, 15, 18]
]

enum GamePhase {
	INTRO,
	MEMORIZE,
	QUIZ,
	REVEAL,
	VICTORY
}

var current_phase: GamePhase = GamePhase.INTRO
var current_round: int = 1
const MAX_ROUNDS: int = 5

# Board-Zustand der aktuellen Runde
var board_numbers: Array[int] = [] # 19 Zahlen von 1..5
var current_target_sum: int = 10
var valid_triplets_for_target: Array = [] # Alle Triplets, die die Zielsumme ergeben
var found_triplets: Array = [] # Gefundene Triplets: [{"triplet": [a,b,c], "team_name": "...", "color": Color, "letters": "...", "calc": "..."}]

# Timer
var memorize_time_left: float = 60.0
var inactivity_time_left: float = 30.0
var is_inactivity_timer_running: bool = false
var last_broadcasted_timer_sec: int = -1

# Buzzer & Auswahl
var buzzer_active: bool = false
var buzzed_player_id: int = -1
var selected_hex_indices: Array[int] = [] # max 3
var highlighted_solution_triplet: Array = [] # Für Hover/Klick-Hervorhebung in der Auflösung

# Punktestand pro Team (Minuspunkte erlaubt!)
var team_scores: Dictionary = {} # { team_name: int }
var teams_cache: Array = []

# Hexagon Geometrie
const HEX_RADIUS: float = 62.0
var hex_positions: Array[Vector2] = []
var hovered_hex_idx: int = -1

# UI Referenzen
@onready var pixel_back_btn = get_node_or_null("PixelBackButton")

# Erklärseite (Intro)
@onready var intro_container = $IntroContainer
@onready var start_game_button = $IntroContainer/VBox/StartGameButton

# TopHeader (wie im Videospielquiz / Bet Buddy Extreme)
@onready var top_header = $TopHeader
@onready var round_label = $TopHeader/RoundLabel
@onready var score_container = $TopHeader/ScoreContainer

# Hauptlayout
@onready var main_layout = $MainLayout

# Center Area & Timer unter dem Hexagon (wie bei Bet Buddy Extreme)
@onready var board_canvas = $MainLayout/CenterArea/BoardContainer/HexCanvas
@onready var timer_container = $MainLayout/CenterArea/TimerContainer
@onready var timer_desc = $MainLayout/CenterArea/TimerContainer/VBox/TimerDisplayHBox/TimerDesc
@onready var timer_label = $MainLayout/CenterArea/TimerContainer/VBox/TimerDisplayHBox/TimerLabel
@onready var timer_bar = $MainLayout/CenterArea/TimerContainer/VBox/TimerBar
@onready var btn_skip_timer = $MainLayout/CenterArea/TimerContainer/VBox/BtnSkipTimer

# Rechte Spalte
@onready var target_sum_card = $MainLayout/RightPanel/VBox/TargetSumCard
@onready var target_sum_label = $MainLayout/RightPanel/VBox/TargetSumCard/VBox/TargetSumLabel

@onready var buzzer_card = $MainLayout/RightPanel/VBox/BuzzerCard
@onready var buzzer_status_label = $MainLayout/RightPanel/VBox/BuzzerCard/VBox/BuzzerStatusLabel
@onready var buzzed_player_name = $MainLayout/RightPanel/VBox/BuzzerCard/VBox/PlayerNameLabel
@onready var buzzed_team_badge = $MainLayout/RightPanel/VBox/BuzzerCard/VBox/TeamBadge
@onready var buzzed_char_icon = $MainLayout/RightPanel/VBox/BuzzerCard/VBox/CharIcon

@onready var gm_selection_card = $MainLayout/RightPanel/VBox/GMCard
@onready var letter_slot_1 = $MainLayout/RightPanel/VBox/GMCard/VBox/Slots/Slot1
@onready var letter_slot_2 = $MainLayout/RightPanel/VBox/GMCard/VBox/Slots/Slot2
@onready var letter_slot_3 = $MainLayout/RightPanel/VBox/GMCard/VBox/Slots/Slot3
@onready var btn_resolve = $MainLayout/RightPanel/VBox/GMCard/VBox/Buttons/BtnResolve
@onready var btn_clear = $MainLayout/RightPanel/VBox/GMCard/VBox/Buttons/BtnClear
@onready var btn_end_round = $MainLayout/RightPanel/VBox/BtnEndRound

@onready var reveal_card = $MainLayout/RightPanel/VBox/RevealCard
@onready var reveal_summary_label = $MainLayout/RightPanel/VBox/RevealCard/VBox/RevealSummaryLabel
@onready var solutions_list = $MainLayout/RightPanel/VBox/RevealCard/VBox/SolutionsScroll/SolutionsList
@onready var btn_next_round = $MainLayout/RightPanel/VBox/RevealCard/VBox/BtnNextRound

# Bottom Feedback Bar
@onready var bottom_bar = $BottomBar
@onready var feedback_label = $BottomBar/FeedbackLabel

# Victory Overlay
@onready var victory_overlay = $VictoryOverlay
@onready var victory_title = $VictoryOverlay/Panel/VBox/VictoryTitle
@onready var victory_podium = $VictoryOverlay/Panel/VBox/Podium
@onready var btn_back_to_board = $VictoryOverlay/Panel/VBox/BtnBackToBoard

func _ready():
	AudioManager.play_random_quiz_music()
	
	NetworkManager.message_received.connect(_on_network_message)
	NetworkManager.client_connected.connect(_on_client_connected)
	
	_compute_hex_positions()
	_init_teams()
	_connect_ui_signals()
	_connect_buttons_sfx(self)
	
	# Initialer Zustand: Erklärseite wie bei allen anderen Spielen
	current_phase = GamePhase.INTRO
	var bg_tilemap = get_node_or_null("BackgroundTileMap")
	if bg_tilemap:
		bg_tilemap.visible = true
	intro_container.visible = true
	main_layout.visible = false
	top_header.visible = false
	bottom_bar.visible = false
	victory_overlay.visible = false
	if pixel_back_btn:
		pixel_back_btn.visible = true
	
	# Handys in den Waiting-Screen schalten
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting",
		"message": "Erkläre die Regeln... Warten auf Start."
	})

func _compute_hex_positions():
	hex_positions.clear()
	var dx = sqrt(3.0) * HEX_RADIUS
	var dy = 1.5 * HEX_RADIUS
	for coord in HEX_COORDS:
		var pos = Vector2(coord["c"] * dx, coord["r"] * dy)
		hex_positions.append(pos)

func _init_teams():
	teams_cache = NetworkManager.computed_teams.duplicate()
	if teams_cache.is_empty():
		# Fallback für lokales Testen ohne Netzwerk
		teams_cache = [
			{"name": "Team Rot", "color": Color(0.95, 0.3, 0.3), "players": [{"name": "Spieler 1", "id": 1}]},
			{"name": "Team Blau", "color": Color(0.3, 0.6, 1.0), "players": [{"name": "Spieler 2", "id": 2}]}
		]
	
	team_scores.clear()
	for team in teams_cache:
		team_scores[team["name"]] = 0
	_update_team_scores_ui()

func _connect_ui_signals():
	if pixel_back_btn:
		if "auto_return_to_main_board" in pixel_back_btn and pixel_back_btn.auto_return_to_main_board:
			# PixelBackButton führt cancel_and_return_to_board bereits selbstständig aus
			pass
		elif pixel_back_btn.has_signal("back_pressed"):
			pixel_back_btn.back_pressed.connect(_on_back_pressed)
		elif pixel_back_btn.has_signal("pressed"):
			pixel_back_btn.pressed.connect(_on_back_pressed)
		
	start_game_button.pressed.connect(_on_start_game_pressed)
	btn_skip_timer.pressed.connect(_on_skip_memorize_pressed)
	btn_resolve.pressed.connect(_on_resolve_pressed)
	btn_clear.pressed.connect(_clear_letter_selection)
	btn_end_round.pressed.connect(_end_round_to_reveal)
	btn_next_round.pressed.connect(_on_next_round_pressed)
	btn_back_to_board.pressed.connect(_on_back_to_main_board_pressed)
	
	board_canvas.draw.connect(_on_hex_canvas_draw)
	board_canvas.gui_input.connect(_on_hex_canvas_gui_input)

func _connect_buttons_sfx(node: Node):
	if node is BaseButton:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func _process(delta):
	if current_phase == GamePhase.MEMORIZE:
		memorize_time_left -= delta
		if memorize_time_left <= 0.0:
			memorize_time_left = 0.0
			_start_quiz_phase()
		_update_memorize_timer_ui()
		
	elif current_phase == GamePhase.QUIZ:
		if is_inactivity_timer_running:
			inactivity_time_left -= delta
			if inactivity_time_left <= 0.0:
				inactivity_time_left = 0.0
				is_inactivity_timer_running = false
				_end_round_to_reveal()
			_update_inactivity_timer_ui()

# ==============================================================================
# SPIEL- & RUNDENABLAUF
# ==============================================================================

func _on_start_game_pressed():
	intro_container.visible = false
	var bg_tilemap = get_node_or_null("BackgroundTileMap")
	if bg_tilemap:
		bg_tilemap.visible = false
	if pixel_back_btn:
		pixel_back_btn.visible = true
	_ensure_gameplay_background()
	if gameplay_bg:
		gameplay_bg.visible = true
	if gameplay_dim:
		gameplay_dim.visible = true
		
	top_header.visible = true
	main_layout.visible = true
	bottom_bar.visible = true
	_start_round(1)

func _start_round(round_idx: int):
	current_round = round_idx
	current_phase = GamePhase.MEMORIZE
	
	victory_overlay.visible = false
	reveal_card.visible = false
	highlighted_solution_triplet.clear()
	selected_hex_indices.clear()
	found_triplets.clear()
	buzzed_player_id = -1
	buzzer_active = false
	is_inactivity_timer_running = false
	last_broadcasted_timer_sec = -1
	
	_generate_valid_board()
	
	memorize_time_left = 60.0
	inactivity_time_left = 30.0
	
	round_label.text = "Runde %d / %d" % [current_round, MAX_ROUNDS]
	timer_container.visible = true
	timer_desc.text = "Merkzeit:"
	_update_memorize_timer_ui()
	btn_skip_timer.visible = true
	
	target_sum_card.visible = false
	buzzer_card.visible = false
	gm_selection_card.visible = false
	btn_end_round.visible = false
	feedback_label.text = "Merke dir die Zahlen im Hexagon! (60 Sekunden Zeit)"
	feedback_label.modulate = Color(1.0, 0.9, 0.5)
	
	_update_letter_slots_ui()
	_update_team_scores_ui()
	board_canvas.queue_redraw()
	
	# Handys informieren
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting",
		"message": "Merke dir das Hexagon! Runde %d" % current_round
	})

func _generate_valid_board():
	# Generiere 19 Zahlen von 1 bis 5, sodass mindestens eine Zielsumme >= 3-mal vorkommt
	var attempts = 0
	while attempts < 1000:
		attempts += 1
		var candidate_numbers: Array[int] = []
		for i in range(19):
			candidate_numbers.append((randi() % 5) + 1)
		
		# Summen aller 27 Triplets berechnen
		var sum_counts = {}
		for triplet in TRIPLETS:
			var s = candidate_numbers[triplet[0]] + candidate_numbers[triplet[1]] + candidate_numbers[triplet[2]]
			sum_counts[s] = sum_counts.get(s, 0) + 1
		
		# Finde alle Summen, die >= 3 mal vorkommen
		var eligible_sums = []
		for s in sum_counts.keys():
			if sum_counts[s] >= 3:
				eligible_sums.append(s)
		
		if not eligible_sums.is_empty():
			board_numbers = candidate_numbers
			# Wähle zufällige Zielsumme aus den qualifizierten
			current_target_sum = eligible_sums[randi() % eligible_sums.size()]
			
			valid_triplets_for_target.clear()
			for triplet in TRIPLETS:
				var s = board_numbers[triplet[0]] + board_numbers[triplet[1]] + board_numbers[triplet[2]]
				if s == current_target_sum:
					var sorted_t = triplet.duplicate()
					sorted_t.sort()
					valid_triplets_for_target.append(sorted_t)
			
			print("[Hexagon] Board generiert! Zielsumme: %d (Möglichkeiten: %d)" % [current_target_sum, valid_triplets_for_target.size()])
			return
			
	# Fallback
	board_numbers = [3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3]
	current_target_sum = 9
	valid_triplets_for_target = TRIPLETS.duplicate()

func _update_memorize_timer_ui():
	var sec = int(ceil(memorize_time_left))
	timer_desc.text = "Merkzeit:"
	timer_label.text = "%02d s" % sec
	timer_bar.max_value = 60.0
	timer_bar.value = memorize_time_left
	timer_label.modulate = Color(1.0, 0.9, 0.3)

func _on_skip_memorize_pressed():
	if current_phase == GamePhase.MEMORIZE:
		memorize_time_left = 0.0
		_start_quiz_phase()

func _start_quiz_phase():
	current_phase = GamePhase.QUIZ
	btn_skip_timer.visible = false
	timer_container.visible = true
	timer_desc.text = "Buzzer-Zeit:"
	
	target_sum_card.visible = true
	target_sum_label.text = str(current_target_sum)
	# Keine Anzeige der Anzahl der Lösungen während dem Spiel!
	
	buzzer_card.visible = true
	gm_selection_card.visible = true
	reveal_card.visible = false
	btn_end_round.visible = true
	
	_reset_buzzer_state()
	
	feedback_label.text = "Zielsumme: %d! Wer eine Kombination weiß: BUZZERN!" % current_target_sum
	feedback_label.modulate = Color(1.0, 1.0, 1.0)
	board_canvas.queue_redraw()

func _reset_buzzer_state():
	buzzer_active = true
	buzzed_player_id = -1
	selected_hex_indices.clear()
	_update_letter_slots_ui()
	
	inactivity_time_left = 30.0
	is_inactivity_timer_running = true
	last_broadcasted_timer_sec = -1
	_update_inactivity_timer_ui()
	
	buzzer_status_label.text = "BUZZER AKTIV"
	buzzer_status_label.modulate = Color(0.2, 1.0, 0.4)
	buzzed_player_name.text = "Warte auf Buzzer..."
	buzzed_team_badge.visible = false
	buzzed_char_icon.visible = false
	
	btn_resolve.disabled = true
	btn_clear.disabled = true
	
	# Handys für Buzzer freigeben (ohne Timer auf dem Handy per Regel 9)
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "buzzer",
		"game": "hexagon",
		"target_sum": current_target_sum,
		"round": current_round
	})
	NetworkManager.broadcast({
		"type": "buzzer_unlocked"
	})

func _update_inactivity_timer_ui():
	var sec = int(ceil(inactivity_time_left))
	if buzzed_player_id != -1:
		timer_desc.text = "%s antwortet:" % buzzed_player_name.text
	else:
		timer_desc.text = "Buzzer-Zeit:"
	timer_label.text = "%02d s" % sec
	timer_bar.max_value = 30.0
	timer_bar.value = inactivity_time_left
	
	if inactivity_time_left <= 5.0:
		timer_label.modulate = Color(1.0, 0.25, 0.25)
	else:
		timer_label.modulate = Color(0.3, 0.9, 1.0)
	# Auf dem Handy läuft kein Timer (Regel 9) -> kein buzzer_timer_sync Broadcast nötig

# ==============================================================================
# BUZZER & GAME MASTER AUSWERTUNG
# ==============================================================================

func _on_network_message(player_id: int, data: Dictionary):
	var msg_type = data.get("type", "")
	if msg_type == "buzz":
		if current_phase == GamePhase.QUIZ and buzzer_active and buzzed_player_id == -1:
			_handle_buzz(player_id)

func _on_client_connected(player_id: int):
	if current_phase == GamePhase.QUIZ and buzzer_active:
		NetworkManager.send_to_player(player_id, {
			"type": "state_change",
			"state": "buzzer",
			"game": "hexagon",
			"target_sum": current_target_sum,
			"round": current_round,
			"time_left": int(ceil(inactivity_time_left))
		})
	else:
		NetworkManager.send_to_player(player_id, {
			"type": "state_change",
			"state": "waiting",
			"message": "Hexagon läuft..."
		})

func _handle_buzz(player_id: int):
	buzzer_active = false
	buzzed_player_id = player_id
	is_inactivity_timer_running = false # Timer pausieren
	
	var p_name = "Unbekannt"
	var p_char = ""
	if NetworkManager.player_sessions.has(player_id):
		p_name = NetworkManager.player_sessions[player_id].get("name", "Unbekannt")
		p_char = NetworkManager.player_sessions[player_id].get("character", "")
	
	var team = _get_team_for_player(player_id)
	var team_name = team.get("name", "Einzelspieler")
	var team_color = team.get("color", Color(0.9, 0.8, 0.2))
	
	AudioManager.play_sfx("button_press")
	
	buzzer_status_label.text = "GEBUZZERT!"
	buzzer_status_label.modulate = Color(1.0, 0.8, 0.1)
	timer_desc.text = "%s antwortet:" % p_name
	
	buzzed_player_name.text = p_name
	buzzed_team_badge.text = team_name
	buzzed_team_badge.modulate = team_color
	buzzed_team_badge.visible = true
	
	if p_char != "" and NetworkManager.character_textures.has(p_char):
		buzzed_char_icon.texture = NetworkManager.character_textures[p_char]
		buzzed_char_icon.visible = true
	else:
		buzzed_char_icon.visible = false
		
	btn_clear.disabled = false
	
	feedback_label.text = "%s (%s) hat gebuzzert! Bitte die 3 Buchstaben verbal nennen." % [p_name, team_name]
	feedback_label.modulate = team_color
	
	# Handys sperren und Timer pausieren (ohne Timer auf dem Handy)
	NetworkManager.broadcast({
		"type": "buzzer_locked",
		"player_name": p_name,
		"team_name": team_name
	})

func _on_hex_canvas_gui_input(event: InputEvent):
	if event is InputEventMouseMotion:
		var local_mouse = event.position - (board_canvas.size * 0.5)
		var prev_hover = hovered_hex_idx
		hovered_hex_idx = _get_hex_at_point(local_mouse)
		if hovered_hex_idx != prev_hover:
			board_canvas.queue_redraw()
			
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var local_mouse = event.position - (board_canvas.size * 0.5)
		var clicked_idx = _get_hex_at_point(local_mouse)
		if clicked_idx != -1 and current_phase == GamePhase.QUIZ:
			_toggle_hex_selection(clicked_idx)

func _unhandled_key_input(event: InputEvent):
	if current_phase != GamePhase.QUIZ or not event.is_pressed() or event.is_echo():
		return
		
	var key_str = OS.get_keycode_string(event.key_label if event.key_label != 0 else event.keycode).to_upper()
	
	if key_str == "ENTER" or key_str == "KP_ENTER":
		if not btn_resolve.disabled:
			_on_resolve_pressed()
	elif key_str == "BACKSPACE" or key_str == "ESCAPE":
		_clear_letter_selection()
	elif key_str.length() == 1 and key_str >= "A" and key_str <= "S":
		var idx = HEX_LETTERS.find(key_str)
		if idx != -1:
			_toggle_hex_selection(idx)

func _get_hex_at_point(p: Vector2) -> int:
	for i in range(hex_positions.size()):
		var center = hex_positions[i]
		if p.distance_to(center) <= HEX_RADIUS * 0.95:
			return i
	return -1

func _toggle_hex_selection(idx: int):
	if selected_hex_indices.has(idx):
		selected_hex_indices.erase(idx)
	else:
		if selected_hex_indices.size() < 3:
			selected_hex_indices.append(idx)
		else:
			selected_hex_indices.remove_at(0)
			selected_hex_indices.append(idx)
			
	AudioManager.play_sfx("button_press")
	_update_letter_slots_ui()
	board_canvas.queue_redraw()

func _clear_letter_selection():
	selected_hex_indices.clear()
	_update_letter_slots_ui()
	board_canvas.queue_redraw()

func _update_letter_slots_ui():
	var s = selected_hex_indices.size()
	letter_slot_1.text = HEX_LETTERS[selected_hex_indices[0]] if s > 0 else "_"
	letter_slot_2.text = HEX_LETTERS[selected_hex_indices[1]] if s > 1 else "_"
	letter_slot_3.text = HEX_LETTERS[selected_hex_indices[2]] if s > 2 else "_"
	
	btn_resolve.disabled = (s != 3)

func _on_resolve_pressed():
	if selected_hex_indices.size() != 3 or current_phase != GamePhase.QUIZ:
		return
		
	var sorted_selection = selected_hex_indices.duplicate()
	sorted_selection.sort()
	
	var letters_str = "%s - %s - %s" % [HEX_LETTERS[sorted_selection[0]], HEX_LETTERS[sorted_selection[1]], HEX_LETTERS[sorted_selection[2]]]
	var team = _get_team_for_player(buzzed_player_id)
	var team_name = team.get("name", "Unbekannt")
	
	# 1. Prüfen, ob es eine gerade Dreierreihe ist
	var is_straight_line = false
	for t in TRIPLETS:
		var st = t.duplicate()
		st.sort()
		if st == sorted_selection:
			is_straight_line = true
			break
			
	if not is_straight_line:
		# Keine gerade Linie -> Fehler (-1 Punkt, Minuspunkte möglich!)
		AudioManager.play_sfx("missed_punch")
		if team_name != "Unbekannt":
			team_scores[team_name] -= 1
			_update_team_scores_ui()
		feedback_label.text = "FALSCH! (-1 Punkt für %s)" % team_name
		feedback_label.modulate = Color(1.0, 0.3, 0.3)
		_flash_banner(Color(1.0, 0.3, 0.3))
		_delayed_reset_buzzer()
		return
		
	# 2. Prüfen, ob bereits gelöst
	for found in found_triplets:
		if found["triplet"] == sorted_selection:
			AudioManager.play_sfx("hit")
			feedback_label.text = "%s wurde BEREITS GELÖST!" % letters_str
			feedback_label.modulate = Color(1.0, 0.6, 0.2)
			_flash_banner(Color(1.0, 0.6, 0.2))
			_delayed_reset_buzzer()
			return
			
	# 3. Summe berechnen
	var actual_sum = board_numbers[sorted_selection[0]] + board_numbers[sorted_selection[1]] + board_numbers[sorted_selection[2]]
	var calc_str = "%d + %d + %d = %d" % [board_numbers[sorted_selection[0]], board_numbers[sorted_selection[1]], board_numbers[sorted_selection[2]], actual_sum]
	
	if actual_sum == current_target_sum:
		# RICHTIG!
		AudioManager.play_sfx("transformation")
		if team_name != "Unbekannt":
			team_scores[team_name] += 1
			_update_team_scores_ui()
			
		found_triplets.append({
			"triplet": sorted_selection,
			"team_name": team_name,
			"color": team.get("color", Color(0.2, 0.8, 1.0)),
			"letters": letters_str,
			"calc": calc_str
		})
		_update_found_list_ui()
		
		feedback_label.text = "RICHTIG! %s (%s) = %d! (+1 Punkt für %s)" % [letters_str, calc_str, current_target_sum, team_name]
		feedback_label.modulate = Color(0.2, 1.0, 0.4)
		_flash_banner(Color(0.2, 1.0, 0.4))
		
		# Prüfen, ob alle Kombinationen gefunden wurden
		if found_triplets.size() >= valid_triplets_for_target.size():
			feedback_label.text = "GLÜCKWUNSCH! Alle Kombinationen für %d wurden gefunden!" % current_target_sum
			_end_round_to_reveal()
			return
	else:
		# FALSCH! Summe stimmt nicht (-1 Punkt, Minuspunkte möglich!)
		# Wichtig: Keine Rechnung anzeigen, nur "FALSCH!", damit die geheimen Zahlen nicht verraten werden
		AudioManager.play_sfx("hit")
		if team_name != "Unbekannt":
			team_scores[team_name] -= 1
			_update_team_scores_ui()
		feedback_label.text = "FALSCH! (-1 Punkt für %s)" % team_name
		feedback_label.modulate = Color(1.0, 0.3, 0.3)
		_flash_banner(Color(1.0, 0.3, 0.3))
		
	board_canvas.queue_redraw()
	_delayed_reset_buzzer()

func _flash_banner(c: Color):
	var tween = create_tween()
	feedback_label.modulate = c
	tween.tween_property(feedback_label, "modulate:a", 1.0, 0.1)
	tween.tween_property(feedback_label, "modulate:a", 0.3, 0.2)
	tween.tween_property(feedback_label, "modulate:a", 1.0, 0.2)

func _delayed_reset_buzzer():
	selected_hex_indices.clear()
	_update_letter_slots_ui()
	board_canvas.queue_redraw()
	
	get_tree().create_timer(1.8).timeout.connect(func():
		if current_phase == GamePhase.QUIZ:
			_reset_buzzer_state()
	)

# ==============================================================================
# AUFLÖSUNG DIREKT AUF DEM HEXAGON-FELD
# ==============================================================================

func _end_round_to_reveal():
	current_phase = GamePhase.REVEAL
	is_inactivity_timer_running = false
	buzzer_active = false
	
	AudioManager.play_sfx("settings_open")
	
	# Handys informieren
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting",
		"message": "Runde %d beendet! Alle Lösungen werden auf dem Hexagon aufgedeckt." % current_round
	})
	
	timer_desc.text = "Runde %d beendet" % current_round
	timer_label.text = "--"
	timer_bar.value = 0
	btn_skip_timer.visible = false
	
	# Rechte Spalte: Zeige Reveal-Karte statt GM-Eingabe
	buzzer_card.visible = false
	gm_selection_card.visible = false
	btn_end_round.visible = false
	reveal_card.visible = true
	
	reveal_summary_label.text = "Zielsumme %d:\n%d von %d Kombinationen wurden gefunden." % [current_target_sum, found_triplets.size(), valid_triplets_for_target.size()]
	btn_next_round.text = "Nächste Runde" if current_round < MAX_ROUNDS else "Zum Gesamtergebnis"
	
	_update_reveal_solutions_list_ui()
	
	feedback_label.text = "Zielsumme %d: Gefundene Kombinationen in Teamfarbe, ungelöste in Weiß!" % current_target_sum
	feedback_label.modulate = Color(1.0, 0.85, 0.3)
	
	board_canvas.queue_redraw()

func _update_reveal_solutions_list_ui():
	for child in solutions_list.get_children():
		child.queue_free()
		
	for t in valid_triplets_for_target:
		var st = t.duplicate()
		st.sort()
		var let_str = "%s-%s-%s" % [HEX_LETTERS[st[0]], HEX_LETTERS[st[1]], HEX_LETTERS[st[2]]]
		var math_str = "%d+%d+%d=%d" % [board_numbers[st[0]], board_numbers[st[1]], board_numbers[st[2]], current_target_sum]
		
		# Wurde dieses Triplet von einem Team gefunden?
		var found_by_team = ""
		var col = Color.WHITE
		var is_found = false
		for f in found_triplets:
			if f["triplet"] == st:
				found_by_team = " (%s)" % f["team_name"]
				col = f["color"]
				is_found = true
				break
		
		if not is_found:
			found_by_team = " (Offen)"
			col = Color.WHITE
				
		var btn = Button.new()
		btn.text = "%s: %s%s" % [let_str, math_str, found_by_team]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.flat = true
		btn.add_theme_font_size_override("font_size", 15)
		btn.add_theme_color_override("font_color", col)
		
		# Beim Klick/Fokus hebt es diese Linie hervor
		btn.pressed.connect(func():
			highlighted_solution_triplet = st
			board_canvas.queue_redraw()
		)
		solutions_list.add_child(btn)

func _on_next_round_pressed():
	if current_round < MAX_ROUNDS:
		_start_round(current_round + 1)
	else:
		_show_victory_podium()

# ==============================================================================
# SIEGEREHRUNG & TURNIER-PUNKTE
# ==============================================================================

func _show_victory_podium():
	current_phase = GamePhase.VICTORY
	victory_overlay.visible = true
	
	AudioManager.play_sfx("confetti_pop")
	
	# Gewinner ermitteln (höchste Punktzahl, Minuspunkte sortieren korrekt)
	var sorted_teams = teams_cache.duplicate()
	sorted_teams.sort_custom(func(a, b):
		return team_scores.get(a["name"], 0) > team_scores.get(b["name"], 0)
	)
	
	var best_team = sorted_teams[0] if not sorted_teams.is_empty() else null
	
	# Turnierpunkte vergeben (2 Punkte für Gewinner, 3 falls Wählerteam)
	if best_team != null and NetworkManager.current_minigame_index != -1:
		var points = 2
		if NetworkManager.current_selecting_team_color == best_team["color"]:
			points = 3
			
		NetworkManager.minigame_winners[NetworkManager.current_minigame_index] = {
			"color": best_team["color"],
			"points": points,
			"selecting_color": NetworkManager.current_selecting_team_color
		}
		
		for p in best_team.get("players", []):
			var pid = _get_player_id(p)
			if pid != -1 and NetworkManager.player_sessions.has(pid):
				NetworkManager.player_sessions[pid]["score"] += points
				
		print("[Hexagon] Minigame gewonnen von %s (+%d Punkte)" % [best_team["name"], points])
		
	victory_title.text = "SIEG FÜR %s!" % (best_team["name"] if best_team else "NIEMAND")
	victory_title.modulate = best_team["color"] if best_team else Color.WHITE
	
	# Podium befüllen
	for child in victory_podium.get_children():
		child.queue_free()
		
	for i in range(sorted_teams.size()):
		var t = sorted_teams[i]
		var score = team_scores.get(t["name"], 0)
		
		var card = VBoxContainer.new()
		card.custom_minimum_size = Vector2(240, 180)
		card.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_theme_constant_override("separation", 8)
		
		var rank_lbl = Label.new()
		rank_lbl.text = "Platz %d" % (i + 1)
		rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_lbl.add_theme_font_size_override("font_size", 28)
		rank_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2) if i == 0 else Color.WHITE)
		card.add_child(rank_lbl)
		
		var name_lbl = Label.new()
		name_lbl.text = t["name"]
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 24)
		name_lbl.add_theme_color_override("font_color", t["color"])
		card.add_child(name_lbl)
		
		var score_lbl = Label.new()
		score_lbl.text = "%d Punkte" % score
		score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score_lbl.add_theme_font_size_override("font_size", 22)
		if score < 0:
			score_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		card.add_child(score_lbl)
		
		# Erstplatzierten-Animation
		if i == 0 and not t.get("players", []).is_empty():
			var first_player = t["players"][0]
			var char_name = first_player.get("character", "Cedric")
			var char_icon = TextureRect.new()
			char_icon.custom_minimum_size = Vector2(80, 80)
			char_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			char_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			char_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			if NetworkManager.character_textures.has(char_name):
				char_icon.texture = NetworkManager.character_textures[char_name]
			card.add_child(char_icon)
			MinigameResultHelper.celebrate_winner(char_icon, char_name)
			
		victory_podium.add_child(card)

func _on_back_to_main_board_pressed():
	AudioManager.stop_music()
	NetworkManager.is_replaying_minigame = false
	NetworkManager.current_minigame_index = -1
	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/MainBoard.tscn")

func _on_back_pressed():
	AudioManager.stop_music()
	if NetworkManager.current_turn_number > 0:
		if NetworkManager.current_minigame_index == -1 or not NetworkManager.minigame_winners.has(NetworkManager.current_minigame_index):
			if not NetworkManager.is_replaying_minigame:
				NetworkManager.current_turn_number -= 1
	NetworkManager.is_replaying_minigame = false
	NetworkManager.current_minigame_index = -1
	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/MainBoard.tscn")

# ==============================================================================
# ZEICHNEN DES HEXAGON-BOARDS
# ==============================================================================

func _on_hex_canvas_draw():
	if hex_positions.is_empty():
		return
		
	var center_offset = board_canvas.size * 0.5
	var font = board_canvas.get_theme_default_font()
	if not font:
		font = ThemeDB.fallback_font
	
	# Zuordnung der Hexagone zu gefundenen Teams bzw. ungelösten Kombinationen ermitteln
	var hex_found_colors = {}
	var hex_unfound_count = {}
	for f in found_triplets:
		var col = f.get("color", Color(0.2, 0.8, 1.0))
		for h_idx in f["triplet"]:
			if not hex_found_colors.has(h_idx):
				hex_found_colors[h_idx] = []
			hex_found_colors[h_idx].append(col)
			
	if current_phase == GamePhase.REVEAL or current_phase == GamePhase.VICTORY:
		for t in valid_triplets_for_target:
			var st = t.duplicate()
			st.sort()
			var is_found = false
			for f in found_triplets:
				if f["triplet"] == st:
					is_found = true
					break
			if not is_found:
				for h_idx in st:
					hex_unfound_count[h_idx] = hex_unfound_count.get(h_idx, 0) + 1

	# -------------------------------------------------------------------------
	# 1. Basis-Hexagone zeichnen (Polygon & Umrandung)
	# -------------------------------------------------------------------------
	for i in range(19):
		var pos = center_offset + hex_positions[i]
		var is_selected = selected_hex_indices.has(i)
		var is_hovered = (i == hovered_hex_idx and current_phase == GamePhase.QUIZ)
		var is_in_highlighted = highlighted_solution_triplet.has(i)
		
		var fill_color = Color(0.1, 0.14, 0.22, 0.95)
		var border_color = Color(0.3, 0.45, 0.65, 0.8)
		var border_width = 3.0
		
		if is_selected:
			fill_color = Color(0.35, 0.28, 0.05, 0.95)
			border_color = Color(1.0, 0.85, 0.2, 1.0)
			border_width = 5.0
		elif is_in_highlighted:
			fill_color = Color(0.25, 0.22, 0.35, 0.98)
			border_color = Color(1.0, 0.95, 0.5, 1.0)
			border_width = 5.0
		elif is_hovered:
			fill_color = Color(0.18, 0.25, 0.38, 0.95)
			border_color = Color(0.6, 0.8, 1.0, 1.0)
			border_width = 4.0
		elif hex_found_colors.has(i):
			# Hexagon gehört zu mindestens einer erfolgreichen Team-Kombination!
			var t_col = hex_found_colors[i][0]
			fill_color = Color(t_col.r * 0.22, t_col.g * 0.22, t_col.b * 0.22, 0.95)
			border_color = Color(t_col.r, t_col.g, t_col.b, 0.95)
			border_width = 4.0
		elif hex_unfound_count.get(i, 0) > 0 and (current_phase == GamePhase.REVEAL or current_phase == GamePhase.VICTORY):
			# Hexagon gehört zu ungelöster Kombination (Weiß markiert)
			fill_color = Color(0.14, 0.16, 0.24, 0.95)
			border_color = Color(0.9, 0.92, 1.0, 0.8)
			border_width = 3.5
			
		_draw_hexagon(board_canvas, pos, HEX_RADIUS - 3.0, fill_color, border_color, border_width)

	# -------------------------------------------------------------------------
	# 2. Verbindungslinien & Kombinations-Pfade (AUF den Hexagon-Flächen)
	# -------------------------------------------------------------------------
	var lines_to_draw = []
	if current_phase == GamePhase.REVEAL or current_phase == GamePhase.VICTORY:
		# In der Auflösung: Erst ungelöste (Weiß), dann gefundene (Teamfarbe)
		# So liegen die Team-Highlights über den weißen ungelösten
		for t in valid_triplets_for_target:
			var st = t.duplicate()
			st.sort()
			var found_entry = null
			for f in found_triplets:
				if f["triplet"] == st:
					found_entry = f
					break
			if found_entry == null:
				# Nicht gefundene Kombination -> WEISS
				lines_to_draw.append({
					"triplet": st,
					"color": Color(1.0, 1.0, 1.0),
					"is_found": false,
					"is_highlighted": (st == highlighted_solution_triplet)
				})
				
		for f in found_triplets:
			# Gefundene Kombination -> TEAMFARBE
			lines_to_draw.append({
				"triplet": f["triplet"],
				"color": f["color"],
				"is_found": true,
				"is_highlighted": (f["triplet"] == highlighted_solution_triplet)
			})
	else:
		# Während des Spiels: Nur gefundene Kombinationen in TEAMFARBE
		for f in found_triplets:
			lines_to_draw.append({
				"triplet": f["triplet"],
				"color": f["color"],
				"is_found": true,
				"is_highlighted": false
			})

	for item in lines_to_draw:
		var t = item["triplet"]
		var c = item["color"]
		var is_hl = item["is_highlighted"]
		var p1 = center_offset + hex_positions[t[0]]
		var p2 = center_offset + hex_positions[t[1]]
		var p3 = center_offset + hex_positions[t[2]]
		
		if is_hl:
			# Extra deutliche Hervorhebung bei Auswahl in der Lösungsliste
			board_canvas.draw_line(p1, p3, Color(1.0, 0.95, 0.4, 0.4), 28.0, true)
			board_canvas.draw_line(p1, p3, Color(1.0, 0.98, 0.7, 1.0), 14.0, true)
			for p in [p1, p2, p3]:
				board_canvas.draw_circle(p, 16.0, Color(1.0, 0.98, 0.7, 1.0))
		elif item["is_found"]:
			# Erfolgreiche Kombination in TEAMFARBE
			board_canvas.draw_line(p1, p3, Color(c.r, c.g, c.b, 0.35), 20.0, true)
			board_canvas.draw_line(p1, p3, Color(c.r, c.g, c.b, 0.95), 8.0, true)
			for p in [p1, p2, p3]:
				board_canvas.draw_circle(p, 10.0, Color(c.r, c.g, c.b, 0.95))
		else:
			# Nicht gefundene Kombination in WEISS
			board_canvas.draw_line(p1, p3, Color(1.0, 1.0, 1.0, 0.25), 18.0, true)
			board_canvas.draw_line(p1, p3, Color(1.0, 1.0, 1.0, 0.88), 6.5, true)
			for p in [p1, p2, p3]:
				board_canvas.draw_circle(p, 8.5, Color(1.0, 1.0, 1.0, 0.88))

	# -------------------------------------------------------------------------
	# 3. Text & Zahlen (mit Kontrast-Pille über Verbindungslinien)
	# -------------------------------------------------------------------------
	for i in range(19):
		var pos = center_offset + hex_positions[i]
		var is_selected = selected_hex_indices.has(i)
		
		if current_phase == GamePhase.MEMORIZE:
			# Zahlen 1..5 groß und sauber zentriert anzeigen
			var num_str = str(board_numbers[i]) if i < board_numbers.size() else "?"
			var f_size = 42
			var ascent = font.get_ascent(f_size)
			var box_w = 64.0
			var baseline = pos.y + ascent * 0.5 - 2.0
			board_canvas.draw_string(font, Vector2(pos.x - box_w * 0.5, baseline), num_str, HORIZONTAL_ALIGNMENT_CENTER, box_w, f_size, Color(1.0, 0.9, 0.4))
			
		elif current_phase == GamePhase.QUIZ:
			# Buchstaben A..S mit dunklem Center-Badge pixelgenau in den Kreisen zentriert
			var circle_r = 24.0
			var circle_col = Color(0.06, 0.08, 0.14, 0.92)
			var border_col = Color(1.0, 0.85, 0.2) if is_selected else Color(0.35, 0.45, 0.65, 0.75)
			board_canvas.draw_circle(pos, circle_r, circle_col)
			board_canvas.draw_arc(pos, circle_r, 0, TAU, 32, border_col, 2.0, true)
			
			var let_str = HEX_LETTERS[i]
			var f_size = 32
			var ascent = font.get_ascent(f_size)
			var box_w = circle_r * 2.0
			var baseline = pos.y + ascent * 0.5 - 1.0
			var text_color = Color(1.0, 0.85, 0.2) if is_selected else Color(0.9, 0.95, 1.0)
			board_canvas.draw_string(font, Vector2(pos.x - box_w * 0.5, baseline), let_str, HORIZONTAL_ALIGNMENT_CENTER, box_w, f_size, text_color)
			
		elif current_phase == GamePhase.REVEAL or current_phase == GamePhase.VICTORY:
			# AUFLÖSUNG: Buchstabe oben, Zahl darunter mit abgedunkeltem Center-Badge
			var circle_r = 30.0
			board_canvas.draw_circle(pos, circle_r, Color(0.05, 0.07, 0.12, 0.92))
			board_canvas.draw_arc(pos, circle_r, 0, TAU, 32, Color(0.4, 0.5, 0.7, 0.6), 2.0, true)
			
			var let_str = HEX_LETTERS[i]
			var num_str = str(board_numbers[i]) if i < board_numbers.size() else "?"
			var box_w = circle_r * 2.0
			
			var f_size_let = 22
			var ascent_let = font.get_ascent(f_size_let)
			var baseline_let = pos.y - 6.0 + ascent_let * 0.5
			board_canvas.draw_string(font, Vector2(pos.x - box_w * 0.5, baseline_let), let_str, HORIZONTAL_ALIGNMENT_CENTER, box_w, f_size_let, Color(0.85, 0.92, 1.0))
			
			var f_size_num = 26
			var ascent_num = font.get_ascent(f_size_num)
			var baseline_num = pos.y + 18.0 + ascent_num * 0.5
			
			var num_color = Color(1.0, 0.85, 0.15)
			if hex_found_colors.has(i):
				num_color = hex_found_colors[i][0]
			elif hex_unfound_count.get(i, 0) > 0:
				num_color = Color.WHITE
				
			board_canvas.draw_string(font, Vector2(pos.x - box_w * 0.5, baseline_num), num_str, HORIZONTAL_ALIGNMENT_CENTER, box_w, f_size_num, num_color)

func _draw_hexagon(canvas: Control, center: Vector2, radius: float, fill: Color, border: Color, border_w: float):
	var points = PackedVector2Array()
	for k in range(6):
		var angle = deg_to_rad(30.0 + 60.0 * k)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	
	# Gefülltes Polygon
	canvas.draw_colored_polygon(points, fill)
	
	# Umrandung
	points.append(points[0])
	canvas.draw_polyline(points, border, border_w, true)

# ==============================================================================
# HILFSFUNKTIONEN FÜR UI & TEAMS
# ==============================================================================

func _update_team_scores_ui():
	for child in score_container.get_children():
		child.queue_free()
		
	for team in teams_cache:
		var t_name: String = team.get("name", "Team")
		var score: int = team_scores.get(t_name, 0)
		var col: Color = team.get("color", Color.WHITE)
		
		# Badge Container mit Team-Rahmen (Videospielquiz-Standard, Regel 7)
		var badge = PanelContainer.new()
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.09, 0.14, 0.9)
		style.border_color = col
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
		
		# Farbiger Indikator-Punkt in Teamfarbe (14 x 14 px)
		var dot = ColorRect.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.color = col
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(dot)
		
		# Team-Name in Teamfarbe
		var name_lbl = Label.new()
		name_lbl.text = t_name
		name_lbl.add_theme_color_override("font_color", col)
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
		
		# Punktestand
		var score_lbl = Label.new()
		score_lbl.text = "%d Pkt" % score
		if score < 0:
			score_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		else:
			score_lbl.add_theme_color_override("font_color", Color.WHITE)
		score_lbl.add_theme_font_size_override("font_size", 24)
		score_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		score_lbl.add_theme_constant_override("outline_size", 4)
		hbox.add_child(score_lbl)
		
		badge.add_child(hbox)
		score_container.add_child(badge)

func _update_found_list_ui():
	pass

func _get_team_for_player(p_id: int) -> Dictionary:
	for team in teams_cache:
		for p in team.get("players", []):
			if _get_player_id(p) == p_id:
				return team
	return teams_cache[0] if not teams_cache.is_empty() else {}

func _get_player_id(player_dict: Dictionary) -> int:
	if player_dict.has("id"):
		return int(player_dict["id"])
	for pid in NetworkManager.player_sessions.keys():
		if NetworkManager.player_sessions[pid].get("name") == player_dict.get("name"):
			return int(pid)
	return -1
