extends SceneTree
## 菜品树体检：默认按当前存档打印四态；--full 模拟全设备 / 全采集 / 全研究。
##
## 用法：
##   godot --headless --path . -s scripts/tools/dish_tree_check.gd
##   godot --headless --path . -s scripts/tools/dish_tree_check.gd -- --full
##
## -s 模式编译期拿不到 autoload，所以先等一帧，再从 root 取出 GameState。
## 只读，不写存档、不改任何游戏状态。

const STATES := ["orderable", "facility", "material", "locked", "no_recipe", "not_food"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var gs := root.get_node_or_null("GameState")
	if gs == null:
		printerr("[dish] GameState 未就绪，无法体检")
		quit(2)
		return
	var full := OS.get_cmdline_user_args().has("--full")
	var keys: Array = gs.call("get_all_dish_keys")
	if keys.is_empty():
		printerr("[dish] 没有读到任何菜品定义")
		quit(2)
		return
	var counts := {}
	for state in STATES:
		counts[state] = 0
	var failures: Array = []
	for dish_key in keys:
		var report: Dictionary = gs.call("explain_dish_reachability", dish_key, full)
		var state := String(report.get("state", "not_food"))
		counts[state] = int(counts.get(state, 0)) + 1
		if not bool(report.get("orderable", false)):
			failures.append(report)
	print("[dish] %s，共 %d 道" % ["菜品树体检（FULL：全设备 / 全采集 / 全研究）" if full else "菜品树体检（当前存档）", keys.size()])
	print("[dish] 可下单 %d | 缺设备 %d | 缺材料 %d | 配方未解锁 %d | 无配方 %d | 非食物 %d" % [
		counts["orderable"], counts["facility"], counts["material"], counts["locked"],
		counts["no_recipe"], counts["not_food"],
	])
	_print_examples(failures, "facility", "缺设备", 6)
	_print_examples(failures, "material", "缺材料", 12)
	_print_examples(failures, "locked", "配方未解锁", 6)
	if not full:
		quit(0)
		return
	if failures.is_empty():
		print("[dish] FULL 口径：全部菜品可达，退出码 0")
		quit(0)
		return
	print("[dish] FULL 口径缺口 %d 道：" % failures.size())
	var cycles := 0
	for report in failures:
		var chain: Array = report.get("chain", [])
		var kind := String(report.get("kind", ""))
		if kind == "cycle" or kind == "depth":
			cycles += 1
		print("  - %s（%s）state=%s recipe=%s kind=%s chain=%s" % [
			report.get("name", ""), report.get("dish", ""), report.get("state", ""),
			report.get("recipe", ""), kind, " -> ".join(chain),
		])
	if cycles > 0:
		print("[dish] 其中疑似研发死锁 / 深度超限 %d 道（见 kind=cycle/depth）" % cycles)
	print("[dish] FULL 口径有缺口，退出码 1")
	quit(1)


func _print_examples(failures: Array, wanted: String, label: String, limit: int) -> void:
	var shown := 0
	for report in failures:
		if String(report.get("state", "")) != wanted:
			continue
		if shown >= limit:
			break
		var chain: Array = report.get("chain", [])
		print("[dish] %s：%s（%s）chain=%s" % [label, report.get("name", ""), report.get("dish", ""), " -> ".join(chain)])
		shown += 1
