class_name GamePanel
extends UIPanel
## 业务面板基类：统一卡片外壳 + 「打开时建一次、数据变了才更新」的刷新纪律。
##
## 为什么不轮询：UIManager 是栈式的，同一时刻只有一个面板可见；数据变化由 GameState
## 通过 EventBus 广播，面板收到事件合并到下一帧重建一次就够。早先这里有个每 0.3 秒
## 无条件调 refresh() 的轮询，导致子类整块重建——书架因此每 0.3 秒把 TabContainer
## 重建一遍，页签弹回第一页、还循环播页签音效（实测确认过）。轮询已整个移除。
##
## 仍然随时间变化的内容（「还剩几秒」这类）由子类把 tick_interval 设成 > 0：
## 基类用一个 Timer 只调 _on_tick() 就地改文字，绝不碰结构。
##
## 子类约定：
## - `_on_init()` 里设 `tick_interval`
## - `_on_open(data)` 开头 set_title / set_subtitle，结尾务必 `super._on_open(data)`
## - `refresh()` 必须幂等：可以安全地重复调用

const THEME_PATH := "res://resources/themes/paper_theme.tres"
## 切语言：重画当前面板（标题在 refresh 里设，见子类约定）
const EVENT_LANGUAGE := &"LanguageChangedEvent"

## 开/关动画时长：短到不耽误操作，长到眼睛能看见「纸被拿起来/放下」
const OPEN_SECONDS := 0.20
const CLOSE_SECONDS := 0.14
## 切页签后内容淡入的时长（结构已换好，只补一层视觉过渡）
const CONTENT_FLASH_SECONDS := 0.16
## 开/关时纸片的起止缩放：1.5% 太像纯淡入，2.5% 才看得出「被拿起来」
const MOTION_SCALE := 0.975

## 会改变面板内容的数据事件；收到任意一个就请求一次刷新
const WATCHED_EVENTS: Array[StringName] = [
	&"MaterialChangedEvent",
	&"CoinChangedEvent",
	&"CatalogDiscoveredEvent",
	&"CraftCompletedEvent",
	&"RecipeUnlockedEvent",
	&"FacilityUpgradedEvent",
	&"LetterUnlockedEvent",
	&"LetterReadEvent",
	&"TaskAcceptedEvent",
	&"TaskCompletedEvent",
	&"ResearchCompletedEvent",
]

## 子类往这里塞内容
var content: VBoxContainer
## 固定在纸上的工具条（页签、筛选）：不随内容滚动
var toolbar: VBoxContainer
## 常驻页脚：不随内容滚动（「试一试」这类必须一直看得见的按钮放这里）
var footer: VBoxContainer
## >0 时基类按这个间隔调 _on_tick()（纯文字更新用，别在里面重建控件）
var tick_interval := 0.0

## 两次重建之间的最短间隔：采集时素材每秒变几十次，全按帧重建会把滚动位置冲没
const MIN_REFRESH_GAP_MS := 250

var _title_label: Label
var _subtitle_label: Label
var _message_label: Label
var _scroll: ScrollContainer
## 打开面板前焦点在哪：关掉时还回去，连续开几个面板不会把焦点丢在天上
var _previous_focus: Control = null
var _tick_timer: Timer
var _refresh_pending := false
var _refreshing := false
var _last_refresh_ms := 0
var _built := false

## 面板根是铺满视口的 Control；缩放围绕屏幕中心，纸片才会「从原地展开」
var _motion_tween: Tween = null
## 切页签时让内容淡回来；和开关动画分开，互不打断
var _content_tween: Tween = null
## 收场动画已经开始：防止连点关闭按钮叠出第二段 tween / 第二声关闭音
var _closing := false
## 右下角的「右键 / Esc 返回」提示；挂在纸片上，不占正文高度
var _back_hint: Label = null
## 真正那张纸（PanelContainer）的容器；浮层要按纸边封顶，而不是按铺满视口的面板根节点。
var _paper: Control = null


