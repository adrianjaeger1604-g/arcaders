extends Node

# ==============================================================================
#                 LAUTSTÄRKE-EINSTELLUNGEN / VOLUME CONFIGURATION
# ==============================================================================
# Ändere diese Werte, um die Lautstärke im ganzen Spiel locker anzupassen!
# (Werte sind in Dezibel (dB). 0.0 ist Standard-Lautstärke, negative Werte leiser)
# ==============================================================================
@export var volume_music: float = 0.0 # Globale Hintergrundmusik-Lautstärke
@export var volume_sfx: float = -8.0   # Globale Soundeffekt-Lautstärke

var music_muted: bool = false
var sfx_muted: bool = false

func set_music_volume(vol: float):
	volume_music = vol
	if not music_muted and active_player != null:
		active_player.volume_db = volume_music

func set_sfx_volume(vol: float):
	volume_sfx = vol

func toggle_music_mute():
	music_muted = not music_muted
	if active_player != null:
		if music_muted:
			active_player.volume_db = -80.0
		else:
			active_player.volume_db = volume_music

func toggle_sfx_mute():
	sfx_muted = not sfx_muted

# Individuelle Lautstärke-Offsets für jeden Soundeffekt (falls manche zu laut/leise sind)
@export var sfx_volume_overrides = {
	"camera_shake": 2.0,      # Erhöhe Shake-Lautstärke leicht (+2 dB)
	"drink": 4.0,             # Erhöhe Trink-Lautstärke (+4 dB)
	"jump": -2.0,             # Mache Sprung leiser (-2 dB)
	"button_press": 0.0,      # Unverändert
	"victory_jubel": -1.0,    # Etwas leiser
	"timer_tick": -2.0,       # Etwas leiser
	"settings_open": 0.0      # Unverändert
}

var tracks = {
	"intro": preload("res://assets/audio/music/intro_music.mp3"),
	"qualifikationsquiz": preload("res://assets/audio/music/qualifikationsquiz_music.wav"),
	"minigame_10sec": preload("res://assets/audio/music/minigame_10sec_music.wav"),
	"minigame_tip_fast": preload("res://assets/audio/music/minigame_tip_fast_music.wav"),
	"video_game_quiz": preload("res://assets/audio/music/videogame_quiz_music.wav")
}

var sfx_tracks = {
	"camera_shake": preload("res://assets/audio/sfx/camera_shake.mp3"),
	"drink": preload("res://assets/audio/sfx/drink.mp3"),
	"jump": preload("res://assets/audio/sfx/jump.mp3"),
	"button_press": preload("res://assets/audio/sfx/button_press.wav"),
	"victory_jubel": preload("res://assets/audio/sfx/victory_jubel.wav"),
	"timer_tick": preload("res://assets/audio/sfx/timer_tick.wav"),
	"settings_open": preload("res://assets/audio/sfx/settings_open.wav")
}

var player_a: AudioStreamPlayer
var player_b: AudioStreamPlayer

var current_track: String = ""
var active_player: AudioStreamPlayer = null

func _ready():
	# Configure looping programmatically
	for key in tracks.keys():
		var stream = tracks[key]
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			
	# Instantiate two players for clean crossfades
	player_a = AudioStreamPlayer.new()
	player_b = AudioStreamPlayer.new()
	
	add_child(player_a)
	add_child(player_b)
	
	player_a.volume_db = -80.0
	player_b.volume_db = -80.0

