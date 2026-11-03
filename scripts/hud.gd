## Сенсорный HUD RE-RAIL (по макету): шкалы слева сверху, радио и миникарта справа,
## джойстик слева снизу, «Обыскать / Фонарь / Атака» справа, предметы по центру снизу.
## Полностью мультитач: каждый палец закрепляется за своим элементом.
extends CanvasLayer

var game: Node
var ui: Control
var font: Font

var touches := {} # index -> {"kind": ..., "origin": Vector2, "pos": Vector2}
var buttons: Array[Dictionary] = []
var joy_origin := Vector2.ZERO
var joy_vec := Vector2.ZERO

const BAR_COLORS := [Color(0.85, 0.15, 0.12), Color(0.85, 0.65, 0.15), Color(0.9, 0.42, 0.12), Color(0.62, 0.5, 0.95)]
const PANEL := Color(0.08, 0.08, 0.07, 0.82)
const EDGE := Color(0.42, 0.38, 0.30, 0.9)
const LCD := Color(0.45, 1.0, 0.55)


func _ready() -> void:
	layer = 20
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.draw.connect(_draw_ui)
	add_child(ui)
	font = ThemeDB.fallback_font


func _process(_d: float) -> void:
	ui.visible = game.state == "play" and not game.interior.open
	_layout()
	ui.queue_redraw()


func _size() -> Vector2:
	return ui.get_viewport_rect().size


## Расположение кнопок пересчитывается каждый кадр — экран может быть любой ширины.
func _layout() -> void:
	var s := _size()
	buttons.clear()
	var ctx: Dictionary = game.context()
	buttons.append({"id": "context", "c": Vector2(s.x - 62, s.y - 138), "r": 26.0, "label": ctx.label, "on": ctx.kind != "none"})
	if game.aboard:
		buttons.append({"id": "bench", "c": Vector2(s.x - 118, s.y - 52), "r": 24.0, "label": "Внутрь", "on": absf(game.train_v) < 5.0})
	else:
		buttons.append({"id": "flash", "c": Vector2(s.x - 118, s.y - 52), "r": 24.0, "label": "Фонарь", "on": true})
	buttons.append({"id": "attack", "c": Vector2(s.x - 48, s.y - 52), "r": 26.0, "label": "Атака", "on": not game.aboard})
	var n: int = game.ITEMS.size()
	var slot := 38.0
	var x0 := s.x * 0.5 - (n * (slot + 4.0)) * 0.5
	for i in n:
		buttons.append({"id": "item:" + game.ITEMS[i], "rect": Rect2(x0 + i * (slot + 4.0), s.y - 50, slot, slot), "on": true})
	buttons.append({"id": "radio", "rect": Rect2(s.x - 206, 8, 96, 48), "on": true})
	buttons.append({"id": "pause", "rect": Rect2(164, 8, 24, 24), "on": true})


func _hit_button(p: Vector2) -> Dictionary:
	for b in buttons:
		if b.has("rect"):
			if (b.rect as Rect2).grow(4).has_point(p):
				return b
		elif p.distance_to(b.c) < b.r + 8.0:
			return b
	return {}


func _tuner_rect() -> Rect2:
	var s := _size()
	return Rect2(s.x * 0.5 - 170, 34, 340, 74)


# ------------------------------------------------------------ ввод

func _input(event: InputEvent) -> void:
	if game.state != "play" or game.menu.is_open() or game.interior.open:
		if not touches.is_empty():
			_release_all()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_touch_move(event.index, event.position)


