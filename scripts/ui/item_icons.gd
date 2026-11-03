class_name ItemIcons
extends RefCounted
## 物品图标的唯一入口：材料按 5 族、菜品按 6 族选一个 CC0 线性 SVG。
##
## 以前各面板各写一份「先看海鲜、再看肉」的规则，材料还会掉回首字章，
## 商人和灶台同一件东西可能长得不一样。这里把归类收成一处：
## - 材料：海鲜 / 肉类 / 水果 / 蔬菜 / 杂项；
## - 菜品：米饭 / 汤面 / 烘焙品 / 饮品 / 沙拉 / 主菜。
## 只有分类命中，没有逐条物品美术；缺的只是「这条鱼长什么样」，不是「图标缺失」。

const MATERIAL_ROOT := "material/"
const DISH_ROOT := "dish/"

const SOUP_TOKENS := ["soup", "noodle", "ramen", "pho", "udon", "laksa"]
const DRINK_TOKENS := ["coffee", "espresso", "americano", "cappuccino", "macchiato", "latte",
	"mocha", "brew", "tea", "chai", "juice", "lemonade", "soda", "lassi", "milkshake",
	"smoothie", "cocoa", "water"]
const BAKERY_TOKENS := ["bread", "cake", "cookie", "pie", "toast", "bun", "croissant",
	"bagel", "muffin", "scone", "waffle", "pancake"]
const SEAFOOD_TAG := "game:tag/seafood"
const MEAT_TAG := "game:tag/meat"
const FRUIT_TAG := "game:tag/fruit"
const VEG_TAG := "game:tag/veg"
const VEGETARIAN_TAG := "game:tag/vegetarian"
const SOUP_TAG := "game:tag/soup"


## 物品键可能带命名空间（item/steak）；归类只看最后一段，并按 _ 切词，
## 避免 steak 里的 tea 被误判成饮品。
static func _tokens(key: String) -> PackedStringArray:
	return key.get_file().to_lower().split("_", false)


static func _has_any(tokens: PackedStringArray, needles: Array) -> bool:
	for needle in needles:
		if tokens.has(String(needle)):
			return true
	return false


## 物品卡片的图标路径。group 是配方的分组（drink/bake/steam/meal…），
## 商人页拿不到配方时可以留空，退化成按物品键与标签判断。
static func path_for(item: ItemDef, group := "") -> String:
	if item == null:
		return ""
	# 配方产物有分组：面包、面团、高汤这些中间材料也按「端上桌的样子」画，
	# 否则灶台卡上会出现一碗杂项。商人页没有分组，才回到材料 5 族。
	if item.is_food() or not group.is_empty():
		return dish_path(item, group)
	return material_path(item)


## 材料 5 族。标签优先，其次看键里的常见词，最后落杂项。
static func material_path(item: ItemDef) -> String:
	if item == null:
		return MATERIAL_ROOT + "misc.svg"
	if item.tags.has(SEAFOOD_TAG):
		return MATERIAL_ROOT + "seafood.svg"
	if item.tags.has(MEAT_TAG):
		return MATERIAL_ROOT + "meat.svg"
	if item.tags.has(FRUIT_TAG):
		return MATERIAL_ROOT + "fruit.svg"
	if item.tags.has(VEG_TAG) or item.tags.has(VEGETARIAN_TAG):
		return MATERIAL_ROOT + "veg.svg"
	var tokens := _tokens(item.id)
	if _has_any(tokens, ["fish", "shrimp", "prawn", "squid", "crab", "seafood"]):
		return MATERIAL_ROOT + "seafood.svg"
	if _has_any(tokens, ["meat", "beef", "pork", "chicken", "ham", "bacon", "sausage"]):
		return MATERIAL_ROOT + "meat.svg"
	if _has_any(tokens, ["apple", "pear", "berry", "orange", "lemon", "fruit", "banana", "tropical"]):
		return MATERIAL_ROOT + "fruit.svg"
	if _has_any(tokens, ["carrot", "onion", "tomato", "cabbage", "leaf", "leafy", "veg", "vegetable", "potato", "corn", "mushroom", "scallion"]):
		return MATERIAL_ROOT + "veg.svg"
	return MATERIAL_ROOT + "misc.svg"


## 菜品 6 族。顺序有意：汤面/沙拉/米饭的键名比分组更具体，先判定；
## 再按 recipe group 落 drink / bake / steam。
static func dish_path(item: ItemDef, group := "") -> String:
	if item == null:
		return DISH_ROOT + "main.svg"
	if group == "drink":
		return DISH_ROOT + "drink.svg"
	var tokens := _tokens(item.id)
	if _has_any(tokens, SOUP_TOKENS) or item.tags.has(SOUP_TAG):
		return DISH_ROOT + "soup_noodle.svg"
	if _has_any(tokens, ["salad"]):
		return DISH_ROOT + "salad.svg"
	if group == "steam" or _has_any(tokens, ["rice"]):
		return DISH_ROOT + "rice.svg"
	if group == "bake" or _has_any(tokens, BAKERY_TOKENS):
		return DISH_ROOT + "bakery.svg"
	# roast_bean 的键里没有 coffee（只有 roasted + bean），但它是咖啡链的第一站；
	# 不补这一条会画成杂项碗，和旁边的咖啡粉、手冲完全不像一条线。
	if tokens.has("roasted") and tokens.has("bean"):
		return DISH_ROOT + "drink.svg"
	if _has_any(tokens, DRINK_TOKENS):
		return DISH_ROOT + "drink.svg"
	# 半成品（semi）大多没有端上桌的样子：面团、奶油、果酱不该一律画成叉勺主菜。
	# 能命中的（面包→烘焙、咖啡豆→饮品、高汤→汤面）已经先返回；剩下的回到材料 5 族，
	# 至少保留「谷物/乳脂/酱料」的底色差异，而不是整排同一枚主菜章。
	if group == "semi":
		return material_path(item)
	return DISH_ROOT + "main.svg"


## 每个图标族的深色主色：组合图标的底色用它和纸白混合，图形用更深的同色。
## 材料 5 族 + 菜品 6 族各自可区分，避免整排卡片都是同一枚淡蓝印章。
static func accent_for(path: String) -> Color:
	match path.get_file():
		"rice.svg":
			return Color("#b97a33")
		"soup_noodle.svg":
			return Color("#b4553f")
		"bakery.svg":
			return Color("#b0833f")
		"drink.svg":
			return Color("#3f7d86")
		"salad.svg":
			return Color("#5f7a45")
		"main.svg":
			return Color("#9a5b6e")
		"veg.svg":
			return Color("#5d8447")
		"fruit.svg":
			return Color("#b85b4a")
		"meat.svg":
			return Color("#9c4b42")
		"seafood.svg":
			return Color("#4a7892")
		"misc.svg":
			return Color("#7a6a55")
	return PanelKit.ACCENT_DEEP


## 按标签要料（「随便一种蔬菜」）时，色章也画对应族的图标。
static func tag_path(tag_key: String) -> String:
	match tag_key:
		SEAFOOD_TAG:
			return MATERIAL_ROOT + "seafood.svg"
		MEAT_TAG:
			return MATERIAL_ROOT + "meat.svg"
		FRUIT_TAG:
			return MATERIAL_ROOT + "fruit.svg"
		VEG_TAG, VEGETARIAN_TAG:
			return MATERIAL_ROOT + "veg.svg"
	return MATERIAL_ROOT + "misc.svg"
