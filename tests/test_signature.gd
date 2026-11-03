extends GutTest
## 招牌菜：玩家自选槽位、自动补位、存档往返与老档兼容。


func before_each() -> void:
	I18NManager.set_language("zh_CN")
	GameState.reset()


func after_each() -> void:
	GameState.reset()


func test_default_slots_are_empty() -> void:
	var slots := GameState.get_signature_slots()
	assert_eq(slots.size(), GameState.SIGNATURE_SLOTS, "招牌菜槽位数量应该固定")
	for key in slots:
		assert_eq(key, "", "新档的招牌菜槽位应该是空的（全部自动补位）")


func test_no_candidates_on_fresh_save() -> void:
	assert_true(GameState.get_signature_candidates().is_empty(), "还没做过菜时没有可上招牌的菜")


func test_rejects_undiscovered_dish() -> void:
	GameState.set_signature_slot(0, "game:item/espresso")
	assert_eq(GameState.get_signature_slots()[0], "", "没发现的菜不能上招牌")


func test_accepts_discovered_dish() -> void:
	GameState.discover("game:item/espresso")
	GameState.set_signature_slot(0, "game:item/espresso")
	assert_eq(GameState.get_signature_slots()[0], "game:item/espresso", "已发现的菜可以上招牌")


func test_same_dish_moves_between_slots() -> void:
	GameState.discover("game:item/espresso")
	GameState.set_signature_slot(0, "game:item/espresso")
	GameState.set_signature_slot(1, "game:item/espresso")
	var slots := GameState.get_signature_slots()
	assert_eq(slots[0], "", "同一道菜不该占两格")
	assert_eq(slots[1], "game:item/espresso", "菜应该挪到新槽位")


func test_clearing_a_slot_returns_to_auto() -> void:
	GameState.discover("game:item/espresso")
	GameState.set_signature_slot(0, "game:item/espresso")
	GameState.set_signature_slot(0, "")
	assert_eq(GameState.get_signature_slots()[0], "", "清空槽位后交回自动")


func test_candidates_sorted_by_price() -> void:
	GameState.discover("game:item/latte")
	GameState.discover("game:item/cake")
	var candidates := GameState.get_signature_candidates()
	assert_gte(candidates.size(), 2, "已发现两道菜时应该有两个候选")
	assert_eq(candidates[0].get_key(), "game:item/cake", "卖价最高的应排第一")
	assert_eq(candidates[1].get_key(), "game:item/latte", "卖价低的排后面")


func test_slots_survive_roundtrip() -> void:
	GameState.discover("game:item/espresso")
	GameState.set_signature_slot(2, "game:item/espresso")
	var data := GameState.to_dict()
	assert_eq(int(data.get("version", 0)), GameState.SAVE_VERSION, "存档版本应升到 4")
	GameState.reset()
	assert_true(GameState.restore_from_dict(data), "读档应该成功")
	assert_eq(GameState.get_signature_slots()[2], "game:item/espresso", "招牌菜应该随存档往返")


func test_old_v3_save_is_rejected() -> void:
	var old := {"version": 3, "coins": 0}
	assert_false(GameState.restore_from_dict(old), "v18 起不再读取 v3 存档")


func test_out_of_range_slot_is_ignored() -> void:
	GameState.discover("game:item/espresso")
	GameState.set_signature_slot(-1, "game:item/espresso")
	GameState.set_signature_slot(9, "game:item/espresso")
	for key in GameState.get_signature_slots():
		assert_eq(key, "", "越界槽位应被忽略")


func test_invalid_save_entries_are_filtered() -> void:
	var data := {
		"version": GameState.SAVE_VERSION,
		"coins": 0,
		"discovered": ["game:item/espresso"],
		"signature_dishes": ["game:item/espresso", "game:item/espresso", "game:item/cake"],
	}
	assert_true(GameState.restore_from_dict(data), "带招牌菜的存档应该能读")
	var slots := GameState.get_signature_slots()
	assert_eq(slots[0], "game:item/espresso", "有效的招牌菜保留")
	assert_eq(slots[1], "", "重复的菜要清掉")
	assert_eq(slots[2], "", "没发现的菜要清掉")
