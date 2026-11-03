## RE-RAIL: Хроники Пепла.
##
## Илья едет на бронедрезине сквозь ядовитый туман на восток, к дочери.
## Четыре главы (data/chapters.json): в каждой — своя станция, своя цель, люди и звери.
## Диалоги — data/dialogs.json, крафт и улучшения — data/crafting.json.
##
## Управление пишет в `ctl` (сенсорный HUD или автоигрок) — вся логика здесь.
extends Node2D

const Art := preload("res://scripts/pixel_art.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Hud := preload("res://scripts/hud.gd")
const Menu := preload("res://scripts/menu.gd")
const Interior := preload("res://scripts/interior.gd")
const Music := preload("res://scripts/music.gd")
const GroundShader := preload("res://shaders/ground.gdshader")
const FogShader := preload("res://shaders/fog.gdshader")

const SAVE_PATH := "user://save.json"
const BOT_SAVE_PATH := "user://save_autoplay.json"
const SAVE_VERSION := 2
const AUTOSAVE_EVERY := 45.0

## Что делать при (пере)загрузке сцены: "menu", "new" или "continue".
static var boot_action := "menu"
static var _card_after_boot := false

const RAIL_Y := 0.0
const TRAIN_MAX := 115.0
const TRAIN_ACCEL := 55.0
const WALK := 62.0
const FLASH_RANGE := 175.0
const FLASH_HALF_ANGLE := 24.0
const TORCH_TIME := 60.0
const COAL_CAPS := [60.0, 100.0, 150.0]

const ITEMS := ["ammo", "medkit", "weapon", "torch", "cans", "grenade"]
const ITEM_NAMES := {"ammo": "Патроны", "medkit": "Аптечка", "weapon": "Оружие", "torch": "Факел",
	"cans": "Консервы", "grenade": "Граната", "scrap": "Хлам", "coal": "Уголь", "cloth": "Ткань",
	"chem": "Химия", "battery": "Батарея", "shotgun": "Обрез", "train_hp": "Обшивка", "charm": "Оберег", "crowbar": "Лом"}

## Виды врагов. fear — боится ли луча фонаря.
const MOBS := {
	"rustling": {"hp": 3.0, "speed": 34.0, "dmg": 12.0, "burn": 1.6, "fear": true, "group": 1},
	"packer": {"hp": 1.2, "speed": 60.0, "dmg": 6.0, "burn": 3.0, "fear": true, "group": 3},
	"crawler": {"hp": 8.0, "speed": 20.0, "dmg": 22.0, "burn": 0.4, "fear": false, "group": 1},
}

var sfx: Node
var hud: CanvasLayer
var menu: CanvasLayer
var interior: CanvasLayer
var music: Node
var autoplay := false
var state := "menu" # "menu" — главное меню на фоне мира, "play" — игра
var paused := false
var vibration := true
var autosave_t := 0.0

# --- данные
var chapters: Array = []
var dialogs: Dictionary = {}
var crafting: Dictionary = {}
var chapter_i := 0
var chapter: Dictionary = {}
var world := Rect2(0, -330, 3400, 660)

# --- управление (пишут HUD или автоигрок)
var ctl := {"move": Vector2.ZERO, "aim": Vector2.RIGHT, "aiming": false, "search": false}

# --- Илья и общий прогресс (переносится между главами)
var stats := {"health": 100.0, "hunger": 80.0, "warmth": 70.0, "sanity": 90.0, "battery": 100.0}
var inv := {"ammo": 6, "medkit": 1, "crowbar": 1, "torch": 2, "cans": 2, "grenade": 1, "shotgun": 0,
	"scrap": 0, "coal": 40.0, "cloth": 1, "chem": 0, "charm": 0}
var upgrades := {"engine": 0, "armor": 0, "lamp": 0, "stove": 0, "bunker": 0, "turret": 0}
var flags := {}
var karma := 0
var weapon := "crowbar"
var dog_joined := false
var train_hp := 100.0

# --- состояние в главе
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
var train_x := 220.0
var train_v := 0.0
var turret_cd := 0.0
var goal_done := false
var finished := false
var ending := ""
var objective := ""
var messages: Array[Dictionary] = []
var time := 0.0
var spawn_t := 5.0

# --- объекты главы
var piles: Array[Dictionary] = []
var monsters: Array[Dictionary] = []
var obstacles: Array[Rect2] = []
var echoes: Array[Dictionary] = []
var npcs: Array[Dictionary] = []
var fireflies: Array[Vector2] = []
var fires: Array[Vector2] = []
var grenades: Array[Dictionary] = []
var safe := {}
var goal := {}
var dog := {}

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
var train_lamp: PointLight2D
var headlights: Array[PointLight2D] = []
var player_node: Node2D
var player_sprite: Sprite2D
var player_frames: Array[Texture2D] = []
var flash_light: PointLight2D
var torch_light: PointLight2D
var goal_lights: Array[PointLight2D] = []
var fire_lights: Array[PointLight2D] = []
var fog_layers: Array[ColorRect] = []
var mob_frames := {}
var dog_frames: Array[Texture2D] = []
var noise_tex: NoiseTexture2D
var flash_burst: PointLight2D


func _ready() -> void:
	autoplay = OS.get_cmdline_user_args().has("--autoplay")
	if autoplay and boot_action == "menu":
		boot_action = "continue" if OS.get_cmdline_user_args().has("--continue") else "new"
	randomize()
	_load_data()
	var save := _read_save() if boot_action == "continue" else {}
	chapter_i = clampi(int(save.get("chapter", 0)), 0, chapters.size() - 1)
	chapter = chapters[chapter_i]
	sfx = Sfx.new()
	add_child(sfx)
	music = Music.new()
	add_child(music)
	_build_world()
	interior = Interior.new()
	interior.game = self
	add_child(interior)
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
			_chapter_card()
			save_game()
		"continue":
			_start_play()
			if not load_game(save):
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


func _load_data() -> void:
	chapters = _json("res://data/chapters.json")
	dialogs = _json("res://data/dialogs.json")
	crafting = _json("res://data/crafting.json")


func _json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Нет файла " + path)
		return null
	return JSON.parse_string(f.get_as_text())


static func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _c(a: Array) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]))


