extends GutTest
## P1 数据层验收：注册表接入、静态内容加载、跨条目校验、Codec 往返。
##
## 这些用例只读被 GameBootstrap 加载好的 DataRegistry，不修改全局状态；
## 唯一会动的用例（load_all 幂等）结束后注册表内容与开始时一致。

const REGISTRY_KEY := DataRegistry.REGISTRY_NAME

var _data: DataRegistry
# 有两条用例会把语言切到 zh_CN：跑完必须还回去，否则后面所有脚本都活在中文里，
# CI（初始 en）与本地（初始 zh）就会跑出两套结果。
var _original_language := ""

func before_each() -> void:
	_original_language = I18NManager.get_current_language()
	var registry_manager := get_node_or_null("/root/RegistryManager")
	assert_not_null(registry_manager, "RegistryManager autoload 应存在（由 mc_game_framework 提供）")
	if registry_manager == null:
		return
	if not registry_manager.has_registry(REGISTRY_KEY):
		return
	_data = registry_manager.get_registry(REGISTRY_KEY) as DataRegistry

func after_each() -> void:
	I18NManager.set_language(_original_language)

func test_data_registry_is_registered() -> void:
	assert_not_null(_data, "GameBootstrap 应把 \"%s\" 注册表注册为 DataRegistry" % REGISTRY_KEY)

func test_all_defs_loaded_from_game_data() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	var defs := _data.get_all_defs()
	assert_gt(defs.size(), 0, "resources/game_data/ 下应至少加载到一条定义")
	for def in defs:
		assert_not_null(def.get_script(), "定义 %s 应带脚本" % def.get_key())
		assert_eq(def.namespace_id, DataRegistry.GAME_NAMESPACE, "定义 %s 应使用 game 命名空间" % def.get_key())

func test_defs_of_each_type_exist() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	for type_id in ["item", "recipe", "facility", "letter", "world"]:
		assert_gt(_data.get_defs_of_type(type_id).size(), 0, "缺少 %s 类型定义" % type_id)

func test_sample_material_fields() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	I18NManager.set_language("zh_CN")
	var bean := _data.get_def("game:item/coffee_bean") as ItemDef
	assert_not_null(bean, "示例材料 game:item/coffee_bean 应存在")
	if bean == null:
		return
	assert_eq(bean.display_name, "data.item.coffee_bean.name", "P3 起 .tres 存翻译键")
	assert_eq(bean.localized(), "咖啡生豆", "按当前语言取出的显示名")
	assert_eq(bean.kind, ItemDef.Kind.MATERIAL)
	assert_eq(bean.material_kind, ItemDef.MaterialKind.BASE)
	var mailbox := GameState.get_harvest_for_material("game:item/coffee_bean")
	assert_not_null(mailbox, "咖啡生豆应有来路（杂货信箱）")
	if mailbox != null:
		assert_eq(mailbox.get_key(), "game:harvest/mailbox", "咖啡生豆属于杂货那一类")
	assert_eq(bean.merchant_price, 2)
	assert_true(bean.in_catalog)

	var water := _data.get_def("game:item/water") as ItemDef
	assert_not_null(water, "水应作为 ItemDef 存在")
	if water != null:
		assert_eq(water.material_kind, ItemDef.MaterialKind.FREE)
		assert_false(water.in_catalog, "水不进图鉴")

func test_sample_recipe_references_resolve() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	var recipe := _data.get_def("game:recipe/americano") as RecipeDef
	assert_not_null(recipe, "示例配方 game:recipe/americano 应存在")
	if recipe == null:
		return
	assert_eq(recipe.output, "game:item/americano")
	assert_eq(recipe.inputs.size(), 2, "美式配方应为 浓缩 + 水")
	assert_almost_eq(recipe.duration_seconds, 5.0, 0.0001, "美式现在是 5 秒（兑换水是即时动作）")
	assert_false(recipe.needs_facility(), "美式不需要设备")
	assert_not_null(_data.get_def(recipe.output), "配方产出应能解析")
	assert_eq(recipe.inputs[0].material, "game:item/espresso", "成品即材料：美式的输入引用食物定义")

func test_food_can_be_recipe_input() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	var latte := _data.get_def("game:recipe/latte") as RecipeDef
	assert_not_null(latte, "示例配方 game:recipe/latte 应存在")
	if latte == null:
		return
	assert_eq(latte.inputs.size(), 2, "拿铁 = 浓缩 + 牛奶")
	assert_eq(latte.inputs[0].material, "game:item/espresso")
	assert_true(_data.get_def(latte.inputs[0].material) is ItemDef, "拿铁的输入应是 ItemDef")

