class_name RecipeDef
extends GameDef
## 配方定义：输入材料 → 输出（食物或中间材料），可绑定设备与耗时。
##
## 耗时为 0 是合法用例（决策：美式这类「一按即得」的配方，不强制等待）。
##
## 配方分两类（决策：`docs/decisions/2026-10-24-research-combos.md`）：
## - `research_pool` 为空：一开始就可见，玩家在灶台直接能做（中间材料、教学线）；
## - `research_pool` 非空：要先在研究台用候选材料试出来，才知道这道菜怎么做。

## 一条配方最多几种原料。**只是数据校验上限**（防内容失控、防配方详情放不下），
## 与批处理份数无关（份数上限由设备等级决定，见 `GameState.max_batches()`）。
## 2026-10-29 定：**9**——十进制直觉，高于当前最强配方 5 种（布朗尼 / 麻婆豆腐 / 拉面）
## 留 4 个余量；不再是 2 的幂，也不再和任何整除逻辑挂钩。
## 原经济 v2「单份原料总份数 ≤ 8」规则已废弃：份数已被「材料 ×N + 时间 ×0.65 +
## 设备等级份数上限」约束，额外的总份数上限没有产出。
const MAX_INPUT_KINDS := 9

## 主产物完整键（物品，材料与食物同属 ItemDef）。卡名、图标、订单都认它。
@export var output: String = ""
## 每做一批的主产物数量（默认 1）。做 N 批即 N × output_amount 份。
@export_range(1, 99, 1) var output_amount: int = 1
## 副产物（可空）。只支持指名 material；按标签的 stack 在这里没有意义。
## 每做一批每种副产物给 stack.amount 份；它们不参与订单与「这道菜」的判定。
@export var extra_outputs: Array[MaterialStack] = []
## 输入材料
@export var inputs: Array[MaterialStack] = []
## 制作耗时（秒）
@export_range(0.0, 600.0, 0.1) var duration_seconds: float = 0.0
## 所需设备完整键（空 = 不需要设备）
@export var facility: String = ""
## 是否作为「工艺」进图鉴
@export var in_catalog: bool = true
## 图鉴排序
@export var order: int = 0
## 候选材料池（完整键）。非空 = 需要研究解锁；池里应包含 inputs 的全部材料
@export var research_pool: Array[String] = []
## 图鉴里未解锁时显示的方向性提示
@export var research_hint: String = ""
## 解锁该配方所需「自己这台设备」的等级；0 = 不限。
## 大于 1 时，材料对了但设备等级不够会得到「火候不对」。
@export_range(0, 10, 1) var research_min_facility_level: int = 0
## 灶台左列的分组：semi（半成品）/ drink（饮品）/ bake（烘焙）/ steam（蒸点）/ meal（正餐）。
## 只影响列表归组，不参与任何数值；认不出的值退回 drink。
@export var group: String = ""
## 成品食物是否允许按设备等级批量制作（默认 false）。
## 只给浓缩这类「一次多杯」的饮品开；中间品仍走「设备等级 + 1」的旧规则。
## Lv1 恒为 1 份，Lv2 = 2 份，以此类推，上限 BATCH_MAX。
@export var allow_batches: bool = false

static func get_type_id() -> String:
	return "recipe"

static func get_codec() -> Codec:
	var fields := GameDef.base_fields()
	fields.append(GameDef._opt_string("output", ""))
	fields.append(GameDef._opt_stacks("inputs"))
	fields.append(GameDef._opt_float("duration_seconds", 0.0))
	fields.append(GameDef._opt_string("facility", ""))
	fields.append(GameDef._opt_bool("in_catalog", true))
	fields.append(GameDef._opt_int("order", 0))
	fields.append(GameDef._opt_strings("research_pool"))
	fields.append(GameDef._opt_string("research_hint", ""))
	fields.append(GameDef._opt_int("research_min_facility_level", 0))
	fields.append(GameDef._opt_string("group", ""))
	fields.append(GameDef._opt_int("output_amount", 1))
	fields.append(GameDef._opt_stacks("extra_outputs"))
	fields.append(GameDef._opt_bool("allow_batches", false))
	return Codec.record(MapCodec.build(fields, func(...values): return _from_values(values)))

static func _from_values(values: Array) -> RecipeDef:
	var def := RecipeDef.new()
	GameDef.apply_base(def, values)
	def.output = values[4]
	var stacks: Array[MaterialStack] = []
	stacks.assign(values[5])
	def.inputs = stacks
	def.duration_seconds = values[6]
	def.facility = values[7]
	def.in_catalog = values[8]
	def.order = values[9]
	var pool: Array[String] = []
	pool.assign(values[10])
	def.research_pool = pool
	def.research_hint = values[11]
	def.research_min_facility_level = values[12]
	def.group = values[13]
	def.output_amount = values[14]
	var extras: Array[MaterialStack] = []
	extras.assign(values[15])
	def.extra_outputs = extras
	def.allow_batches = values[16]
	return def

## 主产物 + 副产物的「每批产出」清单；primary 项带 output_amount。
## 只用于展示与发放，不缓存（Resource 数据在运行期只读）。
func output_stacks() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	rows.append({"material": output, "amount": maxi(1, output_amount), "primary": true})
	for stack in extra_outputs:
		if stack == null or stack.material.is_empty():
			continue
		rows.append({"material": stack.material, "amount": maxi(0, stack.amount), "primary": false})
	return rows

## 是否不需要设备
func needs_facility() -> bool:
	return not facility.is_empty()

## 是否需要先研究才能做
func needs_research() -> bool:
	return not research_pool.is_empty()

## 输入材料的完整键（排序后比较用）。
## 按标签要料的那种（`MaterialStack.by_tag`）没有固定键，不在这里出现——
## 它是「这个标签下任意一种」，要比较成员请用 `DataRegistry.tag_member_keys()`。
func input_keys() -> Array[String]:
	var keys: Array[String] = []
	for stack in inputs:
		if stack != null and not stack.material.is_empty():
			keys.append(stack.material)
	return keys
