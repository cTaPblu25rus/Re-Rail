## Окна RE-RAIL: главное меню, пауза, настройки, «как играть».
## Это же общий «панельный» UI: окно = заголовок + текст + список кнопок
## (позже на нём же — верстак, диалоги, торговля). Свой сенсорный ввод.
extends CanvasLayer

const SETTINGS_PATH := "user://settings.cfg"

var game: Node
var ui: Control
var font: Font

## Текущее окно: {"title", "text", "items": [{"label", "sub", "on", "act": Callable}], "back": Callable, "big": bool}
var screen: Dictionary = {}
var rects: Array[Rect2] = []
var pressed := -1
var confirm := ""
var confirm_idx := -1

var settings := {"music": 0.8, "sfx": 1.0, "vibration": true, "fog_hq": true}


func _ready() -> void:
	layer = 30
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.draw.connect(_draw_ui)
	add_child(ui)
	font = ThemeDB.fallback_font
	load_settings()


func is_open() -> bool:
	return not screen.is_empty()


func show_screen(s: Dictionary) -> void:
	screen = s
	pressed = -1


func close() -> void:
	screen = {}
	game.set_paused(false)


## Кнопка «Назад» Android и клавиша Esc.
func back() -> void:
	if screen.has("back"):
		(screen.back as Callable).call()


func _process(_d: float) -> void:
	ui.queue_redraw()


# ------------------------------------------------------------ экраны

func main_menu() -> void:
	var items := []
	if game.has_save():
		items.append({"label": "Продолжить", "sub": game.save_summary(), "act": func() -> void: game.boot("continue")})
	items.append({"label": "Новая игра", "act": _new_game})
	items.append({"label": "Настройки", "act": func() -> void: settings_menu(main_menu)})
	items.append({"label": "Как играть", "act": func() -> void: help_menu(main_menu)})
	show_screen({"title": "RE-RAIL", "text": "Хроники Пепла", "items": items, "big": true,
		"back": func() -> void: get_tree().quit()})


func _new_game() -> void:
	if game.has_save() and confirm != "new":
		confirm = "new"
		game.say("Сохранение будет перезаписано. Нажми ещё раз.")
		return
	game.boot("new")


func pause_menu() -> void:
	game.set_paused(true)
	show_screen({"title": "Пауза", "text": game.objective, "items": [
		{"label": "Продолжить", "act": close},
		{"label": "Настройки", "act": func() -> void: settings_menu(pause_menu)},
		{"label": "Как играть", "act": func() -> void: help_menu(pause_menu)},
		{"label": "Сохранить и выйти в меню", "act": func() -> void:
			game.save_game()
			game.boot("menu")},
	], "back": close})


func settings_menu(back_to: Callable) -> void:
	var pct := func(v: float) -> String: return "%d%%" % int(round(v * 100.0))
	show_screen({"title": "Настройки", "items": [
		{"label": "Музыка и ветер: " + pct.call(settings.music), "act": func() -> void:
			settings.music = _cycle(settings.music)
			_apply_and_refresh(back_to)},
		{"label": "Звуки: " + pct.call(settings.sfx), "act": func() -> void:
			settings.sfx = _cycle(settings.sfx)
			_apply_and_refresh(back_to)},
		{"label": "Вибрация: " + ("вкл" if settings.vibration else "выкл"), "act": func() -> void:
			settings.vibration = not settings.vibration
			_apply_and_refresh(back_to)},
		{"label": "Туман: " + ("подробный" if settings.fog_hq else "лёгкий (экономит батарею)"), "act": func() -> void:
			settings.fog_hq = not settings.fog_hq
			_apply_and_refresh(back_to)},
		{"label": "Стереть сохранение", "on": game.has_save(), "act": func() -> void:
			if confirm != "wipe":
				confirm = "wipe"
				game.say("Нажми ещё раз, чтобы стереть сохранение.")
				return
			game.wipe_save()
			game.say("Сохранение стёрто.")
			settings_menu(back_to)},
		{"label": "Назад", "act": back_to},
	], "back": back_to})


func _cycle(v: float) -> float:
	var n := snappedf(v + 0.2, 0.2)
	return 0.0 if n > 1.01 else n


func _apply_and_refresh(back_to: Callable) -> void:
	apply_settings()
	save_settings()
	settings_menu(back_to)