func _ready() -> void:
	theme = load(THEME_PATH)
	_build_shell()
	_built = true
	resized.connect(_update_pivot)
	_update_pivot()
	# Timer 建好就按子类在 _on_init 里给的间隔跑；_on_open/_on_pause 再校正
	_tick_timer = Timer.new()
	_tick_timer.timeout.connect(_on_tick)
	add_child(_tick_timer)
	_sync_tick_timer()


func _on_open(_data: Dictionary = {}) -> void:
	# 缓存复用的面板可能停在上一次收场动画的半透明/缩小状态，先把壳复位
	_closing = false
	_kill_motion()
	scale = Vector2.ONE
	modulate.a = 1.0
	if content != null:
		content.modulate.a = 1.0
	# 事件驱动：数据变了才刷新（EventBus 会自动丢弃已销毁面板的 Callable）
	for event_type in WATCHED_EVENTS:
		EventBus.subscribe(event_type, _on_data_changed)
	EventBus.subscribe(EVENT_LANGUAGE, _on_language_changed)
	_message_label.text = ""
	Sfx.play(Sfx.Intent.OPEN)
	refresh()
	_sync_tick_timer()
	_focus_first_control()
	_play_open_motion()


func _on_resume() -> void:
	# 被别的面板盖住期间数据可能变了，回到这一页补一次
	request_refresh()
	_sync_tick_timer()
	# 关闭上面的面板时若把本层遮罩淡到了 0，这里必须归一，否则下面这页永远压在半暗里
	var dimmer := _layer_dimmer()
	if dimmer != null:
		dimmer.modulate.a = 1.0


func _on_pause() -> void:
	_stop_tick()


func _on_close() -> void:
	# request_close 已经在开头播过关闭音了，这里别再叠一声
	if not _closing:
		Sfx.play(Sfx.Intent.CLOSE)
	_closing = false
	_kill_motion()
	_kill_content_tween()
	scale = Vector2.ONE
	modulate.a = 1.0
	if content != null:
		content.modulate.a = 1.0
	for event_type in WATCHED_EVENTS:
		EventBus.unsubscribe(event_type, _on_data_changed)
	EventBus.unsubscribe(EVENT_LANGUAGE, _on_language_changed)
	_stop_tick()
	_restore_focus()


## 子类覆写：重建内容 / 更新按钮状态。必须幂等。
func refresh() -> void:
	pass


## 子类覆写：这页要不要外层滚动区。默认要；灶台这类自己管两列滚动的返回 false。
func wants_outer_scroll() -> bool:
	return true


## 外层滚动区；不套外层滚动时为 null（测试与自检用）。
func get_outer_scroll() -> ScrollContainer:
	return _scroll


## 纸片在屏幕上的矩形；筛选浮层这类「挂在纸上的窗口」需要用它当边界。
func get_paper_rect() -> Rect2:
	if _paper == null:
		return Rect2()
	return _paper.get_global_rect()


## 子类覆写：tick_interval 到点时调用。只改文字，别重建控件。
func _on_tick() -> void:
	pass


# --- 键盘焦点 -------------------------------------------------------------


## 打开面板就把焦点交给内容区第一个能按的东西：键盘/手柄进来不用先猜「焦点在哪」。
## 用 call_deferred 而不是当场 grab —— refresh() 刚建出来的控件这一帧还没布局，
## 布局结束会把焦点冲掉。
func _focus_first_control() -> void:
	if _previous_focus == null:
		_previous_focus = get_viewport().gui_get_focus_owner()
	_grab_first.call_deferred()


func _grab_first() -> void:
	if not is_inside_tree() or not visible:
		return
	# 先找按钮：分组标题（FoldableContainer）也能聚焦，但键盘进来该先摸到能按的东西，
	# 而且 follow_focus 会把列表滚到标题栏只露半截（B 批实测，灶台页）。
	var target := _first_button(content)
	if target == null:
		target = _first_focusable(content)
	if target == null:
		target = _first_focusable(self)
	if target != null:
		target.grab_focus()


