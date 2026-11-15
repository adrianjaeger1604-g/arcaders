extends Control

@onready var grid = $VBoxContainer/CenterContainer/MinigameGrid

# Optional QR / Event references (fallback with get_node_or_null)
@onready var show_qr_button = get_node_or_null("ShowQRButton")
@onready var qr_overlay = get_node_or_null("QROverlay")
@onready var qr_instruction_label = get_node_or_null("QROverlay/CenterContainer/VBoxContainer/InstructionLabel")
@onready var qr_texture_rect = get_node_or_null("QROverlay/CenterContainer/VBoxContainer/CenterBox/QRCodeRect")
@onready var close_qr_button = get_node_or_null("QROverlay/CenterContainer/VBoxContainer/CloseQRButton")
@onready var qr_http_request = get_node_or_null("QRHTTPRequest")

@onready var event_overlay = get_node_or_null("EventOverlay")
@onready var event_label = get_node_or_null("EventOverlay/CenterContainer/MessageLabel")

# Overlay für die Wiederholungs-Bestätigung bereits gespielter Minispiele
@onready var repeat_confirm_overlay = get_node_or_null("RepeatConfirmOverlay")
@onready var repeat_confirm_message = get_node_or_null("RepeatConfirmOverlay/PanelContainer/MarginContainer/VBox/MessageLabel")
@onready var btn_confirm_repeat = get_node_or_null("RepeatConfirmOverlay/PanelContainer/MarginContainer/VBox/HBox/BtnConfirmRepeat")
@onready var btn_cancel_repeat = get_node_or_null("RepeatConfirmOverlay/PanelContainer/MarginContainer/VBox/HBox/BtnCancelRepeat")

var card_scene = preload("res://scenes/ui/MinigameCard.tscn")
var pipe_scene = preload("res://scenes/Pipe.tscn")
var spawned_characters: Array = []
var is_transitioning: bool = false
var _pending_repeat_index: int = -1

var team_colors = [
	Color(0.95, 0.35, 0.35, 1), # Rot
	Color(0.35, 0.65, 1.0, 1), # Blau
	Color(0.35, 0.85, 0.45, 1), # Gruen
	Color(1.0, 0.9, 0.3, 1), # Gelb
	Color(0.75, 0.45, 0.95, 1), # Lila
	Color(1.0, 0.6, 0.25, 1)  # Orange
]

func _ready():
	AudioManager.play_random_mainboard_music()
	NetworkManager.is_replaying_minigame = false
	if repeat_confirm_overlay:
		repeat_confirm_overlay.visible = false
	if btn_confirm_repeat:
		btn_confirm_repeat.pressed.connect(_on_confirm_repeat_pressed)
	if btn_cancel_repeat:
		btn_cancel_repeat.pressed.connect(_on_cancel_repeat_pressed)
	
	if NetworkManager.current_turn_number < NetworkManager.minigame_winners.size():
		NetworkManager.current_turn_number = NetworkManager.minigame_winners.size()
	_populate_grid()
	_spawn_players()
	
	# QR Signalkopplung
	var btn_show_qr = show_qr_button if show_qr_button else find_child("ShowQRButton", true, false)
	var btn_close_qr = close_qr_button if close_qr_button else find_child("CloseQRButton", true, false)
	var http_qr = qr_http_request if qr_http_request else find_child("QRHTTPRequest", true, false)
	
	if btn_show_qr:
		btn_show_qr.pressed.connect(_on_show_qr_button_pressed)
	if btn_close_qr:
		btn_close_qr.pressed.connect(_on_close_qr_button_pressed)
	
	# Zeige das "Team ... ist dran!" Popup zum Rundenstart (nach dem Slam)
	if NetworkManager.computed_teams.size() > 0:
		var active_index = NetworkManager.current_turn_number % NetworkManager.computed_teams.size()
		var active_team = NetworkManager.computed_teams[active_index]
		
		# Wenn gerade ein Spiel beendet wurde, zögern wir das Runden-Popup um 1.6s raus, damit der Slam zuerst kommt!
		if NetworkManager.current_minigame_index != -1:
			SaveManager.auto_save()
			_show_save_toast()
			var turn_timer = get_tree().create_timer(1.6)
			turn_timer.timeout.connect(func(): 
				show_event_popup(active_team["name"] + " ist dran!", active_team["color"])
				if active_team.has("players"):
					for p in active_team["players"]:
						if p.has("character"):
							AudioManager.play_character_sfx(p["character"], "turn")
			)
		else:
			show_event_popup(active_team["name"] + " ist dran!", active_team["color"])
			if active_team.has("players"):
				for p in active_team["players"]:
					if p.has("character"):
						AudioManager.play_character_sfx(p["character"], "turn")
			
	# Jetzt können wir den minigame_index zurücksetzen, damit die Animation nicht bei Overlay-Updates neu triggert
	NetworkManager.current_minigame_index = -1
	_connect_buttons_sfx(self)

