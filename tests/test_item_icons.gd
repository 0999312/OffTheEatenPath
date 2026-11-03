extends GutTest
## 图标归类：材料只落 5 族、菜品只落 6 族；蒸包不能被「bun」误判成汤面。
## 这里直接遍历 294 条物品，保证没有空路径、没有指向未导入的 SVG。

const MATERIAL_PATHS := [
	"material/seafood.svg",
	"material/meat.svg",
	"material/fruit.svg",
	"material/veg.svg",
	"material/misc.svg",
]
const DISH_PATHS := [
	"dish/rice.svg",
	"dish/soup_noodle.svg",
	"dish/bakery.svg",
	"dish/drink.svg",
	"dish/salad.svg",
	"dish/main.svg",
]


func _registry() -> DataRegistry:
	return RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry


func _item(key: String) -> ItemDef:
	var def := _registry().get_def(key)
	assert_not_null(def, "测试前提：%s 存在" % key)
	return def as ItemDef


func test_every_item_maps_to_an_existing_icon() -> void:
	var seen := 0
	for def in _registry().get_all_defs():
		var item := def as ItemDef
		if item == null:
			continue
		seen += 1
		var path := ItemIcons.path_for(item)
		assert_true(ResourceLoader.exists("res://assets/icons/" + path), "%s 的图标应已导入：%s" % [item.id, path])
		if item.is_food():
			assert_has(DISH_PATHS, path, "菜品只能落 6 族：%s" % item.id)
		else:
			assert_has(MATERIAL_PATHS, path, "材料只能落 5 族：%s" % item.id)
	assert_eq(seen, 359, "物品总数与基线一致（R16.2 新增酸奶材料）")


func test_material_families() -> void:
	assert_eq(ItemIcons.path_for(_item("game:item/fish")), "material/seafood.svg")
	assert_eq(ItemIcons.path_for(_item("game:item/bacon")), "material/meat.svg")
	assert_eq(ItemIcons.path_for(_item("game:item/apple")), "material/fruit.svg")
	assert_eq(ItemIcons.path_for(_item("game:item/leafy")), "material/veg.svg")
	assert_eq(ItemIcons.path_for(_item("game:item/salt")), "material/misc.svg")


func test_dish_families() -> void:
	assert_eq(ItemIcons.path_for(_item("game:item/pour_over"), "drink"), "dish/drink.svg")
	assert_eq(ItemIcons.path_for(_item("game:item/noodle_soup")), "dish/soup_noodle.svg")
	assert_eq(ItemIcons.path_for(_item("game:item/caesar_salad")), "dish/salad.svg")
	assert_eq(ItemIcons.path_for(_item("game:item/white_rice"), "steam"), "dish/rice.svg")
	assert_eq(ItemIcons.path_for(_item("game:item/bread"), "bake"), "dish/bakery.svg")
	assert_eq(ItemIcons.path_for(_item("game:item/steak")), "dish/main.svg")


func test_steamed_bun_is_not_soup() -> void:
	# 「bun」曾经在汤面词根里，会把蒸包错画成汤碗；蒸笼分组应优先成米饭族。
	assert_eq(ItemIcons.path_for(_item("game:item/bun"), "steam"), "dish/rice.svg")


## 半成品没有「端上桌的样子」：未知的 semi 不能一律画成主菜叉勺。
## 已能命中的面包仍走烘焙，认不出的面团回材料杂项。
func test_semi_group_falls_back_to_material_family() -> void:
	assert_eq(ItemIcons.path_for(_item("game:item/bread"), "semi"), "dish/bakery.svg")
	assert_eq(ItemIcons.path_for(_item("game:item/dough"), "semi"), "material/misc.svg")


## 烘焙咖啡豆是新手第一道菜；它的键只有 roasted_bean，没有 coffee。
## 不补这条会画成杂项棕碗，和咖啡粉、手冲断成两条视觉链。
func test_roasted_bean_reads_as_drink() -> void:
	assert_eq(ItemIcons.path_for(_item("game:item/roasted_bean"), "semi"), "dish/drink.svg")


## 图标纹理必须裁成方形：图鉴/灶台/商人把图标塞进方框，长条纹理会把图形压扁。
## 这里覆盖全部 11 个族，避免只修了当前截图里的那一个。
func test_icon_textures_are_square() -> void:
	for path in MATERIAL_PATHS + DISH_PATHS:
		var texture := PanelKit.icon_texture(path, 28.0)
		assert_not_null(texture, "图标应能栅格化：%s" % path)
		if texture == null:
			continue
		assert_eq(texture.get_width(), texture.get_height(), "图标纹理必须方形：%s" % path)
		assert_true(texture.get_width() >= 28, "纹理不能比目标尺寸小：%s" % path)


## 组合图标的底色按族区分；同一族内所有材料/菜品共用一种主色。
func test_family_accents_are_distinct_and_readable() -> void:
	var seen := {}
	for path in MATERIAL_PATHS + DISH_PATHS:
		var accent := ItemIcons.accent_for(path)
		assert_gt(accent.get_luminance(), 0.08, "族色不能黑到看不出形状：%s" % path)
		assert_lt(accent.get_luminance(), 0.72, "族色不能淡到和白纸一样：%s" % path)
		seen[accent.to_html(false)] = path
	assert_eq(seen.size(), MATERIAL_PATHS.size() + DISH_PATHS.size(), "11 个族应有 11 种可区分的主色")


## 卡内章默认让鼠标穿透；灶台标签章要能点开成员清单。
## 这个标记必须在 _ready 之后仍然生效，否则标签弹窗会被静默吃掉。
func test_badge_interactive_survives_ready() -> void:
	var passive := ItemBadge.new()
	add_child_autofree(passive)
	assert_eq(passive.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var interactive := ItemBadge.new()
	interactive.set_interactive(true)
	add_child_autofree(interactive)
	assert_eq(interactive.mouse_filter, Control.MOUSE_FILTER_STOP)
