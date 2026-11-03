## Интерьер бронедрезины: тёплая кабина, куда можно зайти на стоянке.
## Койка (сон), верстак (крафт перетаскиванием), печка (уголь и похлёбка), полка с
## радио (дневник эха), карта пути на стене, коврик Пепла.
## Картинка рисуется кодом в 320×180 и масштабируется ×2 (пиксель-арт).
extends CanvasLayer

const W := 320
const H := 180
const SLEEP_COOLDOWN := 90.0
const TOKENS := ["scrap", "cloth", "chem", "coal"]
const TOKEN_COLORS := {"scrap": Color(0.62, 0.6, 0.55), "cloth": Color(0.7, 0.6, 0.42), "chem": Color(0.45, 0.8, 0.45), "coal": Color(0.2, 0.2, 0.22)}

var game: Node
var ui: Control
var font: Font
var open := false
var mode := "room" # "room" — комната, "bench" — верстак
var bg: ImageTexture
var last_sleep := -999.0
var sleep_fade := 0.0

# верстак: что лежит на столе (зарезервировано из инвентаря)
var bench := {}
var drag := "" # какой ресурс тащим
var drag_pos := Vector2.ZERO
var drag_touch := -1

## Горячие точки комнаты в координатах 320×180.
const SPOTS := {
	"bed": Rect2(12, 104, 84, 40),
	"bench": Rect2(116, 96, 92, 30),
	"stove": Rect2(232, 76, 46, 62),
	"radio": Rect2(132, 38, 48, 26),
	"map": Rect2(30, 34, 58, 38),
	"dog": Rect2(112, 140, 50, 16),
}
const SPOT_NAMES := {"bed": "Койка", "bench": "Верстак", "stove": "Печка", "radio": "Дневник эха", "map": "Карта пути", "dog": "Пепел"}


func _ready() -> void:
	layer = 25
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.draw.connect(_draw_ui)
	add_child(ui)
	font = ThemeDB.fallback_font
	bg = _paint_room()


func enter() -> void:
	if not game.aboard or absf(game.train_v) > 5.0:
		game.say("Сначала останови дрезину.")
		return
	open = true
	mode = "room"
	bench.clear()
	game.ctl.move = Vector2.ZERO
	game.sfx.play("clank", -14.0, 0.6)


func leave() -> void:
	open = false
	bench.clear()
	drag = ""
	game.sfx.play("clank", -14.0, 0.7)


func _process(delta: float) -> void:
	ui.visible = open
	sleep_fade = maxf(0.0, sleep_fade - delta * 0.6)
	if open:
		ui.queue_redraw()


# ------------------------------------------------------------ геометрия

func _scale() -> float:
	var s := ui.get_viewport_rect().size
	return minf(s.x / W, s.y / H)


func _origin() -> Vector2:
	var s := ui.get_viewport_rect().size
	return (s - Vector2(W, H) * _scale()) * 0.5


func _to_room(p: Vector2) -> Vector2:
	return (p - _origin()) / _scale()


func _exit_rect() -> Rect2:
	var s := ui.get_viewport_rect().size
	return Rect2(s.x - 96, 8, 88, 26)


func _bench_panel() -> Rect2:
	var s := ui.get_viewport_rect().size
	return Rect2(s.x * 0.5 - 300, 30, 600, 310)


func _token_rect(i: int) -> Rect2:
	var p := _bench_panel()
	return Rect2(p.position + Vector2(16, 44 + i * 58), Vector2(52, 52))


func _table_rect() -> Rect2:
	var p := _bench_panel()
	return Rect2(p.position + Vector2(90, 44), Vector2(230, 170))


func _recipe_rect(i: int) -> Rect2:
	var p := _bench_panel()
	return Rect2(p.position + Vector2(336, 44 + i * 28), Vector2(248, 24))


func _btn(name: String) -> Rect2:
	var p := _bench_panel()
	match name:
		"craft":
			return Rect2(p.position + Vector2(90, 254), Vector2(110, 30))
		"clear":
			return Rect2(p.position + Vector2(210, 254), Vector2(110, 30))
		"upgrades":
			return Rect2(p.position + Vector2(336, 254), Vector2(120, 30))
		"back":
			return Rect2(p.position + Vector2(464, 254), Vector2(120, 30))
	return Rect2()


# ------------------------------------------------------------ ввод

func _input(event: InputEvent) -> void:
	if not open or game.menu.is_open():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index, event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == drag_touch:
			drag_pos = event.position
		get_viewport().set_input_as_handled()


