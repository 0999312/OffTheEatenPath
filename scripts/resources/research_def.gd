class_name ResearchDef
extends GameDef
## 研究台规则（决策：`docs/decisions/2026-10-24-research-combos.md`）。
##
## 研究台本身是普通 FacilityDef（等级决定并行位与升级花费），这份定义只放
## 「怎么判定、失败烧多少、完全不对要等多久」这类规则，方便一次改全局。
## 只应该有一份实例：`resources/game_data/research/research_rules.tres`。

## 研究台设备完整键
@export var facility: String = "game:facility/research_desk"
## 各等级失败时烧掉的份数（下标 = 等级 - 1）
@export var burn_counts: Array[int] = [2, 1, 1, 1, 1]
## 试错时每样材料除了必扣的 1 份，还有这个概率再扣 1 份
@export_range(0.0, 1.0, 0.05) var charge_chance: float = 0.5
## 旧版按比例烧毁的字段（保留读旧档；新规则用 burn_counts）
@export var burn_rates: Array[float] = [1.0, 0.7, 0.4]
## 完全不对（没有命中任何待解锁配方）时的研究耗时
@export_range(0.0, 60.0, 0.1) var default_seconds: float = 2.0

static func get_type_id() -> String:
	return "research"

static func get_codec() -> Codec:
	var fields := GameDef.base_fields()
	fields.append(GameDef._opt_string("facility", "game:facility/research_desk"))
	fields.append(GameDef._opt_floats("burn_rates"))
	fields.append(GameDef._opt_float("default_seconds", 2.0))
	fields.append(GameDef._opt_ints("burn_counts"))
	fields.append(GameDef._opt_float("charge_chance", 0.5))
	return Codec.record(MapCodec.build(fields, func(...values): return _from_values(values)))

static func _from_values(values: Array) -> ResearchDef:
	var def := ResearchDef.new()
	GameDef.apply_base(def, values)
	def.facility = values[4]
	var rates: Array[float] = []
	rates.assign(values[5])
	def.burn_rates = rates
	def.default_seconds = values[6]
	var counts: Array[int] = []
	counts.assign(values[7])
	def.burn_counts = counts
	def.charge_chance = values[8]
	return def

## 某等级失败时烧掉几份（越界时按最后一级算）
func get_burn_count(level: int) -> int:
	if burn_counts.is_empty():
		return 1
	var index := clampi(level, 1, burn_counts.size()) - 1
	return maxi(1, burn_counts[index])


## 某等级失败时的烧毁率（旧口径，只给读旧档的界面用）
## 某等级失败时的烧毁率（越界时回落到最高损失 1.0）
func get_burn_rate(level: int) -> float:
	var index := clampi(level, 1, maxi(1, burn_rates.size())) - 1
	if index < 0 or index >= burn_rates.size():
		return 1.0
	return clampf(burn_rates[index], 0.0, 1.0)
