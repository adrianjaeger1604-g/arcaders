class_name PixelBackButton
extends TextureButton

signal back_requested

## Wenn true, bricht der Klick die Minispiel-Auswahl ab und kehrt sauber zum MainBoard zurück.
@export var auto_return_to_main_board: bool = true

## Wenn true, wird vor dem Abbruch eines Minispiels ein Bestätigungs-Dialog eingeblendet.
@export var require_confirmation: bool = true

var _hover_tween: Tween = null
var _is_cancelling: bool = false

@onready var confirm_layer: CanvasLayer = get_node_or_null("ConfirmLayer")
@onready var cancel_btn: Button = get_node_or_null("ConfirmLayer/DimBackdrop/CenterContainer/ModalPanel/Margin/VBox/ButtonsHBox/CancelBtn")
@onready var confirm_btn: Button = get_node_or_null("ConfirmLayer/DimBackdrop/CenterContainer/ModalPanel/Margin/VBox/ButtonsHBox/ConfirmBtn")

func _ready():
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pivot_offset = size / 2.0 if size != Vector2.ZERO else Vector2(40, 40)
	resized.connect(_on_resized)
	
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	if confirm_layer:
		confirm_layer.visible = false
	if cancel_btn:
		cancel_btn.pressed.connect(_on_cancel_pressed)
	if confirm_btn:
		confirm_btn.pressed.connect(_on_confirm_pressed)

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
		if require_confirmation and confirm_layer:
			show_confirm_dialog()
		else:
			cancel_and_return_to_board()

func show_confirm_dialog():
	if confirm_layer:
		confirm_layer.visible = true

func hide_confirm_dialog():
	if confirm_layer:
		confirm_layer.visible = false

func _on_cancel_pressed():
	AudioManager.play_sfx("button_press")
	hide_confirm_dialog()

func _on_confirm_pressed():
	AudioManager.play_sfx("button_press")
	hide_confirm_dialog()
	cancel_and_return_to_board()

func _unhandled_input(event: InputEvent):
	if confirm_layer and confirm_layer.visible:
		if event.is_action_pressed("ui_cancel"):
			hide_confirm_dialog()
			get_viewport().set_input_as_handled()

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
