class_name ThemeDef
extends GameDef
## 食物主题：一个**开放维度**——地域（东亚 / 西式 / 中亚）、品类（甜品 / 街头小吃）、
## 场合（节日 / 深夜）都可以是主题，不限于地域。
##
## 主题只用于图鉴筛选与展示：不参与售价、订单权重、研究池，也**不进图鉴总数**。
## 后期加主题 = 加一个 `.tres` + 两条翻译键，不改代码；食物用 `theme` 字段挂上去。
##
## 开局的桌面上不该一次摊开十个地方的菜：填了 `unlock_letter` 的主题要读过那封信才解锁，
## 空着的（base / cafe）开局就在。

## 主题在图鉴筛选条里的排序（越小越靠前）
@export var order: int = 0
## 读过这封信才解锁（空 = 开局可见）。信算「完成」的标准见
## `docs/decisions/2026-10-28-progressive-unlock-and-tasks.md` §7.2。
@export var unlock_letter: String = ""

static func get_type_id() -> String:
	return "theme"

static func get_codec() -> Codec:
	var fields := GameDef.base_fields()
	fields.append(GameDef._opt_int("order", 0))
	fields.append(GameDef._opt_string("unlock_letter", ""))
	return Codec.record(MapCodec.build(fields, func(...values): return _from_values(values)))

static func _from_values(values: Array) -> ThemeDef:
	var def := ThemeDef.new()
	GameDef.apply_base(def, values)
	def.order = values[4]
	def.unlock_letter = values[5]
	return def
