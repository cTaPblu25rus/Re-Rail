## Автоигрок RE-RAIL: проходит ВСЮ игру (4 главы и финал) по планам из data/chapters.json
## («bot» у каждой главы) через тот же `ctl` и те же окна, что и игрок.
## Запуск: godot --headless --path . -- --autoplay [--shots=папка]
## Код выхода 0 — игра пройдена до концовки.
## Проверка сохранений: --stop-after=N (сохранить на шаге N главы 1 и выйти), затем --continue.
##
## Шаги плана: drive X · exit · board · loot i · talk id [выборы] · goal · safe · radio f ·
##             craft id · upgrade id · next (доехать до конца перегона)
extends Node

const CHAPTER_TIMEOUT := 300.0

static var total_t := 0.0
static var deaths := 0

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
var plan: Array = []
var did := {} # разовые шаги (craft/upgrade), уже выполненные
var talk_step := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(shots_dir)
		elif a.begins_with("--stop-after="):
			stop_after = int(a.trim_prefix("--stop-after="))
	Engine.time_scale = 3.0 if shots_dir == "" else 1.0
	plan = game.chapter.bot
	if OS.get_cmdline_user_args().has("--continue"):
		print("LOAD: " + state_line())
		done = true
		get_tree().quit(0)
		return
	print("BOT: ===== %s =====" % game.chapter.name)


## Снимок состояния для проверки сохранений.
func state_line() -> String:
	var looted := []
	for p in game.piles:
		looted.append(1 if p.looted else 0)
	return "ch=%d aboard=%s train=%d player=%d,%d scrap=%d coal=%d health=%d karma=%d looted=%s goal=%s" % [
		game.chapter_i, game.aboard, game.train_x, game.player_pos.x, game.player_pos.y, game.inv.scrap,
		game.inv.coal, game.stats.health, game.karma, str(looted), game.goal_done]


func _process(delta: float) -> void:
	if done:
		return
	t += delta
	total_t += delta
	phase_t += delta
	if game.finished:
		_finish(true)
		return
	if t > CHAPTER_TIMEOUT:
		print("BOT: застрял на шаге %d %s · Илья %s · контекст %s · меню %s" % [phase, str(plan[phase]) if phase < plan.size() else "-", str(game.player_pos), str(game.context()), str(game.menu.screen.get("title", "-"))])
		_finish(false)
		return
	if game.dead:
		deaths += 1
		print("BOT: Илья погиб на шаге %d — очнуться" % phase)
		game.respawn()
		phase = 0
	# карточка главы и прочие окна, открытые не нами — закрыть
	if game.menu.is_open() and (phase >= plan.size() or plan[phase][0] != "talk"):
		game.menu.close()
	if stop_after >= 0 and phase >= stop_after:
		game.save_game()
		print("SAVE: " + state_line())
		done = true
		get_tree().quit(0)
		return
	if phase != log_phase:
		log_phase = phase
		phase_t = 0.0
		talk_step = 0
		if phase < plan.size():
			print("BOT: t=%.0f шаг %d %s  (здоровье %d, хлам %d, ткань %d, химия %d, уголь %d, карма %d)" % [
				t, phase, str(plan[phase]), game.stats.health, game.inv.scrap, game.inv.cloth, game.inv.chem, game.inv.coal, game.karma])
	_fight()
	_survive()
	if phase < plan.size():
		_step(plan[phase])
	if shots_dir != "":
		shot_t += delta
		if shot_t > 5.0:
			shot_t = 0.0
			_shot("c%d_%02d" % [game.chapter_i + 1, shot_n])
			shot_n += 1


func _next() -> void:
	game.ctl.move = Vector2.ZERO
	game.press_context(false)
	phase += 1


