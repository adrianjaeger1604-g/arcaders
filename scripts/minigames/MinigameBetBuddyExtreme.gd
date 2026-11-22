extends Control

const ParticipantCardScene = preload("res://scenes/minigames/QuizParticipantCard.tscn")

# Reichhaltiger Themenpool für Bet Buddy Extreme
const TOPICS = [
	"Länder in Afrika",
	"Pokémon der 1. Generation",
	"Hauptstädte in Europa",
	"Automarken",
	"Super Mario Charaktere",
	"Disney- und Pixar-Filme",
	"Chemische Elemente im Periodensystem",
	"Videospielkonsolen",
	"Hunderassen",
	"Marvel Superhelden oder Schurken",
	"Gegenstände, die man im Badezimmer findet",
	"Harry Potter Charaktere",
	"Sportarten bei den Olympischen Sommerspielen",
	"Fast-Food-Ketten",
	"Tiere, die im Meer leben",
	"Brettspiele",
	"Musikinstrumente",
	"Star Wars Charaktere",
	"Länder, die mit einem 'M' beginnen",
	"Schulfächer",
	"Käsesorten",
	"Deutsche Fußballvereine",
	"Filme von Steven Spielberg oder Quentin Tarantino",
	"Vogelarten",
	"Tiere, die Winterschlaf halten",
	"Flüsse in Europa",
	"Eissorten",
]

const TARGET_IN_GAME_POINTS: int = 3
const COUNTDOWN_INTERVAL: float = 10.0

enum Phase {
	INTRO,
	BETTING,
	REVEAL,
	COUNTDOWN,
	ROUND_OVER,
	VICTORY
}

var current_phase: Phase = Phase.INTRO
var current_round: int = 1
var current_topic: String = ""
var used_topics: Array[String] = []

# In-Game Punkte pro Team (kann negativ sein!)
var in_game_scores: Dictionary = {} # { team_name: int }
var teams_cache: Array = []

# Spieler-Wetten dieser Runde:
# { player_id: { "player_name": "...", "partner_id": int, "partner_name": "...", "partner_char": "...", "bet": int, "team_name": "...", "team_color": Color } }
var player_bets: Dictionary = {}
var participant_cards: Dictionary = {}

# Der ausgewählte Herausforderer für die Aufzählung
var chosen_player_id: int = -1
var chosen_player_name: String = ""
var chosen_team_name: String = ""
var chosen_team_color: Color = Color.WHITE
var target_count: int = 0
var remaining_count: int = 0

# Rangliste der Team-Gebote für diese Runde (höchstes Gebot zuerst, maximal 1x pro Team)
var ranked_team_bets: Array = []
# Teams, die in dieser Runde bereits angetreten sind
var attempted_team_names: Array = []

# 10-Sekunden Timer
var challenge_timer: float = 10.0
var is_challenge_timer_running: bool = false
var is_challenge_paused: bool = false

# UI Referenzen
@onready var pixel_back_btn = get_node_or_null("PixelBackButton")
@onready var bg_tilemap = get_node_or_null("BackgroundTileMap")
var gameplay_bg: TextureRect = null
var gameplay_dim: ColorRect = null

func _load_texture_safe(res_path: String) -> Texture2D:
	if FileAccess.file_exists(res_path):
		var bytes = FileAccess.get_file_as_bytes(res_path)
		if not bytes.is_empty():
			var img = Image.new()
			if img.load_png_from_buffer(bytes) == OK or img.load_jpg_from_buffer(bytes) == OK:
				return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(res_path):
		var t = load(res_path)
		if t is Texture2D:
			return t
	return null

func _setup_gameplay_background():
	var tex = _load_texture_safe("res://assets/minigames/bet_buddy_extreme/bet_buddy_bg.png")
	if tex == null:
		tex = _load_texture_safe("res://assets/minigames/bet_buddy_extreme/bet_buddy_bg.jpg")
	
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
	
	# Subtile Tönung für optimalen Kontrast von Texten & Buttons
	gameplay_dim = ColorRect.new()
	gameplay_dim.name = "GameplayDim"
	gameplay_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	gameplay_dim.color = Color(0.05, 0.04, 0.03, 0.35)
	gameplay_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gameplay_dim.visible = false
	add_child(gameplay_dim)
	move_child(gameplay_dim, insert_idx + 1)

# Intro Screen
@onready var intro_container = $IntroContainer
@onready var start_game_button = $IntroContainer/VBox/StartGameButton

# Game Container (Layout wie Videospielquiz)
@onready var game_margin = $GameMargin
@onready var game_container = $GameMargin/GameContainer
@onready var score_container = $GameMargin/GameContainer/ScoreContainer
@onready var middle_section = $GameMargin/GameContainer/MiddleSection
@onready var round_label = $GameMargin/GameContainer/MiddleSection/RoundLabel
@onready var topic_label = $GameMargin/GameContainer/MiddleSection/TopicLabel
@onready var status_label = $GameMargin/GameContainer/MiddleSection/StatusLabel
@onready var scroll_container = $GameMargin/GameContainer/MiddleSection/ScrollContainer
@onready var answers_list = $GameMargin/GameContainer/MiddleSection/ScrollContainer/CenterBox/AnswersList
@onready var tie_notice = $GameMargin/GameContainer/MiddleSection/TieNotice
@onready var tie_notice_label = $GameMargin/GameContainer/MiddleSection/TieNotice/TieNoticeLabel

