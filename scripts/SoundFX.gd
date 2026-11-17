extends Node
class_name SoundFX

## Procedural PCM AudioStreamWAV Synthesizer for Strings & Steel.
## Generates crisp metallic clashes, blade whooshes, flesh cleaves, string snaps,
## and timber stage thuds in memory with zero external audio assets needed.

const SAMPLE_RATE := 22050
const POLYPHONY := 10

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_idx: int = 0
var muted: bool = false


func _ready() -> void:
	for i in range(POLYPHONY):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)

	_streams["whoosh"] = _gen_whoosh(0.18)
	_streams["clang"] = _gen_clang(0.45, false)
	_streams["perfect_parry"] = _gen_clang(0.65, true)
	_streams["flesh"] = _gen_flesh(0.24, false)
	_streams["sever"] = _gen_flesh(0.38, true)
	_streams["snap"] = _gen_string_snap(0.26)
	_streams["thud"] = _gen_thud(0.22)
	_streams["ko_boom"] = _gen_ko_boom(0.85)


func play_sfx(key: String, pitch_jitter: float = 0.08, db_offset: float = 0.0) -> void:
	if muted or not _streams.has(key):
		return
	var p := _players[_next_idx]
	_next_idx = (_next_idx + 1) % _players.size()
	p.stream = _streams[key]
	p.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.volume_db = db_offset
	p.play()


func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := clampi(int(round(samples[i] * 32767.0)), -32768, 32767)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav


func _gen_whoosh(dur: float) -> AudioStreamWAV:
	var n := int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in range(n):
		var t := float(i) / float(n)
		var env := sin(t * PI) * (1.0 - t * 0.35)
		var alpha := 0.06 + 0.25 * sin(t * PI)
		lp = lp + alpha * (randf_range(-1.0, 1.0) - lp)
		out[i] = lp * env * 0.42
	return _make_wav(out)


func _gen_clang(dur: float, heroic: bool) -> AudioStreamWAV:
	var n := int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var freqs := [980.0, 1490.0, 2320.0, 3410.0, 4820.0] if not heroic else [780.0, 1170.0, 1980.0, 2940.0, 4120.0]
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var u := float(i) / float(n)
		var strike := exp(-u * 28.0) * randf_range(-0.6, 0.6)
		var ring := 0.0
		for j in range(freqs.size()):
			var decay := exp(-u * (4.0 + float(j) * 1.9))
			ring += sin(TAU * freqs[j] * t) * decay * (0.24 / (1.0 + float(j) * 0.35))
		out[i] = clampf((strike + ring) * (0.72 if heroic else 0.55), -0.95, 0.95)
	return _make_wav(out)


func _gen_flesh(dur: float, heavy: bool) -> AudioStreamWAV:
	var n := int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var u := float(i) / float(n)
		var thump := sin(TAU * lerpf(165.0, 42.0, minf(1.0, u * 2.5)) * t) * exp(-u * 9.0)
		var squelch_noise := randf_range(-1.0, 1.0)
		lp = lp + (0.22 if heavy else 0.16) * (squelch_noise - lp)
		var wet := lp * exp(-u * 6.5) * (0.8 if heavy else 0.5)
		var crack := sin(TAU * 420.0 * t) * exp(-u * 32.0) * (0.45 if heavy else 0.15)
		out[i] = clampf((thump * 0.65 + wet + crack) * 0.75, -0.95, 0.95)
	return _make_wav(out)


func _gen_string_snap(dur: float) -> AudioStreamWAV:
	var n := int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var u := float(i) / float(n)
		var f := lerpf(620.0, 290.0, u)
		var twang := (sin(TAU * f * t) + 0.5 * sin(TAU * f * 2.03 * t)) * exp(-u * 8.5)
		out[i] = clampf(twang * 0.55, -0.95, 0.95)
	return _make_wav(out)


func _gen_thud(dur: float) -> AudioStreamWAV:
	var n := int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var u := float(i) / float(n)
		var s := sin(TAU * lerpf(120.0, 48.0, u) * t) * exp(-u * 12.0)
		out[i] = clampf(s * 0.6, -0.95, 0.95)
	return _make_wav(out)


func _gen_ko_boom(dur: float) -> AudioStreamWAV:
	var n := int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / float(SAMPLE_RATE)
		var u := float(i) / float(n)
		var sub := sin(TAU * lerpf(92.0, 28.0, minf(1.0, u * 1.4)) * t) * exp(-u * 3.8)
		var brass := sin(TAU * 138.0 * t) * exp(-u * 5.2) * 0.25
		out[i] = clampf((sub * 0.8 + brass) * 0.8, -0.95, 0.95)
	return _make_wav(out)
