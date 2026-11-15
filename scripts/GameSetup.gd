extends Control

@onready var minigames_option: OptionButton = $CenterContainer/VBox/SettingsPanel/MarginContainer/SettingsList/MinigamesRow/MinigamesOption
@onready var quiz_row: HBoxContainer = $CenterContainer/VBox/SettingsPanel/MarginContainer/SettingsList/QuizRow
@onready var quiz_option: OptionButton = $CenterContainer/VBox/SettingsPanel/MarginContainer/SettingsList/QuizRow/QuizOption
@onready var quiz_hint_label: Label = $CenterContainer/VBox/SettingsPanel/MarginContainer/SettingsList/QuizRow/QuizHintLabel

@onready var btn_mode_quiz: Button = $CenterContainer/VBox/SettingsPanel/MarginContainer/SettingsList/TeamModeRow/ToggleContainer/BtnQuizRanking
@onready var btn_mode_manual: Button = $CenterContainer/VBox/SettingsPanel/MarginContainer/SettingsList/TeamModeRow/ToggleContainer/BtnManual
@onready var team_mode_desc: Label = $CenterContainer/VBox/SettingsPanel/MarginContainer/SettingsList/TeamModeDesc

@onready var load_button: Button = $CenterContainer/VBox/ButtonsRow/LoadGameButton
@onready var create_button: Button = $CenterContainer/VBox/ButtonsRow/CreateGameButton
@onready var back_button: PixelBackButton = $PixelBackButton
@onready var save_modal = $SaveGameModal

var is_manual_teams: bool = false

# Pre-created StyleBoxes without expand_margins so buttons never grow
var _active_normal: StyleBoxFlat
var _active_hover: StyleBoxFlat
var _active_pressed: StyleBoxFlat

var _inactive_normal: StyleBoxFlat
var _inactive_hover: StyleBoxFlat
var _inactive_pressed: StyleBoxFlat

var _option_disabled: StyleBoxFlat

func _ready():
	if GlobalSettingsLayer:
		GlobalSettingsLayer.show_gear_button()
		
	AudioManager.play_music("intro")
	
	back_button.auto_return_to_main_board = false
	back_button.back_requested.connect(_on_back_pressed)
	
	_build_styles()
	
	# Initialisiere Minigames Option (Standard: 24)
	for i in range(minigames_option.item_count):
		if minigames_option.get_item_id(i) == NetworkManager.minigames_count:
			minigames_option.select(i)
			break
			
	# Initialisiere Quiz Option (Standard: 5)
	for i in range(quiz_option.item_count):
		if quiz_option.get_item_id(i) == NetworkManager.quiz_questions_count:
			quiz_option.select(i)
			break
			
	is_manual_teams = (NetworkManager.team_assignment_mode == "manual")
	
	btn_mode_quiz.pressed.connect(func(): _set_team_mode(false))
	btn_mode_manual.pressed.connect(func(): _set_team_mode(true))
	create_button.pressed.connect(_on_create_pressed)
	load_button.pressed.connect(_on_load_pressed)
	
	_update_team_mode_ui()
	_connect_buttons_sfx(self)

func _on_load_pressed():
	AudioManager.play_sfx("button_press")
	save_modal.open()

func _connect_buttons_sfx(node: Node):
	if node is Button:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func _create_flat_style(bg: Color, border: Color, b_width: int = 4, corner: int = 4) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left = b_width
	s.border_width_top = b_width
	s.border_width_right = b_width
	s.border_width_bottom = b_width
	s.border_color = border
	s.corner_radius_top_left = corner
	s.corner_radius_top_right = corner
	s.corner_radius_bottom_right = corner
	s.corner_radius_bottom_left = corner
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	# Explizit KEINE expand_margins, damit die Buttons beim Hovern nicht wachsen!
	s.expand_margin_left = 0
	s.expand_margin_top = 0
	s.expand_margin_right = 0
	s.expand_margin_bottom = 0
	s.anti_aliasing = false
	return s

