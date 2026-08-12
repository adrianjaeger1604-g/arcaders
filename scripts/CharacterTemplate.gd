extends CharacterBody2D

@onready var animated_sprite = $AnimatedSprite2D
@onready var drip_sprite = $DripSprite

const SPEED = 200.0
const JUMP_VELOCITY = -400.0
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

# Schalter: Cutscene oder spielbar?
@export var is_in_cutscene: bool = true
@export var character_name: String = "Cedric"

var last_position: Vector2
var is_getting_piped: bool = false
var pipe_target_y: float = 0.0

func _ready():
	last_position = global_position
	animated_sprite.play("idle")
	drip_sprite.visible = false

func _process(_delta):
	if is_in_cutscene:
		var distance_moved = global_position.distance_to(last_position)
		var velocity_this_frame = global_position - last_position
		
		last_position = global_position
		
		if is_playing_special:
			return
		
		# Only auto-animate if we are in resting/moving states. 
		var can_auto_animate = animated_sprite.animation in ["idle", "run"]
		
		if distance_moved > 0.5:
			if can_auto_animate and animated_sprite.animation == "idle":
				animated_sprite.play("run")
			
			if velocity_this_frame.x < 0:
				animated_sprite.flip_h = true
				drip_sprite.position.x = -5
			elif velocity_this_frame.x > 0:
				animated_sprite.flip_h = false
				drip_sprite.position.x = 5
		else:
			if can_auto_animate and animated_sprite.animation == "run":
				animated_sprite.play("idle")

func lock_animation(anim_name: String, duration: float = 0.0):
	animated_sprite.play(anim_name)
	if duration > 0:
		await get_tree().create_timer(duration).timeout
		animated_sprite.play("idle")

func _physics_process(delta):
	# Wenn wir gerade in die Röhre gezogen werden
	if is_getting_piped:
		# Bewege stetig nach unten
		global_position.y += 100 * delta # Konstante Geschwindigkeit
		
		# Wenn tief genug in der Röhre, unsichtbar machen und stoppen
		if global_position.y >= pipe_target_y:
			visible = false
			is_getting_piped = false
			# Hier könnte man auch queue_free() aufrufen, wenn der Char nicht mehr gebraucht wird
		return

	# Spiel-Logik (Jump and Run)
	if is_in_cutscene:
		if not is_on_floor():
			velocity.y += gravity * delta
			# Automatischer Jump-Sprite in der Luft (außer bei speziellen Cutscene-Overrides)
			if not is_playing_special or animated_sprite.animation in ["surprised", "jump", "drink"]:
				animated_sprite.play("jump")
				drip_sprite.visible = false
		else:
			# Only reset vertical velocity if we aren't jumping upwards
			if velocity.y >= 0:
				velocity.y = 0
				velocity.x = move_toward(velocity.x, 0, SPEED * delta * 5.0)
				
			# Wenn er wieder auf dem Boden ankommt und noch den "Jump" Sprite hat, zurücksetzen
			if velocity.y >= 0 and animated_sprite.animation == "jump":
				animated_sprite.play("idle")
				is_playing_special = false
				
				# Wenn er auf der Röhre gelandet ist, sauge ihn ein!
				# Wir checken, ob wir gerade auf der Röhre gelandet sind, indem wir ein Flag einführen oder
				# einfach checken, ob wir sehr nah an einer Röhre sind.
				# Einfacher ist es, das Einsaugen direkt als Funktion aus dem AnimationPlayer oder beim Landen zu triggern.
				
		move_and_slide()
		return
		
	if not is_on_floor():
		velocity.y += gravity * delta
		animated_sprite.play("jump")

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		AudioManager.play_sfx("jump")

	var direction = Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * SPEED
		animated_sprite.flip_h = direction < 0
		drip_sprite.position.x = -5 if direction < 0 else 5
		if is_on_floor():
			animated_sprite.play("run")
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		if is_on_floor():
			animated_sprite.play("idle")

	move_and_slide()

# --- Funktionen für den AnimationPlayer in der Intro-Szene ---
var is_playing_special: bool = false

