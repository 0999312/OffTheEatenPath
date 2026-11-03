class_name SettingsPanel
extends GamePanel
## 设置：通用（语言）、音频、存档、关于、调试——五组折叠。
##
## 这一页原本是一条长滚动条从语言拖到致谢，中途全是同类条目，
## 想找「清档」得先翻过三根滑杆。改成五张可折叠的小纸之后，
## 屏幕上永远只有当前关心的那一组；开合状态记在 `_fold_state`，
## 切语言/清档触发的重建不会把它忘掉。

var _clear_button: Button = null
var _clear_armed := false
## 分组 id → 是否收起；重建时回填，别让用户刚折好的组自己弹开
var _fold_state: Dictionary = {}


func _on_open(data: Dictionary = {}) -> void:
	_clear_armed = false
	super._on_open(data)


## 设置页只在内容空时建一次（避免拖动滑杆时被数据事件重建），切语言时手动重画
func _on_language_changed(_event: Event) -> void:
	super._on_language_changed(_event)
	_build()


func refresh() -> void:
	if not content.get_children().is_empty():
		return
	_build()


func _build() -> void:
	clear_content()
	set_title(I18n.t("ui.settings.title"))
	set_subtitle("")

	content.add_child(_group("general", I18n.t("ui.settings.section_general"), false, _build_general))
	content.add_child(_group("audio", I18n.t("ui.settings.section_audio"), false, _build_audio))
	content.add_child(_group("save", I18n.t("ui.settings.section_save"), true, _build_save))
	content.add_child(_group("about", I18n.t("ui.settings.section_about"), true, _build_about))
	if OS.is_debug_build() and not GameState.offline_unlocked:
		content.add_child(_group("debug", I18n.t("ui.settings.section_debug"), true, _build_debug))


## 一组折叠内容：标题栏由 `PanelKit.fold_section` 统一外观，正文交给 builder 填
func _group(id: String, title_text: String, folded_by_default: bool,
		builder: Callable) -> FoldableContainer:
	var folded: bool = _fold_state.get(id, folded_by_default)
	var section := PanelKit.fold_section(title_text, folded)
	_fold_state[id] = folded
	var body := PanelKit.vbox(8)
	builder.call(body)
	# 正文和标题栏之间留一口气，否则小字会贴着标题栏的边
	section.add_child(PanelKit.pad(body, 2, 12, 2, 2))
	section.folding_changed.connect(func(is_folded: bool) -> void:
		_fold_state[id] = is_folded
	)
	return section


## 通用：语言 + 研究引导重看。招牌菜已搬去桌面上那张便条（决策 2026-10-28 D8）：
## 它是玩家在桌面上做的决定，不该埋在设置页第三层。
func _build_general(body: VBoxContainer) -> void:
	body.add_child(_language_row())
	body.add_child(PanelKit.divider())
	body.add_child(PanelKit.label(I18n.t("ui.settings.research_guide_title"), 19, PanelKit.INK_SOFT))
	body.add_child(PanelKit.hint(I18n.t("ui.settings.research_guide_hint"), 660))
	var guide_button := PanelKit.button(I18n.t("ui.settings.research_guide_button"), Sfx.Intent.NONE)
	guide_button.pressed.connect(_on_research_guide_again)
	body.add_child(guide_button)


## 让研究台下次打开时重新贴一遍三步说明（决策 D10：只自动出现一次，但允许重看）
func _on_research_guide_again() -> void:
	GameState.reset_research_guide()
	show_message(I18n.t("ui.settings.research_guide_done"), PanelKit.INK_SOFT)


## 音频：三条总线音量，拖完立刻写 `user://settings.cfg`
func _build_audio(body: VBoxContainer) -> void:
	body.add_child(_volume_row(I18n.t("ui.settings.volume_master"), "Master"))
	body.add_child(_volume_row(I18n.t("ui.settings.volume_music"), "Music"))
	body.add_child(_volume_row(I18n.t("ui.settings.volume_sfx"), "UI"))
	if Music.available_tracks().is_empty():
		body.add_child(PanelKit.hint(I18n.t("ui.settings.no_music"), 640))


## 存档：路径说明 + 清档（两步确认，避免手滑）
func _build_save(body: VBoxContainer) -> void:
	body.add_child(PanelKit.hint(I18n.t("ui.settings.save_path", [SaveGame.DEFAULT_PATH]), 660))
	body.add_child(PanelKit.divider())
	body.add_child(PanelKit.label(I18n.t("ui.settings.section_reset"), 19, PanelKit.INK_SOFT))
	body.add_child(PanelKit.hint(I18n.t("ui.settings.reset_hint"), 660))
	var clear_button := PanelKit.button(I18n.t("ui.settings.reset_button"))
	clear_button.pressed.connect(_on_clear_pressed)
	_clear_button = clear_button
	body.add_child(clear_button)