## 只找按钮：内容区里真正的动作入口。
func _first_button(node: Node) -> Control:
	for child in node.get_children():
		var control := child as Control
		if control is BaseButton and control.visible and control.focus_mode == Control.FOCUS_ALL:
			if not (control as BaseButton).disabled:
				return control
		var deeper := _first_button(child)
		if deeper != null:
			return deeper
	return null


## 深度优先找第一个「看得见、能聚焦、没禁用」的控件。
## 先找内容区再找整页，是为了让焦点落在能操作的东西上，而不是标题栏的关闭钮。
func _first_focusable(node: Node) -> Control:
	for child in node.get_children():
		var control := child as Control
		if control != null and control.visible and control.focus_mode == Control.FOCUS_ALL:
			if not (control is BaseButton) or not (control as BaseButton).disabled:
				return control
		var deeper := _first_focusable(child)
		if deeper != null:
			return deeper
	return null


func _restore_focus() -> void:
	if _previous_focus != null and is_instance_valid(_previous_focus) and _previous_focus.is_inside_tree():
		_previous_focus.grab_focus()
	_previous_focus = null


# --- 刷新调度 -------------------------------------------------------------


## 请求一次刷新：同一帧内的多个事件合并成一次；重建间隔不足时顺延
func request_refresh() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	var wait := MIN_REFRESH_GAP_MS - (Time.get_ticks_msec() - _last_refresh_ms)
	if wait <= 0 or not is_inside_tree():
		_flush_refresh.call_deferred()
	else:
		get_tree().create_timer(wait / 1000.0).timeout.connect(_flush_refresh)


func _flush_refresh() -> void:
	_refresh_pending = false
	# 延迟到这里时面板可能已经关了 / 被盖住了
	if not is_inside_tree() or not visible:
		return
	_last_refresh_ms = Time.get_ticks_msec()
	# 重建会把滚动位置冲回顶部，先记下来，重建完再放回去
	var scroll_y := _scroll.scroll_vertical if _scroll != null else 0
	refresh()
	if _scroll != null:
		_scroll.scroll_vertical = scroll_y


func _on_data_changed(_event: Event) -> void:
	if not _refresh_pending:
		request_refresh()


## 切语言后整页重画：标题 / 副标题 / 按钮都由 refresh() 重新从翻译表取
func _on_language_changed(_event: Event) -> void:
	if _back_hint != null:
		_back_hint.text = I18n.t("ui.hint.back")
	request_refresh()


func _sync_tick_timer() -> void:
	if _tick_timer == null:
		return
	if tick_interval > 0.0 and visible and is_inside_tree():
		_tick_timer.wait_time = tick_interval
		if _tick_timer.is_stopped():
			_tick_timer.start()
	else:
		_stop_tick()


func _stop_tick() -> void:
	if _tick_timer != null:
		_tick_timer.stop()


# --- 给子类用的小工具 -----------------------------------------------------


func set_title(text: String) -> void:
	_title_label.text = text


func set_subtitle(text: String) -> void:
	_subtitle_label.text = text
	_subtitle_label.visible = not text.is_empty()


## 页脚提示（做不了、买不起之类的反馈）
func show_message(text: String, color: Color = PanelKit.ACCENT_DEEP) -> void:
	_message_label.text = text
	_message_label.add_theme_color_override("font_color", color)


func clear_content() -> void:
	PanelKit.clear(content)


func close_self() -> void:
	request_close()