func _press(idx: int, p: Vector2) -> void:
	if mode == "room":
		if _exit_rect().has_point(p):
			leave()
			return
		var rp := _to_room(p)
		for k in SPOTS:
			if (SPOTS[k] as Rect2).grow(4).has_point(rp):
				use(k)
				return
		return
	# верстак
	for i in TOKENS.size():
		if _token_rect(i).has_point(p) and available(TOKENS[i]) > 0:
			drag = TOKENS[i]
			drag_pos = p
			drag_touch = idx
			return
	if _table_rect().has_point(p):
		_take_back(p)
		return
	var recipes: Array = game.crafting.recipes
	for i in recipes.size():
		if _recipe_rect(i).has_point(p):
			fill(recipes[i].id)
			return
	if _btn("craft").has_point(p):
		craft_bench()
	elif _btn("clear").has_point(p):
		bench.clear()
	elif _btn("upgrades").has_point(p):
		game.menu.upgrades_menu()
	elif _btn("back").has_point(p):
		mode = "room"
		bench.clear()


func _release(idx: int, p: Vector2) -> void:
	if idx != drag_touch or drag == "":
		return
	if _table_rect().grow(10).has_point(p):
		drop(drag)
	drag = ""
	drag_touch = -1


## Тап по столу: вернуть один ресурс того вида, что ближе к пальцу.
func _take_back(p: Vector2) -> void:
	var keys := bench.keys()
	if keys.is_empty():
		return
	var tr := _table_rect()
	var i := clampi(int((p.x - tr.position.x) / (tr.size.x / maxf(keys.size(), 1))), 0, keys.size() - 1)
	var k: String = keys[i]
	bench[k] -= 1
	if bench[k] <= 0:
		bench.erase(k)
	game.sfx.play("click", -8.0)


# ------------------------------------------------------------ действия (общие с автоигроком)

func use(spot: String) -> void:
	match spot:
		"bed":
			sleep()
		"bench":
			mode = "bench"
			bench.clear()
		"stove":
			stove_menu()
		"radio":
			journal()
		"map":
			route_map()
		"dog":
			if game.dog_joined:
				game.sfx.play("bark", -10.0, 1.2)
				game.stats.sanity = minf(100.0, game.stats.sanity + 5.0)
				game.say("Пепел тычется носом в ладонь. Рассудок +5")
			else:
				game.say("Пустой коврик. Тут бы спал пёс.")


func sleep() -> void:
	if game.time - last_sleep < SLEEP_COOLDOWN:
		game.say("Не спится. Мысли об Ане.")
		return
	last_sleep = game.time
	sleep_fade = 1.0
	var st: Dictionary = game.stats
	st.sanity = 100.0
	st.health = minf(100.0, st.health + 30.0)
	st.warmth = 100.0
	st.hunger = maxf(0.0, st.hunger - 15.0)
	game.sfx.play("chime", -10.0, 0.6)
	game.say("Илья поспал. Снилась Аня — маленькая, с косичками.")
	game.save_game()


func stove_menu() -> void:
	if game.upgrades.stove <= 0:
		game.say("Печки нет. Поставь её на верстаке → «Улучшения».")
		return
	var items := [
		{"label": "Подбросить угля", "sub": "уголь 3 → тепло и покой", "on": game.inv.coal >= 3.0, "act": func() -> void:
			stoke()
			game.menu.close()},
		{"label": "Сварить похлёбку", "sub": "консервы 1 → голод +70", "on": game.inv.cans > 0, "act": func() -> void:
			cook()
			game.menu.close()},
		{"label": "Назад", "act": game.menu.close},
	]
	game.menu.show_screen({"title": "Печка", "text": "Чугунная буржуйка тихо гудит.", "items": items, "back": game.menu.close})


func stoke() -> void:
	if game.inv.coal < 3.0:
		return
	game.inv.coal -= 3.0
	game.stats.warmth = 100.0
	game.stats.sanity = minf(100.0, game.stats.sanity + 15.0)
	game.sfx.play("clank", -10.0, 0.5)
	game.say("Печка разгорелась. Тепло.")


func cook() -> void:
	if game.inv.cans <= 0:
		return
	game.inv.cans -= 1
	game.stats.hunger = minf(100.0, game.stats.hunger + 70.0)
	game.sfx.play("chime", -10.0, 0.9)
	game.say("Горячая похлёбка. Голод отступил надолго.")


