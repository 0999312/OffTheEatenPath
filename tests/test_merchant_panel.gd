extends GutTest
## 商人：「买 / 卖」两页签 + 三列卡片墙（Q3 拍板，不再分页）。
##
## 234 道菜全列出来九成是「你没有」，所以卖页默认收着；想看全部再打开开关。

const MERCHANT := "idle_food:merchant"
const BEAN := "game:item/coffee_bean"


func before_each() -> void:
	GameState.reset()


func after_each() -> void:
	UIManager.close_all()
	await wait_process_frames(1)


func _open(tab: String = "") -> MerchantPanel:
	UIManager.close_all()
	await wait_process_frames(1)
	var data := {}
	if not tab.is_empty():
		data["tab"] = tab
	var panel := UIManager.open_panel(ResourceLocation.from_string(MERCHANT), data) as MerchantPanel
	await wait_process_frames(1)
	return panel


func _collect_cards(node: Node, out: Array[ShopCard]) -> void:
	for child in node.get_children():
		if child is ShopCard:
			out.append(child as ShopCard)
		_collect_cards(child, out)


func _cards(panel: MerchantPanel) -> Array[ShopCard]:
	var out: Array[ShopCard] = []
	_collect_cards(panel.content, out)
	return out


func _card_for(panel: MerchantPanel, key: String) -> ShopCard:
	for card in _cards(panel):
		if card.item_key == key:
			return card
	return null


func _first_card_title(panel: MerchantPanel) -> String:
	var cards := _cards(panel)
	return cards[0].get_item_name() if not cards.is_empty() else ""


