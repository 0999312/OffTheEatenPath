class_name GameBridge
extends Node
## 玩法与界面之间的「接线工人」：推动时间、读写存档、统一面板入口。
##
## 为什么需要它：GameState 是被动的（只提供 advance / API），总得有人每帧推动它；
## UIManager 只认 ID，总得有人把「按了个按钮」「按了个键」翻译成 open_panel。
## 这些都放在场景里的一个节点上，而不是塞进 GameState（自动加载不该知道帧率与窗口）
## 或每个面板里（面板之间会互相耦合）。

## 时间推进的步长：10Hz 足够让秒级配方分档推进，又不至于每帧遍历定义
const TICK_INTERVAL := 0.1
## 自动存档间隔（秒）
const AUTOSAVE_INTERVAL := 20.0
## 提示停留时间（秒）
const TOAST_SECONDS := 2.4

## 音效统一走 `Sfx` 意图表（`scripts/systems/sfx.gd`），这里不再 preload 具体文件

## 存档器（路径可在测试里替换）
var save: SaveGame = SaveGame.new()
## 启动时结算出的离线摘要；没有值得展示的内容时为 null
var pending_offline: OfflineSummary = null

var _tick_accumulator := 0.0
var _autosave_accumulator := 0.0


func _ready() -> void:
	_restore_or_start()
	_connect_feedback()
	call_deferred("_open_offline_panel_if_needed")
	set_process(true)


func _exit_tree() -> void:
	EventBus.unsubscribe(&"CraftCompletedEvent", _on_craft_completed)
	EventBus.unsubscribe(&"LetterUnlockedEvent", _on_letter_unlocked)
	EventBus.unsubscribe(&"FacilityUpgradedEvent", _on_facility_upgraded)
	EventBus.unsubscribe(&"ResearchCompletedEvent", _on_research_completed)
	EventBus.unsubscribe(&"RecipeUnlockedEvent", _on_recipe_unlocked)
	EventBus.unsubscribe(&"MilestoneReachedEvent", _on_milestone_reached)
	EventBus.unsubscribe(&"CoinPickedEvent", _on_coin_picked)
	EventBus.unsubscribe(&"TaskCompletedEvent", _on_task_completed)
	save_now()


func _process(delta: float) -> void:
	_tick_accumulator += delta
	if _tick_accumulator >= TICK_INTERVAL:
		GameState.advance(_tick_accumulator)
		_tick_accumulator = 0.0
	_autosave_accumulator += delta
	if _autosave_accumulator >= AUTOSAVE_INTERVAL:
		_autosave_accumulator = 0.0
		save_now()


# --- 完成反馈（提示 + 音效） ----------------------------------------------


## 只订阅「值得说一声」的事件：做完东西、收到信、设备升级。
## 铜币变化不弹提示（每做一份食物都会响一次，太吵），留给 HUD 数字；
## 唯一的例外是玩家亲手点走桌角的铜板（CoinPickedEvent），那是他自己伸手要的。
func _connect_feedback() -> void:
	EventBus.subscribe(&"CraftCompletedEvent", _on_craft_completed)
	EventBus.subscribe(&"LetterUnlockedEvent", _on_letter_unlocked)
	EventBus.subscribe(&"FacilityUpgradedEvent", _on_facility_upgraded)
	EventBus.subscribe(&"ResearchCompletedEvent", _on_research_completed)
	EventBus.subscribe(&"RecipeUnlockedEvent", _on_recipe_unlocked)
	EventBus.subscribe(&"MilestoneReachedEvent", _on_milestone_reached)
	EventBus.subscribe(&"CoinPickedEvent", _on_coin_picked)
	EventBus.subscribe(&"TaskCompletedEvent", _on_task_completed)


func _on_craft_completed(event: Event) -> void:
	var done := event as CraftCompletedEvent
	if done == null:
		return
	# 半成品也要有「这一炉出来了」的声音；toast 只留给端得上桌的成品菜。
	Sfx.play(Sfx.Intent.CRAFT_DONE)
	if not done.is_food:
		return
	var def := _def_of(done.output_key)
	var spec := {"key": "ui.toast.crafted", "args": [_name_arg(def, "ui.table.thing")]}
	if done.first_time:
		spec["suffix"] = {
			"key": "ui.toast.crafted_first",
			"args": [GameState.get_coins_per_first_food()],
		}
	_show_toast(spec, true)