func _touch_down(idx: int, p: Vector2) -> void:
	if game.dead:
		game.respawn()
		return
	if game.finished:
		return
	var b := _hit_button(p)
	if not b.is_empty():
		touches[idx] = {"kind": "btn", "id": b.id, "pos": p}
		_button(b.id, true)
		return
	if game.radio_open and _tuner_rect().has_point(p):
		touches[idx] = {"kind": "tuner", "pos": p}
		_tune(p)
		return
	if p.x < _size().x * 0.45 and not _has_kind("joy"):
		touches[idx] = {"kind": "joy", "origin": p, "pos": p}
		joy_origin = p
		joy_vec = Vector2.ZERO
		return
	if not _has_kind("aim"):
		touches[idx] = {"kind": "aim", "pos": p}
		_aim(p)


func _touch_move(idx: int, p: Vector2) -> void:
	if not touches.has(idx):
		return
	var t: Dictionary = touches[idx]
	t.pos = p
	match t.kind:
		"joy":
			var v: Vector2 = (p - t.origin) / 40.0
			joy_vec = v.limit_length(1.0)
			game.ctl.move = joy_vec
		"aim":
			_aim(p)
		"tuner":
			_tune(p)


func _touch_up(idx: int) -> void:
	if not touches.has(idx):
		return
	var t: Dictionary = touches[idx]
	match t.kind:
		"joy":
			joy_vec = Vector2.ZERO
			game.ctl.move = Vector2.ZERO
		"aim":
			game.ctl.aiming = false
		"btn":
			_button(t.id, false)
	touches.erase(idx)


## Меню открылось посреди касаний — отпустить всё, чтобы Илья не шагал сам.
func _release_all() -> void:
	for idx in touches.keys():
		_touch_up(idx)
	touches.clear()


func _has_kind(k: String) -> bool:
	for t in touches.values():
		if t.kind == k:
			return true
	return false


func _aim(p: Vector2) -> void:
	var sp: Vector2 = game.get_viewport().get_canvas_transform() * game.player_pos
	var d := p - (sp + Vector2(0, -10))
	if d.length() > 4.0:
		game.ctl.aim = d.normalized()
		game.ctl.aiming = true


func _tune(p: Vector2) -> void:
	var r := _tuner_rect()
	var t := clampf((p.x - r.position.x - 14.0) / (r.size.x - 28.0), 0.0, 1.0)
	game.radio_freq = snappedf(87.5 + t * 20.5, 0.1)


func _button(id: String, down: bool) -> void:
	if id == "context":
		game.press_context(down)
		return
	if not down:
		return
	if id == "flash":
		game.toggle_flashlight()
	elif id == "attack":
		game.attack()
	elif id == "bench":
		game.interior.enter()
	elif id == "radio":
		game.toggle_radio()
	elif id == "pause":
		game.menu.pause_menu()
	elif id.begins_with("item:"):
		game.use_item(id.trim_prefix("item:"))


# ------------------------------------------------------------ отрисовка

