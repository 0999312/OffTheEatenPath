extends Node
## 全局游戏状态（autoload，注册在 GameBootstrap 之后）。
##
## 职责边界：这里只有「数字和规则」，没有节点、没有动画、没有 UI。
## 时间由外部推动 —— 主循环每帧调 `advance(delta)`，离线结算（P5）复用同一个入口，
## 所以 `advance()` 必须对任意大的 delta 都成立，不能假设自己被每帧调用。
##
## 「成品即材料」：库存 `_stock` 里放的是物品（材料与食物同属 ItemDef），键都是完整键。

const DATA_REGISTRY_KEY := DataRegistry.REGISTRY_NAME
## 首次做出某个食物奖励的铜币（计划 §2.7）
const COINS_PER_FIRST_FOOD := 5
## 浮点比较容差
const EPSILON := 0.000001
## 单次 advance 的上限，防止存档时间异常时卡死，同时是离线结算的长度上限。
## 第九轮反馈 2：从 24 小时收到 **8 小时**（离线材料改定量后，再长也只是同一批产量）。
const MAX_ADVANCE_SECONDS := 28800.0
## 存档格式版本（破坏性变更时 +1，并在 SaveGame 里补迁移）
## v2：加入研究组合（已解锁配方 / 已试组合 / 进行中的研究）
## v3：库存改整数（小数余量单独存）+ 订单板
## v4：加玩家自选的招牌菜槽位
## v5：加图鉴已看数（旧档没有这个字段时当作「全看过」，读档不亮红点）
## v6：采集点（HarvestDef）取代材料表里的产出字段
## v7：商店供货槽（槽内份数与补货倒计时）
## v8 / v9 也做过若干次破坏性调整（材料表结构调整）
## v10：材料与食物合并成单一 ItemDef，键的路径部分从 `food/…`、`material/…` 统一成
##      `item/…`。旧档的键全部对不上，因此**不做迁移、直接拒绝**（见
##      `docs/decisions/2026-10-26-item-def.md`）：单机无云存档，逐条改名只是把一批
##      注定要被材料表 v5.3 再改一次的键搬一遍，不如让玩家重开一局。
## v13：订单板容量与「换一批」冷却
## v14：图鉴发现顺序、帮手等级、引导进度（R7.1 / R7.2 / R7.4）
## v15：移除帮手等级（旧档残留字段忽略）；离线未解锁时不再推进世界（第八轮反馈 9/10）
## v16：商人等级（第 9 轮反馈 1）；破坏性更新，不做旧档迁移（m00658）
## v17：委托改显式交付（旧口径）
## v18：委托改交付制并加入标签委托；不兼容 v17 及更早存档，直接拒绝
const SAVE_VERSION := 18
## 最低可读版本：v18 起委托语义变化，旧档不再迁移（用户 m04008 Q6=C）
const SAVE_MIN_VERSION := 18
const DISH_REACHABILITY := preload("res://scripts/systems/dish_reachability.gd")
## 研究历史最多保留几条（面板「记录」页只显示这些；决策 2026-10-28 D10）
const RESEARCH_HISTORY_LIMIT := 20
## 商店货架：每种基础材料一个槽。容量按买价分两档（决策 2026-10-28 D4）：
## 买价 ≤ 2 的豆 / 面 / 糖一次摆 20 份，买价 ≥ 3 的奶 / 蛋 / 黄油只摆 10 份。
## 价格固定、不随购买量上涨——「只有被搬空的货物，没有越买越贵」。
const SHOP_SLOT_NORMAL := 20
const SHOP_SLOT_SCARCE := 10
const SHOP_SCARCE_PRICE := 3
## 补货是全局一份计时：第一次买空拨表，之后 6 分钟内再买空不重置；
## 到点一次把所有槽补满。
const SHOP_REFILL_SECONDS := 360.0

## 仓库：容量统一由仓库设施等级决定（第四轮反馈）。只挡采集点累积，
## 买来的、做出来的、信里送的都不受限。不同材料档位仍有不同基数。
const WAREHOUSE_FACILITY := "game:facility/warehouse"
const WAREHOUSE_MAX_LEVEL := 5
## 下标 = 等级 - 1；1 级就是基数，满级 4 倍
## 每级 +1 倍基数：单级提升要看得见（第五轮反馈：1.5/2/3/4 太保守）
const WAREHOUSE_LEVEL_FACTORS: Array[float] = [1.0, 2.0, 3.0, 4.0, 5.0]
const MATERIAL_CAP_COMMON := 20
const MATERIAL_CAP_RARE := 10
const MATERIAL_CAP_INTERMEDIATE := 10
## `harvest_tier` 达到这个数就算稀料，单样上限减半
const MATERIAL_RARE_TIER := 3

## 厨房扩建：一座店里同时能开几条产线（与每个设备自己的槽位相乘）
const KITCHEN_MAX_LEVEL := 4
## 升到 2/3/4 级的花费；索引 = 当前等级 - 1
const KITCHEN_COSTS := [120, 300, 700]
## 批处理：一次最多做几份。只看设备等级（Lv1 → 2 份 … Lv4 → 5 份），与材料有几种无关
## （决策 2026-10-28 D9）；上限跟着设备最高等级 4 走。
const BATCH_MAX := 5
## 批量的时间折扣：做 N 份只要 N×0.65 倍时间，省的是等待不是材料
const BATCH_TIME_FACTOR := 0.65
## 订单板：开局能挂几张委托、最多扩到几张、每扩一张花多少铜币
const ORDER_CAPACITY := 3
const ORDER_CAPACITY_MAX := 5
## 引导共四步：读第一封信 → 做第一道菜 → 读杂货商人的信 → 交第一单。
const TUTORIAL_STEP_COUNT := 4
## 解锁门槛：第 4 封杂货商人的信让商人开张，第 14 封「门槛上的纸」让订单板上桌。
## 只从 read_letters 派生，不写新的存档字段；旧档按已读信自动处于对应状态。
const MERCHANT_UNLOCK_LETTER := "game:letter/milk_merchant"
## 第 14 封「门槛上的纸」：门口递进来的三行字就是最早的订单来源（第 9 轮 D35）。
## 出发信挪到第 16 封之后，订单与离线两把锁分开挂。
const ORDERS_UNLOCK_LETTER := "game:letter/east_asia_note"
const ORDER_CAPACITY_COSTS: Array[int] = [80, 200]
const ORDER_REFILL_SECONDS := 300.0
## 「换一批」：免费重抽整块板，但有冷却，不能一直刷到顺眼为止
const ORDER_REFRESH_COOLDOWN_SECONDS := 300.0
## 招牌菜槽位：氛围层的便条上最多写几道菜（空槽回落到「卖价前三」自动补位）
const SIGNATURE_SLOTS := 3
## 订单酬劳 = 食物收购价 × 数量 × 这个倍数（委托比零卖更值）
const ORDER_REWARD_MULTIPLIER := 2
## 招牌菜被点单时的酬劳加成（1.25 = 多两成半）；每多写一道招牌菜再加 0.1
const SIGNATURE_ORDER_BONUS := 1.25
const SIGNATURE_ORDER_BONUS_PER_EXTRA_SLOT := 0.1
## 手填招牌按「菜系」叠订单权重：同一菜系 1 道 ×1.5、2 道 ×1.8、3 道 ×2.0。
## 只影响这道菜被抽中的概率，不改订单酬劳；自动补位不计。
const SIGNATURE_THEME_BOOSTS: Array[float] = [1.5, 1.8, 2.0]
## 离线看店小费：每 5 分钟一份，常客（完成订单）会提高单价
const OFFLINE_COINS_INTERVAL := 300.0
## 离线材料（第 9 轮反馈 2）：不再按在线涓流全额补，改为**价值锚定**——
## 每个采集点每级每小时 1 份（满级 5 点 × 8 小时 = 200 份），折算卖价低于同期小费。
## 在线涓流一点不动（`advance` 的常规路径）。
const OFFLINE_HARVEST_PER_LEVEL_HOUR := 1.0
## 商人定义：全局只有一份（升级线），与研究台规则同构
const MERCHANT_DEF_KEY := "game:merchant/merchant"
## 结局门槛（第 9 轮反馈 3）：也不写死条目数——内容只增不减，写死会让结局越来越早。
## 比例 0.85 让结局始终落在「几乎集齐」的位置（当前 732 × 0.85 ≈ 622）。
const ENDING_CATALOG_RATIO := 0.85
const ENDING_LETTER_KEY := "game:letter/on_the_road"
## 图鉴里程碑：按收录条目占比触发，发一次就不再发。
## 阈值不写死条目数——总量变了（加内容）自动跟着走。
const MILESTONE_PCTS: Array[float] = [0.25, 0.5, 0.75, 1.0]
const MILESTONE_COINS: Array[int] = [60, 150, 300, 600]

## 一次研究的三种失败档位（成功由「解锁配方」本身表示，不占档位）
enum ResearchOutcome { NONE, MISMATCH, NEAR_MISS, HEAT }

## 铜币
var coins: int = 0
## 是否已解锁离线产出（第 16 封「该发动了」）
var offline_unlocked: bool = false
## 上次结算的 Unix 时间戳（P5 离线结算用）
var last_seen_unix: int = 0
## 本存档累计的在线游戏时长（秒）；离线结算不计入，由 HUD 右上角的时钟读取
var play_seconds: float = 0.0

## 库存：完整键 -> 数量（整数）。基础材料的连续产出先把小数攒在 _stock_fraction，
## 攒够 1 才入库——玩家看到的数字永远是整数。
var _stock: Dictionary = {}
## 基础材料的小数余量：完整键 -> 0..1 之间的小数
var _stock_fraction: Dictionary = {}
## 订单板：当前委托（Order 对象）
var _orders: Array[Order] = []
## 空闲栏位下一次刷出委托还要几秒
var _orders_refill_remaining := 0.0
## 累计交付完成的委托数（常客小费单价用）
var _orders_completed := 0
## 累计刷出过的委托数（离线摘要用）
var _orders_refreshed := 0
## 委托自增编号
var _order_seq := 0
## 订单板当前容量：开局 ORDER_CAPACITY，花铜币最多扩到 ORDER_CAPACITY_MAX
var _order_capacity := ORDER_CAPACITY
## 「换一批」的冷却剩余秒数（0 = 可以换）；随世界时间走，离线也照走
var _order_refresh_cooldown := 0.0
## 图鉴已发现：完整键 -> true
var _discovered: Dictionary = {}
## 做过一次的成品食物：完整键 -> true
var _crafted_food: Dictionary = {}
## 设备等级：完整键 -> 等级（从 1 开始）
var _facility_levels: Dictionary = {}
## 采集点等级：采集点完整键 -> 等级（从 1 开始）
var _harvest_levels: Dictionary = {}
## 采集点冷却：采集点完整键 -> 剩余秒数（0 = 成熟可采）
var _harvest_cooldowns: Dictionary = {}
## 采集点涓流攒的零头：采集点完整键 -> 不够 1 份的小数
var _harvest_pending: Dictionary = {}
## 材料键 → 货架上还剩几份
var _shop_stock: Dictionary = {}
## 商人等级（第 9 轮反馈 1）：1–MerchantDef.max_level，影响槽位与补货速度
var _merchant_level: int = 1
## 全局补货倒计时：距下一次「一次补满所有槽」还有几秒；0 = 没有槽在等补货
## （决策 2026-10-28 D4：不再每 key 一个计时器）
var _shop_refill_remaining := 0.0
## 进行中的制作任务
var _kitchen_level: int = 1
var _jobs: Array[CraftJob] = []
## 已解锁的信件（按解锁顺序）
var _unlocked_letters: Array[String] = []
## 已读过的信件
var _read_letters: Dictionary = {}
## 通过研究解锁的配方：配方键 -> true（不需要研究的配方不记在这里）
var _unlocked_recipes: Dictionary = {}
## 已试过的组合：签名 -> {outcome, recipe, burned}；再试同样组合不烧材料
var _researched: Dictionary = {}
## 进行中的研究任务
var _research_jobs: Array[ResearchJob] = []
## 试错的随机源（每样材料多扣一份的概率）；测试可以固定种子
var _rng := RandomNumberGenerator.new()
## 最近出结果的那次研究（面板显示「上次」用）
var _last_research_signature: String = ""
## 研究历史：按完成先后，最多 RESEARCH_HISTORY_LIMIT 条（面板「记录」页用）
var _research_history: Array[Dictionary] = []
## 研究台三步引导是否已经看过（看一次就不再自动弹）
var _research_guide_seen: bool = false
## 图鉴里程碑已经发到第几档（0 = 还没跨过第一档）
var _milestone_tier: int = 0
## 玩家自选的招牌菜：固定 SIGNATURE_SLOTS 个槽位，空串表示这一格自动补位
var _signature_slots: Array[String] = []
## 下一次补位至少要刷出这个菜系的一单（设置/更换招牌菜时写入；刷出后清空）
var _signature_pending_theme: String = ""
## 上次打开图鉴时已经看到过的发现数；比当前发现数少 = HUD 图鉴上要亮红点
var _catalog_seen: int = 0
## 图鉴发现的先后：元素是条目键，越靠后越新。
## 「定位最新」与「本次打开前新发现」的红点都按它算（R7.1 反馈 3 / 16）。
var _discovery_order: Array[String] = []
## 三步引导：当前步（0..3）与是否已完成/跳过（R7.4 反馈 1）；旧档按已完成迁移
var tutorial_step: int = 0
var tutorial_done: bool = false
## 每道菜累计做过几份（委托进度用；`_crafted_food` 只记「做过没有」）
var _crafted_food_count: Dictionary = {}
## 玩家在信里接下、还没办妥的委托（信件完整键，按接下的先后）
var _accepted_tasks: Array[String] = []
## 已办妥的委托（信件完整键 → true），报酬已发，留在待办里供回看
var _completed_tasks: Dictionary = {}
## 每件委托应下那一刻的计数底数：委托算的是「从答应起又做了多少」，
## 不是「这辈子一共做了多少」。没有它，信里刚让你做的事读信时就已完成（0 分之一），
## 委托等于白送报酬。
var _task_baseline: Dictionary = {}
## 有东西可能改变委托进度（做菜 / 库存 / 图鉴 / 订单），下一个 tick 复查一次
var _tasks_dirty: bool = false
## 配方反查索引：产出 → [配方键]、输入 → [配方键]（R7.1 反馈 24 / R7.2 反馈 23）。
## 图鉴「它可以做…」与订单可达性都查这一份，不各自扫一遍配方表；
## 数据量很小，第一次用到时建一次，配方数量变了（换数据/热重载）自动重建。
var _recipes_by_output: Dictionary = {}
var _recipes_by_input: Dictionary = {}
## 标签输入（`by_tag`）反查：标签键 → 配方键。材料身上挂着标签就能算它的用途。
var _recipes_by_tag: Dictionary = {}
var _recipe_index_size: int = -1

## 「连续做」锁定的配方（空字符串 = 不连续）；只影响本局，不写进存档
var _repeat_recipe_key: String = ""
## 连续做重入保护：立刻完成（0 秒）的配方不再自动续做，避免无限递归
var _repeat_depth: int = 0


func _ready() -> void:
	_rng.randomize()
	reset()


## 回到初始状态。GUT 每个用例前调用它做隔离。
func reset() -> void:
	coins = 0
	offline_unlocked = false
	last_seen_unix = int(Time.get_unix_time_from_system())
	play_seconds = 0.0
	_stock.clear()
	_stock_fraction.clear()
	_discovered.clear()
	_discovery_order.clear()
	tutorial_step = 0
	tutorial_done = false
	_crafted_food.clear()
	_crafted_food_count.clear()
	_facility_levels.clear()
	_kitchen_level = 1
	_harvest_levels.clear()
	_harvest_cooldowns.clear()
	_harvest_pending.clear()
	_shop_stock.clear()
	_shop_refill_remaining = 0.0
	_merchant_level = 1
	_read_letters.clear()
	_unlocked_letters.clear()
	_accepted_tasks.clear()
	_completed_tasks.clear()
	_task_baseline.clear()
	_tasks_dirty = false
	_jobs.clear()
	_unlocked_recipes.clear()
	_researched.clear()
	_research_jobs.clear()
	_research_history.clear()
	_research_guide_seen = false
	_last_research_signature = ""
	_repeat_recipe_key = ""
	_repeat_depth = 0
	_milestone_tier = 0
	_orders.clear()
	_orders_refill_remaining = 0.0
	_orders_completed = 0
	_orders_refreshed = 0
	_order_seq = 0
	_order_capacity = ORDER_CAPACITY
	_order_refresh_cooldown = 0.0
	_signature_slots.clear()
	_signature_pending_theme = ""
	for i in SIGNATURE_SLOTS:
		_signature_slots.append("")
	for def in _defs_of_type("facility"):
		var facility := def as FacilityDef
		# 要靠信件添置的设备（冰箱）开局是 0 级，也还不算「已知」
		if facility != null and not facility.unlock_letter.is_empty():
			_facility_levels[def.get_key()] = 0
			continue
		_facility_levels[def.get_key()] = 1
		# 设备与身处的世界一开始就在房间里，属于「已知」
		_discovered[def.get_key()] = true
	for def in _defs_of_type("world"):
		var world := def as WorldDef
		# 要靠一封信才揭开的地方（沿途的站）开局还不在图鉴里
		if world != null and not world.unlock_letter.is_empty():
			continue
		_discovered[def.get_key()] = true
	# 开局房间里的设备与世界也算「发现」：给它们一个稳定的先后，后续发现才接在后面
	_discovery_order = get_discovered_keys()
	for def in _defs_of_type("harvest"):
		_harvest_levels[(def as HarvestDef).get_key()] = 1
	for key in _shop_keys():
		_shop_stock[key] = get_shop_capacity(key)
	_refresh_letters()
	_refill_orders()
	# 开局就摆在房间里的设备与世界条目不催玩家去看图鉴
	_catalog_seen = get_catalog_discovered_count()


