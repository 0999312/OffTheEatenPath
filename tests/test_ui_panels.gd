extends GutTest
## P3 界面层回归测试：面板登记齐全、面板开关、信件详情发奖、离线面板、HUD 绑定、主场景冒烟。
##
## 面板一律走 UIManager（真实栈），而不是直接 new 脚本，
## 这样测试覆盖的是「玩家真的点开」的那条链路。

const COFFEE_BEAN := "game:item/coffee_bean"
const WINDOW_LETTER := "game:letter/window"
const TMP_DIR := "res://tests/tmp"
const SMOKE_SAVE := "res://tests/tmp/smoke_save.json"

const NORMAL_PANELS: Array[String] = [
	"idle_food:craft",
	"idle_food:orders",
	"idle_food:catalog",
	"idle_food:facility",
	"idle_food:merchant",
	"idle_food:warehouse",
	"idle_food:mail",
	"idle_food:settings",
]


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	GameState.reset()


func after_each() -> void:
	UIManager.close_all()
	await wait_process_frames(1)
	if FileAccess.file_exists(SMOKE_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SMOKE_SAVE))


# --- 登记表 ---------------------------------------------------------------


func test_every_declared_panel_is_registered() -> void:
	var registry := RegistryManager.get_registry("ui") as UIRegistry
	assert_not_null(registry, "应有 ui 注册表")
	for panel_key in GameBootstrap.PANEL_DEFS:
		var location := ResourceLocation.from_string(String(panel_key))
		assert_not_null(location, "面板 ID 应可解析：%s" % panel_key)
		if location != null and registry != null:
			assert_true(registry.has_entry(location), "面板应已登记：%s" % panel_key)


func test_panel_defs_use_expected_layers() -> void:
	# POPUP 只给「压在别的界面之上」的几种：诊断、信件详情、图鉴详情、离线结算
	var popup_panels: Array[String] = GameBootstrap.get_popup_panel_ids()
	assert_eq(popup_panels.size(), 4, "诊断 + 信件详情 + 图鉴详情 + 离线结算应为 POPUP")
	assert_true(popup_panels.has("idle_food:letter_detail"))
	assert_true(popup_panels.has("idle_food:catalog_detail"))
	assert_true(popup_panels.has("idle_food:offline"))


# --- 开关 -----------------------------------------------------------------


func test_normal_panels_open_and_close() -> void:
	for panel_key in NORMAL_PANELS:
		var location := ResourceLocation.from_string(panel_key)
		var panel: UIPanel = UIManager.open_panel(location)
		assert_not_null(panel, "应能打开面板：%s" % panel_key)
		assert_true(UIManager.is_panel_open(location), "打开后 is_panel_open 应为 true：%s" % panel_key)
		UIManager.close_panel(location)
		assert_false(UIManager.is_panel_open(location), "关闭后 is_panel_open 应为 false：%s" % panel_key)
		await wait_process_frames(1)


func test_letter_detail_reads_letter_and_keeps_the_gift() -> void:
	assert_almost_eq(GameState.get_amount(COFFEE_BEAN), 0.0, 0.0001, "读信之前没有礼物")

	var location := ResourceLocation.from_string("idle_food:letter_detail")
	var panel: UIPanel = UIManager.open_panel(location, {"letter": WINDOW_LETTER})
	assert_not_null(panel, "应能打开信件详情")
	assert_true(panel is LetterDetailPanel, "信件详情应使用 LetterDetailPanel 脚本")
	assert_true(GameState.is_letter_read(WINDOW_LETTER), "打开即算读过")
	assert_almost_eq(GameState.get_amount(COFFEE_BEAN), 5.0, 0.0001, "信里的 5 颗咖啡生豆应到账")

	UIManager.close_panel(location)
	await wait_process_frames(1)


func test_letter_detail_without_reward_does_not_crash() -> void:
	# 缺 letter 参数时面板应当只是空着，而不是炸掉
	var location := ResourceLocation.from_string("idle_food:letter_detail")
	var panel: UIPanel = UIManager.open_panel(location)
	assert_not_null(panel, "即使没带参数也应能打开（显示空状态）")
	UIManager.close_panel(location)
	await wait_process_frames(1)


