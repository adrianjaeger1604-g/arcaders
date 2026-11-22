extends CanvasLayer

@onready var overlay = $SettingsOverlay
@onready var gear_button = $SettingsButton if has_node("SettingsButton") else $MarginContainer/SettingsButton
@onready var close_button = $SettingsOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/CloseSettingsButton

@onready var music_mute_btn = $SettingsOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MusicRow/MusicMuteButton
@onready var music_slider = $SettingsOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MusicRow/MusicSlider

@onready var sfx_mute_btn = $SettingsOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SFXRow/SFXMuteButton
@onready var sfx_slider = $SettingsOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SFXRow/SFXSlider
@onready var show_qr_button = $SettingsOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ShowQRButton
@onready var manage_saves_button = get_node_or_null("SettingsOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ManageSavesButton")
@onready var main_menu_button = $SettingsOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MainMenuButton
@onready var save_game_modal = get_node_or_null("SaveGameModal")

@onready var confirm_overlay = $ConfirmOverlay
@onready var confirm_message = $ConfirmOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ConfirmMessage
@onready var confirm_btn = $ConfirmOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/ConfirmButton
@onready var cancel_btn = $ConfirmOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/HBoxContainer/CancelButton

@onready var qr_overlay = $QROverlay
@onready var qr_instruction_label = $QROverlay/CenterContainer/VBoxContainer/InstructionLabel
@onready var qr_texture_rect = $QROverlay/CenterContainer/VBoxContainer/CenterBox/QRCodeRect
@onready var close_qr_button = $QROverlay/CenterContainer/VBoxContainer/CloseQRButton
@onready var qr_http_request = $QRHTTPRequest

func hide_gear_button():
	gear_button.visible = false

func show_gear_button():
	gear_button.visible = true

func _update_gear_visibility():
	if not is_inside_tree():
		return
	var tree = get_tree()
	if tree == null:
		return
	var cur = tree.current_scene
	if cur != null and cur.name == "IntroSequence":
		hide_gear_button()
	else:
		show_gear_button()