func journal() -> void:
	var notes: Array = game.flags.get("journal", [])
	var text := "Пока пусто. Настраивай радио у аномалий." if notes.is_empty() else "\n".join(notes.slice(maxi(0, notes.size() - 6)))
	game.menu.show_screen({"title": "Дневник эха", "text": text, "items": [{"label": "Закрыть", "act": game.menu.close}], "back": game.menu.close})


func route_map() -> void:
	var lines := []
	for i in game.chapters.size():
		var mark := "✓ " if i < game.chapter_i else ("► " if i == game.chapter_i else "· ")
		lines.append(mark + String(game.chapters[i].name))
	var stations := "\n".join(lines)
	game.menu.show_screen({"title": "Карта пути", "text": "Транссибирская магистраль, восточный перегон:\n" + stations,
		"items": [{"label": "Закрыть", "act": game.menu.close}], "back": game.menu.close})


## Сколько ресурса можно ещё выложить на стол.
func available(k: String) -> int:
	return int(game.inv.get(k, 0)) - int(bench.get(k, 0))


func drop(k: String) -> void:
	if available(k) <= 0:
		return
	bench[k] = int(bench.get(k, 0)) + 1
	game.sfx.play("click", -6.0, 0.8)


## Рецепт, который точно совпадает с тем, что лежит на столе.
func matched() -> Dictionary:
	for r in game.crafting.recipes:
		var cost: Dictionary = r.cost
		if cost.size() != bench.size():
			continue
		var ok := true
		for k in cost:
			if int(bench.get(k, 0)) != int(cost[k]):
				ok = false
				break
		if ok:
			return r
	return {}


## Тап по чертежу: выложить на стол всё, что нужно (если хватает).
func fill(id: String) -> void:
	var r: Dictionary = game.recipe(id)
	bench.clear()
	for k in r.cost:
		var need := int(r.cost[k])
		bench[k] = mini(need, int(game.inv.get(k, 0)))
		if bench[k] <= 0:
			bench.erase(k)
	if not game.can_afford(r.cost):
		game.say("Для «%s» не хватает: %s" % [r.name, game.cost_text(r.cost)])


func craft_bench() -> bool:
	var r := matched()
	if r.is_empty():
		game.say("Из этого ничего не собрать.")
		return false
	if not game.craft(r.id):
		game.say("Это уже не собрать.")
		return false
	bench.clear()
	return true


# ------------------------------------------------------------ отрисовка

