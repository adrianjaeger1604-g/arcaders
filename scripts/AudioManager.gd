extends Node

# ==============================================================================
#                 LAUTSTÄRKE-EINSTELLUNGEN / VOLUME CONFIGURATION
# ==============================================================================
# Ändere diese Werte, um die Lautstärke im ganzen Spiel locker anzupassen!
# (Werte sind in Dezibel (dB). 0.0 ist Standard-Lautstärke, negative Werte leiser)
# ==============================================================================
@export var volume_music: float = -3.0 # Globale Hintergrundmusik-Lautstärke (-3 dB Standard, dezent im Hintergrund)
@export var volume_sfx: float = 0.0   # Globale Soundeffekt-Lautstärke (0 dB Referenz, druckvoll & präsent)

var music_muted: bool = false
var sfx_muted: bool = false
var current_music_offset: float = 0.0

func set_music_volume(vol: float):
	volume_music = vol
	if not music_muted and active_player != null:
		active_player.volume_db = volume_music + current_music_offset

func set_sfx_volume(vol: float):
	volume_sfx = vol

func toggle_music_mute():
	music_muted = not music_muted
	if active_player != null:
		if music_muted:
			active_player.volume_db = -80.0
		else:
			active_player.volume_db = volume_music + current_music_offset

func toggle_sfx_mute():
	sfx_muted = not sfx_muted

# Individuelle Lautstärke-Offsets für Hintergrundmusik-Tracks
@export var music_volume_overrides = {
	"fire_emblem": -4.0,       # Druckvoller Kampf-Track etwas absenken, damit SFX voll zur Geltung kommen (-4.0 dB)
	"cookie_clickers": -2.0,
	"cookie_clicker": -2.0,
	"ice_climbers": -2.0,
	"ice_climber": -2.0
}

# Individuelle Lautstärke-Offsets für jeden Soundeffekt (damit alle Effekte gleich laut klingen)
@export var sfx_volume_overrides = {
	"camera_shake": 2.0,        # Erhöhe Shake-Lautstärke leicht (+2 dB)
	"drink": 4.0,               # Erhöhe Trink-Lautstärke (+4 dB)
	"jump": -1.0,               # Sprung-Sound (-1 dB)
	"button_press": 1.0,        # UI Button-Klick (+1 dB)
	"timer_tick": -1.0,         # Timer Ticken (-1 dB)
	"countdown_321go": 1.5,     # 3-2-1-GO Countdown Sound (+1.5 dB)
	"countdown": 1.5,
	"settings_open": 1.0,       # Einstellungs-Menü (+1 dB)
	"super-mario-pipe": 1.0,    # Röhren-Sound (+1 dB)
	"super_mario_pipe": 1.0,
	"confetti-pop-sound-effect": 1.5, # Sieges-Konfetti (+1.5 dB)
	"confetti_pop": 1.5,
	"fire_spread": 1.5,         # Rauschende Flammenwoge & Gefahrenzonen-Schaden (+1.5 dB)
	"healing": 1.5,             # Feiner Heil-Chime (+1.5 dB)
	"heal": 1.5,
	"asteroid_explosion": 1.0,  # Wuchtiger Meteor-Einschlag (+1.0 dB)
	"meteor": 1.0,
	"teleport": 1.5,            # Portal-Warp-Whoosh (+1.5 dB)
	"dmg_buff": 1.5,            # Schwert-Schrein Power-Up (+1.5 dB)
	"transformation": 1.5,      # Typ-Wechsel Transformation (+1.5 dB)
	"type_swap": 1.5,
	"bye_bye": 1.5,             # K.O. Sprach-Clip ("Bye Bye!") (+1.5 dB)
	"hit": 1.5,                 # Treffer-Sound beim Angriff (+1.5 dB)
	"missed_punch": 1.5,        # Verfehlter Schlag Whoosh (+1.5 dB)
	"minecraft_walking": 2.0,   # Minecraft Schritt-Geräusche beim Laufen (+2.0 dB)
	"block_break": 1.5          # Eisblock / Block zerstören Sound (+1.5 dB)
}

var tracks = {
	"intro": preload("res://assets/audio/music/MainBoard_music/intro_music.mp3")
}

var quiz_tracks: Array[AudioStream] = []
var mainboard_tracks: Array[AudioStream] = []