# --- 时间推进 -------------------------------------------------------------


## 推进 `seconds` 秒的世界时间：制作任务推进 + 信件条件复查。
## 材料只在玩家点采集点时到手（在线不再自动涓流，第十轮反馈 4）；离线才按
## 每采集点每级每小时 1 份补货。其余子系统两条路径完全一样，排队制作、
## 研究、订单补位在离线期间照常推进——那些是玩家自己安排好的产线。
func advance(seconds: float, offline: bool = false) -> void:
	if seconds <= 0.0:
		return
	seconds = minf(seconds, MAX_ADVANCE_SECONDS)
	# 只有在线推进才算「玩过」：离线结算是关游戏期间的时间，不该灌进本局时长
	if not offline:
		play_seconds += seconds
	_advance_harvest(seconds)
	_advance_shop(seconds)
	if offline:
		_accrue_offline_harvest(seconds)
	_advance_jobs(seconds)
	_advance_research(seconds)
	_advance_orders(seconds)
	_refresh_letters()
	_advance_tasks()
	last_seen_unix = int(Time.get_unix_time_from_system())


## 本存档累计在线秒数（向下取整）；HUD 默认显示它而不是系统时间
func get_play_seconds() -> int:
	return maxi(0, int(floor(play_seconds)))


## 冷却倒计时：仍然只按世界时间走，离线也照走（离线回来采集点已成熟，但不替玩家采）
func _advance_harvest(seconds: float) -> void:
	for key in _harvest_cooldowns.keys():
		var left := float(_harvest_cooldowns[key]) - seconds
		if left <= 0.0:
			_harvest_cooldowns.erase(key)
		else:
			_harvest_cooldowns[key] = left


## 补货：全局一份倒计时，到点一次把所有槽补满。离线照走（不替玩家买，只是货架满了）。
## 买空只负责「把表拨起来」——已经在走就不重置，否则连买几样会把 CD 越拖越长。
func _advance_shop(seconds: float) -> void:
	if _shop_refill_remaining <= 0.0:
		return
	_shop_refill_remaining = maxf(0.0, _shop_refill_remaining - seconds)
	if _shop_refill_remaining > 0.0:
		return
	for key in _shop_keys():
		_shop_stock[key] = get_shop_capacity(key)


## 有货架的材料：基础材料里能买到的那些（奶油与糖只从这里来，也是它们唯一的来源）
func _shop_keys() -> Array[String]:
	var keys: Array[String] = []
	for def in _defs_of_type("item"):
		var item := def as ItemDef
		if item == null or not item.is_material() or item.is_free():
			continue
		if item.merchant_price <= 0:
			continue
		# 商人等级不够的材料先不上架（辣椒 Lv2、豆腐/泡菜 Lv3）
		if item.merchant_level > get_merchant_level():
			continue
		keys.append(item.get_key())
	return keys


## 槽位容量按买价分两档，数值随商人等级走（第 9 轮反馈 1；旧常量只作回落）
func get_shop_capacity(key: String) -> int:
	var def := _def(key) as ItemDef
	var scarce := def != null and def.merchant_price >= SHOP_SCARCE_PRICE
	var merchant := get_merchant_def()
	if merchant != null:
		var level := get_merchant_level()
		return merchant.capacity_scarce_at(level) if scarce else merchant.capacity_normal_at(level)
	if def == null:
		return SHOP_SLOT_NORMAL
	return SHOP_SLOT_SCARCE if scarce else SHOP_SLOT_NORMAL


## 买空后到补满的秒数：随商人等级缩短（Lv1 360 → Lv4 180）
func get_shop_refill_seconds() -> float:
	var merchant := get_merchant_def()
	if merchant == null:
		return SHOP_REFILL_SECONDS
	return merchant.refill_seconds_at(get_merchant_level())


func get_shop_stock(key: String) -> int:
	return int(_shop_stock.get(key, 0))


## 距离下一次全局补货还有几秒；0 = 没有空槽在等（不是「刚补完」）
func get_shop_refill_remaining() -> float:
	return maxf(0.0, _shop_refill_remaining)


## 兼容旧签名：补货是全局一份，任何 key 问到的是同一个倒计时
func get_shop_refill_left(_key: String) -> float:
	return get_shop_refill_remaining()


func is_shop_empty(key: String) -> bool:
	return get_shop_stock(key) <= 0


## 历史实现：在线自动涓流。第十轮反馈 4 起在线材料只靠玩家点采集点，
## 这里不再被 `advance` 调用；留着是为了对照「旧在线产速」的数值，
## 以及将来若要给某条采集线单独恢复涓流时有个现成的入口。
## 单样材料堆到仓库上限就不再摇到它（池里全都满了就丢掉这一份，不攒着等）。
func _accrue_harvest_trickle(seconds: float) -> void:
	for def in _defs_of_type("harvest"):
		var harvest := def as HarvestDef
		if harvest == null or not is_harvest_unlocked(harvest):
			continue
		var key := harvest.get_key()
		var level := get_harvest_level(key)
		var rate := harvest.trickle_at(level)
		if rate <= 0.0:
			continue
		var pending := float(_harvest_pending.get(key, 0.0)) + rate * seconds
		# 一次推进可能是一小时（离线结算），所以先把整份数收下来再逐份摇
		var units := int(floor(pending))
		_harvest_pending[key] = pending - float(units)
		for _index in units:
			if _pick_from_harvest(harvest).is_empty():
				break


## 离线材料（第 9 轮反馈 2）：每个采集点每级每小时 1 份，到上限就直接丢。
## 不走 `_accrue_harvest_trickle`：那套是「每份随机摇一样」，离线 8 小时满级
## 会摇出两千多份，材料会变成第二货币（§4.2 换算表）。
func _accrue_offline_harvest(seconds: float) -> void:
	var hours := seconds / 3600.0
	if hours <= 0.0:
		return
	for def in _defs_of_type("harvest"):
		var harvest := def as HarvestDef
		if harvest == null or not is_harvest_unlocked(harvest):
			continue
		var level := get_harvest_level(harvest.get_key())
		var units := int(floor(OFFLINE_HARVEST_PER_LEVEL_HOUR * float(level) * hours + EPSILON))
		for _index in units:
			if _pick_from_harvest(harvest).is_empty():
				break


func _advance_jobs(seconds: float) -> void:
	var budget := seconds
	# 事件循环：每次只把「最早完成的那一份」推到完成。完成会触发续做
	# （_continue_repeat）并可能新排进一份；新任务必须继续吃剩下的时间，
	# 否则离线结算完会把它当成刚开工（第十轮反馈 4）。
	# 每轮至少推进一份任务或整体收工，所以不会空转。
	while budget > 0.0 and not _jobs.is_empty():
		var next_index := -1
		var next_left := INF
		for index in _jobs.size():
			if _jobs[index].remaining_seconds < next_left:
				next_left = _jobs[index].remaining_seconds
				next_index = index
		if next_index < 0:
			break
		if next_left > budget:
			# 剩下的时间不够做完任何一份：整体前进，收工
			for job in _jobs:
				job.remaining_seconds -= budget
			break
		for job in _jobs:
			job.remaining_seconds -= next_left
		budget -= next_left
		var done: CraftJob = _jobs[next_index]
		_jobs.remove_at(next_index)
		var recipe := _def(done.recipe_key) as RecipeDef
		if recipe != null:
			_complete_craft(recipe, done.facility_key, done.batches)


func _advance_research(seconds: float) -> void:
	var index := _research_jobs.size() - 1
	while index >= 0:
		var job := _research_jobs[index]
		job.remaining_seconds -= seconds
		if job.remaining_seconds <= 0.0:
			_research_jobs.remove_at(index)
			_complete_research(job)
		index -= 1


# --- 采集点 ---------------------------------------------------------------


## 取一条采集点定义（按采集点键 `game:harvest/farm`）
func get_harvest_def(harvest_key: String) -> HarvestDef:
	return _def(harvest_key) as HarvestDef


## 这条材料能从哪个采集点采到；不在任何池子里返回 null。
## 图鉴的材料页用它把升级按钮挂在该采集点上（按钮改的是采集点等级，不是材料）。
func get_harvest_for_material(material_key: String) -> HarvestDef:
	var item := _def(material_key) as ItemDef
	if item == null or not item.is_material():
		return null
	for def in _defs_of_type("harvest"):
		var harvest := def as HarvestDef
		if harvest != null and item.tags.has(harvest.tag):
			return harvest
	return null


## 桌面上要显示的采集点，按 order 排序（同序按键，保证稳定）
func get_harvest_points() -> Array[HarvestDef]:
	var points: Array[HarvestDef] = []
	for def in _defs_of_type("harvest"):
		var harvest := def as HarvestDef
		if harvest != null:
			points.append(harvest)
	points.sort_custom(func(a: HarvestDef, b: HarvestDef) -> bool:
		if a.order == b.order:
			return a.get_key() < b.get_key()
		return a.order < b.order)
	return points


func get_harvest_level(harvest_key: String) -> int:
	return int(_harvest_levels.get(harvest_key, 1))


## 这条采集点是否已出现在桌面上：设备条件满足，且它挂的解锁信已经读过。
## 空条件 = 开局就有；`unlock_letter` 与设施同语义（决策 2026-10-28 D6）。
func is_harvest_unlocked(harvest: HarvestDef) -> bool:
	if harvest == null:
		return false
	if not harvest.unlock_letter.is_empty() and not _read_letters.has(harvest.unlock_letter):
		return false
	if harvest.unlock_facility.is_empty():
		return true
	return get_facility_level(harvest.unlock_facility) >= harvest.unlock_level


## 当前等级能摇出来的材料（按标签收池，再按 `harvest_tier` 卡等级）
func harvest_pool(harvest: HarvestDef) -> Array[ItemDef]:
	var pool: Array[ItemDef] = []
	if harvest == null or harvest.tag.is_empty():
		return pool
	var level := get_harvest_level(harvest.get_key())
	var data := _data()
	for def in data.get_defs_of_type("item"):
		var item := def as ItemDef
		if item == null or not item.is_material():
			continue
		if not item.tags.has(harvest.tag):
			continue
		if item.harvest_tier > level:
			continue
		pool.append(item)
	pool.sort_custom(func(a: ItemDef, b: ItemDef) -> bool: return a.get_key() < b.get_key())
	return pool


## 冷却剩余秒数（0 = 成熟）
func get_harvest_cooldown_left(harvest_key: String) -> float:
	return maxf(0.0, float(_harvest_cooldowns.get(harvest_key, 0.0)))


func is_harvest_ready(harvest_key: String) -> bool:
	return get_harvest_cooldown_left(harvest_key) <= 0.0


## 某样材料当前的库存上限（采集点累积用）。0 = 不设上限。
## 中间材料最低一档；基础材料按 `harvest_tier` 分常见 / 稀料；免费资源不限。
func get_material_cap(material_key: String) -> int:
	var item := _def(material_key) as ItemDef
	if item == null or not item.is_material():
		return 0
	if item.is_free():
		return 0
	var base := MATERIAL_CAP_INTERMEDIATE
	if item.material_kind == ItemDef.MaterialKind.BASE:
		base = MATERIAL_CAP_RARE if item.harvest_tier >= MATERIAL_RARE_TIER else MATERIAL_CAP_COMMON
	var level := clampi(get_warehouse_level(), 1, WAREHOUSE_MAX_LEVEL)
	return maxi(1, roundi(float(base) * WAREHOUSE_LEVEL_FACTORS[level - 1]))


## 仓库当前等级（设施没装好时按 1 级算，不让容量掉到 0）
func get_warehouse_level() -> int:
	return clampi(maxi(1, get_facility_level(WAREHOUSE_FACILITY)), 1, WAREHOUSE_MAX_LEVEL)


func get_warehouse_cap_common() -> int:
	return maxi(1, roundi(float(MATERIAL_CAP_COMMON) * WAREHOUSE_LEVEL_FACTORS[get_warehouse_level() - 1]))


func get_warehouse_cap_rare() -> int:
	return maxi(1, roundi(float(MATERIAL_CAP_RARE) * WAREHOUSE_LEVEL_FACTORS[get_warehouse_level() - 1]))


func get_warehouse_cap_intermediate() -> int:
	return maxi(1, roundi(float(MATERIAL_CAP_INTERMEDIATE) * WAREHOUSE_LEVEL_FACTORS[get_warehouse_level() - 1]))


## 采集点池子里最高的一档单样上限（只用于概览；逐样判定走 get_material_cap）
func get_harvest_cap(harvest_key: String) -> int:
	var harvest := get_harvest_def(harvest_key)
	if harvest == null:
		return 0
	var highest := 0
	for item in harvest_pool(harvest):
		highest = maxi(highest, get_material_cap(item.get_key()))
	return highest


## 池里每一样都堆到自己的上限了才算满仓——只要还有一样空着，这一下就还能采
func is_harvest_full(harvest_key: String) -> bool:
	var pool := harvest_pool(get_harvest_def(harvest_key))
	if pool.is_empty():
		return true
	for item in pool:
		var cap := get_material_cap(item.get_key())
		if cap <= 0 or get_amount(item.get_key()) < cap:
			return false
	return true


## 现在能不能点这一下：解锁、成熟、没满仓
func can_harvest(harvest_key: String) -> bool:
	var harvest := get_harvest_def(harvest_key)
	if harvest == null or not is_harvest_unlocked(harvest):
		return false
	return is_harvest_ready(harvest_key) and not is_harvest_full(harvest_key)


## 池里随机挑一样还没到上限的材料入库；池子空或全都满了返回空串
func _pick_from_harvest(harvest: HarvestDef) -> String:
	var pool := harvest_pool(harvest)
	var ready: Array[ItemDef] = []
	for item in pool:
		var cap := get_material_cap(item.get_key())
		if cap <= 0 or get_amount(item.get_key()) < cap:
			ready.append(item)
	if ready.is_empty():
		return ""
	var picked := ready[randi() % ready.size()]
	add_item(picked.get_key(), 1)
	return picked.get_key()


## 手动采集：成熟才给，给了就进冷却；冷却中或满仓返回 false。
## 一次给 `yield_at()` 份，每份独立摇一样（所以「采一次地」可能同时拿到洋葱和土豆）。
func harvest(harvest_key: String) -> bool:
	return not harvest_with_result(harvest_key).is_empty()


## 和 harvest() 一样，但把「采到了什么」带回来：材料键 → 份数。
## 一次可能摇出好几样，界面要按品种报，光说「+2」玩家不知道自己拿到了什么。
func harvest_with_result(harvest_key: String) -> Dictionary:
	var harvest := get_harvest_def(harvest_key)
	if harvest == null or not is_harvest_unlocked(harvest):
		return {}
	if not is_harvest_ready(harvest_key) or is_harvest_full(harvest_key):
		return {}
	var level := get_harvest_level(harvest_key)
	var gained: Dictionary = {}
	for _index in harvest.yield_at(level):
		var picked := _pick_from_harvest(harvest)
		if picked.is_empty():
			break
		gained[picked] = int(gained.get(picked, 0)) + 1
	if gained.is_empty():
		return {}
	_harvest_cooldowns[harvest_key] = harvest.cooldown_at(level)
	return gained


## 这一下会给出几份（界面上飘的「+N」用它，不必真的采一次）
func harvest_yield(harvest_key: String) -> int:
	var harvest := get_harvest_def(harvest_key)
	if harvest == null:
		return 0
	return harvest.yield_at(get_harvest_level(harvest_key))


## 采集点升级：铜币 + 这个标签下任意材料自付；满级、钱不够、材料不够都返回 false
func upgrade_harvest(harvest_key: String) -> bool:
	var harvest := get_harvest_def(harvest_key)
	if harvest == null or not is_harvest_unlocked(harvest):
		return false
	var target := get_harvest_level(harvest_key) + 1
	if target > harvest.max_level():
		return false
	var coin_cost := harvest.coin_cost_to(target)
	var item_cost := harvest.item_cost_to(target)
	if coin_cost < 0 or coins < coin_cost:
		return false
	var cost: Array[MaterialStack] = []
	if item_cost > 0:
		var stack := MaterialStack.new()
		stack.by_tag = harvest.tag
		stack.amount = item_cost
		cost.append(stack)
		if not can_consume(cost):
			return false
	if coin_cost > 0:
		add_coins(-coin_cost, "采集点升级")
	if item_cost > 0:
		_consume(cost)
	_harvest_levels[harvest_key] = target
	return true


# --- 库存 -----------------------------------------------------------------


func get_amount(key: String) -> int:
	return int(_stock.get(key, 0))


## 入库并广播（材料与食物通用）；数量一律整数
func add_item(key: String, amount: int) -> void:
	if amount <= 0:
		return
	_add_stock(key, amount)
	_maybe_discover(key)


