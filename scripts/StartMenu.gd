extends Control

@onready var title_label = $CenterContainer/VBox/TitleBox/Title
@onready var quiz_option = $CenterContainer/VBox/SettingsPanel/SettingsList/QuizRow/QuizOption
@onready var minigames_option = $CenterContainer/VBox/SettingsPanel/SettingsList/MinigamesRow/MinigamesOption
@onready var start_button = $CenterContainer/VBox/StartButton

var pulse_tween: Tween

func _ready():
	AudioManager.play_music("intro")
	start_button.pressed.connect(_on_start_pressed)
	_start_title_animation()
	_connect_buttons_sfx(self)

func _connect_buttons_sfx(node: Node):
	if node is Button:
		node.pressed.connect(func(): AudioManager.play_sfx("button_press"))
	for child in node.get_children():
		_connect_buttons_sfx(child)

func _start_title_animation():
	pulse_tween = create_tween().set_loops()
	
	# Initial scale setup for centering
	title_label.pivot_offset = title_label.size / 2.0
	
	# Scale UP
	pulse_tween.tween_property(title_label, "scale", Vector2(1.1, 1.1), 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Scale DOWN
	pulse_tween.tween_property(title_label, "scale", Vector2(1.0, 1.0), 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _on_start_pressed():
	# Speichere die Einstellungen im NetworkManager
	NetworkManager.quiz_questions_count = quiz_option.get_selected_id()
	
	# Hole den gewählten Wert aus dem OptionButton (12, 16, 20, 24)
	var selected_id = minigames_option.get_selected_id()
	NetworkManager.minigames_count = selected_id
	
	print("Einstellungen gespeichert: ", NetworkManager.quiz_questions_count, " Quiz Fragen, ", NetworkManager.minigames_count, " Minispiele.")
	
	# Wechsle zur Lobby (QR Code Szene)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
