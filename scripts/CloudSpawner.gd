extends Node2D

@export var cloud_scene: PackedScene = preload("res://scenes/Cloud.tscn")
@export var initial_clouds_count: int = 2
@export var min_y: float = 50.0
@export var max_y: float = 300.0
@export var spawn_interval: float = 8.0

var timer: float = 0.0

func _ready():
	for i in range(initial_clouds_count):
		var cloud = cloud_scene.instantiate()
		cloud.min_y = min_y
		cloud.max_y = max_y
		cloud.position.x = (float(i) + randf_range(0.1, 0.9)) * (1920.0 / float(max(1, initial_clouds_count)))
		cloud.position.y = randf_range(min_y, max_y)
		add_child(cloud)

func _process(delta):
	timer += delta
	if timer >= spawn_interval:
		timer = 0.0
		spawn_cloud()

func spawn_cloud():
	var cloud = cloud_scene.instantiate()
	cloud.min_y = min_y
	cloud.max_y = max_y
	cloud.position.x = -300.0
	cloud.position.y = randf_range(min_y, max_y)
	add_child(cloud)
