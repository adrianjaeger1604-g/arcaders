extends Control

@onready var http_request = $HTTPRequest
@onready var qr_texture_rect = $CenterContainer/VBoxContainer/CenterBox/QRCodeRect
@onready var instruction_label = $CenterContainer/VBoxContainer/InstructionLabel
@onready var player_list_container = $CenterContainer/VBoxContainer/PlayerListContainer
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
	# Alte UI Elemente entfernen
	for child in player_list_container.get_children():
		child.queue_free()
		
	var has_players = false
	for player_id in NetworkManager.player_sessions.keys():
		has_players = true
		var player = NetworkManager.player_sessions[player_id]
		var p_name = player.get("name", "Unbekannt")
		
		# HBox für Name und Kick-Button
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 15) # Abstand zwischen Name und Button
		
		# Name Label
		var label = Label.new()
		label.text = p_name
		label.theme_type_variation = "H2"
		hbox.add_child(label)
		
		# Kick Button
		var kick_btn = Button.new()
		kick_btn.text = "X"
		kick_btn.modulate = Color(1, 0.3, 0.3)
		
		# Button verkleinern
		kick_btn.add_theme_font_size_override("font_size", 24)
		kick_btn.custom_minimum_size = Vector2(30, 30)
		kick_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER # Zentriere den Button vertikal neben dem Text
		
		kick_btn.pressed.connect(func(): NetworkManager.kick_player(player_id))
		hbox.add_child(kick_btn)
		
		# Kleiner Abstandshalter zwischen den Spielern
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(20, 0)
		hbox.add_child(spacer)
		
		player_list_container.add_child(hbox)
	
	start_button.disabled = not has_players

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