## 连续产出专用：小数先攒着，攒够 1 才进库存（避免界面上出现 2.7 份材料）
func add_item_float(key: String, amount: float) -> void:
	if amount <= 0.0:
		return
	var whole := int(floor(amount))
	var frac := amount - float(whole)
	if frac > 0.0:
		var total_frac := float(_stock_fraction.get(key, 0.0)) + frac
		var carried := int(floor(total_frac))
		_stock_fraction[key] = total_frac - float(carried)
		whole += carried
	if whole > 0:
		add_item(key, whole)


func _add_stock(key: String, delta: int) -> void:
	var new_amount := get_amount(key) + delta
	_stock[key] = new_amount
	# 库存变了，「手上留 N 份」这类委托的进度可能就过了线
	_tasks_dirty = true
	EventBus.publish(MaterialChangedEvent.new(key, float(new_amount), float(delta)))


## 免费物品（水）不占库存、不扣数量
func _is_free(key: String) -> bool:
	var def := _def(key) as ItemDef
	return def != null and def.is_free()


func can_consume(stacks: Array[MaterialStack], multiplier: int = 1) -> bool:
	var need := maxi(1, multiplier)
	for stack in stacks:
		if stack == null:
			continue
		if stack.by_tag.is_empty() and _is_free(stack.material):
			continue
		if count_for(stack) < stack.amount * need:
			return false
	return true


func _consume(stacks: Array[MaterialStack], multiplier: int = 1) -> void:
	var need := maxi(1, multiplier)
	for stack in stacks:
		if stack == null:
			continue
		if stack.by_tag.is_empty() and _is_free(stack.material):
			continue
		_drain_stack(stack, stack.amount * need)


## 这一份需求手上有多少：指名的看自己，按标签要的看标签成员合计。
## 合计而不是「某一样必须够」——「随便两样蔬菜」本来就可以一根葱 + 一根胡萝卜。
func count_for(stack: MaterialStack) -> int:
	if stack == null:
		return 0
	if stack.by_tag.is_empty():
		return 0 if _is_free(stack.material) else get_amount(stack.material)
	var total := 0
	for key in _tag_member_keys(stack.by_tag):
		if _is_free(key):
			continue
		total += get_amount(key)
	return total


## 扣掉 total 份：指名直接扣；按标签要的从持有量最少的成员开始扣（先清掉零碎的那几格）
func _drain_stack(stack: MaterialStack, total: int) -> void:
	if stack.by_tag.is_empty():
		_add_stock(stack.material, -total)
		return
	var keys := _tag_member_keys(stack.by_tag)
	keys.sort_custom(func(a: String, b: String) -> bool:
		var left := get_amount(a)
		var right := get_amount(b)
		return a < b if left == right else left < right
	)
	var remaining := total
	for key in keys:
		if remaining <= 0:
			break
		var owned := get_amount(key)
		if owned <= 0:
			continue
		var take := mini(owned, remaining)
		_add_stock(key, -take)
		remaining -= take


## 某个标签下的物品键（成员索引在 DataRegistry 里，按 `ItemDef.tags` 现算）
func _tag_member_keys(tag_key: String) -> Array[String]:
	var data := _data()
	return data.tag_member_keys(tag_key) if data != null else []


## 某条定义是否属于某个标签（图鉴筛选走这里，成员由 DataRegistry 灌进 TagRegistry）
func has_tag(key: String, tag_key: String) -> bool:
	var registry := DataRegistry.tag_registry()
	if registry == null:
		return false
	var tag_id := ResourceLocation.from_string(tag_key)
	var entry_id := ResourceLocation.from_string(key)
	if tag_id == null or entry_id == null:
		return false
	return registry.has_entry_in_tag(tag_id, entry_id)


# --- 图鉴 -----------------------------------------------------------------


## 点亮一个图鉴条目；已经点亮过返回 false
func discover(key: String) -> bool:
	if _discovered.has(key):
		return false
	var def := _def(key)
	if def == null:
		return false
	_discovered[key] = true
	_discovery_order.erase(key)
	_discovery_order.append(key)
	_tasks_dirty = true
	EventBus.publish(CatalogDiscoveredEvent.new(key, def.get_type_id()))
	_check_milestones()
	return true


func is_discovered(key: String) -> bool:
	return _discovered.has(key)


## 图鉴已点亮的条目数（信件与世界单独算，见 get_discovered_keys）
func get_discovered_keys() -> Array[String]:
	var keys: Array[String] = []
	for key in _discovered:
		keys.append(String(key))
	keys.sort()
	return keys


## 最近发现的条目键；一条都没发现时返回空串。
## HUD 图鉴卡点进来时靠它决定落哪一页、哪一行（R7.1 反馈 3）。
func get_newest_discovered_key() -> String:
	return _discovery_order.back() if not _discovery_order.is_empty() else ""


## 某条目在发现顺序里的位置；-1 = 还没发现（或旧档还没回填顺序）
func get_discovery_index(key: String) -> int:
	return _discovery_order.find(key)


## 上一次打开图鉴时保存的发现数快照。
## 面板打开时先抓住它再 mark_catalog_seen()，行红点才有「本次之前」的基准。
func get_catalog_seen_count() -> int:
	return _catalog_seen


# --- 引导 -----------------------------------------------------------------


## 引导进行到第几步（0..4；4 = 已走完四步）
func get_tutorial_step() -> int:
	return tutorial_step


func is_tutorial_done() -> bool:
	return tutorial_done


## 完成当前一步，返回新的步数。最后一步完成时置 done（奖励由 Tutorial 系统发，这里只记进度）。
func advance_tutorial() -> int:
	if tutorial_done:
		return tutorial_step
	tutorial_step = clampi(tutorial_step + 1, 0, TUTORIAL_STEP_COUNT)
	if tutorial_step >= TUTORIAL_STEP_COUNT:
		tutorial_done = true
	return tutorial_step


## 跳过引导：立刻记为完成，下次启动不再出现
func skip_tutorial() -> void:
	tutorial_step = TUTORIAL_STEP_COUNT
	tutorial_done = true


func _maybe_discover(key: String) -> void:
	var def := _def(key) as ItemDef
	if def == null:
		return
	# 食物一律进图鉴；材料看 in_catalog（水这类免费资源不进）
	if def.is_food() or def.in_catalog:
		discover(key)


# --- 招牌菜 -----------------------------------------------------------------


## 玩家自选的招牌菜槽位（长度固定为 SIGNATURE_SLOTS；空串 = 自动补位）
func get_signature_slots() -> Array[String]:
	var slots: Array[String] = []
	for i in SIGNATURE_SLOTS:
		slots.append(_signature_slots[i] if i < _signature_slots.size() else "")
	return slots


## 招牌菜被点单时的酬劳加成：一道 ×1.25，之后每多一道再加 0.1（三格写满 ×1.45）。
## 空槽不算——自动补位只是替玩家把便条填满，不跟着加价。
func get_signature_bonus() -> float:
	var filled := 0
	for key in get_signature_slots():
		if not key.is_empty():
			filled += 1
	if filled <= 0:
		return 1.0
	return SIGNATURE_ORDER_BONUS + SIGNATURE_ORDER_BONUS_PER_EXTRA_SLOT * float(filled - 1)


## 手填招牌按菜系叠订单权重：返回值 {主题键: 权重倍率}，只统计非空槽位。
## 同一菜系 1 道 ×1.5、2 道 ×1.8、3 道 ×2.0；没有手填的菜系不在字典里。
func get_signature_theme_boosts() -> Dictionary:
	var counts := {}
	for key in get_signature_slots():
		if key.is_empty():
			continue
		var theme := item_theme_key(key)
		counts[theme] = int(counts.get(theme, 0)) + 1
	var boosts := {}
	for theme in counts:
		boosts[theme] = _signature_theme_boost_for_count(int(counts[theme]))
	return boosts


## 某个菜系当前的招牌权重；没有手填该菜系时返回 1.0
func get_signature_theme_boost(theme_key: String) -> float:
	var boosts := get_signature_theme_boosts()
	return float(boosts.get(theme_key, 1.0))


func _signature_theme_boost_for_count(count: int) -> float:
	if count <= 0:
		return 1.0
	return float(SIGNATURE_THEME_BOOSTS[clampi(count - 1, 0, SIGNATURE_THEME_BOOSTS.size() - 1)])


## 把一道菜放进某个槽位；同一道菜已在别的槽位时先清掉那一格。
## `food_key` 传空串（或无效的菜）= 这一格回到自动补位。
func set_signature_slot(slot: int, food_key: String) -> void:
	if slot < 0 or slot >= SIGNATURE_SLOTS:
		return
	while _signature_slots.size() < SIGNATURE_SLOTS:
		_signature_slots.append("")
	var key := food_key if is_valid_signature(food_key) else ""
	var previous := _signature_slots[slot]
	if not key.is_empty():
		for i in SIGNATURE_SLOTS:
			if i != slot and _signature_slots[i] == key:
				_signature_slots[i] = ""
	_signature_slots[slot] = key
	# 新写/换了一道招牌：下一次补位优先刷这个菜系的一单（可立即补则立即补）。
	if not key.is_empty() and key != previous:
		_signature_pending_theme = item_theme_key(key)
	# 清空或换走后，保底菜系若已没有任何手填招牌，就取消，避免永远悬着。
	if not _signature_pending_theme.is_empty() and not get_signature_theme_boosts().has(_signature_pending_theme):
		_signature_pending_theme = ""
	EventBus.publish(SignatureChangedEvent.new(slot))
	_fill_pending_signature_order()


## 订单板有空位时立刻兑现「下一单优先该菜系」；没空位就留到下一次补位。
func _fill_pending_signature_order() -> void:
	if _signature_pending_theme.is_empty() or _orders.size() >= _order_capacity:
		return
	_append_order()


## 能不能上招牌：已发现、是食物、有卖价（卖价为 0 的菜不替玩家赚钱，也不上招牌）
func is_valid_signature(key: String) -> bool:
	if key.is_empty() or not is_discovered(key):
		return false
	var food := _def(key) as ItemDef
	return food != null and food.is_food() and food.sell_price > 0


## 可上招牌的菜：已发现、有卖价，按卖价降序（同价按 order）
func get_signature_candidates() -> Array[ItemDef]:
	var foods: Array[ItemDef] = []
	for def in _defs_of_type("item"):
		var food := def as ItemDef
		if food == null or not food.is_food() or food.sell_price <= 0:
			continue
		if not is_discovered(food.get_key()):
			continue
		foods.append(food)
	foods.sort_custom(func(a: ItemDef, b: ItemDef) -> bool:
		if a.sell_price == b.sell_price:
			return a.order < b.order
		return a.sell_price > b.sell_price
	)
	return foods


# --- 图鉴里程碑 -----------------------------------------------------------


## 各档位需要多少条目：按当前内容总量算占比，不写死数字（加内容自动跟着走）
func get_milestone_targets() -> Array[int]:
	var total := get_catalog_total()
	var targets: Array[int] = []
	for pct in MILESTONE_PCTS:
		targets.append(int(ceil(float(total) * pct)))
	return targets


## 已经发到第几档（0 = 还没跨过第一档）
func get_milestone_tier() -> int:
	return _milestone_tier


## 条目变化后检查是否跨档。pay = false：只对齐档位、不补发（读档用）。
func _check_milestones(pay := true, announce := true) -> void:
	var targets := get_milestone_targets()
	if targets.is_empty():
		return
	var count := get_catalog_discovered_count()
	while _milestone_tier < targets.size() and count >= targets[_milestone_tier]:
		var tier := _milestone_tier
		_milestone_tier = tier + 1
		var coins_granted := 0
		if pay:
			coins_granted = MILESTONE_COINS[tier]
			add_coins(coins_granted, "图鉴 %d%%" % int(round(MILESTONE_PCTS[tier] * 100.0)))
		if announce:
			EventBus.publish(MilestoneReachedEvent.new(_milestone_tier, targets[tier], coins_granted))


## 读档后对齐档位（不补发铜币，也不弹提示）
func _sync_milestone_tier() -> void:
	_check_milestones(false, false)


# --- 铜币 -----------------------------------------------------------------

func add_coins(amount: int, reason: String) -> void:
	if amount == 0:
		return
	coins += amount
	EventBus.publish(CoinChangedEvent.new(coins, amount, reason))


# --- 制作 -----------------------------------------------------------------


## 这条配方的产出是不是食物（决定能不能批处理、要不要记「首次制作」）
func _is_food_output(recipe: RecipeDef) -> bool:
	var output := _def(recipe.output) as ItemDef
	return output != null and output.is_food()


## 这条配方一次最多能做几份。
## 成品不做批处理（做十杯咖啡是十次操作，不是一次）；中间品只看设备等级：
## Lv1 → 2 份 … Lv4 → 5 份（决策 2026-10-28 D9）。材料种类多不影响份数——
## 旧实现用 8 / inputs.size() 整除，5 种材料的配方会掉回 1 份，那是 bug。
func max_batches(recipe_key: String) -> int:
	var recipe := _def(recipe_key) as RecipeDef
	if recipe == null:
		return 0
	if _is_food_output(recipe):
		# 成品默认不做批处理；少数饮品（浓缩）按设备等级开放，Lv1 仍是 1 份。
		if recipe.allow_batches:
			var batch_level := get_facility_level(recipe.facility) if not recipe.facility.is_empty() else 1
			return clampi(batch_level, 1, BATCH_MAX)
		return 1
	if recipe.inputs.is_empty():
		return 1
	# 手作配方（没有设备）按 Lv1 设备算，也就是一次 2 份——不然「一炉多份」只对有机器的配方成立
	var level := get_facility_level(recipe.facility) if not recipe.facility.is_empty() else 1
	return clampi(level + 1, 1, BATCH_MAX)


## 开始制作（batches > 1 只对中间品配方生效，会被 max_batches 夹住）。
## 产线占满、该设备没有空槽、材料不够、配方不存在都返回 false（不抛错）。
func start_craft(recipe_key: String, batches: int = 1) -> bool:
	var recipe := _def(recipe_key) as RecipeDef
	if recipe == null:
		return false
	if not is_recipe_visible(recipe_key):
		return false
	if not has_free_lane():
		return false
	if not has_free_slot(recipe.facility):
		return false
	var want := clampi(batches, 1, maxi(1, max_batches(recipe_key)))
	if not can_consume(recipe.inputs, want):
		return false
	_consume(recipe.inputs, want)
	var seconds := recipe.duration_seconds * float(want) * BATCH_TIME_FACTOR * get_speed_factor(recipe.facility)
	if seconds <= 0.0:
		_complete_craft(recipe, recipe.facility, want)
		return true
	var job := CraftJob.new()
	job.recipe_key = recipe_key
	job.facility_key = recipe.facility
	job.batches = want
	job.total_seconds = seconds
	job.remaining_seconds = seconds
	_jobs.append(job)
	return true


## 产线条数还够不够再开一个任务（厨房扩建定条数，设备等级定同一台设备能开几个）
func has_free_lane() -> bool:
	return _jobs.size() < get_lane_count()


func get_lane_count() -> int:
	return maxi(1, _kitchen_level)


## 还能不能再开一个该设备。无设备配方 = 手作：手作与厨房共用产线条数
## （第十轮反馈 3：手作也能排满一厨房），所以上限是 get_lane_count() 而不是固定 1。
func has_free_slot(facility_key: String) -> bool:
	var capacity := get_lane_count()
	if not facility_key.is_empty():
		var facility := _def(facility_key) as FacilityDef
		if facility == null:
			return false
		var level := get_facility_level(facility_key)
		if level < 1:
			# 还没到手（等信件添置的设备），一格也开不出来
			return false
		capacity = level
	var used := 0
	for job in _jobs:
		if job.facility_key == facility_key:
			used += 1
	return used < capacity


func get_jobs() -> Array[CraftJob]:
	return _jobs.duplicate()


func _complete_craft(recipe: RecipeDef, facility_key: String, batches: int = 1) -> void:
	# 做过一次，工艺本身也进图鉴
	discover(recipe.get_key())
	var units := maxi(1, batches)
	var primary_amount := units * maxi(1, recipe.output_amount)
	add_item(recipe.output, primary_amount)
	for stack in recipe.extra_outputs:
		if stack == null or stack.material.is_empty():
			continue
		# 副产物按「批」发放，不乘主产物数量（主产物 ×2 不代表副产物也 ×2）
		add_item(stack.material, units * maxi(0, stack.amount))
	var is_food := _is_food_output(recipe)
	var first_time := false
	if is_food:
		first_time = not _crafted_food.has(recipe.output)
		if first_time:
			_crafted_food[recipe.output] = true
			add_coins(COINS_PER_FIRST_FOOD, "首次制作")
		_crafted_food_count[recipe.output] = get_food_crafted_count(recipe.output) + primary_amount
		_tasks_dirty = true
	# 食物与半成品都发「这一炉出来了」；toast 与首次奖励只属于成品食物，
	# 音效则由订阅方对所有产物统一播放（R18 反馈 2）。
	EventBus.publish(CraftCompletedEvent.new(recipe.output, is_food, first_time))
	_refresh_letters()
	_continue_repeat(recipe, units)


## 连续做：刚做完的那份如果正是勾住的那道菜，就再开一份。
## 材料不够、没空位就静默停下（并发不出事件，玩家下次进灶台自会看到灰按钮）。
func _continue_repeat(recipe: RecipeDef, batches: int = 1) -> void:
	if _repeat_depth > 0:
		return
	if _repeat_recipe_key.is_empty() or _repeat_recipe_key != recipe.get_key():
		return
	# 0 秒配方（美式这类）不自动续做：它会立刻完成并再次回到这里，递归没有出口
	if recipe.duration_seconds <= 0.0:
		return
	_repeat_depth += 1
	start_craft(recipe.get_key(), batches)
	_repeat_depth -= 1