# ============================================================ мир главы

func _build_world() -> void:
	var biome: Dictionary = chapter.biome
	world = Rect2(0, -330, float(chapter.length), 660)
	var cm := CanvasModulate.new()
	cm.color = _c(biome.ambient)
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
	ground.position = world.position - Vector2(200, 200)
	ground.size = world.size + Vector2(400, 400)
	var gm := ShaderMaterial.new()
	gm.shader = GroundShader
	gm.set_shader_parameter("noise", noise_tex)
	gm.set_shader_parameter("rail_y", RAIL_Y)
	gm.set_shader_parameter("grass_a", _c(biome.grass[0]))
	gm.set_shader_parameter("grass_b", _c(biome.grass[1]))
	gm.set_shader_parameter("dirt_a", _c(biome.dirt[0]))
	gm.set_shader_parameter("dirt_b", _c(biome.dirt[1]))
	ground.material = gm
	ground.z_index = -10
	add_child(ground)

	ents = Node2D.new()
	ents.y_sort_enabled = true
	add_child(ents)

	_build_train()
	_build_player()
	for kind in MOBS:
		var frames := []
		for f in 2:
			match kind:
				"rustling":
					frames.append(Art.rustling(f))
				"packer":
					frames.append(Art.packer(f))
				"crawler":
					frames.append(Art.crawler(f))
		mob_frames[kind] = frames
	dog_frames = [Art.dog(0), Art.dog(1)]

	for i in chapter.wrecks.size():
		_add_wreck(_v(chapter.wrecks[i]), 3 + i + chapter_i * 10)

	# станция
	var st_data: Dictionary = chapter.station
	var st := Sprite2D.new()
	st.texture = Art.station()
	st.offset = Vector2(0, -48)
	st.position = _v(st_data.p)
	ents.add_child(st)
	obstacles.append(Rect2(st.position.x - 70, st.position.y - 36, 140, 36))
	var sign := Label.new()
	sign.text = st_data.name
	sign.add_theme_font_size_override("font_size", 8)
	sign.add_theme_color_override("font_color", Color(0.12, 0.14, 0.16))
	sign.position = Vector2(-58, -59)
	sign.size = Vector2(116, 12)
	sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.add_child(sign)

	# цель главы
	var gd: Dictionary = chapter.goal
	goal = {"kind": gd.kind, "pos": _v(gd.p), "cost": gd.cost, "label": gd.label}
	var gnode := Node2D.new()
	gnode.position = goal.pos
	ents.add_child(gnode)
	var gt := Art.goal(goal.kind, false)
	var gbody := Sprite2D.new()
	gbody.texture = gt[0]
	gbody.offset = Vector2(0, -gt[0].get_height() * 0.5)
	gnode.add_child(gbody)
	var gglow := _glow_sprite(gt[1], gbody.offset)
	gnode.add_child(gglow)
	goal.body = gbody
	goal.glow = gglow
	obstacles.append(Rect2(goal.pos.x - 10, goal.pos.y - 8, 20, 8))
	for off in [Vector2(-100, -10), Vector2(0, 10), Vector2(-210, 20)]:
		var l := _light(Art.radial_light(256), goal.pos + off, Color(1.0, 0.85, 0.55), 1.3, 1.2)
		l.enabled = false
		add_child(l)
		goal_lights.append(l)

	for fp in chapter.fires:
		_add_fire(_v(fp))
	for pd in chapter.piles:
		_add_pile(_v(pd.p), pd.loot)

	if chapter.has("safe"):
		var sd: Dictionary = chapter.safe
		var ss := Sprite2D.new()
		ss.texture = Art.safe(false)
		ss.offset = Vector2(0, -8)
		ss.position = _v(sd.p)
		ents.add_child(ss)
		safe = {"pos": ss.position, "flag": sd.flag, "loot": sd.loot, "open": false, "sprite": ss}

	for nd in chapter.npcs:
		_add_npc(nd)

	# светлячки — добрые огоньки, рядом с ними спокойнее
	for fp in chapter.fireflies:
		var p := _v(fp)
		fireflies.append(p)
		var sw := CPUParticles2D.new()
		sw.position = p
		sw.amount = 14
		sw.lifetime = 3.0
		sw.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		sw.emission_sphere_radius = 26.0
		sw.gravity = Vector2.ZERO
		sw.initial_velocity_min = 2
		sw.initial_velocity_max = 8
		sw.spread = 180
		sw.color = Color(0.8, 1.0, 0.45)
		sw.material = _unshaded()
		sw.z_index = 5
		add_child(sw)
		add_child(_light(Art.radial_light(128), p, Color(0.75, 1.0, 0.5), 0.6, 0.7))

	# декор: трава / угольные кучи, грибы
	var rng := RandomNumberGenerator.new()
	rng.seed = 42 + chapter_i
	var snowy: bool = biome.get("snow", false)
	for i in 70:
		var p := Vector2(rng.randf_range(40, world.end.x - 40), rng.randf_range(-300, 300))
		if absf(p.y - RAIL_Y) < 30.0:
			continue
		var tuft := Sprite2D.new()
		tuft.texture = Art.coal_heap(i) if chapter.id == "coal_mine" else Art.grass_tuft(i)
		tuft.offset = Vector2(0, -3)
		tuft.position = p
		if snowy:
			tuft.modulate = Color(0.75, 0.8, 0.85)
		ents.add_child(tuft)
	if not snowy:
		for i in 16:
			var p := Vector2(rng.randf_range(100, world.end.x - 100), rng.randf_range(-280, 280))
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

	for ed in chapter.echoes:
		echoes.append({"pos": _v(ed.p), "freq": float(ed.freq), "radius": float(ed.r), "text": ed.text,
			"flag": ed.get("flag", ""), "done": false, "locked": false})
	if chapter.daughter.has("freq"):
		echoes.append({"pos": Vector2.ZERO, "freq": float(chapter.daughter.freq), "radius": -1.0,
			"text": chapter.daughter.text, "flag": "daughter_%d" % chapter_i, "done": false, "locked": true})

	cam = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 5.0
	cam.zoom = Vector2(2, 2)
	cam.limit_left = int(world.position.x)
	cam.limit_right = int(world.end.x)
	cam.limit_top = int(world.position.y)
	cam.limit_bottom = int(world.end.y)
	add_child(cam)
	var base_fog := Shader.new()
	base_fog.code = FogShader.code.replace("render_mode blend_mix;", "render_mode blend_mix, unshaded;")
	var lit_fog := Shader.new()
	lit_fog.code = FogShader.code.replace("render_mode blend_mix;", "render_mode blend_add;")
	for cfg in [[base_fog, 0.3, _c(biome.fog), 6.0], [lit_fog, 0.32, _c(biome.fog_lit), 9.0]]:
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
	var air := CPUParticles2D.new()
	air.amount = 60 if snowy else 40
	air.lifetime = 6.0
	air.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	air.emission_rect_extents = Vector2(180, 110)
	air.direction = Vector2(-0.4, 1) if snowy else Vector2(0.3, -1)
	air.spread = 25 if snowy else 40
	air.gravity = Vector2(-6, 10) if snowy else Vector2(4, -3)
	air.initial_velocity_min = 6 if snowy else 3
	air.initial_velocity_max = 16 if snowy else 10
	air.scale_amount_min = 1
	air.scale_amount_max = 1.5
	air.color = Color(0.95, 0.97, 1.0, 0.9) if snowy else Color(1.0, 0.55, 0.2, 0.85)
	air.material = _unshaded()
	air.z_index = 41
	cam.add_child(air)

	flash_burst = _light(Art.radial_light(256), Vector2.ZERO, Color(1.0, 0.95, 0.8), 0.0, 1.4)
	add_child(flash_burst)


