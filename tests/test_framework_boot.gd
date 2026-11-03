extends GutTest
## P0 框架接入回归测试：autoload 生效、EventBus 发布 / 订阅、UIRegistry 注册、面板开关。
##
## 与 scripts/systems/boot_self_check.gd 覆盖同一批链路，
## 差别是这里的失败会由 GUT 记为测试失败，供质量门禁自动判定。
## 运行：godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit

const REQUIRED_AUTOLOADS: Array[String] = [
	"RegistryManager",
	"EventBus",
	"I18NManager",
	"UIManager",
	"GameBootstrap",
]

func test_required_autoloads_present() -> void:
	var root := get_tree().root
	for autoload_name in REQUIRED_AUTOLOADS:
		assert_not_null(root.get_node_or_null(NodePath(autoload_name)), "缺少 autoload：%s" % autoload_name)

func test_event_bus_publish_and_unsubscribe() -> void:
	var received: Array[int] = []
	var listener := func(event: Event) -> void:
		if event is BootCheckEvent:
			received.append((event as BootCheckEvent).marker)

	EventBus.subscribe(&"BootCheckEvent", listener)
	EventBus.publish(BootCheckEvent.new(11))
	EventBus.unsubscribe(&"BootCheckEvent", listener)
	EventBus.publish(BootCheckEvent.new(22))

	assert_eq(received.size(), 1, "EventBus 只应在订阅期间收到事件")
	if received.size() == 1:
		assert_eq(received[0], 11, "EventBus 传递的载荷应保持原值")

func test_ui_registry_registered() -> void:
	assert_true(RegistryManager.has_registry("ui"), "GameBootstrap 应注册 \"ui\" 注册表")
	assert_true(RegistryManager.get_registry("ui") is UIRegistry, "\"ui\" 注册表应为 UIRegistry")

func test_diagnostic_panel_open_and_close() -> void:
	var panel_id := ResourceLocation.from_string(BootSelfCheck.PANEL_ID)
	assert_not_null(panel_id, "诊断面板 ID 应可解析")

	var panel: UIPanel = UIManager.open_panel(panel_id)
	assert_not_null(panel, "UIManager 应能按 UIRegistry 登记打开诊断面板")
	assert_true(UIManager.is_panel_open(panel_id), "面板打开后 is_panel_open 应为 true")
	if panel != null:
		assert_not_null(panel.get_parent(), "面板打开后应挂入场景树")
		assert_true(panel is DiagnosticPanel, "诊断面板场景应使用 DiagnosticPanel 脚本")

	UIManager.close_panel(panel_id)
	assert_false(UIManager.is_panel_open(panel_id), "面板关闭后 is_panel_open 应为 false")
	# 关闭走 queue_free，等一帧让实例真正释放，避免 GUT 报 orphan
	await wait_process_frames(1)

func test_boot_self_check_reports_no_failures() -> void:
	var failures: Array[String] = BootSelfCheck.new().run()
	assert_eq(failures.size(), 0, "启动自检未通过：\n%s" % "\n".join(PackedStringArray(failures)))
	await wait_process_frames(1)