func help_menu(back_to: Callable) -> void:
	show_screen({"title": "Как играть", "text":
		"Левый палец — идти (в дрезине — газ и задний ход). Правый палец — светить фонарём.\n" +
		"Свет — жизнь: в темноте тают рассудок и тепло. Ржавцы боятся луча и сгорают в нём.\n" +
		"«Обыскать» — держи у кучи хлама. Предметы — тап по панели снизу.\n" +
		"Радио: тап по нему и веди пальцем по шкале — у аномалий проступают голоса прошлого.",
		"items": [{"label": "Назад", "act": back_to}], "back": back_to})


# ------------------------------------------------------------ настройки

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for k in settings:
			settings[k] = cfg.get_value("settings", k, settings[k])


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in settings:
		cfg.set_value("settings", k, settings[k])
	cfg.save(SETTINGS_PATH)


func apply_settings() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(settings.music, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(settings.sfx, 0.0001)))
	game.apply_settings(settings)


# ------------------------------------------------------------ ввод

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if is_open():
			back()
		elif game.state == "play":
			pause_menu()
		get_viewport().set_input_as_handled()
		return
	if not is_open():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			pressed = _hit(event.position)
		else:
			var i := _hit(event.position)
			if i != -1 and i == pressed:
				var it: Dictionary = screen.items[i]
				if it.get("on", true):
					game.sfx.play("click", -4.0)
					# подтверждение («нажми ещё раз») действует только для той же кнопки
					if i != confirm_idx:
						confirm = ""
					confirm_idx = i
					(it.act as Callable).call()
			pressed = -1
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()


func _hit(p: Vector2) -> int:
	for i in rects.size():
		if rects[i].has_point(p):
			return i
	return -1


# ------------------------------------------------------------ отрисовка

func _draw_ui() -> void:
	rects.clear()
	if not is_open():
		return
	var s := ui.get_viewport_rect().size
	var big: bool = screen.get("big", false)
	var items: Array = screen.get("items", [])
	var w := 330.0
	var bh := 28.0
	var gap := 6.0
	var text: String = screen.get("text", "")
	var text_h := 0.0
	if text != "" and not big:
		text_h = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w - 24, 11).y + 10.0
	var title_h := 70.0 if big else 34.0
	var h := title_h + text_h + items.size() * (bh + gap) + 16.0
	var top := (s.y - h) * 0.5
	if big:
		ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.35))
		_center(Vector2(s.x * 0.5, top + 36), screen.title, 40, Color(1.0, 0.72, 0.4))
		_center(Vector2(s.x * 0.5, top + 58), text, 14, Color(0.85, 0.9, 0.8))
	else:
		ui.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.55))
		var panel := Rect2(s.x * 0.5 - w * 0.5 - 8, top - 8, w + 16, h + 8)
		ui.draw_rect(panel, Color(0.07, 0.07, 0.06, 0.94))
		ui.draw_rect(panel, Color(0.5, 0.42, 0.3), false, 1.5)
		_center(Vector2(s.x * 0.5, top + 18), screen.title, 18, Color(1.0, 0.8, 0.5))
		if text != "":
			ui.draw_multiline_string(font, Vector2(s.x * 0.5 - w * 0.5 + 12, top + title_h + 2), text, HORIZONTAL_ALIGNMENT_LEFT, w - 24, 11, -1, Color(0.85, 0.85, 0.78))
	var y := top + title_h + text_h
	for i in items.size():
		var it: Dictionary = items[i]
		var r := Rect2(s.x * 0.5 - w * 0.5, y, w, bh)
		rects.append(r)
		var on: bool = it.get("on", true)
		var col := Color(0.16, 0.14, 0.11, 0.95) if i != pressed else Color(0.35, 0.25, 0.14, 0.95)
		ui.draw_rect(r, col)
		ui.draw_rect(r, Color(0.62, 0.5, 0.32, 0.9 if on else 0.3), false, 1.0)
		var label: String = it.label
		var sub: String = it.get("sub", "")
		var tc := Color(0.98, 0.93, 0.82) if on else Color(0.5, 0.48, 0.44)
		if sub == "":
			_center(r.get_center() + Vector2(0, 4), label, 13, tc)
		else:
			_center(r.get_center() + Vector2(0, -1), label, 13, tc)
			_center(r.get_center() + Vector2(0, 11), sub, 9, Color(0.7, 0.7, 0.62))
		y += bh + gap
	# сообщения поверх меню (подтверждения и т.п.)
	var my := s.y - 24.0
	for m in game.messages:
		if game.time - m.t < 3.0:
			_center(Vector2(s.x * 0.5, my), m.text, 11, Color(1, 0.9, 0.7))
			my -= 14.0


func _center(p: Vector2, text: String, size: int, c: Color) -> void:
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ui.draw_string_outline(font, p - Vector2(tw * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.85))
	ui.draw_string(font, p - Vector2(tw * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)