func _build_styles():
	# Active Styles (Orange mit Goldrand)
	_active_normal = _create_flat_style(Color(0.867, 0.35, 0.09, 1.0), Color(1.0, 0.92, 0.68, 1.0))
	_active_hover = _create_flat_style(Color(0.96, 0.44, 0.15, 1.0), Color(1.0, 1.0, 0.85, 1.0))
	_active_pressed = _create_flat_style(Color(0.72, 0.25, 0.05, 1.0), Color(1.0, 0.92, 0.68, 1.0))
	
	# Inactive Styles (Grau mit separatem Slate-Hover)
	_inactive_normal = _create_flat_style(Color(0.20, 0.22, 0.28, 0.9), Color(0.38, 0.42, 0.50, 0.9))
	_inactive_hover = _create_flat_style(Color(0.28, 0.32, 0.40, 1.0), Color(0.68, 0.74, 0.88, 1.0))
	_inactive_pressed = _create_flat_style(Color(0.16, 0.18, 0.24, 1.0), Color(0.50, 0.55, 0.65, 1.0))
	
	# OptionButton Disabled Style ohne expand_margin
	_option_disabled = _create_flat_style(Color(0.32, 0.33, 0.38, 0.8), Color(0.48, 0.50, 0.58, 0.8))
	_option_disabled.content_margin_left = 32
	_option_disabled.content_margin_right = 32
	quiz_option.add_theme_stylebox_override("disabled", _option_disabled)

func _apply_button_styles(btn: Button, is_active: bool):
	var empty_focus = StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("focus", empty_focus)
	
	if is_active:
		btn.add_theme_stylebox_override("normal", _active_normal)
		btn.add_theme_stylebox_override("hover", _active_hover)
		btn.add_theme_stylebox_override("pressed", _active_pressed)
		btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.75, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.95, 0.75, 1.0))
		btn.add_theme_color_override("font_focus_color", Color(1.0, 1.0, 1.0, 1.0))
	else:
		btn.add_theme_stylebox_override("normal", _inactive_normal)
		btn.add_theme_stylebox_override("hover", _inactive_hover)
		btn.add_theme_stylebox_override("pressed", _inactive_pressed)
		btn.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.9, 1.0))
		btn.add_theme_color_override("font_focus_color", Color(0.75, 0.78, 0.85, 1.0))

func _set_team_mode(manual: bool):
	if is_manual_teams != manual:
		is_manual_teams = manual
		_update_team_mode_ui()

func _update_team_mode_ui():
	_apply_button_styles(btn_mode_quiz, not is_manual_teams)
	_apply_button_styles(btn_mode_manual, is_manual_teams)

	if is_manual_teams:
		team_mode_desc.text = "Manuelle Teams: Teams werden vorab manuell festgelegt. Das Qualifikationsquiz vergibt Bonuspunkte (+3, +2, +1) an die Teams."
		team_mode_desc.modulate = Color(1.0, 0.85, 0.4, 1.0)
	else:
		team_mode_desc.text = "Quiz-Ranking: Teams werden automatisch anhand der Punkte im Qualifikationsquiz gebildet."
		team_mode_desc.modulate = Color(1.0, 0.85, 0.4, 1.0)
		
	# Quiz-Option ist in beiden Modi aktiv, da in beiden das Qualifikationsquiz gespielt wird
	quiz_option.disabled = false
	quiz_option.modulate = Color(1.0, 1.0, 1.0, 1.0)
	quiz_hint_label.visible = false

func _on_back_pressed():
	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/StartMenu.tscn")

func _on_create_pressed():
	# 1. Vollstaendiger Reset fuer ein neues Spiel (loescht alte Sessions, Teams, Runden)
	NetworkManager.reset_for_new_game()
	
	# 2. Speichere die neu gewaehlten Einstellungen im NetworkManager
	NetworkManager.quiz_questions_count = quiz_option.get_selected_id()
	NetworkManager.minigames_count = minigames_option.get_selected_id()
	NetworkManager.team_assignment_mode = "manual" if is_manual_teams else "quiz_ranking"
	
	print("Neues Spiel erstellt mit Optionen:")
	print("- Minispiel Felder: ", NetworkManager.minigames_count)
	print("- Teamerstellung: ", NetworkManager.team_assignment_mode)
	print("- Quiz Fragen: ", NetworkManager.quiz_questions_count)
		
	# Weiter zur frischen Anmeldung / QR-Code Lobby
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
