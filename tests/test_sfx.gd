extends GutTest
## 音效层：意图表要真的指向能加载的文件，且坏意图不能把游戏搞炸。

const SFX := preload("res://scripts/systems/sfx.gd")
const PANEL_KIT := preload("res://scripts/ui/panel_kit.gd")


func test_every_registered_intent_loads_a_stream() -> void:
	for intent in SFX.registered_intents():
		var resource: AudioStream = SFX.stream(intent)
		assert_not_null(resource, "意图 %d 没有对应音频" % intent)
		assert_true(SFX.has_stream(intent), "has_stream 与 stream 不一致：%d" % intent)


func test_every_enum_value_is_registered_except_none() -> void:
	var registered := SFX.registered_intents()
	var intents := Sfx.Intent.values()
	assert_eq(registered.size(), intents.size() - 1, "枚举里有未登记到 FILES 的意图")
	for intent in intents:
		if intent == Sfx.Intent.NONE:
			continue
		assert_true(registered.has(intent), "枚举值 %d 没登记音频" % intent)


func test_none_intent_is_silent() -> void:
	assert_null(SFX.stream(Sfx.Intent.NONE))
	assert_false(SFX.has_stream(Sfx.Intent.NONE))


func test_unknown_intent_does_not_crash() -> void:
	assert_null(SFX.stream(9999))
	SFX.play(9999)
	SFX.play(Sfx.Intent.NONE)
	assert_true(true, "坏意图不应该抛错")


func test_play_reaches_the_sound_manager() -> void:
	# SoundManager 是插件注册的 autoload；在 GUT 里能拿到就说明 play 有落点
	var tree := Engine.get_main_loop() as SceneTree
	assert_not_null(tree, "拿不到 SceneTree")
	var manager: Node = tree.root.get_node_or_null("SoundManager")
	assert_not_null(manager, "SoundManager autoload 不在场景树里")
	SFX.play(Sfx.Intent.CLICK)
	assert_true(true, "播放不应抛错")


func test_panel_kit_button_carries_a_click() -> void:
	var button: Button = PANEL_KIT.button("试试")
	add_child_autofree(button)
	assert_eq(button.pressed.get_connections().size(), 1, "默认按钮应该自带一个按键声")


func test_panel_kit_button_can_be_muted() -> void:
	var button: Button = PANEL_KIT.button("试试", Sfx.Intent.NONE)
	add_child_autofree(button)
	assert_eq(button.pressed.get_connections().size(), 0, "传 NONE 时不应该挂声音")

func test_shared_files_are_pitched_down_by_default() -> void:
	# 三组复用文件靠降调区分；不升调是因为升调会把能量推回 3–6 kHz
	assert_almost_eq(SFX.effective_pitch(Sfx.Intent.UPGRADE), 0.92, 0.001, "UPGRADE 应该降调")
	assert_almost_eq(SFX.effective_pitch(Sfx.Intent.RESEARCH_OK), 0.94, 0.001, "RESEARCH_OK 应该降调")
	assert_almost_eq(SFX.effective_pitch(Sfx.Intent.RESEARCH_FAIL), 0.90, 0.001, "RESEARCH_FAIL 应该降调")
	for intent in [Sfx.Intent.CLICK, Sfx.Intent.OPEN, Sfx.Intent.CLOSE]:
		assert_almost_eq(SFX.effective_pitch(intent), 1.0, 0.001, "未登记默认音高的意图不该变调：%d" % intent)
	assert_almost_eq(SFX.effective_pitch(Sfx.Intent.UPGRADE, 1.2), 1.2, 0.001, "显式音高应覆盖默认值")


func test_all_interface_sounds_come_from_kenney() -> void:
	# 第二轮反馈：cozy 素材太活泼，界面音效回到 Kenney 原包（CC0）
	for intent in SFX.registered_intents():
		# 三枚环境音不是「界面包相对文件名」：两枚在 assets/audio/sfx，来访铃是包里 bong_001 的本地副本
		if intent == Sfx.Intent.KNOCK or intent == Sfx.Intent.DISH_CLINK or intent == Sfx.Intent.VISIT:
			continue
		var path := String(SFX.FILES[intent])
		assert_false(path.begins_with("res://"), "意图 %d 不是 Kenney 包内文件：%s" % [intent, path])
		assert_true(ResourceLoader.exists(SFX.SOUND_ROOT + path), "Kenney 包里找不到：%s" % path)


## 第七轮反馈 14：来访用铃，不再和敲门共用。
func test_visit_uses_a_local_copy_of_the_kenney_bell() -> void:
	assert_eq(String(SFX.FILES[Sfx.Intent.VISIT]), "res://assets/audio/sfx/visit_bell.wav",
			"来访铃应是本地副本，便于单独调音")
	assert_true(FileAccess.file_exists(SFX.FILES[Sfx.Intent.VISIT]), "来访铃文件应在仓库里")
	assert_ne(String(SFX.FILES[Sfx.Intent.VISIT]), String(SFX.FILES[Sfx.Intent.KNOCK]), "来访不该再用敲门声")


func test_open_and_close_use_different_soft_files() -> void:
	# open/close 原始一族 >6 kHz 占 45–95%；改用 maximize/minimize 系列（两段能量都接近 0）
	assert_ne(String(SFX.FILES[Sfx.Intent.OPEN]), String(SFX.FILES[Sfx.Intent.CLOSE]), "OPEN 与 CLOSE 应该用不同文件")
	assert_eq(String(SFX.FILES[Sfx.Intent.OPEN]), "maximize_009.wav")
	assert_eq(String(SFX.FILES[Sfx.Intent.CLOSE]), "minimize_008.wav")


func test_shared_file_pairs_stay_paired() -> void:
	assert_eq(String(SFX.FILES[Sfx.Intent.UPGRADE]), String(SFX.FILES[Sfx.Intent.MILESTONE]))
	assert_eq(String(SFX.FILES[Sfx.Intent.CRAFT_DONE]), String(SFX.FILES[Sfx.Intent.RESEARCH_OK]))
	assert_eq(String(SFX.FILES[Sfx.Intent.DENY]), String(SFX.FILES[Sfx.Intent.RESEARCH_FAIL]))


func test_pool_gain_is_applied_to_the_player() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var manager: Node = tree.root.get_node_or_null("SoundManager")
	assert_not_null(manager, "SoundManager 不在场景树里")
	var pool: Node = manager.get("ui_sound_effects")
	assert_not_null(pool, "SoundManager 没有 UI 音效池")
	SFX.play(Sfx.Intent.CLICK)
	var busy: Array = pool.get("busy_players")
	assert_gt(busy.size(), 0, "播放后应该有一个播放器进入 busy 状态")
	var player: AudioStreamPlayer = busy[busy.size() - 1]
	assert_almost_eq(player.volume_db, SFX.GAIN_DB, 0.01, "池级增益没有写进播放器")


func test_play_hands_the_stream_to_a_pooled_player() -> void:
	# 只断言「不报错」太弱：这里查 SoundManager 的 UI 池里确实有播放器拿走了流
	var tree := Engine.get_main_loop() as SceneTree
	var manager: Node = tree.root.get_node_or_null("SoundManager")
	assert_not_null(manager, "SoundManager 不在场景树里")
	var pool: Node = manager.get("ui_sound_effects")
	assert_not_null(pool, "SoundManager 没有 UI 音效池")
	var before: int = pool.get("busy_players").size()
	SFX.play(Sfx.Intent.CLICK)
	var after: int = pool.get("busy_players").size()
	assert_gt(after, before, "播放后应该有一个播放器进入 busy 状态")
