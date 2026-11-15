extends Node2D

const SPEED_MIN = 30.0
const SPEED_MAX = 60.0

@export var min_y: float = 50.0
@export var max_y: float = 300.0

@export var cloud_textures: Array[Texture2D] = [
	preload("res://assets/objects/clouds/spr_cloud_small.png"),
	preload("res://assets/objects/clouds/spr_cloud_medium.png"),
	preload("res://assets/objects/clouds/spr_cloud_big.png")
]

var speed: float = 0.0

func _ready():
	speed = randf_range(SPEED_MIN, SPEED_MAX)
	$Sprite2D.texture = cloud_textures.pick_random()
	if position.y == 0.0:
		position.y = randf_range(min_y, max_y)
	
	# Only set X to off-screen if it hasn't been set by the spawner
	if position.x == 0.0:
		position.x = -300.0

func _process(delta):
	position.x += speed * delta
	# Assuming 1920 width, safely destroy when past 2200
	if position.x > 2200.0:
		queue_free()