## 带收场动画的关闭。UIManager.close_panel 本身保持同步（测试/自检依赖），
## 只有用户主动关面板时才绕到这里：先让纸缩一下淡掉，再真正出栈。
func request_close() -> void:
	if _closing:
		return
	if panel_id == null or not UIManager.is_panel_open(panel_id):
		return
	_closing = true
	Sfx.play(Sfx.Intent.CLOSE)
	_kill_motion()
	_kill_content_tween()
	scale = Vector2.ONE
	modulate.a = 1.0
	_update_pivot()
	_motion_tween = create_tween()
	_motion_tween.set_parallel(true)
	_motion_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_motion_tween.tween_property(self, "scale", Vector2(MOTION_SCALE, MOTION_SCALE), CLOSE_SECONDS)
	_motion_tween.tween_property(self, "modulate:a", 0.0, CLOSE_SECONDS)
	# 本层最后一个面板关掉时，遮罩跟着一起淡，别让背景先「啪」地亮回来
	var dimmer := _layer_dimmer()
	if dimmer != null and _layer_panel_count() <= 1:
		_motion_tween.tween_property(dimmer, "modulate:a", 0.0, CLOSE_SECONDS)
	_motion_tween.finished.connect(_finish_close)


func _finish_close() -> void:
	_motion_tween = null
	# 动画这 0.14 秒里可能已经被 close_all / 自检直接关掉了
	if panel_id != null and UIManager.is_panel_open(panel_id):
		UIManager.close_panel(panel_id)
	_closing = false


func _play_open_motion() -> void:
	_kill_motion()
	scale = Vector2(MOTION_SCALE, MOTION_SCALE)
	modulate.a = 0.0
	_update_pivot()
	_motion_tween = create_tween()
	_motion_tween.set_parallel(true)
	_motion_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(self, "scale", Vector2.ONE, OPEN_SECONDS)
	_motion_tween.tween_property(self, "modulate:a", 1.0, OPEN_SECONDS)
	var dimmer := _layer_dimmer()
	if dimmer != null:
		if _layer_panel_count() <= 1:
			# 第一层面板：遮罩从透明压到 0.5，背景是「被纸压暗」而不是瞬间变黑
			dimmer.modulate.a = 0.0
			_motion_tween.tween_property(dimmer, "modulate:a", 1.0, OPEN_SECONDS)
		else:
			# 已经有一层面板压着背景：遮罩必须立刻实心，否则会透出两层半暗
			dimmer.modulate.a = 1.0


## 切换页签/分段后用：内容已经换好，只补一层很短的淡入，提示「这里刷新了」
func flash_content() -> void:
	if content == null or not is_inside_tree() or _closing:
		return
	_kill_content_tween()
	content.modulate.a = 0.35
	_content_tween = create_tween()
	_content_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_content_tween.tween_property(content, "modulate:a", 1.0, CONTENT_FLASH_SECONDS)


func _kill_motion() -> void:
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	_motion_tween = null


func _kill_content_tween() -> void:
	if _content_tween != null and _content_tween.is_valid():
		_content_tween.kill()
	_content_tween = null


func _update_pivot() -> void:
	pivot_offset = size * 0.5


## 本层面板的遮罩（UIManager 建在面板的父 CanvasLayer 下，固定叫这个名字）
func _layer_dimmer() -> ColorRect:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("BackgroundDimmer") as ColorRect


## 本层还挂着几个面板（被压住的暂停面板仍在树里，所以能当栈深用）
func _layer_panel_count() -> int:
	var parent := get_parent()
	if parent == null:
		return 0
	var count := 0
	for child in parent.get_children():
		if child is UIPanel and not child.is_queued_for_deletion():
			count += 1
	return count


# --- 数据访问（各面板都要，放基类免得抄） ---------------------------------


func data_registry() -> DataRegistry:
	return RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry


func def_of(key: String) -> GameDef:
	# 空键是「还没选中」的常态（例如灶台「可做」段一条都没有时），
	# 往下传会让 ResourceLocation 每次打一条 warning，所以在门口挡掉
	if key.is_empty():
		return null
	var registry := data_registry()
	if registry == null:
		return null
	return registry.get_def(key)


func defs_of(type_id: String) -> Array[GameDef]:
	var registry := data_registry()
	if registry == null:
		return []
	return registry.get_defs_of_type(type_id)


