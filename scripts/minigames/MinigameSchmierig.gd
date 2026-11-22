extends Control

const MinigameResultHelper = preload("res://scripts/minigames/MinigameResultHelper.gd")

const POINTS_TO_WIN: int = 3
const UNBLUR_DURATION: float = 24.0

enum GamePhase {
	INTRO,
	UNBLURRING,
	BUZZED,
	RESOLVED,
	VICTORY
}

var current_phase: GamePhase = GamePhase.INTRO
var current_round: int = 1
var current_blur_amount: float = 1.0
var unblur_time_elapsed: float = 0.0
var is_timer_running: bool = false

# Bild-Pool (Platzhalter, erweiterbar)
var image_pool: Array = [
	{
		"title": "Super Mario Pilz",
		"path": "res://assets/minigames/schmierig/placeholders/mushrooms.bmp"
	},
	{
		"title": "Super-Stern",
		"path": "res://assets/minigames/schmierig/placeholders/star.bmp"
	},
	{
		"title": "Diamant",
		"path": "res://assets/minigames/schmierig/placeholders/diamond.bmp"
	},
	{
		"title": "Herz",
		"path": "res://assets/minigames/schmierig/placeholders/heart.bmp"
	},
	{
		"title": "Pokéball",
		"path": "res://assets/minigames/schmierig/placeholders/pokeball.bmp"
	},
	{
		"title": "Mario Röhre",
		"path": "res://assets/objects/pipes/spr_pipe_down.png"
	},
	{
		"title": "Wolke",
		"path": "res://assets/objects/clouds/spr_cloud_big.png"
	},
	{
		"title": "Bäckerei",
		"path": "res://assets/minigames/cookie_clickers/bakery_bg.jpg"
	}
]
var available_images: Array = []
var current_image_item: Dictionary = {}

# Teams & Punktestand
var teams_cache: Array = []
var team_scores: Dictionary = {} # { team_name: int }
var buzzed_player_id: int = -1
var buzzed_team_name: String = ""
var buzzed_player_name: String = ""
var locked_teams_this_image: Array[String] = []

# UI Referenzen
@onready var pixel_back_btn = get_node_or_null("PixelBackButton")
@onready var bg_tilemap = get_node_or_null("BackgroundTileMap")
@onready var black_bg = $BlackBackground

# Intro
@onready var intro_container = $IntroContainer
@onready var start_game_button = $IntroContainer/VBox/StartGameButton

# Gameplay Container
@onready var gameplay_container = $GameplayContainer

# Top Header
@onready var top_header = $GameplayContainer/TopHeader
@onready var score_container = $GameplayContainer/TopHeader/ScoreContainer

# Center Board
@onready var round_label = $GameplayContainer/CenterBoard/RoundLabel
@onready var solution_label = $GameplayContainer/CenterBoard/SolutionLabel
@onready var image_frame = $GameplayContainer/CenterBoard/ImageFrame
@onready var image_rect = $GameplayContainer/CenterBoard/ImageFrame/ImageRect
@onready var buzzed_shield_overlay = $GameplayContainer/CenterBoard/ImageFrame/BuzzedShieldOverlay
@onready var unblur_progress_bar = $GameplayContainer/CenterBoard/UnblurProgressBar

# Bottom Panel
@onready var bottom_panel = $GameplayContainer/BottomPanel
@onready var unblur_controls = $GameplayContainer/BottomPanel/Margin/VBox/UnblurControls
@onready var unblur_status_label = $GameplayContainer/BottomPanel/Margin/VBox/UnblurControls/UnblurStatusLabel
@onready var btn_close_round_unblur = $GameplayContainer/BottomPanel/Margin/VBox/UnblurControls/Center/BtnCloseRound

@onready var buzzed_controls = $GameplayContainer/BottomPanel/Margin/VBox/BuzzedControls
@onready var buzzed_char_icon = $GameplayContainer/BottomPanel/Margin/VBox/BuzzedControls/PlayerBox/CharIcon
@onready var buzzed_player_label = $GameplayContainer/BottomPanel/Margin/VBox/BuzzedControls/PlayerBox/VBox/PlayerNameLabel
@onready var buzzed_team_badge = $GameplayContainer/BottomPanel/Margin/VBox/BuzzedControls/PlayerBox/VBox/TeamBadge
@onready var btn_correct = $GameplayContainer/BottomPanel/Margin/VBox/BuzzedControls/EvalButtons/BtnCorrect
@onready var btn_wrong = $GameplayContainer/BottomPanel/Margin/VBox/BuzzedControls/EvalButtons/BtnWrong
@onready var btn_close_round_buzzed = $GameplayContainer/BottomPanel/Margin/VBox/BuzzedControls/EvalButtons/BtnCloseRoundBuzzed

