extends GutTest
## P10.15 回归：材料「收集到就记录」，不等到拿去用。
##
## 第三轮试玩反馈原文：「材料不应当是使用后才记录 —— 应当每次收集到就被记录到图鉴里。」
## 代码路径本来就是 add_item() -> _maybe_discover()（game_state.gd:555 / :699），
## 这组用例把「采集、购买、图鉴页面」三条玩家能看到的链路钉住，防止以后有人把
## 点亮挪到扣料 / 做饭才触发。

const MAILBOX := "game:harvest/mailbox"
const BUTTER := "game:item/butter"


func before_each() -> void:
	GameState.reset()


func after_each() -> void:
	UIManager.close_all()
	await wait_process_frames(1)


func _data() -> DataRegistry:
	return RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry


func _label_texts(root: Node) -> Array[String]:
	var texts: Array[String] = []
	for node in root.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	return texts


## 采集这一下摇到的每一样，都该当场点亮；库存也确实增加了
func test_gathering_marks_every_gained_material_as_discovered() -> void:
	var gained := GameState.harvest_with_result(MAILBOX)
	assert_gt(gained.size(), 0, "一级货箱一采至少给一样")
	for key in gained:
		assert_true(GameState.is_discovered(String(key)), "%s 采到就该点亮图鉴" % key)
		assert_gt(GameState.get_amount(String(key)), 0, "%s 应已入库" % key)


## 已记录数当场 +N：不必等做饭消耗，也不用重开面板
func test_gathering_moves_the_catalog_counter_right_away() -> void:
	var before := GameState.get_catalog_discovered_count()
	var gained := GameState.harvest_with_result(MAILBOX)
	assert_eq(GameState.get_catalog_discovered_count(), before + gained.size(),
		"每样新材料各算一条记录")


## 商人买入也走同一条路（玩家分不清「采的」和「买的」，两条都得不掉队）
func test_buying_marks_the_material_too() -> void:
	GameState.add_coins(100, "测试")
	assert_true(GameState.buy_material(BUTTER, 1), "货架上有黄油就该买得到")
	assert_true(GameState.is_discovered(BUTTER), "买到手就点亮图鉴")
	assert_eq(GameState.get_amount(BUTTER), 1)


## 玩家看到的那一层：刚采到的材料，图鉴材料页里是真名，不是「？？？」
func test_catalog_lists_a_freshly_gathered_material_by_name() -> void:
	var gained := GameState.harvest_with_result(MAILBOX)
	var key := String(gained.keys()[0])
	var def := _data().get_def(key) as ItemDef
	assert_not_null(def, "刚采到的材料应有定义")
	if def == null:
		return
	var material_name := def.localized()

	UIManager.close_all()
	await wait_process_frames(1)
	var panel := UIManager.open_panel(ResourceLocation.from_string("idle_food:catalog"), {"tab": "material"}) as CatalogPanel
	await wait_process_frames(1)
	assert_not_null(panel, "书架应能打开")
	if panel == null:
		return
	panel._keyword = material_name
	panel._filter = 1  # 只看已记录，免得别的未记录条目的线索句恰好含这个词
	panel._fill_page(0)
	await wait_process_frames(1)

	var texts := _label_texts(panel.content)
	assert_true(texts.has(material_name), "刚采到的 %s 应显示真名" % material_name)
	assert_false(texts.has(I18n.t("ui.catalog.unknown")), "按真名搜到后不该再剩影子行")