func test_validation_reports_no_issues() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	var issues := _data.validate()
	assert_eq(issues, [] as Array[String], "静态内容应通过全部校验：%s" % str(issues))

func test_facility_upgrade_chain() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	var machine := _data.get_def("game:facility/coffee_machine") as FacilityDef
	assert_not_null(machine, "设备 game:facility/coffee_machine 应存在")
	if machine == null:
		return
	assert_eq(machine.max_level, 4, "经济 v2：设备扩到 4 级")
	assert_almost_eq(machine.get_speed_factor(1), 1.0, 0.0001)
	assert_almost_eq(machine.get_speed_factor(3), 0.6, 0.0001)
	assert_almost_eq(machine.get_speed_factor(4), 0.5, 0.0001, "4 级再快一档")
	var level_two := machine.get_upgrade(2)
	assert_not_null(level_two, "咖啡机应有升到 2 级的条目")
	if level_two != null:
		assert_eq(level_two.coin_cost, 60, "经济 v2：2 级 60 铜币")
		assert_eq(level_two.materials.size(), 1)
	assert_not_null(machine.get_upgrade(4), "4 级升级应存在")
	assert_null(machine.get_upgrade(5), "超出 max_level 的升级不应存在")

func test_codec_json_roundtrip() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	var recipe := _data.get_def("game:recipe/latte") as RecipeDef
	if recipe == null:
		fail_test("示例配方 game:recipe/latte 应存在")
		return
	var encoded := recipe.to_json_data()
	assert_true(encoded.is_success(), "RecipeDef 应能用 Codec 编码为 JSON：%s" % (encoded.get_error() if encoded.is_error() else ""))

	var json_text := JSON.stringify(encoded.get_value())
	var parsed: Variant = JSON.parse_string(json_text)
	assert_not_null(parsed, "编码结果应能序列化为 JSON 文本")
	if parsed == null:
		return

	var decoded := RecipeDef.get_codec().decode(parsed, JsonOps.INSTANCE)
	# 不能用 CodecResource.from_json_data()：基类的 static 函数里调 get_codec() 是静态绑定，
	# 永远命中 CodecResource 的实现（"No codec defined for resource type"），子类的覆写拿不到。
	# 所以解码一律显式走子类的 get_codec()。
	assert_true(decoded.is_success(), "JSON 应能解码回 RecipeDef：%s" % (decoded.get_error() if decoded.is_error() else ""))
	if not decoded.is_success():
		return
	var copy := decoded.get_value() as RecipeDef
	assert_not_null(copy, "解码结果应是 RecipeDef")
	if copy == null:
		return
	assert_eq(copy.get_key(), recipe.get_key())
	assert_eq(copy.output, recipe.output)
	assert_almost_eq(copy.duration_seconds, recipe.duration_seconds, 0.0001)
	assert_eq(copy.inputs.size(), recipe.inputs.size())
	for i in recipe.inputs.size():
		assert_eq(copy.inputs[i].material, recipe.inputs[i].material)
		assert_eq(copy.inputs[i].amount, recipe.inputs[i].amount)

func test_load_all_is_idempotent() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	var count := _data.get_all_defs().size()
	var issues := _data.load_all()
	assert_eq(issues, [] as Array[String], "重复加载不应产生问题：%s" % str(issues))
	assert_eq(_data.get_all_defs().size(), count, "重复加载后条目数应稳定")

func test_unknown_key_returns_null() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	assert_null(_data.get_def("game:item/does_not_exist"))
	assert_false(_data.has_def("game:item/does_not_exist"))
	assert_null(_data.get_def("not-a-key"), "非法键应安全返回 null")

# --- 导出包兼容：目录里是 .tres.remap -------------------------------------
#
# 导出时资源被二进制化，包里目录列出的名字是 `xxx.tres.remap`，原来的 `xxx.tres` 不在目录里。
# 之前 `_load_dir` 只认 `.tres`/`.res` 后缀，导出包因此一条定义都加载不到——第三方试玩出现
# 「所有数据被清空、开局没法玩」就是这个原因。


func test_resolved_resource_name_strips_remap() -> void:
	assert_eq(DataRegistry.resolved_resource_name("apple.tres.remap"), "apple.tres")
	assert_eq(DataRegistry.resolved_resource_name("apple.res.remap"), "apple.res")
	assert_eq(DataRegistry.resolved_resource_name("apple.tres"), "apple.tres", "编辑器里的裸资源名应原样保留")
	assert_eq(DataRegistry.resolved_resource_name("en.json"), "en.json", "非资源文件不应被改写")


