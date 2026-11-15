extends Control

@onready var team_grid = $CenterContainer/VBoxContainer/TeamGrid
@onready var start_btn = $CenterContainer/VBoxContainer/StartPhase2Button

var team_colors = [
	Color(0.95, 0.35, 0.35, 1), # Rot
	Color(0.35, 0.65, 1.0, 1), # Blau
	Color(0.35, 0.85, 0.45, 1), # Gruen
	Color(1.0, 0.9, 0.3, 1), # Gelb
	Color(0.75, 0.45, 0.95, 1), # Lila
	Color(1.0, 0.6, 0.25, 1)  # Orange
]

func _ready():
	AudioManager.stop_music() # Intro-Musik nur bis zum Quiz-Start
	start_btn.pressed.connect(_on_start_pressed)
	_build_teams()
	_connect_buttons_sfx(self)

func _connect_buttons_sfx(node: Node):
	if node is Button:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func _build_teams():
	# Nutze die vom NetworkManager zentral berechneten Teams
	NetworkManager.compute_teams()
	var computed_teams = NetworkManager.computed_teams
	
	# Lösche alte Platzhalter
	for child in team_grid.get_children():
		child.queue_free()
	
	for team in computed_teams:
		_create_team_ui(team["name"], team["players"], team["color"])

func _create_team_ui(team_name: String, players: Array, bg_color: Color):
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 150)
	
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	# Leicht transparent
	style.bg_color.a = 0.8
	style.corner_radius_top_left = 15
	style.corner_radius_top_right = 15
	style.corner_radius_bottom_right = 15
	style.corner_radius_bottom_left = 15
	
	# Mehr Abstand (Padding) nach innen
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	style.content_margin_left = 30
	style.content_margin_right = 30
	
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# Team Name
	var title = Label.new()
	title.text = team_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	# Fetter Font wäre hier cool, aber wir machen es per Theme Override
	title.add_theme_color_override("font_color", Color(1,1,1,1))
	vbox.add_child(title)
	
	if NetworkManager.team_assignment_mode == "manual":
		var team_bonus = 0
		for tp in players:
			var pid = int(tp.get("id", -1))
			if pid == -1:
				for p_sess_id in NetworkManager.player_sessions.keys():
					if NetworkManager.player_sessions[p_sess_id].get("name", "") == tp.get("name", ""):
						pid = int(p_sess_id)
						break
			team_bonus += NetworkManager.quiz_bonus_points.get(pid, 0)
			
		if team_bonus > 0:
			var bonus_lbl = Label.new()
			bonus_lbl.text = "+%d Startpunkte aus Qualifikationsquiz" % team_bonus
			bonus_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bonus_lbl.add_theme_font_size_override("font_size", 16)
			bonus_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4, 1.0))
			bonus_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
			bonus_lbl.add_theme_constant_override("outline_size", 6)
			vbox.add_child(bonus_lbl)
	
	var players_hbox = HBoxContainer.new()
	players_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	players_hbox.add_theme_constant_override("separation", 40)
	
	if players.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "(Keine Spieler)"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 20)
		empty_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.7))
		players_hbox.add_child(empty_lbl)
	else:
		for p in players:
			var p_box = VBoxContainer.new()
			p_box.alignment = BoxContainer.ALIGNMENT_CENTER
			var t = TextureRect.new()
			t.custom_minimum_size = Vector2(96, 96)
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var char_name = p.get("character", "")
			if char_name == "" or not NetworkManager.character_textures.has(char_name):
				char_name = "Cedi"
			if NetworkManager.character_textures.has(char_name):
				t.texture = NetworkManager.character_textures[char_name]
			
			var l = Label.new()
			l.text = p.get("name", "Unbekannt")
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.add_theme_font_size_override("font_size", 24)
			p_box.add_child(t)
			p_box.add_child(l)
			players_hbox.add_child(p_box)
		
		if players.size() == 1:
			var solo_lbl = Label.new()
			solo_lbl.text = "(Spielt alleine)"
			solo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			solo_lbl.add_theme_font_size_override("font_size", 18)
			solo_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.7))
			players_hbox.add_child(solo_lbl)
		
	vbox.add_child(players_hbox)
	panel.add_child(vbox)
	team_grid.add_child(panel)

func _on_start_pressed():
	print("Starte Phase 2!")
	if NetworkManager.board_layout.is_empty():
		NetworkManager.generate_board_layout()
	
	# Switch to Main Board / Phase 2
	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/MainBoard.tscn")
