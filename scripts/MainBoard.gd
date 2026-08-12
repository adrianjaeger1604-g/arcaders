extends Control

@onready var grid = $VBoxContainer/CenterContainer/MinigameGrid

# Settings UI
@onready var settings_button = $SettingsButton
@onready var settings_overlay = $SettingsOverlay
@onready var show_qr_button = $SettingsOverlay/CenterContainer/PanelContainer/VBoxContainer/ShowQRButton
@onready var close_settings_button = $SettingsOverlay/CenterContainer/PanelContainer/VBoxContainer/CloseSettingsButton

# QR UI
@onready var qr_overlay = $QROverlay
@onready var qr_instruction_label = $QROverlay/CenterContainer/VBoxContainer/InstructionLabel
@onready var qr_texture_rect = $QROverlay/CenterContainer/VBoxContainer/CenterBox/QRCodeRect
@onready var close_qr_button = $QROverlay/CenterContainer/VBoxContainer/CloseQRButton
@onready var qr_http_request = $QRHTTPRequest

# Event Popup UI
@onready var event_overlay = $EventOverlay
@onready var event_label = $EventOverlay/CenterContainer/MessageLabel

var card_scene = preload("res://scenes/ui/MinigameCard.tscn")

var team_colors = [
	Color(0.95, 0.35, 0.35, 1), # Rot
	Color(0.35, 0.65, 1.0, 1), # Blau
	Color(0.35, 0.85, 0.45, 1), # Gruen
	Color(1.0, 0.9, 0.3, 1), # Gelb
	Color(0.75, 0.45, 0.95, 1), # Lila
	Color(1.0, 0.6, 0.25, 1)  # Orange
]

func _ready():
	AudioManager.play_music("intro")
	_setup_settings_button()
	_populate_grid()
	_spawn_players()
	
	# Settings & QR Signalkopplung
	var btn_settings = settings_button if settings_button else find_child("SettingsButton", true, false)
	var btn_close_settings = close_settings_button if close_settings_button else find_child("CloseSettingsButton", true, false)
	var btn_show_qr = show_qr_button if show_qr_button else find_child("ShowQRButton", true, false)
	var btn_close_qr = close_qr_button if close_qr_button else find_child("CloseQRButton", true, false)
	var http_qr = qr_http_request if qr_http_request else find_child("QRHTTPRequest", true, false)
	
	if btn_settings:
		btn_settings.pressed.connect(_on_settings_button_pressed)
	if btn_close_settings:
		btn_close_settings.pressed.connect(_on_close_settings_button_pressed)
	if btn_show_qr:
		btn_show_qr.pressed.connect(_on_show_qr_button_pressed)
	if btn_close_qr:
		btn_close_qr.pressed.connect(_on_close_qr_button_pressed)
	if http_qr:
		http_qr.request_completed.connect(_on_qr_request_completed)
	
	# Zeige das "Team ... ist dran!" Popup zum Rundenstart (nach dem Slam)
	if NetworkManager.computed_teams.size() > 0:
		var active_index = NetworkManager.current_turn_number % NetworkManager.computed_teams.size()
		var active_team = NetworkManager.computed_teams[active_index]
		
		# Wenn gerade ein Spiel beendet wurde, zögern wir das Runden-Popup um 1.6s raus, damit der Slam zuerst kommt!
		if NetworkManager.current_minigame_index != -1:
			var turn_timer = get_tree().create_timer(1.6)
			turn_timer.timeout.connect(func(): show_event_popup(active_team["name"] + " ist dran!", active_team["color"]))
		else:
			show_event_popup(active_team["name"] + " ist dran!", active_team["color"])
			
	# Jetzt können wir den minigame_index zurücksetzen, damit die Animation nicht bei Overlay-Updates neu triggert
	NetworkManager.current_minigame_index = -1
	_connect_buttons_sfx(self)

func _connect_buttons_sfx(node: Node):
	if node is Button or node is TextureButton:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)
	
