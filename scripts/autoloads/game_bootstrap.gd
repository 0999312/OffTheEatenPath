extends Node
## 游戏启动装配（组合根 / composition root）。
##
## 职责只有接线：把 mc_game_framework 提供的基础设施（RegistryManager /
## EventBus / I18NManager / UIManager）与《随食出发》自己的注册表、面板绑起来，
## 然后按需触发启动自检。不持有任何玩法状态（玩法状态归 GameState，P2）。
##
## 在 project.godot 的 [autoload] 中必须排在四个框架 autoload 之后，
## 否则 _ready 时框架单例尚未就绪。

## 框架里 UI 注册表的固定键名
const UI_REGISTRY_KEY := "ui"
## 本游戏静态内容注册表的固定键名（DataRegistry）
const DATA_REGISTRY_KEY := DataRegistry.REGISTRY_NAME
## 框架标签注册表的固定键名（成员由 DataRegistry 灌入）
const TAG_REGISTRY_KEY := DataRegistry.TAG_REGISTRY_KEY
## 强制开启启动自检的命令行参数（非调试构建也可用）
const SELF_CHECK_FLAG := "--boot-check"
## 翻译文件目录：`resources/i18n/<locale>.json`
const TRANSLATION_DIR := "res://resources/i18n"
## 支持的语言；第一个也是系统语言匹配不上时的缺省值。
## 没有对应 `resources/i18n/<code>.json` 的语言会被跳过，不影响启动。
const SUPPORTED_LOCALES: Array[String] = [
	"zh_CN", "zh_TW", "en", "ja", "ko", "fr", "de", "es", "pt_BR",
	"ru", "pl", "tr", "it", "id", "vi", "th",
]
## 改名前的 `user://` 目录名（`project.godot` 的 config/name 是《随食出发》时）
const LEGACY_USER_DIR_NAME := "随食出发"
const EVENT_LANGUAGE := &"LanguageChangedEvent"
## 会写进 `user://settings.cfg` 的三条音量总线（顺序与设置面板一致）
const AUDIO_BUSES: Array[String] = ["Master", "Music", "UI"]

## 背景音乐轮播的检查间隔：一秒两次足够，切歌晚半秒听不出来。
const MUSIC_POLL_INTERVAL := 0.5

var _music_poll := 0.0

