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
	AudioManager.play_music("intro")
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
	
	# Mapping der Charaktere zu Icons (Eingestellt in CharacterSelect)
	var char_icons = {
		"red": "🔴",
		"blue": "🔵", 
		"green": "🟢", 
		"yellow": "🟡"
	}
	
	# Lösche alte Platzhalter
	for child in team_grid.get_children():
		child.queue_free()
	
	for team in computed_teams:
		var player1 = team["players"][0]
		var player2 = null
		if team["players"].size() > 1:
			player2 = team["players"][1]
			
		_create_team_ui(team["name"], player1, player2, team["color"], char_icons)

func _create_team_ui(team_name: String, p1: Dictionary, p2, bg_color: Color, char_icons: Dictionary):
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
	
	var players_hbox = HBoxContainer.new()
	players_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	players_hbox.add_theme_constant_override("separation", 40)
	
	# P1 Name + Icon
	var p1_box = VBoxContainer.new()
	p1_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var t1 = TextureRect.new()
	t1.custom_minimum_size = Vector2(96, 96)
	t1.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t1.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t1.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var char1 = p1.get("character", "")
	if NetworkManager.character_textures.has(char1):
		t1.texture = NetworkManager.character_textures[char1]
	
	var l1 = Label.new()
	l1.text = p1.get("name", "Unbekannt")
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l1.add_theme_font_size_override("font_size", 24)
	p1_box.add_child(t1)
	p1_box.add_child(l1)
	players_hbox.add_child(p1_box)
	
	# P2 falls vorhanden
	if p2 != null:
		var p2_box = VBoxContainer.new()
		p2_box.alignment = BoxContainer.ALIGNMENT_CENTER
		var t2 = TextureRect.new()
		t2.custom_minimum_size = Vector2(96, 96)
		t2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t2.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var char2 = p2.get("character", "")
		if NetworkManager.character_textures.has(char2):
			t2.texture = NetworkManager.character_textures[char2]
		
		var l2 = Label.new()
		l2.text = p2.get("name", "Unbekannt")
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l2.add_theme_font_size_override("font_size", 24)
		p2_box.add_child(t2)
		p2_box.add_child(l2)
		players_hbox.add_child(p2_box)
	else:
		var empty_lbl = Label.new()
		empty_lbl.text = "(Spielt alleine)"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 20)
		empty_lbl.add_theme_color_override("font_color", Color(0.8,0.8,0.8,1))
		players_hbox.add_child(empty_lbl)
		
	vbox.add_child(players_hbox)
	panel.add_child(vbox)
	team_grid.add_child(panel)

func _on_start_pressed():
	print("Starte Phase 2!")
	if NetworkManager.board_layout.is_empty():
		NetworkManager.generate_board_layout()
	
	# Switch to Main Board / Phase 2
	get_tree().change_scene_to_file("res://scenes/MainBoard.tscn")
