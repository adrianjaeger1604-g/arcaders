extends StaticBody2D

@onready var sprite: Sprite2D = $Sprite2D

var _pipe_shader: Shader = preload("res://resources/pipe_color.gdshader")
var _pending_color: Variant = null
var _pending_bonus_points: int = 0
var _bonus_label: Label = null

func _ready():
	if sprite == null:
		sprite = get_node_or_null("Sprite2D")
	if _pending_color != null:
		set_team_color(_pending_color)
	if _pending_bonus_points > 0:
		_apply_bonus_points(_pending_bonus_points)

func set_team_color(color: Color):
	_pending_color = color
	if sprite == null:
		sprite = get_node_or_null("Sprite2D")
	if sprite:
		var mat = ShaderMaterial.new()
		mat.shader = _pipe_shader
		mat.set_shader_parameter("team_color", color)
		sprite.material = mat

func set_bonus_points(points: int):
	_pending_bonus_points = points
	if is_inside_tree():
		_apply_bonus_points(points)

func _apply_bonus_points(points: int):
	if points <= 0:
		if _bonus_label and is_instance_valid(_bonus_label):
			_bonus_label.visible = false
		return
		
	if _bonus_label == null or not is_instance_valid(_bonus_label):
		_bonus_label = Label.new()
		_bonus_label.name = "BonusPointsLabel"
		_bonus_label.top_level = true
		_bonus_label.z_index = 2 # Direkt vor der Röhre (z_index 1)
		_bonus_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_bonus_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_bonus_label.custom_minimum_size = Vector2(128, 48)
		_bonus_label.size = Vector2(128, 48)
		# Gleiches Styling wie auf den Minigame-Karten des MainBoards:
		_bonus_label.add_theme_font_size_override("font_size", 48)
		_bonus_label.add_theme_color_override("font_color", Color(1, 1, 1, 1)) # Weiß
		_bonus_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1)) # Schwarze Kontur
		_bonus_label.add_theme_constant_override("outline_size", 8)
		add_child(_bonus_label)
		
	_bonus_label.text = "+" + str(points)
	# Positioniere etwas höher mittig auf dem sichtbaren Röhrenkörper
	_bonus_label.global_position = global_position + Vector2(-64, -56)
	_bonus_label.visible = true
