extends Button

var original_scale = Vector2.ONE
var hover_scale = Vector2(1.05, 1.05)

func _ready():
	# Pivot in die Mitte setzen für sauberes Skalieren!
	pivot_offset = custom_minimum_size / 2.0
	original_scale = scale
	
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)
	focus_entered.connect(_on_hover)
	focus_exited.connect(_on_unhover)

func _on_hover():
	if not disabled:
		var tween = create_tween()
		tween.tween_property(self, "scale", hover_scale, 0.1)

func _on_unhover():
	var tween = create_tween()
	tween.tween_property(self, "scale", original_scale, 0.1)
