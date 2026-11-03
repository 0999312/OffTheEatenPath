extends GutTest
## 内容完整性守卫（审计 2026-10-27 补；同日 P0 修正后白名单清空）：
## 1) 图鉴里的每种材料都必须有来路（配方产出 / 采集 / 商店 / 信件奖励）；
## 2) 信件按 order 顺序解锁，图鉴门槛必须随 order 非递减，且落在图鉴总数 5%–98% 的区间里；
## 3) 冰箱信是出发（第 9 封，离线）之后的间奏信：按图鉴进度触发，门槛高于出发信。
##
## 两条白名单曾对应审计报告里的两个 P0（docs/plans/2026-10-27-audit.md §2）：
## 4 条中间品补了配方、冰箱信从 order 17 挪到 8（§9.2 表 1 / 表 2）。
## 以后若再出现断链：往白名单里加条目，并在这一行下面写清为什么、等谁来修。

const KNOWN_UNSOURCED: Array[String] = []
## 图鉴门槛的可接受区间（占总量）。原来是「必须是 25/30/40/…/100% 的整数档」，
## 但 P8 之后信件涨到 44 封、其中 12 封挂图鉴门槛，固定档位放不下；而 100% 档本身
## 是死锁——最后一封信也占一条图鉴，要求集齐就等于要求先拿到它。
## 现在只守两头：太早会剧透，太晚会永远解不开。
## 2026-10-30：第七封提前到图鉴 50 条，开场合成的教学链从 50 开始；
## 下限随之下放到 5%（50/636≈7.9%），其余区间仍守 98% 上限。
const LETTER_MIN_RATIO := 0.05
const LETTER_MAX_RATIO := 0.98


func _data() -> DataRegistry:
	return RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry


func _add_granted(stack: MaterialStack, out: Dictionary, data: DataRegistry) -> void:
	# 奖励可能是具体材料，也可能是 by_tag（「这个标签下任意一样」）
	if not stack.material.is_empty():
		out[stack.material] = true
	elif not stack.by_tag.is_empty():
		for key in data.tag_member_keys(stack.by_tag):
			out[key] = true


func _letters_by_order(data: DataRegistry) -> Array[LetterDef]:
	var letters: Array[LetterDef] = []
	for def in data.get_defs_of_type("letter"):
		letters.append(def as LetterDef)
	letters.sort_custom(func(a: LetterDef, b: LetterDef) -> bool: return a.order < b.order)
	return letters


func _sourced_materials(data: DataRegistry) -> Dictionary:
	var out := {}
	for def in data.get_defs_of_type("recipe"):
		var recipe := def as RecipeDef
		out[recipe.output] = true
		# 副产物也是「做得出来」的来源：味噌就是酱油的 extra_outputs
		for stack in recipe.extra_outputs:
			out[stack.material] = true
	for def in data.get_defs_of_type("letter"):
		for stack in (def as LetterDef).rewards:
			_add_granted(stack, out, data)
	return out


## 研究签名只看「材料种类集合」：两条都需要研究的配方若输入种类完全相同，
## 研究台会按 order 抢先后，后一条永远命中不了（R18 反馈 1）。
## 这里遍历全部需研究配方；带 by_tag 的配方没有固定键集合，不参与比较。
func test_research_recipe_signatures_are_unique() -> void:
	var data := _data()
	assert_not_null(data, "DataRegistry 未就绪")
	if data == null:
		return
	var by_signature := {}
	var collisions: Array[String] = []
	var checked := 0
	for def in data.get_defs_of_type("recipe"):
		var recipe := def as RecipeDef
		if recipe == null or not recipe.needs_research():
			continue
		var has_wildcard := false
		for stack in recipe.inputs:
			if stack != null and not stack.by_tag.is_empty():
				has_wildcard = true
				break
		if has_wildcard:
			continue
		var signature := GameState.signature_of(recipe.input_keys())
		checked += 1
		if by_signature.has(signature):
			collisions.append("%s 与 %s 都是 %s" % [by_signature[signature], recipe.get_key(), signature])
		else:
			by_signature[signature] = recipe.get_key()
	assert_gt(checked, 0, "应至少有一条具名输入的需研究配方")
	assert_eq(collisions, [] as Array[String],
		"需研究配方的材料种类集合必须唯一，否则后一条永远研究不出来：%s" % str(collisions))