## 锁定「连续做」的配方；传空字符串取消
func set_repeat_recipe(recipe_key: String) -> void:
	if recipe_key.is_empty() or _def(recipe_key) is RecipeDef:
		_repeat_recipe_key = recipe_key


func get_repeat_recipe() -> String:
	return _repeat_recipe_key


## 首次制作一份食物奖励多少铜币（界面显示用）
func get_coins_per_first_food() -> int:
	return COINS_PER_FIRST_FOOD


# --- 研究 -----------------------------------------------------------------


## 研究台规则（只应有一份；没配置时返回 null，调用方要容错）
func get_research_rules() -> ResearchDef:
	var data := _data()
	if data == null:
		return null
	return data.get_research_rules()


## 研究台设备键（规则里配的；没有规则时为空）
func get_research_desk_key() -> String:
	var rules := get_research_rules()
	return rules.facility if rules != null else ""


func get_research_desk_level() -> int:
	var key := get_research_desk_key()
	if key.is_empty():
		return 1
	return get_facility_level(key)


func get_research_desk_facility() -> FacilityDef:
	return _def(get_research_desk_key()) as FacilityDef


## 当前等级下失败会烧掉几份
func get_research_burn_count() -> int:
	var rules := get_research_rules()
	if rules == null:
		return 1
	return rules.get_burn_count(get_research_desk_level())


## 当前等级下失败会烧掉多少比例（旧口径，1.0 = 全烧）
func get_research_burn_rate() -> float:
	var rules := get_research_rules()
	if rules == null:
		return 1.0
	return rules.get_burn_rate(get_research_desk_level())


## 这条配方现在能不能在灶台做：不需要研究的直接可见，需要的必须先解锁
func is_recipe_unlocked(recipe_key: String) -> bool:
	var recipe := _def(recipe_key) as RecipeDef
	if recipe == null:
		return false
	if not recipe.needs_research():
		return true
	return _unlocked_recipes.has(recipe_key)


## 主题是否已经到站：空 unlock_letter 的开局就可见，填了的那封信念过才解锁。
## 「信算完成」原计划是「读过 + 信里的任务办妥」，任务系统见 `docs/TODO.md` §P8.2，
## 在它落地之前先只认「读过」。
func is_theme_unlocked(theme_key: String) -> bool:
	var theme := _def(theme_key) as ThemeDef
	if theme == null:
		return true
	if theme.unlock_letter.is_empty():
		return true
	return _read_letters.has(theme.unlock_letter)


## 条目挂在哪个主题上：材料（中间品）与查不到的条目一律算 base
func item_theme_key(item_key: String) -> String:
	var item := _def(item_key) as ItemDef
	if item == null or item.theme.is_empty():
		return ItemDef.DEFAULT_THEME
	return item.theme


## 配方挂在哪个主题上：看它做出来的东西（配方自己没有 theme 字段）
func recipe_theme_key(recipe_key: String) -> String:
	var recipe := _def(recipe_key) as RecipeDef
	if recipe == null:
		return ItemDef.DEFAULT_THEME
	return item_theme_key(recipe.output)


## 这条配方现在该不该出现在玩家眼前：研究已解锁 + 主题已到站
func is_recipe_visible(recipe_key: String) -> bool:
	if not is_recipe_unlocked(recipe_key):
		return false
	return is_theme_unlocked(recipe_theme_key(recipe_key))


## 灶台可见的配方（按 order，再看键，保证顺序稳定）
func get_visible_recipes() -> Array[RecipeDef]:
	var result: Array[RecipeDef] = []
	for def in _defs_of_type("recipe"):
		var recipe := def as RecipeDef
		if recipe != null and is_recipe_visible(recipe.get_key()):
			result.append(recipe)
	result.sort_custom(func(a: RecipeDef, b: RecipeDef) -> bool:
		if a.order != b.order:
			return a.order < b.order
		return a.get_key() < b.get_key()
	)
	return result


## 还没解锁的配方（研究台要试的目标）
func get_pending_recipes() -> Array[RecipeDef]:
	var result: Array[RecipeDef] = []
	for def in _defs_of_type("recipe"):
		var recipe := def as RecipeDef
		if recipe == null or not recipe.needs_research():
			continue
		if _unlocked_recipes.has(recipe.get_key()):
			continue
		# 还没到站的地方，研究台也不该拿它的配方当目标
		if not is_theme_unlocked(recipe_theme_key(recipe.get_key())):
			continue
		result.append(recipe)
	result.sort_custom(func(a: RecipeDef, b: RecipeDef) -> bool:
		if a.order != b.order:
			return a.order < b.order
		return a.get_key() < b.get_key()
	)
	return result


## 研究台的候选材料池：所有待解锁配方的候选并集（去重、排序）。
## 通配输入（「任意一种蔬菜」）在池里只有一个代表键，这里把标签下**每种材料**都并进来；
## 否则玩家手上是番茄而不是豆子时，一个完全合法的组合会被研究台挡掉（第 9 轮反馈 8）。
func get_research_candidates() -> Array[String]:
	var keys := {}
	var wildcard_tags := {}
	for recipe in get_pending_recipes():
		for key in recipe.research_pool:
			keys[key] = true
		for stack in recipe.inputs:
			if stack != null and not stack.by_tag.is_empty():
				wildcard_tags[stack.by_tag] = true
	if not wildcard_tags.is_empty():
		for def in _defs_of_type("item"):
			var item := def as ItemDef
			# 只收材料：标签下的成品菜不进候选池，否则 veg 会混进几十道菜
			if item == null or not item.is_material():
				continue
			for tag in wildcard_tags:
				if item.tags.has(String(tag)):
					keys[item.get_key()] = true
					break
	var result: Array[String] = []
	for key in keys:
		result.append(String(key))
	result.sort()
	return result


## 这块材料能顶哪些「按标签要料」的位置（候选牌的标签章用，反馈 8）。
## 只算还没解开的研究配方：已经知道的配方不再需要研究，标签也就没有解释价值了。
func get_research_wildcard_tags(key: String) -> Array[String]:
	var tags: Array[String] = []
	var def := _def(key) as ItemDef
	if def == null or not def.is_material():
		return tags
	for recipe in get_pending_recipes():
		for stack in recipe.inputs:
			if stack == null or stack.by_tag.is_empty():
				continue
			if not def.tags.has(stack.by_tag):
				continue
			if not tags.has(stack.by_tag):
				tags.append(stack.by_tag)
	tags.sort()
	return tags


func get_research_jobs() -> Array[ResearchJob]:
	return _research_jobs.duplicate()


## 还能不能开一次研究：并行位 = 研究台等级
func has_free_research_slot() -> bool:
	return _research_jobs.size() < maxi(1, get_research_desk_level())


## 组合签名：材料键排序后 `+` 连接（存档与研究记录的键）
static func signature_of(materials: Array) -> String:
	var keys: Array[String] = []
	for key in materials:
		keys.append(String(key))
	keys.sort()
	return "+".join(keys)


## 已试过的组合结论（没有则空字典）
func get_research_record(signature: String) -> Dictionary:
	var record: Dictionary = _researched.get(signature, {})
	return record.duplicate()


## 已经试出结论的组合数
func get_research_record_count() -> int:
	return _researched.size()


## 这条「火候不足」的记录现在能不能重试：设备等级已经达到配方门槛。
## 只对 HEAT 记录成立；失败组合（措手不及/差一味）仍按旧逻辑回放，不重复收学费。
func is_research_retryable(signature: String) -> bool:
	var record := get_research_record(signature)
	if record.is_empty():
		return false
	if int(record.get("outcome", ResearchOutcome.NONE)) != ResearchOutcome.HEAT:
		return false
	var recipe := _def(String(record.get("recipe", ""))) as RecipeDef
	if recipe == null or recipe.research_min_facility_level <= 0:
		return false
	return get_facility_level(recipe.facility) >= recipe.research_min_facility_level


## 同一组合是否已经有一组研究在做：防止「火候够了」之后连点两次扣两份材料。
func has_research_job(signature: String) -> bool:
	for job in _research_jobs:
		if job.signature == signature:
			return true
	return false


## 已经到站的菜里还有没有没试出来的研究菜：桌面研究台卡的「去试试」提示靠它常驻。
## 只算已解锁主题——还没到站的地方不该让这张卡一直亮着（那会让提示失去时间感）。
func has_unresearched_recipes() -> bool:
	return not get_pending_recipes().is_empty()


## 研究台动过没有：试出过任何结论（成功或失败都算）为 true。
## 老存档补引导用——没动过研究台的存档，桌面卡片会给一句提示，不补发信件。
func has_started_research() -> bool:
	return not _researched.is_empty() or not _research_history.is_empty()


## 最近出结果的研究记录，最新的在前，最多 RESEARCH_HISTORY_LIMIT 条。
## 每条：{signature, materials, recipe, outcome, succeeded, burned, seconds}
func get_research_history() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index in range(_research_history.size() - 1, -1, -1):
		out.append(_research_history[index].duplicate(true))
	return out


## 研究台的三步引导看过没有（首次打开时弹一次）
func has_seen_research_guide() -> bool:
	return _research_guide_seen


func mark_research_guide_seen() -> void:
	_research_guide_seen = true


## 设置页「再看一遍」：清掉标志，下次打开研究台会重新弹
func reset_research_guide() -> void:
	_research_guide_seen = false


## 最近出结果的那个组合签名（没有则空串）
func get_last_research_signature() -> String:
	return _last_research_signature


## 把某次研究的结论写成一句人话（面板与提示共用）
func describe_research(signature: String) -> String:
	var record := get_research_record(signature)
	if record.is_empty():
		return I18n.t("ui.research.desc_untried")
	var outcome := int(record.get("outcome", ResearchOutcome.MISMATCH))
	var recipe_key := String(record.get("recipe", ""))
	var recipe := _def(recipe_key) as RecipeDef
	var recipe_name := recipe.localized() if recipe != null else recipe_key
	match outcome:
		ResearchOutcome.NEAR_MISS:
			# 只差一样时把缺的那一样念出来：按标签要的念「任意蔬菜」，玩家才知道
			# 补同类材料也算数（反馈 8：以前只说「还差一样」，通配信息被吞掉了）。
			var missing := _missing_input_label(recipe, signature)
			if missing.is_empty():
				return I18n.t("ui.research.desc_near_miss", [recipe_name])
			return I18n.t("ui.research.desc_near_miss_missing", [recipe_name, missing])
		ResearchOutcome.HEAT:
			var needed := 0
			var facility_name := I18n.t("ui.research.desc_facility")
			if recipe != null:
				needed = recipe.research_min_facility_level
				var facility := _def(recipe.facility)
				if facility != null:
					facility_name = facility.localized()
			# 升级后旧记录自动改口：历史行与台面提示都读这里，不用迁移存档。
			if recipe != null and is_research_retryable(signature):
				return I18n.t("ui.research.desc_heat_ready", [facility_name, get_facility_level(recipe.facility)])
			return I18n.t("ui.research.desc_heat", [facility_name, needed])
	if recipe != null and is_recipe_unlocked(recipe_key):
		return I18n.t("ui.research.desc_success", [recipe_name])
	return I18n.t("ui.research.desc_mismatch")


## near miss 缺的那一样怎么念。具名输入念材料名，按标签要的念标签译文；
## 从组合签名反推玩家已经放了什么，不改研究记录结构（老存档里的结论照样念得出来）。
func _missing_input_label(recipe: RecipeDef, signature: String) -> String:
	if recipe == null or signature.is_empty():
		return ""
	var provided := {}
	for key in signature.split("+"):
		provided[String(key)] = true
	for stack in recipe.inputs:
		if stack == null:
			continue
		if not stack.material.is_empty():
			if not provided.has(stack.material):
				return _stack_label(stack)
			continue
		if stack.by_tag.is_empty():
			continue
		var matched := false
		for key in provided:
			var item := _def(String(key)) as ItemDef
			if item != null and item.tags.has(stack.by_tag):
				matched = true
				break
		if not matched:
			return _stack_label(stack)
	return ""


## 一份配方输入怎么念：指名的念物品名，按标签要的念标签名（与面板上的 stack_name 一致）
func _stack_label(stack: MaterialStack) -> String:
	if not stack.by_tag.is_empty():
		var tag := _def(stack.by_tag) as TagDef
		return tag.localized() if tag != null else stack.by_tag
	var item := _def(stack.material) as ItemDef
	return item.localized() if item != null else stack.material


## 判定一组材料会走到哪个结论。不消耗材料、不推进时间，界面用它做预告。
## 返回 {outcome, recipe_key, needed_level, seconds, succeeded}
func evaluate_research(materials: Array) -> Dictionary:
	var rules := get_research_rules()
	var default_seconds := rules.default_seconds if rules != null else 2.0
	var selection := {}
	for key in materials:
		selection[String(key)] = true
	var near_miss: RecipeDef = null
	for recipe in get_pending_recipes():
		if _recipe_matches(recipe, selection):
			var needed := recipe.research_min_facility_level
			if needed > 0 and get_facility_level(recipe.facility) < needed:
				return {
					"outcome": ResearchOutcome.HEAT,
					"recipe_key": recipe.get_key(),
					"needed_level": needed,
					"seconds": _research_seconds(recipe),
					"succeeded": false,
				}
			return {
				"outcome": ResearchOutcome.NONE,
				"recipe_key": recipe.get_key(),
				"needed_level": 0,
				"seconds": _research_seconds(recipe),
				"succeeded": true,
			}
		if near_miss == null and _recipe_matches_without_one(recipe, selection):
			near_miss = recipe
	if near_miss != null:
		return {
			"outcome": ResearchOutcome.NEAR_MISS,
			"recipe_key": near_miss.get_key(),
			"needed_level": 0,
			"seconds": _research_seconds(near_miss),
			"succeeded": false,
		}
	return {
		"outcome": ResearchOutcome.MISMATCH,
		"recipe_key": "",
		"needed_level": 0,
		"seconds": default_seconds,
		"succeeded": false,
	}


## 放 2–4 样材料进研究台。数量超限、材料不在候选池、手头不够、没空位都返回 false。
## 试过的组合不扣材料，直接回放上次结论（直接返回 true）。
func start_research(materials: Array) -> bool:
	var rules := get_research_rules()
	if rules == null:
		return false
	var keys := _normalized_materials(materials)
	if keys.size() < 2 or keys.size() > 4:
		return false
	var candidates := get_research_candidates()
	for key in keys:
		if not candidates.has(key):
			return false
	var signature := signature_of(keys)
	# 已经试过的组合直接回放结论；只有「火候不足且设备已达标」是例外——
	# 旧结论不再作数，要继续走扣料与计时，成功后覆盖记录。
	if _researched.has(signature) and not is_research_retryable(signature):
		var record: Dictionary = _researched[signature]
		var record_recipe := String(record.get("recipe", ""))
		EventBus.publish(ResearchCompletedEvent.new(
			signature,
			int(record.get("outcome", ResearchOutcome.MISMATCH)),
			record_recipe,
			not record_recipe.is_empty() and is_recipe_unlocked(record_recipe),
			[]))
		return true
	if has_research_job(signature):
		return false
	if not has_free_research_slot():
		return false
	for key in keys:
		if _is_free(key):
			continue
		if get_amount(key) + EPSILON < 1.0:
			return false
	var chance := rules.charge_chance
	var charged := {}
	for key in keys:
		if _is_free(key):
			continue
		# 每样一定扣 1 份；另有 charge_chance 的概率再扣 1 份（手头不够就只扣 1 份）
		var take := 1
		if _rng.randf() < chance and get_amount(key) >= 2.0:
			take = 2
		charged[key] = take
	var verdict := evaluate_research(keys)
	var job := ResearchJob.new()
	job.signature = signature
	job.materials = keys
	job.recipe_key = String(verdict.get("recipe_key", ""))
	job.outcome = int(verdict.get("outcome", ResearchOutcome.MISMATCH))
	job.succeeded = bool(verdict.get("succeeded", false))
	job.total_seconds = maxf(float(verdict.get("seconds", rules.default_seconds)), 0.0)
	job.remaining_seconds = job.total_seconds
	job.charged = charged.duplicate()
	# 先按「可能多扣」全额扣掉，结束时按固定份数烧毁、其余返还 —— 中途关窗口也付过账了
	for key in charged:
		_add_stock(String(key), -float(charged[key]))
	if job.total_seconds <= 0.0:
		_complete_research(job)
		return true
	_research_jobs.append(job)
	return true


## 取消一次研究（材料全退）
func cancel_research(signature: String) -> bool:
	for index in range(_research_jobs.size() - 1, -1, -1):
		var job := _research_jobs[index]
		if job.signature != signature:
			continue
		_research_jobs.remove_at(index)
		var paid := job.charged if not job.charged.is_empty() else _flat_charge(job.materials)
		for key in paid:
			if not _is_free(String(key)):
				add_item(String(key), float(paid[key]))
		return true
	return false


