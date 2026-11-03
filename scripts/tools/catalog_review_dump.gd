extends Node
## 第十一轮试玩反馈：图鉴全量核验的数据导出。
##
## 与 scripts/tools/audit_dump.gd 分开，是为了让这一轮审计可以单独重跑，不覆盖
## 2026-10-28 那份历史产物。产物交给同一目录下的 Node 脚本生成 review.csv。
##
## 用法：godot --headless --path . res://scenes/tools/catalog_review_dump.tscn
## 必须跑场景而不是 -s：后者在建 autoload 之前编译脚本，GameDef 依赖的
## I18NManager 会“Identifier not found”。

const ROOT := "res://resources/game_data"
const OUT := "res://docs/plans/2026-11-01-catalog-review/_dump.json"

## 子目录 → 该目录下的定义（顺序与 DataRegistry.dir_types() 一致）
const DIRS := ["items", "recipes", "facilities", "letters", "world", "research", "harvest", "themes", "tags", "merchant"]


func _ready() -> void:
	var by_dir := {}
	var registry := DataRegistry.new()
	var total := 0
	for sub in DIRS:
		var defs := _load_dir(sub)
		by_dir[sub] = defs
		total += defs.size()
		for def in defs:
			registry.register_def(def)
	var catalog_keys := registry.get_catalog_keys()
	var data := {
		"catalog_keys": catalog_keys,
		"catalog_entries": _catalog_entries(registry, catalog_keys),
		"items": _items(by_dir.get("items", [])),
		"recipes": _recipes(by_dir.get("recipes", [])),
		"facilities": _facilities(by_dir.get("facilities", [])),
		"themes": _themes(by_dir.get("themes", [])),
		"world": _world(by_dir.get("world", [])),
		"letters": _letters(by_dir.get("letters", [])),
		"harvest": _harvest(by_dir.get("harvest", [])),
		"tags": _tags(by_dir.get("tags", [])),
		"research": _research(by_dir.get("research", [])),
		"merchant": _merchant(by_dir.get("merchant", [])),
	}
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	if file == null:
		printerr("打不开输出文件：%s" % error_string(FileAccess.get_open_error()))
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(data, "  ", true, true))
	file.close()
	print("catalog review dump: %d defs, %d catalog entries, %d items, %d recipes" % [
		total, catalog_keys.size(), data.items.size(), data.recipes.size(),
	])
	get_tree().quit(0)


func _load_dir(sub: String) -> Array:
	var out: Array = []
	var dir := ROOT.path_join(sub)
	for name in DirAccess.get_files_at(dir):
		if not name.ends_with(".tres"):
			continue
		var res := ResourceLoader.load(dir.path_join(name))
		if res == null:
			push_error("加载失败：%s" % dir.path_join(name))
			continue
		out.append(res)
	return out


func _stack(stack: MaterialStack) -> Dictionary:
	return {"material": stack.material, "amount": stack.amount, "by_tag": stack.by_tag}


func _stacks(stacks: Array) -> Array:
	var out: Array = []
	for stack in stacks:
		out.append(_stack(stack))
	return out


func _key(def: GameDef) -> String:
	return def.get_key()


func _catalog_entries(registry: DataRegistry, keys: Array[String]) -> Array:
	var out: Array = []
	for key in keys:
		var def := registry.get_def(key)
		out.append({"key": key, "type": def.get_type_id() if def != null else ""})
	return out


func _items(defs: Array) -> Array:
	var out: Array = []
	for def in defs:
		out.append({
			"key": _key(def),
			"id": def.id,
			"display_name": def.display_name,
			"description": def.description,
			"kind": def.kind,
			"material_kind": def.material_kind,
			"merchant_price": def.merchant_price,
			"merchant_level": def.merchant_level,
			"sell_price": def.sell_price,
			"in_catalog": def.in_catalog,
			"theme": def.theme,
			"tags": def.tags,
			"harvest_tier": def.harvest_tier,
			"order": def.order,
			"taste": def.taste,
			"catalog_hint": def.catalog_hint,
			"order_weight": def.order_weight,
		})
	return out


