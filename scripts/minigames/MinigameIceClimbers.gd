extends Control

# ==============================================================================
#                             MINIGAME: ICE CLIMBERS
# ==============================================================================
# Ein vertikales Jump & Run im Doodle-Jump- / Ice-Climber-Stil für alle Spieler!
# - Steuerung in Echtzeit über Handys (Links, Rechts, Sprung)
# - Endlose prozedural generierte Eis-Plattformen nach oben
# - Kamera scrollt sanft mit dem führenden Kletterer nach oben
# - Feste Eiswände links und rechts (kein Rauslaufen)
# - Wer unten aus dem Bildschirm fällt, scheidet aus (bye_bye Sound!)
# - Das letzte überlebende Team gewinnt das Spiel!
# ==============================================================================

const MinigameResultHelper = preload("res://scripts/minigames/MinigameResultHelper.gd")

# Game Boundaries & Arena
const VIEWPORT_WIDTH: float = 1920.0
const VIEWPORT_HEIGHT: float = 1080.0
const WALL_LEFT_X: float = 120.0
const WALL_RIGHT_X: float = 1800.0
const INITIAL_FLOOR_Y: float = 1020.0
const INITIAL_FLOOR_HEIGHT: float = 120.0

# Player Physics
const GRAVITY: float = 1350.0
const JUMP_VELOCITY: float = -720.0
const MOVE_SPEED: float = 380.0
const ACCELERATION: float = 5200.0
const TURN_ACCELERATION: float = 9000.0
const FRICTION: float = 3200.0

# Platform Generation
# Vertikaler Abstand zwischen Schichten: 140 bis 162 px (Apex-Höhe ist 192 px -> 30-52 px Freiraum)
const PLATFORM_LAYER_STEP_MIN: float = 140.0
const PLATFORM_LAYER_STEP_MAX: float = 162.0
const PLATFORM_WIDTH_MIN: float = 175.0
const PLATFORM_WIDTH_MAX: float = 230.0
const PLATFORM_HEIGHT: float = 24.0
const ICE_BLOCK_WIDTH: float = 70.0
const ICE_BLOCK_HEIGHT: float = 26.0

# Nodes
@onready var intro_background = get_node_or_null("IntroBackground")
@onready var intro_container = $IntroContainer
@onready var start_btn = $IntroContainer/VBox/StartGameButton
@onready var pixel_back_btn = get_node_or_null("PixelBackButton")

@onready var sky_rect = get_node_or_null("SkyBackgroundLayer/SkyRect")
@onready var star_field = get_node_or_null("SkyBackgroundLayer/StarField")

@onready var world = $World
@onready var camera = $World/Camera2D
@onready var platform_container = $World/Platforms
@onready var player_container = $World/Players
@onready var fx_container = $World/FX
@onready var snow_particles = $World/SnowParticles

@onready var hud = $HUD
@onready var altitude_label = $HUD/TopBar/Margin/HBox/AltitudeLabel
@onready var top_banner = $HUD/TopBar/Margin/HBox/TitleLabel
@onready var countdown_label = $HUD/CountdownLabel
@onready var team_sidebar = $HUD/TeamSidebar/VBox
@onready var victory_overlay = $HUD/VictoryOverlay
@onready var victory_title = $HUD/VictoryOverlay/VBox/VictoryTitle
@onready var victory_subtitle = $HUD/VictoryOverlay/VBox/VictorySubtitle
@onready var return_btn = get_node_or_null("HUD/VictoryOverlay/VBox/ReturnButton")

# State
var game_state: String = "intro" # "intro", "countdown", "playing", "game_over"
var countdown_timer: float = 3.0
var highest_climbed_y: float = INITIAL_FLOOR_Y - (INITIAL_FLOOR_HEIGHT * 0.5)
var current_top_platform_y: float = INITIAL_FLOOR_Y - (INITIAL_FLOOR_HEIGHT * 0.5)
var active_platforms: Array[StaticBody2D] = []
var last_layer_platforms: Array[Dictionary] = [] # Array von { "x": float, "w": float }
var last_layer_x_positions: Array[float] = []
var next_ice_barrier_meter: int = 100

# Players: Dictionary of p_id -> PlayerData
# { "node": CharacterBody2D, "name": String, "team_index": int, "team_color": Color,
#   "alive": bool, "input_dir": float, "input_jump": bool, "jump_buffered": float,
#   "coyote_time": float, "character_name": String, "anim_sprite": AnimatedSprite2D,
#   "hud_card": Control, "hud_status_label": Label }
var players_data: Dictionary = {}

func _ready():
	AudioManager.play_music("ice_climbers")
	_setup_fallback_teams_if_needed()
	_connect_buttons_sfx(self)
	
	if start_btn:
		start_btn.pressed.connect(_on_start_pressed)
	if return_btn == null:
		return_btn = find_child("ReturnButton", true, false)
	if return_btn:
		if not return_btn.pressed.is_connected(_on_return_pressed):
			return_btn.pressed.connect(_on_return_pressed)
	if pixel_back_btn:
		if "auto_return_to_main_board" in pixel_back_btn and pixel_back_btn.auto_return_to_main_board:
			# PixelBackButton führt cancel_and_return_to_board bereits selbstständig aus
			pass
		else:
			pixel_back_btn.pressed.connect(_on_back_pressed)
		
	NetworkManager.message_received.connect(_on_network_message)
	NetworkManager.client_connected.connect(_on_client_connected)
	
	victory_overlay.visible = false
	countdown_label.visible = false
	hud.visible = false
	world.visible = false
	if intro_background:
		intro_background.visible = true
	intro_container.visible = true
	
	# Handys während der Regelerklärung im Wartescreen halten
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})
	
	_build_arena_walls()
	_spawn_initial_floor()
	_generate_platforms_up_to(INITIAL_FLOOR_Y - 1800.0)
	_setup_players()
	_build_team_sidebar()
	
	camera.position = Vector2(VIEWPORT_WIDTH * 0.5, 540.0)
	_update_altitude_hud()
	_setup_intro_scroll()

func _setup_intro_scroll():
	var scroll_area = get_node_or_null("IntroContainer/VBox/ScrollArea")
	var inst_lbl = get_node_or_null("IntroContainer/VBox/ScrollArea/InstructionContainer/Instruction")
	if scroll_area and inst_lbl:
		await get_tree().process_frame
		if is_instance_valid(inst_lbl) and is_instance_valid(scroll_area):
			var content_h = inst_lbl.get_minimum_size().y + 32.0
			scroll_area.custom_minimum_size.y = clampf(content_h, 80.0, 480.0)

func _setup_fallback_teams_if_needed():
	if NetworkManager.computed_teams.is_empty():
		# Standalone / Editor-Test
		var fallback_pids = NetworkManager.player_sessions.keys()
		if fallback_pids.is_empty():
			NetworkManager.player_sessions[1] = { "name": "Spieler 1", "character": "Cedric", "score": 0 }
			NetworkManager.player_sessions[2] = { "name": "Spieler 2", "character": "Simon", "score": 0 }
			fallback_pids = [1, 2]
			
		var team_colors = [Color(0.24, 0.65, 1.0), Color(1.0, 0.35, 0.35), Color(0.35, 0.88, 0.45), Color(0.95, 0.78, 0.22)]
		var teams = []
		for i in range(fallback_pids.size()):
			var p_id = fallback_pids[i]
			var t_idx = i % 2
			while teams.size() <= t_idx:
				teams.append({
					"name": "Team %d" % (teams.size() + 1),
					"color": team_colors[teams.size() % team_colors.size()],
					"players": []
				})
			teams[t_idx]["players"].append({
				"id": p_id,
				"name": NetworkManager.player_sessions[p_id]["name"],
				"character": NetworkManager.player_sessions[p_id].get("character", "Cedric")
			})
		NetworkManager.computed_teams = teams

func _connect_buttons_sfx(node: Node):
	if node is BaseButton:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

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

