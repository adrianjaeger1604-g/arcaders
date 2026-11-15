extends Control

@onready var saves_container: VBoxContainer = $PanelContainer/MarginContainer/VBox/ScrollContainer/SavesList
@onready var no_saves_label: Label = $PanelContainer/MarginContainer/VBox/NoSavesLabel
@onready var close_button: Button = $PanelContainer/MarginContainer/VBox/BottomRow/CloseButton
@onready var save_current_button: Button = get_node_or_null("PanelContainer/MarginContainer/VBox/BottomRow/SaveCurrentButton")

# Delete Confirm Dialog
@onready var confirm_overlay: ColorRect = $ConfirmOverlay
@onready var confirm_label: Label = $ConfirmOverlay/PanelContainer/MarginContainer/VBox/MessageLabel
@onready var btn_confirm_delete: Button = $ConfirmOverlay/PanelContainer/MarginContainer/VBox/HBox/BtnConfirmDelete
@onready var btn_cancel_delete: Button = $ConfirmOverlay/PanelContainer/MarginContainer/VBox/HBox/BtnCancelDelete

var _pending_delete_path: String = ""

# Styling für die Listeneinträge
var item_style_normal: StyleBoxFlat
var item_style_autosave: StyleBoxFlat

# Styling für den Löschen-Button (analog zum Kick-Button in Main.gd)
var del_btn_normal: StyleBoxFlat
var del_btn_hover: StyleBoxFlat
var del_btn_pressed: StyleBoxFlat

# Styling für den Laden-Button (ohne expand_margin für saubere Ausrichtung)
var load_btn_normal: StyleBoxFlat
var load_btn_hover: StyleBoxFlat
var load_btn_pressed: StyleBoxFlat

# Styling für den Duplizieren-Button
var dup_btn_normal: StyleBoxFlat
var dup_btn_hover: StyleBoxFlat
var dup_btn_pressed: StyleBoxFlat

func _ready():
	visible = false
	confirm_overlay.visible = false
	
	_build_styles()
	close_button.pressed.connect(close)
	if save_current_button:
		save_current_button.pressed.connect(_on_save_current_pressed)
	btn_confirm_delete.pressed.connect(_on_confirm_delete_pressed)
	btn_cancel_delete.pressed.connect(_on_cancel_delete_pressed)

func _on_save_current_pressed():
	AudioManager.play_sfx("button_press")
	var new_path = SaveManager.save_game()
	if not new_path.is_empty():
		SaveManager.current_save_path = new_path
		refresh_list()

