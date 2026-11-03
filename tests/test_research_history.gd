extends GutTest
## 研究记录与首启引导（P10.4 / 决策 D10）：历史顺序、20 条上限、存档往返、
## 引导标志，以及老档缺字段时按结论表补齐。
##
## 历史直接灌 `_complete_research`（真实收口）而不是走公开流程试 21 次：
## 真配方一旦试成就会被解锁、候选池随之变化，测不出「上限」这条边界。

const MILK := "game:item/milk"
const SUGAR := "game:item/sugar"


func before_each() -> void:
	GameState.reset()


## 灌 n 条失败的历史记录（签名 sig_0 … sig_n-1，最新最后灌）
func _populate_history(count: int) -> void:
	for index in count:
		var job := ResearchJob.new()
		job.signature = "sig_%d" % index
		job.materials.assign([MILK, SUGAR])
		job.outcome = GameState.ResearchOutcome.MISMATCH
		job.succeeded = false
		job.total_seconds = 4.0
		GameState._complete_research(job)


# --- 历史列表 -------------------------------------------------------------

func test_history_lists_newest_first() -> void:
	_populate_history(3)
	var history := GameState.get_research_history()
	assert_eq(history.size(), 3, "三条都在")
	assert_eq(String(history[0].get("signature")), "sig_2", "最新的在最上面")
	assert_eq(String(history[2].get("signature")), "sig_0", "最旧的在最下面")
	assert_eq(history[0].get("materials", []).size(), 2, "记下用了哪几样")
	assert_gt(float(history[0].get("seconds", 0.0)), 0.0, "记下用时")


func test_history_keeps_only_the_last_twenty() -> void:
	_populate_history(GameState.RESEARCH_HISTORY_LIMIT + 1)
	var history := GameState.get_research_history()
	assert_eq(history.size(), GameState.RESEARCH_HISTORY_LIMIT, "最多留 20 条")
	assert_eq(String(history[0].get("signature")), "sig_20", "最新的还在")
	assert_eq(String(history[history.size() - 1].get("signature")), "sig_1", "最旧的那条被挤掉")
	assert_eq(GameState.get_research_record_count(), 21, "结论表本身不受 20 条上限影响")


# --- 存档往返 -------------------------------------------------------------

func test_history_and_guide_round_trip_through_save() -> void:
	_populate_history(2)
	GameState.mark_research_guide_seen()
	var data := GameState.to_dict()
	assert_eq((data.get("research_history", []) as Array).size(), 2, "存档带上历史")
	assert_true(bool(data.get("research_guide_seen", false)), "存档带上引导标志")

	GameState.reset()
	assert_eq(GameState.get_research_history().size(), 0, "reset 清历史")
	assert_false(GameState.has_seen_research_guide(), "reset 清引导标志")

	assert_true(GameState.restore_from_dict(data), "存档应能恢复")
	var history := GameState.get_research_history()
	assert_eq(history.size(), 2, "恢复两条")
	assert_eq(String(history[0].get("signature")), "sig_1", "恢复后顺序不变")
	assert_eq(history[0].get("materials", []).size(), 2, "材料也恢复")
	assert_true(GameState.has_seen_research_guide(), "引导标志恢复")


func test_old_save_without_history_is_rebuilt_from_records() -> void:
	_populate_history(2)
	var data := GameState.to_dict()
	data.erase("research_history")
	data.erase("research_guide_seen")

	GameState.reset()
	assert_true(GameState.restore_from_dict(data), "缺字段的老档照读")
	assert_eq(GameState.get_research_history().size(), 2, "老档按结论表补齐历史")
	assert_false(GameState.has_seen_research_guide(), "缺字段时默认没看过")


# --- 设置页重看 -----------------------------------------------------------

func test_reset_guide_brings_it_back() -> void:
	GameState.mark_research_guide_seen()
	assert_true(GameState.has_seen_research_guide())
	GameState.reset_research_guide()
	assert_false(GameState.has_seen_research_guide(), "重看后下次打开会再弹")
