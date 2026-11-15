extends Node2D

@onready var animation_player = $AnimationPlayer
@onready var camera = $Camera2D

@onready var skip_layer = $SkipLayer
@onready var skip_container = $SkipLayer/SkipContainer
@onready var skip_button = $SkipLayer/SkipContainer/SkipButton
@onready var skip_label = $SkipLayer/SkipContainer/SkipButton/HBox/SkipLabel
@onready var skip_chevron = $SkipLayer/SkipContainer/SkipButton/HBox/ChevronIcon

var shake_strength: float = 0.0
var shake_fade: float = 5.0
var rng = RandomNumberGenerator.new()

var skip_fade_tween: Tween
var is_mouse_hovering_skip: bool = false
var hide_timer: float = 0.0
const HIDE_TIMEOUT: float = 2.5
var is_skipped: bool = false

func _ready():
	rng.randomize()
	if GlobalSettingsLayer:
		GlobalSettingsLayer.hide_gear_button()
	# Startet intro_music bei 2:37 (157.0s)
	AudioManager.play_music("intro", 0.5, 157.0, 0.0)
	# Intro-Animation sofort starten
	animation_player.play("intro")
	
	# Skip UI Setup (initial transparent)
	if skip_button:
		skip_button.focus_mode = Control.FOCUS_NONE
	if skip_chevron and FileAccess.file_exists("res://assets/ui/shared/pixel_chevron_right.svg"):
		var svg_str = FileAccess.get_file_as_string("res://assets/ui/shared/pixel_chevron_right.svg")
		var img = Image.new()
		if img.load_svg_from_string(svg_str, 2.0) == OK:
			skip_chevron.texture = ImageTexture.create_from_image(img)
	skip_container.modulate.a = 0.0
	skip_button.pressed.connect(_on_skip_pressed)
	skip_button.mouse_entered.connect(_on_skip_mouse_entered)
	skip_button.mouse_exited.connect(_on_skip_mouse_exited)

func _input(event):
	if is_skipped:
		return
	if event is InputEventMouseMotion:
		_show_skip_prompt()
	elif event is InputEventKey and event.is_pressed():
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_on_skip_pressed()

func _process(delta):
	if shake_strength > 0:
		shake_strength = lerpf(shake_strength, 0, shake_fade * delta)
		camera.offset = Vector2(rng.randf_range(-shake_strength, shake_strength), rng.randf_range(-shake_strength, shake_strength))
		
	if hide_timer > 0.0 and not is_mouse_hovering_skip:
		hide_timer -= delta
		if hide_timer <= 0.0:
			_hide_skip_prompt()

func _show_skip_prompt():
	hide_timer = HIDE_TIMEOUT
	if skip_fade_tween and skip_fade_tween.is_valid():
		skip_fade_tween.kill()
	skip_fade_tween = create_tween()
	skip_fade_tween.tween_property(skip_container, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE)

func _hide_skip_prompt():
	if is_mouse_hovering_skip or is_skipped:
		return
	if skip_fade_tween and skip_fade_tween.is_valid():
		skip_fade_tween.kill()
	skip_fade_tween = create_tween()
	skip_fade_tween.tween_property(skip_container, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE)

func _on_skip_mouse_entered():
	is_mouse_hovering_skip = true
	if skip_label:
		skip_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	if skip_chevron:
		skip_chevron.modulate = Color(1.0, 0.9, 0.3, 1.0)
	_show_skip_prompt()

func _on_skip_mouse_exited():
	is_mouse_hovering_skip = false
	if skip_label:
		skip_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	if skip_chevron:
		skip_chevron.modulate = Color(1.0, 1.0, 1.0, 1.0)
	hide_timer = HIDE_TIMEOUT

func _on_skip_pressed():
	if is_skipped:
		return
	is_skipped = true
	AudioManager.play_sfx("button_press")
	get_tree().change_scene_to_file("res://scenes/StartMenu.tscn")

func shake_camera(strength: float = 20.0):
	shake_strength = strength
	AudioManager.play_sfx("camera_shake")

func _on_animation_player_animation_finished(anim_name):
	# Wenn die intro-Animation fertig ist (oder eine andere), machen wir weiter
	if anim_name == "intro" and not is_skipped:
		is_skipped = true
		print("Intro beendet - wechsle zum Hauptmenü!")
		get_tree().change_scene_to_file("res://scenes/StartMenu.tscn")
