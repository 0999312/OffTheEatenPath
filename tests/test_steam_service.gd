extends GutTest
## Steam 接入探针：没有插件/没有 Steam 客户端时必须静默降级，不能影响启动与门禁。


func test_autoload_is_present() -> void:
	var node: Node = get_tree().root.get_node_or_null("SteamService")
	assert_not_null(node, "SteamService 未注册为 autoload")


func test_status_is_always_readable() -> void:
	var node: Node = get_tree().root.get_node_or_null("SteamService")
	assert_not_null(node)
	assert_true(node.get_status() is String, "status 应为字符串")
	assert_true(node.get_status() != "", "status 不应为空")
	assert_true(node.get_app_id() >= 0, "app_id 应为非负")
	assert_true(node.get_build_id() >= 0, "build_id 应为非负")
	assert_true(node.get_persona_name() is String)


func test_offline_degradation_is_consistent() -> void:
	var node: Node = get_tree().root.get_node_or_null("SteamService")
	assert_not_null(node)
	if not node.is_available():
		assert_false(node.is_initialized(), "没有插件时不应报告已初始化")
	else:
		# 装了插件但没有 Steam 客户端时，初始化可以失败；此时仍必须可查询。
		assert_true(node.get_status() != "")