@onready var resolved_controls = $GameplayContainer/BottomPanel/Margin/VBox/ResolvedControls
@onready var resolved_summary_label = $GameplayContainer/BottomPanel/Margin/VBox/ResolvedControls/ResolvedSummaryLabel
@onready var btn_next_round = $GameplayContainer/BottomPanel/Margin/VBox/ResolvedControls/BtnNextRound

# Winner Overlay
@onready var winner_overlay = $MinigameWinnerOverlay

func _ready():
	AudioManager.play_random_quiz_music()
	
	NetworkManager.message_received.connect(_on_network_message)
	NetworkManager.client_connected.connect(_on_client_connected)
	
	_init_teams()
	_init_scores()
	_connect_ui_signals()
	_connect_buttons_sfx(self)
	
	# Initialer Zustand: Erklärseite aktiv
	current_phase = GamePhase.INTRO
	if bg_tilemap:
		bg_tilemap.visible = true
	intro_container.visible = true
	gameplay_container.visible = false
	if winner_overlay:
		winner_overlay.visible = false
	if pixel_back_btn:
		pixel_back_btn.visible = true
		
	_setup_intro_scroll()
	
	# Handys in den Waiting-Screen schalten
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting",
		"title": "Schmierig",
		"message": "Erkläre die Regeln... Warten auf Start."
	})

func _setup_intro_scroll():
	var scroll_area = get_node_or_null("IntroContainer/VBox/ScrollArea")
	var inst_lbl = get_node_or_null("IntroContainer/VBox/ScrollArea/InstructionContainer/Instruction")
	if scroll_area and inst_lbl:
		await get_tree().process_frame
		if is_instance_valid(inst_lbl) and is_instance_valid(scroll_area):
			var content_h = inst_lbl.get_minimum_size().y + 8.0
			scroll_area.custom_minimum_size.y = clampf(content_h, 80.0, 480.0)

func _init_teams():
	teams_cache = NetworkManager.computed_teams.duplicate()
	if teams_cache.is_empty():
		# Lokaler Fallback fuer Tests
		teams_cache = [
			{
				"name": "Team Rot",
				"color": Color(0.95, 0.28, 0.28),
				"players": [{"name": "Spieler 1", "id": 1, "character": "Cedric"}]
			},
			{
				"name": "Team Blau",
				"color": Color(0.25, 0.6, 1.0),
				"players": [{"name": "Spieler 2", "id": 2, "character": "Anna"}]
			}
		]

func _init_scores():
	team_scores.clear()
	for team in teams_cache:
		team_scores[team["name"]] = 0
	_update_score_ui()

func _update_score_ui():
	for child in score_container.get_children():
		child.queue_free()
		
	for team in teams_cache:
		var team_name = team["name"]
		var team_color = team["color"]
		var score = team_scores.get(team_name, 0)
		
		var badge = PanelContainer.new()
		var badge_style = StyleBoxFlat.new()
		badge_style.bg_color = Color(0.08, 0.09, 0.14, 0.92)
		badge_style.set_border_width_all(2)
		badge_style.border_color = team_color
		badge_style.set_corner_radius_all(8)
		badge_style.content_margin_left = 12.0
		badge_style.content_margin_right = 12.0
		badge_style.content_margin_top = 6.0
		badge_style.content_margin_bottom = 6.0
		badge.add_theme_stylebox_override("panel", badge_style)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		
		# Farbindikator
		var dot = ColorRect.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = team_color
		hbox.add_child(dot)
		
		# Teamname
		var lbl_name = Label.new()
		lbl_name.text = team_name
		lbl_name.add_theme_color_override("font_color", team_color)
		lbl_name.add_theme_font_size_override("font_size", 22)
		lbl_name.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.06, 0.96))
		lbl_name.add_theme_constant_override("outline_size", 8)
		hbox.add_child(lbl_name)
		
		# Separator
		var sep = VSeparator.new()
		hbox.add_child(sep)
		
		# Punkteanzeige
		var lbl_pts = Label.new()
		lbl_pts.text = "%d / %d Pkt" % [score, POINTS_TO_WIN]
		if score < 0:
			lbl_pts.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		else:
			lbl_pts.add_theme_color_override("font_color", Color.WHITE)
		lbl_pts.add_theme_font_size_override("font_size", 22)
		lbl_pts.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.06, 0.96))
		lbl_pts.add_theme_constant_override("outline_size", 8)
		hbox.add_child(lbl_pts)
		
		badge.add_child(hbox)
		score_container.add_child(badge)

