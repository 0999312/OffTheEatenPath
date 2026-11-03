extends GutTest
## P8：主题渐进解锁 + 设备可用性。
##
## 两条都在守「开局不该一口气摊开十个地方」：主题靠到站信解锁，
## 设备没到手时它的配方不算「可做」。另外守一条死锁——信件要的材料
## 如果落在还没到站的地方，那封信就永远解不开。

const BASE := "game:theme/base"
const CAFE := "game:theme/cafe"
const EAST_ASIA := "game:theme/east_asia"
const FRIDGE := "game:facility/fridge"
## 注册表里的键带命名空间：`get_key()` 是 "game:letter/…"，不是 .tres 里的 id
const FRIDGE_LETTER := "game:letter/fridge_hum"
const ARRIVE := "game:letter/east_asia_arrive"


func _data() -> DataRegistry:
	return RegistryManager.get_registry(DataRegistry.REGISTRY_NAME) as DataRegistry


func before_each() -> void:
	GameState.reset()


## 测试里要读一封还没满足条件的信：直接把解锁名单摆好（Array[String]，塞未类型化数组会被静默丢掉）
func _force_unlock(letter_key: String) -> void:
	var unlocked: Array[String] = [letter_key]
	GameState.set("_unlocked_letters", unlocked)


func test_home_and_cafe_are_open_from_the_start() -> void:
	assert_true(GameState.is_theme_unlocked(BASE), "家常开局就在")
	assert_true(GameState.is_theme_unlocked(CAFE), "咖啡馆也开局就在：拿铁是第三封信的钥匙，它一锁就断链")


func test_a_region_stays_closed_until_its_arrival_letter() -> void:
	assert_false(GameState.is_theme_unlocked(EAST_ASIA), "东亚还没到站")
	_force_unlock(ARRIVE)
	assert_true(GameState.mark_letter_read(ARRIVE), "到站信应能读")
	assert_true(GameState.is_theme_unlocked(EAST_ASIA), "读完就到站了")


func test_a_locked_theme_hides_its_recipes() -> void:
	var recipe_key := ""
	for def in _data().get_defs_of_type("recipe"):
		var recipe := def as RecipeDef
		if recipe == null or recipe.needs_research():
			continue
		if GameState.recipe_theme_key(recipe.get_key()) == EAST_ASIA:
			recipe_key = recipe.get_key()
			break
	assert_ne(recipe_key, "", "东亚应有一道不用研究的配方")
	if recipe_key.is_empty():
		return
	assert_false(GameState.is_recipe_visible(recipe_key), "未到站的配方不该可见")
	var visible: Array[String] = []
	for recipe in GameState.get_visible_recipes():
		visible.append(recipe.get_key())
	assert_false(visible.has(recipe_key), "未到站的配方不该进灶台")

	_force_unlock(ARRIVE)
	GameState.mark_letter_read(ARRIVE)
	assert_true(GameState.is_recipe_visible(recipe_key), "到站之后它才出现")


func test_every_theme_unlock_points_at_a_real_letter() -> void:
	var data := _data()
	for def in data.get_defs_of_type("theme"):
		var theme := def as ThemeDef
		if theme == null or theme.unlock_letter.is_empty():
			continue
		assert_not_null(data.get_def(theme.unlock_letter),
			"%s 的 unlock_letter 指向不存在的信：%s" % [theme.get_key(), theme.unlock_letter])


func test_every_region_theme_is_gated() -> void:
	# 漏写 unlock_letter 的那一天，这个主题就等于开局全开——一次漏 8 个也看不出来。
	# base 与 cafe 是序章的两个地方，其余必须挂到站信。
	var open: Array[String] = [BASE, CAFE]
	var data := _data()
	var regions := 0
	for def in data.get_defs_of_type("theme"):
		var theme := def as ThemeDef
		if theme == null or open.has(theme.get_key()):
			continue
		regions += 1
		assert_false(theme.unlock_letter.is_empty(),
			"%s 没写 unlock_letter，开局就会全开" % theme.get_key())
	assert_eq(regions, 9, "除 base / cafe 外应有 9 个地区主题")


func test_a_locked_facility_is_not_ready() -> void:
	assert_false(GameState.is_facility_ready(FRIDGE), "冰箱还没到手")
	assert_true(GameState.is_facility_ready(""), "手作没有设备，永远可以做")
	_force_unlock(FRIDGE_LETTER)
	GameState.mark_letter_read(FRIDGE_LETTER)
	assert_true(GameState.is_facility_ready(FRIDGE), "读完信冰箱进厨房")


func test_starter_letters_only_ask_for_starter_food() -> void:
	# 死锁守卫：开局能读到的信，它要的菜必须在开局就做得出
	for def in _data().get_defs_of_type("letter"):
		var letter := def as LetterDef
		if letter == null or letter.condition != LetterDef.Condition.FOOD_CRAFTED:
			continue
		var theme := GameState.item_theme_key(letter.condition_ref)
		assert_true(GameState.is_theme_unlocked(theme),
			"%s 要的 %s 属于 %s，而那里开局还没到站——这封信会永远解不开"
				% [letter.get_key(), letter.condition_ref, theme])
