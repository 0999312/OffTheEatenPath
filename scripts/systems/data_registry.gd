class_name DataRegistry
extends RegistryBase
## 静态内容注册表：启动时扫描 `resources/game_data/` 下的 `.tres`，逐条校验后登记。
##
## 为什么继承框架的 RegistryBase：框架 RegistryManager 已经负责「注册表们的注册表」，
## 数据表只是其中一张；自建容器会绕开 RegistryManager，导致两种查找入口并存。
##
## 键是完整键 `namespace:id`（如 `game:item/coffee_bean`），与 ResourceLocation.to_string() 一致。
## 校验失败集中在 `load_all()` 的返回值里，由 GameBootstrap 汇总报错，启动自检据此判定失败。

const REGISTRY_NAME := "data"
const GAME_NAMESPACE := GameDef.DEFAULT_NAMESPACE
const DATA_ROOT := "res://resources/game_data"
## 框架标签注册表在 RegistryManager 里的键名
const TAG_REGISTRY_KEY := "tag"
## 标签条目落在哪张注册表：材料与食物合并成单表之后，两类标签都指向物品表
const TAG_ENTRY_REGISTRY := "registry:item"

## 目录名 → 该目录下应有的定义类型
## （写成函数而非 const：const 字典里放 class 引用不是常量表达式，GDScript 会解析失败）
static func dir_types() -> Dictionary:
	return {
		"items": ItemDef,
		"recipes": RecipeDef,
		"facilities": FacilityDef,
		"letters": LetterDef,
		"world": WorldDef,
		"research": ResearchDef,
		"harvest": HarvestDef,
		"themes": ThemeDef,
		"tags": TagDef,
		"merchant": MerchantDef,
	}

func _validate_entry(entry: Variant) -> bool:
	return entry is GameDef

func _get_expected_type_name() -> String:
	return "GameDef"

# ─── 登记 / 查找 ───

## 类型索引：type_id → Array[GameDef]。
## 面板每开一次都要「按类型取定义」，原来每次都遍历全部条目（O(全部)）；
## 配方/材料长起来之后这是实打实的开销，登记时就分好桶，查找变成 O(该类型数量)。
var _by_type: Dictionary = {}


## 按定义自己的 namespace/id 登记；键重复或类型不对时返回 false
func register_def(def: GameDef) -> bool:
	if def == null or not def.is_key_valid():
		push_error("[DataRegistry] 定义键非法：%s（namespace=%s id=%s）" % [def.get_key() if def != null else "<null>", def.namespace_id if def != null else "", def.id if def != null else ""])
		return false
	return register(def.get_resource_location(), def)


## 覆写基类：登记成功就顺手放进类型桶，查找时不必再全表扫
func register(id: ResourceLocation, entry: Variant) -> bool:
	if not super.register(id, entry):
		return false
	var def := entry as GameDef
	if def != null:
		var type_id := def.get_type_id()
		if not _by_type.has(type_id):
			_by_type[type_id] = []
		var bucket: Array = _by_type[type_id]
		bucket.append(def)
	return true


## 覆写基类：注销时同步从类型桶里摘掉，避免索引里留下已删的定义
func unregister(id: ResourceLocation) -> bool:
	var def := get_entry(id) as GameDef
	if not super.unregister(id):
		return false
	if def != null:
		var bucket: Array = _by_type.get(def.get_type_id(), [])
		bucket.erase(def)
	return true


## 覆写基类：清空时索引一起清
func clear() -> void:
	_by_type.clear()
	super.clear()


## 用完整键取定义（`game:item/coffee_bean`），取不到返回 null
func get_def(key: String) -> GameDef:
	var location := ResourceLocation.from_string(key)
	if location == null:
		return null
	return get_entry(location) as GameDef

## 是否存在该键
func has_def(key: String) -> bool:
	var location := ResourceLocation.from_string(key)
	if location == null:
		return false
	return has_entry(location)

## 全部定义
func get_all_defs() -> Array[GameDef]:
	var result: Array[GameDef] = []
	for entry in get_all_entries().values():
		if entry is GameDef:
			result.append(entry)
	return result

