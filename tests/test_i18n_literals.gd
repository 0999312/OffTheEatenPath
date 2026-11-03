extends GutTest
## 界面字面量键的常驻检查（第三轮反馈 13：商人筛选空态把 ui.filter.empty 原样显示）。
##
## 人工队读不完 13 个面板的每一句，这条测试替人读：扫 scripts/ 下所有
## I18n.t("ui.*") / I18n.plural("ui.*") 的字面量，任何一个键不在
## zh_CN / en 表里就失败。数据键由 test_i18n_coverage 负责。

const I18N_DIR := "res://resources/i18n"
const SCRIPT_ROOT := "res://scripts"

var _zh := {}
var _en := {}


func before_all() -> void:
	_zh = _flatten(_read_json(I18N_DIR.path_join("zh_CN.json")))
	_en = _flatten(_read_json(I18N_DIR.path_join("en.json")))
	assert_false(_zh.is_empty(), "中文表应能解析")
	assert_false(_en.is_empty(), "英文表应能解析")


func test_literal_ui_keys_exist_in_both_locales() -> void:
	var missing: Array[String] = []
	for path in _gd_files(SCRIPT_ROOT):
		var source := FileAccess.get_file_as_string(path)
		for call in _calls(source, "I18n.t("):
			for key in _keys_in(call):
				if not _zh.has(key):
					missing.append("%s → zh_CN 缺 %s" % [path, key])
				if not _en.has(key):
					missing.append("%s → en 缺 %s" % [path, key])
		for base in _plural_bases(source):
			for suffix in ["one", "other"]:
				var full := "%s.%s" % [base, suffix]
				if not _zh.has(full):
					missing.append("%s → zh_CN 缺 %s" % [path, full])
				if not _en.has(full):
					missing.append("%s → en 缺 %s" % [path, full])
	missing.sort()
	assert_eq(missing, [], "这些字面量键没有翻译：\n%s" % "\n".join(missing))


## 反馈 13 的直接回归：商人筛选没结果时会显示这一条
func test_filter_empty_key_is_present() -> void:
	assert_true(_zh.has("ui.filter.empty"), "zh_CN 应有 ui.filter.empty")
	assert_true(_en.has("ui.filter.empty"), "en 应有 ui.filter.empty")


## 从 needle 处开始做括号配对，返回每次调用的参数字符串（跳过字符串里的括号）
func _calls(source: String, needle: String) -> Array[String]:
	var calls: Array[String] = []
	var from := 0
	while true:
		var start := source.find(needle, from)
		if start < 0:
			break
		var open := start + needle.length() - 1
		var depth := 1
		var index := open + 1
		var in_string := false
		while index < source.length() and depth > 0:
			var ch := source[index]
			if in_string:
				if ch == "\\":
					index += 1
				elif ch == "\"":
					in_string = false
			elif ch == "\"":
				in_string = true
			elif ch == "(":
				depth += 1
			elif ch == ")":
				depth -= 1
			index += 1
		calls.append(source.substr(open + 1, index - open - 2))
		from = index
	return calls


func _keys_in(call: String) -> Array[String]:
	var keys: Array[String] = []
	var regex := RegEx.create_from_string("\"((?:ui|data)\\.[a-z0-9_.]+)\"")
	for found in regex.search_all(call):
		var key := found.get_string(1)
		if not keys.has(key):
			keys.append(key)
	return keys


func _plural_bases(source: String) -> Array[String]:
	var bases: Array[String] = []
	var regex := RegEx.create_from_string("\"((?:ui|data)\\.[a-z0-9_.]+)\"")
	for call in _calls(source, "I18n.plural("):
		var found := regex.search(call)
		if found != null and not bases.has(found.get_string(1)):
			bases.append(found.get_string(1))
	return bases


func _read_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _flatten(data: Dictionary) -> Dictionary:
	var out := {}
	_flatten_into(data, "", out)
	return out


func _flatten_into(data: Dictionary, prefix: String, out: Dictionary) -> void:
	for key in data:
		var value = data[key]
		var path := String(key) if prefix.is_empty() else prefix + "." + String(key)
		if value is Dictionary:
			_flatten_into(value, path, out)
		else:
			out[path] = value


func _gd_files(dir: String, out: Array[String] = []) -> Array[String]:
	for name in DirAccess.get_files_at(dir):
		if name.ends_with(".gd"):
			out.append(dir.path_join(name))
	for sub in DirAccess.get_directories_at(dir):
		_gd_files(dir.path_join(sub), out)
	return out