func _show_save_toast():
	var toast = Label.new()
	toast.text = "SPIELSTAND GESPEICHERT"
	toast.add_theme_font_size_override("font_size", 24)
	toast.add_theme_color_override("font_color", Color(1.0, 0.92, 0.68, 1.0))
	toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	toast.add_theme_constant_override("outline_size", 6)
	toast.position = Vector2(1920 - 420, 24)
	toast.modulate.a = 0.0
	add_child(toast)
	
	var tw = create_tween()
	tw.tween_property(toast, "modulate:a", 1.0, 0.3)
	tw.tween_interval(1.8)
	tw.tween_property(toast, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): toast.queue_free())

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
			thumb_tex = _get_thumbnail_safe("res://assets/minigames/10sec/10sec_thumbnail.png")
		elif "CookieClickers" in scene_file or "TipFast" in scene_file or "CookieClicker" in scene_file:
			thumb_tex = _get_thumbnail_safe("res://assets/minigames/cookie_clickers/cookie_clickers_thumbnail.png")
			if not thumb_tex:
				thumb_tex = _get_thumbnail_safe("res://assets/minigames/tip_fast/tip_fast_thumbnail.png")
		elif "VideoGameQuiz" in scene_file:
			thumb_tex = _get_thumbnail_safe("res://assets/minigames/video_game_quiz/video_game_quiz_thumbnail.png")
		elif "FireEmblem" in scene_file:
			thumb_tex = _get_thumbnail_safe("res://assets/minigames/fire_emblem/fire_emblem_thumbnail.png")
		elif "IceClimbers" in scene_file:
			thumb_tex = _get_thumbnail_safe("res://assets/minigames/ice_climbers/ice_climbers_thumbnail.png")
		elif "Hexagon" in scene_file:
			thumb_tex = _get_thumbnail_safe("res://assets/minigames/hexagon/hexagon_thumbnail.png")
			if not thumb_tex:
				thumb_tex = _get_thumbnail_safe("res://assets/minigames/hexagon/hexagon_thumbnail.jpg")
		elif "BetBuddyExtreme" in scene_file or "BetBuddy" in scene_file:
			thumb_tex = _get_thumbnail_safe("res://assets/minigames/bet_buddy_extreme/bet_buddy_extreme_thumbnail.png")
			if not thumb_tex:
				thumb_tex = _get_thumbnail_safe("res://assets/minigames/bet_buddy_extreme/bet_buddy_extreme_thumbnail.jpg")
			
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
				
			# Schon gespieltes Spiel bleibt anklickbar zum Wiederholen!
			card.disabled = false
			card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			card.pressed.connect(_on_played_minigame_pressed.bind(i))
			
			var bg_panel = card.get_node_or_null("BackgroundPanel")
			if not bg_panel:
				bg_panel = card.find_child("BackgroundPanel", true, false)
			
			# 1. Thumbnail leicht abdunkeln, damit warme Töne (Gelb/Orange) nicht mit kühlen Teamfarben (Blau) zu Grau verschmelzen
			var status_tex = card.get_node_or_null("BackgroundPanel/StatusTexture")
			if not status_tex:
				status_tex = card.find_child("StatusTexture", true, false)
			if status_tex and thumb_tex:
				status_tex.modulate = Color(0.72, 0.72, 0.72, 1.0)
				
			# 2. Transparenter Farb-Wash über das Thumbnail legen (echtes Alpha-Blending statt destruktives Modulate)
			if bg_panel:
				var color_overlay = ColorRect.new()
				color_overlay.name = "WinnerColorOverlay"
				color_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
				color_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
				color_overlay.color = Color(winner_color.r, winner_color.g, winner_color.b, 0.52)
				bg_panel.add_child(color_overlay)
			
			# 3. Gewinner-Teamname ermitteln für Barrierefreiheit & sofortige Klarheit
			var winner_team_name = ""
			for t in NetworkManager.computed_teams:
				if t.get("color", Color.WHITE).is_equal_approx(winner_color):
					winner_team_name = t.get("name", "")
					break
			if winner_team_name == "":
				for idx in range(team_colors.size()):
					if team_colors[idx].is_equal_approx(winner_color):
						winner_team_name = "Team %d" % (idx + 1)
						break
			
			# 4. Team-Badge am unteren Rand der Karte einbetten
			if bg_panel and winner_team_name != "":
				var team_badge = PanelContainer.new()
				team_badge.name = "WinnerTeamBadge"
				team_badge.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
				team_badge.custom_minimum_size = Vector2(0, 30)
				team_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
				
				var badge_style = StyleBoxFlat.new()
				badge_style.bg_color = Color(0.04, 0.05, 0.09, 0.88)
				badge_style.border_width_top = 2
				badge_style.border_color = winner_color
				badge_style.corner_radius_bottom_left = 12
				badge_style.corner_radius_bottom_right = 12
				badge_style.anti_aliasing = false
				team_badge.add_theme_stylebox_override("panel", badge_style)
				
				var badge_label = Label.new()
				badge_label.text = winner_team_name
				badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				badge_label.add_theme_font_size_override("font_size", 16)
				badge_label.add_theme_color_override("font_color", winner_color)
				badge_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
				badge_label.add_theme_constant_override("outline_size", 6)
				badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
				team_badge.add_child(badge_label)
				
				bg_panel.add_child(team_badge)
				
			# 5. Punktzahl gut lesbar und zentriert anzeigen
			var points_label = Label.new()
			points_label.text = "+" + str(points_won)
			points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			points_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			points_label.offset_bottom = -14 # Leicht nach oben versetzt für perfekten Ausgleich mit dem Team-Badge
			points_label.add_theme_font_size_override("font_size", 48)
			points_label.add_theme_color_override("font_color", Color(1, 1, 1, 1)) # Weiss
			points_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1)) # Schwarze Kontur
			points_label.add_theme_constant_override("outline_size", 8)
			points_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			
			if bg_panel:
				bg_panel.add_child(points_label)
				
			# 6. Soliden Farbrahmen im Vordergrund aufziehen
			var border_overlay = card.get_node_or_null("BackgroundPanel/BorderOverlay")
			if not border_overlay:
				border_overlay = card.find_child("BorderOverlay", true, false)
			if border_overlay and bg_panel:
				var border_style = StyleBoxFlat.new()
				border_style.bg_color = Color(0, 0, 0, 0)
				border_style.border_width_left = 5
				border_style.border_width_top = 5
				border_style.border_width_right = 5
				border_style.border_width_bottom = 5
				border_style.border_color = winner_color
				border_style.corner_radius_top_left = 12
				border_style.corner_radius_top_right = 12
				border_style.corner_radius_bottom_right = 12
				border_style.corner_radius_bottom_left = 12
				border_style.anti_aliasing = false
				border_overlay.add_theme_stylebox_override("panel", border_style)
				bg_panel.move_child(border_overlay, bg_panel.get_child_count() - 1)
			
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

