class_name I18n
extends RefCounted
## 翻译键的唯一出口：数据条目由 id 派生，界面文案走 `ui.*`。
##
## 键规范见 `docs/plans/2026-10-24-i18n.md` §3.1：
## - 数据条目：`<id 的 / 换成 .>.<字段短名>`，如 `item/americano` + `display_name`
##   → `item.americano.name`；带命名空间的完整键（`game:item/americano`）也接受，
##   冒号前的命名空间会被丢掉；
## - 界面文案：`ui.<面板>.<用途>`，如 `ui.order.title`；
## - 占位符统一 `{0}` `{1}`，交给框架 `I18NManager.get_text()` 的 `String.format`。
##
## 这里只负责「键怎么拼」与「复数取哪一条」；文本本身在
## `resources/i18n/<locale>.json`，切换语言由框架 `I18NManager` 负责。

## 语言的显示名（用各自的语言写，切换列表里不该出现翻译腔）
const LOCALE_NAMES := {
	"zh_CN": "中文",
	"zh_TW": "繁體中文",
	"en": "English",
	"ja": "日本語",
	"ko": "한국어",
	"fr": "Français",
	"de": "Deutsch",
	"es": "Español",
	"pt_BR": "Português (Brasil)",
	"ru": "Русский",
	"pl": "Polski",
	"tr": "Türkçe",
	"it": "Italiano",
	"id": "Bahasa Indonesia",
	"vi": "Tiếng Việt",
	"th": "ไทย",
}

## GameDef 字段 → 翻译键后缀；没列的字段直接用字段名
const FIELD_SUFFIXES := {
	"display_name": "name",
	"description": "desc",
	"catalog_hint": "hint",
	"research_hint": "hint",
	"taste": "taste",
	"title": "title",
	"body": "body",
	"subtitle": "subtitle",
}

## 数据条目的翻译键：`item/americano` + `display_name` → `data.item.americano.name`
## `.tres` 里存的也是这个完整键（P3 起），两边由同一套规则派生。
static func key_for(id: String, field: StringName) -> String:
	var path := id
	var colon := path.find(":")
	if colon >= 0:
		path = path.substr(colon + 1)
	return "data.%s.%s" % [path.replace("/", "."), _suffix_of(field)]

## 取翻译；缺键时框架原样返回键（回退由调用方决定）
static func t(key: String, args: Array = []) -> String:
	return I18NManager.get_text(key, args)

## 复数键：英文靠 `one` / `other` 两条，中文两条写同一句即可
static func plural_key(key: String, count: int) -> String:
	return "%s.%s" % [key, "one" if count == 1 else "other"]

## 复数文案（直接可显示）：`count` 同时作为 `{0}` 传进文本
static func plural(key: String, count: int, args: Array = []) -> String:
	return t(plural_key(key, count), [count] + args)

## 列表连接符：中文「、」，英文「, 」
static func list_sep() -> String:
	return t("ui.common.list_sep")

## 当前语言是否中文：只给「同一数值在两种语言里换单位」这类格式用，
## 文案本身仍应走翻译键。
static func is_zh() -> bool:
	return I18NManager.get_current_language().begins_with("zh")

static func _suffix_of(field: StringName) -> String:
	var field_name := String(field)
	var mapped: Variant = FIELD_SUFFIXES.get(field_name)
	return field_name if mapped == null else String(mapped)
