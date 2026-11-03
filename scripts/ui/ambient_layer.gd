class_name AmbientLayer
extends Control
## 房间里「没有角色」的来访痕迹：贴在屏幕边缘的一张长便条、桌上偶尔多出的一枚铜板。
##
## 为什么不做成 NPC / 对话框：这款游戏的叙事是留白的，人物一旦开口就会变成任务系统。
## 这里只做「别人来过」的物证——不解释是谁、不记录次数、不给奖励，也不参与存档。
##
## 两种触发：
## 1. 交付订单 → 过一会儿桌上多出一枚铜板（有人吃完、付了钱）
## 2. 随机时刻 → 桌面上另一个随机位置再出现一枚铜板
## 物证只用铜板、不放杯子：杯子太像「有人坐过」，铜板更像路过的人留下的。
## 声音可以留——纸铃（VISIT）与杯碟轻碰（DISH_CLINK）只交代「有人来过、吃完了」，不加第二个物件。
## 痕迹是纯装饰：mouse_filter 全部 IGNORE，不挡任何点击，也不改变 GameState。
##
## 例外是那张长便条：它是招牌菜的唯一入口（决策 2026-10-28 D8）。
## 点便条弹出「不设 / 第 1–3 道」，选一档再挑菜，或交给自动补位。
## 之所以从设置页搬到这里：招牌菜是玩家在桌面上做的决定，却藏在设置页第三层，
## 三轮试玩里没人找到过。便条本身显示当前写了哪几道，选完立刻能看见。

const EVENT_ORDER := &"OrderChangedEvent"
const EVENT_DISCOVERED := &"CatalogDiscoveredEvent"
const EVENT_CRAFT := &"CraftCompletedEvent"
const EVENT_RESTORED := &"StateRestoredEvent"
const EVENT_SIGNATURE := &"SignatureChangedEvent"
const EVENT_LANGUAGE := &"LanguageChangedEvent"

## 贴在上缘偏右的长便条：两端各压一条胶带，纸面微微歪一点
const SIGN_POS := Vector2(596.0, 18.0)
const SIGN_SIZE := Vector2(448.0, 62.0)
## 便条是两端用胶带压住的纸：贴得略歪，但位置固定，不随风摆动
const SIGN_TILT_DEG := -0.8
## 便条上最多列几道招牌菜；多了只取卖价最高的几道
const SIGNATURE_LIMIT := 3

## 铜板落在桌面下半部的空白区：避开中间的「桌上空着」、去灶台按钮和左下角材料数。
## 每次出现都在这个矩形里随机取一个点，并随机转一个角度，像随手放在桌上的。
const COIN_AREA := Rect2(260.0, 420.0, 620.0, 120.0)
const COIN_SIZE := Vector2(40.0, 40.0)
## 普通痕迹停 8 秒；铜板要慢得多——它是一份「可以顺手点走」的小费，不是弹窗。
## 铜板在桌面待满 30 秒，最后 5 秒才渐隐（第四轮反馈：8 秒太快，来不及看见）。
const TRACE_HOLD := 8.0
const COIN_HOLD := 30.0
const COIN_FADE := 5.0
## 点走一枚铜板（或等它自己淡到消失）拿到的小费；一次只算一枚。
const COIN_REWARD := 1

var _sign: Control
var _sign_content: HBoxContainer
## 两级菜单：先选哪一档，再选哪道菜。菜单是 Window，不进便条布局，也不进存档。
var _slot_menu: PopupMenu
var _food_menu: PopupMenu
## 当前正在填的档位（0 起）；第二级菜单回来时用它
var _menu_slot := 0
var _traces: Dictionary = {}
var _trace_tweens: Dictionary = {}
var _visit_timer: Timer
var _coin_timer: Timer
var _coin_taken := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.randomize()
	_build_sign()
	_build_menus()
	_build_traces()
	EventBus.subscribe(EVENT_ORDER, _on_order_changed)
	EventBus.subscribe(EVENT_DISCOVERED, _on_sign_content_changed)
	EventBus.subscribe(EVENT_CRAFT, _on_craft_completed)
	EventBus.subscribe(EVENT_RESTORED, _on_sign_content_changed)
	EventBus.subscribe(EVENT_SIGNATURE, _on_sign_content_changed)
	# 招牌上的字全是翻译文案：切语言时整块重建，否则会停在旧语言。
	EventBus.subscribe(EVENT_LANGUAGE, _on_sign_content_changed)
	_visit_timer = Timer.new()
	_visit_timer.name = "VisitTimer"
	_visit_timer.one_shot = true
	_visit_timer.timeout.connect(_on_visit)
	add_child(_visit_timer)
	# 第一次早一点，让玩家知道「这里会有动静」；之后放得很稀
	_visit_timer.start(_rng.randf_range(26.0, 40.0))
	# 交付后过一会儿才放下铜板：人吃完、付钱、离开，不是同时发生的
	_coin_timer = Timer.new()
	_coin_timer.one_shot = true
	_coin_timer.wait_time = 0.9
	_coin_timer.timeout.connect(_on_coin_arrived)
	add_child(_coin_timer)

