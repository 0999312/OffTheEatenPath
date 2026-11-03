extends GutTest
## 版本号单一真源校验（规则见 docs/DEVELOPMENT.md §6.1）。
## version.txt 记录「语义版本-构建号」，project.godot 与 export_presets.cfg 只写语义版本。

const VERSION_PATH := "res://version.txt"
const VERSION_PATTERN := "^\\d+\\.\\d+\\.\\d+-\\d{4,}$"
const CHECKED_KEYS := ["file_version", "product_version"]


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "读不到 %s" % path)
	if file == null:
		return ""
	return file.get_as_text()


func _semver_of(version: String) -> String:
	return version.split("-", false)[0]


func test_version_txt_follows_semver_build_pattern() -> void:
	var raw := _read_text(VERSION_PATH).strip_edges()
	var pattern := RegEx.create_from_string(VERSION_PATTERN)
	assert_not_null(pattern.search(raw), "version.txt 应为 <主>.<次>.<补丁>-<4 位以上构建号>，当前：%s" % raw)


func test_project_version_matches_version_txt() -> void:
	var semver := _semver_of(_read_text(VERSION_PATH).strip_edges())
	var project_version := str(ProjectSettings.get_setting("application/config/version", ""))
	assert_eq(project_version, semver, "project.godot 的 config/version 与 version.txt 的语义版本不一致")


func test_export_presets_versions_match_version_txt() -> void:
	var semver := _semver_of(_read_text(VERSION_PATH).strip_edges())
	var presets := _read_text("res://export_presets.cfg")
	var found := 0
	for line in presets.split("\n"):
		var stripped := line.strip_edges()
		for key in CHECKED_KEYS:
			var prefix := "application/%s=\"" % key
			if not stripped.begins_with(prefix):
				continue
			found += 1
			var value := stripped.trim_prefix(prefix).trim_suffix("\"")
			assert_eq(value, semver, "export_presets.cfg 的 application/%s 与 version.txt 的语义版本不一致" % key)
	assert_gt(found, 0, "export_presets.cfg 里找不到 application/file_version 或 product_version")
