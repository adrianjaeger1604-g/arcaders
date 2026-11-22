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
const GameButtonScene = preload("res://scenes/ui/GameButton.tscn")

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
@onready var pixel_back_btn = find_child("PixelBackButton", true, false)

@onready var sky_rect = get_node_or_null("SkyBackgroundLayer/SkyRect")

@onready var world = $World
@onready var camera = $World/Camera2D
@onready var platform_container = $World/Platforms
@onready var player_container = $World/Players
@onready var fx_container = $World/FX
@onready var snow_particles = $World/SnowParticles
@onready var left_wall_column = get_node_or_null("World/LeftWallColumn")
@onready var right_wall_column = get_node_or_null("World/RightWallColumn")

@onready var hud = $HUD
@onready var altitude_label = $HUD/TopBar/Margin/HBox/AltitudeLabel
@onready var top_banner = $HUD/TopBar/Margin/HBox/TitleLabel
@onready var countdown_label = $HUD/CountdownLabel
@onready var winner_overlay = $HUD/MinigameWinnerOverlay

# State
var game_state: String = "intro" # "intro", "test_room", "countdown", "playing", "game_over"
var countdown_timer: float = 3.0
var highest_climbed_y: float = INITIAL_FLOOR_Y - (INITIAL_FLOOR_HEIGHT * 0.5)
var current_top_platform_y: float = INITIAL_FLOOR_Y - (INITIAL_FLOOR_HEIGHT * 0.5)
var active_platforms: Array[StaticBody2D] = []
var last_layer_platforms: Array[Dictionary] = [] # Array von { "x": float, "w": float }
var last_layer_x_positions: Array[float] = []
var next_ice_barrier_meter: int = 100

# Testraum
var is_test_room: bool = false
var test_room_container: Node2D = null
var test_room_ui: Control = null
var test_room_floor_btn: Button = null
var test_room_start_triggered: bool = false

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
		start_btn.text = "STEUERUNG TESTEN"
		start_btn.pressed.connect(_on_start_pressed)
	if pixel_back_btn:
		if "auto_return_to_main_board" in pixel_back_btn and pixel_back_btn.auto_return_to_main_board:
			# PixelBackButton führt cancel_and_return_to_board bereits selbstständig aus
			pass
		else:
			pixel_back_btn.pressed.connect(_on_back_pressed)
		
	NetworkManager.message_received.connect(_on_network_message)
	NetworkManager.client_connected.connect(_on_client_connected)
	
	if winner_overlay:
		winner_overlay.visible = false
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
	_apply_white_brick_walls()
	if platform_container:
		platform_container.z_index = 0
	if player_container:
		player_container.z_index = 10
	if fx_container:
		fx_container.z_index = 15
	_spawn_initial_floor()
	_setup_players()
	
	camera.position = Vector2(VIEWPORT_WIDTH * 0.5, 540.0)
	_update_altitude_hud()
	_setup_intro_scroll()

func _setup_intro_scroll():
	var scroll_area = get_node_or_null("IntroContainer/VBox/ScrollArea")
	var inst_lbl = get_node_or_null("IntroContainer/VBox/ScrollArea/InstructionContainer/Instruction")
	if scroll_area and inst_lbl:
		await get_tree().process_frame
		if is_instance_valid(inst_lbl) and is_instance_valid(scroll_area):
			var content_h = inst_lbl.get_minimum_size().y + 8.0
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
	if not NetworkManager.minigame_winners.has(NetworkManager.current_minigame_index):
		NetworkManager.current_minigame_index = -1
	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/MainBoard.tscn")

func _on_return_pressed():
	AudioManager.stop_music()
	NetworkManager.is_replaying_minigame = false
	if not NetworkManager.minigame_winners.has(NetworkManager.current_minigame_index):
		NetworkManager.current_minigame_index = -1
	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/MainBoard.tscn")

# ==============================================================================
#                             ARENA & PLATTFORMEN
# ==============================================================================

func _build_arena_walls():
	# Linke Wand (Kollision bündig an der Innenkante WALL_LEFT_X)
	var left_wall = StaticBody2D.new()
	left_wall.position = Vector2(WALL_LEFT_X - 40.0, 0)
	var left_shape = CollisionShape2D.new()
	var l_rect = RectangleShape2D.new()
	l_rect.size = Vector2(80.0, 200000.0) # Riesige vertikale Sperre
	left_shape.shape = l_rect
	left_wall.add_child(left_shape)
	world.add_child(left_wall)
	
	# Rechte Wand (Kollision bündig an der Innenkante WALL_RIGHT_X)
	var right_wall = StaticBody2D.new()
	right_wall.position = Vector2(WALL_RIGHT_X + 40.0, 0)
	var right_shape = CollisionShape2D.new()
	var r_rect = RectangleShape2D.new()
	r_rect.size = Vector2(80.0, 200000.0)
	right_shape.shape = r_rect
	right_wall.add_child(right_shape)
	world.add_child(right_wall)

func _apply_white_brick_walls():
	var brick_tex = _create_white_brick_texture()
	if left_wall_column:
		left_wall_column.texture = brick_tex
		left_wall_column.stretch_mode = TextureRect.STRETCH_TILE
		left_wall_column.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if right_wall_column:
		right_wall_column.texture = brick_tex
		right_wall_column.stretch_mode = TextureRect.STRETCH_TILE
		right_wall_column.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