func _build_styles():
	item_style_normal = StyleBoxFlat.new()
	item_style_normal.bg_color = Color(0.12, 0.14, 0.22, 0.95)
	item_style_normal.border_width_left = 3
	item_style_normal.border_width_top = 3
	item_style_normal.border_width_right = 3
	item_style_normal.border_width_bottom = 3
	item_style_normal.border_color = Color(1.0, 0.92, 0.68, 0.6)
	item_style_normal.corner_radius_top_left = 8
	item_style_normal.corner_radius_top_right = 8
	item_style_normal.corner_radius_bottom_right = 8
	item_style_normal.corner_radius_bottom_left = 8
	item_style_normal.anti_aliasing = false
	
	item_style_autosave = StyleBoxFlat.new()
	item_style_autosave.bg_color = Color(0.14, 0.13, 0.24, 0.95)
	item_style_autosave.border_width_left = 4
	item_style_autosave.border_width_top = 4
	item_style_autosave.border_width_right = 4
	item_style_autosave.border_width_bottom = 4
	item_style_autosave.border_color = Color(1.0, 0.85, 0.3, 0.95) # Goldener Glow
	item_style_autosave.corner_radius_top_left = 8
	item_style_autosave.corner_radius_top_right = 8
	item_style_autosave.corner_radius_bottom_right = 8
	item_style_autosave.corner_radius_bottom_left = 8
	item_style_autosave.anti_aliasing = false
	
	# Kompakte Laden-Button Styles (ohne expand_margin)
	load_btn_normal = StyleBoxFlat.new()
	load_btn_normal.bg_color = Color(0.8666, 0.349, 0.09, 1.0)
	load_btn_normal.border_width_left = 3
	load_btn_normal.border_width_top = 3
	load_btn_normal.border_width_right = 3
	load_btn_normal.border_width_bottom = 3
	load_btn_normal.border_color = Color(1.0, 0.9215, 0.6823, 1.0)
	load_btn_normal.corner_radius_top_left = 4
	load_btn_normal.corner_radius_top_right = 4
	load_btn_normal.corner_radius_bottom_right = 4
	load_btn_normal.corner_radius_bottom_left = 4
	load_btn_normal.content_margin_left = 14
	load_btn_normal.content_margin_right = 14
	load_btn_normal.content_margin_top = 6
	load_btn_normal.content_margin_bottom = 6
	load_btn_normal.expand_margin_left = 0
	load_btn_normal.expand_margin_top = 0
	load_btn_normal.expand_margin_right = 0
	load_btn_normal.expand_margin_bottom = 0
	load_btn_normal.anti_aliasing = false
	
	load_btn_hover = load_btn_normal.duplicate()
	load_btn_hover.bg_color = Color(0.7666, 0.249, 0.0, 1.0)
	
	load_btn_pressed = load_btn_normal.duplicate()
	load_btn_pressed.bg_color = Color(0.70, 0.22, 0.0, 1.0)
	load_btn_pressed.content_margin_top = 8
	load_btn_pressed.content_margin_bottom = 4
	
	# Duplizieren-Button Stil (Sekundärer blauer Pixel-Button)
	dup_btn_normal = StyleBoxFlat.new()
	dup_btn_normal.bg_color = Color(0.20, 0.32, 0.52, 1.0)
	dup_btn_normal.border_width_left = 2
	dup_btn_normal.border_width_top = 2
	dup_btn_normal.border_width_right = 2
	dup_btn_normal.border_width_bottom = 2
	dup_btn_normal.border_color = Color(0.55, 0.78, 1.0, 0.9)
	dup_btn_normal.corner_radius_top_left = 4
	dup_btn_normal.corner_radius_top_right = 4
	dup_btn_normal.corner_radius_bottom_right = 4
	dup_btn_normal.corner_radius_bottom_left = 4
	dup_btn_normal.content_margin_left = 12
	dup_btn_normal.content_margin_right = 12
	dup_btn_normal.content_margin_top = 6
	dup_btn_normal.content_margin_bottom = 6
	dup_btn_normal.expand_margin_left = 0
	dup_btn_normal.expand_margin_top = 0
	dup_btn_normal.expand_margin_right = 0
	dup_btn_normal.expand_margin_bottom = 0
	dup_btn_normal.anti_aliasing = false
	
	dup_btn_hover = dup_btn_normal.duplicate()
	dup_btn_hover.bg_color = Color(0.28, 0.44, 0.68, 1.0)
	dup_btn_hover.border_color = Color(0.8, 0.92, 1.0, 1.0)
	
	dup_btn_pressed = dup_btn_normal.duplicate()
	dup_btn_pressed.bg_color = Color(0.15, 0.24, 0.40, 1.0)
	dup_btn_pressed.border_color = Color(0.45, 0.65, 0.9, 1.0)
	
	# Roter "X" Lösch-Button Stil (wie in Main.gd)
	del_btn_normal = StyleBoxFlat.new()
	del_btn_normal.bg_color = Color(0.85, 0.22, 0.22, 1.0)
	del_btn_normal.border_width_left = 2
	del_btn_normal.border_width_top = 2
	del_btn_normal.border_width_right = 2
	del_btn_normal.border_width_bottom = 2
	del_btn_normal.border_color = Color(1.0, 0.45, 0.45, 0.9)
	del_btn_normal.corner_radius_top_left = 4
	del_btn_normal.corner_radius_top_right = 4
	del_btn_normal.corner_radius_bottom_right = 4
	del_btn_normal.corner_radius_bottom_left = 4
	del_btn_normal.content_margin_left = 0
	del_btn_normal.content_margin_top = 0
	del_btn_normal.content_margin_right = 0
	del_btn_normal.content_margin_bottom = 0
	del_btn_normal.expand_margin_left = 0
	del_btn_normal.expand_margin_top = 0
	del_btn_normal.expand_margin_right = 0
	del_btn_normal.expand_margin_bottom = 0
	del_btn_normal.anti_aliasing = false
	
	del_btn_hover = del_btn_normal.duplicate()
	del_btn_hover.bg_color = Color(1.0, 0.32, 0.32, 1.0)
	del_btn_hover.border_color = Color(1.0, 0.8, 0.8, 1.0)
	
	del_btn_pressed = del_btn_normal.duplicate()
	del_btn_pressed.bg_color = Color(0.65, 0.15, 0.15, 1.0)
	del_btn_pressed.border_color = Color(0.8, 0.3, 0.3, 1.0)