## 产出某样东西的配方（不限食物）。材料页想知道「这份半成品怎么做」，就用它。
## 一样东西可能有几条做法，这里只取第一条——图鉴给方向，不摊全菜单。
func recipe_for_output(item_key: String) -> RecipeDef:
	if item_key.is_empty():
		return null
	for def in defs_of("recipe"):
		var recipe := def as RecipeDef
		if recipe != null and recipe.output == item_key:
			return recipe
	return null


## 产出这道菜、还没解锁的「需要研究」配方：图鉴里靠它给材料线索。
## 一道菜可能有几种做法，只取第一条——线索给一个方向就够，不必把菜单全摊开。
func research_recipe_for_food(item_key: String) -> RecipeDef:
	if item_key.is_empty():
		return null
	for def in defs_of("recipe"):
		var recipe := def as RecipeDef
		if recipe == null or recipe.output != item_key:
			continue
		if recipe.needs_research() and not GameState.is_recipe_unlocked(recipe.get_key()):
			return recipe
	return null


## 一条研究配方的线索：**总是**按具名材料拼「到研究台把这几样放一起试试」。
## 2026-10-29 用户报：有的菜（卡布奇诺）只显示一句氛围 hint，看起来就是描述，
## 玩家不知道往研究台放什么——材料句才是主线索，氛围句另走 `research_flavor()`。
func research_clue(recipe: RecipeDef) -> String:
	if recipe == null:
		return ""
	var names: Array[String] = []
	# 走 inputs 而不是 input_keys：后者刻意不含 by_tag，会漏掉「任意蔬菜」这类线索。
	for stack in recipe.inputs:
		var name := stack_name(stack)
		if not name.is_empty() and not names.has(name):
			names.append(name)
	if names.is_empty():
		return I18n.t("ui.catalog.hint_recipe_locked")
	return I18n.t("ui.catalog.hint_research_try", [I18n.list_sep().join(names)])


## 研究配方自带的氛围 hint（「名字里有一顶帽子」这类）：只做补充，不代替材料句。
func research_flavor(recipe: RecipeDef) -> String:
	if recipe == null:
		return ""
	return recipe.localized(&"research_hint")


## 一份材料还没遇见时该写的来历：能造就写配方，能买就写价钱，能采就写采集点。
## 返回若干条，调用方决定给全部（详情，一行一条）还是只取第一条（列表）。
func material_sources(item: ItemDef) -> Array[String]:
	var sources: Array[String] = []
	if item == null:
		return sources
	var maker := recipe_for_output(item.get_key())
	if maker != null:
		var inputs: Array[String] = []
		for stack in maker.inputs:
			inputs.append(stack_name(stack))
		var ingredients := I18n.list_sep().join(inputs)
		if maker.facility.is_empty():
			sources.append(I18n.t("ui.catalog.hint_material_made_plain", [ingredients]))
		else:
			var facility := def_of(maker.facility)
			var place := facility.localized() if facility != null else maker.facility
			sources.append(I18n.t("ui.catalog.hint_material_made", [ingredients, place]))
	if item.merchant_price > 0:
		sources.append(I18n.t("ui.catalog.hint_material_buy", [str(item.merchant_price)]))
	var harvest := GameState.get_harvest_for_material(item.get_key())
	if harvest != null:
		# 采集点没开放、或这条材料的稀有度超过当前采集等级时，光写「能弄到」会骗人：
		# 把门槛和现状一起说清（第七轮反馈 6/17）
		var level := GameState.get_harvest_level(harvest.get_key())
		if not GameState.is_harvest_unlocked(harvest):
			sources.append(I18n.t("ui.catalog.hint_material_harvest_unopened", [harvest.localized()]))
		elif item.harvest_tier > level:
			sources.append(I18n.t("ui.catalog.hint_material_harvest_locked", [harvest.localized(), str(item.harvest_tier), str(level)]))
		else:
			sources.append(I18n.t("ui.catalog.hint_material_harvest", [harvest.localized()]))
	if item.is_free():
		sources.append(I18n.t("ui.catalog.hint_material_free"))
	return sources