# Action Area
@onready var action_area = $GameMargin/GameContainer/ActionArea
@onready var btn_reveal_bets = $GameMargin/GameContainer/ActionArea/BtnRevealBets
@onready var btn_start_countdown = $GameMargin/GameContainer/ActionArea/BtnStartCountdown

# Challenge Dashboard (Aufzählung)
@onready var challenge_box = $GameMargin/GameContainer/ActionArea/ChallengeBox
@onready var challenger_label = $GameMargin/GameContainer/ActionArea/ChallengeBox/VBox/HeaderBox/ChallengerLabel
@onready var count_display = $GameMargin/GameContainer/ActionArea/ChallengeBox/VBox/CounterAndTimerBox/CounterCard/VBox/CountDisplay
@onready var btn_hit_minus = $GameMargin/GameContainer/ActionArea/ChallengeBox/VBox/CounterAndTimerBox/CounterCard/VBox/Buttons/BtnHitMinus
@onready var btn_undo_plus = $GameMargin/GameContainer/ActionArea/ChallengeBox/VBox/CounterAndTimerBox/CounterCard/VBox/Buttons/BtnUndoPlus
@onready var timer_label = $GameMargin/GameContainer/ActionArea/ChallengeBox/VBox/CounterAndTimerBox/TimerCard/VBox/TimerDisplayHBox/TimerLabel
@onready var hourglass_icon = $GameMargin/GameContainer/ActionArea/ChallengeBox/VBox/CounterAndTimerBox/TimerCard/VBox/TimerDisplayHBox/HourglassIcon
@onready var timer_bar = $GameMargin/GameContainer/ActionArea/ChallengeBox/VBox/CounterAndTimerBox/TimerCard/VBox/TimerBar
@onready var btn_toggle_pause = $GameMargin/GameContainer/ActionArea/ChallengeBox/VBox/CounterAndTimerBox/TimerCard/VBox/BtnTogglePause
@onready var btn_give_up = $GameMargin/GameContainer/ActionArea/ChallengeBox/VBox/ChallengeActions/BtnGiveUp
@onready var btn_success = $GameMargin/GameContainer/ActionArea/ChallengeBox/VBox/ChallengeActions/BtnSuccess

# Round Result Box
@onready var round_result_box = $GameMargin/GameContainer/ActionArea/RoundResultBox
@onready var result_title = $GameMargin/GameContainer/ActionArea/RoundResultBox/VBox/ResultTitle
@onready var result_desc = $GameMargin/GameContainer/ActionArea/RoundResultBox/VBox/ResultDesc
@onready var btn_next_round = $GameMargin/GameContainer/ActionArea/RoundResultBox/VBox/BtnNextRound

# Winner Overlay
@onready var winner_overlay = get_node_or_null("MinigameWinnerOverlay")

func _ready():
	AudioManager.play_random_quiz_music()
	_setup_gameplay_background()
	
	NetworkManager.message_received.connect(_on_network_message)
	NetworkManager.client_connected.connect(_on_client_connected)
	
	_init_teams()
	_connect_ui_signals()
	_connect_buttons_sfx(self)
	
	# Initialer Zustand: Erklärseite
	current_phase = Phase.INTRO
	intro_container.visible = true
	game_margin.visible = false
	game_container.visible = false
	if winner_overlay:
		winner_overlay.visible = false
	if pixel_back_btn:
		pixel_back_btn.visible = true
	_setup_intro_scroll()

	# Handys in den Waiting-Screen schalten
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting",
		"message": "Erkläre Bet Buddy Extreme..."
	})

func _init_teams():
	teams_cache = NetworkManager.computed_teams.duplicate()
	if teams_cache.is_empty():
		# Fallback für lokales Testen ohne Netzwerk
		teams_cache = [
			{
				"name": "Team Rot",
				"color": Color(0.95, 0.3, 0.3),
				"players": [
					{"name": "Cedric", "id": 1, "character": "Cedric"},
					{"name": "Anna", "id": 2, "character": "Anna"}
				]
			},
			{
				"name": "Team Blau",
				"color": Color(0.3, 0.6, 1.0),
				"players": [
					{"name": "Finnja", "id": 3, "character": "Finnja"},
					{"name": "Luca", "id": 4, "character": "Luca"}
				]
			}
		]
	
	in_game_scores.clear()
	for team in teams_cache:
		in_game_scores[team["name"]] = 0
	_update_scoreboard_ui()

