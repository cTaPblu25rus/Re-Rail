## Процедурный пиксель-арт RE-RAIL: все спрайты рисуются кодом при запуске.
## Позже любой спрайт можно заменить на нарисованный художником PNG того же размера.
extends RefCounted

const RUST := Color(0.42, 0.24, 0.14)
const RUST_DARK := Color(0.26, 0.15, 0.10)
const IRON := Color(0.30, 0.30, 0.30)
const IRON_DARK := Color(0.16, 0.16, 0.17)
const GLOW := Color(1.0, 0.62, 0.25)
const CLEAR := Color(0, 0, 0, 0)

static var _rng := RandomNumberGenerator.new()


static func _img(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	return img


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h).intersection(Rect2i(0, 0, img.get_width(), img.get_height())), c)


## Ржавчина и потёртости: случайные пиксели внутри непрозрачной области.
static func _grime(img: Image, r: Rect2i, colors: Array, density: float, seed: int) -> void:
	_rng.seed = seed
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			if img.get_pixel(x, y).a < 0.5:
				continue
			if _rng.randf() < density:
				img.set_pixel(x, y, colors[_rng.randi() % colors.size()])


static func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------ дрезина

## Бронедрезина в 3/4: крыша сверху, борт снизу, нос справа. Возвращает [тело, свечение].
static func draisine() -> Array:
	var w := 84
	var h := 46
	var body := _img(w, h)
	var glow := _img(w, h)
	# крыша
	_rect(body, 4, 4, 70, 20, RUST)
	for x in range(4, 74, 12):
		_rect(body, x, 4, 1, 20, RUST_DARK)
	_rect(body, 4, 4, 70, 1, RUST.lightened(0.2))
	_rect(body, 14, 7, 14, 6, IRON_DARK) # вентиляционный люк
	_rect(body, 15, 8, 12, 1, IRON)
	_rect(body, 36, 2, 30, 3, IRON_DARK) # трубы по крыше
	_rect(body, 36, 2, 30, 1, IRON)
	_rect(body, 58, 0, 3, 5, IRON_DARK) # выхлоп
	# нос (скошенный)
	for i in 10:
		_rect(body, 74 + i, 6 + i, 1, 30 - i, RUST_DARK.lerp(RUST, 0.3))
	# борт
	_rect(body, 4, 24, 72, 14, RUST_DARK)
	_rect(body, 4, 24, 72, 1, RUST)
	for x in range(4, 76, 9):
		_rect(body, x, 25, 1, 13, RUST_DARK.darkened(0.3))
	# окна: тёмные рамы, свет — в отдельной текстуре свечения
	for wx in [10, 24, 38]:
		_rect(body, wx, 27, 10, 7, IRON_DARK)
		_rect(glow, wx + 1, 28, 8, 5, GLOW)
		_rect(glow, wx + 1, 28, 8, 1, GLOW.lightened(0.4))
	_rect(body, 54, 26, 9, 11, IRON_DARK) # дверь
	_rect(body, 55, 27, 7, 9, RUST_DARK.darkened(0.2))
	# поручни
	_rect(body, 2, 22, 76, 1, IRON)
	# колёса и рама
	_rect(body, 2, 38, 80, 3, IRON_DARK)
	for wx in [10, 28, 52, 68]:
		_rect(body, wx, 39, 8, 6, Color(0.1, 0.1, 0.1))
		_rect(body, wx + 2, 40, 4, 1, IRON)
	# фары на носу
	_rect(glow, 80, 18, 3, 3, Color(1.0, 0.95, 0.75))
	_rect(glow, 80, 26, 3, 3, Color(1.0, 0.95, 0.75))
	_grime(body, Rect2i(0, 0, w, h), [RUST.lightened(0.15), RUST_DARK.darkened(0.2), Color(0.5, 0.3, 0.15)], 0.12, 7)
	return [_tex(body), _tex(glow)]