func _draw_ui() -> void:
	if not open:
		return
	var s := ui.get_viewport_rect().size
	var k := _scale()
	var o := _origin()
	ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.015, 0.01))
	ui.draw_texture_rect(bg, Rect2(o, Vector2(W, H) * k), false)
	var t: float = game.time
	# окно: туман за стеклом плывёт
	var win := Rect2(o + Vector2(198, 30) * k, Vector2(28, 26) * k)
	for i in 5:
		var fx := fposmod(t * 6.0 + i * 13.0, 40.0) - 8.0
		ui.draw_rect(Rect2(win.position + Vector2(fx, 4.0 + i * 4.5) * k, Vector2(10, 3) * k).intersection(win), Color(0.45, 0.6, 0.52, 0.35))
	# печка: огонь, если стоит; иначе — пустое место у стены
	if game.upgrades.stove <= 0:
		ui.draw_rect(Rect2(o + Vector2(234, 40) * k, Vector2(42, 56) * k), Color(0.34, 0.20, 0.11))
		ui.draw_rect(Rect2(o + Vector2(234, 96) * k, Vector2(42, 42) * k), Color(0.42, 0.26, 0.14))
		ui.draw_rect(Rect2(o + Vector2(238, 84) * k, Vector2(34, 50) * k), Color(0.9, 0.8, 0.6, 0.35), false, 1.0)
	else:
		var fl := 0.75 + 0.25 * sin(t * 11.0) * sin(t * 3.7)
		ui.draw_rect(Rect2(o + Vector2(244, 112) * k, Vector2(22, 10) * k), Color(1.0, 0.45 + 0.2 * fl, 0.1, 0.9))
		ui.draw_circle(o + Vector2(255, 117) * k, 34.0 * k * fl, Color(1.0, 0.5, 0.2, 0.08))
	# лампа покачивается, тёплое пятно света
	var sway := sin(t * 1.3) * 3.0
	var lamp := o + Vector2(160 + sway, 26) * k
	ui.draw_line(o + Vector2(160, 8) * k, lamp, Color(0.15, 0.12, 0.1), 1.0 * k)
	ui.draw_circle(lamp, 3.0 * k, Color(1.0, 0.85, 0.5))
	# тёплый свет лампы: мягкие круги поверх и общий оранжевый оттенок
	ui.draw_rect(Rect2(o, Vector2(W, H) * k), Color(1.0, 0.5, 0.15, 0.07))
	for r in [150.0, 110.0, 75.0, 45.0]:
		ui.draw_circle(lamp + Vector2(0, 40) * k, r * k, Color(1.0, 0.62, 0.28, 0.045))
	ui.draw_circle(lamp, 7.0 * k, Color(1.0, 0.85, 0.5, 0.35))
	# Пепел спит на коврике
	if game.dog_joined:
		var breathe := 1.0 + 0.04 * sin(t * 2.0)
		var dp := o + Vector2(137, 150) * k
		ui.draw_set_transform(dp, 0.0, Vector2(k * breathe, k))
		ui.draw_rect(Rect2(-12, -5, 22, 6), Color(0.42, 0.40, 0.38))
		ui.draw_rect(Rect2(8, -7, 6, 5), Color(0.42, 0.40, 0.38))
		ui.draw_rect(Rect2(-15, -3, 4, 2), Color(0.38, 0.36, 0.34))
		ui.draw_set_transform(Vector2.ZERO)
	# подписи горячих точек
	if mode == "room":
		for key in SPOTS:
			var r: Rect2 = SPOTS[key]
			var c := o + (r.position + Vector2(r.size.x * 0.5, -2)) * k
			_label(c, SPOT_NAMES[key], 10, Color(1.0, 0.9, 0.7, 0.85))
		var er := _exit_rect()
		ui.draw_rect(er, Color(0.1, 0.08, 0.06, 0.9))
		ui.draw_rect(er, Color(0.62, 0.5, 0.32), false, 1.0)
		_label(er.get_center() + Vector2(0, 4), "Наружу", 12, Color(0.98, 0.93, 0.82))
		_status(s)
	else:
		_draw_bench(s)
	if sleep_fade > 0.0:
		ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, clampf(sleep_fade * 1.5, 0.0, 1.0)))
	# сообщения
	var my := s.y - 18.0
	for m in game.messages:
		if game.time - m.t < 4.0:
			_label(Vector2(s.x * 0.5, my), m.text, 11, Color(1, 0.92, 0.75))
			my -= 14.0


func _status(s: Vector2) -> void:
	var st: Dictionary = game.stats
	var txt := "Здоровье %d · Голод %d · Тепло %d · Рассудок %d" % [st.health, st.hunger, st.warmth, st.sanity]
	_label(Vector2(s.x * 0.5, 20), txt, 11, Color(0.95, 0.9, 0.8))