## 某一类的全部定义（查类型桶，不遍历全部条目）
func get_defs_of_type(type_id: String) -> Array[GameDef]:
	var result: Array[GameDef] = []
	for def in _by_type.get(type_id, []):
		result.append(def)
	return result

## 图鉴收录范围：物品（in_catalog，材料与食物同表，图鉴按 kind 分两页）/ 配方（in_catalog）
## / 设备 / 信件 / 世界。水这类免费资源不进图鉴（in_catalog = false），配方若标了
## in_catalog = false 也不进；ResearchDef 是规则而不是条目，同样不进图鉴。
func get_catalog_keys() -> Array[String]:
	var keys: Array[String] = []
	for def in get_all_defs():
		if def is ItemDef and not (def as ItemDef).in_catalog:
			continue
		if def is RecipeDef and not (def as RecipeDef).in_catalog:
			continue
		# 采集点是材料的一个出口，不是独立条目：名字与说明都复用材料
		if def is HarvestDef or def is ResearchDef or def is MerchantDef:
			continue
		# 主题与标签都是筛选维度，不是作品条目
		if def is ThemeDef or def is TagDef:
			continue
		# 研究台是工具不是作品：它有自己的面板，不进「工艺·设备」页
		if def is FacilityDef and (def as FacilityDef).category == "research":
			continue
		keys.append(def.get_key())
	keys.sort()
	return keys

## 研究台规则（只应有一份；没有则返回 null）
func get_research_rules() -> ResearchDef:
	for def in get_defs_of_type("research"):
		return def as ResearchDef
	return null

# ─── 标签 ───

## 框架标签注册表（GameBootstrap 登记；没登记时返回 null）
static func tag_registry() -> TagRegistry:
	return RegistryManager.get_registry(TAG_REGISTRY_KEY) as TagRegistry


## 把 `TagDef` 与各定义的 `tags` 字段灌进框架 TagRegistry。
## 这是标签成员的**唯一灌入点**：`ItemDef.tags` 是数据，TagRegistry 是它的索引，
## 别处只读不写——两处都写就会对不上。启动时在校验之前跑一次，配方里的
## `by_tag` 校验要看标签底下到底有没有东西。
func rebuild_tags() -> Array[String]:
	var issues: Array[String] = []
	var registry := tag_registry()
	if registry == null:
		issues.append("标签注册表未登记（RegistryManager 里没有 %s）" % TAG_REGISTRY_KEY)
		return issues
	registry.clear()
	var entry_type := ResourceLocation.from_string(TAG_ENTRY_REGISTRY)
	for def in get_defs_of_type("tag"):
		var tag_def := def as TagDef
		if tag_def == null:
			continue
		var tag_id := ResourceLocation.from_string(tag_def.get_key())
		if tag_id == null:
			issues.append("%s：标签键非法，无法登记" % tag_def.get_key())
			continue
		registry.register_tag(tag_id, entry_type)
	for def in get_defs_of_type("item"):
		var item := def as ItemDef
		if item == null:
			continue
		var item_id := ResourceLocation.from_string(item.get_key())
		if item_id == null:
			issues.append("%s：物品键非法，无法挂标签" % item.get_key())
			continue
		for tag_key in item.tags:
			var tag_id := ResourceLocation.from_string(tag_key)
			if tag_id == null:
				issues.append("%s：tags 里的 %s 不是合法标签键" % [item.get_key(), tag_key])
				continue
			if not registry.has_entry(tag_id):
				issues.append("%s：tags 里的 %s 没有登记成标签" % [item.get_key(), tag_key])
				continue
			registry.add_to_tag(tag_id, item_id)
	return issues


## 属于该标签的物品键（按 `ItemDef.tags` 现算，不查注册表）。
## 校验要能脱离全局 TagRegistry 单独跑（测试会建一个 scratch registry），
## 所以「谁是成员」以数据为准，注册表只是查询用的索引。
func tag_member_keys(tag_key: String) -> Array[String]:
	var keys: Array[String] = []
	if tag_key.is_empty():
		return keys
	for def in get_defs_of_type("item"):
		var item := def as ItemDef
		if item != null and item.tags.has(tag_key):
			keys.append(item.get_key())
	keys.sort()
	return keys

