extends Node2D

@export var cloud_scene: PackedScene = preload("res://scenes/Cloud.tscn")

var timer: float = 0.0
const SPAWN_INTERVAL: float = 10.0

func _ready():
	# Spawn two clouds immediately when the spawner enters the scene tree
	# One on the left side, one on the right side
	var cloud1 = cloud_scene.instantiate()
	cloud1.position.x = randf_range(0.0, 960.0)
	add_child(cloud1)
	
	var cloud2 = cloud_scene.instantiate()
	cloud2.position.x = randf_range(960.0, 1920.0)
	add_child(cloud2)

func _process(delta):
	timer += delta
	if timer >= SPAWN_INTERVAL:
		timer = 0.0
		spawn_cloud()

func spawn_cloud():
	var cloud = cloud_scene.instantiate()
	add_child(cloud)