func _connect_ui_signals():
	if pixel_back_btn:
		if "auto_return_to_main_board" in pixel_back_btn and pixel_back_btn.auto_return_to_main_board:
			pass
		elif pixel_back_btn.has_signal("back_pressed"):
			pixel_back_btn.back_pressed.connect(_on_back_pressed)
		elif pixel_back_btn.has_signal("pressed"):
			pixel_back_btn.pressed.connect(_on_back_pressed)
		
	start_game_button.pressed.connect(_on_start_game_pressed)
	btn_reveal_bets.pressed.connect(_on_reveal_bets_pressed)
	btn_start_countdown.pressed.connect(_on_start_countdown_pressed)
	
	btn_hit_minus.pressed.connect(_on_hit_minus_pressed)
	btn_undo_plus.pressed.connect(_on_undo_plus_pressed)
	btn_toggle_pause.pressed.connect(_on_toggle_pause_pressed)
	btn_give_up.pressed.connect(_on_give_up_pressed)
	btn_success.pressed.connect(_on_success_pressed)
	btn_next_round.pressed.connect(_on_next_round_pressed)
	
	# Verhindere, dass Buttons Fokus behalten, damit Leertaste nie versehentlich Buttons aktiviert
	for btn in [btn_hit_minus, btn_undo_plus, btn_toggle_pause, btn_give_up, btn_success, btn_reveal_bets, btn_start_countdown, btn_next_round]:
		if btn:
			btn.focus_mode = Control.FOCUS_NONE

func _connect_buttons_sfx(node: Node):
	if node is BaseButton:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func _setup_intro_scroll():
	var scroll_area = get_node_or_null("IntroContainer/VBox/ScrollArea")
	var inst_lbl = get_node_or_null("IntroContainer/VBox/ScrollArea/InstructionContainer/Instruction")
	if scroll_area and inst_lbl:
		await get_tree().process_frame
		if is_instance_valid(inst_lbl) and is_instance_valid(scroll_area):
			var content_h = inst_lbl.get_minimum_size().y + 8.0
			scroll_area.custom_minimum_size.y = clampf(content_h, 80.0, 480.0)

func _process(delta):
	if current_phase == Phase.COUNTDOWN and is_challenge_timer_running and not is_challenge_paused:
		var prev_sec = int(ceil(challenge_timer))
		challenge_timer -= delta
		var curr_sec = int(ceil(challenge_timer))
		if curr_sec != prev_sec and curr_sec in [3, 2, 1]:
			AudioManager.play_sfx("timer_tick")
			
		if challenge_timer <= 0.0:
			challenge_timer = 0.0
			is_challenge_timer_running = false
			_handle_challenge_timeout()
		_update_challenge_timer_ui()

func _input(event: InputEvent):
	if current_phase != Phase.COUNTDOWN:
		return
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
		
	if event.keycode == KEY_SPACE or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_select"):
		if remaining_count > 0:
			_on_hit_minus_pressed()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_on_undo_plus_pressed()
		get_viewport().set_input_as_handled()

# ==============================================================================
# SPIEL- & PHASENSTEUERUNG
# ==============================================================================

func _on_start_game_pressed():
	intro_container.visible = false
	if pixel_back_btn:
		pixel_back_btn.visible = true
	if bg_tilemap:
		bg_tilemap.visible = false
	if gameplay_bg:
		gameplay_bg.visible = true
	if gameplay_dim:
		gameplay_dim.visible = true
	game_margin.visible = true
	game_container.visible = true
	_start_round(1)

func _pick_random_topic() -> String:
	var available = []
	for t in TOPICS:
		if not used_topics.has(t):
			available.append(t)
	if available.is_empty():
		used_topics.clear()
		available = TOPICS.duplicate()
	var picked = available[randi() % available.size()]
	used_topics.append(picked)
	return picked

func _start_round(round_num: int):
	current_round = round_num
	current_phase = Phase.BETTING
	
	round_label.text = "Runde %d" % current_round
	round_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	
	current_topic = _pick_random_topic()
	topic_label.text = current_topic
	if status_label:
		status_label.visible = false
	
	# Action-Zustände zurücksetzen
	action_area.visible = true
	btn_reveal_bets.visible = true
	btn_reveal_bets.disabled = false
	btn_reveal_bets.text = "Wetten aufdecken"
	btn_start_countdown.visible = false
	challenge_box.visible = false
	round_result_box.visible = false
	tie_notice.visible = false
	if winner_overlay:
		winner_overlay.visible = false
	
	player_bets.clear()
	ranked_team_bets.clear()
	attempted_team_names.clear()
	_setup_betting_participants()
	_update_scoreboard_ui()
	
	# Handys informieren
	_broadcast_bet_phase()

func _broadcast_bet_phase():
	NetworkManager.current_game_state = "bet_buddy_bet"
	for team in teams_cache:
		var players = team.get("players", [])
		for i in range(players.size()):
			var p = players[i]
			var pid = _get_player_id(p)
			if pid == -1:
				continue
				
			var partner_name = p.get("name", "Dich selbst")
			if players.size() > 1:
				var partner_idx = (i + 1) % players.size()
				partner_name = players[partner_idx].get("name", "Partner")
				
			NetworkManager.send_to_player(pid, {
				"type": "state_change",
				"state": "bet_buddy_bet",
				"topic": current_topic,
				"partner_name": partner_name,
				"player_id": pid
			})

# ==============================================================================
# PHASE 1: WETT-EINGANG
# ==============================================================================