func _draw_ui() -> void:
	var s := _size()
	var st: Dictionary = game.stats

	# вспышка боли и безумие по краям экрана
	if game.hurt_flash > 0.0:
		_vignette(s, Color(0.8, 0.05, 0.02, 0.45 * game.hurt_flash))
	if st.sanity < 30.0 and not game.aboard:
		var k: float = (30.0 - st.sanity) / 30.0
		_vignette(s, Color(0.35, 0.1, 0.45, (0.25 + 0.15 * sin(game.time * 3.0)) * k))

	# шкалы
	var vals := [st.health, st.hunger, st.warmth, st.sanity]
	for i in 4:
		var y := 10.0 + i * 22.0
		_icon(i, Vector2(10, y - 1))
		ui.draw_rect(Rect2(32, y, 124, 11), PANEL)
		ui.draw_rect(Rect2(32, y, 124, 11), EDGE, false, 1.0)
		var w: float = 120.0 * clampf(vals[i] / 100.0, 0.0, 1.0)
		ui.draw_rect(Rect2(34, y + 2, w, 7), BAR_COLORS[i])
		ui.draw_rect(Rect2(34, y + 2, w, 2), BAR_COLORS[i].lightened(0.35))

	# цель
	if game.objective != "":
		_text_center(Vector2(s.x * 0.5, 22), game.objective, 12, Color(0.95, 0.9, 0.75))

	# радио
	var rr := Rect2(s.x - 206, 8, 96, 48)
	ui.draw_rect(rr, PANEL)
	ui.draw_rect(rr, EDGE if not game.radio_open else LCD, false, 1.5)
	ui.draw_rect(Rect2(rr.position + Vector2(6, 6), Vector2(84, 22)), Color(0.03, 0.08, 0.04))
	ui.draw_string(font, rr.position + Vector2(8, 22), "«Эхо» %.1f" % game.radio_freq, HORIZONTAL_ALIGNMENT_LEFT, 82, 12, LCD)
	var bars := int(game.radio_signal * 5.0 + 0.5) if game.radio_open else 0
	for i in 5:
		var bh := 3.0 + i * 2.0
		ui.draw_rect(Rect2(rr.position.x + 8 + i * 6, rr.position.y + 42 - bh, 4, bh), LCD if i < bars else Color(0.2, 0.3, 0.2))
	ui.draw_string(font, rr.position + Vector2(40, 42), "радио", HORIZONTAL_ALIGNMENT_LEFT, 54, 10, Color(0.7, 0.7, 0.6))

	# ресурсы
	var inv: Dictionary = game.inv
	_txt(Vector2(s.x - 206, 70), "Уголь %d/%d  Хлам %d" % [int(inv.coal), int(game.coal_cap()), inv.scrap], 10, Color(0.9, 0.85, 0.7))
	_txt(Vector2(s.x - 206, 82), "Ткань %d  Химия %d" % [inv.cloth, inv.chem], 10, Color(0.85, 0.82, 0.75))
	_txt(Vector2(s.x - 206, 94), "Батарея %d%%" % int(st.battery), 10, Color(0.95, 0.9, 0.4))
	if game.train_hp < 100.0:
		var hc := Color(1, 0.4, 0.3) if game.train_hp <= 0.0 else Color(0.9, 0.7, 0.5)
		_txt(Vector2(s.x - 206, 106), "Дрезина %d%%" % int(game.train_hp), 10, hc)

	_draw_minimap(Vector2(s.x - 54, 54), 46.0)

	# пауза
	var pr := Rect2(164, 8, 24, 24)
	ui.draw_rect(pr, PANEL)
	ui.draw_rect(pr, EDGE, false, 1.0)
	ui.draw_rect(Rect2(pr.position + Vector2(8, 6), Vector2(3, 12)), Color(0.9, 0.85, 0.7))
	ui.draw_rect(Rect2(pr.position + Vector2(13, 6), Vector2(3, 12)), Color(0.9, 0.85, 0.7))

	# тюнер
	if game.radio_open and not game.finished:
		_draw_tuner()

	# джойстик
	var jc := joy_origin if _has_kind("joy") else Vector2(80, s.y - 80)
	ui.draw_circle(jc, 44.0, Color(0, 0, 0, 0.25))
	ui.draw_arc(jc, 44.0, 0, TAU, 40, Color(0.8, 0.8, 0.7, 0.35), 2.0)
	for a in 4:
		var dir := Vector2.RIGHT.rotated(a * PI / 2)
		var tip := jc + dir * 36.0
		ui.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 6 + dir.orthogonal() * 5, tip - dir * 6 - dir.orthogonal() * 5]), Color(0.8, 0.8, 0.7, 0.4))
	ui.draw_circle(jc + joy_vec * 30.0, 18.0, Color(0.75, 0.72, 0.65, 0.45))
	if game.aboard:
		_text_center(jc + Vector2(0, -54), "◀ назад   газ ▶", 11, Color(0.9, 0.85, 0.7, 0.8))

	# кнопки
	for b in buttons:
		if b.has("c"):
			_round_button(b)
	_draw_hotbar()

	# сообщения
	var y := s.y * 0.66
	for m in game.messages:
		var age: float = game.time - m.t
		if age < 5.0:
			_text_center(Vector2(s.x * 0.5, y), m.text, 12, Color(1, 0.95, 0.85, clampf(5.0 - age, 0.0, 1.0)))
			y += 16.0

	# прогресс обыска
	if game.search_t > 0.0:
		var sp: Vector2 = game.get_viewport().get_canvas_transform() * game.player_pos
		ui.draw_arc(sp + Vector2(0, -30), 9.0, -PI / 2, -PI / 2 + TAU * game.search_t, 24, Color(1, 0.9, 0.5), 3.0)

	if game.dead:
		ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.7))
		_text_center(s * 0.5 + Vector2(0, -10), "Илья пал во тьме", 26, Color(0.9, 0.3, 0.2))
		_text_center(s * 0.5 + Vector2(0, 22), "коснись, чтобы очнуться в дрезине", 13, Color(0.9, 0.85, 0.75))
	elif game.finished:
		ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.6))
		_text_center(s * 0.5 + Vector2(0, -30), "RE-RAIL: Хроники Пепла", 26, Color(1, 0.8, 0.5))
		_text_center(s * 0.5 + Vector2(0, 0), "Пролог пройден. Дочь жива.", 15, Color(0.95, 0.9, 0.8))
		_text_center(s * 0.5 + Vector2(0, 22), "Продолжение следует: Тайшет, конец магистрали…", 12, Color(0.75, 0.75, 0.7))