func _on_letter_unlocked(event: Event) -> void:
	var unlocked := event as LetterUnlockedEvent
	if unlocked == null:
		return
	_show_toast({"key": "ui.toast.letter", "args": [_letter_title_arg(unlocked)]}, true)
	Sfx.play(Sfx.Intent.LETTER)


func _on_facility_upgraded(event: Event) -> void:
	var upgraded := event as FacilityUpgradedEvent
	if upgraded == null:
		return
	var def := _def_of(upgraded.facility_key)
	_show_toast({
		"key": "ui.toast.facility_upgraded",
		"args": [_name_arg(def, "ui.common.device"), upgraded.level],
	}, false)
	Sfx.play(Sfx.Intent.UPGRADE)


## 研究出结果：成功的喜报由「配方解锁」那条发，这里只处理没成的
func _on_research_completed(event: Event) -> void:
	var completed := event as ResearchCompletedEvent
	if completed == null:
		return
	if completed.succeeded:
		return
	# 研究结论是「材料 + 结果」拼出来的整句，交个重建函数最省事：
	# 切语言时它会连同材料名一起重拼
	var signature := completed.signature
	_show_toast({"build": func() -> String: return GameState.describe_research(signature)}, false)
	Sfx.play(Sfx.Intent.RESEARCH_FAIL)


func _on_recipe_unlocked(event: Event) -> void:
	var unlocked := event as RecipeUnlockedEvent
	if unlocked == null:
		return
	var def := _def_of(unlocked.recipe_key)
	_show_toast({"key": "ui.toast.recipe_unlocked", "args": [_name_arg(def, "ui.common.new_recipe")]}, true)
	Sfx.play(Sfx.Intent.RESEARCH_OK)


## 图鉴跨过一档：报一句进度 + 铜币（pay 为 false 的情况下只是静默对齐档位，不该响）
func _on_milestone_reached(event: Event) -> void:
	var reached := event as MilestoneReachedEvent
	if reached == null or reached.coins_granted <= 0:
		return
	_show_toast({"key": "ui.toast.milestone", "args": [reached.coins_granted]}, true)
	Sfx.play(Sfx.Intent.MILESTONE)


## 委托办妥：信里应下的那件事做完了，报酬已经进账，这里补一句
func _on_task_completed(event: Event) -> void:
	var done := event as TaskCompletedEvent
	if done == null:
		return
	var def := _def_of(done.letter_key) as LetterDef
	if def == null:
		return
	# 委托标题也是翻译键；万一没写，退回信自己的标题键
	var title_key := def.task_title if not def.task_title.is_empty() else def.title
	_show_toast({"key": "ui.toast.task_done", "args": [{"t": title_key}]}, true)
	Sfx.play(Sfx.Intent.ORDER_DONE)


## 玩家亲手点走桌角铜板：数字已经进账，这里只补一句轻的（不打断手头的事）
func _on_coin_picked(event: Event) -> void:
	var picked := event as CoinPickedEvent
	if picked == null:
		return
	_show_toast({"key": "ui.toast.coin_picked", "args": [picked.amount]}, false)


## 弹一条提示；同时有多条时只留最新的（提示不是流水账，旧的没必要排队）
##
## `spec` 传的是**文案配方**（`{"key", "args"}` / `{"build", Callable}`），不是成品字符串：
## 提示在屏幕上停留期间可能被切语言，ToastMessage 会拿同一份配方就地重翻。
func _show_toast(spec: Dictionary, accent: bool) -> void:
	var toast_id := ResourceLocation.from_string(UIKeys.TOAST_MESSAGE)
	if toast_id == null:
		return
	var data := spec.duplicate(true)
	data["accent"] = accent
	UIManager.dismiss_all_toasts()
	UIManager.show_toast(toast_id, data, TOAST_SECONDS)


## 条目名也当翻译键传下去；取不到定义时退回一句通用文案
func _name_arg(def: GameDef, fallback_key: String) -> Variant:
	if def == null:
		return {"t": fallback_key}
	return {"t": def.display_name}


## 信件标题的键（`LetterDef.title` 存的就是键），取不到就退回事件里那串已翻好的字
func _letter_title_arg(unlocked: LetterUnlockedEvent) -> Variant:
	var def := _def_of(unlocked.letter_key)
	if def != null and not def.title.is_empty() and def.title.begins_with("data."):
		return {"t": def.title}
	return unlocked.title