var sfx_tracks = {
	"camera_shake": preload("res://assets/audio/sfx/camera_shake.mp3"),
	"drink": preload("res://assets/audio/sfx/drink.mp3"),
	"jump": preload("res://assets/audio/sfx/jump.mp3"),
	"button_press": preload("res://assets/audio/sfx/button_press.mp3"),
	"timer_tick": preload("res://assets/audio/sfx/timer_tick.wav"),
	"countdown_321go": preload("res://assets/audio/sfx/countdown_321go.mp3"),
	"countdown": preload("res://assets/audio/sfx/countdown_321go.mp3"),
	"settings_open": preload("res://assets/audio/sfx/settings_open.wav"),
	"super-mario-pipe": preload("res://assets/audio/sfx/super-mario-pipe.mp3"),
	"super_mario_pipe": preload("res://assets/audio/sfx/super-mario-pipe.mp3"),
	"confetti-pop-sound-effect": preload("res://assets/audio/sfx/confetti-pop-sound-effect.mp3"),
	"confetti_pop": preload("res://assets/audio/sfx/confetti-pop-sound-effect.mp3"),
	"fire_spread": preload("res://assets/audio/sfx/fire_spread.mp3"),
	"healing": preload("res://assets/audio/sfx/healing.mp3"),
	"heal": preload("res://assets/audio/sfx/healing.mp3"),
	"asteroid_explosion": preload("res://assets/audio/sfx/asteroid_explosion.wav"),
	"meteor": preload("res://assets/audio/sfx/asteroid_explosion.wav"),
	"teleport": preload("res://assets/audio/sfx/teleport.mp3"),
	"dmg_buff": preload("res://assets/audio/sfx/dmg_buff.mp3"),
	"transformation": preload("res://assets/audio/sfx/transformation.mp3"),
	"type_swap": preload("res://assets/audio/sfx/transformation.mp3"),
	"bye_bye": preload("res://assets/audio/sfx/bye_bye.mp3"),
	"hit": preload("res://assets/audio/sfx/hit.mp3"),
	"missed_punch": preload("res://assets/audio/sfx/missed_punch.mp3"),
	"minecraft_walking": preload("res://assets/audio/sfx/minecraft_walking.mp3"),
	"block_break": preload("res://assets/audio/sfx/block_break.mp3")
}

var player_a: AudioStreamPlayer
var player_b: AudioStreamPlayer

var current_track: String = ""
var active_player: AudioStreamPlayer = null
var sfx_last_play_time = {}
var bgm_tween: Tween = null
var last_mainboard_stream: AudioStream = null

func _configure_stream_loop(stream: AudioStream, enable_loop: bool = true):
	if stream is AudioStreamWAV:
		var total_samples = int(stream.get_length() * stream.mix_rate)
		if total_samples > 0:
			stream.loop_begin = 0
			stream.loop_end = total_samples
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if enable_loop else AudioStreamWAV.LOOP_DISABLED
	elif stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = enable_loop

func _load_mp3_safe(res_path: String) -> AudioStream:
	if ResourceLoader.exists(res_path):
		var s = load(res_path)
		if s != null:
			return s
	if FileAccess.file_exists(res_path):
		var bytes = FileAccess.get_file_as_bytes(res_path)
		if not bytes.is_empty():
			var mp3 = AudioStreamMP3.new()
			mp3.data = bytes
			return mp3
	return null

