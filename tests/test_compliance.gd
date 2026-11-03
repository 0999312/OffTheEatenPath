extends GutTest
## 发布合规与音乐接口：致谢面板能开、许可清单在仓库里、音频总线按用途分开。

const THIRD_PARTY := "res://docs/THIRD_PARTY.md"


func before_each() -> void:
	GameState.reset()


func after_each() -> void:
	var ui := UIManager
	if ui != null:
		ui.close_all()


func test_third_party_doc_exists_and_covers_the_real_dependencies() -> void:
	assert_true(FileAccess.file_exists(THIRD_PARTY), "缺少 docs/THIRD_PARTY.md")
	var text := FileAccess.get_file_as_string(THIRD_PARTY)
	for keyword in ["Godot", "mc_game_framework", "Sound Manager", "Kenney", "MiSans", "GodotShaders", "GUT"]:
		assert_string_contains(text, keyword, "许可清单里没有提到 %s" % keyword)


func test_credits_panel_is_registered_and_opens() -> void:
	assert_true(GameBootstrap.PANEL_DEFS.has(UIKeys.CREDITS), "致谢面板没有登记")
	var panel := _open(UIKeys.CREDITS)
	await wait_process_frames(1)
	assert_not_null(panel, "致谢面板打不开")
	if panel == null:
		return
	assert_true(panel is CreditsPanel)
	assert_gt(panel.content.get_child_count(), 0, "致谢面板是空的")


func test_settings_has_music_and_effects_volume_rows() -> void:
	var panel := _open(UIKeys.SETTINGS) as SettingsPanel
	await wait_process_frames(1)
	assert_not_null(panel, "设置面板打不开")
	if panel == null:
		return
	var found: Array[Node] = []
	_walk_collect(panel, "HSlider", found)
	assert_gte(found.size(), 3, "设置里应该有总音量/音乐/音效三条滑杆")


func test_audio_buses_are_split_by_purpose() -> void:
	assert_gte(AudioServer.get_bus_index("Music"), 1, "缺少 Music 总线")
	assert_gte(AudioServer.get_bus_index("UI"), 1, "缺少 UI 总线")
	var manager: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("SoundManager")
	assert_not_null(manager, "SoundManager 不在场景树里")
	var ui_pool: Node = manager.get("ui_sound_effects")
	assert_eq(ui_pool.get("bus"), "UI", "界面音效应该走 UI 总线")


func test_music_interface_is_safe_without_assets() -> void:
	var tracks := Music.available_tracks()
	assert_true(tracks is Array, "available_tracks 应该返回数组")
	# 缺素材时 play() 会 push_warning（GUT 会把 warning 记成脏输出），所以这里只验查表这一层
	assert_false(Music.has_track("definitely_not_a_track"))
	assert_false(Music.is_playing(), "没有素材时不该有音乐在播")


func test_music_volume_round_trips_on_its_bus() -> void:
	var before := Music.get_volume()
	Music.set_volume(0.4)
	assert_almost_eq(Music.get_volume(), 0.4, 0.02, "音乐音量没有写到 Music 总线")
	Music.set_volume(before)


func _open(panel_id: String) -> GamePanel:
	UIManager.open_panel(ResourceLocation.from_string(panel_id))
	return UIManager.get_top_panel(UILayer.NORMAL) as GamePanel


## 收集所有指定类型的后代（lambda 按值捕获，别在闭包里累加计数）
func _walk_collect(root: Node, type_name: String, found: Array[Node]) -> void:
	if root.is_class(type_name):
		found.append(root)
	for child in root.get_children():
		_walk_collect(child, type_name, found)