func _step(s: Array) -> void:
	match s[0]:
		"drive":
			if not game.aboard:
				_next()
				return
			var target: float = s[1]
			var dx: float = target - game.train_x
			if absf(dx) < 25.0 and absf(game.train_v) < 8.0:
				_next()
			else:
				var brake: float = game.train_v * game.train_v / (2.0 * game.TRAIN_ACCEL * 0.8)
				game.ctl.move = Vector2(signf(dx) if absf(dx) > brake + 10.0 else 0.0, 0)
		"next":
			if not game.aboard:
				_walk_to(game.door_pos(), 24.0)
				if game.context().kind == "board":
					game.press_context(true)
				return
			game.ctl.move = Vector2(1, 0) # смена главы перезагрузит сцену
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
				var k: String = game.context().kind
				if k == "board" or k == "patch":
					game.press_context(true)
		"loot":
			var p: Dictionary = game.piles[s[1]]
			if p.looted:
				_next()
				return
			if _walk_to(p.pos + Vector2(0, 8), 14.0):
				game.press_context(true)
		"talk":
			_talk(s[1], s[2])
		"goal":
			if game.goal_done:
				_next()
				return
			if _walk_to(game.goal.pos + Vector2(0, 14), 18.0):
				if not game.can_afford(game.goal.cost):
					print("BOT: не хватает на цель: %s" % game.cost_text(game.goal.cost))
					_finish(false)
					return
				game.press_context(true)
		"safe":
			if game.safe.is_empty() or game.safe.open:
				_next()
				return
			if _walk_to(game.safe.pos + Vector2(0, 10), 14.0):
				game.press_context(true)
				if not game.safe.open:
					print("BOT: сейф не открылся (нет кода)")
					_finish(false)
		"radio":
			game.ctl.move = Vector2.ZERO
			if not game.radio_open:
				game.toggle_radio()
			game.radio_freq = s[1]
			var e: Dictionary = game.radio_echo
			if (not e.is_empty() and e.done) or phase_t > 8.0:
				if game.radio_open:
					game.toggle_radio()
				_next()
		"inside":
			game.ctl.move = Vector2.ZERO
			if absf(game.train_v) < 5.0 and not game.interior.open:
				game.interior.enter()
			if game.interior.open and (shots_dir == "" or phase_t > 1.2):
				if shots_dir != "":
					_shot("c%d_interior" % (game.chapter_i + 1))
				_next()
		"outside":
			game.interior.leave()
			_next()
		"bench":
			# крафт перетаскиванием: выложить ресурсы на стол по одному и собрать
			var key := "%d:%d" % [game.chapter_i, phase]
			if not did.has(key):
				did[key] = true
				var r: Dictionary = game.recipe(s[1])
				game.interior.use("bench")
				for k in r.cost:
					for n in int(r.cost[k]):
						game.interior.drop(k)
			if shots_dir != "" and phase_t < 1.2:
				return # дать кадру отрисоваться, чтобы снять стол с ресурсами
			if not did.has(key + "c"):
				did[key + "c"] = true
				if shots_dir != "":
					_shot("c%d_bench" % (game.chapter_i + 1))
				var r: Dictionary = game.recipe(s[1])
				var m: Dictionary = game.interior.matched()
				var ok: bool = game.interior.craft_bench()
				print("BOT: верстак (перетаскивание) %s → стол узнал «%s», %s" % [s[1], m.get("name", "-"), "собрано" if ok else "НЕ собрано"])
				if not ok:
					_finish(false)
					return
				game.interior.mode = "room"
			_next()
		"sleep", "cook", "stoke":
			var before: Dictionary = game.stats.duplicate()
			match s[0]:
				"sleep":
					game.interior.sleep()
				"cook":
					game.interior.cook()
				"stoke":
					game.interior.stoke()
			print("BOT: %s: рассудок %d→%d, голод %d→%d, тепло %d→%d" % [s[0], before.sanity, game.stats.sanity, before.hunger, game.stats.hunger, before.warmth, game.stats.warmth])
			_next()
		"craft", "upgrade":
			var key := "%d:%d" % [game.chapter_i, phase]
			if not did.has(key):
				did[key] = true
				var ok: bool = game.craft(s[1]) if s[0] == "craft" else game.do_upgrade(s[1])
				print("BOT: %s %s → %s" % [s[0], s[1], "OK" if ok else "не хватило ресурсов"])
			_next()


