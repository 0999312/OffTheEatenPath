class_name OfflinePanel
extends GamePanel
## 离线结算（POPUP 层）：回到游戏那一刻，把「离开的这段时间长了什么」交代清楚。
##
## 不是设置页，也不常驻：由 GameBridge 在启动时结算一次，带 summary 打开；
## 没解锁 / 离开太短 / 什么都没长，都不会弹。
##
## 清单逐条浮出来、数字从 0 滚到实际值（短、不抢戏；总时长压在 0.6 秒内）。
## 之所以不做「过场动画 / 场景切换」：这套界面是纸面极简，多一层演出反而打断节奏，
## 而且过场要接管暂停与恢复，收益不抵成本。

const STAGGER_SECONDS := 0.06
const FADE_SECONDS := 0.14
const COUNT_SECONDS := 0.45

var _summary: OfflineSummary = null
var _rows: Array[Control] = []
var _counters: Array[Dictionary] = []
## 正在跑的浮出 / 滚数动画；重画前必须收掉，否则 tween 会打到已释放的节点
var _tweens: Array[Tween] = []


func _on_open(data: Dictionary = {}) -> void:
	_summary = data.get("summary") as OfflineSummary
	if _summary == null:
		push_warning("[OfflinePanel] 没有带结算数据，直接关闭")
		close_self()
		return
	set_title(I18n.t("ui.offline.title"))
	set_subtitle(_summary.elapsed_text())
	super._on_open(data)
	_build()
	_play_reveal()


func refresh() -> void:
	pass


## 切语言时**就地重画**：收掉正在跑的动画 → 重建文案 → 直接把行和数字落到终值。
## 不重播浮出动画：玩家已经在读这份账单了，再来一遍反而像卡了一下。
func _on_language_changed(_event: Event) -> void:
	super._on_language_changed(_event)
	if _summary == null:
		return
	_kill_tweens()
	set_title(I18n.t("ui.offline.title"))
	set_subtitle(_summary.elapsed_text())
	_build()
	_settle()


func _build() -> void:
	clear_content()
	PanelKit.clear(footer)
	_rows.clear()
	_counters.clear()
	_build_footer()
	if not _summary.offline_unlocked:
		content.add_child(PanelKit.hint(I18n.t("ui.offline.locked"), 640))
		return
	if not _summary.has_gains():
		content.add_child(PanelKit.hint(I18n.t("ui.offline.nothing"), 640))
		return
	for gain in _summary.gains:
		var row := _gain_row(String(gain.get("key", "")), String(gain["name"]), int(gain["delta"]))
		content.add_child(row)
	if _summary.coins_gained > 0:
		content.add_child(PanelKit.divider())
		content.add_child(_gain_row("", I18n.t("ui.offline.tips"), _summary.coins_gained))
	if _summary.orders_refreshed > 0:
		content.add_child(PanelKit.hint(I18n.t("ui.offline.orders", [_summary.orders_refreshed]), 640))
	if not _summary.letter_keys.is_empty():
		content.add_child(PanelKit.divider())
		content.add_child(PanelKit.hint(I18n.t("ui.offline.letters", [_summary.letter_keys.size()]), 640))


## 这张纸上只有几行字，面板下面空着一大半，眼睛没地方停——底部给一个落点。
##「收下」不是领奖（收益在打开面板之前就结算了），它是「看完了，继续」的确认动作。
func _build_footer() -> void:
	if not _summary.has_gains():
		return
	var action := PanelKit.hbox(10)
	action.add_child(PanelKit.spacer())
	var take := PanelKit.primary_button(I18n.t("ui.offline.take"), Sfx.Intent.NONE, 44.0)
	take.custom_minimum_size.x = 150.0
	take.pressed.connect(close_self)
	action.add_child(take)
	footer.add_child(action)

## 条目名优先按 key 现翻（结算时缓存的那串是当时的语言），取不到才用缓存名
func _gain_row(key: String, name: String, delta: int) -> HBoxContainer:
	var row := PanelKit.hbox(10)
	row.add_child(PanelKit.label(_gain_name(key, name), 19))
	row.add_child(PanelKit.spacer())
	var value := PanelKit.label("+0", 19, PanelKit.ACCENT_DEEP)
	row.add_child(value)
	row.modulate.a = 0.0
	_rows.append(row)
	_counters.append({"label": value, "value": delta})
	return row


## 直接定格到动画结束时的样子（切语言重画用）
func _settle() -> void:
	for row in _rows:
		if is_instance_valid(row):
			row.modulate.a = 1.0
	for entry in _counters:
		var label := entry["label"] as Label
		if is_instance_valid(label):
			label.text = "+%s" % PanelKit.big_number_text(int(entry["value"]))


func _kill_tweens() -> void:
	for tween in _tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_tweens.clear()


func _gain_name(key: String, fallback: String) -> String:
	if key.is_empty():
		return fallback
	return I18n.t(I18n.key_for(key, &"display_name"))


func _play_reveal() -> void:
	if _rows.is_empty():
		return
	var reveal := create_tween()
	_tweens.append(reveal)
	for index in _rows.size():
		reveal.tween_interval(STAGGER_SECONDS)
		reveal.tween_property(_rows[index], "modulate:a", 1.0, FADE_SECONDS)
	for index in _counters.size():
		var entry := _counters[index]
		var label := entry["label"] as Label
		if label == null:
			continue
		var target := float(entry["value"])
		var count := create_tween()
		_tweens.append(count)
		count.tween_interval(STAGGER_SECONDS * float(index))
		count.tween_method(
			func(value: float) -> void:
				label.text = "+%s" % PanelKit.big_number_text(int(round(value))),
			0.0,
			target,
			COUNT_SECONDS
		)