func _on_return_pressed():
	AudioManager.stop_music()
	NetworkManager.is_replaying_minigame = false
	NetworkManager.current_minigame_index = -1
	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/MainBoard.tscn")

# ==============================================================================
#                             ARENA & PLATTFORMEN
# ==============================================================================

func _build_arena_walls():
	# Linke Wand
	var left_wall = StaticBody2D.new()
	left_wall.position = Vector2(WALL_LEFT_X, 0)
	var left_shape = CollisionShape2D.new()
	var l_rect = RectangleShape2D.new()
	l_rect.size = Vector2(80.0, 200000.0) # Riesige vertikale Sperre
	left_shape.shape = l_rect
	left_wall.add_child(left_shape)
	world.add_child(left_wall)
	
	# Rechte Wand
	var right_wall = StaticBody2D.new()
	right_wall.position = Vector2(WALL_RIGHT_X, 0)
	var right_shape = CollisionShape2D.new()
	var r_rect = RectangleShape2D.new()
	r_rect.size = Vector2(80.0, 200000.0)
	right_shape.shape = r_rect
	right_wall.add_child(right_shape)
	world.add_child(right_wall)

func _spawn_initial_floor():
	var floor_body = StaticBody2D.new()
	floor_body.position = Vector2((WALL_LEFT_X + WALL_RIGHT_X) * 0.5, INITIAL_FLOOR_Y)
	
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	var width = (WALL_RIGHT_X - WALL_LEFT_X) + 60.0
	shape.size = Vector2(width, INITIAL_FLOOR_HEIGHT)
	col.shape = shape
	col.one_way_collision = false # Fester Anfangsboden direkt am Bildschirmrand
	floor_body.add_child(col)
	
	# Visuelle Gestaltung des Anfangsbodens (Eis- und Schneeblock bis zum Bildschirmrand)
	var visual = _create_platform_visual(width, INITIAL_FLOOR_HEIGHT, true)
	floor_body.add_child(visual)
	
	platform_container.add_child(floor_body)
	active_platforms.append(floor_body)

func _get_max_horizontal_reach(vertical_step: float) -> float:
	# Flugzeit t_land bis zur Höhe -vertical_step bei v0 = JUMP_VELOCITY (-720) und GRAVITY (1350)
	# 0.5 * GRAVITY * t^2 + JUMP_VELOCITY * t + vertical_step = 0
	var d = (JUMP_VELOCITY * JUMP_VELOCITY) - (2.0 * GRAVITY * vertical_step)
	if d <= 0.0:
		return 220.0
	var t_land = (-JUMP_VELOCITY + sqrt(d)) / GRAVITY
	return MOVE_SPEED * t_land

func _generate_platforms_up_to(target_y: float):
	var floor_top_y = INITIAL_FLOOR_Y - (INITIAL_FLOOR_HEIGHT * 0.5)
	while current_top_platform_y > target_y:
		var barrier_y = floor_top_y - (float(next_ice_barrier_meter) * 10.0)
		
		# Alle 100m Höhe eine Reihe zerstörbarer Eisblöcke einfügen
		if (current_top_platform_y - barrier_y) <= 240.0 and current_top_platform_y > barrier_y:
			# Ausgewogener Absprung-Layer unter der Barriere (ca. 148 px darunter)
			var pre_barrier_y = barrier_y + 148.0
			if current_top_platform_y > pre_barrier_y + 25.0:
				var step_to_pre = current_top_platform_y - pre_barrier_y
				current_top_platform_y = pre_barrier_y
				_spawn_platform_layer(pre_barrier_y, step_to_pre)
				
			# Durchgehende Barriere aus 24 zerstörbaren kurzen Eisblöcken von links nach rechts spawnen
			_spawn_ice_barrier_row(barrier_y, next_ice_barrier_meter)
			next_ice_barrier_meter += 100
			
			# Virtuelle Plattformen auf der Barriere als Referenz für die Schicht darüber
			last_layer_platforms = [
				{ "x": 560.0, "w": 220.0 },
				{ "x": 1360.0, "w": 220.0 }
			]
			last_layer_x_positions = [560.0, 1360.0]
			
			# Nächste Schicht 150 px über der Barriere platzieren
			current_top_platform_y = barrier_y - 150.0
			_spawn_platform_layer(current_top_platform_y, 150.0)
			continue
			
		var step: float
		# Erste Schicht über dem Boden: Erreichbarer erster Schritt (138 px),
		# damit jeder Spieler vom Boden gut auf die erste Plattform springen kann!
		if current_top_platform_y >= floor_top_y - 10.0:
			step = 138.0
		else:
			step = randf_range(PLATFORM_LAYER_STEP_MIN, PLATFORM_LAYER_STEP_MAX)
		current_top_platform_y -= step
		_spawn_platform_layer(current_top_platform_y, step)