func test_offline_panel_shows_summary() -> void:
	var summary := OfflineSummary.new()
	summary.elapsed_seconds = 3.0 * 3600.0 + 12.0 * 60.0
	summary.gains = [{"name": "咖啡生豆", "delta": 5760.0}]
	summary.coins_gained = 0
	summary.offline_unlocked = true

	var location := ResourceLocation.from_string("idle_food:offline")
	var panel: UIPanel = UIManager.open_panel(location, {"summary": summary})
	assert_not_null(panel, "应能打开离线结算")
	assert_true(panel is OfflinePanel, "离线结算应使用 OfflinePanel 脚本")

	UIManager.close_panel(location)
	await wait_process_frames(1)


func test_catalog_row_opens_detail_popup() -> void:
	GameState.discover(COFFEE_BEAN)
	var catalog_location := ResourceLocation.from_string("idle_food:catalog")
	var panel: UIPanel = UIManager.open_panel(catalog_location, {"tab": "material"})
	assert_not_null(panel, "应能打开书架")
	assert_true(panel is CatalogPanel, "书架应使用 CatalogPanel 脚本")

	var view: Button = null
	for node in panel.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == "查看" and not button.disabled:
			view = button
			break
	assert_not_null(view, "已发现的条目应有可用的「查看」按钮")
	if view != null:
		view.pressed.emit()
		await wait_process_frames(1)

	var detail_location := ResourceLocation.from_string("idle_food:catalog_detail")
	assert_true(UIManager.is_panel_open(detail_location), "查看应打开图鉴详情弹层")
	UIManager.close_panel(detail_location)
	UIManager.close_panel(catalog_location)
	await wait_process_frames(1)


func test_catalog_detail_renders_full_entry() -> void:
	GameState.discover(COFFEE_BEAN)
	var location := ResourceLocation.from_string("idle_food:catalog_detail")
	var panel: UIPanel = UIManager.open_panel(location, {"key": COFFEE_BEAN, "type": "material"})
	assert_not_null(panel, "应能直接打开图鉴详情")
	assert_true(panel is CatalogDetailPanel, "详情应使用 CatalogDetailPanel 脚本")
	if panel != null:
		assert_true(panel.get_child_count() > 0, "详情应有内容")
	UIManager.close_panel(location)
	await wait_process_frames(1)


## 第十轮反馈 5：图鉴条目末尾的「它可以做…」——反查下游配方，点一下就换到那条
## 配方的详情（就地换，不走 UIManager 的同 id 防重复）。
func test_catalog_detail_lists_downstream_recipes_and_jumps() -> void:
	GameState.discover("game:item/coffee_ground")
	GameState.discover("game:recipe/pour_over")
	var location := ResourceLocation.from_string("idle_food:catalog_detail")
	var panel := UIManager.open_panel(location, {"key": "game:item/coffee_ground", "type": "material"}) as CatalogDetailPanel
	assert_not_null(panel, "应能打开研磨咖啡（半成品）的图鉴条目")
	if panel == null:
		return
	var fold: FoldableContainer = null
	for node in panel.content.find_children("*", "FoldableContainer", true, false):
		var candidate := node as FoldableContainer
		if candidate != null and candidate.title == I18n.t("ui.craft.used_in"):
			fold = candidate
			break
	assert_not_null(fold, "记录过的材料应出现「它可以做…」")
	if fold == null:
		UIManager.close_panel(location)
		return
	fold.folded = false
	await wait_process_frames(1)
	var pour_over := panel.def_of("game:recipe/pour_over") as RecipeDef
	assert_not_null(pour_over, "滴滤咖啡配方应存在")
	var output := panel.def_of(pour_over.output) as ItemDef
	var button: Button = null
	for node in fold.find_children("*", "Button", true, false):
		var candidate := node as Button
		if candidate != null and candidate.text == output.localized():
			button = candidate
			break
	assert_not_null(button, "下游按钮应写着成品名")
	if button != null:
		button.pressed.emit()
		await wait_process_frames(1)
		assert_eq(panel._key, "game:recipe/pour_over", "点击后详情应就地换成滴滤咖啡的配方")
		assert_eq(panel._type_id, "recipe", "条目类型应随之切换")
	UIManager.close_panel(location)
	await wait_process_frames(1)


