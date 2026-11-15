extends Control

@onready var teams_container: HFlowContainer = $CenterContainer/VBox/ScrollContainer/TeamsContainer
@onready var confirm_button: Button = $CenterContainer/VBox/ConfirmButton
@onready var status_label: Label = $CenterContainer/VBox/StatusLabel
@onready var team_count_label: Label = $CenterContainer/VBox/ControlsBar/TeamCountLabel
@onready var btn_auto_distribute: Button = $CenterContainer/VBox/ControlsBar/BtnAutoDistribute

const MAX_TEAM_SIZE: int = 2

var team_definitions = [
	{"name": "Team Rot", "color": Color(0.95, 0.35, 0.35, 1.0)},
	{"name": "Team Blau", "color": Color(0.35, 0.65, 1.0, 1.0)},
	{"name": "Team Grün", "color": Color(0.35, 0.85, 0.45, 1.0)},
	{"name": "Team Gelb", "color": Color(1.0, 0.9, 0.3, 1.0)},
	{"name": "Team Lila", "color": Color(0.75, 0.45, 0.95, 1.0)},
	{"name": "Team Orange", "color": Color(1.0, 0.6, 0.25, 1.0)}
]

var num_teams: int = 2
# Jedes Team hat genau MAX_TEAM_SIZE (2) Slots: team_slots[t_idx] = [player_dict_or_null, player_dict_or_null]
var team_slots: Array = []
var players: Array = []
var selected_slot = null # Dictionary {"team": int, "slot": int} oder null
var slot_nodes: Dictionary = {} # "team_slot" -> SlotControl

