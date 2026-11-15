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
@onready var answer_label = $MarginContainer/OuterVBox/AnswerHBox/AnswerLabel
@onready var status_icon = $MarginContainer/OuterVBox/AnswerHBox/StatusIcon
@onready var chars_container = $MarginContainer/OuterVBox/CharAndNameBox/CharactersContainer

var raw_answer = ""
var submitted_text = "Eingereicht!"
var current_icon_name = ""
var team_color = Color(0.2, 0.8, 0.2, 1) # Default Grün für Allgemeinwissen
var is_active = true # Wird false, wenn die Runde schließt und keine Antwort kam

func _ensure_references():
	if name_label == null:
		name_label = get_node_or_null("MarginContainer/OuterVBox/CharAndNameBox/NameLabel")
	if answer_label == null:
		answer_label = get_node_or_null("MarginContainer/OuterVBox/AnswerHBox/AnswerLabel")
		if answer_label == null:
			answer_label = get_node_or_null("MarginContainer/OuterVBox/AnswerLabel")
	if status_icon == null:
		status_icon = get_node_or_null("MarginContainer/OuterVBox/AnswerHBox/StatusIcon")
	if chars_container == null:
		chars_container = get_node_or_null("MarginContainer/OuterVBox/CharAndNameBox/CharactersContainer")

func _ready():
	_ensure_references()
	_update_visuals()

func setup(display_name: String, characters: Array, t_color: Color = Color(0.2, 0.8, 0.2, 1)):
	_ensure_references()
	if name_label:
		name_label.text = display_name
	team_color = t_color
	raw_answer = ""
	submitted_text = "Eingereicht!"
	current_state = State.WAITING
	is_active = true
	
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
				char_holder.custom_minimum_size = Vector2(60, 64) # Platz für Sprite
				char_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				char_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE # WICHTIG: Klicks nicht abfangen!
				
				sprite_dup.position = Vector2(30, 32) # Zentrieren (angepasst an kompaktes Layout)
				sprite_dup.scale = Vector2(4, 4) # Größer abbilden, wie bei Phase 2
				sprite_dup.play("idle")
				
				char_holder.add_child(sprite_dup)
				if chars_container:
					chars_container.add_child(char_holder)
			char_instance.free()
			
	_update_visuals()

func set_answer(answer: String):
	raw_answer = answer
	submitted_text = "Eingereicht!"
	current_icon_name = ""
	set_state(State.SUBMITTED)

func set_custom_answer(answer: String, new_state: int = -1, icon: String = ""):
	raw_answer = answer
	if new_state == State.SUBMITTED:
		submitted_text = answer
	current_icon_name = icon
	if new_state != -1:
		current_state = new_state
	_update_visuals()

func set_state(new_state: int):
	current_state = new_state
	_update_visuals()