func open():
	visible = true
	confirm_overlay.visible = false
	_pending_delete_path = ""
	
	if save_current_button:
		# Button nur anzeigen, wenn gerade ein aktives Spiel (mit Teams) läuft
		save_current_button.visible = (NetworkManager.computed_teams.size() > 0)
		
	refresh_list()

func close():
	visible = false

func refresh_list():
	for child in saves_container.get_children():
		child.queue_free()
		
	var saves = SaveManager.get_save_files()
	
	if saves.is_empty():
		no_saves_label.visible = true
		return
		
	no_saves_label.visible = false
	
	for s_data in saves:
		var item = _create_save_entry(s_data)
		saves_container.add_child(item)

func _create_save_entry(s_data: Dictionary) -> Control:
	var panel = PanelContainer.new()
	var is_auto = s_data.get("is_autosave", false)
	panel.add_theme_stylebox_override("panel", item_style_autosave if is_auto else item_style_normal)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	margin.add_child(hbox)
	
	# Linke Seite: Details
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	hbox.add_child(vbox)
	
	# Titel-Zeile mit Badge
	var title_box = HBoxContainer.new()
	title_box.add_theme_constant_override("separation", 10)
	vbox.add_child(title_box)
	
	var badge = Label.new()
	if is_auto:
		badge.text = "[AUTOSAVE]"
		badge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	else:
		badge.text = "[SPIELSTAND]"
		badge.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0, 1.0))
	badge.add_theme_font_size_override("font_size", 22)
	title_box.add_child(badge)
	
	var title_lbl = Label.new()
	title_lbl.text = s_data.get("formatted_date", "Unbekannt")
	title_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_box.add_child(title_lbl)
	
	# Info-Zeile
	var info_lbl = Label.new()
	var round_num = s_data.get("current_turn", 0)
	var played = s_data.get("played_minigames", 0)
	var total = s_data.get("total_minigames", 24)
	var p_count = s_data.get("player_count", 0)
	var t_count = s_data.get("team_count", 0)
	
	info_lbl.text = "Runde %d  •  %d/%d Minispiele gespielt  •  %d Spieler (%d Teams)" % [round_num, played, total, p_count, t_count]
	info_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 0.85))
	info_lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(info_lbl)
	
	# Rechte Seite: Buttons
	var btn_box = HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 10)
	hbox.add_child(btn_box)
	
	var btn_load = Button.new()
	btn_load.text = "LADEN"
	btn_load.custom_minimum_size = Vector2(130, 44)
	btn_load.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_load.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn_load.add_theme_font_size_override("font_size", 24)
	btn_load.add_theme_stylebox_override("normal", load_btn_normal)
	btn_load.add_theme_stylebox_override("hover", load_btn_hover)
	btn_load.add_theme_stylebox_override("pressed", load_btn_pressed)
	btn_load.add_theme_stylebox_override("hover_pressed", load_btn_pressed)
	btn_load.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn_load.pressed.connect(func(): _on_load_clicked(s_data.get("filepath", "")))
	btn_box.add_child(btn_load)
	
	var btn_duplicate = Button.new()
	btn_duplicate.text = "DUPLIZIEREN"
	btn_duplicate.custom_minimum_size = Vector2(150, 44)
	btn_duplicate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_duplicate.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn_duplicate.add_theme_font_size_override("font_size", 20)
	btn_duplicate.add_theme_stylebox_override("normal", dup_btn_normal)
	btn_duplicate.add_theme_stylebox_override("hover", dup_btn_hover)
	btn_duplicate.add_theme_stylebox_override("pressed", dup_btn_pressed)
	btn_duplicate.add_theme_stylebox_override("hover_pressed", dup_btn_pressed)
	btn_duplicate.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn_duplicate.add_theme_color_override("font_color", Color.WHITE)
	btn_duplicate.add_theme_color_override("font_hover_color", Color.WHITE)
	btn_duplicate.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	btn_duplicate.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.9))
	btn_duplicate.add_theme_color_override("font_focus_color", Color.WHITE)
	btn_duplicate.pressed.connect(func(): _on_duplicate_clicked(s_data.get("filepath", "")))
	btn_box.add_child(btn_duplicate)
	
	var btn_delete = Button.new()
	btn_delete.text = "X"
	btn_delete.custom_minimum_size = Vector2(44, 44)
	btn_delete.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_delete.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn_delete.add_theme_font_size_override("font_size", 24)
	btn_delete.add_theme_stylebox_override("normal", del_btn_normal)
	btn_delete.add_theme_stylebox_override("hover", del_btn_hover)
	btn_delete.add_theme_stylebox_override("pressed", del_btn_pressed)
	btn_delete.add_theme_stylebox_override("hover_pressed", del_btn_pressed)
	btn_delete.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn_delete.add_theme_color_override("font_color", Color.WHITE)
	btn_delete.add_theme_color_override("font_hover_color", Color.WHITE)
	btn_delete.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	btn_delete.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.9))
	btn_delete.add_theme_color_override("font_focus_color", Color.WHITE)
	btn_delete.pressed.connect(func(): _on_delete_clicked(s_data))
	btn_box.add_child(btn_delete)
	
	return panel