func _create_white_brick_texture() -> ImageTexture:
	var tw = 120
	var th = 40
	var img = Image.create(tw, th, false, Image.FORMAT_RGBA8)
	
	var col_mortar = Color(0.12, 0.12, 0.16, 1.0) # Dunkle Fuge für scharfe Abgrenzung
	var col_brick_base = Color(0.93, 0.95, 0.97, 1.0) # Weißer Backstein
	var col_brick_hi = Color(1.0, 1.0, 1.0, 1.0) # Glanzkante oben/links
	var col_brick_sh = Color(0.74, 0.77, 0.83, 1.0) # Icy-Schattenkante unten/rechts
	var col_brick_groove = Color(0.86, 0.89, 0.93, 1.0) # Feiner Texturstrich
	
	img.fill(col_mortar)
	
	# 3 Backsteine nebeneinander (je 38px + 2px Fuge), 2 Reihen versetzt
	for row in range(2):
		var y_start = row * 20 + 2
		var y_end = (row + 1) * 20 - 1
		var x_offset = 0 if row == 0 else -20
		
		for b in range(-1, 4):
			var bx_start = x_offset + b * 40 + 2
			var bx_end = x_offset + (b + 1) * 40 - 1
			
			for y in range(y_start, y_end):
				for x in range(bx_start, bx_end):
					if x < 0 or x >= tw:
						continue
					if y == y_start or x == bx_start:
						img.set_pixel(x, y, col_brick_hi)
					elif y == y_end - 1 or x == bx_end - 1:
						img.set_pixel(x, y, col_brick_sh)
					elif y == y_start + 8:
						img.set_pixel(x, y, col_brick_groove)
					else:
						img.set_pixel(x, y, col_brick_base)
						
	return ImageTexture.create_from_image(img)

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
				
			# Durchgehende Barriere aus 24 zerstörbaren kurzen Eisblöcken spawnen (50% Chance für 2-zeilig)
			var is_double = randf() < 0.5
			_spawn_ice_barrier_row(barrier_y, next_ice_barrier_meter, is_double)
			next_ice_barrier_meter += 100
			
			var top_barrier_y = barrier_y - ICE_BLOCK_HEIGHT if is_double else barrier_y
			
			# Virtuelle Plattformen auf der Barriere als Referenz für die Schicht darüber
			last_layer_platforms = [
				{ "x": 560.0, "w": 220.0 },
				{ "x": 1360.0, "w": 220.0 }
			]
			last_layer_x_positions = [560.0, 1360.0]
			
			# Nächste Schicht 150 px über der Barriere platzieren
			current_top_platform_y = top_barrier_y - 150.0
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
	var alt_meters = max(0.0, (floor_top_y - layer_y) / 10.0)
	var allow_crumbling = alt_meters >= 500.0
	
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
				var is_crumble_m = allow_crumbling and (randf() < 0.20)
				var plat = _create_single_platform(Vector2(mid_x, layer_y), mid_w, PLATFORM_HEIGHT, is_crumble_m)
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
				
			var crumble_l = false
			var crumble_r = false
			if allow_crumbling and randf() < 0.25:
				if randf() < 0.5:
					crumble_l = true
				else:
					crumble_r = true
					
			var plat_l = _create_single_platform(Vector2(x_l, layer_y), w_l, PLATFORM_HEIGHT, crumble_l)
			var plat_r = _create_single_platform(Vector2(x_r, layer_y), w_r, PLATFORM_HEIGHT, crumble_r)
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
				
			var crumble_split_l = false
			var crumble_split_r = false
			if allow_crumbling and randf() < 0.25:
				if randf() < 0.5:
					crumble_split_l = true
				else:
					crumble_split_r = true
					
			var plat_l = _create_single_platform(Vector2(x_l, layer_y), w_l, PLATFORM_HEIGHT, crumble_split_l)
			var plat_r = _create_single_platform(Vector2(x_r, layer_y), w_r, PLATFORM_HEIGHT, crumble_split_r)
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
				
			var is_crumble_s = allow_crumbling and (randf() < 0.18)
			var plat_s = _create_single_platform(Vector2(x_single, layer_y), w_single, PLATFORM_HEIGHT, is_crumble_s)
			platform_container.add_child(plat_s)
			active_platforms.append(plat_s)
			new_layer_platforms.append({ "x": x_single, "w": w_single })
			
	last_layer_platforms = new_layer_platforms
	last_layer_x_positions.clear()
	for p_info in new_layer_platforms:
		last_layer_x_positions.append(p_info.x)

func _create_single_platform(pos: Vector2, w: float, h: float, is_crumbling: bool = false) -> StaticBody2D:
	var body = StaticBody2D.new()
	body.position = pos
	
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(w, h)
	col.shape = shape
	col.one_way_collision = true
	col.one_way_collision_margin = 14.0
	body.add_child(col)
	
	var vis = _create_platform_visual(w, h, false, is_crumbling)
	vis.name = "Visual"
	body.add_child(vis)
	
	if is_crumbling:
		body.add_to_group("crumbling_platforms")
		body.set_meta("is_crumbling", true)
		body.set_meta("crumble_state", "idle")
		body.set_meta("timer", 2.0)
		body.set_meta("crumb_timer", 0.0)
		body.set_meta("fall_velocity", 0.0)
		body.set_meta("width", w)
		body.set_meta("height", h)
		body.set_meta("orig_x", pos.x)
		body.set_meta("rot_speed", randf_range(-1.2, 1.2))
		
	return body

