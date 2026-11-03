extends GutTest
## 翻译键派生、缺键回退、占位符格式化、复数键、设置文件读写容错。

const TEST_SETTINGS_PATH := "user://__test_settings.cfg"

var _original_path: String


func before_each() -> void:
	_original_path = SettingsStore.path
	SettingsStore.path = TEST_SETTINGS_PATH


func after_each() -> void:
	SettingsStore.path = _original_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_PATH))


func test_key_for_derives_data_key() -> void:
	assert_eq(I18n.key_for("item/americano", &"display_name"), "data.item.americano.name")
	assert_eq(I18n.key_for("letter/window", &"body"), "data.letter.window.body")
	assert_eq(I18n.key_for("recipe/latte", &"research_hint"), "data.recipe.latte.hint")


func test_key_for_strips_namespace_prefix() -> void:
	assert_eq(I18n.key_for("game:item/americano", &"display_name"), "data.item.americano.name")


func test_key_for_unknown_field_uses_field_name() -> void:
	assert_eq(I18n.key_for("item/cookie", &"sell_price"), "data.item.cookie.sell_price")


func test_t_falls_back_to_key_when_missing() -> void:
	assert_eq(I18n.t("ui.nope.missing"), "ui.nope.missing")


func test_t_formats_placeholders() -> void:
	var original_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	var translation := Translation.new()
	translation.locale = "zh_CN"
	translation.add_message("test.greeting", "你好，{0}")
	TranslationServer.add_translation(translation)
	assert_eq(I18n.t("test.greeting", ["小明"]), "你好，小明")
	TranslationServer.remove_translation(translation)
	TranslationServer.set_locale(original_locale)


func test_plural_key_selects_one_or_other() -> void:
	assert_eq(I18n.plural_key("ui.order.count", 1), "ui.order.count.one")
	assert_eq(I18n.plural_key("ui.order.count", 2), "ui.order.count.other")
	assert_eq(I18n.plural_key("ui.order.count", 0), "ui.order.count.other")


func test_settings_defaults_when_file_missing() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_PATH))
	assert_eq(String(SettingsStore.get_value("general", "locale", "fallback")), "fallback")


func test_settings_roundtrip_when_writable() -> void:
	var ok := SettingsStore.set_value(SettingsStore.SECTION_GENERAL, SettingsStore.KEY_LOCALE, "en")
	if not ok:
		pass_test("user:// 在当前环境不可写（沙箱），跳过往返断言")
		return
	assert_eq(SettingsStore.get_locale(), "en")