func test_catalog_progress_lives_outside_scroll() -> void:
	GameState.discover(COFFEE_BEAN)
	var location := ResourceLocation.from_string("idle_food:catalog")
	var panel := UIManager.open_panel(location, {"tab": "material"}) as CatalogPanel
	assert_not_null(panel, "应能打开书架")
	if panel != null:
		# 文案带数字（「已记录 1 / 56」），取数字前的固定前缀来认这一行
		var prefix := I18n.t("ui.catalog.recorded", [0, 0]).split("0")[0]
		var footer_label: Label = null
		for node in panel.footer.find_children("*", "Label", true, false):
			var label := node as Label
			if label != null and label.text.begins_with(prefix):
				footer_label = label
				break
		assert_not_null(footer_label, "完成度应固定在页脚")
		for node in panel.content.find_children("*", "Label", true, false):
			var label := node as Label
			assert_false(label != null and label.text.begins_with(prefix),
					"完成度不能跟着列表一起滚")
	UIManager.close_panel(location)
	await wait_process_frames(1)


func test_catalog_detail_letter_can_be_read() -> void:
	GameState.discover(WINDOW_LETTER)
	assert_false(GameState.is_letter_read(WINDOW_LETTER), "读之前应是未读")
	var registry := RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry
	var letter: LetterDef = null
	if registry != null:
		letter = registry.get_def(WINDOW_LETTER) as LetterDef
	assert_not_null(letter, "应能取到信件定义")
	var location := ResourceLocation.from_string("idle_food:catalog_detail")
	var panel: UIPanel = UIManager.open_panel(location, {"key": WINDOW_LETTER, "type": "letter"})
	assert_not_null(panel, "应能打开信件图鉴条目")
	await wait_process_frames(1)
	assert_true(GameState.is_letter_read(WINDOW_LETTER), "在图鉴里读正文也应算读过")
	if letter != null and panel != null:
		var body_text := letter.localized(&"body")
		if body_text.is_empty():
			return
		var found := false
		for node in panel.find_children("*", "Label", true, false):
			var label := node as Label
			if label != null and label.text.contains(body_text.left(8)):
				found = true
				break
		assert_true(found, "图鉴详情应能读到信件正文")
	UIManager.close_panel(location)
	await wait_process_frames(1)


func test_offline_panel_tolerates_missing_summary() -> void:
	var location := ResourceLocation.from_string("idle_food:offline")
	var panel: UIPanel = UIManager.open_panel(location)
	assert_not_null(panel, "没有摘要时也应能打开")
	UIManager.close_panel(location)
	await wait_process_frames(1)


## 反馈 9/15：设备页要能直达仓库 / 研究 / 订单。
func test_facility_panel_lists_facilities() -> void:
	GameState.reset()
	var location := ResourceLocation.from_string("idle_food:facility")
	var panel := UIManager.open_panel(location) as FacilityPanel
	assert_not_null(panel, "应能打开设备页")
	await wait_process_frames(1)
	if panel != null:
		var texts: Array[String] = []
		for node in panel.find_children("*", "Label", true, false):
			var label := node as Label
			if label != null:
				texts.append(label.text)
		assert_true(texts.has(I18n.t("ui.facility.section")), "设备页应有「设施」区")
	UIManager.close_panel(location)
	await wait_process_frames(1)



## 反馈 20：所有面板右下角都能看到返回提示；右键（ui_back）和 Esc 走同一条关闭路径。
func test_back_hint_and_right_click_close_the_panel() -> void:
	var location := ResourceLocation.from_string("idle_food:facility")
	var panel: UIPanel = UIManager.open_panel(location)
	await wait_process_frames(2)
	assert_not_null(panel, "应能打开设备页")
	var texts: Array[String] = []
	for node in panel.find_children("*", "Label", true, false):
		texts.append((node as Label).text)
	assert_true(texts.has(I18n.t("ui.hint.back")), "面板右下角应有「右键 / Esc 返回」")
	# 不把 GameBridge 加进树：_ready 会读档、退出会写档，测试只要输入分发这一小段。
	var bridge := GameBridge.new()
	var event := InputEventAction.new()
	event.action = &"ui_back"
	event.pressed = true
	bridge._unhandled_input(event)
	bridge.free()
	await wait_seconds(0.35)
	assert_false(UIManager.is_panel_open(location), "右键应关闭最上面一层面板")


