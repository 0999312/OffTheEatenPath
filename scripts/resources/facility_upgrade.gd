class_name FacilityUpgrade
extends CodecResource
## 设备的一次升级：目标等级、铜币花费、材料花费。
## 拆成独立 Resource，是为了让 FacilityDef 的升级表在 .tres 里可以逐条编辑而不写成字典。

## 升到第几级
@export var target_level: int = 2
## 铜币花费
@export_range(0, 100000, 1) var coin_cost: int = 0
## 材料花费
@export var materials: Array[MaterialStack] = []

static func get_type_id() -> String:
	return "facility_upgrade"

static func get_codec() -> Codec:
	var fields := [
		GameDef._opt_int("target_level", 2),
		GameDef._opt_int("coin_cost", 0),
		GameDef._opt_stacks("materials"),
	]
	return Codec.record(MapCodec.build(fields, func(...values): return _from_values(values)))

static func _from_values(values: Array) -> FacilityUpgrade:
	var upgrade := FacilityUpgrade.new()
	upgrade.target_level = values[0]
	upgrade.coin_cost = values[1]
	var stacks: Array[MaterialStack] = []
	stacks.assign(values[2])
	upgrade.materials = stacks
	return upgrade
