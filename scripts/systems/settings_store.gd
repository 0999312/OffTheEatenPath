class_name SettingsStore
extends RefCounted
## 本地设置（语言、音量、灶台选择）：`user://settings.cfg`。
##
## 与存档解耦——清档不重置设置（决策见 `docs/TODO.md` A4）。写入失败只告警、
## 不中断游戏：Web 导出与只读环境下 `user://` 可能不可写。
##
## 为什么不做成 autoload：没有状态、没有生命周期，纯函数式读改写更简单，
## 也避免与框架的四个单例抢职责。

const DEFAULT_PATH := "user://settings.cfg"
const SECTION_GENERAL := "general"
const SECTION_AUDIO := "audio"
const SECTION_CRAFT := "craft"
const KEY_LOCALE := "locale"
## 灶台上次选中的配方键（空串 = 没选过）
const KEY_LAST_RECIPE := "last_recipe"
## 灶台筛选：0 = 全部，1 = 可做，2 = 未记录（与 CraftPanel.Filter 对齐）
const KEY_FILTER_MODE := "filter_mode"
## 旧版的布尔键：仅用于把老设置迁到 filter_mode，不再写入
const LEGACY_KEY_ONLY_CRAFTABLE := "only_craftable"

## 正常运行时用 DEFAULT_PATH；测试可临时改路径
static var path: String = DEFAULT_PATH

## 读一个值；文件不存在、没存过这个键或读取失败时返回默认值
static func get_value(section: String, key: String, default_value: Variant = null) -> Variant:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return default_value
	if not config.has_section_key(section, key):
		return default_value
	# ConfigFile.get_value 的默认参数不接受 NIL（引擎会报错），这里给个占位类型；
	# 键存在时返回的永远是文件里的真实类型
	return config.get_value(section, key, 0.0)


## 这个 section.key 是否存在（用来区分「没存过」和「存了 0」）
static func has_value(section: String, key: String) -> bool:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return false
	return config.has_section_key(section, key)


## 写一个值；成功返回 true。保留文件里其它 section 的已有内容。
static func set_value(section: String, key: String, value: Variant) -> bool:
	var config := ConfigFile.new()
	config.load(path)  # 文件不存在也没关系，下一步会新建
	config.set_value(section, key, value)
	var err := config.save(path)
	if err != OK:
		push_warning("[SettingsStore] 设置写入失败（错误码 %d）：%s" % [err, path])
		return false
	return true

## 保存的界面语言；没有保存过返回空串（调用方回落到系统语言）
static func get_locale() -> String:
	return String(get_value(SECTION_GENERAL, KEY_LOCALE, ""))

static func set_locale(code: String) -> bool:
	return set_value(SECTION_GENERAL, KEY_LOCALE, code)


## 灶台上次选中的配方（第八轮反馈 3）；空串表示还没选过
static func get_craft_recipe() -> String:
	return String(get_value(SECTION_CRAFT, KEY_LAST_RECIPE, ""))


static func set_craft_recipe(recipe_key: String) -> bool:
	return set_value(SECTION_CRAFT, KEY_LAST_RECIPE, recipe_key)


## 灶台筛选模式（第八轮反馈 3；R15 改为三档）
## 新键不存在时回落旧布尔键：true → 可做，false → 全部。
static func get_craft_filter() -> int:
	if has_value(SECTION_CRAFT, KEY_FILTER_MODE):
		return clampi(int(get_value(SECTION_CRAFT, KEY_FILTER_MODE, 0)), 0, 2)
	return 1 if bool(get_value(SECTION_CRAFT, LEGACY_KEY_ONLY_CRAFTABLE, false)) else 0


static func set_craft_filter(mode: int) -> bool:
	return set_value(SECTION_CRAFT, KEY_FILTER_MODE, clampi(mode, 0, 2))
