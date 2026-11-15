extends Node
## 程序化音效：启动时合成 WAV，无需外部音频资源

const RATE := 22050

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _idx := 0

func _ready() -> void:
	_streams["swing"] = _make(0.18, "noise", 0.22, 900.0)
	_streams["hit"] = _make(0.16, "metal", 0.42, 520.0)
	_streams["hurt"] = _make(0.22, "noise", 0.36, 220.0)
	_streams["dodge"] = _make(0.20, "noise", 0.18, 1400.0)
	_streams["parry"] = _make(0.28, "metal", 0.40, 1180.0)
	_streams["spell"] = _make(0.45, "sine", 0.30, 320.0)
	_streams["transform"] = _make(0.70, "sweep", 0.36, 180.0)
	_streams["death"] = _make(0.50, "noise", 0.34, 140.0)
	_streams["coin"] = _make(0.18, "chime", 0.26, 1600.0)

	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

func play(sound: String) -> void:
	if not _streams.has(sound) or _players.is_empty():
		return
	var p := _players[_idx]
	_idx = (_idx + 1) % _players.size()
	p.stream = _streams[sound]
	p.play()

func _make(duration: float, kind: String, volume: float, freq: float) -> AudioStreamWAV:
	var count := int(RATE * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261115
	var phase := 0.0

	for i in count:
		var t := float(i) / RATE
		var env := exp(-t * (5.0 / maxf(duration, 0.01)))
		var s := 0.0
		match kind:
			"sine":
				s = sin(TAU * freq * t)
			"noise":
				s = rng.randf_range(-1.0, 1.0) * 0.8
			"metal":
				s = sin(TAU * freq * t) * 0.6 \
					+ sin(TAU * freq * 2.7 * t) * 0.25 \
					+ rng.randf_range(-0.25, 0.25)
			"sweep":
				phase += TAU * (freq + 600.0 * t / maxf(duration, 0.01)) / RATE
				s = sin(phase) * 0.8
			"chime":
				s = sin(TAU * freq * t) * 0.5 + sin(TAU * freq * 1.5 * t) * 0.4
			_:
				s = rng.randf_range(-1.0, 1.0)
		var v := clampf(s * env * volume, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))

	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