func _on_played_minigame_pressed(minigame_index: int):
	if is_transitioning:
		return
	_pending_repeat_index = minigame_index
	
	# Hole Informationen über das Spiel und den bisherigen Gewinner
	var winner_data = NetworkManager.minigame_winners.get(minigame_index, null)
	var points_won = 2
	var winner_team_name = "Team"
	if winner_data is Dictionary:
		points_won = winner_data.get("points", 2)
		var w_col = winner_data.get("color", Color.BLACK)
		for t in NetworkManager.computed_teams:
			if t.get("color", Color.WHITE).is_equal_approx(w_col):
				winner_team_name = t.get("name", "Team")
				break
	elif winner_data is Color:
		for t in NetworkManager.computed_teams:
			if t.get("color", Color.WHITE).is_equal_approx(winner_data):
				winner_team_name = t.get("name", "Team")
				break
	
	# Ermittle den Namen des Minispiels
	var game_name = "dieses Spiel"
	if minigame_index < NetworkManager.board_layout.size():
		var scene_path = NetworkManager.board_layout[minigame_index]
		var base = scene_path.get_file().get_basename()
		if "10Sec" in base:
			game_name = "10 Sekunden"
		elif "CookieClickers" in base or "TipFast" in base or "CookieClicker" in base:
			game_name = "Cookie Clickers"
		elif "VideoGameQuiz" in base:
			game_name = "Videospielquiz"
		elif "FireEmblem" in base:
			game_name = "Fire Emblem"
		elif "IceClimbers" in base:
			game_name = "Ice Climbers"
		elif "Hexagon" in base:
			game_name = "Hexagon"
		elif "BetBuddyExtreme" in base or "BetBuddy" in base:
			game_name = "Bet Buddy Extreme"
		elif "Quiz" in base or "Qualifikationsquiz" in base:
			game_name = "Quiz"
	
	if repeat_confirm_message:
		repeat_confirm_message.text = "Soll " + game_name + " (Feld " + str(minigame_index + 1) + ") wirklich wiederholt werden?\n\nDie bisher vergebenen +" + str(points_won) + " Punkte an " + winner_team_name + " werden zurückgesetzt und es kann einen neuen Gewinner geben."
	if repeat_confirm_overlay:
		repeat_confirm_overlay.visible = true