func _spawn_platform_layer(layer_y: float, step: float):
	var floor_top_y = INITIAL_FLOOR_Y - (INITIAL_FLOOR_HEIGHT * 0.5)
	var max_reach = _get_max_horizontal_reach(step)
	
	# Begrenzungen für Plattformen (innerhalb der Wände)
	var min_x_bound = WALL_LEFT_X + 60.0
	var max_x_bound = WALL_RIGHT_X - 60.0
	
	# Wenn wir direkt über dem Boden starten, 2 faire Startplattformen links und rechts platzieren
	if layer_y > floor_top_y - 200.0 or last_layer_platforms.is_empty():
		var w1 = 220.0
		var w2 = 220.0
		var p1_x = 560.0
		var p2_x = 1360.0
		
		var plat_1 = _create_single_platform(Vector2(p1_x, layer_y), w1, PLATFORM_HEIGHT)
		var plat_2 = _create_single_platform(Vector2(p2_x, layer_y), w2, PLATFORM_HEIGHT)
		platform_container.add_child(plat_1)
		platform_container.add_child(plat_2)
		active_platforms.append(plat_1)
		active_platforms.append(plat_2)
		
		last_layer_platforms = [
			{ "x": p1_x, "w": w1 },
			{ "x": p2_x, "w": w2 }
		]
		last_layer_x_positions = [p1_x, p2_x]
		return
		
	# Sprungweiten-Definition:
	# "Knapp" = spürbare Lücke (110 bis 165 px), voller Anlauf/Schub im Sprung nötig
	# Aber strikt gedeckelt auf (max_reach - 80.0), damit jeder Sprung garantiert machbar ist!
	var tight_gap_max = clampf(max_reach - 85.0, 115.0, 160.0)
	var tight_gap_min = clampf(tight_gap_max - 40.0, 80.0, 120.0)
	var medium_gap_min = 40.0
	var medium_gap_max = 80.0
	
	var new_layer_platforms: Array[Dictionary] = []
	
	if last_layer_platforms.size() == 2:
		var p_left = last_layer_platforms[0] if last_layer_platforms[0].x <= last_layer_platforms[1].x else last_layer_platforms[1]
		var p_right = last_layer_platforms[1] if last_layer_platforms[0].x <= last_layer_platforms[1].x else last_layer_platforms[0]
		var center_dist = p_right.x - p_left.x
		
		# Zusammenführung auf 1 Plattform, wenn beide nah genug sind (<= 620 px)
		var can_merge = center_dist <= 620.0
		var do_merge = can_merge and (randf() < 0.40)
		
		if do_merge:
			var mid_x = (p_left.x + p_right.x) * 0.5
			var mid_w = randf_range(230.0, 270.0)
			
			# Prüfe Erreichbarkeit von beiden Seiten
			var gap_from_left = (mid_x - mid_w * 0.5) - (p_left.x + p_left.w * 0.5)
			var gap_from_right = (p_right.x - p_right.w * 0.5) - (mid_x + mid_w * 0.5)
			
			if gap_from_left <= max_reach - 75.0 and gap_from_right <= max_reach - 75.0:
				var plat = _create_single_platform(Vector2(mid_x, layer_y), mid_w, PLATFORM_HEIGHT)
				platform_container.add_child(plat)
				active_platforms.append(plat)
				new_layer_platforms.append({ "x": mid_x, "w": mid_w })
		
		# Wenn nicht zusammengeführt: 2 Plattformen erzeugen (jede garantiert erreichbar von ihrer Vorgängerin)
		if new_layer_platforms.is_empty():
			# 1. Linke Plattform
			var w_l = randf_range(PLATFORM_WIDTH_MIN, PLATFORM_WIDTH_MAX)
			var dir_l = 1.0
			if p_left.x < min_x_bound + w_l * 0.5 + 80.0:
				dir_l = 1.0
			elif p_left.x > 820.0 - w_l * 0.5:
				dir_l = -1.0
			else:
				dir_l = 1.0 if randf() < 0.5 else -1.0
				
			var is_tight_l = randf() < 0.65
			var gap_l = randf_range(tight_gap_min, tight_gap_max) if is_tight_l else randf_range(medium_gap_min, medium_gap_max)
			var x_l = p_left.x + dir_l * ((p_left.w + w_l) * 0.5 + gap_l)
			x_l = clampf(x_l, min_x_bound + w_l * 0.5, 840.0 - w_l * 0.5)
			
			# Sicherheits-Klammer: Maximal erreichbarer Abstand
			var actual_gap_l = abs(x_l - p_left.x) - (p_left.w + w_l) * 0.5
			if actual_gap_l > max_reach - 80.0:
				x_l = p_left.x + sign(x_l - p_left.x) * ((p_left.w + w_l) * 0.5 + (max_reach - 85.0))
				
			# 2. Rechte Plattform
			var w_r = randf_range(PLATFORM_WIDTH_MIN, PLATFORM_WIDTH_MAX)
			var dir_r = -1.0
			if p_right.x > max_x_bound - w_r * 0.5 - 80.0:
				dir_r = -1.0
			elif p_right.x < 1100.0 + w_r * 0.5:
				dir_r = 1.0
			else:
				dir_r = -1.0 if randf() < 0.5 else 1.0
				
			var is_tight_r = randf() < 0.65
			var gap_r = randf_range(tight_gap_min, tight_gap_max) if is_tight_r else randf_range(medium_gap_min, medium_gap_max)
			var x_r = p_right.x + dir_r * ((p_right.w + w_r) * 0.5 + gap_r)
			x_r = clampf(x_r, 1080.0 + w_r * 0.5, max_x_bound - w_r * 0.5)
			
			# Sicherheits-Klammer: Maximal erreichbarer Abstand
			var actual_gap_r = abs(x_r - p_right.x) - (p_right.w + w_r) * 0.5
			if actual_gap_r > max_reach - 80.0:
				x_r = p_right.x + sign(x_r - p_right.x) * ((p_right.w + w_r) * 0.5 + (max_reach - 85.0))
				
			var plat_l = _create_single_platform(Vector2(x_l, layer_y), w_l, PLATFORM_HEIGHT)
			var plat_r = _create_single_platform(Vector2(x_r, layer_y), w_r, PLATFORM_HEIGHT)
			platform_container.add_child(plat_l)
			platform_container.add_child(plat_r)
			active_platforms.append(plat_l)
			active_platforms.append(plat_r)
			new_layer_platforms.append({ "x": x_l, "w": w_l })
			new_layer_platforms.append({ "x": x_r, "w": w_r })
	else:
		# Vorherige Schicht hatte 1 Plattform (p_single)
		var p_single = last_layer_platforms[0]
		
		# Aufspaltung in 2 Wege möglich, wenn die Plattform nicht zu nah an den Wänden liegt
		var can_split = p_single.x >= 600.0 and p_single.x <= 1320.0
		var do_split = can_split and (randf() < 0.55)
		
		if do_split:
			var w_l = randf_range(PLATFORM_WIDTH_MIN, PLATFORM_WIDTH_MAX)
			var w_r = randf_range(PLATFORM_WIDTH_MIN, PLATFORM_WIDTH_MAX)
			var gap_l = randf_range(tight_gap_min, tight_gap_max)
			var gap_r = randf_range(tight_gap_min, tight_gap_max)
			
			var x_l = p_single.x - ((p_single.w + w_l) * 0.5 + gap_l)
			var x_r = p_single.x + ((p_single.w + w_r) * 0.5 + gap_r)
			
			x_l = clampf(x_l, min_x_bound + w_l * 0.5, p_single.x - 130.0)
			x_r = clampf(x_r, p_single.x + 130.0, max_x_bound - w_r * 0.5)
			
			# Beide Wege müssen von p_single erreichbar sein
			if abs(x_l - p_single.x) - (p_single.w + w_l) * 0.5 > max_reach - 80.0:
				x_l = p_single.x - ((p_single.w + w_l) * 0.5 + (max_reach - 85.0))
			if abs(x_r - p_single.x) - (p_single.w + w_r) * 0.5 > max_reach - 80.0:
				x_r = p_single.x + ((p_single.w + w_r) * 0.5 + (max_reach - 85.0))
				
			var plat_l = _create_single_platform(Vector2(x_l, layer_y), w_l, PLATFORM_HEIGHT)
			var plat_r = _create_single_platform(Vector2(x_r, layer_y), w_r, PLATFORM_HEIGHT)
			platform_container.add_child(plat_l)
			platform_container.add_child(plat_r)
			active_platforms.append(plat_l)
			active_platforms.append(plat_r)
			new_layer_platforms.append({ "x": x_l, "w": w_l })
			new_layer_platforms.append({ "x": x_r, "w": w_r })
		else:
			# Einzelner Pfad fortsetzen (Zickzack-Sprung)
			var w_single = randf_range(PLATFORM_WIDTH_MIN, PLATFORM_WIDTH_MAX)
			var dir_s = 1.0
			if p_single.x < 560.0:
				dir_s = 1.0
			elif p_single.x > 1360.0:
				dir_s = -1.0
			else:
				dir_s = 1.0 if randf() < 0.5 else -1.0
				
			var is_tight_s = randf() < 0.65
			var gap_s = randf_range(tight_gap_min, tight_gap_max) if is_tight_s else randf_range(medium_gap_min, medium_gap_max)
			var x_single = p_single.x + dir_s * ((p_single.w + w_single) * 0.5 + gap_s)
			x_single = clampf(x_single, min_x_bound + w_single * 0.5, max_x_bound - w_single * 0.5)
			
			var actual_gap_s = abs(x_single - p_single.x) - (p_single.w + w_single) * 0.5
			if actual_gap_s > max_reach - 80.0:
				x_single = p_single.x + sign(x_single - p_single.x) * ((p_single.w + w_single) * 0.5 + (max_reach - 85.0))
				
			var plat_s = _create_single_platform(Vector2(x_single, layer_y), w_single, PLATFORM_HEIGHT)
			platform_container.add_child(plat_s)
			active_platforms.append(plat_s)
			new_layer_platforms.append({ "x": x_single, "w": w_single })
			
	last_layer_platforms = new_layer_platforms
	last_layer_x_positions.clear()
	for p_info in new_layer_platforms:
		last_layer_x_positions.append(p_info.x)

func _create_single_platform(pos: Vector2, w: float, h: float) -> StaticBody2D:
	var body = StaticBody2D.new()
	body.position = pos
	
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(w, h)
	col.shape = shape
	col.one_way_collision = true
	col.one_way_collision_margin = 14.0
	body.add_child(col)
	
	var vis = _create_platform_visual(w, h, false)
	body.add_child(vis)
	return body