## 反馈 23：成品还能被哪些配方当输入，折叠区要真的列出下家，而不是一句空话。
func test_craft_detail_used_in_lists_followup_recipes() -> void:
	var recipe_key := GameState.recipe_for_output("game:item/bread")
	assert_false(recipe_key.is_empty(), "面包应有一条已可见的配方")
	var location := ResourceLocation.from_string("idle_food:craft")
	var panel := UIManager.open_panel(location) as CraftPanel
	assert_not_null(panel, "应能打开灶台")
	await wait_process_frames(1)
	if panel != null:
		panel._select_recipe(recipe_key)
		for i in 4:
			await wait_process_frames(1)
		var section: FoldableContainer = null
		for node in panel.find_children("*", "FoldableContainer", true, false):
			var fold := node as FoldableContainer
			if fold != null and fold.title.begins_with(I18n.t("ui.craft.used_in")):
				section = fold
				break
		assert_not_null(section, "详情应有「它可以做…」折叠区")
		if section != null:
			section.folded = false
			for i in 3:
				await wait_process_frames(1)
			assert_gt(section.find_children("*", "Button", true, false).size(), 0,
					"展开后应列出至少一条用到面包的配方")
	UIManager.close_panel(location)
	await wait_process_frames(1)


# --- HUD ------------------------------------------------------------------


## HUD 现在是全动态构建的（hud.tscn 里只剩根节点），控件靠 name 查找
func _hud_label(hud: GameHud, label_name: String) -> Label:
	return hud.find_child(label_name, true, false) as Label


## 顶栏以设置按钮为基准：所有可见卡片都应是同一高度，左半边不能比右侧高
func test_hud_cards_match_settings_height() -> void:
	var hud := preload("res://scenes/ui/hud.tscn").instantiate() as GameHud
	add_child_autofree(hud)
	await wait_process_frames(2)
	var row := hud.get_child(0)
	var settings: Control = row.get_child(row.get_child_count() - 1) as Control
	assert_eq(settings.size.y, GameHud.HUD_HEIGHT, "设置按钮应与卡片同高")
	for i in range(row.get_child_count() - 1):
		var card := row.get_child(i) as Control
		if card != null and card.size.x > 0.0:
			assert_eq(card.size.y, GameHud.HUD_HEIGHT, "HUD 卡片应与设置按钮同高：%s" % card.name)


## HUD 单元测试不在主场景里，TooltipLayer 不存在时会回落到 tooltip_text；
## 主场景里则写在 meta 上。两种路径都读，断言的是「绑到了哪种文案」。
func _clock_tooltip(hud: GameHud) -> String:
	var card := hud._clock_card
	return String(card.get_meta(&"tooltip_layer_text", card.tooltip_text))


func test_hud_binds_state_and_follows_events() -> void:
	var hud := preload("res://scenes/ui/hud.tscn").instantiate() as GameHud
	assert_not_null(hud, "HUD 场景应能实例化")
	add_child_autofree(hud)
	await wait_process_frames(1)

	var coins_label := _hud_label(hud, "Coins")
	var catalog_label := _hud_label(hud, "Catalog")
	var clock_label := _hud_label(hud, "Clock")
	assert_not_null(coins_label, "HUD 应有铜币数字")
	assert_not_null(catalog_label, "HUD 应有图鉴进度")
	assert_not_null(clock_label, "HUD 应有时钟")

	assert_eq(coins_label.text, "0", "初始铜币应与 GameState 一致")
	assert_not_null(hud.find_child("CoinMark", true, false) as CoinIcon, "HUD 铜币应使用铜板图标，而不是「铜」字")
	assert_string_contains(catalog_label.text, "/", "图鉴进度应形如「3 / 25」")
	assert_eq(clock_label.text, "0:00:00", "时钟默认显示本局游戏时长")
	assert_eq(_clock_tooltip(hud), I18n.t("ui.hud.clock_playtime_tooltip"),
			"时长模式应提示点击可切现实时间")

	GameState.advance(65.0)
	hud._refresh_clock()
	assert_eq(clock_label.text, "0:01:05", "游戏时长应随在线时间累计")
	hud._toggle_clock_mode()
	assert_true(clock_label.text.length() == 5 and clock_label.text[2] == ":",
			"切到现实时间后应形如 HH:MM：%s" % clock_label.text)
	assert_eq(_clock_tooltip(hud), I18n.t("ui.hud.clock_realtime_tooltip"),
			"现实时间模式应提示点击可切回时长")
	hud._toggle_clock_mode()
	assert_eq(clock_label.text, "0:01:05", "再点一次应切回本局时长")

	GameState.add_coins(42, "测试")
	await wait_process_frames(1)
	assert_eq(coins_label.text, "42", "铜币事件应刷新 HUD")