func _add_fire(p: Vector2) -> void:
	fires.append(p)
	var fire := Node2D.new()
	fire.position = p
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
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.5, 1))
	g.set_color(1, Color(0.8, 0.2, 0.05, 0))
	flame.color_ramp = g
	flame.material = _unshaded()
	fire.add_child(flame)
	var l := _light(Art.radial_light(256), p + Vector2(0, -10), Color(1.0, 0.6, 0.3), 1.2, 0.9)
	add_child(l)
	fire_lights.append(l)


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
	train_lamp = _light(Art.radial_light(256), Vector2(-8, -6), Color(1.0, 0.62, 0.3), 1.15, 0.85)
	train_node.add_child(train_lamp)
	var cone := Art.cone_light(256, 20.0)
	for hy in [-18.0, -10.0]:
		var hl := _light(cone, Vector2(40, hy), Color(1.0, 0.93, 0.75), 0.65, 1.6)
		train_node.add_child(hl)
		headlights.append(hl)


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


func _add_npc(nd: Dictionary) -> void:
	var node := Node2D.new()
	node.position = _v(nd.p)
	ents.add_child(node)
	var spr := Sprite2D.new()
	if nd.look == "dog":
		spr.texture = dog_frames[0]
		spr.offset = Vector2(0, -6)
		var chain := Line2D.new()
		chain.points = PackedVector2Array([Vector2(-6, -2), Vector2(-22, 2)])
		chain.width = 1.0
		chain.default_color = Color(0.5, 0.5, 0.5)
		node.add_child(chain)
		dog = {"node": node, "sprite": spr, "pos": node.position, "chain": chain, "bark_t": 0.0, "sniff_t": 10.0, "anim": 0.0}
	else:
		spr.texture = Art.survivor(nd.look)
		spr.offset = Vector2(0, -11)
	node.add_child(spr)
	var hidden: bool = nd.get("hidden", false)
	node.visible = not hidden
	npcs.append({"id": nd.id, "pos": node.position, "node": node, "dialog": nd.dialog, "done": false, "hidden": hidden})


## Пепел едет с Ильёй и в следующие главы: создаём его рядом с дрезиной.
func _spawn_companion_dog() -> void:
	_add_npc({"id": "dog", "p": [train_x + 14, RAIL_Y + 26], "look": "dog", "dialog": "dog"})
	npcs[npcs.size() - 1].done = true


# ============================================================ API для HUD, меню и автоигрока

func say(text: String) -> void:
	messages.append({"text": text, "t": time})
	while messages.size() > 3:
		messages.pop_front()


func train_rect() -> Rect2:
	return Rect2(train_x - 42, RAIL_Y - 30, 84, 38)


func door_pos() -> Vector2:
	return Vector2(train_x + 14, RAIL_Y + 22)


func coal_cap() -> float:
	return COAL_CAPS[clampi(upgrades.bunker, 0, 2)]


func item_count(id: String) -> int:
	if id == "weapon":
		return inv.ammo if weapon == "shotgun" else 1
	return int(inv.get(id, 0))


func item_name(id: String) -> String:
	if id == "weapon":
		return "Обрез" if weapon == "shotgun" else "Лом"
	return ITEM_NAMES.get(id, id)


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


func nearest_npc() -> Dictionary:
	for n in npcs:
		if n.hidden or (n.id == "dog" and dog_joined):
			continue
		if player_pos.distance_to(n.pos) < 28.0:
			return n
	return {}


func npc(id: String) -> Dictionary:
	for n in npcs:
		if n.id == id:
			return n
	return {}


## Контекстная кнопка: что сейчас можно сделать рукой.
func context() -> Dictionary:
	if dead or finished:
		return {"kind": "none", "label": ""}
	if aboard:
		return {"kind": "exit", "label": "Выйти"}
	if player_pos.distance_to(door_pos()) < 30.0:
		if train_hp <= 0.0:
			return {"kind": "patch", "label": "Латать"}
		return {"kind": "board", "label": "Сесть"}
	var n := nearest_npc()
	if not n.is_empty():
		return {"kind": "talk", "label": "Говорить", "npc": n.id}
	if not goal_done and player_pos.distance_to(goal.pos + Vector2(0, 12)) < 36.0:
		return {"kind": "goal", "label": "Чинить"}
	if not safe.is_empty() and not safe.open and player_pos.distance_to(safe.pos) < 26.0:
		return {"kind": "safe", "label": "Сейф"}
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
		"patch":
			if inv.scrap >= 2:
				inv.scrap -= 2
				train_hp = 50.0
				sfx.play("clank", -4.0)
				say("Пробоины залатаны.")
			else:
				say("Нужно 2 хлама, чтобы залатать дрезину.")
		"talk":
			menu.dialog(c.npc)
		"goal":
			_do_goal()
		"safe":
			_open_safe()