func _def_of(key: String) -> GameDef:
	var registry := RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry
	if registry == null:
		return null
	return registry.get_def(key)


func _unhandled_input(event: InputEvent) -> void:
	# 光标在输入框里时，键盘归输入框：m/c/o/r 这些字母要能打进搜索词，
	# 不能顺手把面板切走（第七轮反馈 12）。只留 Esc 关面板——那是玩家的退路。
	# 鼠标不拦：点别处仍能改焦点、点面板外仍能取消。
	if event is InputEventKey and _text_input_has_focus():
		if event.is_action_pressed("ui_cancel"):
			_close_top_panel_from_input()
		return
	if event.is_action_pressed("panel_craft"):
		toggle_panel(UIKeys.CRAFT)
	elif event.is_action_pressed("panel_catalog"):
		toggle_panel(UIKeys.CATALOG)
	elif event.is_action_pressed("panel_facility"):
		toggle_panel(UIKeys.FACILITY)
	elif event.is_action_pressed("panel_merchant"):
		toggle_panel(UIKeys.MERCHANT)
	elif event.is_action_pressed("panel_mail"):
		toggle_panel(UIKeys.MAIL)
	elif event.is_action_pressed("panel_research"):
		toggle_panel(UIKeys.RESEARCH)
	elif event.is_action_pressed("panel_settings"):
		toggle_panel(UIKeys.SETTINGS)
	elif event.is_action_pressed("ui_cancel"):
		_close_top_panel_from_input()
	elif event.is_action_pressed("ui_back"):
		# 右键 = 返回（第七轮反馈 20）。只有 GUI 没吃掉的右键才会走到这里，
		# 所以输入框自己的右键菜单、弹窗里的右键都安全。
		_close_top_panel_from_input()


## 焦点是否落在单行/多行文本输入里。CodeEdit 继承 TextEdit，一并算上。
func _text_input_has_focus() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


## Esc 的统一退路：先关弹窗，再关普通面板；都没开就什么都不做
func _close_top_panel_from_input() -> void:
	if UIManager.get_top_panel(UILayer.POPUP) != null:
		_close_top_panel(UILayer.POPUP)
	elif UIManager.get_top_panel(UILayer.NORMAL) != null:
		_close_top_panel(UILayer.NORMAL)


# --- 存档与离线 -----------------------------------------------------------


## 有存档就恢复并结算离开时间，没有就开新档
##
## 恢复分两道：`SaveGame` 只保证「读得出结构」，能不能迁移旧版本由 `GameState` 说了算。
## 所以主档虽然能解析、但版本不认识时，还要再用备份试一次——常见于「升版本后第一次启动」。
##
## v10 起旧档一律拒绝（键从 food/、material/ 统一成 item/，逐条改名不划算）：
## 两道都读不进来时不静默开新局：先把旧档另存一份，再弹一次「不兼容」的提示。
func _restore_or_start() -> void:
	var data := save.load_state()
	if not data.is_empty() and GameState.restore_from_dict(data):
		_resume_from_saved_state()
		return
	if save.has_backup():
		var backup := save.load_backup()
		if not backup.is_empty() and GameState.restore_from_dict(backup):
			push_warning("[GameBridge] 主档无法迁移，已改用备份存档")
			_resume_from_saved_state()
			return
	# 走到这里说明主档与备份都迁移不了。新档第一次自动存档就会覆盖主档，
	# 所以先把旧档另存一份，再尽量让玩家看见——不能静默丢档。
	if not data.is_empty():
		var version := int(data.get("version", 0))
		var kept := save.preserve("v%d" % version)
		push_warning("[GameBridge] 存档读不进来（v%d，版本超范围或含 v10 之前的物品键），已开新局：%s" % [version, save.path])
		if not kept.is_empty():
			push_warning("[GameBridge] 旧档已另存：%s" % kept)
		_notify_unreadable_save(version, kept)
	elif save.exists():
		var kept_corrupt := save.preserve("corrupt")
		if not kept_corrupt.is_empty():
			push_warning("[GameBridge] 存档损坏，已另存现场：%s" % kept_corrupt)
		_notify_unreadable_save(0, kept_corrupt)
	GameState.reset()
	GameState.last_seen_unix = 0