## 图标源文件有透明留白；PanelKit 应按目标尺寸重新栅格化并裁掉留白，
## 否则放大后又会糊又会显得小。
func test_icon_rasterizes_at_target_size() -> void:
	var icon := PanelKit.icon("ui/book.svg", 24.0)
	add_child_autofree(icon)
	assert_true(icon.texture is ImageTexture, "图标应在运行时栅格化")
	var texture := icon.texture as ImageTexture
	assert_not_null(texture, "图标应有纹理")
	if texture != null:
		assert_true(texture.get_width() >= 24, "裁完的图形不能比目标尺寸还小")
		assert_true(texture.get_width() <= 24 * 6, "栅格化倍数最多 6 倍，别把显存烧穿")


## 放大窗口时图标要跟着给更大的源纹理，否则 4K 全屏下会被二次放大
func test_icon_scale_bucket_tracks_window() -> void:
	var bucket := PanelKit.icon_scale_bucket()
	assert_between(bucket, 2, 6, "倍数夹在 2–6 之间")


func test_hud_catalog_progress_matches_state() -> void:
	var hud := preload("res://scenes/ui/hud.tscn").instantiate() as GameHud
	add_child_autofree(hud)
	await wait_process_frames(1)

	var catalog_label := _hud_label(hud, "Catalog")
	assert_not_null(catalog_label, "HUD 应有图鉴进度")
	var expected := "%d / %d" % [GameState.get_catalog_discovered_count(), GameState.get_catalog_total()]
	assert_eq(catalog_label.text, expected, "图鉴进度应与 GameState 计数一致")


## 回归：读信之后红点必须消失（曾经只发解锁事件，不发已读事件）
func test_hud_clears_unread_mail_after_reading() -> void:
	var hud := preload("res://scenes/ui/hud.tscn").instantiate() as GameHud
	add_child_autofree(hud)
	await wait_process_frames(1)

	var mail_label := _hud_label(hud, "Mail")
	assert_not_null(mail_label, "HUD 应有未读信件提示")
	assert_gt(GameState.get_unread_letter_count(), 0, "初始应至少有一封未读信")
	assert_true(mail_label.is_visible_in_tree(), "有未读信时红点应可见")

	# 读信可能连锁解锁下一封，所以读到未读数为 0 为止（带守卫防止死循环）
	var guard := 0
	while GameState.get_unread_letter_count() > 0 and guard < 20:
		for key in GameState.get_unlocked_letters():
			GameState.mark_letter_read(key)
		guard += 1
	await wait_process_frames(1)

	assert_eq(GameState.get_unread_letter_count(), 0, "全部读完后未读数应为 0")
	# 读委托信会自动收下待办（第四轮反馈），所以卡片改成显示待办数而不是消失
	var open := GameState.get_open_task_count()
	assert_gt(open, 0, "读过的委托信都进了待办")
	assert_true(mail_label.is_visible_in_tree(), "还有待办时卡片仍亮着")
	assert_eq(mail_label.text, I18n.plural("ui.hud.task_open", open), "卡片改显示待办数")

	var empty_tasks: Array[String] = []
	GameState.set("_accepted_tasks", empty_tasks)
	hud._refresh_mail()
	assert_false(mail_label.is_visible_in_tree(), "待办也清空后红点才消失")


