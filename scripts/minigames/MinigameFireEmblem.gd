extends Control

const MinigameResultHelper = preload("res://scripts/minigames/MinigameResultHelper.gd")

enum Phase {
	INTRO,
	EQUIPMENT,
	REVEAL,
	BATTLE,
	GAME_OVER
}

const GRID_SIZE: int = 11
const CENTER: Vector2i = Vector2i(5, 5)
const MAX_ARENA_DIST: int = 7 # abs(x-5) + abs(y-5) <= 7 ergibt 85 Felder in Hexagon-/Achteck-Form

const ROLE_CONFIG = {
	"tank": {
		"name": "Tank",
		"icon": "shield",
		"hp": 8,
		"dmg": 2,
		"steps": 2,
		"desc": "8 HP  •  2 DMG  •  2 Felder"
	},
	"dps": {
		"name": "Damage Dealer",
		"icon": "sword",
		"hp": 5,
		"dmg": 3,
		"steps": 2,
		"desc": "5 HP  •  3 DMG  •  2 Felder"
	},
	"utility": {
		"name": "Utility",
		"icon": "boots",
		"hp": 6,
		"dmg": 2,
		"steps": 3,
		"desc": "6 HP  •  2 DMG  •  3 Felder"
	}
}

const RPS_CONFIG = {
	"scissors": {
		"name": "Schere",
		"icon": "scissors",
		"beats": "paper",
		"color": Color(1.0, 0.42, 0.42, 1.0)
	},
	"rock": {
		"name": "Stein",
		"icon": "rock",
		"beats": "scissors",
		"color": Color(0.65, 0.72, 0.82, 1.0)
	},
	"paper": {
		"name": "Papier",
		"icon": "paper",
		"beats": "rock",
		"color": Color(0.98, 0.88, 0.38, 1.0)
	}
}

const SPECIAL_TYPES = {
	"heal": {
		"name": "Heilquelle",
		"icon": "heal",
		"desc": "+2 HP beim Betreten",
		"color": Color(0.22, 0.75, 0.38, 0.9)
	},
	"type_swap": {
		"name": "Typ-Wechsel",
		"icon": "swap",
		"desc": "Wähle Schere, Stein oder Papier",
		"color": Color(0.32, 0.65, 0.95, 0.9)
	},
	"meteor": {
		"name": "Meteor-Schrein",
		"icon": "meteor",
		"desc": "2 Feuerschaden im + Bereich",
		"color": Color(0.95, 0.42, 0.15, 0.9)
	},
	"dmg_boost": {
		"name": "Schwert-Schrein",
		"icon": "sword",
		"desc": "+1 Schaden für 2 Runden",
		"color": Color(0.88, 0.25, 0.35, 0.9)
	},
	"teleport": {
		"name": "Teleporter",
		"icon": "portal",
		"desc": "Teleportiert in die sichere Mitte",
		"color": Color(0.68, 0.35, 0.95, 0.9)
	}
}

@onready var pixel_back_btn = get_node_or_null("PixelBackButton")
@onready var bg_tilemap = get_node_or_null("BackgroundTileMap")
@onready var intro_container: Control = $IntroContainer
@onready var start_equip_btn: Button = $IntroContainer/VBox/StartGameButton

@onready var equip_container: Control = $EquipmentContainer
@onready var equip_title: Label = $EquipmentContainer/VBox/Title
@onready var equip_status: Label = $EquipmentContainer/VBox/StatusLabel
@onready var equip_grid: GridContainer = $EquipmentContainer/VBox/PlayersGrid
@onready var equip_action_btn: Button = $EquipmentContainer/VBox/ActionButton

@onready var battle_container: Control = $BattleContainer
@onready var round_label: Label = $BattleContainer/MainHBox/LeftPanel/Margin/VBox/RoundLabel
@onready var zone_label: Label = $BattleContainer/MainHBox/LeftPanel/Margin/VBox/ZoneLabel
@onready var teams_status_list: VBoxContainer = $BattleContainer/MainHBox/LeftPanel/Margin/VBox/Scroll/TeamsStatusList
@onready var board_viewport: Control = $BattleContainer/MainHBox/BoardCenter/BoardFrame
@onready var turn_banner: Label = $BattleContainer/MainHBox/RightPanel/Margin/VBox/TurnStatusLabel
@onready var log_label: RichTextLabel = $BattleContainer/MainHBox/RightPanel/Margin/VBox/LogPanel/Margin/CombatLog
@onready var execute_turn_btn: Button = $BattleContainer/MainHBox/RightPanel/Margin/VBox/ExecuteTurnButton
@onready var back_to_board_btn: Button = $BattleContainer/MainHBox/RightPanel/Margin/VBox/BackToBoardButton
@onready var winner_overlay = get_node_or_null("MinigameWinnerOverlay")

var current_phase: Phase = Phase.INTRO
var round_number: int = 1
var zone_max_dist: int = 7 # Alle Felder mit manhattan_dist > zone_max_dist sind in der roten Zone
var is_resolving_turn: bool = false

# Spieler-Daten im Minispiel:
# p_id -> {
#   "id": int, "name": String, "character": String, "team_index": int, "team_name": String, "team_color": Color,
#   "rps": String, "role": String, "equip_ready": bool,
#   "hp": int, "max_hp": int, "dmg": int, "steps": int, "alive": bool,
#   "pos": Vector2i, "dmg_boost_turns": int,
#   "turn_ready": bool, "planned_path": Array[Vector2i], "attack_dir": String, "meteor_target_id": int
# }
var fe_players: Dictionary = {}

# Sonderfelder auf dem Spielfeld: "x,y" -> "heal" | "type_swap" | "meteor" | "dmg_boost" | "teleport"
var special_tiles: Dictionary = {}

# UI-Referenzen für das Spielfeld
var tile_nodes: Dictionary = {} # Vector2i -> Panel
var unit_nodes: Dictionary = {} # p_id -> Control
var tile_fire_nodes: Dictionary = {} # Vector2i -> TextureRect (aktive Feuer-Animation auf Kacheln)
var perimeter_fire_nodes: Array[Dictionary] = [] # [{ "node": TextureRect, "phase": int, "ring": int }]
var fx_layer: Control = null
var fire_ring_layer: Control = null
var board_camera_root: Control = null
var cam_tween: Tween = null
var phase_bg_rect: TextureRect = null
var tex_barracks_bg: Texture2D = null
var tex_battlefield_bg: Texture2D = null
var board_grid_origin: Vector2 = Vector2.ZERO
var tile_px_size: float = 60.0
var tile_gap: float = 3.0

# Pixel-Art Feuer- & Schlachtfeld-Assets
var tex_fire_frames: Array[Texture2D] = []
var tex_ember_frames: Array[Texture2D] = []
var tex_battlefield_props: Dictionary = {}
var fire_anim_accum: float = 0.0
var fire_anim_step: int = 0

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

func _setup_phase_backgrounds():
	tex_barracks_bg = _load_texture_safe("res://assets/minigames/fire_emblem/barracks_bg.png")
	tex_battlefield_bg = _load_texture_safe("res://assets/minigames/fire_emblem/battlefield_bg.png")
	
	phase_bg_rect = TextureRect.new()
	phase_bg_rect.name = "PhaseBackgroundRect"
	phase_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	phase_bg_rect.pivot_offset = Vector2.ZERO
	phase_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	phase_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	phase_bg_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	phase_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phase_bg_rect.visible = false
	add_child(phase_bg_rect)
	move_child(phase_bg_rect, 2)
	
	_init_battlefield_pixel_assets()

func _init_battlefield_pixel_assets():
	# 1. Vier animierte Pixel-Art Feuer-Frames (28x28) exakt in Kachelgröße
	tex_fire_frames.clear()
	var peak_offsets = [
		[5, 10, 14, 18, 22],
		[4, 9, 13, 18, 22],
		[6, 10, 15, 19, 23],
		[5, 9, 14, 19, 22]
	]
	var peak_heights = [
		[14, 20, 23, 18, 13],
		[16, 18, 21, 22, 15],
		[13, 22, 19, 17, 16],
		[15, 19, 24, 20, 14]
	]
	for f_idx in range(4):
		var f_img = Image.create(28, 28, false, Image.FORMAT_RGBA8)
		f_img.fill(Color(0, 0, 0, 0))
		var centers: Array = peak_offsets[f_idx]
		var heights: Array = peak_heights[f_idx]
		
		for py in range(1, 27):
			var y_from_bottom = 26 - py
			for px in range(2, 26):
				# Berechne Flammen-Intensität über mehrere Pixel-Flammenzungen innerhalb der Kachel
				var heat = 0.0
				for c_i in range(centers.size()):
					var cx = float(centers[c_i]) + sin(float(py + f_idx * 3) * 0.48 + float(c_i)) * 1.15
					var h_max = float(heights[c_i])
					var dist_x = abs(float(px) - cx)
					var width_at_y = max(1.0, (1.0 - float(y_from_bottom) / (h_max + 2.0)) * 4.4)
					if y_from_bottom <= h_max and dist_x <= width_at_y:
						var local_h = (1.0 - dist_x / width_at_y) * (1.0 - float(y_from_bottom) / (h_max + 2.5))
						heat = max(heat, local_h)
				if y_from_bottom <= 5:
					var edge_fade = 1.0 - max(0.0, (abs(float(px) - 13.5) - 9.0) / 3.5)
					heat = max(heat, (1.0 - float(y_from_bottom) / 6.5) * 0.68 * edge_fade)
					
				if heat > 0.14:
					var c = Color(0.24, 0.05, 0.04, 0.92) # Dunkle Kontur
					if heat > 0.68:
						c = Color(1.0, 0.94, 0.42, 0.98) # Weißgelber Flammenkern
					elif heat > 0.46:
						c = Color(1.0, 0.68, 0.16, 0.96) # Goldorange
					elif heat > 0.28:
						c = Color(0.95, 0.34, 0.09, 0.94) # Feuerrot-Orange
					elif heat > 0.18:
						c = Color(0.68, 0.13, 0.06, 0.90) # Tiefrot
					f_img.set_pixel(px, py, c)
					
		# Aufsteigende Pixel-Funken (Embers) oben innerhalb der Kachel
		for s_i in range(4):
			var sx = (5 + s_i * 5 + f_idx * 2 + (s_i % 2)) % 18 + 5
			var sy = (2 + (s_i * 7 - f_idx * 3 + 28)) % 9 + 2
			f_img.set_pixel(sx, sy, Color(1.0, 0.86, 0.28, 0.95))
			if sy + 1 < 26:
				f_img.set_pixel(sx, sy + 1, Color(0.96, 0.42, 0.12, 0.88))
		tex_fire_frames.append(ImageTexture.create_from_image(f_img))
		
	# 3. Vorwarn-Glutkranz (2 Frames) für den nächsten Ring vor dem Schrumpfen
	tex_ember_frames.clear()
	for e_idx in range(2):
		var e_img = Image.create(28, 28, false, Image.FORMAT_RGBA8)
		e_img.fill(Color(0, 0, 0, 0))
		for py in range(22, 28):
			for px in range(2, 26):
				if (px + py + e_idx) % 2 == 0:
					var is_hot = ((px * 5 + py * 3 + e_idx) % 4 == 0)
					e_img.set_pixel(px, py, Color(1.0, 0.62, 0.16, 0.78) if is_hot else Color(0.82, 0.24, 0.08, 0.62))
		tex_ember_frames.append(ImageTexture.create_from_image(e_img))
		
	# 4. Kleine Pixel-Art Schlachtfeld-Relikte (Rüstung, Helm, zerbrochenes Schwert, Schild, kahle Erde)
	tex_battlefield_props["helmet"] = _build_prop_texture([
		"........................",
		"........................",
		"........######..........",
		".......#SSSSSS#.........",
		"......#SSWWWWSS#........",
		"......#SSSSSSSS#........",
		"......#SS####SS#........",
		"......#S#....#S#........",
		"......#SS####SS#........",
		".......#SSSSSS#.........",
		".....dddd######ddd......",
		"....ddddddddddddddd.....",
		"........................"
	])
	tex_battlefield_props["shield"] = _build_prop_texture([
		"........................",
		".......########.........",
		".....##BBBBBBBB##.......",
		"....#BBGGGGGGGGBB#......",
		"....#BGBBBBBBBBGB#......",
		"....#BGBBGGGGGBGB#......",
		".....#BGGGGGGGGB#.......",
		"......##BBBBBB##........",
		"........######..........",
		".....dddddddddddddd.....",
		"........................"
	])
	tex_battlefield_props["sword"] = _build_prop_texture([
		"........................",
		"...............##.......",
		"..............#GG#......",
		".............#G##.......",
		"...........##B#.........",
		"..........#WW#..........",
		".........#SS#...........",
		"........#SS#............",
		".......#SS#.............",
		"......ddddddd...........",
		".....ddddddddd..........",
		"........................"
	])
	tex_battlefield_props["armor"] = _build_prop_texture([
		"........................",
		".....####....####.......",
		"....#SSSS####SSSS#......",
		"....#SSWWWWWWWWSS#......",
		".....#SSSSSSSSSS#.......",
		".....#SSGGGGGGSS#.......",
		"......#SSSSSSSS#........",
		".......########.........",
		"....ddddddddddddddd.....",
		"........................"
	])
	tex_battlefield_props["dirt"] = _build_prop_texture([
		"........................",
		".....ddddddddddd........",
		"...ddddDDDDDDDddddd.....",
		"..dddDDDDDDDDDDDDddd....",
		"...ddddDDDDDDDDddddd....",
		".....ddddddddddddd......",
		"........ddddddd.........",
		"........................"
	])

