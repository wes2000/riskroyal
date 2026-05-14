extends Node

const SAMPLE_RATE := 22050

var _players: Dictionary = {}

func _ready() -> void:
	var cues := ["chip_transfer", "bust", "crown_win", "match_end", "button_press", "twist_stinger"]
	for cue in cues:
		var player := AudioStreamPlayer.new()
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = SAMPLE_RATE
		stream.buffer_length = 1.5
		player.stream = stream
		player.name = cue
		add_child(player)
		_players[cue] = player
	# Plan C Task 2: scan scripts/audio/sfx/ for user-provided overrides.
	_scan_asset_slots()

func play_chip_transfer() -> void:
	_play("chip_transfer")

func play_bust() -> void:
	_play("bust")

func play_crown_win() -> void:
	_play("crown_win")

func play_match_end() -> void:
	_play("match_end")

func play_button_press() -> void:
	_play("button_press")

func play_twist_stinger() -> void:
	_play("twist_stinger")

# Plan C Task 3: signal-to-SFX dispatcher.
func bind_controller(controller) -> void:
	if controller == null:
		return
	if not controller.player_busted.is_connected(_on_player_busted_for_sfx):
		controller.player_busted.connect(_on_player_busted_for_sfx)
	if not controller.crown_awarded.is_connected(_on_crown_awarded_for_sfx):
		controller.crown_awarded.connect(_on_crown_awarded_for_sfx)
	if not controller.house_twist_announced.is_connected(_on_house_twist_for_sfx):
		controller.house_twist_announced.connect(_on_house_twist_for_sfx)
	if not controller.match_ended.is_connected(_on_match_ended_for_sfx):
		controller.match_ended.connect(_on_match_ended_for_sfx)

func _on_player_busted_for_sfx(_peer_id: int, _chip_loss: int) -> void:
	play_bust()

func _on_crown_awarded_for_sfx(_peer_id: int, _count: int) -> void:
	play_crown_win()

func _on_house_twist_for_sfx(_twist_dict: Dictionary) -> void:
	play_twist_stinger()

func _on_match_ended_for_sfx(_rankings: Array) -> void:
	play_match_end()

static func signal_to_cue_name(signal_name: String) -> String:
	match signal_name:
		"player_busted":
			return "bust"
		"crown_awarded":
			return "crown_win"
		"house_twist_announced":
			return "twist_stinger"
		"match_ended":
			return "match_end"
		_:
			return ""

func _play(cue_name: String) -> void:
	if not _players.has(cue_name):
		return
	var player: AudioStreamPlayer = _players[cue_name]
	# If the stream is file-backed (Task 2 asset swap), just play it.
	if not (player.stream is AudioStreamGenerator):
		player.play()
		return
	# Procedural path: start playback then push synthesized samples.
	player.play()
	var pb = player.get_stream_playback()
	if pb == null:
		return
	var params := synth_params(cue_name)
	if params.is_empty():
		return
	var samples := _synth_waveform(params)
	var i := 0
	while i < samples.size():
		pb.push_frame(Vector2(samples[i], samples[i]))
		i += 1