func _create_platform_visual(w: float, h: float, is_ground: bool, is_crumbling: bool = false) -> Node2D:
	var node = Node2D.new()
	
	# Grundkörper: Eisplatte (Tiefes Ozeanblau mit kühlem Farbverlauf, bei brüchigen Plattformen rissiger Graublau-Ton)
	var base_rect = ColorRect.new()
	base_rect.size = Vector2(w, h)
	base_rect.position = Vector2(-w * 0.5, -h * 0.5)
	if is_ground:
		base_rect.color = Color(0.12, 0.32, 0.56, 1.0)
	elif is_crumbling:
		base_rect.color = Color(0.20, 0.44, 0.62, 1.0)
	else:
		base_rect.color = Color(0.18, 0.46, 0.74, 1.0)
	node.add_child(base_rect)
	
	# Untere Eisschicht (dunklere Tiefe / 3D-Kante)
	var bot_shade = ColorRect.new()
	bot_shade.size = Vector2(w, 8.0)
	bot_shade.position = Vector2(-w * 0.5, h * 0.5 - 8.0)
	bot_shade.color = Color(0.08, 0.20, 0.36, 1.0) if is_crumbling else Color(0.08, 0.22, 0.40, 1.0)
	node.add_child(bot_shade)
	
	# Dunkler Abschlussstrich ganz unten (2px)
	var bot_edge = ColorRect.new()
	bot_edge.size = Vector2(w, 2.0)
	bot_edge.position = Vector2(-w * 0.5, h * 0.5 - 2.0)
	bot_edge.color = Color(0.04, 0.12, 0.24, 1.0)
	node.add_child(bot_edge)
	
	# Gechiselte Eisfacetten / Kristall-Lichtreflexe
	if not is_ground and w >= 80.0:
		var facet_1 = ColorRect.new()
		facet_1.size = Vector2(w * 0.35, 4.0)
		facet_1.position = Vector2(-w * 0.35, -2.0)
		facet_1.color = Color(0.45, 0.76, 0.96, 0.55) if not is_crumbling else Color(0.55, 0.80, 0.95, 0.45)
		node.add_child(facet_1)
		
		var facet_2 = ColorRect.new()
		facet_2.size = Vector2(w * 0.25, 3.0)
		facet_2.position = Vector2(w * 0.12, 1.0)
		facet_2.color = Color(0.60, 0.85, 1.0, 0.45) if not is_crumbling else Color(0.70, 0.88, 1.0, 0.35)
		node.add_child(facet_2)
		
		# Seitliche Eiskanten-Abschrägung (Pixel-Ecken)
		var corner_l = ColorRect.new()
		corner_l.size = Vector2(3.0, 6.0)
		corner_l.position = Vector2(-w * 0.5, h * 0.5 - 6.0)
		corner_l.color = Color(0.04, 0.12, 0.24, 1.0)
		node.add_child(corner_l)
		
		var corner_r = ColorRect.new()
		corner_r.size = Vector2(3.0, 6.0)
		corner_r.position = Vector2(w * 0.5 - 3.0, h * 0.5 - 6.0)
		corner_r.color = Color(0.04, 0.12, 0.24, 1.0)
		node.add_child(corner_r)

	# Schneeschicht oben (flauschiges Weiß mit sanfter Frost-Schattenkante)
	var snow_h = 7.0 if not is_ground else 10.0
	if not is_crumbling:
		var snow_cap = ColorRect.new()
		snow_cap.size = Vector2(w, snow_h)
		snow_cap.position = Vector2(-w * 0.5, -h * 0.5)
		snow_cap.color = Color(0.96, 0.98, 1.0, 1.0)
		node.add_child(snow_cap)
		
		var snow_sub = ColorRect.new()
		snow_sub.size = Vector2(w, 2.0)
		snow_sub.position = Vector2(-w * 0.5, -h * 0.5 + snow_h - 2.0)
		snow_sub.color = Color(0.76, 0.88, 0.98, 0.9)
		node.add_child(snow_sub)
	else:
		# Brüchige Plattform: Sichtbare Bruchfuge in der Schneedecke
		var break_x = -w * 0.12
		var left_w = (w * 0.5) + break_x - 3.0
		var right_x = break_x + 3.0
		var right_w = (w * 0.5) - break_x - 3.0
		
		var cap_l = ColorRect.new()
		cap_l.size = Vector2(left_w, snow_h)
		cap_l.position = Vector2(-w * 0.5, -h * 0.5)
		cap_l.color = Color(0.94, 0.96, 0.98, 1.0)
		node.add_child(cap_l)
		
		var cap_r = ColorRect.new()
		cap_r.size = Vector2(right_w, snow_h)
		cap_r.position = Vector2(right_x, -h * 0.5)
		cap_r.color = Color(0.94, 0.96, 0.98, 1.0)
		node.add_child(cap_r)
		
		# Schattenkante links & rechts
		var sub_l = ColorRect.new()
		sub_l.size = Vector2(left_w, 2.0)
		sub_l.position = Vector2(-w * 0.5, -h * 0.5 + snow_h - 2.0)
		sub_l.color = Color(0.72, 0.84, 0.94, 0.9)
		node.add_child(sub_l)
		
		var sub_r = ColorRect.new()
		sub_r.size = Vector2(right_w, 2.0)
		sub_r.position = Vector2(right_x, -h * 0.5 + snow_h - 2.0)
		sub_r.color = Color(0.72, 0.84, 0.94, 0.9)
		node.add_child(sub_r)

	# Hängende pixelige Eiszapfen an der Unterseite
	if not is_ground and w >= 120.0 and not is_crumbling:
		var icicle_count = int(w / 38.0)
		for j in range(icicle_count):
			var ic_x = (-w * 0.5) + 16.0 + (j * 36.0) + randf_range(-4.0, 4.0)
			var ic_len = randf_range(8.0, 16.0)
			
			# Breiter Eiszapfen-Körper
			var ic_base = ColorRect.new()
			ic_base.size = Vector2(4.0, ic_len)
			ic_base.position = Vector2(ic_x, h * 0.5)
			ic_base.color = Color(0.48, 0.78, 0.98, 0.85)
			node.add_child(ic_base)
			
			# Spitze des Eiszapfens
			var ic_tip = ColorRect.new()
			ic_tip.size = Vector2(2.0, 4.0)
			ic_tip.position = Vector2(ic_x + 1.0, h * 0.5 + ic_len)
			ic_tip.color = Color(0.90, 0.96, 1.0, 0.95)
			node.add_child(ic_tip)

	# Spezifische Risse für brüchige Plattformen
	if is_crumbling:
		var cracks = Node2D.new()
		cracks.name = "Cracks"
		
		var c1_x = -w * 0.12
		var segs = [
			Vector2(c1_x - 1.0, -h * 0.5 + 2.0), Vector2(3.0, 6.0),
			Vector2(c1_x + 1.0, -h * 0.5 + 7.0), Vector2(2.0, 6.0),
			Vector2(c1_x - 2.0, -h * 0.5 + 12.0), Vector2(3.0, 6.0),
			Vector2(c1_x, h * 0.5 - 6.0), Vector2(2.0, 6.0)
		]
		for s in range(0, segs.size(), 2):
			var cr = ColorRect.new()
			cr.position = segs[s]
			cr.size = segs[s + 1]
			cr.color = Color(0.04, 0.10, 0.20, 0.95)
			cracks.add_child(cr)
			
			var ch = ColorRect.new()
			ch.position = segs[s] + Vector2(cr.size.x, 0)
			ch.size = Vector2(1.0, cr.size.y)
			ch.color = Color(0.85, 0.95, 1.0, 0.8)
			cracks.add_child(ch)
			
		if w >= 130.0:
			var c2_x = w * 0.20
			var segs2 = [
				Vector2(c2_x, -h * 0.5 + 4.0), Vector2(2.0, 5.0),
				Vector2(c2_x + 2.0, -h * 0.5 + 8.0), Vector2(3.0, 5.0),
				Vector2(c2_x - 1.0, -h * 0.5 + 12.0), Vector2(2.0, 5.0)
			]
			for s in range(0, segs2.size(), 2):
				var cr2 = ColorRect.new()
				cr2.position = segs2[s]
				cr2.size = segs2[s + 1]
				cr2.color = Color(0.04, 0.10, 0.20, 0.95)
				cracks.add_child(cr2)
				
		node.add_child(cracks)
			
	return node

