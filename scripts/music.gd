## Процедурная адаптивная музыка RE-RAIL. Ничего не записано заранее: при запуске
## (в фоновом потоке) синтезируются три петли на одной гармонии ля-минор
## Am – F – C – G – Am – F – E – E (72 удара в минуту, 8 тактов ≈ 27 с):
##   road   — «дорога»: гитарный перебор (Karplus-Strong), бас и губная гармошка;
##   home   — «дом»: музыкальная шкатулка и тёплый пэд — внутри дрезины;
##   danger — «опасность»: глухой пульс барабана и тремоло на ми — когда твари рядом.
## Слои играют одновременно и плавно смешиваются по состоянию игры.
extends Node

const RATE := 22050
const BPM := 72.0
const BEATS := 32 # 8 тактов по 4 доли

## Аккорды по тактам: MIDI-ноты (бас, затем голоса).
const CHORDS := [
	[45, 57, 60, 64], # Am
	[41, 57, 60, 65], # F
	[48, 55, 60, 64], # C
	[43, 55, 59, 62], # G
	[45, 57, 60, 64], # Am
	[41, 57, 60, 65], # F
	[40, 56, 59, 64], # E
	[40, 56, 59, 62], # E7
]
## Мелодия гармошки: [доля от начала, MIDI, длительность в долях]
const MELODY := [
	[0.0, 76, 1.5], [2.0, 74, 0.5], [2.5, 72, 1.5],
	[4.0, 72, 1.0], [5.0, 69, 2.5],
	[8.0, 67, 1.0], [9.0, 69, 1.0], [10.0, 72, 2.0],
	[12.0, 71, 1.0], [13.0, 67, 2.5],
	[16.0, 76, 1.5], [18.0, 79, 0.5], [18.5, 76, 1.5],
	[20.0, 77, 1.0], [21.0, 76, 0.5], [21.5, 74, 2.0],
	[24.0, 71, 1.5], [26.0, 72, 0.5], [26.5, 74, 1.5],
	[28.0, 76, 4.0],
]

var players := {}
var target := {"road": 0.0, "home": 0.0, "danger": 0.0}
var level := {"road": 0.0, "home": 0.0, "danger": 0.0}
var loaded := false
var _task := -1
var _streams := {}
var _mutex := Mutex.new()


func _ready() -> void:
	for k in target:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		players[k] = p
	_task = WorkerThreadPool.add_task(_render_all)


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)


## Задать желаемую громкость слоёв (0..1). Смешивание плавное.
func mix(road: float, home: float, danger: float) -> void:
	target.road = road
	target.home = home
	target.danger = danger


func _process(delta: float) -> void:
	if not loaded:
		_mutex.lock()
		var done := _streams.size() == 3
		_mutex.unlock()
		if not done:
			return
		loaded = true
		for k in players:
			players[k].stream = _streams[k]
			players[k].play()
	for k in level:
		level[k] = move_toward(level[k], target[k], delta * 0.35)
		players[k].volume_db = linear_to_db(maxf(level[k], 0.0001))


# ------------------------------------------------------------ синтез

