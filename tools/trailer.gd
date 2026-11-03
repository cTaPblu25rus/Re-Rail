## Режиссёр трейлера RE-RAIL. Ставит одну сцену из настоящей игры по аргументу:
##   godot --path . --write-movie out/f.png --fixed-fps 30 -- --shot=fight --chapter=0
## Сцены: drive, radio, fight, packers, crawler, snow, interior, station,
## title (--text="…" [--big]), music (только музыкальная подложка, --len=секунды).
## Сборку всех сцен в ролик делает tools/make_trailer.sh.
extends Node

var game: Node
var shot := ""
var text := ""
var big := false
var length := 4.0
var t := 0.0
var card: CanvasLayer
var card_ui: Control
var font: Font
var fired := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.trim_prefix("--shot=")
		elif a.begins_with("--text="):
			text = a.trim_prefix("--text=").replace("|", "\n")
		elif a == "--big":
			big = true
		elif a.begins_with("--len="):
			length = float(a.trim_prefix("--len="))
	font = ThemeDB.fallback_font
	card = CanvasLayer.new()
	card.layer = 60
	card_ui = Control.new()
	card_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_ui.draw.connect(_draw_card)
	card.add_child(card_ui)
	add_child(card)
	# музыку сцен заглушаем: подложка пишется отдельно и сводится целиком
	if shot != "music":
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), -80.0)
	call_deferred("_setup")


func _setup() -> void:
	game.menu.close()
	game.spawn_t = 9999.0
	# в трейлере картинка чуть светлее, чтобы читалась на маленьком экране
	for c in game.get_children():
		if c is CanvasModulate:
			c.color = c.color * 1.35
	game.chapter.max_mobs = 0
	var g := game
	match shot:
		"drive":
			g.aboard = true
			g.train_x = 400.0
			g.train_v = 90.0
		"radio":
			g.aboard = false
			g.player_pos = Vector2(1300, -60)
			g.facing = Vector2.UP
			g.radio_open = true
			g.radio_freq = 91.0
		"fight":
			g.aboard = false
			g.player_pos = Vector2(1000, 60)
			g.train_x = 900.0
			g.inv.shotgun = 1
			g.weapon = "shotgun"
			g.inv.ammo = 8
			g.facing = Vector2.RIGHT
			g.flashlight_on = false
			g.spawn_at("rustling", Vector2(1075, 40))
			g.spawn_at("rustling", Vector2(1090, 85))
			g.spawn_at("rustling", Vector2(1060, 120))
			g.sfx.play("growl", 0.0)
		"packers":
			g.aboard = false
			g.player_pos = Vector2(1000, 70)
			g.train_x = 880.0
			g._dog_join()
			g.dog.pos = Vector2(985, 84)
			g.flashlight_on = false
			for i in 3:
				g.spawn_at("packer", Vector2(1070 + i * 12, 45 + i * 20))
			g.spawn_at("packer", Vector2(900, 150))
			g.sfx.play("growl", 0.0, 1.4)
		"crawler":
			g.aboard = false
			g.player_pos = Vector2(1000, 70)
			g.train_x = 860.0
			g.inv.shotgun = 1
			g.weapon = "shotgun"
			g.inv.ammo = 8
			g.facing = Vector2.RIGHT
			g.spawn_at("crawler", Vector2(1075, 70))
			g.sfx.play("growl", 2.0, 0.6)
		"snow":
			g.aboard = false
			g.player_pos = Vector2(900, 70)
			g.train_x = 780.0
			g.use_item("torch")
			g.spawn_at("rustling", Vector2(1080, 40))
		"interior":
			g.aboard = true
			g.train_v = 0.0
			g.upgrades.stove = 1
			g.dog_joined = true
			g.interior.enter()
		"station":
			g._complete_goal()
			g.aboard = false
			g.player_pos = Vector2(2800, -112)
			g.facing = Vector2.UP
			g.train_x = 2600.0
		"title", "music":
			g.aboard = true
			g.train_x = 400.0
	if shot == "title":
		game.sfx.play("bang", -2.0, 0.6)
		if text.begins_with("Десять"):
			game.radio_open = true
			game.radio_freq = 103.7 # помехи под первые титры