func _ready():
	randomize()
	var fe_stream = _load_mp3_safe("res://assets/audio/music/fire_emblem_music.mp3")
	if fe_stream != null:
		tracks["fire_emblem"] = fe_stream

	var ic_stream = _load_mp3_safe("res://assets/audio/music/ice_climbers_music.mp3")
	if ic_stream != null:
		tracks["ice_climbers"] = ic_stream
		tracks["ice_climber"] = ic_stream

	var cc_stream = _load_mp3_safe("res://assets/audio/music/cookie_clickers_music.mp3")
	if cc_stream != null:
		tracks["cookie_clickers"] = cc_stream
		tracks["cookie_clicker"] = cc_stream
		tracks["coockie_clickers"] = cc_stream
		tracks["minigame_cookie_clickers"] = cc_stream
		tracks["minigame_tip_fast"] = cc_stream
	
	# Fallback für SFX falls Ressourcen dynamisch geladen werden müssen
	var extra_sfx = {
		"fire_spread": "res://assets/audio/sfx/fire_spread.mp3",
		"healing": "res://assets/audio/sfx/healing.mp3",
		"heal": "res://assets/audio/sfx/healing.mp3",
		"asteroid_explosion": "res://assets/audio/sfx/asteroid_explosion.wav",
		"meteor": "res://assets/audio/sfx/asteroid_explosion.wav",
		"teleport": "res://assets/audio/sfx/teleport.mp3",
		"dmg_buff": "res://assets/audio/sfx/dmg_buff.mp3",
		"transformation": "res://assets/audio/sfx/transformation.mp3",
		"type_swap": "res://assets/audio/sfx/transformation.mp3",
		"bye_bye": "res://assets/audio/sfx/bye_bye.mp3",
		"hit": "res://assets/audio/sfx/hit.mp3",
		"missed_punch": "res://assets/audio/sfx/missed_punch.mp3",
		"minecraft_walking": "res://assets/audio/sfx/minecraft_walking.mp3",
		"block_break": "res://assets/audio/sfx/block_break.mp3"
	}
	for s_name in extra_sfx:
		if not sfx_tracks.has(s_name) or sfx_tracks[s_name] == null:
			var path = extra_sfx[s_name]
			if ResourceLoader.exists(path):
				sfx_tracks[s_name] = load(path)
			elif path.ends_with(".mp3"):
				sfx_tracks[s_name] = _load_mp3_safe(path)

	load_quiz_tracks()
	load_mainboard_tracks()
	
	# Configure looping programmatically
	for key in tracks.keys():
		_configure_stream_loop(tracks[key], true)
			
	# Instantiate two players for clean crossfades
	player_a = AudioStreamPlayer.new()
	player_b = AudioStreamPlayer.new()
	player_a.name = "BGM_Player_A"
	player_b.name = "BGM_Player_B"
	
	add_child(player_a)
	add_child(player_b)
	
	player_a.volume_db = -80.0
	player_b.volume_db = -80.0
	
	player_a.finished.connect(func(): _on_player_finished(player_a))
	player_b.finished.connect(func(): _on_player_finished(player_b))

func _on_player_finished(player: AudioStreamPlayer):
	if player == active_player:
		print("AudioManager: Track beendet -> '", current_track, "'.")
		if current_track.begins_with("mainboard:"):
			play_random_mainboard_music(1.0)
		elif current_track.begins_with("quiz:") or not current_track.is_empty():
			# Während eines Spiels denselben Track wieder von vorne abspielen (Loop)
			player.play(0.0)

func load_quiz_tracks():
	quiz_tracks.clear()
	var dir_path = "res://assets/audio/music/quiz_music"
	var loaded_paths = {}
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				var clean_name = file_name
				if clean_name.ends_with(".import"):
					clean_name = clean_name.trim_suffix(".import")
				if (clean_name.ends_with(".mp3") or clean_name.ends_with(".wav") or clean_name.ends_with(".ogg")) and not clean_name.begins_with("."):
					var full_path = dir_path + "/" + clean_name
					if not loaded_paths.has(full_path):
						var stream: AudioStream = null
						if full_path.ends_with(".mp3"):
							stream = _load_mp3_safe(full_path)
						elif ResourceLoader.exists(full_path):
							stream = load(full_path)
						if stream and not quiz_tracks.has(stream):
							loaded_paths[full_path] = true
							if stream.resource_name.is_empty():
								stream.resource_name = clean_name.get_basename()
							_configure_stream_loop(stream, true)
							quiz_tracks.append(stream)
			file_name = dir.get_next()
			
	# Fallback falls DirAccess in exportierter Umgebung leer sein sollte
	if quiz_tracks.is_empty():
		var fallback_files = [
			"res://assets/audio/music/quiz_music/Professor Layton and the Unwound Future_Lost Future OST - Puzzles (Reinvented).mp3",
			"res://assets/audio/music/quiz_music/Puzzle-Solving Piece. - Laytons Mystery Journey..mp3",
			"res://assets/audio/music/quiz_music/Puzzles - Professor Layton And The Curious Village Soundtrack.mp3",
			"res://assets/audio/music/quiz_music/Wer wird Millionär Soundtracks [8] - 32.000-500.000 €.mp3"
		]
		for path in fallback_files:
			var stream = _load_mp3_safe(path)
			if stream and not quiz_tracks.has(stream):
				if stream.resource_name.is_empty():
					stream.resource_name = path.get_file().get_basename()
				_configure_stream_loop(stream, true)
				quiz_tracks.append(stream)
					
	print("AudioManager: ", quiz_tracks.size(), " Quiz-Tracks geladen.")