## Текст с тёмной обводкой — читается и на снегу, и в темноте.
func _txt(p: Vector2, text: String, size: int, c: Color) -> void:
	ui.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.85))
	ui.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)


func _vignette(s: Vector2, c: Color) -> void:
	var t := 26.0
	ui.draw_rect(Rect2(0, 0, s.x, t), c)
	ui.draw_rect(Rect2(0, s.y - t, s.x, t), c)
	ui.draw_rect(Rect2(0, 0, t, s.y), c)
	ui.draw_rect(Rect2(s.x - t, 0, t, s.y), c)


func _text_center(p: Vector2, text: String, size: int, c: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ui.draw_string_outline(font, p - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, c.a * 0.85))
	ui.draw_string(font, p - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)


func _px(origin: Vector2, rows: Array, c: Color) -> void:
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] == "#":
				ui.draw_rect(Rect2(origin + Vector2(x, y) * 2.0, Vector2(2, 2)), c)


## Пиксельные иконки шкал: сердце, окорок, градусник, мозг.
func _icon(i: int, p: Vector2) -> void:
	match i:
		0:
			_px(p, [".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."], BAR_COLORS[0])
		1:
			_px(p, ["..####.", ".######", ".######", "..####.", ".#.....", "#......"], Color(0.8, 0.4, 0.35))
		2:
			_px(p, ["..#..", "..#..", "..#..", "..#..", ".###.", ".###."], Color(0.95, 0.3, 0.2))
		3:
			_px(p, [".#####.", "##.#.##", "#.###.#", "##.#.##", ".#####."], Color(0.95, 0.6, 0.7))


