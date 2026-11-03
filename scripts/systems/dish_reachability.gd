extends RefCounted
## 菜品可达性：从「现在能拿到什么」倒推一道配方能不能真的做出来。
##
## 只读查询，不改 GameState 的任何状态。两种口径：
## - LIVE：按当前存档判（配方可见、设备到手、采集等级、库存、商店价）；
## - FULL：模拟全设备就绪、全采集满级、全配方可见，但仍要求材料有真实来源
##   （商店 / 采集 / 免费 / 可继续倒推的配方），用来做内容树体检。
##
## 判据与订单闸门共用同一份，避免「订单板说能做、灶台做不了」两套真相。

const MAX_DEPTH := 4

var _gs: Node
var _full := false
var _memo: Dictionary = {}


static func explain_recipe(gs: Node, recipe_key: String, full := false) -> Dictionary:
	var engine := new()
	engine._gs = gs
	engine._full = full
	return engine._recipe_report(recipe_key, {}, 1)


func _def(key: String) -> GameDef:
	if _gs == null:
		return null
	return _gs.call("_def", key) as GameDef


## 一条配方为什么能做 / 为什么卡住。返回 {ok, kind, chain}。
## kind：ok / locked / facility / material / depth / cycle / invalid。
func _recipe_report(recipe_key: String, visited: Dictionary, depth: int) -> Dictionary:
	if depth > MAX_DEPTH:
		return _fail("depth", ["recipe:" + recipe_key])
	var mark := "r:" + recipe_key
	if visited.has(mark):
		return _fail("cycle", ["recipe:" + recipe_key])
	if _memo.has(recipe_key):
		return _memo[recipe_key]
	var recipe := _def(recipe_key) as RecipeDef
	if recipe == null:
		return _fail("invalid", ["recipe:" + recipe_key])
	if not _full and not bool(_gs.call("is_recipe_visible", recipe_key)):
		return _fail("locked", ["recipe:" + recipe_key])
	if not _full and not bool(_gs.call("is_facility_ready", recipe.facility)):
		return _fail("facility", ["recipe:" + recipe_key, "facility:" + recipe.facility])
	visited[mark] = true
	var result := _check_inputs(recipe, recipe_key, visited, depth)
	visited.erase(mark)
	# 只缓存成功结果：失败链可能因为 visited 里的环而有路径依赖。
	if bool(result.get("ok", false)):
		_memo[recipe_key] = result
	return result


func _check_inputs(recipe: RecipeDef, recipe_key: String, visited: Dictionary, depth: int) -> Dictionary:
	for stack in recipe.inputs:
		if stack == null:
			continue
		var report: Dictionary
		if not stack.by_tag.is_empty():
			report = _tag_report(stack.by_tag, visited, depth)
		elif not stack.material.is_empty():
			report = _item_report(stack.material, visited, depth)
		else:
			report = _fail("invalid", ["item:?"])
		if not bool(report.get("ok", false)):
			var chain: Array = ["recipe:" + recipe_key]
			chain.append_array(report.get("chain", []))
			var failed := report.duplicate()
			failed["chain"] = chain
			return failed
	return {"ok": true, "kind": "ok", "chain": []}


func _tag_report(tag_key: String, visited: Dictionary, depth: int) -> Dictionary:
	var members: Array = _gs.call("_tag_member_keys", tag_key)
	if members.is_empty():
		return _fail("material", ["tag:" + tag_key])
	var first_failure: Dictionary = {}
	for member in members:
		var report := _item_report(String(member), visited, depth)
		if bool(report.get("ok", false)):
			return report
		var kind := String(report.get("kind", ""))
		if first_failure.is_empty() or (kind != "cycle" and kind != "depth"):
			first_failure = report
	if first_failure.is_empty():
		return _fail("material", ["tag:" + tag_key])
	var chain: Array = ["tag:" + tag_key]
	chain.append_array(first_failure.get("chain", []))
	var failed := first_failure.duplicate()
	failed["chain"] = chain
	return failed


func _item_report(item_key: String, visited: Dictionary, depth: int) -> Dictionary:
	var item := _def(item_key) as ItemDef
	if item == null:
		return _fail("invalid", ["item:" + item_key])
	# FULL 不看库存：否则有货的老档会掩盖内容树里真实缺源的菜。
	if not _full and int(_gs.call("get_amount", item_key)) > 0:
		return _ok()
	if item.is_free():
		return _ok()
	if item.merchant_price > 0:
		return _ok()
	var harvest := _gs.call("get_harvest_for_material", item_key) as HarvestDef
	if harvest != null:
		if _full:
			return _ok()
		if bool(_gs.call("is_harvest_unlocked", harvest)) and item.harvest_tier <= int(_gs.call("get_harvest_level", harvest.get_key())):
			return _ok()
	var producers: Array = _gs.call("recipes_producing", item_key)
	var first_failure: Dictionary = {}
	for producer in producers:
		var producer_key := String(producer)
		if not _full and not bool(_gs.call("is_recipe_visible", producer_key)):
			continue
		var report := _recipe_report(producer_key, visited, depth + 1)
		if bool(report.get("ok", false)):
			return report
		var kind := String(report.get("kind", ""))
		if first_failure.is_empty() or (kind != "cycle" and kind != "depth"):
			first_failure = report
	if not first_failure.is_empty():
		var chain: Array = ["item:" + item_key]
		chain.append_array(first_failure.get("chain", []))
		var failed := first_failure.duplicate()
		failed["chain"] = chain
		return failed
	return _fail("material", ["item:" + item_key])


func _ok() -> Dictionary:
	return {"ok": true, "kind": "ok", "chain": []}


func _fail(kind: String, chain: Array) -> Dictionary:
	return {"ok": false, "kind": kind, "chain": chain}