## 关于：致谢入口 + 快捷键速查
func _build_about(body: VBoxContainer) -> void:
	body.add_child(PanelKit.hint(I18n.t("ui.settings.about_hint"), 660))
	var credits_button := PanelKit.button(I18n.t("ui.settings.credits_button"), Sfx.Intent.NONE)
	credits_button.pressed.connect(func() -> void:
		UIManager.open_panel(ResourceLocation.from_string(UIKeys.CREDITS))
	)
	body.add_child(credits_button)
	body.add_child(PanelKit.divider())
	body.add_child(PanelKit.hint(I18n.t("ui.settings.shortcuts"), 660))


## 调试（只在 debug 构建出现）：解开离线产出，好验收结算面板
func _build_debug(body: VBoxContainer) -> void:
	body.add_child(PanelKit.hint(I18n.t("ui.settings.debug_hint"), 660))
	var unlock_button := PanelKit.button(I18n.t("ui.settings.debug_button"))
	unlock_button.pressed.connect(_on_debug_unlock_offline)
	body.add_child(unlock_button)


## 语言：列出 GameBootstrap 支持的全部语言。切换立刻生效并写 `user://settings.cfg`
func _language_row() -> HBoxContainer:
	var row := PanelKit.hbox(12)
	row.add_child(PanelKit.label(I18n.t("ui.settings.language"), 19))
	var option := PanelKit.option_button(280)
	var current := I18NManager.get_current_language()
	var selected := 0
	for i in GameBootstrap.SUPPORTED_LOCALES.size():
		var code: String = GameBootstrap.SUPPORTED_LOCALES[i]
		option.add_item(I18n.LOCALE_NAMES.get(code, code), i)
		if code == current:
			selected = i
	option.selected = selected
	option.item_selected.connect(_on_language_selected)
	row.add_child(option)
	return row


func _on_language_selected(index: int) -> void:
	var code: String = GameBootstrap.SUPPORTED_LOCALES[index]
	SettingsStore.set_locale(code)
	I18NManager.set_language(code)
	show_message(I18n.t("ui.settings.language_changed"), PanelKit.INK_SOFT)


## 一条音量滑杆：拖动即改总线并写进 `user://settings.cfg`；启动时由 GameBootstrap 回读。
## 标签给固定宽度，滑杆才会三段对齐——不然 "Sound effects" 比 "Music" 长，滑杆起点就错开了。
## 用 PaperSlider 而不是裸 HSlider：主题的 20px 把手在高分屏会被放大糊边（用户 2026-11-03 报）。
func _volume_row(label_text: String, bus_name: String) -> HBoxContainer:
	var row := PanelKit.hbox(12)
	var name_label := PanelKit.label(label_text, 19)
	name_label.custom_minimum_size = Vector2(170, 0)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)
	var slider := PaperSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = _saved_bus_volume(bus_name)
	slider.value_changed.connect(_on_volume_changed.bind(bus_name))
	row.add_child(slider)
	return row


## 优先用保存过的音量；没保存过就沿用总线当前值（首次运行）
func _saved_bus_volume(bus_name: String) -> float:
	var saved: Variant = SettingsStore.get_value(SettingsStore.SECTION_AUDIO, bus_name, null)
	if saved == null:
		return _bus_volume(bus_name)
	return clampf(float(saved), 0.0, 1.0)


func _on_volume_changed(value: float, bus_name: String) -> void:
	_set_bus_volume(bus_name, value)
	SettingsStore.set_value(SettingsStore.SECTION_AUDIO, bus_name, value)


func _bus_volume(bus_name: String) -> float:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		index = 0
	return db_to_linear(AudioServer.get_bus_volume_db(index))


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		index = 0
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(index, linear <= 0.001)


## 调试入口：解开离线产出，并立刻存档，好让下次回游戏真的弹出结算
func _on_debug_unlock_offline() -> void:
	GameState.debug_unlock_offline()
	clear_content()
	_build()
	show_message(I18n.t("ui.settings.debug_done"), PanelKit.INK_SOFT)


func _on_clear_pressed() -> void:
	if not _clear_armed:
		_clear_armed = true
		_clear_button.text = I18n.t("ui.settings.reset_confirm")
		show_message(I18n.t("ui.settings.reset_armed"), PanelKit.DANGER_DEEP)
		return
	var saver := SaveGame.new()
	saver.remove()
	GameState.reset()
	GameState.last_seen_unix = 0
	_clear_armed = false
	_clear_button.text = I18n.t("ui.settings.reset_button")
	show_message(I18n.t("ui.settings.reset_done"), PanelKit.INK_SOFT)
	EventBus.publish(CoinChangedEvent.new(GameState.coins, 0, "清档"))