func toggle_flashlight() -> void:
	if aboard or dead:
		return
	flashlight_on = not flashlight_on
	sfx.play("click", -6.0)


func attack() -> void:
	if aboard or dead or attack_cd > 0.0:
		return
	if weapon == "shotgun" and inv.ammo > 0:
		_shoot()
		return
	attack_cd = 0.5
	sfx.play("swing", -4.0)
	var hit := false
	for m in monsters:
		var to: Vector2 = m.pos - player_pos
		if to.length() < 30.0 and to.normalized().dot(facing) > 0.2:
			m.hp -= 1.5
			m.pos += to.normalized() * (14.0 if m.kind == "crawler" else 30.0)
			hit = true
	if hit:
		sfx.play("hit", 0.0)
		_vibrate(30, 0.6)


func _shoot() -> void:
	attack_cd = 0.9
	inv.ammo -= 1
	sfx.play("shot", 2.0)
	_vibrate(70, 1.0)
	flash_burst.position = player_pos + facing * 14.0
	flash_burst.energy = 1.6
	spawn_t -= 2.0 # выстрел слышно далеко
	for m in monsters:
		var to: Vector2 = m.pos - player_pos
		var d := to.length()
		if d < 150.0 and rad_to_deg(absf(facing.angle_to(to))) < 18.0:
			m.hp -= 3.0 * clampf(1.3 - d / 150.0, 0.4, 1.0)
			m.pos += to.normalized() * 30.0
	if inv.ammo <= 0:
		say("Патроны кончились — снова лом.")
		weapon = "crowbar"


func use_item(id: String) -> void:
	if dead:
		return
	match id:
		"ammo":
			say("Патронов: %d. %s" % [inv.ammo, "Обрез заряжен." if inv.shotgun > 0 else "Обрез собирается на верстаке."])
		"medkit":
			if inv.medkit > 0 and stats.health < 100.0:
				inv.medkit -= 1
				stats.health = minf(100.0, stats.health + 45.0)
				sfx.play("chime", -8.0, 0.8)
				say("Аптечка: +45 здоровья.")
		"weapon":
			if inv.shotgun > 0:
				weapon = "crowbar" if weapon == "shotgun" else "shotgun"
				sfx.play("click", -4.0)
				say("В руках: " + item_name("weapon"))
			else:
				say("Лом в руке. Обрез можно собрать на верстаке.")
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
		"grenade":
			if inv.grenade > 0 and not aboard:
				inv.grenade -= 1
				grenades.append({"pos": player_pos + Vector2(0, -8), "vel": facing * 140.0, "t": 0.0})
				sfx.play("swing", -6.0, 0.7)


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


# --- ресурсы: стоимость и награды

func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if float(inv.get(k, 0)) < float(cost[k]) - 0.001:
			return false
	return true


func pay(cost: Dictionary) -> void:
	for k in cost:
		if k == "coal":
			inv.coal -= float(cost[k])
		else:
			inv[k] = int(inv[k]) - int(cost[k])


func give(loot: Dictionary) -> String:
	var parts: Array[String] = []
	for k in loot:
		var v = loot[k]
		match k:
			"coal":
				var before: float = inv.coal
				inv.coal = minf(coal_cap(), inv.coal + float(v))
				parts.append("уголь +%d" % int(inv.coal - before))
			"battery":
				stats.battery = minf(100.0, stats.battery + float(v))
				parts.append("батарея")
			"train_hp":
				train_hp = minf(100.0, train_hp + float(v))
				parts.append("обшивка +%d" % int(v))
			"shotgun":
				inv.shotgun = 1
				weapon = "shotgun"
				parts.append("обрез")
			"charm":
				inv.charm = 1
				parts.append("оберег")
			_:
				inv[k] = int(inv.get(k, 0)) + int(v)
				parts.append("%s ×%d" % [ITEM_NAMES.get(k, k).to_lower(), int(v)])
	return ", ".join(parts)


static func cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for k in cost:
		parts.append("%s %d" % [ITEM_NAMES.get(k, k).to_lower(), int(cost[k])])
	return ", ".join(parts)


# --- верстак

func recipe(id: String) -> Dictionary:
	for r in crafting.recipes:
		if r.id == id:
			return r
	return {}


func can_craft(r: Dictionary) -> bool:
	if r.id == "shotgun" and inv.shotgun > 0:
		return false
	if r.id == "patch" and train_hp >= 100.0:
		return false
	return can_afford(r.cost)


func craft(id: String) -> bool:
	var r := recipe(id)
	if r.is_empty() or not can_craft(r):
		return false
	pay(r.cost)
	var got := give(r.give)
	sfx.play("chime", -6.0)
	say("Собрано: " + got)
	return true


func upgrade_info(id: String) -> Dictionary:
	for u in crafting.upgrades:
		if u.id == id:
			return u
	return {}


func next_upgrade_cost(id: String) -> Dictionary:
	var u := upgrade_info(id)
	var lvl: int = upgrades[id]
	if u.is_empty() or lvl >= u.levels.size():
		return {}
	return u.levels[lvl]


func can_upgrade(id: String) -> bool:
	var u := upgrade_info(id)
	if u.has("need_flag") and not flags.has(u.need_flag):
		return false
	var c := next_upgrade_cost(id)
	return not c.is_empty() and can_afford(c)


func do_upgrade(id: String) -> bool:
	if not can_upgrade(id):
		return false
	pay(next_upgrade_cost(id))
	upgrades[id] += 1
	sfx.play("clank", -2.0, 1.2)
	sfx.play("chime", -8.0)
	say("Дрезина: %s — уровень %d" % [upgrade_info(id).name, upgrades[id]])
	_apply_upgrade_visuals()
	save_game()
	return true