func _exit_tree() -> void:
	EventBus.unsubscribe(EVENT_ORDER, _on_order_changed)
	EventBus.unsubscribe(EVENT_DISCOVERED, _on_sign_content_changed)
	EventBus.unsubscribe(EVENT_CRAFT, _on_craft_completed)
	EventBus.unsubscribe(EVENT_RESTORED, _on_sign_content_changed)
	EventBus.unsubscribe(EVENT_SIGNATURE, _on_sign_content_changed)
	EventBus.unsubscribe(EVENT_LANGUAGE, _on_sign_content_changed)


# --- 长便条招牌 -----------------------------------------------------------


func _build_sign() -> void:
	_sign = Control.new()
	_sign.name = "Sign"
	_sign.position = SIGN_POS
	_sign.size = SIGN_SIZE
	_sign.pivot_offset = SIGN_SIZE * 0.5
	# 便条接住点击：整层仍是 IGNORE，只有这一块纸挡鼠标（决策 2026-10-28 D8）
	_sign.mouse_filter = Control.MOUSE_FILTER_STOP
	_sign.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_sign.gui_input.connect(_on_sign_input)
	_sign.rotation = deg_to_rad(SIGN_TILT_DEG)
	add_child(_sign)

	var board := PanelContainer.new()
	board.name = "Board"
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := PanelKit.slab(Color(0.972, 0.945, 0.870), PanelKit.INK, 3, 1)
	style.content_margin_left = 14.0
	style.content_margin_top = 4.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 4.0
	style.shadow_color = Color(0.07, 0.11, 0.16, 0.16)
	style.shadow_size = 3
	style.shadow_offset = Vector2(2, 3)
	board.add_theme_stylebox_override("panel", style)
	_sign.add_child(board)

	_sign_content = HBoxContainer.new()
	_sign_content.name = "SignatureDishes"
	_sign_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_sign_content.add_theme_constant_override("separation", 7)
	_sign_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(_sign_content)

	_add_tape(-14.0, -6.0)
	_add_tape(SIGN_SIZE.x - 44.0, 13.0)
	_refresh_sign()


## 半透明胶带：把纸「贴」在屏幕边缘，而不是挂起来
func _add_tape(x: float, angle: float) -> void:
	var tape := Panel.new()
	tape.name = "Tape"
	tape.position = Vector2(x, -6.0)
	tape.size = Vector2(58.0, 18.0)
	tape.rotation = deg_to_rad(angle)
	tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := PanelKit.slab(Color(0.985, 0.982, 0.950, 0.72), Color(0, 0, 0, 0), 1, 0)
	tape.add_theme_stylebox_override("panel", style)
	_sign.add_child(tape)


func _refresh_sign() -> void:
	if _sign_content == null:
		return
	PanelKit.clear(_sign_content)
	var foods := _signature_foods()
	_sign.tooltip_text = ""
	if foods.is_empty():
		_add_sign_text(I18n.t("ui.ambient.sign_title"), 16, PanelKit.INK)
		_add_sign_text(I18n.t("ui.ambient.sign_subtitle"), 9, PanelKit.INK_DIM)
		return

	# 手填的招牌是墨色；自动补位只负责把便条填满，用浅墨区分且不计菜系加成。
	var manual_keys := GameState.get_signature_slots()
	var has_auto := false
	_add_sign_text(I18n.t("ui.ambient.sign_label"), 10, PanelKit.ACCENT)
	_add_sign_divider()
	for i in foods.size():
		if i > 0:
			_add_sign_text("·", 13, PanelKit.INK_DIM)
		var is_manual := manual_keys.has(foods[i].get_key())
		if not is_manual:
			has_auto = true
		_add_sign_text(foods[i].localized(), 14, PanelKit.INK if is_manual else PanelKit.INK_DIM)
	if has_auto:
		_sign.tooltip_text = I18n.t("ui.ambient.sign_auto_tip")