func _setup_betting_participants():
	participant_cards.clear()
	for child in answers_list.get_children():
		answers_list.remove_child(child)
		child.queue_free()
		
	var all_players = _get_all_players()
	var p_count = all_players.size()
	if p_count <= 4:
		answers_list.columns = max(1, p_count)
	elif p_count <= 6:
		answers_list.columns = 3
	else:
		answers_list.columns = 4
		
	_update_scroll_container_height(p_count, answers_list.columns)
		
	for p in all_players:
		var pid = p["id"]
		var card = ParticipantCardScene.instantiate()
		card.name = "PlayerCard_%d" % pid
		answers_list.add_child(card)
		participant_cards[pid] = card
		var char_name = p.get("character", "Cedric")
		card.setup(p["name"], [char_name], p["team_color"])
		card.set_custom_answer("Tippt gerade...", 0) # 0 = WAITING
		card.set_meta("player_id", pid)
		card.set_meta("team_color", p["team_color"])
		
	_check_all_bets_in()

func _on_network_message(player_id: int, data: Dictionary):
	var msg_type = data.get("type", "")
	if msg_type == "bet_buddy_submit":
		if current_phase == Phase.BETTING:
			var bet_val = max(1, int(data.get("bet", 1)))
			_register_player_bet(player_id, bet_val)

func _on_client_connected(player_id: int, _player_name: String = ""):
	if current_phase == Phase.BETTING:
		var p_info = _get_player_info_by_id(player_id)
		var already_sub = player_bets.has(player_id)
		var b_val = player_bets[player_id].get("bet", 1) if already_sub else 1
		NetworkManager.send_to_player(player_id, {
			"type": "state_change",
			"state": "bet_buddy_bet",
			"topic": current_topic,
			"partner_name": p_info.get("partner_name", "Partner"),
			"player_id": player_id,
			"already_submitted": already_sub,
			"bet_val": b_val
		})
	elif current_phase == Phase.COUNTDOWN:
		NetworkManager.send_to_player(player_id, {
			"type": "state_change",
			"state": "bet_buddy_spectate",
			"topic": current_topic,
			"player_name": chosen_player_name,
			"remaining": remaining_count,
			"time_left": int(ceil(challenge_timer))
		})
	else:
		NetworkManager.send_to_player(player_id, {
			"type": "state_change",
			"state": "waiting",
			"message": "Bet Buddy Extreme läuft..."
		})

func _register_player_bet(player_id: int, bet_val: int):
	var p_info = _get_player_info_by_id(player_id)
	player_bets[player_id] = {
		"player_id": player_id,
		"player_name": p_info.get("name", "Spieler"),
		"partner_id": p_info.get("partner_id", player_id),
		"partner_name": p_info.get("partner_name", "Partner"),
		"partner_char": p_info.get("partner_char", ""),
		"team_name": p_info.get("team_name", "Team"),
		"team_color": p_info.get("team_color", Color.WHITE),
		"bet": bet_val
	}
	
	AudioManager.play_sfx("button_press")
	
	# Update Participant Card
	var card = participant_cards.get(player_id)
	if card and is_instance_valid(card) and card.has_method("set_custom_answer"):
		card.set_custom_answer("Eingereicht!", 1) # 1 = SUBMITTED
		
	_check_all_bets_in()

func _check_all_bets_in():
	var total_players = _get_all_players().size()
	var submitted = player_bets.size()
	if status_label:
		status_label.text = "%d von %d Wetten abgegeben" % [submitted, total_players]
	
	if submitted >= total_players and total_players > 0:
		btn_reveal_bets.text = "Alle Wetten da! Aufdecken"
	else:
		btn_reveal_bets.text = "Wetten aufdecken (%d/%d)" % [submitted, total_players]
	btn_reveal_bets.add_theme_color_override("font_color", Color.WHITE)

func _update_scroll_container_height(count: int, columns: int):
	if not scroll_container:
		return
	var cols = max(1, columns)
	var rows = ceil(float(max(1, count)) / float(cols))
	if rows <= 1:
		scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll_container.custom_minimum_size.y = 204
		scroll_container.scroll_vertical = 0
	else:
		scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		var content_height = rows * 180 + max(0, rows - 1) * 16 + 24
		var max_height = 420
		scroll_container.custom_minimum_size.y = min(content_height, max_height)

# ==============================================================================
# PHASE 2: WETTEN AUFDECKEN & HÖCHSTBIETENDER (INKL. GLEICHSTANDS-ROULETTE)
# ==============================================================================

