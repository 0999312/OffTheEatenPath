extends GutTest
## G1 机器核查：界面上不该出现没翻出来的原始键（`ui.craft.title` 这种）。
##
## 人工队没法把 13 个面板逐字读完，这条测试替他们读：逐个打开常驻面板，
## 把 Label / Button / TabBar 上的字都扫一遍，命中「整串长得像键」就算漏翻。
## 数据条目名（`data.item.*`）也在检查范围——它们同样走翻译键。

const PANEL_IDS: Array[String] = [
	"idle_food:diagnostic_panel",
	"idle_food:craft",
	"idle_food:orders",
	"idle_food:catalog",
	"idle_food:research",
	"idle_food:facility",
	"idle_food:merchant",
	"idle_food:mail",
	"idle_food:settings",
	"idle_food:credits",
]

## 整串只有键、没被翻成句子时才算漏翻；正文里提到 `ui.` 不算
var _raw_key := RegEx.create_from_string("^(ui|data)(\\.[a-z0-9_]+)+$")


func before_each() -> void:
	GameState.reset()


func after_each() -> void:
	UIManager.close_all()
	await wait_process_frames(1)


func test_panels_show_no_raw_translation_keys() -> void:
	for panel_id in PANEL_IDS:
		var location := ResourceLocation.from_string(panel_id)
		var panel: UIPanel = UIManager.open_panel(location)
		assert_not_null(panel, "应能打开面板：%s" % panel_id)
		if panel == null:
			continue
		await wait_process_frames(2)
		var leaks := _raw_keys_in(panel)
		assert_eq(leaks, [], "面板 %s 里有没翻出来的键：%s" % [panel_id, ", ".join(leaks)])
		UIManager.close_panel(location)
		await wait_process_frames(1)


## 同一个键在界面上重复出现很正常，报之前先去重
func _raw_keys_in(root: Node) -> Array[String]:
	var leaks: Array[String] = []
	for node in root.find_children("*", "Label", true, false):
		_collect(leaks, (node as Label).text)
	for node in root.find_children("*", "Button", true, false):
		_collect(leaks, (node as Button).text)
	for node in root.find_children("*", "TabBar", true, false):
		var bar := node as TabBar
		for index in bar.tab_count:
			_collect(leaks, bar.get_tab_title(index))
	leaks.sort()
	return leaks


func _collect(leaks: Array[String], text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty() or leaks.has(trimmed):
		return
	if _raw_key.search(trimmed) != null:
		leaks.append(trimmed)
