class_name MaterialStack
extends CodecResource
## 「某种物品 × 若干份」的组合，配方输入、设备升级材料、信件奖励共用。
##
## 要料有两种写法，二选一：
## - `material`：指名某一样（`game:item/coffee_bean`），DataRegistry 校验它确实存在；
## - `by_tag`：这个标签下的任意一种都算（`game:tag/veg` = 「随便一种蔬菜」），
##   标签必须是 `TagDef.Scope.INGREDIENT`。
## 字段名沿用「材料」是因为多数场合装的是材料；食物也能当配方输入，同样走这里。

## 物品完整键（namespace:id）；与 by_tag 二选一
@export var material: String = ""
## 数量，必须 > 0
@export var amount: int = 1
## 食材标签完整键；填了就表示「属于这个标签的任意一种」，与 material 二选一
@export var by_tag: String = ""

static func get_type_id() -> String:
	return "material_stack"

static func get_codec() -> Codec:
	var fields := [
		GameDef._opt_string("material", ""),
		GameDef._opt_int("amount", 1),
		GameDef._opt_string("by_tag", ""),
	]
	return Codec.record(MapCodec.build(fields, func(...values): return _from_values(values)))

static func _from_values(values: Array) -> MaterialStack:
	var stack := MaterialStack.new()
	stack.material = values[0]
	stack.amount = values[1]
	stack.by_tag = values[2]
	return stack

func _to_string() -> String:
	if not by_tag.is_empty():
		return "任意 %s ×%d" % [by_tag, amount]
	return "%s ×%d" % [material, amount]