func test_every_catalog_material_has_a_source() -> void:
	var data := _data()
	assert_not_null(data, "DataRegistry 未就绪")
	if data == null:
		return
	var sourced := _sourced_materials(data)
	var missing: Array[String] = []
	for def in data.get_defs_of_type("item"):
		var item := def as ItemDef
		if item == null or not item.in_catalog or not item.is_material():
			continue
		if item.merchant_price > 0:
			continue
		if sourced.has(item.get_key()):
			continue
		if GameState.get_harvest_for_material(item.get_key()) != null:
			continue
		missing.append(item.get_key())
	# 白名单之外不允许出现「图鉴里有、但永远拿不到」的材料
	var unexpected: Array[String] = []
	for key in missing:
		if not KNOWN_UNSOURCED.has(key):
			unexpected.append(key)
	assert_eq(unexpected, [] as Array[String],
			"图鉴材料没有来路（配方 / 采集 / 商店 / 信件都没有）：%s" % str(unexpected))


func test_whitelisted_unsourced_materials_are_still_unsourced() -> void:
	# 白名单里还剩的条目必须真的还缺，否则说明可以从白名单删掉
	var data := _data()
	assert_not_null(data, "DataRegistry 未就绪")
	if data == null:
		return
	var produced := {}
	for def in data.get_defs_of_type("recipe"):
		produced[(def as RecipeDef).output] = true
	for key in KNOWN_UNSOURCED:
		var item := data.get_def(key) as ItemDef
		assert_not_null(item, "%s 不存在，请更新白名单" % key)
		if item == null:
			continue
		assert_false(produced.has(key), "%s 已经有配方产出了，请从 KNOWN_UNSOURCED 删掉" % key)


func test_letter_catalog_thresholds_are_percentages_of_the_catalog() -> void:
	var data := _data()
	assert_not_null(data, "DataRegistry 未就绪")
	if data == null:
		return
	var total := data.get_catalog_keys().size()
	for letter in _letters_by_order(data):
		if letter.condition != LetterDef.Condition.CATALOG_COUNT:
			continue
		var low := roundi(float(total) * LETTER_MIN_RATIO)
		var high := roundi(float(total) * LETTER_MAX_RATIO)
		assert_between(letter.condition_value, low, high,
			"%s 的门槛 %d 落在图鉴 %d 的 %d–%d 之外，改内容后要按新总数重算" % [letter.get_key(), letter.condition_value, total, low, high])


func test_catalog_gated_letters_follow_order() -> void:
	# 顺序锁：遇到第一封条件不满足的就停，所以低门槛信不能排在高门槛信后面
	var data := _data()
	assert_not_null(data, "DataRegistry 未就绪")
	if data == null:
		return
	var last := 0
	var violations: Array[String] = []
	for letter in _letters_by_order(data):
		if letter.condition != LetterDef.Condition.CATALOG_COUNT:
			continue
		if letter.condition_value < last:
			violations.append("%s（order %d，门槛 %d）排在前一封门槛 %d 之后" % [letter.get_key(), letter.order, letter.condition_value, last])
		last = maxi(last, letter.condition_value)
	assert_eq(violations, [] as Array[String],
			"信件门槛与 order 顺序矛盾，低门槛信会被高门槛信卡住：%s" % str(violations))


func test_fridge_letter_arrives_after_leaving_as_an_interlude() -> void:
	# 第六轮：原 9–13 封挪到出发（离站，第 9 封）之后当间奏信；
	# 冰箱信仍按图鉴进度触发，门槛要高于出发信，且前面不能有门槛更高的信
	var data := _data()
	assert_not_null(data, "DataRegistry 未就绪")
	if data == null:
		return
	var fridge := data.get_def("game:letter/fridge_hum") as LetterDef
	assert_not_null(fridge, "冰箱信应存在")
	if fridge == null:
		return
	assert_eq(fridge.condition, LetterDef.Condition.CATALOG_COUNT, "冰箱信按图鉴进度触发")
	var leave := data.get_def("game:letter/before_leaving") as LetterDef
	assert_not_null(leave, "离站信应存在")
	if leave == null:
		return
	assert_lt(fridge.order, leave.order, "冰箱信应排在出发信之前（序章 13 对 16）")
	assert_lt(fridge.condition_value, leave.condition_value,
		"冰箱信门槛 %d 应低于出发信 %d：先开冰箱，再带着离线出发" % [fridge.condition_value, leave.condition_value])
	var blockers := 0
	for letter in _letters_by_order(data):
		if letter.order >= fridge.order:
			continue
		if letter.condition != LetterDef.Condition.CATALOG_COUNT:
			continue
		if letter.condition_value > fridge.condition_value:
			blockers += 1
	assert_eq(blockers, 0, "冰箱信被门槛更高的信卡住，顺序解锁会让它永远读不到")


