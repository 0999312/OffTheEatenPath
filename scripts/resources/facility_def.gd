class_name FacilityDef
extends GameDef
## 设备定义：研磨机 / 咖啡机 / 烤箱 / 冰箱。设备平时只影响速度与并行，
## 开局就有 1 级；填了 `unlock_letter` 的设备例外——开局是 0 级（还没有），
## 读到那封信才进厨房（冰箱：`docs/plans/2026-10-25-content-v5-structure.md` §2.1）。

## 最高等级（含 1 级）
@export_range(1, 10, 1) var max_level: int = 3
## 各等级的速度系数（下标 = 等级 - 1；1.0 = 基准，0.8 = 快 20%）
@export var level_speed_factors: Array[float] = []
## 升级表（从 2 级起）
@export var upgrades: Array[FacilityUpgrade] = []
## 设备类别，决定它影响哪些工艺（自由文本，P2 用它匹配配方）
@export var category: String = ""
## 解锁这封信才进厨房（空 = 开局就有 1 级）
@export var unlock_letter: String = ""
## 进度条等处的设备标志色；透明 = 按 category 回落
@export var accent: Color = Color(0, 0, 0, 0)

static func get_type_id() -> String:
	return "facility"

static func get_codec() -> Codec:
	var fields := GameDef.base_fields()
	fields.append(GameDef._opt_int("max_level", 3))
	fields.append(GameDef._opt_floats("level_speed_factors"))
	fields.append(GameDef._opt_upgrades("upgrades"))
	fields.append(GameDef._opt_string("category", ""))
	fields.append(GameDef._opt_string("unlock_letter", ""))
	return Codec.record(MapCodec.build(fields, func(...values): return _from_values(values)))

static func _from_values(values: Array) -> FacilityDef:
	var def := FacilityDef.new()
	GameDef.apply_base(def, values)
	def.max_level = values[4]
	var factors: Array[float] = []
	factors.assign(values[5])
	def.level_speed_factors = factors
	var upgrades: Array[FacilityUpgrade] = []
	upgrades.assign(values[6])
	def.upgrades = upgrades
	def.category = values[7]
	def.unlock_letter = values[8]
	return def

## 某等级的速度系数（越界时回落 1.0）
func get_speed_factor(level: int) -> float:
	var index := level - 1
	if index < 0 or index >= level_speed_factors.size():
		return 1.0
	return level_speed_factors[index]

## 升到目标等级的升级条目（不存在则返回 null）
func get_upgrade(target_level: int) -> FacilityUpgrade:
	for upgrade in upgrades:
		if upgrade != null and upgrade.target_level == target_level:
			return upgrade
	return null

## 设备标志色：tres 里显式填了就用，否则按类别回落（R7.2 规范③）。
func display_accent() -> Color:
	if accent.a > 0.0:
		return accent
	match category:
		"stove":
			return Color("#B4553F")
		"oven":
			return Color("#B9863F")
		"steamer":
			return Color("#4F8A7B")
		"coffee":
			return Color("#A84F7B")
		"grinder":
			return Color("#7A6A55")
		"pan":
			return Color("#6B7F4F")
		"hand":
			return Color("#8C8578")
		"storage":
			return Color("#6E7B86")
		"research":
			return Color("#4E6E8E")
		_:
			return Color("#8C9AA8")