## Брошенный вагон: зеленовато-ржавый, окна выбиты.
static func wreck(seed: int) -> ImageTexture:
	var w := 96
	var h := 42
	var img := _img(w, h)
	var base := Color(0.24, 0.27, 0.22)
	_rect(img, 2, 2, 92, 18, base.lightened(0.05))
	_rect(img, 2, 2, 92, 1, base.lightened(0.25))
	for x in range(2, 94, 8):
		_rect(img, x, 2, 1, 18, base.darkened(0.3))
	_rect(img, 2, 20, 92, 16, base.darkened(0.25))
	for wx in range(8, 88, 14):
		_rect(img, wx, 23, 9, 7, Color(0.04, 0.05, 0.05))
		if (wx / 14 + seed) % 3 == 0:
			_rect(img, wx + 2, 24, 3, 2, base) # осколки
	_rect(img, 4, 36, 88, 3, IRON_DARK)
	for wx in [10, 26, 64, 80]:
		_rect(img, wx, 37, 7, 5, Color(0.08, 0.08, 0.08))
	_grime(img, Rect2i(0, 0, w, h), [RUST, RUST_DARK, base.darkened(0.4), Color(0.35, 0.3, 0.2)], 0.22, seed)
	return _tex(img)


# ------------------------------------------------------------ персонажи

## Илья: капюшон, противогаз, плащ, рюкзак. frame 0/1 — шаг.
static func player(frame: int) -> ImageTexture:
	var img := _img(14, 22)
	var coat := Color(0.36, 0.27, 0.18)
	var hood := Color(0.30, 0.22, 0.15)
	_rect(img, 4, 0, 6, 7, hood)
	_rect(img, 5, 3, 5, 3, Color(0.45, 0.45, 0.42)) # маска
	_rect(img, 8, 4, 2, 1, Color(0.15, 0.15, 0.15)) # фильтр
	_rect(img, 1, 7, 4, 7, Color(0.30, 0.33, 0.20)) # рюкзак
	_rect(img, 1, 7, 4, 1, Color(0.40, 0.43, 0.27))
	_rect(img, 4, 7, 7, 9, coat)
	_rect(img, 4, 7, 7, 1, coat.lightened(0.2))
	_rect(img, 10, 9, 3, 2, coat.darkened(0.1)) # рука вперёд
	_rect(img, 4, 16, 7, 2, coat.darkened(0.25)) # полы плаща
	var leg := Color(0.14, 0.12, 0.10)
	if frame == 0:
		_rect(img, 5, 18, 2, 4, leg)
		_rect(img, 8, 18, 2, 4, leg)
	else:
		_rect(img, 4, 18, 2, 3, leg)
		_rect(img, 9, 18, 2, 4, leg)
	return _tex(img)


## Ржавец: сутулый, длинные руки. Возвращает [тело, глаза].
static func rustling(frame: int) -> Array:
	var img := _img(14, 22)
	var eyes := _img(14, 22)
	var c := Color(0.20, 0.11, 0.07)
	_rect(img, 4, 1, 6, 6, c)
	_rect(img, 3, 0, 1, 2, c) # рога
	_rect(img, 10, 0, 1, 2, c)
	_rect(img, 3, 7, 8, 8, c.lightened(0.05))
	var arm := 1 if frame == 0 else 0
	_rect(img, 1, 8 + arm, 2, 9, c)
	_rect(img, 11, 8 + (1 - arm), 2, 9, c)
	_rect(img, 4, 15, 2, 7 - arm, c.darkened(0.2))
	_rect(img, 8, 15, 2, 6 + arm, c.darkened(0.2))
	_grime(img, Rect2i(0, 0, 14, 22), [RUST, Color(0.3, 0.15, 0.08)], 0.25, 3 + frame)
	_rect(eyes, 5, 3, 1, 1, Color(1.0, 0.45, 0.1))
	_rect(eyes, 8, 3, 1, 1, Color(1.0, 0.45, 0.1))
	return [_tex(img), _tex(eyes)]


# ------------------------------------------------------------ окружение

static func scrap_pile(seed: int, looted: bool) -> ImageTexture:
	var img := _img(22, 12)
	_rng.seed = seed
	for y in 12:
		var half := int(11.0 * sqrt(1.0 - pow((y - 12.0) / 12.0, 2.0)))
		for x in range(11 - half, 11 + half):
			var cols := [IRON, IRON_DARK, RUST, RUST_DARK, Color(0.35, 0.33, 0.28)]
			var col: Color = cols[_rng.randi() % cols.size()]
			img.set_pixel(x, y, col.darkened(0.5) if looted else col)
	if not looted:
		_rect(img, 6, 3, 8, 1, IRON.lightened(0.3)) # торчащая труба
		_rect(img, 14, 5, 1, 4, RUST.lightened(0.2))
	return _tex(img)