## 订单板入口常驻 HUD，交付后数字要跟着变
func test_hud_shows_order_board_count() -> void:
	# 订单板在第九封信后才露出；这条测的是 HUD 的计数与刷新，不是解锁，先手动放开。
	GameState._read_letters[GameState.ORDERS_UNLOCK_LETTER] = true
	var hud := preload("res://scenes/ui/hud.tscn").instantiate() as GameHud
	add_child_autofree(hud)
	await wait_process_frames(1)

	var orders_label := _hud_label(hud, "Orders")
	assert_not_null(orders_label, "HUD 应有订单板入口")
	assert_eq(orders_label.text, "订单 %d" % GameState.get_orders().size())

	var order := GameState.get_orders()[0]
	GameState.add_item(order.dish_key, order.quantity)
	assert_true(GameState.deliver_order(order.id))
	await wait_process_frames(1)
	assert_eq(orders_label.text, "订单 %d" % (GameState.ORDER_CAPACITY - 1), "交付后应刷新")


## 回归：HUD 比 GameBridge 先 ready，读档后必须整体重拉一次
func test_hud_refreshes_after_state_restored() -> void:
	var hud := preload("res://scenes/ui/hud.tscn").instantiate() as GameHud
	add_child_autofree(hud)
	await wait_process_frames(1)

	GameState.add_coins(120, "测试")
	var snapshot := GameState.to_dict()
	GameState.add_coins(55, "测试")
	await wait_process_frames(1)
	var coins_label := _hud_label(hud, "Coins")
	assert_eq(coins_label.text, "175", "两次加币后 HUD 应是 175")

	GameState.restore_from_dict(snapshot)
	await wait_process_frames(1)
	assert_eq(coins_label.text, "120", "读档事件应让 HUD 重新拉快照")


# --- 主场景冒烟 ------------------------------------------------------------


func test_main_scene_wires_desktop_hud_and_bridge() -> void:
	var scene := preload("res://scenes/screens/main.tscn").instantiate()
	var bridge := scene.get_node("GameBridge") as GameBridge
	assert_not_null(bridge, "主场景应带 GameBridge")
	# 测试里不要读写玩家真实存档
	bridge.save = SaveGame.new(SMOKE_SAVE)
	add_child_autofree(scene)
	await wait_process_frames(2)

	assert_not_null(scene.get_node_or_null("HudLayer/Hud"), "主场景应实例化 HUD")
	assert_not_null(scene.get_node_or_null("Room/Desktop/Table/Front/TableBox"), "主场景应有桌面")
	assert_not_null(scene.get_node_or_null("Backdrop"), "主场景应有房间背景")

	# 车窗光是 Backdrop 的子节点：只照背景，不可能盖到 Room/HUD/面板上。
	var sunlight := scene.get_node_or_null("Backdrop/Sunlight") as ColorRect
	assert_not_null(sunlight, "主场景应有一层背景车窗光")
	if sunlight != null:
		assert_eq(sunlight.mouse_filter, Control.MOUSE_FILTER_IGNORE, "车窗光不能挡住点击")
		assert_true(sunlight.material is ShaderMaterial, "车窗光应使用 ShaderMaterial")
		assert_not_null((sunlight.material as ShaderMaterial).shader, "车窗光材质应绑定 shader")
	assert_null(scene.get_node_or_null("Room/Desktop/Table/Front/Sunlight"),
			"车窗光不该叠在桌面纸面这类 UI 上")

	# 六个入口分列左右两栏，每栏三张卡片
	for rail_name in ["LeftRail", "RightRail"]:
		var rail := scene.get_node_or_null("Room/Desktop/%s" % rail_name) as VBoxContainer
		assert_not_null(rail, "主场景应有 %s" % rail_name)
		if rail == null:
			continue
		assert_eq(rail.get_child_count(), 3, "%s 应有三张入口卡片" % rail_name)
		for card in rail.get_children():
			assert_true(card is HotspotCard, "%s 里应是 HotspotCard" % rail_name)

	assert_true(scene is MainScreen, "主场景根节点应使用 MainScreen 脚本")