func test_catalog_min_gates_are_ordered_above_previous_catalog_targets() -> void:
	var data := _data()
	assert_not_null(data, "DataRegistry 未就绪")
	if data == null:
		return
	var total := data.get_catalog_keys().size()
	var last_catalog_target := 0
	var gate_count := 0
	for letter in _letters_by_order(data):
		if letter.condition == LetterDef.Condition.CATALOG_COUNT:
			last_catalog_target = maxi(last_catalog_target, letter.condition_value)
		if letter.catalog_min <= 0:
			continue
		gate_count += 1
		assert_eq(letter.condition, LetterDef.Condition.AFTER_LETTER,
			"%s 的 catalog_min 只能挂在 AFTER_LETTER 上" % letter.get_key())
		assert_gt(letter.catalog_min, last_catalog_target,
			"%s 的门槛 %d 应高于此前最近的离站图鉴门槛 %d" % [letter.get_key(), letter.catalog_min, last_catalog_target])
		assert_lt(letter.catalog_min, total,
			"%s 的门槛 %d 不能超过图鉴总数 %d" % [letter.get_key(), letter.catalog_min, total])
	assert_eq(gate_count, 8, "8 个站间过渡各应有一道 catalog_min 门槛")


func test_catalog_min_blocks_until_catalog_reaches_target() -> void:
	var data := _data()
	assert_not_null(data, "DataRegistry 未就绪")
	if data == null:
		return
	var gate := data.get_def("game:letter/southeast_asia_arrive") as LetterDef
	assert_not_null(gate, "东南亚到站信应存在")
	if gate == null:
		return
	GameState.reset()
	GameState._read_letters["game:letter/beyond_paper"] = true
	var keys := data.get_catalog_keys()
	GameState._discovered.clear()
	for i in range(gate.catalog_min - 1):
		GameState._discovered[keys[i]] = true
	assert_false(GameState._letter_condition_met(gate),
		"差一条时不能放行（门槛 %d）" % gate.catalog_min)
	GameState._discovered[keys[gate.catalog_min - 1]] = true
	assert_true(GameState._letter_condition_met(gate),
		"正好达到门槛时应放行")


## 用户 m02051 第 1 条：读完离站信不该被「下一封自己的门槛」卡住。
## 门禁必须落在到站信上：离站信读完 → 间期/任务信立刻出现 → 到站信再等图鉴。
func test_arrival_gate_does_not_block_the_letter_before_it() -> void:
	var data := _data()
	assert_not_null(data, "DataRegistry 未就绪")
	if data == null:
		return
	var leave := data.get_def("game:letter/south_asia_leave") as LetterDef
	var interval := data.get_def("game:letter/butcher_street") as LetterDef
	var arrival := data.get_def("game:letter/middle_east_arrive") as LetterDef
	assert_not_null(leave)
	assert_not_null(interval)
	assert_not_null(arrival)
	if leave == null or interval == null or arrival == null:
		return
	assert_eq(interval.catalog_min, 0, "间期信不应再背站间门槛")
	assert_eq(arrival.catalog_min, 330, "门槛应落在中东到站信上")
	assert_eq(arrival.condition_ref, interval.get_key(), "到站信紧跟间期信")
	GameState.reset()
	GameState._read_letters[leave.get_key()] = true
	assert_true(GameState._letter_condition_met(interval),
		"读完南亚离站信，屠夫街应立即放行")
	assert_false(GameState._letter_condition_met(arrival),
		"图鉴 0 条时，中东到站信仍应被 264 门槛挡住")


