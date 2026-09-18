extends CanvasLayer

@onready var overlay = $SettingsOverlay
@onready var gear_button = $MarginContainer/SettingsButton
@onready var close_button = $SettingsOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/CloseSettingsButton

@onready var music_mute_btn = $SettingsOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MusicRow/MusicMuteButton
@onready var music_slider = $SettingsOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MusicRow/MusicSlider

@onready var sfx_mute_btn = $SettingsOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SFXRow/SFXMuteButton
@onready var sfx_slider = $SettingsOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SFXRow/SFXSlider
@onready var show_qr_button = $SettingsOverlay/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ShowQRButton

@onready var qr_overlay = $QROverlay
@onready var qr_instruction_label = $QROverlay/CenterContainer/VBoxContainer/InstructionLabel
@onready var qr_texture_rect = $QROverlay/CenterContainer/VBoxContainer/CenterBox/QRCodeRect
@onready var close_qr_button = $QROverlay/CenterContainer/VBoxContainer/CloseQRButton
@onready var qr_http_request = $QRHTTPRequest

func _ready():
	overlay.visible = false
	qr_overlay.visible = false
	
	# Connect buttons
	gear_button.pressed.connect(_on_gear_pressed)
	close_button.pressed.connect(_on_close_pressed)
	show_qr_button.pressed.connect(_on_show_qr_pressed)
	close_qr_button.pressed.connect(_on_close_qr_pressed)
	
	qr_http_request.request_completed.connect(_on_qr_request_completed)
	
	music_mute_btn.pressed.connect(_on_music_mute_pressed)
	sfx_mute_btn.pressed.connect(_on_sfx_mute_pressed)
	
	music_slider.value_changed.connect(_on_music_slider_changed)
	sfx_slider.value_changed.connect(_on_sfx_slider_changed)
	
	_update_ui_state()

func _on_gear_pressed():
	AudioManager.play_sfx("settings_open")
	overlay.visible = true
	
	# Hide QR button on Main screen (Lobby)
	var current_scene_name = get_tree().current_scene.name
	if current_scene_name == "Main":
		show_qr_button.hide()
	else:
		show_qr_button.show()
		
	_update_ui_state()

func _on_close_pressed():
	overlay.visible = false

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
	AudioManager.play_sfx("settings_open")
	overlay.visible = false
	qr_overlay.visible = true
	_generate_qr_code()

func _on_close_qr_pressed():
	qr_overlay.visible = false

func _generate_qr_code():
	var ip = NetworkManager.get_local_ip()
	qr_instruction_label.text = "Scanne den QR Code!\nLokale IP: " + ip
	
	var random_timestamp = str(Time.get_ticks_msec())
	var join_url = "http://" + ip + ":8000/?ip=" + ip + "&nocache=" + random_timestamp
	var api_url = "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=" + join_url.uri_encode()
	qr_http_request.request(api_url)

func _on_qr_request_completed(result, response_code, headers, body):
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var image = Image.new()
		var error = image.load_png_from_buffer(body)
		if error == OK:
			var texture = ImageTexture.create_from_image(image)
			qr_texture_rect.texture = texture
		else:
			print("Fehler beim Laden des QR PNGs.")
	else:
		print("Fehler beim Abrufen des QR Codes. HTTP Code: ", response_code)