func play_music(track_name: String, fade_duration: float = 0.5, start_from_sec: float = 0.0, volume_offset_db: float = 0.0):
	if track_name == current_track:
		return # Already playing! Seamless continue.
		
	if not tracks.has(track_name):
		printerr("AudioManager: Track not found: ", track_name)
		return
		
	print("AudioManager: Switching BGM to '", track_name, "' starting from ", start_from_sec, "s with offset ", volume_offset_db, " dB")
	current_track = track_name
	var next_stream = tracks[track_name]
	
	# Loop MP3 tracks dynamically if supported
	if next_stream is AudioStreamMP3:
		next_stream.loop = true
	
	# Determine active/inactive players
	var fade_out_player = active_player
	var fade_in_player = player_b if active_player == player_a else player_a
	
	# Setup the new stream and start playing at silent volume
	fade_in_player.stream = next_stream
	fade_in_player.volume_db = -80.0
	
	# Start playing from a specific position if requested
	fade_in_player.play(start_from_sec)
	
	active_player = fade_in_player
	
	# Crossfade using Tweens
	var tween = create_tween()
	
	# Fade in BGM to target volume (global volume + custom offset)
	var target_volume = volume_music + volume_offset_db
	if music_muted:
		target_volume = -80.0
	tween.tween_property(fade_in_player, "volume_db", target_volume, fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	# Parallel fade out the previous player if playing
	if fade_out_player and fade_out_player.playing:
		tween.parallel().tween_property(fade_out_player, "volume_db", -80.0, fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_callback(func(): fade_out_player.stop())

func stop_music(fade_duration: float = 0.5):
	current_track = ""
	if active_player and active_player.playing:
		var fade_out_player = active_player
		active_player = null
		
		var tween = create_tween()
		tween.tween_property(fade_out_player, "volume_db", -80.0, fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_callback(func(): fade_out_player.stop())

func play_sfx(sfx_name: String):
	if sfx_muted:
		return
		
	if not sfx_tracks.has(sfx_name):
		printerr("AudioManager: SFX not found: ", sfx_name)
		return
		
	# Sicherheits-Limit: Maximal 16 parallele Soundeffekte gleichzeitig, um Audio-Verzerrungen zu vermeiden
	var active_sfx = []
	for child in get_children():
		if child is AudioStreamPlayer and child != player_a and child != player_b:
			active_sfx.append(child)
			
	if active_sfx.size() >= 16:
		var oldest = active_sfx[0]
		oldest.stop()
		oldest.queue_free()
		
	var asp = AudioStreamPlayer.new()
	# Dupliziere den Stream, damit er parallel auf mehreren Kanälen 
	# unabhängig abgespielt werden kann, ohne sich gegenseitig abzuschneiden!
	var original_stream = sfx_tracks[sfx_name]
	if original_stream:
		asp.stream = original_stream.duplicate()
		
	# Berechne die Ziel-Lautstärke: Globale SFX-Lautstärke + individueller Offset
	var offset = sfx_volume_overrides.get(sfx_name, 0.0)
	asp.volume_db = volume_sfx + offset
	
	add_child(asp)
	asp.play()
	asp.finished.connect(func(): asp.queue_free())

func play_character_sfx(character_name: String, action: String = ""):
	if sfx_muted or character_name == "" or character_name == "unknown":
		return
		
	var formatted_name = character_name.to_lower().strip_edges()
	if formatted_name == "cedi":
		formatted_name = "cedric"
		
	var base_name = formatted_name
	if action != "":
		base_name = formatted_name + "_" + action
		
	var wav_path = "res://assets/audio/sfx/characters/" + base_name + ".wav"
	var mp3_path = "res://assets/audio/sfx/characters/" + base_name + ".mp3"
	
	var final_path = ""
	if ResourceLoader.exists(wav_path):
		final_path = wav_path
	elif ResourceLoader.exists(mp3_path):
		final_path = mp3_path
	else:
		# Fallback auf Sound ohne Action-Suffix
		wav_path = "res://assets/audio/sfx/characters/" + formatted_name + ".wav"
		mp3_path = "res://assets/audio/sfx/characters/" + formatted_name + ".mp3"
		if ResourceLoader.exists(wav_path):
			final_path = wav_path
		elif ResourceLoader.exists(mp3_path):
			final_path = mp3_path
		
	if final_path != "":
		# Sicherheits-Limit: Maximal 16 parallele Soundeffekte gleichzeitig
		var active_sfx = []
		for child in get_children():
			if child is AudioStreamPlayer and child != player_a and child != player_b:
				active_sfx.append(child)
				
		if active_sfx.size() >= 16:
			var oldest = active_sfx[0]
			oldest.stop()
			oldest.queue_free()
			
		var asp = AudioStreamPlayer.new()
		asp.stream = load(final_path)
		asp.volume_db = volume_sfx # Standard SFX volume
		add_child(asp)
		asp.play()
		asp.finished.connect(func(): asp.queue_free())
	else:
		# Nur fuer Debugging
		print("Kein Charakter-SFX gefunden fuer: ", formatted_name, " (Aktion: ", action, ")")