func _complete_research(job: ResearchJob) -> void:
	var paid := job.charged if not job.charged.is_empty() else _flat_charge(job.materials)
	var burned: Array[String] = []
	var refund: Dictionary = {}
	if job.succeeded:
		var recipe := _def(job.recipe_key) as RecipeDef
		if recipe != null:
			_unlock_recipe(recipe)
		# 成功：放进去的都算学费，不退
	else:
		# 失败：按「份」烧掉固定的数量，剩下退回
		var burn_count := get_research_burn_count()
		var pool: Array[String] = []
		var keys: Array[String] = []
		for key in paid:
			keys.append(String(key))
		keys.sort()
		for key in keys:
			for index in range(int(paid[key])):
				pool.append(key)
		for index in range(mini(burn_count, pool.size())):
			burned.append(pool[index])
		for key in keys:
			var burned_here := burned.count(key)
			var left := int(paid[key]) - burned_here
			if left > 0:
				refund[key] = left
	for key in refund:
		if not _is_free(String(key)):
			add_item(String(key), float(refund[key]))
	_researched[job.signature] = {
		"outcome": job.outcome,
		"recipe": job.recipe_key,
		"burned": burned.duplicate(),
	}
	_research_history.append({
		"signature": job.signature,
		"materials": job.materials.duplicate(),
		"recipe": job.recipe_key,
		"outcome": job.outcome,
		"succeeded": job.succeeded,
		"burned": burned.duplicate(),
		"seconds": job.total_seconds,
	})
	while _research_history.size() > RESEARCH_HISTORY_LIMIT:
		_research_history.pop_front()
	_last_research_signature = job.signature
	EventBus.publish(ResearchCompletedEvent.new(
		job.signature, job.outcome, job.recipe_key, job.succeeded, burned.duplicate()
	))
	# 研究也能办委托（第六轮：研究出拿铁）：这次成功要立刻被待办扫到
	_tasks_dirty = true


## 解锁配方：进图鉴「工艺」页、灶台可见、发事件
func _unlock_recipe(recipe: RecipeDef) -> void:
	_unlocked_recipes[recipe.get_key()] = true
	discover(recipe.get_key())
	EventBus.publish(RecipeUnlockedEvent.new(recipe.get_key()))


func _research_seconds(recipe: RecipeDef) -> float:
	# 0 秒配方（美式）在研究台上保底 1 秒，否则结果一闪而过读不到
	return maxf(recipe.duration_seconds, 1.0)


## 给测试固定试错的随机种子（0 = 恢复随机）
## 固定随机种子（0 = 恢复真随机）。研究与订单抽选共用同一个随机源，测试靠它取确定性。
func set_random_seed(value: int) -> void:
	if value == 0:
		_rng.randomize()
	else:
		_rng.seed = value


## 兼容旧名字：研究测试用它固定随机源
func set_research_seed(value: int) -> void:
	set_random_seed(value)


## 每样各 1 份的扣款表（老存档没有 charged 字段时用）
static func _flat_charge(materials: Array) -> Dictionary:
	var paid := {}
	for key in materials:
		paid[String(key)] = 1
	return paid


func _normalized_materials(materials: Array) -> Array[String]:
	var keys: Array[String] = []
	for key in materials:
		var text := String(key)
		if text.is_empty() or keys.has(text):
			continue
		keys.append(text)
	keys.sort()
	return keys


static func _same_key_set(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key):
			return false
	return true


static func _is_subset(subset: Dictionary, superset: Dictionary) -> bool:
	for key in subset:
		if not superset.has(key):
			return false
	return true


## 一组研究材料是否正好对应这条配方的输入。
## 具名输入要精确命中；by_tag 输入允许该标签下任意一种材料（与合成一致）。
func _recipe_matches(recipe: RecipeDef, selection: Dictionary) -> bool:
	if recipe == null or recipe.inputs.size() != selection.size():
		return false
	return _match_inputs_at(recipe.inputs, 0, selection.duplicate())


## 递归匹配输入：每一步消耗一个剩余材料，by_tag 输入在标签成员里挑一个。
## 输入最多 4 样，分支很小，回溯不会成为热点。
func _match_inputs_at(inputs: Array, index: int, remaining: Dictionary) -> bool:
	if index >= inputs.size():
		return remaining.is_empty()
	var stack = inputs[index]
	if stack == null:
		return false
	if not stack.material.is_empty():
		if not remaining.has(stack.material):
			return false
		var next := remaining.duplicate()
		next.erase(stack.material)
		return _match_inputs_at(inputs, index + 1, next)
	if stack.by_tag.is_empty():
		return false
	for key in remaining:
		var item := _def(String(key)) as ItemDef
		if item == null or not item.tags.has(stack.by_tag):
			continue
		var next := remaining.duplicate()
		next.erase(key)
		if _match_inputs_at(inputs, index + 1, next):
			return true
	return false


## 选择比配方少一样、且正好匹配「任意缺掉一个输入」的其余输入（near miss 提示）。
func _recipe_matches_without_one(recipe: RecipeDef, selection: Dictionary) -> bool:
	if recipe == null or recipe.inputs.size() < 2:
		return false
	if selection.size() != recipe.inputs.size() - 1:
		return false
	for skip in range(recipe.inputs.size()):
		var rest: Array = []
		for i in range(recipe.inputs.size()):
			if i != skip:
				rest.append(recipe.inputs[i])
		if _match_inputs_at(rest, 0, selection.duplicate()):
			return true
	return false


# --- 设备 -----------------------------------------------------------------


func get_facility_level(facility_key: String) -> int:
	# 0 级 = 还没到手（等信件添置的设备）；桌上的设备开局就是 1 级
	return int(_facility_levels.get(facility_key, 0))


## 这个设备现在能不能用：手作（空键）永远可以，有设备的看够不够 1 级。
## 合成表判断「现在能不能做」必须连它一起看——冰箱还没到，冰块就不该算可做。
func is_facility_ready(facility_key: String) -> bool:
	if facility_key.is_empty():
		return true
	return get_facility_level(facility_key) >= 1


## 设备对耗时的乘数（1 级 = 1.0，每级更快）
func get_speed_factor(facility_key: String) -> float:
	if facility_key.is_empty():
		return 1.0
	var facility := _def(facility_key) as FacilityDef
	if facility == null:
		return 1.0
	return maxf(facility.get_speed_factor(get_facility_level(facility_key)), 0.01)


## 升级设备：等级上限、铜币、材料任一不满足返回 false
func upgrade_facility(facility_key: String) -> bool:
	var facility := _def(facility_key) as FacilityDef
	if facility == null:
		return false
	var level := get_facility_level(facility_key)
	if level < 1:
		# 0 级是「还没到手」，不是可升级的低等级
		return false
	if level >= facility.max_level:
		return false
	var upgrade := facility.get_upgrade(level + 1)
	if upgrade == null:
		return false
	if coins < upgrade.coin_cost:
		return false
	if not can_consume(upgrade.materials):
		return false
	add_coins(-upgrade.coin_cost, "设备升级")
	_consume(upgrade.materials)
	_facility_levels[facility_key] = level + 1
	EventBus.publish(FacilityUpgradedEvent.new(facility_key, level + 1))
	return true


# --- 厨房扩建（产线） ------------------------------------------------------


func get_kitchen_level() -> int:
	return _kitchen_level


## 升到下一级要多少铜币；满级返回 -1
func get_kitchen_upgrade_cost() -> int:
	if _kitchen_level >= KITCHEN_MAX_LEVEL:
		return -1
	return int(KITCHEN_COSTS[clampi(_kitchen_level - 1, 0, KITCHEN_COSTS.size() - 1)])


func can_upgrade_kitchen() -> bool:
	var cost := get_kitchen_upgrade_cost()
	return cost >= 0 and coins >= cost


## 扩一条产线：只花铜币（设备升级才要材料），这样两条升级轴的代价不重叠
func upgrade_kitchen() -> bool:
	if not can_upgrade_kitchen():
		return false
	add_coins(-get_kitchen_upgrade_cost(), "厨房扩建")
	_kitchen_level += 1
	EventBus.publish(KitchenUpgradedEvent.new(_kitchen_level))
	return true


# --- 信件 -----------------------------------------------------------------


## 按 order 顺序解锁：遇到第一封条件不满足的就停下，后面的不会越过它先解锁
func _refresh_letters() -> void:
	for letter in _sorted_letters():
		var key := letter.get_key()
		if _unlocked_letters.has(key):
			continue
		if not _letter_condition_met(letter):
			break
		_unlocked_letters.append(key)
		# 走 discover()：信件本身也是图鉴条目，点亮时要算进里程碑
		discover(key)
		EventBus.publish(LetterUnlockedEvent.new(key, letter.localized(&"title")))
		if letter.unlocks_offline:
			offline_unlocked = true


func _letter_condition_met(letter: LetterDef) -> bool:
	var base_met := false
	match letter.condition:
		LetterDef.Condition.IMMEDIATE:
			base_met = true
		LetterDef.Condition.AFTER_LETTER:
			base_met = _read_letters.has(letter.condition_ref)
		LetterDef.Condition.FOOD_CRAFTED:
			base_met = _crafted_food.has(letter.condition_ref)
		LetterDef.Condition.CATALOG_COUNT:
			base_met = get_catalog_discovered_count() >= get_catalog_target_for(letter)
		LetterDef.Condition.TASK_COMPLETED:
			base_met = _completed_tasks.has(letter.condition_ref)
	if not base_met:
		return false
	# 次级条件：站间门禁要求「读完上一封 + 图鉴 ≥ N」，两者都满足才放行。
	if letter.catalog_min > 0 and get_catalog_discovered_count() < letter.catalog_min:
		return false
	# 上一封带「要亲手交付」的委托时，先办妥再放行下一封（R14 反馈 3）。
	# 订单/研究是隐式委托，不拦；否则读信后下一封会立刻冒出来。
	if get_task_blocking_letter(letter) != null:
		return false
	return true


## 下一封被上一封的显式委托挡住时返回那封信；否则 null。信箱页也用它解释在等什么。
func get_task_blocking_letter(letter: LetterDef) -> LetterDef:
	var previous := _previous_letter(letter)
	if previous != null and previous.has_task() and is_task_hand_in(previous):
		if not _completed_tasks.has(previous.get_key()):
			return previous
	return null


## 按 order 找上一封信；没有就返回 null。
func _previous_letter(letter: LetterDef) -> LetterDef:
	var previous: LetterDef = null
	for def in _defs_of_type("letter"):
		var candidate := def as LetterDef
		if candidate == null or candidate.order >= letter.order:
			continue
		if previous == null or candidate.order > previous.order:
			previous = candidate
	return previous


## 读信即收下。带委托的信读到这里就自动进待办（第四轮反馈：不必再点一下
## 「接下这件事」）；已经读过、但老档里没接下的委托，再打开时也补上。
func mark_letter_read(letter_key: String) -> bool:
	if not _unlocked_letters.has(letter_key):
		return false
	var first_read := not _read_letters.has(letter_key)
	if first_read:
		_read_letters[letter_key] = true
		_grant_letter_rewards(_def(letter_key) as LetterDef)
		_unlock_facilities_for(letter_key)
		_unlock_world_for(letter_key)
	# 先把委托收下，再刷新信件：上一封带显式委托时，刷新才知道它还没交付。
	var letter := _def(letter_key) as LetterDef
	if letter != null and letter.has_task():
		accept_task(letter_key)
	_refresh_letters()
	if first_read:
		# 已读不改变图鉴收录，但会改变未读数（以及可能解锁下一封），HUD 红点靠它复位
		EventBus.publish(LetterReadEvent.new(letter_key))
	return true


## 信里说「有台柜子搬进来了」，设备这才进厨房：从 0 级补到 1 级并收进图鉴。
func _unlock_facilities_for(letter_key: String) -> void:
	for def in _defs_of_type("facility"):
		var facility := def as FacilityDef
		if facility == null or facility.unlock_letter != letter_key:
			continue
		if get_facility_level(facility.get_key()) >= 1:
			continue
		_facility_levels[facility.get_key()] = 1
		discover(facility.get_key())


## 信里写到「车窗外原来是这里」，沿途的世界条目这才收进图鉴。
func _unlock_world_for(letter_key: String) -> void:
	for def in _defs_of_type("world"):
		var world := def as WorldDef
		if world == null or world.unlock_letter != letter_key:
			continue
		if _discovered.has(world.get_key()):
			continue
		discover(world.get_key())


## 信里的东西在读信时收下（解锁不等于收到）。重复调用不会重复发放。
func _grant_letter_rewards(letter: LetterDef) -> void:
	if letter == null:
		return
	for stack in letter.rewards:
		if stack == null:
			continue
		_grant_stack(stack)
	if letter.reward_coins > 0:
		add_coins(letter.reward_coins, "信件：%s" % letter.title)


## 发一份东西：指名的直接发；按标签要的发标签里键最小的那一样。
## 发货必须落成具体物品——存档里只认键，不能存「一堆蔬菜里的某一堆」。
func _grant_stack(stack: MaterialStack) -> void:
	if stack == null:
		return
	if stack.by_tag.is_empty():
		add_item(stack.material, stack.amount)
		return
	var keys := _tag_member_keys(stack.by_tag)
	if keys.is_empty():
		push_warning("[GameState] %s 底下没有任何物品，奖励发放跳过" % stack.by_tag)
		return
	add_item(keys[0], stack.amount)


func get_unlocked_letters() -> Array[String]:
	return _unlocked_letters.duplicate()


## 按顺序第一封还没寄到的信：信箱页脚拿它说清「下一封在等什么」。
## 信件是按 order 逐封放行的，所以这一封的条件就是玩家当前真正的卡点。
func get_next_locked_letter() -> LetterDef:
	for def in _sorted_letters():
		var letter := def as LetterDef
		if letter != null and not _unlocked_letters.has(letter.get_key()):
			return letter
	return null


## 图鉴进度：已收录条目数（只算 get_catalog_keys() 收录的范围）
func get_catalog_discovered_count() -> int:
	var data := _data()
	if data == null:
		return _discovered.size()
	var count := 0
	for key in data.get_catalog_keys():
		if _discovered.has(key):
			count += 1
	return count


## 图鉴收录总数
func get_catalog_total() -> int:
	var data := _data()
	if data == null:
		return 0
	return data.get_catalog_keys().size()


## 结局门槛：按当时图鉴总量算比例，内容追加后自动往后挪。
func get_ending_catalog_target() -> int:
	return int(round(float(get_catalog_total()) * ENDING_CATALOG_RATIO))


## 某封图鉴门槛信实际要多少条：结局信走比例，其余走资源里写的数。
func get_catalog_target_for(letter: LetterDef) -> int:
	if letter != null and letter.get_key() == ENDING_LETTER_KEY:
		return get_ending_catalog_target()
	return letter.condition_value if letter != null else 0


## 图鉴顶部「还差多少」的锚点：下一封还没读的图鉴门槛信。
## 同时覆盖 CATALOG_COUNT 主条件和 catalog_min 次级条件；全部读完返回 0。
## 门槛跟着信的阅读状态走，所以读信本身就会让提示往前走一格。
func get_next_catalog_target() -> int:
	for letter in _sorted_letters():
		var letter_def := letter as LetterDef
		if letter_def == null:
			continue
		if _read_letters.has(letter.get_key()):
			continue
		var target := 0
		if letter_def.condition == LetterDef.Condition.CATALOG_COUNT:
			target = get_catalog_target_for(letter_def)
		target = maxi(target, letter_def.catalog_min)
		if target > 0:
			return target
	return 0


## 图鉴里有几条新发现是玩家还没打开看过的（HUD 图鉴红点用）
func get_catalog_new_count() -> int:
	return maxi(0, get_catalog_discovered_count() - _catalog_seen)


## 上次打开图鉴之后新发现、且在图鉴收录范围内的条目键（列表行红点用）。
## 用发现顺序从新到旧数够 new_count 条：比起「索引 >= 已看数」更稳——
## 已看数是收录范围内的计数，发现顺序里还可能夹着不收录的条目。
func get_new_catalog_keys() -> Array[String]:
	var out: Array[String] = []
	var new_count := get_catalog_new_count()
	if new_count <= 0:
		return out
	var data := _data()
	if data == null:
		return out
	var cataloged: Dictionary = {}
	for key in data.get_catalog_keys():
		cataloged[key] = true
	for index in range(_discovery_order.size() - 1, -1, -1):
		var key := _discovery_order[index]
		if not cataloged.has(key):
			continue
		out.append(key)
		if out.size() >= new_count:
			break
	return out


## 玩家打开过图鉴：把「新的」清掉，红点随之收起
func mark_catalog_seen() -> void:
	_catalog_seen = get_catalog_discovered_count()
	EventBus.publish(CatalogSeenEvent.new())


## 已读信件数（引导第一步「读第一封信」用）
func get_read_letter_count() -> int:
	return _read_letters.size()


## 商人在读完杂货商人的信后开张（导出状态，不新增存档键；旧档按已读信自动兼容）
func is_merchant_unlocked() -> bool:
	return _read_letters.has(MERCHANT_UNLOCK_LETTER)


## 第九封「离开前」读完后，订单板才摆上桌；解锁前 HUD 不显示订单入口
func is_orders_unlocked() -> bool:
	return _read_letters.has(ORDERS_UNLOCK_LETTER)


## 有没有亲手做出过一道成品菜（引导第三步「做第一道菜」用）
func has_crafted_any_food() -> bool:
	return not _crafted_food.is_empty()


## 未读信件数（HUD 红点用）
func get_unread_letter_count() -> int:
	var count := 0
	for key in _unlocked_letters:
		if not _read_letters.has(key):
			count += 1
	return count


func is_letter_read(letter_key: String) -> bool:
	return _read_letters.has(letter_key)