func _build_prop_texture(rows: Array) -> Texture2D:
	var h_cnt = rows.size()
	var w_cnt = 24
	var img = Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var y_off = int((24 - h_cnt) * 0.5)
	var pal = {
		"#": Color(0.10, 0.08, 0.07, 0.85),
		"S": Color(0.58, 0.62, 0.68, 0.82),
		"W": Color(0.82, 0.86, 0.92, 0.85),
		"G": Color(0.78, 0.62, 0.24, 0.82),
		"B": Color(0.28, 0.36, 0.52, 0.82),
		"d": Color(0.34, 0.24, 0.15, 0.52),
		"D": Color(0.26, 0.18, 0.11, 0.62)
	}
	for r_i in range(h_cnt):
		var line: String = rows[r_i]
		for c_i in range(min(w_cnt, line.length())):
			var ch = line.substr(c_i, 1)
			if pal.has(ch):
				img.set_pixel(c_i, y_off + r_i, pal[ch])
	return ImageTexture.create_from_image(img)

func _process(delta: float):
	if current_phase != Phase.BATTLE and current_phase != Phase.GAME_OVER:
		return
	if tex_fire_frames.is_empty():
		return
	fire_anim_accum += delta
	if fire_anim_accum < 0.13:
		return
	fire_anim_accum = 0.0
	fire_anim_step = (fire_anim_step + 1) % 4096
	
	# 1. Äußeren Brenn-Rand rund um das Hex-Spielfeld animieren
	for entry in perimeter_fire_nodes:
		var node: TextureRect = entry["node"]
		if is_instance_valid(node) and node.visible:
			var f_idx = (fire_anim_step + int(entry["phase"])) % tex_fire_frames.size()
			node.texture = tex_fire_frames[f_idx]
			
	# 2. Feuer auf den Gefahrenzonen-Kacheln animieren
	for cell in tile_fire_nodes:
		var f_node: TextureRect = tile_fire_nodes[cell]
		if not is_instance_valid(f_node) or not f_node.visible:
			continue
		var phase = (cell.x * 3 + cell.y * 5)
		if is_cell_in_danger_zone(cell):
			var f_idx = (fire_anim_step + phase) % tex_fire_frames.size()
			f_node.texture = tex_fire_frames[f_idx]
		elif not tex_ember_frames.is_empty():
			var e_idx = (fire_anim_step + phase) % tex_ember_frames.size()
			f_node.texture = tex_ember_frames[e_idx]

func _set_phase_background(mode: String):
	if phase_bg_rect:
		phase_bg_rect.pivot_offset = Vector2.ZERO
		phase_bg_rect.position = Vector2.ZERO
		phase_bg_rect.scale = Vector2.ONE
	if mode == "intro":
		if bg_tilemap:
			bg_tilemap.visible = true
		if phase_bg_rect:
			phase_bg_rect.visible = false
	elif mode == "barracks":
		if bg_tilemap:
			bg_tilemap.visible = false
		if phase_bg_rect and tex_barracks_bg:
			phase_bg_rect.texture = tex_barracks_bg
			phase_bg_rect.modulate = Color(0.82, 0.80, 0.78, 1.0)
			phase_bg_rect.visible = true
	elif mode == "battlefield":
		if bg_tilemap:
			bg_tilemap.visible = false
		if phase_bg_rect and tex_battlefield_bg:
			phase_bg_rect.texture = tex_battlefield_bg
			phase_bg_rect.modulate = Color(1.0, 1.0, 1.0, 1.0)
			phase_bg_rect.visible = true

func _ready():
	AudioManager.play_music("fire_emblem")
	NetworkManager.message_received.connect(_on_message_received)
	NetworkManager.client_connected.connect(_on_client_reconnected)
	
	start_equip_btn.pressed.connect(_on_start_equipment_pressed)
	equip_action_btn.pressed.connect(_on_equip_action_pressed)
	execute_turn_btn.pressed.connect(_on_execute_turn_pressed)
	back_to_board_btn.pressed.connect(_on_back_pressed)
	if winner_overlay:
		winner_overlay.visible = false
	
	_setup_phase_backgrounds()
	_set_phase_background("intro")
	_setup_static_pixel_icons()
	_connect_buttons_sfx(self)
	
	equip_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	equip_title.add_theme_constant_override("outline_size", 12)
	equip_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	equip_status.add_theme_constant_override("outline_size", 8)
	
	intro_container.visible = true
	equip_container.visible = false
	battle_container.visible = false
	_setup_intro_scroll()
	
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})

func _setup_intro_scroll():
	var scroll_area = get_node_or_null("IntroContainer/VBox/ScrollArea")
	var inst_lbl = get_node_or_null("IntroContainer/VBox/ScrollArea/InstructionContainer/Instruction")
	if scroll_area and inst_lbl:
		await get_tree().process_frame
		if is_instance_valid(inst_lbl) and is_instance_valid(scroll_area):
			var content_h = inst_lbl.get_minimum_size().y + 8.0
			scroll_area.custom_minimum_size.y = clampf(content_h, 80.0, 480.0)

func _setup_static_pixel_icons():
	# Zone-Icon links neben ZoneLabel einbauen
	if zone_label and zone_label.get_parent():
		var parent_vbox = zone_label.get_parent()
		var idx = zone_label.get_index()
		var z_row = HBoxContainer.new()
		z_row.name = "ZoneRow"
		z_row.alignment = BoxContainer.ALIGNMENT_CENTER
		z_row.add_theme_constant_override("separation", 8)
		parent_vbox.remove_child(zone_label)
		z_row.add_child(PixelIcon.create("fire", "S"))
		z_row.add_child(zone_label)
		parent_vbox.add_child(z_row)
		parent_vbox.move_child(z_row, idx)
		
	# Legende mit standardisierten S-Pixel-Icons füllen
	var legend_box = get_node_or_null("BattleContainer/MainHBox/RightPanel/Margin/VBox/LegendBox")
	if legend_box:
		var rps_row = HBoxContainer.new()
		rps_row.add_theme_constant_override("separation", 6)
		rps_row.add_child(PixelIcon.create("scissors", "S"))
		rps_row.add_child(_make_legend_label("Schere >"))
		rps_row.add_child(PixelIcon.create("paper", "S"))
		rps_row.add_child(_make_legend_label("Papier >"))
		rps_row.add_child(PixelIcon.create("rock", "S"))
		rps_row.add_child(_make_legend_label("Stein (+1 / -1 DMG)"))
		legend_box.add_child(rps_row)
		
		var grid = GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 4)
		var entries = [
			["heal", "Heilquelle: +2 HP"],
			["swap", "Typ-Wechsel"],
			["sword", "Schwert: +1 DMG (2 R.)"],
			["portal", "Teleport: Zur Mitte"],
			["meteor", "Meteor: 2 DMG"],
			["fire", "Zone: -1 HP"]
		]
		for entry in entries:
			var item = HBoxContainer.new()
			item.add_theme_constant_override("separation", 6)
			item.add_child(PixelIcon.create(entry[0], "S"))
			item.add_child(_make_legend_label(entry[1]))
			grid.add_child(item)
		legend_box.add_child(grid)

func _make_legend_label(txt: String) -> Label:
	var lbl = Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.88, 0.9, 0.95, 0.92))
	return lbl

func _connect_buttons_sfx(node: Node):
	if node is BaseButton:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func is_valid_cell(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= GRID_SIZE or cell.y < 0 or cell.y >= GRID_SIZE:
		return false
	return manhattan_dist(cell, CENTER) <= MAX_ARENA_DIST

func manhattan_dist(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

func arena_ring_dist(cell: Vector2i) -> int:
	var dx = abs(cell.x - CENTER.x)
	var dy = abs(cell.y - CENTER.y)
	var manh = dx + dy
	var cheb = max(dx, dy)
	return max(manh, cheb + clampi(cheb - 1, 0, 2))

func is_cell_in_danger_zone(cell: Vector2i) -> bool:
	return arena_ring_dist(cell) > zone_max_dist

func _init_fe_players():
	fe_players.clear()
	
	# Falls im Editor direkt getestet wird und noch keine Teams existieren, erstelle Demo-Teams aus Sessions
	if NetworkManager.computed_teams.is_empty() and not NetworkManager.player_sessions.is_empty():
		NetworkManager.compute_teams()
		
	for t_idx in range(NetworkManager.computed_teams.size()):
		var team = NetworkManager.computed_teams[t_idx]
		var t_name = team.get("name", "Team " + str(t_idx + 1))
		var t_color = team.get("color", Color(0.35, 0.65, 1.0, 1.0))
		for p_entry in team.get("players", []):
			var pid = _get_player_id(p_entry)
			if pid == -1:
				continue
			var s_data = NetworkManager.player_sessions.get(pid, p_entry)
			var char_name = s_data.get("character", p_entry.get("character", "Cedi"))
			if char_name == "" or not NetworkManager.character_textures.has(char_name):
				char_name = "Cedi"
			fe_players[pid] = {
				"id": pid,
				"name": s_data.get("name", p_entry.get("name", "Spieler " + str(pid))),
				"character": char_name,
				"team_index": t_idx,
				"team_name": t_name,
				"team_color": t_color,
				"rps": "rock",
				"role": "tank",
				"equip_ready": false,
				"hp": 8,
				"max_hp": 8,
				"dmg": 2,
				"steps": 2,
				"alive": true,
				"pos": CENTER,
				"dmg_boost_turns": 0,
				"turn_ready": false,
				"planned_path": [],
				"attack_dir": "up",
				"meteor_target_pos": Vector2i(-1, -1),
				"swap_rps_choice": ""
			}

func _get_player_id(player_dict: Dictionary) -> int:
	if player_dict.has("id"):
		return int(player_dict["id"])
	for pid in NetworkManager.player_sessions.keys():
		if NetworkManager.player_sessions[pid].get("name") == player_dict.get("name"):
			return int(pid)
	return -1

# ==============================================================================
# PHASE 1 & 2: EQUIPMENT & REVEAL
# ==============================================================================

func _on_start_equipment_pressed():
	if pixel_back_btn:
		pixel_back_btn.visible = true
	AudioManager.play_music("fire_emblem")
	_set_phase_background("barracks")
	_init_fe_players()
	current_phase = Phase.EQUIPMENT
	intro_container.visible = false
	equip_container.visible = true
	battle_container.visible = false
	
	equip_title.text = "Equipmentphase"
	equip_action_btn.text = "AUSWAHL AUFDECKEN"
	_refresh_equipment_ui(false)
	
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "fire_emblem_equip"
	})

func _refresh_equipment_ui(reveal: bool):
	for child in equip_grid.get_children():
		child.queue_free()
		
	var total = fe_players.size()
	var ready_count = 0
	for pid in fe_players:
		if fe_players[pid]["equip_ready"]:
			ready_count += 1
			
	if not reveal:
		equip_status.text = "Wählt Typ & Klasse auf dem Handy! (%d / %d bereit)" % [ready_count, total]
	else:
		equip_status.text = "Alle Auswahlen im Überblick:"
		
	var pids = fe_players.keys()
	pids.sort()
	equip_grid.columns = 3 if pids.size() >= 5 else 2
	
	for pid in pids:
		var p = fe_players[pid]
		var is_ready = p.get("equip_ready", false)
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(460, 140)
		var style = StyleBoxFlat.new()
		
		# Stroke immer in Teamfarbe mit 4px Rahmen (wie bei QuizParticipantCard)
		style.border_width_left = 4
		style.border_width_top = 4
		style.border_width_right = 4
		style.border_width_bottom = 4
		style.border_color = p["team_color"]
		style.corner_radius_top_left = 10
		style.corner_radius_top_right = 10
		style.corner_radius_bottom_right = 10
		style.corner_radius_bottom_left = 10
		style.shadow_size = 0
		
		# Füllung: Wenn jemand bereit ist: weiß. Sonst (warten oder aufdecken): schwarz
		if not reveal:
			if is_ready:
				style.bg_color = Color(1.0, 1.0, 1.0, 1.0) # Weiß bei Bereitschaft
			else:
				style.bg_color = Color(0.1, 0.1, 0.1, 1.0) # Schwarz beim Warten
		else:
			style.bg_color = Color(0.1, 0.1, 0.1, 1.0) # Schwarz beim Aufdecken (kein Dunkelblau)
			
		card.add_theme_stylebox_override("panel", style)
		
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 16)
		margin.add_theme_constant_override("margin_right", 16)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_bottom", 12)
		card.add_child(margin)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 16)
		margin.add_child(hbox)
		
		var icon = TextureRect.new()
		icon.custom_minimum_size = Vector2(72, 72)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if NetworkManager.character_textures.has(p["character"]):
			icon.texture = NetworkManager.character_textures[p["character"]]
		hbox.add_child(icon)
		
		var vbox = VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 6)
		hbox.add_child(vbox)
		
		var name_lbl = Label.new()
		name_lbl.text = "%s (%s)" % [p["name"], p["team_name"]]
		name_lbl.add_theme_font_size_override("font_size", 24)
		
		if not reveal:
			if is_ready:
				# Weißer Hintergrund: Dunkler Name und grüner Statustext ohne Outline (QuizParticipantCard Standard)
				name_lbl.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08, 1.0))
				name_lbl.add_theme_constant_override("outline_size", 0)
				name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0))
				vbox.add_child(name_lbl)
				
				var st_lbl = Label.new()
				st_lbl.text = "Eingereicht!"
				st_lbl.add_theme_color_override("font_color", Color(0.08, 0.55, 0.18, 1.0))
				st_lbl.add_theme_font_size_override("font_size", 20)
				st_lbl.add_theme_constant_override("outline_size", 0)
				st_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0))
				vbox.add_child(st_lbl)
			else:
				# Schwarzer Hintergrund: Weißer Name und grauer Statustext
				name_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
				vbox.add_child(name_lbl)
				
				var st_lbl = Label.new()
				st_lbl.text = "Tippt gerade..."
				st_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
				st_lbl.add_theme_font_size_override("font_size", 20)
				vbox.add_child(st_lbl)
		else:
			# Schwarzer Hintergrund beim Aufdecken: Weißer Name
			name_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
			vbox.add_child(name_lbl)
			
			var rps_info = RPS_CONFIG.get(p["rps"], RPS_CONFIG["rock"])
			var role_info = ROLE_CONFIG.get(p["role"], ROLE_CONFIG["tank"])
			
			var choice_row = HBoxContainer.new()
			choice_row.add_theme_constant_override("separation", 8)
			choice_row.add_child(PixelIcon.create(rps_info["icon"], "M"))
			var rps_lbl = Label.new()
			rps_lbl.text = rps_info["name"] + "   •  "
			rps_lbl.add_theme_font_size_override("font_size", 22)
			rps_lbl.add_theme_color_override("font_color", Color.WHITE)
			choice_row.add_child(rps_lbl)
			choice_row.add_child(PixelIcon.create(role_info["icon"], "M"))
			var role_lbl = Label.new()
			role_lbl.text = role_info["name"]
			role_lbl.add_theme_font_size_override("font_size", 22)
			role_lbl.add_theme_color_override("font_color", Color.WHITE)
			choice_row.add_child(role_lbl)
			vbox.add_child(choice_row)
			
			var stats_row = HBoxContainer.new()
			stats_row.add_theme_constant_override("separation", 14)
			var stat_col = Color(1.0, 0.9, 0.55, 0.95)
			stats_row.add_child(PixelIcon.create_stat_chip("heart", "%d HP" % p["max_hp"], "S", 18, stat_col))
			stats_row.add_child(PixelIcon.create_stat_chip("sword", "%d DMG" % p["dmg"], "S", 18, stat_col))
			stats_row.add_child(PixelIcon.create_stat_chip("boots", "%d Felder" % p["steps"], "S", 18, stat_col))
			vbox.add_child(stats_row)
			
		equip_grid.add_child(card)