func _on_reveal_bets_pressed():
	if current_phase != Phase.BETTING:
		return
		
	# Falls noch nicht alle gewettet haben, fülle Defaults (1) ein
	var all_players = _get_all_players()
	for p in all_players:
		if not player_bets.has(p["id"]):
			_register_player_bet(p["id"], 1)
			
	current_phase = Phase.REVEAL
	btn_reveal_bets.visible = false
	status_label.text = "Wetten aufgedeckt! Höchstbietender wird ermittelt..."
	status_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	AudioManager.play_sfx("settings_open")
	
	# 1. Zeige alle Gebote auf den Teilnehmerkarten an
	for pid in player_bets.keys():
		var b = player_bets[pid]
		var card = participant_cards.get(pid)
		if card and is_instance_valid(card) and card.has_method("set_custom_answer"):
			card.set_custom_answer("%d Begriffe" % b["bet"], 2) # 2 = REVEALED
		
	# 2. Absolutes Höchstgebot unter ALLEN einzelnen Spielern ermitteln
	var highest_bet = 1
	for pid in player_bets.keys():
		var b = player_bets[pid]
		if b["bet"] > highest_bet:
			highest_bet = b["bet"]
			
	# 3. ALLE Spieler mit diesem Höchstgebot sammeln (für die Auslosung, falls Gleichstand)
	var targets_with_highest_bet: Array = []
	for pid in player_bets.keys():
		var b = player_bets[pid]
		if b["bet"] == highest_bet:
			targets_with_highest_bet.append(b)
			
	# Auswertung & Gleichstands-Auflösung
	target_count = highest_bet
	btn_start_countdown.disabled = true
	btn_start_countdown.visible = true
	
	if targets_with_highest_bet.size() > 1:
		tie_notice.visible = true
		if tie_notice_label:
			tie_notice_label.text = "GLEICHSTAND bei %d Begriffen! Das Los entscheidet..." % highest_bet
			tie_notice_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.1))
		_animate_tie_break(targets_with_highest_bet)
	else:
		tie_notice.visible = false
		var chosen = targets_with_highest_bet[0] if not targets_with_highest_bet.is_empty() else {}
		ranked_team_bets = _build_ranked_team_bets(chosen)
		_select_challenger(chosen)
		btn_start_countdown.disabled = false

func _build_ranked_team_bets(chosen: Dictionary) -> Array:
	var result = []
	result.append(chosen)
	
	# Für alle anderen Teams jeweils den besten Bieter ermitteln
	var other_teams = {} # team_name -> Array of bets
	for pid in player_bets.keys():
		var b = player_bets[pid]
		if b["team_name"] != chosen["team_name"]:
			if not other_teams.has(b["team_name"]):
				other_teams[b["team_name"]] = []
			other_teams[b["team_name"]].append(b)
			
	var other_team_reps = []
	for t_name in other_teams.keys():
		var team_list = other_teams[t_name]
		var max_team_bet = 1
		for tb in team_list:
			if tb["bet"] > max_team_bet:
				max_team_bet = tb["bet"]
		var best_in_team = []
		for tb in team_list:
			if tb["bet"] == max_team_bet:
				best_in_team.append(tb)
		best_in_team.shuffle()
		other_team_reps.append(best_in_team[0])
		
	# Sortiere die anderen Teams nach ihrem Gebot absteigend
	other_team_reps.sort_custom(func(a, b): return a["bet"] > b["bet"])
	for rep in other_team_reps:
		result.append(rep)
		
	return result

func _animate_tie_break(candidates: Array):
	var ticks = 14
	var delay = 0.08
	for i in range(ticks):
		var pick = candidates[i % candidates.size()]
		# Highlight candidate card
		for c in candidates:
			var card = participant_cards.get(c["player_id"])
			if card and is_instance_valid(card):
				card.set_state(2) # 2 = REVEALED
		var pick_card = participant_cards.get(pick["player_id"])
		if pick_card and is_instance_valid(pick_card):
			pick_card.set_state(3) # 3 = SELECTED
		AudioManager.play_sfx("button_press")
		await get_tree().create_timer(delay).timeout
		delay += 0.02
		
	# Endgültige Wahl aus ALLEN Spielern mit Höchstgebot
	var chosen = candidates[randi() % candidates.size()]
	AudioManager.play_sfx("transformation")
	
	ranked_team_bets = _build_ranked_team_bets(chosen)
			
	_select_challenger(chosen)
	if tie_notice_label:
		if chosen.get("player_name", "") != chosen.get("partner_name", ""):
			tie_notice_label.text = "LOS ENTSCHIEDEN! %s wurde genommen, demnach muss %s (%s) aufzählen!" % [chosen["player_name"], chosen["partner_name"], chosen["team_name"]]
		else:
			tie_notice_label.text = "LOS ENTSCHIEDEN! %s (%s) wurde genommen und muss aufzählen!" % [chosen["player_name"], chosen["team_name"]]
		tie_notice_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	btn_start_countdown.disabled = false

func _select_challenger(b: Dictionary):
	attempted_team_names.clear()
	attempted_team_names.append(b["team_name"])
	
	chosen_player_id = b["partner_id"]
	chosen_player_name = b["partner_name"]
	chosen_team_name = b["team_name"]
	chosen_team_color = b["team_color"]
	target_count = b["bet"]
	remaining_count = target_count
	
	# Markiere alle anderen Karten als normal REVEALED
	for child in answers_list.get_children():
		if child.has_method("set_state"):
			child.set_state(2) # Normal REVEALED
			
	var bettor_card = participant_cards.get(b["player_id"])
	if bettor_card and is_instance_valid(bettor_card) and bettor_card.has_method("set_custom_answer"):
		bettor_card.set_custom_answer("%d Begriffe" % target_count, 3) # 3 = SELECTED
		
	if b.get("player_name", "") != b.get("partner_name", ""):
		status_label.text = "%s wurde genommen, demnach muss %s (%s) antreten und %d Begriffe aufzählen!" % [b["player_name"], chosen_player_name, chosen_team_name, target_count]
	else:
		status_label.text = "%s (%s) muss antreten und %d Begriffe aufzählen!" % [chosen_player_name, chosen_team_name, target_count]
	status_label.add_theme_color_override("font_color", chosen_team_color)