# --- 信件委托 -------------------------------------------------------------


## 这道菜累计做过几份（委托按份数算进度；没做过返回 0）
func get_food_crafted_count(food_key: String) -> int:
	return int(_crafted_food_count.get(food_key, 0))


## 这个主题下已经做过几道菜（同一道做十次只算一道）
func get_theme_crafted_count(theme_key: String) -> int:
	var count := 0
	for key in _crafted_food:
		if item_theme_key(String(key)) == theme_key:
			count += 1
	return count


## 这个标签下已经做过几道菜（同一道做十次只算一道）
func get_tag_crafted_count(tag_key: String) -> int:
	var count := 0
	for key in _crafted_food:
		var item := _def(String(key)) as ItemDef
		if item != null and item.tags.has(tag_key):
			count += 1
	return count


## 还没办妥的委托数（HUD 角标用）
func get_open_task_count() -> int:
	return maxi(0, _accepted_tasks.size() - _completed_tasks.size())


func is_task_accepted(letter_key: String) -> bool:
	return _accepted_tasks.has(letter_key)


func is_task_completed(letter_key: String) -> bool:
	return _completed_tasks.has(letter_key)


## 收下这封信的委托：得先读过信，且信里确实有事要办。
## 读信时由 mark_letter_read() 自动调用（第四轮反馈），这里是唯一的状态入口。
func accept_task(letter_key: String) -> bool:
	var letter := _def(letter_key) as LetterDef
	if letter == null or not letter.has_task():
		return false
	if not _read_letters.has(letter_key):
		return false
	if _accepted_tasks.has(letter_key) or _completed_tasks.has(letter_key):
		return false
	_accepted_tasks.append(letter_key)
	# 物品型委托按「手上有没有」推进；主题/标签按全局累计推进，都不设底数。
	# 主题/标签若冻结接任务瞬间的历史值，玩家先把菜做完再读信就会永远 0 进度。
	if _is_stock_task(letter) or _is_cumulative_task(letter):
		_task_baseline.erase(letter_key)
	else:
		_task_baseline[letter_key] = _task_raw_progress(letter)
	EventBus.publish(TaskAcceptedEvent.new(letter_key))
	return true


## 这件委托要不要玩家亲手交付。订单与研究是隐式的：达标就自动办妥。
func is_task_hand_in(letter: LetterDef) -> bool:
	if letter == null or not letter.has_task():
		return false
	var goal := letter.task_goal
	return (
		goal == LetterDef.TaskGoal.CRAFT_FOOD
		or goal == LetterDef.TaskGoal.CRAFT_THEME
		or goal == LetterDef.TaskGoal.COLLECT
		or goal == LetterDef.TaskGoal.CATALOG_COUNT
		or goal == LetterDef.TaskGoal.CRAFT_TAG
	)


func _is_stock_task(letter: LetterDef) -> bool:
	var goal := letter.task_goal
	return goal == LetterDef.TaskGoal.CRAFT_FOOD or goal == LetterDef.TaskGoal.COLLECT


## 主题/标签委托按「全局累计做过几道」算，不按接任务后的增量。
## 这两类目标统计的是历史收藏，接任务前已经做过的菜本来就该算数。
func _is_cumulative_task(letter: LetterDef) -> bool:
	if letter == null:
		return false
	var goal := letter.task_goal
	return goal == LetterDef.TaskGoal.CRAFT_THEME or goal == LetterDef.TaskGoal.CRAFT_TAG


## 交付还要交出几份：物品型委托整份交付。
func get_task_delivery_need(letter: LetterDef) -> int:
	if letter == null or not _is_stock_task(letter):
		return 0
	return letter.task_target()


## 现在能不能点「交付 / 确认完成」。隐式委托永远返回 false。
func can_deliver_task(letter_key: String) -> bool:
	var letter := _def(letter_key) as LetterDef
	if letter == null or not letter.has_task():
		return false
	if not _accepted_tasks.has(letter_key) or _completed_tasks.has(letter_key):
		return false
	if not is_task_hand_in(letter):
		return false
	if _is_stock_task(letter):
		var have := get_task_progress(letter).x
		var need := get_task_delivery_need(letter)
		return have >= letter.task_target() and get_amount(letter.task_ref) >= need
	return get_task_progress(letter).x >= letter.task_target()


## 把物品交出去并办妥。返回 false 表示条件不够（界面据此禁用按钮）。
func deliver_task(letter_key: String) -> bool:
	if not can_deliver_task(letter_key):
		return false
	var letter := _def(letter_key) as LetterDef
	if _is_stock_task(letter):
		var need := get_task_delivery_need(letter)
		if need > 0:
			_add_stock(letter.task_ref, -need)
	_complete_task(letter)
	return true


## 待办里所有带委托的信，按信的 order 排（办妥的也在里面，由界面自己分栏）
func get_task_letters() -> Array[LetterDef]:
	var result: Array[LetterDef] = []
	for letter_key in _accepted_tasks:
		var letter := _def(letter_key) as LetterDef
		if letter != null and letter.has_task():
			result.append(letter)
	result.sort_custom(func(a: LetterDef, b: LetterDef) -> bool:
		if a.order != b.order:
			return a.order < b.order
		return a.get_key() < b.get_key()
	)
	return result


## 还没办妥、目标是「做成某道菜」的委托，对应的配方键。
## 灶台用它给那张卡打「委托」标记：咖啡教学里告诉玩家先做哪一杯（R7.3 反馈 21）。
func get_active_task_recipe_keys() -> Array[String]:
	var out: Array[String] = []
	for letter in get_task_letters():
		if _completed_tasks.has(letter.get_key()):
			continue
		if letter.task_goal != LetterDef.TaskGoal.CRAFT_FOOD:
			continue
		for recipe_key in recipes_producing(letter.task_ref):
			if not is_recipe_visible(recipe_key):
				continue
			if not out.has(recipe_key):
				out.append(recipe_key)
			break
	return out


## 一件委托的进度：(当前, 目标)。办妥之后当前值直接给目标值，免得界面显示 9/10。
func get_task_progress(letter: LetterDef) -> Vector2i:
	if letter == null or not letter.has_task():
		return Vector2i.ZERO
	var target := letter.task_target()
	var key := letter.get_key()
	if _completed_tasks.has(key):
		return Vector2i(target, target)
	var current := 0
	if _is_stock_task(letter):
		# 物品型：手上凑到多少算多少，交出去才真正完成。
		current = get_amount(letter.task_ref)
	elif letter.task_goal == LetterDef.TaskGoal.CATALOG_COUNT or _is_cumulative_task(letter):
		current = _task_raw_progress(letter)
	else:
		current = maxi(0, _task_raw_progress(letter) - int(_task_baseline.get(key, 0)))
	return Vector2i(clampi(current, 0, target), target)


## 该类目标的累计原值（不做基线扣减）：图鉴数、订单数这些从开局起算的量
func _task_raw_progress(letter: LetterDef) -> int:
	match letter.task_goal:
		LetterDef.TaskGoal.CRAFT_FOOD:
			return get_food_crafted_count(letter.task_ref)
		LetterDef.TaskGoal.CRAFT_THEME:
			return get_theme_crafted_count(letter.task_ref)
		LetterDef.TaskGoal.CRAFT_TAG:
			return get_tag_crafted_count(letter.task_ref)
		LetterDef.TaskGoal.COLLECT:
			return get_amount(letter.task_ref)
		LetterDef.TaskGoal.CATALOG_COUNT:
			return get_catalog_discovered_count()
		LetterDef.TaskGoal.DELIVER_ORDER:
			return _orders_completed
		LetterDef.TaskGoal.RESEARCH_RECIPE:
			# 配方只能靠研究解锁，所以「解锁了」就是「研究出来了」。
			# 用解锁态而不是研究记录，是为了让旧存档里早已解锁的配方也算数。
			return 1 if is_recipe_unlocked(letter.task_ref) else 0
	return 0


## 每 tick 复查待办：只在真有东西变化过时才扫（做菜 / 库存 / 图鉴 / 订单）。
## 不每帧硬扫是因为图鉴计数要遍历 600 多条，而绝大多数 tick 什么也没发生。
func _advance_tasks() -> void:
	if not _tasks_dirty:
		return
	_tasks_dirty = false
	if _accepted_tasks.is_empty():
		return
	for letter_key in _accepted_tasks:
		if _completed_tasks.has(letter_key):
			continue
		var letter := _def(letter_key) as LetterDef
		if letter == null or not letter.has_task():
			continue
		# 订单与研究是隐式委托：达标即办妥。物品与主题要玩家亲手交付/确认。
		if is_task_hand_in(letter):
			continue
		if get_task_progress(letter).x >= letter.task_target():
			_complete_task(letter)


## 办妥一件委托：发报酬、留档、广播一句。报酬只发一次（已完成的不再进这里）。
func _complete_task(letter: LetterDef) -> void:
	var letter_key := letter.get_key()
	if _completed_tasks.has(letter_key):
		return
	_completed_tasks[letter_key] = true
	if letter.task_reward_coins > 0:
		add_coins(letter.task_reward_coins, "委托：%s" % letter.localized(&"task_title"))
	for stack in letter.task_rewards:
		if stack == null or stack.material.is_empty():
			continue
		add_item(stack.material, stack.amount)
	EventBus.publish(TaskCompletedEvent.new(letter_key))
	# 有些信靠「某人办妥了某事」才到（例如第一件委托办妥后寄来的咖啡机信）。
	# advance() 里 _refresh_letters() 跑在 _advance_tasks() 之前，这里补一次，免得要等下一帧。
	_refresh_letters()


# --- 数据访问 -------------------------------------------------------------


func _data() -> DataRegistry:
	return RegistryManager.get_registry(DATA_REGISTRY_KEY) as DataRegistry


func _def(key: String) -> GameDef:
	var data := _data()
	if data == null:
		return null
	return data.get_def(key)


func _defs_of_type(type_id: String) -> Array[GameDef]:
	var data := _data()
	if data == null:
		return []
	return data.get_defs_of_type(type_id)


# --- 配方反查 -------------------------------------------------------------


func _ensure_recipe_index() -> void:
	var recipes := _defs_of_type("recipe")
	if _recipe_index_size == recipes.size() and not _recipes_by_output.is_empty():
		return
	_recipes_by_output.clear()
	_recipes_by_input.clear()
	_recipes_by_tag.clear()
	for def in recipes:
		var recipe := def as RecipeDef
		if recipe == null:
			continue
		var key := recipe.get_key()
		# 反查索引收主产物与副产物：详情里的「它还能从哪来」要能看见副产物来源。
		# 订单/「去做」只认主产物，由 recipe_for_output 再筛一次。
		var produced: Array[String] = [recipe.output]
		for stack in recipe.extra_outputs:
			if stack != null and not stack.material.is_empty() and not produced.has(stack.material):
				produced.append(stack.material)
		for output_key in produced:
			if not _recipes_by_output.has(output_key):
				_recipes_by_output[output_key] = []
			(_recipes_by_output[output_key] as Array).append(key)
		for input_key in recipe.input_keys():
			if not _recipes_by_input.has(input_key):
				_recipes_by_input[input_key] = []
			(_recipes_by_input[input_key] as Array).append(key)
		for stack in recipe.inputs:
			if stack == null or stack.by_tag.is_empty():
				continue
			if not _recipes_by_tag.has(stack.by_tag):
				_recipes_by_tag[stack.by_tag] = []
			if not (_recipes_by_tag[stack.by_tag] as Array).has(key):
				(_recipes_by_tag[stack.by_tag] as Array).append(key)
	_recipe_index_size = recipes.size()


## 产出某件物品的配方键（按数据顺序）；没有返回空数组
func recipes_producing(item_key: String) -> Array[String]:
	_ensure_recipe_index()
	var out: Array[String] = []
	for key in _recipes_by_output.get(item_key, []):
		out.append(String(key))
	return out


## 把某件物品当输入的配方键（按数据顺序）；没有返回空数组。
## 除了点名它的配方，还要算「按标签收它」的配方：`by_tag` 输入（任意蔬菜等）
## 会收下身上挂了这个标签的材料，反查时不能漏（第十轮反馈 5）。
func recipes_using(item_key: String) -> Array[String]:
	_ensure_recipe_index()
	var out: Array[String] = []
	for key in _recipes_by_input.get(item_key, []):
		out.append(String(key))
	var item := _def(item_key) as ItemDef
	if item != null:
		for tag_key in item.tags:
			for key in _recipes_by_tag.get(tag_key, []):
				if not out.has(key):
					out.append(String(key))
	return out


## 某道成品对应的第一条可见配方键；没有（或未解锁/未研究）返回空串。
## 订单「去做」与图鉴详情共用这一处反查（R7.1 反馈 24 / R7.2 反馈 23）。
func recipe_for_output(output_key: String) -> String:
	for key in recipes_producing(output_key):
		var recipe := _def(key) as RecipeDef
		# 副产物也能反查到配方，但订单与「去做」只认主产物
		if recipe == null or recipe.output != output_key:
			continue
		if is_recipe_visible(key):
			return key
	return ""


func _sorted_letters() -> Array[GameDef]:
	var letters := _defs_of_type("letter")
	letters.sort_custom(func(a: GameDef, b: GameDef) -> bool:
		var la := a as LetterDef
		var lb := b as LetterDef
		return la.order < lb.order
	)
	return letters


# --- 商人 -----------------------------------------------------------------


## 商人定义（全局一份；缺省表的那几级由 MerchantDef 自己夹到边界）
func get_merchant_def() -> MerchantDef:
	var def := _def(MERCHANT_DEF_KEY)
	if def is MerchantDef:
		return def as MerchantDef
	for entry in _defs_of_type("merchant"):
		return entry as MerchantDef
	return null


func get_merchant_level() -> int:
	return _merchant_level


func get_merchant_max_level() -> int:
	var merchant := get_merchant_def()
	return merchant.max_level if merchant != null else 1


## 升到下一级的条目；满级或没有表返回 null
func get_merchant_upgrade() -> FacilityUpgrade:
	var merchant := get_merchant_def()
	if merchant == null or _merchant_level >= merchant.max_level:
		return null
	return merchant.get_upgrade(_merchant_level + 1)


## 升到下一级要多少铜币；满级返回 -1
func get_merchant_upgrade_cost() -> int:
	var upgrade := get_merchant_upgrade()
	return upgrade.coin_cost if upgrade != null else -1


func can_upgrade_merchant() -> bool:
	var upgrade := get_merchant_upgrade()
	if upgrade == null:
		return false
	if coins < upgrade.coin_cost:
		return false
	return can_consume(upgrade.materials)


## 升级商人：铜币 + 材料（面粉/蛋 → 糖/盐 → 香料/油），与设备升级同构
func upgrade_merchant() -> bool:
	var upgrade := get_merchant_upgrade()
	if upgrade == null or not can_upgrade_merchant():
		return false
	add_coins(-upgrade.coin_cost, "商人升级")
	_consume(upgrade.materials)
	_merchant_level += 1
	# 新等级可能解锁新材料：补一次货架，免得玩家升级后还得等一轮补货
	for key in _shop_keys():
		if not _shop_stock.has(key):
			_shop_stock[key] = get_shop_capacity(key)
	EventBus.publish(MerchantUpgradedEvent.new(_merchant_level))
	return true


## 这门材料现在能不能在货架上看到（等级够、有买价、不是免费资源）
func is_material_on_sale(key: String) -> bool:
	var def := _def(key) as ItemDef
	if def == null or not def.is_material() or def.is_free():
		return false
	return def.merchant_price > 0 and def.merchant_level <= get_merchant_level()


# --- 商店 -----------------------------------------------------------------


## 用铜币买材料。价格来自 ItemDef.merchant_price，不在这里硬编码。
## 从商人货架买：只能买槽里已经有的份数，价格固定。
## 买空后进 6 分钟冷却，冷却走完一次补满（离线照走，但不会替玩家买）。
func buy_material(key: String, amount: int) -> bool:
	var def := _def(key) as ItemDef
	if def == null or amount <= 0:
		return false
	if not def.is_material() or def.is_free() or def.merchant_price <= 0:
		return false
	if get_shop_stock(key) < amount:
		return false
	var cost := def.merchant_price * amount
	if coins < cost:
		return false
	add_coins(-cost, "购买%s" % def.localized())
	add_item(key, amount)
	_shop_stock[key] = get_shop_stock(key) - amount
	if get_shop_stock(key) <= 0:
		_shop_stock[key] = 0
		# 拨表：已经在走就让它继续走，不因再买空一样而重置（全局一份）
		if _shop_refill_remaining <= 0.0:
			_shop_refill_remaining = get_shop_refill_seconds()
	return true


## 把材料或成品食物卖给商人。收购价来自各自的 sell_price（<= 0 = 不收）。
func sell_item(key: String, amount: int) -> bool:
	var def := _def(key)
	if def == null or amount <= 0:
		return false
	var price := _sell_price_of(def)
	if price <= 0:
		return false
	if get_amount(key) < amount:
		return false
	_add_stock(key, -amount)
	add_coins(price * amount, "卖出%s" % def.localized())
	return true


## 兼容旧调用（材料与成品食物都走同一条收购逻辑）
func sell_material(key: String, amount: int) -> bool:
	return sell_item(key, amount)


func _sell_price_of(def: GameDef) -> int:
	var item := def as ItemDef
	return item.sell_price if item != null else 0


# --- 订单板 ---------------------------------------------------------------