func _draw_bench(s: Vector2) -> void:
	var p := _bench_panel()
	ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.45))
	ui.draw_rect(p, Color(0.09, 0.07, 0.05, 0.96))
	ui.draw_rect(p, Color(0.6, 0.45, 0.28), false, 1.5)
	_label(p.position + Vector2(p.size.x * 0.5, 22), "Верстак — перетащи ресурсы на стол", 15, Color(1, 0.82, 0.55))
	# ресурсы
	for i in TOKENS.size():
		var r := _token_rect(i)
		var key: String = TOKENS[i]
		var av := available(key)
		ui.draw_rect(r, Color(0.16, 0.13, 0.1))
		ui.draw_rect(r, Color(0.5, 0.42, 0.3, 1.0 if av > 0 else 0.3), false, 1.0)
		_token(r.get_center() + Vector2(0, -4), key, 1.0 if av > 0 else 0.3)
		_label(r.get_center() + Vector2(0, 22), "%s %d" % [game.ITEM_NAMES[key], av], 9, Color(0.9, 0.85, 0.75))
	# стол
	var tr := _table_rect()
	ui.draw_rect(tr, Color(0.30, 0.20, 0.12))
	for y in range(int(tr.position.y) + 14, int(tr.end.y), 18):
		ui.draw_line(Vector2(tr.position.x, y), Vector2(tr.end.x, y), Color(0.22, 0.14, 0.08), 1.0)
	ui.draw_rect(tr, Color(0.55, 0.4, 0.25), false, 1.5)
	var keys := bench.keys()
	if keys.is_empty():
		_label(tr.get_center(), "пусто", 11, Color(0.7, 0.6, 0.5, 0.6))
	for i in keys.size():
		var cx := tr.position.x + tr.size.x * (i + 0.5) / keys.size()
		for n in int(bench[keys[i]]):
			_token(Vector2(cx + (n % 3 - 1) * 14.0, tr.position.y + 50 + int(n / 3) * 16.0), keys[i], 1.0)
		_label(Vector2(cx, tr.end.y - 12), "×%d" % int(bench[keys[i]]), 11, Color(1, 0.95, 0.85))
	var m := matched()
	var mt := "→ " + String(m.name) if not m.is_empty() else ("ничего не выходит" if not keys.is_empty() else "")
	_label(Vector2(tr.get_center().x, tr.end.y + 22), mt, 13, Color(0.6, 1.0, 0.6) if not m.is_empty() else Color(0.8, 0.6, 0.5))
	# чертежи
	_label(p.position + Vector2(460, 38), "Чертежи (тап — выложить)", 10, Color(0.85, 0.75, 0.6))
	var recipes: Array = game.crafting.recipes
	for i in recipes.size():
		var r := _recipe_rect(i)
		var rec: Dictionary = recipes[i]
		var can: bool = game.can_craft(rec)
		ui.draw_rect(r, Color(0.14, 0.11, 0.08))
		ui.draw_rect(r, Color(0.5, 0.42, 0.3, 0.9 if can else 0.3), false, 1.0)
		ui.draw_string(font, r.position + Vector2(6, 16), rec.name, HORIZONTAL_ALIGNMENT_LEFT, 110, 11, Color(0.98, 0.93, 0.82) if can else Color(0.55, 0.52, 0.48))
		ui.draw_string(font, r.position + Vector2(116, 16), game.cost_text(rec.cost), HORIZONTAL_ALIGNMENT_LEFT, 130, 9, Color(0.75, 0.72, 0.62))
	# кнопки
	for b in [["craft", "Собрать"], ["clear", "Убрать всё"], ["upgrades", "Улучшения"], ["back", "← Назад"]]:
		var r := _btn(b[0])
		var on: bool = b[0] != "craft" or not m.is_empty()
		ui.draw_rect(r, Color(0.2, 0.15, 0.1) if on else Color(0.12, 0.1, 0.08))
		ui.draw_rect(r, Color(0.65, 0.5, 0.3, 1.0 if on else 0.3), false, 1.0)
		_label(r.get_center() + Vector2(0, 4), b[1], 12, Color(0.98, 0.93, 0.82) if on else Color(0.5, 0.48, 0.44))
	if drag != "":
		_token(drag_pos, drag, 1.0)


func _token(c: Vector2, key: String, a: float) -> void:
	var col: Color = TOKEN_COLORS[key]
	match key:
		"scrap":
			ui.draw_rect(Rect2(c - Vector2(8, 4), Vector2(16, 5)), Color(col, a))
			ui.draw_rect(Rect2(c - Vector2(3, 8), Vector2(5, 14)), Color(col.darkened(0.3), a))
		"cloth":
			ui.draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -6), c + Vector2(8, -8), c + Vector2(9, 6), c + Vector2(-7, 8)]), Color(col, a))
		"chem":
			ui.draw_rect(Rect2(c - Vector2(5, 2), Vector2(10, 10)), Color(col, a))
			ui.draw_rect(Rect2(c - Vector2(2, 8), Vector2(4, 6)), Color(0.8, 0.8, 0.8, a))
		"coal":
			ui.draw_circle(c, 7.0, Color(col, a))
			ui.draw_circle(c + Vector2(-2, -2), 2.0, Color(0.4, 0.4, 0.42, a))


func _label(p: Vector2, text: String, size: int, c: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ui.draw_string_outline(font, p - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.85 * c.a))
	ui.draw_string(font, p - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)


# ------------------------------------------------------------ картинка комнаты