func _spawn_ice_barrier_row(barrier_y: float, meter: int, is_double: bool = false):
	# Durchgehende Reihe(n) aus kurzen zerstörbaren Eisblöcken über die gesamte Bildschirmbreite (120 bis 1800 px)
	var total_width = WALL_RIGHT_X - WALL_LEFT_X # 1680.0 px
	var count = int(round(total_width / ICE_BLOCK_WIDTH)) # 24 Blöcke
	
	var row_count = 2 if is_double else 1
	for r in range(row_count):
		var row_y = barrier_y - (float(r) * ICE_BLOCK_HEIGHT)
		var x_stagger = (ICE_BLOCK_WIDTH * 0.5) if (r % 2 == 1) else 0.0
		
		for i in range(count):
			var bx = WALL_LEFT_X + (float(i) + 0.5) * ICE_BLOCK_WIDTH + x_stagger
			if bx > WALL_RIGHT_X - (ICE_BLOCK_WIDTH * 0.5):
				bx -= total_width
			var block = _create_destructible_ice_block(Vector2(bx, row_y), ICE_BLOCK_WIDTH, ICE_BLOCK_HEIGHT)
			platform_container.add_child(block)
			active_platforms.append(block)
			
	# Retro Höhen-Markierung dezent hinter der obersten Reihe platzieren
	var top_barrier_y = barrier_y - (float(row_count - 1) * ICE_BLOCK_HEIGHT)
	_spawn_barrier_milestone_badge(top_barrier_y, meter)

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
	
	# Äußerer dunkler Pixel-Rahmen für perfekten Retro-Raster-Look
	var border = ColorRect.new()
	border.size = Vector2(w, h)
	border.position = Vector2(-w * 0.5, -h * 0.5)
	border.color = Color(0.06, 0.14, 0.24, 1.0)
	node.add_child(border)
	
	# Eis-Grundkörper (kräftiges, eisiges Cyan)
	var body_rect = ColorRect.new()
	body_rect.size = Vector2(w - 2.0, h - 2.0)
	body_rect.position = Vector2(-w * 0.5 + 1.0, -h * 0.5 + 1.0)
	body_rect.color = Color(0.24, 0.62, 0.90, 1.0)
	node.add_child(body_rect)
	
	# Dunklerer Schatten-Rand unten (3px) und rechts (2px)
	var bot_edge = ColorRect.new()
	bot_edge.size = Vector2(w - 2.0, 3.0)
	bot_edge.position = Vector2(-w * 0.5 + 1.0, h * 0.5 - 4.0)
	bot_edge.color = Color(0.08, 0.26, 0.48, 1.0)
	node.add_child(bot_edge)
	
	var right_edge = ColorRect.new()
	right_edge.size = Vector2(2.0, h - 2.0)
	right_edge.position = Vector2(w * 0.5 - 3.0, -h * 0.5 + 1.0)
	right_edge.color = Color(0.10, 0.30, 0.52, 1.0)
	node.add_child(right_edge)
	
	# Heller Glanz-Streifen links (2px)
	var left_edge = ColorRect.new()
	left_edge.size = Vector2(2.0, h - 4.0)
	left_edge.position = Vector2(-w * 0.5 + 1.0, -h * 0.5 + 1.0)
	left_edge.color = Color(0.72, 0.92, 1.0, 0.75)
	node.add_child(left_edge)
	
	# Schneekappe / Frost-Highlight oben drauf (4px weiß)
	var snow_cap = ColorRect.new()
	snow_cap.size = Vector2(w - 2.0, 4.0)
	snow_cap.position = Vector2(-w * 0.5 + 1.0, -h * 0.5 + 1.0)
	snow_cap.color = Color(0.96, 0.98, 1.0, 1.0)
	node.add_child(snow_cap)
	
	# Horizontale Chisel-Fuge in der Mitte (wie ein echter Eis-Backstein)
	var mid_groove = ColorRect.new()
	mid_groove.size = Vector2(w - 8.0, 2.0)
	mid_groove.position = Vector2(-w * 0.5 + 4.0, 0.0)
	mid_groove.color = Color(0.12, 0.38, 0.65, 0.9)
	node.add_child(mid_groove)
	
	var mid_hi = ColorRect.new()
	mid_hi.size = Vector2(w - 8.0, 1.0)
	mid_hi.position = Vector2(-w * 0.5 + 4.0, 2.0)
	mid_hi.color = Color(0.60, 0.88, 1.0, 0.6)
	node.add_child(mid_hi)
	
	# Kristalline Facette
	var facet = ColorRect.new()
	facet.size = Vector2(w * 0.35, 4.0)
	facet.position = Vector2(-w * 0.25, -6.0)
	facet.color = Color(0.78, 0.92, 1.0, 0.55)
	node.add_child(facet)
	
	# Funkelnder Kristall-Pixel
	var sparkle = ColorRect.new()
	sparkle.size = Vector2(3.0, 3.0)
	sparkle.position = Vector2(w * 0.25, -5.0)
	sparkle.color = Color(1.0, 1.0, 1.0, 0.95)
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
	lbl.text = "%d M" % meter
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
	body.z_index = 10
	
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
	if character_name.to_lower() == "cedi" or character_name.strip_edges().is_empty() or character_name.to_lower() == "unknown":
		possible_names.append("Cedric")
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
	container.z_index = 2
	container.z_as_relative = true
	
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
	lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.06, 0.98))
	lbl.add_theme_constant_override("outline_size", 6)
	container.add_child(lbl)
	
	return container