func load_mainboard_tracks():
	mainboard_tracks.clear()
	var dir_path = "res://assets/audio/music/MainBoard_music"
	if not DirAccess.dir_exists_absolute(dir_path):
		dir_path = "res://assets/audio/music/mainboard_music"
		
	var loaded_paths = {}
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				var clean_name = file_name
				if clean_name.ends_with(".import"):
					clean_name = clean_name.trim_suffix(".import")
				if (clean_name.ends_with(".mp3") or clean_name.ends_with(".wav") or clean_name.ends_with(".ogg")) and not clean_name.begins_with("."):
					var full_path = dir_path + "/" + clean_name
					if not loaded_paths.has(full_path):
						var stream: AudioStream = null
						if full_path.ends_with(".mp3"):
							stream = _load_mp3_safe(full_path)
						elif ResourceLoader.exists(full_path):
							stream = load(full_path)
						if stream != null:
							loaded_paths[full_path] = true
							if stream.resource_name.is_empty():
								stream.resource_name = clean_name.get_basename()
							_configure_stream_loop(stream, false)
							mainboard_tracks.append(stream)
							print("AudioManager: MainBoard-Track geladen: ", clean_name)
			file_name = dir.get_next()
			
	# Fallback falls DirAccess in exportierter Umgebung leer sein sollte
	if mainboard_tracks.is_empty():
		var fallback_files = [
			dir_path + "/C418 - Haggstrom - Minecraft Volume Alpha.mp3",
			dir_path + "/C418 - Living Mice - Minecraft Volume Alpha.mp3",
			dir_path + "/C418 - Mice on Venus - Minecraft Volume Alpha.mp3",
			dir_path + "/C418 - Minecraft - Minecraft Volume Alpha.mp3",
			dir_path + "/C418 - Subwoofer Lullaby - Minecraft Volume Alpha.mp3",
			dir_path + "/intro_music.mp3"
		]
		for path in fallback_files:
			var stream = _load_mp3_safe(path)
			if stream and not mainboard_tracks.has(stream):
				if stream.resource_name.is_empty():
					stream.resource_name = path.get_file().get_basename()
				_configure_stream_loop(stream, false)
				mainboard_tracks.append(stream)
					
	print("AudioManager: ", mainboard_tracks.size(), " MainBoard-Tracks geladen.")

func play_random_quiz_music(fade_duration: float = 0.5, force_new: bool = false):
	# Wenn bereits ein Quiz-Track läuft (während eines Minispiels/Quiz), diesen Track nicht unterbrechen oder wechseln!
	if not force_new and current_track.begins_with("quiz:") and active_player != null and active_player.playing and active_player.volume_db > -40.0:
		return
		
	if quiz_tracks.is_empty():
		load_quiz_tracks()
	if quiz_tracks.is_empty():
		print("AudioManager: Keine Quiz-Musik gefunden in res://assets/audio/music/quiz_music/")
		return
		
	var chosen_stream: AudioStream = null
	if quiz_tracks.size() == 1:
		chosen_stream = quiz_tracks[0]
	else:
		var pool = quiz_tracks.duplicate()
		if active_player != null and active_player.stream != null and active_player.playing and active_player.volume_db > -40.0:
			pool.erase(active_player.stream)
		if pool.is_empty():
			pool = quiz_tracks.duplicate()
		chosen_stream = pool[randi() % pool.size()]
		
	var stream_name = chosen_stream.resource_name
	if stream_name.is_empty():
		stream_name = chosen_stream.resource_path.get_file().get_basename()
	if stream_name.is_empty():
		stream_name = "quiz_track"
	_play_stream(chosen_stream, "quiz:" + stream_name, fade_duration)

