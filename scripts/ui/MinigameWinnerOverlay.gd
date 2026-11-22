class_name MinigameWinnerOverlay
extends ColorRect

signal continue_pressed

@onready var center_container = $CenterContainer
@onready var modal_panel = $CenterContainer/ModalPanel
@onready var title_label = $CenterContainer/ModalPanel/Margin/VBox/TitleHBox/TitleLabel
@onready var subtitle_label = $CenterContainer/ModalPanel/Margin/VBox/SubtitleLabel
@onready var characters_hbox = $CenterContainer/ModalPanel/Margin/VBox/CharactersHBox
@onready var btn_continue = $CenterContainer/ModalPanel/Margin/VBox/BtnContinue

@export var auto_navigate_to_main_board: bool = true

func _ready():
	if btn_continue:
		btn_continue.pressed.connect(_on_continue_pressed)

func setup_winner(winning_team: Variant, points: int = 2, custom_subtitle: String = ""):
	AudioManager.play_sfx("confetti_pop")
	
	for child in characters_hbox.get_children():
		child.queue_free()
		
	if winning_team == null or (typeof(winning_team) == TYPE_DICTIONARY and winning_team.is_empty()):
		title_label.text = "UNENTSCHIEDEN!"
		title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		subtitle_label.text = custom_subtitle if custom_subtitle != "" else "Kein Team konnte den Sieg für sich entscheiden!"
		_animate_in()
		return
		
	var team_name = winning_team.get("name", "Team")
	var team_color = winning_team.get("color", Color(1.0, 0.85, 0.2))
	
	title_label.text = "%s gewinnt!" % team_name
	title_label.add_theme_color_override("font_color", team_color)
	
	if custom_subtitle != "":
		subtitle_label.text = custom_subtitle
	else:
		subtitle_label.text = "+%d Punkte für das Spielbrett" % points
		
	# Spieler des Teams ermitteln
	var players = winning_team.get("players", [])
	if players.is_empty():
		for t in NetworkManager.computed_teams:
			if t.get("name") == team_name or t.get("color") == team_color:
				players = t.get("players", [])
				break
				
	# Für jeden Spieler eine animierte Charakter-Box erstellen
	for p in players:
		var p_name = p.get("name", "Spieler")
		var char_name = p.get("character", "Cedric")
		if char_name == "" or char_name == "unknown":
			char_name = "Cedric"
		
		AudioManager.play_character_sfx(char_name, "win")
		
		var p_box = VBoxContainer.new()
		p_box.alignment = BoxContainer.ALIGNMENT_CENTER
		p_box.add_theme_constant_override("separation", 10)
		p_box.custom_minimum_size = Vector2(110, 0)
		
		var holder = Control.new()
		holder.custom_minimum_size = Vector2(96, 96)
		holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		
		var char_icon = TextureRect.new()
		char_icon.custom_minimum_size = Vector2(96, 96)
		char_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		char_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		char_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		if NetworkManager.character_textures.has(char_name):
			char_icon.texture = NetworkManager.character_textures[char_name]
		elif NetworkManager.character_textures.has("Cedi"):
			char_icon.texture = NetworkManager.character_textures["Cedi"]
			
		holder.add_child(char_icon)
		p_box.add_child(holder)
		
		var lbl_name = Label.new()
		lbl_name.text = p_name
		lbl_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl_name.add_theme_font_size_override("font_size", 22)
		lbl_name.add_theme_color_override("font_color", Color.WHITE)
		lbl_name.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.06, 0.96))
		lbl_name.add_theme_constant_override("outline_size", 8)
		p_box.add_child(lbl_name)
		
		characters_hbox.add_child(p_box)
		
		# Erst kurz springen, dann Trink-Animation in Endlosschleife!
		MinigameResultHelper.celebrate_winner(char_icon, char_name)
		
	# Handys informieren
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting",
		"title": "SPIEL BEENDET",
		"message": "Spiel beendet! %s gewinnt!" % team_name
	})
	
	_animate_in()

func _animate_in():
	visible = true
	modulate.a = 0.0
	modal_panel.scale = Vector2(0.85, 0.85)
	modal_panel.pivot_offset = modal_panel.size * 0.5
	
	var tw = create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.25)
	tw.tween_property(modal_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_continue_pressed():
	AudioManager.play_sfx("button_press")
	continue_pressed.emit()
	if auto_navigate_to_main_board:
		AudioManager.stop_music()
		NetworkManager.is_replaying_minigame = false
		NetworkManager.broadcast({
			"type": "state_change",
			"state": "waiting",
			"title": "SPIELBRETT",
			"message": "Zurück auf dem Spielbrett! Bitte auf den Hauptbildschirm schauen."
		})
		var tree = get_tree()
		if tree:
			tree.change_scene_to_file("res://scenes/MainBoard.tscn")