## Разговор: подойти, открыть диалог и нажимать выборы по индексам; потом закрыть.
func _talk(id: String, choices: Array) -> void:
	var n: Dictionary = game.npc(id)
	if n.is_empty() or n.done or (id == "dog" and game.dog_joined):
		if game.menu.is_open() and not game.finished:
			game.menu.close()
		_next()
		return
	if not game.menu.is_open():
		if talk_step > 0:
			_next() # диалог закрылся сам
			return
		if _walk_to(n.pos + Vector2(0, 10), 14.0):
			game.press_context(true)
		return
	if talk_step < choices.size():
		var items: Array = game.menu.screen.items
		var idx: int = choices[talk_step]
		talk_step += 1
		if idx < items.size() and items[idx].get("on", true):
			print("BOT:   выбор «%s»" % items[idx].label)
			(items[idx].act as Callable).call()
		else:
			print("BOT:   выбор %d недоступен" % idx)
	elif not game.finished:
		game.menu.close()
		_next()


## Идти к точке; true — пришли. Простой обход препятствий: если застряли — шаг вбок.
func _walk_to(target: Vector2, eps: float) -> bool:
	var d: Vector2 = target - game.player_pos
	if d.length() < eps:
		game.ctl.move = Vector2.ZERO
		return true
	var dir := d.normalized()
	# цель по ту сторону дрезины — обойти её вокруг ближайшего торца
	var tr: Rect2 = game.train_rect().grow(6)
	var from: Vector2 = game.player_pos
	if (from.y > tr.end.y) != (target.y > tr.end.y) or (from.y < tr.position.y) != (target.y < tr.position.y):
		var mid_x := lerpf(from.x, target.x, clampf((tr.get_center().y - from.y) / (target.y - from.y + 0.001), 0.0, 1.0))
		if mid_x > tr.position.x - 4.0 and mid_x < tr.end.x + 4.0:
			var side := tr.position.x - 12.0 if from.x < tr.get_center().x else tr.end.x + 12.0
			if absf(from.x - side) > 4.0:
				dir = Vector2(signf(side - from.x), 0)
			else:
				dir = Vector2(0, signf(target.y - from.y))
	game.ctl.move = dir
	if phase_t > 1.0 and int(phase_t * 2.0) % 6 == 5:
		game.ctl.move = dir.orthogonal()
	return false


func _survive() -> void:
	if game.stats.hunger < 25.0 and game.inv.cans > 0:
		game.use_item("cans")
	if game.stats.health < 45.0 and game.inv.medkit > 0:
		game.use_item("medkit")
	if not game.aboard and (game.stats.sanity < 25.0 or game.stats.warmth < 20.0) and game.inv.torch > 0 and game.torch_left <= 0.0:
		game.use_item("torch")


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
	if bd < 26.0 or (game.weapon == "shotgun" and bd < 110.0 and best.kind == "crawler"):
		game.attack()
	var close_count := 0
	for m in game.monsters:
		if m.pos.distance_to(game.player_pos) < 70.0:
			close_count += 1
	if close_count >= 3 and game.inv.grenade > 0:
		game.use_item("grenade")


func _finish(ok: bool) -> void:
	done = true
	print("BOT: %s · игровое время %.0f с · смертей %d · карма %d · концовка «%s» · дрезина: %s" % [
		"ИГРА ПРОЙДЕНА" if ok else "НЕ ПРОЙДЕНО", total_t, deaths, game.karma, game.ending, str(game.upgrades)])
	if shots_dir != "":
		await get_tree().create_timer(0.5).timeout
		_shot("final")
	get_tree().quit(0 if ok else 1)


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots_dir, name])