## 面板登记表：ResourceLocation 字符串 → 场景 / 层级 / 缓存策略
## ID 常量集中在 UIKeys，避免这里和调用方各写一份字符串。
const PANEL_DEFS := {
	UIKeys.DIAGNOSTIC: {
		"scene": "res://scenes/ui/diagnostic_panel.tscn",
		"layer": UILayer.POPUP,
		"cache_mode": UIPanel.CacheMode.NONE,
	},
	UIKeys.CRAFT: {
		"scene": "res://scenes/ui/panels/craft_panel.tscn",
		"layer": UILayer.NORMAL,
		"cache_mode": UIPanel.CacheMode.NONE,
	},
	UIKeys.ORDERS: {
		"scene": "res://scenes/ui/panels/order_panel.tscn",
		"layer": UILayer.NORMAL,
		"cache_mode": UIPanel.CacheMode.NONE,
	},
	UIKeys.CATALOG: {
		"scene": "res://scenes/ui/panels/catalog_panel.tscn",
		"layer": UILayer.NORMAL,
		"cache_mode": UIPanel.CacheMode.NONE,
	},
	UIKeys.RESEARCH: {
		"scene": "res://scenes/ui/panels/research_panel.tscn",
		"layer": UILayer.NORMAL,
		"cache_mode": UIPanel.CacheMode.NONE,
	},
	UIKeys.FACILITY: {
		"scene": "res://scenes/ui/panels/facility_panel.tscn",
		"layer": UILayer.NORMAL,
		"cache_mode": UIPanel.CacheMode.NONE,
	},
	UIKeys.MERCHANT: {
		"scene": "res://scenes/ui/panels/merchant_panel.tscn",
		"layer": UILayer.NORMAL,
		"cache_mode": UIPanel.CacheMode.NONE,
	},
	UIKeys.WAREHOUSE: {
		"scene": "res://scenes/ui/panels/warehouse_panel.tscn",
		"layer": UILayer.NORMAL,
		"cache_mode": UIPanel.CacheMode.NONE,
	},
	UIKeys.MAIL: {
		"scene": "res://scenes/ui/panels/mail_panel.tscn",
		"layer": UILayer.NORMAL,
		"cache_mode": UIPanel.CacheMode.NONE,
	},
	UIKeys.SETTINGS: {
		"scene": "res://scenes/ui/panels/settings_panel.tscn",
		"layer": UILayer.NORMAL,
		"cache_mode": UIPanel.CacheMode.NONE,
	},
	UIKeys.CREDITS: {
		"scene": "res://scenes/ui/panels/credits_panel.tscn",
		"layer": UILayer.NORMAL,
		"cache_mode": UIPanel.CacheMode.NONE,
	},
	UIKeys.LETTER_DETAIL: {
		"scene": "res://scenes/ui/panels/letter_detail_panel.tscn",
		"layer": UILayer.POPUP,
		"cache_mode": UIPanel.CacheMode.NONE,
	},
	UIKeys.CATALOG_DETAIL: {
		"scene": "res://scenes/ui/panels/catalog_detail_panel.tscn",
		"layer": UILayer.POPUP,
		"cache_mode": UIPanel.CacheMode.NONE,
	},
	UIKeys.OFFLINE: {
		"scene": "res://scenes/ui/panels/offline_panel.tscn",
		"layer": UILayer.POPUP,
		"cache_mode": UIPanel.CacheMode.NONE,
	},
}

## 提示（toast）登记表：走框架的 TOAST 层，不进面板栈
const TOAST_DEFS := {
	UIKeys.TOAST_MESSAGE: "res://scenes/ui/toast_message.tscn",
}

func _ready() -> void:
	_migrate_user_dir()
	_load_localization()
	_apply_window_title()
	_apply_audio_settings()
	EventBus.subscribe(EVENT_LANGUAGE, _on_language_changed)
	_register_registries()
	_load_game_data()
	_register_panels()
	_register_toasts()
	if _should_run_self_check():
		_run_self_check()
	_start_music()


## 背景音乐随机轮播：切曲子由 `_process` 里「这首是不是快到尾巴了」决定，
## 用一个低频轮询而不是给每首接 finished 信号，切歌逻辑只有一处。
## 提前一个 crossfade 换曲，新曲淡入刚好叠在旧曲淡出上。
func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_music_poll += delta
	if _music_poll < MUSIC_POLL_INTERVAL:
		return
	_music_poll = 0.0
	Music.warm_next()
	if Music.needs_next():
		Music.play_random()


func _exit_tree() -> void:
	EventBus.unsubscribe(EVENT_LANGUAGE, _on_language_changed)


func _on_language_changed(_event: Event) -> void:
	_apply_window_title()


# ─── 用户目录 ───

## 项目英文名改过一轮：`user://` 目录名跟着 `config/name` 变过一次。
## 只在「新目录还没有任何进度」时把旧目录的存档与设置搬过来，绝不覆盖新档。
func _migrate_user_dir() -> void:
	var root := OS.get_user_data_dir()
	if FileAccess.file_exists("user://save_v1.json") or FileAccess.file_exists("user://settings.cfg"):
		return
	var legacy := root.get_base_dir().path_join(LEGACY_USER_DIR_NAME)
	if not DirAccess.dir_exists_absolute(legacy):
		return
	_copy_dir(legacy, root)