func test_tutorial_catalog_thresholds_step_by_at_most_fifty() -> void:
	# 2026-10-31（第九轮）：序章加长到 16 封，门槛改为 50 / 100 / 110。
	# 教学链每开一封信仍要留台阶；图鉴总量涨到 749 之后，台阶放到 50 条。
	# 冰箱 100 → 出发 110 是两封序章信的衔接（第三轮反馈第 4 条）。
	var data := _data()
	assert_not_null(data, "DataRegistry 未就绪")
	if data == null:
		return
	var gates: Array[LetterDef] = []
	for letter in _letters_by_order(data):
		if letter.condition != LetterDef.Condition.CATALOG_COUNT:
			continue
		if letter.order > 16:
			break
		gates.append(letter)
	var values: Array[int] = []
	for gate in gates:
		values.append(gate.condition_value)
	assert_eq(values, [50, 100, 110] as Array[int], "序章到出发的三道图鉴门槛应为 50 / 100 / 110")
	for index in range(1, gates.size()):
		var step := gates[index].condition_value - gates[index - 1].condition_value
		assert_lte(step, 50, "%s 的门槛 %d 比上一封高 %d 条，教学期每封最多跨 50 条"
			% [gates[index].get_key(), gates[index].condition_value, step])


func test_east_asia_arrival_is_the_stage_gate() -> void:
	# 一主题一阶段：到站信同时是阶段门禁。东亚到站从「读完离站信」改为图鉴 120，
	# 这样序章内容收得差不多才会被放上车，后续每个主题都沿用「到站信 + 图鉴门槛」。
	var data := _data()
	assert_not_null(data, "DataRegistry 未就绪")
	if data == null:
		return
	var arrive := data.get_def("game:letter/east_asia_arrive") as LetterDef
	assert_not_null(arrive, "东亚到站信应存在")
	if arrive == null:
		return
	assert_eq(arrive.condition, LetterDef.Condition.CATALOG_COUNT, "东亚到站信应承担阶段门禁")
	assert_eq(arrive.condition_value, 120, "东亚阶段的图鉴门槛应为 120")
	var leave := data.get_def("game:letter/before_leaving") as LetterDef
	assert_not_null(leave, "离站信应存在")
	if leave != null:
		assert_gt(arrive.condition_value, leave.condition_value, "阶段门禁应高于序章离站门槛")


func test_letter_handwriting_roundtrips_through_codec() -> void:
	var letter := LetterDef.new()
	letter.id = "letter/handwriting_test"
	letter.body = "test body"
	letter.handwriting = "familiar"
	var encoded := letter.to_json_data()
	assert_true(encoded.is_success(), "LetterDef 应能用 Codec 编码：%s" % (encoded.get_error() if encoded.is_error() else ""))
	if not encoded.is_success():
		return
	var parsed: Variant = JSON.parse_string(JSON.stringify(encoded.get_value()))
	assert_not_null(parsed, "编码结果应能序列化为 JSON 文本")
	if parsed == null:
		return
	var decoded := LetterDef.get_codec().decode(parsed, JsonOps.INSTANCE)
	assert_true(decoded.is_success(), "JSON 应能解码回 LetterDef：%s" % (decoded.get_error() if decoded.is_error() else ""))
	if not decoded.is_success():
		return
	var copy := decoded.get_value() as LetterDef
	assert_not_null(copy, "解码结果应是 LetterDef")
	if copy == null:
		return
	assert_eq(copy.handwriting, "familiar", "字迹字段应随 Codec 往返")


func test_ending_letter_key_and_catalog_target_are_in_sync() -> void:
	var data := _data()
	assert_not_null(data, "DataRegistry 未就绪")
	if data == null:
		return
	var ending := data.get_def(GameState.ENDING_LETTER_KEY) as LetterDef
	assert_not_null(ending, "结局信应使用 GameState.ENDING_LETTER_KEY 指向的 key")
	if ending == null:
		return
	assert_eq(ending.order, 69, "结局信仍应是第 69 封")
	assert_eq(ending.condition, LetterDef.Condition.CATALOG_COUNT, "结局信仍按图鉴总数触发")
	assert_eq(ending.condition_value, GameState.get_ending_catalog_target(),
		"结局信里写的门槛应与当前图鉴总量算出的目标一致")
	assert_eq(GameState.get_catalog_target_for(ending), ending.condition_value,
		"结局信的实际门槛应走比例目标")