func test_remap_names_are_normalized_and_deduped() -> void:
	# 导出包的目录形态：只有 `.tres.remap`，没有裸 `.tres`
	var exported := DataRegistry.resource_file_names(PackedStringArray([
		"apple.tres.remap", "bob.res.remap", "en.json", "notes.txt",
	]))
	assert_eq(exported, PackedStringArray(["apple.tres", "bob.res"]),
			"导出包里的 .remap 应还原成资源名，非资源文件应被跳过")

	# 编辑器里两种形态并存（比如导入后残留的 remap）：同一份定义只保留一个
	var both := DataRegistry.resource_file_names(PackedStringArray([
		"apple.tres", "apple.tres.remap",
	]))
	assert_eq(both, PackedStringArray(["apple.tres"]), "两种形态并存时只加载一次，否则会报键重复")

# --- 物品同表之后的校验（C 方案） -----------------------------------------
#
# 材料与食物合并成一张表之后，类型系统只剩「这是不是物品」一层，
# 挡不住「这块肉被写成了菜」，也挡不住「食物被当成别的类型」。
# 下面三条用例都跑在**独立的数据层实例**上，喂合成数据看校验怎么报，
# 不碰 GameBootstrap 加载好的全局 DataRegistry。


func _scratch_registry() -> DataRegistry:
	return DataRegistry.new()


func _make_item(id: String) -> ItemDef:
	var item := ItemDef.new()
	item.id = id
	item.display_name = "data.%s.name" % id.replace("/", ".")
	item.description = "data.%s.desc" % id.replace("/", ".")
	return item


func _mentions(issues: Array[String], needle: String) -> bool:
	for issue in issues:
		if issue.contains(needle):
			return true
	return false


func test_item_validation_dispatches_by_kind() -> void:
	var data := _scratch_registry()
	var food := _make_item("item/zz_food")
	food.kind = ItemDef.Kind.FOOD
	food.merchant_price = 5
	food.sell_price = 9
	var food_issues := data._validate_def(food)
	assert_true(_mentions(food_issues, "taste 为空"), "食物缺 taste 应报错：%s" % str(food_issues))
	assert_true(_mentions(food_issues, "倒卖"), "卖价高于买价应报倒卖：%s" % str(food_issues))

	var material := _make_item("item/zz_material")
	material.kind = ItemDef.Kind.MATERIAL
	material.taste = "data.item.zz_material.taste"
	material.catalog_hint = "data.item.zz_material.hint"
	var material_issues := data._validate_def(material)
	assert_true(_mentions(material_issues, "taste 是食物专用字段"), "材料写 taste 应报错：%s" % str(material_issues))
	assert_true(_mentions(material_issues, "catalog_hint 是食物专用字段"), "材料写 catalog_hint 应报错：%s" % str(material_issues))

	# kind 是 FOOD 却挂着材料档位：这是把中间的合成品直接标成菜，得挑出来
	var fake_food := _make_item("item/zz_fake_food")
	fake_food.kind = ItemDef.Kind.FOOD
	fake_food.taste = "data.item.zz_fake_food.taste"
	fake_food.material_kind = ItemDef.MaterialKind.FREE
	assert_true(_mentions(data._validate_def(fake_food), "食物不该有 material_kind"),
			"食物挂材料档位应报错")


func test_food_is_a_valid_recipe_input() -> void:
	var data := _scratch_registry()
	var espresso := _make_item("item/zz_espresso")
	espresso.kind = ItemDef.Kind.FOOD
	espresso.taste = "data.item.zz_espresso.taste"
	espresso.sell_price = 6
	assert_true(data.register_def(espresso), "合成食物应能登记")

	var stack := MaterialStack.new()
	stack.material = espresso.get_key()
	stack.amount = 1
	var recipe := RecipeDef.new()
	recipe.id = "recipe/zz_americano"
	recipe.display_name = "data.recipe.zz_americano.name"
	recipe.output = espresso.get_key()
	recipe.inputs.append(stack)
	recipe.duration_seconds = 1.0
	var issues := data._validate_def(recipe)
	assert_false(_mentions(issues, "不能作为堆叠物品"), "食物应能当配方输入：%s" % str(issues))
	assert_false(_mentions(issues, "期望 item"), "食物应能当配方输出/输入：%s" % str(issues))
	assert_eq(issues, [] as Array[String], "这条合成配方应完全通过校验：%s" % str(issues))