## 递归复制目录内容（同名的文件跳过，不覆盖）
func _copy_dir(from: String, to: String) -> void:
	var dir := DirAccess.open(from)
	if dir == null:
		push_warning("[GameBootstrap] 旧用户目录打不开：%s" % from)
		return
	if not DirAccess.dir_exists_absolute(to):
		DirAccess.make_dir_recursive_absolute(to)
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var src := from.path_join(entry)
		var dst := to.path_join(entry)
		if dir.current_is_dir():
			_copy_dir(src, dst)
		elif not FileAccess.file_exists(dst):
			var bytes := FileAccess.get_file_as_bytes(src)
			if bytes.is_empty():
				push_warning("[GameBootstrap] 旧存档文件读不出来：%s" % src)
			else:
				var out := FileAccess.open(dst, FileAccess.WRITE)
				if out == null:
					push_warning("[GameBootstrap] 旧存档迁移失败：%s" % dst)
				else:
					out.store_buffer(bytes)
					out.close()
		entry = dir.get_next()
	dir.list_dir_end()


## 窗口标题跟随当前语言（project.godot 里只能写死一个名字）
func _apply_window_title() -> void:
	if DisplayServer.get_name() == "headless":
		return
	get_window().title = I18n.t("ui.app.title")


## 把设置面板存下的音量写回总线；没存过（首次运行）就保持工程里的默认值。
## 与存档分离：清档不动音量（`docs/TODO.md` A4 的拍板）。
func _apply_audio_settings() -> void:
	for bus in AUDIO_BUSES:
		var saved: Variant = SettingsStore.get_value(SettingsStore.SECTION_AUDIO, bus, null)
		if saved == null:
			continue
		var index := AudioServer.get_bus_index(bus)
		if index < 0:
			continue
		var linear := clampf(float(saved), 0.0, 1.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(index, linear <= 0.001)


## 进游戏就有声：从 `assets/audio/music/` 随机挑一首；目录为空时 `play_random()` 返回 false。
func _start_music() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Music.play_random()

# ─── 本地化 ───

## 载入两种语言的 JSON，并按设置（或系统语言）选一个
func _load_localization() -> void:
	for code in SUPPORTED_LOCALES:
		var path := "%s/%s.json" % [TRANSLATION_DIR, code]
		if not FileAccess.file_exists(path):
			continue
		if not I18NManager.load_translation(code, path):
			push_error("[GameBootstrap] 翻译文件加载失败：%s" % path)
	var locale := SettingsStore.get_locale()
	if locale.is_empty() or not SUPPORTED_LOCALES.has(locale):
		locale = _system_locale()
	I18NManager.set_language(locale)

## 先精确匹配，再按语言前缀匹配（zh_Hans→zh_CN、pt_PT→pt_BR 之类），最后回退英文
func _system_locale() -> String:
	var sys := OS.get_locale()
	if SUPPORTED_LOCALES.has(sys):
		return sys
	var base := sys.split("_")[0]
	for code in SUPPORTED_LOCALES:
		if code == base or code.begins_with(base + "_"):
			return code
	return "en"

# ─── 接线 ───

## 注册本游戏自己的注册表（框架只提供容器，内容由游戏提供）
func _register_registries() -> void:
	if not RegistryManager.has_registry(UI_REGISTRY_KEY):
		RegistryManager.register_registry(UI_REGISTRY_KEY, UIRegistry.new())
	if not RegistryManager.has_registry(DATA_REGISTRY_KEY):
		RegistryManager.register_registry(DATA_REGISTRY_KEY, DataRegistry.new())
	if not RegistryManager.has_registry(TAG_REGISTRY_KEY):
		RegistryManager.register_registry(TAG_REGISTRY_KEY, TagRegistry.new())

## 扫描 resources/game_data/ 下全部 .tres，登记进 DataRegistry；问题逐条报错
func _load_game_data() -> void:
	var data_registry := RegistryManager.get_registry(DATA_REGISTRY_KEY) as DataRegistry
	if data_registry == null:
		push_error("[GameBootstrap] 取不到 DataRegistry，静态内容未加载")
		return
	var started := Time.get_ticks_usec()
	var issues: Array[String] = data_registry.load_all()
	var loaded := Time.get_ticks_usec()
	# 标签索引要在校验之前灌好：配方里 by_tag 的校验要看标签底下有没有东西
	issues.append_array(data_registry.rebuild_tags())
	issues.append_array(data_registry.validate())
	var finished := Time.get_ticks_usec()
	# 加载预算是公开数字：内容只会一直涨（后面还要接 Mod），没有这行就不知道该在
	# 什么时候上延迟加载。debug 构建才打，正式包不留噪声。
	if OS.is_debug_build():
		print("[GameBootstrap] 静态内容 %d 条：读取 %.1f ms，校验 %.1f ms" % [
				data_registry.get_all_entries().size(),
				(loaded - started) / 1000.0,
				(finished - loaded) / 1000.0])
	for issue in issues:
		push_error("[GameBootstrap] 数据层问题：%s" % issue)

## 当前登记在 POPUP 层的面板 ID（测试与调试用）
static func get_popup_panel_ids() -> Array[String]:
	var ids: Array[String] = []
	for panel_key in PANEL_DEFS:
		var def: Dictionary = PANEL_DEFS[panel_key]
		if int(def.get("layer", UILayer.NORMAL)) == UILayer.POPUP:
			ids.append(String(panel_key))
	ids.sort()
	return ids


## 按 PANEL_DEFS 把面板场景登记进 UIRegistry
func _register_panels() -> void:
	var ui_registry := RegistryManager.get_registry(UI_REGISTRY_KEY) as UIRegistry
	if ui_registry == null:
		push_error("[GameBootstrap] 取不到 UIRegistry，面板注册已跳过")
		return
	for id_text in PANEL_DEFS:
		var def: Dictionary = PANEL_DEFS[id_text]
		var scene_path: String = def["scene"]
		var panel_id := ResourceLocation.from_string(id_text)
		if panel_id == null:
			push_error("[GameBootstrap] 面板 ID 非法：%s" % id_text)
			continue
		var scene := load(scene_path) as PackedScene
		if scene == null:
			push_error("[GameBootstrap] 面板场景加载失败：%s" % scene_path)
			continue
		ui_registry.register_panel(panel_id, scene, def["layer"], def["cache_mode"])


## 按 TOAST_DEFS 把提示场景登记进 UIRegistry（TOAST 层）
func _register_toasts() -> void:
	var ui_registry := RegistryManager.get_registry(UI_REGISTRY_KEY) as UIRegistry
	if ui_registry == null:
		push_error("[GameBootstrap] 取不到 UIRegistry，提示注册已跳过")
		return
	for id_text in TOAST_DEFS:
		var scene_path: String = TOAST_DEFS[id_text]
		var toast_id := ResourceLocation.from_string(id_text)
		if toast_id == null:
			push_error("[GameBootstrap] 提示 ID 非法：%s" % id_text)
			continue
		var scene := load(scene_path) as PackedScene
		if scene == null:
			push_error("[GameBootstrap] 提示场景加载失败：%s" % scene_path)
			continue
		ui_registry.register_toast(toast_id, scene)

# ─── 启动自检 ───

## 调试构建默认自检；发布构建只在显式传 --boot-check 时自检。
## `--` 之后的参数（如 `MyGame.exe -- --boot-check`）落在 get_cmdline_user_args() 里，
## 不查它的话导出版本永远跑不到自检，"发布包数据层为空"这类问题就没法用自检发现。
func _should_run_self_check() -> bool:
	if OS.is_debug_build():
		return true
	return SELF_CHECK_FLAG in OS.get_cmdline_args() or SELF_CHECK_FLAG in OS.get_cmdline_user_args()

func _run_self_check() -> void:
	var failures: Array[String] = BootSelfCheck.new().run()
	if failures.is_empty():
		print("[GameBootstrap] 启动自检通过：autoload / EventBus / UIRegistry / 面板开关 / 数据层 / 本地化")
		return
	for message in failures:
		push_error("[GameBootstrap] 启动自检失败：%s" % message)