## 当前委托（副本，调用方别改内部数组）
func get_orders() -> Array[Order]:
	return _orders.duplicate()


## 下一次刷委托还剩几秒；订单满时返回 0
func get_orders_refill_remaining() -> float:
	return _orders_refill_remaining if _orders.size() < _order_capacity else 0.0


func get_orders_completed() -> int:
	return _orders_completed


func get_orders_refreshed() -> int:
	return _orders_refreshed


## 现在能挂几张委托（开局 ORDER_CAPACITY，花铜币可扩到 ORDER_CAPACITY_MAX）
func get_order_capacity() -> int:
	return _order_capacity


## 再扩一张单子要多少铜币；已经到上限返回 -1
func get_order_capacity_cost() -> int:
	if _order_capacity >= ORDER_CAPACITY_MAX:
		return -1
	return int(ORDER_CAPACITY_COSTS[_order_capacity - ORDER_CAPACITY])


func can_upgrade_order_capacity() -> bool:
	var cost := get_order_capacity_cost()
	return cost >= 0 and coins >= cost


## 花铜币扩一张单子；腾出来的新位置立刻补一单，不用等补位倒计时
func upgrade_order_capacity() -> bool:
	if not can_upgrade_order_capacity():
		return false
	add_coins(-get_order_capacity_cost(), "订单板扩容")
	_order_capacity += 1
	_refill_orders()
	EventBus.publish(OrderChangedEvent.new("expanded", _order_capacity))
	return true


## 「换一批」还要等几秒；0 = 现在就能换
func get_order_refresh_cooldown() -> float:
	return maxf(0.0, _order_refresh_cooldown)


## 免费换一批：整块板清空重抽。冷却期内、或者板上本来就没单子时换不了。
func refresh_orders() -> bool:
	if _order_refresh_cooldown > 0.0 or _orders.is_empty():
		return false
	_orders.clear()
	_order_refresh_cooldown = ORDER_REFRESH_COOLDOWN_SECONDS
	_orders_refreshed += 1
	_refill_orders()
	EventBus.publish(OrderChangedEvent.new("refreshed", _orders.size()))
	return true


## 拒掉一条委托：不扣铜币、不扣菜，腾出的位置按正常补位倒计时慢慢补
func decline_order(order_id: int) -> bool:
	var index := -1
	for i in _orders.size():
		if _orders[i].id == order_id:
			index = i
			break
	if index < 0:
		return false
	_orders.remove_at(index)
	if _orders.size() < _order_capacity and _orders_refill_remaining <= 0.0:
		_orders_refill_remaining = ORDER_REFILL_SECONDS
	EventBus.publish(OrderChangedEvent.new("declined", order_id))
	return true


## 交付一条委托：扣菜、发酬劳与赠品，腾出的位置重新开始倒计时。
func deliver_order(order_id: int) -> bool:
	var index := -1
	for i in _orders.size():
		if _orders[i].id == order_id:
			index = i
			break
	if index < 0:
		return false
	var order := _orders[index]
	if get_amount(order.dish_key) < order.quantity:
		return false
	_add_stock(order.dish_key, -order.quantity)
	add_coins(order.reward_coins, "订单：%s" % _display_name_of(order.dish_key))
	if not order.bonus_material.is_empty() and order.bonus_amount > 0:
		add_item(order.bonus_material, order.bonus_amount)
	_orders.remove_at(index)
	_orders_completed += 1
	_tasks_dirty = true
	if _orders.size() < _order_capacity and _orders_refill_remaining <= 0.0:
		_orders_refill_remaining = ORDER_REFILL_SECONDS
	EventBus.publish(OrderChangedEvent.new("delivered", order_id))
	return true


## 补满订单板；没有可做的菜（还没解锁任何配方）时留空，等 advance 再试
func _refill_orders() -> void:
	var guard := 0
	while _orders.size() < _order_capacity and guard < _order_capacity + 1:
		if not _append_order():
			break
		guard += 1
	if _orders.size() < _order_capacity and _orders_refill_remaining <= 0.0:
		_orders_refill_remaining = ORDER_REFILL_SECONDS


func _advance_orders(seconds: float) -> void:
	_order_refresh_cooldown = maxf(0.0, _order_refresh_cooldown - seconds)
	if _orders.size() >= _order_capacity:
		return
	_orders_refill_remaining -= seconds
	var guard := 0
	while _orders.size() < _order_capacity and _orders_refill_remaining <= 0.0 and guard < _order_capacity + 1:
		if not _append_order():
			_orders_refill_remaining = ORDER_REFILL_SECONDS
			return
		_orders_refilled_from_clock()
		_orders_refill_remaining += ORDER_REFILL_SECONDS
		guard += 1


func _orders_refilled_from_clock() -> void:
	_orders_refreshed += 1


## 追加一条委托；没有可委托的菜时返回 false
func _append_order() -> bool:
	var dishes := _order_dish_keys()
	if dishes.is_empty():
		return false
	var dish_key := _pick_order_dish(dishes)
	if dish_key.is_empty():
		return false
	var food := _def(dish_key) as ItemDef
	if food == null:
		return false
	var quantity := 1 + ((_order_seq + _orders_completed) % 2)
	var order := Order.new()
	order.id = _order_seq
	order.dish_key = dish_key
	order.quantity = quantity
	order.is_signature = _signature_slots.has(dish_key)
	order.signature_theme_key = item_theme_key(dish_key)
	order.signature_theme_boost = get_signature_theme_boost(order.signature_theme_key)
	order.reward_coins = _order_reward_for(food, quantity, order.is_signature)
	order.bonus_material = _order_bonus_material()
	order.bonus_amount = 1 + quantity + int(food.sell_price / 20)
	_order_seq += 1
	_orders.append(order)
	EventBus.publish(OrderChangedEvent.new("refilled", order.id))
	return true


## 一条委托的酬劳：基础价 × 份数 × 倍率；招牌菜按当前有效槽数加成
func _order_reward_for(food: ItemDef, quantity: int, is_signature: bool) -> int:
	var reward := maxi(4, food.sell_price * quantity * ORDER_REWARD_MULTIPLIER)
	if is_signature:
		reward = roundi(float(reward) * get_signature_bonus())
	return reward


## 按 order_weight × 招牌菜系权重抽一道菜；总权重为 0 时返回空串。
## 若上一次设置招牌留下了「下一单优先该菜系」的保底，先把候选池收窄到该菜系；
## 收窄后没有可做的菜时退回全池，保底留到下一次补位。
func _pick_order_dish(dishes: Array[String]) -> String:
	var pool := dishes
	if not _signature_pending_theme.is_empty():
		var themed: Array[String] = []
		for key in dishes:
			if item_theme_key(key) == _signature_pending_theme:
				themed.append(key)
		if not themed.is_empty():
			pool = themed
			_signature_pending_theme = ""
	var boosts := get_signature_theme_boosts()
	var total := 0.0
	for key in pool:
		var food := _def(key) as ItemDef
		if food != null:
			total += maxf(0.0, food.order_weight) * float(boosts.get(item_theme_key(key), 1.0))
	if total <= 0.0:
		return ""
	var roll := _rng.randf() * total
	for key in pool:
		var food := _def(key) as ItemDef
		if food == null:
			continue
		roll -= maxf(0.0, food.order_weight) * float(boosts.get(item_theme_key(key), 1.0))
		if roll <= 0.0:
			return key
	return pool[pool.size() - 1]


# --- 菜品可达性 / 订单闸门 -------------------------------------------------


## 现在这道配方能不能真的做出来：配方可见、设备到手、每个输入都有真实来源。
## 与菜品树体检共用 dish_reachability.gd 的同一份倒推逻辑（R7.3 反馈 6）。
func is_orderable_now(recipe_key: String) -> bool:
	var report: Dictionary = DISH_REACHABILITY.explain_recipe(self, recipe_key, false)
	return bool(report.get("ok", false))


## 全部食物（图鉴里的 237 道菜），菜品树体检与全量测试共用。
func get_all_dish_keys() -> Array[String]:
	var keys: Array[String] = []
	for def in _defs_of_type("item"):
		var item := def as ItemDef
		if item != null and item.is_food():
			keys.append(item.get_key())
	keys.sort_custom(func(a: String, b: String) -> bool:
		var food_a := _def(a) as ItemDef
		var food_b := _def(b) as ItemDef
		if food_a.order != food_b.order:
			return food_a.order < food_b.order
		return a < b
	)
	return keys


## 单道菜的四态诊断：可下单 / 缺设备 / 缺材料 / 配方未解锁。
## full=true 时模拟全设备、全采集、全配方可见，用来查内容树缺口。
func explain_dish_reachability(dish_key: String, full := false) -> Dictionary:
	var food := _def(dish_key) as ItemDef
	var result := {
		"dish": dish_key,
		"name": _display_name_of(dish_key),
		"state": "not_food",
		"orderable": false,
		"recipe": "",
		"kind": "invalid",
		"chain": [],
	}
	if food == null or not food.is_food():
		return result
	var producers: Array = recipes_producing(dish_key)
	if producers.is_empty():
		result["state"] = "no_recipe"
		result["kind"] = "invalid"
		return result
	var visible_failure: Dictionary = {}
	for producer in producers:
		var recipe_key := String(producer)
		var report: Dictionary = DISH_REACHABILITY.explain_recipe(self, recipe_key, full)
		if bool(report.get("ok", false)):
			result["state"] = "orderable"
			result["orderable"] = true
			result["recipe"] = recipe_key
			result["kind"] = "ok"
			result["chain"] = []
			return result
		var kind := String(report.get("kind", ""))
		if kind == "locked":
			continue
		if visible_failure.is_empty():
			visible_failure = {"recipe": recipe_key, "report": report}
	if not visible_failure.is_empty():
		var chosen: Dictionary = visible_failure["report"]
		result["recipe"] = String(visible_failure["recipe"])
		result["kind"] = String(chosen.get("kind", "material"))
		result["chain"] = chosen.get("chain", [])
		result["state"] = "facility" if result["kind"] == "facility" else "material"
		return result
	result["recipe"] = String(producers[0])
	result["kind"] = "locked"
	result["chain"] = ["recipe:" + String(producers[0])]
	result["state"] = "locked"
	return result


## 可委托的菜：已解锁配方产出的、有收购价的食物（按图鉴顺序）
## 只有食物能上订单板：材料既不能被「做一份」，也不该被当成一道菜。
func _order_dish_keys() -> Array[String]:
	var keys: Array[String] = []
	var legacy: Array[String] = []
	for recipe in get_visible_recipes():
		var food := _def(recipe.output) as ItemDef
		if food == null or not food.is_food() or food.sell_price <= 0:
			continue
		# 权重 0 = 这道菜不上订单板
		if food.order_weight <= 0.0:
			continue
		if not legacy.has(recipe.output):
			legacy.append(recipe.output)
		# 闸门：设备没到手、料没有真实来源、配方还没研究的菜不上板
		if not is_orderable_now(recipe.get_key()):
			continue
		if not keys.has(recipe.output):
			keys.append(recipe.output)
	if keys.is_empty() and not legacy.is_empty():
		# 保险：数据异常时不要让订单板整块空白。正常存档不该走到这里。
		push_warning("[GameState] 订单闸门筛空，回退旧列表；请检查配方可达性")
		keys = legacy
	keys.sort_custom(func(a: String, b: String) -> bool:
		var food_a := _def(a) as ItemDef
		var food_b := _def(b) as ItemDef
		if food_a.order != food_b.order:
			return food_a.order < food_b.order
		return a < b
	)
	return keys


## 订单赠品从「能卖钱的基础材料」里轮换，不碰中间材料（中间材料是玩家自己合出来的）
func _order_bonus_material() -> String:
	var pool: Array[String] = []
	for def in _defs_of_type("item"):
		var item := def as ItemDef
		if item == null or not item.is_material():
			continue
		if item.material_kind == ItemDef.MaterialKind.BASE and item.sell_price > 0:
			pool.append(item.get_key())
	if pool.is_empty():
		return ""
	pool.sort()
	return pool[(_order_seq + _orders_completed) % pool.size()]


func _display_name_of(key: String) -> String:
	var def := _def(key)
	return def.localized() if def != null else key


# --- 存档 -----------------------------------------------------------------


## 序列化成可 JSON 的字典（v3）。字段只放状态，不放定义引用。
## v3 起库存为整数（另存小数余量）、并记录订单板；v1/v2 老档仍可读。
func to_dict() -> Dictionary:
	var jobs: Array = []
	for job in _jobs:
		jobs.append({
			"recipe": job.recipe_key,
			"facility": job.facility_key,
			"batches": job.batches,
			"total": job.total_seconds,
			"remaining": job.remaining_seconds,
		})
	var research_jobs: Array = []
	for job in _research_jobs:
		research_jobs.append({
			"signature": job.signature,
			"materials": job.materials.duplicate(),
			"recipe": job.recipe_key,
			"outcome": job.outcome,
			"succeeded": job.succeeded,
			"charged": job.charged.duplicate(),
			"total": job.total_seconds,
			"remaining": job.remaining_seconds,
		})
	return {
		"version": SAVE_VERSION,
		"coins": coins,
		"offline_unlocked": offline_unlocked,
		"last_seen_unix": last_seen_unix,
		"play_seconds": play_seconds,
		"stock": _stock.duplicate(),
		"discovered": _discovered.keys(),
		"crafted_food": _crafted_food.keys(),
		"facility_levels": _facility_levels.duplicate(),
		"kitchen_level": _kitchen_level,
		"harvest_levels": _harvest_levels.duplicate(),
		"harvest_cooldowns": _harvest_cooldowns.duplicate(),
		"harvest_pending": _harvest_pending.duplicate(),
		"shop_stock": _shop_stock.duplicate(),
		"shop_refill_remaining": _shop_refill_remaining,
		"merchant_level": _merchant_level,
		"unlocked_letters": _unlocked_letters.duplicate(),
		"read_letters": _read_letters.keys(),
		"crafted_food_count": _crafted_food_count.duplicate(),
		"accepted_tasks": _accepted_tasks.duplicate(),
		"completed_tasks": _completed_tasks.keys(),
		"task_baseline": _task_baseline.duplicate(),
		"jobs": jobs,
		"unlocked_recipes": _unlocked_recipes.keys(),
		"researched": _researched.duplicate(true),
		"research_history": _research_history.duplicate(true),
		"research_guide_seen": _research_guide_seen,
		"research_jobs": research_jobs,
		"last_research": _last_research_signature,
		"milestone_tier": _milestone_tier,
		"stock_fraction": _stock_fraction.duplicate(),
		"orders": _orders.map(func(order: Order) -> Dictionary: return order.to_dict()),
		"orders_refill": _orders_refill_remaining,
		"orders_completed": _orders_completed,
		"orders_refreshed": _orders_refreshed,
		"order_seq": _order_seq,
		"order_capacity": _order_capacity,
		"signature_dishes": get_signature_slots(),
		"signature_pending_theme": _signature_pending_theme,
		"catalog_seen": _catalog_seen,
		"discovery_order": _discovery_order.duplicate(),
		"tutorial_step": tutorial_step,
		"tutorial_done": tutorial_done,
	}


## 存档里是否还留着 v10 之前的物品键。键可能出现在库存字典的键、订单的 dish_key、
## 图鉴已点亮数组、招牌槽等任何位置，所以整份字典递归扫一遍字符串。
## 存档只有几十 KB，扫一次的开销可以忽略；比起按版本号猜，按内容判断不会误伤
## 「版本号小但键已经是新的」那些老档（v8 / v9 期间也做过破坏性调整）。
func _has_legacy_item_keys(value: Variant) -> bool:
	match typeof(value):
		TYPE_STRING:
			return _is_legacy_item_key(String(value))
		TYPE_DICTIONARY:
			var dict := value as Dictionary
			for key in dict:
				if _has_legacy_item_keys(key) or _has_legacy_item_keys(dict[key]):
					return true
		TYPE_ARRAY:
			var list := value as Array
			for item in list:
				if _has_legacy_item_keys(item):
					return true
	return false


## v10 之前的物品键：命名空间是 game，路径以 food/ 或 material/ 开头（现在一律 item/）
static func _is_legacy_item_key(text: String) -> bool:
	var prefix := GameDef.DEFAULT_NAMESPACE + ":"
	if not text.begins_with(prefix):
		return false
	var path := text.substr(prefix.length())
	return path.begins_with("food/") or path.begins_with("material/")