func _paint_room() -> ImageTexture:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var wood := Color(0.34, 0.20, 0.11)
	var plank := Color(0.42, 0.26, 0.14)
	var iron := Color(0.22, 0.20, 0.19)
	# стены: доски и заклёпки
	img.fill(wood)
	for y in range(0, 96, 8):
		img.fill_rect(Rect2i(0, y, W, 1), wood.darkened(0.35))
	for x in range(0, W, 40):
		img.fill_rect(Rect2i(x, 0, 2, 96), iron)
		for y in range(4, 96, 12):
			img.set_pixel(x, y, Color(0.5, 0.45, 0.4))
	# потолочная балка
	img.fill_rect(Rect2i(0, 0, W, 8), iron)
	img.fill_rect(Rect2i(0, 7, W, 1), Color(0.4, 0.36, 0.32))
	# пол
	img.fill_rect(Rect2i(0, 96, W, H - 96), plank)
	for y in range(100, H, 10):
		img.fill_rect(Rect2i(0, y, W, 1), plank.darkened(0.3))
		var off := (y / 10) % 2 * 30
		for x in range(off, W, 60):
			img.fill_rect(Rect2i(x, y, 1, 10), plank.darkened(0.3))
	# окно
	img.fill_rect(Rect2i(196, 28, 32, 30), iron)
	img.fill_rect(Rect2i(198, 30, 28, 26), Color(0.12, 0.18, 0.17))
	img.fill_rect(Rect2i(211, 30, 2, 26), iron)
	# карта на стене
	img.fill_rect(Rect2i(30, 34, 58, 38), Color(0.75, 0.68, 0.5))
	img.fill_rect(Rect2i(32, 52, 54, 1), Color(0.3, 0.25, 0.2))
	for x in range(34, 86, 12):
		img.fill_rect(Rect2i(x, 50, 2, 5), Color(0.7, 0.2, 0.15))
	img.fill_rect(Rect2i(84, 44, 3, 3), Color(0.8, 0.1, 0.1)) # Тайшет
	# полка с радио
	img.fill_rect(Rect2i(128, 60, 56, 3), Color(0.25, 0.15, 0.08))
	img.fill_rect(Rect2i(136, 42, 40, 18), Color(0.30, 0.30, 0.28))
	img.fill_rect(Rect2i(139, 45, 18, 8), Color(0.1, 0.25, 0.12))
	for x in range(160, 174, 3):
		img.fill_rect(Rect2i(x, 45, 2, 12), Color(0.2, 0.2, 0.2))
	img.fill_rect(Rect2i(170, 34, 1, 8), Color(0.5, 0.5, 0.5)) # антенна
	# койка
	img.fill_rect(Rect2i(12, 112, 84, 26), Color(0.25, 0.22, 0.2))
	img.fill_rect(Rect2i(14, 108, 80, 14), Color(0.55, 0.5, 0.4))
	img.fill_rect(Rect2i(16, 106, 20, 10), Color(0.8, 0.78, 0.7)) # подушка
	img.fill_rect(Rect2i(40, 110, 54, 12), Color(0.45, 0.25, 0.2)) # одеяло
	# верстак
	img.fill_rect(Rect2i(116, 100, 92, 8), Color(0.45, 0.30, 0.16))
	img.fill_rect(Rect2i(120, 108, 6, 22), Color(0.3, 0.2, 0.1))
	img.fill_rect(Rect2i(198, 108, 6, 22), Color(0.3, 0.2, 0.1))
	img.fill_rect(Rect2i(128, 94, 14, 6), Color(0.4, 0.4, 0.4)) # тиски
	img.fill_rect(Rect2i(160, 96, 22, 3), Color(0.55, 0.3, 0.2)) # лом
	img.fill_rect(Rect2i(186, 92, 8, 8), Color(0.6, 0.5, 0.2)) # банка
	for x in range(124, 204, 10):
		img.fill_rect(Rect2i(x, 84, 2, 8), Color(0.35, 0.35, 0.35)) # инструменты на стене
	# место под печку / печка
	img.fill_rect(Rect2i(236, 80, 38, 56), Color(0.12, 0.11, 0.11))
	img.fill_rect(Rect2i(238, 82, 34, 52), Color(0.18, 0.17, 0.16))
	img.fill_rect(Rect2i(242, 110, 26, 14), Color(0.06, 0.05, 0.05))
	img.fill_rect(Rect2i(250, 40, 10, 40), Color(0.15, 0.14, 0.13)) # труба
	# коврик
	img.fill_rect(Rect2i(112, 144, 50, 12), Color(0.45, 0.18, 0.15))
	img.fill_rect(Rect2i(114, 146, 46, 8), Color(0.55, 0.28, 0.18))
	# потёртости
	for i in 900:
		var x := rng.randi_range(0, W - 1)
		var y := rng.randi_range(0, H - 1)
		var c := img.get_pixel(x, y)
		img.set_pixel(x, y, c.darkened(0.15) if rng.randf() < 0.5 else c.lightened(0.06))
	return ImageTexture.create_from_image(img)