## 氛围层只是装饰：必须存在、必须不挡点击，痕迹能出现
func test_main_scene_has_non_blocking_ambient_decor() -> void:
	var scene := preload("res://scenes/screens/main.tscn").instantiate()
	var bridge := scene.get_node("GameBridge") as GameBridge
	bridge.save = SaveGame.new(SMOKE_SAVE)
	add_child_autofree(scene)
	await wait_process_frames(2)

	var ambient := scene.get_node_or_null("Room/Ambient")
	assert_not_null(ambient, "主场景应有氛围层")
	if ambient == null:
		return
	assert_eq(ambient.mouse_filter, Control.MOUSE_FILTER_IGNORE, "氛围层不能挡住桌面点击")
	assert_not_null(ambient.get_node_or_null("Sign"), "氛围层应有贴在屏幕边缘的招牌")
	assert_false(ambient.is_trace_visible("coin"), "没有访客时不该出现铜板")
	assert_null(ambient.get_node_or_null("Cup"), "氛围层不该再有杯子")
	assert_null(ambient.get_node_or_null("Note"), "氛围层不该再有纸条")

	ambient.show_trace("coin")
	await wait_seconds(0.2)
	assert_true(ambient.is_trace_visible("coin"), "访客留下的铜板应能淡入")
	var coin := ambient.get_node_or_null("Coin") as Control
	assert_not_null(coin, "铜板痕迹应存在")
	if coin != null:
		assert_almost_eq(coin.size.x, 40.0, 0.001, "桌面铜板应使用 40px 尺寸")
		assert_almost_eq(coin.size.y, 40.0, 0.001, "桌面铜板应使用 40px 尺寸")
		assert_true(coin.position.x >= AmbientLayer.COIN_AREA.position.x
				and coin.position.x <= AmbientLayer.COIN_AREA.end.x - coin.size.x,
				"铜板应落在桌面空白区的随机带里")
		assert_true(coin.position.y >= AmbientLayer.COIN_AREA.position.y
				and coin.position.y <= AmbientLayer.COIN_AREA.end.y - coin.size.y,
				"铜板应落在桌面空白区的随机带里")


## 招牌菜便条：只写已发现的菜，按市场价取前三；未发现的不泄露
func test_sign_lists_top_discovered_dishes() -> void:
	var scene := preload("res://scenes/screens/main.tscn").instantiate()
	var bridge := scene.get_node("GameBridge") as GameBridge
	bridge.save = SaveGame.new(SMOKE_SAVE)
	add_child_autofree(scene)
	await wait_process_frames(2)

	var ambient := scene.get_node_or_null("Room/Ambient")
	assert_not_null(ambient, "主场景应有氛围层")
	if ambient == null:
		return

	assert_true(ambient.get_signature_names().is_empty(), "没有已发现菜品时便条不该写菜名")
	for key in ["game:item/espresso", "game:item/latte", "game:item/cake", "game:item/pudding"]:
		GameState.discover(key)
	await wait_process_frames(2)

	var names: Array = ambient.get_signature_names()
	assert_eq(names.size(), 3, "便条最多写三道招牌菜")
	assert_eq(names[0], "蛋糕", "卖价最高的应排第一")
	assert_eq(names[1], "布丁", "卖价第二的应排第二")
	assert_eq(names[2], "拿铁", "卖价第三的应排第三")


# --- 环境提示（toast） -----------------------------------------------------


func test_toast_is_registered_and_shows() -> void:
	var registry := RegistryManager.get_registry("ui") as UIRegistry
	var toast_id := ResourceLocation.from_string("idle_food:toast_message")
	assert_not_null(toast_id, "提示 ID 应可解析")
	assert_true(registry.has_entry(toast_id), "提示应登记进 UIRegistry")

	var toast := UIManager.show_toast(toast_id, {"text": "拿铁 做好了", "accent": true}, 1.0)
	assert_not_null(toast, "show_toast 应返回提示实例")
	await wait_process_frames(1)
	assert_true(toast is ToastMessage, "提示应使用 ToastMessage 脚本")
	var label := _find_label(toast)
	assert_not_null(label, "提示里应有文字")
	if label != null:
		assert_eq(label.text, "拿铁 做好了", "文字应来自 data.text")
	UIManager.dismiss_all_toasts()
	await wait_process_frames(1)


func test_craft_finish_shows_toast() -> void:
	var bridge := GameBridge.new()
	bridge.save = SaveGame.new(SMOKE_SAVE)
	add_child_autofree(bridge)
	await wait_process_frames(1)

	EventBus.publish(CraftCompletedEvent.new("game:item/americano", true, true))
	await wait_process_frames(1)
	var toast_layer := UIManager.get_node_or_null("UILayer_300")
	assert_not_null(toast_layer, "应有 TOAST 层")
	if toast_layer != null:
		assert_gt(toast_layer.get_child_count(), 0, "做完食物应冒出一条提示")
	UIManager.dismiss_all_toasts()
	await wait_process_frames(1)