func _connect_ui_signals():
	if start_game_button:
		start_game_button.pressed.connect(_on_start_game_pressed)
	if btn_close_round_unblur:
		btn_close_round_unblur.pressed.connect(_on_close_round_pressed)
	if btn_close_round_buzzed:
		btn_close_round_buzzed.pressed.connect(_on_close_round_pressed)
	if btn_correct:
		btn_correct.pressed.connect(_on_eval_correct_pressed)
	if btn_wrong:
		btn_wrong.pressed.connect(_on_eval_wrong_pressed)
	if btn_next_round:
		btn_next_round.pressed.connect(_on_next_round_pressed)

func _on_start_game_pressed():
	if bg_tilemap:
		bg_tilemap.visible = false
	intro_container.visible = false
	gameplay_container.visible = true
	current_round = 1
	_start_new_round()

func _start_new_round():
	current_phase = GamePhase.UNBLURRING
	locked_teams_this_image.clear()
	buzzed_player_id = -1
	buzzed_team_name = ""
	buzzed_player_name = ""
	
	round_label.text = "Runde %d" % current_round
	solution_label.text = ""
	solution_label.visible = false
	buzzed_shield_overlay.visible = false
	
	# Bild auswaehlen
	_select_next_image()
	
	# Shader und Timer zuruecksetzen
	current_blur_amount = 1.0
	unblur_time_elapsed = 0.0
	is_timer_running = true
	_set_shader_blur(1.0)
	unblur_progress_bar.value = 0.0
	
	# Bottom Panel umschalten
	unblur_controls.visible = true
	buzzed_controls.visible = false
	resolved_controls.visible = false
	unblur_status_label.text = "Buzzer aktiv! Wer erkennt das Motiv zuerst?"
	
	# Handys fuer Buzzer freigeben
	_broadcast_buzzer_state()

func _select_next_image():
	if available_images.is_empty():
		available_images = image_pool.duplicate()
		available_images.shuffle()
		
	current_image_item = available_images.pop_front()
	var img_path = current_image_item.get("path", "")
	if ResourceLoader.exists(img_path):
		var tex = load(img_path)
		if tex:
			image_rect.texture = tex
	elif img_path.ends_with(".bmp") or img_path.ends_with(".png") or img_path.ends_with(".jpg"):
		var img = Image.load_from_file(img_path)
		if img:
			var tex = ImageTexture.create_from_image(img)
			image_rect.texture = tex

func _set_shader_blur(amount: float):
	if image_rect.material is ShaderMaterial:
		image_rect.material.set_shader_parameter("blur_amount", clampf(amount, 0.0, 1.0))

func _process(delta: float):
	if current_phase == GamePhase.UNBLURRING and is_timer_running:
		unblur_time_elapsed += delta
		var progress = clampf(unblur_time_elapsed / UNBLUR_DURATION, 0.0, 1.0)
		current_blur_amount = 1.0 - progress
		_set_shader_blur(current_blur_amount)
		unblur_progress_bar.value = progress * 100.0
		
		if progress >= 1.0:
			unblur_status_label.text = "Bild komplett sichtbar! Wer kennt die Antwort?"

# ==============================================================================
# BUZZER & NETZWERK
# ==============================================================================

func _on_network_message(player_id: int, data: Dictionary):
	var msg_type = data.get("type", "")
	if msg_type == "buzz":
		if current_phase == GamePhase.UNBLURRING and buzzed_player_id == -1:
			var team = _get_team_for_player(player_id)
			var team_name = team.get("name", "")
			if team_name in locked_teams_this_image:
				return # Buzzer fuer dieses Team ist gesperrt
			_handle_buzz(player_id, team)