# ─── 加载 ───

## 清空后重新扫描 DATA_ROOT；返回问题描述数组（空 = 全部通过）
func load_all(root_path: String = DATA_ROOT) -> Array[String]:
	clear()
	var issues: Array[String] = []
	var types := dir_types()
	for dir_name in types:
		var expected: Script = types[dir_name]
		issues.append_array(_load_dir(root_path.path_join(dir_name), expected))
	return issues

## 把目录里列出的文件名还原成可加载的资源名：导出包里的 `.remap` 后缀要去掉。
##
## 编辑器里资源是 `xxx.tres`，导出后变成 `xxx.tres.remap`（内容被二进制化，原名不再单独进包）；
## 两种形态都要能加载，而 `ResourceLoader.load()` 在包里会自动沿 remap 转发到真正的资源。
static func resolved_resource_name(file_name: String) -> String:
	return file_name.trim_suffix(".remap")

## 从目录列出的文件名里挑出可加载的资源，把导出包的 `.remap` 名字还原，并对同名的去重。
## 编辑器（`xxx.tres`）与导出包（`xxx.tres.remap`）两种形态都认；两者并存时只保留一个，
## 否则同一份定义会被登记两遍、报键重复。
static func resource_file_names(file_names: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	var seen: Dictionary = {}
	for file_name in file_names:
		var resource_name := resolved_resource_name(file_name)
		if not (resource_name.ends_with(".tres") or resource_name.ends_with(".res")):
			continue
		if seen.has(resource_name):
			continue
		seen[resource_name] = true
		result.append(resource_name)
	return result

func _load_dir(dir_path: String, expected: Script) -> Array[String]:
	var issues: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		issues.append("目录不存在：%s（%s 类型的定义无处加载）" % [dir_path, _type_name_of(expected)])
		return issues
	var dir := DirAccess.open(dir_path)
	if dir == null:
		issues.append("无法打开目录：%s（错误码 %d）" % [dir_path, DirAccess.get_open_error()])
		return issues
	for resource_name in resource_file_names(dir.get_files()):
		var path := dir_path.path_join(resource_name)
		var resource := ResourceLoader.load(path)
		if resource == null:
			issues.append("加载失败：%s" % path)
			continue
		if not (resource is GameDef):
			issues.append("类型不符：%s 期望 %s，实际 %s" % [path, _type_name_of(expected), resource.get_class()])
			continue
		var def := resource as GameDef
		if def.get_script() != expected:
			issues.append("类型不符：%s 期望 %s，实际 %s" % [path, _type_name_of(expected), _type_name_of(def.get_script())])
			continue
		if has_def(def.get_key()):
			issues.append("键重复：%s（%s）" % [def.get_key(), path])
			continue
		if not register_def(def):
			issues.append("登记失败：%s（%s）" % [def.get_key(), path])
	return issues

# ─── 校验 ───

## 跨条目校验：id 唯一性、引用可达、数值合法。返回问题描述数组（空 = 通过）
func validate() -> Array[String]:
	var issues: Array[String] = []
	var entries := get_all_entries()
	for key in entries:
		var def := entries[key] as GameDef
		if def == null:
			continue
		issues.append_array(_validate_def(def))
	issues.append_array(_validate_letter_orders())
	issues.append_array(_validate_base_material_sources())
	return issues


## 每种基础材料都得有来路：桌面有采集点，或者商人卖；否则玩家永远拿不到它
func _validate_base_material_sources() -> Array[String]:
	var issues: Array[String] = []
	var sources: Dictionary = {}
	for def in get_defs_of_type("harvest"):
		var harvest := def as HarvestDef
		if harvest == null:
			continue
		for item in _harvest_candidates(harvest):
			sources[item.get_key()] = true
	for def in get_defs_of_type("item"):
		var material := def as ItemDef
		if material == null or not _is_base_material(material):
			continue
		if sources.has(material.get_key()) or material.merchant_price > 0:
			continue
		issues.append("%s：基础材料既没有采集点也不出售，玩家拿不到" % material.get_key())
	return issues

## 基础材料 = 材料档位里最底层的那些（可采集、可购买）
static func _is_base_material(item: ItemDef) -> bool:
	return item.kind == ItemDef.Kind.MATERIAL and item.material_kind == ItemDef.MaterialKind.BASE

func _validate_def(def: GameDef) -> Array[String]:
	var issues: Array[String] = []
	var ctx := def.get_key()
	if def.id.is_empty():
		issues.append("%s：id 为空" % ctx)
	if not def.is_key_valid():
		issues.append("%s：namespace / id 含有非法字符（只允许小写字母、数字、_ - . /）" % ctx)
	# 采集点是材料的一个来源，玩家看到的名字来自材料本身，不需要自己的显示名
	if def.display_name.is_empty() and not (def is HarvestDef):
		issues.append("%s：display_name 为空" % ctx)

	if def is RecipeDef:
		var recipe := def as RecipeDef
		issues.append_array(_validate_key_ref("%s.output" % ctx, recipe.output, ["item"]))
		if recipe.output_amount < 1:
			issues.append("%s：output_amount 必须 >= 1（实际 %d）" % [ctx, recipe.output_amount])
		var seen_outputs := {recipe.output: true}
		for i in recipe.extra_outputs.size():
			var extra := recipe.extra_outputs[i]
			var label := "%s.extra_outputs[%d]" % [ctx, i]
			issues.append_array(_validate_stack(label, extra))
			if extra == null:
				continue
			if not extra.by_tag.is_empty():
				issues.append("%s：副产物不支持 by_tag，请指名 material" % label)
			if extra.material == recipe.output:
				issues.append("%s：副产物与主产物重复（%s）" % [label, extra.material])
			elif seen_outputs.has(extra.material):
				issues.append("%s：副产物重复（%s）" % [label, extra.material])
			else:
				seen_outputs[extra.material] = true
		if recipe.inputs.is_empty():
			issues.append("%s：inputs 为空（配方至少需要一种输入）" % ctx)
		if recipe.inputs.size() > RecipeDef.MAX_INPUT_KINDS:
			issues.append("%s：inputs 有 %d 种原料，上限 %d 种" % [ctx, recipe.inputs.size(), RecipeDef.MAX_INPUT_KINDS])
		for stack in recipe.inputs:
			issues.append_array(_validate_stack(ctx, stack))
		if recipe.duration_seconds < 0.0:
			issues.append("%s：duration_seconds 不能为负（%s）" % [ctx, recipe.duration_seconds])
		if recipe.needs_facility():
			issues.append_array(_validate_key_ref("%s.facility" % ctx, recipe.facility, ["facility"]))
		issues.append_array(_validate_research_fields(recipe))
	elif def is ResearchDef:
		var rules := def as ResearchDef
		issues.append_array(_validate_key_ref("%s.facility" % ctx, rules.facility, ["facility"]))
		if rules.burn_rates.is_empty():
			issues.append("%s：burn_rates 为空（至少要给出 1 级的烧毁率）" % ctx)
		for rate in rules.burn_rates:
			if rate < 0.0 or rate > 1.0:
				issues.append("%s：burn_rates 含越界值（%s，应在 0..1）" % [ctx, rate])
		if rules.default_seconds < 0.0:
			issues.append("%s：default_seconds 不能为负" % ctx)
	elif def is FacilityDef:
		var facility := def as FacilityDef
		if facility.max_level < 1:
			issues.append("%s：max_level 必须 >= 1" % ctx)
		if facility.level_speed_factors.size() != facility.max_level:
			issues.append("%s：level_speed_factors 有 %d 项，应为 max_level(%d) 项" % [ctx, facility.level_speed_factors.size(), facility.max_level])
		for factor in facility.level_speed_factors:
			if factor <= 0.0:
				issues.append("%s：level_speed_factors 含非正数（%s）" % [ctx, factor])
		for upgrade in facility.upgrades:
			if upgrade == null:
				issues.append("%s：upgrades 含空条目" % ctx)
				continue
			if upgrade.target_level <= 1 or upgrade.target_level > facility.max_level:
				issues.append("%s：升级目标等级 %d 越界（应在 2..%d）" % [ctx, upgrade.target_level, facility.max_level])
			if upgrade.coin_cost < 0:
				issues.append("%s：升级 %d 级的 coin_cost 不能为负" % [ctx, upgrade.target_level])
			for stack in upgrade.materials:
				issues.append_array(_validate_stack(ctx, stack))
		if not facility.unlock_letter.is_empty():
			issues.append_array(_validate_key_ref("%s.unlock_letter" % ctx, facility.unlock_letter, ["letter"]))
	elif def is HarvestDef:
		issues.append_array(_validate_harvest(ctx, def as HarvestDef))
	elif def is LetterDef:
		var letter := def as LetterDef
		if letter.order <= 0:
			issues.append("%s：order 必须 > 0" % ctx)
		if letter.title.is_empty():
			issues.append("%s：title 为空" % ctx)
		if letter.body.is_empty():
			issues.append("%s：body 为空" % ctx)
		if letter.needs_condition_ref():
			var expected_types := ["item"]
			if (
				letter.condition == LetterDef.Condition.AFTER_LETTER
				or letter.condition == LetterDef.Condition.TASK_COMPLETED
			):
				expected_types = ["letter"]
			issues.append_array(_validate_key_ref("%s.condition_ref" % ctx, letter.condition_ref, expected_types))
			# 类型收窄成 item 之后，只靠 type_id 分不出「这道菜」与「这块肉」，这里补一刀
			if letter.condition == LetterDef.Condition.FOOD_CRAFTED:
				var dish := get_def(letter.condition_ref) as ItemDef
				if dish != null and not dish.is_food():
					issues.append("%s：FOOD_CRAFTED 的 condition_ref(%s) 不是食物" % [ctx, letter.condition_ref])
		if letter.condition == LetterDef.Condition.CATALOG_COUNT:
			if letter.condition_value <= 0:
				issues.append("%s：CATALOG_COUNT 的 condition_value 必须 > 0" % ctx)
			elif letter.condition_value > get_catalog_keys().size():
				issues.append("%s：CATALOG_COUNT(%d) 超过图鉴总数(%d)，这封信永远到不了" % [ctx, letter.condition_value, get_catalog_keys().size()])
		if letter.catalog_min < 0:
			issues.append("%s：catalog_min 不能为负" % ctx)
		elif letter.catalog_min > 0:
			if letter.condition != LetterDef.Condition.AFTER_LETTER:
				issues.append("%s：catalog_min 目前只允许与 AFTER_LETTER 搭配" % ctx)
			if letter.catalog_min > get_catalog_keys().size():
				issues.append("%s：catalog_min(%d) 超过图鉴总数(%d)，这封信永远到不了" % [ctx, letter.catalog_min, get_catalog_keys().size()])
		if letter.has_task():
			if letter.task_title.is_empty():
				issues.append("%s：task_title 为空" % ctx)
			if letter.task_body.is_empty():
				issues.append("%s：task_body 为空" % ctx)
			var target_types: Array[String] = []
			match letter.task_goal:
				LetterDef.TaskGoal.CRAFT_FOOD, LetterDef.TaskGoal.COLLECT:
					target_types = ["item"]
				LetterDef.TaskGoal.RESEARCH_RECIPE:
					target_types = ["recipe"]
				LetterDef.TaskGoal.CRAFT_THEME:
					target_types = ["theme"]
				LetterDef.TaskGoal.CRAFT_TAG:
					target_types = ["tag"]
			if not target_types.is_empty():
				issues.append_array(_validate_key_ref("%s.task_ref" % ctx, letter.task_ref, target_types))
		for stack in letter.rewards:
			issues.append_array(_validate_stack(ctx, stack))
	elif def is ItemDef:
		issues.append_array(_validate_item(ctx, def as ItemDef))
	return issues

## 物品校验：交易数据两种 kind 都查，展示字段按 kind 分派。
## 合并成一张表之后，类型只能挡住「这是不是物品」，挡不住「这块肉是不是被写成了菜」，
## 所以这里按 kind 把不属于该类的字段挑出来。
func _validate_item(ctx: String, item: ItemDef) -> Array[String]:
	var issues: Array[String] = []
	if item.merchant_price < 0:
		issues.append("%s：merchant_price 不能为负" % ctx)
	if item.sell_price < 0:
		issues.append("%s：sell_price 不能为负" % ctx)
	if item.sell_price > 0 and item.merchant_price > 0 and item.sell_price > item.merchant_price:
		issues.append("%s：sell_price(%d) 高于 merchant_price(%d)，倒卖就能刷钱" % [ctx, item.sell_price, item.merchant_price])
	if item.is_food():
		if item.taste.is_empty():
			issues.append("%s：taste 为空（图鉴需要有味觉记忆）" % ctx)
		if item.material_kind != ItemDef.MaterialKind.BASE:
			issues.append("%s：食物不该有 material_kind（只有材料分基础 / 中间 / 免费）" % ctx)
	else:
		if not item.taste.is_empty():
			issues.append("%s：taste 是食物专用字段，材料不该写" % ctx)
		if not item.catalog_hint.is_empty():
			issues.append("%s：catalog_hint 是食物专用字段，材料不该写" % ctx)
	issues.append_array(_validate_item_tags(ctx, item))
	return issues


## 标签校验：每个都要是已登记的标签，且材料只挂 ingredients 那一类。
## 食物可以两类都挂（既是「街边·宵夜」，也是「任意一种肉」的成员这种写法不常见，
## 但「成品即材料」之后一道菜确实可能被当成某类原料，所以不拦）。
func _validate_item_tags(ctx: String, item: ItemDef) -> Array[String]:
	var issues: Array[String] = []
	var seen: Dictionary = {}
	for tag_key in item.tags:
		if seen.has(tag_key):
			issues.append("%s：tags 里 %s 重复" % [ctx, tag_key])
			continue
		seen[tag_key] = true
		var tag := get_def(tag_key) as TagDef
		if tag == null:
			issues.append("%s：tags 里的 %s 不是标签定义" % [ctx, tag_key])
			continue
		if item.is_material() and not tag.is_ingredient():
			issues.append("%s：材料只能挂 ingredient 标签，%s 是图鉴标签（scope=food）" % [ctx, tag_key])
	return issues

## 研究相关字段的校验（候选池、提示、设备门槛）。
## 候选池必须能「包含」配方输入：否则玩家无论怎么试都试不出来，是设计错误而不是玩法。
func _validate_research_fields(recipe: RecipeDef) -> Array[String]:
	var issues: Array[String] = []
	var ctx := recipe.get_key()
	if not recipe.needs_research():
		if not recipe.research_hint.is_empty():
			issues.append("%s：有 research_hint 但 research_pool 为空（这条配方不需要研究）" % ctx)
		if recipe.research_min_facility_level > 0:
			issues.append("%s：有 research_min_facility_level 但不需要研究（门槛不会生效）" % ctx)
		return issues
	# research_hint 可空：图鉴对没写提示的研究配方自动拼一句「试试哪几样」，
	# 不然一百多条配方每一条都要写文案，写作量和维护量都不现实。
	var pool := {}
	for key in recipe.research_pool:
		if pool.has(key):
			issues.append("%s：research_pool 里 %s 重复" % [ctx, key])
			continue
		pool[key] = true
		var target := get_def(key)
		if target == null:
			issues.append("%s：research_pool 引用了不存在的物品 %s" % [ctx, key])
		elif not (target is ItemDef):
			issues.append("%s：research_pool 里的 %s 是 %s，不能作为候选材料" % [ctx, key, target.get_type_id()])
	if recipe.research_pool.size() < 2:
		issues.append("%s：research_pool 至少要有 2 样（研究要选 2–4 样）" % ctx)
	if recipe.inputs.size() > 4:
		issues.append("%s：输入超过 4 样，研究台最多放 4 样" % ctx)
	for stack in recipe.inputs:
		if stack == null:
			continue
		if not stack.by_tag.is_empty():
			# 按标签要料的输入：候选池里至少要有这个标签的一个成员。
			# 要求「全部成员都在池里」会让池子随标签膨胀（veg 有 10 个成员），
			# 要求「一个都不在」则会做出玩家怎么摆都试不出来的死组合，取中间。
			var hit := false
			for member in tag_member_keys(stack.by_tag):
				if pool.has(member):
					hit = true
					break
			if not hit:
				issues.append("%s：research_pool 里没有 %s 底下的任何物品，这条组合试不出来" % [ctx, stack.by_tag])
			continue
		if not pool.has(stack.material):
			issues.append("%s：research_pool 少了输入材料 %s" % [ctx, stack.material])
	if recipe.research_min_facility_level > 0:
		if not recipe.needs_facility():
			issues.append("%s：research_min_facility_level 需要配 facility 才有意义" % ctx)
		var facility := get_def(recipe.facility) as FacilityDef
		if facility != null and recipe.research_min_facility_level > facility.max_level:
			issues.append("%s：research_min_facility_level(%d) 超过 %s 的最高等级(%d)" % [ctx, recipe.research_min_facility_level, recipe.facility, facility.max_level])
	return issues

## 物品引用必须存在，且是物品（材料与食物同表，两者都可以当输入/输出/附件）。
## 「成品即材料」：浓缩可以当拿铁的输入，所以配方输入不做 kind 限制。
## 某个采集点在这个标签下可能摇到的材料（与 GameState.harvest_pool 同口径，但不看等级）
func _harvest_candidates(harvest: HarvestDef) -> Array[ItemDef]:
	var pool: Array[ItemDef] = []
	for key in tag_member_keys(harvest.tag):
		var item := get_def(key) as ItemDef
		if item == null or not item.is_material():
			continue
		if item.material_kind != ItemDef.MaterialKind.BASE:
			continue
		pool.append(item)
	return pool


## 采集点校验：标签存在且是食材标签、池子里有货、四条数值数组长度一致、升级表比等级数少一项
func _validate_harvest(ctx: String, harvest: HarvestDef) -> Array[String]:
	var issues: Array[String] = []
	if harvest.tag.is_empty():
		issues.append("%s：tag 为空，不知道采什么" % ctx)
		return issues
	var tag_def := get_def(harvest.tag) as TagDef
	if tag_def == null:
		issues.append("%s：tag 指向不存在的标签（%s）" % [ctx, harvest.tag])
		return issues
	if not tag_def.is_ingredient():
		issues.append("%s：tag 必须是食材标签，%s 是图鉴标签" % [ctx, harvest.tag])
	# 池子是按标签现算的：标签底下必须有基础材料，而且最低等级就得有货，
	# 否则这条升级线前几级摇出来的永远是空。
	var pool := _harvest_candidates(harvest)
	if pool.is_empty():
		issues.append("%s：%s 底下没有可采集的基础材料" % [ctx, harvest.tag])
	elif not pool.any(func(item: ItemDef) -> bool: return item.harvest_tier <= 1):
		issues.append("%s：%s 底下没有 harvest_tier = 1 的材料，开局摇不出东西" % [ctx, harvest.tag])
	for item in pool:
		if item.harvest_tier > harvest.max_level():
			issues.append("%s：%s 的 harvest_tier(%d) 超出采集点最高等级，永远摇不到" % [ctx, item.id, item.harvest_tier])
	if not harvest.unlock_facility.is_empty():
		issues.append_array(_validate_key_ref("%s.unlock_facility" % ctx, harvest.unlock_facility, ["facility"]))
	if not harvest.unlock_letter.is_empty():
		issues.append_array(_validate_key_ref("%s.unlock_letter" % ctx, harvest.unlock_letter, ["letter"]))
	var levels := harvest.max_level()
	if (
		harvest.cooldown_seconds.size() != levels
		or harvest.yield_per_click.size() != levels
		or harvest.trickle_per_second.size() != levels
	):
		issues.append("%s：三条等级数值（cooldown/yield/trickle）长度必须一致" % ctx)
	for seconds in harvest.cooldown_seconds:
		if seconds <= 0.0:
			issues.append("%s：cooldown_seconds 必须为正（%s）" % [ctx, seconds])
	for amount in harvest.yield_per_click:
		if amount <= 0:
			issues.append("%s：yield_per_click 必须为正（%d）" % [ctx, amount])
	for rate in harvest.trickle_per_second:
		if rate < 0.0:
			issues.append("%s：trickle_per_second 不能为负（%s）" % [ctx, rate])
	if harvest.upgrade_coin_costs.size() != levels - 1:
		issues.append("%s：upgrade_coin_costs 有 %d 项，应为 %d 项" % [ctx, harvest.upgrade_coin_costs.size(), levels - 1])
	if harvest.upgrade_item_amounts.size() != levels - 1:
		issues.append("%s：upgrade_item_amounts 有 %d 项，应为 %d 项" % [ctx, harvest.upgrade_item_amounts.size(), levels - 1])
	for cost in harvest.upgrade_coin_costs:
		if cost < 0:
			issues.append("%s：upgrade_coin_costs 含负数（%d）" % [ctx, cost])
	for amount in harvest.upgrade_item_amounts:
		if amount < 0:
			issues.append("%s：upgrade_item_amounts 含负数（%d）" % [ctx, amount])
	return issues


func _validate_stack(ctx: String, stack: MaterialStack) -> Array[String]:
	var issues: Array[String] = []
	if stack == null:
		issues.append("%s：物品条目为空" % ctx)
		return issues
	var by_tag := not stack.by_tag.is_empty()
	if stack.material.is_empty() and not by_tag:
		issues.append("%s：物品引用为空（material 与 by_tag 至少填一个）" % ctx)
	elif by_tag and not stack.material.is_empty():
		issues.append("%s：material(%s) 与 by_tag(%s) 只能二选一" % [ctx, stack.material, stack.by_tag])
	elif by_tag:
		issues.append_array(_validate_tag_ref("%s.by_tag" % ctx, stack.by_tag))
	elif not has_def(stack.material):
		issues.append("%s：引用了不存在的物品 %s" % [ctx, stack.material])
	else:
		var target := get_def(stack.material)
		if not (target is ItemDef):
			issues.append("%s：%s 是 %s，不能作为堆叠物品" % [ctx, stack.material, target.get_type_id()])
	if stack.amount <= 0:
		issues.append("%s：%s 的数量必须 > 0（实际 %d）" % [ctx, stack, stack.amount])
	return issues


## 食材标签引用：必须是已登记、scope 为 ingredient、且底下至少有一个物品。
## 空标签的配方永远凑不齐料，属于设计错误而不是玩法。
func _validate_tag_ref(field: String, key: String) -> Array[String]:
	var issues: Array[String] = []
	var tag := get_def(key) as TagDef
	if tag == null:
		issues.append("%s：引用了不存在的标签 %s" % [field, key])
		return issues
	if not tag.is_ingredient():
		issues.append("%s：%s 是图鉴标签（scope=food），不能当配方输入" % [field, key])
		return issues
	if tag_member_keys(key).is_empty():
		issues.append("%s：%s 底下没有任何物品，这条配方永远凑不齐" % [field, key])
	return issues

## 引用键必须存在且属于 allowed_types（type_id）
func _validate_key_ref(field: String, key: String, allowed_types: Array) -> Array[String]:
	var issues: Array[String] = []
	if key.is_empty():
		issues.append("%s：引用为空" % field)
		return issues
	var target := get_def(key)
	if target == null:
		issues.append("%s：引用了不存在的定义 %s" % [field, key])
		return issues
	if not allowed_types.has(target.get_type_id()):
		issues.append("%s：%s 是 %s，期望 %s" % [field, key, target.get_type_id(), ", ".join(allowed_types)])
	return issues

func _validate_letter_orders() -> Array[String]:
	var issues: Array[String] = []
	var seen := {}
	for def in get_defs_of_type("letter"):
		var order := (def as LetterDef).order
		if seen.has(order):
			issues.append("信件 order 重复：%d（%s 与 %s）" % [order, seen[order], def.get_key()])
		else:
			seen[order] = def.get_key()
	return issues

static func _type_name_of(script: Script) -> String:
	if script == null:
		return "<null>"
	return script.get_global_name()
