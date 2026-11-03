extends GutTest
## P3 数据文案验收：`.tres` 里存的是翻译键，取出来必须是当前语言的人话。
##
## 两条底线：
## 1. 切到英文后，任何静态文案字段都不该残留中文（否则玩家会看到半中半英）；
## 2. 切到中文后，取出的文本不该是 `data.*` 键名（否则说明键没进 JSON）。

const REGISTRY_KEY := DataRegistry.REGISTRY_NAME
## 常见汉字的码点范围；只用来找漏译，不参与分词
const CJK_PATTERN := "[\\x{4e00}-\\x{9fff}]"

var _data: DataRegistry
var _original_locale: String


func before_each() -> void:
	var registry_manager := get_node_or_null("/root/RegistryManager")
	if registry_manager != null and registry_manager.has_registry(REGISTRY_KEY):
		_data = registry_manager.get_registry(REGISTRY_KEY) as DataRegistry
	_original_locale = I18NManager.get_current_language()


func after_each() -> void:
	I18NManager.set_language(_original_locale)


func test_english_texts_have_no_chinese() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	I18NManager.set_language("en")
	var cjk := RegEx.create_from_string(CJK_PATTERN)
	var problems: Array[String] = []
	for def in _data.get_all_defs():
		for field in _fields_of(def):
			var text := def.localized(field)
			if cjk.search(text) != null:
				problems.append("%s.%s → %s" % [def.get_key(), field, text])
	assert_eq(problems.size(), 0, "英文界面下仍有中文：\n%s" % "\n".join(problems))


func test_chinese_texts_resolve_to_human_text() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	I18NManager.set_language("zh_CN")
	var problems: Array[String] = []
	for def in _data.get_all_defs():
		var name_text := def.localized()
		if name_text.is_empty():
			problems.append("%s → 空的显示名" % def.get_key())
		elif name_text.begins_with("data."):
			problems.append("%s → 未解析的键 %s" % [def.get_key(), name_text])
	assert_eq(problems.size(), 0, "中文下取不到人话：\n%s" % "\n".join(problems))


func test_translated_fields_covered_in_both_locales() -> void:
	if _data == null:
		fail_test("DataRegistry 未就绪")
		return
	I18NManager.set_language("en")
	var covered := {}
	for def in _data.get_all_defs():
		for field in _fields_of(def):
			if not def.localized(field).is_empty():
				covered["%s|%s" % [def.get_key(), field]] = true
	I18NManager.set_language("zh_CN")
	var missing: Array[String] = []
	for item in covered:
		var parts := String(item).split("|")
		var def := _data.get_def(parts[0])
		if def == null or def.localized(StringName(parts[1])).is_empty():
			missing.append(String(item))
	assert_eq(missing.size(), 0, "这些字段英文有、中文没有：\n%s" % "\n".join(missing))


## 一个定义上所有「玩家看得见」的字段
func _fields_of(def: GameDef) -> Array[StringName]:
	var fields: Array[StringName] = [&"display_name", &"description"]
	if def is ItemDef and (def as ItemDef).is_food():
		fields.append(&"taste")
		fields.append(&"catalog_hint")
	elif def is RecipeDef:
		fields.append(&"research_hint")
	elif def is LetterDef:
		fields.append(&"title")
		fields.append(&"body")
	elif def is WorldDef:
		fields.append(&"subtitle")
		fields.append(&"body")
		fields.append(&"catalog_hint")
	return fields
