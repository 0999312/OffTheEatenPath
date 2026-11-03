extends SceneTree
## 内容自检的数据导出（P10.13 三表）。
##
## 用 ResourceLoader 读 .tres，而不是正则拆文本——字段类型由资源类给出，
## 改动字段名时这里会跟着编译期报错。产物给 docs/plans/2026-10-28-content-audit/
## 下的 Node 脚本做硬检查并渲染 Markdown；人工只审软检查清单。
##
## 用法：godot --headless --path . -s scripts/tools/audit_dump.gd

const ROOT := "res://resources/game_data"
const OUT := "res://docs/plans/2026-10-28-content-audit/_dump.json"


func _init() -> void:
	var data := {
		"items": _items(),
		"recipes": _recipes(),
		"facilities": _facilities(),
		"themes": _themes(),
		"harvest": _harvest(),
		"letters": _letters(),
		"research": _research(),
	}
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	if file == null:
		printerr("打不开输出文件：%s" % error_string(FileAccess.get_open_error()))
		quit(1)
		return
	file.store_string(JSON.stringify(data, "  ", true, true))
	file.close()
	print("audit dump: %d items, %d recipes, %d facilities, %d themes, %d harvest, %d letters" % [
		data.items.size(), data.recipes.size(), data.facilities.size(),
		data.themes.size(), data.harvest.size(), data.letters.size(),
	])
	quit(0)


func _load_dir(sub: String) -> Array:
	var out: Array = []
	var dir := ROOT.path_join(sub)
	var names := DirAccess.get_files_at(dir)
	names.sort()
	for name in names:
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


func _items() -> Array:
	var out: Array = []
	for def in _load_dir("items"):
		out.append({
			"key": _key(def),
			"id": def.id,
			"display_name": def.display_name,
			"kind": def.kind,
			"material_kind": def.material_kind,
			"merchant_price": def.merchant_price,
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


func _recipes() -> Array:
	var out: Array = []
	for def in _load_dir("recipes"):
		out.append({
			"key": _key(def),
			"id": def.id,
			"display_name": def.display_name,
			"output": def.output,
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


func _facilities() -> Array:
	var out: Array = []
	for def in _load_dir("facilities"):
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
			"max_level": def.max_level,
			"category": def.category,
			"unlock_letter": def.unlock_letter,
			"upgrades": upgrades,
			"level_speed_factors": def.level_speed_factors,
		})
	return out


func _themes() -> Array:
	var out: Array = []
	for def in _load_dir("themes"):
		out.append({
			"key": _key(def),
			"id": def.id,
			"display_name": def.display_name,
			"order": def.order,
			"unlock_letter": def.unlock_letter,
		})
	return out


func _harvest() -> Array:
	var out: Array = []
	for def in _load_dir("harvest"):
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


func _letters() -> Array:
	var out: Array = []
	for def in _load_dir("letters"):
		out.append({
			"key": _key(def),
			"id": def.id,
			"title": def.title,
			"order": def.order,
			"condition": def.condition,
			"condition_ref": def.condition_ref,
			"condition_value": def.condition_value,
			"rewards": _stacks(def.rewards),
			"reward_coins": def.reward_coins,
			"unlocks_offline": def.unlocks_offline,
			"task_title": def.task_title,
			"task_goal": def.task_goal,
			"task_ref": def.task_ref,
			"task_amount": def.task_amount,
			"task_reward_coins": def.task_reward_coins,
			"task_rewards": _stacks(def.task_rewards),
		})
	return out


func _research() -> Array:
	var out: Array = []
	for def in _load_dir("research"):
		out.append({
			"key": _key(def),
			"id": def.id,
			"facility": def.facility,
			"burn_counts": def.burn_counts,
			"charge_chance": def.charge_chance,
			"burn_rates": def.burn_rates,
			"default_seconds": def.default_seconds,
		})
	return out
