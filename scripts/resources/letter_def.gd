class_name LetterDef
extends GameDef
## 信件定义：叙事 + 解锁 + 委托。整封一次显示（决策：不做打字机）。
##
## 解锁条件数据驱动：`condition` 选类型，`condition_ref` / `condition_value` 给参数，
## P2 的 GameState 按这两个字段判断是否解锁，信件本身不写逻辑。
##
## 委托也挂在信上（一封信最多一件）：读信即收进待办；物品/主题/标签类要玩家
## 亲自交付或确认才算办妥，订单/研究类达标即自动办妥。

enum Condition {
	IMMEDIATE,      ## 开局即可读
	AFTER_LETTER,   ## 读完 condition_ref 指向的信件后
	FOOD_CRAFTED,   ## 首次做出 condition_ref 指向的食物后
	CATALOG_COUNT,  ## 图鉴条目数达到 condition_value 后
	TASK_COMPLETED, ## condition_ref 指向的那封信的委托办妥后
}

## 委托的目标类型。NONE = 这封信不带委托。
enum TaskGoal {
	NONE,           ## 没有委托
	CRAFT_FOOD,     ## 做出 task_ref 指向的那道菜 task_amount 份
	CRAFT_THEME,    ## 做出 task_ref 指向主题里的任意 task_amount 道菜
	COLLECT,        ## 手上持有 task_ref 指向的材料 task_amount 份
	CATALOG_COUNT,  ## 图鉴收到 task_amount 条
	DELIVER_ORDER,  ## 累计交付 task_amount 张委托
	RESEARCH_RECIPE, ## 研究出 task_ref 指向的那道菜（研究台组合成功）
	CRAFT_TAG,      ## 做出带 task_ref 标签的任意 task_amount 道菜
}

## 信件标题
@export var title: String = ""
## 信件正文（整封一次显示，用换行分段）
@export_multiline var body: String = ""
## 字迹：unknown / familiar / own；空串不显示（见 ui.letter.handwriting_*）
@export var handwriting: String = ""
## 解锁顺序（1 起，必须唯一）
@export var order: int = 0
@export var condition: Condition = Condition.IMMEDIATE
## 条件参数：AFTER_LETTER / FOOD_CRAFTED / TASK_COMPLETED 是完整键
@export var condition_ref: String = ""
## 条件参数：CATALOG_COUNT 的目标数量
@export var condition_value: int = 0
## 次级条件：图鉴达到这个数才解锁；0 = 不额外要求。
## 用于「读完上一封 + 图鉴 ≥ N」的站间门禁，不替代 condition。
@export var catalog_min: int = 0
## 附件奖励
@export var rewards: Array[MaterialStack] = []
## 铜币奖励
@export_range(0, 100000, 1) var reward_coins: int = 0
## 是否解锁离线产出能力（决策：出发信——序章第 16 封——之后解锁）
@export var unlocks_offline: bool = false

## 委托标题（随信附带的这一件事）
@export var task_title: String = ""
## 委托正文：为什么做这件事、做到什么程度
@export_multiline var task_body: String = ""
## 委托目标类型；NONE 表示这封信没有委托
@export var task_goal: TaskGoal = TaskGoal.NONE
## 目标参数：CRAFT_FOOD / COLLECT 是物品完整键，CRAFT_THEME 是主题完整键，
## CRAFT_TAG 是标签完整键
@export var task_ref: String = ""
## 目标数量（份 / 条 / 张）；CRAFT_FOOD / CRAFT_THEME / CRAFT_TAG 表示几份 / 几道
@export_range(1, 9999, 1) var task_amount: int = 1
## 办妥时给的铜币
@export_range(0, 100000, 1) var task_reward_coins: int = 0
## 办妥时给的材料
@export var task_rewards: Array[MaterialStack] = []

static func get_type_id() -> String:
	return "letter"

static func get_codec() -> Codec:
	var fields := GameDef.base_fields()
	fields.append(GameDef._opt_string("title", ""))
	fields.append(GameDef._opt_string("body", ""))
	fields.append(GameDef._opt_int("order", 0))
	fields.append(GameDef._opt_int("condition", Condition.IMMEDIATE))
	fields.append(GameDef._opt_string("condition_ref", ""))
	fields.append(GameDef._opt_int("condition_value", 0))
	fields.append(GameDef._opt_int("catalog_min", 0))
	fields.append(GameDef._opt_stacks("rewards"))
	fields.append(GameDef._opt_int("reward_coins", 0))
	fields.append(GameDef._opt_bool("unlocks_offline", false))
	fields.append(GameDef._opt_string("task_title", ""))
	fields.append(GameDef._opt_string("task_body", ""))
	fields.append(GameDef._opt_int("task_goal", TaskGoal.NONE))
	fields.append(GameDef._opt_string("task_ref", ""))
	fields.append(GameDef._opt_int("task_amount", 1))
	fields.append(GameDef._opt_int("task_reward_coins", 0))
	fields.append(GameDef._opt_stacks("task_rewards"))
	fields.append(GameDef._opt_string("handwriting", ""))
	return Codec.record(MapCodec.build(fields, func(...values): return _from_values(values)))

static func _from_values(values: Array) -> LetterDef:
	var def := LetterDef.new()
	GameDef.apply_base(def, values)
	def.title = values[4]
	def.body = values[5]
	def.order = values[6]
	def.condition = values[7]
	def.condition_ref = values[8]
	def.condition_value = values[9]
	def.catalog_min = values[10]
	var rewards: Array[MaterialStack] = []
	rewards.assign(values[11])
	def.rewards = rewards
	def.reward_coins = values[12]
	def.unlocks_offline = values[13]
	def.task_title = values[14]
	def.task_body = values[15]
	def.task_goal = values[16]
	def.task_ref = values[17]
	def.task_amount = values[18]
	def.task_reward_coins = values[19]
	var task_rewards: Array[MaterialStack] = []
	task_rewards.assign(values[20])
	def.task_rewards = task_rewards
	def.handwriting = values[21]
	return def

## 该信件是否需要 condition_ref 参数
func needs_condition_ref() -> bool:
	return (
		condition == Condition.AFTER_LETTER
		or condition == Condition.FOOD_CRAFTED
		or condition == Condition.TASK_COMPLETED
	)

## 这封信是否带一件待办的事
func has_task() -> bool:
	return task_goal != TaskGoal.NONE

## 委托的目标数量（至少 1，防止数据里漏填导致「0 份即完成」）
func task_target() -> int:
	return maxi(1, task_amount)