func _on_cancel_repeat_pressed():
	_pending_repeat_index = -1
	if repeat_confirm_overlay:
		repeat_confirm_overlay.visible = false

func _on_confirm_repeat_pressed():
	if repeat_confirm_overlay:
		repeat_confirm_overlay.visible = false
	if _pending_repeat_index == -1 or is_transitioning:
		return
	
	var minigame_index = _pending_repeat_index
	_pending_repeat_index = -1
	
	# 1. Bisher vergebene Punkte zurücksetzen
	if NetworkManager.minigame_winners.has(minigame_index):
		var winner_data = NetworkManager.minigame_winners[minigame_index]
		var points_won = 2
		var winner_color = Color.BLACK
		var selecting_color = Color(0, 0, 0, 0)
		
		if winner_data is Dictionary:
			points_won = winner_data.get("points", 2)
			winner_color = winner_data.get("color", Color.BLACK)
			selecting_color = winner_data.get("selecting_color", Color(0, 0, 0, 0))
		elif winner_data is Color:
			winner_color = winner_data
			
		# Punkte von den Spielern des bisherigen Gewinner-Teams abziehen
		for team in NetworkManager.computed_teams:
			if team.get("color", Color.WHITE).is_equal_approx(winner_color):
				for p in team.get("players", []):
					var p_id = -1
					if p is Dictionary and p.has("id"):
						p_id = int(p["id"])
					elif p is Dictionary and p.has("name"):
						for pid in NetworkManager.player_sessions.keys():
							if NetworkManager.player_sessions[pid].get("name") == p["name"]:
								p_id = int(pid)
								break
					if p_id != -1 and NetworkManager.player_sessions.has(p_id):
						NetworkManager.player_sessions[p_id]["score"] = max(0, NetworkManager.player_sessions[p_id]["score"] - points_won)
						var new_score = NetworkManager.player_sessions[p_id]["score"]
						# Punkte-Update an den Controller senden
						NetworkManager.send_to_player(p_id, {
							"type": "score_update",
							"score": new_score
						})
		
		# Ursprüngliches Auswähl-Team wiederherstellen (für den 3-Punkte-Bonus, falls gespeichert)
		if selecting_color.a > 0.0:
			NetworkManager.current_selecting_team_color = selecting_color
		
		# Aus den gewerteten Spielen entfernen
		NetworkManager.minigame_winners.erase(minigame_index)
	
	# Markiere als Wiederholung, damit der Runden-Zähler nicht erhöht wird
	NetworkManager.is_replaying_minigame = true
	NetworkManager.current_minigame_index = minigame_index
	
	# Starte den Szenenübergang
	_start_minigame_transition(minigame_index)