func _process(delta: float) -> void:
	t += delta
	var g := game
	if t < 0.1:
		g.cam.reset_smoothing()
	match shot:
		"drive":
			g.ctl.move = Vector2(1, 0)
		"radio":
			g.radio_freq = snappedf(minf(94.2, 91.0 + t * 1.6), 0.1) # стрелка ползёт к частоте эха
		"fight":
			# тьма → твари подходят → вспышка фонаря → два выстрела → граната
			_aim_nearest()
			g.ctl.move = Vector2(-0.15, 0.05)
			_at(0.9, func() -> void: g.toggle_flashlight())
			_at(1.6, func() -> void: g.attack())
			_at(2.6, func() -> void:
				g.attack_cd = 0.0
				g.attack())
			_at(3.1, func() -> void: g.use_item("grenade"))
		"packers":
			_aim_nearest()
			g.ctl.move = Vector2(-0.2, 0)
			_at(1.2, func() -> void: g.toggle_flashlight())
		"crawler":
			_aim_nearest()
			_at(1.6, func() -> void: g.attack())
			_at(2.7, func() -> void:
				g.attack_cd = 0.0
				g.attack())
		"snow":
			g.ctl.move = Vector2(0.8, -0.1)
			g.ctl.aiming = false
		"station":
			g.ctl.move = Vector2(-0.35, 0.0)
		"music":
			# подложка: спокойная дорога → бой → выдох
			var calm := 1.0 - smoothstep(9.0, 12.0, t)
			var fight := smoothstep(10.0, 13.0, t) * (1.0 - smoothstep(length - 12.0, length - 9.0, t))
			var home := smoothstep(length - 12.0, length - 9.0, t)
			g.music.mix(0.9 * calm + 0.7 * fight + 0.5 * home, home * 0.6, fight)
	card_ui.queue_redraw()


func _at(when: float, f: Callable) -> void:
	if t >= when and not fired.has(when):
		fired[when] = true
		f.call()


func _aim_nearest() -> void:
	var best: Dictionary = {}
	var bd := 1e9
	for m in game.monsters:
		var d: float = m.pos.distance_to(game.player_pos)
		if d < bd:
			bd = d
			best = m
	if not best.is_empty():
		game.ctl.aim = (best.pos - game.player_pos).normalized()
		game.ctl.aiming = true


func _draw_card() -> void:
	var s := card_ui.get_viewport_rect().size
	# кинематографичные полосы сверху и снизу
	if shot != "title":
		card_ui.draw_rect(Rect2(0, 0, s.x, s.y * 0.09), Color.BLACK)
		card_ui.draw_rect(Rect2(0, s.y * 0.91, s.x, s.y * 0.09), Color.BLACK)
		return
	card_ui.draw_rect(Rect2(Vector2.ZERO, s), Color.BLACK)
	var a := clampf(t / 0.35, 0.0, 1.0) * clampf((length - t) / 0.35, 0.0, 1.0)
	var lines := text.split("\n")
	if big:
		var zoom := 1.0 + t * 0.03
		_center(Vector2(s.x * 0.5, s.y * 0.46), lines[0], int(64 * zoom), Color(1.0, 0.62, 0.25, a))
		for i in range(1, lines.size()):
			_center(Vector2(s.x * 0.5, s.y * 0.46 + 34 + i * 24), lines[i], 18, Color(0.92, 0.9, 0.82, a))
		return
	var y := s.y * 0.5 - (lines.size() - 1) * 14.0
	for ln in lines:
		_center(Vector2(s.x * 0.5, y + 8), ln, 22, Color(0.95, 0.92, 0.85, a))
		y += 30.0


func _center(p: Vector2, s: String, size: int, c: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	card_ui.draw_string(font, p - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)
