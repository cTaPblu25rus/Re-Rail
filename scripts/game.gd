## RE-RAIL: Хроники Пепла — пролог «Пепельная».
##
## Илья едет на бронедрезине сквозь ядовитый туман. Цель пролога: доехать до станции
## «Пепельная», собрать 5 кусков хлама и починить генератор. После этого радио
## впервые ловит голос дочери.
##
## Управление пишет в `ctl` (сенсорный HUD или автоигрок) — вся логика здесь.
extends Node2D

const Art := preload("res://scripts/pixel_art.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Hud := preload("res://scripts/hud.gd")
const Menu := preload("res://scripts/menu.gd")
const GroundShader := preload("res://shaders/ground.gdshader")
const FogShader := preload("res://shaders/fog.gdshader")

const WORLD := Rect2(0, -330, 3400, 660)
const RAIL_Y := 0.0
const TRAIN_MAX := 115.0
const TRAIN_ACCEL := 55.0
const WALK := 62.0
const SCRAP_FOR_GENERATOR := 5
const FLASH_RANGE := 175.0
const FLASH_HALF_ANGLE := 24.0
const TORCH_TIME := 60.0

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const AUTOSAVE_EVERY := 45.0

## Что делать при (пере)загрузке сцены: "menu", "new" или "continue".
static var boot_action := "menu"

const ITEMS := ["ammo", "medkit", "crowbar", "torch", "cans"]
const ITEM_NAMES := {"ammo": "Патроны", "medkit": "Аптечка", "crowbar": "Лом", "torch": "Факел", "cans": "Консервы"}

var sfx: Node
var hud: CanvasLayer
var menu: CanvasLayer
var autoplay := false
var state := "menu" # "menu" — главное меню на фоне мира, "play" — игра
var paused := false
var vibration := true
var autosave_t := 0.0

# --- управление (пишут HUD или автоигрок)
var ctl := {"move": Vector2.ZERO, "aim": Vector2.RIGHT, "aiming": false, "search": false}

# --- состояние Ильи
var stats := {"health": 100.0, "hunger": 80.0, "warmth": 70.0, "sanity": 90.0, "battery": 100.0}
var inv := {"ammo": 6, "medkit": 1, "crowbar": 1, "torch": 2, "cans": 2, "scrap": 0, "coal": 40.0}
var aboard := true
var flashlight_on := true
var torch_left := 0.0
var player_pos := Vector2(220, 30)
var facing := Vector2.RIGHT
var attack_cd := 0.0
var hurt_flash := 0.0
var dead := false
var search_t := 0.0
var step_t := 0.0

# --- дрезина
var train_x := 220.0
var train_v := 0.0

# --- мир
var piles: Array[Dictionary] = []
var monsters: Array[Dictionary] = []
var obstacles: Array[Rect2] = []
var echoes: Array[Dictionary] = []
var spawn_t := 5.0
var generator_fixed := false
var finished := false
var objective := ""
var messages: Array[Dictionary] = []
var time := 0.0

# --- радио
var radio_open := false
var radio_freq := 92.0
var radio_signal := 0.0
var radio_echo: Dictionary = {}
var decode_t := 0.0

# --- узлы
var cam: Camera2D
var ents: Node2D
var train_node: Node2D
var player_node: Node2D
var player_sprite: Sprite2D
var player_frames: Array[Texture2D] = []
var flash_light: PointLight2D
var torch_light: PointLight2D
var generator_body: Sprite2D
var generator_glow: Sprite2D
var station_lights: Array[PointLight2D] = []
var fire_light: PointLight2D
var fog_layers: Array[ColorRect] = []
var rust_frames: Array = []
var noise_tex: NoiseTexture2D


func _ready() -> void:
	autoplay = OS.get_cmdline_user_args().has("--autoplay")
	if autoplay and boot_action == "menu":
		boot_action = "continue" if OS.get_cmdline_user_args().has("--continue") else "new"
	randomize()
	sfx = Sfx.new()
	add_child(sfx)
	_build_world()
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	menu = Menu.new()
	menu.game = self
	add_child(menu)
	menu.apply_settings()
	match boot_action:
		"new":
			_start_play()
			say("Илья: «Держись, родная. Я еду».")
			save_game()
		"continue":
			_start_play()
			if not load_game():
				say("Сохранение повреждено — начинаем заново.")
		_:
			state = "menu"
			menu.main_menu()
	if autoplay:
		var bot: Node = load("res://tools/autoplay.gd").new()
		bot.game = self
		add_child(bot)


func _start_play() -> void:
	state = "play"
	paused = false


# ============================================================ меню, пауза, сохранения

## Перезапуск сцены с нужным действием — самый надёжный «чистый лист».
func boot(action: String) -> void:
	boot_action = action
	get_tree().reload_current_scene()


func set_paused(p: bool) -> void:
	paused = p if state == "play" else false
	if paused:
		ctl.move = Vector2.ZERO
		ctl.search = false
		ctl.aiming = false
		sfx.set_engine(0.0, false)


func apply_settings(st: Dictionary) -> void:
	vibration = st.vibration
	if fog_layers.size() > 1:
		fog_layers[1].visible = st.fog_hq


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if menu == null:
				return
			if menu.is_open():
				menu.back()
			elif state == "play":
				menu.pause_menu()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if state == "play" and not dead and not autoplay:
				save_game()
				if what != NOTIFICATION_WM_CLOSE_REQUEST and menu != null and not menu.is_open():
					menu.pause_menu()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_summary() -> String:
	var d := _read_save()
	if d.is_empty():
		return ""
	var mins := int(float(d.get("time", 0.0)) / 60.0)
	return "Пролог · %d мин в пути · хлам %d" % [mins, int(d.get("inv", {}).get("scrap", 0))]


func wipe_save() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func save_game() -> void:
	if state != "play" or autoplay and not OS.get_cmdline_user_args().has("--test-save"):
		return
	var looted := []
	for p in piles:
		looted.append(p.looted)
	var heard := []
	for e in echoes:
		heard.append(e.done)
	var d := {
		"version": SAVE_VERSION, "time": time,
		"stats": stats, "inv": inv,
		"aboard": aboard, "player": [player_pos.x, player_pos.y], "train_x": train_x,
		"flashlight_on": flashlight_on, "torch_left": torch_left,
		"looted": looted, "echoes": heard,
		"generator_fixed": generator_fixed, "finished": finished,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


func _read_save() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func load_game() -> bool:
	var d := _read_save()
	if d.is_empty() or int(d.get("version", 0)) != SAVE_VERSION:
		return false
	time = float(d.time)
	for k in stats:
		stats[k] = float(d.stats.get(k, stats[k]))
	for k in inv:
		inv[k] = float(d.inv.get(k, inv[k])) if k == "coal" else int(d.inv.get(k, inv[k]))
	aboard = bool(d.aboard)
	player_pos = Vector2(float(d.player[0]), float(d.player[1]))
	train_x = float(d.train_x)
	flashlight_on = bool(d.flashlight_on)
	torch_left = float(d.torch_left)
	for i in mini(piles.size(), d.looted.size()):
		if d.looted[i]:
			piles[i].looted = true
			piles[i].sprite.texture = Art.scrap_pile(int(piles[i].pos.x), true)
	for i in mini(echoes.size(), d.echoes.size()):
		echoes[i].done = bool(d.echoes[i])
	if d.generator_fixed:
		_light_station()
	finished = bool(d.finished)
	say("Продолжаем путь.")
	return true


# ============================================================ мир

func _build_world() -> void:
	var cm := CanvasModulate.new()
	cm.color = Color(0.24, 0.30, 0.28)
	add_child(cm)

	noise_tex = NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	fn.fractal_octaves = 3
	noise_tex.noise = fn
	noise_tex.seamless = true
	noise_tex.width = 256
	noise_tex.height = 256

	var ground := ColorRect.new()
	ground.position = WORLD.position - Vector2(200, 200)
	ground.size = WORLD.size + Vector2(400, 400)
	var gm := ShaderMaterial.new()
	gm.shader = GroundShader
	gm.set_shader_parameter("noise", noise_tex)
	gm.set_shader_parameter("rail_y", RAIL_Y)
	ground.material = gm
	ground.z_index = -10
	add_child(ground)

	ents = Node2D.new()
	ents.y_sort_enabled = true
	add_child(ents)

	_build_train()
	_build_player()
	rust_frames = [Art.rustling(0), Art.rustling(1)]

	# брошенные вагоны на запасных путях
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var wrecks := [Vector2(700, -120), Vector2(1250, -110), Vector2(1900, 140), Vector2(2350, -130)]
	for i in wrecks.size():
		_add_wreck(wrecks[i], 3 + i)
	_add_wreck(Vector2(1320.0, -168.0), 7)

	# станция «Пепельная»
	var st := Sprite2D.new()
	st.texture = Art.station()
	st.offset = Vector2(0, -48)
	st.position = Vector2(2760, -150)
	ents.add_child(st)
	obstacles.append(Rect2(2690, -186, 140, 36))
	var sign := Label.new()
	sign.text = "СТАНЦИЯ ПЕПЕЛЬНАЯ"
	sign.add_theme_font_size_override("font_size", 9)
	sign.add_theme_color_override("font_color", Color(0.12, 0.14, 0.16))
	sign.position = Vector2(-58, -59)
	sign.size = Vector2(116, 12)
	sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.add_child(sign)

	var gen := Node2D.new()
	gen.position = Vector2(2860, -110)
	ents.add_child(gen)
	var gtex := Art.generator(false)
	generator_body = Sprite2D.new()
	generator_body.texture = gtex[0]
	generator_body.offset = Vector2(0, -10)
	gen.add_child(generator_body)
	generator_glow = _glow_sprite(gtex[1], Vector2(0, -10))
	gen.add_child(generator_glow)
	obstacles.append(Rect2(2848, -118, 24, 10))
	for lp in [Vector2(2760, -120), Vector2(2860, -100), Vector2(2650, -90)]:
		var l := _light(Art.radial_light(256), lp, Color(1.0, 0.85, 0.55), 1.3, 1.2)
		l.enabled = false
		add_child(l)
		station_lights.append(l)

	# костёр в бочке у стартовой стоянки
	var fire := Node2D.new()
	fire.position = Vector2(150, 70)
	ents.add_child(fire)
	var barrel := Sprite2D.new()
	var bimg := Image.create(10, 12, false, Image.FORMAT_RGBA8)
	bimg.fill(Color(0.25, 0.2, 0.17))
	bimg.fill_rect(Rect2i(0, 3, 10, 1), Color(0.15, 0.12, 0.1))
	bimg.fill_rect(Rect2i(0, 8, 10, 1), Color(0.15, 0.12, 0.1))
	barrel.texture = ImageTexture.create_from_image(bimg)
	barrel.offset = Vector2(0, -6)
	fire.add_child(barrel)
	var flame := CPUParticles2D.new()
	flame.position = Vector2(0, -12)
	flame.amount = 18
	flame.lifetime = 0.7
	flame.direction = Vector2(0, -1)
	flame.spread = 20
	flame.initial_velocity_min = 8
	flame.initial_velocity_max = 18
	flame.gravity = Vector2(0, -10)
	flame.scale_amount_min = 1.5
	flame.scale_amount_max = 2.5
	flame.color_ramp = _fire_ramp()
	flame.material = _unshaded()
	fire.add_child(flame)
	fire_light = _light(Art.radial_light(256), Vector2(150, 60), Color(1.0, 0.6, 0.3), 1.2, 0.9)
	add_child(fire_light)

	# кучи хлама
	_add_pile(Vector2(900, 110), {"scrap": 2, "coal": 15.0, "cans": 1})
	_add_pile(Vector2(1620, -140), {"scrap": 1, "battery": 40.0})
	_add_pile(Vector2(1180, 150), {"ammo": 4, "coal": 8.0})
	_add_pile(Vector2(2560, 120), {"scrap": 2, "torch": 1})
	_add_pile(Vector2(2700, -95), {"scrap": 1, "medkit": 1})

	# светящиеся грибы и трава
	for i in 70:
		var p := Vector2(rng.randf_range(40, WORLD.end.x - 40), rng.randf_range(-300, 300))
		if absf(p.y - RAIL_Y) < 30.0:
			continue
		var tuft := Sprite2D.new()
		tuft.texture = Art.grass_tuft(i)
		tuft.offset = Vector2(0, -3)
		tuft.position = p
		ents.add_child(tuft)
	for i in 16:
		var p := Vector2(rng.randf_range(100, WORLD.end.x - 100), rng.randf_range(-280, 280))
		if absf(p.y - RAIL_Y) < 34.0:
			continue
		for k in 3:
			var m := Sprite2D.new()
			m.texture = Art.mushroom()
			m.material = _unshaded()
			m.position = p + Vector2(rng.randf_range(-6, 6), rng.randf_range(-4, 4))
			m.offset = Vector2(0, -3)
			ents.add_child(m)
		if i % 2 == 0:
			add_child(_light(Art.radial_light(64), p, Color(1.0, 0.6, 0.25), 0.7, 0.5))

	# эхо прошлого (радио)
	echoes = [
		{"pos": Vector2(1300, -110), "freq": 94.2, "radius": 260.0, "done": false,
			"text": "…рейс двести четырнадцать… не открывайте двери… в тумане кто-то ходит…"},
		{"pos": Vector2(2700, -60), "freq": 101.4, "radius": 320.0, "done": false,
			"text": "…генератор на Пепельной… ему нужно пять кусков железа… свет их отгоняет…"},
		{"pos": Vector2.ZERO, "freq": 103.7, "radius": -1.0, "done": false, "locked": true,
			"text": "…папа?.. если ты слышишь… я жива… Тайшет… конец магистрали… приезжай…"},
	]

	# камера, туман и искры
	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 5.0
	cam.zoom = Vector2(2, 2)
	cam.limit_left = int(WORLD.position.x)
	cam.limit_right = int(WORLD.end.x)
	cam.limit_top = int(WORLD.position.y)
	cam.limit_bottom = int(WORLD.end.y)
	add_child(cam)
	var base_fog := Shader.new()
	base_fog.code = FogShader.code.replace("render_mode blend_mix;", "render_mode blend_mix, unshaded;")
	var lit_fog := Shader.new()
	lit_fog.code = FogShader.code.replace("render_mode blend_mix;", "render_mode blend_add;")
	for cfg in [[base_fog, 0.3, Color(0.42, 0.56, 0.50), 6.0], [lit_fog, 0.32, Color(0.55, 0.75, 0.6), 9.0]]:
		var fr := ColorRect.new()
		var fm := ShaderMaterial.new()
		fm.shader = cfg[0]
		fm.set_shader_parameter("noise", noise_tex)
		fm.set_shader_parameter("density", cfg[1])
		fm.set_shader_parameter("fog_color", cfg[2])
		fm.set_shader_parameter("drift", cfg[3])
		fr.material = fm
		fr.z_index = 40
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cam.add_child(fr)
		fog_layers.append(fr)
	var embers := CPUParticles2D.new()
	embers.amount = 40
	embers.lifetime = 6.0
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(180, 110)
	embers.direction = Vector2(0.3, -1)
	embers.spread = 40
	embers.gravity = Vector2(4, -3)
	embers.initial_velocity_min = 3
	embers.initial_velocity_max = 10
	embers.scale_amount_min = 1
	embers.scale_amount_max = 1.5
	embers.color = Color(1.0, 0.55, 0.2, 0.85)
	embers.material = _unshaded()
	embers.z_index = 41
	cam.add_child(embers)


func _fire_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.5, 1))
	g.set_color(1, Color(0.8, 0.2, 0.05, 0))
	return g