func _handle_buzz(player_id: int, team: Dictionary):
	current_phase = GamePhase.BUZZED
	is_timer_running = false
	buzzed_player_id = player_id
	buzzed_team_name = team.get("name", "Einzelspieler")
	
	var p_name = "Spieler"
	var p_char = "Cedric"
	if NetworkManager.player_sessions.has(player_id):
		p_name = NetworkManager.player_sessions[player_id].get("name", "Spieler")
		p_char = NetworkManager.player_sessions[player_id].get("character", "Cedric")
	buzzed_player_name = p_name
	
	AudioManager.play_sfx("button_press")
	
	# Bild sofort wieder unscharf maskieren und Sichtschutz aktivieren
	_set_shader_blur(1.0)
	buzzed_shield_overlay.visible = true
	
	# Handys informieren und sperren
	NetworkManager.broadcast({
		"type": "buzzer_locked",
		"player_name": p_name,
		"team_name": buzzed_team_name
	})
	
	# Bottom Panel auf Auswertung schalten
	unblur_controls.visible = false
	buzzed_controls.visible = true
	resolved_controls.visible = false
	
	buzzed_player_label.text = p_name
	buzzed_team_badge.text = buzzed_team_name
	buzzed_team_badge.modulate = team.get("color", Color.WHITE)
	
	if p_char != "" and NetworkManager.character_textures.has(p_char):
		buzzed_char_icon.texture = NetworkManager.character_textures[p_char]
		buzzed_char_icon.visible = true
	else:
		buzzed_char_icon.visible = false

func _on_eval_correct_pressed():
	AudioManager.play_sfx("confetti_pop")
	
	team_scores[buzzed_team_name] = team_scores.get(buzzed_team_name, 0) + 1
	_update_score_ui()
	
	# Bild scharf aufdecken und Loesung anzeigen
	_resolve_current_image("%s (%s) hat richtig geraten! (+1 Punkt)" % [buzzed_player_name, buzzed_team_name])
	
	# Pruefen ob das Team gewonnen hat
	if team_scores[buzzed_team_name] >= POINTS_TO_WIN:
		var winning_team = _get_team_by_name(buzzed_team_name)
		_trigger_victory(winning_team)

func _on_eval_wrong_pressed():
	AudioManager.play_sfx("missed_punch")
	
	# Team fuer dieses Bild sperren
	if not buzzed_team_name in locked_teams_this_image:
		locked_teams_this_image.append(buzzed_team_name)
		
	# Handy des falschen Teams sperren
	var team = _get_team_by_name(buzzed_team_name)
	for p in team.get("players", []):
		var pid = _get_player_id(p)
		if pid != -1:
			NetworkManager.send_to_player(pid, {
				"type": "state_change",
				"state": "inactive",
				"title": "BUZZER GESPERRT",
				"message": "Falsche Antwort! Dein Team ist fuer dieses Bild gesperrt."
			})
			
	# Pruefen ob noch Teams uebrig sind
	var remaining_teams = 0
	for t in teams_cache:
		if not t["name"] in locked_teams_this_image:
			remaining_teams += 1
			
	if remaining_teams <= 0:
		# Alle Teams haben falsch geantwortet -> Aufloesen!
		_resolve_current_image("Alle Teams lagen falsch! Kein Team erhaelt einen Punkt.")
	else:
		# Weiter unblurren fuer die uebrigen Teams
		buzzed_player_id = -1
		buzzed_team_name = ""
		buzzed_player_name = ""
		current_phase = GamePhase.UNBLURRING
		is_timer_running = true
		buzzed_shield_overlay.visible = false
		_set_shader_blur(current_blur_amount)
		
		unblur_controls.visible = true
		buzzed_controls.visible = false
		resolved_controls.visible = false
		unblur_status_label.text = "Buzzer wieder aktiv fuer die uebrigen Teams!"
		
		# Uebrige Handys entsperren
		for pid in NetworkManager.player_sessions.keys():
			var p_team = _get_team_for_player(pid)
			if not p_team.get("name") in locked_teams_this_image:
				NetworkManager.send_to_player(pid, {
					"type": "buzzer_unlocked"
				})

func _on_close_round_pressed():
	_resolve_current_image("Runde geschlossen! Kein Team erhält einen Punkt.")