func _create_platform_visual(w: float, h: float, is_ground: bool) -> Node2D:
	var node = Node2D.new()
	
	# Eis-Körper (Grundplatte mit pixeligem Rand)
	var base_rect = ColorRect.new()
	base_rect.size = Vector2(w, h)
	base_rect.position = Vector2(-w * 0.5, -h * 0.5)
	base_rect.color = Color(0.18, 0.46, 0.74, 0.96) if not is_ground else Color(0.14, 0.36, 0.62, 1.0)
	node.add_child(base_rect)
	
	# Dunklerer unterer Rand / Schatten
	var shadow_rect = ColorRect.new()
	shadow_rect.size = Vector2(w, 5.0)
	shadow_rect.position = Vector2(-w * 0.5, h * 0.5 - 5.0)
	shadow_rect.color = Color(0.08, 0.22, 0.38, 1.0)
	node.add_child(shadow_rect)
	
	# Schneeschicht oben drauf (glänzendes Weiß/Hellcyan)
	var snow_cap = ColorRect.new()
	var snow_h = 7.0 if not is_ground else 10.0
	snow_cap.size = Vector2(w, snow_h)
	snow_cap.position = Vector2(-w * 0.5, -h * 0.5)
	snow_cap.color = Color(0.92, 0.98, 1.0, 1.0)
	node.add_child(snow_cap)
	
	# Kleine hängende Eiszapfen-Pixel an der Unterseite
	if not is_ground and w >= 160.0:
		var icicle_count = int(w / 45.0)
		for j in range(icicle_count):
			var icicle = ColorRect.new()
			var ic_x = (-w * 0.5) + 18.0 + (j * 42.0) + randf_range(-6.0, 6.0)
			var ic_len = randf_range(6.0, 14.0)
			icicle.size = Vector2(5.0, ic_len)
			icicle.position = Vector2(ic_x, h * 0.5)
			icicle.color = Color(0.72, 0.92, 1.0, 0.88)
			node.add_child(icicle)
			
	return node

func _spawn_ice_barrier_row(barrier_y: float, meter: int):
	# Durchgehende Reihe aus kurzen zerstörbaren Eisblöcken über die gesamte Bildschirmbreite (120 bis 1800 px)
	var total_width = WALL_RIGHT_X - WALL_LEFT_X # 1680.0 px
	var count = int(round(total_width / ICE_BLOCK_WIDTH)) # 24 Blöcke
	
	for i in range(count):
		var bx = WALL_LEFT_X + (float(i) + 0.5) * ICE_BLOCK_WIDTH
		var block = _create_destructible_ice_block(Vector2(bx, barrier_y), ICE_BLOCK_WIDTH, ICE_BLOCK_HEIGHT)
		platform_container.add_child(block)
		active_platforms.append(block)
		
	# Retro Höhen-Markierung dezent hinter der Reihe platzieren
	_spawn_barrier_milestone_badge(barrier_y, meter)

func _create_destructible_ice_block(pos: Vector2, w: float = ICE_BLOCK_WIDTH, h: float = ICE_BLOCK_HEIGHT) -> StaticBody2D:
	var body = StaticBody2D.new()
	body.position = pos
	body.add_to_group("destructible_ice_blocks")
	
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(w, h)
	col.shape = shape
	col.one_way_collision = false # Fester Decken- & Bodenblock (wie im Original Ice Climbers)
	body.add_child(col)
	
	var vis = _create_ice_block_visual(w, h)
	body.add_child(vis)
	return body

func _create_ice_block_visual(w: float, h: float) -> Node2D:
	var node = Node2D.new()
	
	# Eis-Grundkörper (kräftiges, eisiges Cyan-Blau)
	var base_rect = ColorRect.new()
	base_rect.size = Vector2(w, h)
	base_rect.position = Vector2(-w * 0.5, -h * 0.5)
	base_rect.color = Color(0.20, 0.58, 0.86, 0.98)
	node.add_child(base_rect)
	
	# Dunklerer Schatten-Rand unten (3px)
	var bot_edge = ColorRect.new()
	bot_edge.size = Vector2(w, 3.0)
	bot_edge.position = Vector2(-w * 0.5, h * 0.5 - 3.0)
	bot_edge.color = Color(0.08, 0.24, 0.44, 1.0)
	node.add_child(bot_edge)
	
	# Dunklere Fugen-Kante rechts (2px) für klaren Block-Raster-Look
	var right_edge = ColorRect.new()
	right_edge.size = Vector2(2.0, h)
	right_edge.position = Vector2(w * 0.5 - 2.0, -h * 0.5)
	right_edge.color = Color(0.10, 0.28, 0.48, 1.0)
	node.add_child(right_edge)
	
	# Heller Glanz-Streifen links (1px)
	var left_edge = ColorRect.new()
	left_edge.size = Vector2(1.0, h - 3.0)
	left_edge.position = Vector2(-w * 0.5, -h * 0.5 + 4.0)
	left_edge.color = Color(0.65, 0.88, 1.0, 0.65)
	node.add_child(left_edge)
	
	# Schneekappe / Frost-Highlight oben drauf (4px weiß-hellcyan)
	var snow_cap = ColorRect.new()
	snow_cap.size = Vector2(w, 4.0)
	snow_cap.position = Vector2(-w * 0.5, -h * 0.5)
	snow_cap.color = Color(0.92, 0.98, 1.0, 1.0)
	node.add_child(snow_cap)
	
	# Kristalline Glanz-Facette in der Mitte
	var facet = ColorRect.new()
	facet.size = Vector2(w * 0.40, 3.0)
	facet.position = Vector2(-w * 0.20, -2.0)
	facet.color = Color(0.82, 0.95, 1.0, 0.65)
	node.add_child(facet)
	
	# Kleiner funkelnder Kristall-Pixel
	var sparkle = ColorRect.new()
	sparkle.size = Vector2(4.0, 4.0)
	sparkle.position = Vector2(w * 0.22, 2.0)
	sparkle.color = Color(0.96, 1.0, 1.0, 0.85)
	node.add_child(sparkle)
	
	return node

func _spawn_barrier_milestone_badge(barrier_y: float, meter: int):
	if fx_container == null:
		return
	var badge = PanelContainer.new()
	badge.add_to_group("altitude_badges")
	badge.position = Vector2((WALL_LEFT_X + WALL_RIGHT_X) * 0.5 - 120.0, barrier_y - 68.0)
	badge.custom_minimum_size = Vector2(240.0, 40.0)
	badge.z_index = -1
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.15, 0.28, 0.85)
	style.border_color = Color(0.42, 0.82, 1.0, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	badge.add_theme_stylebox_override("panel", style)
	
	var lbl = Label.new()
	lbl.text = "❄  %d M  ❄" % meter
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.96, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.14, 0.28, 1.0))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(lbl)
	
	fx_container.add_child(badge)

func _recycle_old_platforms():
	var death_threshold = camera.position.y + 700.0
	var i = 0
	while i < active_platforms.size():
		var p = active_platforms[i]
		if not is_instance_valid(p):
			active_platforms.remove_at(i)
		elif p.position.y > death_threshold and p.position.y < INITIAL_FLOOR_Y - 50.0:
			p.queue_free()
			active_platforms.remove_at(i)
		else:
			i += 1
			
	var badges = get_tree().get_nodes_in_group("altitude_badges")
	for b in badges:
		if is_instance_valid(b) and b.position.y > death_threshold:
			b.queue_free()

# ==============================================================================
#                             SPIELER-SETUP & SPAWN
# ==============================================================================

func _setup_players():
	players_data.clear()
	for child in player_container.get_children():
		child.queue_free()
		
	var all_spawning_players: Array = []
	for team_idx in range(NetworkManager.computed_teams.size()):
		var team = NetworkManager.computed_teams[team_idx]
		for p in team.get("players", []):
			var p_id = _get_player_id(p)
			var p_name = str(p.get("name", "Spieler"))
			var char_name = str(p.get("character", "Cedric"))
			all_spawning_players.append({
				"id": p_id,
				"name": p_name,
				"character": char_name,
				"team_index": team_idx,
				"team_name": team.get("name", "Team"),
				"team_color": team.get("color", Color(1, 1, 1))
			})
			
	var count = max(1, all_spawning_players.size())
	var spawn_width = (WALL_RIGHT_X - WALL_LEFT_X) - 200.0
	var spacing = spawn_width / float(count + 1)
	
	var floor_top_y = INITIAL_FLOOR_Y - (INITIAL_FLOOR_HEIGHT * 0.5)
	for i in range(all_spawning_players.size()):
		var info = all_spawning_players[i]
		var spawn_x = WALL_LEFT_X + 100.0 + ((i + 1) * spacing)
		# Kapsel-Unterkante liegt bei Y + 38.0 -> exakt auf Bodenhöhe spawn_y
		var spawn_y = floor_top_y - 38.0
		_create_player_node(info, Vector2(spawn_x, spawn_y))