func _find_label(node: Node) -> Label:
	if node is Label:
		return node as Label
	for child in node.get_children():
		var found := _find_label(child)
		if found != null:
			return found
	return null


## 按标签要料的配方（炖菜 = 任意肉 + 任意蔬菜）要能在灶台上正常列出来：
## by_tag 的栈没有具体物品键，不能拿空键去查定义，否则会打一条「找不到」的错。
## 配方不写死成炖菜：它属于地区主题，主题渐进解锁之后开局多半还没到站。
func test_craft_panel_renders_by_tag_inputs() -> void:
	var location := ResourceLocation.from_string("idle_food:craft")
	var panel: UIPanel = UIManager.open_panel(location)
	assert_not_null(panel, "应能打开灶台")
	assert_true(panel is CraftPanel, "灶台应使用 CraftPanel 脚本")
	await wait_process_frames(1)

	var craft := panel as CraftPanel
	var target := ""
	var tags: Array[String] = []
	for recipe in craft._recipes:
		for stack in recipe.inputs:
			if not stack.by_tag.is_empty():
				target = recipe.get_key()
				break
		if not target.is_empty():
			for stack in recipe.inputs:
				if not stack.by_tag.is_empty():
					tags.append(stack.by_tag)
			break
	assert_ne(target, "", "当前可见的配方里应至少有一道按标签要料")
	if target.is_empty():
		UIManager.close_panel(location)
		return

	craft.set("_selected", target)
	craft.call("refresh")
	await wait_process_frames(1)

	var texts: Array[String] = []
	for node in panel.find_children("*", "Label", true, false):
		var label := node as Label
		if label != null:
			texts.append(label.text)
	for tag in tags:
		# by_tag 存的是 "game:tag/veg"，翻译键只取短名
		var tag_name := I18n.t("data.tag.%s.name" % String(tag).trim_prefix("game:tag/"))
		var found := false
		for text in texts:
			if text.contains(tag_name):
				found = true
				break

		assert_true(found, "灶台应把「任意%s」念成标签名（%s）" % [tag, tag_name])

	UIManager.close_panel(location)
	await wait_process_frames(1)


## 桌面研究台卡的提示要常驻：只要还有没试出来的菜就挂着，全部试完才收回（用户 2026-10-29 要求）。
func test_research_hotspot_hint_stays_until_every_dish_is_found() -> void:
	assert_true(GameState.has_unresearched_recipes(), "新档应还有没试出来的菜")

	var scene := preload("res://scenes/screens/main.tscn").instantiate()
	var bridge := scene.get_node("GameBridge") as GameBridge
	bridge.save = SaveGame.new(SMOKE_SAVE)
	add_child_autofree(scene)
	await wait_process_frames(2)

	var card := _research_hotspot_card(scene)
	assert_not_null(card, "右栏应有研究台卡片")
	if card == null:
		return
	assert_eq(card.subtitle, I18n.t("ui.hotspot.research_subtitle_hint"),
			"还有菜没试出来时副标题应是提示")

	# 把到站的菜全解锁：提示应收回成日常文案
	for recipe in GameState.get_pending_recipes():
		GameState._unlock_recipe(recipe)
	assert_false(GameState.has_unresearched_recipes(), "全解锁后不应再有没试出来的菜")
	scene.call("_refresh_research_hint")
	await wait_process_frames(1)
	var after := _research_hotspot_card(scene)
	assert_not_null(after, "重建后右栏仍应有研究台卡片")
	if after != null:
		assert_eq(after.subtitle, I18n.t("ui.hotspot.research_subtitle"),
				"菜都试完后副标题应回到日常文案")


func _research_hotspot_card(scene: Node) -> HotspotCard:
	var rail := scene.get_node_or_null("Room/Desktop/RightRail") as VBoxContainer
	if rail == null:
		return null
	for child in rail.get_children():
		var card := child as HotspotCard
		if card != null and card.title == I18n.t("ui.hotspot.research_title"):
			return card
	return null