func _resolve_current_image(summary_text: String):
	current_phase = GamePhase.RESOLVED
	is_timer_running = false
	buzzed_shield_overlay.visible = false
	
	# Bild vollstaendig scharf darstellen
	_set_shader_blur(0.0)
	
	# Loesungstext ueber dem Bild anzeigen
	var title = current_image_item.get("title", "")
	solution_label.text = "LÖSUNG: %s" % title
	solution_label.visible = true
	
	# Handys informieren
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting",
		"title": "Schmierig",
		"message": "Aufloesung: %s" % title
	})
	
	# Bottom Panel umschalten
	unblur_controls.visible = false
	buzzed_controls.visible = false
	resolved_controls.visible = true
	resolved_summary_label.text = summary_text

func _on_next_round_pressed():
	current_round += 1
	_start_new_round()

func _broadcast_buzzer_state():
	for pid in NetworkManager.player_sessions.keys():
		var p_team = _get_team_for_player(pid)
		var t_name = p_team.get("name", "")
		if t_name in locked_teams_this_image:
			NetworkManager.send_to_player(pid, {
				"type": "state_change",
				"state": "inactive",
				"title": "BUZZER GESPERRT",
				"message": "Falsche Antwort! Dein Team ist fuer dieses Bild gesperrt."
			})
		else:
			NetworkManager.send_to_player(pid, {
				"type": "state_change",
				"state": "buzzer",
				"game": "schmierig",
				"round": current_round
			})
			NetworkManager.send_to_player(pid, {
				"type": "buzzer_unlocked"
			})

func _on_client_connected(player_id: int, _player_name: String = ""):
	if current_phase == GamePhase.INTRO:
		NetworkManager.send_to_player(player_id, {
			"type": "state_change",
			"state": "waiting",
			"title": "Schmierig",
			"message": "Erklaere die Regeln... Warten auf Start."
		})
	elif current_phase == GamePhase.UNBLURRING:
		var p_team = _get_team_for_player(player_id)
		if p_team.get("name") in locked_teams_this_image:
			NetworkManager.send_to_player(player_id, {
				"type": "state_change",
				"state": "inactive",
				"title": "BUZZER GESPERRT",
				"message": "Falsche Antwort! Dein Team ist fuer dieses Bild gesperrt."
			})
		else:
			NetworkManager.send_to_player(player_id, {
				"type": "state_change",
				"state": "buzzer",
				"game": "schmierig",
				"round": current_round
			})
			if buzzed_player_id == -1:
				NetworkManager.send_to_player(player_id, {
					"type": "buzzer_unlocked"
				})

# ==============================================================================
# SIEG & TURNIERWERTUNG
# ==============================================================================

func _trigger_victory(winning_team: Dictionary):
	current_phase = GamePhase.VICTORY
	is_timer_running = false
	
	var points = 2
	if winning_team != null and NetworkManager.current_minigame_index != -1:
		if NetworkManager.current_selecting_team_color == winning_team.get("color"):
			points = 3
			
		NetworkManager.minigame_winners[NetworkManager.current_minigame_index] = {
			"color": winning_team.get("color"),
			"points": points,
			"selecting_color": NetworkManager.current_selecting_team_color
		}
		
		for p in winning_team.get("players", []):
			var pid = _get_player_id(p)
			if pid != -1 and NetworkManager.player_sessions.has(pid):
				NetworkManager.player_sessions[pid]["score"] += points
				
	if winner_overlay:
		winner_overlay.visible = true
		winner_overlay.setup_winner(winning_team, points)

# ==============================================================================
# HELPER FUNKTIONEN
# ==============================================================================

func _get_team_for_player(player_id: int) -> Dictionary:
	for team in teams_cache:
		for p in team.get("players", []):
			if _get_player_id(p) == player_id:
				return team
	return {"name": "Einzelspieler", "color": Color(0.9, 0.8, 0.2), "players": []}

func _get_team_by_name(team_name: String) -> Dictionary:
	for team in teams_cache:
		if team.get("name") == team_name:
			return team
	return {}

func _get_player_id(player_dict: Dictionary) -> int:
	if player_dict.has("id"):
		return int(player_dict["id"])
	elif player_dict.has("peer_id"):
		return int(player_dict["peer_id"])
	return -1

func _connect_buttons_sfx(node: Node):
	if node is Button:
		node.mouse_entered.connect(func(): pass)
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)