func _apply_player_equipment(pid: int, rps: String, role: String):
	if not fe_players.has(pid):
		return
	if not RPS_CONFIG.has(rps):
		rps = "rock"
	if not ROLE_CONFIG.has(role):
		role = "tank"
		
	var r_cfg = ROLE_CONFIG[role]
	var p = fe_players[pid]
	p["rps"] = rps
	p["role"] = role
	p["hp"] = r_cfg["hp"]
	p["max_hp"] = r_cfg["hp"]
	p["dmg"] = r_cfg["dmg"]
	p["steps"] = r_cfg["steps"]
	p["equip_ready"] = true

func _on_equip_action_pressed():
	if current_phase == Phase.EQUIPMENT:
		# Falls jemand noch nicht gewählt hat, zufällige Ausrüstung zuweisen
		var rps_keys = RPS_CONFIG.keys()
		var role_keys = ROLE_CONFIG.keys()
		for pid in fe_players:
			if not fe_players[pid]["equip_ready"]:
				_apply_player_equipment(
					pid,
					rps_keys[randi() % rps_keys.size()],
					role_keys[randi() % role_keys.size()]
				)
		current_phase = Phase.REVEAL
		equip_title.text = "Gewählte Ausrüstung"
		equip_action_btn.text = "AUFS SCHLACHTFELD!"
		_refresh_equipment_ui(true)
		NetworkManager.broadcast({
			"type": "state_change",
			"state": "waiting"
		})
	elif current_phase == Phase.REVEAL:
		_start_battle_phase()

# ==============================================================================
# PHASE 3: SCHLACHTFELD & TAKTIK-RUNDE
# ==============================================================================

func _start_battle_phase():
	AudioManager.play_music("fire_emblem")
	_set_phase_background("battlefield")
	current_phase = Phase.BATTLE
	round_number = 1
	zone_max_dist = MAX_ARENA_DIST
	is_resolving_turn = false
	
	equip_container.visible = false
	battle_container.visible = true
	back_to_board_btn.visible = false
	execute_turn_btn.visible = true
	
	_assign_team_corner_spawns()
	_spawn_initial_special_tiles()
	_build_board_visuals()
	_append_log("[color=#ffd866][b]--- Schlacht beginnt! ---[/b][/color]\nAlle Teams starten in ihren Ecken. Plant euren 1. Zug auf dem Handy!")
	_start_planning_round()

func _assign_team_corner_spawns():
	# Gleichmäßige Ecken/Sektoren am Rand des Hex-Feldes (Abstand ~5-6 vom Zentrum (5,5))
	# Für 2, 3, 4, 5 oder 6 Teams symmetrische Ankerpunkte
	var anchor_sets = {
		1: [Vector2i(1, 3)],
		2: [Vector2i(1, 3), Vector2i(9, 7)],
		3: [Vector2i(5, 0), Vector2i(1, 8), Vector2i(9, 8)],
		4: [Vector2i(1, 3), Vector2i(9, 3), Vector2i(9, 7), Vector2i(1, 7)],
		5: [Vector2i(5, 0), Vector2i(10, 3), Vector2i(8, 9), Vector2i(2, 9), Vector2i(0, 3)],
		6: [Vector2i(3, 0), Vector2i(9, 2), Vector2i(10, 7), Vector2i(7, 10), Vector2i(1, 8), Vector2i(0, 3)]
	}
	
	var num_teams = max(1, NetworkManager.computed_teams.size())
	var anchors: Array = anchor_sets.get(clampi(num_teams, 1, 6), anchor_sets[4])
	var occupied: Dictionary = {}
	
	for t_idx in range(NetworkManager.computed_teams.size()):
		var anchor: Vector2i = anchors[t_idx % anchors.size()]
		# Sammle alle gültigen Felder, sortiert nach Distanz zum Team-Ankerpunkt (aber innerhalb der sicheren Zone)
		var candidate_cells: Array[Vector2i] = []
		for y in range(GRID_SIZE):
			for x in range(GRID_SIZE):
				var c = Vector2i(x, y)
				if is_valid_cell(c) and manhattan_dist(c, CENTER) <= 6:
					candidate_cells.append(c)
		candidate_cells.sort_custom(func(a: Vector2i, b: Vector2i):
			var da = abs(a.x - anchor.x) + abs(a.y - anchor.y)
			var db = abs(b.x - anchor.x) + abs(b.y - anchor.y)
			if da == db:
				return manhattan_dist(a, CENTER) > manhattan_dist(b, CENTER)
			return da < db
		)
		
		for pid in fe_players:
			if fe_players[pid]["team_index"] == t_idx:
				for cell in candidate_cells:
					var key = "%d,%d" % [cell.x, cell.y]
					if not occupied.has(key):
						occupied[key] = pid
						fe_players[pid]["pos"] = cell
						break

func _get_cell_quadrant(c: Vector2i) -> int:
	# 4 Quadranten um CENTER (5, 5):
	# 0: Nord-West, 1: Nord-Ost, 2: Süd-West, 3: Süd-Ost
	var is_east = c.x >= CENTER.x
	var is_south = c.y >= CENTER.y
	if not is_east and not is_south:
		return 0 # Top-Left
	elif is_east and not is_south:
		return 1 # Top-Right
	elif not is_east and is_south:
		return 2 # Bottom-Left
	else:
		return 3 # Bottom-Right

