extends RefCounted
## 四步引导的数据与推进逻辑（不注册 autoload）。
##
## 只负责「第几步该说什么、该去哪个面板、完成时发什么」；界面在
## scripts/ui/tutorial_bar.gd，持久字段在 GameState（tutorial_step / tutorial_done）。
##
## 顺序按现在的开放节奏走：先读第一封信，接着必须亲手做出第一道菜（不是
## 只看一眼灶台），再等杂货商人开张，最后才是交单。订单在第九封信后才解锁，
## 所以第四步带 requires_orders：没解锁时整条引导先收起，解锁后再出现。
##
## 奖励总额 = 第一台可升级设备（研磨机）2 级铜币价 60 × 1.2 = 72，
## 分四步各 18；材料包选开局商店就能买到的基础材料，不硬编码在 UI 里。

const STEPS := [
	{
		"id": "read_letter",
		"title": "ui.tutorial.step0_title",
		"body": "ui.tutorial.step0_body",
		"panel": UIKeys.MAIL,
		"coins": 18,
		"item": "game:item/rice",
		"amount": 2,
	},
	{
		"id": "cook_first_dish",
		"title": "ui.tutorial.step1_title",
		"body": "ui.tutorial.step1_body",
		"panel": UIKeys.CRAFT,
		"coins": 18,
		"item": "game:item/coffee_bean",
		"amount": 2,
	},
	{
		"id": "read_merchant_letter",
		"title": "ui.tutorial.step2_title",
		"body": "ui.tutorial.step2_body",
		"panel": UIKeys.MAIL,
		"coins": 18,
		"item": "game:item/flour",
		"amount": 2,
	},
	{
		"id": "deliver_first_order",
		"title": "ui.tutorial.step3_title",
		"body": "ui.tutorial.step3_body",
		"panel": UIKeys.ORDERS,
		"coins": 18,
		"item": "game:item/milk",
		"amount": 2,
		"requires_orders": true,
	},
]


static func step_count() -> int:
	return STEPS.size()


static func step(index: int) -> Dictionary:
	if index < 0 or index >= STEPS.size():
		return {}
	return STEPS[index]


## 完成当前这一步：先记进度，再发这一步的奖励。
## 只有这一条路径会发奖励，所以重复调用不会重复发（步数已经变了）。
static func complete_current_step() -> int:
	var index := GameState.get_tutorial_step()
	if GameState.is_tutorial_done() or index >= STEPS.size():
		return index
	GameState.advance_tutorial()
	_grant_reward(index)
	return GameState.get_tutorial_step()


## 奖励总额，测试与文档共用；避免把 72 这个数字散落在 UI 里。
static func total_reward_coins() -> int:
	var total := 0
	for entry in STEPS:
		total += int(entry.get("coins", 0))
	return total


static func _grant_reward(index: int) -> void:
	var entry := step(index)
	if entry.is_empty():
		return
	var coins := int(entry.get("coins", 0))
	if coins > 0:
		GameState.add_coins(coins, "引导奖励")
	var item_key := String(entry.get("item", ""))
	if not item_key.is_empty():
		GameState.add_item(item_key, maxi(0, int(entry.get("amount", 0))))