func _synth_waveform(params: Dictionary) -> PackedFloat32Array:
	var waveform_type: String = params.get("waveform_type", "")
	var duration_sec: float = params.get("duration_sec", 0.1)
	var frequency: float = params.get("frequency", 440.0)
	var num_samples := int(SAMPLE_RATE * duration_sec)
	var samples := PackedFloat32Array()
	samples.resize(num_samples)

	match waveform_type:
		"descending_saw":
			# Frequency descends from `frequency` to frequency*0.25 over duration
			for i in range(num_samples):
				var t: float = float(i) / float(num_samples)
				var freq: float = frequency * (1.0 - t * 0.75)
				var phase: float = fmod(float(i) * freq / float(SAMPLE_RATE), 1.0)
				samples[i] = (phase * 2.0 - 1.0) * (1.0 - t)
		"arpeggio_ceg":
			# C-E-G arpeggio: three equal segments
			var freqs := [261.63, 329.63, 392.0]
			var seg_len := num_samples / 3
			for i in range(num_samples):
				var seg := mini(i / seg_len, 2)
				var freq: float = freqs[seg]
				var t: float = float(i) / float(num_samples)
				var phase: float = fmod(float(i) * freq / float(SAMPLE_RATE), 1.0)
				# sine approximation via triangle
				var tri: float = phase * 2.0 - 1.0
				samples[i] = tri * (1.0 - t * 0.3)
		"descending_tone":
			# Sine-like tone descending from `frequency` to frequency/2
			for i in range(num_samples):
				var t: float = float(i) / float(num_samples)
				var freq: float = frequency * (1.0 - t * 0.5)
				var phase: float = fmod(float(i) * freq / float(SAMPLE_RATE), 1.0)
				var tri: float = phase * 2.0 - 1.0
				samples[i] = tri * (1.0 - t)
		"click":
			# Short sharp click: decaying noise burst
			for i in range(num_samples):
				var t: float = float(i) / float(num_samples)
				var phase: float = fmod(float(i) * frequency / float(SAMPLE_RATE), 1.0)
				samples[i] = (phase * 2.0 - 1.0) * exp(-t * 20.0)
		"rising_sweep":
			# Frequency rises from `frequency` to params.frequency_end
			var freq_end: float = params.get("frequency_end", frequency * 4.0)
			for i in range(num_samples):
				var t: float = float(i) / float(num_samples)
				var freq: float = frequency + (freq_end - frequency) * t
				var phase: float = fmod(float(i) * freq / float(SAMPLE_RATE), 1.0)
				samples[i] = phase * 2.0 - 1.0
		"soft_tone":
			# Soft sine-like tone with fade in/out
			for i in range(num_samples):
				var t: float = float(i) / float(num_samples)
				var envelope: float = sin(t * PI)
				var phase: float = fmod(float(i) * frequency / float(SAMPLE_RATE), 1.0)
				var tri: float = phase * 2.0 - 1.0
				samples[i] = tri * envelope * 0.5
		_:
			# Silence for unknown waveform types
			for i in range(num_samples):
				samples[i] = 0.0

	return samples

static func synth_params(cue_name: String) -> Dictionary:
	match cue_name:
		"bust":
			return {
				"frequency": 200.0,
				"duration_sec": 0.4,
				"waveform_type": "descending_saw",
			}
		"crown_win":
			return {
				"frequency": 261.63,
				"duration_sec": 0.6,
				"waveform_type": "arpeggio_ceg",
			}
		"match_end":
			return {
				"frequency": 440.0,
				"duration_sec": 1.0,
				"waveform_type": "descending_tone",
			}
		"button_press":
			return {
				"frequency": 1000.0,
				"duration_sec": 0.05,
				"waveform_type": "click",
			}
		"twist_stinger":
			return {
				"frequency": 200.0,
				"frequency_end": 800.0,
				"duration_sec": 0.5,
				"waveform_type": "rising_sweep",
			}
		"chip_transfer":
			return {
				"frequency": 600.0,
				"duration_sec": 0.15,
				"waveform_type": "soft_tone",
			}
		_:
			return {}

static func expected_slot_filenames() -> Array[String]:
	return ["chip_transfer.ogg", "bust.ogg", "crown_win.ogg", "match_end.ogg", "button_press.ogg", "twist_stinger.ogg"]

static func cue_name_for_filename(filename: String) -> String:
	if not filename.ends_with(".ogg"):
		return ""
	var stem = filename.substr(0, filename.length() - 4)
	for known in ["chip_transfer", "bust", "crown_win", "match_end", "button_press", "twist_stinger"]:
		if stem == known:
			return stem
	return ""

func _scan_asset_slots() -> void:
	var dir = DirAccess.open("res://scripts/audio/sfx")
	if dir == null:
		return
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var cue = cue_name_for_filename(fname)
			if cue != "" and _players.has(cue):
				var stream = load("res://scripts/audio/sfx/%s" % fname)
				if stream != null:
					_players[cue].stream = stream
		fname = dir.get_next()
	dir.list_dir_end()