func _find_best_special_tile_cell(st_type: String, preferred_quadrant: int = -1, collected_at: Vector2i = Vector2i(-1, -1), collector_pos: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	var occupied: Dictionary = {}
	var player_positions: Array[Vector2i] = []
	for pid in fe_players:
		if fe_players[pid]["alive"]:
			var p_pos: Vector2i = fe_players[pid]["pos"]
			occupied["%d,%d" % [p_pos.x, p_pos.y]] = true
			player_positions.append(p_pos)
			
	var existing_special_positions: Array[Vector2i] = []
	var quadrant_counts = [0, 0, 0, 0]
	for k in special_tiles.keys():
		occupied[k] = true
		var parts = k.split(",")
		if parts.size() == 2:
			var s_pos = Vector2i(int(parts[0]), int(parts[1]))
			existing_special_positions.append(s_pos)
			var q = _get_cell_quadrant(s_pos)
			quadrant_counts[q] += 1
			
	# Positionen, von denen das neue Sonderfeld weit entfernt spawnen soll
	var avoid_points: Array[Vector2i] = []
	if collected_at != Vector2i(-1, -1):
		avoid_points.append(collected_at)
	if collector_pos != Vector2i(-1, -1) and not avoid_points.has(collector_pos):
		avoid_points.append(collector_pos)

	# Wenn kein bevorzugter Quadrant vorgegeben ist, wähle einen geeigneten Zielquadranten:
	var target_quadrant = preferred_quadrant
	if target_quadrant < 0:
		if not avoid_points.is_empty():
			var ref_pos = collector_pos if collector_pos != Vector2i(-1, -1) else collected_at
			var from_quad = _get_cell_quadrant(ref_pos)
			var opp_quad = 3 - from_quad # 0 <-> 3, 1 <-> 2
			
			# Die 3 anderen Quadranten (Quadrant des Aufsammelns/Spielers strikt ausschließen!)
			var candidate_quads = [opp_quad]
			for q in range(4):
				if q != from_quad and q != opp_quad:
					candidate_quads.append(q)
			
			# Finde unter den anderen Quadranten die mit den wenigsten Sonderfeldern
			var min_c = 999
			var best_quads = []
			for q in candidate_quads:
				if quadrant_counts[q] < min_c:
					min_c = quadrant_counts[q]
					best_quads = [q]
				elif quadrant_counts[q] == min_c:
					best_quads.append(q)
			
			if best_quads.has(opp_quad):
				target_quadrant = opp_quad
			else:
				target_quadrant = best_quads[randi() % best_quads.size()]
		else:
			var min_c = 999
			var best_quads = []
			for q in range(4):
				if quadrant_counts[q] < min_c:
					min_c = quadrant_counts[q]
					best_quads = [q]
				elif quadrant_counts[q] == min_c:
					best_quads.append(q)
			target_quadrant = best_quads[randi() % best_quads.size()]
		
	# Sammle alle gültigen Kandidaten
	var all_candidates: Array[Vector2i] = []
	var max_allowed_dist = min(5, zone_max_dist - 1)
	
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var c = Vector2i(x, y)
			var key = "%d,%d" % [c.x, c.y]
			if c == CENTER:
				continue
			if not is_valid_cell(c) or is_cell_in_danger_zone(c) or occupied.has(key):
				continue
			if manhattan_dist(c, CENTER) > max_allowed_dist:
				continue
			# Teleport-Schrein soll nicht zu nah am Zentrum spawnen (sonst wirkungslos)
			if st_type == "teleport" and manhattan_dist(c, CENTER) < 3:
				continue
			all_candidates.append(c)
			
	if all_candidates.is_empty():
		return Vector2i(-1, -1)
		
	# Mindestabstände zum Aufsammelort (große Distanzen zuerst, z. B. >= 7, 6, 5, 4, 3)
	var from_dists = [7, 6, 5, 4, 3] if not avoid_points.is_empty() else [0]
		
	# Filtere/Priorisiere Kandidaten:
	# 1. Bevorzuge den Ziel-Quadranten
	# 2. Mindestabstand zu Aufsammelort & Sammler (>= 7, >= 6, >= 5, >= 4, >= 3)
	# 3. Mindestabstand zu existierenden Sonderfeldern (optimal >= 3, mindestens >= 2)
	# 4. Mindestabstand zu Spielern (nicht direkt vor den Füßen, >= 2)
	for min_from_dist in from_dists:
		for min_special_dist in [3, 2, 1]:
			for min_player_dist in [2, 1, 0]:
				var filtered: Array[Vector2i] = []
				for c in all_candidates:
					if target_quadrant >= 0 and _get_cell_quadrant(c) != target_quadrant:
						continue
					var ok = true
					for ap in avoid_points:
						if min_from_dist > 0 and manhattan_dist(c, ap) < min_from_dist:
							ok = false
							break
					if not ok:
						continue
					for s_pos in existing_special_positions:
						if manhattan_dist(c, s_pos) < min_special_dist:
							ok = false
							break
					if not ok:
						continue
					for p_pos in player_positions:
						if manhattan_dist(c, p_pos) < min_player_dist:
							ok = false
							break
					if ok:
						filtered.append(c)
						
				if not filtered.is_empty():
					# Unter den besten Kandidaten die am weitesten vom Sammler entfernten bevorzugen
					if not avoid_points.is_empty():
						filtered.sort_custom(func(a: Vector2i, b: Vector2i):
							var da = 0
							var db = 0
							for ap in avoid_points:
								da += manhattan_dist(a, ap)
								db += manhattan_dist(b, ap)
							return da > db
						)
						var top_count = min(3, filtered.size())
						return filtered[randi() % top_count]
					return filtered[randi() % filtered.size()]
					
	# Fallback 1: Falls im Zielquadranten kein Platz mit Abstand ist, andere Quadranten durchsuchen
	# (aber immer noch den Quadranten des Aufsammelns ausschließen!)
	var from_quad = _get_cell_quadrant(avoid_points[0]) if not avoid_points.is_empty() else -1
	for min_from_dist in from_dists:
		for min_special_dist in [3, 2, 1]:
			var fallback_filtered: Array[Vector2i] = []
			for c in all_candidates:
				if from_quad >= 0 and _get_cell_quadrant(c) == from_quad:
					continue
				var ok = true
				for ap in avoid_points:
					if min_from_dist > 0 and manhattan_dist(c, ap) < min_from_dist:
						ok = false
						break
				if not ok:
					continue
				for s_pos in existing_special_positions:
					if manhattan_dist(c, s_pos) < min_special_dist:
						ok = false
						break
				if ok:
					fallback_filtered.append(c)
			if not fallback_filtered.is_empty():
				if not avoid_points.is_empty():
					fallback_filtered.sort_custom(func(a: Vector2i, b: Vector2i):
						var da = 0
						var db = 0
						for ap in avoid_points:
							da += manhattan_dist(a, ap)
							db += manhattan_dist(b, ap)
						return da > db
					)
					var top_count = min(3, fallback_filtered.size())
					return fallback_filtered[randi() % top_count]
				return fallback_filtered[randi() % fallback_filtered.size()]
				
	# Fallback 2: Ohne Quadranten-Filter, aber immer noch maximale Distanz zu avoid_points wählen
	if not avoid_points.is_empty():
		all_candidates.sort_custom(func(a: Vector2i, b: Vector2i):
			var da = 0
			var db = 0
			for ap in avoid_points:
				da += manhattan_dist(a, ap)
				db += manhattan_dist(b, ap)
			return da > db
		)
		var top_count = min(3, all_candidates.size())
		return all_candidates[randi() % top_count]
			
	return all_candidates[randi() % all_candidates.size()]

func _spawn_initial_special_tiles():
	special_tiles.clear()
	# 4 Quadranten um CENTER (5,5) gleichmäßig und fair bestücken:
	# Jeder Quadrant erhält genau 2 verschiedene Sonderfelder!
	# Verteilung der 8 Sonderfelder (2x heal, 2x type_swap, 2x dmg_boost, 1x meteor, 1x teleport):
	var quadrant_pairs = [
		["heal", "dmg_boost"],
		["heal", "type_swap"],
		["type_swap", "teleport"],
		["dmg_boost", "meteor"]
	]
	quadrant_pairs.shuffle()
	
	for q_idx in range(4):
		var pair = quadrant_pairs[q_idx]
		pair.shuffle()
		for st_type in pair:
			var cell = _find_best_special_tile_cell(st_type, q_idx)
			if cell != Vector2i(-1, -1):
				special_tiles["%d,%d" % [cell.x, cell.y]] = st_type

func _spawn_single_special_tile(st_type: String, collected_at: Vector2i = Vector2i(-1, -1), collector_pos: Vector2i = Vector2i(-1, -1)):
	# Spawnt ein einzelnes Sonderfeld weit entfernt vom Aufsammelort & Sammler
	var cell = _find_best_special_tile_cell(st_type, -1, collected_at, collector_pos)
	if cell != Vector2i(-1, -1):
		special_tiles["%d,%d" % [cell.x, cell.y]] = st_type

func _build_board_visuals():
	for child in board_viewport.get_children():
		child.queue_free()
	tile_nodes.clear()
	unit_nodes.clear()
	tile_fire_nodes.clear()
	perimeter_fire_nodes.clear()
	
	board_viewport.clip_contents = false
	
	var vp_size = board_viewport.custom_minimum_size
	if vp_size.x < 100:
		vp_size = Vector2(860, 860)
	tile_px_size = 56.0
	tile_gap = 3.0
	var total_board_px = GRID_SIZE * tile_px_size + (GRID_SIZE - 1) * tile_gap
	board_grid_origin = (vp_size - Vector2(total_board_px, total_board_px)) * 0.5
	
	board_camera_root = Control.new()
	board_camera_root.name = "BoardCameraRoot"
	board_camera_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	board_camera_root.pivot_offset = Vector2.ZERO
	board_camera_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_viewport.add_child(board_camera_root)
	
	fire_ring_layer = Control.new()
	fire_ring_layer.name = "FireRingLayer"
	fire_ring_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	fire_ring_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fire_ring_layer.z_index = 2
	
	# Deterministische Boden-Details (Rüstung, Helm, Schild, Schwert, kahle Erde) auf ausgewählten Kacheln
	var prop_map = {
		"3,2": "helmet",
		"7,2": "sword",
		"2,4": "shield",
		"8,4": "armor",
		"3,8": "sword",
		"7,8": "helmet",
		"2,6": "dirt",
		"8,6": "dirt",
		"4,4": "dirt",
		"6,6": "dirt",
		"5,3": "dirt",
		"5,7": "dirt",
		"4,6": "shield",
		"6,4": "armor"
	}
	
	# 1. Erstelle alle gültigen Spielfeld-Kacheln
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var cell = Vector2i(x, y)
			if not is_valid_cell(cell):
				continue
			var tile_panel = Panel.new()
			tile_panel.custom_minimum_size = Vector2(tile_px_size, tile_px_size)
			tile_panel.size = Vector2(tile_px_size, tile_px_size)
			tile_panel.position = _cell_to_pixel(cell)
			
			# Kleines Schlachtfeld-Bodendetail im Miniatur-Maßstab passend zu den Charakteren (16x16 px)
			var prop_rect = TextureRect.new()
			prop_rect.name = "PropDetail"
			var prop_sz = 16.0
			prop_rect.size = Vector2(prop_sz, prop_sz)
			var off_x = 8.0 if ((cell.x + cell.y) % 2 == 0) else (tile_px_size - prop_sz - 8.0)
			var off_y = tile_px_size - prop_sz - 7.0
			prop_rect.position = Vector2(off_x, off_y)
			prop_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			prop_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			prop_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			prop_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var cell_key = "%d,%d" % [cell.x, cell.y]
			if prop_map.has(cell_key) and tex_battlefield_props.has(prop_map[cell_key]):
				prop_rect.texture = tex_battlefield_props[prop_map[cell_key]]
			else:
				prop_rect.visible = false
			tile_panel.add_child(prop_rect)
			
			var icon_node = PixelIcon.create("", "M")
			icon_node.name = "SpecialIcon"
			icon_node.position = (Vector2(tile_px_size, tile_px_size) - PixelIcon.SIZE_M) * 0.5
			icon_node.visible = false
			tile_panel.add_child(icon_node)
			
			board_camera_root.add_child(tile_panel)
			tile_nodes[cell] = tile_panel
			
			# Animiertes Pixel-Feuer exakt in Feldgröße (tile_px_size x tile_px_size)
			var fire_rect = TextureRect.new()
			fire_rect.name = "TileFire_%d_%d" % [cell.x, cell.y]
			fire_rect.size = Vector2(tile_px_size, tile_px_size)
			fire_rect.pivot_offset = Vector2(tile_px_size * 0.5, tile_px_size * 0.5)
			fire_rect.position = _cell_to_pixel(cell)
			fire_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			fire_rect.stretch_mode = TextureRect.STRETCH_SCALE
			fire_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			fire_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if not tex_fire_frames.is_empty():
				fire_rect.texture = tex_fire_frames[(cell.x * 3 + cell.y * 5) % tex_fire_frames.size()]
			fire_rect.visible = false
			fire_ring_layer.add_child(fire_rect)
			tile_fire_nodes[cell] = fire_rect
			
	# 1b. Geschlossener äußerer Feuerring rund um das gesamte Spielfeld (oben, unten, links, rechts und Diagonalen)
	for py_grid in range(-1, GRID_SIZE + 1):
		for px_grid in range(-1, GRID_SIZE + 1):
			var p_cell = Vector2i(px_grid, py_grid)
			if is_valid_cell(p_cell):
				continue
			var r_dist = arena_ring_dist(p_cell)
			if r_dist != 8:
				continue
			var pos_px = _cell_to_pixel(p_cell)
			var perim_fire = TextureRect.new()
			perim_fire.size = Vector2(tile_px_size, tile_px_size)
			perim_fire.position = pos_px
			perim_fire.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			perim_fire.stretch_mode = TextureRect.STRETCH_SCALE
			perim_fire.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			perim_fire.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var phase = abs(px_grid * 7 + py_grid * 11)
			if not tex_fire_frames.is_empty():
				perim_fire.texture = tex_fire_frames[phase % tex_fire_frames.size()]
			perim_fire.modulate = Color(1.0, 0.95, 0.9, 0.92)
			fire_ring_layer.add_child(perim_fire)
			perimeter_fire_nodes.append({
				"node": perim_fire,
				"phase": phase,
				"ring": r_dist
			})
			
	board_camera_root.add_child(fire_ring_layer)
			
	# 2. Erstelle Charakter-Nodes
	for pid in fe_players:
		var p = fe_players[pid]
		var unit = Control.new()
		unit.name = "Unit_" + str(pid)
		unit.size = Vector2(tile_px_size, tile_px_size)
		unit.position = _cell_to_pixel(p["pos"])
		unit.z_index = 5
		
		# Team-Farb-Basisring
		var ring = Panel.new()
		ring.name = "TeamRing"
		ring.size = Vector2(tile_px_size - 8, tile_px_size - 8)
		ring.position = Vector2(4, 4)
		var ring_style = StyleBoxFlat.new()
		ring_style.bg_color = Color(p["team_color"].r, p["team_color"].g, p["team_color"].b, 0.28)
		ring_style.border_width_left = 3
		ring_style.border_width_top = 3
		ring_style.border_width_right = 3
		ring_style.border_width_bottom = 3
		ring_style.border_color = p["team_color"]
		ring_style.corner_radius_top_left = 8
		ring_style.corner_radius_top_right = 8
		ring_style.corner_radius_bottom_right = 8
		ring_style.corner_radius_bottom_left = 8
		ring.add_theme_stylebox_override("panel", ring_style)
		unit.add_child(ring)
		
		# Charakter-Sprite
		var sprite = TextureRect.new()
		sprite.name = "Sprite"
		sprite.size = Vector2(46, 46)
		sprite.position = Vector2((tile_px_size - 46) * 0.5, 10)
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if NetworkManager.character_textures.has(p["character"]):
			sprite.texture = NetworkManager.character_textures[p["character"]]
		unit.add_child(sprite)
		
		# Typ- & Boost-Badge oben links (standardisierte Größe S)
		var badge_box = HBoxContainer.new()
		badge_box.name = "BadgeBox"
		badge_box.position = Vector2(4, 2)
		badge_box.add_theme_constant_override("separation", 2)
		badge_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rps_ic = PixelIcon.create(RPS_CONFIG.get(p["rps"], RPS_CONFIG["rock"])["icon"], "S")
		rps_ic.name = "RPSIcon"
		badge_box.add_child(rps_ic)
		var boost_ic = PixelIcon.create("bolt", "S")
		boost_ic.name = "BoostIcon"
		boost_ic.visible = false
		badge_box.add_child(boost_ic)
		unit.add_child(badge_box)
		
		# HP-Anzeige oben rechts (Zahl + PixelIcon "heart" in Größe S)
		var hp_box = HBoxContainer.new()
		hp_box.name = "HPBox"
		hp_box.position = Vector2(tile_px_size - 38, 1)
		hp_box.alignment = BoxContainer.ALIGNMENT_END
		hp_box.add_theme_constant_override("separation", 1)
		hp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hp_lbl = Label.new()
		hp_lbl.name = "HPLabel"
		hp_lbl.add_theme_font_size_override("font_size", 14)
		hp_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.45))
		hp_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		hp_lbl.add_theme_constant_override("outline_size", 4)
		hp_box.add_child(hp_lbl)
		var heart_ic = PixelIcon.create("heart", "S")
		heart_ic.custom_minimum_size = Vector2(14, 14)
		heart_ic.size = Vector2(14, 14)
		hp_box.add_child(heart_ic)
		unit.add_child(hp_box)
		
		# Spielername unten
		var name_lbl = Label.new()
		name_lbl.name = "NameLabel"
		name_lbl.size = Vector2(tile_px_size + 16, 18)
		name_lbl.position = Vector2(-8, tile_px_size - 16)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		name_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		name_lbl.add_theme_constant_override("outline_size", 4)
		name_lbl.text = p["name"]
		unit.add_child(name_lbl)
		
		board_camera_root.add_child(unit)
		unit_nodes[pid] = unit
		
	# 3. Effekt-Ebene für Angriffe, Meteore und schwebenden Text
	fx_layer = Control.new()
	fx_layer.name = "FXLayer"
	fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.z_index = 20
	board_camera_root.add_child(fx_layer)
	
	_refresh_board_visuals()

func _cell_to_pixel(cell: Vector2i) -> Vector2:
	return board_grid_origin + Vector2(
		cell.x * (tile_px_size + tile_gap),
		cell.y * (tile_px_size + tile_gap)
	)

func _focus_camera_on_pixel(local_pt: Vector2, zoom: float = 1.60, duration: float = 0.36):
	if board_camera_root == null:
		return
	if cam_tween != null and cam_tween.is_valid():
		cam_tween.kill()
		
	var vp_size = board_viewport.size
	if vp_size.x < 100.0:
		vp_size = Vector2(860.0, 860.0)
	var vp_center = vp_size * 0.5
	var vp_global = board_viewport.global_position
	if vp_global.length_squared() < 1.0:
		vp_global = Vector2(485.0, 110.0)
		
	var delta_pt = local_pt - vp_center
	var clamped_local = vp_center + Vector2(
		clampf(delta_pt.x, -240.0, 240.0),
		clampf(delta_pt.y, -185.0, 185.0)
	)
	
	var target_board_pos = vp_center - clamped_local * zoom
	var target_scale = Vector2(zoom, zoom)
	var target_bg_pos = (vp_global + vp_center) - (vp_global + clamped_local) * zoom
	
	cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	cam_tween.tween_property(board_camera_root, "scale", target_scale, duration)
	cam_tween.tween_property(board_camera_root, "position", target_board_pos, duration)
	if phase_bg_rect != null and phase_bg_rect.visible:
		cam_tween.tween_property(phase_bg_rect, "scale", target_scale, duration)
		cam_tween.tween_property(phase_bg_rect, "position", target_bg_pos, duration)
	await cam_tween.finished

func _focus_camera_on_cell(cell: Vector2i, zoom: float = 1.60, duration: float = 0.36):
	var center_px = _cell_to_pixel(cell) + Vector2(tile_px_size * 0.5, tile_px_size * 0.5)
	await _focus_camera_on_pixel(center_px, zoom, duration)

func _reset_camera(duration: float = 0.38):
	if board_camera_root == null:
		return
	if cam_tween != null and cam_tween.is_valid():
		cam_tween.kill()
		
	cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	cam_tween.tween_property(board_camera_root, "scale", Vector2.ONE, duration)
	cam_tween.tween_property(board_camera_root, "position", Vector2.ZERO, duration)
	if phase_bg_rect != null:
		cam_tween.tween_property(phase_bg_rect, "scale", Vector2.ONE, duration)
		cam_tween.tween_property(phase_bg_rect, "position", Vector2.ZERO, duration)
	await cam_tween.finished

func _update_single_unit_hud(pid: int):
	if not unit_nodes.has(pid) or not fe_players.has(pid):
		return
	var unit: Control = unit_nodes[pid]
	var p = fe_players[pid]
	var rps_icon_name = RPS_CONFIG.get(p["rps"], RPS_CONFIG["rock"])["icon"]
	var rps_ic: PixelIcon = unit.get_node("BadgeBox/RPSIcon")
	rps_ic.set_icon(rps_icon_name)
	var boost_ic: PixelIcon = unit.get_node("BadgeBox/BoostIcon")
	boost_ic.visible = (p["dmg_boost_turns"] > 0)
	var hp_lbl: Label = unit.get_node("HPBox/HPLabel")
	hp_lbl.text = "%d" % p["hp"]
	var hp_ratio = float(p["hp"]) / float(max(1, p["max_hp"]))
	if hp_ratio > 0.5:
		hp_lbl.add_theme_color_override("font_color", Color(0.35, 1.0, 0.45))
	elif hp_ratio > 0.25:
		hp_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	else:
		hp_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))