## 图鉴里一条材料的来历：合并前两条（可做 → 可买 → 可采 → 常备）。
## 只显示第一条会把「商店有卖」盖在「货箱能做」下面（第七轮反馈 17），
## 两条足够说清主要渠道，再多会把详情页读成一张清单。
func material_hint(item: ItemDef, verbose: bool = false) -> String:
	var sources := material_sources(item)
	if sources.is_empty():
		return I18n.t("ui.catalog.hint_material_unknown")
	var shown: Array[String] = []
	for i in mini(2, sources.size()):
		shown.append(sources[i])
	if verbose:
		return "\n".join(shown)
	return I18n.t("ui.catalog.source_separator").join(shown)


## 一份材料需求怎么念：指名的念物品名，按标签要的念标签名（「任意蔬菜」）
func stack_name(stack: MaterialStack) -> String:
	if stack == null:
		return ""
	if not stack.by_tag.is_empty():
		var tag := def_of(stack.by_tag)
		var tag_name := tag.localized() if tag != null else stack.by_tag
		return I18n.t("ui.catalog.any_tag", [tag_name])
	var target := def_of(stack.material)
	return target.localized() if target != null else stack.material


## 「它可以做…」：一件东西还能被哪些配方当输入（反查走 GameState 的同一份索引）。
## 灶台的配方详情与图鉴的材料/食物/配方条目共用这一份（第十轮反馈 5）；折叠着放，
## 默认不抢正文位置；最多列 8 条，再多就报个数。
## on_pick 收到已解锁下游的配方键；on_unknown 为空时不画未解锁的条目——图鉴里只列
## 已经查得到的；非空时把它们画成「？？？」+「需要研究」交给回调（灶台跳图鉴）。
## 没有下游时返回 null，调用方整段不加。
func used_in_section(item_key: String, on_pick: Callable, on_unknown: Callable = Callable(), only_known := false) -> Control:
	var visible_keys: Array[String] = []
	var hidden_keys: Array[String] = []
	for key in GameState.recipes_using(item_key):
		# 图鉴只列已经记录过的下游（还没做过的不报名字），灶台把能做的都列出来
		if only_known and not GameState.is_discovered(key):
			continue
		if GameState.is_recipe_visible(key):
			visible_keys.append(key)
			continue
		if not on_unknown.is_valid():
			continue
		var other := def_of(key) as RecipeDef
		if other == null or not other.needs_research():
			continue
		# 主题还没到站的下游连影子都不给：那不是「需要研究」，是还没轮到它
		if not GameState.is_theme_unlocked(GameState.recipe_theme_key(key)):
			continue
		hidden_keys.append(key)
	if visible_keys.is_empty() and hidden_keys.is_empty():
		return null
	var section := PanelKit.fold_section(I18n.t("ui.craft.used_in"), true)
	var box := PanelKit.vbox(4)
	var shown := 0
	var total := visible_keys.size() + hidden_keys.size()
	for key in visible_keys:
		if shown >= 8:
			break
		var other := def_of(key) as RecipeDef
		if other == null:
			continue
		# 玩家认的是成品名（「美式」），配方名只在灶台右列当副标题
		var output := def_of(other.output) as ItemDef
		var shown_name := output.localized() if output != null else other.localized()
		var button := PanelKit.button(shown_name, Sfx.Intent.NONE)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(func() -> void: on_pick.call(key))
		box.add_child(button)
		shown += 1
	# 隐藏条目排在可见条目后面：先讲已经能做的，再讲「还有一扇没开的门」
	for key in hidden_keys:
		if shown >= 8:
			break
		box.add_child(_used_in_unknown_row(key, on_unknown))
		shown += 1
	if total > shown:
		box.add_child(PanelKit.hint(I18n.t("ui.craft.used_in_more", [total - shown])))
	section.add_child(box)
	return section