func _get_player_id(player_dict: Dictionary) -> int:
	# 1. Zuerst prüfen, ob es eine aktive Session mit gleichem Namen gibt (Synchronisation nach Reconnect)
	var p_name = str(player_dict.get("name", "")).strip_edges().to_lower()
	for session_id in NetworkManager.player_sessions:
		if str(NetworkManager.player_sessions[session_id].get("name", "")).strip_edges().to_lower() == p_name:
			return int(session_id)
	# 2. Gespeicherte ID als int
	if player_dict.has("id"):
		return int(player_dict["id"])
	return randi() % 90000 + 1000

func _create_player_node(info: Dictionary, spawn_pos: Vector2):
	var pid = info["id"]
	var char_name = info["character"]
	
	# CharacterBody2D
	var body = CharacterBody2D.new()
	body.position = spawn_pos
	body.collision_layer = 2
	body.collision_mask = 1 # Kollidiert mit Plattformen & Wänden
	
	# Collision Shape
	var col = CollisionShape2D.new()
	var cap = CapsuleShape2D.new()
	cap.radius = 22.0
	cap.height = 56.0
	col.shape = cap
	col.position = Vector2(0, 10.0)
	body.add_child(col)
	
	# Animated Sprite aus Templates oder Fallback
	var anim_sprite = _instantiate_character_sprite(char_name)
	anim_sprite.name = "AnimatedSprite"
	body.add_child(anim_sprite)
	
	# Team-Indikator & Namensschild über dem Kopf
	var name_badge = _create_player_overhead_badge(info["name"], info["team_color"])
	name_badge.position = Vector2(0, -56.0)
	body.add_child(name_badge)
	
	player_container.add_child(body)
	
	# Sofort sauber auf den Boden setzen ohne Fallglitch
	body.velocity = Vector2(0.0, 15.0)
	body.move_and_slide()
	
	players_data[pid] = {
		"node": body,
		"name": info["name"],
		"character_name": char_name,
		"team_index": info["team_index"],
		"team_name": info["team_name"],
		"team_color": info["team_color"],
		"alive": true,
		"input_dir": 0.0,
		"input_jump": false,
		"is_holding_jump": false,
		"jump_buffered": 0.0,
		"coyote_time": 0.0,
		"anim_sprite": anim_sprite,
		"overhead_badge": name_badge
	}

func _instantiate_character_sprite(character_name: String) -> AnimatedSprite2D:
	var base = MinigameResultHelper.get_sprite_base(character_name)
	if base.is_empty():
		base = character_name.to_lower()
	if base.is_empty():
		base = "cedric"
		
	# Prüfe ob Template-Szene existiert (Groß-/Kleinschreibung tolerant)
	var possible_names = [character_name, character_name.capitalize(), character_name.to_pascal_case()]
	for c_name in possible_names:
		var scene_path = "res://scenes/characters/%s.tscn" % c_name
		if ResourceLoader.exists(scene_path):
			var scn: PackedScene = load(scene_path)
			var inst = scn.instantiate()
			var sprite_node = inst.get_node_or_null("AnimatedSprite2D")
			if sprite_node and sprite_node is AnimatedSprite2D:
				inst.remove_child(sprite_node)
				inst.queue_free()
				sprite_node.scale = Vector2(4.2, 4.2)
				sprite_node.play("idle")
				return sprite_node
			inst.queue_free()
		
	# Fallback Frames bauen mit vollständigem 4-Frame Run-Cycle
	var frames = SpriteFrames.new()
	var idle_1 = load("res://assets/characters/%s/idle/spr_%s_idle_1.png" % [base, base]) if ResourceLoader.exists("res://assets/characters/%s/idle/spr_%s_idle_1.png" % [base, base]) else null
	var idle_2 = load("res://assets/characters/%s/idle/spr_%s_idle_2.png" % [base, base]) if ResourceLoader.exists("res://assets/characters/%s/idle/spr_%s_idle_2.png" % [base, base]) else null
	var run_1 = load("res://assets/characters/%s/run/spr_%s_run_1.png" % [base, base]) if ResourceLoader.exists("res://assets/characters/%s/run/spr_%s_run_1.png" % [base, base]) else null
	var run_2 = load("res://assets/characters/%s/run/spr_%s_run_2.png" % [base, base]) if ResourceLoader.exists("res://assets/characters/%s/run/spr_%s_run_2.png" % [base, base]) else null
	var run_3 = load("res://assets/characters/%s/run/spr_%s_run_3.png" % [base, base]) if ResourceLoader.exists("res://assets/characters/%s/run/spr_%s_run_3.png" % [base, base]) else null
	var jump_tex = load("res://assets/characters/%s/jump/spr_%s_jump.png" % [base, base]) if ResourceLoader.exists("res://assets/characters/%s/jump/spr_%s_jump.png" % [base, base]) else null
	
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 3.0)
	if idle_1: frames.add_frame("idle", idle_1)
	if idle_2: frames.add_frame("idle", idle_2)
	
	frames.add_animation("run")
	frames.set_animation_speed("run", 8.0)
	if run_1: frames.add_frame("run", run_1)
	if run_2: frames.add_frame("run", run_2)
	if run_3: frames.add_frame("run", run_3)
	if run_2: frames.add_frame("run", run_2)
	elif run_1: frames.add_frame("run", run_1)
	
	frames.add_animation("jump")
	if jump_tex: frames.add_frame("jump", jump_tex)
	elif idle_1: frames.add_frame("jump", idle_1)
	
	var asp = AnimatedSprite2D.new()
	asp.sprite_frames = frames
	asp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	asp.scale = Vector2(4.2, 4.2)
	asp.play("idle")
	return asp

func _create_player_overhead_badge(p_name: String, team_col: Color) -> Node2D:
	var container = Node2D.new()
	
	# Kleiner Pfeil in Teamfarbe
	var arrow = Polygon2D.new()
	arrow.polygon = PackedVector2Array([Vector2(-6, 0), Vector2(6, 0), Vector2(0, 7)])
	arrow.color = team_col
	container.add_child(arrow)
	
	# Name Label
	var lbl = Label.new()
	lbl.text = p_name
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.position = Vector2(-70, -26)
	lbl.size = Vector2(140, 24)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", team_col)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 4)
	container.add_child(lbl)
	
	return container

# ==============================================================================
#                             TEAM SIDEBAR & HUD
# ==============================================================================

func _build_team_sidebar():
	for child in team_sidebar.get_children():
		child.queue_free()
		
	for team_idx in range(NetworkManager.computed_teams.size()):
		var team = NetworkManager.computed_teams[team_idx]
		var team_col = team.get("color", Color(1, 1, 1))
		
		var team_panel = PanelContainer.new()
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(team_col.r * 0.15, team_col.g * 0.15, team_col.b * 0.15, 0.85)
		sb.border_width_left = 3
		sb.border_color = team_col
		sb.corner_radius_top_left = 6
		sb.corner_radius_bottom_left = 6
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		team_panel.add_theme_stylebox_override("panel", sb)
		
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		
		var team_title = Label.new()
		team_title.text = team.get("name", "Team")
		team_title.add_theme_font_size_override("font_size", 16)
		team_title.add_theme_color_override("font_color", team_col)
		vbox.add_child(team_title)
		
		for p in team.get("players", []):
			var pid = _get_player_id(p)
			var row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			
			var char_name = str(p.get("character", "Cedric"))
			var icon = TextureRect.new()
			icon.custom_minimum_size = Vector2(22, 22)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			if NetworkManager.character_textures.has(char_name):
				icon.texture = NetworkManager.character_textures[char_name]
			row.add_child(icon)
			
			var p_label = Label.new()
			p_label.text = str(p.get("name", "Spieler"))
			p_label.add_theme_font_size_override("font_size", 14)
			p_label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
			row.add_child(p_label)
			
			var status_tag = Label.new()
			status_tag.text = "▲"
			status_tag.add_theme_font_size_override("font_size", 12)
			status_tag.add_theme_color_override("font_color", Color(0.35, 0.95, 0.45))
			row.add_child(status_tag)
			
			vbox.add_child(row)
			
			if players_data.has(pid):
				players_data[pid]["hud_card"] = row
				players_data[pid]["hud_status_label"] = status_tag
				
		team_panel.add_child(vbox)
		team_sidebar.add_child(team_panel)