func test_recipe_inputs_are_capped_at_nine_kinds() -> void:
	var data := _scratch_registry()
	var recipe := RecipeDef.new()
	recipe.id = "recipe/zz_too_many_inputs"
	recipe.display_name = "data.recipe.zz_too_many_inputs.name"
	recipe.output = "game:item/zz_out"
	recipe.duration_seconds = 1.0
	for i in RecipeDef.MAX_INPUT_KINDS + 1:
		var stack := MaterialStack.new()
		stack.material = "game:item/zz_in_%d" % i
		stack.amount = 1
		recipe.inputs.append(stack)
	var issues := data._validate_def(recipe)
	assert_true(_mentions(issues, "上限"), "超过 %d 种原料应报错：%s"
			% [RecipeDef.MAX_INPUT_KINDS, str(issues)])


func test_harvest_tag_must_be_an_ingredient_tag_with_base_members() -> void:
	var data := _scratch_registry()
	# 一条合法的食材标签 + 一个基础材料成员
	var tag := TagDef.new()
	tag.id = "tag/zz_veg"
	tag.display_name = "data.tag.zz_veg.name"
	tag.description = "data.tag.zz_veg.desc"
	tag.scope = TagDef.Scope.INGREDIENT
	assert_true(data.register_def(tag))
	var leafy := _make_item("item/zz_leafy")
	leafy.kind = ItemDef.Kind.MATERIAL
	leafy.material_kind = ItemDef.MaterialKind.BASE
	leafy.tags.assign(["game:tag/zz_veg"])
	assert_true(data.register_def(leafy))

	var harvest := _make_harvest("harvest/zz_point", "game:tag/zz_veg")
	assert_eq(data._validate_def(harvest), [] as Array[String], "指向食材标签的采集点应通过校验：%s"
		% str(data._validate_def(harvest)))

	# 1) 没填标签
	var empty := _make_harvest("harvest/zz_empty", "")
	assert_true(_mentions(data._validate_def(empty), "tag 为空"), "不填标签应报错")

	# 2) 指向不存在的标签
	var missing := _make_harvest("harvest/zz_missing", "game:tag/zz_nope")
	assert_true(_mentions(data._validate_def(missing), "指向不存在的标签"), "标签不存在应报错")

	# 3) 指向图鉴标签（scope=food）
	var home := _make_tag("tag/zz_home", TagDef.Scope.FOOD)
	assert_true(data.register_def(home))
	var wrong_scope := _make_harvest("harvest/zz_scope", "game:tag/zz_home")
	assert_true(_mentions(data._validate_def(wrong_scope), "必须是食材标签"), "图鉴标签不能当采集池")

	# 4) 标签底下只有中间品
	var jam_tag := _make_tag("tag/zz_jam", TagDef.Scope.INGREDIENT)
	assert_true(data.register_def(jam_tag))
	var jam := _make_item("item/zz_jam")
	jam.kind = ItemDef.Kind.MATERIAL
	jam.material_kind = ItemDef.MaterialKind.INTERMEDIATE
	jam.tags.assign(["game:tag/zz_jam"])
	assert_true(data.register_def(jam))
	var no_base := _make_harvest("harvest/zz_jam", "game:tag/zz_jam")
	assert_true(_mentions(data._validate_def(no_base), "没有可采集的基础材料"), "中间品不能采集")

	# 5) 标签底下的基础材料都太稀有（等级 1 摇不出来）
	leafy.harvest_tier = 3
	assert_true(_mentions(data._validate_def(harvest), "没有 harvest_tier = 1"), "1 级池子空着应报错")
	leafy.harvest_tier = 1

	# 6) 成员等级超过采集点最高等级
	leafy.harvest_tier = 9
	assert_true(_mentions(data._validate_def(harvest), "超出采集点最高等级"), "永远摇不到应报错")


func _make_harvest(id: String, tag: String) -> HarvestDef:
	var harvest := HarvestDef.new()
	harvest.id = id
	harvest.tag = tag
	harvest.display_name = "data.%s.name" % id.replace("/", ".")
	harvest.description = "data.%s.desc" % id.replace("/", ".")
	harvest.cooldown_seconds.assign([1.0])
	harvest.yield_per_click.assign([1])
	harvest.trickle_per_second.assign([0.0])
	return harvest


func _make_tag(id: String, scope: TagDef.Scope) -> TagDef:
	var tag := TagDef.new()
	tag.id = id
	tag.display_name = "data.%s.name" % id.replace("/", ".")
	tag.description = "data.%s.desc" % id.replace("/", ".")
	tag.scope = scope
	return tag

