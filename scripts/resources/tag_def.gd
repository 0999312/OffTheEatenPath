class_name TagDef
extends GameDef
## 标签：可叠加的「场合 / 属性 / 类别」维度，一处定义、多个条目挂上去。
##
## 与 ThemeDef 的分工：主题回答「这道菜从哪来」（单选、互斥，图鉴按主题分栏），
## 标签回答「它在什么场合出现」（多选，图鉴里叠在主题之上再筛一次）。
## 标签同样不进图鉴总数，也不参与售价 / 订单权重 / 研究池。
## 后期加标签 = 加一个 `.tres` + 两条翻译键，条目用 `tags` 数组挂上去。
##
## `scope` 决定这个标签贴在哪一类条目上、被谁读：
## - `FOOD`：图鉴筛选条里的一格（「街边·宵夜」），食物的 `tags` 挂它；
## - `INGREDIENT`：配方输入可以说「随便哪一种蔬菜」，由 `MaterialStack.by_tag` 引用，
##   材料的 `tags` 挂它。见 `docs/plans/2026-10-25-material-table.md` §1。

## 标签的用途
enum Scope {
	FOOD,  ## 图鉴筛选：食物挂它，图鉴筛选条读它
	INGREDIENT,  ## 配方输入按标签要料：材料挂它，`MaterialStack.by_tag` 读它
}

## 标签在图鉴筛选条里的排序（越小越靠前）
@export var order: int = 0
## 这个标签算哪一类维度（图鉴筛选 / 配方输入）
@export var scope: Scope = Scope.FOOD

static func get_type_id() -> String:
	return "tag"

## 能不能被 `MaterialStack.by_tag` 引用
func is_ingredient() -> bool:
	return scope == Scope.INGREDIENT

static func get_codec() -> Codec:
	var fields := GameDef.base_fields()
	fields.append(GameDef._opt_int("order", 0))
	fields.append(GameDef._opt_int("scope", 0))
	return Codec.record(MapCodec.build(fields, func(...values): return _from_values(values)))

static func _from_values(values: Array) -> TagDef:
	var def := TagDef.new()
	GameDef.apply_base(def, values)
	def.order = values[4]
	def.scope = values[5]
	return def
