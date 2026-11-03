## Процедурный звук RE-RAIL: ветер, двигатель, шаги, удары, рык, радиопомехи, «голос эха».
## Никаких файлов — всё синтезируется при запуске (~0.5 с), в фоне.
extends Node

const RATE := 22050

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var streams := {}
var wind: AudioStreamPlayer
var drone: AudioStreamPlayer
var engine: AudioStreamPlayer
var radio_static: AudioStreamPlayer
var radio_voice: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1234
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	streams.step = _wav(_step())
	streams.swing = _wav(_swing())
	streams.hit = _wav(_hit())
	streams.hurt = _wav(_hurt())
	streams.growl = _wav(_growl())
	streams.pickup = _wav(_pickup())
	streams.clank = _wav(_clank())
	streams.click = _wav(_click())
	wind = _loop_player(_wind(), -10.0, "Music")
	drone = _loop_player(_drone(), -16.0, "Music")
	engine = _loop_player(_engine(), -80.0, "SFX")
	radio_static = _loop_player(_static(), -80.0, "SFX")
	radio_voice = _loop_player(_voice(), -80.0, "SFX")
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)


func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = streams[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch * _rng.randf_range(0.94, 1.06)
	p.play()


## Двигатель: громкость и частота «пыхтения» зависят от скорости дрезины.
func set_engine(speed01: float, running: bool) -> void:
	engine.volume_db = linear_to_db(0.0001 + (0.25 + 0.55 * speed01 if running else 0.0))
	engine.pitch_scale = 0.7 + speed01 * 1.1


## Радио: signal 0 — сплошные помехи, 1 — чистый голос.
func set_radio(open: bool, signal_level: float) -> void:
	if not open:
		radio_static.volume_db = -80.0
		radio_voice.volume_db = -80.0
		return
	radio_static.volume_db = linear_to_db(0.0001 + 0.5 * (1.0 - signal_level) + 0.05)
	radio_voice.volume_db = linear_to_db(0.0001 + 0.8 * signal_level)


# ------------------------------------------------------------ синтез

func _loop_player(samples: PackedFloat32Array, vol: float, bus: String) -> AudioStreamPlayer:
	var wav := _wav(samples)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = samples.size()
	var p := AudioStreamPlayer.new()
	p.stream = wav
	p.volume_db = vol
	p.bus = bus
	add_child(p)
	p.play()
	return p


func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(RATE * seconds))
	return b


## Бесшовная петля: конец плавно перетекает в начало.
func _seamless(b: PackedFloat32Array, fade_s: float) -> PackedFloat32Array:
	var f := int(RATE * fade_s)
	var n := b.size() - f
	var out := b.slice(0, n)
	for i in f:
		var t := float(i) / f
		out[i] = out[i] * t + b[n + i] * (1.0 - t)
	return out


func _wind() -> PackedFloat32Array:
	var b := _buf(8.5)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var cut := 0.02 + 0.015 * sin(t * TAU / 4.25) + 0.01 * sin(t * TAU / 1.7)
		lp += (randf_range(-1, 1) - lp) * cut
		lp2 += (lp - lp2) * cut
		b[i] = lp2 * 6.0 * (0.6 + 0.4 * sin(t * TAU / 8.5 * 2.0))
	return _seamless(b, 0.5)


func _drone() -> PackedFloat32Array:
	var b := _buf(8.0) # частоты кратны 0.125 Гц — ровная петля
	for i in b.size():
		var t := float(i) / RATE
		b[i] = 0.4 * sin(TAU * 55.0 * t) + 0.3 * sin(TAU * 55.25 * t) + 0.18 * sin(TAU * 82.5 * t) + 0.06 * sin(TAU * 110.125 * t)
	return b


func _engine() -> PackedFloat32Array:
	var b := _buf(0.5) # четыре «пыха» за петлю
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var ph := fmod(t, 0.125) / 0.125
		var env := exp(-ph * 6.0)
		lp += (randf_range(-1, 1) - lp) * 0.15
		b[i] = (lp * 1.6 + 0.6 * sin(TAU * 48.0 * t)) * env
	return b