func _unshaded() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return m


func _glow_sprite(tex: Texture2D, offset: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.offset = offset
	s.material = _unshaded()
	return s


func _light(tex: Texture2D, pos: Vector2, col: Color, energy: float, scale: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = tex
	l.position = pos
	l.color = col
	l.energy = energy
	l.texture_scale = scale
	return l


func _build_train() -> void:
	train_node = Node2D.new()
	ents.add_child(train_node)
	var tex := Art.draisine()
	var body := Sprite2D.new()
	body.texture = tex[0]
	body.offset = Vector2(0, -23)
	train_node.add_child(body)
	train_node.add_child(_glow_sprite(tex[1], Vector2(0, -23)))
	train_node.add_child(_light(Art.radial_light(256), Vector2(-8, -6), Color(1.0, 0.62, 0.3), 1.15, 0.85))
	var cone := Art.cone_light(256, 20.0)
	for hy in [-18.0, -10.0]:
		var hl := _light(cone, Vector2(40, hy), Color(1.0, 0.93, 0.75), 0.65, 1.6)
		train_node.add_child(hl)


func _build_player() -> void:
	player_node = Node2D.new()
	ents.add_child(player_node)
	player_frames = [Art.player(0), Art.player(1)]
	player_sprite = Sprite2D.new()
	player_sprite.texture = player_frames[0]
	player_sprite.offset = Vector2(0, -11)
	player_node.add_child(player_sprite)
	flash_light = _light(Art.cone_light(256, FLASH_HALF_ANGLE), Vector2(0, -10), Color(1.0, 0.95, 0.8), 0.85, FLASH_RANGE / 128.0)
	player_node.add_child(flash_light)
	# слабый отсвет фонаря на самом Илье — чтобы его было видно в темноте
	player_node.add_child(_light(Art.radial_light(128), Vector2(0, -10), Color(0.9, 0.85, 0.7), 0.55, 0.42))
	torch_light = _light(Art.radial_light(256), Vector2(0, -12), Color(1.0, 0.55, 0.25), 1.1, 0.75)
	torch_light.enabled = false
	player_node.add_child(torch_light)


func _add_wreck(pos: Vector2, seed: int) -> void:
	var s := Sprite2D.new()
	s.texture = Art.wreck(seed)
	s.offset = Vector2(0, -21)
	s.position = pos
	ents.add_child(s)
	obstacles.append(Rect2(pos.x - 46, pos.y - 24, 92, 24))


func _add_pile(pos: Vector2, loot: Dictionary) -> void:
	var s := Sprite2D.new()
	s.texture = Art.scrap_pile(int(pos.x), false)
	s.offset = Vector2(0, -6)
	s.position = pos
	ents.add_child(s)
	piles.append({"pos": pos, "loot": loot, "looted": false, "sprite": s})


# ============================================================ API для HUD и автоигрока

func say(text: String) -> void:
	messages.append({"text": text, "t": time})
	while messages.size() > 3:
		messages.pop_front()


func train_rect() -> Rect2:
	return Rect2(train_x - 42, RAIL_Y - 30, 84, 38)


func door_pos() -> Vector2:
	return Vector2(train_x + 14, RAIL_Y + 22)


func nearest_pile() -> Dictionary:
	var best: Dictionary = {}
	var bd := 28.0
	for p in piles:
		if p.looted:
			continue
		var d: float = player_pos.distance_to(p.pos)
		if d < bd:
			bd = d
			best = p
	return best


## Контекстная кнопка: что сейчас можно сделать рукой.
func context() -> Dictionary:
	if dead:
		return {"kind": "none", "label": ""}
	if aboard:
		return {"kind": "exit", "label": "Выйти"}
	if player_pos.distance_to(door_pos()) < 30.0:
		return {"kind": "board", "label": "Сесть"}
	if not generator_fixed and player_pos.distance_to(Vector2(2860, -100)) < 34.0:
		return {"kind": "repair", "label": "Чинить"}
	if not nearest_pile().is_empty():
		return {"kind": "search", "label": "Обыскать"}
	return {"kind": "none", "label": "Обыскать"}


## Нажатие контекстной кнопки (down = true) или её отпускание.
func press_context(down: bool) -> void:
	var c := context()
	ctl.search = down and c.kind == "search"
	if not down:
		return
	match c.kind:
		"exit":
			_exit_train()
		"board":
			_board_train()
		"repair":
			_repair()


func toggle_flashlight() -> void:
	if aboard or dead:
		return
	flashlight_on = not flashlight_on
	sfx.play("click", -6.0)


func attack() -> void:
	if aboard or dead or attack_cd > 0.0:
		return
	if inv.crowbar <= 0:
		say("Нечем бить.")
		return
	attack_cd = 0.5
	sfx.play("swing", -4.0)
	var hit := false
	for m in monsters:
		var to: Vector2 = m.pos - player_pos
		if to.length() < 30.0 and to.normalized().dot(facing) > 0.2:
			m.hp -= 1.5
			m.pos += to.normalized() * 30.0
			m.burn = maxf(m.burn, 0.4)
			hit = true
	if hit:
		sfx.play("hit", 0.0)
		_vibrate(30, 0.6)


func use_item(id: String) -> void:
	if dead:
		return
	match id:
		"ammo":
			say("Патронов: %d. Ружьё соберёшь на верстаке (скоро)." % inv.ammo)
		"medkit":
			if inv.medkit > 0 and stats.health < 100.0:
				inv.medkit -= 1
				stats.health = minf(100.0, stats.health + 45.0)
				sfx.play("pickup", -4.0, 0.8)
				say("Аптечка: +45 здоровья.")
		"crowbar":
			say("Лом в руке. «Атака» — удар.")
		"torch":
			if torch_left > 0.0:
				say("Факел уже горит.")
			elif inv.torch > 0:
				inv.torch -= 1
				torch_left = TORCH_TIME
				sfx.play("clank", -14.0, 1.6)
				say("Факел зажжён: тепло и свет на минуту.")
		"cans":
			if inv.cans > 0:
				inv.cans -= 1
				stats.hunger = minf(100.0, stats.hunger + 45.0)
				sfx.play("pickup", -6.0, 0.7)
				say("Консервы: голод отступил.")


func toggle_radio() -> void:
	radio_open = not radio_open
	sfx.play("click", -4.0)


func respawn() -> void:
	if not dead:
		return
	dead = false
	aboard = true
	stats.health = 55.0
	stats.sanity = maxf(stats.sanity, 50.0)
	stats.warmth = maxf(stats.warmth, 60.0)
	stats.hunger = maxf(stats.hunger, 40.0)
	monsters_clear()
	say("Илья очнулся в дрезине. Голова гудит.")


func monsters_clear() -> void:
	for m in monsters:
		m.node.queue_free()
	monsters.clear()


# ============================================================ действия

func _exit_train() -> void:
	if absf(train_v) > 12.0:
		say("Слишком быстро — сначала притормози.")
		return
	aboard = false
	train_v = 0.0
	player_pos = door_pos() + Vector2(0, 4)
	facing = Vector2.DOWN
	sfx.play("clank", -12.0, 0.7)


func _board_train() -> void:
	aboard = true
	ctl.search = false
	sfx.play("clank", -12.0, 0.8)


func _repair() -> void:
	if inv.scrap < SCRAP_FOR_GENERATOR:
		say("Генератору нужно %d хлама. У тебя %d." % [SCRAP_FOR_GENERATOR, inv.scrap])
		return
	inv.scrap -= SCRAP_FOR_GENERATOR
	_light_station()
	sfx.play("clank", 0.0, 0.9)
	_vibrate(200, 1.0)
	say("Генератор ожил! Пепельная залита светом.")
	say("Радио затрещало… поймай частоту 103.7")
	save_game()


func _light_station() -> void:
	generator_fixed = true
	var g := Art.generator(true)
	generator_body.texture = g[0]
	generator_glow.texture = g[1]
	for l in station_lights:
		l.enabled = true
	echoes[2].locked = false


func _loot(p: Dictionary) -> void:
	p.looted = true
	p.sprite.texture = Art.scrap_pile(int(p.pos.x), true)
	var parts: Array[String] = []
	for k in p.loot:
		var v = p.loot[k]
		match k:
			"scrap":
				inv.scrap += int(v)
				parts.append("хлам ×%d" % int(v))
			"coal":
				inv.coal += float(v)
				parts.append("уголь +%d" % int(v))
			"battery":
				stats.battery = minf(100.0, stats.battery + float(v))
				parts.append("батарейки")
			_:
				inv[k] += int(v)
				parts.append("%s ×%d" % [ITEM_NAMES[k].to_lower(), int(v)])
	sfx.play("pickup", -2.0)
	_vibrate(40, 0.5)
	say("Найдено: " + ", ".join(parts))


func _vibrate(ms: int, amp: float) -> void:
	if vibration and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, amp)


# ============================================================ цикл

func _process(delta: float) -> void:
	if state == "menu":
		# главное меню: мир живёт, камера медленно плывёт вдоль путей
		time += delta
		ctl.move = Vector2.ZERO
		train_x = 220.0
		_update_visuals(delta)
		cam.position = Vector2(300.0 + fmod(time * 14.0, 2400.0), RAIL_Y - 10.0)
		return
	if paused:
		time += delta # сообщения в меню паузы продолжают гаснуть
		_update_visuals(0.0)
		return
	time += delta
	autosave_t += delta
	if autosave_t > AUTOSAVE_EVERY:
		autosave_t = 0.0
		save_game()
	if not dead:
		_update_train(delta)
		if not aboard:
			_update_player(delta)
		_update_survival(delta)
		_update_monsters(delta)
	_update_radio(delta)
	_update_objective()
	_update_visuals(delta)


func _update_train(delta: float) -> void:
	var throttle := 0.0
	if aboard:
		throttle = clampf(ctl.move.x, -1.0, 1.0)
		if absf(throttle) < 0.2:
			throttle = 0.0
	if throttle != 0.0 and inv.coal > 0.0:
		train_v = move_toward(train_v, throttle * TRAIN_MAX, TRAIN_ACCEL * delta)
		inv.coal = maxf(0.0, inv.coal - absf(throttle) * 0.75 * delta)
		if inv.coal <= 0.0:
			say("Уголь кончился!")
	else:
		train_v = move_toward(train_v, 0.0, TRAIN_ACCEL * 0.8 * delta)
	train_x = clampf(train_x + train_v * delta, 70.0, WORLD.end.x - 70.0)
	if train_x <= 70.0 or train_x >= WORLD.end.x - 70.0:
		train_v = 0.0
	sfx.set_engine(absf(train_v) / TRAIN_MAX, aboard)


func _update_player(delta: float) -> void:
	attack_cd -= delta
	var mv: Vector2 = ctl.move
	if mv.length() > 1.0:
		mv = mv.normalized()
	var slow := 0.6 if stats.sanity <= 0.0 else 1.0
	var step := mv * WALK * slow * delta
	_move_player(step)
	if ctl.aiming:
		facing = (ctl.aim as Vector2).normalized()
	elif mv.length() > 0.2:
		facing = mv.normalized()
	if mv.length() > 0.2:
		step_t += delta * mv.length()
		if step_t > 0.32:
			step_t = 0.0
			sfx.play("step", -14.0)
	# обыск — удержание кнопки
	var pile := nearest_pile()
	if ctl.search and not pile.is_empty():
		search_t += delta
		if search_t >= 1.0:
			search_t = 0.0
			ctl.search = false
			_loot(pile)
	else:
		search_t = 0.0


func _move_player(step: Vector2) -> void:
	var rects := obstacles.duplicate()
	rects.append(train_rect())
	for axis in [Vector2(step.x, 0), Vector2(0, step.y)]:
		var np: Vector2 = player_pos + axis
		var feet := Rect2(np.x - 4, np.y - 3, 8, 3)
		var blocked := false
		for r in rects:
			if r.intersects(feet):
				blocked = true
				break
		if not blocked:
			player_pos = np
	player_pos = player_pos.clamp(WORLD.position + Vector2(10, 20), WORLD.end - Vector2(10, 10))


## Насколько точка защищена светом (0..1): лампы дрезины, костёр, станция, факел.
func safety(p: Vector2) -> float:
	var s := 0.0
	s = maxf(s, 1.0 - p.distance_to(Vector2(train_x - 8, RAIL_Y - 6)) / 95.0)
	s = maxf(s, 1.0 - p.distance_to(Vector2(150, 64)) / 80.0)
	if generator_fixed:
		s = maxf(s, 1.0 - p.distance_to(Vector2(2780, -110)) / 220.0)
	if torch_left > 0.0 and not aboard:
		s = maxf(s, (1.0 - p.distance_to(player_pos) / 80.0) * 0.9)
	return clampf(s * 2.0, 0.0, 1.0)


func _update_survival(delta: float) -> void:
	stats.hunger = maxf(0.0, stats.hunger - 0.28 * delta)
	var lit := 1.0 if aboard else safety(player_pos)
	var warm := aboard or player_pos.distance_to(Vector2(150, 64)) < 60.0 or torch_left > 0.0
	stats.warmth = clampf(stats.warmth + (3.5 if warm else -0.65) * delta, 0.0, 100.0)
	if lit > 0.4:
		stats.sanity = minf(100.0, stats.sanity + 4.0 * delta)
	else:
		var drain := 1.4 * (0.5 if flashlight_on and stats.battery > 0.0 else 1.0)
		stats.sanity = maxf(0.0, stats.sanity - drain * delta)
	if not aboard and flashlight_on:
		stats.battery = maxf(0.0, stats.battery - 0.9 * delta)
		if stats.battery <= 0.0:
			flashlight_on = false
			say("Фонарь сел.")
	if torch_left > 0.0:
		torch_left -= delta
		if torch_left <= 0.0:
			say("Факел догорел.")
	var dmg := 0.0
	if stats.hunger <= 0.0:
		dmg += 0.8
	if stats.warmth <= 0.0:
		dmg += 1.2
	if stats.sanity <= 0.0:
		dmg += 1.5
	_damage(dmg * delta, false)


func _damage(amount: float, loud: bool) -> void:
	if amount <= 0.0 or dead:
		return
	stats.health = maxf(0.0, stats.health - amount)
	if loud:
		hurt_flash = 1.0
		sfx.play("hurt", 0.0)
		_vibrate(80, 0.9)
	if stats.health <= 0.0:
		dead = true
		ctl.search = false
		say("Илья пал во тьме.")


func flashlight_active() -> bool:
	return flashlight_on and stats.battery > 0.0 and not aboard


func _update_monsters(delta: float) -> void:
	if aboard:
		# Ржавцы не подходят к освещённой дрезине — расползаются.
		for m in monsters:
			m.pos += (m.pos - player_pos).normalized() * 50.0 * delta
			m.fade -= delta
	else:
		spawn_t -= delta
		if spawn_t <= 0.0:
			spawn_t = randf_range(3.5, 6.5) * (0.6 if stats.sanity < 30.0 else 1.0)
			if monsters.size() < 4:
				_spawn_monster()
	var flash_dir := facing
	for m in monsters:
		m.hit_cd -= delta
		m.anim += delta
		var to_player: Vector2 = player_pos - m.pos
		var dist := to_player.length()
		var lit_by_flash := false
		if flashlight_active() and dist < FLASH_RANGE:
			var ang := rad_to_deg(absf(flash_dir.angle_to(-to_player)))
			lit_by_flash = ang < FLASH_HALF_ANGLE
		var afraid := lit_by_flash or safety(m.pos) > 0.3
		if aboard:
			pass
		elif afraid:
			m.pos -= to_player.normalized() * (65.0 if lit_by_flash else 45.0) * delta
			if lit_by_flash:
				m.burn += delta
				m.hp -= delta * 1.6
		else:
			m.pos += to_player.normalized() * 34.0 * delta
			if dist < 12.0 and m.hit_cd <= 0.0:
				m.hit_cd = 1.2
				_damage(12.0, true)
				m.pos -= to_player.normalized() * 24.0
		m.node.position = m.pos
		var fr: Array = rust_frames[int(m.anim * 4.0) % 2]
		m.body.texture = fr[0]
		m.eyes.texture = fr[1]
		m.body.flip_h = to_player.x < 0.0
		m.eyes.flip_h = m.body.flip_h
		m.node.modulate = Color(1, 1, 1, clampf(m.fade, 0.0, 1.0)) * (Color(1.6, 1.2, 1.0, 1) if lit_by_flash else Color.WHITE)
	# гибель и уход
	for i in range(monsters.size() - 1, -1, -1):
		var m := monsters[i]
		if m.hp <= 0.0:
			inv.scrap += 1
			sfx.play("hit", -6.0, 0.6)
			say("Ржавец рассыпался. Хлам +1")
			m.node.queue_free()
			monsters.remove_at(i)
		elif m.fade <= 0.0 or m.pos.distance_to(player_pos) > 520.0:
			m.node.queue_free()
			monsters.remove_at(i)


func _spawn_monster() -> void:
	for attempt in 8:
		var ang := randf() * TAU
		var p := player_pos + Vector2(cos(ang), sin(ang)) * randf_range(250.0, 320.0)
		if not WORLD.grow(-20).has_point(p) or safety(p) > 0.0:
			continue
		var node := Node2D.new()
		var body := Sprite2D.new()
		body.offset = Vector2(0, -11)
		node.add_child(body)
		var eyes := _glow_sprite(rust_frames[0][1], Vector2(0, -11))
		node.add_child(eyes)
		node.position = p
		ents.add_child(node)
		monsters.append({"node": node, "body": body, "eyes": eyes, "pos": p, "hp": 3.0, "burn": 0.0,
			"hit_cd": 0.0, "anim": randf(), "fade": 1.0})
		var d := p.distance_to(player_pos)
		sfx.play("growl", linear_to_db(clampf(1.2 - d / 400.0, 0.05, 1.0)), randf_range(0.8, 1.1))
		return


func _update_radio(delta: float) -> void:
	radio_signal = 0.0
	radio_echo = {}
	if radio_open:
		for e in echoes:
			if e.get("locked", false):
				continue
			var near := 1.0
			if e.radius > 0.0:
				near = clampf(1.2 - player_pos.distance_to(e.pos) / e.radius, 0.0, 1.0) if not aboard else clampf(1.2 - Vector2(train_x, 0).distance_to(e.pos) / e.radius, 0.0, 1.0)
			var tune := clampf(1.0 - absf(radio_freq - e.freq) / 0.8, 0.0, 1.0)
			var s := near * tune
			if s > radio_signal:
				radio_signal = s
				radio_echo = e
		if radio_signal > 0.85 and not radio_echo.is_empty():
			decode_t += delta
			if decode_t > 1.5 and not radio_echo.done:
				radio_echo.done = true
				say("Эхо записано в дневник.")
				_vibrate(60, 0.4)
				if radio_echo.radius < 0.0:
					finished = true
					save_game()
		else:
			decode_t = 0.0
	sfx.set_radio(radio_open, radio_signal)


## Текст эха с помехами: чем слабее сигнал, тем больше символов съедено.
func radio_text() -> String:
	if radio_echo.is_empty():
		return "…шшш…"
	var src: String = radio_echo.text
	var out := ""
	for i in src.length():
		var ch := src[i]
		var h := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
		out += ch if (ch == " " or h < radio_signal * 1.15 - 0.1) else "·"
	return out


func _update_objective() -> void:
	if finished:
		objective = "Конец пролога. Дочь жива — путь лежит на восток."
	elif dead:
		objective = ""
	elif generator_fixed:
		objective = "Настрой радио на 103.7"
	elif train_x < 2450.0 and player_pos.x < 2450.0:
		objective = "Доберись до станции «Пепельная» →"
	elif inv.scrap < SCRAP_FOR_GENERATOR:
		objective = "Найди хлам для генератора: %d / %d" % [inv.scrap, SCRAP_FOR_GENERATOR]
	else:
		objective = "Почини генератор у станции"


func _update_visuals(delta: float) -> void:
	hurt_flash = maxf(0.0, hurt_flash - delta * 2.0)
	train_node.position = Vector2(train_x, RAIL_Y + 14)
	if aboard:
		player_pos = door_pos() + Vector2(0, 4)
	player_node.visible = not aboard
	player_node.position = player_pos
	var moving: bool = (ctl.move as Vector2).length() > 0.2 and not aboard
	player_sprite.texture = player_frames[int(time * 6.0) % 2] if moving else player_frames[0]
	player_sprite.flip_h = facing.x < 0.0
	flash_light.enabled = flashlight_active()
	flash_light.rotation = facing.angle()
	flash_light.energy = 0.85 * clampf(stats.battery / 15.0, 0.35, 1.0)
	torch_light.enabled = torch_left > 0.0 and not aboard
	torch_light.energy = 1.0 + 0.15 * sin(time * 17.0) + 0.1 * sin(time * 7.3)
	fire_light.energy = 1.1 + 0.15 * sin(time * 13.0) + 0.1 * sin(time * 5.1)
	var focus := Vector2(train_x + train_v * 0.6, RAIL_Y) if aboard else player_pos
	cam.position = focus
	var vs := get_viewport_rect().size / cam.zoom
	for fr in fog_layers:
		fr.position = -vs * 0.5 - Vector2(8, 8)
		fr.size = vs + Vector2(16, 16)