# ==============================================================================
#                             HUD & HÖHE
# ==============================================================================

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

func _update_dynamic_background(_alt_m: float):
	if sky_rect and is_instance_valid(sky_rect):
		sky_rect.color = Color(0, 0, 0, 1)

# ==============================================================================
#                             SPIELABLAUF & COUNTDOWN
# ==============================================================================

func _on_start_pressed():
	AudioManager.play_music("ice_climbers")
	if pixel_back_btn:
		pixel_back_btn.visible = true
	if is_instance_valid(intro_background):
		intro_background.visible = false
		intro_background.process_mode = Node.PROCESS_MODE_DISABLED
		intro_background.queue_free()
		intro_background = null
	intro_container.visible = false
	_enter_test_room()

func _enter_test_room():
	game_state = "test_room"
	is_test_room = true
	test_room_start_triggered = false
	
	world.visible = true
	hud.visible = true
	countdown_label.visible = false
	
	top_banner.text = "ICE CLIMBERS: TESTRAUM"
	altitude_label.text = "TESTRAUM"
	
	camera.position = Vector2(VIEWPORT_WIDTH * 0.5, 540.0)
	
	_build_test_room_arena()
	_reset_players_to_floor()
	
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "ice_climbers",
		"enabled": true,
		"countdown_text": "TEST",
		"banner_text": "Testraum: Steuerung ausprobieren!"
	})

func _build_test_room_arena():
	active_platforms.clear()
	for child in platform_container.get_children():
		child.queue_free()
		
	test_room_container = Node2D.new()
	test_room_container.name = "TestRoomContainer"
	test_room_container.z_index = 0
	world.add_child(test_room_container)
	if is_instance_valid(player_container):
		world.move_child(test_room_container, player_container.get_index())
	
	_spawn_initial_floor()
	
	# Test-Plattformen (Tier 1 bis Tier 5, keine Überlappung mit Blöcken!)
	var test_plats = [
		# Tier 1 (Y = 810)
		{ "pos": Vector2(460.0, 810.0), "w": 240.0 },
		{ "pos": Vector2(1460.0, 810.0), "w": 240.0 },
		
		# Tier 2 (Y = 660)
		{ "pos": Vector2(280.0, 660.0), "w": 180.0 },
		{ "pos": Vector2(960.0, 660.0), "w": 300.0 },
		{ "pos": Vector2(1640.0, 660.0), "w": 180.0 },
		
		# Tier 3 (Y = 510)
		{ "pos": Vector2(560.0, 510.0), "w": 260.0 },
		{ "pos": Vector2(1360.0, 510.0), "w": 260.0 },
		
		# Tier 4 (Y = 360)
		{ "pos": Vector2(280.0, 360.0), "w": 180.0 },
		{ "pos": Vector2(960.0, 360.0), "w": 280.0 },
		{ "pos": Vector2(1640.0, 360.0), "w": 180.0 },
		
		# Tier 5 (Y = 210)
		{ "pos": Vector2(600.0, 210.0), "w": 260.0 },
		{ "pos": Vector2(1320.0, 210.0), "w": 260.0 }
	]
	for p_info in test_plats:
		var p_node = _create_single_platform(p_info["pos"], p_info["w"], PLATFORM_HEIGHT, false)
		test_room_container.add_child(p_node)
		active_platforms.append(p_node)
		
	# Zerstörbare Eisblöcke zum Testen (keine Überlappung mit Plattformen!)
	var block_configs = [
		# Tier 1 Mitte (Y = 810)
		Vector2(855.0, 810.0), Vector2(925.0, 810.0), Vector2(995.0, 810.0), Vector2(1065.0, 810.0),
		
		# Tier 2 Seiten (Y = 660)
		Vector2(500.0, 660.0), Vector2(570.0, 660.0), Vector2(640.0, 660.0),
		Vector2(1280.0, 660.0), Vector2(1350.0, 660.0), Vector2(1420.0, 660.0),
		
		# Tier 3 Mitte (Y = 510)
		Vector2(855.0, 510.0), Vector2(925.0, 510.0), Vector2(995.0, 510.0), Vector2(1065.0, 510.0),
		
		# Tier 4 Seiten (Y = 360)
		Vector2(500.0, 360.0), Vector2(570.0, 360.0), Vector2(640.0, 360.0),
		Vector2(1280.0, 360.0), Vector2(1350.0, 360.0), Vector2(1420.0, 360.0),
		
		# Tier 5 Mitte (Y = 210)
		Vector2(855.0, 210.0), Vector2(925.0, 210.0), Vector2(995.0, 210.0), Vector2(1065.0, 210.0)
	]
	for b_pos in block_configs:
		var block = _create_destructible_ice_block(b_pos, ICE_BLOCK_WIDTH, ICE_BLOCK_HEIGHT)
		block.add_to_group("test_room_blocks")
		test_room_container.add_child(block)
		active_platforms.append(block)
		
	_spawn_test_room_floor_button()

