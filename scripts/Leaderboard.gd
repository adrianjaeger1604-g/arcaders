extends Control

const MinigameResultHelper = preload("res://scripts/minigames/MinigameResultHelper.gd")

@onready var player_list = $CenterContainer/VBoxContainer/PlayerList
@onready var next_phase_btn = $CenterContainer/VBoxContainer/NextPhaseButton
@onready var title_label = $CenterContainer/VBoxContainer/Title

var winner_names: Array = []

var max_score_possible = 1 # Hoechste Punktzahl der Runde = voller Balken

# Dauer, die der Balken mit der hoechsten Punktzahl zum Fuellen braucht.
# Alle Balken steigen gleich schnell -> niedrigere stoppen frueher, der Spitzenreiter zuletzt.
const RISE_DURATION = 3.5

func _ready():
	AudioManager.stop_music() # Intro-Musik nur bis zum Quiz-Start
	next_phase_btn.pressed.connect(_on_next_phase_pressed)
	_connect_buttons_sfx(self)
	
	var bg_tilemap = get_node_or_null("BackgroundTileMap")
	if bg_tilemap:
		bg_tilemap.visible = false
	var gameplay_bg = get_node_or_null("GameplayBG")
	if gameplay_bg:
		if not gameplay_bg.texture:
			gameplay_bg.texture = load("res://assets/quiz/qualifikationsquiz_bg.jpg")
		gameplay_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		gameplay_bg.visible = true
	
	# Hoechste Punktzahl der Runde bestimmt den vollen Balken
	var actual_max_score = 0
	for p_id in NetworkManager.player_sessions:
		var score = NetworkManager.player_sessions[p_id].get("score", 0)
		if score > actual_max_score:
			actual_max_score = score
			
	max_score_possible = max(1, actual_max_score) # Division durch 0 vermeiden
	
	_populate_leaderboard()
	
	# Aufsteigender Spannungs-Sound, synchron zum Balken des Spitzenreiters
	if actual_max_score > 0:
		AudioManager.play_rising_sfx(RISE_DURATION)

func _connect_buttons_sfx(node: Node):
	if node is Button:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func _populate_leaderboard():
	# Clean up any existing placeholders
	for child in player_list.get_children():
		child.queue_free()
		
	# Spieler in fester Reihenfolge (nach Spieler-ID) anzeigen,
	# damit der Erstplatzierte nicht von vornherein oben steht!
	var players = []
	for p_id in NetworkManager.player_sessions:
		players.append(NetworkManager.player_sessions[p_id])
		
	players.sort_custom(func(a, b): return a.get("id", 0) < b.get("id", 0))
	
	# 1 Spalte zentriert für bis zu 4 Spieler, ab 5 Spieler 2 Spalten
	player_list.columns = 2 if players.size() > 4 else 1
	player_list.add_theme_constant_override("v_separation", 16)
	player_list.add_theme_constant_override("h_separation", 36 if player_list.columns == 2 else 20)
	
	# Gewinner bestimmen (bei Gleichstand mehrere)
	winner_names.clear()
	var top = -1
	for p in players:
		var s = p.get("score", 0)
		if s > top:
			top = s
	if top > 0:
		for p in players:
			if p.get("score", 0) == top:
				winner_names.append(p.get("name", "Unbekannt"))
	
	var i = 0
	for p_data in players:
		_create_player_bar(p_data, i)
		i += 1

