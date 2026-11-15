class_name PixelBackButton
extends TextureButton

signal back_requested

## Wenn true, bricht der Klick die Minispiel-Auswahl ab und kehrt sauber zum MainBoard zurück.
@export var auto_return_to_main_board: bool = true

var _hover_tween: Tween = null
var _is_cancelling: bool = false

func _ready():
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pivot_offset = size / 2.0 if size != Vector2.ZERO else Vector2(40, 40)
	resized.connect(_on_resized)
	
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_resized():
	pivot_offset = size / 2.0

func _on_mouse_entered():
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_mouse_exited():
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_pressed():
	AudioManager.play_sfx("button_press")
	back_requested.emit()
	if auto_return_to_main_board:
		cancel_and_return_to_board()

func cancel_and_return_to_board():
	if _is_cancelling:
		return
	_is_cancelling = true
	disabled = true
	
	AudioManager.stop_music()
	
	# Da das Spiel aus Versehen geklickt wurde, ziehen wir den Runden-Zähler wieder ab,
	# aber NUR, wenn das Spiel noch nicht beendet/gewertet wurde und es kein Replay war!
	if NetworkManager.current_turn_number > 0:
		if NetworkManager.current_minigame_index == -1 or not NetworkManager.minigame_winners.has(NetworkManager.current_minigame_index):
			if not NetworkManager.is_replaying_minigame:
				NetworkManager.current_turn_number -= 1
	
	NetworkManager.is_replaying_minigame = false
	# Setze den Minispiel-Index zurück, damit kein Slam oder falscher Punkt getriggert wird
	NetworkManager.current_minigame_index = -1
	
	# Stelle sicher, dass die Controller-Handys im Wartebildschirm bleiben
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})
	
	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/MainBoard.tscn")
