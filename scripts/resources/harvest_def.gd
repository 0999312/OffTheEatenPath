class_name HarvestDef
extends GameDef
## 采集点定义：桌面下沿的一处产地，出货范围是一**类**材料（食材标签）。
##
## 为什么按标签而不是按单样：材料只会越来越多，一个一个点往桌上排会先把屏幕挤爆
## （7 张卡已经 1440px > 1280）；改成「一处产地管一类货」，加新材料只要给它挂上标签。
## 具体摇出哪一样是随机的，等级越高池子里能出现的东西越多——门槛写在
## `ItemDef.harvest_tier` 上（材料自己的稀有度），不在这张表里抄名单。
##
## 与 ItemDef 分开的理由：采集点是「一条五级升级线 + 四项随级变化的数值」，
## 塞进物品表会让中间品、水这些不可采集的条目挂一串空字段；
## 而且它不占产线槽、不参与设备 speed factor，混进 FacilityDef 会污染设备逻辑。
##
## 三条数组（cooldown / yield / trickle）长度必须一致，就是这条线的最高等级；
## 索引 0 是 Lv1。`upgrade_coin_costs` 与 `upgrade_item_amounts` 各比最高等级少一项
## （「升到 2 级」「升到 3 级」…）。单样上限不在这里：它跟着仓库等级走，
## 见 `GameState.get_material_cap()`（第四轮反馈）。

## 出货范围：食材标签的完整键（`game:tag/veg`）。标签下 `harvest_tier <= 当前等级`
## 的材料都可能被摇出来。
@export var tag: String = ""
## 每次点击后的冷却秒数（按级）
@export var cooldown_seconds: Array[float] = []
## 每次点击到手几份（按级）
@export var yield_per_click: Array[int] = []
## 自动涓流每秒产量（按级，0 = 这一级还没有涓流）
@export var trickle_per_second: Array[float] = []
## 升到下一级的花费（铜币）
@export var upgrade_coin_costs: Array[int] = []
## 升到下一级要交的份数（这个标签下任意材料，0 = 只花铜币）
@export var upgrade_item_amounts: Array[int] = []
## 这条采集点几级才出现在桌面上（空 = 开局就有）
@export var unlock_facility: String = ""
@export_range(0, 9, 1) var unlock_level: int = 0
## 要读过这封信才出现（与 `FacilityDef.unlock_letter` 同语义；空 = 不看信件）
@export var unlock_letter: String = ""
## 桌面上的排列顺序（小的靠前）
@export_range(0, 99, 1) var order: int = 0

static func get_type_id() -> String:
	return "harvest"

## 最高等级 = 数值数组的长度（至少 1 级）
func max_level() -> int:
	return maxi(1, cooldown_seconds.size())

## 取某一级的数值；越界就夹到边界，调用方不必自己 clamp
func cooldown_at(level: int) -> float:
	var index := clampi(level - 1, 0, cooldown_seconds.size() - 1)
	return cooldown_seconds[index] if index >= 0 else 0.0

func yield_at(level: int) -> int:
	var index := clampi(level - 1, 0, yield_per_click.size() - 1)
	return yield_per_click[index] if index >= 0 else 1



func trickle_at(level: int) -> float:
	var index := clampi(level - 1, 0, trickle_per_second.size() - 1)
	return trickle_per_second[index] if index >= 0 else 0.0

## 升到 `target_level` 的铜币花费；已满级或没有配置返回 -1
func coin_cost_to(target_level: int) -> int:
	if target_level <= 1 or target_level > max_level():
		return -1
	var index := target_level - 2
	if index < 0 or index >= upgrade_coin_costs.size():
		return -1
	return upgrade_coin_costs[index]

## 升到 `target_level` 要交的材料份数；没有配置按 0 算
func item_cost_to(target_level: int) -> int:
	if target_level <= 1 or target_level > max_level():
		return 0
	var index := target_level - 2
	if index < 0 or index >= upgrade_item_amounts.size():
		return 0
	return upgrade_item_amounts[index]

static func get_codec() -> Codec:
	var fields := GameDef.base_fields()
	fields.append(GameDef._opt_string("tag", ""))
	fields.append(GameDef._opt_floats("cooldown_seconds"))
	fields.append(GameDef._opt_ints("yield_per_click"))
	fields.append(GameDef._opt_floats("trickle_per_second"))
	fields.append(GameDef._opt_ints("upgrade_coin_costs"))
	fields.append(GameDef._opt_ints("upgrade_item_amounts"))
	fields.append(GameDef._opt_string("unlock_facility", ""))
	fields.append(GameDef._opt_int("unlock_level", 0))
	fields.append(GameDef._opt_string("unlock_letter", ""))
	fields.append(GameDef._opt_int("order", 0))
	return Codec.record(MapCodec.build(fields, func(...values): return _from_values(values)))

static func _from_values(values: Array) -> HarvestDef:
	var def := HarvestDef.new()
	GameDef.apply_base(def, values)
	def.tag = values[4]
	def.cooldown_seconds = _floats(values[5])
	def.yield_per_click = _ints(values[6])
	def.trickle_per_second = _floats(values[7])
	def.upgrade_coin_costs = _ints(values[8])
	def.upgrade_item_amounts = _ints(values[9])
	def.unlock_facility = values[10]
	def.unlock_level = values[11]
	def.unlock_letter = values[12]
	def.order = values[13]
	return def

static func _ints(raw: Variant) -> Array[int]:
	var result: Array[int] = []
	if raw is Array:
		for item in raw:
			result.append(int(item))
	return result

static func _floats(raw: Variant) -> Array[float]:
	var result: Array[float] = []
	if raw is Array:
		for item in raw:
			result.append(float(item))
	return result
