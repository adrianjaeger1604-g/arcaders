extends Control

@onready var player_grid = $CenterContainer/VBoxContainer/PlayerGrid
@onready var next_button = $CenterContainer/VBoxContainer/GameButton

func _ready():
	AudioManager.play_music("intro")
	NetworkManager.character_selected.connect(_on_character_selected)
	next_button.pressed.connect(_on_next_pressed)
	
	# Sende allen Handys den Befehl, in die Charakter-Auswahl zu wechseln
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "character_select"
	})
	
	# Zeige Spieler an, die beriets in der Lobby waren
	for p_id in NetworkManager.player_sessions.keys():
		var p_name = NetworkManager.player_sessions[p_id]["name"]
		var chara = NetworkManager.player_sessions[p_id].get("character", "")
		_add_or_update_player_ui(p_id, p_name, chara)
		
	_connect_buttons_sfx(self)

func _connect_buttons_sfx(node: Node):
	if node is Button:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func _on_character_selected(player_id, character):
	if NetworkManager.player_sessions.has(player_id):
		var p_name = NetworkManager.player_sessions[player_id]["name"]
		_add_or_update_player_ui(player_id, p_name, character)

func _add_or_update_player_ui(p_id, p_name, character):
	var node_name = "PlayerRow_" + str(p_id)
	var hbox = player_grid.get_node_or_null(node_name)
	
	if hbox == null:
		hbox = VBoxContainer.new()
		hbox.name = node_name
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_theme_constant_override("separation", 5)
		hbox.custom_minimum_size = Vector2(200, 0)
		
		var tex_rect = TextureRect.new()
		tex_rect.name = "CharTexture"
		tex_rect.custom_minimum_size = Vector2(128, 128)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		# Wichtig für Pixel Art in Godot:
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		
		var label = Label.new()
		label.name = "NameLabel"
		label.custom_minimum_size = Vector2(200, 0)
		label.add_theme_font_size_override("font_size", 32)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		
		hbox.add_child(tex_rect)
		hbox.add_child(label)
		player_grid.add_child(hbox)
		
	var label = hbox.get_node("NameLabel")
	var tex_rect = hbox.get_node("CharTexture")
	
	var question_mark_tex = preload("res://assets/ui/shared/questionmark_box.png")
	var rotating_shadow_mat = preload("res://resources/rotating_shadow_mat.tres")
	if character == "":
		label.text = p_name
		tex_rect.texture = question_mark_tex
		tex_rect.material = null
	else:
		label.text = p_name
		tex_rect.material = rotating_shadow_mat
		# Aus NetworkManager laden
		if NetworkManager.character_textures.has(character):
			tex_rect.texture = NetworkManager.character_textures[character]
		else:
			tex_rect.texture = null

func _on_next_pressed():
	print("Lobby Auswahl beendet. Wechsle zum Quiz...")
	get_tree().change_scene_to_file("res://scenes/Qualifikationsquiz.tscn")
