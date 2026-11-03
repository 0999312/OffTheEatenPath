class_name ItemDef
extends GameDef
## 物品定义：材料与食物共用一张表，用 `kind` 区分。
##
## 为什么合并（决策见 `docs/decisions/2026-10-26-item-def.md`）：
## - 它们本来就是同一件事的两端——中间材料由配方产出、又当配方输入，食物既能被卖、
##   又能当输入（美式用浓缩做），原先 `FoodDef` / `MaterialDef` 两个类之间的判断
##   散落在买卖、扣料、订单、图鉴、离线上十条分支里，每加一种「既能…又能…」都要改两处；
## - 交易数据（`merchant_price` / `sell_price`，以后的库存与解锁）只有一份，放物品层，
##   不必在两个类里各写一遍再保证一致；
## - 键统一成 `game:item/<slug>`，一个目录 `resources/game_data/items/`，加一条内容
##   只加一个 `.tres`。
##
## 字段的使用面按 `kind` 收窄，不用另一个类表达：
## - `material_kind` / `merchant_price` / `in_catalog`：材料（`Kind.MATERIAL`）；
## - `taste` / `catalog_hint` / `theme` / `order_weight`：食物（`Kind.FOOD`）。
## `sell_price` / `order` / `display_name` / `description` / `tags` 两种都用。
##
## 产出参数（冷却、收获、涓流、库存上限、解锁条件）在 `HarvestDef` 里，不在这里：
## 一条采集点是一条五级升级线，塞进物品表会让中间品和水都挂一串空字段。

## 物品大类：材料（配方输入 / 采集 / 商店货架）还是食物（成品菜 / 订单 / 招牌）
enum Kind {
	MATERIAL, ## 材料
	FOOD,     ## 食物
}

## 材料的细分档位（只有 `Kind.MATERIAL` 有意义）
enum MaterialKind {
	BASE,         ## 基础材料：桌面采集点产出，商人可买
	INTERMEDIATE, ## 中间材料：只能由配方产出
	FREE,         ## 免费资源：配方自动供给，不累积、不进图鉴
}

const DEFAULT_THEME := "game:theme/base"

## 大类
@export var kind: Kind = Kind.MATERIAL
## 材料档位（仅 `Kind.MATERIAL` 有意义）
@export var material_kind: MaterialKind = MaterialKind.BASE
## 商人单价（铜币，仅材料有意义；<= 0 表示不出售）
@export_range(0, 10000, 1) var merchant_price: int = 0
## 商人收购价（铜币；<= 0 表示没人收，食物同时也不会出现在订单板上）
## 订单酬劳按它推算，所以它同时是这道菜的「市场价值」。
@export_range(0, 10000, 1) var sell_price: int = 0
## 是否进图鉴（水这类免费资源为 false）
@export var in_catalog: bool = true
## 口味/味觉记忆短句（食物）
@export var taste: String = ""
## 未发现时图鉴显示的提示（剪影 + 线索，食物）
@export var catalog_hint: String = ""
## 图鉴排序
@export var order: int = 0
## 食物主题（完整键，如 `game:theme/east_asia`）。主题只用于图鉴筛选与展示，
## 不参与售价 / 订单权重 / 研究池。未写 = `game:theme/base`（家常）。
@export var theme: String = DEFAULT_THEME
## 订单板上被点到的相对权重（0 = 不上订单板；基础菜常被点，费工的菜少被点）
@export_range(0.0, 10.0, 0.1) var order_weight: float = 1.0
## 标签（完整键数组，如 `["game:tag/home", "game:tag/sweet"]`）。
## 标签是可叠加的「场合 / 属性」，与单选、互斥的 `theme` 分工不同：
## 一道菜只能有一个来路，但可以既家常、又适合当宵夜。
## 标签只用于图鉴再筛一层，不参与售价 / 订单权重 / 研究池，也不进图鉴总数。
## 食材标签（`TagDef.scope == INGREDIENT`）还有第二重身份：采集点的出货范围。
@export var tags: Array[String] = []
## 采集档位：这条材料最早从几级的采集点开始出现（1 = 一级就能采到）。
## 采集点按标签摇货，等级越高池子越大——门槛写在材料上，而不是在每个采集点里
## 再抄一遍名单（同一标签下的稀有度是材料自己的属性）。
@export_range(1, 9, 1) var harvest_tier: int = 1
## 商人的哪一级开始上架（第 9 轮反馈 1）。与 harvest_tier 同构：门槛写在材料上，
## 升级表里不抄名单。1 = 开张就能买。
@export_range(1, 9, 1) var merchant_level: int = 1


static func get_type_id() -> String:
	return "item"


## 是食物类物品
func is_food() -> bool:
	return kind == Kind.FOOD


## 是材料类物品
func is_material() -> bool:
	return kind == Kind.MATERIAL


## 是配方自动供给的免费资源（水、清汤这类）：不累积、不占图鉴、商店也不卖
func is_free() -> bool:
	return kind == Kind.MATERIAL and material_kind == MaterialKind.FREE


static func get_codec() -> Codec:
	var fields := GameDef.base_fields()
	fields.append(GameDef._opt_int("kind", Kind.MATERIAL))
	fields.append(GameDef._opt_int("material_kind", MaterialKind.BASE))
	fields.append(GameDef._opt_int("merchant_price", 0))
	fields.append(GameDef._opt_int("sell_price", 0))
	fields.append(GameDef._opt_bool("in_catalog", true))
	fields.append(GameDef._opt_string("taste", ""))
	fields.append(GameDef._opt_string("catalog_hint", ""))
	fields.append(GameDef._opt_int("order", 0))
	fields.append(GameDef._opt_string("theme", DEFAULT_THEME))
	fields.append(GameDef._opt_float("order_weight", 1.0))
	fields.append(GameDef._opt_strings("tags"))
	fields.append(GameDef._opt_int("harvest_tier", 1))
	fields.append(GameDef._opt_int("merchant_level", 1))
	return Codec.record(MapCodec.build(fields, func(...values): return _from_values(values)))


static func _from_values(values: Array) -> ItemDef:
	var def := ItemDef.new()
	GameDef.apply_base(def, values)
	def.kind = values[4]
	def.material_kind = values[5]
	def.merchant_price = values[6]
	def.sell_price = values[7]
	def.in_catalog = values[8]
	def.taste = values[9]
	def.catalog_hint = values[10]
	def.order = values[11]
	def.theme = values[12]
	def.order_weight = values[13]
	var tag_keys: Array[String] = []
	tag_keys.assign(values[14])
	def.tags = tag_keys
	def.harvest_tier = values[15]
	def.merchant_level = values[16]
	return def