func _spawn_test_room_floor_button():
	if is_instance_valid(test_room_ui):
		test_room_ui.queue_free()
		
	test_room_ui = Control.new()
	test_room_ui.name = "TestRoomUI"
	test_room_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	test_room_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	test_room_ui.theme = preload("res://resources/global_button_theme.tres")
	hud.add_child(test_room_ui)
	
	# Primärbutton mittig der X-Achse mit exakt 24px Abstand zum unteren Bildschirmrand
	test_room_floor_btn = GameButtonScene.instantiate()
	test_room_floor_btn.theme = preload("res://resources/global_button_theme.tres")
	test_room_floor_btn.text = "SPIEL STARTEN"
	test_room_floor_btn.custom_minimum_size = Vector2(360, 60)
	test_room_floor_btn.pivot_offset = Vector2(180, 30)
	test_room_floor_btn.anchor_left = 0.5
	test_room_floor_btn.anchor_right = 0.5
	test_room_floor_btn.anchor_top = 1.0
	test_room_floor_btn.anchor_bottom = 1.0
	test_room_floor_btn.offset_left = -180.0
	test_room_floor_btn.offset_right = 180.0
	test_room_floor_btn.offset_top = -84.0
	test_room_floor_btn.offset_bottom = -24.0
	test_room_floor_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	test_room_floor_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	test_room_floor_btn.pressed.connect(_on_test_room_start_button_pressed)
	_connect_buttons_sfx(test_room_floor_btn)
	test_room_ui.add_child(test_room_floor_btn)

func _on_test_room_start_button_pressed():
	if test_room_start_triggered:
		return
	test_room_start_triggered = true
	AudioManager.play_sfx("button_press")
	
	if is_instance_valid(test_room_floor_btn):
		test_room_floor_btn.disabled = true
		var tw = create_tween()
		tw.tween_property(test_room_floor_btn, "scale", Vector2(0.96, 0.96), 0.1)
		tw.tween_property(test_room_floor_btn, "modulate:a", 0.0, 0.25)
		
	_start_real_game_from_test_room()

func _start_real_game_from_test_room():
	is_test_room = false
	
	if is_instance_valid(intro_background):
		intro_background.visible = false
		intro_background.process_mode = Node.PROCESS_MODE_DISABLED
		intro_background.queue_free()
		intro_background = null
		
	if is_instance_valid(test_room_container):
		test_room_container.queue_free()
		test_room_container = null
	if is_instance_valid(test_room_ui):
		test_room_ui.queue_free()
		test_room_ui = null
		
	active_platforms.clear()
	for child in platform_container.get_children():
		child.queue_free()
		
	_spawn_initial_floor()
	current_top_platform_y = INITIAL_FLOOR_Y - (INITIAL_FLOOR_HEIGHT * 0.5)
	highest_climbed_y = current_top_platform_y
	last_layer_platforms.clear()
	last_layer_x_positions.clear()
	next_ice_barrier_meter = 100
	_generate_platforms_up_to(INITIAL_FLOOR_Y - 1800.0)
	
	_reset_players_to_floor()
	
	camera.position = Vector2(VIEWPORT_WIDTH * 0.5, 540.0)
	top_banner.text = "ICE CLIMBERS"
	_update_altitude_hud()
	
	game_state = "countdown"
	countdown_timer = 3.0
	countdown_label.visible = true
	countdown_label.text = "3"
	countdown_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	AudioManager.play_sfx("countdown_321go")
	
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "ice_climbers",
		"enabled": false,
		"countdown_text": "3",
		"banner_text": "Bereithalten... Countdown läuft!"
	})

func _reset_players_to_floor():
	var all_pids = players_data.keys()
	var count = max(1, all_pids.size())
	var spawn_width = (WALL_RIGHT_X - WALL_LEFT_X) - 200.0
	var spacing = spawn_width / float(count + 1)
	var floor_top_y = INITIAL_FLOOR_Y - (INITIAL_FLOOR_HEIGHT * 0.5)
	
	for i in range(all_pids.size()):
		var pid = all_pids[i]
		var p = players_data[pid]
		var body: CharacterBody2D = p["node"]
		if not is_instance_valid(body):
			continue
			
		var spawn_x = WALL_LEFT_X + 100.0 + ((i + 1) * spacing)
		var spawn_y = floor_top_y - 38.0
		body.position = Vector2(spawn_x, spawn_y)
		body.velocity = Vector2(0.0, 15.0)
		body.collision_layer = 2
		body.collision_mask = 1
		body.modulate = Color(1, 1, 1, 1)
		body.scale = Vector2(1, 1)
		
		p["alive"] = true
		p["input_dir"] = 0.0
		p["input_jump"] = false
		p["is_holding_jump"] = false
		p["jump_buffered"] = 0.0
		p["coyote_time"] = 0.0
		
		var anim: AnimatedSprite2D = p["anim_sprite"]
		if anim:
			anim.play("idle")

func _schedule_test_block_respawn(pos: Vector2):
	if game_state == "test_room":
		get_tree().create_timer(4.0).timeout.connect(func():
			if game_state == "test_room" and is_instance_valid(test_room_container):
				_respawn_test_block(pos)
		)