func _on_load_clicked(filepath: String):
	if filepath.is_empty():
		return
	AudioManager.play_sfx("button_press")
	SaveManager.load_game(filepath)

func _on_duplicate_clicked(filepath: String):
	if filepath.is_empty():
		return
	AudioManager.play_sfx("button_press")
	var new_path = SaveManager.duplicate_save(filepath)
	if not new_path.is_empty():
		refresh_list()

func _on_delete_clicked(s_data: Dictionary):
	AudioManager.play_sfx("button_press")
	_pending_delete_path = s_data.get("filepath", "")
	var name_str = s_data.get("display_name", "Spielstand")
	var date_str = s_data.get("formatted_date", "")
	confirm_label.text = "Möchtest du diesen Spielstand wirklich unwiderruflich löschen?\n\n'%s' (%s)" % [name_str, date_str]
	confirm_overlay.visible = true

func _on_confirm_delete_pressed():
	AudioManager.play_sfx("button_press")
	if not _pending_delete_path.is_empty():
		SaveManager.delete_save(_pending_delete_path)
		_pending_delete_path = ""
	confirm_overlay.visible = false
	refresh_list()

func _on_cancel_delete_pressed():
	AudioManager.play_sfx("button_press")
	_pending_delete_path = ""
	confirm_overlay.visible = false