func _spawn_tile_pulse(cell: Vector2i, color: Color):
	if fx_layer == null:
		return
	var pulse = Panel.new()
	pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pulse.size = Vector2(tile_px_size + 4, tile_px_size + 4)
	pulse.pivot_offset = pulse.size * 0.5
	pulse.position = _cell_to_pixel(cell) - Vector2(2, 2)
	var st = StyleBoxFlat.new()
	st.bg_color = Color(color.r, color.g, color.b, 0.36)
	st.border_width_left = 3
	st.border_width_top = 3
	st.border_width_right = 3
	st.border_width_bottom = 3
	st.border_color = Color(1.0, 1.0, 1.0, 0.95)
	st.corner_radius_top_left = 8
	st.corner_radius_top_right = 8
	st.corner_radius_bottom_right = 8
	st.corner_radius_bottom_left = 8
	pulse.add_theme_stylebox_override("panel", st)
	fx_layer.add_child(pulse)
	var tw = create_tween().set_parallel(true)
	tw.tween_property(pulse, "scale", Vector2(1.22, 1.22), 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(pulse, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(func(): pulse.queue_free())

func _refresh_board_visuals():
	round_label.text = "RUNDE %d" % round_number
	var turns_until_shrink = 2 - ((round_number - 1) % 2)
	if zone_max_dist > 1:
		zone_label.text = "Feuer rückt vor in %d %s (Radius: %d)" % [
			turns_until_shrink,
			"Runde" if turns_until_shrink == 1 else "Runden",
			zone_max_dist
		]
	else:
		zone_label.text = "Feuer-Zone auf Maximalstufe!"
		
	# Kacheln aktualisieren
	for cell in tile_nodes:
		var panel: Panel = tile_nodes[cell]
		var style = StyleBoxFlat.new()
		var key = "%d,%d" % [cell.x, cell.y]
		var r_dist = arena_ring_dist(cell)
		var in_danger = is_cell_in_danger_zone(cell)
		var is_next_ring = (not in_danger and zone_max_dist > 1 and r_dist == zone_max_dist and turns_until_shrink == 1)
		var is_checker = ((cell.x + cell.y) % 2) == 0
		var terrain_hash = (cell.x * 17 + cell.y * 31 + cell.x * cell.y * 7) % 10
		var is_bare_dirt = (terrain_hash < 5)
		
		if in_danger:
			style.bg_color = Color(0.55, 0.16, 0.08, 0.34) if is_checker else Color(0.46, 0.13, 0.06, 0.34)
			style.border_color = Color(1.0, 0.44, 0.14, 0.90)
		elif special_tiles.has(key):
			var st_cfg = SPECIAL_TYPES[special_tiles[key]]
			style.bg_color = Color(st_cfg["color"].r * 0.45, st_cfg["color"].g * 0.45, st_cfg["color"].b * 0.45, 0.72)
			style.border_color = st_cfg["color"]
		else:
			# Schlachtfeld-Optik: durchscheinender Mix aus kahler aufgewühlter Erde und abgetretenem Gras,
			# damit die Hintergrund-Details (Rüstungen, Schwerter, Schilde, Wagen-Spuren) sichtbar bleiben
			if is_bare_dirt:
				style.bg_color = Color(0.32, 0.22, 0.14, 0.24) if is_checker else Color(0.27, 0.18, 0.11, 0.24)
				style.border_color = Color(0.62, 0.47, 0.31, 0.56)
			else:
				style.bg_color = Color(0.24, 0.36, 0.16, 0.22) if is_checker else Color(0.20, 0.31, 0.13, 0.22)
				style.border_color = Color(0.46, 0.58, 0.30, 0.54)
			if is_next_ring:
				style.border_color = Color(0.98, 0.48, 0.16, 0.88)
			
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_right = 6
		style.corner_radius_bottom_left = 6
		panel.add_theme_stylebox_override("panel", style)
		
		var prop_node = panel.get_node_or_null("PropDetail")
		if prop_node:
			prop_node.visible = (prop_node.texture != null and not in_danger and not special_tiles.has(key))
		
		var icon_node: PixelIcon = panel.get_node("SpecialIcon")
		icon_node.position = (Vector2(tile_px_size, tile_px_size) - PixelIcon.SIZE_M) * 0.5
		if special_tiles.has(key):
			icon_node.set_icon(SPECIAL_TYPES[special_tiles[key]]["icon"], Color.WHITE)
			icon_node.visible = true
		else:
			icon_node.visible = false
			
		# Animiertes Feuer-Overlay auf der Kachel aktualisieren
		if tile_fire_nodes.has(cell):
			var fire_rect: TextureRect = tile_fire_nodes[cell]
			var phase = (cell.x * 3 + cell.y * 5)
			if in_danger:
				fire_rect.visible = true
				if not tex_fire_frames.is_empty():
					fire_rect.texture = tex_fire_frames[(fire_anim_step + phase) % tex_fire_frames.size()]
				var ring_depth = r_dist - zone_max_dist
				fire_rect.modulate = Color(1.0, 0.96, 0.90, 0.96) if ring_depth == 1 else Color(1.0, 0.86, 0.78, 0.98)
			elif is_next_ring and not tex_ember_frames.is_empty():
				fire_rect.visible = true
				fire_rect.texture = tex_ember_frames[(fire_anim_step + phase) % tex_ember_frames.size()]
				fire_rect.modulate = Color(1.0, 0.85, 0.65, 0.82)
			else:
				fire_rect.visible = false
			
	# Charakter-Nodes aktualisieren
	for pid in unit_nodes:
		var unit: Control = unit_nodes[pid]
		var p = fe_players[pid]
		unit.visible = p["alive"]
		if not p["alive"]:
			continue
		unit.position = _cell_to_pixel(p["pos"])
		var rps_icon_name = RPS_CONFIG.get(p["rps"], RPS_CONFIG["rock"])["icon"]
		var rps_ic: PixelIcon = unit.get_node("BadgeBox/RPSIcon")
		rps_ic.set_icon(rps_icon_name)
		var boost_ic: PixelIcon = unit.get_node("BadgeBox/BoostIcon")
		boost_ic.visible = (p["dmg_boost_turns"] > 0)
		
		var hp_box: Control = unit.get_node("HPBox")
		hp_box.position = Vector2(tile_px_size - 36, 1)
		var hp_lbl: Label = unit.get_node("HPBox/HPLabel")
		hp_lbl.text = "%d" % p["hp"]
		var hp_ratio = float(p["hp"]) / float(max(1, p["max_hp"]))
		if hp_ratio > 0.5:
			hp_lbl.add_theme_color_override("font_color", Color(0.35, 1.0, 0.45))
		elif hp_ratio > 0.25:
			hp_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
		else:
			hp_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
			
	_refresh_sidebar_status()

func _refresh_sidebar_status():
	for child in teams_status_list.get_children():
		child.queue_free()
		
	var alive_count = 0
	var ready_count = 0
	for pid in fe_players:
		if fe_players[pid]["alive"]:
			alive_count += 1
			if fe_players[pid]["turn_ready"]:
				ready_count += 1
				
	if current_phase == Phase.BATTLE and not is_resolving_turn:
		turn_banner.text = "Züge bereit: %d / %d" % [ready_count, alive_count]
		
	for t_idx in range(NetworkManager.computed_teams.size()):
		var team = NetworkManager.computed_teams[t_idx]
		var t_box = VBoxContainer.new()
		t_box.add_theme_constant_override("separation", 6)
		
		var t_header = Label.new()
		t_header.text = team.get("name", "Team " + str(t_idx + 1))
		t_header.add_theme_font_size_override("font_size", 22)
		t_header.add_theme_color_override("font_color", team.get("color", Color.WHITE))
		t_box.add_child(t_header)
		
		for pid in fe_players:
			var p = fe_players[pid]
			if p["team_index"] != t_idx:
				continue
			var p_row = PanelContainer.new()
			var p_style = StyleBoxFlat.new()
			p_style.bg_color = Color(0.11, 0.14, 0.22, 0.9) if p["alive"] else Color(0.08, 0.08, 0.10, 0.6)
			p_style.border_width_left = 3
			p_style.border_color = p["team_color"] if p["alive"] else Color(0.3, 0.3, 0.3, 0.5)
			p_style.corner_radius_top_left = 6
			p_style.corner_radius_bottom_left = 6
			p_style.content_margin_left = 10
			p_style.content_margin_right = 10
			p_style.content_margin_top = 6
			p_style.content_margin_bottom = 6
			p_row.add_theme_stylebox_override("panel", p_style)
			
			var r_vbox = VBoxContainer.new()
			r_vbox.add_theme_constant_override("separation", 4)
			p_row.add_child(r_vbox)
			
			var rps_icon = RPS_CONFIG.get(p["rps"], RPS_CONFIG["rock"])["icon"]
			var role_icon = ROLE_CONFIG.get(p["role"], ROLE_CONFIG["tank"])["icon"]
			var status_icon = "skull" if not p["alive"] else ("check" if p["turn_ready"] else "hourglass")
			
			var top_row = HBoxContainer.new()
			top_row.add_theme_constant_override("separation", 6)
			top_row.add_child(PixelIcon.create(status_icon, "S"))
			
			var top_lbl = Label.new()
			top_lbl.text = p["name"]
			top_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			top_lbl.add_theme_font_size_override("font_size", 17)
			top_lbl.add_theme_color_override("font_color", Color.WHITE if p["alive"] else Color(0.55, 0.55, 0.6))
			top_row.add_child(top_lbl)
			
			top_row.add_child(PixelIcon.create(rps_icon, "S"))
			top_row.add_child(PixelIcon.create(role_icon, "S"))
			r_vbox.add_child(top_row)
			
			if p["alive"]:
				var sub_row = HBoxContainer.new()
				sub_row.add_theme_constant_override("separation", 12)
				var sub_col = Color(0.85, 0.9, 1.0, 0.9)
				var boost_txt = " (+1)" if p["dmg_boost_turns"] > 0 else ""
				sub_row.add_child(PixelIcon.create_stat_chip("heart", "%d/%d" % [p["hp"], p["max_hp"]], "S", 14, sub_col))
				sub_row.add_child(PixelIcon.create_stat_chip("sword", "%d%s" % [p["dmg"], boost_txt], "S", 14, sub_col))
				sub_row.add_child(PixelIcon.create_stat_chip("boots", "%d" % p["steps"], "S", 14, sub_col))
				r_vbox.add_child(sub_row)
			else:
				var sub_lbl = Label.new()
				sub_lbl.text = "Ausgeschieden"
				sub_lbl.add_theme_color_override("font_color", Color(0.75, 0.35, 0.35, 0.85))
				sub_lbl.add_theme_font_size_override("font_size", 14)
				r_vbox.add_child(sub_lbl)
			
			t_box.add_child(p_row)
			
		teams_status_list.add_child(t_box)

func _start_planning_round():
	is_resolving_turn = false
	execute_turn_btn.disabled = false
	execute_turn_btn.text = "ZÜGE AUSFÜHREN"
	
	for pid in fe_players:
		var p = fe_players[pid]
		p["turn_ready"] = not p["alive"]
		p["planned_path"] = []
		p["attack_dir"] = "up"
		p["meteor_target_pos"] = Vector2i(-1, -1)
		p["swap_rps_choice"] = ""
		
	_refresh_board_visuals()
	_broadcast_battle_state_to_all()

func _build_player_turn_payload(target_pid: int) -> Dictionary:
	var units_list: Array = []
	for pid in fe_players:
		var u = fe_players[pid]
		if not u["alive"]:
			continue
		units_list.append({
			"id": pid,
			"name": u["name"],
			"character": u["character"],
			"team_index": u["team_index"],
			"team_name": u["team_name"],
			"team_color": "#" + u["team_color"].to_html(false),
			"x": u["pos"].x,
			"y": u["pos"].y,
			"hp": u["hp"],
			"max_hp": u["max_hp"],
			"dmg": u["dmg"] + (1 if u["dmg_boost_turns"] > 0 else 0),
			"dmg_boost": (u["dmg_boost_turns"] > 0),
			"rps": u["rps"],
			"role": u["role"]
		})
		
	var specials_list: Array = []
	for k in special_tiles:
		var parts = k.split(",")
		if parts.size() == 2:
			var st_type = special_tiles[k]
			specials_list.append({
				"x": int(parts[0]),
				"y": int(parts[1]),
				"type": st_type,
				"icon": SPECIAL_TYPES[st_type]["icon"],
				"name": SPECIAL_TYPES[st_type]["name"]
			})
			
	var me = fe_players.get(target_pid, {})
	return {
		"type": "state_change",
		"state": "fire_emblem_turn",
		"round": round_number,
		"grid_size": GRID_SIZE,
		"center": {"x": CENTER.x, "y": CENTER.y},
		"max_arena_dist": MAX_ARENA_DIST,
		"zone_max_dist": zone_max_dist,
		"me": {
			"id": target_pid,
			"name": me.get("name", ""),
			"team_index": me.get("team_index", 0),
			"team_name": me.get("team_name", ""),
			"alive": me.get("alive", false),
			"turn_ready": me.get("turn_ready", false),
			"x": me.get("pos", CENTER).x,
			"y": me.get("pos", CENTER).y,
			"hp": me.get("hp", 0),
			"max_hp": me.get("max_hp", 8),
			"dmg": me.get("dmg", 2) + (1 if me.get("dmg_boost_turns", 0) > 0 else 0),
			"steps": me.get("steps", 2),
			"rps": me.get("rps", "rock"),
			"role": me.get("role", "tank")
		},
		"units": units_list,
		"specials": specials_list
	}

func _broadcast_battle_state_to_all():
	NetworkManager.current_game_state = "fire_emblem_turn"
	for pid in fe_players:
		NetworkManager.send_to_player(pid, _build_player_turn_payload(pid))

# ==============================================================================
# NACHRICHTEN VOM HANDY & RECONNECT
# ==============================================================================

func _on_message_received(player_id: int, data: Dictionary):
	var msg_type = data.get("type", "")
	
	if msg_type == "fe_equip_submit" and current_phase == Phase.EQUIPMENT:
		var rps = str(data.get("rps", "rock"))
		var role = str(data.get("role", "tank"))
		_apply_player_equipment(player_id, rps, role)
		_refresh_equipment_ui(false)
		
		# Prüfen ob alle bereit sind
		var all_ready = true
		for pid in fe_players:
			if not fe_players[pid]["equip_ready"]:
				all_ready = false
				break
		if all_ready and not fe_players.is_empty():
			equip_status.text = "Alle Spieler sind bereit! Klicke auf 'AUSWAHL AUFDECKEN'."
			
	elif msg_type == "fe_turn_submit" and current_phase == Phase.BATTLE and not is_resolving_turn:
		if not fe_players.has(player_id) or not fe_players[player_id]["alive"]:
			return
		var p = fe_players[player_id]
		var raw_path = data.get("path", [])
		var validated_path: Array[Vector2i] = []
		var curr = p["pos"]
		var max_steps = int(p["steps"])
		
		if typeof(raw_path) == TYPE_ARRAY:
			for step_item in raw_path:
				if validated_path.size() >= max_steps:
					break
				if typeof(step_item) == TYPE_DICTIONARY:
					var next_cell = Vector2i(int(step_item.get("x", curr.x)), int(step_item.get("y", curr.y)))
					if is_valid_cell(next_cell) and manhattan_dist(curr, next_cell) == 1:
						validated_path.append(next_cell)
						curr = next_cell
						
		var atk_dir = str(data.get("attack_dir", "up"))
		if not ["up", "down", "left", "right"].has(atk_dir):
			atk_dir = "up"
			
		var m_pos = Vector2i(-1, -1)
		var raw_m_pos = data.get("meteor_pos", null)
		if typeof(raw_m_pos) == TYPE_DICTIONARY:
			var cand = Vector2i(int(raw_m_pos.get("x", -1)), int(raw_m_pos.get("y", -1)))
			if is_valid_cell(cand):
				m_pos = cand
				
		var swap_rps = str(data.get("swap_rps", ""))
		if not ["scissors", "rock", "paper"].has(swap_rps):
			swap_rps = ""
			
		p["planned_path"] = validated_path
		p["attack_dir"] = atk_dir
		p["meteor_target_pos"] = m_pos
		p["swap_rps_choice"] = swap_rps
		p["turn_ready"] = true
		
		_refresh_sidebar_status()
		
		# Sobald alle lebenden Spieler ihren Zug bestätigt haben, automatisch auflösen!
		var all_turns_ready = true
		for pid in fe_players:
			if fe_players[pid]["alive"] and not fe_players[pid]["turn_ready"]:
				all_turns_ready = false
				break
		if all_turns_ready:
			_resolve_turn()

func _on_client_reconnected(p_id: int, _p_name: String):
	if current_phase == Phase.EQUIPMENT:
		if fe_players.has(p_id) and not fe_players[p_id]["equip_ready"]:
			NetworkManager.send_to_player(p_id, {
				"type": "state_change",
				"state": "fire_emblem_equip"
			})
		else:
			NetworkManager.send_to_player(p_id, {
				"type": "state_change",
				"state": "waiting"
			})
	elif current_phase == Phase.BATTLE and not is_resolving_turn:
		if fe_players.has(p_id):
			NetworkManager.send_to_player(p_id, _build_player_turn_payload(p_id))
		else:
			NetworkManager.send_to_player(p_id, {
				"type": "state_change",
				"state": "waiting"
			})
	else:
		NetworkManager.send_to_player(p_id, {
			"type": "state_change",
			"state": "waiting"
		})

# ==============================================================================
# ZUG-AUFLÖSUNG (BEWEGUNG, KOLLISION, SONDERFELDER, ANGRIFFE, ZONE)
# ==============================================================================

func _on_execute_turn_pressed():
	if current_phase == Phase.BATTLE and not is_resolving_turn:
		_resolve_turn()

func _resolve_turn():
	if is_resolving_turn or current_phase != Phase.BATTLE:
		return
	is_resolving_turn = true
	execute_turn_btn.disabled = true
	turn_banner.text = "Züge werden ausgeführt..."
	
	# Handys während der Animation auf Warten setzen
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})
	
	_append_log("\n[color=#ffd866][b]--- Runde %d: Auflösung ---[/b][/color]" % round_number)
	
	# 1. BEWEGUNG SCHRITT FÜR SCHRITT (bis zu 3 Schritte wegen Utility)
	var max_possible_steps = 3
	var path_blocked: Dictionary = {}
	for pid in fe_players:
		path_blocked[pid] = false
		
	var walk_player: AudioStreamPlayer = null
		
	for step_idx in range(max_possible_steps):
		var any_attempt = false
		var current_positions: Dictionary = {}
		var desired_positions: Dictionary = {}
		
		for pid in fe_players:
			var p = fe_players[pid]
			if not p["alive"]:
				continue
			current_positions[pid] = p["pos"]
			var path: Array = p["planned_path"]
			if not path_blocked[pid] and step_idx < path.size():
				desired_positions[pid] = path[step_idx]
				if path[step_idx] != p["pos"]:
					any_attempt = true
			else:
				desired_positions[pid] = p["pos"]
				
		if not any_attempt:
			break
			
		# Starte den Minecraft-Laufsound exakt für die Dauer der tatsächlichen Bewegung
		if (walk_player == null or not is_instance_valid(walk_player)) and not AudioManager.sfx_muted:
			walk_player = AudioStreamPlayer.new()
			var walk_stream = AudioManager.sfx_tracks.get("minecraft_walking", null)
			if walk_stream:
				walk_player.stream = walk_stream.duplicate()
				AudioManager._configure_stream_loop(walk_player.stream, true)
			var offset = AudioManager.sfx_volume_overrides.get("minecraft_walking", 2.0)
			walk_player.volume_db = AudioManager.volume_sfx + offset
			add_child(walk_player)
			walk_player.play()
			
		# Kollisionsprüfung:
		# a) Wollen zwei oder mehr Spieler auf dasselbe Feld?
		# b) Tauschen zwei Spieler frontal ihre Plätze (A->B und B->A)?
		# c) Läuft A auf das Feld von B, während B blockiert wurde?
		var bounced_pids: Dictionary = {}
		
		# Frontal-Tausch erkennen
		var pids = current_positions.keys()
		for i in range(pids.size()):
			for j in range(i + 1, pids.size()):
				var p1 = pids[i]
				var p2 = pids[j]
				if desired_positions[p1] == current_positions[p2] and desired_positions[p2] == current_positions[p1]:
					bounced_pids[p1] = desired_positions[p1]
					bounced_pids[p2] = desired_positions[p2]
					desired_positions[p1] = current_positions[p1]
					desired_positions[p2] = current_positions[p2]
					
		# Iterativ prüfen, ob mehrere Spieler dasselbe Zielfeld beanspruchen
		var changed = true
		while changed:
			changed = false
			var target_counts: Dictionary = {}
			for pid in pids:
				var tgt: Vector2i = desired_positions[pid]
				if not target_counts.has(tgt):
					target_counts[tgt] = []
				target_counts[tgt].append(pid)
				
			for tgt in target_counts:
				var claimers: Array = target_counts[tgt]
				if claimers.size() > 1:
					for pid in claimers:
						if desired_positions[pid] != current_positions[pid]:
							bounced_pids[pid] = desired_positions[pid]
							desired_positions[pid] = current_positions[pid]
							changed = true
							
		# Animation für Schritt step_idx abspielen
		var move_tween = create_tween().set_parallel(true)
		for pid in pids:
			var unit: Control = unit_nodes[pid]
			var start_px = _cell_to_pixel(current_positions[pid])
			if bounced_pids.has(pid):
				path_blocked[pid] = true
				var bump_cell: Vector2i = bounced_pids[pid]
				var mid_px = start_px.lerp(_cell_to_pixel(bump_cell), 0.42)
				var seq = create_tween()
				seq.tween_property(unit, "position", mid_px, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				seq.tween_property(unit, "position", start_px, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				_spawn_floating_text(bump_cell, "ABGEPRALLT!", Color(1.0, 0.65, 0.25), "bolt")
				_append_log("[icon=bolt] [b]%s[/b] ist bei (%d,%d) abgeprallt!" % [fe_players[pid]["name"], bump_cell.x, bump_cell.y])
			else:
				fe_players[pid]["pos"] = desired_positions[pid]
				var end_px = _cell_to_pixel(desired_positions[pid])
				move_tween.tween_property(unit, "position", end_px, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				
		await get_tree().create_timer(0.42).timeout
		_refresh_board_visuals()
		
		# Prüfe, ob im nächsten Schritt noch jemand läuft: falls nein, Laufsound sofort beenden
		var will_continue_walking = false
		if step_idx + 1 < max_possible_steps:
			for pid in fe_players:
				var p = fe_players[pid]
				if p["alive"] and not path_blocked[pid] and (step_idx + 1) < p["planned_path"].size():
					will_continue_walking = true
					break
		if not will_continue_walking and walk_player != null and is_instance_valid(walk_player):
			walk_player.stop()
			walk_player.queue_free()
			walk_player = null
		
	if walk_player != null and is_instance_valid(walk_player):
		walk_player.stop()
		walk_player.queue_free()
		walk_player = null
		
	_refresh_board_visuals()
		
	# 2. SONDERFELDER AUSLÖSEN (nacheinander mit sanftem Kamera-Zoom zeigen)
	var alive_before_specials = _get_alive_pids()
	var any_special_triggered = false
	for pid in alive_before_specials:
		var p = fe_players[pid]
		if not p["alive"]:
			continue
		var key = "%d,%d" % [p["pos"].x, p["pos"].y]
		if special_tiles.has(key):
			any_special_triggered = true
			var st_type = special_tiles[key]
			var pickup_pos: Vector2i = p["pos"]
			special_tiles.erase(key)
			await _trigger_special_tile(pid, st_type)
			_spawn_single_special_tile(st_type, pickup_pos, p["pos"])
			
	if any_special_triggered:
		await _reset_camera(0.38)
		_refresh_board_visuals()
		await get_tree().create_timer(0.35).timeout
		if _get_alive_team_count() == 0:
			await _trigger_sudden_death_revive(alive_before_specials)
		elif _check_for_game_over():
			return
		
	# 3. GLEICHZEITIGE ANGRIFFSPHASE (logisch gleichzeitig, aber visuell nacheinander mit Kamera-Zoom gezeigt!)
	# Alle Spieler, die zu Beginn der Angriffsphase gelebt haben, führen ihren Schlag aus:
	# auch dann, wenn sie durch einen früher gezeigten Angriff in derselben Runde bereits auf 0 HP gefallen sind.
	var alive_before_attacks = _get_alive_pids()
	var any_attack_shown = false
	
	for pid in alive_before_attacks:
		var attacker = fe_players[pid]
		var dir_vec = _dir_to_vector(attacker["attack_dir"])
		var target_cell: Vector2i = attacker["pos"] + dir_vec
		if not is_valid_cell(target_cell):
			continue
			
		any_attack_shown = true
		turn_banner.text = "Angriff: %s!" % attacker["name"]
		
		# Sanfter Zoom auf den Mittelpunkt zwischen Angreifer und Zielkachel
		var att_center = _cell_to_pixel(attacker["pos"]) + Vector2(tile_px_size * 0.5, tile_px_size * 0.5)
		var tgt_center = _cell_to_pixel(target_cell) + Vector2(tile_px_size * 0.5, tile_px_size * 0.5)
		var focus_px = (att_center + tgt_center) * 0.5
		await _focus_camera_on_pixel(focus_px, 1.62, 0.34)
		
		# Kurzer Ausfallschritt (Lunge) des Angreifers in Schlagrichtung
		if unit_nodes.has(pid):
			var att_unit: Control = unit_nodes[pid]
			var start_pos = _cell_to_pixel(attacker["pos"])
			var lunge_offset = Vector2(dir_vec.x, dir_vec.y) * 14.0
			var lunge_tw = create_tween()
			lunge_tw.tween_property(att_unit, "position", start_pos + lunge_offset, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			lunge_tw.tween_property(att_unit, "position", start_pos, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			
		_spawn_slash_effect(attacker["pos"], target_cell, attacker["team_color"])
		
		# Prüfe, wer auf target_cell steht (alle zu Beginn der Angriffsphase lebenden Spieler sind gültige Ziele)
		var hit_someone = false
		for def_pid in alive_before_attacks:
			var defender = fe_players[def_pid]
			if defender["pos"] != target_cell:
				continue
			hit_someone = true
			if defender["team_index"] == attacker["team_index"]:
				_spawn_floating_text(target_cell, "Team!", Color(0.55, 0.85, 1.0), "shield")
				continue
				
			var base_dmg = int(attacker["dmg"]) + (1 if attacker["dmg_boost_turns"] > 0 else 0)
			var adv = _get_rps_advantage(attacker["rps"], defender["rps"])
			var final_dmg = max(1, base_dmg + adv)
			var eff_text = ""
			if adv > 0:
				eff_text = " (Effektiv +1)"
			elif adv < 0:
				eff_text = " (Schwach -1)"
				
			defender["hp"] = max(0, int(defender["hp"]) - final_dmg)
			_update_single_unit_hud(def_pid)
			_refresh_sidebar_status()
			
			AudioManager.play_sfx("hit")
			
			# Treffer-Shake auf dem getroffenen Charakter (bleibt während der Angriffsphase sichtbar, damit er selbst noch zuschlagen kann!)
			if unit_nodes.has(def_pid):
				var def_unit: Control = unit_nodes[def_pid]
				var def_base = _cell_to_pixel(defender["pos"])
				var hit_tw = create_tween()
				hit_tw.tween_property(def_unit, "position", def_base + Vector2(6, -3), 0.05)
				hit_tw.tween_property(def_unit, "position", def_base + Vector2(-6, 3), 0.05)
				hit_tw.tween_property(def_unit, "position", def_base + Vector2(4, 2), 0.05)
				hit_tw.tween_property(def_unit, "position", def_base, 0.06)
				
			var dmg_color = Color(1.0, 0.25, 0.25)
			var prefix = "-"
			if adv > 0:
				dmg_color = Color(1.0, 0.85, 0.2)
				prefix = "KRIT -"
			_spawn_floating_text(defender["pos"], "%s%d HP" % [prefix, final_dmg], dmg_color, "sword")
			_append_log("[icon=sword] [b]%s[/b] trifft [b]%s[/b] für [color=#ff6666]%d Schaden[/color]%s!" % [
				attacker["name"], defender["name"], final_dmg, eff_text
			])
			
		if hit_someone:
			await get_tree().create_timer(0.62).timeout
		else:
			AudioManager.play_sfx("missed_punch")
			await get_tree().create_timer(0.36).timeout
			
	if any_attack_shown:
		await _reset_camera(0.38)
		
	# Jetzt erst scheiden alle im Schlagabtausch auf 0 HP gefallenen Kämpfer endgültig aus
	var any_ko = false
	for def_pid in alive_before_attacks:
		var defender = fe_players[def_pid]
		if defender["hp"] <= 0 and defender["alive"]:
			defender["alive"] = false
			any_ko = true
			turn_banner.text = "%s scheidet aus!" % defender["name"]
			await _focus_camera_on_cell(defender["pos"], 1.65, 0.32)
			AudioManager.play_sfx("bye_bye")
			_spawn_floating_text(defender["pos"], "BESIEGT!", Color(1.0, 0.3, 0.3), "skull")
			_append_log("[icon=skull] [b]%s[/b] (%s) wurde besiegt!" % [defender["name"], defender["team_name"]])
			if unit_nodes.has(def_pid):
				var u_node: Control = unit_nodes[def_pid]
				var ko_tw = create_tween().set_parallel(true)
				ko_tw.tween_property(u_node, "modulate:a", 0.0, 0.5)
				ko_tw.tween_property(u_node, "scale", Vector2(0.3, 0.3), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			await get_tree().create_timer(0.95).timeout
			
	if any_ko:
		await _reset_camera(0.35)
			
	# Reduziere temporäre Schadens-Buffs
	for pid in fe_players:
		if fe_players[pid]["dmg_boost_turns"] > 0:
			fe_players[pid]["dmg_boost_turns"] -= 1
			
	_refresh_board_visuals()
	await get_tree().create_timer(0.35).timeout
	
	# Prüfe nach der Angriffsphase auf Doppel-K.O. (Sudden Death) oder vorzeitigen Sieg
	if _get_alive_team_count() == 0:
		await _trigger_sudden_death_revive(alive_before_attacks)
	elif _check_for_game_over():
		return
	
	# 4. ZONEN-SCHADEN & ZONEN-SCHRUMPFUNG
	var alive_before_zone = _get_alive_pids()
	var zone_hit_any = false
	for pid in alive_before_zone:
		var p = fe_players[pid]
		if not p["alive"]:
			continue
		if is_cell_in_danger_zone(p["pos"]):
			zone_hit_any = true
			turn_banner.text = "Feuerzone: %s!" % p["name"]
			await _focus_camera_on_cell(p["pos"], 1.56, 0.32)
			AudioManager.play_sfx("fire_spread")
			p["hp"] = max(0, p["hp"] - 1)
			_update_single_unit_hud(pid)
			_spawn_tile_pulse(p["pos"], Color(1.0, 0.38, 0.12))
			_spawn_floating_text(p["pos"], "ZONE -1 HP", Color(1.0, 0.35, 0.2), "fire")
			_append_log("[icon=fire] [b]%s[/b] steht in der Gefahrenzone (-1 HP)!" % p["name"])
			if unit_nodes.has(pid):
				var unit_node: Control = unit_nodes[pid]
				var base_pos = _cell_to_pixel(p["pos"])
				var shake_tw = create_tween()
				shake_tw.tween_property(unit_node, "position", base_pos + Vector2(5, -2), 0.05)
				shake_tw.tween_property(unit_node, "position", base_pos + Vector2(-5, 2), 0.05)
				shake_tw.tween_property(unit_node, "position", base_pos, 0.06)
			if p["hp"] <= 0:
				p["alive"] = false
				turn_banner.text = "%s ist gefallen!" % p["name"]
				AudioManager.play_sfx("bye_bye")
				_spawn_floating_text(p["pos"], "BESIEGT!", Color(1.0, 0.3, 0.3), "skull")
				_append_log("[icon=skull] [b]%s[/b] ist in der Gefahrenzone gefallen!" % p["name"])
				if unit_nodes.has(pid):
					var u_node: Control = unit_nodes[pid]
					var ko_tw = create_tween().set_parallel(true)
					ko_tw.tween_property(u_node, "modulate:a", 0.0, 0.5)
					ko_tw.tween_property(u_node, "scale", Vector2(0.3, 0.3), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
				await get_tree().create_timer(0.95).timeout
			else:
				await get_tree().create_timer(0.52).timeout
				
	if zone_hit_any:
		await _reset_camera(0.36)
		_refresh_board_visuals()
		await get_tree().create_timer(0.35).timeout
		if _get_alive_team_count() == 0:
			await _trigger_sudden_death_revive(alive_before_zone)
		
	# Alle 2 Runden breitet sich das Feuer um 1 Stufe weiter nach innen aus
	if round_number % 2 == 0 and zone_max_dist > 1:
		var newly_burning_ring = zone_max_dist
		zone_max_dist -= 1
		_append_log("[color=#ff5555][b][icon=fire] Das Feuer breitet sich nach innen aus! (Neuer sicherer Radius: %d)[/b][/color]" % zone_max_dist)
		_spawn_floating_text(CENTER, "FEUER BREITET SICH AUS!", Color(1.0, 0.45, 0.18), "fire")
		AudioManager.play_sfx("fire_spread")
		await _animate_fire_spreading_inward(newly_burning_ring)
		_refresh_board_visuals()
		await get_tree().create_timer(0.35).timeout
		
	# 5. SIEG-BEDINGUNG PRÜFEN
	if _check_for_game_over():
		return
		
	round_number += 1
	_start_planning_round()

func _animate_fire_spreading_inward(ignited_ring_dist: int):
	_refresh_board_visuals()
	var wave_tween = create_tween().set_parallel(true)
	var temp_fx_nodes: Array[Node] = []
	
	for cell in tile_nodes:
		if arena_ring_dist(cell) != ignited_ring_dist:
			continue
		# Bestimme Startpunkt der überspringenden Flammenzunge (1 Schritt weiter außen vom Zentrum weg)
		var step_out = Vector2i(0, 0)
		if abs(cell.x - CENTER.x) >= abs(cell.y - CENTER.y):
			step_out.x = 1 if cell.x >= CENTER.x else -1
		else:
			step_out.y = 1 if cell.y >= CENTER.y else -1
		var outer_cell = cell + step_out
		var start_px = _cell_to_pixel(outer_cell)
		var target_px = _cell_to_pixel(cell)
		
		# Animierte Flammenwoge exakt in Feldgröße, die vom äußeren Feuerring auf das neue Feld überspringt
		if fx_layer != null and not tex_fire_frames.is_empty():
			var surge = TextureRect.new()
			surge.size = Vector2(tile_px_size, tile_px_size)
			surge.pivot_offset = Vector2(tile_px_size * 0.5, tile_px_size * 0.5)
			surge.position = start_px
			surge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			surge.stretch_mode = TextureRect.STRETCH_SCALE
			surge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			surge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			surge.texture = tex_fire_frames[(cell.x + cell.y) % tex_fire_frames.size()]
			surge.modulate = Color(1.0, 0.92, 0.45, 0.98)
			fx_layer.add_child(surge)
			temp_fx_nodes.append(surge)
			wave_tween.tween_property(surge, "position", target_px, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			wave_tween.tween_property(surge, "modulate:a", 0.0, 0.18).set_delay(0.28)
			
		# Das neue Feld-Feuer wächst von klein auf volle Feldgröße heran
		if tile_fire_nodes.has(cell):
			var fire_rect: TextureRect = tile_fire_nodes[cell]
			fire_rect.scale = Vector2(0.25, 0.25)
			fire_rect.modulate = Color(1.0, 1.0, 0.65, 1.0)
			wave_tween.tween_property(fire_rect, "scale", Vector2(1.0, 1.0), 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			wave_tween.tween_property(fire_rect, "modulate", Color(1.0, 0.96, 0.90, 0.96), 0.42)
			
	await get_tree().create_timer(0.46).timeout
	for n in temp_fx_nodes:
		if is_instance_valid(n):
			n.queue_free()

func _trigger_special_tile(pid: int, st_type: String):
	var p = fe_players[pid]
	var cell: Vector2i = p["pos"]
	var st_cfg = SPECIAL_TYPES.get(st_type, {"name": "Sonderfeld", "color": Color.WHITE})
	turn_banner.text = "%s: %s!" % [p["name"], st_cfg["name"]]
	
	# Sanfter Kamera-Zoom auf das eingesammelte Sonderfeld
	await _focus_camera_on_cell(cell, 1.62, 0.35)
	_spawn_tile_pulse(cell, st_cfg["color"])
	
	if st_type == "heal":
		AudioManager.play_sfx("healing")
		var before = p["hp"]
		p["hp"] = min(p["max_hp"], p["hp"] + 2)
		var healed = p["hp"] - before
		_update_single_unit_hud(pid)
		_refresh_sidebar_status()
		_spawn_floating_text(cell, "+%d HP" % max(1, healed), Color(0.3, 1.0, 0.45), "heal")
		_append_log("[icon=heal] [b]%s[/b] nutzt eine Heilquelle (+%d HP)!" % [p["name"], healed])
		await get_tree().create_timer(0.62).timeout
		
	elif st_type == "type_swap":
		AudioManager.play_sfx("transformation")
		var chosen_rps = str(p.get("swap_rps_choice", ""))
		if not ["scissors", "rock", "paper"].has(chosen_rps):
			var order = ["scissors", "rock", "paper"]
			var idx = order.find(p["rps"])
			chosen_rps = order[(idx + 1) % order.size()]
		p["rps"] = chosen_rps
		var new_cfg = RPS_CONFIG[p["rps"]]
		_update_single_unit_hud(pid)
		_refresh_sidebar_status()
		_spawn_floating_text(cell, new_cfg["name"], Color(0.4, 0.85, 1.0), new_cfg["icon"])
		_append_log("[icon=swap] [b]%s[/b] wechselt den Typ zu [b][icon=%s] %s[/b]!" % [p["name"], new_cfg["icon"], new_cfg["name"]])
		await get_tree().create_timer(0.62).timeout
		
	elif st_type == "dmg_boost":
		AudioManager.play_sfx("dmg_buff")
		p["dmg_boost_turns"] = 2
		_update_single_unit_hud(pid)
		_refresh_sidebar_status()
		_spawn_floating_text(cell, "+1 DMG (2 Runden)", Color(1.0, 0.8, 0.25), "sword")
		_append_log("[icon=sword] [b]%s[/b] aktiviert den Schwert-Schrein (+1 Schaden für 2 Runden)!" % p["name"])
		await get_tree().create_timer(0.62).timeout
		
	elif st_type == "teleport":
		var safe_cells: Array[Vector2i] = []
		var occupied: Dictionary = {}
		for opid in fe_players:
			if fe_players[opid]["alive"]:
				occupied["%d,%d" % [fe_players[opid]["pos"].x, fe_players[opid]["pos"].y]] = true
		for y in range(GRID_SIZE):
			for x in range(GRID_SIZE):
				var c = Vector2i(x, y)
				var k = "%d,%d" % [c.x, c.y]
				if is_valid_cell(c) and manhattan_dist(c, CENTER) <= min(3, zone_max_dist) and not occupied.has(k):
					safe_cells.append(c)
		if not safe_cells.is_empty():
			var dest = safe_cells[randi() % safe_cells.size()]
			AudioManager.play_sfx("teleport")
			_spawn_floating_text(cell, "PORTAL!", Color(0.75, 0.45, 1.0), "portal")
			await get_tree().create_timer(0.28).timeout
			
			p["pos"] = dest
			var unit: Control = unit_nodes[pid]
			var tw = create_tween()
			tw.tween_property(unit, "position", _cell_to_pixel(dest), 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			
			# Kamera folgt sanft zum Zielort des Teleports
			await _focus_camera_on_cell(dest, 1.62, 0.44)
			_spawn_tile_pulse(dest, Color(0.75, 0.45, 1.0))
			_spawn_floating_text(dest, "TELEPORT!", Color(0.75, 0.45, 1.0), "portal")
			_append_log("[icon=portal] [b]%s[/b] teleportiert auf Feld (%d,%d)!" % [p["name"], dest.x, dest.y])
			await get_tree().create_timer(0.58).timeout
			
	elif st_type == "meteor":
		# Kurz zeigen, wer den Meteor auf dem Sonderfeld beschwört
		_spawn_floating_text(cell, "METEOR-ZAUBER!", Color(1.0, 0.55, 0.2), "meteor")
		await get_tree().create_timer(0.32).timeout
		
		# Bestimme das Zentrum des + förmigen Meteor-Bereichs
		var target_center: Vector2i = p.get("meteor_target_pos", Vector2i(-1, -1))
		if not is_valid_cell(target_center):
			target_center = CENTER
			var best_dist = 999
			for ep_id in fe_players:
				var ep = fe_players[ep_id]
				if ep["alive"] and ep["team_index"] != p["team_index"]:
					var d = manhattan_dist(cell, ep["pos"])
					if d < best_dist:
						best_dist = d
						target_center = ep["pos"]
						
		var plus_offsets = [
			Vector2i(0, 0),
			Vector2i(1, 0),
			Vector2i(-1, 0),
			Vector2i(0, 1),
			Vector2i(0, -1)
		]
		var impact_cells: Array[Vector2i] = []
		for off in plus_offsets:
			var ic = target_center + off
			if is_valid_cell(ic):
				impact_cells.append(ic)
				
		# Kamera schwenkt smooth zum Einschlagsort des Kometen
		await _focus_camera_on_cell(target_center, 1.50, 0.42)
		AudioManager.play_sfx("asteroid_explosion")
		_spawn_meteor_plus_effect(impact_cells)
		_append_log("[icon=meteor] [b]%s[/b] beschwört einen Meteor im + Bereich um (%d,%d)!" % [p["name"], target_center.x, target_center.y])
		
		var hit_any = false
		for ep_id in fe_players:
			var victim = fe_players[ep_id]
			if not victim["alive"] or victim["team_index"] == p["team_index"]:
				continue
			if impact_cells.has(victim["pos"]):
				hit_any = true
				victim["hp"] = max(0, victim["hp"] - 2)
				_update_single_unit_hud(ep_id)
				_refresh_sidebar_status()
				if unit_nodes.has(ep_id):
					var v_unit: Control = unit_nodes[ep_id]
					var v_base = _cell_to_pixel(victim["pos"])
					var v_tw = create_tween()
					v_tw.tween_property(v_unit, "position", v_base + Vector2(6, -4), 0.05)
					v_tw.tween_property(v_unit, "position", v_base + Vector2(-6, 4), 0.05)
					v_tw.tween_property(v_unit, "position", v_base, 0.06)
				_spawn_floating_text(victim["pos"], "METEOR -2 HP!", Color(1.0, 0.45, 0.15), "meteor")
				_append_log("[icon=meteor] [b]%s[/b] wird vom Meteor getroffen (-2 HP)!" % victim["name"])
				if victim["hp"] <= 0:
					victim["alive"] = false
					turn_banner.text = "%s wurde ausgelöscht!" % victim["name"]
					await _focus_camera_on_cell(victim["pos"], 1.65, 0.32)
					AudioManager.play_sfx("bye_bye")
					_spawn_floating_text(victim["pos"], "BESIEGT!", Color(1.0, 0.3, 0.3), "skull")
					_append_log("[icon=skull] [b]%s[/b] wurde vom Meteor ausgelöscht!" % victim["name"])
					if unit_nodes.has(ep_id):
						var u_node: Control = unit_nodes[ep_id]
						var ko_tw = create_tween().set_parallel(true)
						ko_tw.tween_property(u_node, "modulate:a", 0.0, 0.5)
						ko_tw.tween_property(u_node, "scale", Vector2(0.3, 0.3), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
					await get_tree().create_timer(0.95).timeout
		if not hit_any:
			_spawn_floating_text(target_center, "METEOR!", Color(1.0, 0.55, 0.2), "meteor")
		await get_tree().create_timer(0.75).timeout

func _dir_to_vector(dir_str: String) -> Vector2i:
	match dir_str:
		"up": return Vector2i(0, -1)
		"down": return Vector2i(0, 1)
		"left": return Vector2i(-1, 0)
		"right": return Vector2i(1, 0)
	return Vector2i(0, -1)

func _get_rps_advantage(att_rps: String, def_rps: String) -> int:
	if att_rps == def_rps:
		return 0
	if RPS_CONFIG.get(att_rps, {}).get("beats", "") == def_rps:
		return 1
	return -1

func _show_planned_paths_on_board() -> Array[Node]:
	var created: Array[Node] = []
	if fx_layer == null:
		return created
	var half = Vector2(tile_px_size * 0.5, tile_px_size * 0.5)
	
	# 1. Blaue Feld-Markierungen für alle geplanten Schritte
	var marked_cells: Dictionary = {}
	for pid in fe_players:
		var p = fe_players[pid]
		if not p["alive"]:
			continue
		var path: Array = p["planned_path"]
		if path.is_empty():
			continue
		var all_cells: Array = [p["pos"]]
		all_cells.append_array(path)
		for c in all_cells:
			var key = "%d,%d" % [c.x, c.y]
			if marked_cells.has(key):
				continue
			marked_cells[key] = true
			var hl = Panel.new()
			hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hl.size = Vector2(tile_px_size - 4, tile_px_size - 4)
			hl.position = _cell_to_pixel(c) + Vector2(2, 2)
			var st = StyleBoxFlat.new()
			st.bg_color = Color(0.11, 0.35, 0.74, 0.55)
			st.border_width_left = 3
			st.border_width_top = 3
			st.border_width_right = 3
			st.border_width_bottom = 3
			st.border_color = Color(0.45, 0.78, 1.0, 0.95)
			st.corner_radius_top_left = 6
			st.corner_radius_top_right = 6
			st.corner_radius_bottom_right = 6
			st.corner_radius_bottom_left = 6
			hl.add_theme_stylebox_override("panel", st)
			fx_layer.add_child(hl)
			created.append(hl)
			
	# 2. Weißer Pfeil über die gelaufenen Felder pro Spieler
	for pid in fe_players:
		var p = fe_players[pid]
		if not p["alive"]:
			continue
		var path: Array = p["planned_path"]
		if path.is_empty():
			continue
		var pts: PackedVector2Array = PackedVector2Array()
		pts.append(_cell_to_pixel(p["pos"]) + half)
		for step_cell in path:
			pts.append(_cell_to_pixel(step_cell) + half)
		if pts.size() < 2:
			continue
			
		var last_pt = pts[pts.size() - 1]
		var prev_pt = pts[pts.size() - 2]
		var dir = (last_pt - prev_pt).normalized()
		var line_pts = pts.duplicate()
		line_pts[line_pts.size() - 1] = last_pt - dir * 10.0
		
		var outline_line = Line2D.new()
		outline_line.points = line_pts
		outline_line.width = 11.0
		outline_line.default_color = Color(0.0, 0.0, 0.0, 0.75)
		outline_line.joint_mode = Line2D.LINE_JOINT_ROUND
		outline_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		outline_line.end_cap_mode = Line2D.LINE_CAP_ROUND
		fx_layer.add_child(outline_line)
		created.append(outline_line)
		
		var white_line = Line2D.new()
		white_line.points = line_pts
		white_line.width = 6.0
		white_line.default_color = Color(1.0, 1.0, 1.0, 0.96)
		white_line.joint_mode = Line2D.LINE_JOINT_ROUND
		white_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		white_line.end_cap_mode = Line2D.LINE_CAP_ROUND
		fx_layer.add_child(white_line)
		created.append(white_line)
		
		var perp = Vector2(-dir.y, dir.x)
		var tip = last_pt + dir * 4.0
		var base_l = last_pt - dir * 14.0 + perp * 10.0
		var base_r = last_pt - dir * 14.0 - perp * 10.0
		
		var head_outline = Polygon2D.new()
		head_outline.polygon = PackedVector2Array([
			tip + dir * 2.5,
			base_l + perp * 2.5 - dir * 1.5,
			base_r - perp * 2.5 - dir * 1.5
		])
		head_outline.color = Color(0.0, 0.0, 0.0, 0.75)
		fx_layer.add_child(head_outline)
		created.append(head_outline)
		
		var head = Polygon2D.new()
		head.polygon = PackedVector2Array([tip, base_l, base_r])
		head.color = Color(1.0, 1.0, 1.0, 0.98)
		fx_layer.add_child(head)
		created.append(head)
		
	return created

func _spawn_meteor_plus_effect(impact_cells: Array[Vector2i]):
	if fx_layer == null:
		return
	for c in impact_cells:
		var blast = Panel.new()
		blast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		blast.size = Vector2(tile_px_size - 6, tile_px_size - 6)
		blast.position = _cell_to_pixel(c) + Vector2(3, 3)
		var st = StyleBoxFlat.new()
		st.bg_color = Color(1.0, 0.35, 0.1, 0.65)
		st.border_width_left = 3
		st.border_width_top = 3
		st.border_width_right = 3
		st.border_width_bottom = 3
		st.border_color = Color(1.0, 0.85, 0.35, 1.0)
		st.corner_radius_top_left = 8
		st.corner_radius_top_right = 8
		st.corner_radius_bottom_right = 8
		st.corner_radius_bottom_left = 8
		blast.add_theme_stylebox_override("panel", st)
		
		var center_box = CenterContainer.new()
		center_box.set_anchors_preset(Control.PRESET_FULL_RECT)
		center_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center_box.add_child(PixelIcon.create("meteor", "M"))
		blast.add_child(center_box)
		fx_layer.add_child(blast)
		
		var tw = create_tween()
		tw.tween_property(blast, "modulate:a", 0.0, 0.55)
		tw.tween_callback(func(): blast.queue_free())

func _spawn_slash_effect(from_cell: Vector2i, to_cell: Vector2i, color: Color):
	if fx_layer == null:
		return
	var slash = Panel.new()
	slash.size = Vector2(tile_px_size - 8, tile_px_size - 8)
	slash.position = _cell_to_pixel(to_cell) + Vector2(4, 4)
	var st = StyleBoxFlat.new()
	st.bg_color = Color(color.r, color.g, color.b, 0.45)
	st.border_width_left = 3
	st.border_width_top = 3
	st.border_width_right = 3
	st.border_width_bottom = 3
	st.border_color = Color.WHITE
	st.corner_radius_top_left = 8
	st.corner_radius_top_right = 8
	st.corner_radius_bottom_right = 8
	st.corner_radius_bottom_left = 8
	slash.add_theme_stylebox_override("panel", st)
	
	var center_box = CenterContainer.new()
	center_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_box.add_child(PixelIcon.create("sword", "M"))
	slash.add_child(center_box)
	fx_layer.add_child(slash)
	
	var tw = create_tween()
	tw.tween_property(slash, "modulate:a", 0.0, 0.42)
	tw.tween_callback(func(): slash.queue_free())

func _spawn_floating_text(cell: Vector2i, text: String, color: Color, icon_name: String = ""):
	if fx_layer == null:
		return
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	row.position = _cell_to_pixel(cell) + Vector2(-36, -8)
	row.custom_minimum_size = Vector2(tile_px_size + 72, 28)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon_name != "":
		row.add_child(PixelIcon.create(icon_name, "S"))
	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 5)
	row.add_child(lbl)
	fx_layer.add_child(row)
	
	var tw = create_tween().set_parallel(true)
	tw.tween_property(row, "position:y", row.position.y - 34.0, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(row, "modulate:a", 0.0, 0.85).set_delay(0.25)
	tw.chain().tween_callback(func(): row.queue_free())

func _append_log(bbcode_line: String):
	if log_label:
		PixelIcon.append_rich_line(log_label, bbcode_line, "S")

# ==============================================================================
# PHASE 4: SIEGEREHRUNG & PUNKTEVERGABE (INKL. SUDDEN DEATH BEI DOPPEL-K.O.)
# ==============================================================================

func _get_alive_pids() -> Array:
	var res: Array = []
	for pid in fe_players:
		if fe_players[pid]["alive"]:
			res.append(int(pid))
	return res

func _get_alive_team_count() -> int:
	var alive_teams: Dictionary = {}
	for pid in fe_players:
		if fe_players[pid]["alive"]:
			alive_teams[fe_players[pid]["team_index"]] = true
	return alive_teams.size()

func _trigger_sudden_death_revive(last_alive_pids: Array):
	var revived_names: Array[String] = []
	for pid in last_alive_pids:
		if not fe_players.has(pid):
			continue
		var p = fe_players[pid]
		p["alive"] = true
		p["hp"] = 1
		if unit_nodes.has(pid):
			var u: Control = unit_nodes[pid]
			u.modulate.a = 1.0
			u.scale = Vector2.ONE
			u.visible = true
		revived_names.append(p["name"])
		_spawn_floating_text(p["pos"], "SUDDEN DEATH (1 HP)!", Color(1.0, 0.88, 0.25), "heart")
		
	turn_banner.text = "DOPPEL-K.O.! Sudden Death (1 HP)!"
	turn_banner.add_theme_color_override("font_color", Color(1.0, 0.88, 0.25))
	_append_log("[color=#ffd866][b][icon=bolt] DOPPEL K.O.! Sudden Death: %s überleben knapp mit 1 HP![/b][/color]" % ", ".join(revived_names))
	_refresh_board_visuals()
	_refresh_sidebar_status()
	await get_tree().create_timer(0.75).timeout

func _check_for_game_over() -> bool:
	var alive_teams: Dictionary = {}
	for pid in fe_players:
		var p = fe_players[pid]
		if p["alive"]:
			alive_teams[p["team_index"]] = true
			
	if alive_teams.size() != 1:
		return false
		
	current_phase = Phase.GAME_OVER
	is_resolving_turn = false
	execute_turn_btn.visible = false
	back_to_board_btn.visible = false
	
	var winning_team_idx = alive_teams.keys()[0]
		
	if winning_team_idx != -1 and winning_team_idx < NetworkManager.computed_teams.size():
		var winning_team = NetworkManager.computed_teams[winning_team_idx]
		turn_banner.text = "SIEGER: " + winning_team["name"] + "!"
		turn_banner.add_theme_color_override("font_color", winning_team["color"])
		_append_log("\n[color=#ffd866][b][icon=trophy:M] %s gewinnt Fire Emblem![/b][/color]" % winning_team["name"])
		
		var points = 2
		if NetworkManager.current_selecting_team_color == winning_team["color"]:
			points = 3
			
		if NetworkManager.current_minigame_index != -1:
			NetworkManager.minigame_winners[NetworkManager.current_minigame_index] = {
				"color": winning_team["color"],
				"points": points,
				"selecting_color": NetworkManager.current_selecting_team_color
			}
			for p in winning_team.get("players", []):
				var p_id = _get_player_id(p)
				if p_id != -1 and NetworkManager.player_sessions.has(p_id):
					NetworkManager.player_sessions[p_id]["score"] += points
					
		if winner_overlay:
			winner_overlay.setup_winner(winning_team, points, "Letztes überlebendes Team auf dem Schlachtfeld!")
	else:
		turn_banner.text = "Unentschieden!"
		if winner_overlay:
			winner_overlay.setup_winner(null, 0, "Alle Einheiten sind auf dem Schlachtfeld gefallen!")
		
	_refresh_sidebar_status()
	return true

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