func play_drink():
	is_playing_special = true
	animated_sprite.play("drink")
	AudioManager.play_sfx("drink")

func play_drip():
	drip_sprite.visible = true
	drip_sprite.play("drip")
	
func _on_drip_animation_finished():
	drip_sprite.visible = false

func play_surprised():
	is_playing_special = true
	animated_sprite.play("surprised")

func play_jump():
	is_playing_special = true
	animated_sprite.play("jump")
	AudioManager.play_sfx("jump")

func face_left():
	animated_sprite.flip_h = true
	drip_sprite.position.x = -5

func face_right():
	animated_sprite.flip_h = false
	drip_sprite.position.x = 5

func jump_on_pipe(y_multiplier: float = 1.6, x_multiplier: float = 0.4):
	is_playing_special = true
	# Gib dem Charakter einen anpassbaren physikalischen Impuls nach oben
	velocity.y = JUMP_VELOCITY * y_multiplier
	# Schiebe ihn leicht nach rechts auf die Röhre
	velocity.x = SPEED * x_multiplier
	AudioManager.play_sfx("jump")

func jump_to_target(target_global_pos: Vector2, arc_height: float = 150.0):
	is_playing_special = true
	animated_sprite.play("jump")
	drip_sprite.visible = false
	AudioManager.play_sfx("jump")
	
	var displacement_x = target_global_pos.x - global_position.x
	# Höchster Punkt des Sprungs: min(start_y, ziel_y) - arc_height
	var peak_y = min(global_position.y, target_global_pos.y) - arc_height
	
	# Höhenunterschiede zum Peak (muss positiv sein)
	var h1 = max(0.0, global_position.y - peak_y)
	var h2 = max(0.0, target_global_pos.y - peak_y)
	
	# Berechne die benötigten Zeiten für Aufstieg (t1) und Abstieg (t2)
	var t1 = sqrt(2.0 * h1 / gravity)
	var t2 = sqrt(2.0 * h2 / gravity)
	var total_time = t1 + t2
	
	if total_time > 0:
		velocity.x = displacement_x / total_time
		velocity.y = -sqrt(2.0 * gravity * h1)
	else:
		velocity.y = JUMP_VELOCITY
		velocity.x = 0

func jump_into_pipe(pipe_name: String = "Pipe", arc_height: float = 120.0):
	var pipe = get_parent().find_child(pipe_name)
	if pipe:
		# Die Röhre ist zentriert, Skalierung ist oft 4x, Sprite-Größe 32x32 -> 128 Höhe
		# Das obere Ende ist also ca. -64 von der Mitte der Röhre.
		# Damit Cedric nicht schon vorher mit den Füßen aufkommt (seine Füße sind ca. 64 Pixel unter seiner Position),
		# zielen wir mit seiner base position auf -128.
		var target_pos = pipe.global_position + Vector2(0, -128)
		jump_to_target(target_pos, arc_height)
	else:
		# Fallback falls keine Röhre gefunden wurde
		jump_on_pipe(1.3, 0.6)

func enter_pipe(target_depth_y: float = 180.0):
	# Wir warten ganz kurz ab, bis Cedric auch wirklich physisch wieder auf dem Boden angekommen ist.
	# Fallback: Maximal 1 Sekunde warten, falls is_on_floor() fehlschlägt.
	var timeout = 0.0
	while not is_on_floor() and timeout < 1.0:
		await get_tree().process_frame
		timeout += get_process_delta_time()
		
	is_getting_piped = true
	is_playing_special = true
	# Spiele Idle-Animation, stoppe sie aber sofort (frame 0 bleibt stehen)
	animated_sprite.play("idle") 
	animated_sprite.stop()
	
	# Die Pipe selbst wurde auf z_index = 1 gesetzt.
	# Cedric bleibt auf z_index = 0, dadurch rutscht er in die Röhre (dahinter), aber bleibt vor dem blauen Hintergrund!
	
	# Setze das Ziel, wie tief er fallen soll, bevor er unsichtbar wird
	pipe_target_y = global_position.y + target_depth_y