func _update_altitude_hud():
	var floor_top_y = INITIAL_FLOOR_Y - (INITIAL_FLOOR_HEIGHT * 0.5)
	var highest_player_y = floor_top_y
	for pid in players_data:
		var p = players_data[pid]
		if p.get("alive", false):
			var py = p["node"].position.y
			if py < highest_player_y:
				highest_player_y = py
				
	var current_meters = int(max(0.0, (floor_top_y - (highest_player_y + 38.0)) / 10.0))
	altitude_label.text = "HÖHE: %d m" % current_meters
	_update_dynamic_background(float(current_meters))

func _update_dynamic_background(alt_m: float):
	if sky_rect == null or not is_instance_valid(sky_rect):
		return
		
	# Farbverlauf basierend auf erreichter Höhe:
	# 0m bis 60m: Eisiges Tal (Arktisches Dunkelblau)
	# 60m bis 160m: Hoher Berggipfel / Frostiges Eis-Azur
	# 160m bis 280m: Dämmerung / Alpin-Violett
	# 280m bis 420m: Stratosphäre (Tiefes Indigo-Nachtblau)
	# 420m+: Weltraum / Kosmos (Tiefschwarz mit funkelnden Sternen)
	var col_valley = Color(0.05, 0.11, 0.22)
	var col_peak = Color(0.07, 0.20, 0.36)
	var col_twilight = Color(0.14, 0.10, 0.30)
	var col_strato = Color(0.06, 0.04, 0.18)
	var col_space = Color(0.02, 0.02, 0.06)
	
	var target_col: Color
	if alt_m < 60.0:
		var t = clampf(alt_m / 60.0, 0.0, 1.0)
		target_col = col_valley.lerp(col_peak, t)
	elif alt_m < 160.0:
		var t = clampf((alt_m - 60.0) / 100.0, 0.0, 1.0)
		target_col = col_peak.lerp(col_twilight, t)
	elif alt_m < 280.0:
		var t = clampf((alt_m - 160.0) / 120.0, 0.0, 1.0)
		target_col = col_twilight.lerp(col_strato, t)
	else:
		var t = clampf((alt_m - 280.0) / 140.0, 0.0, 1.0)
		target_col = col_strato.lerp(col_space, t)
		
	sky_rect.color = sky_rect.color.lerp(target_col, 0.08)
	
	# Sterne ab 100m sanft einblenden
	if star_field and is_instance_valid(star_field):
		if alt_m > 100.0:
			star_field.emitting = true
			var star_alpha = clampf((alt_m - 100.0) / 180.0, 0.0, 1.0)
			star_field.modulate.a = star_alpha
		else:
			star_field.emitting = false
			star_field.modulate.a = 0.0
			
	# Schnee-Partikel oberhalb der Stratosphäre (> 240m) langsam ausdünnen
	if snow_particles and is_instance_valid(snow_particles):
		if alt_m > 240.0:
			snow_particles.modulate.a = clampf(1.0 - ((alt_m - 240.0) / 160.0), 0.15, 1.0)
		else:
			snow_particles.modulate.a = 1.0

# ==============================================================================
#                             SPIELABLAUF & COUNTDOWN
# ==============================================================================

func _on_start_pressed():
	AudioManager.play_music("ice_climbers")
	if pixel_back_btn:
		pixel_back_btn.visible = false
	if intro_background:
		intro_background.visible = false
		intro_background.process_mode = Node.PROCESS_MODE_DISABLED
		# Vollständig entfernen, damit die TileMap-Deckenkollision bei y=0 komplett verschwindet!
		intro_background.queue_free()
		intro_background = null
	intro_container.visible = false
	world.visible = true
	hud.visible = true
	countdown_label.visible = true
	game_state = "countdown"
	countdown_timer = 3.0
	countdown_label.text = "3"
	countdown_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	AudioManager.play_sfx("countdown_321go")
	
	# Handys bereits auf den Ice-Climbers-Bildschirm schalten, aber DEAKTIVIERT (wie bei Cookie Clickers)!
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "ice_climbers",
		"enabled": false,
		"countdown_text": "3"
	})

func _process(delta):
	if game_state == "countdown":
		_process_countdown(delta)

func _process_countdown(delta):
	countdown_timer -= delta
	var new_text = ""
	if countdown_timer > 2.0:
		new_text = "3"
	elif countdown_timer > 1.0:
		new_text = "2"
	elif countdown_timer > 0.0:
		new_text = "1"
	else:
		new_text = "GO!"
		
	if new_text != "GO!" and new_text != countdown_label.text:
		countdown_label.text = new_text
		NetworkManager.broadcast({
			"type": "ice_climbers_countdown",
			"countdown_text": new_text
		})
	elif new_text == "GO!" and game_state == "countdown":
		countdown_label.text = "GO!"
		countdown_label.modulate = Color(1.0, 0.9, 0.2)
		game_state = "playing"
		
		# Handys jetzt freischalten!
		NetworkManager.broadcast({
			"type": "state_change",
			"state": "ice_climbers",
			"enabled": true,
			"countdown_text": "GO!"
		})
		
		# Countdown nach 0.6s sanft ausblenden
		var tw = create_tween()
		tw.tween_property(countdown_label, "modulate:a", 0.0, 0.5)
		tw.tween_callback(func(): countdown_label.visible = false)

# ==============================================================================
#                             PHYSIK & LOOP
# ==============================================================================

func _physics_process(delta):
	if game_state == "countdown":
		_process_countdown_physics(delta)
		return
	if game_state != "playing":
		return
		
	_process_local_keyboard_input()
	_update_all_players(delta)
	_update_camera(delta)
	_check_player_eliminations()
	_recycle_old_platforms()
	_generate_platforms_up_to(camera.position.y - 1400.0)
	_update_altitude_hud()

func _process_countdown_physics(_delta: float):
	# Hält alle Spieler während des 3-2-1 Countdowns stabil und flackerfrei auf dem Boden
	for pid in players_data:
		var p = players_data[pid]
		if not p["alive"]:
			continue
		var body: CharacterBody2D = p["node"]
		var anim: AnimatedSprite2D = p["anim_sprite"]
		body.velocity.y = 15.0
		body.velocity.x = 0.0
		body.move_and_slide()
		if anim.animation != "idle":
			anim.play("idle")

func _process_local_keyboard_input():
	# Erlaubt das Testen des ersten Spielers direkt über Pfeiltasten / WASD
	var active_pids = players_data.keys()
	if active_pids.is_empty():
		return
	var test_pid = active_pids[0]
	var p = players_data[test_pid]
	if not p["alive"]:
		return
		
	var dir = Input.get_axis("ui_left", "ui_right")
	if dir != 0.0:
		p["input_dir"] = dir
	elif Input.is_key_pressed(KEY_A):
		p["input_dir"] = -1.0
	elif Input.is_key_pressed(KEY_D):
		p["input_dir"] = 1.0
	else:
		p["input_dir"] = 0.0
		
	var j_held = Input.is_action_pressed("ui_accept") or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_W)
	if j_held and not p.get("is_holding_jump", false):
		p["jump_buffered"] = 0.16
	p["is_holding_jump"] = j_held