## Станция: крыша сверху, кирпичная стена, заколоченные окна. Табличка — Label поверх.
static func station() -> ImageTexture:
	var w := 140
	var h := 96
	var img := _img(w, h)
	var roof := Color(0.22, 0.20, 0.19)
	_rect(img, 0, 0, w, 34, roof)
	for y in range(0, 34, 4):
		_rect(img, 0, y, w, 1, roof.darkened(0.35))
	_rect(img, 90, 0, 30, 14, CLEAR) # провал в крыше
	_rect(img, 92, 2, 26, 10, Color(0.06, 0.05, 0.05))
	var brick := Color(0.45, 0.20, 0.14)
	_rect(img, 0, 34, w, 62, brick)
	for y in range(34, 96, 4):
		_rect(img, 0, y, w, 1, brick.darkened(0.4))
		var off := 0 if (y / 4) % 2 == 0 else 5
		for x in range(off, w, 10):
			_rect(img, x, y, 1, 4, brick.darkened(0.4))
	_rect(img, 12, 38, 116, 12, Color(0.55, 0.6, 0.62)) # табличка
	_rect(img, 12, 49, 116, 1, Color(0.3, 0.32, 0.33))
	for wx in [16, 98]:
		_rect(img, wx, 56, 22, 22, Color(0.05, 0.05, 0.05))
		for py in [59, 65, 71]:
			_rect(img, wx - 2, py, 26, 3, Color(0.38, 0.28, 0.18)) # доски
	_rect(img, 60, 58, 20, 38, Color(0.08, 0.07, 0.06)) # дверь
	_grime(img, Rect2i(0, 34, w, 62), [brick.darkened(0.25), brick.lightened(0.1), Color(0.3, 0.3, 0.28)], 0.12, 11)
	return _tex(img)


static func generator(lit: bool) -> Array:
	var img := _img(24, 20)
	var glow := _img(24, 20)
	_rect(img, 1, 2, 22, 16, Color(0.33, 0.35, 0.33))
	_rect(img, 1, 2, 22, 1, Color(0.5, 0.52, 0.5))
	_rect(img, 1, 12, 22, 2, Color(0.75, 0.6, 0.1)) # жёлтая полоса
	_rect(img, 4, 5, 6, 5, Color(0.12, 0.12, 0.12)) # решётка
	_rect(img, 15, 4, 4, 4, Color(0.15, 0.15, 0.15))
	_grime(img, Rect2i(0, 0, 24, 20), [RUST, RUST_DARK], 0.2, 5)
	_rect(glow, 16, 5, 2, 2, Color(0.3, 1.0, 0.4) if lit else Color(0.6, 0.1, 0.05))
	return [_tex(img), _tex(glow)]


static func mushroom() -> ImageTexture:
	var img := _img(5, 6)
	_rect(img, 0, 0, 5, 2, Color(1.0, 0.65, 0.25))
	_rect(img, 1, 0, 3, 1, Color(1.0, 0.85, 0.5))
	_rect(img, 2, 2, 1, 4, Color(0.9, 0.8, 0.6))
	return _tex(img)


static func grass_tuft(seed: int) -> ImageTexture:
	var img := _img(9, 7)
	_rng.seed = seed
	for i in 6:
		var x := _rng.randi_range(0, 8)
		var hh := _rng.randi_range(3, 7)
		_rect(img, x, 7 - hh, 1, hh, Color(0.25, 0.32, 0.14).lerp(Color(0.45, 0.42, 0.2), _rng.randf()))
	return _tex(img)


# ------------------------------------------------------------ свет

static func radial_light(size: int) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, 0.45))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t


## Конус света: вершина в центре текстуры, луч смотрит вправо (+X).
static func cone_light(size: int, half_angle_deg: float) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := size * 0.5
	var half := deg_to_rad(half_angle_deg)
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c)
			var r := d.length() / c
			if r > 1.0 or d.x <= 0.0:
				img.set_pixel(x, y, CLEAR)
				continue
			var ang := absf(atan2(d.y, d.x))
			var edge := clampf(1.0 - (ang - half * 0.6) / (half * 0.4), 0.0, 1.0)
			var fall := pow(1.0 - r, 0.7)
			var near := clampf(r * 6.0, 0.0, 1.0) # не слепит у самой руки
			img.set_pixel(x, y, Color(1, 1, 1, edge * fall * near))
	return _tex(img)


