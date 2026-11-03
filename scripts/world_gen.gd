## Генератор RE-RAIL:
##  • events(...) — случайные события в пути для любой главы: завал на путях,
##    путник, брошенный груз (детерминированно от зерна — после загрузки те же);
##  • endless(...) — перегон «Бесконечной магистрали»: биом, станция, цель, хлам,
##    твари и костры, с ростом сложности по глубине. Формат — как у глав в chapters.json.
extends RefCounted

const STATIONS := ["РАЗЪЕЗД 47", "ПОЛУСТАНОК ГЛУХОЙ", "СТАНЦИЯ КРАСНЫЙ ЯР", "РАЗЪЕЗД ТИХИЙ",
	"СТАНЦИЯ БЕРЁЗОВКА", "ПОЛУСТАНОК 112 КМ", "СТАНЦИЯ НИЖНЯЯ ПОЙМА", "РАЗЪЕЗД ВОЛЧИЙ",
	"СТАНЦИЯ ОЗЁРНАЯ", "ПОЛУСТАНОК КЕДРОВЫЙ", "СТАНЦИЯ ЗАРЯ", "РАЗЪЕЗД ПОСЛЕДНИЙ"]
const GOALS := [
	{"kind": "generator", "label": "Чинить генератор", "done": "Генератор ожил — станция в свету."},
	{"kind": "switch", "label": "Перевести стрелку", "done": "Стрелка встала — путь открыт."},
	{"kind": "gate", "label": "Открыть ворота", "done": "Ворота со скрипом разошлись."},
	{"kind": "tower", "label": "Оживить вышку", "done": "Вышка загудела над станцией."},
]
const LORE := [
	"…кто-нибудь слышит… у нас кончилась вода… станция в двух перегонах…",
	"…не ходите ночью без огня… они идут на темноту…",
	"…здесь был наш дом… мы ушли на восток… ищите нас по дыму…",
	"…сигнал бедствия… поезд четыреста… мы в тумане…",
	"…если ты это слышишь — ты не один… держись рельсов…",
]
const LOOT_EXTRA := ["coal", "cloth", "chem", "ammo", "cans", "medkit", "torch", "battery"]


## События в пути для главы. Ставятся в «пустых» местах между стартом и станцией.
static func events(ch: Dictionary, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var gx := float(ch.goal.p[0])
	var out := []
	# завал на путях — посередине перегона
	out.append({"kind": "blocker", "x": snappedf(rng.randf_range(gx * 0.42, gx * 0.62), 10.0)})
	# путник у дороги
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	out.append({"kind": "wanderer", "p": [snappedf(rng.randf_range(gx * 0.25, gx * 0.8), 10.0), 70.0 * side]})
	# брошенный груз
	var loot := {"scrap": 1}
	loot[LOOT_EXTRA[rng.randi() % LOOT_EXTRA.size()]] = 1 if rng.randf() < 0.6 else 2
	out.append({"kind": "crate", "p": [snappedf(rng.randf_range(gx * 0.2, gx * 0.85), 10.0), -80.0 if side > 0 else 80.0], "loot": loot})
	return out


## Перегон «Бесконечной магистрали» на глубине depth (1, 2, 3…).
static func endless(depth: int, seed: int, templates: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var tpl: Dictionary = templates[rng.randi() % templates.size()]
	var length := 3000.0 + rng.randf_range(0.0, 900.0)
	var gx := snappedf(length - 360.0, 10.0)
	var g: Dictionary = GOALS[rng.randi() % GOALS.size()]
	var need_scrap := mini(4 + depth, 10)
	var cost := {"scrap": need_scrap}
	if depth >= 2:
		cost["chem"] = mini(1 + depth / 3, 3)
	# хлама в кучах — с запасом над ценой цели
	var piles := []
	var n_piles := 5 + rng.randi() % 3
	var scrap_left := need_scrap + 2
	for i in n_piles:
		var x := snappedf(lerpf(500.0, gx - 160.0, (i + rng.randf_range(0.1, 0.9)) / n_piles), 10.0)
		var y := snappedf(rng.randf_range(90.0, 170.0) * (-1.0 if rng.randf() < 0.5 else 1.0), 10.0)
		var loot := {}
		var sc := mini(scrap_left, 1 + rng.randi() % 3) if i < n_piles - 1 else scrap_left
		if sc > 0:
			loot["scrap"] = sc
			scrap_left -= sc
		loot[LOOT_EXTRA[rng.randi() % LOOT_EXTRA.size()]] = 1 + rng.randi() % 2
		if rng.randf() < 0.5:
			loot["coal"] = 8 + rng.randi() % 12
		if cost.has("chem") and i == 1:
			loot["chem"] = int(cost.chem)
		piles.append({"p": [x, y], "loot": loot})
	var mobs := {"rustling": 1.0, "packer": minf(0.2 * depth, 1.0), "crawler": minf(0.15 * (depth - 1), 0.8)}
	var wrecks := []
	for i in 3 + rng.randi() % 3:
		wrecks.append([snappedf(rng.randf_range(400, gx - 300), 10.0), snappedf(rng.randf_range(110, 170) * (-1.0 if i % 2 == 0 else 1.0), 10.0)])
	var fires := [[snappedf(rng.randf_range(900, gx - 600), 10.0), snappedf(rng.randf_range(60, 120) * (-1.0 if rng.randf() < 0.5 else 1.0), 10.0)]]
	var station: String = STATIONS[rng.randi_range(0, STATIONS.size() - 1)]
	return {
		"id": "endless_%d" % depth,
		"endless": true,
		"name": "Перегон %d · %s" % [depth, station.capitalize()],
		"intro": "Бесконечная магистраль уходит дальше на восток. Перегон %d. Чем дальше — тем гуще туман и злее твари." % depth,
		"length": length,
		"biome": tpl.biome,
		"mobs": mobs,
		"max_mobs": mini(4 + depth / 2, 7),
		"spawn": [maxf(2.2, 3.6 - depth * 0.15), maxf(4.0, 6.5 - depth * 0.2)],
		"station": {"p": [gx - 100.0, -150.0], "name": station},
		"goal": {"kind": g.kind, "p": [gx, -110.0], "label": g.label, "cost": cost, "done": g.done,
			"after": "Путь открыт. Дальше на восток →"},
		"wrecks": wrecks,
		"fires": fires,
		"piles": piles,
		"npcs": [],
		"fireflies": [[snappedf(rng.randf_range(800, gx - 800), 10.0), 150.0]] if rng.randf() < 0.5 else [],
		"echoes": [{"p": [snappedf(rng.randf_range(600, gx - 400), 10.0), -60.0], "freq": snappedf(rng.randf_range(88.5, 107.0), 0.1),
			"r": 300.0, "text": LORE[rng.randi() % LORE.size()]}],
		"daughter": {},
		"bot": ["auto"],
	}
