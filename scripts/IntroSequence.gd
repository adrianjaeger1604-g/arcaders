extends Node2D

@onready var animation_player = $AnimationPlayer
@onready var camera = $Camera2D

var shake_strength: float = 0.0
var shake_fade: float = 5.0
var rng = RandomNumberGenerator.new()

func _ready():
	rng.randomize()
	# Startet intro_music bei 30.0 Sekunden und 6.0 dB lauter
	AudioManager.play_music("intro", 0.5, 30.0, 6.0)
	# Intro-Animation sofort starten
	animation_player.play("intro")

func _process(delta):
	if shake_strength > 0:
		shake_strength = lerpf(shake_strength, 0, shake_fade * delta)
		camera.offset = Vector2(rng.randf_range(-shake_strength, shake_strength), rng.randf_range(-shake_strength, shake_strength))

func shake_camera(strength: float = 20.0):
	shake_strength = strength
	AudioManager.play_sfx("camera_shake")

func _on_animation_player_animation_finished(anim_name):
	# Wenn die intro-Animation fertig ist (oder eine andere), machen wir weiter
	if anim_name == "intro":
		print("Intro beendet - wechsle zum Hauptmenü!")
		get_tree().change_scene_to_file("res://scenes/StartMenu.tscn")