# ==============================================================================
# PHASE 3: AUFZÄHLUNGSSCREEN (10s TIMER, ZÄHLER, GESCHAFFT / AUFGEBEN)
# ==============================================================================

func _on_start_countdown_pressed():
	current_phase = Phase.COUNTDOWN
	btn_start_countdown.visible = false
	challenge_box.visible = true
	round_result_box.visible = false
	tie_notice.visible = false
	
	# Nicht mehr der Wettgewinner leuchtet aktiv, sondern der Spieler, der aufzählen muss!
	for pid in participant_cards.keys():
		var card = participant_cards[pid]
		if not is_instance_valid(card):
			continue
		if pid == chosen_player_id:
			card.set_custom_answer("Noch %d" % target_count, 3) # 3 = SELECTED (leuchtet in Teamfarbe)
		else:
			card.set_state(2) # 2 = REVEALED (normale schwarze Karte mit Teamrahmen)
	
	challenger_label.text = "%s (%s) muss %d Begriffe aufzählen!" % [chosen_player_name, chosen_team_name, target_count]
	challenger_label.add_theme_color_override("font_color", chosen_team_color)
	status_label.text = "Aufzählung läuft! 10 Sekunden pro Begriff."
	status_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	
	remaining_count = target_count
	_update_counter_display()
	
	# 10s Timer starten
	challenge_timer = COUNTDOWN_INTERVAL
	is_challenge_timer_running = true
	is_challenge_paused = false
	btn_toggle_pause.text = "Timer Pause"
	_update_challenge_timer_ui()
	
	btn_hit_minus.disabled = false
	btn_undo_plus.disabled = false
	btn_give_up.disabled = false
	btn_success.disabled = true # Erst bei 0 aktiv!
	
	# Controller in Zuschauer-Modus
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "bet_buddy_spectate",
		"topic": current_topic,
		"player_name": chosen_player_name,
		"remaining": remaining_count,
		"time_left": 10
	})

func _update_counter_display():
	count_display.text = str(remaining_count)
	
	if remaining_count <= 0:
		count_display.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		btn_success.disabled = false
		btn_hit_minus.disabled = true
	else:
		count_display.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		btn_success.disabled = true
		btn_hit_minus.disabled = false

func _on_hit_minus_pressed():
	if current_phase != Phase.COUNTDOWN or remaining_count <= 0:
		return
		
	remaining_count -= 1
	AudioManager.play_sfx("button_press")
	
	# 10-Sekunden Timer sofort wieder auf 10s zurücksetzen!
	challenge_timer = COUNTDOWN_INTERVAL
	is_challenge_timer_running = true
	_update_challenge_timer_ui()
	_update_counter_display()
	
	if remaining_count <= 0:
		AudioManager.play_sfx("transformation")
		status_label.text = "Ziel erreicht! Klicke auf 'Geschafft!' um den Punkt zu vergeben."
		status_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	else:
		status_label.text = "Noch %d Begriff(e) benötigt!" % remaining_count
		status_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
		
	var challenger_card = participant_cards.get(chosen_player_id)
	if challenger_card and is_instance_valid(challenger_card):
		if remaining_count <= 0:
			challenger_card.set_custom_answer("Geschafft!", 3)
		else:
			challenger_card.set_custom_answer("Noch %d" % remaining_count, 3)
		
	# Controller benachrichtigen
	NetworkManager.broadcast({
		"type": "bet_buddy_timer_update",
		"remaining": remaining_count,
		"time_left": int(ceil(challenge_timer))
	})

func _on_undo_plus_pressed():
	if current_phase != Phase.COUNTDOWN:
		return
	remaining_count += 1
	AudioManager.play_sfx("button_press")
	_update_counter_display()
	
	var challenger_card = participant_cards.get(chosen_player_id)
	if challenger_card and is_instance_valid(challenger_card):
		challenger_card.set_custom_answer("Noch %d" % remaining_count, 3)
	
	# Controller benachrichtigen
	NetworkManager.broadcast({
		"type": "bet_buddy_timer_update",
		"remaining": remaining_count,
		"time_left": int(ceil(challenge_timer))
	})

func _on_toggle_pause_pressed():
	if current_phase != Phase.COUNTDOWN:
		return
	is_challenge_paused = not is_challenge_paused
	btn_toggle_pause.text = "Timer Fortsetzen" if is_challenge_paused else "Timer Pausieren"

