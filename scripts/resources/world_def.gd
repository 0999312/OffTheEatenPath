class_name WorldDef
extends GameDef
## 世界条目：图鉴「世界」页的内容（白纸空间、窗、远方的味道……）。
## 世界观刻意淡化虚实边界（决策），所以这里只有叙事字段，没有数值。

## 条目标题（可用 `display_name`，此字段留给需要副标题的条目）
@export var subtitle: String = ""
## 正文
@export_multiline var body: String = ""
## 图鉴排序
@export var order: int = 0
## 未发现时的提示
@export var catalog_hint: String = ""
## 要靠哪封信才揭开（空 = 开局就已知，如车厢与门口）
@export var unlock_letter: String = ""

static func get_type_id() -> String:
	return "world"

static func get_codec() -> Codec:
	var fields := GameDef.base_fields()
	fields.append(GameDef._opt_string("subtitle", ""))
	fields.append(GameDef._opt_string("body", ""))
	fields.append(GameDef._opt_int("order", 0))
	fields.append(GameDef._opt_string("catalog_hint", ""))
	fields.append(GameDef._opt_string("unlock_letter", ""))
	return Codec.record(MapCodec.build(fields, func(...values): return _from_values(values)))

static func _from_values(values: Array) -> WorldDef:
	var def := WorldDef.new()
	GameDef.apply_base(def, values)
	def.subtitle = values[4]
	def.body = values[5]
	def.order = values[6]
	def.catalog_hint = values[7]
	def.unlock_letter = values[8]
	return def