static func _f(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


func _render_all() -> void:
	var spb := int(round(RATE * 60.0 / BPM)) # сэмплов на долю
	var n := spb * BEATS
	var road := _render_road(n, spb)
	var home := _render_home(n, spb)
	var danger := _render_danger(spb * 8, spb)
	_mutex.lock()
	_streams.road = _wav(road)
	_streams.home = _wav(home)
	_streams.danger = _wav(danger)
	_mutex.unlock()


## Пишем звук в кольцевой буфер: хвосты нот, вылезшие за конец, уходят в начало —
## петля замыкается без щелчка.
func _add(buf: PackedFloat32Array, start: int, note: PackedFloat32Array, gain: float) -> void:
	var n := buf.size()
	for i in note.size():
		var j := (start + i) % n
		buf[j] += note[i] * gain


## Струна Karplus-Strong.
func _pluck(freq: float, seconds: float, bright: float) -> PackedFloat32Array:
	var len := int(RATE * seconds)
	var out := PackedFloat32Array()
	out.resize(len)
	var period := maxi(2, int(round(RATE / freq)))
	var ring := PackedFloat32Array()
	ring.resize(period)
	var prev := 0.0
	for i in period:
		prev = prev * (1.0 - bright) + randf_range(-1.0, 1.0) * bright
		ring[i] = prev
	var idx := 0
	for i in len:
		var cur := ring[idx]
		var nxt := ring[(idx + 1) % period]
		ring[idx] = (cur + nxt) * 0.5 * 0.996
		idx = (idx + 1) % period
		out[i] = cur
	return out


## Губная гармошка: квадратно-пилообразный тон с вибрато и мягкой атакой.
func _harmonica(freq: float, seconds: float) -> PackedFloat32Array:
	var len := int(RATE * seconds)
	var out := PackedFloat32Array()
	out.resize(len)
	var ph := 0.0
	for i in len:
		var t := float(i) / RATE
		var vib := 1.0 + 0.006 * sin(TAU * 5.2 * t) * clampf(t * 2.0, 0.0, 1.0)
		ph += TAU * freq * vib / RATE
		var tone := sin(ph) * 0.6 + sin(ph * 2.0) * 0.25 + sin(ph * 3.0) * 0.18 + sin(ph * 4.0) * 0.08
		var env := clampf(t / 0.08, 0.0, 1.0) * clampf((seconds - t) / 0.25, 0.0, 1.0)
		out[i] = tone * env
	return out


func _bell(freq: float, seconds: float) -> PackedFloat32Array:
	var len := int(RATE * seconds)
	var out := PackedFloat32Array()
	out.resize(len)
	for i in len:
		var t := float(i) / RATE
		out[i] = (sin(TAU * freq * t) + 0.35 * sin(TAU * freq * 2.76 * t) * exp(-t * 3.0)) * exp(-t * 2.2)
	return out


func _pad(freqs: Array, seconds: float) -> PackedFloat32Array:
	var len := int(RATE * seconds)
	var out := PackedFloat32Array()
	out.resize(len)
	for i in len:
		var t := float(i) / RATE
		var v := 0.0
		for f in freqs:
			v += sin(TAU * f * t) + 0.3 * sin(TAU * f * 1.003 * t)
		var env := clampf(t / 0.8, 0.0, 1.0) * clampf((seconds - t) / 0.8, 0.0, 1.0)
		out[i] = v * env / freqs.size()
	return out


func _render_road(n: int, spb: int) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n)
	var pattern := [0, 1, 2, 3, 2, 1, 2, 3] # перебор восьмыми
	for bar in 8:
		var ch: Array = CHORDS[bar]
		var bar_start := bar * 4 * spb
		_add(buf, bar_start, _pluck(_f(ch[0] - 12 + 12), 2.5, 0.35), 0.55) # бас
		_add(buf, bar_start + 2 * spb, _pluck(_f(ch[0]), 1.6, 0.3), 0.3)
		for k in 8:
			var note: int = ch[pattern[k]] if pattern[k] > 0 else ch[1]
			_add(buf, bar_start + k * spb / 2, _pluck(_f(note), 1.4, 0.55), 0.22 if k % 2 == 0 else 0.16)
	for m in MELODY:
		_add(buf, int(m[0] * spb), _harmonica(_f(m[1]), m[2] * 60.0 / BPM), 0.14)
	return buf


func _render_home(n: int, spb: int) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n)
	for bar in 8:
		var ch: Array = CHORDS[bar]
		var bar_start := bar * 4 * spb
		_add(buf, bar_start, _pad([_f(ch[0]), _f(ch[1]), _f(ch[2])], 4.0 * 60.0 / BPM + 0.4), 0.18)
		for k in 4:
			var note: int = ch[1 + (k % 3)] + 12
			_add(buf, bar_start + k * spb, _bell(_f(note), 1.6), 0.2)
	for m in MELODY:
		if int(m[0]) % 4 == 0:
			_add(buf, int(m[0] * spb) + spb / 2, _bell(_f(m[1] + 12), 2.0), 0.12)
	return buf


func _render_danger(n: int, spb: int) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n)
	var drum := PackedFloat32Array()
	drum.resize(int(RATE * 0.5))
	for i in drum.size():
		var t := float(i) / RATE
		drum[i] = sin(TAU * (60.0 - t * 60.0) * t) * exp(-t * 9.0) + randf_range(-1, 1) * exp(-t * 60.0) * 0.3
	for b in 8:
		_add(buf, b * spb, drum, 0.7 if b % 2 == 0 else 0.45)
		_add(buf, b * spb + spb * 3 / 4, drum, 0.25)
	# тремоло на ми и си — тревожная квинта
	for i in n:
		var t := float(i) / RATE
		var trem := 0.5 + 0.5 * sin(TAU * 7.0 * t)
		buf[i] += (sin(TAU * _f(52) * t) + 0.6 * sin(TAU * _f(59) * t) + 0.3 * sin(TAU * _f(65) * t)) * trem * 0.12
	return buf


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
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = samples.size()
	return wav
