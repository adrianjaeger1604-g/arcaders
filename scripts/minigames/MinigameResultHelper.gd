class_name MinigameResultHelper
extends RefCounted

const RISE_DURATION: float = 3.5

# Ermittelt die Teamfarbe für einen Spieler (oder Fallback)
static func get_player_team_color(p_id: int, fallback: Color = Color(0.42, 0.24, 0.82, 1)) -> Color:
	for team in NetworkManager.computed_teams:
		for player in team.get("players", []):
			if player.get("id", -1) == p_id:
				return team.get("color", fallback)
			if NetworkManager.player_sessions.has(p_id) and player.get("name") == NetworkManager.player_sessions[p_id].get("name"):
				return team.get("color", fallback)
	return fallback

# Ermittelt den Asset-Ordnernamen (z.B. "cedric") aus der Idle-Textur
static func get_sprite_base(character_name: String) -> String:
	var tex = NetworkManager.character_textures.get(character_name)
	if tex == null:
		return ""
	var file = tex.resource_path.get_file().get_basename()
	return file.trim_prefix("spr_").get_slice("_idle", 0)

static func load_idle_frames(base: String) -> Array:
	var frames = []
	var n = 1
	while true:
		var path = "res://assets/characters/%s/idle/spr_%s_idle_%d.png" % [base, base, n]
		if not ResourceLoader.exists(path):
			break
		frames.append(load(path))
		n += 1
	return frames

static func load_drink_frames(base: String) -> Array:
	var frames = []
	var n = 1
	while true:
		var path = "res://assets/characters/%s/drink/spr_%s_drink_%d.png" % [base, base, n]
		if not ResourceLoader.exists(path):
			break
		frames.append(load(path))
		n += 1
	return frames

# Lässt das Charakter-Icon hochspringen und danach Drink-Frames abspielen
static func celebrate_winner(char_icon: TextureRect, character_name: String):
	if char_icon == null or not is_instance_valid(char_icon):
		return
		
	var base = get_sprite_base(character_name)
	var drink_frames = load_drink_frames(base)
	if drink_frames.is_empty():
		drink_frames = load_idle_frames(base)
	if drink_frames.is_empty() and char_icon.texture:
		drink_frames = [char_icon.texture]
		
	var jump_path = "res://assets/characters/%s/jump/spr_%s_jump.png" % [base, base]
	if ResourceLoader.exists(jump_path):
		char_icon.texture = load(jump_path)
	
	# Einmal kurz springen (angepasste Sprunghöhe, damit der Charakter im Sichtbereich bleibt)
	var jump = char_icon.create_tween()
	jump.tween_property(char_icon, "position:y", -22.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	jump.tween_property(char_icon, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await jump.finished
	
	if not is_instance_valid(char_icon):
		return
		
	# Danach Drink-Animation in Endlosschleife
	if not drink_frames.is_empty():
		char_icon.texture = drink_frames[0]
	if drink_frames.size() > 1:
		var timer = Timer.new()
		timer.wait_time = 0.5
		timer.autostart = true
		var frame_idx = [0]
		timer.timeout.connect(func():
			if is_instance_valid(char_icon):
				frame_idx[0] = (frame_idx[0] + 1) % drink_frames.size()
				char_icon.texture = drink_frames[frame_idx[0]]
		)
		char_icon.add_child(timer)

# Erstellt ein einheitliches, gestyltes ProgressBar-Widget
static func create_styled_bar(max_val: float, fill_color: Color, bar_size: Vector2 = Vector2(400, 40)) -> Dictionary:
	var bar_container = MarginContainer.new()
	bar_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var bar = ProgressBar.new()
	bar.custom_minimum_size = bar_size
	bar.max_value = max_val
	bar.value = 0.0
	bar.step = 0.0
	bar.show_percentage = false
	
	var style_bg = StyleBoxFlat.new()
	style_bg.bg_color = Color(0.2, 0.2, 0.2, 1)
	style_bg.corner_radius_top_left = 10
	style_bg.corner_radius_top_right = 10
	style_bg.corner_radius_bottom_right = 10
	style_bg.corner_radius_bottom_left = 10
	bar.add_theme_stylebox_override("background", style_bg)
	
	var style_fg = StyleBoxFlat.new()
	style_fg.bg_color = fill_color
	style_fg.corner_radius_top_left = 10
	style_fg.corner_radius_top_right = 10
	style_fg.corner_radius_bottom_right = 10
	style_fg.corner_radius_bottom_left = 10
	bar.add_theme_stylebox_override("fill", style_fg)
	
	bar_container.add_child(bar)
	
	var score_label = Label.new()
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	score_label.add_theme_font_size_override("font_size", 24)
	score_label.add_theme_color_override("font_color", Color.WHITE)
	score_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	score_label.add_theme_constant_override("outline_size", 6)
	bar_container.add_child(score_label)
	
	return {
		"container": bar_container,
		"bar": bar,
		"label": score_label
	}

# Erstellt einen unsichtbaren Spacer mit der gleichen Breite wie die linke Box,
# damit der Fortschrittsbalken exakt in der Bildschirmmitte zentriert ist.
static func create_balancing_spacer(width: float) -> Control:
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(width, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer
