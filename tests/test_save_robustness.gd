extends GutTest
## P5 存档健壮性：双槽轮写、写后校验、损坏回退、版本不认识时改用备份。

const TMP_DIR := "res://tests/tmp"
const TMP_SAVE := "res://tests/tmp/robust_save.json"

var _saver: SaveGame = null


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	_saver = SaveGame.new(TMP_SAVE)
	_saver.remove()
	GameState.reset()


func after_each() -> void:
	if _saver != null:
		_saver.remove()


func _payload(coins: int) -> Dictionary:
	var data := GameState.to_dict()
	data["coins"] = coins
	return data


func _write_raw(target: String, text: String) -> void:
	var file := FileAccess.open(target, FileAccess.WRITE)
	assert_not_null(file, "临时文件应能创建：%s" % target)
	if file == null:
		return
	file.store_string(text)
	file.close()


# --- 正常写入 -------------------------------------------------------------


func test_save_then_load_keeps_the_data_and_leaves_no_temp_file() -> void:
	assert_eq(_saver.save_state(_payload(42)), OK, "写盘应成功")
	assert_true(FileAccess.file_exists(TMP_SAVE), "主档应存在")
	assert_false(FileAccess.file_exists(_saver.temp_path()), "临时文件应已转正，不该留在盘上")

	var loaded := _saver.load_state()
	assert_eq(int(loaded.get("coins", -1)), 42)
	assert_eq(_saver.last_load_source, "main", "应记下读到的是主档")


func test_second_save_rotates_the_previous_one_into_backup() -> void:
	assert_eq(_saver.save_state(_payload(10)), OK)
	assert_eq(_saver.save_state(_payload(20)), OK)

	assert_eq(int(_saver.load_state().get("coins", -1)), 20, "主档应是最新一次")
	assert_true(_saver.has_backup(), "第二次写盘应留下备份")
	assert_eq(int(_saver.load_backup().get("coins", -1)), 10, "备份应是上一版")


# --- 损坏回退 -------------------------------------------------------------


func test_corrupt_main_falls_back_to_backup() -> void:
	assert_eq(_saver.save_state(_payload(10)), OK)
	assert_eq(_saver.save_state(_payload(20)), OK)
	_write_raw(TMP_SAVE, "{ 这不是 JSON")

	var loaded := _saver.load_state()
	assert_eq(int(loaded.get("coins", -1)), 10, "主档坏了应回退到备份")
	assert_eq(_saver.last_load_source, "backup")


func test_saving_over_a_corrupt_main_keeps_the_good_backup() -> void:
	assert_eq(_saver.save_state(_payload(10)), OK)
	assert_eq(_saver.save_state(_payload(20)), OK)
	_write_raw(TMP_SAVE, "坏掉的主档")

	assert_eq(_saver.save_state(_payload(30)), OK, "坏主档不该挡住新的写入")
	assert_eq(int(_saver.load_state().get("coins", -1)), 30, "新的主档应可用")
	assert_eq(int(_saver.load_backup().get("coins", -1)), 10, "坏主档不该挤掉上一份好备份")


func test_missing_version_field_is_treated_as_unreadable() -> void:
	_write_raw(TMP_SAVE, JSON.stringify({"coins": 5}))
	assert_true(_saver.load_state().is_empty(), "没有版本字段的档应当作读不出来")
	assert_eq(_saver.last_load_source, "")


func test_remove_deletes_main_backup_and_temp() -> void:
	assert_eq(_saver.save_state(_payload(1)), OK)
	assert_eq(_saver.save_state(_payload(2)), OK)
	_write_raw(_saver.temp_path(), "{}")

	_saver.remove()
	assert_false(FileAccess.file_exists(TMP_SAVE), "主档应被删除")
	assert_false(FileAccess.file_exists(_saver.backup_path()), "备份应被删除")
	assert_false(FileAccess.file_exists(_saver.temp_path()), "临时文件应被删除")
	assert_false(_saver.exists())


# --- 版本迁移失败时改用备份（GameBridge 的恢复顺序） -----------------------


func test_bridge_falls_back_to_backup_when_main_version_is_unknown() -> void:
	assert_eq(_saver.save_state(_payload(10)), OK)
	assert_eq(_saver.save_state(_payload(20)), OK)

	# 主档换成「结构合法但版本不认识」的档：SaveGame 读得出来，GameState 迁移不了
	var future := _payload(999)
	future["version"] = 99
	_write_raw(TMP_SAVE, JSON.stringify(future, "\t"))

	var bridge := GameBridge.new()
	bridge.save = SaveGame.new(TMP_SAVE)
	bridge.call("_restore_or_start")
	assert_eq(GameState.coins, 10, "应退回备份那一版（10 铜币），而不是开新档")
	bridge.free()


func test_bridge_starts_a_new_game_when_no_save_survives() -> void:
	_write_raw(TMP_SAVE, "整个文件都坏了")

	var bridge := GameBridge.new()
	bridge.save = SaveGame.new(TMP_SAVE)
	bridge.call("_restore_or_start")
	assert_eq(GameState.coins, 0, "两份都不可用时应开新档")
	assert_eq(GameState.last_seen_unix, 0, "新档不该结算离线时间")
	bridge.free()