func _update_challenge_timer_ui():
	timer_label.text = "%04.1f s" % challenge_timer
	timer_bar.value = challenge_timer
	
	if challenge_timer <= 3.0:
		timer_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		if hourglass_icon:
			hourglass_icon.modulate = Color(1.0, 0.35, 0.35)
		timer_bar.modulate = Color(1.0, 0.35, 0.35)
	else:
		timer_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		if hourglass_icon:
			hourglass_icon.modulate = Color(0.85, 0.88, 0.95, 0.9)
		timer_bar.modulate = Color(1.0, 1.0, 1.0)

func _handle_challenge_timeout():
	AudioManager.play_sfx("hit")
	_handle_challenge_failed("ZEIT ABGELAUFEN! 10 Sekunden ohne neuen Begriff.")

func _on_give_up_pressed():
	if current_phase != Phase.COUNTDOWN:
		return
	AudioManager.play_sfx("hit")
	_handle_challenge_failed("%s hat aufgegeben!" % chosen_player_name)

func _handle_challenge_failed(reason_msg: String):
	if current_phase != Phase.COUNTDOWN:
		return
	is_challenge_timer_running = false
	
	# Bisherigen Challenger auf der Karte als nicht geschafft markieren
	var prev_card = participant_cards.get(chosen_player_id)
	if prev_card and is_instance_valid(prev_card):
		prev_card.set_custom_answer("Vorbei", 2)
		
	# Nächstes Team mit dem höchsten Gebot suchen, das noch nicht an der Reihe war
	var next_candidate = null
	for c in ranked_team_bets:
		if not attempted_team_names.has(c["team_name"]):
			next_candidate = c
			break
			
	if next_candidate != null:
		_takeover_challenge(next_candidate, reason_msg)
	else:
		# Alle Teams hatten ihre Chance und sind gescheitert -> Runde ohne Punkte beenden
		_resolve_round(false, "Kein Team konnte die verbleibenden Begriffe aufzählen!")

func _takeover_challenge(next_candidate: Dictionary, reason_msg: String):
	var prev_player = chosen_player_name
	var prev_team = chosen_team_name
	
	attempted_team_names.append(next_candidate["team_name"])
	chosen_player_id = next_candidate["partner_id"]
	chosen_player_name = next_candidate["partner_name"]
	chosen_team_name = next_candidate["team_name"]
	chosen_team_color = next_candidate["team_color"]
	
	# Challenger Card aktualisieren (neuer Spieler leuchtet in Teamfarbe)
	for pid in participant_cards.keys():
		var card = participant_cards[pid]
		if not is_instance_valid(card):
			continue
		if pid == chosen_player_id:
			card.set_custom_answer("Noch %d" % remaining_count, 3) # 3 = SELECTED
		else:
			card.set_state(2)
			
	challenger_label.text = "%s (%s) übernimmt! Noch %d Begriffe aufzählen." % [chosen_player_name, chosen_team_name, remaining_count]
	challenger_label.add_theme_color_override("font_color", chosen_team_color)
	
	status_label.text = "%s (%s) ist raus! %s (%s) übernimmt die restlichen %d Begriffe." % [prev_player, prev_team, chosen_player_name, chosen_team_name, remaining_count]
	status_label.add_theme_color_override("font_color", chosen_team_color)
	
	# 10s Timer für den neuen Herausforderer zurücksetzen und pausieren
	challenge_timer = COUNTDOWN_INTERVAL
	is_challenge_timer_running = true
	is_challenge_paused = true
	btn_toggle_pause.text = "Timer Starten"
	_update_challenge_timer_ui()
	_update_counter_display()
	
	AudioManager.play_sfx("transformation")
	
	# Mobile Controller informieren
	NetworkManager.broadcast({
		"type": "bet_buddy_timer_update",
		"remaining": remaining_count,
		"time_left": int(ceil(challenge_timer))
	})

func _on_success_pressed():
	if current_phase != Phase.COUNTDOWN or remaining_count > 0:
		return
	is_challenge_timer_running = false
	AudioManager.play_sfx("confetti_pop")
	_resolve_round(true, "HERVORRAGEND! Alle %d Begriffe erfolgreich genannt!" % target_count)

