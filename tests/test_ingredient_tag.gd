extends GutTest
## 标签系统接线：框架 TagRegistry 的登记与灌入、食材标签（`MaterialStack.by_tag`）的
## 校验、合计与扣料。
##
## 标签成员只有一处真相：`ItemDef.tags`；TagRegistry 只是它的索引。
## 测试里会临时往全局表塞一条食材标签（现有数据里还没有），用完在 after_each 拔掉。

const REGISTRY_KEY := DataRegistry.REGISTRY_NAME
const TAG_REGISTRY_KEY := DataRegistry.TAG_REGISTRY_KEY
const TEST_TAG := "game:tag/test_veg"
const ONION := "game:item/onion"
const TOMATO := "game:item/tomato"
const LATTE := "game:item/latte"

var _data: DataRegistry
var _installed := false


func before_each() -> void:
	var registry_manager := get_node_or_null("/root/RegistryManager")
	if registry_manager == null or not registry_manager.has_registry(REGISTRY_KEY):
		return
	_data = registry_manager.get_registry(REGISTRY_KEY) as DataRegistry
	GameState.reset()


func after_each() -> void:
	_remove_test_tag()
	GameState.reset()


# --- 注册表接线 ------------------------------------------------------------


func test_tag_registry_is_registered() -> void:
	assert_not_null(DataRegistry.tag_registry(), "GameBootstrap 应把 TagRegistry 登记进 RegistryManager")


func test_every_tag_def_lands_in_the_registry() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	var registry := DataRegistry.tag_registry()
	assert_not_null(registry)
	for def in _data.get_defs_of_type("tag"):
		var tag := def as TagDef
		assert_not_null(registry.get_tag(ResourceLocation.from_string(tag.get_key())),
				"%s 应已登记成标签" % tag.get_key())


## 成员跟着 `ItemDef.tags` 走：注册表里查到的，必须和数据里挂的一致
func test_registry_members_match_item_tags() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	var registry := DataRegistry.tag_registry()
	var sweet := ResourceLocation.from_string("game:tag/sweet")
	assert_true(registry.has_entry_in_tag(sweet, ResourceLocation.from_string(LATTE)), "拿铁应带甜品饮品标签")
	for def in _data.get_defs_of_type("item"):
		var item := def as ItemDef
		for tag_key in item.tags:
			assert_true(registry.has_entry_in_tag(ResourceLocation.from_string(tag_key),
					ResourceLocation.from_string(item.get_key())),
					"%s 应出现在 %s 的成员里" % [item.get_key(), tag_key])


func test_rebuild_is_idempotent() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	var registry := DataRegistry.tag_registry()
	var sweet := ResourceLocation.from_string("game:tag/sweet")
	var before_count := registry.get_all_entries_of_tag(sweet).size()
	assert_true(_data.rebuild_tags().is_empty(), "重建标签索引不该报问题")
	assert_eq(registry.get_all_entries_of_tag(sweet).size(), before_count, "重复重建不该翻倍")


## 随内容发布的标签分两类：9 条场合标签（图鉴筛选）与 6 条食材标签（配方输入通配）
func test_shipped_tags_are_split_into_two_scopes() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	var ingredient: Array[String] = []
	for def in _data.get_defs_of_type("tag"):
		var tag := def as TagDef
		if tag.is_ingredient():
			ingredient.append(tag.get_key())
	ingredient.sort()
	assert_eq(ingredient.size(), 7, "食材标签应有七条（肉 / 蔬 / 果 / 海鲜 / 杂货 / 畜牧 / 巧克力）")
	assert_eq(ingredient,
		["game:tag/chocolate", "game:tag/fruit", "game:tag/livestock", "game:tag/meat", "game:tag/pantry", "game:tag/seafood", "game:tag/veg"] as Array[String])


# --- 校验 ------------------------------------------------------------------


func test_stack_requires_material_or_tag() -> void:
	var registry := _scratch_registry()
	var stack := MaterialStack.new()
	stack.amount = 1
	assert_true(_mentions(registry._validate_stack("测试", stack), "至少填一个"), "两样都空应报错")


func test_stack_rejects_both_material_and_tag() -> void:
	var registry := _scratch_registry()
	var stack := MaterialStack.new()
	stack.material = ONION
	stack.by_tag = TEST_TAG
	assert_true(_mentions(registry._validate_stack("测试", stack), "二选一"), "同时填两样应报错")


func test_stack_rejects_catalog_tag() -> void:
	var registry := _scratch_registry()
	registry.register_def(_tag_def("tag/sweet", TagDef.Scope.FOOD))
	registry.register_def(_item_def("item/onion"))
	var stack := MaterialStack.new()
	stack.by_tag = "game:tag/sweet"
	assert_true(_mentions(registry._validate_stack("测试", stack), "不能当配方输入"),
			"图鉴标签不能当 by_tag")