func _recipes(defs: Array) -> Array:
	var out: Array = []
	for def in defs:
		out.append({
			"key": _key(def),
			"id": def.id,
			"display_name": def.display_name,
			"description": def.description,
			"output": def.output,
			"output_amount": def.output_amount,
			"extra_outputs": _stacks(def.extra_outputs),
			"inputs": _stacks(def.inputs),
			"duration_seconds": def.duration_seconds,
			"facility": def.facility,
			"in_catalog": def.in_catalog,
			"order": def.order,
			"research_pool": def.research_pool,
			"research_hint": def.research_hint,
			"research_min_facility_level": def.research_min_facility_level,
			"group": def.group,
		})
	return out


func _facilities(defs: Array) -> Array:
	var out: Array = []
	for def in defs:
		var upgrades: Array = []
		for upgrade in def.upgrades:
			upgrades.append({
				"target_level": upgrade.target_level,
				"coin_cost": upgrade.coin_cost,
				"materials": _stacks(upgrade.materials),
			})
		out.append({
			"key": _key(def),
			"id": def.id,
			"display_name": def.display_name,
			"description": def.description,
			"max_level": def.max_level,
			"category": def.category,
			"unlock_letter": def.unlock_letter,
			"upgrades": upgrades,
			"level_speed_factors": def.level_speed_factors,
		})
	return out


func _themes(defs: Array) -> Array:
	var out: Array = []
	for def in defs:
		out.append({
			"key": _key(def),
			"id": def.id,
			"display_name": def.display_name,
			"description": def.description,
			"order": def.order,
			"unlock_letter": def.unlock_letter,
		})
	return out


func _world(defs: Array) -> Array:
	var out: Array = []
	for def in defs:
		out.append({
			"key": _key(def),
			"id": def.id,
			"display_name": def.display_name,
			"description": def.description,
			"subtitle": def.subtitle,
			"body": def.body,
			"order": def.order,
			"catalog_hint": def.catalog_hint,
			"unlock_letter": def.unlock_letter,
		})
	return out


func _harvest(defs: Array) -> Array:
	var out: Array = []
	for def in defs:
		out.append({
			"key": _key(def),
			"id": def.id,
			"display_name": def.display_name,
			"tag": def.tag,
			"cooldown_seconds": def.cooldown_seconds,
			"yield_per_click": def.yield_per_click,
			"trickle_per_second": def.trickle_per_second,
			"upgrade_coin_costs": def.upgrade_coin_costs,
			"upgrade_item_amounts": def.upgrade_item_amounts,
			"unlock_facility": def.unlock_facility,
			"unlock_level": def.unlock_level,
			"unlock_letter": def.unlock_letter,
			"order": def.order,
		})
	return out


func _letters(defs: Array) -> Array:
	var out: Array = []
	for def in defs:
		out.append({
			"key": _key(def),
			"id": def.id,
			"display_name": def.display_name,
			"description": def.description,
			"title": def.title,
			"body": def.body,
			"order": def.order,
			"condition": def.condition,
			"condition_ref": def.condition_ref,
			"condition_value": def.condition_value,
			"catalog_min": def.catalog_min,
			"rewards": _stacks(def.rewards),
			"reward_coins": def.reward_coins,
			"unlocks_offline": def.unlocks_offline,
			"task_title": def.task_title,
			"task_body": def.task_body,
			"task_goal": def.task_goal,
			"task_ref": def.task_ref,
			"task_amount": def.task_amount,
			"task_reward_coins": def.task_reward_coins,
			"task_rewards": _stacks(def.task_rewards),
		})
	return out


func _tags(defs: Array) -> Array:
	var out: Array = []
	for def in defs:
		out.append({
			"key": _key(def),
			"id": def.id,
			"display_name": def.display_name,
			"description": def.description,
			"order": def.order,
			"scope": def.scope,
			"ingredient": def.is_ingredient(),
		})
	return out


func _research(defs: Array) -> Array:
	var out: Array = []
	for def in defs:
		out.append({
			"key": _key(def),
			"id": def.id,
			"display_name": def.display_name,
			"description": def.description,
			"facility": def.facility,
			"burn_counts": def.burn_counts,
			"charge_chance": def.charge_chance,
			"burn_rates": def.burn_rates,
			"default_seconds": def.default_seconds,
		})
	return out


func _merchant(defs: Array) -> Array:
	var out: Array = []
	for def in defs:
		out.append({
			"key": _key(def),
			"id": def.id,
			"display_name": def.display_name,
			"description": def.description,
			"max_level": def.max_level,
			"capacity_normal": def.capacity_normal,
			"capacity_scarce": def.capacity_scarce,
			"refill_seconds": def.refill_seconds,
		})
	return out