func _ready():
	overlay.visible = false
	qr_overlay.visible = false
	
	# Connect buttons
	gear_button.pressed.connect(_on_gear_pressed)
	close_button.pressed.connect(_on_close_pressed)
	show_qr_button.pressed.connect(_on_show_qr_pressed)
	if manage_saves_button:
		manage_saves_button.pressed.connect(_on_manage_saves_pressed)
	close_qr_button.pressed.connect(_on_close_qr_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	
	confirm_overlay.visible = false
	confirm_btn.pressed.connect(_on_confirm_return_pressed)
	cancel_btn.pressed.connect(_on_cancel_confirm_pressed)
	
	music_mute_btn.pressed.connect(_on_music_mute_pressed)
	sfx_mute_btn.pressed.connect(_on_sfx_mute_pressed)
	
	music_slider.value_changed.connect(_on_music_slider_changed)
	sfx_slider.value_changed.connect(_on_sfx_slider_changed)
	
	_update_ui_state()
	_connect_buttons_sfx(self)
	_setup_gear_button()
	
	get_tree().tree_changed.connect(_update_gear_visibility)
	_update_gear_visibility()

var _gear_hover_tween: Tween = null

func _setup_gear_button():
	if gear_button == null:
		return
	gear_button.pivot_offset = Vector2(32, 32)
	if not gear_button.mouse_entered.is_connected(_on_gear_mouse_entered):
		gear_button.mouse_entered.connect(_on_gear_mouse_entered)
	if not gear_button.mouse_exited.is_connected(_on_gear_mouse_exited):
		gear_button.mouse_exited.connect(_on_gear_mouse_exited)

func _on_gear_mouse_entered():
	if _gear_hover_tween:
		_gear_hover_tween.kill()
	_gear_hover_tween = create_tween()
	_gear_hover_tween.tween_property(gear_button, "scale", Vector2(1.08, 1.08), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_gear_mouse_exited():
	if _gear_hover_tween:
		_gear_hover_tween.kill()
	_gear_hover_tween = create_tween()
	_gear_hover_tween.tween_property(gear_button, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _connect_buttons_sfx(node: Node):
	if node is BaseButton:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func _on_gear_pressed():
	overlay.visible = true
	confirm_overlay.visible = false
	
	var current_scene_name = ""
	if get_tree().current_scene:
		current_scene_name = get_tree().current_scene.name
	
	# Hide QR button on Main screen (Lobby)
	if current_scene_name == "Main":
		show_qr_button.hide()
	else:
		show_qr_button.show()
		
	# Zeige "Zurück zum Hauptmenü" auf dem MainBoard und während Minispielen
	if _can_show_main_menu_button():
		main_menu_button.show()
	else:
		main_menu_button.hide()
		
	if manage_saves_button:
		if current_scene_name == "GameSetup" or current_scene_name == "Main":
			manage_saves_button.hide()
		else:
			manage_saves_button.show()
		
	_update_ui_state()

func _is_in_minigame() -> bool:
	if not is_inside_tree():
		return false
	var cur = get_tree().current_scene
	if cur == null:
		return false
	var path = cur.scene_file_path
	if path.begins_with("res://scenes/minigames/"):
		return true
	if NetworkManager.current_minigame_index != -1:
		return true
	return false

func _can_show_main_menu_button() -> bool:
	var cur = get_tree().current_scene
	if cur == null:
		return false
	var cur_name = cur.name
	if cur_name == "StartMenu" or cur_name == "IntroSequence":
		return false
	if cur_name == "MainBoard" or _is_in_minigame():
		return true
	return false

func _on_manage_saves_pressed():
	overlay.visible = false
	if save_game_modal:
		save_game_modal.open()

func _on_main_menu_pressed():
	if _is_in_minigame():
		overlay.visible = false
		confirm_message.text = "Der Fortschritt dieses Minispiels wird gelöscht!\n\nMöchtest du wirklich zum Hauptmenü zurückkehren?"
		confirm_overlay.visible = true
	else:
		_execute_return_to_main_menu()

func _on_cancel_confirm_pressed():
	confirm_overlay.visible = false
	overlay.visible = true

func _on_confirm_return_pressed():
	confirm_overlay.visible = false
	overlay.visible = false
	
	# Minispiel sauber abbrechen (nur dekrementieren, falls das Spiel abgebrochen wurde und noch nicht gewertet ist)
	if NetworkManager.current_turn_number > 0 and NetworkManager.current_minigame_index != -1:
		if not NetworkManager.minigame_winners.has(NetworkManager.current_minigame_index):
			if not NetworkManager.is_replaying_minigame:
				NetworkManager.current_turn_number -= 1
	NetworkManager.is_replaying_minigame = false
	NetworkManager.current_minigame_index = -1
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})
	
	_execute_return_to_main_menu()

func _execute_return_to_main_menu():
	overlay.visible = false
	confirm_overlay.visible = false
	AudioManager.stop_music()
	if SaveManager and NetworkManager.computed_teams.size() > 0:
		SaveManager.auto_save()
	get_tree().change_scene_to_file("res://scenes/StartMenu.tscn")

func _on_close_pressed():
	overlay.visible = false
	confirm_overlay.visible = false

func _on_music_mute_pressed():
	AudioManager.toggle_music_mute()
	_update_ui_state()

func _on_sfx_mute_pressed():
	AudioManager.toggle_sfx_mute()
	_update_ui_state()

func _on_music_slider_changed(value: float):
	AudioManager.set_music_volume(value)

func _on_sfx_slider_changed(value: float):
	AudioManager.set_sfx_volume(value)

var icon_speaker_on = preload("res://assets/ui/icons/icon_speaker_on.png")
var icon_speaker_muted = preload("res://assets/ui/icons/icon_speaker_muted.png")

func _update_ui_state():
	music_mute_btn.text = ""
	music_mute_btn.icon = icon_speaker_muted if AudioManager.music_muted else icon_speaker_on
	music_mute_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	music_mute_btn.expand_icon = true
	
	sfx_mute_btn.text = ""
	sfx_mute_btn.icon = icon_speaker_muted if AudioManager.sfx_muted else icon_speaker_on
	sfx_mute_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sfx_mute_btn.expand_icon = true
	
	music_slider.set_value_no_signal(AudioManager.volume_music)
	sfx_slider.set_value_no_signal(AudioManager.volume_sfx)

func _on_show_qr_pressed():
	overlay.visible = false
	qr_overlay.visible = true
	_generate_qr_code()

func _on_close_qr_pressed():
	qr_overlay.visible = false

func _generate_qr_code():
	var ip = NetworkManager.get_local_ip()
	qr_instruction_label.text = "Scanne den QR Code!\nLokale IP: " + ip
	
	if not NetworkManager.qr_code_ready.is_connected(_on_qr_ready):
		NetworkManager.qr_code_ready.connect(_on_qr_ready)
		
	var tex = NetworkManager.get_or_request_qr_code(qr_http_request)
	if tex != null:
		qr_texture_rect.texture = tex

func _on_qr_ready(texture: ImageTexture):
	if is_instance_valid(qr_texture_rect):
		qr_texture_rect.texture = texture
