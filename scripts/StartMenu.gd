extends Control

@onready var title_label = $CenterContainer/VBox/TitleBox/Title
@onready var start_button = $CenterContainer/VBox/StartButton

var pulse_tween: Tween

var character_scenes = [
	preload("res://scenes/characters/Aaron.tscn"),
	preload("res://scenes/characters/Anna.tscn"),
	preload("res://scenes/characters/Cedric.tscn"),
	preload("res://scenes/characters/Finnja.tscn"),
	preload("res://scenes/characters/Jan.tscn"),
	preload("res://scenes/characters/Janek.tscn"),
	preload("res://scenes/characters/Leonie.tscn"),
	preload("res://scenes/characters/Lia.tscn"),
	preload("res://scenes/characters/Luca.tscn"),
	preload("res://scenes/characters/Marius.tscn"),
	preload("res://scenes/characters/Mikka.tscn"),
	preload("res://scenes/characters/Miles.tscn"),
	preload("res://scenes/characters/Paul.tscn"),
	preload("res://scenes/characters/Simon.tscn")
]
var active_characters = []
var spawn_timer: Timer

func is_in_intro() -> bool:
	if get_parent() != null and get_parent().name == "IntroSequence":
		return true
	if owner != null and owner.name == "IntroSequence":
		return true
	if get_tree() != null and get_tree().current_scene != null and get_tree().current_scene.name == "IntroSequence":
		return true
	return false

func _ready():
	_start_title_animation()

	if is_in_intro():
		# Wenn das Startmenü als Kindknoten in IntroSequence eingebunden ist,
		# darf es weder die Musik neu starten noch Charaktere spawnen.
		# Erst wenn die IntroSequenz endet und StartMenu.tscn als eigenständige Szene geladen wird,
		# wird der normale Startmenü-Ablauf aktiv.
		return

	if GlobalSettingsLayer:
		GlobalSettingsLayer.show_gear_button()

	AudioManager.play_music("intro")
	start_button.pressed.connect(_on_start_pressed)
	_connect_buttons_sfx(self)
	_setup_random_animations()

var available_scenes = []
var last_spawned_scene = null

func _setup_random_animations():
	if is_in_intro():
		return
	spawn_timer = Timer.new()
	spawn_timer.wait_time = randf_range(1.0, 3.0)
	spawn_timer.autostart = true
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(spawn_timer)

func _on_spawn_timer_timeout():
	spawn_timer.wait_time = randf_range(2.0, 6.0)
	
	if available_scenes.is_empty():
		available_scenes = character_scenes.duplicate()
		available_scenes.shuffle()
		# Verhindere, dass der erste aus der neuen Runde derselbe ist wie der letzte aus der alten Runde
		if available_scenes.back() == last_spawned_scene and available_scenes.size() > 1:
			var first_scene = available_scenes.pop_front()
			available_scenes.push_back(first_scene)
			
	var char_scene = available_scenes.pop_back()
	last_spawned_scene = char_scene
	
	if char_scene:
		var char_inst = char_scene.instantiate()
		char_inst.mute_sfx = true
		add_child(char_inst)
		# Bewege den Charakter im Szenenbaum nach oben (vor das Tilemap, hinter das UI)
		move_child(char_inst, 2) 
		
		# Setze Startposition links außerhalb des Bildschirms auf y=960 (Boden-Höhe der Intro)
		char_inst.global_position = Vector2(-150, 960) 
		char_inst.set_physics_process(false)
		
		# Initialisiere Metadaten für Status und Timer
		char_inst.set_meta("run_speed", randf_range(200.0, 450.0))
		char_inst.set_meta("state", "run")
		char_inst.set_meta("action_timer", randf_range(1.0, 3.0)) # Wann die erste Aktion passiert
		
		active_characters.append(char_inst)

func _process(delta):
	if is_in_intro():
		return
	for i in range(active_characters.size() - 1, -1, -1):
		var c = active_characters[i]
		if is_instance_valid(c):
			var state = c.get_meta("state")
			var speed = c.get_meta("run_speed")
			
			if state == "run":
				# Normales Laufen
				c.global_position.x += speed * delta
				
				var timer = c.get_meta("action_timer") - delta
				if timer <= 0:
					# Zufällig entscheiden: Trinken (stehen bleiben) oder Springen
					if randf() > 0.5:
						c.set_meta("state", "drink")
						c.play_drink(false)
						c.play_drip()
						
						var t = create_tween()
						t.tween_interval(randf_range(1.5, 3.0))
						t.finished.connect(func():
							if is_instance_valid(c):
								c.set_meta("state", "run")
								c.is_playing_special = false
								c.animated_sprite.play("run")
								c.set_meta("action_timer", randf_range(2.0, 6.0))
						)
					else:
						c.set_meta("state", "jump")
						c.play_jump(false)
						
						var jump_dur = 0.35
						var t = create_tween()
						t.tween_property(c, "global_position:y", 960 - 150, jump_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
						t.tween_property(c, "global_position:y", 960, jump_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
						t.finished.connect(func():
							if is_instance_valid(c):
								c.set_meta("state", "run")
								c.is_playing_special = false
								c.animated_sprite.play("run")
								c.set_meta("action_timer", randf_range(2.0, 6.0))
						)
				else:
					c.set_meta("action_timer", timer)
					
			elif state == "jump":
				# Während dem Sprung weiter nach vorne bewegen
				c.global_position.x += speed * delta
				
			# (Im Status "drink" ändert sich die X-Position nicht, sie bleiben einfach stehen)
			
			# Wenn sie weit genug rechts sind, löschen
			if c.global_position.x > get_viewport_rect().size.x + 200:
				c.queue_free()
				active_characters.remove_at(i)
		else:
			active_characters.remove_at(i)

func _connect_buttons_sfx(node: Node):
	if node is Button:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func _update_title_pivot():
	if is_instance_valid(title_label):
		if title_label.size.x > 0 and title_label.size.y > 0:
			title_label.pivot_offset = title_label.size / 2.0
		else:
			title_label.pivot_offset = title_label.custom_minimum_size / 2.0

func _start_title_animation():
	if pulse_tween and pulse_tween.is_valid():
		pulse_tween.kill()

	if not title_label.resized.is_connected(_update_title_pivot):
		title_label.resized.connect(_update_title_pivot)
	_update_title_pivot()
	get_tree().process_frame.connect(_update_title_pivot, CONNECT_ONE_SHOT)

	title_label.scale = Vector2.ONE

	# Endlose sanfte Puls-Animation (Pochen) für das Titel-Logo
	pulse_tween = create_tween().set_loops()
	pulse_tween.tween_property(title_label, "scale", Vector2(1.08, 1.08), 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse_tween.tween_property(title_label, "scale", Vector2(1.0, 1.0), 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _on_start_pressed():
	# Wechsle zur neuen Szene für Spieloptionen
	get_tree().change_scene_to_file("res://scenes/GameSetup.tscn")
