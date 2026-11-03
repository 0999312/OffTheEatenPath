class_name CreditsPanel
extends GamePanel
## 致谢与第三方许可：发布版必须能让人在不看仓库的情况下查到「用了别人的什么」。
##
## 条目写在代码里而不是 .tres：这些都是不可配置的法律文本，改成数据驱动没有收益，
## 反而会被当成游戏内容去改动。真正的权威清单在 `docs/THIRD_PARTY.md`，这里放摘要。
## 文案是翻译键：切语言后整块重建，许可文本本身不随游戏内容改。

const ENTRIES := [
	{"title": "ui.credits.engine_title", "body": "ui.credits.engine_body"},
	{"title": "ui.credits.framework_title", "body": "ui.credits.framework_body"},
	{"title": "ui.credits.sfx_title", "body": "ui.credits.sfx_body"},
	{"title": "ui.credits.sfx_assets_title", "body": "ui.credits.sfx_assets_body"},
	{"title": "ui.credits.music_title", "body": "ui.credits.music_body"},
	{"title": "ui.credits.font_title", "body": "ui.credits.font_body"},
	{"title": "ui.credits.icons_title", "body": "ui.credits.icons_body"},
	{"title": "ui.credits.shader_title", "body": "ui.credits.shader_body"},
	{"title": "ui.credits.test_title", "body": "ui.credits.test_body"},
]


func _on_open(data: Dictionary = {}) -> void:
	super._on_open(data)


func refresh() -> void:
	if not content.get_children().is_empty():
		return
	_build()


## 切语言：refresh() 有「只建一次」守卫，这里直接重建
func _on_language_changed(_event: Event) -> void:
	super._on_language_changed(_event)
	_build()


func _build() -> void:
	clear_content()
	set_title(I18n.t("ui.credits.title"))
	set_subtitle(I18n.t("ui.credits.subtitle"))
	for entry in ENTRIES:
		var row := PanelKit.vbox(4)
		row.add_child(PanelKit.label(I18n.t(String(entry["title"])), 19))
		row.add_child(PanelKit.hint(I18n.t(String(entry["body"])), 640))
		content.add_child(row)
		content.add_child(PanelKit.divider())
	content.add_child(PanelKit.hint(I18n.t("ui.credits.footer"), 640))