func _create_player_bar(p_data: Dictionary, index: int):
	var p_name = p_data.get("name", "Unbekannt")
	var target_score = p_data.get("score", 0)
	var is_two_cols = player_list.columns == 2
	
	# Create a container for the row
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10 if is_two_cols else 12)
	
	var left_box_w = 110 if is_two_cols else 130
	var bar_w = 320 if is_two_cols else 460
	
	# Left Content (Name + Character)
	var left_box = HBoxContainer.new()
	left_box.alignment = BoxContainer.ALIGNMENT_CENTER
	left_box.custom_minimum_size = Vector2(left_box_w, 0)
	
	# Character + Name Box
	var char_name_vbox = VBoxContainer.new()
	char_name_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	char_name_vbox.custom_minimum_size = Vector2(left_box_w, 0)
	char_name_vbox.add_theme_constant_override("separation", 4)
	
	# Character Icon (in einem zentrierten Control, damit es springen kann,
	# ohne dass der Container die Position zuruecksetzt)
	var char_holder = Control.new()
	char_holder.custom_minimum_size = Vector2(64, 64)
	char_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var char_icon = TextureRect.new()
	char_icon.size = Vector2(64, 64)
	char_icon.position = Vector2.ZERO
	char_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	char_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	char_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var character_name = p_data.get("character", "")
	if character_name == "" or not NetworkManager.character_textures.has(character_name):
		character_name = "Cedi"
		
	if NetworkManager.character_textures.has(character_name):
		char_icon.texture = NetworkManager.character_textures[character_name]
	char_holder.add_child(char_icon)
	char_name_vbox.add_child(char_holder)
	
	# Name Label (direkt unter dem Charakter, wird bei Überlänge mit '...' auspunktiert)
	var name_label = Label.new()
	name_label.text = p_name
	name_label.add_theme_font_size_override("font_size", 18 if is_two_cols else 22)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(left_box_w, 0)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	name_label.add_theme_constant_override("outline_size", 6)
	char_name_vbox.add_child(name_label)
	
	left_box.add_child(char_name_vbox)
	
	row.add_child(left_box)
	
	# Progress Bar Container
	var bar_data = MinigameResultHelper.create_styled_bar(max_score_possible, _get_bar_color(p_data), Vector2(bar_w, 40))
	var bar = bar_data["bar"]
	var score_label = bar_data["label"]
	score_label.text = "0 Punkte"
	score_label.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.06, 0.96))
	score_label.add_theme_constant_override("outline_size", 6)
	row.add_child(bar_data["container"])
	
	# Symmetrischer Ausgleichs-Spacer rechts NUR bei 1 Spalte
	if not is_two_cols:
		var right_spacer = MinigameResultHelper.create_balancing_spacer(left_box.custom_minimum_size.x)
		row.add_child(right_spacer)
	
	player_list.add_child(row)
	
	# Alle Balken starten gleichzeitig und steigen mit gleicher Geschwindigkeit.
	# Die Dauer ist proportional zur Punktzahl -> der Spitzenreiter steigt am laengsten.
	var duration = RISE_DURATION * (float(target_score) / float(max_score_possible))
	if target_score <= 0:
		return
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(bar, "value", float(target_score), duration).set_trans(Tween.TRANS_LINEAR)
	tween.tween_method(func(val: float): score_label.text = str(int(round(val))) + " Punkte", 0.0, float(target_score), duration).set_trans(Tween.TRANS_LINEAR)
	
	# Kleiner "Pop" wenn der Balken sein Ziel erreicht
	bar.pivot_offset = bar.custom_minimum_size / 2.0
	var pop = create_tween()
	pop.tween_interval(duration)
	pop.tween_property(bar, "scale", Vector2(1.06, 1.15), 0.08)
	pop.tween_property(bar, "scale", Vector2.ONE, 0.15)

	# Gewinner(-innen): kurz springen, danach Idle-Animation + Titel
	if p_name in winner_names:
		var t = create_tween()
		t.tween_interval(duration + 0.1)
		t.tween_callback(func(): _celebrate_winner(char_icon, character_name))
		if p_name == winner_names[0]:
			t.tween_callback(_show_winner_title)

# Einheitliche Balkenfarbe fuer Einzelspiele: kraeftiges, dunkles Violett (guter Kontrast zu Weiss)
const SOLO_BAR_COLOR = Color(0.42, 0.24, 0.82, 1)

# Liefert die Teamfarbe des Spielers, falls Teams existieren - sonst die Einheitsfarbe.
func _get_bar_color(p_data: Dictionary) -> Color:
	var p_name = p_data.get("name", "")
	for team in NetworkManager.computed_teams:
		for member in team.get("players", []):
			if member.get("name", "") == p_name:
				return team.get("color", SOLO_BAR_COLOR)
	return SOLO_BAR_COLOR

# Ermittelt den Asset-Ordnernamen (z.B. "cedric") aus der Idle-Textur des Charakters
func _get_sprite_base(character_name: String) -> String:
	return MinigameResultHelper.get_sprite_base(character_name)

func _load_idle_frames(base: String) -> Array:
	return MinigameResultHelper.load_idle_frames(base)

func _load_drink_frames(base: String) -> Array:
	return MinigameResultHelper.load_drink_frames(base)

func _celebrate_winner(char_icon: TextureRect, character_name: String):
	MinigameResultHelper.celebrate_winner(char_icon, character_name)

func _show_winner_title():
	AudioManager.play_sfx("confetti-pop-sound-effect")
	if NetworkManager.team_assignment_mode == "manual":
		title_label.text = "Es gibt Punkte für die ersten drei Plätze!"
	else:
		if winner_names.size() == 1:
			title_label.text = "%s gewinnt!" % winner_names[0]
		else:
			title_label.text = "Gleichstand: %s!" % " & ".join(PackedStringArray(winner_names))
	title_label.pivot_offset = title_label.size / 2.0
	title_label.scale = Vector2(0.5, 0.5)
	title_label.modulate.a = 0.0
	var t = create_tween().set_parallel(true)
	t.tween_property(title_label, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(title_label, "modulate:a", 1.0, 0.25)



func _on_next_phase_pressed():
	print("Proceeding to next phase...")
	# Handys in Warte-Screen schicken
	NetworkManager.broadcast({
		"type": "state_change",
		"state": "waiting"
	})
	# Berechne Bonuspunkte & initialisiere Turnier-Scores
	NetworkManager.finalize_quiz_ranking_and_bonus()
	# Transition to Team Display
	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/TeamDisplay.tscn")