func _update_all_players(delta: float):
	for pid in players_data:
		var p = players_data[pid]
		if not p["alive"]:
			continue
			
		var body: CharacterBody2D = p["node"]
		var anim: AnimatedSprite2D = p["anim_sprite"]
		
		# Gravitation anwenden
		if not body.is_on_floor():
			body.velocity.y += GRAVITY * delta
			p["coyote_time"] = max(0.0, p["coyote_time"] - delta)
		else:
			body.velocity.y = 15.0 # Hält den Charakter stabil auf One-Way-Plattformen ohne Kontaktflackern
			p["coyote_time"] = 0.18 # Großzügiges Coyote-Window (180ms) für lag-freies Kanten-Timing
			
		# Puffer für Sprung-Eingaben
		if p["input_jump"]:
			p["jump_buffered"] = 0.25 # 250ms Buffer
			p["input_jump"] = false # Einmaliger Impuls pro Tap
		if p["jump_buffered"] > 0.0:
			p["jump_buffered"] -= delta
			
		# Sprung ausführen
		if p["jump_buffered"] > 0.0 and (body.is_on_floor() or p["coyote_time"] > 0.0):
			body.velocity.y = JUMP_VELOCITY
			p["jump_buffered"] = 0.0
			p["coyote_time"] = 0.0
			p["jump_cut_immune"] = 0.20 # Erhöht auf 200ms für zuverlässige Sprünge auch bei schnellem Antippen auf Smartphones
			AudioManager.play_sfx("jump")
			_spawn_jump_dust(body.position + Vector2(0, 24))
			
		# Variable Sprunghöhe (Mario-Mechanik):
		# Wenn der Sprung-Knopf losgelassen wird während der Charakter nach oben steigt,
		# wird der Sprung gekappt (kurzer Klick = kürzerer Sprung, langer Klick = voller Sprung).
		# Aber erst nach der minimalen Takeoff-Immunität (200ms)!
		if p.has("jump_cut_immune") and p["jump_cut_immune"] > 0.0:
			p["jump_cut_immune"] -= delta
		elif not p.get("is_holding_jump", false) and body.velocity.y < -420.0:
			body.velocity.y = -420.0
			
		# Horizontale Bewegung (Snappy Arcade Movement)
		var target_vx = p["input_dir"] * MOVE_SPEED
		if p["input_dir"] != 0.0:
			# Schnellerer Richtungswechsel beim Umdrehen
			var accel = TURN_ACCELERATION if (target_vx * body.velocity.x < 0.0) else ACCELERATION
			body.velocity.x = move_toward(body.velocity.x, target_vx, accel * delta)
			anim.flip_h = p["input_dir"] < 0.0
		else:
			body.velocity.x = move_toward(body.velocity.x, 0.0, FRICTION * delta)
			
		# Animationen sauber steuern (verhindert Frame-Resets und Flackern)
		var is_jumping_in_air = not body.is_on_floor() and (body.velocity.y < -40.0 or p["coyote_time"] <= 0.0)
		if is_jumping_in_air:
			if anim.animation != "jump":
				anim.play("jump")
		else:
			if abs(body.velocity.x) > 15.0:
				if anim.animation != "run":
					anim.play("run")
			else:
				if anim.animation != "idle":
					anim.play("idle")
				
		# Bewegung ausführen
		body.move_and_slide()
		
		# Kopf-Kollision mit zerstörbaren Eisblöcken (Headbonk wie im Original Ice Climbers)
		var coll_count = body.get_slide_collision_count()
		for c_idx in range(coll_count):
			var col = body.get_slide_collision(c_idx)
			var collider = col.get_collider()
			if is_instance_valid(collider) and collider.is_in_group("destructible_ice_blocks"):
				var normal = col.get_normal()
				# Normal muss nach unten zeigen (Kollision von unten gegen den Block)
				# und die Kopf-Position des Spielers muss sich unterhalb des Blocks befinden
				if normal.y > 0.3 and body.global_position.y > collider.global_position.y:
					_break_ice_block(collider, body)
		
		# Horizontale Wandsperre erzwingen
		if body.position.x < WALL_LEFT_X + 24.0:
			body.position.x = WALL_LEFT_X + 24.0
			body.velocity.x = 0.0
		elif body.position.x > WALL_RIGHT_X - 24.0:
			body.position.x = WALL_RIGHT_X - 24.0
			body.velocity.x = 0.0

func _update_camera(delta: float):
	# Finde die höchste Y-Position aller noch lebenden Spieler
	var highest_y = 999999.0
	for pid in players_data:
		var p = players_data[pid]
		if p["alive"]:
			var y = p["node"].position.y
			if y < highest_y:
				highest_y = y
				
	if highest_y >= 900000.0:
		return
		
	# Kamera scrollt nach oben, wenn ein Spieler im oberen Drittel des Bildschirms ist
	var target_camera_y = highest_y + 120.0
	if target_camera_y < camera.position.y:
		# Sanfte, flotte Nachführung (Kamera scrollt AUSSCHLIESSLICH nach oben, niemals zurück!)
		var dist = camera.position.y - target_camera_y
		var scroll_speed = max(420.0, dist * 3.5)
		camera.position.y = move_toward(camera.position.y, target_camera_y, delta * scroll_speed)
		
	# Schnee-Partikel mit der Kamera nach oben bewegen
	if snow_particles:
		snow_particles.position.y = camera.position.y - 540.0

func _check_player_eliminations():
	# Grenze am unteren Bildschirmrand: 540px unter Kamerazentrum + 50px Puffer
	var death_barrier_y = camera.position.y + 580.0
	
	for pid in players_data:
		var p = players_data[pid]
		if not p["alive"]:
			continue
			
		if p["node"].position.y > death_barrier_y:
			_eliminate_player(pid)

func _eliminate_player(pid: int):
	var p = players_data[pid]
	p["alive"] = false
	
	AudioManager.play_sfx("bye_bye")
	_spawn_floating_text(p["node"].position, "ELIMINIERT!", Color(1.0, 0.3, 0.3), "skull")
	
	# Ausblenden und Kollision deaktivieren
	var body: CharacterBody2D = p["node"]
	body.collision_layer = 0
	body.collision_mask = 0
	
	var tw = create_tween().set_parallel(true)
	tw.tween_property(body, "modulate:a", 0.0, 0.45)
	tw.tween_property(body, "scale", Vector2(0.2, 0.2), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	# Sidebar HUD aktualisieren
	if p.has("hud_status_label") and is_instance_valid(p["hud_status_label"]):
		var lbl: Label = p["hud_status_label"]
		lbl.text = "✖"
		lbl.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
	if p.has("hud_card") and is_instance_valid(p["hud_card"]):
		p["hud_card"].modulate = Color(0.5, 0.5, 0.5, 0.6)
		
	# Siegbedingung prüfen
	_check_victory_condition()

func _check_victory_condition():
	if game_state != "playing":
		return
		
	# Zähle überlebende Teams
	var living_teams: Dictionary = {}
	for pid in players_data:
		var p = players_data[pid]
		if p["alive"]:
			living_teams[p["team_index"]] = true
			
	if living_teams.size() == 1:
		# Genau ein Team steht noch!
		var winning_team_idx = living_teams.keys()[0]
		_trigger_victory(winning_team_idx)
	elif living_teams.is_empty():
		# Alle gleichzeitig gefallen -> Unentschieden / Sudden Death
		_trigger_victory(-1)

# ==============================================================================
#                             SIEG & ABSCHLUSS
# ==============================================================================

func _trigger_victory(winning_team_idx: int):
	game_state = "game_over"
	
	# Handys zurück auf Waiting setzen
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})
	
	victory_overlay.visible = true
	victory_overlay.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(victory_overlay, "modulate:a", 1.0, 0.45)
	
	if winning_team_idx != -1 and winning_team_idx < NetworkManager.computed_teams.size():
		var winning_team = NetworkManager.computed_teams[winning_team_idx]
		var team_name = winning_team.get("name", "Team")
		var team_col = winning_team.get("color", Color(1, 1, 1))
		
		victory_title.text = "SIEGER: %s!" % team_name
		victory_title.add_theme_color_override("font_color", team_col)
		victory_subtitle.text = "Das Team hat die eisige Bergspitze bezwungen!"
		
		AudioManager.play_sfx("confetti-pop-sound-effect")
		for p in winning_team.get("players", []):
			if p.has("character"):
				AudioManager.play_character_sfx(p["character"], "win")
				
		# Punkte auf dem Spielbrett vergeben
		if NetworkManager.current_minigame_index != -1:
			var points = 2
			if NetworkManager.current_selecting_team_color == team_col:
				points = 3
			NetworkManager.minigame_winners[NetworkManager.current_minigame_index] = {
				"color": team_col,
				"points": points,
				"selecting_color": NetworkManager.current_selecting_team_color
			}
			for p in winning_team.get("players", []):
				var pid = _get_player_id(p)
				if pid != -1 and NetworkManager.player_sessions.has(pid):
					NetworkManager.player_sessions[pid]["score"] += points
	else:
		victory_title.text = "UNENTSCHIEDEN!"
		victory_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		victory_subtitle.text = "Alle Kletterer sind in die Tiefe gestürzt!"

