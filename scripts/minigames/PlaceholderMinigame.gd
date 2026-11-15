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
	if NetworkManager.current_turn_number > 0:
		if NetworkManager.current_minigame_index == -1 or not NetworkManager.minigame_winners.has(NetworkManager.current_minigame_index):
			if not NetworkManager.is_replaying_minigame:
				NetworkManager.current_turn_number -= 1
	NetworkManager.is_replaying_minigame = false
	NetworkManager.current_minigame_index = -1
	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/MainBoard.tscn")