func _apply_upgrade_visuals() -> void:
	for hl in headlights:
		hl.energy = 0.65 + 0.2 * upgrades.lamp
		hl.texture_scale = 1.6 + 0.35 * upgrades.lamp
	train_lamp.texture_scale = 0.85 * (1.0 + 0.4 * upgrades.lamp)


# --- диалоги

func dialog_choose(npc_id: String, choice: Dictionary) -> void:
	if choice.has("cost"):
		pay(choice.cost)
	var got := ""
	if choice.has("give"):
		got = give(choice.give)
	karma += int(choice.get("karma", 0))
	if choice.has("flag"):
		flags[choice.flag] = true
	if int(choice.get("karma", 0)) > 0:
		sfx.play("chime", -8.0)
	if choice.get("done", false):
		var n := npc(npc_id)
		if not n.is_empty():
			n.done = true
	if got != "":
		say("Получено: " + got)
	match choice.get("action", ""):
		"dog_join":
			_dog_join()
		"ending":
			_ending()


func choice_allowed(choice: Dictionary) -> bool:
	if choice.has("cost") and not can_afford(choice.cost):
		return false
	if choice.has("need_karma") and karma < int(choice.need_karma):
		return false
	return true


func _dog_join() -> void:
	dog_joined = true
	if not dog.is_empty():
		dog.chain.visible = false
	sfx.play("bark", 0.0)
	say("Пепел теперь с тобой.")


# ============================================================ действия

func _exit_train() -> void:
	if absf(train_v) > 12.0:
		say("Слишком быстро — сначала притормози.")
		return
	aboard = false
	train_v = 0.0
	player_pos = door_pos() + Vector2(0, 4)
	facing = Vector2.DOWN
	if dog_joined and not dog.is_empty():
		dog.pos = player_pos + Vector2(-14, 4)
	sfx.play("clank", -12.0, 0.7)


func _board_train() -> void:
	aboard = true
	ctl.search = false
	sfx.play("clank", -12.0, 0.8)


func _do_goal() -> void:
	if not can_afford(goal.cost):
		say("Нужно: %s." % cost_text(goal.cost))
		return
	pay(goal.cost)
	_complete_goal()
	sfx.play("clank", 0.0, 0.9)
	_vibrate(200, 1.0)
	say(chapter.goal.done)
	if not chapter.daughter.is_empty():
		say("Радио затрещало… поймай частоту %.1f" % float(chapter.daughter.freq))
	else:
		say(chapter.goal.after)
	save_game()


func _complete_goal() -> void:
	goal_done = true
	var g := Art.goal(goal.kind, true)
	goal.body.texture = g[0]
	goal.glow.texture = g[1]
	for l in goal_lights:
		l.enabled = true
	for e in echoes:
		if e.radius < 0.0:
			e.locked = false
	var anya := npc("anya")
	if not anya.is_empty():
		anya.hidden = false
		anya.node.visible = true


func _open_safe() -> void:
	if not flags.has(safe.flag):
		say("Кодовый замок. Может, кто-то говорил код по радио?")
		sfx.play("click", -4.0)
		return
	safe.open = true
	safe.sprite.texture = Art.safe(true)
	sfx.play("clank", -4.0, 1.3)
	say("Код подошёл! " + give(safe.loot))


func _loot(p: Dictionary) -> void:
	p.looted = true
	p.sprite.texture = Art.scrap_pile(int(p.pos.x), true)
	sfx.play("pickup", -2.0)
	_vibrate(40, 0.5)
	say("Найдено: " + give(p.loot))


func _vibrate(ms: int, amp: float) -> void:
	if vibration and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, amp)


func _ending() -> void:
	finished = true
	if karma >= 2:
		ending = "good"
	elif karma >= 0:
		ending = "neutral"
	else:
		ending = "bad"
	save_game()
	menu.ending_card()


func _chapter_card() -> void:
	menu.chapter_card()


## Конец главы: дрезина дошла до края перегона после выполненной цели.
func _advance_chapter() -> void:
	if chapter_i >= chapters.size() - 1:
		return
	chapter_i += 1
	save_game(true)
	boot("continue_card")


# ============================================================ меню, пауза, сохранения

func boot(action: String) -> void:
	boot_action = "continue" if action == "continue_card" else action
	_card_after_boot = action == "continue_card"
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


func _save_path() -> String:
	return BOT_SAVE_PATH if autoplay else SAVE_PATH


func has_save() -> bool:
	return FileAccess.file_exists(_save_path())


func save_summary() -> String:
	var d := _read_save()
	if d.is_empty():
		return ""
	var ci := clampi(int(d.get("chapter", 0)), 0, chapters.size() - 1)
	var mins := int(float(d.get("time", 0.0)) / 60.0)
	return "%s · %d мин в пути" % [chapters[ci].name, mins]


func wipe_save() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path()))


## fresh = true — сохранить только общий прогресс (новая глава начнётся с начала).
func save_game(fresh: bool = false) -> void:
	if state != "play":
		return
	var d := {
		"version": SAVE_VERSION, "time": time, "chapter": chapter_i,
		"stats": stats, "inv": inv, "upgrades": upgrades, "flags": flags, "karma": karma,
		"weapon": weapon, "dog": dog_joined, "train_hp": train_hp, "finished": finished, "ending": ending,
	}
	if not fresh:
		var looted := []
		for p in piles:
			looted.append(p.looted)
		var heard := []
		for e in echoes:
			heard.append(e.done)
		var talked := []
		for n in npcs:
			talked.append(n.done)
		d.merge({
			"in_chapter": true,
			"aboard": aboard, "player": [player_pos.x, player_pos.y], "train_x": train_x,
			"flashlight_on": flashlight_on, "torch_left": torch_left,
			"looted": looted, "echoes": heard, "npcs": talked,
			"goal_done": goal_done, "safe_open": safe.get("open", false),
		})
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