func _populate_grid():
	var total_minigames = NetworkManager.minigames_count
	
	# Passende Spaltenanzahl ermitteln
	if total_minigames == 12 or total_minigames == 16:
		grid.columns = 4
	elif total_minigames == 20:
		grid.columns = 5
	else: # Default 24
		grid.columns = 6
	
	for i in range(total_minigames):
		var card = card_scene.instantiate()
		
		# Robustes Befüllen des Labels auf der Karte mit Fallback
		var card_label = card.get_node_or_null("BackgroundPanel/Label")
		if not card_label:
			card_label = card.find_child("Label", true, false)
		if card_label:
			card_label.text = str(i + 1)
		
		# We need to know which minigame this is to load the thumbnail.
		var scene_path = ""
		if i < NetworkManager.board_layout.size():
			scene_path = NetworkManager.board_layout[i]
		
		# Look for thumbnail named after the scene
		var scene_file = scene_path.get_file().get_basename() # z.B. "Minigame10Sec" or "PlaceholderMinigame"
		
		var thumb_tex = null
		if "10Sec" in scene_file:
			thumb_tex = preload("res://assets/minigames/10sec/10sec_thumbnail.png")
		elif "TipFast" in scene_file:
			thumb_tex = preload("res://assets/minigames/tip_fast/tip_fast_thumbnail.png")
		elif "VideoGameQuiz" in scene_file:
			thumb_tex = preload("res://assets/minigames/video_game_quiz/video_game_quiz_thumbnail.png")
			
		if thumb_tex:
			var status_tex = card.get_node_or_null("BackgroundPanel/StatusTexture")
			if not status_tex:
				status_tex = card.find_child("StatusTexture", true, false)
			if status_tex:
				status_tex.texture = thumb_tex
			if card_label:
				card_label.hide() # Hide number if we have an image
		
		# Check if this minigame was already won
		if NetworkManager.minigame_winners.has(i):
			var winner_data = NetworkManager.minigame_winners[i]
			var winner_color = Color(0,0,0,1)
			var points_won = 2 # standard fallback
			
			if typeof(winner_data) == TYPE_COLOR:
				winner_color = winner_data
			elif typeof(winner_data) == TYPE_DICTIONARY:
				winner_color = winner_data["color"]
				points_won = winner_data["points"]
				
			card.disabled = true
			
			# Zeige einen farbigen Rahmen oder Schimmer über dem Thumbnail
			if thumb_tex:
				var status_tex = card.get_node_or_null("BackgroundPanel/StatusTexture")
				if not status_tex:
					status_tex = card.find_child("StatusTexture", true, false)
				if status_tex:
					status_tex.modulate = winner_color
				
			# Zeige die Punktzahl in weiss auf der Karte an!
			var points_label = Label.new()
			points_label.text = "+" + str(points_won)
			points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			points_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			points_label.add_theme_font_size_override("font_size", 48)
			points_label.add_theme_color_override("font_color", Color(1, 1, 1, 1)) # Weiss
			points_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1)) # Schwarze Kontur
			points_label.add_theme_constant_override("outline_size", 8)
			
			var bg_panel = card.get_node_or_null("BackgroundPanel")
			if not bg_panel:
				bg_panel = card.find_child("BackgroundPanel", true, false)
			if bg_panel:
				bg_panel.add_child(points_label)
			
			# Animation check: Ist es das gerade beendete Minispiel?
			if i == NetworkManager.current_minigame_index:
				points_label.pivot_offset = Vector2(128, 72)
				points_label.scale = Vector2(6, 6)
				points_label.modulate.a = 0.0
				
				# Starte die Slam- und Shake-Animation zeitversetzt
				var anim_tween = create_tween()
				anim_tween.tween_interval(0.8)
				
				# Einfliegen / Draufklatschen (Slam) in 0.35s
				anim_tween.tween_property(points_label, "scale", Vector2(1, 1), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
				anim_tween.parallel().tween_property(points_label, "modulate:a", 1.0, 0.25)
				
				# Am Ende des Slams wackelt der Bildschirm!
				anim_tween.tween_callback(func(): shake_screen(25.0, 0.4))
				
		else:
			# Not played yet, make it playable
			card.pressed.connect(_on_minigame_pressed.bind(i))
			
		grid.add_child(card)

func _on_minigame_pressed(minigame_index: int):
	print("Lade Minispiel Index ", minigame_index)
	NetworkManager.current_minigame_index = minigame_index
	
	# Speichere welches Team das Spiel ausgesucht hat (bevor wir den Turn-Zaehler erhoehen!)
	if NetworkManager.computed_teams.size() > 0:
		var selecting_index = NetworkManager.current_turn_number % NetworkManager.computed_teams.size()
		NetworkManager.current_selecting_team_color = NetworkManager.computed_teams[selecting_index]["color"]
	
	# Erhoehe den Runden-Zaehler fuer die naechste Wahl
	NetworkManager.current_turn_number += 1
	
	if minigame_index < NetworkManager.board_layout.size():
		var scene_path = NetworkManager.board_layout[minigame_index]
		get_tree().change_scene_to_file(scene_path)
	else:
		print("ERROR: Invalider Minispiel-Index oder leeres Layout!")

func _spawn_players():
	var players = []
	for p_id in NetworkManager.player_sessions.keys():
		var p_data = NetworkManager.player_sessions[p_id]
		players.append(p_data)
		
	var num_players = players.size()
	if num_players == 0:
		return # Keine Spieler verbunden
		
	# Berechne die Teams, falls noch nicht geschehen
	if NetworkManager.computed_teams.size() == 0:
		NetworkManager.compute_teams()
		
	# Bestimme das aktive Team, das gerade an der Reihe ist (strikter sequentieller Runden-Zaehler)
	var active_team = null
	if NetworkManager.computed_teams.size() > 0:
		var active_index = NetworkManager.current_turn_number % NetworkManager.computed_teams.size()
		active_team = NetworkManager.computed_teams[active_index]
		
	var spacing = 180 # Horizontaler Abstand zwischen den Charakteren
	var center_x = 960 # Bildschirmmitte (1920 / 2)
	var start_x = center_x - (spacing * (num_players - 1)) / 2.0
	var spawn_y = 960 # Cedric steht bei y=960 perfekt auf der TileMap3 (y=16 / 1024px)
	
	for i in range(num_players):
		var p_data = players[i]
		var char_name = p_data.get("character", "Cedric")
		if char_name == "" or char_name == "unknown":
			char_name = "Cedric"
			
		print("MAINBOARD DEBUG: Spieler = ", p_data.get("name"), " | Charakter aus Daten = '", p_data.get("character"), "' | Gewählter Name = '", char_name, "'")
			
		# Finde die Teamfarbe des Spielers und ob er im aktiven Team ist
		var team_color = Color(1, 1, 1, 1) # Fallback Weiß
		var is_active = false
		
		for team in NetworkManager.computed_teams:
			for p in team["players"]:
				if p.get("name", "") == p_data.get("name", ""):
					team_color = team["color"]
					if active_team and active_team["name"] == team["name"]:
						is_active = true
					break
			
		var scene_path = _get_character_scene_path(char_name)
		print("MAINBOARD DEBUG: Scene Path für '", char_name, "' ist '", scene_path, "'")
		
		var char_scene = load(scene_path)
		if char_scene:
			var char_instance = char_scene.instantiate()
			char_instance.position = Vector2(start_x + (i * spacing), spawn_y)
			char_instance.is_in_cutscene = true # Schaltet Tastatursteuerung aus
			add_child(char_instance)
			
			# Wenn das Team dieses Spielers an der Reihe ist, lass ihn trinken!
			if is_active:
				# Warte 0.2 Sekunden, bis der Charakter gelandet ist, und lass ihn dann durchgehend trinken
				get_tree().create_timer(0.2).timeout.connect(char_instance.play_drink)
			
			# Füge Namenslabel über dem Kopf des Charakters hinzu
			var name_label = Label.new()
			name_label.text = p_data.get("name", "Spieler")
			name_label.add_theme_font_size_override("font_size", 24)
			
			# Label zentrieren (Breite 300, halbe Breite Versatz nach links)
			name_label.custom_minimum_size = Vector2(300, 40)
			name_label.position = Vector2(-150, -110) # 110 Pixel über dem Ursprung des Charakters
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			
			# Setze die Schriftfarbe auf die Teamfarbe
			name_label.add_theme_color_override("font_color", team_color)
			
			# Füge dem Label eine Outline hinzu, damit man es auf blauem Hintergrund perfekt liest
			name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
			name_label.add_theme_constant_override("outline_size", 10) # Etwas dickere Outline für noch bessere Lesbarkeit
			
			char_instance.add_child(name_label)

func _get_character_scene_path(character_name: String) -> String:
	var formatted_name = character_name
	if formatted_name == "Cedi":
		formatted_name = "Cedric"
		
	var path = "res://scenes/characters/" + formatted_name + ".tscn"
	if ResourceLoader.exists(path):
		return path
		
	# Fallback, falls die spezifische .tscn nicht existiert
	return "res://scenes/characters/Cedric.tscn"

# --- Einstellungen & QR Code Steuerung ---

func _on_settings_button_pressed():
	AudioManager.play_sfx("settings_open")
	if settings_overlay:
		settings_overlay.visible = true

func _on_close_settings_button_pressed():
	if settings_overlay:
		settings_overlay.visible = false

func _on_show_qr_button_pressed():
	AudioManager.play_sfx("settings_open")
	if qr_overlay:
		qr_overlay.visible = true
	_generate_qr_code()

func _on_close_qr_button_pressed():
	if qr_overlay:
		qr_overlay.visible = false

func _generate_qr_code():
	var ip = NetworkManager.get_local_ip()
	
	var label = qr_instruction_label if qr_instruction_label else find_child("InstructionLabel", true, false)
	if label:
		label.text = "Scanne den QR Code!\nLokale IP: " + ip
	
	# Für Cache-Busting
	var random_timestamp = str(Time.get_ticks_msec())
	var join_url = "http://" + ip + ":8000/?ip=" + ip + "&nocache=" + random_timestamp
	
	# Nutze externe API für den QR Code
	var api_url = "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=" + join_url.uri_encode()
	var http_qr = qr_http_request if qr_http_request else find_child("QRHTTPRequest", true, false)
	if http_qr:
		http_qr.request(api_url)

func _on_qr_request_completed(result, response_code, headers, body):
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var image = Image.new()
		var error = image.load_png_from_buffer(body)
		if error == OK:
			var texture = ImageTexture.create_from_image(image)
			var qr_rect = qr_texture_rect if qr_texture_rect else find_child("QRCodeRect", true, false)
			if qr_rect:
				qr_rect.texture = texture
		else:
			print("Fehler beim Laden des QR PNGs.")
	else:
		print("Fehler beim Abrufen des QR Codes. HTTP Code: ", response_code)

func _setup_settings_button():
	var btn = settings_button if settings_button else find_child("SettingsButton", true, false)
	if btn:
		btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# Micro-animations/hover-effects using modulations
		btn.mouse_entered.connect(func(): btn.modulate = Color(0.85, 0.85, 0.85, 1))
		btn.mouse_exited.connect(func(): btn.modulate = Color(1, 1, 1, 1))
		btn.button_down.connect(func(): btn.modulate = Color(0.7, 0.7, 0.7, 1))
		btn.button_up.connect(func(): btn.modulate = Color(0.85, 0.85, 0.85, 1) if btn.is_hovered() else Color(1, 1, 1, 1))

func show_event_popup(message: String, team_color: Color = Color.WHITE):
	if event_overlay:
		event_overlay.visible = true
		event_overlay.modulate.a = 0.0
	else:
		var overlay = find_child("EventOverlay", true, false)
		if overlay:
			overlay.visible = true
			overlay.modulate.a = 0.0
			
	var label = event_label if event_label else find_child("MessageLabel", true, false)
	if label:
		label.text = message
		label.add_theme_color_override("font_color", team_color)
	
	var overlay_node = event_overlay if event_overlay else find_child("EventOverlay", true, false)
	if overlay_node:
		var tween = create_tween()
		# Fade in over 0.5 seconds
		tween.tween_property(overlay_node, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# Wait for 2.0 seconds
		tween.tween_interval(2.0)
		# Fade out over 0.5 seconds
		tween.tween_property(overlay_node, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		# Set visible to false when done
		tween.tween_callback(func(): overlay_node.visible = false)

func shake_screen(intensity: float = 20.0, duration: float = 0.4):
	AudioManager.play_sfx("camera_shake")
	var shake_tween = create_tween()
	var original_pos = Vector2.ZERO
	
	var steps = 8
	var step_duration = duration / steps
	for j in range(steps - 1):
		var offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		shake_tween.tween_property(self, "position", offset, step_duration)
		intensity *= 0.75 # Dampen the shake effect
		
	shake_tween.tween_property(self, "position", original_pos, step_duration)