func play_random_mainboard_music(fade_duration: float = 0.5):
	if mainboard_tracks.is_empty():
		load_mainboard_tracks()
	if mainboard_tracks.is_empty():
		print("AudioManager: Keine MainBoard-Musik gefunden in res://assets/audio/music/MainBoard_music/")
		return
		
	var chosen_stream: AudioStream = null
	if mainboard_tracks.size() == 1:
		chosen_stream = mainboard_tracks[0]
	else:
		var pool = []
		for s in mainboard_tracks:
			if active_player != null and s == active_player.stream and active_player.playing and active_player.volume_db > -40.0:
				continue
			if s == last_mainboard_stream:
				continue
			pool.append(s)
			
		if pool.is_empty():
			for s in mainboard_tracks:
				if active_player != null and s == active_player.stream and active_player.playing and active_player.volume_db > -40.0:
					continue
				pool.append(s)
		if pool.is_empty():
			pool = mainboard_tracks.duplicate()
			
		chosen_stream = pool[randi() % pool.size()]
		
	last_mainboard_stream = chosen_stream
	var stream_name = chosen_stream.resource_name
	if stream_name.is_empty():
		stream_name = chosen_stream.resource_path.get_file().get_basename()
	if stream_name.is_empty():
		stream_name = "mainboard_track"
	_play_stream(chosen_stream, "mainboard:" + stream_name, fade_duration)

func play_music(track_name: String, fade_duration: float = 0.5, start_from_sec: float = 0.0, volume_offset_db: float = 0.0):
	# Quiz-Aliase automatisch an zufällige Quiz-Musik weiterleiten
	if track_name in ["quiz", "quiz_music", "qualifikationsquiz", "hexagon", "bet_buddy", "bet_buddy_extreme", "schmierig"]:
		play_random_quiz_music(fade_duration)
		return
		
	# MainBoard-Aliase an zufällige MainBoard-Musik weiterleiten
	if track_name in ["mainboard", "main_board", "board", "mainboard_music"]:
		play_random_mainboard_music(fade_duration)
		return
		
	if not tracks.has(track_name):
		# Falls ein entfernter Platzhalter angefragt wird, stoppen wir die Musik sauber
		print("AudioManager: Musiktrack nicht vorhanden oder entfernt: ", track_name)
		stop_music(fade_duration)
		return
		
	# Intro-Song standardmäßig bei 2:37 (157s) starten, falls keine Startzeit vorgegeben wurde
	if track_name == "intro" and is_zero_approx(start_from_sec):
		start_from_sec = 157.0
		
	var track_offset = music_volume_overrides.get(track_name, 0.0)
	_play_stream(tracks[track_name], track_name, fade_duration, start_from_sec, volume_offset_db + track_offset)

