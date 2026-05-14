extends GutTest

const SoundManager = preload("res://scripts/audio/sound_manager.gd")

func test_synth_params_bust_is_descending_saw():
	var p = SoundManager.synth_params("bust")
	assert_eq(float(p.get("frequency", 0.0)), 200.0, "bust starts at 200 Hz")
	assert_eq(float(p.get("duration_sec", 0.0)), 0.4)
	assert_eq(String(p.get("waveform_type", "")), "descending_saw")

func test_synth_params_crown_win_is_arpeggio():
	var p = SoundManager.synth_params("crown_win")
	assert_eq(String(p.get("waveform_type", "")), "arpeggio_ceg")
	assert_eq(float(p.get("duration_sec", 0.0)), 0.6)

func test_synth_params_unknown_returns_empty():
	var p = SoundManager.synth_params("not_a_cue")
	assert_true(p.is_empty(), "unknown cue name returns empty Dictionary")