## 旧档读不动时的玩家可见提示。headless / 无窗口环境跳过，只留日志。
##
## 这里刻意不新增 i18n key：这条提示只在版本断代时出现一次，中英双语写死比
## 让 16 个语言文件各加一条（并牵动 3039 计数与生成检查）划算。
func _notify_unreadable_save(version: int, kept: String) -> void:
	if kept.is_empty() or DisplayServer.get_name() == "headless":
		return
	var where := ProjectSettings.globalize_path(kept)
	var zh := ""
	var en := ""
	if version > 0:
		zh = "存档版本 v%d 与当前版本不兼容，本次将以新档开始。\n旧档已另存一份，没有删除：\n%s" % [version, where]
		en = "This save (v%d) is not compatible and a new game will start.\nYour old save was kept at:\n%s" % [version, where]
	else:
		zh = "存档无法读取（可能已损坏），本次将以新档开始。\n原文件已另存一份，没有删除：\n%s" % where
		en = "This save could not be read and a new game will start.\nA copy of the old file was kept at:\n%s" % where
	OS.alert("%s\n\n%s" % [zh, en], "存档不兼容 / Incompatible Save")


## 恢复成功后按「上次离开时间」补上离线产出
func _resume_from_saved_state() -> void:
	var last_seen := GameState.last_seen_unix
	if last_seen <= 0:
		return
	var now := int(Time.get_unix_time_from_system())
	var elapsed := maxf(float(now - last_seen), 0.0)
	if elapsed <= 0.0:
		return
	pending_offline = GameState.apply_offline(elapsed)


## 立刻落盘
func save_now() -> void:
	GameState.last_seen_unix = int(Time.get_unix_time_from_system())
	var error := save.save_state(GameState.to_dict())
	if error != OK:
		push_error("[GameBridge] 存档写入失败（错误码 %d）：%s" % [error, save.path])


## 回游戏那一刻把离线收益交代清楚（没解锁 / 时间太短 / 没产出都不打扰）
func _open_offline_panel_if_needed() -> void:
	if pending_offline == null or not pending_offline.is_meaningful():
		pending_offline = null
		return
	UIManager.open_panel(ResourceLocation.from_string(UIKeys.OFFLINE), {"summary": pending_offline})


func take_pending_offline() -> OfflineSummary:
	var summary := pending_offline
	pending_offline = null
	return summary


# --- 面板入口 -------------------------------------------------------------


## 还没开放的入口：商人等杂货商人的信，订单板等第九封信（离店）。
## 状态由已读信件派生，不加存档键；旧档按 read_letters 自动正确。
func _locked_panel(panel_id: String) -> bool:
	if panel_id == UIKeys.MERCHANT and not GameState.is_merchant_unlocked():
		_show_toast({"key": "ui.toast.merchant_locked"}, false)
		return true
	if panel_id == UIKeys.ORDERS and not GameState.is_orders_unlocked():
		_show_toast({"key": "ui.toast.orders_locked"}, false)
		return true
	return false


## 打开面板；已经打开则关闭（同一个按钮按两次 = 收起来）
func toggle_panel(panel_id: String) -> void:
	var location := ResourceLocation.from_string(panel_id)
	if location == null:
		push_error("[GameBridge] 面板 ID 非法：%s" % panel_id)
		return
	if _locked_panel(panel_id):
		return
	if UIManager.is_panel_open(location):
		# 只有「要关的就是当前可见的栈顶面板」才播收场动画；
		# 被弹窗压着或不是栈顶时直接出栈，避免把看不见的纸淡掉。
		var top: Variant = UIManager.get_top_panel(UILayer.NORMAL)
		if UIManager.get_top_panel(UILayer.POPUP) == null and top is GamePanel \
				and (top as GamePanel).panel_id.equals(location):
			(top as GamePanel).request_close()
		else:
			UIManager.close_panel(location)
		return
	UIManager.open_panel(location)


## Esc：有收场动画的面板走 request_close，其余保持框架原来的同步关闭
func _close_top_panel(layer: int) -> void:
	var top: Variant = UIManager.get_top_panel(layer)
	if top == null:
		return
	if top is GamePanel:
		(top as GamePanel).request_close()
	else:
		UIManager.back(layer)


## 带参数打开（信件详情、离线结算这类弹窗用）
func open_panel(panel_id: String, data: Dictionary = {}) -> void:
	var location := ResourceLocation.from_string(panel_id)
	if location == null:
		push_error("[GameBridge] 面板 ID 非法：%s" % panel_id)
		return
	if _locked_panel(panel_id):
		return
	UIManager.open_panel(location, data)
