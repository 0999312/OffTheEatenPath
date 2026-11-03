extends SceneTree
## 研究池同步：把每个配方的 research_pool 对齐到「去重后的具名 inputs」。
##
## 默认 dry-run，只写 tests/tmp/research_pool_diff.md；--apply 才写回 .tres；
## --check 在有差异时退出 1（供将来的门禁使用）。
## 用法：
##   godot --headless --path . -s scripts/tools/sync_research_pools.gd
##   godot --headless --path . -s scripts/tools/sync_research_pools.gd -- --apply
##   godot --headless --path . -s scripts/tools/sync_research_pools.gd -- --check
##
## 规则（第 8 轮拍板 Q4，R8.1 按数据校验修订）：
## - research_pool = 具名 inputs 去重 + 每个 by_tag 输入的首个标签成员（按 item key 排序）；
## - 研究台 evaluate_research 支持 by_tag（标签下任意一种材料），与合成一致；
## - 只处理 research_pool 非空的配方；空池配方不研究，不碰。

const RECIPES_DIR := "res://resources/game_data/recipes"
const ITEMS_DIR := "res://resources/game_data/items"
const REPORT_PATH := "res://tests/tmp/research_pool_diff.md"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var apply := args.has("--apply")
	var check := args.has("--check")
	var tag_members := _collect_tag_members()
	var files := DirAccess.get_files_at(RECIPES_DIR)
	files.sort()
	var rows: Array[String] = []
	var total := 0
	var researched := 0
	var changed := 0
	var tags_touched := 0
	for file in files:
		if not String(file).ends_with(".tres"):
			continue
		total += 1
		var path := RECIPES_DIR.path_join(String(file))
		var recipe: Resource = load(path)
		if recipe == null:
			printerr("[pool] 读不出配方：%s" % path)
			quit(2)
			return
		if recipe.research_pool.is_empty():
			continue
		researched += 1
		var current: Array[String] = []
		current.assign(recipe.research_pool)
		var suggested := _suggest_pool(recipe, tag_members)
		var tags: Array[String] = []
		for stack in recipe.inputs:
			if stack != null and not stack.by_tag.is_empty():
				tags.append(stack.by_tag)
		if not tags.is_empty():
			tags_touched += 1
		if _same_set(current, suggested):
			continue
		changed += 1
		var named := _unique(recipe.input_keys())
		rows.append("- `%s`（`%s`）" % [recipe.get_key(), file])
		rows.append("  - 具名输入：%s" % _fmt(named))
		if not tags.is_empty():
			rows.append("  - 标签输入：%s（池内补：%s）" % [_fmt(tags), _fmt(_diff(suggested, named))])
		rows.append("  - 当前池：%s" % _fmt(current))
		rows.append("  - 建议池：%s" % _fmt(suggested))
		var missing := _diff(suggested, current)
		var extra := _diff(current, suggested)
		if not missing.is_empty():
			rows.append("  - 缺少：%s" % _fmt(missing))
		if not extra.is_empty():
			rows.append("  - 多余：%s" % _fmt(extra))
		if apply:
			var err := _write_pool(path, suggested)
			if err != OK:
				printerr("[pool] 写回失败（%d）：%s" % [err, path])
				quit(2)
				return
	var mode := "APPLY" if apply else ("CHECK" if check else "DRY-RUN")
	var header: Array[String] = [
		"# 研究池对齐报告（%s）" % mode,
		"",
		"- 生成：2026-10-31，脚本 `scripts/tools/sync_research_pools.gd`",
		"- 配方总数：%d；有研究池：%d；需改：%d；涉及 by_tag 输入：%d" % [total, researched, changed, tags_touched],
		"",
		"规则：research_pool = 去重后的具名 inputs + 每个 by_tag 的首个成员（按 item key 排序）。",
		"",
	]
	var text := "\n".join(header + rows) + "\n"
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f == null:
		printerr("[pool] 写不了报告：%s（错误 %d）" % [REPORT_PATH, FileAccess.get_open_error()])
		quit(2)
		return
	f.store_string(text)
	f.close()
	print("[pool] %s：配方 %d，有池 %d，需改 %d，by_tag %d；报告 %s" % [mode, total, researched, changed, tags_touched, REPORT_PATH])
	if check and changed > 0:
		print("[pool] 有差异，退出码 1")
		quit(1)
		return
	quit(0)


## 扫一遍物品资源，建「标签 → 成员键（排序）」索引；与 DataRegistry.tag_member_keys 同序。
func _collect_tag_members() -> Dictionary:
	var members := {}
	for file in DirAccess.get_files_at(ITEMS_DIR):
		if not String(file).ends_with(".tres"):
			continue
		var item: Resource = load(ITEMS_DIR.path_join(String(file)))
		if item == null:
			continue
		for tag in item.tags:
			if not members.has(tag):
				members[tag] = []
			members[tag].append(item.get_key())
	for tag in members:
		members[tag].sort()
	return members


## 建议池：具名输入按 inputs 顺序去重；by_tag 输入补该标签的首个成员。
func _suggest_pool(recipe: Resource, tag_members: Dictionary) -> Array[String]:
	var suggested: Array[String] = []
	for stack in recipe.inputs:
		if stack == null:
			continue
		if not stack.material.is_empty():
			if not suggested.has(stack.material):
				suggested.append(stack.material)
			continue
		if stack.by_tag.is_empty():
			continue
		var list: Array = tag_members.get(stack.by_tag, [])
		for candidate in list:
			var member := String(candidate)
			if not suggested.has(member):
				suggested.append(member)
				break
	return suggested


func _unique(values: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		if not out.has(value):
			out.append(value)
	return out


func _same_set(a: Array[String], b: Array[String]) -> bool:
	if a.size() != b.size():
		return false
	for value in a:
		if not b.has(value):
			return false
	return true


func _diff(a: Array[String], b: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for value in a:
		if not b.has(value):
			out.append(value)
	return out


func _fmt(values: Array[String]) -> String:
	if values.is_empty():
		return "（空）"
	return "、".join(values)

## 只替换 [resource] 段里的 research_pool 一行，保留原文件的字段顺序与格式；
## 没有这一行时插到 id 之前（souffle 这类原本不研究的配方）。
func _write_pool(path: String, pool: Array[String]) -> Error:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return ERR_FILE_CANT_READ
	var lines := text.split("
")
	var new_line := "research_pool = Array[String]([%s])" % _quoted(pool)
	var replaced := false
	for i in lines.size():
		if lines[i].begins_with("research_pool = "):
			lines[i] = new_line
			replaced = true
			break
	if not replaced:
		var insert_at := -1
		for i in lines.size():
			if lines[i].begins_with("id = "):
				insert_at = i
				break
		if insert_at < 0:
			return ERR_FILE_CORRUPT
		lines.insert(insert_at, new_line)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string("\n".join(lines))
	f.close()
	return OK


func _quoted(pool: Array[String]) -> String:
	var parts: Array[String] = []
	for value in pool:
		parts.append("\"%s\"" % value)
	return ", ".join(parts)