# ------------------------------------------------------------ новые существа и люди

## Пёс Пепел (16×11). frame 0/1 — бег.
static func dog(frame: int) -> ImageTexture:
	var img := _img(16, 11)
	var fur := Color(0.42, 0.40, 0.38)
	_rect(img, 3, 3, 9, 4, fur)
	_rect(img, 11, 1, 4, 4, fur) # голова
	_rect(img, 14, 3, 2, 2, fur.darkened(0.2)) # морда
	_rect(img, 12, 0, 1, 2, fur.darkened(0.3)) # ухо
	_rect(img, 13, 2, 1, 1, Color(0.05, 0.05, 0.05)) # глаз
	_rect(img, 0, 2 + frame, 3, 1, fur) # хвост
	var l := 1 if frame == 0 else 0
	_rect(img, 4 - l, 7, 1, 4, fur.darkened(0.3))
	_rect(img, 6 + l, 7, 1, 4, fur.darkened(0.3))
	_rect(img, 9 - l, 7, 1, 4, fur.darkened(0.3))
	_rect(img, 11 + l, 7, 1, 4, fur.darkened(0.3))
	_grime(img, Rect2i(0, 0, 16, 11), [fur.lightened(0.15), fur.darkened(0.2)], 0.2, 9)
	return _tex(img)


## Стайник: мелкий тощий ржавец (10×15). Возвращает [тело, глаза].
static func packer(frame: int) -> Array:
	var img := _img(10, 15)
	var eyes := _img(10, 15)
	var c := Color(0.30, 0.14, 0.08)
	_rect(img, 3, 0, 4, 4, c)
	_rect(img, 2, 4, 6, 5, c)
	_rect(img, 0, 5 + frame, 2, 5, c)
	_rect(img, 8, 6 - frame, 2, 5, c)
	_rect(img, 3, 9, 1, 6 - frame, c.darkened(0.2))
	_rect(img, 6, 9, 1, 5 + frame, c.darkened(0.2))
	_rect(eyes, 3, 1, 1, 1, Color(1.0, 0.85, 0.2))
	_rect(eyes, 6, 1, 1, 1, Color(1.0, 0.85, 0.2))
	return [_tex(img), _tex(eyes)]


## Ползун: низкий бронированный, много глаз (24×13). Возвращает [тело, глаза].
static func crawler(frame: int) -> Array:
	var img := _img(24, 13)
	var eyes := _img(24, 13)
	var shell := Color(0.18, 0.17, 0.16)
	for x in 20:
		var hh := int(6.0 * sin(PI * (x + 0.5) / 20.0)) + 2
		_rect(img, x + 2, 9 - hh, 1, hh, shell.lightened(0.1 * float(x % 4 == 0)))
	for k in 5:
		var lx := 4 + k * 4
		_rect(img, lx, 9, 1, 3 + (k + frame) % 2, shell.darkened(0.3))
	_grime(img, Rect2i(0, 0, 24, 13), [RUST_DARK, Color(0.3, 0.28, 0.25)], 0.25, 13)
	for ex in [17, 19, 21]:
		_rect(eyes, ex, 5, 1, 1, Color(0.6, 1.0, 0.3))
	return [_tex(img), _tex(eyes)]


## Выживший (14×22): разные плащи и шапки по виду.
static func survivor(look: String) -> ImageTexture:
	var img := _img(14, 22)
	var coat := Color(0.30, 0.32, 0.36)
	var head := Color(0.75, 0.6, 0.5)
	var hat := Color(0.2, 0.2, 0.22)
	match look:
		"family":
			coat = Color(0.45, 0.30, 0.28)
			hat = Color(0.55, 0.5, 0.45)
		"mechanic":
			coat = Color(0.25, 0.32, 0.45)
			hat = Color(0.6, 0.45, 0.15)
		"trader":
			coat = Color(0.40, 0.34, 0.20)
			hat = Color(0.25, 0.18, 0.12)
		"miner":
			coat = Color(0.22, 0.22, 0.24)
			hat = Color(0.8, 0.7, 0.2)
		"hermit":
			coat = Color(0.45, 0.42, 0.40)
			hat = Color(0.85, 0.85, 0.85)
		"anya":
			coat = Color(0.30, 0.42, 0.36)
			hat = Color(0.7, 0.15, 0.15) # красный шарф/шапка
	_rect(img, 4, 0, 6, 3, hat)
	_rect(img, 5, 3, 5, 4, head)
	_rect(img, 3, 7, 8, 9, coat)
	_rect(img, 3, 7, 8, 1, coat.lightened(0.2))
	if look == "anya":
		_rect(img, 4, 7, 6, 2, hat)
	_rect(img, 4, 16, 6, 2, coat.darkened(0.25))
	_rect(img, 5, 18, 2, 4, Color(0.14, 0.12, 0.10))
	_rect(img, 8, 18, 2, 4, Color(0.14, 0.12, 0.10))
	if look == "family":
		_rect(img, 11, 12, 3, 10, Color(0.5, 0.4, 0.35)) # ребёнок рядом
		_rect(img, 11, 10, 3, 3, head)
	if look == "trader":
		_rect(img, 0, 15, 5, 7, Color(0.35, 0.25, 0.15)) # ящик с товаром
	return _tex(img)