func _respawn_test_block(pos: Vector2):
	if game_state != "test_room" or not is_instance_valid(test_room_container):
		return
	var block = _create_destructible_ice_block(pos, ICE_BLOCK_WIDTH, ICE_BLOCK_HEIGHT)
	block.add_to_group("test_room_blocks")
	test_room_container.add_child(block)
	active_platforms.append(block)
	
	block.scale = Vector2(0.1, 0.1)
	var tw = create_tween()
	tw.tween_property(block, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
			"countdown_text": "GO!",
			"banner_text": "Klettere nach oben! Nicht abstürzen!"
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
	if game_state == "test_room":
		_process_local_keyboard_input()
		_update_all_players(delta)
		return
	if game_state != "playing":
		return
		
	_process_local_keyboard_input()
	_update_all_players(delta)
	_process_crumbling_platforms(delta)
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

var _last_kb_dir: float = 0.0
var _last_kb_jump: bool = false

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
	if dir == 0.0:
		if Input.is_key_pressed(KEY_A):
			dir = -1.0
		elif Input.is_key_pressed(KEY_D):
			dir = 1.0

	if dir != 0.0:
		p["input_dir"] = dir
		_last_kb_dir = dir
	elif _last_kb_dir != 0.0:
		# Setze nur auf 0 zurück, wenn die Richtungs-Eingabe vorher von der Tastatur kam
		p["input_dir"] = 0.0
		_last_kb_dir = 0.0
		
	var j_held = Input.is_action_pressed("ui_accept") or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_W)
	if j_held:
		if not _last_kb_jump:
			p["jump_buffered"] = 0.25
		p["is_holding_jump"] = true
		_last_kb_jump = true
	elif _last_kb_jump:
		# Setze Sprunghaltung nur zurück, wenn sie über Tastatur gehalten wurde
		p["is_holding_jump"] = false
		_last_kb_jump = false

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
			p["jump_cut_immune"] = 0.04 # 40ms kurzes Takeoff-Fenster für extrem reaktive Sprunghöhe
			AudioManager.play_sfx("jump")
			_spawn_jump_dust(body.position + Vector2(0, 24))
			
		# Variable Sprunghöhe (Mario-Mechanik):
		# Wenn der Sprung-Knopf losgelassen wird während der Charakter nach oben steigt,
		# wird der Sprung sofort gekappt (kurzer Tap = kleiner Sprung ca. 75-80px, halten = voller Sprung ca. 192px).
		if p.has("jump_cut_immune") and p["jump_cut_immune"] > 0.0:
			p["jump_cut_immune"] -= delta
		elif not p.get("is_holding_jump", false) and body.velocity.y < -320.0:
			body.velocity.y = -320.0
			
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

func _process_crumbling_platforms(delta: float):
	var crumbling_nodes = get_tree().get_nodes_in_group("crumbling_platforms")
	if crumbling_nodes.is_empty():
		return
		
	# 1. Ermittle welche brüchigen Plattformen aktuell von mindestens einem lebenden Spieler betreten werden
	var stepped_plats: Dictionary = {}
	for pid in players_data:
		var p = players_data[pid]
		if not p.get("alive", false):
			continue
		var p_body: CharacterBody2D = p["node"]
		if not is_instance_valid(p_body):
			continue
			
		# A) Prüfung über Slide-Kollision (Bodenkontakt)
		if p_body.is_on_floor():
			var coll_count = p_body.get_slide_collision_count()
			for c_idx in range(coll_count):
				var col = p_body.get_slide_collision(c_idx)
				if col.get_normal().y < -0.5:
					var collider = col.get_collider()
					if is_instance_valid(collider) and collider.is_in_group("crumbling_platforms"):
						stepped_plats[collider] = true
						
		# B) Robuste Geometrie-Prüfung (Unterkante der Spieler-Kapsel liegt bei Y + 38.0)
		var feet_pos = p_body.global_position + Vector2(0, 38.0)
		for plat in crumbling_nodes:
			if not is_instance_valid(plat):
				continue
			if plat.get_meta("crumble_state", "idle") == "falling":
				continue
			var pw = plat.get_meta("width", 200.0)
			var ph = plat.get_meta("height", 24.0)
			var plat_pos = plat.global_position
			var plat_top = plat_pos.y - ph * 0.5
			if abs(feet_pos.x - plat_pos.x) <= pw * 0.5 + 6.0:
				if feet_pos.y >= plat_top - 6.0 and feet_pos.y <= plat_top + 16.0:
					if p_body.velocity.y >= -15.0:
						stepped_plats[plat] = true

	# 2. Status-Maschine für jede brüchige Plattform aktualisieren
	for plat in crumbling_nodes:
		if not is_instance_valid(plat):
			continue
			
		var state = plat.get_meta("crumble_state", "idle")
		var is_stepped = stepped_plats.has(plat)
		
		match state:
			"idle":
				if is_stepped:
					# Spieler hat die Plattform betreten
					plat.set_meta("crumble_state", "stepped")
					plat.set_meta("has_been_stepped", true)
					AudioManager.play_sfx("hit")
					
			"stepped":
				if not is_stepped:
					# Spieler war drauf und ist nun abgesprungen / weitergegangen!
					# 2-Sekunden-Countdown startet
					plat.set_meta("crumble_state", "countdown")
					plat.set_meta("timer", 2.0)
					plat.set_meta("crumb_timer", 0.0)
					AudioManager.play_sfx("hit")
					
			"countdown":
				var t = plat.get_meta("timer", 2.0) - delta
				plat.set_meta("timer", t)
				
				# Visuelles Zittern / Rütteln (wird intensiver je näher der Einsturz rückt)
				var vis = plat.get_node_or_null("Visual")
				var progress = clampf(1.0 - (t / 2.0), 0.0, 1.0)
				var shake_amp = 1.5 + progress * 3.5
				if vis:
					vis.position.x = sin(Time.get_ticks_msec() * 0.05) * shake_amp
					var cracks = vis.get_node_or_null("Cracks")
					if cracks:
						cracks.modulate = Color(1.3, 0.7, 0.7) if (int(Time.get_ticks_msec() / 80) % 2 == 0) else Color(1.0, 1.0, 1.0)
						
				# Bröckelnde Eisstaub-Partikel fallen herab
				var ct = plat.get_meta("crumb_timer", 0.0) - delta
				if ct <= 0.0:
					plat.set_meta("crumb_timer", randf_range(0.12, 0.22))
					var pw = plat.get_meta("width", 200.0)
					_spawn_crumb_particle(plat.global_position + Vector2(randf_range(-pw * 0.4, pw * 0.4), 10.0))
					
				if t <= 0.0:
					# 2 Sekunden abgelaufen: Plattform stürzt ab!
					plat.set_meta("crumble_state", "falling")
					plat.set_meta("fall_velocity", 120.0)
					plat.collision_layer = 0
					plat.collision_mask = 0
					for child in plat.get_children():
						if child is CollisionShape2D:
							child.set_deferred("disabled", true)
					AudioManager.play_sfx("block_break")
					
					var pw = plat.get_meta("width", 200.0)
					for k in range(3):
						var offset_x = (-0.35 + 0.35 * float(k)) * pw
						_spawn_ice_shatter_fx(plat.global_position + Vector2(offset_x, 0))
						
			"falling":
				var vy = plat.get_meta("fall_velocity", 120.0) + GRAVITY * 1.1 * delta
				plat.set_meta("fall_velocity", vy)
				plat.position.y += vy * delta
				plat.rotation += plat.get_meta("rot_speed", 0.6) * delta
				
				# Aufräumen sobald unter Bildschirmrand
				if plat.position.y > camera.position.y + 750.0:
					active_platforms.erase(plat)
					plat.queue_free()