## 未解锁的下游：不报名字，只报「有人要它」，整行可点去图鉴看研究线索。
## 不能用 hint()——自动换行的 Label 在 HBoxContainer 里最小宽度只有 1px，
## 会被挤成逐字竖排、把整行撑到 150+ 高（2026-10-31 实机截图）。
func _used_in_unknown_row(recipe_key: String, on_unknown: Callable) -> Control:
	var row := PanelKit.hbox(8)
	var button := PanelKit.button(I18n.t("ui.craft.used_in_unknown"), Sfx.Intent.NONE)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 15)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void: on_unknown.call(recipe_key))
	row.add_child(button)
	row.add_child(PanelKit.hint_inline(I18n.t("ui.craft.used_in_research")))
	return row


## 标签成员弹窗：点开「任意蔬菜」能看见这个标签下到底有哪些东西（反馈 22）。
## 灶台的配料标签章与研究台的候选牌共用这一份，别两处各写一套成员列表。
func show_tag_members(tag_key: String) -> void:
	var registry := RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry
	if registry == null:
		return
	var members := registry.tag_member_keys(tag_key)
	var tag := def_of(tag_key) as TagDef
	var tag_name := tag.localized() if tag != null and not tag.localized().is_empty() else tag_key
	var popup := PopupPanel.new()
	popup.add_theme_stylebox_override("panel", PanelKit.slab(PanelKit.CARD_HI, PanelKit.INK, 10))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	popup.add_child(margin)
	var box := PanelKit.vbox(6)
	margin.add_child(box)
	box.add_child(PanelKit.label(I18n.t("ui.craft.tag_members", [tag_name, members.size()]), 17))
	var list := PanelKit.vbox(3)
	var shown := 0
	for key in members:
		if shown >= 12:
			break
		var item := def_of(key) as ItemDef
		if item != null:
			list.add_child(PanelKit.label(item.localized(), 16, PanelKit.INK_SOFT))
			shown += 1
	if members.size() > shown:
		list.add_child(PanelKit.hint(I18n.t("ui.craft.tag_members_more", [members.size() - shown])))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(250, clampf(float(members.size()) * 22.0, 60.0, 240.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(list)
	box.add_child(scroll)
	add_child(popup)
	popup.popup_hide.connect(popup.queue_free)
	popup.popup_centered.call_deferred()


## 某条定义是否属于某个标签（成员索引在框架 TagRegistry 里，由 DataRegistry 灌入）
func has_tag(key: String, tag_key: String) -> bool:
	return GameState.has_tag(key, tag_key)


# --- 外壳 -----------------------------------------------------------------


## 纸片尺寸：比画面略小，四周留出房间的边。
## 高度 566 → 648（2026-10-28 SC-07）：16:9（1280×720）下卡片实际取 608（720−112），
## 图鉴食物页滚动区只有 250px、行高 68px，刚好 3 行多；+40 让 4 行完整可见。
## 上限仍 760：撑满会把面板底部留白吃掉，和 E 批「页脚下留 14px」冲突。
const CARD_SIZE := Vector2(880.0, 648.0)


func _build_shell() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# 一张纸 + 它自己投下的影子。纸只有一张，右下那圈渐隐是「离桌面有多高」，
	# 不是第二张纸——所以这里不能再垫一张带描边的深色纸。
	var stack := Control.new()
	_paper = stack
	# 卡片高度随视口长，桌面留 112px 给窗边留白，上限 760 免得变成一堵纸墙。
	# 注意：canvas_items + aspect=expand 下 16:9 的设计视口恒为 1280×720，
	# 这一条在 16:9 上取不到效果（只会等比放大），真正受益的是 4:3 / 带鱼屏——
	# 1024×768 实测卡片 566 → 760，图鉴食物页列表 143px → 295px（自检 S10）。
	var card_size := CARD_SIZE
	var view_height := size.y
	if view_height <= 0.0:
		view_height = get_viewport_rect().size.y
	card_size.y = clampf(view_height - 112.0, CARD_SIZE.y, 760.0)
	stack.custom_minimum_size = card_size
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(stack)

	stack.add_child(PanelKit.cast_shadow(6, 1.0))

	var card := PanelContainer.new()
	var card_style := PanelKit.slab(PanelKit.CARD, PanelKit.INK, 6, 2, false)
	card_style.content_margin_left = 30.0
	card_style.content_margin_top = 24.0
	card_style.content_margin_right = 30.0
	card_style.content_margin_bottom = 20.0
	card.add_theme_stylebox_override("panel", card_style)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_child(card)

	# 胶带只属于房间里那张桌子。面板是「拿起来看的纸」，不需要再贴一次。
	var layout := PanelKit.vbox(10)
	card.add_child(layout)

	# 返回提示贴在纸角：挂在 stack 上而不是 layout 里，免得占掉一行的纵向空间。
	# 鼠标穿透，右键仍由 GameBridge 统一处理。
	_back_hint = PanelKit.caption(I18n.t("ui.hint.back"))
	_back_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_back_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_back_hint.offset_left = -230.0
	_back_hint.offset_top = -30.0
	_back_hint.offset_right = -42.0
	_back_hint.offset_bottom = -22.0
	stack.add_child(_back_hint)

	var header := PanelKit.hbox(12)
	layout.add_child(header)
	_title_label = PanelKit.title("面板")
	header.add_child(_title_label)
	header.add_child(PanelKit.spacer())
	# 关闭音由 _on_close 统一给，按钮本身不再叠一层
	var close_button := PanelKit.icon_button("feedback/cross.svg", 46.0, 26.0)
	close_button.pressed.connect(close_self)
	header.add_child(close_button)

	_subtitle_label = PanelKit.hint("")
	_subtitle_label.visible = false
	layout.add_child(_subtitle_label)

	layout.add_child(PanelKit.divider())

	# 固定在纸上的工具条（页签、筛选之类）。**不能放进下面的滚动区**：
	# 工具条一旦跟着内容滚，玩家滚到一半就不知道自己在哪一页了。
	toolbar = PanelKit.vbox(8)
	layout.add_child(toolbar)

	# 大多数面板是「一页纸从头滚到底」；灶台例外——左列列表与右列详情各自滚，
	# 外层再套一层滚动区会把两列一起卷走（试玩第三轮反馈 2）。
	var scrolling := wants_outer_scroll()
	var scroll: ScrollContainer = null
	if scrolling:
		scroll = ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		# 焦点往下 Tab 到看不见的行时，滚动区自己把它带进视口
		scroll.follow_focus = true
		# 兜底：滚动区是唯一「最小高为 0」的兄弟节点，工具条或页脚一旦长高，
		# VBox 会把它一路压到 0，整页内容凭空消失。给个下限让它至少露出两行，
		# 挤压会变成「难看但看得见」，而不是「空白面板」（2026-10-27 自检 S1）。
		scroll.custom_minimum_size.y = 120
		layout.add_child(scroll)
	_scroll = scroll

	# 右边留出滚动条的位置，否则右对齐的字会被压在滚动条底下
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 18)
	# 最后一行下面留出呼吸：滚动到底时贴着面板底边像被裁掉一截（报告 P2-3）
	margin.add_theme_constant_override("margin_bottom", 14)
	# 不套外层滚动时内容由子类自己安排：高出去的部分裁在纸里，别压到页脚上
	margin.clip_contents = not scrolling
	if scrolling:
		scroll.add_child(margin)
	else:
		layout.add_child(margin)
	content = PanelKit.vbox(10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not scrolling:
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(content)

	_message_label = PanelKit.hint("")
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# 页脚放在提示上方：先看到按钮和代价，再看到「做不了，因为……」
	footer = PanelKit.vbox(6)
	layout.add_child(footer)
	layout.add_child(_message_label)