## Цели глав: генератор, стрелка, ворота тоннеля, радиовышка. [тело, свечение]
static func goal(kind: String, done: bool) -> Array:
	match kind:
		"switch":
			var img := _img(20, 20)
			var glow := _img(20, 20)
			_rect(img, 2, 12, 16, 6, IRON_DARK)
			_rect(img, 8, 6, 4, 7, IRON)
			var lean := 4 if done else -4
			for i in 8:
				_rect(img, 10 + int(lean * i / 8.0), 6 - i, 2, 1, Color(0.7, 0.15, 0.1))
			_rect(glow, 9, 13, 2, 2, Color(0.3, 1.0, 0.4) if done else Color(0.9, 0.2, 0.1))
			return [_tex(img), _tex(glow)]
		"gate":
			var img := _img(40, 30)
			var glow := _img(40, 30)
			_rect(img, 0, 0, 40, 30, Color(0.15, 0.14, 0.13))
			_rect(img, 4, 4, 32, 26, Color(0.04, 0.04, 0.04) if done else Color(0.30, 0.22, 0.14))
			if not done:
				for x in range(6, 36, 5):
					_rect(img, x, 4, 1, 26, Color(0.2, 0.15, 0.1))
			_grime(img, Rect2i(0, 0, 40, 30), [RUST, RUST_DARK], 0.15, 4)
			_rect(glow, 18, 1, 4, 2, Color(0.3, 1.0, 0.4) if done else Color(0.9, 0.2, 0.1))
			return [_tex(img), _tex(glow)]
		"tower":
			var img := _img(26, 60)
			var glow := _img(26, 60)
			for y in 58:
				var half := 2 + int(y * 0.18)
				_rect(img, 13 - half, y + 2, 1, 1, IRON)
				_rect(img, 13 + half, y + 2, 1, 1, IRON)
				if y % 8 == 0:
					_rect(img, 13 - half, y + 2, half * 2 + 1, 1, IRON_DARK)
			_rect(glow, 12, 0, 3, 3, Color(1.0, 0.25, 0.15) if done else Color(0.25, 0.08, 0.06))
			return [_tex(img), _tex(glow)]
	return generator(done)


static func safe(open: bool) -> ImageTexture:
	var img := _img(16, 16)
	_rect(img, 1, 2, 14, 14, Color(0.32, 0.34, 0.36))
	_rect(img, 1, 2, 14, 1, Color(0.5, 0.52, 0.54))
	if open:
		_rect(img, 3, 4, 10, 10, Color(0.05, 0.05, 0.05))
	else:
		_rect(img, 6, 7, 4, 4, Color(0.15, 0.15, 0.15))
		_rect(img, 7, 8, 2, 2, Color(0.7, 0.65, 0.4))
	_grime(img, Rect2i(0, 0, 16, 16), [RUST, RUST_DARK], 0.15, 21)
	return _tex(img)


static func coal_heap(seed: int) -> ImageTexture:
	var img := _img(26, 12)
	_rng.seed = seed
	for y in 12:
		var half := int(13.0 * sqrt(1.0 - pow((y - 12.0) / 12.0, 2.0)))
		for x in range(13 - half, 13 + half):
			img.set_pixel(x, y, Color(0.06, 0.06, 0.07).lerp(Color(0.2, 0.2, 0.22), _rng.randf() * 0.6))
	return _tex(img)
