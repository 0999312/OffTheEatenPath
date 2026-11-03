extends RefCounted
class_name BootSelfCheck
## 启动自检：只读地验证 mc_game_framework 接入与数据层链路是否贯通。
##
##   1) 四个框架 autoload 已注册且进入场景树
##   2) EventBus：订阅 → 发布 → 取消订阅
##   3) RegistryManager 中已注册 UIRegistry（键 "ui"）
##   4) UIManager 能按 UIRegistry 打开并关闭面板
##   5) DataRegistry（键 "data"）已加载静态内容且跨条目校验无问题
##
## 用法：`BootSelfCheck.new().run()` 返回失败描述数组，空数组表示全部通过。
## 自检不修改玩法状态，可重复执行（GameBootstrap 与 GUT 测试共用同一实现）。
## 脚本内不使用 autoload 全局名，缺失时报告失败而不是编译中断。

const UI_REGISTRY_KEY := "ui"
const DATA_REGISTRY_KEY := DataRegistry.REGISTRY_NAME
const EVENT_TYPE := &"BootCheckEvent"
const PANEL_ID := "idle_food:diagnostic_panel"
const REQUIRED_AUTOLOADS: Array[String] = [
	"RegistryManager",
	"EventBus",
	"I18NManager",
	"UIManager",
]
## 启动时必须已加载的语言（`resources/i18n/<code>.json`）
const REQUIRED_LOCALES: Array[String] = ["zh_CN", "en"]
## 验证翻译真的能命中的探针键
const LOCALIZED_PROBE_KEY := "ui.settings.language"

var _failures: Array[String] = []

## 执行全部自检，返回失败描述数组（空数组即通过）
func run() -> Array[String]:
	_failures = []
	var root: Window = _scene_root()
	if root == null:
		_fail("自检需要运行中的 SceneTree，当前取不到根节点")
		return _failures.duplicate()

	_check_autoloads(root)
	_check_event_type()
	_check_event_bus()
	_check_ui_registry()
	_check_panel_roundtrip()
	_check_data_registry()
	_check_localization()
	return _failures.duplicate()

# ─── 各项检查 ───

func _check_autoloads(root: Window) -> void:
	for autoload_name in REQUIRED_AUTOLOADS:
		if root.get_node_or_null(NodePath(autoload_name)) == null:
			_fail("缺少 autoload %s（检查 project.godot 的 [autoload] 段与 mc_game_framework 插件是否启用）" % autoload_name)

func _check_event_type() -> void:
	var event := BootCheckEvent.new()
	if event.get_event_type() != EVENT_TYPE:
		_fail("事件类型解析异常：期望 %s，实际 %s（Event 子类必须有 class_name）" % [EVENT_TYPE, event.get_event_type()])

func _check_event_bus() -> void:
	var bus: Node = _autoload("EventBus")
	if bus == null:
		return

	var received: Array[int] = []
	var listener := func(event: Event) -> void:
		if event is BootCheckEvent:
			received.append((event as BootCheckEvent).marker)

	bus.subscribe(EVENT_TYPE, listener)
	bus.publish(BootCheckEvent.new(4242))
	bus.unsubscribe(EVENT_TYPE, listener)
	bus.publish(BootCheckEvent.new(7))

	if received.size() != 1:
		_fail("EventBus 订阅期应收到 1 次事件，实际收到 %d 次" % received.size())
	elif received[0] != 4242:
		_fail("EventBus 传递的事件载荷错误：期望 4242，实际 %d" % received[0])

func _check_ui_registry() -> void:
	var registry_manager: Node = _autoload("RegistryManager")
	if registry_manager == null:
		return
	if not registry_manager.has_registry(UI_REGISTRY_KEY):
		_fail("RegistryManager 缺少 \"%s\" 注册表：UIRegistry 未注册（应由 GameBootstrap 注册）" % UI_REGISTRY_KEY)
		return
	if not (registry_manager.get_registry(UI_REGISTRY_KEY) is UIRegistry):
		_fail("RegistryManager 的 \"%s\" 注册表不是 UIRegistry 类型" % UI_REGISTRY_KEY)

func _check_panel_roundtrip() -> void:
	var ui_manager: Node = _autoload("UIManager")
	if ui_manager == null:
		return
	var panel_id := ResourceLocation.from_string(PANEL_ID)
	if panel_id == null:
		_fail("面板 ID 非法：%s" % PANEL_ID)
		return

	var panel: UIPanel = ui_manager.open_panel(panel_id)
	if panel == null:
		_fail("UIManager.open_panel 返回 null：%s（面板未在 UIRegistry 登记，或场景根节点不是 UIPanel）" % PANEL_ID)
		return
	if not ui_manager.is_panel_open(panel_id):
		_fail("面板打开后 is_panel_open 返回 false：%s" % PANEL_ID)
	if panel.get_parent() == null:
		_fail("面板打开后未挂入场景树：%s" % PANEL_ID)
	if panel is DiagnosticPanel and (panel as DiagnosticPanel).open_count != 1:
		_fail("面板 _on_open 生命周期未按预期调用：open_count=%d" % (panel as DiagnosticPanel).open_count)

	ui_manager.close_panel(panel_id)
	if ui_manager.is_panel_open(panel_id):
		_fail("面板关闭后 is_panel_open 仍返回 true：%s" % PANEL_ID)

func _check_data_registry() -> void:
	var registry_manager: Node = _autoload("RegistryManager")
	if registry_manager == null:
		return
	if not registry_manager.has_registry(DATA_REGISTRY_KEY):
		_fail("RegistryManager 缺少 \"%s\" 注册表：DataRegistry 未注册（应由 GameBootstrap 注册）" % DATA_REGISTRY_KEY)
		return
	var data_registry := registry_manager.get_registry(DATA_REGISTRY_KEY) as DataRegistry
	if data_registry == null:
		_fail("RegistryManager 的 \"%s\" 注册表不是 DataRegistry 类型" % DATA_REGISTRY_KEY)
		return
	var defs := data_registry.get_all_defs()
	if defs.is_empty():
		_fail("DataRegistry 为空：resources/game_data/ 下没有加载到任何定义")
		return
	var issues: Array[String] = data_registry.validate()
	for issue in issues:
		_fail("数据层校验失败：%s" % issue)

func _check_localization() -> void:
	var loaded := TranslationServer.get_loaded_locales()
	for code in REQUIRED_LOCALES:
		if not loaded.has(code):
			_fail("翻译未加载：%s（检查 resources/i18n/%s.json 与 GameBootstrap）" % [code, code])
	var manager: Node = _autoload("I18NManager")
	if manager == null:
		return
	if String(manager.call("get_text", LOCALIZED_PROBE_KEY)) == LOCALIZED_PROBE_KEY:
		_fail("翻译键 %s 取不到文本：当前语言 %s" % [LOCALIZED_PROBE_KEY, manager.call("get_current_language")])

# ─── 工具 ───

func _scene_root() -> Window:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root

func _autoload(autoload_name: String) -> Node:
	var root: Window = _scene_root()
	if root == null:
		return null
	return root.get_node_or_null(NodePath(autoload_name))

func _fail(message: String) -> void:
	_failures.append(message)