func _resolve_round(success: bool, reason_msg: String):
	current_phase = Phase.ROUND_OVER
	is_challenge_timer_running = false
	challenge_box.visible = false
	round_result_box.visible = true
	
	if success:
		in_game_scores[chosen_team_name] += 1
		result_title.text = "GESCHAFFT!"
		result_title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		result_desc.text = "%s\n+1 Punkt für %s!" % [reason_msg, chosen_team_name]
		status_label.text = "Runde gewonnen! +1 Punkt für %s." % chosen_team_name
		status_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		var card = participant_cards.get(chosen_player_id)
		if card and is_instance_valid(card):
			card.set_custom_answer("Geschafft! (+1)", 3)
	else:
		# KEIN Minuspunkt mehr!
		result_title.text = "NICHT GESCHAFFT!"
		result_title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		result_desc.text = "%s\nKeine Punkte in dieser Runde." % reason_msg
		status_label.text = "Runde beendet! Keine Punkte vergeben."
		status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		var card = participant_cards.get(chosen_player_id)
		if card and is_instance_valid(card):
			card.set_custom_answer("Vorbei", 2)
		
	_update_scoreboard_ui()
	
	# Prüfen, ob ein Team 3 Punkte erreicht hat
	var winner_team = null
	for team in teams_cache:
		var score = in_game_scores.get(team["name"], 0)
		if score >= TARGET_IN_GAME_POINTS:
			winner_team = team
			break
			
	if winner_team != null:
		current_phase = Phase.VICTORY
		round_result_box.visible = false
		
		# Handys sofort informieren, dass das Spiel vorbei ist
		NetworkManager.broadcast({
			"type": "state_change",
			"state": "waiting",
			"title": "SPIEL BEENDET",
			"message": "%s gewinnt Bet Buddy Extreme!" % winner_team.get("name", "Team")
		})
		
		var points = 2
		if NetworkManager.current_minigame_index != -1:
			if NetworkManager.current_selecting_team_color == winner_team["color"]:
				points = 3
			NetworkManager.minigame_winners[NetworkManager.current_minigame_index] = {
				"color": winner_team["color"],
				"points": points,
				"selecting_color": NetworkManager.current_selecting_team_color
			}
			for p in winner_team.get("players", []):
				var pid = _get_player_id(p)
				if pid != -1 and NetworkManager.player_sessions.has(pid):
					NetworkManager.player_sessions[pid]["score"] += points
					
		if winner_overlay:
			winner_overlay.visible = true
			winner_overlay.setup_winner(winner_team, points)
	else:
		btn_next_round.text = "Nächste Runde starten"
		var round_msg = "+1 Punkt für %s!" % chosen_team_name if success else "Keine Punkte in dieser Runde."
		NetworkManager.broadcast({
			"type": "state_change",
			"state": "waiting",
			"title": "RUNDE BEENDET",
			"message": round_msg + " Bitte auf den Hauptbildschirm schauen."
		})

func _on_next_round_pressed():
	var winner_team = null
	for team in teams_cache:
		var score = in_game_scores.get(team["name"], 0)
		if score >= TARGET_IN_GAME_POINTS:
			winner_team = team
			break
			
	if winner_team != null:
		_on_back_to_main_board_pressed()
	else:
		_start_round(current_round + 1)

func _on_back_to_main_board_pressed():
	AudioManager.stop_music()
	NetworkManager.current_game_state = "waiting"
	NetworkManager.is_replaying_minigame = false
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting",
		"title": "SPIELBRETT",
		"message": "Zurück auf dem Spielbrett! Bitte auf den Hauptbildschirm schauen."
	})
	if not NetworkManager.minigame_winners.has(NetworkManager.current_minigame_index):
		NetworkManager.current_minigame_index = -1
	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/MainBoard.tscn")

func _on_back_pressed():
	AudioManager.stop_music()
	NetworkManager.current_game_state = "waiting"
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting",
		"title": "SPIELBRETT",
		"message": "Zurück auf dem Spielbrett! Bitte auf den Hauptbildschirm schauen."
	})
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

# ==============================================================================
# HILFSFUNKTIONEN FÜR SCOREBOARD & SPIELER (VIDEOSPIELQUIZ STYLE)
# ==============================================================================

func _update_scoreboard_ui():
	for child in score_container.get_children():
		child.queue_free()
		
	for team in teams_cache:
		var t_color: Color = team.get("color", Color(1, 1, 1, 1))
		var t_name: String = team.get("name", "Team")
		var score: int = in_game_scores.get(t_name, 0)
		
		# Badge Container mit Team-Rahmen (wie im Videospielquiz)
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
		
		# Punktestand in hellem Weiß (oder Rot bei Minuspunkten)
		var score_lbl = Label.new()
		score_lbl.text = str(score) + " / " + str(TARGET_IN_GAME_POINTS) + " Pkt"
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

func _get_all_players() -> Array:
	var list = []
	for team in teams_cache:
		var players = team.get("players", [])
		for i in range(players.size()):
			var p = players[i]
			var pid = _get_player_id(p)
			var partner_name = p.get("name", "Partner")
			var partner_id = pid
			var partner_char = p.get("character", "")
			if players.size() > 1:
				var partner_idx = (i + 1) % players.size()
				var part = players[partner_idx]
				partner_name = part.get("name", "Partner")
				partner_id = _get_player_id(part)
				partner_char = part.get("character", "")
				
			list.append({
				"id": pid,
				"name": p.get("name", "Spieler"),
				"character": p.get("character", "Cedric"),
				"team_name": team.get("name", "Team"),
				"team_color": team.get("color", Color.WHITE),
				"partner_id": partner_id,
				"partner_name": partner_name,
				"partner_char": partner_char
			})
	return list

func _get_player_info_by_id(pid: int) -> Dictionary:
	for p in _get_all_players():
		if p["id"] == pid:
			return p
	return {}

func _get_player_id(player_dict: Dictionary) -> int:
	if player_dict.has("id"):
		return int(player_dict["id"])
	for pid in NetworkManager.player_sessions.keys():
		if NetworkManager.player_sessions[pid].get("name") == player_dict.get("name"):
			return int(pid)
	return -1