func _read_save() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(_save_path(), FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func load_game(d: Dictionary) -> bool:
	if d.is_empty() or int(d.get("version", 0)) != SAVE_VERSION:
		return false
	time = float(d.time)
	for k in stats:
		stats[k] = float(d.stats.get(k, stats[k]))
	for k in inv:
		inv[k] = float(d.inv.get(k, inv[k])) if k == "coal" else int(d.inv.get(k, inv[k]))
	for k in upgrades:
		upgrades[k] = int(d.upgrades.get(k, 0))
	flags = d.get("flags", {})
	karma = int(d.get("karma", 0))
	weapon = d.get("weapon", "crowbar")
	train_hp = float(d.get("train_hp", 100.0))
	finished = bool(d.get("finished", false))
	ending = d.get("ending", "")
	if d.get("dog", false):
		dog_joined = true
		if dog.is_empty():
			_spawn_companion_dog()
		dog.chain.visible = false
	_apply_upgrade_visuals()
	if d.get("in_chapter", false):
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
		for i in mini(npcs.size(), d.npcs.size()):
			npcs[i].done = bool(d.npcs[i])
		if d.goal_done:
			_complete_goal()
		if d.get("safe_open", false) and not safe.is_empty():
			safe.open = true
			safe.sprite.texture = Art.safe(true)
		if not finished:
			say("Продолжаем путь.")
	elif _card_after_boot:
		_card_after_boot = false
		_chapter_card()
	if finished:
		menu.ending_card()
	return true


# ============================================================ цикл

func _process(delta: float) -> void:
	if state == "menu":
		# главное меню: мир живёт, камера медленно плывёт вдоль путей
		time += delta
		ctl.move = Vector2.ZERO
		train_x = 220.0
		_update_visuals(delta)
		cam.position = Vector2(300.0 + fmod(time * 14.0, world.size.x - 800.0), RAIL_Y - 10.0)
		music.mix(0.75, 0.0, 0.0)
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
		_update_dog(delta)
		_update_turret(delta)
		_update_grenades(delta)
	_update_radio(delta)
	_update_objective()
	_update_visuals(delta)
	_update_music()
	if goal_done and aboard and train_x >= world.end.x - 90.0 and chapter_i < chapters.size() - 1:
		_advance_chapter()


func _update_train(delta: float) -> void:
	var throttle := 0.0
	if aboard and not interior.open:
		throttle = clampf(ctl.move.x, -1.0, 1.0)
		if absf(throttle) < 0.2:
			throttle = 0.0
	var vmax: float = TRAIN_MAX * (1.0 + 0.2 * upgrades.engine)
	if train_hp <= 0.0:
		throttle = 0.0
	if throttle != 0.0 and inv.coal > 0.0:
		train_v = move_toward(train_v, throttle * vmax, TRAIN_ACCEL * delta)
		inv.coal = maxf(0.0, inv.coal - absf(throttle) * 0.75 * (1.0 - 0.2 * upgrades.engine) * delta)
		if inv.coal <= 0.0:
			say("Уголь кончился!")
	else:
		train_v = move_toward(train_v, 0.0, TRAIN_ACCEL * 0.8 * delta)
	# дальше цели главы не проехать, пока она не выполнена: путь закрыт
	var limit: float = world.end.x - 70.0 if goal_done else goal.pos.x + 40.0
	var nx := clampf(train_x + train_v * delta, 70.0, limit)
	if nx >= limit and train_v > 1.0 and not goal_done and not flags.has("_blocked_msg_%d" % chapter_i):
		flags["_blocked_msg_%d" % chapter_i] = true
		say("Путь закрыт — сначала: " + String(chapter.goal.label).to_lower())
	if nx <= 70.0 or nx >= limit:
		train_v = 0.0
	train_x = nx
	sfx.set_engine(absf(train_v) / vmax, aboard)


func _update_player(delta: float) -> void:
	attack_cd -= delta
	var mv: Vector2 = ctl.move
	if mv.length() > 1.0:
		mv = mv.normalized()
	var slow := 0.6 if stats.sanity <= 0.0 else 1.0
	_move_player(mv * WALK * slow * delta)
	if ctl.aiming:
		facing = (ctl.aim as Vector2).normalized()
	elif mv.length() > 0.2:
		facing = mv.normalized()
	if mv.length() > 0.2:
		step_t += delta * mv.length()
		if step_t > 0.32:
			step_t = 0.0
			sfx.play("step", -14.0)
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
	player_pos = player_pos.clamp(world.position + Vector2(10, 20), world.end - Vector2(10, 10))


## Насколько точка защищена светом (0..1). Пустая дрезина светит слабее.
func safety(p: Vector2) -> float:
	var s := 0.0
	var lamp_r: float = (95.0 if aboard else 42.0) * (1.0 + 0.4 * upgrades.lamp)
	s = maxf(s, 1.0 - p.distance_to(Vector2(train_x - 8, RAIL_Y - 6)) / lamp_r)
	for f in fires:
		s = maxf(s, 1.0 - p.distance_to(f) / 80.0)
	if goal_done:
		s = maxf(s, 1.0 - p.distance_to(goal.pos + Vector2(-80, 0)) / 220.0)
	if torch_left > 0.0 and not aboard:
		s = maxf(s, (1.0 - p.distance_to(player_pos) / 80.0) * 0.9)
	return clampf(s * 2.0, 0.0, 1.0)


func _update_survival(delta: float) -> void:
	var cold: float = chapter.biome.get("cold", 1.0)
	stats.hunger = maxf(0.0, stats.hunger - 0.28 * delta)
	var lit := 1.0 if aboard else safety(player_pos)
	var near_fire := false
	for f in fires:
		if player_pos.distance_to(f) < 60.0:
			near_fire = true
	var warm := aboard or near_fire or torch_left > 0.0
	var warm_rate: float = 3.5 * (2.0 if aboard and upgrades.stove > 0 else 1.0)
	stats.warmth = clampf(stats.warmth + (warm_rate if warm else -0.65 * cold) * delta, 0.0, 100.0)
	var near_flies := false
	for ff in fireflies:
		if player_pos.distance_to(ff) < 60.0 and not aboard:
			near_flies = true
	if lit > 0.4 or near_flies:
		var regen: float = 4.0 * (2.0 if aboard and upgrades.stove > 0 else 1.0)
		stats.sanity = minf(100.0, stats.sanity + regen * delta)
	else:
		var drain: float = 1.4 * (0.5 if flashlight_active() else 1.0) * (0.75 if inv.charm > 0 else 1.0)
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
	var train_c := Vector2(train_x, RAIL_Y)
	if not aboard and not finished:
		spawn_t -= delta
		if spawn_t <= 0.0:
			var sp: Array = chapter.spawn
			spawn_t = randf_range(float(sp[0]), float(sp[1])) * (0.6 if stats.sanity < 30.0 else 1.0)
			if monsters.size() < int(chapter.max_mobs):
				_spawn_monster()
	for m in monsters:
		var def: Dictionary = MOBS[m.kind]
		m.hit_cd -= delta
		m.stun -= delta
		m.anim += delta
		var to_player: Vector2 = player_pos - m.pos
		var dist := to_player.length()
		var lit_by_flash := false
		if flashlight_active() and dist < FLASH_RANGE:
			lit_by_flash = rad_to_deg(absf(facing.angle_to(-to_player))) < FLASH_HALF_ANGLE
		if lit_by_flash:
			m.hp -= delta * float(def.burn)
		var speed: float = def.speed
		if aboard or finished:
			m.pos -= to_player.normalized() * 50.0 * delta
			m.fade -= delta
		elif m.stun > 0.0:
			pass
		elif (lit_by_flash and def.fear) or safety(m.pos) > 0.3:
			m.pos -= to_player.normalized() * (65.0 if lit_by_flash else 45.0) * delta
		else:
			if lit_by_flash:
				speed *= 0.5
			# пустая дрезина рядом — твари грызут обшивку
			var to_train: Vector2 = train_c - m.pos
			if dist > 160.0 and to_train.length() < 220.0:
				if to_train.length() > 48.0:
					m.pos += to_train.normalized() * speed * delta
				else:
					train_hp = maxf(0.0, train_hp - float(def.dmg) * 0.25 * (1.0 - 0.35 * upgrades.armor) * delta)
					if train_hp <= 0.0 and not flags.has("_hull_msg"):
						flags["_hull_msg"] = true
						say("Дрезину пробили! Латать: 2 хлама у двери.")
			else:
				m.pos += to_player.normalized() * speed * delta
				if dist < 12.0 and m.hit_cd <= 0.0:
					m.hit_cd = 1.2
					_damage(float(def.dmg), true)
					m.pos -= to_player.normalized() * 24.0
		m.node.position = m.pos
		var fr: Array = mob_frames[m.kind][int(m.anim * 4.0) % 2]
		m.body.texture = fr[0]
		m.eyes.texture = fr[1]
		m.body.flip_h = to_player.x < 0.0
		m.eyes.flip_h = m.body.flip_h
		var tint := Color(1.6, 1.2, 1.0, 1) if lit_by_flash else (Color(0.6, 0.6, 1.0) if m.stun > 0.0 else Color.WHITE)
		m.node.modulate = Color(tint.r, tint.g, tint.b, clampf(m.fade, 0.0, 1.0))
	for i in range(monsters.size() - 1, -1, -1):
		var m := monsters[i]
		if m.hp <= 0.0:
			inv.scrap += 1
			sfx.play("hit", -6.0, 0.6)
			say("Тварь рассыпалась. Хлам +1")
			m.node.queue_free()
			monsters.remove_at(i)
		elif m.fade <= 0.0 or m.pos.distance_to(player_pos) > 520.0:
			m.node.queue_free()
			monsters.remove_at(i)


func _pick_kind() -> String:
	var weights: Dictionary = chapter.mobs
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var r := randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return k
	return "rustling"


func _spawn_monster() -> void:
	var kind := _pick_kind()
	var def: Dictionary = MOBS[kind]
	for attempt in 8:
		var ang := randf() * TAU
		var p := player_pos + Vector2(cos(ang), sin(ang)) * randf_range(250.0, 320.0)
		if not world.grow(-20).has_point(p) or safety(p) > 0.0:
			continue
		for g in int(def.group):
			var gp := p + Vector2(randf_range(-20, 20), randf_range(-20, 20))
			var node := Node2D.new()
			var body := Sprite2D.new()
			var tex: Texture2D = mob_frames[kind][0][0]
			body.offset = Vector2(0, -tex.get_height() * 0.5)
			node.add_child(body)
			var eyes := _glow_sprite(mob_frames[kind][0][1], body.offset)
			node.add_child(eyes)
			node.position = gp
			ents.add_child(node)
			monsters.append({"kind": kind, "node": node, "body": body, "eyes": eyes, "pos": gp, "hp": float(def.hp),
				"hit_cd": 0.0, "anim": randf(), "fade": 1.0, "stun": 0.0})
		var d := p.distance_to(player_pos)
		sfx.play("growl", linear_to_db(clampf(1.2 - d / 400.0, 0.05, 1.0)), 1.4 if kind == "packer" else (0.6 if kind == "crawler" else 1.0))
		return


## Пёс Пепел: ходит рядом, лает на тьму, кусает тварей, чует хлам.
func _update_dog(delta: float) -> void:
	if dog.is_empty() or not dog_joined:
		return
	dog.node.visible = not aboard
	if aboard:
		dog.pos = door_pos()
		dog.node.position = dog.pos
		return
	dog.bark_t -= delta
	dog.sniff_t -= delta
	dog.anim += delta
	var target: Vector2 = player_pos + Vector2(-16 if facing.x >= 0.0 else 16, 6)
	var foe: Dictionary = {}
	var fd := 180.0
	for m in monsters:
		var d: float = m.pos.distance_to(dog.pos)
		if d < fd:
			fd = d
			foe = m
	if not foe.is_empty():
		if dog.bark_t <= 0.0:
			dog.bark_t = 3.5
			sfx.play("bark", -2.0)
		if fd < 90.0:
			target = foe.pos
		if fd < 16.0:
			foe.hp -= 0.9 * delta
			foe.pos += (foe.pos - dog.pos).normalized() * 30.0 * delta
	var to: Vector2 = target - dog.pos
	var moving := to.length() > 6.0
	if moving:
		dog.pos += to.normalized() * minf(to.length() * 3.0, 85.0) * delta
	dog.node.position = dog.pos
	dog.sprite.texture = dog_frames[int(dog.anim * 8.0) % 2] if moving else dog_frames[0]
	dog.sprite.flip_h = to.x < 0.0
	if dog.sniff_t <= 0.0:
		dog.sniff_t = 30.0
		if not sniffed_pile().is_empty():
			say("Пепел что-то учуял — смотри на карту.")


## Ближайшая необысканная куча — её пёс показывает на миникарте.
func sniffed_pile() -> Dictionary:
	if not dog_joined:
		return {}
	var best: Dictionary = {}
	var bd := 600.0
	for p in piles:
		if p.looted:
			continue
		var d: float = p.pos.distance_to(player_pos)
		if d < bd:
			bd = d
			best = p
	return best


## Турель на крыше дрезины: сама бьёт тварей рядом, тратит патроны.
func _update_turret(delta: float) -> void:
	if upgrades.turret <= 0:
		return
	turret_cd -= delta
	if turret_cd > 0.0 or inv.ammo <= 0:
		return
	var tc := Vector2(train_x, RAIL_Y - 20)
	for m in monsters:
		if m.pos.distance_to(tc) < 130.0:
			turret_cd = 1.2
			inv.ammo -= 1
			m.hp -= 2.0
			m.pos += (m.pos - tc).normalized() * 20.0
			sfx.play("shot", -8.0, 1.3)
			flash_burst.position = tc
			flash_burst.energy = 0.8
			return


func _update_grenades(delta: float) -> void:
	flash_burst.energy = maxf(0.0, flash_burst.energy - delta * 5.0)
	for i in range(grenades.size() - 1, -1, -1):
		var g := grenades[i]
		g.t += delta
		g.pos += g.vel * delta
		g.vel *= 0.92
		if g.t >= 0.8:
			sfx.play("bang", 2.0)
			_vibrate(120, 1.0)
			flash_burst.position = g.pos
			flash_burst.energy = 2.5
			for m in monsters:
				if m.pos.distance_to(g.pos) < 100.0:
					m.stun = 3.0
					m.hp -= 0.5
					m.pos += (m.pos - g.pos).normalized() * 25.0
			grenades.remove_at(i)


func _update_radio(delta: float) -> void:
	radio_signal = 0.0
	radio_echo = {}
	if radio_open:
		var here: Vector2 = Vector2(train_x, 0) if aboard else player_pos
		for e in echoes:
			if e.locked:
				continue
			var near := 1.0
			if e.radius > 0.0:
				near = clampf(1.35 - here.distance_to(e.pos) / e.radius, 0.0, 1.0)
			var tune := clampf(1.0 - absf(radio_freq - e.freq) / 0.8, 0.0, 1.0)
			var s := near * tune
			if s > radio_signal:
				radio_signal = s
				radio_echo = e
		if radio_signal > 0.85 and not radio_echo.is_empty():
			decode_t += delta
			if decode_t > 1.5 and not radio_echo.done:
				radio_echo.done = true
				if radio_echo.flag != "":
					flags[radio_echo.flag] = true
				var journal: Array = flags.get("journal", [])
				journal.append("%s: %s" % [String(chapter.name).get_slice(" · ", 1), radio_echo.text])
				flags["journal"] = journal
				say("Эхо записано в дневник.")
				if radio_echo.radius < 0.0:
					stats.sanity = minf(100.0, stats.sanity + 30.0)
					say("Голос Ани. Она жива. Рассудок +30")
					say(chapter.goal.after)
				_vibrate(60, 0.4)
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
	var gd: Dictionary = chapter.goal
	var anya := npc("anya")
	if finished:
		objective = "Конец. Спасибо, что доехал."
	elif dead:
		objective = ""
	elif goal_done:
		if not anya.is_empty() and not anya.hidden:
			objective = "Подойди к Ане"
		else:
			objective = "Путь открыт — в дрезину и на восток →"
	elif (train_x if aboard else player_pos.x) < goal.pos.x - 420.0:
		objective = "Доберись до: %s →" % String(chapter.station.name).capitalize()
	elif not can_afford(goal.cost):
		objective = "%s: нужно %s" % [gd.label, cost_text(goal.cost)]
	else:
		objective = gd.label


## Адаптивная музыка: дорога в пути, шкатулка в кабине, барабаны рядом с тварями.
func _update_music() -> void:
	if dead or finished:
		music.mix(0.2 if finished else 0.0, 0.6 if finished else 0.0, 0.0)
		return
	if interior.open:
		music.mix(0.0, 0.9, 0.0)
		return
	var threat := 0.0
	if not aboard:
		for m in monsters:
			threat = maxf(threat, clampf(1.2 - m.pos.distance_to(player_pos) / 220.0, 0.0, 1.0))
	var road := (0.45 + 0.4 * clampf(absf(train_v) / TRAIN_MAX, 0.0, 1.0)) if aboard else 0.28
	music.mix(road * (1.0 - 0.6 * threat), 0.0, threat)


func _update_visuals(delta: float) -> void:
	hurt_flash = maxf(0.0, hurt_flash - delta * 2.0)
	train_node.position = Vector2(train_x, RAIL_Y + 14)
	train_node.modulate = Color(1, 0.75, 0.7) if train_hp <= 0.0 else Color.WHITE
	train_lamp.energy = (1.15 if aboard else 0.6) * (1.0 + 0.2 * upgrades.lamp)
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
	for i in fire_lights.size():
		fire_lights[i].energy = 1.1 + 0.15 * sin(time * 13.0 + i) + 0.1 * sin(time * 5.1 + i * 2.0)
	if state == "play":
		cam.position = Vector2(train_x + train_v * 0.6, RAIL_Y) if aboard else player_pos
	var vs := get_viewport_rect().size / cam.zoom
	for fr in fog_layers:
		fr.position = -vs * 0.5 - Vector2(8, 8)
		fr.size = vs + Vector2(16, 16)
