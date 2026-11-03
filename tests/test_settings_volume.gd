extends GutTest
## 音量持久化：写进 settings.cfg 的 audio 段，启动时 GameBootstrap 把它写回总线。

const TEST_SETTINGS_PATH := "user://__test_volume_settings.cfg"

var _original_path: String


func before_each() -> void:
	_original_path = SettingsStore.path
	SettingsStore.path = TEST_SETTINGS_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_PATH))


func after_each() -> void:
	SettingsStore.path = _original_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_PATH))
	_restore_bus("Master", 1.0)


func test_audio_volume_roundtrip_when_writable() -> void:
	var ok := SettingsStore.set_value(SettingsStore.SECTION_AUDIO, "Master", 0.35)
	if not ok:
		pass_test("user:// 在当前环境不可写（沙箱），跳过往返断言")
		return
	var saved := float(SettingsStore.get_value(SettingsStore.SECTION_AUDIO, "Master", -1.0))
	assert_almost_eq(saved, 0.35, 0.001, "音量应该写进 settings.cfg")


func test_bootstrap_applies_saved_volume() -> void:
	var ok := SettingsStore.set_value(SettingsStore.SECTION_AUDIO, "Master", 0.25)
	if not ok:
		pass_test("user:// 在当前环境不可写（沙箱），跳过应用断言")
		return
	GameBootstrap._apply_audio_settings()
	var index := AudioServer.get_bus_index("Master")
	assert_almost_eq(db_to_linear(AudioServer.get_bus_volume_db(index)), 0.25, 0.02, "启动时应该把保存的音量写回总线")


func test_missing_settings_keeps_bus_untouched() -> void:
	var index := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(index, 0.0)
	GameBootstrap._apply_audio_settings()
	assert_almost_eq(db_to_linear(AudioServer.get_bus_volume_db(index)), 1.0, 0.02, "没有保存值时不应该改总线音量")


func _restore_bus(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(index, false)