func _round_button(b: Dictionary) -> void:
	var c: Vector2 = b.c
	var r: float = b.r
	var pressed := false
	for t in touches.values():
		if t.kind == "btn" and t.id == b.id:
			pressed = true
	var a := 0.9 if b.on else 0.35
	ui.draw_circle(c, r, Color(0.08, 0.08, 0.07, 0.75 * a))
	ui.draw_arc(c, r, 0, TAU, 32, Color(0.55, 0.5, 0.4, a) if not pressed else Color(1, 0.85, 0.5), 2.0)
	match b.id:
		"context":
			_px(c - Vector2(7, 9), ["..#.#.#", "..#.#.#", ".##.#.#", "#######", "#######", ".######", "..#####", "...###."], Color(0.95, 0.75, 0.6, a))
		"bench":
			_px(c - Vector2(7, 9), ["...#...", "..###..", ".#####.", "#######", "#.###.#", "#.#.#.#", "#.###.#", "#######"], Color(1.0, 0.7, 0.4, a))
		"flash":
			var on: bool = game.flashlight_on
			_px(c - Vector2(4, 11), [".###.", "#####", ".###.", ".###.", ".###.", ".###.", ".###.", ".###.", ".###.", ".###."], Color(0.75, 0.75, 0.72, a))
			if on and not game.aboard:
				ui.draw_circle(c + Vector2(0, -11), 3.0, Color(1, 0.95, 0.6))
		"attack":
			_px(c - Vector2(9, 5), ["...........##", "..........##.", ".........##..", "........##...", "##.....##....", ".#######....."], Color(0.75, 0.3, 0.2, a))
	_text_center(c + Vector2(0, r + 13), b.label, 11, Color(0.95, 0.92, 0.85, a))


func _draw_hotbar() -> void:
	var icons := {
		"ammo": [".#.#.#", ".#.#.#", "######", "######", "######", "######"],
		"medkit": ["..##..", "######", "##..##", "#....#", "##..##", "######"],
		"crowbar": ["....##", ".....#", ".....#", "....#.", "...#..", ".##..."],
		"shotgun": ["......", "######", "######", "##....", "#.....", "......"],
		"grenade": ["..##..", ".#..#.", "######", "######", "######", ".####."],
		"torch": ["..##..", ".####.", "..##..", "..#...", "..#...", "..#..."],
		"cans": [".####.", "######", "#....#", "#.##.#", "#....#", "######"],
	}
	var cols := {"ammo": Color(0.85, 0.7, 0.3), "medkit": Color(0.9, 0.9, 0.88), "crowbar": Color(0.75, 0.3, 0.25),
		"shotgun": Color(0.55, 0.45, 0.35), "torch": Color(1, 0.6, 0.2), "cans": Color(0.8, 0.25, 0.2), "grenade": Color(0.5, 0.6, 0.4)}
	for b in buttons:
		if not b.has("rect"):
			continue
		var id: String = b.id
		if not id.begins_with("item:"):
			continue
		var it := id.trim_prefix("item:")
		var r: Rect2 = b.rect
		var count: int = game.item_count(it)
		var icon_id := it
		if it == "weapon":
			icon_id = game.weapon
		var active: bool = it == "torch" and game.torch_left > 0.0
		ui.draw_rect(r, PANEL)
		ui.draw_rect(r, Color(1, 0.6, 0.2) if active else EDGE, false, 1.5)
		_px(r.position + Vector2(8, 6), icons[icon_id], cols[icon_id] if count > 0 else Color(0.35, 0.35, 0.33))
		ui.draw_string(font, r.position + Vector2(r.size.x - 14, r.size.y - 4), str(count), HORIZONTAL_ALIGNMENT_LEFT, 14, 10, Color(1, 1, 0.9))
		_text_center(Vector2(r.get_center().x, r.end.y + 9), game.item_name(it), 8, Color(0.85, 0.82, 0.72))


