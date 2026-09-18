extends Button

enum State {
	WAITING,
	SUBMITTED,
	REVEALED,
	SELECTED
}

var current_state = State.WAITING

# Referenzen
@onready var name_label = $MarginContainer/OuterVBox/CharAndNameBox/NameLabel
@onready var answer_label = $MarginContainer/OuterVBox/AnswerLabel
@onready var chars_container = $MarginContainer/OuterVBox/CharAndNameBox/CharactersContainer

var raw_answer = ""
var team_color = Color(0.2, 0.8, 0.2, 1) # Default Grün für Allgemeinwissen
var is_active = true # Wird false, wenn die Runde schließt und keine Antwort kam

func _ready():
	_update_visuals()

func setup(display_name: String, characters: Array, t_color: Color = Color(0.2, 0.8, 0.2, 1)):
	name_label.text = display_name
	team_color = t_color
	
	# Load and spawn character sprites
	for char_name in characters:
		var formatted_name = char_name
		if formatted_name == "" or formatted_name == "unknown" or formatted_name == "Cedi":
			formatted_name = "Cedric"
			
		var scene_path = "res://scenes/characters/" + formatted_name + ".tscn"
		if ResourceLoader.exists(scene_path):
			var char_scene = load(scene_path)
			var char_instance = char_scene.instantiate()
			# Finde die AnimatedSprite2D
			var sprite = char_instance.get_node_or_null("AnimatedSprite2D")
			if sprite != null:
				var sprite_dup = sprite.duplicate()
				# Da das Sprite normalerweise zentriert ist, setzen wir es in ein Control
				var char_holder = Control.new()
				char_holder.custom_minimum_size = Vector2(60, 70) # Platz für Sprite
				char_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE # WICHTIG: Klicks nicht abfangen!
				
				sprite_dup.position = Vector2(30, 35) # Zentrieren (angepasst an neues Layout)
				sprite_dup.scale = Vector2(4, 4) # Größer abbilden, wie bei Phase 2
				sprite_dup.play("idle")
				
				char_holder.add_child(sprite_dup)
				chars_container.add_child(char_holder)
			char_instance.free()

func set_answer(answer: String):
	raw_answer = answer
	set_state(State.SUBMITTED)

func set_state(new_state: int):
	current_state = new_state
	_update_visuals()

func _update_visuals():
	# StyleBox erstellen für den Button
	var style = StyleBoxFlat.new()
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_left = 4
	style.border_width_right = 4
	style.border_width_top = 4
	style.border_width_bottom = 4
	
	match current_state:
		State.WAITING:
			style.bg_color = Color(0.1, 0.1, 0.1, 1) # Schwarz
			style.border_color = Color(1, 1, 1, 1) # Weißer Stroke
			name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			answer_label.visible = true
			answer_label.text = "Noch keine Antwort"
			answer_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
			_set_characters_animation("idle")
			
		State.SUBMITTED:
			style.bg_color = Color(1, 1, 1, 1) # Weiß
			style.border_color = Color(0.8, 0.8, 0.8, 1) # Grau/Weißer Stroke
			name_label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
			answer_label.visible = true
			answer_label.text = "Beantwortet!"
			answer_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2, 1)) # Grün (Positiv)
			_set_characters_animation("drink")
			
		State.REVEALED:
			style.bg_color = Color(0.1, 0.1, 0.1, 1) # Schwarz
			style.border_color = Color(1, 1, 1, 1) # Weißer Stroke
			name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			answer_label.visible = true
			
			if raw_answer != "":
				answer_label.text = raw_answer
				answer_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			else:
				is_active = false
				answer_label.text = "Keine Antwort gegeben"
				answer_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
				
				# Ausgrauen, da keine Antwort
				style.bg_color = Color(0.15, 0.15, 0.15, 1)
				style.border_color = Color(0.3, 0.3, 0.3, 1)
				name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
				
			_set_characters_animation("idle")
			
		State.SELECTED:
			style.bg_color = team_color # Grün oder Team-Farbe
			style.border_color = Color(1, 1, 1, 1) # Weißer Stroke
			name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			answer_label.visible = true
			answer_label.text = raw_answer
			answer_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			_set_characters_animation("drink")
			
	# Anwenden auf Button-Zustände (damit Hover nicht stört, setzen wir alles gleich)
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("hover", style)
	add_theme_stylebox_override("pressed", style)
	add_theme_stylebox_override("disabled", style)

func _set_characters_animation(anim_name: String):
	for holder in chars_container.get_children():
		for child in holder.get_children():
			if child.has_method("play"):
				child.play(anim_name)
