extends Control

@onready var http_request = $HTTPRequest
@onready var qr_texture_rect = $CenterContainer/VBoxContainer/CenterBox/QRCodeRect
@onready var instruction_label = $CenterContainer/VBoxContainer/InstructionLabel
@onready var player_list = $CenterContainer/VBoxContainer/PlayerList
@onready var start_button = $CenterContainer/VBoxContainer/GameButton

# Dies wäre später die echte gehostete Adresse, z.B. https://arcaders.vercel.app
const CONTROLLER_URL = "http://arcaders-controller.vercel.app/"

func _ready():
	AudioManager.play_music("intro")
	NetworkManager.client_connected.connect(_on_player_connected)
	NetworkManager.client_disconnected.connect(_on_player_disconnected)
	start_button.pressed.connect(_on_start_game_pressed)
	# Button anfangs deaktivieren, bis min. 1 Spieler da ist
	start_button.disabled = true
	_generate_qr_code()
	_connect_buttons_sfx(self)

func _connect_buttons_sfx(node: Node):
	if node is Button:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func _update_player_list_text():
	var names = []
	for player in NetworkManager.player_sessions.values():
		var p_name = player.get("name", "Unbekannt")
		names.append(p_name)
	player_list.text = ", ".join(names)
	
	start_button.disabled = names.is_empty()

func _on_player_connected(player_id, player_name):
	_update_player_list_text()

func _on_player_disconnected(player_id):
	# Call deferred to ensure NetworkManager has removed the player from the dictionary first
	call_deferred("_update_player_list_text")

func _on_start_game_pressed():
	print("Lobby voll, wechsle zur Charakterauswahl...")
	get_tree().change_scene_to_file("res://scenes/CharacterSelect.tscn")

func _generate_qr_code():
	var ip = NetworkManager.get_local_ip()
	instruction_label.text = "Scanne den QR Code!\nLokale IP: " + ip
	
	# Für Cache-Busting: Time-Parameter anhängen, damit der Browser nicht aggressiv alte HTML-Seiten verwendet
	var random_timestamp = str(Time.get_ticks_msec())
	var join_url = "http://" + ip + ":8000/?ip=" + ip + "&nocache=" + random_timestamp
	
	# Nutze externe API für den QR Code (schnell und einfach für den Prototyp)
	var api_url = "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=" + join_url.uri_encode()
	
	http_request.request_completed.connect(self._on_qr_request_completed)
	http_request.request(api_url)

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