func _update_visuals():
	_ensure_references()
	if name_label == null or answer_label == null:
		return
		
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
	
	# Icon ermitteln
	var ic_name = current_icon_name
	var ic_color = Color.WHITE
	
	match current_state:
		State.WAITING:
			name_label.remove_theme_constant_override("outline_size")
			name_label.remove_theme_color_override("font_outline_color")
			answer_label.remove_theme_constant_override("outline_size")
			answer_label.remove_theme_color_override("font_outline_color")
			
			style.bg_color = Color(0.1, 0.1, 0.1, 1) # Schwarz
			style.border_color = team_color # Team-Stroke
			style.border_width_left = 4
			style.border_width_right = 4
			style.border_width_top = 4
			style.border_width_bottom = 4
			style.shadow_size = 0
			
			name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			answer_label.visible = true
			answer_label.text = raw_answer if raw_answer != "" else "Tippt gerade..."
			answer_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
			answer_label.custom_minimum_size = Vector2(160, 0)
			answer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			answer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ic_name = ""
			_set_characters_animation("idle")
			
		State.SUBMITTED:
			style.bg_color = Color(1, 1, 1, 1) # Weiß
			style.border_color = team_color # Team-Stroke
			style.border_width_left = 4
			style.border_width_right = 4
			style.border_width_top = 4
			style.border_width_bottom = 4
			style.shadow_size = 0
			
			# Name bekommt KEINEN Stroke (Outline), da der Text selbst schwarz auf weiß ist!
			name_label.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08, 1))
			name_label.add_theme_constant_override("outline_size", 0)
			name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0))
			
			answer_label.visible = true
			# Antwort noch NICHT anzeigen! Erst nach Schließen der Runde!
			answer_label.text = "Eingereicht!"
			answer_label.add_theme_color_override("font_color", Color(0.08, 0.55, 0.18, 1)) # Sauberes Grün
			answer_label.add_theme_constant_override("outline_size", 0)
			answer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0))
			
			# Einfach nur "Eingereicht!" zentriert anzeigen, kein Haken-Icon
			answer_label.custom_minimum_size = Vector2(160, 0)
			answer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			answer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			
			ic_name = ""
			_set_characters_animation("drink")
			
		State.REVEALED:
			name_label.remove_theme_constant_override("outline_size")
			name_label.remove_theme_color_override("font_outline_color")
			answer_label.remove_theme_constant_override("outline_size")
			answer_label.remove_theme_color_override("font_outline_color")
			
			style.bg_color = Color(0.1, 0.1, 0.1, 1) # Schwarz
			style.border_color = team_color # Team-Stroke
			style.border_width_left = 4
			style.border_width_right = 4
			style.border_width_top = 4
			style.border_width_bottom = 4
			style.shadow_size = 0
			
			name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			answer_label.visible = true
			answer_label.custom_minimum_size = Vector2(160, 0)
			answer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			answer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ic_name = "" # Haken-Icon weg beim Verteilen!
			
			if raw_answer != "":
				answer_label.text = raw_answer
				answer_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			else:
				is_active = false
				answer_label.text = "Keine Antwort"
				answer_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
				
				# Ausgrauen, da keine Antwort
				style.bg_color = Color(0.15, 0.15, 0.15, 1)
				style.border_color = Color(0.3, 0.3, 0.3, 1)
				name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
				
			_set_characters_animation("idle")
			
		State.SELECTED:
			name_label.remove_theme_constant_override("outline_size")
			name_label.remove_theme_color_override("font_outline_color")
			answer_label.remove_theme_constant_override("outline_size")
			answer_label.remove_theme_color_override("font_outline_color")
			
			# Fill-Farbe ist dieselbe wie die Teamfarbe (Stroke), kein Drop-Shadow
			style.bg_color = team_color
			style.border_color = team_color
			style.border_width_left = 4
			style.border_width_right = 4
			style.border_width_top = 4
			style.border_width_bottom = 4
			style.shadow_size = 0
			style.shadow_color = Color(0, 0, 0, 0)
			
			name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			answer_label.visible = true
			answer_label.text = raw_answer
			answer_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			answer_label.custom_minimum_size = Vector2(160, 0)
			answer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			answer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ic_name = "" # Kein Haken-Icon beim Verteilen!
			_set_characters_animation("drink")
			
	# Pixel-Icon anwenden
	if status_icon != null:
		if ic_name != "":
			status_icon.visible = true
			status_icon.texture = PixelIcon.get_icon_texture(ic_name)
			status_icon.modulate = ic_color
		else:
			status_icon.visible = false
			
	# Anwenden auf Button-Zustände (damit Hover nicht stört, setzen wir alles gleich)
			
	# Anwenden auf Button-Zustände (damit Hover nicht stört, setzen wir alles gleich)
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("hover", style)
	add_theme_stylebox_override("pressed", style)
	add_theme_stylebox_override("disabled", style)

func _set_characters_animation(anim_name: String):
	_ensure_references()
	if chars_container == null:
		return
	for holder in chars_container.get_children():
		for child in holder.get_children():
			if child.has_method("play"):
				child.play(anim_name)