func _on_minigame_pressed(minigame_index: int):
	if is_transitioning:
		return
	
	print("Lade Minispiel Index ", minigame_index)
	NetworkManager.current_minigame_index = minigame_index
	NetworkManager.is_replaying_minigame = false
	
	# Speichere welches Team das Spiel ausgesucht hat (bevor wir den Turn-Zaehler erhoehen!)
	if NetworkManager.computed_teams.size() > 0:
		var selecting_index = NetworkManager.current_turn_number % NetworkManager.computed_teams.size()
		NetworkManager.current_selecting_team_color = NetworkManager.computed_teams[selecting_index]["color"]
	
	# Erhoehe den Runden-Zaehler fuer die naechste Wahl
	NetworkManager.current_turn_number += 1
	
	_start_minigame_transition(minigame_index)

func _start_minigame_transition(minigame_index: int):
	if is_transitioning:
		return
	is_transitioning = true
	
	if minigame_index < NetworkManager.board_layout.size():
		var scene_path = NetworkManager.board_layout[minigame_index]
		
		# Wenn Spieler auf dem Feld sind: lass alle in ihre Röhre gehen
		var characters_to_pipe = []
		for char_inst in spawned_characters:
			if is_instance_valid(char_inst):
				characters_to_pipe.append(char_inst)
				
		if characters_to_pipe.size() > 0:
			AudioManager.stop_music(0.8)
			var pending_count = characters_to_pipe.size()
			for char_inst in characters_to_pipe:
				char_inst.pipe_entered.connect(func():
					pending_count -= 1
				)
				# 140 Pixel nach unten in die Röhre einsaugen
				char_inst.enter_pipe(140.0, 130.0, false)
				
			# Warte bis alle Spieler in der Röhre verschwunden sind (Sicherheits-Timeout: 1.5s)
			var max_wait = 1.5
			while pending_count > 0 and max_wait > 0.0:
				await get_tree().process_frame
				max_wait -= get_process_delta_time()
				
			# Kurze Pause nach dem Abtauchen aller Spieler
			await get_tree().create_timer(0.2).timeout
			
		get_tree().change_scene_to_file(scene_path)
	else:
		print("ERROR: Invalider Minispiel-Index oder leeres Layout!")
		is_transitioning = false

