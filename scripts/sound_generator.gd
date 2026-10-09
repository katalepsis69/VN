class_name SoundGenerator
extends RefCounted

## Generates procedural 8-bit / retro visual novel UI and typewriter sounds in pure GDScript.
## Zero external audio dependencies required.

static func create_typewriter_blip(pitch_hz: float = 650.0) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 22050
	var sample_count := 450 # ~20ms ultra crisp blip
	var data := PackedByteArray()
	data.resize(sample_count)
	
	for i in range(sample_count):
		var t := float(i) / 22050.0
		var envelope := 1.0 - (float(i) / float(sample_count))
		# Pleasant triangle/sine blend
		var val := sin(t * pitch_hz * TAU) * envelope * 80.0
		data[i] = int(128.0 + val) & 0xFF
		
	wav.data = data
	return wav

static func create_advance_click() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 22050
	var sample_count := 880 # ~40ms gentle wood/soft click
	var data := PackedByteArray()
	data.resize(sample_count)
	
	for i in range(sample_count):
		var t := float(i) / 22050.0
		var envelope := exp(-float(i) / 120.0) # Fast exponential decay
		var val := (sin(t * 320.0 * TAU) + sin(t * 540.0 * TAU) * 0.5) * envelope * 90.0
		data[i] = int(128.0 + val) & 0xFF
		
	wav.data = data
	return wav