func _spawn_crumb_particle(pos: Vector2):
	if fx_container == null:
		return
	var dot = ColorRect.new()
	var dsize = randf_range(2.0, 4.0)
	dot.size = Vector2(dsize, dsize)
	dot.position = pos
	dot.color = Color(0.85, 0.95, 1.0, 0.85)
	fx_container.add_child(dot)
	
	var tw = create_tween().set_parallel(true)
	tw.tween_property(dot, "position:y", pos.y + randf_range(30.0, 65.0), 0.35)
	tw.tween_property(dot, "position:x", pos.x + randf_range(-6.0, 6.0), 0.35)
	tw.tween_property(dot, "modulate:a", 0.0, 0.35)
	tw.finished.connect(func(): if is_instance_valid(dot): dot.queue_free())

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
	
	if winning_team_idx != -1 and winning_team_idx < NetworkManager.computed_teams.size():
		var winning_team = NetworkManager.computed_teams[winning_team_idx]
		var team_col = winning_team.get("color", Color(1, 1, 1))
		var points = 2
		if NetworkManager.current_selecting_team_color == team_col:
			points = 3
			
		# Punkte auf dem Spielbrett vergeben
		if NetworkManager.current_minigame_index != -1:
			NetworkManager.minigame_winners[NetworkManager.current_minigame_index] = {
				"color": team_col,
				"points": points,
				"selecting_color": NetworkManager.current_selecting_team_color
			}
			for p in winning_team.get("players", []):
				var pid = _get_player_id(p)
				if pid != -1 and NetworkManager.player_sessions.has(pid):
					NetworkManager.player_sessions[pid]["score"] += points
					
		if winner_overlay:
			winner_overlay.setup_winner(winning_team, points, "Das Team hat die eisige Bergspitze bezwungen!")
	else:
		if winner_overlay:
			winner_overlay.setup_winner(null, 0, "Alle Kletterer sind in die Tiefe gestürzt!")

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
		if game_state != "playing" and game_state != "test_room":
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
			"countdown_text": "GO!",
			"banner_text": "Klettere nach oben! Nicht abstürzen!"
		})
	elif game_state == "test_room":
		NetworkManager.send_to_player(player_id, {
			"type": "state_change",
			"state": "ice_climbers",
			"enabled": true,
			"countdown_text": "TEST",
			"banner_text": "Testraum: Steuerung ausprobieren!"
		})
	elif game_state == "countdown":
		NetworkManager.send_to_player(player_id, {
			"type": "state_change",
			"state": "ice_climbers",
			"enabled": false,
			"countdown_text": countdown_label.text,
			"banner_text": "Bereithalten... Countdown läuft!"
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
	var is_test_block = block.is_in_group("test_room_blocks")
	block.remove_from_group("destructible_ice_blocks")
	active_platforms.erase(block)
	
	for child in block.get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)
			
	AudioManager.play_sfx("block_break")
	_spawn_ice_shatter_fx(block_pos)
	
	if is_instance_valid(player_body):
		# Knackiger Arcade-Rückstoß nach unten beim Kopf-Aufprall
		player_body.velocity.y = 80.0
		
	block.queue_free()
	
	# Im Testraum: Zerstörten Block nach 4 Sekunden automatisch respawnen
	if is_test_block:
		_schedule_test_block_respawn(block_pos)
	
	# Prüfen, ob der Kopf des Spielers (Radius 22px) auch einen direkt angrenzenden Block berührt
	if is_instance_valid(player_body):
		var p_x = player_body.global_position.x
		for neighbor in get_tree().get_nodes_in_group("destructible_ice_blocks"):
			if is_instance_valid(neighbor) and neighbor != block:
				if abs(neighbor.global_position.y - block_pos.y) < 15.0:
					var dist_x = abs(neighbor.global_position.x - p_x)
					if dist_x < (ICE_BLOCK_WIDTH * 0.5 + 16.0):
						var n_pos = neighbor.global_position
						var n_is_test = neighbor.is_in_group("test_room_blocks")
						neighbor.remove_from_group("destructible_ice_blocks")
						active_platforms.erase(neighbor)
						for child in neighbor.get_children():
							if child is CollisionShape2D:
								child.set_deferred("disabled", true)
						_spawn_ice_shatter_fx(n_pos)
						neighbor.queue_free()
						if n_is_test:
							_schedule_test_block_respawn(n_pos)

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