func _static() -> PackedFloat32Array:
	var b := _buf(2.0)
	var hp := 0.0
	var prev := 0.0
	for i in b.size():
		var n := randf_range(-1, 1)
		hp = 0.7 * (hp + n - prev)
		prev = n
		var crackle := 1.0 if randf() < 0.002 else 0.0
		b[i] = hp * 0.5 + crackle * randf_range(-1, 1)
	return _seamless(b, 0.1)


## «Голос эха»: не речь, а призрачные слоги — форманты с вибрато и паузами.
func _voice() -> PackedFloat32Array:
	var b := _buf(4.0)
	var syll := [0.0, 0.3, 0.55, 0.95, 1.6, 1.85, 2.2, 2.9, 3.2]
	for i in b.size():
		var t := float(i) / RATE
		var env := 0.0
		for s in syll:
			var d: float = t - s
			if d > 0.0 and d < 0.28:
				env = maxf(env, sin(PI * d / 0.28))
		var f0 := 210.0 + 18.0 * sin(TAU * 5.5 * t) + 30.0 * sin(TAU * 0.4 * t)
		var ph := TAU * f0 * t
		var tone := 0.5 * sin(ph) + 0.3 * sin(ph * 2.0) + 0.25 * sin(ph * 3.0) + 0.12 * sin(ph * 5.0)
		b[i] = tone * env * 0.6
	return _seamless(b, 0.15)


func _step() -> PackedFloat32Array:
	var b := _buf(0.07)
	var lp := 0.0
	for i in b.size():
		lp += (randf_range(-1, 1) - lp) * 0.25
		b[i] = lp * exp(-float(i) / RATE * 60.0) * 2.0
	return b


func _swing() -> PackedFloat32Array:
	var b := _buf(0.18)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (randf_range(-1, 1) - lp) * (0.05 + t * 2.0)
		b[i] = lp * sin(PI * t / 0.18) * 1.5
	return b


func _hit() -> PackedFloat32Array:
	var b := _buf(0.25)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (sin(TAU * (90.0 - t * 200.0) * t) * 0.8 + randf_range(-1, 1) * 0.4 * exp(-t * 40.0)) * exp(-t * 14.0)
	return b


func _hurt() -> PackedFloat32Array:
	var b := _buf(0.35)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (sin(TAU * 60.0 * t) + randf_range(-1, 1) * 0.6) * exp(-t * 9.0)
	return b


func _growl() -> PackedFloat32Array:
	var b := _buf(0.9)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := 70.0 + 25.0 * sin(TAU * 7.0 * t)
		lp += (randf_range(-1, 1) - lp) * 0.08
		b[i] = (0.6 * sin(TAU * f * t) * (0.5 + 0.5 * sin(TAU * 31.0 * t)) + lp * 1.2) * sin(PI * t / 0.9)
	return b


func _pickup() -> PackedFloat32Array:
	var b := _buf(0.22)
	for i in b.size():
		var t := float(i) / RATE
		var f := 660.0 if t < 0.09 else 990.0
		b[i] = sin(TAU * f * t) * 0.5 * exp(-fmod(t, 0.09) * 25.0)
	return b


func _clank() -> PackedFloat32Array:
	var b := _buf(0.8)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (0.5 * sin(TAU * 410.0 * t) + 0.35 * sin(TAU * 1130.0 * t) + 0.2 * sin(TAU * 2370.0 * t)) * exp(-t * 6.0) + randf_range(-1, 1) * exp(-t * 80.0) * 0.5
	return b


func _click() -> PackedFloat32Array:
	var b := _buf(0.04)
	for i in b.size():
		b[i] = randf_range(-1, 1) * exp(-float(i) / RATE * 150.0)
	return b


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	var k := 0.8 / peak
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] * k, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav
