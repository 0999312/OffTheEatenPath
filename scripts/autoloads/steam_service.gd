extends Node
## Steam 接入探针（GodotSteam GDExtension）。
##
## 设计目标：没有安装插件时（编辑器、headless、GUT、Web）保持静默降级，
## 不改变现有游戏逻辑、不产生 ERROR、不影响门禁；安装插件并由 Steam 客户端
## 启动后才真正初始化。正式成就/云存档等能力后续按需求再接。

const DEFAULT_APP_ID := 5551230
## 正式 App ID（Off the Eaten Path，2026-11-03 创建）。注意：1420688 是 **Store Item ID**，
## 不是 App ID；App 5551230 下挂 depot 5551231，Developer Comp package 1914304。
## 本地调试想临时用 Valve 的 480：直接改这里的常量；不要在 project.godot 写
## `[steam] initialization/app_id`——GodotSteam 4.23.2 会触发旧设置转换，实测导致初始化失败。
## 正式构建必须落到自己的 App ID 上。

var _available := false
var _initialized := false
var _app_id := 0
var _status := "unavailable"
var _persona := ""
var _build_id := 0


func _ready() -> void:
	_probe()


func _probe() -> void:
	if not Engine.has_singleton("Steam"):
		return
	var steam: Object = Engine.get_singleton("Steam")
	if steam == null:
		return
	_available = true
	_app_id = int(ProjectSettings.get_setting("steam/initialization/app_id", DEFAULT_APP_ID))
	if _app_id <= 0:
		_app_id = DEFAULT_APP_ID
	var result: Variant = steam.call("steamInitEx", _app_id, true)
	_read_init_result(result)
	if _initialized:
		if steam.has_method("getPersonaName"):
			_persona = str(steam.call("getPersonaName"))
		if steam.has_method("getAppBuildId"):
			_build_id = int(steam.call("getAppBuildId"))
		print("[Steam] initialized app_id=%d user=%s build=%d" % [_app_id, _persona, _build_id])
	else:
		push_warning("[Steam] 初始化未成功（%s），按离线模式继续。" % _status)


func _read_init_result(result: Variant) -> void:
	if result is Dictionary:
		var data: Dictionary = result
		var raw: Variant = data.get("status", null)
		if raw is int:
			_initialized = int(raw) == 0
			_status = "success" if _initialized else "failed(%d)" % int(raw)
		else:
			var text := str(raw) if raw != null else "unknown"
			_status = text
			_initialized = text.to_lower() == "success" or text == "0"
	elif result is bool:
		_initialized = bool(result)
		_status = "success" if _initialized else "failed"
	else:
		_status = "unknown"


func is_available() -> bool:
	return _available


func is_initialized() -> bool:
	return _initialized


func get_status() -> String:
	return _status


func get_app_id() -> int:
	return _app_id


func get_build_id() -> int:
	return _build_id


func get_persona_name() -> String:
	return _persona


func _exit_tree() -> void:
	if not _initialized or not Engine.has_singleton("Steam"):
		return
	var steam: Object = Engine.get_singleton("Steam")
	if steam != null and steam.has_method("shutdown"):
		steam.call("shutdown")