func test_stack_rejects_empty_ingredient_tag() -> void:
	var registry := _scratch_registry()
	registry.register_def(_tag_def("tag/veg", TagDef.Scope.INGREDIENT))
	var stack := MaterialStack.new()
	stack.by_tag = "game:tag/veg"
	assert_true(_mentions(registry._validate_stack("测试", stack), "底下没有任何物品"),
			"空标签的配方永远凑不齐，应在校验期报出来")


func test_stack_accepts_ingredient_tag_with_members() -> void:
	var registry := _scratch_registry()
	registry.register_def(_tag_def("tag/veg", TagDef.Scope.INGREDIENT))
	registry.register_def(_item_def("item/onion", ["game:tag/veg"]))
	var stack := MaterialStack.new()
	stack.by_tag = "game:tag/veg"
	assert_eq(registry._validate_stack("测试", stack), [] as Array[String], "有成员的食材标签应通过")


func test_material_cannot_wear_catalog_tag() -> void:
	var registry := _scratch_registry()
	registry.register_def(_tag_def("tag/sweet", TagDef.Scope.FOOD))
	registry.register_def(_item_def("item/onion", ["game:tag/sweet"]))
	var issues: Array[String] = []
	for def in registry.get_defs_of_type("item"):
		issues.append_array(registry._validate_item("测试", def as ItemDef))
	assert_true(_mentions(issues, "材料只能挂 ingredient 标签"), "材料不该挂图鉴标签")


# --- 合计与扣料 ------------------------------------------------------------


func test_count_for_tag_sums_members() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	_install_test_tag()
	GameState.add_item(ONION, 1)
	GameState.add_item(TOMATO, 3)
	var stack := _tag_stack(2)
	assert_eq(GameState.count_for(stack), 4, "按标签要料时手上有多少是成员合计")
	assert_true(GameState.can_consume([stack]), "合计够就能做")


func test_consume_drains_smallest_members_first() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	_install_test_tag()
	GameState.add_item(ONION, 1)
	GameState.add_item(TOMATO, 3)
	GameState._consume([_tag_stack(2)])
	assert_eq(GameState.get_amount(ONION), 0, "先清掉只有 1 份的洋葱")
	assert_eq(GameState.get_amount(TOMATO), 2, "再从未动过的番茄里扣 1")


func test_cannot_consume_more_than_the_tag_holds() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	_install_test_tag()
	GameState.add_item(ONION, 1)
	var stack := _tag_stack(2)
	assert_false(GameState.can_consume([stack]), "只凑得出 1 份，要 2 份应被拒")


func test_has_tag_reads_the_registry() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	assert_true(GameState.has_tag(LATTE, "game:tag/sweet"), "拿铁属于甜品饮品标签")
	assert_false(GameState.has_tag(LATTE, "game:tag/home"), "拿铁不是家常菜")
	assert_false(GameState.has_tag(LATTE, "game:tag/does_not_exist"), "不存在的标签查出来应是 false")


# --- 辅助 ------------------------------------------------------------------


func _scratch_registry() -> DataRegistry:
	return DataRegistry.new()


func _tag_def(id: String, scope: TagDef.Scope) -> TagDef:
	var def := TagDef.new()
	def.namespace_id = GameDef.DEFAULT_NAMESPACE
	def.id = id
	def.display_name = "data.%s.name" % id.replace("/", ".")
	def.description = "data.%s.desc" % id.replace("/", ".")
	def.scope = scope
	return def


func _item_def(id: String, tags: Array = []) -> ItemDef:
	var def := ItemDef.new()
	def.namespace_id = GameDef.DEFAULT_NAMESPACE
	def.id = id
	def.display_name = "data.%s.name" % id.replace("/", ".")
	def.description = "data.%s.desc" % id.replace("/", ".")
	def.kind = ItemDef.Kind.MATERIAL
	def.material_kind = ItemDef.MaterialKind.BASE
	def.tags.assign(tags)
	return def


func _tag_stack(amount: int) -> MaterialStack:
	var stack := MaterialStack.new()
	stack.by_tag = TEST_TAG
	stack.amount = amount
	return stack


func _mentions(issues: Array[String], needle: String) -> bool:
	for issue in issues:
		if issue.contains(needle):
			return true
	return false


## 临时造一条食材标签，挂到洋葱与番茄上，并重建索引
func _install_test_tag() -> void:
	_data.register_def(_tag_def("tag/test_veg", TagDef.Scope.INGREDIENT))
	(_data.get_def(ONION) as ItemDef).tags.append(TEST_TAG)
	(_data.get_def(TOMATO) as ItemDef).tags.append(TEST_TAG)
	_data.rebuild_tags()
	_installed = true


## 拆掉临时标签并重建索引，恢复真实数据的样子
func _remove_test_tag() -> void:
	if not _installed:
		return
	_installed = false
	for key in [ONION, TOMATO]:
		var item := _data.get_def(key) as ItemDef
		if item != null:
			item.tags.erase(TEST_TAG)
	_data.unregister(ResourceLocation.from_string(TEST_TAG))
	_data.rebuild_tags()
