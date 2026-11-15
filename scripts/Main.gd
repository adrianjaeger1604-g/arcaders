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
	NetworkManager.current_game_state = "join"
	NetworkManager.game_locked = false
	NetworkManager.client_connected.connect(_on_player_connected)
	NetworkManager.client_disconnected.connect(_on_player_disconnected)
	start_button.pressed.connect(_on_start_game_pressed)
	# Button anfangs deaktivieren, bis min. 1 Spieler da ist
	start_button.disabled = NetworkManager.player_sessions.is_empty()
	_update_player_list_text()
	_generate_qr_code()
	_connect_buttons_sfx(self)
	
	var back_btn = get_node_or_null("PixelBackButton")
	if back_btn:
		back_btn.auto_return_to_main_board = false
		back_btn.back_requested.connect(func():
			var tree = get_tree()
			if tree:
				tree.change_scene_to_file("res://scenes/GameSetup.tscn")
		)

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
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_theme_constant_override("separation", 10) # Abstand zwischen Name und Button
		
		# Name Label
		var label = Label.new()
		var is_conn = player.get("connected", true)
		if is_conn:
			label.text = p_name
		else:
			label.text = p_name + " (offline)"
			label.modulate = Color(0.75, 0.75, 0.75, 0.8)
		label.theme_type_variation = "H2"
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(label)
		
		# Kick Button (Höhe exakt auf die Texthöhe des Namens abgestimmt)
		var kick_btn = Button.new()
		kick_btn.text = "X"
		
		var btn_normal = StyleBoxFlat.new()
		btn_normal.bg_color = Color(0.85, 0.22, 0.22, 1.0)
		btn_normal.border_width_left = 2
		btn_normal.border_width_top = 2
		btn_normal.border_width_right = 2
		btn_normal.border_width_bottom = 2
		btn_normal.border_color = Color(1.0, 0.45, 0.45, 0.9)
		btn_normal.corner_radius_top_left = 4
		btn_normal.corner_radius_top_right = 4
		btn_normal.corner_radius_bottom_right = 4
		btn_normal.corner_radius_bottom_left = 4
		btn_normal.content_margin_left = 0
		btn_normal.content_margin_top = 0
		btn_normal.content_margin_right = 0
		btn_normal.content_margin_bottom = 0
		btn_normal.expand_margin_left = 0
		btn_normal.expand_margin_top = 0
		btn_normal.expand_margin_right = 0
		btn_normal.expand_margin_bottom = 0

		var btn_hover = btn_normal.duplicate()
		btn_hover.bg_color = Color(1.0, 0.32, 0.32, 1.0)
		btn_hover.border_color = Color(1.0, 0.8, 0.8, 1.0)

		var btn_pressed = btn_normal.duplicate()
		btn_pressed.bg_color = Color(0.65, 0.15, 0.15, 1.0)
		btn_pressed.border_color = Color(0.8, 0.3, 0.3, 1.0)

		kick_btn.add_theme_stylebox_override("normal", btn_normal)
		kick_btn.add_theme_stylebox_override("hover", btn_hover)
		kick_btn.add_theme_stylebox_override("pressed", btn_pressed)
		kick_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		kick_btn.add_theme_color_override("font_color", Color.WHITE)
		kick_btn.add_theme_color_override("font_hover_color", Color.WHITE)
		kick_btn.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.9))
		kick_btn.add_theme_font_size_override("font_size", 20)
		kick_btn.custom_minimum_size = Vector2(30, 30)
		kick_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		kick_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		
		kick_btn.pressed.connect(func():
			AudioManager.play_sfx("button_press")
			NetworkManager.kick_player(player_id)
		)
		hbox.add_child(kick_btn)
		
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
	
	if not NetworkManager.qr_code_ready.is_connected(_on_qr_ready):
		NetworkManager.qr_code_ready.connect(_on_qr_ready)
		
	var tex = NetworkManager.get_or_request_qr_code(http_request)
	if tex != null:
		qr_texture_rect.texture = tex

func _on_qr_ready(texture: ImageTexture):
	if is_instance_valid(qr_texture_rect):
		qr_texture_rect.texture = texture