func _button_with_text(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == text:
			return button
	return null


func test_buy_page_builds_a_three_column_wall_without_paging() -> void:
	var panel := await _open()
	panel._flush_pending_cards()
	assert_eq(panel._tab, 0, "默认停在买页")
	assert_gt(panel._tab_defs().size(), 0, "买页有货")
	var cards := _cards(panel)
	assert_eq(cards.size(), panel._tab_defs().size(), "卡片墙一次列全，没有第二页")

	var grids := panel.content.find_children("*", "GridContainer", true, false)
	assert_gt(grids.size(), 0, "内容用 GridContainer 排卡")
	if not grids.is_empty():
		assert_eq((grids[0] as GridContainer).columns, 3, "每行固定三列")
	assert_null(_button_with_text(panel.footer, I18n.t("ui.merchant.next")), "页脚不再有下一页")


func test_sell_page_starts_with_only_what_you_hold() -> void:
	var panel := await _open()
	panel._on_tab_changed(1)
	await wait_process_frames(1)
	assert_eq(panel._tab, 1)
	assert_eq(panel._tab_defs().size(), 0, "空手时卖页不列任何菜")

	GameState.add_item("game:item/toast", 1)
	panel.refresh()
	await wait_process_frames(1)
	panel._flush_pending_cards()
	var defs := panel._tab_defs()
	assert_eq(defs.size(), 1, "手里有一份就只列那一道")
	if defs.size() == 1:
		assert_eq(defs[0].get_key(), "game:item/toast")
	assert_eq(_first_card_title(panel), (defs[0] as ItemDef).localized(), "卡上写成品名")


## 「有货 / 全部」是工具条上的状态段，不再是行尾的 CheckButton（统一检索 §3）。
## 切换只放宽「手上有没有」这一道门：没记录过的菜仍然不列（G 批防剧透）。
func test_show_all_lists_recorded_dishes_you_do_not_hold() -> void:
	var panel := await _open("sell")
	assert_eq(panel._tab, 1, "open 时可以点名页签")
	assert_eq(panel._tab_defs().size(), 0)
	assert_true(panel.toolbar.find_children("*", "CheckButton", true, false).is_empty(),
			"卖页的「全部」不该再是 CheckButton")
	assert_eq(panel._bar.get_segment("owned"), 0, "默认只看有货")

	var foods := _all_foods()
	assert_gt(foods.size(), 30, "测试需要足够的菜")
	for index in 30:
		GameState.discover(String(foods[index].get_key()))

	panel.refresh()
	await wait_process_frames(1)
	assert_eq(panel._tab_defs().size(), 0, "只记录不持有，默认可卖页仍是空的")

	var chip := _button_with_text(panel._bar, I18n.t("ui.merchant.filter_all"))
	assert_not_null(chip, "卖页要有「全部」状态芯片")
	if chip == null:
		return
	chip.pressed.emit()
	await wait_process_frames(1)
	assert_true(panel._show_all_owned, "点「全部」后放宽持有条件")
	assert_eq(panel._bar.get_segment("owned"), 1, "重建后状态段仍停在「全部」")
	assert_eq(panel._tab_defs().size(), 30, "打开开关后只列这 30 道已记录的菜，其余仍藏着")
	panel._flush_pending_cards()
	assert_eq(_cards(panel).size(), 30, "三十张卡全在墙上，一屏滚到底")


func _all_foods() -> Array:
	var registry := RegistryManager.get_registry("data")
	var out: Array = []
	for def in registry.get_defs_of_type("item"):
		if bool(def.call("is_food")):
			out.append(def)
	return out


func test_clicking_a_card_opens_the_trade_popup_and_buys_one() -> void:
	GameState.add_coins(1000, "测试")
	var panel := await _open()
	panel._flush_pending_cards()
	var card := _card_for(panel, BEAN)
	assert_not_null(card, "咖啡豆是常备货")
	if card == null:
		return
	var price := GameState.get_shop_stock(BEAN)
	assert_gt(price, 0)
	var def := panel.def_of(BEAN) as ItemDef
	var unit := def.merchant_price
	var stock_before := GameState.get_shop_stock(BEAN)
	var coins_before := GameState.coins

	panel._on_card_activated(BEAN, card)
	await wait_process_frames(1)
	assert_not_null(panel._trade_popup, "点卡弹交易确认")
	if panel._trade_popup == null:
		return
	assert_true(panel._trade_popup.visible)
	var buy_one := _button_with_text(panel._trade_popup, I18n.t("ui.merchant.buy_button", [1, unit]))
	assert_not_null(buy_one, "弹窗里有「买 1」")
	if buy_one == null:
		return
	buy_one.pressed.emit()
	await wait_process_frames(2)
	assert_eq(GameState.coins, coins_before - unit, "买一份扣一份的钱")
	assert_eq(GameState.get_shop_stock(BEAN), stock_before - 1, "货架少一份")
	assert_null(panel._trade_popup, "成交后弹窗关闭")


func test_upgrade_popup_is_not_padded_by_autowrapping_hints() -> void:
	var panel := await _open()
	panel._open_upgrade_popup()
	await wait_process_frames(2)
	assert_not_null(panel._upgrade_popup, "升级弹窗应打开")
	if panel._upgrade_popup == null:
		return
	assert_lt(panel._upgrade_popup.size.y, 560, "提示文本先按 320 宽换行，弹窗不该被撑到近满屏")


func test_sell_all_from_the_trade_popup() -> void:
	GameState.add_coins(0, "测试")
	GameState.add_item("game:item/toast", 3)
	var panel := await _open("sell")
	panel._flush_pending_cards()
	var card := _card_for(panel, "game:item/toast")
	assert_not_null(card, "持有三道吐司就列一张卡")
	if card == null:
		return
	var def := panel.def_of("game:item/toast") as ItemDef
	var coins_before := GameState.coins
	panel._on_card_activated("game:item/toast", card)
	await wait_process_frames(1)
	assert_not_null(panel._trade_popup)
	if panel._trade_popup == null:
		return
	var sell_all := _button_with_text(panel._trade_popup, I18n.t("ui.merchant.sell_all", [def.sell_price * 3]))
	assert_not_null(sell_all, "弹窗里有「全卖」")
	if sell_all == null:
		return
	sell_all.pressed.emit()
	await wait_process_frames(2)
	assert_eq(GameState.get_amount("game:item/toast"), 0, "全卖清空持有")
	assert_eq(GameState.coins, coins_before + def.sell_price * 3, "按份数结算")


## 补货是全局一份表：页脚那一句比每行各挂一句更接近真相
func test_footer_shows_the_global_restock_clock() -> void:
	GameState.add_coins(1000, "测试")
	var panel := await _open()
	assert_null(panel._refill_footer, "满架时页脚不摆倒计时")
	GameState.buy_material(BEAN, 20)
	panel.refresh()
	await wait_process_frames(1)
	assert_not_null(panel._refill_footer, "有槽在等补货时页脚出现全局倒计时")
	if panel._refill_footer != null:
		assert_eq(panel._refill_footer.text,
				I18n.t("ui.merchant.refill_all", [PanelKit.duration_text(GameState.SHOP_REFILL_SECONDS)]),
				"页脚说的是「全部货架」，与空架行共用同一份表")


func test_footer_clears_itself_when_the_restock_lands() -> void:
	GameState.add_coins(1000, "测试")
	GameState.buy_material(BEAN, 20)
	var panel := await _open()
	assert_not_null(panel._refill_footer)
	GameState.advance(GameState.SHOP_REFILL_SECONDS)
	panel._on_tick()
	await wait_process_frames(2)
	assert_null(panel._refill_footer, "补满后页脚收起")
	assert_eq(GameState.get_shop_stock(BEAN), 20, "货架补满")