func _add_sign_text(text: String, size: int, color: Color) -> void:
	var label := PanelKit.label(text, size, color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sign_content.add_child(label)


func _add_sign_divider() -> void:
	var line := ColorRect.new()
	line.color = Color(PanelKit.INK, 0.24)
	line.custom_minimum_size = Vector2(1.0, 20.0)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sign_content.add_child(line)


## 便条上写哪几道菜：先按玩家自选的槽位排（无效的跳过），空槽再用自动补位
## （已发现、有卖价，按市场价取前三）。不泄露未发现的菜。
func _signature_foods() -> Array[ItemDef]:
	var foods: Array[ItemDef] = []
	var taken: Dictionary = {}
	for key in GameState.get_signature_slots():
		if key.is_empty() or taken.has(key):
			continue
		var def := _food_by_key(key)
		if def == null:
			continue
		taken[key] = true
		foods.append(def)
	for food in _auto_signature_foods(taken):
		if foods.size() >= SIGNATURE_LIMIT:
			break
		foods.append(food)
	return foods


## 自动补位的菜：从图鉴里已发现、有卖价的菜按卖价降序取，跳过玩家已选走的
func _auto_signature_foods(exclude: Dictionary) -> Array[ItemDef]:
	var registry := RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry
	if registry == null:
		return []
	var foods: Array[ItemDef] = []
	for def in registry.get_defs_of_type("item"):
		var food := def as ItemDef
		if food == null or not food.is_food() or food.sell_price <= 0:
			continue
		if exclude.has(food.get_key()):
			continue
		if not GameState.is_discovered(food.get_key()):
			continue
		foods.append(food)
	foods.sort_custom(func(a: ItemDef, b: ItemDef) -> bool:
		if a.sell_price == b.sell_price:
			return a.order < b.order
		return a.sell_price > b.sell_price
	)
	return foods


func _food_by_key(key: String) -> ItemDef:
	var registry := RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry
	if registry == null:
		return null
	var def := registry.get_def(key) as ItemDef
	return def if def != null and def.is_food() else null


func _on_craft_completed(event: Event) -> void:
	var done := event as CraftCompletedEvent
	if done != null and done.is_food:
		_refresh_sign()


func _on_sign_content_changed(_event: Event) -> void:
	_refresh_sign()


## 当前便条上写了什么（给测试与调试用）
func get_signature_names() -> Array[String]:
	var names: Array[String] = []
	for food in _signature_foods():
		names.append(food.localized())
	return names


# --- 招牌菜菜单 -----------------------------------------------------------


## 便条是招牌菜的唯一入口：点它先选档位，再选菜（决策 2026-10-28 D8）。
## 用两级 PopupMenu 而不是把三个下拉留回设置页：同一份状态两个入口，
## 以后总会有一边忘了同步（设置页里的那三个已经删掉了）。
func _build_menus() -> void:
	_slot_menu = PopupMenu.new()
	_slot_menu.name = "SlotMenu"
	_slot_menu.id_pressed.connect(_on_slot_menu_id)
	add_child(_slot_menu)
	_food_menu = PopupMenu.new()
	_food_menu.name = "FoodMenu"
	_food_menu.id_pressed.connect(_on_food_menu_id)
	add_child(_food_menu)


func _on_sign_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_slot_menu()
		accept_event()


func _open_slot_menu() -> void:
	if _slot_menu == null:
		return
	Sfx.play(Sfx.Intent.TAB)
	_slot_menu.clear()
	_slot_menu.add_item(I18n.t("ui.ambient.sign_clear"), 0)
	for slot in GameState.SIGNATURE_SLOTS:
		_slot_menu.add_item(I18n.t("ui.ambient.sign_slot", [slot + 1]), slot + 1)
	_popup_under_sign(_slot_menu)


func _on_slot_menu_id(id: int) -> void:
	if id == 0:
		_clear_signature()
		return
	_menu_slot = clampi(id - 1, 0, GameState.SIGNATURE_SLOTS - 1)
	_open_food_menu()


## 第二级：只有「自动」+ 已发现、有卖价的菜；未发现的不列，别在菜单里剧透
func _open_food_menu() -> void:
	if _food_menu == null:
		return
	Sfx.play(Sfx.Intent.TAB)
	_food_menu.clear()
	_food_menu.add_item(I18n.t("ui.ambient.sign_auto"), 0)
	for food in GameState.get_signature_candidates():
		_food_menu.add_item(food.localized(), _food_menu.item_count)
	_popup_under_sign(_food_menu)


func _on_food_menu_id(id: int) -> void:
	var candidates := GameState.get_signature_candidates()
	var key := ""
	if id > 0 and id <= candidates.size():
		key = candidates[id - 1].get_key()
	GameState.set_signature_slot(_menu_slot, key)


## 「不设」把三档一起清空：空档本来就靠自动补位，逐档清反而要按三次
func _clear_signature() -> void:
	for slot in GameState.SIGNATURE_SLOTS:
		GameState.set_signature_slot(slot, "")


## 菜单贴着便条下沿弹出；按钮用的是旋转控件，取它的全局矩形才不会落在胶带外面
func _popup_under_sign(menu: PopupMenu) -> void:
	var rect := _sign.get_global_rect()
	var at := Vector2i(int(rect.position.x), int(rect.end.y + 4.0))
	menu.reset_size()
	menu.popup(Rect2i(at, Vector2i.ZERO))


# --- 痕迹 -----------------------------------------------------------------


func _build_traces() -> void:
	_add_trace("coin", _make_coin())


func _add_trace(kind: String, visual: Control) -> void:
	var trace := Control.new()
	trace.name = kind.capitalize()
	trace.position = COIN_AREA.position
	trace.size = COIN_SIZE
	trace.pivot_offset = trace.size * 0.5
	# 铜板可以点：这是整层里唯一接鼠标的东西，别的痕迹都不挡点击。
	if kind == "coin":
		trace.mouse_filter = Control.MOUSE_FILTER_STOP
		trace.gui_input.connect(_on_coin_input)
	else:
		trace.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trace.visible = false
	trace.modulate.a = 0.0
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	trace.add_child(visual)
	add_child(trace)
	_traces[kind] = trace


func _make_coin() -> Control:
	var coin := CoinIcon.new()
	coin.custom_minimum_size = COIN_SIZE
	coin.hole_color = PanelKit.CARD
	return coin


## 让一种痕迹出现：淡入、停一会儿、淡出。再次触发会从头计时。
func show_trace(kind: String) -> void:
	if not _traces.has(kind):
		return
	var trace := _traces[kind] as Control
	if trace == null:
		return
	if _trace_tweens.has(kind):
		var old := _trace_tweens[kind] as Tween
		if old != null and old.is_valid():
			old.kill()
	if kind == "coin":
		_coin_taken = false
	trace.visible = true
	trace.modulate.a = 0.0
	trace.position = Vector2(
		_rng.randf_range(COIN_AREA.position.x, COIN_AREA.end.x - COIN_SIZE.x),
		_rng.randf_range(COIN_AREA.position.y, COIN_AREA.end.y - COIN_SIZE.y)
	)
	# 随机角度是「放」上去的，不是「转」进去的：角度直接定住，不补间回正。
	# 下限 7° 是为了避免偶尔抽到接近 0° 时看起来像摆正的。
	var angle := _rng.randf_range(7.0, 22.0) * (-1.0 if _rng.randf() < 0.5 else 1.0)
	trace.rotation = deg_to_rad(angle)
	trace.scale = Vector2(0.94, 0.94)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(trace, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	tween.tween_property(trace, "scale", Vector2.ONE, 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	var hold := COIN_HOLD - COIN_FADE if kind == "coin" else TRACE_HOLD
	var fade := COIN_FADE if kind == "coin" else 1.4
	tween.tween_interval(hold)
	tween.tween_property(trace, "modulate:a", 0.0, fade).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void: _on_trace_faded(kind))
	_trace_tweens[kind] = tween


## 痕迹淡完了：藏起来；铜板没被点走的话，就当玩家收下了。
func _on_trace_faded(kind: String) -> void:
	if _traces.has(kind):
		var trace := _traces[kind] as Control
		if trace != null:
			trace.visible = false
	if kind != "coin" or _coin_taken:
		return
	_coin_taken = true
	_grant_coin()


## 点铜板：立刻记进账，再播一小段「被拿走」的动效。
func _on_coin_input(event: InputEvent) -> void:
	if _coin_taken:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_coin_taken = true
		_grant_coin(true)
		_play_coin_pickup()
		accept_event()


## picked 只有玩家亲手点时才是 true：超时自动收下的不弹提示。
func _grant_coin(picked := false) -> void:
	GameState.add_coins(COIN_REWARD, "tip")
	Sfx.play(Sfx.Intent.DISH_CLINK, 0.98)
	if picked:
		EventBus.publish(CoinPickedEvent.new(COIN_REWARD))


## 铜板被点走：原地弹起、转一点、缩掉淡去，同时溅一圈小铜屑与一道涟漪。
func _play_coin_pickup() -> void:
	var trace := _traces.get("coin") as Control
	if trace == null:
		return
	if _trace_tweens.has("coin"):
		var old := _trace_tweens["coin"] as Tween
		if old != null and old.is_valid():
			old.kill()
	trace.visible = true
	trace.modulate.a = 1.0
	trace.pivot_offset = trace.size * 0.5
	var center := trace.position + trace.size * 0.5
	_spawn_coin_sparkle(center)
	_spawn_coin_ring(center)
	var lift_from := trace.position.y
	var tween := create_tween()
	tween.tween_property(trace, "scale", Vector2(1.3, 1.3), 0.1) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(trace, "rotation", deg_to_rad(9.0), 0.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(trace, "position:y", lift_from - 10.0, 0.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(trace, "scale", Vector2(0.05, 0.05), 0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(trace, "position:y", lift_from - 18.0, 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(trace, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void: trace.visible = false)
	_trace_tweens["coin"] = tween


## 铜板被拿走时的一圈涟漪：很快扩开、淡掉，不挡点击。
func _spawn_coin_ring(at: Vector2) -> void:
	VfxKit.ring(self, at, VfxKit.GOLD, 26.0, 0.42)


## 收走铜板时溅一圈小铜屑：原地炸开、一眨眼就没，不挡点击。
## 粒子统一走 GPU（项目约束：不用 CPUParticles2D）。
func _spawn_coin_sparkle(at: Vector2) -> void:
	VfxKit.sparkle(self, at, VfxKit.GOLD, 9, 40.0)


## 给测试与调试用：这种痕迹现在是否露在外面
func is_trace_visible(kind: String) -> bool:
	if not _traces.has(kind):
		return false
	var trace := _traces[kind] as Control
	return trace != null and trace.visible and trace.modulate.a > 0.01


# --- 来访节奏 -------------------------------------------------------------


func _on_visit() -> void:
	# 门口轻铃，不是敲门：敲门声曾让玩家以为有人来谈生意（第七轮反馈 14）
	Sfx.play(Sfx.Intent.VISIT, 0.94)
	if _rng.randf() < 0.85:
		show_trace("coin")
	_schedule_next_visit()


## 铜板落到桌上：人吃完了，杯子先放下、留下钱
func _on_coin_arrived() -> void:
	show_trace("coin")
	# 铜板落地：压到背景层，和订单到账的界面音区分开（第七轮反馈 14）
	Sfx.play(Sfx.Intent.COIN, 0.96, -3.0)


func _schedule_next_visit() -> void:
	_visit_timer.start(_rng.randf_range(90.0, 170.0))


func _on_order_changed(event: Event) -> void:
	var order_event := event as OrderChangedEvent
	if order_event == null:
		return
	# 交付后过一会儿才出现：人吃完、付钱、离开，不是同时发生的
	if order_event.reason == "delivered":
		_coin_timer.start()