func _ready():
	if GlobalSettingsLayer:
		GlobalSettingsLayer.show_gear_button()
		
	AudioManager.play_music("intro")
	_connect_buttons_sfx(self)
	
	_load_players()
	
	# Anzahl Teams ergibt sich strikt aus 2er-Teams (keine 3er-Teams möglich)
	var needed_teams = int(ceil(players.size() / float(MAX_TEAM_SIZE)))
	num_teams = clampi(max(needed_teams, 2), 1, team_definitions.size())
	if players.size() < 2:
		num_teams = 1
		
	_distribute_players_into_slots(false)
	
	btn_auto_distribute.icon = PixelIcon.get_icon_texture("dice")
	btn_auto_distribute.expand_icon = false
	btn_auto_distribute.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	btn_auto_distribute.add_theme_constant_override("h_separation", 8)
	btn_auto_distribute.pressed.connect(_on_auto_distribute_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	
	_rebuild_ui()

func _connect_buttons_sfx(node: Node):
	if node is Button:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func _load_players():
	players.clear()
	for p_id in NetworkManager.player_sessions.keys():
		var p_data = NetworkManager.player_sessions[p_id].duplicate()
		p_data["id"] = int(p_id)
		players.append(p_data)
		
	# Fallback für Tests im Editor, falls keine Spieler verbunden sind
	if players.is_empty():
		players = [
			{"id": 1, "name": "Spieler 1", "character": "Cedi", "score": 0},
			{"id": 2, "name": "Spieler 2", "character": "Aaron", "score": 0},
			{"id": 3, "name": "Spieler 3", "character": "Jan", "score": 0},
			{"id": 4, "name": "Spieler 4", "character": "Paul", "score": 0}
		]

func _distribute_players_into_slots(shuffle_list: bool):
	team_slots.clear()
	for t_idx in range(num_teams):
		var slots_for_team = []
		for s_idx in range(MAX_TEAM_SIZE):
			slots_for_team.append(null)
		team_slots.append(slots_for_team)
		
	var ordered = players.duplicate()
	if shuffle_list:
		ordered.shuffle()
		
	# Verteile Spieler gleichmäßig (max. 2 pro Team)
	var p_idx = 0
	for s_idx in range(MAX_TEAM_SIZE):
		for t_idx in range(num_teams):
			if p_idx < ordered.size():
				team_slots[t_idx][s_idx] = ordered[p_idx]
				p_idx += 1

func _on_auto_distribute_pressed():
	selected_slot = null
	_distribute_players_into_slots(true)
	_rebuild_ui()

func _swap_slots(from_team: int, from_slot: int, to_team: int, to_slot: int):
	if from_team == to_team and from_slot == to_slot:
		return
	if from_team < 0 or from_team >= team_slots.size() or to_team < 0 or to_team >= team_slots.size():
		return
		
	var temp = team_slots[from_team][from_slot]
	team_slots[from_team][from_slot] = team_slots[to_team][to_slot]
	team_slots[to_team][to_slot] = temp
	
	# Falls in einem Team dadurch Slot 0 leer und Slot 1 belegt ist, rücke Slot 1 nach oben auf Slot 0
	for t_idx in [from_team, to_team]:
		if team_slots[t_idx][0] == null and team_slots[t_idx][1] != null:
			team_slots[t_idx][0] = team_slots[t_idx][1]
			team_slots[t_idx][1] = null
			
	selected_slot = null
	AudioManager.play_sfx("button_press")
	_rebuild_ui()

func _on_slot_clicked(t_idx: int, s_idx: int):
	var clicked_player = team_slots[t_idx][s_idx]
	
	# Wenn noch kein Spieler ausgewählt ist, wähle diesen aus (sofern dort ein Spieler sitzt)
	if selected_slot == null:
		if clicked_player != null:
			selected_slot = {"team": t_idx, "slot": s_idx}
			AudioManager.play_sfx("button_press")
			_update_selection_styles()
		return
		
	# Wenn derselbe Slot nochmal geklickt wurde -> Auswahl aufheben
	if selected_slot["team"] == t_idx and selected_slot["slot"] == s_idx:
		selected_slot = null
		AudioManager.play_sfx("button_press")
		_update_selection_styles()
		return
		
	# Anderen Slot geklickt -> Tausche beide Plätze!
	_swap_slots(selected_slot["team"], selected_slot["slot"], t_idx, s_idx)

func _on_team_card_dropped(from_team: int, from_slot: int, target_team: int):
	if from_team == target_team:
		return
	# Wenn das Ziel-Team noch einen freien zweiten Platz hat, dorthin verschieben,
	# ansonsten mit dem zweiten (oder ersten) Spieler des Ziel-Teams tauschen.
	if team_slots[target_team][1] == null:
		_swap_slots(from_team, from_slot, target_team, 1)
	else:
		_swap_slots(from_team, from_slot, target_team, 1)

# -------------------------------------------------------------------
# Drag & Drop Hilfsklassen
# -------------------------------------------------------------------
class PlayerSlotRow extends PanelContainer:
	var player_data = null # Dictionary oder null (freier Slot)
	var team_idx: int = 0
	var slot_idx: int = 0
	var swap_callback: Callable
	var click_callback: Callable
	var is_drag_hovering: bool = false
	var press_pos: Vector2 = Vector2.ZERO
	var was_pressed: bool = false
	var normal_style: StyleBoxFlat
	var selected_style: StyleBoxFlat
	var hover_drop_style: StyleBoxFlat
	var is_currently_selected: bool = false
	
	func setup(p_data, t_idx: int, s_idx: int, on_swap: Callable, on_click: Callable):
		player_data = p_data
		team_idx = t_idx
		slot_idx = s_idx
		swap_callback = on_swap
		click_callback = on_click
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if p_data != null else Control.CURSOR_ARROW
		
		normal_style = StyleBoxFlat.new()
		normal_style.bg_color = Color(0.14, 0.16, 0.22, 0.95) if p_data != null else Color(0.11, 0.13, 0.18, 0.45)
		normal_style.border_width_left = 2
		normal_style.border_width_top = 2
		normal_style.border_width_right = 2
		normal_style.border_width_bottom = 2
		normal_style.border_color = Color(0.32, 0.38, 0.50, 0.85) if p_data != null else Color(0.30, 0.34, 0.44, 0.45)
		normal_style.corner_radius_top_left = 8
		normal_style.corner_radius_top_right = 8
		normal_style.corner_radius_bottom_right = 8
		normal_style.corner_radius_bottom_left = 8
		normal_style.content_margin_left = 12
		normal_style.content_margin_right = 12
		normal_style.content_margin_top = 8
		normal_style.content_margin_bottom = 8
		
		selected_style = normal_style.duplicate()
		selected_style.bg_color = Color(0.24, 0.30, 0.46, 1.0)
		selected_style.border_width_left = 3
		selected_style.border_width_top = 3
		selected_style.border_width_right = 3
		selected_style.border_width_bottom = 3
		selected_style.border_color = Color(1.0, 0.9, 0.3, 1.0)
		
		hover_drop_style = normal_style.duplicate()
		hover_drop_style.bg_color = Color(0.20, 0.38, 0.30, 0.98)
		hover_drop_style.border_width_left = 3
		hover_drop_style.border_width_top = 3
		hover_drop_style.border_width_right = 3
		hover_drop_style.border_width_bottom = 3
		hover_drop_style.border_color = Color(0.45, 1.0, 0.65, 1.0)
		
		_apply_current_style()
		mouse_exited.connect(func():
			if is_drag_hovering:
				is_drag_hovering = false
				_apply_current_style()
		)
		
	func set_selected(sel: bool):
		is_currently_selected = sel
		_apply_current_style()
		
	func _apply_current_style():
		if is_drag_hovering:
			add_theme_stylebox_override("panel", hover_drop_style)
		elif is_currently_selected:
			add_theme_stylebox_override("panel", selected_style)
		else:
			add_theme_stylebox_override("panel", normal_style)
			
	func _get_drag_data(_at_position: Vector2) -> Variant:
		if player_data == null:
			return null
		was_pressed = false
		var preview = _build_drag_preview()
		set_drag_preview(preview)
		return {
			"type": "player_slot_drag",
			"from_team": team_idx,
			"from_slot": slot_idx,
			"player_id": int(player_data.get("id", -1))
		}
		
	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		var ok = typeof(data) == TYPE_DICTIONARY and data.get("type") == "player_slot_drag"
		if ok:
			var same = (int(data.get("from_team", -1)) == team_idx and int(data.get("from_slot", -1)) == slot_idx)
			if not same and not is_drag_hovering:
				is_drag_hovering = true
				_apply_current_style()
			return not same
		return false
		
	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		is_drag_hovering = false
		_apply_current_style()
		if typeof(data) == TYPE_DICTIONARY and data.get("type") == "player_slot_drag":
			var f_team = int(data.get("from_team", -1))
			var f_slot = int(data.get("from_slot", -1))
			if f_team != -1 and f_slot != -1 and swap_callback.is_valid():
				swap_callback.call(f_team, f_slot, team_idx, slot_idx)
				
	func _gui_input(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				was_pressed = true
				press_pos = event.position
			else:
				if was_pressed and event.position.distance_to(press_pos) < 12.0:
					if click_callback.is_valid():
						click_callback.call(team_idx, slot_idx)
				was_pressed = false
				
	func _build_drag_preview() -> Control:
		var preview_panel = PanelContainer.new()
		preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var p_style = StyleBoxFlat.new()
		p_style.bg_color = Color(0.18, 0.24, 0.36, 0.96)
		p_style.border_width_left = 3
		p_style.border_width_top = 3
		p_style.border_width_right = 3
		p_style.border_width_bottom = 3
		p_style.border_color = Color(1.0, 0.9, 0.3, 1.0)
		p_style.corner_radius_top_left = 8
		p_style.corner_radius_top_right = 8
		p_style.corner_radius_bottom_right = 8
		p_style.corner_radius_bottom_left = 8
		p_style.content_margin_left = 14
		p_style.content_margin_right = 18
		p_style.content_margin_top = 8
		p_style.content_margin_bottom = 8
		preview_panel.add_theme_stylebox_override("panel", p_style)
		
		var hbox = HBoxContainer.new()
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_theme_constant_override("separation", 10)
		
		var icon = TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.custom_minimum_size = Vector2(44, 44)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var char_name = player_data.get("character", "Cedi")
		if NetworkManager.character_textures.has(char_name):
			icon.texture = NetworkManager.character_textures[char_name]
		hbox.add_child(icon)
		
		var lbl = Label.new()
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.text = player_data.get("name", "Spieler")
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		hbox.add_child(lbl)
		hbox.add_child(PixelIcon.create("swap", "S"))
		
		preview_panel.add_child(hbox)
		
		var wrapper = Control.new()
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(preview_panel)
		preview_panel.position = -Vector2(90, 28)
		return wrapper

class TeamDropCard extends PanelContainer:
	var team_idx: int
	var drop_callback: Callable
	
	func setup(t_idx: int, on_drop: Callable):
		team_idx = t_idx
		drop_callback = on_drop
		mouse_filter = Control.MOUSE_FILTER_PASS
		
	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return typeof(data) == TYPE_DICTIONARY and data.get("type") == "player_slot_drag" and int(data.get("from_team", -1)) != team_idx
		
	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if typeof(data) == TYPE_DICTIONARY and data.get("type") == "player_slot_drag":
			var f_team = int(data.get("from_team", -1))
			var f_slot = int(data.get("from_slot", -1))
			if f_team != -1 and f_slot != -1 and drop_callback.is_valid():
				drop_callback.call(f_team, f_slot, team_idx)

func _rebuild_ui():
	team_count_label.text = "Teams: %d (Max. 2 Spieler pro Team)" % num_teams
	slot_nodes.clear()
	
	for child in teams_container.get_children():
		child.queue_free()
		
	for t_idx in range(num_teams):
		var t_def = team_definitions[t_idx]
		var team_panel = _create_team_card(t_idx, t_def)
		teams_container.add_child(team_panel)
		
	_update_selection_styles()
	_validate_teams()

func _update_selection_styles():
	for key in slot_nodes:
		var node: PlayerSlotRow = slot_nodes[key]
		if not is_instance_valid(node):
			continue
		var is_sel = (selected_slot != null and selected_slot["team"] == node.team_idx and selected_slot["slot"] == node.slot_idx)
		node.set_selected(is_sel)
		
	if selected_slot != null:
		var sel_p = team_slots[selected_slot["team"]][selected_slot["slot"]]
		var p_name = sel_p.get("name", "Spieler") if sel_p != null else "Spieler"
		status_label.text = "'%s' ausgewählt — klicke auf einen anderen Spieler zum Tauschen!" % p_name
		status_label.modulate = Color(1.0, 0.9, 0.35, 1.0)
		status_label.visible = true
	else:
		_validate_teams()

func _create_team_card(t_idx: int, t_def: Dictionary) -> Control:
	var panel = TeamDropCard.new()
	panel.setup(t_idx, _on_team_card_dropped)
	panel.custom_minimum_size = Vector2(370, 230)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.18, 0.95)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = t_def["color"]
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_theme_constant_override("separation", 12)
	
	# Header
	var header = PanelContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h_style = StyleBoxFlat.new()
	h_style.bg_color = t_def["color"]
	h_style.corner_radius_top_left = 7
	h_style.corner_radius_top_right = 7
	h_style.corner_radius_bottom_left = 4
	h_style.corner_radius_bottom_right = 4
	h_style.content_margin_top = 8
	h_style.content_margin_bottom = 8
	header.add_theme_stylebox_override("panel", h_style)
	
	var header_lbl = Label.new()
	header_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_lbl.text = t_def["name"]
	header_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_lbl.add_theme_font_size_override("font_size", 24)
	header_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	header_lbl.add_theme_constant_override("outline_size", 4)
	header_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	header.add_child(header_lbl)
	vbox.add_child(header)
	
	# 2 feste Spieler-Slots pro Team (verhindert 3er-Teams)
	var slots_box = VBoxContainer.new()
	slots_box.mouse_filter = Control.MOUSE_FILTER_PASS
	slots_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slots_box.add_theme_constant_override("separation", 10)
	
	for s_idx in range(MAX_TEAM_SIZE):
		var p_data = team_slots[t_idx][s_idx]
		var slot_row = _create_slot_row(p_data, t_idx, s_idx)
		slots_box.add_child(slot_row)
		slot_nodes["%d_%d" % [t_idx, s_idx]] = slot_row
		
	vbox.add_child(slots_box)
	panel.add_child(vbox)
	return panel

func _create_slot_row(player, t_idx: int, s_idx: int) -> PlayerSlotRow:
	var row_panel = PlayerSlotRow.new()
	row_panel.custom_minimum_size = Vector2(0, 68)
	row_panel.setup(player, t_idx, s_idx, _swap_slots, _on_slot_clicked)
	
	var hbox = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 12)
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	
	if player != null:
		var grip_icon = PixelIcon.create("grip", "S", Color(0.75, 0.8, 0.9, 0.85))
		grip_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(grip_icon)
		
		var icon = TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.custom_minimum_size = Vector2(46, 46)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var char_name = player.get("character", "Cedi")
		if char_name == "" or not NetworkManager.character_textures.has(char_name):
			char_name = "Cedi"
		if NetworkManager.character_textures.has(char_name):
			icon.texture = NetworkManager.character_textures[char_name]
		hbox.add_child(icon)
		
		var text_vbox = VBoxContainer.new()
		text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		text_vbox.add_theme_constant_override("separation", 0)
		
		var name_lbl = Label.new()
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_lbl.text = player.get("name", "Unbekannt")
		name_lbl.add_theme_font_size_override("font_size", 20)
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		text_vbox.add_child(name_lbl)
		
		var char_tag = Label.new()
		char_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		char_tag.text = "[" + char_name + "]"
		char_tag.add_theme_font_size_override("font_size", 14)
		char_tag.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 0.75))
		text_vbox.add_child(char_tag)
		
		hbox.add_child(text_vbox)
		
		var swap_hint = PixelIcon.create("swap", "S", Color(0.95, 0.85, 0.4, 0.85))
		swap_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(swap_hint)
	else:
		var empty_lbl = Label.new()
		empty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_lbl.text = "— Freier Platz (Hierhin ziehen) —"
		empty_lbl.add_theme_font_size_override("font_size", 17)
		empty_lbl.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8, 0.6))
		hbox.add_child(empty_lbl)
		
	row_panel.add_child(hbox)
	return row_panel

