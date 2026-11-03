extends GutTest
## 切语言后仍然留在屏幕上的东西，必须就地重翻：环境提示（toast）与离线结算弹窗。
##
## 这两处的共同点是「文案在某个时刻翻死了一次」：提示是一行字，结算是缓存在
## OfflineSummary 里的名字。修法不是重开面板，而是**存配方、渲染时现翻**
## （提示存 `{"key", "args"}` / `{"build", Callable}`，结算行按 key 现取名字）。

const OFFLINE_PANEL := "idle_food:offline"
const TOAST_ID := "idle_food:toast_message"
const BEAN := "game:item/coffee_bean"

var _original_locale := "zh_CN"


func before_each() -> void:
	_original_locale = I18NManager.get_current_language()
	GameState.reset()


func after_each() -> void:
	I18NManager.set_language(_original_locale)
	UIManager.close_all()
	await wait_process_frames(1)


# --- 提示文案配方 -----------------------------------------------------------


func test_toast_spec_retranslates_plain_key() -> void:
	var spec := {"key": "ui.toast.coin_picked", "args": [3]}
	I18NManager.set_language("zh_CN")
	var zh := ToastMessage.message_text(spec)
	I18NManager.set_language("en")
	var en := ToastMessage.message_text(spec)

	assert_ne(zh, en, "同一份配方应随语言翻出不同文案")
	assert_string_contains(zh, "3", "占位符应填进中文文案")
	assert_string_contains(en, "3", "占位符应填进英文文案")


func test_toast_spec_translates_nested_item_name() -> void:
	# 条目名本身也是翻译键（`{"t": ...}`），不能在发提示那一刻翻死
	var spec := {"key": "ui.toast.recipe_unlocked", "args": [{"t": "data.item.latte.name"}]}
	I18NManager.set_language("en")
	var en := ToastMessage.message_text(spec)
	I18NManager.set_language("zh_CN")
	var zh := ToastMessage.message_text(spec)

	assert_string_contains(en, "Latte", "英文提示里应是英文菜名")
	assert_string_contains(zh, I18n.t("data.item.latte.name"), "中文提示里应是中文菜名")
	assert_ne(en, zh, "两种语言的提示整句都应不同")


func test_toast_spec_supports_builder() -> void:
	# 研究结论那种「拼出来的整句」交一个重建函数，切语言时整句重拼
	var calls := [0]
	var spec := {"build": func() -> String:
		calls[0] += 1
		return I18n.t("ui.toast.coin_picked", [7])}
	I18NManager.set_language("zh_CN")
	var zh := ToastMessage.message_text(spec)
	I18NManager.set_language("en")
	var en := ToastMessage.message_text(spec)

	assert_eq(calls[0], 2, "每次渲染都应重新调用重建函数")
	assert_ne(zh, en, "整句应随语言重拼")


# --- 提示本身就地重翻 -------------------------------------------------------


func test_visible_toast_retranslates_without_rebuilding() -> void:
	var spec := {"key": "ui.toast.recipe_unlocked", "args": [{"t": "data.item.latte.name"}]}
	I18NManager.set_language("zh_CN")
	var toast_id := ResourceLocation.from_string(TOAST_ID)
	var toast := UIManager.show_toast(toast_id, spec, 30.0)
	assert_not_null(toast, "应能弹出提示")
	await wait_process_frames(1)
	var label := _find_label(toast)
	assert_not_null(label, "提示里应有文字")
	if label == null:
		return
	var zh := label.text

	I18NManager.set_language("en")
	await wait_process_frames(1)
	assert_eq(label.text, ToastMessage.message_text(spec), "同一节点上的文字应就地换掉")
	assert_ne(label.text, zh, "换成英文后不应还是中文")


# --- 离线结算就地重画 -------------------------------------------------------


func test_offline_panel_rebuilds_on_language_change() -> void:
	var summary := OfflineSummary.new()
	summary.offline_unlocked = true
	summary.elapsed_seconds = 125.0
	summary.coins_gained = 0
	summary.gains = [{"key": BEAN, "name": "占位名", "type_id": "item", "kind": ItemDef.Kind.MATERIAL, "delta": 3}]

	I18NManager.set_language("zh_CN")
	var panel := UIManager.open_panel(ResourceLocation.from_string(OFFLINE_PANEL),
			{"summary": summary}) as OfflinePanel
	assert_not_null(panel, "应能打开离线结算")
	await wait_process_frames(1)
	assert_string_contains(_all_text(panel), I18n.t("data.item.coffee_bean.name"),
			"结算行应显示当前语言的材料名")

	I18NManager.set_language("en")
	await wait_process_frames(1)
	var text := _all_text(panel)
	assert_string_contains(text, I18n.t("ui.offline.title"), "标题应换成新语言")
	assert_string_contains(text, I18n.t("data.item.coffee_bean.name"),
			"材料名应按 key 重新取，而不是用结算时缓存的那串")
	assert_false(text.contains("占位名"), "缓存里的旧名字不应再出现")


# --- 辅助 -------------------------------------------------------------------


func _find_label(root: Node) -> Label:
	var found := root.find_children("*", "Label", true, false)
	if found.is_empty():
		return null
	return found[0] as Label


func _all_text(root: Node) -> String:
	var parts: Array[String] = []
	for node in root.find_children("*", "Label", true, false):
		parts.append((node as Label).text)
	return "\n".join(parts)