func _draw_minimap(c: Vector2, r: float) -> void:
	ui.draw_circle(c, r + 3.0, EDGE)
	ui.draw_circle(c, r, Color(0.12, 0.17, 0.12, 0.95))
	var center: Vector2 = Vector2(game.train_x, 0) if game.aboard else game.player_pos
	var k := r / 420.0 # пикселей миникарты на пиксель мира
	var to_map := func(w: Vector2) -> Vector2: return c + (w - center) * k
	var ry: float = (to_map.call(Vector2(0, game.RAIL_Y)) as Vector2).y
	if absf(ry - c.y) < r:
		var hw := sqrt(r * r - (ry - c.y) * (ry - c.y))
		ui.draw_line(Vector2(c.x - hw, ry), Vector2(c.x + hw, ry), Color(0.55, 0.5, 0.45), 2.0)
	var goal_c := Color(0.8, 0.35, 0.25)
	var pts := [[game.goal.pos, goal_c, 4.0]]
	for n in game.npcs:
		if not n.hidden and not (n.id == "dog" and game.dog_joined):
			pts.append([n.pos, Color(0.4, 0.95, 0.5), 2.5])
	for ff in game.fireflies:
		pts.append([ff, Color(0.85, 1.0, 0.4), 2.0])
	if game.dog_joined and not game.aboard:
		pts.append([game.dog.pos, Color(0.75, 0.65, 0.5), 2.0])
	var sniff: Dictionary = game.sniffed_pile()
	if not sniff.is_empty():
		var sp2: Vector2 = to_map.call(sniff.pos)
		if sp2.distance_to(c) < r - 2.0:
			ui.draw_arc(sp2, 4.0 + 1.5 * sin(game.time * 5.0), 0, TAU, 16, Color(1, 0.9, 0.5), 1.0)
	for p in game.piles:
		if not p.looted:
			pts.append([p.pos, Color(0.7, 0.7, 0.6), 1.5])
	for m in game.monsters:
		pts.append([m.pos, Color(1, 0.3, 0.1), 2.0])
	pts.append([Vector2(game.train_x, 0), Color(0.95, 0.5, 0.25), 3.5])
	if not game.aboard:
		pts.append([game.player_pos, Color(1, 1, 1), 2.5])
	for pt in pts:
		var mp: Vector2 = to_map.call(pt[0])
		if mp.distance_to(c) < r - 2.0:
			ui.draw_circle(mp, pt[2], pt[1])
		elif pt[1] == goal_c:
			# станция за краем — стрелка на ободе
			var dir := (mp - c).normalized()
			ui.draw_circle(c + dir * (r - 3.0), 3.0, pt[1])


func _draw_tuner() -> void:
	var r := _tuner_rect()
	ui.draw_rect(r, Color(0.04, 0.06, 0.04, 0.92))
	ui.draw_rect(r, LCD, false, 1.5)
	var x0 := r.position.x + 14.0
	var w := r.size.x - 28.0
	for i in 41:
		var x := x0 + w * i / 40.0
		var tall := 8.0 if i % 5 == 0 else 4.0
		ui.draw_line(Vector2(x, r.position.y + 8), Vector2(x, r.position.y + 8 + tall), Color(LCD, 0.6), 1.0)
		if i % 10 == 0:
			ui.draw_string(font, Vector2(x - 10, r.position.y + 28), "%d" % int(87.5 + 20.5 * i / 40.0), HORIZONTAL_ALIGNMENT_LEFT, 24, 9, Color(LCD, 0.7))
	var nx: float = x0 + w * (game.radio_freq - 87.5) / 20.5
	ui.draw_line(Vector2(nx, r.position.y + 4), Vector2(nx, r.position.y + 32), Color(1, 0.4, 0.2), 2.0)
	var txt: String = game.radio_text()
	var shake: Vector2 = Vector2(randf_range(-1, 1), 0) * (1.0 - game.radio_signal)
	ui.draw_string(font, Vector2(r.position.x + 8, r.position.y + 50) + shake, txt.substr(0, 52), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16, 11, Color(LCD, 0.5 + 0.5 * game.radio_signal))
	if txt.length() > 52:
		ui.draw_string(font, Vector2(r.position.x + 8, r.position.y + 66) + shake, txt.substr(52), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16, 11, Color(LCD, 0.5 + 0.5 * game.radio_signal))
	ui.draw_string(font, Vector2(r.position.x + 8, r.end.y + 12), "веди пальцем по шкале", HORIZONTAL_ALIGNMENT_LEFT, 200, 9, Color(0.7, 0.7, 0.6))