func _play_stream(next_stream: AudioStream, track_identifier: String, fade_duration: float = 0.5, start_from_sec: float = 0.0, volume_offset_db: float = 0.0):
	# Bereits aktiv und spielt gerade mit hörbarer Lautstärke? Dann nahtlos weiterlaufen lassen.
	if track_identifier == current_track and active_player != null and active_player.playing and active_player.volume_db > -40.0:
		return
		
	print("AudioManager: Switching BGM to '", track_identifier, "' starting from ", start_from_sec, "s with offset ", volume_offset_db, " dB")
	current_track = track_identifier
	current_music_offset = volume_offset_db
	
	# Vorherigen Tween sofort abbrechen, damit keine veralteten stop()-Callbacks die neue Musik killen!
	if bgm_tween and bgm_tween.is_valid():
		bgm_tween.kill()
		bgm_tween = null
	
	# Loop MP3/OGG/WAV tracks dynamisch konfigurieren:
	# MainBoard-Tracks rotieren nach Track-Ende als Hintergrund-Playlist.
	# Während eines Spiels (Quiz / Minispiele) wird der zufällig gewählte Song kontinuierlich geloopt!
	var should_loop = not track_identifier.begins_with("mainboard:")
	_configure_stream_loop(next_stream, should_loop)
	
	# Bestimme den aktiven und den nächsten Player
	var fade_out_player = active_player
	var fade_in_player = player_b if active_player == player_a else player_a
	
	# Neuen Player initialisieren
	fade_in_player.stop()
	fade_in_player.stream = next_stream
	fade_in_player.volume_db = -80.0
	fade_in_player.play(start_from_sec)
	
	active_player = fade_in_player
	
	var target_volume = volume_music + current_music_offset
	if music_muted:
		target_volume = -80.0
		
	if fade_duration <= 0.0:
		fade_in_player.volume_db = target_volume
		if fade_out_player and fade_out_player != fade_in_player:
			fade_out_player.stop()
			fade_out_player.volume_db = -80.0
		var other = player_b if fade_in_player == player_a else player_a
		if other != fade_in_player:
			other.stop()
			other.volume_db = -80.0
		return
		
	bgm_tween = create_tween()
	bgm_tween.set_parallel(true)
	bgm_tween.tween_property(fade_in_player, "volume_db", target_volume, fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	var other_player = player_b if fade_in_player == player_a else player_a
	if other_player and other_player.playing:
		bgm_tween.tween_property(other_player, "volume_db", -80.0, fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		bgm_tween.chain().tween_callback(func():
			if other_player != active_player and is_instance_valid(other_player):
				other_player.stop()
		)

func stop_music(fade_duration: float = 0.5):
	current_track = ""
	current_music_offset = 0.0
	if bgm_tween and bgm_tween.is_valid():
		bgm_tween.kill()
		bgm_tween = null
		
	var player_to_stop = active_player
	active_player = null
	
	if player_to_stop == null or not player_to_stop.playing:
		if player_a:
			player_a.stop()
			player_a.volume_db = -80.0
		if player_b:
			player_b.stop()
			player_b.volume_db = -80.0
		return
		
	if fade_duration <= 0.0:
		if player_a:
			player_a.stop()
			player_a.volume_db = -80.0
		if player_b:
			player_b.stop()
			player_b.volume_db = -80.0
		return
		
	bgm_tween = create_tween()
	bgm_tween.tween_property(player_to_stop, "volume_db", -80.0, fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	bgm_tween.tween_callback(func():
		if player_to_stop != active_player and is_instance_valid(player_to_stop):
			player_to_stop.stop()
			player_to_stop.volume_db = -80.0
	)

func play_sfx(sfx_name: String):
	if sfx_muted:
		return
		
	if not sfx_tracks.has(sfx_name):
		printerr("AudioManager: SFX not found: ", sfx_name)
		return
		
	var now = Time.get_ticks_msec()
	# Debounce gleichen Soundeffekt innerhalb von 40ms (z.B. wenn mehrere Spieler gleichzeitig in Pipes gehen)
	if sfx_last_play_time.has(sfx_name) and (now - sfx_last_play_time[sfx_name]) < 40:
		return
	sfx_last_play_time[sfx_name] = now
		
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

# Erzeugt prozedural einen aufsteigenden Spannungs-Sound (Pitch-Sweep) und spielt ihn ab.
# Gibt den Player zurueck, damit er z.B. vorzeitig gestoppt werden kann.
func play_rising_sfx(duration: float = 3.0, start_hz: float = 180.0, end_hz: float = 1100.0) -> AudioStreamPlayer:
	if sfx_muted:
		return null
	var mix_rate := 22050
	var total := int(duration * mix_rate)
	var data := PackedByteArray()
	data.resize(total * 2)
	var phase := 0.0
	var phase2 := 0.0
	for i in total:
		var t := float(i) / total # 0..1
		# Exponentieller Sweep klingt "gleichmaessig" aufsteigend
		var freq := start_hz * pow(end_hz / start_hz, t)
		phase = fmod(phase + freq / mix_rate, 1.0)
		phase2 = fmod(phase2 + freq * 1.005 / mix_rate, 1.0) # leicht verstimmt -> breiter Klang
		var saw := (phase * 2.0 - 1.0) * 0.5 + (phase2 * 2.0 - 1.0) * 0.5
		var sine := sin(phase * TAU)
		# Tremolo, das schneller wird -> mehr Spannung
		var trem_rate: float = lerp(6.0, 22.0, t)
		var trem := 0.75 + 0.25 * sin(TAU * trem_rate * float(i) / mix_rate)
		# Huellkurve: kurzes Fade-in, Lautstaerke steigt an, kurzes Fade-out am Ende
		var env: float = min(1.0, t * 20.0) * lerp(0.45, 1.0, t) * min(1.0, (1.0 - t) * 40.0)
		var s := (sine * 0.6 + saw * 0.25) * trem * env * 0.6
		data.encode_s16(i * 2, int(clamp(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = data
	var asp := AudioStreamPlayer.new()
	asp.stream = wav
	asp.volume_db = volume_sfx
	add_child(asp)
	asp.play()
	asp.finished.connect(func(): asp.queue_free())
	return asp

func play_character_sfx(character_name: String, action: String = ""):
	if sfx_muted:
		return
		
	var formatted_name = character_name.to_lower().strip_edges()
	if formatted_name == "" or formatted_name == "unknown" or formatted_name == "cedi":
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