## 从字典恢复全部状态；版本不认识返回 false（调用方决定当新档还是报错）。
##
## v1 → v2：v1 没有研究相关字段，按「都没试过」恢复，其余照旧，不丢档。
## v2 → v3：库存从 float 改为 int，小数部分转入 `stock_fraction`，不会凭空多出半份。
## v10：物品键从 `food/`、`material/` 统一成 `item/`，旧档里的键一条也对不上。
##      版本号仍按「1..当前版本」放行（缺字段的老档照读），但只要档里出现旧键就直接拒绝
##      ——按内容判断比按版本号判断更准：v8 / v9 期间也做过破坏性调整。
## 恢复后仍会跑一次 `_refresh_letters()`，这样「存档之后新加的信件」也能补解锁。
func restore_from_dict(data: Dictionary) -> bool:
	var version := int(data.get("version", 0))
	if version < SAVE_MIN_VERSION or version > SAVE_VERSION:
		return false
	if _has_legacy_item_keys(data):
		push_warning("[GameState] 存档里还有 v10 之前的物品键（food/、material/），旧档不再支持")
		return false
	reset()
	coins = int(data.get("coins", 0))
	offline_unlocked = bool(data.get("offline_unlocked", false))
	last_seen_unix = int(data.get("last_seen_unix", 0))
	play_seconds = maxf(0.0, float(data.get("play_seconds", 0.0)))

	_stock.clear()
	_stock_fraction.clear()
	var stock: Dictionary = data.get("stock", {})
	for key in stock:
		# v1/v2 的库存是 float（基础材料连续累积）；v3 起是整数。
		# 老档向下取整，小数部分转入余量，读档后不会凭空多出半份材料。
		var raw := float(stock[key])
		var whole := int(floor(raw))
		_stock[String(key)] = whole
		var frac := raw - float(whole)
		if frac > EPSILON:
			_stock_fraction[String(key)] = frac
	var fractions: Dictionary = data.get("stock_fraction", {})
	for key in fractions:
		var fraction_key := String(key)
		var total := float(_stock.get(fraction_key, 0)) + float(_stock_fraction.get(fraction_key, 0.0)) + float(fractions[key])
		var whole := int(floor(total))
		_stock[fraction_key] = whole
		var remainder := total - float(whole)
		if remainder > EPSILON:
			_stock_fraction[fraction_key] = remainder
		else:
			_stock_fraction.erase(fraction_key)

	_discovered.clear()
	for key in data.get("discovered", []):
		_discovered[String(key)] = true

	_crafted_food.clear()
	for key in data.get("crafted_food", []):
		_crafted_food[String(key)] = true

	_facility_levels.clear()
	var levels: Dictionary = data.get("facility_levels", {})
	for key in levels:
		_facility_levels[String(key)] = int(levels[key])
	_kitchen_level = clampi(int(data.get("kitchen_level", 1)), 1, KITCHEN_MAX_LEVEL)
	for def in _defs_of_type("facility"):
		if not _facility_levels.has(def.get_key()):
			# 老档里没有这一条：等信件添置的设备按 0 级补，其余按 1 级
			var missing := def as FacilityDef
			var awaits_letter := missing != null and not missing.unlock_letter.is_empty()
			_facility_levels[def.get_key()] = 0 if awaits_letter else 1

	# 采集点：v5 及更老的档没有这两项，按「全部 1 级、没有冷却」补。
	# 采集点改按标签收池之后，老档里存的是材料键，这里只认采集点自己的键。
	_harvest_levels.clear()
	var harvest_levels: Dictionary = data.get("harvest_levels", {})
	for key in harvest_levels:
		if _def(String(key)) is HarvestDef:
			_harvest_levels[String(key)] = clampi(int(harvest_levels[key]), 1, 9)
	for def in _defs_of_type("harvest"):
		var harvest_key := (def as HarvestDef).get_key()
		if not _harvest_levels.has(harvest_key):
			_harvest_levels[harvest_key] = 1
	# 商店货架：v6 及更老的档没有这两项，按「全部满架、没有冷却」补。
	# 老档的补货是「每个 key 一个倒计时」，迁移成全局一份：取还在走的最长那条。
	_shop_stock.clear()
	_shop_refill_remaining = 0.0
	var shop_stock: Dictionary = data.get("shop_stock", {})
	for key in shop_stock:
		_shop_stock[String(key)] = clampi(int(shop_stock[key]), 0, get_shop_capacity(String(key)))
	var legacy_refill: Dictionary = data.get("shop_refill", {})
	for key in legacy_refill:
		_shop_refill_remaining = maxf(_shop_refill_remaining, float(legacy_refill[key]))
	_shop_refill_remaining = maxf(_shop_refill_remaining, float(data.get("shop_refill_remaining", 0.0)))
	# v16：商人等级；破坏性更新后缺省即 Lv1
	_merchant_level = clampi(int(data.get("merchant_level", 1)), 1, maxi(get_merchant_max_level(), 1))
	for key in _shop_keys():
		if not _shop_stock.has(key):
			_shop_stock[key] = get_shop_capacity(key)
	_harvest_cooldowns.clear()
	var cooldowns: Dictionary = data.get("harvest_cooldowns", {})
	for key in cooldowns:
		var left := float(cooldowns[key])
		if left > 0.0 and _def(String(key)) is HarvestDef:
			_harvest_cooldowns[String(key)] = left
	_harvest_pending.clear()
	var pendings: Dictionary = data.get("harvest_pending", {})
	for key in pendings:
		var pending := float(pendings[key])
		if pending > 0.0 and _def(String(key)) is HarvestDef:
			_harvest_pending[String(key)] = pending

	_unlocked_letters.clear()
	for key in data.get("unlocked_letters", []):
		_unlocked_letters.append(String(key))

	_read_letters.clear()
	for key in data.get("read_letters", []):
		_read_letters[String(key)] = true

	_crafted_food_count.clear()
	var crafted_counts: Dictionary = data.get("crafted_food_count", {})
	for key in crafted_counts:
		_crafted_food_count[String(key)] = maxi(0, int(crafted_counts[key]))
	# v11 及更老的档只记「做过没有」，没有份数：补 1，别让委托进度看起来是 0
	for key in _crafted_food:
		if not _crafted_food_count.has(key):
			_crafted_food_count[key] = 1

	_accepted_tasks.clear()
	for key in data.get("accepted_tasks", []):
		var accepted_key := String(key)
		if _def(accepted_key) is LetterDef:
			_accepted_tasks.append(accepted_key)
	_task_baseline.clear()
	for raw_key in data.get("task_baseline", {}):
		if _def(String(raw_key)) is LetterDef:
			_task_baseline[String(raw_key)] = int(data["task_baseline"][raw_key])
	_completed_tasks.clear()
	for key in data.get("completed_tasks", []):
		var done_key := String(key)
		if _def(done_key) is LetterDef:
			_completed_tasks[done_key] = true
	if not _accepted_tasks.is_empty():
		_tasks_dirty = true

	# 读过的解锁信要补回设备（存档里没存 0/1 级的区别，按已读信件重算一次）
	for key in _read_letters:
		_unlock_facilities_for(String(key))

	_jobs.clear()
	for entry in data.get("jobs", []):
		if not entry is Dictionary:
			continue
		var job := CraftJob.new()
		job.recipe_key = String(entry.get("recipe", ""))
		job.facility_key = String(entry.get("facility", ""))
		job.batches = maxi(1, int(entry.get("batches", 1)))
		job.total_seconds = float(entry.get("total", 0.0))
		job.remaining_seconds = float(entry.get("remaining", 0.0))
		if _def(job.recipe_key) != null:
			_jobs.append(job)

	_unlocked_recipes.clear()
	for key in data.get("unlocked_recipes", []):
		_unlocked_recipes[String(key)] = true
	_researched.clear()
	var researched: Dictionary = data.get("researched", {})
	for signature in researched:
		var entry: Variant = researched[signature]
		if not entry is Dictionary:
			continue
		var record: Dictionary = entry
		_researched[String(signature)] = {
			"outcome": int(record.get("outcome", 0)),
			"recipe": String(record.get("recipe", "")),
			"burned": record.get("burned", []),
		}

	_research_history.clear()
	for entry in data.get("research_history", []):
		if not entry is Dictionary:
			continue
		var history_record: Dictionary = entry
		var history_materials: Array[String] = []
		var materials_raw: Variant = history_record.get("materials", [])
		if materials_raw is Array:
			for key in materials_raw:
				history_materials.append(String(key))
		var history_signature := String(history_record.get("signature", ""))
		if history_signature.is_empty() and not history_materials.is_empty():
			history_signature = signature_of(history_materials)
		if history_signature.is_empty():
			continue
		_research_history.append({
			"signature": history_signature,
			"materials": history_materials,
			"recipe": String(history_record.get("recipe", "")),
			"outcome": int(history_record.get("outcome", 0)),
			"succeeded": bool(history_record.get("succeeded", false)),
			"burned": history_record.get("burned", []),
			"seconds": float(history_record.get("seconds", 0.0)),
		})
	while _research_history.size() > RESEARCH_HISTORY_LIMIT:
		_research_history.pop_front()
	# 老档没有历史数组：把试过的组合补回来（顺序与用时无从得知，按签名排序兜底）
	if _research_history.is_empty() and not _researched.is_empty():
		var legacy_history: Array[Dictionary] = []
		for signature in _researched:
			var legacy_record: Dictionary = _researched[signature]
			var legacy_materials: Array[String] = []
			for key in String(signature).split("+"):
				if not key.is_empty():
					legacy_materials.append(key)
			legacy_history.append({
				"signature": String(signature),
				"materials": legacy_materials,
				"recipe": String(legacy_record.get("recipe", "")),
				"outcome": int(legacy_record.get("outcome", 0)),
				"succeeded": false,
				"burned": legacy_record.get("burned", []),
				"seconds": 0.0,
			})
		legacy_history.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["signature"]) < String(b["signature"]))
		for legacy_entry in legacy_history:
			_research_history.append(legacy_entry)
		while _research_history.size() > RESEARCH_HISTORY_LIMIT:
			_research_history.pop_front()

	_research_guide_seen = bool(data.get("research_guide_seen", false))

	_research_jobs.clear()
	for entry in data.get("research_jobs", []):
		if not entry is Dictionary:
			continue
		var record: Dictionary = entry
		var signature := String(record.get("signature", ""))
		if signature.is_empty():
			continue
		var job := ResearchJob.new()
		job.signature = signature
		var materials: Array[String] = []
		for key in record.get("materials", []):
			materials.append(String(key))
		job.materials = materials
		job.recipe_key = String(record.get("recipe", ""))
		job.outcome = int(record.get("outcome", 0))
		job.succeeded = bool(record.get("succeeded", false))
		job.total_seconds = float(record.get("total", 0.0))
		job.remaining_seconds = float(record.get("remaining", 0.0))
		var charged: Dictionary = {}
		var charged_raw = record.get("charged", {})
		if charged_raw is Dictionary:
			for key in charged_raw:
				charged[String(key)] = int(charged_raw[key])
		job.charged = charged
		_research_jobs.append(job)

	_last_research_signature = String(data.get("last_research", ""))

	# 里程碑档位：老存档没有这个字段，就按当前进度补算（补算只对齐档位，不重发铜币）
	_milestone_tier = int(data.get("milestone_tier", -1))
	if _milestone_tier < 0:
		_milestone_tier = 0
		_sync_milestone_tier()

	_orders.clear()
	# 容量小改大由玩家花币扩；读档时只认 [ORDER_CAPACITY, ORDER_CAPACITY_MAX] 内的值
	_order_capacity = clampi(int(data.get("order_capacity", ORDER_CAPACITY)), ORDER_CAPACITY, ORDER_CAPACITY_MAX)
	_order_refresh_cooldown = 0.0
	_orders_completed = int(data.get("orders_completed", 0))
	_orders_refreshed = int(data.get("orders_refreshed", 0))
	_order_seq = int(data.get("order_seq", 0))
	_orders_refill_remaining = float(data.get("orders_refill", ORDER_REFILL_SECONDS))
	for entry in data.get("orders", []):
		if not entry is Dictionary:
			continue
		var order := Order.from_dict(entry)
		var dish := _def(order.dish_key) as ItemDef
		if dish != null and dish.is_food():
			_orders.append(order)
	# 手改过的存档可能比容量多塞了单子，多余的砍掉（从尾部砍，保留先刷出来的）
	while _orders.size() > _order_capacity:
		_orders.pop_back()
	if _orders.is_empty():
		_refill_orders()

	# v4 起才有招牌菜；老档没有字段 = 三格全部自动补位。
	# 手改过的存档可能塞进未发现的菜或重复的菜，逐格过滤掉。
	_signature_slots.clear()
	var chosen: Array = data.get("signature_dishes", [])
	for i in SIGNATURE_SLOTS:
		var chosen_key := ""
		if i < chosen.size():
			var candidate := String(chosen[i])
			if is_valid_signature(candidate) and not _signature_slots.has(candidate):
				chosen_key = candidate
		_signature_slots.append(chosen_key)
	# 保底菜系是 R18 新字段：旧档没有 = 没有待兑现的保底。
	# 只有当前仍有同菜系手填招牌时才认，避免手改档留下永不过期的悬空值。
	_signature_pending_theme = String(data.get("signature_pending_theme", ""))
	if not _signature_pending_theme.is_empty() and not get_signature_theme_boosts().has(_signature_pending_theme):
		_signature_pending_theme = ""
	_fill_pending_signature_order()

	# v4 起才有「看过多少条图鉴」；老档没有字段 = 当作全看过，别一读档就亮红点
	_catalog_seen = clampi(int(data.get("catalog_seen", get_catalog_discovered_count())), 0, get_catalog_discovered_count())

	# v14：图鉴发现顺序。旧档没有这一项，按已发现键排序回填即可（只需稳定，不必精确）；
	# 手改档漏了几条也在这里补齐，保证「最新一条」永远指向一个真实条目。
	_discovery_order.clear()
	var order_raw: Variant = data.get("discovery_order", [])
	if order_raw is Array:
		for raw_key in order_raw:
			var order_key := String(raw_key)
			if _discovered.has(order_key) and not _discovery_order.has(order_key):
				_discovery_order.append(order_key)
	for discovered_key in get_discovered_keys():
		if not _discovery_order.has(discovered_key):
			_discovery_order.append(discovered_key)

	# v15：帮手已移除。旧档里残留的 helper_level 不读，保持手动收铜板。

	# v14：引导。旧档（v13 及更老）默认「已完成」，否则老玩家一进来就被教做人；
	# 新档由 reset() 置为未完成，从第一步开始。
	var legacy_tutorial := version < 14
	tutorial_step = clampi(int(data.get("tutorial_step", 3 if legacy_tutorial else 0)), 0, TUTORIAL_STEP_COUNT)
	tutorial_done = bool(data.get("tutorial_done", legacy_tutorial))

	_refresh_letters()
	# 启动时 HUD 先于 GameBridge ready，恢复过程又不逐项发增量事件：
	# 这里补一次「整体已换档」的信号，让所有界面重拉快照（见 StateRestoredEvent）
	EventBus.publish(StateRestoredEvent.new())
	return true


# --- 离线结算 -------------------------------------------------------------


## 离线看店小费单价：每 5 分钟一份，完成 10 单涨 1，最高 5
func get_offline_coin_rate() -> int:
	return 1 + mini(_orders_completed / 10, 4)


## 结算「离开的这段时间」：推进世界，并把净变化整理成一份摘要给 OfflinePanel。
##
## 只统计净增的条目：期间边产边耗（做了一半的配方）不会被重复计入。
func apply_offline(elapsed_seconds: float) -> OfflineSummary:
	var summary := OfflineSummary.new()
	summary.elapsed_seconds = maxf(elapsed_seconds, 0.0)
	summary.offline_unlocked = offline_unlocked
	if summary.elapsed_seconds <= 0.0:
		return summary
	# 离线产出锁还没打开：世界时间不推进。否则产地等级再高，玩家在解锁前
	# 也能靠离线攒材料、完成制作（第八轮反馈 9 / 10）。只把 last_seen 拨到
	# 当下，免得下次再按同一段时间重复结算。
	if not offline_unlocked:
		last_seen_unix = int(Time.get_unix_time_from_system())
		return summary
	var before_stock := _stock.duplicate()
	var before_coins := coins
	var before_letter_count := _unlocked_letters.size()
	var before_refreshed := _orders_refreshed
	# 与材料、小费共用同一个 8 小时上限：人不在三天，也只按 8 小时结算一次。
	var paid_seconds := minf(summary.elapsed_seconds, MAX_ADVANCE_SECONDS)
	advance(paid_seconds, true)
	# 看店小费：离家期间常客自己上门留下的铜币，避免「离线只长材料」。
	# 只有解锁离线后才发；订单完成得越多，单价越高（上限 5）。
	if offline_unlocked:
		var periods := int(paid_seconds / OFFLINE_COINS_INTERVAL)
		if periods > 0:
			add_coins(periods * get_offline_coin_rate(), "看店小费")
	summary.orders_refreshed = _orders_refreshed - before_refreshed
	for key in _stock:
		var delta := get_amount(key) - int(before_stock.get(key, 0))
		if delta <= 0:
			continue
		var def := _def(key) as ItemDef
		summary.gains.append({
			"key": String(key),
			"name": def.localized() if def != null else String(key),
			"type_id": def.get_type_id() if def != null else "",
			"kind": def.kind if def != null else ItemDef.Kind.MATERIAL,
			"delta": delta,
		})
	# 材料与食物现在同为 `"item"`，只按 type_id 排会退化成按 key 排；
	# 改按 kind 排（FOOD=1 > MATERIAL=0，即成品在前、材料在后），保持原先的观感。
	summary.gains.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["kind"]) != int(b["kind"]):
			return int(a["kind"]) > int(b["kind"])
		return String(a["key"]) < String(b["key"])
	)
	summary.coins_gained = coins - before_coins
	for index in range(before_letter_count, _unlocked_letters.size()):
		summary.letter_keys.append(_unlocked_letters[index])
	summary.unlocked_now = offline_unlocked and not summary.offline_unlocked
	return summary


## 调试构建专用：跳过第 16 封信，直接解开离线产出，好在一次会话里试它。
## 正式内容里这把锁只由 LetterDef.unlocks_offline 打开。
func debug_unlock_offline() -> void:
	if not OS.is_debug_build():
		return
	offline_unlocked = true
