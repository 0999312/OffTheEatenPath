class_name MerchantDef
extends GameDef
## 商人升级线：一条独立于设备和厨房、只服务「货架」的成长轴（第 9 轮反馈 1）。
##
## 为什么单独建类而不是做成一台设备：
## - 设备页与图鉴按「厨具 / 设备」组织，商人给的是**货源**——槽位、补货速度、能进的货；
## - 做成设备会把它塞进制作面板的厨具筛选，并让「设备 8 项」变成 9 项；
## - 材料解锁门槛写在 ItemDef.merchant_level 上（与采集点的 harvest_tier 同构），
##   这里不重复抄名单：加新货只要给材料填一个等级。
##
## 容量与补货按「等级下标」查表（索引 0 = Lv1），升级花费复用 FacilityUpgrade
## （target_level / coin_cost / materials），与设备升级面板同构，UI 可以照抄。

## 表里没有数值时的回落（与旧常量 SHOP_SLOT_NORMAL / SHOP_SLOT_SCARCE / SHOP_REFILL_SECONDS 一致）
const FALLBACK_NORMAL := 20
const FALLBACK_SCARCE := 10
const FALLBACK_REFILL := 360.0

## 最高等级（含 1 级）
@export_range(1, 10, 1) var max_level: int = 4
## 各等级普通货的槽位（索引 = 等级 - 1）
@export var capacity_normal: Array[int] = []
## 各等级贵料的槽位（买价 >= SHOP_SCARCE_PRICE 的材料走这一档）
@export var capacity_scarce: Array[int] = []
## 各等级「买空后一次补满」的秒数（索引 = 等级 - 1）
@export var refill_seconds: Array[float] = []
## 升级表（从 2 级起）
@export var upgrades: Array[FacilityUpgrade] = []


static func get_type_id() -> String:
	return "merchant"


static func get_codec() -> Codec:
	var fields := GameDef.base_fields()
	fields.append(GameDef._opt_int("max_level", 4))
	fields.append(GameDef._opt_ints("capacity_normal"))
	fields.append(GameDef._opt_ints("capacity_scarce"))
	fields.append(GameDef._opt_floats("refill_seconds"))
	fields.append(GameDef._opt_upgrades("upgrades"))
	return Codec.record(MapCodec.build(fields, func(...values): return _from_values(values)))


static func _from_values(values: Array) -> MerchantDef:
	var def := MerchantDef.new()
	GameDef.apply_base(def, values)
	def.max_level = values[4]
	def.capacity_normal = _ints(values[5])
	def.capacity_scarce = _ints(values[6])
	def.refill_seconds = _floats(values[7])
	var upgrades: Array[FacilityUpgrade] = []
	upgrades.assign(values[8])
	def.upgrades = upgrades
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


## 某等级的普通槽位；越界夹到表的两端（表为空时回落 20，与旧常量一致）
func capacity_normal_at(level: int) -> int:
	return _at(capacity_normal, level, FALLBACK_NORMAL)


## 某等级的贵料槽位
func capacity_scarce_at(level: int) -> int:
	return _at(capacity_scarce, level, FALLBACK_SCARCE)


## 某等级买空后的补货秒数
func refill_seconds_at(level: int) -> float:
	if refill_seconds.is_empty():
		return FALLBACK_REFILL
	var index := clampi(level - 1, 0, refill_seconds.size() - 1)
	return maxf(refill_seconds[index], 1.0)


## 升到目标等级的升级条目（不存在则返回 null）
func get_upgrade(target_level: int) -> FacilityUpgrade:
	for upgrade in upgrades:
		if upgrade != null and upgrade.target_level == target_level:
			return upgrade
	return null


static func _at(values: Array[int], level: int, fallback: int) -> int:
	if values.is_empty():
		return fallback
	var index := clampi(level - 1, 0, values.size() - 1)
	return maxi(values[index], 1)
