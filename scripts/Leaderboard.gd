extends Control

@onready var player_list = $CenterContainer/VBoxContainer/PlayerList
@onready var next_phase_btn = $CenterContainer/VBoxContainer/NextPhaseButton

var max_score_possible = 10 # This could be dynamically calculated, but let's assume a reasonable max for UI scaling. We can adjust it based on max actual score.

func _ready():
	AudioManager.play_music("intro")
	next_phase_btn.pressed.connect(_on_next_phase_pressed)
	_connect_buttons_sfx(self)
	
	# Determine the max score among all players to scale the progress bars nicely
	var actual_max_score = 1
	for p_id in NetworkManager.player_sessions:
		var score = NetworkManager.player_sessions[p_id].get("score", 0)
		if score > actual_max_score:
			actual_max_score = score
			
	max_score_possible = max(10, actual_max_score) # at least 10 for scale
	
	_populate_leaderboard()

func _connect_buttons_sfx(node: Node):
	if node is Button:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func _populate_leaderboard():
	# Clean up any existing placeholders
	for child in player_list.get_children():
		child.queue_free()
		
	# Sort players by score descending
	var players = []
	for p_id in NetworkManager.player_sessions:
		players.append(NetworkManager.player_sessions[p_id])
		
	players.sort_custom(func(a, b): return a.get("score", 0) > b.get("score", 0))
	
	var i = 0
	for p_data in players:
		_create_player_bar(p_data, i)
		i += 1

func _create_player_bar(p_data: Dictionary, index: int):
	var p_name = p_data.get("name", "Unbekannt")
	var target_score = p_data.get("score", 0)
	
	# Create a container for the row
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	
	# Spacer (Left Invisible Element to keep bar centered)
	var spacer_left = Control.new()
	spacer_left.custom_minimum_size = Vector2(0, 0) # Flexible spacer
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer_left)
	
	# Left Content (Name + Character)
	var left_box = HBoxContainer.new()
	left_box.alignment = BoxContainer.ALIGNMENT_END
	left_box.custom_minimum_size = Vector2(350, 0)
	left_box.add_theme_constant_override("separation", 15)
	
	# Trophy
	var trophy_label = Label.new()
	trophy_label.text = "🏆" if index == 0 else ""
	trophy_label.add_theme_font_size_override("font_size", 32)
	trophy_label.custom_minimum_size = Vector2(40, 0)
	trophy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if index == 0:
		trophy_label.modulate.a = 0.0
	left_box.add_child(trophy_label)
	
	# Character + Name Box
	var char_name_vbox = VBoxContainer.new()
	char_name_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	# Character Icon
	var char_icon = TextureRect.new()
	char_icon.custom_minimum_size = Vector2(64, 64)
	char_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	char_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	char_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var character_name = p_data.get("character", "")
	if NetworkManager.character_textures.has(character_name):
		char_icon.texture = NetworkManager.character_textures[character_name]
	char_name_vbox.add_child(char_icon)
	
	# Name Label
	var name_label = Label.new()
	name_label.text = p_name
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_name_vbox.add_child(name_label)
	
	left_box.add_child(char_name_vbox)
	
	row.add_child(left_box)
	
	# Progress Bar Container
	var bar_container = MarginContainer.new()
	bar_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	# Progress Bar
	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(450, 40)
	bar.max_value = max_score_possible
	bar.value = 0 # Start at 0 for animation
	bar.step = 1.0 # Or 0.1 for smoother animation, though scores are integers
	bar.show_percentage = false # We'll show the actual points instead
	
	# Style the bar nicely
	var style_bg = StyleBoxFlat.new()
	style_bg.bg_color = Color(0.2, 0.2, 0.2, 1)
	style_bg.corner_radius_top_left = 10
	style_bg.corner_radius_top_right = 10
	style_bg.corner_radius_bottom_right = 10
	style_bg.corner_radius_bottom_left = 10
	bar.add_theme_stylebox_override("background", style_bg)
	
	var style_fg = StyleBoxFlat.new()
	# Different colors based on rank could be cool!
	if index == 0:
		style_fg.bg_color = Color(1.0, 0.84, 0.0, 1) # Gold
	elif index == 1:
		style_fg.bg_color = Color(0.75, 0.75, 0.75, 1) # Silver
	elif index == 2:
		style_fg.bg_color = Color(0.8, 0.5, 0.2, 1) # Bronze
	else:
		style_fg.bg_color = Color(0.2, 0.6, 1.0, 1) # Blue
		
	style_fg.corner_radius_top_left = 10
	style_fg.corner_radius_top_right = 10
	style_fg.corner_radius_bottom_right = 10
	style_fg.corner_radius_bottom_left = 10
	bar.add_theme_stylebox_override("fill", style_fg)
	
	bar_container.add_child(bar)
	
	# Add a label OVER the progress bar to show the exact number
	var score_label = Label.new()
	score_label.text = "0 / " + str(max_score_possible)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_label.set_anchors_preset(Control.PRESET_FULL_RECT) # Centers inside the MarginContainer
	score_label.add_theme_font_size_override("font_size", 24)
	bar_container.add_child(score_label)
	
	row.add_child(bar_container)
	
	# Spacer (Right Invisible Element to keep bar centered)
	var spacer_right = Control.new()
	spacer_right.custom_minimum_size = Vector2(350, 0) # Same size as left content to center bar
	row.add_child(spacer_right)
	
	player_list.add_child(row)
	
	# Animate using Tween
	var tween = create_tween()
	# Delay animation slightly based on rank for a cool effect
	tween.tween_interval(0.2 * index) 
	tween.tween_property(bar, "value", target_score, 1.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# We also want to animate the text counting up
	var int_tween = create_tween()
	int_tween.tween_interval(0.2 * index)
	# Custom method to update the label text
	int_tween.tween_method(func(val: float): score_label.text = str(int(val)) + " Points", 0.0, float(target_score), 1.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Pokal am Ende der Animation einblenden
	if index == 0:
		var trophy_tween = create_tween()
		trophy_tween.tween_interval((0.2 * index) + 1.6)
		trophy_tween.tween_property(trophy_label, "modulate:a", 1.0, 0.5)


func _on_next_phase_pressed():
	print("Proceeding to next phase...")
	# Handys in Warte-Screen schicken
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})
	# Transition to Team Display
	get_tree().change_scene_to_file("res://scenes/TeamDisplay.tscn")