# ==============================================================================
#                             NETZWERK & STEUERUNG
# ==============================================================================

func _find_player_entry(player_id: int) -> Dictionary:
	if players_data.has(player_id):
		return players_data[player_id]
	if players_data.has(str(player_id)):
		return players_data[str(player_id)]
	# Fallback über Spieler-Namen in player_sessions
	if NetworkManager.player_sessions.has(player_id):
		var s_name = str(NetworkManager.player_sessions[player_id].get("name", "")).strip_edges().to_lower()
		for pid in players_data:
			if str(players_data[pid].get("name", "")).strip_edges().to_lower() == s_name:
				return players_data[pid]
	# Fallback über computed_teams
	for team in NetworkManager.computed_teams:
		for tp in team.get("players", []):
			if int(tp.get("id", -999)) == player_id:
				var tp_name = str(tp.get("name", "")).strip_edges().to_lower()
				for pid in players_data:
					if str(players_data[pid].get("name", "")).strip_edges().to_lower() == tp_name:
						return players_data[pid]
	return {}

func _on_network_message(player_id: int, data: Dictionary):
	if data.get("type") == "ice_climbers_input":
		if game_state != "playing":
			return # Eingaben während des Countdowns ignorieren
		var p = _find_player_entry(player_id)
		if not p.is_empty():
			if data.has("dir"):
				p["input_dir"] = float(data["dir"])
			if data.has("jump"):
				var j_held = bool(data["jump"])
				if j_held and not p.get("is_holding_jump", false):
					p["jump_buffered"] = 0.25
				p["is_holding_jump"] = j_held

func _on_client_connected(player_id: int, _player_name: String):
	if game_state == "playing":
		NetworkManager.send_to_player(player_id, {
			"type": "state_change",
			"state": "ice_climbers",
			"enabled": true,
			"countdown_text": "GO!"
		})
	elif game_state == "countdown":
		NetworkManager.send_to_player(player_id, {
			"type": "state_change",
			"state": "ice_climbers",
			"enabled": false,
			"countdown_text": countdown_label.text
		})
	elif game_state == "intro" or game_state == "game_over":
		NetworkManager.send_to_player(player_id, {
			"type": "state_change",
			"state": "waiting"
		})

# ==============================================================================
#                             VISUELLE EFFEKTE
# ==============================================================================

func _spawn_jump_dust(pos: Vector2):
	if fx_container == null:
		return
	var dust = ColorRect.new()
	dust.size = Vector2(28.0, 6.0)
	dust.position = pos - Vector2(14.0, 3.0)
	dust.color = Color(0.85, 0.95, 1.0, 0.85)
	fx_container.add_child(dust)
	
	var tw = create_tween().set_parallel(true)
	tw.tween_property(dust, "scale", Vector2(1.5, 0.2), 0.22)
	tw.tween_property(dust, "modulate:a", 0.0, 0.22)
	tw.finished.connect(func(): if is_instance_valid(dust): dust.queue_free())

func _spawn_floating_text(pos: Vector2, text: String, color: Color, _icon_name: String = ""):
	if fx_container == null:
		return
	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.position = pos - Vector2(100, 40)
	lbl.size = Vector2(200, 32)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 6)
	fx_container.add_child(lbl)
	
	var tw = create_tween()
	tw.tween_property(lbl, "position:y", pos.y - 95.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.35).set_delay(0.40)
	tw.finished.connect(func(): if is_instance_valid(lbl): lbl.queue_free())

func _break_ice_block(block: StaticBody2D, player_body: CharacterBody2D):
	if not is_instance_valid(block) or not block.is_in_group("destructible_ice_blocks"):
		return
		
	var block_pos = block.global_position
	block.remove_from_group("destructible_ice_blocks")
	active_platforms.erase(block)
	
	for child in block.get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)
			
	AudioManager.play_sfx("hit")
	_spawn_ice_shatter_fx(block_pos)
	
	if is_instance_valid(player_body):
		# Knackiger Arcade-Rückstoß nach unten beim Kopf-Aufprall
		player_body.velocity.y = 80.0
		
	block.queue_free()
	
	# Prüfen, ob der Kopf des Spielers (Radius 22px) auch einen direkt angrenzenden Block berührt
	if is_instance_valid(player_body):
		var p_x = player_body.global_position.x
		for neighbor in get_tree().get_nodes_in_group("destructible_ice_blocks"):
			if is_instance_valid(neighbor) and neighbor != block:
				if abs(neighbor.global_position.y - block_pos.y) < 15.0:
					var dist_x = abs(neighbor.global_position.x - p_x)
					if dist_x < (ICE_BLOCK_WIDTH * 0.5 + 16.0):
						neighbor.remove_from_group("destructible_ice_blocks")
						active_platforms.erase(neighbor)
						for child in neighbor.get_children():
							if child is CollisionShape2D:
								child.set_deferred("disabled", true)
						_spawn_ice_shatter_fx(neighbor.global_position)
						neighbor.queue_free()

func _spawn_ice_shatter_fx(pos: Vector2):
	if fx_container == null:
		return
		
	var shard_colors = [
		Color(0.92, 0.98, 1.0, 1.0),
		Color(0.65, 0.88, 1.0, 0.95),
		Color(0.35, 0.70, 0.95, 0.90),
		Color(0.18, 0.45, 0.75, 0.85)
	]
	
	# Fliegende Eissplitter
	for i in range(10):
		var shard = ColorRect.new()
		var sw = randf_range(5.0, 10.0)
		var sh = randf_range(5.0, 10.0)
		shard.size = Vector2(sw, sh)
		shard.position = pos + Vector2(randf_range(-25.0, 25.0), randf_range(-10.0, 10.0))
		shard.color = shard_colors[i % shard_colors.size()]
		fx_container.add_child(shard)
		
		var target_offset = Vector2(
			randf_range(-100.0, 100.0),
			randf_range(-60.0, 130.0)
		)
		var tw = create_tween().set_parallel(true)
		tw.tween_property(shard, "position", shard.position + target_offset, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(shard, "rotation", randf_range(-3.5, 3.5), 0.42)
		tw.tween_property(shard, "scale", Vector2(0.2, 0.2), 0.42)
		tw.tween_property(shard, "modulate:a", 0.0, 0.42).set_ease(Tween.EASE_IN)
		tw.finished.connect(func(): if is_instance_valid(shard): shard.queue_free())
		
	# Weiß-cyaner Explosions-Flash
	var flash = ColorRect.new()
	flash.size = Vector2(50.0, 24.0)
	flash.position = pos - Vector2(25.0, 12.0)
	flash.color = Color(1.0, 1.0, 1.0, 0.85)
	fx_container.add_child(flash)
	
	var f_tw = create_tween().set_parallel(true)
	f_tw.tween_property(flash, "scale", Vector2(1.8, 1.8), 0.18)
	f_tw.tween_property(flash, "modulate:a", 0.0, 0.18)
	f_tw.finished.connect(func(): if is_instance_valid(flash): flash.queue_free())