func _validate_teams():
	var empty_teams = 0
	for t_idx in range(num_teams):
		var count = 0
		for s_idx in range(MAX_TEAM_SIZE):
			if team_slots[t_idx][s_idx] != null:
				count += 1
		if count == 0:
			empty_teams += 1
			
	if empty_teams > 0:
		status_label.text = "Achtung: %d Team(s) sind noch leer!" % empty_teams
		status_label.modulate = Color(1.0, 0.4, 0.3, 1.0)
		status_label.visible = true
		confirm_button.disabled = true
	else:
		status_label.text = ""
		status_label.visible = false
		confirm_button.disabled = false

func _on_confirm_pressed():
	NetworkManager.computed_teams.clear()
	
	for t_idx in range(num_teams):
		var t_def = team_definitions[t_idx]
		var team_data = {
			"name": t_def["name"],
			"color": t_def["color"],
			"players": []
		}
		
		for s_idx in range(MAX_TEAM_SIZE):
			var p = team_slots[t_idx][s_idx]
			if p != null:
				var p_id = int(p["id"])
				var p_session = NetworkManager.player_sessions.get(p_id, p).duplicate()
				p_session["id"] = p_id
				team_data["players"].append(p_session)
				if NetworkManager.player_sessions.has(p_id):
					NetworkManager.player_sessions[p_id]["id"] = p_id
					
		if not team_data["players"].is_empty():
			NetworkManager.computed_teams.append(team_data)
			
	print("Manuelle Teamauswahl abgeschlossen. Erstellte Teams: ", NetworkManager.computed_teams.size())
	print("Wechsle nun zum Qualifikationsquiz zur Punkte-Ermittlung...")
	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/Qualifikationsquiz.tscn")
