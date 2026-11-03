class_name SaveGame
extends RefCounted
## 存档读写的唯一入口：只做文件 IO、写后校验与轮转备份，状态序列化在 `GameState.to_dict()`。
##
## 为什么是「主档 + 备份」两槽，而不是单文件：
## 断电、进程被杀、磁盘满都可能留下半截 JSON，单槽坏掉就等于这一局没了。
## 所以每次写都是「写临时文件 → 校验读得回来 → 旧主档挪进备份 → 临时文件转正」，
## 读档时主档坏就用备份顶上去；任一步失败都保留上一份能用的档，不做破坏性覆盖。
##
## 路径可注入：正式运行用 `user://`，GUT 用 `res://tests/tmp/`。
## 版本判断仍然只在 `GameState.restore_from_dict()` 里做——这里只挡「读不出结构」的文件。

const DEFAULT_PATH := "user://save_v1.json"
const BACKUP_SUFFIX := ".bak"
const TEMP_SUFFIX := ".tmp"

## 存档文件路径
var path: String
## 上一次 `load_state()` 用的是哪份：`"main"` / `"backup"` / `""`（没读到）
var last_load_source := ""
## 上一次读档的失败原因（诊断用，正常为 `""`）
var last_load_error := ""


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path


func backup_path() -> String:
	return path + BACKUP_SUFFIX


func temp_path() -> String:
	return path + TEMP_SUFFIX


## 主档或备份任一存在即算有档
func exists() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(backup_path())


func remove() -> void:
	for target in [path, backup_path(), temp_path()]:
		_erase(target)


## 把主档与备份各复制一份到 `<path>.<tag>.json` / `<path>.<tag>.bak.json`。
##
## 用途只有一个：读得出来、但版本迁移不认的旧档，不能在开新局后被自动存档覆盖。
## 不覆盖同名副本（二次启动仍读不动时顺延序号），也不动主档与备份本身。
## 返回主档副本路径；主档不存在或复制失败时返回 `""`。
func preserve(tag: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var base := path.get_basename()
	var target := "%s.%s.json" % [base, tag]
	var serial := 2
	while FileAccess.file_exists(target):
		target = "%s.%s-%d.json" % [base, tag, serial]
		serial += 1
	if _copy_file(path, target) != OK:
		push_warning("[SaveGame] 旧档另存失败：%s" % target)
		return ""
	if FileAccess.file_exists(backup_path()):
		var backup_target := "%s.bak.json" % target.trim_suffix(".json")
		if _copy_file(backup_path(), backup_target) != OK:
			push_warning("[SaveGame] 旧备份另存失败：%s" % backup_target)
	return target


## 写盘：临时文件 → 校验 → 轮转备份 → 转正。返回 Error。
##
## 主档本身已经损坏时**不**用它覆盖备份（那份备份可能正是唯一的好档）。
func save_state(data: Dictionary) -> Error:
	var tmp := temp_path()
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		var err := FileAccess.get_open_error()
		push_error("[SaveGame] 打不开存档写入：%s（错误 %d）" % [tmp, err])
		return err
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	if not _is_readable_save(tmp):
		push_error("[SaveGame] 写出的存档校验失败，已放弃本次写入：%s" % tmp)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return ERR_FILE_CORRUPT

	# 旧主档能读才进备份；坏档不该挤掉上一份好备份
	if FileAccess.file_exists(path) and _is_readable_save(path):
		var copy_error := _copy_file(path, backup_path())
		if copy_error != OK:
			push_warning("[SaveGame] 备份旧档失败（错误 %d），继续写主档" % copy_error)

	var rename_error := _move_file(tmp, path)
	if rename_error != OK:
		push_error("[SaveGame] 存档落盘失败（错误 %d）：%s" % [rename_error, path])
		_erase(tmp)
		return rename_error
	return OK


## 读主档；主档不可用时自动回退备份。两份都不可用返回空字典（调用方按新档处理）。
func load_state() -> Dictionary:
	last_load_source = ""
	last_load_error = ""

	var main := _read_save(path)
	if not main.is_empty():
		last_load_source = "main"
		return main

	var backup := _read_save(backup_path())
	if not backup.is_empty():
		last_load_source = "backup"
		push_warning("[SaveGame] 主档不可用（%s），已回退备份：%s" % [last_load_error, backup_path()])
		return backup

	return {}


## 只读备份（版本迁移失败时由调用方决定要不要再试一次备份）
func load_backup() -> Dictionary:
	return _read_save(backup_path())


func has_backup() -> bool:
	return FileAccess.file_exists(backup_path())


func _read_save(target: String) -> Dictionary:
	if not FileAccess.file_exists(target):
		last_load_error = "文件不存在"
		return {}
	var text := FileAccess.get_file_as_string(target)
	if text.is_empty():
		last_load_error = "文件为空"
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		last_load_error = "不是合法 JSON：%s" % json.get_error_message()
		push_warning("[SaveGame] %s（%s）" % [last_load_error, target])
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		last_load_error = "内容不是字典"
		push_warning("[SaveGame] %s：%s" % [last_load_error, target])
		return {}
	var data := parsed as Dictionary
	if not data.has("version"):
		last_load_error = "缺少版本字段"
		push_warning("[SaveGame] %s：%s" % [last_load_error, target])
		return {}
	last_load_error = ""
	return data


## 删一个文件（Web 端没有真实 OS 路径，一律走 DirAccess 的相对 API）
func _erase(target: String) -> void:
	if not FileAccess.file_exists(target):
		return
	var dir := DirAccess.open(target.get_base_dir())
	if dir == null:
		push_warning("[SaveGame] 打不开目录，删不掉：%s" % target)
		return
	var error := dir.remove(target.get_file())
	if error != OK:
		push_warning("[SaveGame] 删除失败（错误 %d）：%s" % [error, target])


## 复制：读出来再写一遍，够小（存档几十 KB），在所有平台都一样能用
func _copy_file(source: String, target: String) -> Error:
	var text := FileAccess.get_file_as_string(source)
	if text.is_empty():
		return ERR_FILE_CANT_READ
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK


## 转正：优先同目录 rename，失败退回「复制 + 删临时」
func _move_file(source: String, target: String) -> Error:
	var dir := DirAccess.open(target.get_base_dir())
	if dir != null:
		var error := dir.rename(source.get_file(), target.get_file())
		if error == OK:
			return OK
	var copy_error := _copy_file(source, target)
	if copy_error != OK:
		return copy_error
	_erase(source)
	return OK


func _is_readable_save(target: String) -> bool:
	if not FileAccess.file_exists(target):
		return false
	var text := FileAccess.get_file_as_string(target)
	if text.is_empty():
		return false
	var json := JSON.new()
	if json.parse(text) != OK:
		return false
	if not json.data is Dictionary:
		return false
	return (json.data as Dictionary).has("version")