func _spawn_players():
	var players = []
	for p_id in NetworkManager.player_sessions.keys():
		var p_data = NetworkManager.player_sessions[p_id].duplicate()
		p_data["id"] = int(p_id)
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
		
	var spacing = 180.0 # Horizontaler Abstand zwischen den Charakteren
	if num_players > 8:
		spacing = clamp(1600.0 / (num_players - 1), 130.0, 180.0)
	var center_x = 960.0 # Bildschirmmitte (1920 / 2)
	var start_x = center_x - (spacing * (num_players - 1)) / 2.0
	var pipe_y = 1010.0 # Röhre ragt aus dem Boden (TileMap3 bei y=1024)
	var spawn_y = 882.0 # Charakter steht auf dem Röhrenrand (y=946)
	
	spawned_characters.clear()
	var spawned_player_data = []
	
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
		
		var char_x = start_x + (i * spacing)
		
		# Röhre unter dem Spieler spawnen (in Teamfarbe, z_index 1)
		var pipe_inst = pipe_scene.instantiate()
		pipe_inst.position = Vector2(char_x, pipe_y)
		pipe_inst.z_index = 1
		if pipe_inst.has_method("set_team_color"):
			pipe_inst.set_team_color(team_color)
			
		# Prüfe, ob dieser Spieler im Qualifikationsquiz Bonuspunkte geholt hat (+3, +2, +1)
		var p_id = int(p_data.get("id", -1))
		if p_id == -1:
			for pid in NetworkManager.player_sessions.keys():
				if NetworkManager.player_sessions[pid].get("name", "") == p_data.get("name", ""):
					p_id = int(pid)
					break
		var bonus = NetworkManager.quiz_bonus_points.get(p_id, 0)
		if pipe_inst.has_method("set_bonus_points"):
			pipe_inst.set_bonus_points(bonus)
			
		add_child(pipe_inst)
		
		var char_scene = load(scene_path)
		if char_scene:
			var char_instance = char_scene.instantiate()
			char_instance.position = Vector2(char_x, spawn_y)
			char_instance.z_index = 0 # Hinter der Röhre (z_index 1)
			char_instance.is_in_cutscene = true # Schaltet Tastatursteuerung aus
			add_child(char_instance)
			spawned_characters.append(char_instance)
			spawned_player_data.append({
				"instance": char_instance,
				"is_active": is_active,
				"x": char_x
			})
			
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
			
	# Regel für Blickrichtungen & Aktionen anwenden:
	# Alle Spieler schauen auf dem MainBoard immer nach rechts.
	# Spieler, die dran sind: trinken weiterhin.
	for data in spawned_player_data:
		var char_inst = data["instance"]
		var is_act = data["is_active"]
		
		char_inst.face_right()
		if is_act:
			get_tree().create_timer(0.2).timeout.connect(func():
				if is_instance_valid(char_inst):
					char_inst.face_right()
					char_inst.play_drink()
			)
		else:
			get_tree().create_timer(0.2).timeout.connect(func():
				if is_instance_valid(char_inst):
					char_inst.face_right()
			)

func _get_character_scene_path(character_name: String) -> String:
	var formatted_name = character_name
	if formatted_name == "Cedi":
		formatted_name = "Cedric"
		
	var path = "res://scenes/characters/" + formatted_name + ".tscn"
	if ResourceLoader.exists(path):
		return path
		
	# Fallback, falls die spezifische .tscn nicht existiert
	return "res://scenes/characters/Cedric.tscn"

# --- QR Code Steuerung ---

func _on_show_qr_button_pressed():
	if is_transitioning:
		return
	AudioManager.play_sfx("button_press")
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
	
	if not NetworkManager.qr_code_ready.is_connected(_on_qr_ready):
		NetworkManager.qr_code_ready.connect(_on_qr_ready)
		
	var http_qr = qr_http_request if qr_http_request else find_child("QRHTTPRequest", true, false)
	var tex = NetworkManager.get_or_request_qr_code(http_qr)
	if tex != null:
		var qr_rect = qr_texture_rect if qr_texture_rect else find_child("QRCodeRect", true, false)
		if qr_rect:
			qr_rect.texture = tex

func _on_qr_ready(texture: ImageTexture):
	var qr_rect = qr_texture_rect if qr_texture_rect else find_child("QRCodeRect", true, false)
	if qr_rect and is_instance_valid(qr_rect):
		qr_rect.texture = texture


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

func _get_thumbnail_safe(png_path: String) -> Texture2D:
	if ResourceLoader.exists(png_path):
		var loaded = load(png_path)
		if loaded is Texture2D:
			return loaded
	if FileAccess.file_exists(png_path):
		var bytes = FileAccess.get_file_as_bytes(png_path)
		var img = Image.new()
		if img.load_png_from_buffer(bytes) == OK:
			return ImageTexture.create_from_image(img)
	return null

func _get_fire_emblem_thumbnail() -> Texture2D:
	return _get_thumbnail_safe("res://assets/minigames/fire_emblem/fire_emblem_thumbnail.png")

func _get_ice_climbers_thumbnail() -> Texture2D:
	return _get_thumbnail_safe("res://assets/minigames/ice_climbers/ice_climbers_thumbnail.png")
