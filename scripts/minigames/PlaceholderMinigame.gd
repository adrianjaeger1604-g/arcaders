extends Control

@onready var back_btn = $CenterContainer/VBox/BackButton

func _ready():
	back_btn.pressed.connect(_on_back_pressed)
	
	# Stelle sicher, dass Handys im Waiting Screen sind
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/MainBoard.tscn")
