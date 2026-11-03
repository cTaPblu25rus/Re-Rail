## Автоигрок RE-RAIL: проходит пролог от начала до конца через тот же `ctl`,
## что и сенсорный HUD. Запуск: godot --headless --path . -- --autoplay [--shots=папка]
## Код выхода 0 — пролог пройден.
##
## План: доехать до кучи №1 → обыскать → вернуться в дрезину → доехать до станции →
## обыскать кучи у станции → починить генератор → поймать голос дочери по радио.
## В бою: держит фонарь на ближайшем ржавце, бьёт ломом, если тот подобрался.
extends Node

const TIMEOUT := 260.0

var game: Node
var shots_dir := ""
var t := 0.0
var phase := 0
var phase_t := 0.0
var shot_t := 0.0
var shot_n := 0
var log_phase := -1
var done := false
var stop_after := -1

# Последовательность целей: [вид, параметр]
var plan := [
	["drive", 880.0],
	["exit", null],
	["loot", 0],
	["board", null],
	["drive", 2530.0],
	["exit", null],
	["loot", 3],
	["loot", 4],
	["repair", null],
	["radio", 103.7],
]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(shots_dir)
	Engine.time_scale = 3.0 if shots_dir == "" else 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stop-after="):
			stop_after = int(a.trim_prefix("--stop-after="))
	if OS.get_cmdline_user_args().has("--continue"):
		print("LOAD: " + state_line())
		get_tree().quit(0)
		done = true


## Снимок состояния для проверки сохранений (--stop-after=N, затем --continue).
func state_line() -> String:
	var looted := []
	for p in game.piles:
		looted.append(1 if p.looted else 0)
	return "aboard=%s train=%d player=%d,%d scrap=%d coal=%d health=%d looted=%s gen=%s" % [
		game.aboard, game.train_x, game.player_pos.x, game.player_pos.y, game.inv.scrap,
		game.inv.coal, game.stats.health, str(looted), game.generator_fixed]


func _process(delta: float) -> void:
	if done:
		return
	t += delta
	phase_t += delta
	if game.dead:
		print("BOT: Илья погиб на фазе %d — очнуться" % phase)
		game.respawn()
		phase = 0 if game.train_x < 2400.0 else 4
		_skip_finished()
	if game.finished:
		_finish(true)
		return
	if t > TIMEOUT:
		_finish(false)
		return
	if stop_after >= 0 and phase >= stop_after:
		game.save_game()
		print("SAVE: " + state_line())
		done = true
		get_tree().quit(0)
		return
	if phase != log_phase:
		log_phase = phase
		phase_t = 0.0
		if phase < plan.size():
			print("BOT: t=%.0f фаза %d %s  (здоровье %d, рассудок %d, хлам %d, уголь %d)" % [t, phase, str(plan[phase]), game.stats.health, game.stats.sanity, game.inv.scrap, game.inv.coal])
	_fight()
	if phase < plan.size():
		_step(plan[phase])
	if shots_dir != "":
		shot_t += delta
		if shot_t > 4.0:
			shot_t = 0.0
			_shot("s%02d" % shot_n)
			shot_n += 1


## Пропустить уже выполненные «обыскать» после воскрешения.
func _skip_finished() -> void:
	while phase < plan.size() and plan[phase][0] == "loot" and game.piles[plan[phase][1]].looted:
		phase += 1


func _next() -> void:
	game.ctl.move = Vector2.ZERO
	game.press_context(false)
	phase += 1
	_skip_finished()


func _step(s: Array) -> void:
	match s[0]:
		"drive":
			var target: float = s[1]
			var dx: float = target - game.train_x
			if absf(dx) < 25.0 and absf(game.train_v) < 8.0:
				_next()
			else:
				var brake: float = game.train_v * game.train_v / (2.0 * game.TRAIN_ACCEL * 0.8)
				game.ctl.move = Vector2(signf(dx) if absf(dx) > brake + 10.0 else 0.0, 0)
		"exit":
			game.ctl.move = Vector2.ZERO
			if game.aboard:
				game.press_context(true)
			else:
				_next()
		"board":
			if game.aboard:
				_next()
			else:
				_walk_to(game.door_pos(), 24.0)
				if game.context().kind == "board":
					game.press_context(true)
		"loot":
			var p: Dictionary = game.piles[s[1]]
			if p.looted:
				_next()
				return
			if _walk_to(p.pos + Vector2(0, 8), 14.0):
				game.press_context(true)
		"repair":
			if game.generator_fixed:
				_next()
				return
			if _walk_to(Vector2(2860, -88), 20.0):
				game.press_context(true)
		"radio":
			game.ctl.move = Vector2.ZERO
			if not game.radio_open:
				game.toggle_radio()
			game.radio_freq = s[1]


## Идти к точке; true — пришли. Простой обход препятствий: если застряли — шаг вбок.
func _walk_to(target: Vector2, eps: float) -> bool:
	var d: Vector2 = target - game.player_pos
	if d.length() < eps:
		game.ctl.move = Vector2.ZERO
		return true
	var dir := d.normalized()
	var before: Vector2 = game.player_pos
	game.ctl.move = dir
	if phase_t > 1.0 and int(phase_t * 2.0) % 6 == 5:
		game.ctl.move = dir.orthogonal()
	return false


func _fight() -> void:
	if game.aboard:
		game.ctl.aiming = false
		return
	var best: Dictionary = {}
	var bd := 220.0
	for m in game.monsters:
		var d: float = m.pos.distance_to(game.player_pos)
		if d < bd:
			bd = d
			best = m
	if best.is_empty():
		game.ctl.aiming = false
		if not game.flashlight_on and game.stats.battery > 5.0:
			game.toggle_flashlight()
		return
	game.ctl.aim = (best.pos - game.player_pos).normalized()
	game.ctl.aiming = true
	if bd < 26.0:
		game.attack()
	if game.stats.health < 45.0 and game.inv.medkit > 0:
		game.use_item("medkit")
	if game.stats.sanity < 25.0 and game.inv.torch > 0 and game.torch_left <= 0.0:
		game.use_item("torch")


func _finish(ok: bool) -> void:
	done = true
	print("BOT: %s за %.0f с игрового времени (здоровье %d, рассудок %d, хлам %d, уголь %d)" % [
		"ПРОЛОГ ПРОЙДЕН" if ok else "НЕ ПРОЙДЕНО (таймаут)", t, game.stats.health, game.stats.sanity, game.inv.scrap, game.inv.coal])
	if shots_dir != "":
		await get_tree().create_timer(0.5).timeout
		_shot("final")
	get_tree().quit(0 if ok else 1)


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots_dir, name])
